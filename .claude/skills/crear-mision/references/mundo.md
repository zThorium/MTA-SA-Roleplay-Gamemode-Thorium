# El mundo alrededor de la misión: instancias, vidas, radio, HUD, estrellas, enemigos, radar

Todo esto **ya lo resuelve el motor**; una misión nueva solo debe respetar las reglas de diseño.

## Instancias y estado (`s_core.lua`)
- Máquina de estados `LOBBY → LOADING → IN_PROGRESS → COMPLETED/FAILED → CLEANUP`. Cada instancia vive en su dimensión `MISSIONS.DIM_BASE (1000) + n`; ahí están los jugadores, vehículos, peds, props y blips del grupo.
- Sala (menú CEF con `/misiones`, o marcador del contacto): invitaciones (Y/N) o jugadores cercanos, roles con equipo propio, voto de dificultad (Fácil ×1.0 / Normal ×1.25 / Difícil ×1.5), sala abierta o privada. Aforo = `min(def.maxP, rango de respeto del líder)`.
- Al entrar se guarda una instantánea (posición, interior, dimensión, vida, armadura, armas) y se restaura al salir; la BD guarda la posición original cada 30 s para que el autoguardado de `rp_characters` (que corre con el jugador dentro de la misión) no deje a nadie en la dimensión de misión tras un cierre. Al abandonar/desconectar se restaura antes de que `rp_characters` guarde (`onPlayerQuit` con prioridad `high`).

## Vidas compartidas y espectador (compatible con `rp_injury`)
- `rp_injury` abate en vez de matar: el motor escucha `rp:onPlayerDowned`, gasta una vida compartida (Fácil 4, Normal 2, Difícil 0), espera 3,2 s y revive en `snap` con invulnerabilidad de 3,5 s. Sin vidas → espectador (cámara a un compañero, flechas ◄ ►). Todos fuera → misión fallida. Respaldo con `onPlayerWasted` si `rp_injury` no está activo.

## Radio y HUD
- Radio silenciada mientras dura la misión: `exports.rp_radio:setRadioSuppressed("rp_missions", true/false)` (corta emisoras de internet, cierra el panel, apaga la radio nativa; el servidor rechaza `rp:radio:set` dentro de misión). Se reaplica si `rp_radio` se reinicia.
- HUD, chat y notificaciones ocultos en cinemáticas y resultados: `exports.rp_hud:setHudSuppressed("rp_missions:cinematic", true/false)` (por motivos apilables). **No** tocar `rp:hudHidden` ni `setPlayerHudComponentVisible` a mano.

## Estrellas de búsqueda (`rp_wanted`)
- **No se puede entrar con estrellas ni arrestado** (se comprueba al abrir el menú, crear sala, unirse, invitar y al iniciar). Dentro: `exports.rp_wanted:setWantedSuspended(jugador, true)` pone las estrellas en 0 y bloquea delitos nuevos (incluidos los que reporta el cliente); se levanta al salir, así que nunca se sale con estrellas. Se reaplica si `rp_wanted` se reinicia.

## Enemigos
- **Escalado**: `total = (Base + (Jugadores-1) × Factor) × multiplicador de dificultad` (`count`/`per` del grupo; Fácil 0,85×, Normal 1×, Difícil 1,25×; tope `MAX_ENEMIES_ALIVE`). Salud ×1/1,25/1,6, armadura 0/25/60, puntería 0,40/0,60/0,85.
- **IA** en el cliente que sincroniza a cada ped (`isElementSyncer`): apunta al objetivo más cercano (jugadores y aliados), ráfagas con pausas, avanza si está lejos. Aliados (`ally = true`, p. ej. Sweet): no mueren, siguen al grupo, suben al vehículo y disparan (también desde el auto con `setPedDoingGangDriveby`), se teletransportan si quedan a > 70 m.
- **Aparición validada**: un punto al azar puede caer dentro de una casa o bajo un tejado (y no se les puede disparar). El servidor propone `4×count+4` candidatos alrededor del punto del grupo y el cliente más cercano los valida con rayos: **hay suelo a la altura esperada, sin techo encima (rayo vertical desde arriba) y línea de vista libre hasta el punto central**; el servidor solo acepta puntos cerca del grupo. Respaldo (sin respuesta en 2,5 s o sin válidos): junto al punto central. **Diseño**: el punto central `x,y,z` de cada grupo debe ser un **lugar abierto** (calle, patio), no un interior; mejor varios grupos pequeños que uno con radio grande en zona de casas.
- Los enemigos solo aparecen cuando alguien está a < 150 m (`SPAWN_RANGE`): el mundo no tiene colisión cargada más lejos y se caerían.
- Kills: `onPedWasted` acredita al jugador (o al conductor si mata con un vehículo). Headshot a enemigos: el cliente avisa (`rp:missions:headshot`), el servidor valida (instancia, arma de fuego, distancia) y mata.

## Radar (`rp_hud`)
- El minimapa propio solo dibuja blips conocidos dentro de su alcance (icono 0 = < 900 m y dentro del radar). Los blips de objetivo de misión llevan `elementData "rp:radarEdge" = true`: se dibujan **siempre**, clavados al borde cuando están lejos (el motor lo pone en los blips de `goto`, `interact`, `deliver` y vehículos).

## Vehículos de misión
- Se crean en la dimensión de la instancia, motor encendido, con blip adjunto visible solo para el grupo; `elementData "rp:mission"` los marca. `getin` exige a todos los vivos dentro; `deliver` falla la misión si el vehículo se destruye (`minHealth`). En cinemáticas se bajan los jugadores y se apartan los vehículos del escenario.

## Recompensas y persistencia (`s_finish.lua`)
- XP individual `= (500 + xpBonus + 15·bajas + 100·objetivos) × dificultad` (`rp_levels:giveXP`, suma atómica); dinero y respeto `× dificultad`; si falla solo `5·bajas × dificultad` de XP. Dinero: `UPDATE characters SET money = money + ?` atómico (anti-rollback) y `saveCharacter` tras restaurar. Respeto por contacto (`character_respect`, tope 1000 total) actualiza la estadística nativa 64 (`setPedStat`); rangos (`MISSIONS.RESPECT_RANKS`) suben el tamaño de grupo (2-4) y dan descuento (`getRespectDiscount`, listo para tiendas). Progreso y mejor tiempo en `mission_progress`.
- Victoria: pose de CJ y de los demás (`CASINO/manwinb|manwind`), cámara orbital 7 s, pantalla de resultados con contadores animados.
