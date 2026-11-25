# Estándar de cinemáticas (rp_missions)

Objetivo: que cada cinemática se sienta como un micro-cortometraje de crimen de los 90 (lenguaje de GTA SA) y no como "cabezas
parlantes" que explican el objetivo. El motor vive en `rp_missions/client/c_cinematic.lua`; los datos, en `shared/s_missions_data.lua`
(`stage.cutscene`). **Toda cinemática nueva debe cumplir esta lista.** Ejemplo de referencia: intro de la misión `grove_turf`.

## Los 4 pilares → reglas concretas

### 1. Lenguaje de cámara
- **Nunca un plano fijo y largo.** Mínimo 3 planos por cinemática; ningún plano de diálogo pasa de ~5 s sin cambio de encuadre o movimiento.
- **Cámara en mano**: activa por defecto (`shake = 1`). `shake = 0` solo para planos "de tripode" deliberados; `1.3-2` para tensión.
- **Ángulos con intención**: personaje intimidante/autoridad (Tenpenny, Toreno, polis) → contrapicado (`from` bajo, mirando hacia arriba) y `roll` de 4-8° (ángulo holandés). Personaje débil/nervioso → picado leve.
- **Planos detalle (insert shots)**: 0,8-1,5 s sobre un objeto (arma, billetes, vaso, humo) entre dos planos de conversación. Son un plano más: `from` pegado al objeto, `look` al objeto, `dur` corto, `fov` 30-40.
- **Plano de reacción**: tras una frase importante, corte al que escucha (`look = { me = true }`).
- Seguimiento: `look`/`from`/`to` aceptan `{ npc = "sweet", dz = 0.4 }` o `{ me = true }`, así la cámara sigue al actor aunque se mueva.
- Zoom lento: `fov` → `fovTo` (empuje sutil, 6-10°). `ease`: `smooth` (por defecto), `linear`, `in`, `out`.

### 2. Bloqueo de escena (blocking)
- **Nunca un actor quieto repitiendo una animación en bucle.** El programador de gestos (`cutscene.talk`, activo por defecto) lanza gestos de conversación de un solo disparo mientras habla cada personaje y hace que los demás lo miren (ver "Cómo lo hace el juego"). `cutscene.anim` / `npc.anim` en bucle solo para acciones concretas (apoyarse, fumar, trabajar), nunca para "hablar". Además, cambios con `cutscene.actors`:
  `{ t = ms, npc = "ryder", anim = {block, name, loop}, rot = grados, walk = { x, y, z, ms }, after = {block, name, loop} }`.
- Cada personaje ocupa el espacio según su personalidad: Ryder nervioso/encorvado y moviéndose, Tenpenny invade el espacio del jugador (`rel` menor), The Truth errático.
- Acciones de fondo cuando sea posible: caminar un poco (`walk`), fumar, apoyarse, recoger algo.

### 3. Ritmo del diálogo
- **Voz obligatoria** (ver "Estándar de voces" en `CLAUDE.md`).
- **Interrupciones y solapes**: `overlap = ms` hace que la línea empiece antes de que acabe la anterior (peleas Sweet/Ryder, dudas); `gap = ms` para pausas dramáticas; `at = ms` para fijar un instante exacto. Los subtítulos solapados se apilan solos.
- Frases cortas; que los personajes se corten, duden o cambien de tema. Nada de "ve al punto A y mata a B" en una sola frase: el objetivo es la excusa final tras desarrollar personajes (mínimo 3-4 líneas de intro).

### 4. Transiciones y sonido
- **Sin pantallas de carga ni cortes bruscos**: al terminar, la cámara vuela ~0,9 s hasta quedar detrás del jugador y entrega el control (`exit = "behind"`, por defecto). La cinemática final de misión no hace ese vuelo: va seguida de la pantalla de resultados.
- **Sin música de fondo.** La radio queda silenciada durante misiones (`rp_radio`); dejar respirar el ambiente (sirenas, motores, cigarras). Solo voces y, si hace falta, un efecto puntual.
- HUD, chat, notificaciones y radio ocultos durante la cinemática (`rp_hud:setHudSuppressed`); bandas de cine (`letterbox = true`).

## Esquema de datos

