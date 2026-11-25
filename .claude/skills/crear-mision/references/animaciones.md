# Animación de personajes: cómo funciona y cómo se usa en una misión

Objetivo: que los personajes se muevan como personas reales (gestos, postura, miradas) y no como figuras quietas repitiendo un bucle.

## 1. Cómo lo hace el juego original (análisis de `gta-reversed` y de `anim/cuts.img`)

- Una cinemática de GTA SA es una **escena rodada con mocap completo**, no "un personaje con una animación". En `anim/cuts.img` (formato IMG `VER2`, sectores de 2048 B) cada una son tres archivos:
  - `.ifp`: el mocap de **toda la escena**. Una pista por actor y por prop (`cssweet`, `csryder`, `csplay` = CJ, `cssmoke`, silla, nevera, cigarro). Cada personaje es una animación de **61-63 huesos** (columna, pelvis, cuello, cabeza, brazos, **dedos**, piernas y **huesos de cara**: mandíbula, labios, mejillas, cejas, párpados, ojos), 400-900 fotogramas a 30 fps. Los actores caminan por la escena (movimiento de raíz).
  - `.cut` (texto): `info/offset` (dónde está la escena), `model` (actores y **props**), `text` (cada subtítulo con **inicio y duración en ms**), `attach` (objetos pegados a un hueso: el cigarro de Ryder), `remove` (oculta objetos reales del mapa), `peffect` (**partículas con tiempos**: humo del cigarro), `extracol` (**iluminación propia** de la escena), `uncompress`.
  - `.dat`: los **splines de cámara** (trayectoria y objetivo animados). Formato sin documentar; `CCamera::LoadPathSplines` no está reversado en `gta-reversed`. No es prioritario: la cámara se hace con `setCameraMatrix`.
- Preparación/cierre (`CCutsceneMgr`): se pone a 0 la densidad de peatones y tráfico, se guarda y restaura el armamento, se ocultan objetos reales, se silencia el habla ambiental y la radio; fade de 1 s antes del final y restauración total.
- **Banderas de animación** (`AnimAssocDescriptions.h`): `IS_PARTIAL` (se mezcla solo sobre parte del cuerpo), `IS_BLEND_AUTO_REMOVE`, `IS_FINISH_AUTO_REMOVE`, `IS_LOOPED`, `CAN_EXTRACT_VELOCITY` (mueve al personaje con el mocap), `IGNORE_ROOT_TRANSLATION`, `FACIAL`. Todo se mezcla con *blend deltas*: nunca hay cortes secos entre poses.
- **Los gestos de conversación NO son bucles.** `prtial_gngtlkA..H` están marcados `PARTIAL | BLEND_AUTO_REMOVE | FINISH_AUTO_REMOVE`: son gestos de **un solo disparo** que se mezclan sobre la postura base (idle o caminar). `CTaskComplexGangLeader` elige uno al azar cada pocos segundos mientras el personaje habla, y además hace que los miembros de la pandilla merodeen alrededor del líder y se miren.
- Conclusión de diseño: lo que da vida es **variedad, momento, mezcla y movimiento por el espacio**, no una animación mejor.

## 2. Lo que se usa en MTA (`rp_mocap`)

`rp_mocap` es una **biblioteca de clips de mocap real** recortados de `cuts.img` (gestos de ~3 s de un disparo + idles de ~3 s en bucle), por personaje, con la raíz normalizada. Catálogo generado: `rp_mocap/MOCAP_CATALOGO.md` (en juego `/mocap lista`). Personajes hoy: sweet, cj (= jugadores), ryder, smoke, cesar, tenpenny, bigbear, bdup, jose, hernandez, grove1.

**Uso automático en cinemáticas** (`scheduleTalk` en `rp_missions/server/s_stages.lua`): al empezar, cada actor (NPC y jugadores = `cj`) recibe un idle en bucle; cuando habla una línea el servidor elige gestos al azar (sin repetir el anterior) cada ~3,4-4,4 s y entre medias vuelve el idle; los demás giran la cabeza hacia quien habla (`setPedLookAt`); al terminar se suelta todo. Mapeo `who`→personaje: tabla `WHO_CHAR` (`sweet, ryder, cesar, smoke, me→cj`). Si `rp_mocap` no está activo o falta el personaje, cae a los gestos genéricos `GANGS/prtial_gngtlk*` (solo respaldo).

**API** (`rp_mocap`): servidor `hasCharacter`, `getClipCount`, `pickClip`, `play(jugadores, ped, personaje, tipo, indice, bucle)`, `stop`; cliente `playClip`, `stopClip`. Comandos admin (nivel 2): `/mocap lista`, `/mocap <personaje> gesture|idle [n]`, `/mocapped <personaje>` (ped de prueba que alterna idle y gestos), `/mocapparar`; cliente `/mocapc`, `/mocapcargar`, `/mocapdescargar`.

## 3. Pipeline para añadir personajes o clips

