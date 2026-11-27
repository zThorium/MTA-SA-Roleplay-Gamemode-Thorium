# Auditoría de rp_citizens

## 2026-11-27 · mejorar · foco: tráfico aéreo (fase 2)
- **Qué cambia en el juego**: el cielo tiene tráfico. Vuelos de línea entre Los Santos, San Fierro y Las Venturas en los dos sentidos (AT-400, Shamal, Andromada, Nevada), avionetas por la costa sur, una fumigadora sobre los campos de Red County, avionetas dando vueltas en Verdant Meadows y helicópteros de noticias (centro de LS y SF), turísticos (Vinewood, el Strip) y de patrulla policial (Ganton-East LS). **Todos los jugadores ven el mismo avión en el mismo sitio.**
- **Diseño**: tráfico **determinista** en `c_air.lua`. Cada ruta (`ROUTES`) es una curva Catmull-Rom con horario fijo (sale cada `period` s, o circuito cerrado con `n` aeronaves); la posición en la ruta se calcula en cada fotograma con la hora del servidor, sin acumular nada, así que no se desincroniza ni gasta red: el servidor solo da la hora (`s_clock.lua`, evento `rp:citizens:clock`, máx. una petición cada 2 s por jugador y otra cada 10 min). Cada cliente crea su copia solo a menos de 700 m (máx. 6, las más cercanas). El modelo de cada vuelo sale de un hash del número de vuelo: el mismo en todos los clientes. Sin colisión y sin congelar (posición, rotación y velocidad real en cada fotograma) para que suenen el motor, giren hélices y rotores y haya efecto Doppler; piloto con el acelerador pisado, tren de aterrizaje recogido y luces de noche. Alabeo de giro coordinado (atan(v·ω/g)), máx. 25° en reactores, 35° en avionetas y 15° en helicópteros. `setVehiclesLODDistance` sube la distancia de dibujado de aviones y trenes a 500 m (solo si era menor; se restaura al parar).
- **Integración**: sigue el interruptor `/poblacion` con `citizenPopulationEnabled()` (nuevo, sin la suspensión de pasajero: el tráfico aéreo ya es el mismo para todos), personaje cargado y fuera de interiores. El helicóptero de patrulla lleva `rp:copCar` (`rp_wanted`; a 140 m de altura queda fuera del radio de testigo). `/poblacioninfo` cuenta las aeronaves; `/vuelos` dice cuándo pasa cerca cada ruta (para probar).
- **Verificación**: sintaxis con `lua5.1.dll`; la geometría y el horario se ejecutaron con funciones de MTA simuladas: altura mínima de cada ruta (reactores ≥ 249 m, fumigadora 110 m, helicópteros ≥ 140 m), alabeo y velocidad; 15 min simulados en el aeropuerto de LS: 14 aeronaves de 6 rutas, máx. 2 a la vez, 0 elementos sin borrar.
- **Nota**: 82 → 82 (se documentó `/vuelos`, DOC-03).
- **Reglas manuales revisadas**: SEG-02/SEG-03 (el único evento remoto nuevo solo devuelve la hora y está limitado por jugador; `client` y limpieza en `onPlayerQuit`), CLI-03 (`onClientPreRender` con ≤ 6 aeronaves; el horario se revisa cada 500 ms), CIC-04/CIC-06 (timers cancelados y LOD restaurado al parar).
- **Pendiente**: despegues y aterrizajes con reserva de pista (fase 4), helicóptero policial que persigue con foco según `rp_wanted` (fase 3, servidor). Las alturas de las rutas se eligieron por encima de edificios y montes conocidos; si alguna atraviesa algo en juego, se ajusta en `ROUTES`. Sin colisión: un jugador en avión las atraviesa.
- **Probar en juego**: `/vuelos` en el aeropuerto de LS, en el centro de LS y en el Strip para saber cuándo pasa cada una. Comprobar que **suena el motor** y giran rotores y hélices, que el alabeo va **hacia dentro** de la curva (si no, `BANK_SIGN = -1`), que no hay tirones al moverse, que la distancia a la que aparecen no se nota (si «surgen» de la nada, bajar `CREATE_DIST`) y que dos jugadores en el mismo sitio ven el mismo avión a la vez. `/debugscript 3` limpio.

<details><summary>scripts/auditar-recurso.sh rp_citizens --md</summary>

### Auditoría automática (2026-11-27, commit 0c8e0ed)