```lua
cutscene = {
    letterbox = true,
    tail = 600,                    -- ms extra al final (opcional)
    exit = "behind",               -- vuelo a la camara de gameplay (por defecto)
    place = { x, y, z, rot, spread = 1.4 },          -- donde se coloca al grupo
    npcs  = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 }, anim = {...} } },
    anim  = { "GANGS", "prtial_gngtlkA", true },     -- animacion del grupo (true = bucle; false = una vez y se queda)
    shots = { { from, to, look, lookTo, dur, fov, fovTo, roll, rollTo, shake, ease }, ... },
    lines = { { who, text, at, overlap, gap }, ... },-- los indices NO se reordenan (nombran el audio: <mision>_<etapa>c<n>.mp3)
    actors = { { t, npc, anim, rot, walk, after, clear }, ... },
}
```
La duración total la calcula `totalCutsceneTime` (shared/s_config.lua) con el horario real de los diálogos (voz incluida) y el último plano se alarga para cubrirlo. ENTER omite (solo el líder).

## Lista de comprobación antes de dar una cinemática por terminada
- [ ] ≥ 3 planos, al menos uno con movimiento claro y uno de reacción o detalle.
- [ ] Al menos un contrapicado/`roll` si hay un personaje de autoridad; si no, justificar planos neutros.
- [ ] Cada NPC con animación de conversación y ≥ 1 cambio en `actors`.
- [ ] Al menos un `overlap` o `gap` si hay ≥ 4 líneas.
- [ ] Voces generadas y `build_voice_index.ps1` ejecutado.
- [ ] Sin música; ninguna pantalla negra ni corte brusco al devolver el control.
- [ ] Probada en juego (cámara en mano legible, nada atraviesa paredes, NPC visible en cada plano de diálogo) y avisar a Fabián para revisarla.

## Siguiente fase: recurso editor (`rp_cinematics`, propuesta)
Idea (no construida): un recurso admin para **grabar** cinemáticas en juego y guardarlas como datos reutilizables por cualquier misión.
1. `/cinegrabar <nombre>`: modo freecam (reusar `rp_admin/c_freecam`); atajo para fijar un **plano** (posición/objetivo/fov/roll) y ver la previsualización interpolada.
2. Línea de tiempo en CEF: planos, líneas de diálogo (con audio), actores y animaciones; reproducir/pausar/ir a un instante.
3. Guardado en BD (`cinematics`, `cinematic_shots`...) o export a Lua pegable en `s_missions_data.lua`.
4. API: `exports.rp_cinematics:play(players, id, opts)` desde cualquier recurso (misiones, robos, trabajos), reusando este motor.
Orden recomendado: primero extraer el motor de `rp_missions` a un recurso `rp_cinematics` (mismo formato de datos), luego el editor.

## Cómo lo hace el juego original (análisis de `gta-reversed` + `anim/cuts.img` local)

Fuentes: `source/game_sa/CutsceneMgr.cpp`, `Animation/AnimAssocDescriptions.h`, `Tasks/TaskTypes/TaskComplexGangLeader.cpp` y el `cuts.img` del juego instalado (148 cinemáticas: `sweet1a`, `ryder1a`, `smoke1a`, `heist1a`...).

**1. Una cinemática no es un "personaje con animación": es una escena rodada con mocap completo.** `cuts.img` guarda por cada escena tres archivos:
- `.ifp`: el mocap de **toda la escena**. Cada actor y cada prop tiene su pista (`cssweet_x:root`, `csryder_x:root`, `CsChair:Root`...). Los actores no hablan en un sitio: se sientan, abren la nevera, caminan por la habitación (la animación tiene movimiento de raíz, `ANIMATION_CAN_EXTRACT_VELOCITY`).
- `.cut` (texto): `info/offset` (dónde está la escena en el mundo), `model` (lista de actores y **props**: silla, mesa, nevera, lámpara, cigarro), `text` (línea de subtítulo con **inicio y duración en ms** por clave GXT), `attach` (objetos pegados a un hueso: el cigarrillo de Ryder en su mano), `remove` (oculta objetos reales del mapa para sustituirlos por los de la escena), `peffect` (**efectos de partículas con tiempos**: `cigarette_smoke` sobre el cigarro), `extracol` (**preset de iluminación/color** propio de la escena) y `motion`.
- `.dat`: los **splines de cámara** (trayectoria y objetivo animados, con FOV) hechos a mano en 3ds Max. La cámara se activa con `TakeControlWithSpline(JUMPCUT)` + `SetWideScreenOn` (bandas de cine).

**2. Preparación y cierre** (`StartCutscene`, `SetupCutsceneToStart`, `FinishCutscene`): se pone a 0 la densidad de peatones y tráfico, se guarda/retira el armamento del jugador (se restaura al final), se ocultan los objetos reales, se desactiva el habla ambiental y se carga la pista de audio. El mundo "se vacía" para que nada estropee el plano. Al terminar, `Fade` de 1 s antes del final y restauración de todo (`restoreEverythingAfterCutscene`).

