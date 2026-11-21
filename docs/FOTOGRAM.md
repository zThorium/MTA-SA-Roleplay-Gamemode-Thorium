# Fotogram: diseño de comentarios, selfie y filtros

Documento de diseño para ampliar la app **Fotogram** (la "Instagram" de `rp_phone`).
Se implementa por partes, una por PR: **1) comentarios → 2) selfie → 3) filtros**.

## 1. Cómo funciona hoy

Todo vive en `rp_phone` (`server/s_phone.lua`, `client/c_phone.lua`, `html/app.js`, `html/index.html`).

- **UI**: CEF a pantalla completa con el teléfono dibujado en HTML. Vistas `view-social` (feed) y `view-social-new` (nueva foto). Lua → JS con `executeBrowserJavascript("RP.setFeed(...)")`; JS → Lua con `mta.triggerEvent("rp:phone:ui:*")`.
- **Foto**: `rp:phone:ui:capture` oculta el teléfono y el HUD (`rp:hudHidden`), espera 400 ms, y en `onClientRender` hace `dxUpdateScreenSource` (640×360) → `dxGetTexturePixels` → `dxConvertPixels(pixels, "jpeg", 70)` → base64 → `RP.setPhoto()`. Es una captura de la vista actual, **sin control de cámara**.
- **Publicar**: `triggerLatentServerEvent("rp:social:post", 200000, ...)` con el base64. El servidor valida (≤ 350 KB, solo `[A-Za-z0-9+/=]`, tiene teléfono, no abatido, anti-doble-envío con `busy`) e inserta en `social_posts.image` (`MEDIUMTEXT`).
- **Feed**: `rp:social:feed` devuelve los últimos 15 posts con **imagen incluida** (`triggerLatentClientEvent`, 200 KB/s), con `likes` y `liked` por subconsulta. Los likes alternan en `rp:social:like` (DELETE y, si no borró nada, INSERT IGNORE).
- **Tablas** (`schema.lua`): `social_posts(id, character_id, caption, image, created_at)` y `social_likes(post_id, character_id)`, ambas con `ON DELETE CASCADE`.

### Problemas detectados (a tener en cuenta)

1. **El feed pesa demasiado**: 15 fotos × hasta 350 KB ≈ **5 MB** por apertura, a 200 KB/s son ~25 s. Una foto 640×360 JPEG q70 suele pesar 40–80 KB (el feed real ronda 1 MB), pero el techo es alto y se repite cada vez que se abre la app.
2. Las imágenes se guardan en **base64** (+33 % de tamaño) en `MEDIUMTEXT`.
3. No hay paginación, ni caché en cliente, ni límite de publicaciones por personaje.
4. El like se aplica de forma optimista en la UI y el servidor no confirma (aceptable, pero un comentario sí necesita confirmación).

## 2. Límites de MTA a respetar

| Tema | Límite / comportamiento | Decisión |
|---|---|---|
| Eventos normales | Sin límite duro, pero bloquean el canal de sincronización | Fotos siempre con `triggerLatent*Event` |
| Ancho de banda latente | Se fija por llamada (hoy 200 000 B/s) | Mantener; 1 foto ≈ 0,3–0,5 s |
| Tamaño de imagen | `dxCreateScreenSource` hasta el tamaño de pantalla; `dxConvertPixels` jpeg/png/plain | Mantener 640×360 (16:9) o 640×480 para selfie vertical; JPEG calidad 65–75 |
| Strings Lua → CEF | `executeBrowserJavascript` acepta cientos de KB, pero cada string se copia | Enviar **una imagen cada vez** y no el feed completo con imágenes |
| CEF → Lua | Los argumentos de `mta.triggerEvent` se serializan; strings de cientos de KB son lentos | Evitar devolver imágenes desde JS a Lua (ver filtros) |
| Shaders | `dxCreateShader` acepta HLSL (SM 2.0/3.0); se puede pasar el código como string | Los shaders van embebidos en un `.lua`/`.fx` del recurso |
| Render targets | Se crean con `dxCreateRenderTarget(w,h)`; hay que redibujarlos si se pierde el dispositivo (`onClientRestore`) y destruirlos al cerrar | Crear al abrir la cámara, destruir al cerrar |
| Almacenamiento | MariaDB; los `fileCreate` del servidor van a la carpeta del recurso y se sincronizarían como `<file>` | **Guardar en la BD**, no en archivos |

## 3. Parte 1: comentarios en los posteos

### Modelo de datos (nueva entrada **al final** de `schema.lua`)

```sql
CREATE TABLE IF NOT EXISTS social_comments (
    id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    post_id      INT UNSIGNED NOT NULL,
    character_id INT UNSIGNED NOT NULL,
    body         VARCHAR(200) NOT NULL,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_comments_post (post_id, id),
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES social_posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_character FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
```

(skill `migracion-bd`: solo entradas nuevas al final, nada de editar las existentes.)

### Eventos

