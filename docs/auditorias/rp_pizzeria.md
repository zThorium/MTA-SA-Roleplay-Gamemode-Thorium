# Auditoría de rp_pizzeria

## 2026-11-25 · mejorar
- **Motivo**: el sonido de pintar salsa sonaba "a fallo"; incorporar las imágenes útiles de los packs de Kenney (Input Prompts, Emotes, UI Pack).
- **Nota**: 100 → 100.
- **Cambios**:
  - Pintar: un sonido suave al empezar cada trazo (antes uno cada 170 ms que se pisaban) y un «¡bien!» al cubrir el 80 % de salsa o queso.
  - Globos de ánimo sobre los clientes con los emotes de Kenney (estilo 3, escalados ×4): feliz, esperando (…), triste, enojado, corazones, queja (💢), propina (💲) y un «!» que late cuando el cliente ya está en la caja esperando que lo atiendan. La tarjeta de resultado usa los mismos.
  - Tecla E dibujada (Input Prompts) en el aviso de cada estación y sobre el objeto resaltado del tutorial; ratón dibujado (arrastrar / clic) en el globo del entrenador y en los pasos del corte.
  - UI Pack: revisado y no usado (botones y paneles genéricos que chocarían con el estilo actual).
  - `tools/gen_assets.ps1` ya no genera caritas (no pisa los emotes); `CREDITOS.md` del recurso con el origen y la licencia de las imágenes.
- **Reglas manuales revisadas**: SEG-05 ✔ (todo CC0, sin material de Rockstar), CLI-03 ✔ (texturas creadas una vez por turno).
- **Pendiente**: —
- **Probar en juego**: pintar salsa (un sonido por trazo y «bien» al cubrir); globos sobre los clientes («!» al llegar a la caja, cara según la paciencia, 💲 con propina, 💢 con queja); la tecla E en los avisos.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |
</details>

## 2026-11-25 · mejorar
- **Motivo**: sonidos definitivos (packs de Kenney que dejó Fabián) y música de fondo que reaccione a la presión del turno.
- **Nota**: 100 → 100.
- **Cambios**:
  - 26 efectos de Kenney «Interface Sounds» y «UI Audio» (CC0) en `html/sounds/kenney/`, asignados por momento en `SOUNDS` (`html/app.js`), con variantes al azar para los repetidos (ingredientes, cortes, pintar). Sonidos nuevos: botones, elegir herramienta, abrir/cerrar ventana, «¡Bien!», pasos del tutorial, pintar salsa/queso, reponer. Se quitan los sintetizados sin uso; queda `sizzle.wav`.
  - `musica_fondo.mp3` en bucle (`MUSIC_VOLUME`). Urgencia: con un cliente en el último tercio de paciencia la música acelera a 1,1× y en el último 15 % a 1,22× (cambio suave, sin cambiar el tono), suena un reloj cada segundo y los bordes de la pantalla laten en rojo; al atenderlo vuelve sola a la normalidad.
  - `html/sounds/CREDITOS.md`: qué suena en cada momento y licencias.
- **Reglas manuales revisadas**: SEG-05 ✔ (sin material de Rockstar; Kenney es CC0), CLI-03 ✔ (la urgencia se calcula en el bucle del HUD que ya existía).
- **Pendiente**: anotar la fuente y la licencia de `musica_fondo.mp3` en `CREDITOS.md`.
- **Probar en juego**: que se oigan los sonidos de cada estación y de los botones; la música en bucle; dejar que un cliente se impaciente: la música acelera, suena el reloj y laten los bordes; al atenderlo, todo vuelve a la calma.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · mejorar
- **Motivo**: en la mesa de armado no se entendía el orden (se ponían ingredientes sin salsa ni queso) y la tarjeta del tutorial obligaba a mirar a una esquina fija.
- **Nota**: 100 → 100.
- **Cambios**:
  - Entrenador de la mesa de armado (tutorial y hasta `GUIDES_UP_TO_LEVEL`, antes `CUT_GUIDES_UP_TO_LEVEL`): 4 pasos en orden (salsa ≥ 80 %, queso ≥ 80 %, cada ingrediente en su cantidad y mitad, «Al horno»); oscurece la ventana y deja iluminado solo lo que hay que tocar; globo pegado al elemento con «Paso N de 4» y el conteo («Llevas 2 de 4»); elige sola la herramienta al cambiar de paso.
  - La tarjeta del tutorial del HUD se coloca junto a lo que hay que mirar: al lado del objetivo 3D en pantalla (Lua manda la posición hasta 10 veces/s), a la izquierda del panel Cocina o debajo de la comanda; se esconde mientras hay una ventana abierta.
