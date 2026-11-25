---
name: crear-mision
description: Crear, modificar o revisar una misión cooperativa de rp_missions (Thorium, MTA:SA) con el estándar completo del proyecto - etapas y enemigos, cinemáticas al estilo GTA SA, mocap real de personajes, voces clonadas con IA (Fish Audio), radio/HUD/estrellas y verificación. Úsala SIEMPRE que haya que añadir o tocar una misión, una cinemática, una voz o una animación de personaje; contiene todo el conocimiento acumulado.
---

# Crear una misión (rp_missions)

Una misión es **un bloque de datos** en `resources/[roleplay]/rp_missions/shared/s_missions_data.lua` (`MISSION_DEFS`). El motor
(`server/s_core.lua` lobby/instancias/vidas, `s_stages.lua` etapas/enemigos/cinemáticas, `s_finish.lua` recompensas; cliente
`c_core.lua`, `c_cinematic.lua`, `c_hud.lua`) no se toca para una misión normal. Ejemplo canónico: `grove_turf` (Sweet).

Esta skill es **autocontenida**: el `CLAUDE.md` del repo no está versionado, así que todos los estándares viven aquí.
Lee el archivo de `references/` de cada área que toques. Responde y documenta **en español**.

## Estándares obligatorios (resumen; el detalle está en references/)

1. **Voces con IA**: toda línea de un personaje (no `me`) lleva audio clonado con Fish Audio (skill `voces-gta`); nunca solo subtítulos ni TTS de Windows como resultado final. → `references/voces.md`
2. **Cinemáticas estilo GTA SA**: cámara en mano, ≥ 3 planos, planos **relativos al actor**, contrapicado/roll para autoridad, plano de reacción, solapes de diálogo, sin música, salida fluida al gameplay. → `references/cinematicas.md`
3. **Animación de personajes con mocap real** (`rp_mocap`): gestos e idles recortados de las cinemáticas del juego; nunca un bucle estático sobre un personaje congelado. → `references/animaciones.md`
4. **Mundo**: radio silenciada y HUD oculto en cinemáticas; no se entra con estrellas ni se acumulan dentro; blips de objetivo siempre visibles en el radar; enemigos con aparición validada por rayos. → `references/mundo.md`
5. **Verificación**: servidor de prueba sin errores y aviso explícito de que el **cliente hay que probarlo en juego**; una misión no está terminada sin voces. → `references/verificacion.md`

## Flujo (en este orden)

1. **Diseño**: contacto (`MISSIONS.CONTACTS`), nivel/respeto mínimos, jugadores (min/max/recomendado), roles con equipo, recompensas, hora/clima, `spawns`/`snap`/`victory`. Formato completo: `references/formato-mision.md`; plantilla: `templates/mision-plantilla.lua`.
2. **Etapas**: lista ordenada de componentes (`goto`, `getin`, `enemies`/`waves`, `interact`, `deliver`, `wait`, `cutscene`, `radio`, `npcs`, `boardNpc`). Siempre `text` (objetivo en HUD) y `snap` donde convenga reaparecer. Coordenadas inventadas = **aproximadas**: anotarlo y ajustarlas en juego con `/mmover` y `/mskip`.
3. **Cinemática de intro y de cierre** con `TalkShots(npc, planoGeneral)` + `lines` + `place` + `npcs`. Los gestos, idles y miradas son **automáticos** (`scheduleTalk` + `rp_mocap`).
4. **Personajes**: comprobar con `/mocap lista` que cada `who` tiene mocap y voz; si falta, ampliar la biblioteca (`references/animaciones.md`) y registrar la voz (`references/voces.md`).
5. **Voces**: generar todas las líneas (temperatura 0.3, idioma es, con tildes), ejecutar `rp_missions/tools/build_voice_index.ps1` y revisar tamaños (~1 KB por carácter).
6. **Registro y docs**: comandos o exports nuevos → `RECURSOS.md` y `rp_adminpanel/server/s_catalog.lua`; tablas → skill `migracion-bd`; memoria del proyecto `rp-missions.md`.
7. **Verificar** (`references/verificacion.md`) y entregar con la lista de qué probar en juego.

## Reglas críticas (cuestan horas si se olvidan)

- **No reiniciar `rp_mocap` ni `rp_animlab` sin `/mocapdescargar` / `/animlab descargar` antes**: descargar un IFP al parar el recurso cierra el cliente de MTA. Tras `/mocapdescargar` basta `/mocapcargar` (y se recarga sola al reproducir). `rp_mocap` va antes que `rp_missions` en `mtaserver.conf`.
- Los índices de `cutscene.lines` y `radio` **no se reordenan**: nombran los audios `<clave>_<etapa><c|r><n>.mp3`.
- Las animaciones personalizadas **no se sincronizan solas**: el servidor avisa a cada cliente (`rp:mocap:play`).
- Probar siempre con `/debugscript 3`: con el nivel 0 los errores y avisos de Lua no aparecen en ninguna parte.
- Los `.ifp` (mocap) y `muestras/` (audio del juego) son material de Rockstar: **nunca** al repo. La API key de Fish vive en `~/.fish-audio-key` o `FISH_API_KEY`, nunca en el repo.
- **Nunca normalizar codificación en masa** sobre carpetas de recursos (corrompe wav/mp3/ifp). Para añadir texto a archivos usar heredoc de bash o `[IO.File]::AppendAllText(..., UTF8Encoding($false))`, nunca `Add-Content`.
- Más trampas de MTA y del proyecto: `references/trampas.md`.

## Qué NO hacer
No usar TTS de Windows como voz final; no repetir un gesto en bucle sobre un personaje congelado; no mezclar música en cinemáticas; no colocar cámaras con coordenadas fijas en planos de diálogo; no dejar una misión con coordenadas sin marcar como aproximadas; no dar por buena una cinemática sin avisar a Fabián de que la pruebe en juego.
