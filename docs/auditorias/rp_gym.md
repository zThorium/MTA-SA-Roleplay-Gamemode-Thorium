# Auditoría de rp_gym

## 2026-11-26 · arreglar (congelar al elegir peso)
- **Motivo**: al elegir el peso del press o las mancuernas el personaje podía moverse.
- **Cambios**: `gymSelect(sel)` en `client/c_main.lua`: mientras se elige el peso el personaje queda congelado y sin controles; se descongela al empezar (Enter), cancelar (Retroceso), alejarse, cambiar de personaje o parar el recurso, y solo si lo congeló el gimnasio.
- **Probar en juego**: E en el press o las mancuernas, intentar moverse y pegar mientras se elige; Enter y Retroceso devuelven el control.

## 2026-11-26 · arreglar + mejorar (congelamiento en el combate e interfaz)
- **Motivo**: al recibir golpes del entrenador el jugador quedaba congelado (sin poder pegar ni cubrirse); al terminar quedaba atrapado en el ring; pedido de rehacer la interfaz de todo el recurso y de logs para seguir el fallo.
- **Causa**: cada golpe sin cubrirse quitaba los controles 1-2 s y el entrenador pega cada 0,65-1,1 s: el aturdimiento se encadenaba sin fin y, sin controles, tampoco se podía cubrir.
- **Cambios**: inmunidad de `GYM_FIGHT.STUN_IMMUNE_MS` tras cada aturdimiento; el entrenador se aparta `TRAINER_RECOVER_MS` tras conectar; vigilante que reactiva los controles si quedan desactivados sin aturdimiento; logs `[rp_gym:pelea]` (cliente y servidor, `GYM_FIGHT.DEBUG`). Al ganar o perder aparece junto al entrenador, fuera del ring. Interfaz nueva con `client/c_ui.lua` (paleta del HUD, fuentes de `rp_notify`, teclas dibujadas): avisos "Pulsa E", tarjeta de máquina, selector de peso, aviso de estadística, `/stats`, presentación, fichas de vida, "¡Levántate!" y tarjeta de resultado (UX-01, UX-06).
- **Probar en juego**: recibir varios golpes seguidos sin cubrirse y comprobar que se recupera el control; ganar y perder (aparece junto al entrenador); revisar `/debugscript 3` con el prefijo `[rp_gym:pelea]`; todas las pantallas del gimnasio.

## 2026-11-26 · arreglar (esquinas y paredes del ring)
- **Motivo**: Fabián midió en juego las esquinas del ring; pidió paredes invisibles para no salir del ring por error.
- **Causa**: el centro del ring se calculó con el giro del IPL invertido (salía a 0,9 m en X e Y del real).
- **Cambios**: esquinas medidas en juego; centro (760.91, 0.24); público, árbitro y salida recolocados con el centro corregido. Paredes invisibles en `client/c_fight.lua`: durante el combate el jugador y el entrenador no pasan de `ring.half` (2,45 m) del centro.
- **Probar en juego**: que nadie pueda salir del ring empujando contra las cuerdas ni al caer; que el público no quede dentro de una pared; `/debugscript 3` limpio.

## 2026-11-26 · mejorar (combate en el ring)
- **Motivo**: pedido de Fabián: público y fotógrafos alrededor del ring, sangre, aturdimiento con mareo, caídas con cuenta del árbitro y Espacio para levantarse, perder sin quedar abatido, cinemática de presentación y sonidos de Kenney (narrador e impactos).
- **Cambios**: `server/s_trainers.lua` (público, árbitro y fotógrafos como peds del servidor; fase de presentación `GYM_FIGHT.INTRO_MS`; eventos `rp:gym:down` y `rp:gym:lost`; derrota fuera del ring; element data `rp:gymFight`). `client/c_fight.lua` reescrito (cinemática, IA, golpes, efectos, cuenta y HUD del combate). `rp_injury/client/c_injury.lua`: no deja abatido durante un combate de `rp_gym`. Packs Kenney Impact Sounds y Voiceover Fighter añadidos a `assets/` (CC0); sonidos de público, obturador y textura de sangre sintetizados (`tools/gen_assets.py`). Teclas dibujadas (UX-01): Espacio animado, clic derecho + Shift para cubrirse.
- **Reglas manuales revisadas**: SEG-02 ✔ (el cliente solo puede perder o cambiar su animación; vidas, ring y victoria los decide el servidor); UX-01 ✔ en el combate; UX-06 ✔; UX-10 ✔ (`CREDITOS.md`).
- **Pendiente**: PRU-01/PRU-02 (sin `scripts/test.sh`); sin comprobación automática de sintaxis Lua; posiciones del público, árbitro y salida estimadas ([A]); banco de quejidos `PAIN_A` 1 elegido por la frecuencia de CJ, sin escuchar.
- **Probar en juego**: combate completo (presentación, cuenta, campana), golpes con sangre y gritos del público, flashes, aturdimiento y visión borrosa sin cubrirse, caída y Espacio, perder por cuenta o por vida (aparece fuera del ring, sin abatido), ganar (K.O.), que no salgan estrellas; `/debugscript 3` limpio.

