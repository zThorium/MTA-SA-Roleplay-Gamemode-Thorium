# Auditoría de rp_scoreboard

## 2026-11-26 · mejorar · foco: Tab rediseñado en CEF y perfil personalizable
- **Motivo**: Fabián: el Tab se veía genérico; pidió que se vea propio del servidor de rol, con animación al abrir y cerrar, nivel, nombres con color y letras animadas, bandera, iconos animados y una foto pequeña, todo editable por el jugador.
- **Nota**: 82 → 98.
- **Cambios**:
  - Tab pasa de dx a **CEF** (navegador creado una vez y mostrado/ocultado). Al abrir nace como una línea dorada que se estira y se despliega; al soltar se contrae a la línea y desaparece. Las filas entran escalonadas.
  - Cabecera: servidor, jugadores / máximo con punto en vivo, cuántos en facciones y hora. Por fila: ID, foto (o iniciales con su color), bandera que ondea, nombre con efecto, icono animado, facción (etiqueta con su color, de `rp:faction`), **nivel** en hexágono con color por rango (de `rp:level`, salta al subir) y ping en barras. Tu fila resaltada; quien aún no tiene personaje sale apagado.
  - **`/perfil`**: editor con vista previa en vivo: color o degradado (16 colores + hex), 9 letras animadas, 18 iconos animados, 29 banderas y foto por enlace.
  - Servidor: tabla `scoreboard_profiles` (por personaje), dato público `rp:tabProfile`; la foto la descarga el servidor solo de https de hosts de imágenes permitidos, sin redirecciones, máx. 200 KB, y comprueba que sea PNG/JPG/GIF/WEBP por sus bytes (SEG-02, evita pedir URLs internas). Los clientes la piden una vez por versión. Guardado y foto con espera entre usos.
  - Admin: `/borrarperfiltab <id o nombre>` (catálogo del panel) para fotos o estilos inapropiados.
  - Assets: banderas (flag-icons, MIT) añadidas a `assets/banderas/`; teclas, sonidos y fuentes copiados de `assets/` con `CREDITOS.md` (UX-10). Teclas dibujadas en el pie (UX-01), sonidos de abrir/cerrar y de cada acción del editor (UX-06).
  - `cache="false"` (EST-02), Tab no abre con chat/consola/cursor activos (CLI-01), carga al reiniciar solo con BD lista (BD-05), prueba `perfil_tab_guardar_y_leer` en rp_test (PRU-01).
- **Reglas manuales revisadas**: SEG-02 ✔ (todo se revalida en el servidor contra `shared/s_config.lua`), SEG-03 ✔ (nombres y datos con `textContent`), BD-06 ✔. PRU-02: pendiente de probar en juego.
- **Probar en juego**: mantener y soltar Tab (animación de abrir y cerrar, rueda para desplazar con muchos jugadores), `/perfil` (cada efecto, icono, bandera, degradado, guardar; la fila cambia para otro jugador), subir una foto de imgur (PNG y GIF) y quitarla, un enlace no permitido (aviso), reiniciar `rp_scoreboard` con gente dentro, `/borrarperfiltab` con y sin admin.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 3235c02)

**Nota: 98/100** · OK 31 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_scoreboard.md |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
| OK | I | EST-02 | Scripts de cliente con cache="false" |  |
| OK | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) |  |
| OK | I | EST-04 | meta.xml y archivos coinciden |  |
| OK | I | EST-05 | Prefijos s_/c_ según carpeta |  |
| OK | R | EST-06 | Cabecera de comentario en cada .lua |  |
| OK | B | EST-07 | Registrado en mtaserver.conf tras sus dependencias |  |
| OK | B | SEG-01 | Handlers de eventos remotos usan client |  |
| OK | B | SEG-05 | Sin secretos, IPs privadas ni emails |  |
| OK | B | SEG-06 | Sin loadstring |  |
| OK | B | BD-01 | Sin dbConnect propio |  |
| OK | B | BD-02 | Sin dbPoll(-1) sin justificar |  |
| OK | B | BD-03 | SQL parametrizado (sin concatenar) |  |
| OK | B | BD-04 | Esquema solo en rp_database/schema.lua |  |
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
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
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
