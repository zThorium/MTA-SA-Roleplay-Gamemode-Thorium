# Auditoría de rp_markers

## 2026-11-27 · mejorar (puntos fijos movibles por los admins)
- **Motivo**: Fabián: los marcadores de algunos recursos no se podían mover con el editor de admin; pide centralizar los marcadores en rp_markers.
- **Causa**: no era el `createMarker` nativo, sino que no había dónde guardar la posición nueva: 8 recursos tienen las puertas en la config y 5 en su propia BD con su `/mover`; además su lógica (avisos «Pulsa E», teletransportes, blips) usa esas coordenadas, no el marcador.
- **Cambios**: `server/s_points.lua` y `client/c_points.lua`: `placePoint(clave, x, y, z)` (servidor y cliente) da la posición efectiva de un punto, `registerMarker(marker, clave, opciones)` lo apunta para la vista ALT y el editor; tabla `marker_points` (ID estable, base de la config, posición movida, quién y cuándo); evento `rp:markers:moved` para que el dueño reconstruya; `ownerSaves` para los que guardan en su BD; `level` mínimo (policía 3, misiones 2); `/resetmarker <id>`; tipo `marker` en `WORLD_TYPES` de rp_admin. Se mantiene que el marcador lo cree su recurso (si lo creara rp_markers, un restart borraría todos): lo central es la posición; la clave vive en el marcador para rehidratar tras reiniciar rp_markers. Regla 12 de `CLAUDE.md` (todo marcador con rp_markers). Adaptados: `rp_ammunation`, `rp_restaurants` (también arregla que matar al empleado duplicaba las puertas), `rp_gym` (puertas de Ganton), `rp_pool` (salas), `rp_bikes`, `rp_shootingrange`, `rp_wanted` (Pay 'n' Spray), `rp_races` (solo el marcador del menú, no la pista), y con BD propia `rp_vehicles` (gasolineras y talleres), `rp_firefighters`, `rp_police`, `rp_missions`. Después: `rp_robbery` (marcador de salida visible en el interior, guardado en `points.exit` como `/robopunto <id> salida`; durante un robo solo se mueve la salida, sin rehacer la escena).
- **Reglas manuales revisadas**: SEG-02 ✔ (el movimiento llega por `rp:admin:move:save` de rp_admin, revalidado allí; nivel por marcador comprobado aquí) · BD-06 ✔ · BD-04 ✔ (`marker_points` al final de `schema.lua`) · PRU-02 ✔ (`admin_marcadores_movibles` y `admin_exports_mover` con rp_markers).
- **Pendiente**: los marcadores temporales (checkpoints de carreras, autoescuela y misiones, evidencias, incendios, flechas de GPS, destino de Vroom) no se registran: no tienen posición fija. Tampoco «Terminar turno» de la pizzería (cambia de dimensión en cada turno).
- **Después (revisión de todos los `createMarker`)**: `registerPoint` para marcadores fijos que crea el cliente (el servidor no tiene el elemento; la vista ALT los dibuja y el editor los mueve sin vista previa del objeto) y evento `rp:markers:ready` al arrancar rp_markers para volver a registrarlos. Adaptados `rp_agency` (entrada; EXIT_SPAWN la sigue), `rp_jobs` (sedes y puntos de venta) y `rp_pizzeria` (contratación). La autoescuela no tiene marcador fijo (el instructor es un ped, ya movible como tipo `school`), las bicis ya estaban, las salidas de casas se mueven como tipo `house` y la corona de `rp_furniture` es una luz.
- **Probar en juego**: ALT + clic derecho sobre la puerta del Ammu-Nation, moverla 3 m y guardar: el blip y el aviso «Pulsa E» están en el sitio nuevo y al salir del interior apareces allí; `restart rp_ammunation` y `restart rp_markers` la mantienen; `/resetmarker <id>` la devuelve. Mover una gasolinera y comprobar que `/nearbybencineras` muestra la posición nueva. Con admin nivel 1, intentar mover un punto de policía → «hace falta admin nivel 3».

## 2026-11-25 · crear
- **Motivo**: los cilindros nativos de GTA se ven anticuados; un único recurso los moderniza en toda la GM.
- **Nota**: — → 100.
- **Cambios**:
  - El cliente pone alfa 0 a todo `createMarker` de tipo `cylinder` (sigue siendo zona de colisión) y dibuja en 3D: aro de suelo que respira, aro segmentado que gira, dos ondas de pulso, haz de luz que se apaga con la cámara encima, partículas en espiral. Dentro del marcador todo acelera y brilla más.
  - Insignia flotante (disco oscuro, aro del color del marcador, icono blanco) que aparece con un "pop" a 16 m, y etiqueta de texto a 8 m.
  - 28 iconos propios y texturas generados con `tools/gen_textures.ps1` (dibujo propio, sin material de terceros).
  - Export `setMarkerStyle` (servidor sincronizado por elementData `rp:marker`, cliente para marcadores locales) con validación compartida (`MARKERS.sanitizeStyle`); `getMarkerIcons`.
  - Se respetan los marcadores con alfa 0 de origen (zonas invisibles), los demás tipos (checkpoint, ring, arrow, corona) y `native = true`. Se oculta todo durante cinemáticas (`rp_hud:isHudSuppressed`). Al parar el recurso, cada marcador recupera su color.
  - `/markerdemo` (admin): todos los iconos alrededor, solo en el cliente del admin; añadido al catálogo de `rp_adminpanel`.
- **Reglas manuales revisadas**: SEG-02 ✔ (el único evento va del servidor al cliente y lo autoriza el servidor), SEG-04 ✔ (sin eventos remotos), BD-06 N/A, CIC-06 ✔ (restaura colores y mata el timer al parar), CLI-03 ✔ (escaneo cada 400 ms; el render solo recorre la lista visible). PRU-02: pendiente de probar en juego.
- **Integración**: icono y texto en los 19 sitios que crean cilindros, repartidos en 12 recursos (`<include resource="rp_markers" />` + `setMarkerStyle`): rp_ammunation (gun/exit), rp_shootingrange (target), rp_bikes (bike), rp_agency (job), rp_jobs (job en sedes, money en mercados, arrow en destinos), rp_missions (star en contactos, arrow en objetivos), rp_police (police, exit, clothes, gun, info, key, car por punto; info en evidencias), rp_pool (enter/exit), rp_properties (exit), rp_races (flag), rp_vehicles (fuel, wrench), rp_wanted (car en Pay 'n' Spray). Checkpoints, aros, flechas y coronas siguen nativos. Las auditorías de esos recursos no cambian (sus FALLA son anteriores).
- **Lenguaje de colores**: `MARKERS.PALETTE` por categoría de icono (`ICON_CATEGORY`) manda sobre el color de creación, para que el mismo tipo de lugar se vea igual en toda la GM. Excepciones explícitas: puntos de la comisaría en azul policía (salvo la salida) y evidencias con su color (sangre roja, casquillo amarillo).
- **Pendiente**: —
- **Probar en juego**: `/markerdemo`; acercarse y alejarse (pop de la insignia, texto); entrar en un marcador; ver un marcador de otro recurso (Ammu-Nation, propiedades) ya rediseñado; `restart rp_markers` con marcadores a la vista (vuelven los cilindros y luego el nuevo estilo); una cinemática de misión (no se ven).

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 067d44a)

**Nota: 98/100** · OK 25 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_markers.md |
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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 2 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | BD-05 | Espera a la BD al arrancar | no usa la BD |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