- **Reglas manuales revisadas**: SEG-02 ✔ (el entrenador solo guía; el servidor sigue evaluando lo armado), CLI-03 ✔ (la posición se envía con umbral de 100 ms y 10 px).
- **Pendiente**: —
- **Probar en juego**: tutorial: la tarjeta aparece junto a la caja, el horno o el cliente y se mueve con la cámara; en la mesa de armado los 4 pasos en orden con el globo al lado de cada herramienta; con la ventana abierta no se ve la tarjeta del HUD.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · mejorar
- **Motivo**: el corte no se entendía (muchos jugadores son niños) y faltaban efectos visuales; preparar sonidos y música propios.
- **Nota**: 100 → 100.
- **Cambios**:
  - Corte: líneas guía punteadas numeradas; la activa brilla en amarillo y un cuchillo animado la recorre; el trazo parecido se ajusta a la guía (verde, «¡Bien!», destello) y avisa si es corto o torcido; 3 pasos ilustrados (agarra el cuchillo, sigue la línea, N cortes = M trozos); «Empacar» late al terminar y la caja se cierra sobre la pizza. Guías y ajuste en el tutorial y hasta `CUT_GUIDES_UP_TO_LEVEL` (2); desde el nivel 3 solo el centro marcado.
  - Efectos en el mundo (`client/c_fx.lua`): vapor en hornos y freidora mientras trabajan, humo negro si se quema, chispas doradas sobre el cliente encantado.
  - Efectos del HUD: confeti con nota ≥ 85, el dinero vuela al marcador, rebote al poner ingredientes, hornos en su punto que brillan.
  - Música de fondo opcional (`html/sounds/music.mp3`, `MUSIC_VOLUME`) y `html/sounds/CREDITOS.md` con la lista de sonidos para reemplazar y sus licencias.
- **Reglas manuales revisadas**: SEG-02 ✔ (las guías solo ayudan a trazar; el servidor sigue evaluando ángulos y distancia al centro, y decide si hay guías por nivel o tutorial), CLI-03 ✔ (efectos recalculados cada 300 ms; el bucle de dibujo del corte solo vive mientras el panel está abierto), CIC-06 ✔ (efectos destruidos al terminar el turno o parar el recurso).
- **Pendiente**: sonidos y música definitivos de Fabián.
- **Probar en juego**: cortar con guías en el tutorial (ajuste, «¡Bien!», caja); en nivel 3 sin guías; vapor y humo al hornear y al quemar; confeti y dinero volando con una pizza excelente.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · arreglar
- **Motivo**: el cliente ya estaba en la caja, pero al pulsar E salía "todavía viene llegando".
- **Nota**: 100 → 100.
- **Causa**: la llegada la decidía solo el servidor con un tiempo calculado a 1,25 m/s (`ARRIVE_MS`); desde que los peds caminan con el andar real de GTA llegan antes.
- **Cambios**: el cliente avisa (`rp:pizzeria:arrived`) cuando el ped llega a la caja; el servidor lo acepta solo si es el primero de la fila y desde un tiempo mínimo plausible (`MIN_ARRIVE_FRACTION` = 40 % de `ARRIVE_MS` desde que entra; 0,8 s al avanzar un puesto). `ARRIVE_MS` queda como respaldo si el aviso no llega.
- **Reglas manuales revisadas**: SEG-02 ✔ (el aviso solo puede adelantar la llegada dentro de un mínimo físico; no da dinero ni nota), SEG-04 ✔ (throttle de 200 ms).
- **Pendiente**: —
- **Probar en juego**: en cuanto el cliente se para frente a la caja, E toma el pedido y el aviso cambia a "tomar el pedido"; con dos clientes, el segundo también al avanzar.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · arreglar
- **Motivo**: los clientes avanzaban "teletransportándose de a poco"; y en el turno seguían visibles el minimapa, las necesidades y el resto del HUD de `rp_hud`.
- **Nota**: 100 → 100 (`rp_hud`: 89 → 89, sus fallas son anteriores).
- **Causa**: `client/c_customers.lua` usaba `setPedControlState(ped, "forward", ...)`; el control se llama `"forwards"` (así lo usa `rp_citizens/c_citizens.lua:258`). El nombre mal escrito no da error, el ped nunca andaba y lo único que lo movía era el empujón anti-atasco de 0,5 m cada 1,5 s.
- **Cambios**:
  - Control `"forwards"` + `"walk"`, como `rp_citizens`; el empujón anti-atasco pasa a 3 s y solo actúa si de verdad no avanza.
  - `rp_hud`: export de cliente nuevo `setHudHidden(razon, bool)` que oculta solo su HUD (como F7), sin tocar chat, avisos ni `rp:hudHidden` (que también ocultaría el HUD de la pizzería). `rp_pizzeria` lo activa al empezar el turno y lo quita al terminar o al parar el recurso (CIC-05).
  - Skill `arreglar-recurso`: la trampa de `"forwards"` en los fallos típicos.
