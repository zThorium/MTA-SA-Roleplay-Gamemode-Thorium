# Auditoría de rp_mapeditor

## 2026-11-27 · crear · editor de mapas para super admin y rol builder
- **Contexto**: Fabián pidió un editor de mapas en el juego, solo para super admins y jugadores con rol builder, que haga lo mismo que el editor de mapas de MTA. Decisiones: proyectos en MySQL (`.map` como importar/exportar), edición en una dimensión de borrador y publicación al mundo, todos los tipos en la v1, y rol builder en el IAM de `rp_adminpanel`.
- **Hecho**:
  - `rp_adminpanel`: permiso `world.build` con `players = true` (excepción de cuenta válida con nivel 0), sección «Builders» en IAM y evento `rp:adminpanel:permsChanged`.
  - `rp_characters`: `saveCharacter` respeta el elementData de servidor `rp:savePos` (posición real mientras el jugador edita).
  - `rp_database`: tablas `mapedit_projects`, `mapedit_elements`, `mapedit_versions` y `mapedit_log` (SQL probado contra el MySQL local).
  - Recurso nuevo con servidor (proyectos, borrador, versiones, mapa vivo, quitados, `.map`), cliente (cámara, gizmo, selección, deshacer, modo prueba, tutorial) y CEF de 4 paneles.
  - Catálogo de 9 924 modelos generado con `tools/generar-catalogo.ps1`.
  - Pruebas en `rp_test/server/s_tests_mapeditor.lua`: cascada de BD, validación, ida y vuelta `.map` y exports.
- **Correcciones de la auditoría**: EST-01 (`<info>` en una línea y `min_mta_version`), EST-03 (`<include>` de `rp_characters` y `rp_adminpanel`; `rp_police` y `rp_missions` opcionales con `getResourceFromName` porque arrancan después), BD-03 (borrado por id en vez de `IN (...)`; en `rp_adminpanel` un JOIN), CIC-04 (timer de ajustes cancelable).
- **Excepción justificada**: INT-02 (`estandar:mundo`): `setTime`/`setWeather` solo en el cliente, solo con los ajustes del propio mapa y solo en su dimensión (≠ 0) o en el borrador del builder; al salir se devuelve la hora que corresponde y el clima anterior.
- **Nota**: 59 → 98 (0 FALLA).
- **Reglas manuales revisadas**:
  - SEG-02: el cliente solo propone; el servidor revalida permiso, sesión en ese proyecto, modelo (catálogo), rangos, límites, bloqueos y frecuencia en cada operación.
  - SEG-04: `rp:me:op` y `rp:me:cmd` con límite de frecuencia; operaciones de hasta 250 elementos y `.map` de hasta 1,5 MB.
  - BD-06: los elementos se escriben al momento; la versión publicada es un snapshot inmutable (salvo marcadores movidos con el editor de `rp_admin`).
  - CIC-03: al salir, al cerrar sesión, al morir, al perder el rol o al parar el recurso se devuelve posición, dimensión, interior, congelado y alfa; el borrador se destruye al irse el último editor.
  - INT-09: N/A. Es una herramienta de staff; no hay hechos que merezcan logro.
  - UX-01..05: barra de teclas dibujadas, una herramienta activa a la vez, tutorial guiado de 5 pasos la primera vez y textos de ayuda en cada panel.
  - UX-10: teclas y sonidos copiados de `assets/` con `CREDITOS.md`.
  - PRU-02: el cliente se prueba en el juego (lista en el PR).

<details><summary>Informe de la auditoría</summary>

### Auditoría automática (2026-11-27, commit dee41ed)

**Nota: 98/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_mapeditor.md |
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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 2 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 27000 |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |

</details>