**Nota: 82/100** · OK 26 · FALLA B 0 · FALLA I 2 · AVISO 4

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-02 | Scripts de cliente con cache="false" | meta.xml:22 c_nodes_veh.lua ; meta.xml:23 c_nodes_ped.lua ; meta.xml:24 c_citizens.lua ; meta.xml:31 c_editor.lua ; meta.xml:33 c_sync.lua ; meta.xml:35 c_scenes.lua |
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_wanted |
| AVISO | I | EST-04 | meta.xml y archivos coinciden | lua sin declarar: resources/[roleplay]/rp_citizens/backups/c_citizens_pre_ia_conduccion.lua ; resources/[roleplay]/rp_citizens/backups/c_citizens_pre_radio.lua |
| AVISO | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 49 outputChatBox: revisar si son avisos de acciones |
| AVISO | I | CLI-01 | Las teclas ignoran chat/consola/cursor | resources/[roleplay]/rp_citizens/c_editor.lua |
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
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-06 | Teclas sin choques con otros recursos | k z |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-27 · mejorar · foco: tráfico marítimo (fase 1)
- **Qué cambia en el juego**: aparecen **barcos ambientales** en bahías, costa y ríos de todo San Andreas (lanchas y yates en las marinas, pesqueros en los puertos, botes en los ríos) y **guardacostas**, más frecuentes con estrellas. Navegan por las rutas originales del juego, giran con suavidad, flotan sobre el nivel real del agua con un leve vaivén, frenan y pitan si te cruzas, huyen a toda máquina si los embistes o les disparas, quedan a la deriva si matas al piloto y se pueden robar a nado.
- **Fase 1 · datos**: `rp_map/tools/MapData.cs` (`CitizenNodes`) genera un tercer conjunto `BOAT` con los nodos viales que tienen el bit 7 (barcos) del `.DAT`, sin carriles ni semáforos, en `c_nodes_boat.lua` (1.596 nodos, 3.316 enlaces). `c_nodes_veh.lua` y `c_nodes_ped.lua` salen idénticos (mismos índices: el editor `/nodos` no se ve afectado).
- **Fase 1 · barcos** (`c_boats.lua`, archivo aparte para no engordar `c_citizens.lua`): siempre cinemáticos (congelados, sin física, como los dummies de los autos) y con colisión solo a menos de 45 m; pasan a física real al huir, a la deriva o al subirse el jugador. Aparecen a 120-280 m (fuera de cámara si están a menos de 180 m) desvaneciéndose y se van igual a más de 360 m. Máx. 4 de día, 2 de noche, +2 con estrellas. Siguen el encendido de la población (`citizensEnabled`: `/poblacion`, pasajero, interiores) y piden personaje cargado. Marca propia `rp:citizenBoat` (no `rp:citizen`: `sweepOrphans` borraría los vehículos que no están en su tabla de autos). Guardacostas con `rp:copCar`/`rp:cop` para `rp_wanted`. Timers cancelados al parar (CIC-04).
- **Documentación**: fila de `rp_citizens` en `RECURSOS.md` (no existía): exports y comandos (DOC-02, DOC-03). `/poblacioninfo` cuenta los barcos.
- **Nota**: 76 → 82.
- **Reglas manuales revisadas**: CLI-03 (un `onClientPreRender` que solo mueve ≤ 6 barcos; el resto en timers de 250 ms y 1 s), CIC-06 (al reiniciar el recurso MTA destruye los barcos; el que conduce el jugador se olvida pero no se destruye mientras va dentro), SEG-02/04 (sin eventos remotos nuevos), UX (sin interacción nueva: no aplica tutorial ni teclas).
- **Pendiente**: EST-02 en los scripts antiguos y EST-03 (`rp_wanted` sin `<include>`), anteriores a este cambio. Los pasajeros de un auto no ven los barcos del conductor (`c_sync.lua` solo copia autos y peatones). Fases siguientes: tráfico aéreo determinista por horario (`c_air.lua`), helicóptero policial con `rp_wanted`, despegues y aterrizajes, y la capa de barcos en el editor `/nodos`.
- **Probar en juego**: en la costa de Santa María/Marina, Ocean Docks, la bahía de San Fierro (Bayside) y el río de Flint. Comprobar que los barcos **flotan a la altura correcta** (ni hundidos ni en el aire: el calado por modelo está en `MODELS` de `c_boats.lua`), que la escora en las curvas va hacia dentro, que el motor suena estando congelados, que frenan y pitan al cruzarte, que huyen al embestirlos o dispararles, que se pueden robar a nado y que no atraviesan muelles en los ríos estrechos. `/poblacioninfo` debe mostrar los barcos y `/debugscript 3` estar limpio.

<details><summary>scripts/auditar-recurso.sh rp_citizens --md</summary>

### Auditoría automática (2026-11-27, commit bc1db6a)

**Nota: 82/100** · OK 26 · FALLA B 0 · FALLA I 2 · AVISO 4

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| FALLA | I | EST-02 | Scripts de cliente con cache="false" | meta.xml:22 c_nodes_veh.lua ; meta.xml:23 c_nodes_ped.lua ; meta.xml:24 c_citizens.lua ; meta.xml:28 c_editor.lua ; meta.xml:30 c_sync.lua ; meta.xml:32 c_scenes.lua |
| FALLA | I | EST-03 | Dependencias declaradas con &lt;include&gt; (u opcionales comprobadas) | sin include: rp_wanted |
| AVISO | I | EST-04 | meta.xml y archivos coinciden | lua sin declarar: resources/[roleplay]/rp_citizens/backups/c_citizens_pre_ia_conduccion.lua ; resources/[roleplay]/rp_citizens/backups/c_citizens_pre_radio.lua |
| AVISO | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 46 outputChatBox: revisar si son avisos de acciones |
| AVISO | I | CLI-01 | Las teclas ignoran chat/consola/cursor | resources/[roleplay]/rp_citizens/c_editor.lua |
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
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-06 | Teclas sin choques con otros recursos | k z |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

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
