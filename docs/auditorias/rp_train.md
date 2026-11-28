# Auditoría de rp_train

## 2026-11-28 · mejorar (barreras largas en el cruce de Idlewood)
- **Foco**: barreras que abarcan todo el cruce de Idlewood (2200, -1732) y poder ajustar el largo del brazo.
- **Nota**: 100/100 → 100/100 (OK 32, FALLA B 0, FALLA I 0, AVISO 0)
- **Cambios**:
  - P5 Columna `rail_crossings.length` (BD-01, `ADD COLUMN IF NOT EXISTS`, NULL = brazo de serie): el brazo 968 se escala a lo largo (`setObjectScale(arm, 1, 1, length / BARRIER_ARM_LENGTH)`) y pierde la colisión, como el de los torniquetes.
  - P5 `/puntabarrera [id]` (DOC-03, catálogo de `rp_adminpanel`): de pie donde debe acabar la punta del brazo bajado; gira (`rot` = rumbo base→punta, `side` = 1) y alarga esa barrera o la más cercana a 25 m (`BARRIER_TIP_MAX`).
  - Dos barreras sembradas en el esquema (idempotente, `NOT EXISTS` a 3 m): base (2194.93, -1725.55) con brazo de 12,49 m hacia el sur y base (2206.68, -1739.14) con brazo de 13,02 m hacia el norte.
- **Reglas manuales**: SEG-02 (solo admin, sin eventos remotos), BD-06 (consultas parametrizadas), INT-09 N/A (herramienta de admin).
- **Pendiente**: el sentido de bajada supone que la rotación Y +90 lleva el brazo al eje X local (lo mismo que asumen los torniquetes); si en juego baja al revés, cambiar el signo en `/puntabarrera` o usar `side = -1`. Si se borra una de las dos barreras sembradas, el esquema la vuelve a crear al reiniciar `rp_database`: para quitarla del todo, borrar también su `INSERT` en `schema.lua`.
- **Probar en juego**: `restart rp_database` y `restart rp_train`; en el cruce ver que los dos brazos suben en vertical (~12-13 m) y al pasar el tren bajan cubriendo cada uno su mitad hasta la punta indicada; `/puntabarrera` junto a una barrera para reajustar; `/debugscript 3` limpio.

## 2026-11-27 · mejorar (boletería destacada, torniquetes y rejas)
- **Foco**: que se vea quién vende los boletos y torniquetes en las estaciones donde se valida (corta) el boleto con una UI.
- **Nota**: 98/100 → 100/100 (OK 31 → 32, FALLA B 0, FALLA I 0, AVISO 1 → 0)
- **Cambios**:
  - P4 Boletería destacada (`c_booth.lua`): el empleado (data `rp:train:booth`) tiene un aura blanca en el piso que respira (disco que crece y se apaga + anillo que se abre, texturas SVG), el personaje se ve normal; solo peds en streaming y a menos de 45 m (UX-02). Se probó antes un contorno con shader en capa, pero pintaba el ped entero de blanco.
  - P5 Torniquetes (`/creartorniquete`, tipo `gate` en `train_fixtures`, sin cambio de esquema): poste 966 + brazo 968 escalado y elemento `rp_traingate`. Desde fuera, UI CEF con el boleto y la E dibujada; con E el servidor revalida personaje, distancia, lado, mundo, abatido/esposado y boleto, lo gasta y deja un pase de 30 min para esa estación; el brazo sube 3,5 s. Desde el andén se sale libre al acercarse. Con el brazo bajado el cliente no deja cruzar desde fuera.
  - P5 Subir al tren: en una estación con torniquetes se sube con el pase (se gasta); sin torniquetes, como antes con el boleto. Aviso «Primero valida tu boleto en el torniquete».
  - P2 Integración: tipo `turnstile` en la gramática Owl de `rp_admin` (`/nearbyturnstiles`, `/delturnstile <id>`...), comando en el catálogo de `rp_adminpanel`, saludo de la boletería que menciona los torniquetes.
  - P4 Experiencia: boleto que se perfora, se rasga el talón y aparece el sello VALIDADO, con sonidos Kenney (abrir, perforar, rasgar, confirmar, error) y la tecla E dibujada (UX-01, UX-06); sin boleto dice dónde comprarlo y el precio; la tarjeta tiembla si intentas cruzar cerrado. Modo demo en `html/index.html#demo`.
  - P5 Rejas (`/crearreja <tipo>`, tipo `fence`): cinco modelos del juego (`FENCE_MODELS`) congelados en el servidor e irrompibles en el cliente (`setObjectBreakable`), para cerrar los lados de los torniquetes. Columna nueva `train_fixtures.model` (BD-04, entrada al final de `schema.lua`).
  - P4 Editor 3D común (`c_signeditor.lua`): cartel, torniquete y reja se abren en el editor al crearlos y se reeditan con `/editarcartel`, `/editartorniquete` y `/editarreja [id]`; las piezas se mueven en vivo en el juego del admin, el torniquete marca ENTRADA y ANDÉN, la reja su caja; si el servidor rechaza el guardado (más de 30 m) vuelven a su sitio. Guardado único `rp:train:fixtureSave` validado en el servidor (admin, números, distancia). Geometría del torniquete compartida (`TrainGateLayout`). El personaje queda congelado mientras edita. `/duplicar <cantidad> <x> <y> <z> [rot]` prepara copias en fila (vista previa en verde claro, ejes X/Y/Z dibujados y coordenadas en pantalla) que el servidor crea al guardar, con límites revalidados (`DUP_MAX` 20, `DUP_STEP_MAX` 10 m).
  - P3 Pruebas: tipos `gate` y `fence` en `admin_exports_de_elementos`, columna `model` en `train_tabla_boleterias_y_carteles` y `train_rejas_modelos`.
