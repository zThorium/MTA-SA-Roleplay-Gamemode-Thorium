# Auditoría de rp_citizens

## 2026-11-27 · arreglar · síntoma: autos y motos que a veces salen volando y conductores que saltan en pleno vuelo
- **Causa raíz**: el modo fantasma (`ghostCar`, para deshacer solapes y atascos) apagaba **toda** la colisión del auto con `setElementCollisionsEnabled(false)` mientras tenía física y conductor. El wiki de MTA avisa de que un vehículo sin colisión y con conductor da fallos: también deja de chocar con el suelo, así que se hunde o se queda flotando sobre el auto de delante, y al volver a ser sólido, metido en el asfalto o en otro auto, la física lo expulsa hacia arriba y sale volando. El fantasma se activa justo en las filas (`FOLLOW`) tras un roce de 2 s, que es lo que se ve en la captura (auto flotando sobre el de delante en una fila).
  Además, `stageGuards` hacía bajar al conductor (`abandonCar`) en cuanto el auto se inclinaba, también en pleno vuelo: por eso los NPC saltaban mientras el auto subía.
- **Arreglo**: el fantasma usa `setElementCollidableWith` solo contra los vehículos cargados y el jugador (también los que cargan mientras dura); el suelo y el mapa siguen sólidos. `unghostCar` lo deshace al terminar y al pasar a auto lejano. Mientras el antivuelo ve el auto en el aire (`s.airSince`), nadie se baja: el antivuelo lo endereza y lo baja, o lo retira a los 2,5 s.
- **Evidencia**: captura de Fabián (auto en `FOLLOW` a 0 km/h flotando sobre el de delante, telemetría `fuera_de_linea_en_curva` en (1978,-1750)); nota del wiki de `setElementCollisionsEnabled`; el arreglo anterior (05efdfa) solo tocó el chequeo de solape y el antivuelo, no el fantasma. Sintaxis comprobada con `lua5.1.dll`.
- **Nota**: 76 → 76.
- **Pendiente**: `applyRails` mueve con `setElementPosition` hasta 1,5 m/s de lado a los autos con física en curvas; podría meterlos en un auto vecino. El desvanecimiento al retirar (`despawnCar` suave y `setCitizensSuspended`) sigue apagando toda la colisión ~1 s (el auto puede hundirse un poco antes de desaparecer).
- **Probar en juego**: filas en semáforos y atascos en cruces (Ganton, Idlewood, Market), empujar con tu auto a uno de la fila. Ningún auto debe flotar sobre otro ni salir disparado; si alguno sube, debe bajar con el conductor dentro. `/debugscript 3` limpio.

<details><summary>scripts/auditar-recurso.sh rp_citizens --md</summary>

### Auditoría automática (2026-11-27, commit 90a224a)

**Nota: 76/100** · OK 23 · FALLA B 0 · FALLA I 2 · AVISO 7

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-02 | Scripts de cliente con cache="false" | meta.xml:22 c_nodes_veh.lua ; meta.xml:23 c_nodes_ped.lua ; meta.xml:24 c_citizens.lua ; meta.xml:25 c_editor.lua ; meta.xml:27 c_sync.lua ; meta.xml:29 c_scenes.lua |
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_wanted |
| AVISO | I | EST-04 | meta.xml y archivos coinciden | lua sin declarar: resources/[roleplay]/rp_citizens/backups/c_citizens_pre_ia_conduccion.lua ; resources/[roleplay]/rp_citizens/backups/c_citizens_pre_radio.lua |
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
| AVISO | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 46 outputChatBox: revisar si son avisos de acciones |
| AVISO | I | CLI-01 | Las teclas ignoran chat/consola/cursor | resources/[roleplay]/rp_citizens/c_editor.lua |
| AVISO | I | DOC-02 | Exports documentados en RECURSOS.md | citizenAwayFromRoad ; citizenRoadSpot ; citizenWalkSpot ; citizenWatch ; getRoadGraph |
| AVISO | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda | /barrioinfo ; /objetoscerca ; /pandilleros ; /poblacion ; /poblacioninfo ; /trafico_tel |
| AVISO | I | PRU-01 | Pruebas en rp_test | usa la BD y rp_test no lo menciona |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
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
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-06 | Teclas sin choques con otros recursos | k z |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-27 · arreglar · síntoma: autos que salen volando o levitan al cielo, aparecen encima de otro o solapados
- **Causa raíz**:
  1. Los autos lejanos (dummies) no tienen colisión y pueden quedar solapados. Al acercarse el jugador recuperan la física (`makeReal`) y, si estaban dentro de otro, la física los expulsa: salen volando o quedan con el parachoques encima del otro. El chequeo que los pasaba a fantasma medía la **distancia entre centros** (4,8 m al hacerse sólido, 4,2 m al dejar de ser fantasma, 2,4 m para detectar solapes), menos que el largo de un auto (~4,6 m; un bus 12 m), y solo miraba autos de la población y el del jugador, no los de otros jugadores ni los aparcados.
  2. El antivuelo (`carWatchdog`) busca el suelo solo 6 m hacia abajo (`groundAt`): un auto que ya había subido más dejaba de contar como «en el aire» y nada lo frenaba ni lo retiraba.
