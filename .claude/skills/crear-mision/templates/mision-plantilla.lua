-- PLANTILLA de misión para rp_missions. Copiar el bloque al final de MISSION_DEFS (shared/s_missions_data.lua).
-- Sustituir TODO lo marcado con <...>. Las coordenadas inventadas son APROXIMADAS: ajustar en juego (/mmover, /mskip).
-- Detalle de campos: references/formato-mision.md. Cinemáticas: references/cinematicas.md. Voces: references/voces.md.
--
-- Orden de trabajo: 1) datos -> 2) voces de las líneas (voz.ps1 lote) -> 3) tools/build_voice_index.ps1 -> 4) probar.

{
    key = "<clave_unica>",                    -- nombra los audios <clave>_<etapa><c|r><n>.mp3
    title = "<Titulo>",
    contact = "sweet",                        -- sweet | ryder | cesar | smoke (MISSIONS.CONTACTS)
    desc = "<Descripcion para el menu>",
    minP = 1, maxP = 4, recommended = 3,
    minLevel = 1, minRespect = 0,
    cash = 2400, respect = 60, xpBonus = 0,
    weather = 0, hour = 19,
    roles = {
        { id = "driver", name = "Conductor", max = 1, weapons = { { 22, 80 } }, desc = "<que hace>" },
        { id = "gang",   name = "Pandillero", max = 4, weapons = { { 22, 90 }, { 4, 1 } }, desc = "<que hace>" },
    },
    spawns = { { 0.0, 0.0, 13.4, 90 }, { 0.0, 2.0, 13.4, 90 }, { 0.0, 4.0, 13.4, 90 }, { 0.0, 6.0, 13.4, 90 } },   -- <APROXIMADO>
    snap = { 0.0, 0.0, 13.4, 180 },
    victory = { 0.0, 0.0, 13.4, 180, spread = 1.6 },
    victoryCam = { from = P(5.0, 10.0, 16.5), look = P(0.0, 0.0, 14.4) },
    stages = {
        ----------------------------------------------------------------
        -- 1. Intro: cinemática (planos relativos al actor, gestos/idles/miradas de mocap AUTOMATICOS)
        ----------------------------------------------------------------
        {
            text = "Habla con <contacto>",
            cutscene = {
                letterbox = true,
                -- Solo el primer plano (general) usa coordenadas del mundo; el resto lo genera TalkShots relativo al actor
                shots = TalkShots("sweet", { from = P(0.0, -12.0, 17.0), to = P(0.0, -8.0, 16.0), look = P(0.0, 0.0, 14.4), dur = 3200, fov = 62 }),
                lines = {
                    -- NO reordenar nunca estos indices: nombran los audios (<clave>_1c1, 1c2, ...). "me" no lleva voz.
                    { who = "sweet", text = "<Frase 1 con tildes y signos: ¿¡ñ>" },
                    { who = "me",    text = "<Respuesta del jugador>" },
                    { who = "sweet", text = "<Frase 3 que interrumpe>", overlap = 450 },
                    { who = "sweet", text = "<Frase 4 con pausa dramatica>", gap = 500 },
                },
                place = { 0.0, 0.0, 13.4, 90, spread = 1.4 },    -- el grupo, lado a lado, mirando hacia rot
                npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
            },
        },
        ----------------------------------------------------------------
        -- 2. Subir al vehiculo (todos los vivos dentro)
        ----------------------------------------------------------------
        {
            text = "Sube al <vehiculo>",
            pos = P(0.0, 8.0, 13.4),
            vehicles = { { key = "car", model = 492, x = 0.0, y = 8.0, z = 13.4, rot = 90, color = { 86, 86 } } },
            getin = "car",
            radio = { { who = "sweet", text = "<Llamada de radio, con tildes>" } },
        },
        ----------------------------------------------------------------
        -- 3. Conducir (el aliado sube al vehiculo al empezar la etapa)
        ----------------------------------------------------------------
        {
            text = "Conduce hasta <destino>",
            pos = P(100.0, 0.0, 14.0),
            goto = { 100.0, 0.0, 14.0, 18, vehicle = true },
            boardNpc = { "sweet", "car" },
        },
        ----------------------------------------------------------------
        -- 4. Combate: el punto central x,y,z debe ser un LUGAR ABIERTO (calle/patio); la aparicion se valida con rayos
        ----------------------------------------------------------------
        {
            text = "Elimina a <enemigos>",
            pos = P(100.0, 0.0, 14.0),
            enemies = {
                { skins = { 102, 103, 104 }, weapon = 22, ammo = 200, x = 100.0, y = 0.0, z = 14.0, radius = 14, count = 4, per = 2, label = "<Banda>" },
            },
            snap = { 90.0, 0.0, 14.0, 0 },
        },
        ----------------------------------------------------------------
        -- 5. Cierre: cinemática final (los jugadores bajan solos del vehiculo y el vehiculo se aparta)
        ----------------------------------------------------------------
        {
            text = "Habla con <contacto>",
            cutscene = {
                letterbox = true,
                shots = TalkShots("sweet", { from = P(5.0, 10.0, 16.0), to = P(2.0, 6.0, 15.4), look = P(0.0, 0.0, 14.4), dur = 3200, fov = 58 }),
                lines = {
                    { who = "sweet", text = "<Frase de cierre 1>" },
                    { who = "me",    text = "<Respuesta>" },
                    { who = "sweet", text = "<Frase de cierre 3>" },
                },
                place = { 0.0, 0.0, 13.4, 180, spread = 1.5 },
                npcs = { { key = "sweet", contact = "sweet", skin = 270, rel = 2.6, ally = true, weapon = { 28, 500 } } },
            },
        },
    },
},