## 2026-11-26 · arreglar
- **Motivo**: error `attempt to call global 'setPedControlState' (a nil value)` en `s_trainers.lua` (líneas 73 y 129) al pelear con el entrenador; pegarle daba estrellas; pedido de Fabián: ring con esquinas, campanas y K.O.; quitar las máquinas fijas.
- **Causa**: `setPedControlState` solo existe en el cliente de MTA; la IA del entrenador corría en el servidor.
- **Nota**: 92 → 96.
- **Cambios**: IA del entrenador en `client/c_fight.lua` con el jugador como sincronizador del ped (`setElementSyncer`). `rp_wanted:setWantedSuspended` durante el combate (solo si no estaba ya suspendido) y no se pelea con estrellas. Ring de Ganton (`in_bxing05`, medido en `gen_int3_1.col`): esquinas opuestas, rendirse = salir a más de 3,8 m del centro. Campanas sintetizadas (`tools/gen_bells.py`) y "K.O." con el entrenador tendido 3,5 s. Fuera las máquinas fijas; las del interior original se quitan con `removeWorldModel` (se restauran al parar).
- **Reglas manuales revisadas**: SEG-02 ✔ (el cliente solo mueve el ped; vidas, ring y resultado los decide el servidor); UX-06 ✔; UX-10 ✔ (sonidos propios con `CREDITOS.md`).
- **Pendiente**: PRU-01/PRU-02 (sin `scripts/test.sh`); CLI-01 (aviso previo).
- **Probar en juego**: pelear con 35 % de músculo y sin estrellas: los dos aparecen en esquinas, campana, el entrenador pega, al ganar K.O. y campana; pegarle no da estrellas; salir del ring = rendirse; el interior sin cinta, banco ni bici; `/debugscript 3` limpio.

## 2026-11-26 · mejorar
- **Motivo**: pedido de Fabián: gimnasio de Ganton con marcador en la puerta, interior y máquinas originales, aviso al subir una estadística, `/stats` y estilos de pelea ganándole al entrenador.
- **Nota**: 92 (sin registro previo).
- **Cambios**: `GYM_FIXED` y `server/s_fixed.lua` (puerta con `rp_markers` y blip 54, E para entrar y salir, máquinas en las posiciones de `gen_int3_stream0.ipl` usando los objetos del interior, entrenador de boxeo fijo); las fijas no se borran con `/borrarmaquina` ni `/borrarentrenador`. Aviso `rp:gym:statChange` al cruzar cada 1 % y panel `/stats` (`client/c_stats.lua`) con sonidos Kenney (UX-06, UX-10, `CREDITOS.md`). `/stats` en `rp_help` (DOC-03).
- **Reglas manuales revisadas**: SEG-02 ✔ (la puerta revalida personaje, interior, dimensión, distancia, cooldown y estado); BD-06 ✔ (sin tablas nuevas); UX-10 ✔.
- **Pendiente**: PRU-01/PRU-02 (no se pudo correr `scripts/test.sh`: falta `.env`); posición del entrenador es estimada ([A]); UX-01 (los avisos siguen con "[E]" en texto, no tecla dibujada).
- **Probar en juego**: entrar y salir por la puerta; subir a cinta, banco, mancuernas y bici y ver que el personaje cuadra con la máquina original; ganar 1 % y ver el aviso; `/stats`; pelear con el entrenador con 35 % de músculo; `/debugscript 3` limpio.

<details><summary>Informe automático</summary>

### Auditoría automática (2026-11-26, commit c8ae973)

**Nota: 94/100** · OK 28 · FALLA B 0 · FALLA I 0 · AVISO 3

| Estado | Grav. | Regla | Qué | Evidencia |
|---|---|---|---|---|
| AVISO | I | CLI-01 | Las teclas ignoran chat/consola/cursor | resources/[roleplay]/rp_gym/client/c_machines.lua |
| AVISO | R | DOC-04 | Registro de auditoría en docs/auditorias/ | falta docs/auditorias/rp_gym.md |
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
| OK | R | INT-04 | Avisos con rp_notify (no outputChatBox) | 8 outputChatBox |
| OK | R | INT-06 | Teclas sin choques con otros recursos |  |
| OK | R | CLI-02 | onClientRender sin trabajo pesado por frame |  |
| OK | I | CLI-04 | El cliente no copia config compartida al cargar |  |
| OK | B | DOC-01 | Fila en RECURSOS.md |  |
| OK | I | DOC-02 | Exports documentados en RECURSOS.md |  |
| OK | I | DOC-03 | Comandos en RECURSOS.md, panel de admin o ayuda |  |
| N/A | I | CIC-05 | El cliente devuelve cámara/controles/HUD al parar |  |
| N/A | B | INT-05 | Dimensiones propias sin choques |  |

</details>