- **Arreglo**: `overlapsVehicle` compara las **cajas reales** de los modelos (ejes separadores en planta) contra todos los vehículos cargados (lista una vez por tick en `refreshSnapshots`) y el jugador a pie; sustituye a `nearOtherCar` en los tres sitios. El antivuelo busca el suelo hasta 80 m más abajo cuando el auto está cargado; si no hay nada, cuenta como vuelo (se endereza, baja y a los 2,5 s se retira).
- **Evidencia**: prueba en Lua 5.1 de `boxesOverlap` con 8 casos (autos en fila a 4,2 m ahora sí se tocan; bus de 12 m con un auto a 6 m del centro ahora sí; carriles vecinos no).
- **Nota**: 76 → 78.
- **Probar en juego**: acercarse rápido a zonas con tráfico denso y a autos aparcados o de otros jugadores en la calle; atascos en cruces. No deben salir disparados ni quedar subidos uno sobre otro; un auto que salga volando debe bajar o desaparecer en ~2,5 s.

## 2026-11-27 · arreglar · síntoma: los autos giran de golpe 45-90 grados y luego siguen como si nada
- **Causa raíz**: la ruta de los autos retrocedía unos metros en dos casos:
  1. En tramos cortos (< ~13 m) cada arco de `computeTurnPoints` usa hasta el 60 % del tramo, así que dos arcos seguidos se solapan: el inicio de la curva nueva (E) quedaba hasta ~2,7 m detrás del final de la anterior (X). `planSegment` lo añadía igual.
  2. En curvas suaves con cambio de carril (offset distinto a la entrada y la salida), `intersect` devolvía un punto de control más allá del final de la curva y la Bézier se pasaba y volvía atrás.
  Los autos lejanos sin física (`moveDummies`) apuntan siempre al siguiente punto: al quedar detrás, giraban de golpe hacia él y luego retomaban el rumbo. Los autos con física también recibían ese rumbo como error de dirección.
- **Arreglo**: `planSegment` quita los puntos nuevos que quedan detrás del último de la ruta (pasa su giro, cruce, semáforo y maniobra al siguiente punto que se conserva) e `intersect` exige que el punto de control quede por delante del final de la curva. Mismo cambio en `tools/trafico/lib/geometry.js` (port en JS).
- **Evidencia** (`tools/trafico`, las 38 851 maniobras de la red): rutas con retroceso 35 260 → 1; `audit.js`: cruces problemáticos 2033 → 1603, fallos del simulador 2283 → 1701, radio < 4,5 m 133 → 123.
- **Nota**: 76 → 76.
- **Pendiente**: `rp_emergency/client/c_graph.lua` tiene su propia copia de la generación de curvas (`intersect`); no se revisó.
- **Probar en juego**: mirar tráfico a 60-120 m en calles con muchos nodos seguidos (curvas de LS, Ganton, autopistas con enlaces cortos, SF): los autos no deben girar de golpe y volver. Comprobar que siguen parando en los semáforos.

<details><summary>scripts/auditar-recurso.sh rp_citizens --md</summary>

### Auditoría automática (2026-11-26, commit c884c94)

**Nota: 76/100** · OK 23 · FALLA B 0 · FALLA I 2 · AVISO 7

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-02 | Scripts de cliente con cache="false" | meta.xml:22 c_nodes_veh.lua ; meta.xml:23 c_nodes_ped.lua ; meta.xml:24 c_citizens.lua ; meta.xml:25 c_editor.lua ; meta.xml:27 c_sync.lua ; meta.xml:29 c_scenes.lua |
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_wanted |
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
| AVISO | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 21 outputChatBox: revisar si son avisos de acciones |
| AVISO | I | CLI-01 | Las teclas ignoran chat/consola/cursor | resources/[roleplay]/rp_citizens/c_editor.lua |
| AVISO | I | DOC-02 | Exports documentados en RECURSOS.md | citizenAwayFromRoad ; citizenRoadSpot ; citizenWalkSpot ; citizenWatch ; getRoadGraph |
| AVISO | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda | /barrioinfo ; /objetoscerca ; /pandilleros ; /poblacion ; /poblacioninfo ; /trafico_tel |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_citizens.md |
| AVISO | I | PRU-01 | Pruebas en rp_test | usa la BD y rp_test no lo menciona |
| OK | B | EST-01 | meta.xml con info y min_mta_version |  |
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
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-06 | Teclas sin choques con otros recursos | k z |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