- **Reglas manuales revisadas**: SEG-02 ✔ (`client`, distancia, lado del paso y boleto revalidados en el servidor; el bloqueo del cliente es solo comodidad: el servidor exige el pase al subir), SEG-04 ✔ (el boleto se gasta antes de dar el pase), CIC-03 ✔ (torniquetes recreados al arrancar; los pases viven en memoria y se pierden con un `restart`), UX-01/02/06 ✔.
- **Pendiente**: el aspecto del torniquete es una barrera pequeña (no hay modelo de torniquete en GTA SA); el largo y el sentido del brazo (`GATE_ARM_LENGTH`, `GATE_ARM_SIDE`) hay que ajustarlos en juego. Los pases no sobreviven a un `restart rp_train`. Solo bloquea el paso del propio torniquete: los admins deben cerrar los accesos del andén con varios.
- **Probar en juego**: aura en el piso de la boletería (personaje normal) que desaparece a 45 m; `/creartorniquete` fuera de Unity mirando al andén; sin boleto (UI pide comprarlo, no deja cruzar); con boleto (se corta, sube el brazo, se pasa); volver a pasar con el pase (no gasta otro); subir al tren sin pasar por el torniquete (lo rechaza); salir desde el andén (se abre solo); `/delturnstile`; `/editartorniquete` (mover, girar, cancelar vuelve a su sitio, guardar; personaje congelado y descongelado al cerrar); `/duplicar 6 1.6 0 0` con el editor abierto (vista previa, Enter crea 6 copias); `/crearreja` sin tipo (lista) y con cada tipo, chocar con un coche (no se rompe ni se mueve), `/editarreja`, `/delstationfence`; `restart rp_train` con la UI abierta; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-27, commit 1b37797)