- **Reglas manuales revisadas**: INT-01 ✔ (no se toca `rp:hudHidden` ni el HUD nativo; se usa una API de `rp_hud`), CIC-05/06 ✔.
- **Pendiente**: —
- **Probar en juego**: clientes caminando con el paso normal de GTA de la puerta a la caja, a la espera, al mostrador y a la silla; al empezar el turno desaparecen minimapa, necesidades y clima, y vuelven al terminar (también con `/terminarturno` y al reiniciar `rp_pizzeria`); F7 sigue funcionando fuera del turno.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · arreglar
- **Motivo**: (1) el tutorial saturaba: 8 insignias grandes de `rp_markers`, flecha, visor y tarjeta a la vez; (2) los clientes caminaban raro, con una animación en bucle; (3) la pizza solo se podía entregar en una caja registradora concreta, aunque el cliente esperaba en otro sitio.
- **Nota**: 100 → 100.
- **Causas**: (1) diseño: los marcadores de `rp_markers` están hechos para destacar sitios en la calle, no 8 estaciones juntas en una cocina. (2) La animación `WALK_civi` se reproducía en el sitio (`updatePosition = false`) mientras el script deslizaba al ped: cada ciclo avanzaba y volvía. (3) Diseño: estación de entrega fija.
- **Cambios**:
  - Estaciones con aro fino en el suelo y nombre solo de cerca (sin `rp_markers`); se encienden solo las útiles ahora según la mano y la cocina (horno libre con pizza cruda, horno en su punto, corte, armado con pedidos, caja con cliente, freidora con guarnición pendiente, mostrador con la caja).
  - Tutorial con un único objetivo: las demás estaciones casi invisibles; textos de una línea; pasos de interfaz con foco (pantalla oscura y solo la comanda o el panel Cocina iluminados con borde blanco parpadeante) y sin guía 3D a la vez. El paso de entrega señala al cliente.
  - Caminar real: el ped anda con su motor (`forward` + `walk`) y el script solo lo orienta (giro suave); si apenas avanza en 1,5 s recibe un empujón de medio metro, nunca un salto. El ancla queda solo para los sentados.
  - Entrega en todo el mostrador (`COUNTER`) con la caja en la mano; el servidor valida la zona y el cliente viene al punto del mostrador frente al jugador.
