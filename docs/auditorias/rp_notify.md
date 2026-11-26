# Auditoría de rp_notify

## 2026-11-26 · mejorar · foco: legibilidad y bordes suaves
- **Motivo**: Fabián: la fuente de los globos (Kenney Future, sin minúsculas reales y con esquinas biseladas) cuesta leerla, y los bordes diagonales y redondos se ven en dientes de sierra.
- **Nota**: 100 → 100.
- **Cambios**:
  - El texto que se lee pasa a **Rubik** (SIL OFL, añadida a `assets/fuentes/rubik/` con su licencia y a la paleta de `assets/README.md`). Kenney Future queda solo en etiquetas cortas en mayúsculas (y en el titular de `popup` en rp_notify).
  - **Antialiasing**: `dxDrawPrimitive`/`dxDrawLine` no suavizan; las formas se dibujan ahora con `c_dx.lua` (círculos, aros, líneas con extremos redondos, polígonos y rectángulos redondeados con un borde de 1 px que se desvanece). Mismo archivo en rp_notify, rp_chat y rp_nametags.
- **Probar en juego**: que los textos se lean bien en resolución baja y que los bordes diagonales, redondos e iconos ya no tengan escalones.

## 2026-11-25 · mejorar · foco: rediseño visual completo y más original, con SFX, VFX y GFX
- **Motivo**: las notificaciones eran rectángulos planos con una letra de icono; se pidió un diseño propio y con más vida.
- **Nota**: 91 → 100.
- **Cambios**:
  - **Toast**: tarjeta con el borde izquierdo en diagonal y degradado del color del tipo al negro. Entra deslizando con rebote y un **barrido de color** que se recoge hasta quedar como franja lateral; un **brillo** la cruza y salen dos **pulsos** del icono. Iconos vectoriales (✓, ✕, !, i) dibujados con dx. El **aro del icono** marca el tiempo restante (antes, barra inferior).
  - Gesto por tipo: chispas al estilo confeti (hecho), sacudida corta (error), latido del icono (atención).
  - El mismo aviso repetido ya no se apila: suma `x2`, `x3` con un salto y un tic, y reinicia su tiempo. Si hay más de 4, el más viejo **sale animado** (antes desaparecía de golpe) y el resto se reacomoda suave.
  - Los toasts van **debajo del bloque de arriba a la derecha del HUD** (`rp_hud:getTopRightBottom`), que antes tapaban.
  - **Popup** como titular: banda oscura que se abre desde el centro con halo del color del tipo y destello, dos líneas de luz que se extienden, un rombo con pulso, letras del título que llegan separadas y se juntan, y subtítulo después.
  - **Globo**: bocadillo redondeado con sombra que salta al aparecer, se escala con la distancia y escribe el texto letra a letra. El texto se parte al crearlo (antes, cada frame: CLI-02).
  - GFX: fuentes Kenney Future y Future Narrow (comprobado que tienen tildes, ñ, ¿ y ¡). SFX: paleta estándar de Kenney (`glass_001` info, `confirmation_002` hecho, `question_001` atención, `error_004` error, `bong_001`/`confirmation_003` titulares, `pluck_002` globo, `tick_002` repetido), con enfriamiento para que nunca suenen en ráfaga (UX-06). Se quitan los `.wav` viejos y `old_generated/` (UX-10, `CREDITOS.md`).
  - Con el HUD suprimido (`rp:hudHidden`: cinemáticas, foto) toasts y popups **se pausan** y salen después (antes seguían dibujándose sobre la cinemática).
  - `/silenciarnotis` se guarda entre sesiones y ya no lo pisa `rp_hud` al terminar una cinemática (preferencia del jugador y silencio externo separados).
  - `/probarnotis`: muestra todos los tipos en tu pantalla para revisar el diseño.
  - `cache="false"` en el cliente (EST-02); export y comandos documentados en `RECURSOS.md` (DOC-02, DOC-03).
- **API**: sin cambios (`notify`, `popup`, `bubble` de cliente y servidor, `setNotificationsMuted`, eventos `rp:notify*`).
- **Reglas manuales revisadas**: SEG-02/SEG-03 ✔ (solo dibuja; el servidor no recibe nada), CIC-06 ✔ (sin estado en el servidor), CLI-03 ✔ (fuentes creadas una vez; por frame solo primitivas), UX-06 ✔, UX-10 ✔. PRU-02: pendiente de probar en juego.
- **Pendiente**: el panel de miedo de `rp_robbery` también se coloca bajo `getTopRightBottom`; si coinciden en pantalla podrían solaparse (revisar en juego).
- **Probar en juego**: `/probarnotis` (los 4 tipos, el repetido `x2`, el titular y el globo); varios avisos seguidos (máx. 4, el viejo sale animado); un aviso durante una cinemática (se pausa y sale después); `/silenciarnotis`, reconectar y comprobar que sigue silenciado; resolución baja (≤ 768 px de alto) y alta; que no tape el dinero ni las estrellas.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit e3f0b92)

**Nota: 100/100** · OK 26 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
