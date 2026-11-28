# Auditoría de rp_chat

## 2026-11-26 · arreglar · síntoma: «ERROR: Client trying to change protected element data … (rp:typing)» en la consola
- **Causa raíz**: el indicador de «escribiendo…» hacía `setElementData(localPlayer, "rp:typing", …)` desde el cliente, y el servidor tiene `elementdata_whitelisted` activo: rechaza (y registra como error) cualquier element data sincronizado escrito por un cliente. Cada vez que alguien abría o cerraba el chat salía un error y el indicador no llegaba a los demás.
- **Arreglo**: el cliente avisa con `rp:chat:typing` (solo al cambiar) y el servidor valida (`client`, personaje en juego, no abatido, máximo un encendido cada 200 ms) y pone `rp:typing`. Se limpia al salir, al cerrar el personaje y al parar el recurso (SEG-01).
- **Prevención**: la regla queda en `docs/CONVENCIONES.md` (Eventos y seguridad).
- **Nota**: 98 → 98.
- **Probar en juego**: abrir y cerrar el chat varias veces con otro jugador al lado (ve los tres puntos) y la consola del servidor sin ese error.

## 2026-11-26 · mejorar · foco: legibilidad y bordes suaves
- **Motivo**: Fabián: la fuente de los globos (Kenney Future, sin minúsculas reales y con esquinas biseladas) cuesta leerla, y los bordes diagonales y redondos se ven en dientes de sierra.
- **Nota**: 98 → 98.
- **Cambios**:
  - El texto que se lee pasa a **Rubik** (SIL OFL, añadida a `assets/fuentes/rubik/` con su licencia y a la paleta de `assets/README.md`). Kenney Future queda solo en etiquetas cortas en mayúsculas (y en el titular de `popup` en rp_notify).
  - **Antialiasing**: `dxDrawPrimitive`/`dxDrawLine` no suavizan; las formas se dibujan ahora con `c_dx.lua` (círculos, aros, líneas con extremos redondos, polígonos y rectángulos redondeados con un borde de 1 px que se desvanece). Mismo archivo en rp_notify, rp_chat y rp_nametags.
- **Probar en juego**: que los textos se lean bien en resolución baja y que los bordes diagonales, redondos e iconos ya no tengan escalones.

## 2026-11-26 · mejorar · foco: burbujas y chat con la línea visual de rp_notify, más profesional
- **Motivo**: que el chat de rol se vea al nivel del rediseño de notificaciones (`rp_notify`, mismo PR).
- **Nota**: 85 → 98.
- **Cambios**:
  - **Burbujas**: bocadillo oscuro redondeado con sombra que salta al aparecer, línea de luz que se abre desde el centro y texto letra a letra. Fuentes Kenney Future. El texto se parte al llegar, no en cada frame (CLI-02).
  - Estilo por tipo: **decir** (oscuro, línea blanca), **susurro** (morado, más pequeño, etiqueta «SUSURRO» y cola de puntos como un pensamiento), **grito** (rojo, letra grande, sacudida y trazos de énfasis que salen del bocadillo).
  - **Pila**: hasta 3 frases por jugador; la nueva abajo, las viejas suben suave, más pequeñas y apagadas (antes, una frase nueva borraba la anterior).
  - **«Escribiendo…»**: píldora con tres puntos que saltan sobre quien tiene el chat abierto (element data `rp:typing`, solo se sincroniza al cambiar; se ve a 15 m).
  - **Líneas del chat** con color por partes (nombre, verbo, texto) y apagadas con la distancia, con la misma paleta que las burbujas: decir, grito, susurro, OOC, `/me`, `/do` y PM. Los nombres se limpian de códigos `#RRGGBB`.
  - Errores y usos (abatido, jugador no encontrado, demasiado lejos, usos de comandos, aviso de MG en PM) pasan a `rp_notify` en vez del chat (INT-04). Quien recibe un PM ve además un aviso.
  - `cache="false"` en el cliente (EST-02), timer cancelable (CIC-04), limpieza en `rp:onCharacterLogout` (CIC-02), el PM solo se guarda si la BD está lista (BD-05), `<include resource="rp_notify">`.
- **Reglas manuales revisadas**: SEG-02 ✔ (sin eventos remotos de cliente a servidor; `rp:typing` es solo visual), SEG-03 ✔, CIC-06 ✔, CLI-03 ✔ (fuentes creadas una vez). PRU-02: pendiente de probar en juego.
- **Pendiente**: PRU-01 (prueba en `rp_test` del historial de PMs; el cambio no toca la BD).
- **Probar en juego** (con 2 jugadores): decir, susurrar (con y sin ID), gritar (sacudida y trazos), 3-4 frases seguidas (pila), «escribiendo…» al abrir el chat y que desaparezca al enviar o cancelar, `/me`, `/do`, `/b` y `/pm` (colores en el chat y aviso al recibir), con `/ame` activo (la pila va por encima), de lejos (se apaga y se reduce) y en otra dimensión (no se ve).

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 6318518)

**Nota: 98/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | PRU-01 | Pruebas en rp_test | usa la BD y rp_test no lo menciona |
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
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 4 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos | b u |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-28 · mejorar (#107, radio de facción, departamentos y megáfono)
- **Qué**: `/r` radio IC de la facción (oyen los miembros conectados, de servicio si su tipo lo tiene; quien está a 6 m oye tu parte con globo «RADIO»), `/d` canal común de los tipos `policia`, `medicos`, `bomberos` y `gobierno`, y `/meg` (alias `/megafono`) desde un vehículo de emergencia, 60 m, con globo «MEGAFONO» que tiembla como el grito. Clic de radio (Kenney CC0) al recibir.
- **Integración**: solo con la API de `rp_factions` por tipo (`getPlayerFactionInfo`, `getFactionPlayers`, `getFactions`), con `pcall` (dependencia opcional). `getPlayerFactionInfo` añade `hasDuty` y `onDuty`.
- **UX**: uso y errores con `rp_notify` («Debes estar de servicio...», «Necesitas ir en un vehículo de emergencia...»); comandos en el panel F1.
- **Prueba**: `rp_test` › `fac_radio_comandos`.
- **Probar en juego**: policía de servicio `/r prueba` (lo ven los policías de servicio, con clic; quien está al lado ve «dice por radio»); fuera de servicio, aviso; `/d` desde bomberos lo recibe la policía; `/meg alto` en una patrulla.
- **INT-09**: N/A, comunicación sin hecho lograble.
- **Pendiente (futuro)**: radio como ítem con frecuencias libres; megáfono en vehículos de facción cuando exista #105.