**3. Banderas de animación** (`AnimationFlags`): `IS_PARTIAL` (se mezcla sobre otra animación solo en parte del cuerpo), `IS_BLEND_AUTO_REMOVE` (se desvanece y se elimina sola), `IS_FINISH_AUTO_REMOVE`, `IS_LOOPED`, `CAN_EXTRACT_VELOCITY` (mueve al personaje con el mocap), `IGNORE_ROOT_TRANSLATION`, `FACIAL`. Todo se mezcla con *blend deltas*: jamás hay cortes secos entre poses.

**4. Los gestos de conversación no son bucles.** `prtial_gngtlkA..H` están marcadas `IS_PARTIAL | BLEND_AUTO_REMOVE | FINISH_AUTO_REMOVE`: son **gestos de un solo disparo que se mezclan sobre la postura base** (idle o caminar). `CTaskComplexGangLeader` elige uno al azar cada pocos segundos, además de hacer que los miembros de la pandilla **merodeen alrededor del líder**, se miren y lancen "abuse speech". Lo que da vida no es una animación mejor: es **variedad, momento, mezcla y movimiento por el espacio**.

**5. Qué nos queda como estándar (lo que podemos replicar en MTA hoy)**
- Gestos de un solo disparo con `blendTime`, elegidos al azar (no repetir el anterior), ligados a la línea de voz (`scheduleTalk`).
- Mirada: los oyentes giran la cabeza hacia quien habla (`setPedLookAt`).
- Props en escena (cigarro, vaso, mesa) pegados a huesos y efectos con tiempo (`createEffect`), y hora/clima fijos por escena (`weather`, `hour` de la misión).
- Actores que **se mueven por el espacio** (`actors.walk`), no solo estar de pie.
- Mundo despejado: quitar tráfico/peatones cercanos durante la cinemática.
- Cámara con trayectorias suaves (nuestros planos from→to con easing) y subtítulos con inicio/duración reales.

**6. Mocap real del juego en MTA (en curso; la cámara no es prioritaria: se hace con `setCameraMatrix`).**
Hallazgos medidos en `sweet1b.ifp` (formato ANPK): cada actor (`cssweet`, `csryder`, `csplay` = CJ, `cssmoke`) es una animación de **61-63 pistas** (columna, pelvis, cuello, cabeza, brazos, **dedos**, piernas y **huesos de cara**: mandíbula, labios, mejillas, cejas, párpados, ojos) con 400-900 fotogramas a 30 fps. Los props (silla, nevera, mesa, cigarro) son animaciones propias de 2-4 huesos. Los nombres de hueso son los del esqueleto de peds salvo tres (`root`→`Normal`, `Spine 1`→`Spine`, `Spine 2`→`Spine1`) y algunos con espacio inicial; `ped.ifp` confirma los IDs (`Normal`=0, `Pelvis`=1, `Spine`=2, `Spine1`=3, `Neck`=4, `Head`=5, `Jaw`=8, brazos 21-26/31-36, piernas 41-44/51-54).
- Según la wiki de MTA, `engineLoadIFP` acepta ANPK, ANP2 y ANP3, así que no hace falta convertir formato; solo alinear nombres de hueso.
- **Formato recomendado: ANP3.** `extract-cuts.ps1` genera además `<escena>_p.ifp` (ANP3 estándar, solo los 26 huesos del esqueleto de peds presentes en cada actor, cuantización idéntica a la de MTA: xyz negados x4096, w x4096, traslación x1024, tiempo x60). Recorrido validado: cuaternios unitarios, raíz <8 m, 60 s por actor. El ANPK crudo hace que MTA cree ranuras extra de huesos (cara, dedos) y se sospecha que provocó un cierre del cliente al descargar el recurso.
- **Herramientas (hechas):** `rp_animlab/tools/extract-cuts.ps1` lee `cuts.img` (formato IMG `VER2`), extrae el `.ifp` y el `.cut` de una escena y escribe dos copias: `<escena>.ifp` con los huesos renombrados al esqueleto de peds y `<escena>_orig.ifp`. El recurso `rp_animlab` (`/animlab cargar|tocar|ped|objetivo|parar`, admin nivel 2) las carga y las reproduce en tu personaje o en un ped de prueba. Los `.ifp` no se suben al repo (material de Rockstar).
- **Límites conocidos:** (a) las cabezas de `rp_heads` son objetos pegados al hueso `Head`: el cuerpo, brazos, dedos y el movimiento de cabeza sí se verán, pero no la animación facial/labios; (b) la pista del root trae movimiento relativo a la escena: probar con `mover 0` y colocar al actor por script; (c) cada clip dura toda la escena (~24 s) y es el de la voz original en inglés: lo útil es **trocear** (arrancar en un instante con `setPedAnimationProgress` y cortar por temporizador) y formar una **biblioteca de gestos** de Sweet/Ryder/CJ; (d) `setPedAnimationSpeed` crasheó el cliente (ver memoria del gimnasio): no usarlo.
- **Plan:** 1) probar en juego `/animlab tocar sweet1b cssweet 1 0` con el IFP renombrado y con el `_orig` para saber si MTA aplica los huesos; 2) si no se ven: convertir a ANP3 con los IDs de hueso de arriba (o editar con Blender + DragonFF, que importa/exporta IFP); 3) catalogar segmentos de ~2-4 s con gesto de habla/idle/reacción por personaje; 4) que `scheduleTalk` los reproduzca (el servidor manda el bloque, el segmento y el actor; cada cliente carga el IFP y lo aplica a los peds locales porque las animaciones personalizadas no se sincronizan solas).
- **Cámara (`.dat`)**: sin documentación pública del formato; no es prioritario.