**Nota: 100/100** · OK 32 · FALLA B 0 · FALLA I 0 · AVISO 0

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-26 · mejorar (pasajeros, boleterías, carteles LED)
- **Foco**: boleterías donde comprar el boleto, viajar como pasajero bajando solo en estaciones, carteles LED con la llegada estimada y claxon cuando faltan 10 s para salir.
- **Nota**: 98/100 → 98/100 (OK 27 → 31, FALLA B 0, FALLA I 0, AVISO 1)
- **Cambios**:
  - P5 Claxon de salida: el tren espera 20 s en cada andén y, cuando faltan `DEPART_HORN_MS` (10 s), suena `sounds/claxon.mp3` en 3D (`rp:train:horn`, sustituye al claxon de llegada). Mientras espera, la locomotora lleva `rp:train:dwell` = estación.
  - P5 Boleterías: `/crearboleteria` pone una empleada en la estación más cercana que vende el item nuevo `train_ticket` con el menú de `rp_shops` (`addTempShop`, que acepta un saludo opcional; precio, cobro y peso los valida `rp_shops`). Se vuelven a registrar si se reinicia `rp_shops`. Tabla nueva `train_fixtures` (BD-04, solo hacia adelante).
  - P5 Pasajeros (`s_passengers.lua` / `c_passengers.lua`): E junto a un vagón del tren de pasajeros parado en el andén; el servidor comprueba personaje, abatido/esposado, que el tren esté en el andén, distancia al vagón (`TrainTrack.carFrame`), plazas y el boleto, que se gasta (SEG-02). Viaja sentado y oculto dentro del vagón, sin controles, con cámara que gira con el ratón. Solo baja con E en el andén; el cliente propone el suelo más alto junto al vagón y el servidor lo valida (si no, lo deja junto al vagón).
  - P5 Carteles LED (`/crearcartel`, `c_stations.lua`): render target por cartel cercano (se libera al alejarse) con máscara de puntos repetida (`images/led_dot.png`) y texto que se desplaza: «PRÓXIMO TREN EN m:ss · DIRECCIÓN …», «EL TREN ESTÁ LLEGANDO» o «TREN EN ANDÉN · SALE EN n s». El servidor publica `rp:train:eta` cada 2 s (crucero + paradas intermedias + frenadas); export `getTrainEta`.
  - P1 Ciclo de vida: el pasajero se suelta junto al vagón al cambiar de personaje, quedar abatido o parar el recurso; al morir, donde esté; `onPlayerQuit` limpia el estado (CIC-01/02). El cliente devuelve la cámara al parar (CIC-05).
  - P2 Integración: listar y borrar boleterías y carteles con la gramática Owl de `rp_admin` (`ticketbooth`, `trainsign`, con `kind`); comandos nuevos en el catálogo de `rp_adminpanel`.
  - P4 Experiencia: aviso con la E dibujada para subir y bajar y el ratón dibujado al viajar (UX-01, Kenney CC0 copiados de `assets/`, UX-10); una sola indicación a la vez (UX-02); saludo de la empleada con el precio y el paso siguiente; cuenta atrás de la salida en el aviso y en el cartel (UX-07).
  - P3 Pruebas: `train_tabla_boleterias_y_carteles`, `train_boleto_en_catalogo`, `train_llegada_estimada` y los tipos `booth`/`sign` en `admin_exports_de_elementos` (PRU-01). `scripts/test.sh`: todas las de `rp_train` y admin pasan; fallan las de Fotogram y `rp_animlab` porque en esta copia faltan archivos que no están en git (`rp_phone/config.music.lua`, `.ifp` de `rp_animlab`/`rp_mocap`), ajeno a este cambio.
