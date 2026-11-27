# Auditoría de rp_citizens

## 2026-11-27 · mejorar · foco: despegues y aterrizajes (fase C)
- **Qué cambia en el juego**: en el aeropuerto de Los Santos los aviones **despegan** (aparecen en la cabecera, ruedan acelerando, rotan, suben y recogen el tren) y **aterrizan** (aproximación alineada con la pista, tren bajado, toma de contacto a ~58 m/s y frenada hasta el final de la pista). Cuando los admins capturen las pistas de SF, LV o Verdant Meadows, aparecen solos los vuelos entre aeropuertos.
- **Por qué con captura**: los datos del juego no dan el eje de las pistas (en los IPL solo están los centros de las piezas del modelo, que incluyen las calles de rodaje, y no hay objetos de luces de pista). Inventarlas dejaría aviones aterrizando en el césped. La pista de LS va **provisional** (y = −2493 según la cinemática de `rp_login`, x 1420 → 2080, z 13); `/runways` la marca así hasta que se capture de nuevo.
- **Diseño**:
  - Pistas en `runways.json` (servidor, `s_clock.lua`). Comandos de admin `/setrunway <ls|sf|lv|verdant> <start|end>` (alias `/pista`; a pie sobre el eje; altura de los pies; 300-3.000 m), `/delrunway`, `/runways`. Se envían con la hora (`rp:citizens:clockRecv`) y, al cambiar, a todos (`rp:citizens:runways`). El cliente rehace el horario en el siguiente ciclo.
  - Rutas generadas en `c_air.lua` (`buildAirportRoutes`), con velocidad y tren por punto (`pts[i][4]`, `pts[i][5]`):
    - por cada pista, salida y llegada internacionales (por el eje, desde y hacia fuera del mapa);
    - entre cada par de pistas del mismo tipo, vuelo directo con un punto de crucero a 320 m;
    - Verdant Meadows solo para avionetas (velocidades × 0,55, alturas × 0,6).
  - **Reserva de pista**: cada ruta ocupa la pista desde el inicio hasta pasar 30 m (despegue) y desde que baja de 30 m hasta el final (aterrizaje). Las horas de salida (periodo 480 s) se eligen en orden fijo, la primera cada 5 s sin choque y con 15 s de margen, así que el resultado es igual en todos los clientes.
  - En vuelo y en pista: las ruedas nunca bajan de la cota de la pista y se suma la altura real del modelo (`getElementDistanceFromCentreOfMassToBaseOfModel`). Fundido de 3 s al aparecer y al irse, porque no hay rodaje.
- **Verificación**: sintaxis con `lua5.1.dll`; simulación con solo LS y con tres pistas (SF y LV inventadas, solo para la prueba): 2 y 12 rutas, **0 s con dos vuelos a la vez en la misma pista en 24 h**, sin saltos (≤ 8 m por 0,1 s a 80 m/s), toma a 58 m/s. Margen mínimo sobre calles y aceras del juego en vuelo (> 30 m sobre la pista): salida de LS 32 m antes de subir el primer tramo de ascenso a 100 m; llegada 45 m sobre las colinas de Flint.
- **Nota**: 82 → 82.
- **Pendiente**: capturar las pistas de SF, LV y Verdant Meadows y **recapturar LS** (provisional). No hay rodaje ni puertas de embarque. La carrera de despegue y la frenada se ajustan al largo de cada pista: en una pista corta frenan fuerte.
- **Probar en juego**: `/irvuelo salida` y `/irvuelo llegada` en LS. Que ruede por el centro de la pista (si va por el borde o el césped, recapturar con `/setrunway ls start|end`); que las ruedas toquen el asfalto, sin hundirse ni flotar; que el tren baje en la aproximación y suba tras despegar; y que no atraviese las grúas de Ocean Docks al salir hacia el este. Después capturar SF y LV y comprobar que aparecen los vuelos entre aeropuertos (`/vuelos`).

## 2026-11-27 · mejorar · foco: punto de agua para la policía (fase B)
- **Cambio de plan**: la fase B era un helicóptero policial, pero `rp_wanted` ya lo tiene completo; se descartó para no duplicarlo. En su lugar, persecución por mar en `rp_wanted` (ver `docs/auditorias/rp_wanted.md`).
- **Cambio en `rp_citizens`**: export de cliente `citizenBoatSpot(minD, maxD)` en `c_boats.lua`: punto de agua navegable sobre la red de barcos a esa distancia del jugador, de preferencia fuera de la vista, con el nivel del agua y el rumbo hacia el jugador. Lo usa `rp_wanted` para hacer aparecer sus lanchas.
- **Nota**: 82 → 82.