- **Reglas manuales revisadas**: SEG-02 ✔ (la zona de entrega la valida el servidor con margen), CLI-03 ✔ (aros con 24 segmentos por estación; el cálculo de lo útil va en un timer de 250 ms), CIC-06 ✔.
- **Pendiente**: —
- **Probar en juego**: tutorial completo (solo un objetivo encendido; foco en la comanda y en Cocina); clientes caminando con el paso normal de GTA por el pasillo, sin bucles ni saltos; entregar desde distintos puntos del mostrador; fuera del tutorial, que se encienda la estación útil según lo que llevas.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · arreglar
- **Motivo**: (1) los clientes llegaban al punto B y volvían de golpe al punto A; (2) sin guía, un jugador nuevo no entiende qué hace cada máquina ni dónde se entrega la pizza.
- **Nota**: 100 → 100.
- **Causa de (1)**: la animación de andar (`WALK_civi`) va con `updatePosition = false` (`client/c_customers.lua`) porque el desplazamiento lo hace el script; al cortarla al llegar, GTA devuelve al ped al punto donde empezó la animación.
- **Cambios**:
  - Ancla por cliente: al llegar se fija su punto (o la silla al sentarse) y cada frame se repone si el motor lo movió, sin cortar la animación que esté haciendo.
  - Marcadores fijos de `rp_markers` en las 8 estaciones con icono y nombre (Caja: pedidos, Entregas, Mesa de armado, Horno 1/2, Corte y empaque, Freidora, Despensa).
  - Tutorial guiado (`client/c_tutorial.lua`): automático en el primer turno (0 pizzas entregadas) o con «Turno con tutorial» en el panel. El servidor manda un solo cliente (Rosa, 4 pepperoni, normal, 4 trozos, 15 min de paciencia) y no manda más hasta entregarlo (`S.tutorial`). Una flecha 3D marca la estación del paso y una tarjeta del HUD lo explica; el paso sale del estado del servidor (fila, pedido, mano, horno), así que avanza solo. Al entregar: despensa, freidora y cierre, y empieza el turno normal a los 12 s.
  - Guía en pantalla del tutorial (a partir de la referencia de Fabián): lejos, visor de esquinas verdes sobre el destino con la distancia, o flecha en el borde si queda fuera de pantalla; a 2,4 m, el mueble real resaltado con un marco blanco ajustado a su forma (copia invisible del modelo del IPL para medir su caja; `obj` en cada estación).
- **Reglas manuales revisadas**: SEG-02 ✔ (el tutorial lo decide el servidor: el cliente solo elige «tutorial» y el servidor además lo fuerza en el primer turno), CIC-06 ✔ (marcadores y flecha se borran al terminar el turno y al parar el recurso), CLI-03 ✔ (el tour se recalcula cada 300 ms, no por frame).
- **Pendiente**: —
- **Probar en juego**: primer turno con un personaje sin pizzas: flecha en la caja → tomar pedido → armado → horno → sacar en verde → corte → Entregas; la tarjeta cambia sola en cada paso; al terminar enseña despensa y freidora y llegan clientes normales. Los clientes ya no vuelven al punto de partida al llegar a la caja, a la espera ni a la silla.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · arreglar
- **Motivo**: (1) la comanda aparecía en cuanto el cliente entraba por la puerta, sin nadie en la fila; (2) los clientes avanzaban a saltos (teletransporte) en vez de caminar; (3) `ERROR: Server triggered clientside event rp:pizzeria:shift, but event is not added clientside` al reiniciar con un turno abierto.
- **Nota**: 100 → 100.
- **Causas**:
  1. `html/app.js` (`renderTickets`) dibujaba como comanda a todo cliente existente, también al que venía entrando.
  2. `client/c_customers.lua` movía los peds con controles de GTA y, si un tramo pasaba de 7 s, los ponía en el punto. El tramo del pasillo (~10 m) tarda más de 7 s caminando, así que siempre saltaban; y si el ped de cliente no respondía a los controles, saltaba en todos.
  3. `server/s_pizzeria.lua` mandaba `rp:pizzeria:shift` al cliente dentro de `onResourceStop`, cuando el script de cliente ya estaba descargado.