| Evento | Dirección | Contenido |
|---|---|---|
| `rp:social:comments` | cliente → servidor | `postId`, `beforeId` opcional (paginación hacia atrás) |
| `rp:social:comments` | servidor → cliente | `postId`, lista `{id, author, body, date, mine}` (máx. 20 por página) |
| `rp:social:comment` | cliente → servidor | `postId`, `texto` |
| `rp:social:comment:delete` | cliente → servidor | `commentId` (autor del comentario, autor del post o admin) |
| UI: `rp:phone:ui:comments`, `...:comment`, `...:commentDelete` | CEF → Lua cliente | reenvío a los anteriores |

Todos los nombres siguen `rp:<sistema>:<acción>`; los del CEF, `rp:phone:ui:<acción>`.

### Servidor (`s_phone.lua`)

- Reutiliza `hasPhone`, `cleanText(texto, 200, false)`, el chequeo `rp:downed` y el patrón `client` (nunca `source`).
- **Validar que el post existe** con `INSERT ... SELECT` o `INSERT` y capturar el error 1452 (FK), sin concatenar SQL.
- **Anti-spam**: tabla local `lastComment[player]` con cooldown (~3 s) y tope de comentarios por post y personaje en una ventana (p. ej. 10/min). Reutilizar `busy[player]`.
- El feed añade `comments` (conteo) con la subconsulta `(SELECT COUNT(*) FROM social_comments c WHERE c.post_id = p.id)`.
- Borrado: `DELETE FROM social_comments WHERE id = ? AND (character_id = ? OR post_id IN (SELECT id FROM social_posts WHERE character_id = ?))`, o admin (`getPlayerAdminLevel >= 1`).
- **Aviso al autor del post** si está conectado: `rp_notify` ("X comentó tu foto"). No se persiste en esta parte (no hay centro de notificaciones).
- Sincronización: **bajo demanda**. No se empuja a todos los clientes; quien tenga abierto el post recarga al comentar (el servidor responde con la lista actualizada al autor del comentario). Refresco manual/al reabrir para los demás. Suficiente para un RP; el tiempo real no compensa la complejidad.

### UI (`index.html`, `app.js`, `style.css`)

- En cada post: botón 💬 con el contador junto al ❤️.
- Nueva vista `view-social-comments`: foto reducida arriba, lista de comentarios (autor en negrita, texto, fecha, "Eliminar" si aplica), campo de texto fijo abajo con botón "Enviar" y botón "Cargar anteriores".
- Siempre `textContent` (nunca `innerHTML`) para los textos de otros jugadores.
- Al entrar a la vista se pide `comments(postId)`; el feed no cambia de estructura.

### Optimización previa recomendable (misma PR o PR 1b)

Quitar la imagen del evento del feed: `rp:social:feed` devuelve solo metadatos y el cliente pide cada imagen con `rp:social:image(postId)` (latente, cola de una a la vez, caché en la sesión del CEF por `postId`). Reduce la apertura de ~1–5 MB a unos pocos KB y las fotos llegan a medida que se ven. Si se hace, de paso se puede cambiar el almacenamiento a binario (`MEDIUMBLOB`, `decodeString("base64")`) en una columna nueva `image_blob` y mantener `image` como respaldo para los posts viejos.

## 4. Parte 2: selfie dentro del juego

Objetivo: en la pantalla "Nueva foto", además de 📷 (captura de la escena actual) un botón 🤳 que pone una **cámara frontal** y toma la foto con el personaje de frente.

### Flujo

1. CEF → `rp:phone:ui:selfie`. El cliente comprueba que el jugador está a pie (o conduciendo/sentado: usar el modo "escena" actual), no abatido, no en animación bloqueante.
2. Se oculta el teléfono (`guiSetVisible(browserGui, false)`) y el HUD (`rp:hudHidden`), se ocultan nametags y se entra en **modo selfie**:
   - `setCameraMatrix` cada frame en `onClientPreRender` (así sigue al personaje sin saltos): posición = cabeza (`getPedBonePosition(localPlayer, 8)`) + vector hacia delante del ped × 0,9 m + ligero desplazamiento lateral/arriba (el "brazo"), mirando a la cabeza; `fov` ~ 70.
   - Controles bloqueados (`toggleAllControls(false, true, false)` salvo los que se usen) y animación opcional de "sostener el móvil" con `setPedAnimation` (bloque propio del teléfono si existe; si no, solo la pose).
   - Guía en pantalla con dx: marco, botón de disparo (clic o `Enter`/`Space`), `Esc` o `Backspace` para cancelar, flechas/rueda para acercar o alejar (limitado a 0,6–1,6 m).
3. Al disparar: se espera un frame, `dxUpdateScreenSource(screenSource, true)`, se recorta a la relación deseada (4:5 vertical o 16:9) y se genera el JPEG como hoy.
4. `setCameraTarget(localPlayer)` para restaurar la cámara, se quitan los handlers, se desbloquean controles, se muestra el teléfono y se llama a `RP.setPhoto(base64)`.

### Detalles técnicos