## 2026-11-27 · mejorar · foco: lanzaderas por mar con horario (fase A)
- **Qué cambia en el juego**: un **ferry** cruza la bahía de San Fierro (Bayside ↔ Pier 69) y una **lancha** recorre la costa de LS (muelle de Santa María ↔ Ocean Docks). Salen del muelle acelerando y pitando, frenan al llegar y dan la vuelta mientras esperan 40-45 s. Todos los jugadores los ven en el mismo sitio a la vez, como los aviones.
- **Cambio de diseño en `c_air.lua`**: el motor de horarios pasa de velocidad constante a **tabla tiempo → distancia** por ruta (velocidad en cada punto de paso, `pts[i][4]` opcional), base también para la fase C (despegues y aterrizajes). Tres tipos de ruta: con horario (`period`), circuito (`loop`) y lanzadera (`shuttle`, ida y vuelta con `dwell`). El camino de las lanzaderas sale de la red de barcos (Dijkstra entre los nodos más cercanos a `from` y `to`, determinista) y su perfil de velocidad es simétrico (`v = min(crucero, sqrt(1 + 2·a·d))` desde cada extremo), así que la vuelta es la ida al revés. En el muelle el rumbo gira del de llegada al de salida con un suavizado que también sale de la hora. Los barcos flotan sobre `getWaterLevel` (consultado cada ~0,5 s) con vaivén; motor al ralentí atracados.
- **Arreglo de paso**: en la ruta «Costa» un comentario mal colocado (commit bd2f79c) anulaba el punto `{ 900, -2750, 55 }`; restaurado.
- **Verificación**: sintaxis con `lua5.1.dll`; simulación de todas las rutas en pasos de 0,1 s: sin saltos (salto máximo = velocidad × 0,1 s) ni giros bruscos (≤ 3,3° por paso); los vuelos conservan sus tiempos; ferry 2.003 m en 243 s, lancha 2.354 m en 259 s; contra la máscara agua/tierra de `rp_map` (celdas de 50 m): 0-2 % en celdas de tierra, solo junto a los muelles.
- **Nota**: 82 → 82.
- **Probar en juego**: `/irvuelo ferry` y `/irvuelo lancha`; que floten bien, que giren en el muelle sin atravesarlo, que piten al salir y que no corten por tierra.

## 2026-11-27 · mejorar · foco: avionetas más bajas
- **Motivo**: Fabián vio una avioneta con `/irvuelo` pero iba tan alta que casi no se veía.
- **Cambio**: las rutas de avioneta bajan: costa 150-200 → 55-110 m (90 m sobre las grúas de Ocean Docks), fumigadora 110 → 60-75 m, Verdant Meadows 130-140 → 75-105 m. Cada punto de paso tiene su propia altura: ~30-40 m sobre el suelo más alto del tramo.
- **Cómo se midió el suelo**: z máxima de los nodos de calles y aceras del juego (`c_nodes_veh.lua` y `c_nodes_ped.lua`, sin los de interiores, que están a más de 600 m) a menos de 150 m de la ruta. El relieve de `rp_map` (`terrain.js`) **no sirve** para esto: es la media de objetos por celda y da más de 500 m en zonas llanas como el aeropuerto de San Fierro. Margen mínimo resultante: costa 36 m, fumigadora 33 m, Verdant 37 m; el resto de rutas, ≥ 76 m.
- **Nota**: 82 → 82.
- **Probar en juego**: `/irvuelo costa`, `/irvuelo fumigadora` y `/irvuelo verdant`: que se vean bien y que no atraviesen árboles, colinas, grúas ni edificios.

## 2026-11-27 · mejorar · foco: encontrar el tráfico aéreo (`/gotoaircraft`)
- **Motivo**: Fabián no lograba ver ningún avión porque no sabía dónde ni cuándo pasan.
- **Cambio**: comando de admin `/gotoaircraft [ruta]` (sintaxis Owl) con alias `/irvuelo`. El servidor comprueba `admin_level >= 1`, saca al admin del vehículo, lo pasa a interior y dimensión 0 y avisa al cliente (`rp:citizens:air:goto`). El cliente, que tiene el horario, elige un vuelo que seguirá en el aire dentro de 30 s y dentro del mapa (sin ruta, los de línea primero y el que más tiempo le queda; con ruta, la que contenga el texto), lleva al admin al suelo o al agua justo bajo ese punto (congelado hasta que carga la colisión) y sigue la aeronave con un blip en el radar (icono 5) hasta que sale del mapa o pasan 3 min. Respuestas con `rp_notify`. Añadido al catálogo de `rp_adminpanel` y a `RECURSOS.md`.
- **Verificación**: sintaxis con `lua5.1.dll` y comando ejecutado con MTA simulado (sin ruta, `noticias`, `ls-lv` y una ruta inexistente).
- **Nota**: 82 → 82.
- **Probar en juego**: `/irvuelo` y `/irvuelo noticias` con una cuenta admin (y que una sin `admin_level` reciba «No tienes permiso»); que caigas en el suelo y no en el aire, que el blip aparezca en el radar y se mueva, y que la aeronave pase por encima en ~30 s. Las rutas de la costa pueden dejarte en el agua.

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