### Estado del mocap en MTA (2026-11-24)
- **Funciona**: el ANP3 convertido (`<escena>_p.ifp`) se reproduce con `setPedAnimation` sobre el jugador y sobre peds (confirmado en juego con `/animlab tocar sweet1b cssweet`). El ANPK crudo no registraba la animación.
- **Crash crítico conocido**: al **detener o reiniciar** un recurso con un IFP cargado el cliente se cierra (`client.dll+0xC2155`, AccessViolation, reproducible). La wiki de MTA dice que el IFP se descarga solo al parar el recurso; hay un PR de MTA con problemas de animaciones de cinemática (#4664). Hasta aislarlo: usar `/animlab descargar` antes de reiniciar `rp_animlab`.
- **Regla de diseño para producción**: los IFP deben vivir en un recurso propio de **solo-IFP que nunca se reinicia** en desarrollo (carga todo una vez al conectar y expone `playMocap(ped, bloque, anim, ...)`); `rp_missions` solo pide reproducir. Así reiniciar misiones no descarga IFP. No cargar/descargar IFP por misión.
- **Biblioteca de gestos**: `rp_animlab/tools/segments.ps1` mide por ventanas el movimiento de brazos/piernas/columna/raíz y propone tramos de gesto de pie. `/animlab segmento <escena> <actor> <inicio_s> <dur_s>` los prueba. Candidatos en `sweet1b` (ventana 3 s): cssmoke 1, 4, 17, 20, 41 s; csryder 13, 50 s; cssweet 35 s (Sweet casi siempre camina por la cocina; hay que usar otras escenas `sweet1a/1c/2a...` y ventanas de 2 s).
- **`/animlab descargar` no crashea** (confirmado): `destroyElement(ifp)` tras soltar la animación es seguro; solo falla la descarga automática al parar el recurso. Procedimiento: `/animlab descargar` y luego reiniciar.
- **Biblioteca extraída (26 escenas, 13,7 MB, solo ANP3)**: `sweet1a/1b/1c/2a/2b/3a/3b/4a/5a/6a/6b/7a`, `grove1a/1b/1c/2`, `ryder1a/2a/3a`, `smoke1a/1b/2a/2b/3a/4a`, `cesar1a` (actores humanos autodetectados: cssweet, csryder, csplay=CJ, cssmoke, cskendl, cscesar, cstenpenny, cspulaski, csbigbearthin...). `tools/catalogo_gestos.txt` lista por actor y escena la duración y los mejores tramos de gesto. **Sweet** tiene gestos de pie claros en `sweet2b` (44, 59, 76, 80 s; clip de 83,2 s) y `sweet3a` (3, 10, 30, 36 s; clip de 50,5 s). Probar: `/animlab segmento sweet2b cssweet 44 3 83.2`.

## Biblioteca de mocap `rp_mocap` (estándar de animación de personajes)

Las cinemáticas usan **mocap real del juego** (recortado de `cuts.img`) en vez de bucles genéricos. Está listo y se usa solo: `scheduleTalk` (rp_missions) lo elige si `rp_mocap` está activo y tiene al personaje; si no, cae a los gestos `GANGS/prtial_gngtlk*`.

- **Qué hay**: `rp_mocap/MOCAP_CATALOGO.md` (generado) lista cada personaje con sus clips: **gestos** (~3 s, un disparo, brazos activos, de pie, sin desplazarse) e **idles** (~3 s, se reproducen en bucle). Hoy: sweet 11g/6i, cj 14/6, ryder 5/6, smoke 5/6, cesar 2/2, tenpenny 2/6, bigbear 4/4, bdup 3/4, jose 3/2, hernandez 2/2, grove1 2/4. Los clips traen la raíz **normalizada** (en el sitio, orientación base de ped), por eso no desplazan ni giran al personaje.
- **Cómo funciona en una cinemática** (automático): al empezar, cada actor (NPC y jugadores = `cj`) recibe un idle de mocap en bucle; cuando habla una línea, el servidor elige gestos al azar (sin repetir el anterior) cada ~3,4-4,4 s y entre medias vuelve el idle; los demás miran a quien habla; al terminar se suelta todo. Mapeo línea→personaje: `sweet→sweet`, `ryder→ryder`, `cesar→cesar`, `smoke→smoke`, `me→cj` (tabla `WHO_CHAR` en `s_stages.lua`). Las animaciones personalizadas no se sincronizan solas: el servidor avisa a cada cliente (`rp:mocap:play`) y cada uno las aplica localmente.
- **Probarlas**: `/mocap lista`, `/mocap sweet gesture 3`, `/mocap sweet idle`, `/mocapped sweet` (ped de prueba que alterna idle y gestos), `/mocapparar` (admin nivel 2).
- **Añadir personajes o clips**: 1) `rp_animlab/tools/extract-cuts.ps1 -SoloP -Escenas <escenas>` extrae escenas del personaje (ANP3) a `rp_animlab/anims`; 2) `rp_mocap/tools/build-library.ps1 -Escenas <rp_animlab/anims> -Salida <rp_mocap>` regenera `anims/mocap_<personaje>.ifp`, `shared/mocap_catalog.lua` y `MOCAP_CATALOGO.md`; 3) añadir los `<file>` nuevos a `meta.xml`, `/mocapdescargar` y reiniciar `rp_mocap`; 4) si es un personaje de misión nuevo, mapearlo en `WHO_CHAR` y en `SKINS` (`s_mocap.lua`).
- **Regla crítica**: `rp_mocap` **no se reinicia en desarrollo** sin `/mocapdescargar` antes (descargar un IFP al parar el recurso cierra el cliente de MTA). Reiniciar `rp_missions` es seguro: los IFP viven en `rp_mocap`. Orden en `mtaserver.conf`: `rp_mocap` antes de `rp_missions`.
- **Por qué la raíz se normaliza**: el mocap de cinemática trae la traslación en coordenadas de la escena (hasta ±27 m) y un giro de escena (a veces 180° contrario al de un ped, o inclinado si el actor está sentado); sin corregirlo el actor sale despedido. `build-library.ps1` pone x,y = 0, z relativa a la altura de idle (0,02) y gira la raíz a la orientación base (+90° de yaw), y descarta ventanas con inclinación > 12°.
- **Límites**: sin animación facial (las cabezas son objetos de `rp_heads`); solo hay gestos de pie y personajes con pocas escenas tienen pocos clips; los clips de Cesar (2g/2i) y los de Smoke/Ryder son pocos: repetirán. Ampliar con más escenas (hay 148 en `cuts.img`).