- Reutilizar `doCapture`; extraer una función `takePhoto(mode)` con `mode = "scene" | "selfie"` para no duplicar.
- **Recorte**: `dxCreateScreenSource(screenW, screenH)` → dibujar la región deseada en un `dxCreateRenderTarget(640, 800 o 360)` con `dxDrawImageSection` → `dxGetTexturePixels(renderTarget)`. Destruir el render target al terminar.
- **Limpieza obligatoria** en `onClientResourceStop`, `onClientPlayerWasted`, `rp:onClientPlayerDowned` y al cerrar el teléfono: restaurar cámara, controles, HUD, destruir `screenSource` y `renderTarget`, quitar handlers y timers (evitar cámara atascada).
- **Servidor**: sin cambios de protocolo. Solo se amplía la validación de imagen si el formato vertical cambia el tamaño (sigue ≤ 350 KB).
- **Seguridad**: es una captura del cliente, así que el servidor no puede verificar el contenido. Se asume y se mitiga con límite de tamaño, de frecuencia y borrado por admin (`/borrarpost <id>` con `comando-admin`, registrado en `rp_adminpanel`).

## 5. Parte 3: filtros

### Enfoque elegido: shaders DX aplicados en el cliente antes de codificar

Opciones evaluadas:

| Opción | Pros | Contras |
|---|---|---|
| **A. Shaders HLSL con `dxCreateShader` sobre la captura** (elegida) | Misma pipeline que la foto, resultado idéntico al guardado, filtros ricos (viñeta, grano, curvas), rápido | Hay que escribir HLSL; vista previa en el teléfono requiere aplicar el filtro en DX o aproximarlo en CSS |
| B. `ctx.filter` / canvas 2D en el CEF y devolver `toDataURL` a Lua | Fácil y con vista previa inmediata | Devolver strings de cientos de KB de CEF a Lua es lento; depende de la versión de Chromium de MTA |
| C. `dxDrawImage` con `color` (tinte) | Trivial | Solo tintes planos, sin contraste ni saturación reales |

### Diseño

- Catálogo en `shared/s_filters.lua` (o dentro del cliente): `{ id = "bn", name = "Blanco y negro" }`, `sepia`, `calido`, `frio`, `vintage` (viñeta + grano), `contraste`, `desvanecido`. El `id` se envía al servidor **solo como metadato opcional** (columna `filter VARCHAR(16)`) o no se envía; la imagen ya viene procesada.
- Un único `fx` parametrizable con `dxSetShaderValue`: `Tex`, `Saturation`, `Contrast`, `Brightness`, `Tint` (float3), `Vignette`, `Grain`, `Time`. Cada filtro es un preset de parámetros. Un shader en lugar de uno por filtro reduce código y memoria.
- Proceso: `captura (screenSource)` → `renderTarget` con `dxSetRenderTarget` + `dxDrawImage(0,0,w,h, shader)` → `dxGetTexturePixels(renderTarget)` → `dxConvertPixels(..., "jpeg", 70)`.
- **Vista previa**: se guarda la captura "sin filtro" en el cliente (pixels o textura). Al elegir un filtro en el CEF se envía `rp:phone:ui:filter(id)`, el cliente re-renderiza con el preset y devuelve el base64 nuevo a `RP.setPhoto`. Cada cambio de filtro mueve ~50–80 KB Lua → CEF (aceptable). Un carrusel de 6 miniaturas se genera una sola vez a 160×90 al tomar la foto.
- Conservar el original en memoria solo mientras esté abierta la pantalla "Nueva foto"; liberar texturas/render targets al publicar, cancelar o cerrar el teléfono.
- Compatibilidad: comprobar `dxGetStatus().VideoCardPSVersion`; si no hay shaders (`dxCreateShader` devuelve `false`), ocultar los filtros y publicar sin ellos.

## 6. Orden de implementación y checklist

| PR | Contenido | Archivos principales |
|---|---|---|
| **A** (siguiente) | Comentarios (+ opcional: imágenes bajo demanda en el feed) | `rp_database/schema.lua`, `rp_phone/*`, `RECURSOS.md`, `docs/FOTOGRAM.md` |
| **B** | Selfie con cámara frontal | `rp_phone/client/c_phone.lua`, `html/*` |
| **C** | Filtros con shaders | `rp_phone/client/c_filters.lua` (+ `.fx`), `html/*`, `meta.xml` |

Cada PR: consola del servidor sin errores, `/debugscript 3` limpio, probar con dos personajes (uno comenta/ve lo del otro), y actualizar `RECURSOS.md` y este documento.

## 7. Riesgos

- No hay forma de validar el contenido de las fotos (son capturas del cliente): depender de moderación admin.
- Crecimiento de la tabla de imágenes: añadir poda (p. ej. conservar los últimos N posts globales o por personaje) y un tope de publicaciones por personaje y día.
- El tiempo real de comentarios entre jugadores queda fuera de alcance (solo bajo demanda).
- Los shaders y render targets son lo más sensible a fugas de memoria y al cambio de resolución/pérdida de dispositivo: destruir siempre al cerrar y probar `onClientRestore`.