- **Reglas manuales revisadas**: SEG-02 ✔ (`client` y todo revalidado en el servidor), SEG-04 ✔ (el boleto se gasta antes de subir; el cobro es de `rp_shops`), BD-06 ✔, CIC-03 ✔ (carteles y boleterías se recrean al arrancar; el estado de viaje se reenvía en cada parada), CIC-06 ✔, INT-07 ✔ (E contextual: solo actúa junto a un vagón o viajando), CLI-03 ✔ (búsqueda de vagón cada 250 ms; por frame solo los carteles cercanos y el aviso), UX-01/02/06/07/10 ✔, UX-03 no aplica (tres pasos, cada uno con su aviso).
- **Pendiente**: el pasajero va oculto dentro del vagón (no hay asientos modelados en el 570); la cámara sigue al vagón y no al sentido de marcha; la llegada estimada es aproximada (se corrige cada 2 s); sin blip de estación en el minimapa.
- **Probar en juego**: `/crearboleteria` y `/crearcartel` en Unity Station; comprar el boleto (sin dinero → error); E junto a un vagón con el tren en marcha (no deja), parado sin boleto (pide comprarlo) y con boleto (sube, se gasta); mirar con el ratón; intentar bajar en marcha; bajar en Market (queda en el andén); claxon a los 10 s de la salida; el cartel cuenta atrás y se lee de día y de noche; `restart rp_train` con un pasajero dentro (queda junto al vagón con controles y cámara); `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 7a642fc)

**Nota: 98/100** · OK 31 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
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
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

## 2026-11-26 · arreglar (vagones)
- **Síntoma** (prueba de Fabián): al iniciar, locomotora y vagón solapados; la locomotora se va y el vagón se queda siempre en el andén. Ya pasaba antes de esta rama (primera captura).
- **Causa raíz**: el enganche de trenes de MTA (`attachTrailerToVehicle`) no arrastraba los vagones; el foro de MTA reconoce problemas de sincronización de remolques desde hace años. Además, al crear cada pieza en el nodo más cercano, dos piezas podían caer en el mismo nodo.
- **Arreglo**: sin enganche. Cada vagón es un tren suelto en la vía principal (`rp:train:of`, `rp:train:idx`), colocado con `setTrainPosition`; el cliente que lo sincroniza (el mismo que la locomotora) le aplica la velocidad real de la locomotora más una corrección de hasta `CAR_CATCHUP` m/s hacia su sitio, calculado con el largo real de cada modelo (`getElementBoundingBox`) + `COUPLING`. Solo si está a más de `CAR_SNAP` m (al aparecer) se coloca de una vez. Unidades de `setTrainPosition` confirmadas con la wiki (bucle 0..18107 = `TrainTrack.gameLength`).
- **Probar en juego**: `restart rp_train`; en Unity los 3 vagones detrás de la locomotora, sin solaparse, y salen con ella; seguir el tren hasta Market (curvas y túnel): los vagones no se separan ni chocan.

## 2026-11-26 · arreglar
- **Síntoma** (prueba en juego de Fabián): el tren salía con los vagones solapados, uno en la vía de al lado (túnel de Market), e iba en reversa empujando los vagones.
- **Causa raíz**: (1) cada vagón se colocaba con `setElementPosition` y el juego lo engancha a la vía más cercana; en LS corre pegada la vía de `tracks4.dat`. (2) Al detectar marcha atrás se invertía el signo de `setTrainSpeed` en vez del sentido del tren, así que la locomotora avanzaba empujando a los vagones.
- **Arreglo**: sentido con `setTrainDirection` (`TRAIN.CLOCKWISE`; el servidor lo corrige y avisa si el juego lo mueve al revés) y velocidad siempre positiva; se retira `rp:train:sign`. MTA 1.6 no tiene `getTrainTrack`/`setTrainTrack` (comprobado en `client.dll` y `deathmatch.dll`; la primera versión daba `attempt to call global getTrainTrack`): cada pieza se pone primero en un nodo exacto de la vía principal (`TrainTrack.nodePoint`, el juego engancha a la vía del nodo más cercano) y luego en su punto con `setTrainPosition` (distancia horizontal como el juego: `TrainTrack.gameD`). La geometría pasa a `shared/`: el cliente detecta un vagón a más de 2 m de la vía principal (la paralela de Unity está a 4 m) y lo devuelve igual. Geometría probada fuera del juego con `lua5.1.dll`: proyección exacta, desvío de la vía de tracks4 = 4,0 m. Fluidez: a menos de `SYNC_RADIUS` (180 m) el jugador más cercano es el sincronizador (`setElementSyncer` persistente), así el tren visible siempre lo mueve la física y nunca los saltos de 500 ms del servidor.
- **Nota**: 98/100 → 98/100.
- **Probar en juego**: salida desde Unity con los 3 vagones detrás de la locomotora y en la misma vía; pasar por el túnel de Market; ir en un vehículo al lado del tren (debe verse fluido); si en consola sale `sentido corregido`, poner `CLOCKWISE` al valor que indica.

## 2026-11-26 · mejorar
- **Foco**: recorrido completo del tren de Los Santos, saliendo de Unity Station, y bajo coste.
- **Nota**: 98/100 → 98/100 (OK 27, FALLA B 0, FALLA I 0, AVISO 1)
- **Cambios**:
  - P5 Recorrido: el bucle completo de `tracks.dat` (926 nodos, 18,1 km) se cuenta desde Unity Station (`ROUTE_ORIGIN`): Unity > Market > Cranberry > Yellow Bell > Sobell > Linden. Los trenes salen de una estación (`TRAINS[i].station`): el de pasajeros de Unity (espera 20 s en el andén y arranca), el de carga de Cranberry. Export nuevo `getTrainRoute`; `getTrainState` añade `station`, `next` y `nextIn`. Prueba `train_recorrido_desde_unity` (PRU-01).
  - P4 Rendimiento: sin jugadores a menos de `PLACE_RADIUS` (450 m) del tren ni de donde quedó, el servidor ya no llama a `setElementPosition`/`setElementRotation` en cada paso (antes ~40 RPC/s a todos los jugadores con 2 trenes de 5 piezas); solo avanza su distancia en memoria. Tampoco reenvía `rp:train:v` si nadie sincroniza el tren, y las posiciones de los jugadores se leen una vez por paso para todos los trenes.
- **Reglas manuales revisadas**: SEG-02 ✔ (sin eventos remotos), CIC-04 (timer permanente que muere con el recurso), INT-03 ✔. Contrato intacto: `rp:train`, `rp:train:v`, `rp:train:sign`, `rp_railcrossing`, `getTrainState`, `getTrackLength`.
- **Pendiente**: lo de la entrada anterior (brazo 968, bocina en clientes que no sincronizan).
- **Probar en juego**: `restart rp_train` y ver en consola la línea `recorrido: Unity Station (0.0 km) > ...`; ir a Unity Station: el Brown Streak espera allí y arranca hacia Market; seguirlo en un vehículo por todo el bucle; alejarse más de 450 m y volver a acercarse: el tren aparece en su sitio, en marcha, sin saltos ni un tren fantasma parado; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit f8baccc)

**Nota: 98/100** · OK 27 · FALLA B 0 · FALLA I 0 · AVISO 1

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
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
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | R | DOC-04 | Registro de auditoría en docs/auditorias/ |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>

---

## 2026-11-26 · crear
- **Motivo**: devolver el tren de San Andreas al servidor, con bocina si hay alguien en la vía y pasos a nivel con barreras, campanas y tráfico IA que se detiene.
- **Nota**: — → 96/100  (OK 26, FALLA B 0, FALLA I 0, AVISO 2)
- **Cambios**: recurso nuevo. Vía principal desde `tracks.dat` (solo servidor); el servidor simula la posición de cada tren y solo el cliente que lo sincroniza aplica la velocidad (BD-05 espera a la BD, CLI-02 sin onClientRender: temporizador de 250 ms solo con trenes cargados). Tabla `rail_crossings`; comandos de admin en el panel (DOC-03); prueba en `rp_test` (PRU-01). `rp_citizens` frena ante barreras bajadas.
- **Reglas manuales revisadas**: SEG-02 ✔ (sin eventos remotos), BD-06 ✔ (INSERT/DELETE parametrizados), PRU-02 ✔ (4 pruebas PASS), UX-10 ✔ (sonido con CREDITOS.md). CIC-04: temporizadores permanentes que mueren con el recurso.
- **Pendiente**: calibrar en juego la posición y el giro del brazo 968 (`side`, `/crearbarrera inv`); comprobar que la bocina nativa suena con `setPedControlState` en clientes que no sincronizan el tren.
- **Probar en juego**: esperar el tren en Unity Station (para 20 s); pararse en la vía (bocina); `/crearbarrera` a cada lado de un cruce y ver bajar/subir barreras, campanas y autos IA detenidos; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit 0f460db)

**Nota: 96/100** · OK 26 · FALLA B 0 · FALLA I 0 · AVISO 2

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | CIC-04 | Los timers se pueden cancelar | usa setTimer y nunca killTimer/isTimer |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_train.md |
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
| OK | I | BD-05 | Espera a la BD al arrancar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 1 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | I | CLI-01 | Las teclas ignoran chat/consola/cursor |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| OK | I | PRU-01 | Pruebas en rp_test |  |
| N/A | B | SEG-01 | Handlers de eventos remotos usan client | sin eventos remotos |
| N/A | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit | sin estado por jugador |
| N/A | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout | sin estado por jugador |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