1. Elegir escenas del personaje en `cuts.img` (lista: `extract-cuts.ps1 -Listar`; 148 cinemáticas: `sweet1a..7a`, `ryder1a..3a`, `smoke1a..4a`, `grove1a..2`, `cesar1a`, `heist*`, `truth_*`, `zero_*`…).
2. `rp_animlab/tools/extract-cuts.ps1 -Img "<juego>\anim\cuts.img" -SoloP -Salida rp_animlab\anims -Escenas <lista>` (¡invocarlo con `&`, no con `-File`: el array llega como una sola cadena!). Convierte ANPK→**ANP3** de ped (solo los 26 huesos estándar, cuantización idéntica a la que aplica MTA: xyz negados ×4096, w ×4096, traslación ×1024, tiempo ×60) y detecta solo los actores humanos (pistas con ≥ 40 huesos).
3. `rp_mocap/tools/build-library.ps1 -Escenas rp_animlab\anims -Salida rp_mocap` mide ventanas de 3 s, clasifica **GESTO** (brazos activos, de pie, sin desplazarse, sin inclinar) e **IDLE** (casi quieto, cierra bien el bucle), elige por personaje con diversidad entre escenas y **normaliza la raíz**. Escribe `anims/mocap_<personaje>.ifp`, `shared/mocap_catalog.lua`, `MOCAP_CATALOGO.md`.
4. `rp_mocap/tools/check-library.ps1 -Anims rp_mocap\anims -Ped "<juego>\anim\ped.ifp"` → debe decir **0 en T-pose**.
5. Añadir los `<file>` nuevos a `rp_mocap/meta.xml`; `/mocapdescargar`; `restart rp_mocap` (los clientes descargan los IFP al iniciar el recurso).
6. Personaje de misión nuevo: mapear en `WHO_CHAR` (`s_stages.lua`) y en `SKINS` (`rp_mocap/server/s_mocap.lua`). Probar con `/mocapped <personaje>`.

Para probar un tramo concreto antes de meterlo en la biblioteca: recurso de laboratorio `rp_animlab` (no va en `mtaserver.conf`): `/animlab segmento <escena> <actor> <inicio_s> <dur_s> <total_s>`; `tools/segments.ps1` y `tools/catalogo_gestos.txt` listan candidatos.

## 4. Por qué la raíz se normaliza (y otros hallazgos que no hay que redescubrir)

- El mocap de cinemática trae la **traslación de raíz en coordenadas de la escena** (hasta ±27 m; en un ped normal parte de 0) y un **giro de escena** (a veces 180° contrario al de un ped, o inclinado si el actor está sentado). Sin corregirlo el actor sale despedido ("se desplaza y desaparece"). `build-library.ps1` pone x,y = 0, z relativa a la altura de idle (0,02), gira la raíz a la orientación base (yaw +90°) y descarta ventanas con inclinación > 12°.
- **T-pose**: en las cinemáticas un actor (sobre todo CJ) aparece en T-pose antes de empezar a moverse; esos tramos parecen "quietos" y se colaban como idles. Se descarta todo tramo con hombros y codos a < 25° de la identidad.
- Formato: `engineLoadIFP` acepta ANPK/ANP2/ANP3, pero el **ANPK crudo no registraba la animación** y se sospecha que provocaba cierres del cliente; el **ANP3 de ped** funciona. Mapeo de huesos cut→ped: `root→Normal(0)`, `Spine 1→Spine(2)`, `Spine 2→Spine1(3)`, `Neck(4)`, `Head(5)`, `Jaw(8)`, brazos 21-26 (derecho) y 31-36 (izquierdo), piernas 41-44 (izq.) y 51-54 (der.), `Belly(201)`, pechos 301/302. Se descartan huesos de cara y pulgares (no existen en el esqueleto de ped).
- **`setPedAnimation`** (cliente y servidor comparten orden): `(ped, bloque, anim, tiempo, bucle, moverPosición, interrumpible, congelarÚltimoCuadro, mezcla)`. El `false` silencioso suele ser un argumento mal (`/debugscript 3` lo muestra). Para gestos de un solo disparo: `bucle=false`, `congelar=false`, mezcla 250-300 ms. Nunca usar `setPedAnimationSpeed` (crashea el cliente).
- **Crash crítico**: parar/reiniciar un recurso con IFP cargado cierra el cliente de MTA (`client.dll+0xC2155`, determinista). `destroyElement(ifp)` tras soltar la animación **es seguro**. Por eso los IFP viven en `rp_mocap` y nunca se reinician sin `/mocapdescargar`.
- **Cabeza** (`rp_heads` + `bone_attach`): las cabezas son objetos pegados al hueso `Head`; el cuerpo y el movimiento de cabeza se ven, pero **no hay animación facial/labios**. Si una animación gira la cabeza 180° (corrección de `bone_attach`), poner el `elementData` `rp:noNeckFix = true` mientras dure (el motor ya lo hace en cinemáticas).
- Cada clip es en el sitio; mover a un actor por el espacio se hace aparte (`cutscene.actors` con `walk`), no con el clip.
- Límites: sin cara; Cesar (2g/2i) y Tenpenny (2g/6i) tienen pocos clips y repetirán; hay 148 escenas por explotar.