### Cámaras relativas al actor (regla)
Los planos de diálogo **no usan coordenadas fijas** (se ven mal si cambia la colocación y acaban mirando la espalda del actor): `from`/`to`/`look` aceptan `{ npc = "sweet", fwd = 2.4, right = 0.7, dz = 0.25 }` o `{ me = true, ... }`, donde `fwd` es hacia delante de la mirada del actor, `right` a su derecha y `dz` la altura sobre su cabeza. La plantilla `TalkShots(npc, planoGeneral)` de `s_missions_data.lua` da los 5 planos estándar (general ? medio con empuje ? reacción del jugador ? contrapicado ? sobre el hombro). Solo el plano general usa coordenadas del mundo. Los jugadores se colocan **lado a lado** (perpendicular a la mirada), nunca en fila.

- **Recarga de IFP sin reiniciar:** tras `/mocapdescargar` se puede volver a cargar con `/mocapcargar`; además `rp_mocap` recarga solo la biblioteca de un personaje la primera vez que se pide un clip. Así nunca hace falta reiniciar el recurso (que es lo que cierra el cliente).

- **T-pose**: el mocap de cinemática deja a veces a un actor (sobre todo CJ) en T-pose antes de empezar a moverse; esos tramos parecen "quietos" y se colaban como idles. `build-library.ps1` descarta todo tramo cuyos hombros y codos estén a menos de 25° de la rotación identidad, y `tools/check-library.ps1 -Anims <rp_mocap\anims> -Ped <ped.ifp>` lista los clips en T-pose (debe dar 0). Pasar siempre ese comprobador tras regenerar la biblioteca.