- **Cambios**:
  - Las comandas solo existen al tomar el pedido en la caja; la fila se muestra como contador bajo el riel. El aviso de la caja dice "X viene llegando" hasta que llega.
  - Los clientes caminan con la animación real `WALK_civi` y desplazamiento propio a velocidad constante (`WALK_SPEED` = 1,25 m/s) siguiendo el camino, con giro suave (300°/s). Sin física, no se atascan y no hace falta teletransportar.
  - `ARRIVE_MS` (cuándo se puede tomar el pedido) se calcula con la longitud real del camino de la puerta a la caja (≈15 s) en vez de un número fijo que no coincidía con lo que se ve.
  - Al parar el recurso no se mandan eventos al cliente (CIC-06).
- **Reglas manuales revisadas**: CLI-03 ✔ (el movimiento recorre solo la lista de peds propios por frame, con `dt` acotado), CIC-06 ✔, SEG-02 sin cambios (la llegada la sigue decidiendo el servidor).
- **Pendiente**: si el ritmo de los pies no casa con el desplazamiento, ajustar `WALK_SPEED`.
- **Probar en juego**: empezar turno: el cliente entra caminando por la puerta, recorre el pasillo y se pone en la caja sin saltos; mientras camina no hay comanda y la caja dice "viene llegando"; al tomarle el pedido cae su comanda y él va caminando a la zona de espera; con dos clientes, el segundo avanza en la fila; `restart rp_pizzeria` con el turno abierto sin error rojo.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · arreglar
- **Motivo**: al empezar el turno salía "Entró un cliente" cada segundo, la comanda #1 reaparecía en bucle con su animación y solo había un NPC; en la caja no se podía tomar ningún pedido.
- **Nota**: 100 → 100.
- **Causa**: `server/s_pizzeria.lua` creaba el reloj del turno con `setTimer(tick, 1000, 0, S)`. MTA copia las tablas pasadas como argumento, así que cada segundo `tick` recibía una copia nueva del estado inicial (sin pedidos, `nextId = 0`, primer cliente ya vencido): generaba otra vez el pedido #1, sonaba la campana y mandaba ese estado falso al HUD. El estado real nunca recibía pedidos. Comprobado en el servidor aislado: un `setTimer` con tabla que suma 1 da `1,1,1` y el original queda en 0.
- **Cambios**:
  - El reloj pasa el estado con un cierre (`setTimer(function() tick(S) end, ...)`) (CIC-04 sin cambios).
  - HUD: solo cae con animación la comanda nueva (o la que pasa de la fila al riel); las demás no se re-animan en cada actualización.
  - Skill `arreglar-recurso`: la trampa de `setTimer` con tablas, en la lista de fallos típicos.
