# Estándar de cinemáticas (estilo GTA SA)

Objetivo: micro-cortometrajes de crimen de los 90, no "cabezas parlantes" que explican el objetivo. El motor de cinemáticas está en
`rp_missions/client/c_cinematic.lua` (cámara, subtítulos, radio, salida a gameplay) y `server/s_stages.lua` (puesta en escena, actores, gestos).
Ejemplo canónico: intro de `grove_turf` en `s_missions_data.lua`.

## Los 4 pilares y sus reglas

### 1. Lenguaje de cámara (cine de los 90: Singleton, Hughes, Tarantino)
- **Nunca un plano fijo y largo.** Mínimo 3 planos por cinemática; ninguno de diálogo pasa de ~5 s sin cambio de encuadre o movimiento.
- **Cámara en mano** por defecto (`shake = 1`); `0` solo para planos de trípode deliberados; `1.3-2` para tensión.
- **Ángulos con intención**: personaje intimidante o con autoridad (Tenpenny, Toreno, policías) → **contrapicado** y `roll` de 4-8° (ángulo holandés). Personaje débil o nervioso → picado leve.
- **Planos detalle (insert)**: 0,8-1,5 s sobre un objeto (arma, billetes, vaso, humo) entre dos planos de conversación: `from` pegado al objeto, `fov` 30-40.
- **Plano de reacción** tras una frase importante (`look = { me = true }`).
- Zoom lento `fov → fovTo` (empuje de 6-10°). `ease`: `smooth` (por defecto), `linear`, `in`, `out`.

### 2. Bloqueo de escena
- Nunca un actor quieto repitiendo una animación en bucle. Los gestos/idles/miradas son **automáticos** (mocap, ver `animaciones.md`). `cutscene.anim` / `npc.anim` en bucle solo para **acciones** (apoyarse, fumar, trabajar), nunca para "hablar".
- Cada personaje ocupa el espacio según su personalidad (Ryder nervioso y encorvado, Tenpenny invade el espacio del jugador con un `rel` menor, The Truth errático).
- Movimiento por el espacio: `cutscene.actors = { { t = ms, npc = "ryder", walk = { x, y, z, ms }, rot = grados, anim = {block, name, loop}, after = {...}, clear = true } }`.

### 3. Ritmo del diálogo
- Voz obligatoria (ver `voces.md`).
- Solapes e interrupciones: `overlap = ms` (la línea empieza antes de que acabe la anterior: peleas Sweet/Ryder), `gap = ms` (pausa dramática), `at = ms` (instante exacto). Los subtítulos solapados se apilan solos.
- Frases cortas; que se corten, duden o cambien de tema. Mínimo 3-4 líneas de intro: el objetivo es la excusa final tras desarrollar personajes.

### 4. Transiciones y sonido
- Sin pantallas de carga ni cortes bruscos: al terminar, la cámara **vuela ~0,9 s hasta quedar detrás del jugador** y entrega el control (`exit = "behind"`, por defecto). La última cinemática no hace ese vuelo (le sigue la pantalla de resultados).
- **Sin música de fondo.** La radio queda silenciada en misiones; dejar respirar el ambiente.
- HUD, chat, notificaciones y radio ocultos durante la cinemática (el motor llama a `rp_hud:setHudSuppressed` y `rp_radio:setRadioSuppressed`); bandas de cine (`letterbox = true`).

## Cámaras relativas al actor (regla que evita mirar la espalda)

Los planos de diálogo **no usan coordenadas fijas** (acaban mirando la espalda del actor si cambia la colocación): `from`/`to`/`look` aceptan
`{ npc = "sweet", fwd = 2.4, right = 0.7, dz = 0.25 }` o `{ me = true, ... }` (`fwd` hacia delante de la mirada del actor, `right` a su derecha, `dz` altura sobre su cabeza; sigue al actor aunque se mueva). Sin `fwd/right`: `{ npc = "sweet", dz = 0.1 }` apunta a la cabeza.
Plantilla `TalkShots(npc, planoGeneral)` (en `s_missions_data.lua`): general (coordenadas del mundo) → medio con empuje lento → reacción del jugador → contrapicado → sobre el hombro. Solo el plano general usa coordenadas del mundo.

## Puesta en escena (servidor)
- `place = { x, y, z, rot, spread }`: el grupo se coloca **lado a lado**, perpendicular a la mirada (nunca en fila). Las `npcs` con `rel = 2.6` se colocan delante del grupo mirándolo.
- Antes de empezar, **se baja a todos de los vehículos** y se espera 0,7 s, y los vehículos de misión cercanos al escenario se **apartan y congelan** (si no, los actores se colocan dentro del auto); se descongelan al terminar.
- Jugadores congelados durante la cinemática; `rp:noNeckFix` activo; ENTER omite (solo el líder).
- Duración total: `totalCutsceneTime` (shared/s_config.lua) con el horario real de los diálogos (voz incluida); el último plano se alarga para cubrirlo.

## Esquema de datos
```lua
cutscene = {
    letterbox = true, tail = 600, exit = "behind",
    place = { x, y, z, rot, spread = 1.4 },
    npcs  = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
    shots = TalkShots("sweet", { from = P(...), to = P(...), look = P(...), dur = 3200, fov = 62 }),
    lines = { { who = "sweet", text = "...", overlap = 450, gap = 500 }, ... },   -- índices NO se reordenan (nombran los audios)
    actors = { { t = 1200, npc = "sweet", walk = { x, y, z, ms } } },
    talk = false,   -- desactiva gestos/miradas automáticos (casi nunca)
}
```

## Lista de comprobación (antes de dar una cinemática por terminada)
- [ ] ≥ 3 planos, uno con movimiento claro y uno de reacción o detalle; cámaras relativas al actor.
- [ ] Contrapicado/`roll` si hay un personaje de autoridad; si no, justificar planos neutros.
- [ ] Cada NPC con mocap (`/mocap lista`) y ≥ 1 gesto durante sus líneas; sin bucles estáticos.
- [ ] ≥ 1 `overlap` o `gap` si hay ≥ 4 líneas.
- [ ] Voces generadas y `build_voice_index.ps1` ejecutado.
- [ ] Sin música; nadie dentro de un vehículo al empezar; sin corte brusco al devolver el control.
- [ ] Probada en juego y Fabián avisado para revisarla (cámara legible, nada atraviesa paredes, NPC visible en cada plano de diálogo).