- **Reglas manuales revisadas**: CIC-06 ✔ (el timer sigue guardado en `S.timer` y se mata en `cleanup`), SEG-02/SEG-04 sin cambios.
- **Pendiente**: — (en `rp_restaurants` hay un `setTimer(clerkAnim, ..., loc, ...)` con tabla, pero solo lee `loc.ped`, así que la copia no le afecta).
- **Probar en juego**: empezar turno: llega un cliente, a los 30-46 s otro (máx. 2 en nivel 1), cada uno con su número (#1, #2...), un solo aviso "Entró un cliente" por cliente, comandas quietas en el riel; tomar el pedido en la caja y ver que la comanda cambia sin que las demás vuelvan a caer.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>

## 2026-11-25 · crear
- **Motivo**: trabajo de pizzero dinámico al estilo de los juegos de gestión de pizzería, en la Well Stacked Pizza de Idlewood.
- **Nota**: — → 100.
- **Cambios**:
  - Marcador con maletín en el comedor (interior 5, dimensión 25006 de `rp_restaurants`): contratar, ver progreso y empezar turno (panel CEF).
  - Turno instanciado en `26000+slot` dentro del mismo interior. Estaciones colocadas sobre el mobiliario real, leído del IPL binario `gen_int5_stream2.ipl` de `gta_int.img` (mostrador, cajas, hornos `CJ_FF_PIZZA_OVEN`, freidora, cocina, mesas y sillas). Los puntos que dio Fabián se usan para armado, freidora, despensa y corte.
  - Pedidos generados en el servidor según el nivel de `rp_jobs`: ingredientes, cantidades, mitades, punto de horneado, trozos y guarnición. Hornos y freidora se miden con el reloj del servidor; armado y cortes se evalúan en el servidor con tiempos mínimos, tope de piezas y stock.
  - Clientes NPC de cliente con máquina de estados (entrar, fila, esperar, recoger, sentarse a comer en las sillas reales, irse o irse enojado) y emoji de ánimo según la paciencia.
  - HUD CEF dibujado con dx (comandas en riel, hornos, freidora, mano, avisos de stock, tarjeta de resultado) y paneles CEF (armado, corte, freidora, despensa, contratación y salida).
  - `rp_jobs`: trabajo externo `pizza` (`external = "rp_pizzeria"`) y exports `startExternalShift`, `endExternalShift`, `payExternalJob`, `giveExternalJobXP`; no crea sede ni HUD para trabajos externos.
- **Reglas manuales revisadas**: SEG-01 ✔ (el auditor da N/A porque los `addEvent` se registran en un bucle; los 10 handlers remotos usan `client`), SEG-02 ✔ (el cliente solo manda ids, posiciones normalizadas, coberturas y ángulos; precio, nota y pago son del servidor; horno y freidora con su reloj), SEG-04 ✔ (`throttled` por jugador, tiempos mínimos de armado y corte, cooldown de reposición, tope de 40 piezas y de 12 cortes), BD-06 N/A (el dinero pasa por `rp_jobs:payExternalJob` con `MAX_TASK_PAY`), CIC-06 ✔ (fin de turno por salida, `/terminarturno`, muerte, abatido, cambio de personaje, desconexión o parada de `rp_pizzeria` o `rp_jobs`: se destruyen timer y objeto de la mano y se devuelve al jugador al comedor; los peds de cliente se borran al cerrar el turno). PRU-02: pendiente de probar en juego.
- **Verificación**: servidor aislado (22103/22105): `64 loaded, 0 failed`; `rp_jobs` lista 7 trabajos con `Pizzero`; pagos y XP externos devuelven 0/false sin turno; pedidos de nivel 1 a 5 coherentes; notas: armado perfecto 1.00 / malo 0.00, horno en punto 1.00 / crudo y quemado 0.00, cortes perfectos 0.99 / torcidos 0.00, final 99 con propina y 20 con «¡Está quemada!». Scripts de cliente compilan. CEF revisado en Chrome sin ventana (HUD y mesa de armado).
- **Pendiente**: ajustar en juego la altura y el giro de los clientes sentados (`SEAT_*`), los puntos de fila y espera, y la posición de la pizza y la caja en la mano.
- **Probar en juego**: contratar y empezar turno; un pedido completo con guarnición; dejar quemar una pizza; dejar que un cliente se vaya enojado; tirar una pizza; quedarse sin masa y reponer; varios clientes a la vez; salir por el comedor, con `/terminarturno` y desconectando a mitad; `restart rp_pizzeria` y `restart rp_jobs` con el turno abierto.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-25, commit 70df770)

**Nota: 100/100** · OK 30 · FALLA B 0 · FALLA I 0 · AVISO 0

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
| OK | I | CIC-01 | Estado por jugador se limpia en onPlayerQuit |  |
| OK | I | CIC-02 | Estado por personaje se limpia en rp:onCharacterLogout |  |
| OK | I | CIC-04 | Los timers se pueden cancelar |  |
| OK | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| OK | B | INT-01 | HUD y radio solo con setHudSuppressed/setRadioSuppressed |  |
| OK | I | INT-02 | Hora y clima solo desde rp_events |  |
| OK | I | INT-03 | Eventos propios con prefijo "rp:" |  |
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 0 outputChatBox |
| OK | B | INT-05 | Dimensiones propias sin choques | 26000 |
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
| N/A | I | PRU-01 | Pruebas en rp_test | no usa la BD |

</details>
