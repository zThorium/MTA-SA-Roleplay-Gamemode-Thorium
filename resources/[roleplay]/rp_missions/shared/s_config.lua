--[[
    rp_missions / shared / s_config.lua

    Ajustes del sistema de misiones cooperativas (estilo GTA SA / GTA Online).
    Los datos de cada mision viven en s_missions_data.lua.
]]

MISSIONS = {
    DIM_BASE = 1000,          -- cada instancia usa DIM_BASE + n
    DIM_COUNT = 200,

    LOBBY_RANGE = 40,         -- metros para listar "jugadores cercanos" al invitar
    INVITE_TIME = 30000,      -- ms que dura una invitacion
    START_RANGE = 6,          -- el marcador de contacto: radio para abrir el menu
    RESPAWN_DELAY = 3200,     -- ms entre caer y reaparecer (vida compartida)
    INVULN_TIME = 3500,       -- ms de invulnerabilidad al reaparecer
    RESULT_TIME = 15000,      -- ms que se muestra la pantalla de resultados
    FAIL_TIME = 9000,
    VICTORY_CAM_TIME = 7000,
    HOLD_RANGE = 2.6,         -- distancia maxima para interactuar con un punto
    TICK = 400,               -- ms del bucle de cada instancia
    SPAWN_RANGE = 150,        -- los enemigos aparecen cuando alguien se acerca a esta distancia
    MAX_ENEMIES_ALIVE = 28,

    -- Dificultad (votada por el grupo). reward = multiplicador de XP/dinero/respeto.
    DIFFICULTY_ORDER = { "easy", "normal", "hard" },
    DIFFICULTY = {
        easy   = { label = "Facil",   reward = 1.0,  lives = 4, hp = 1.0,  armor = 0,  acc = 0.40, count = 0.85, color = { 76, 211, 138 } },
        normal = { label = "Normal",  reward = 1.25, lives = 2, hp = 1.25, armor = 25, acc = 0.60, count = 1.0,  color = { 245, 165, 36 } },
        hard   = { label = "Dificil", reward = 1.5,  lives = 0, hp = 1.6,  armor = 60, acc = 0.85, count = 1.25, color = { 229, 72, 77 } },
    },

    -- Recompensas (formula del diseno): XP = (BASE + kills*KILL + objetivos*OBJECTIVE) * dificultad
    REWARD = { BASE_XP = 500, KILL_XP = 15, OBJECTIVE_XP = 100, FAIL_KILL_XP = 5 },

    -- Respeto: puntos por contacto, tope total 1000 (= estadistica nativa de GTA SA)
    RESPECT_MAX = 1000,
    STAT_RESPECT = 64,
    -- Rangos de respeto (puntos totales). partyCap = integrantes maximos que puede liderar.
    RESPECT_RANKS = {
        { at = 0,   name = "Novato",    partyCap = 2, discount = 0.00 },
        { at = 120, name = "Conocido",  partyCap = 3, discount = 0.03 },
        { at = 320, name = "Respetado", partyCap = 4, discount = 0.06 },
        { at = 600, name = "Veterano",  partyCap = 4, discount = 0.10 },
        { at = 850, name = "Leyenda",   partyCap = 4, discount = 0.15 },
    },

    -- Identidad visual (estilo GTA SA). Texto de objetivo con etiquetas ~y~ ~r~ ~b~ ~g~ ~w~; si un texto no lleva etiquetas
    -- se colorea solo con TAGWORDS (la etiqueta explicita siempre manda).
    TAGS = { y = "#E1B02C", r = "#B4191D", b = "#2C599D", g = "#36682C", w = "#FFFFFF" },
    TAGWORDS = {
        r = { "Ballas", "ladrones", "Guardia Nacional", "guardia", "enemigos", "Vagos", "Matones", "matones", "vigías" },
        y = { "farmacia", "Idlewood", "Jefferson", "puerto", "panadería", "Willowfield", "taller", "callejón", "Grove Street", "arsenal", "alturas", "casa de Cesar" },
        b = { "Greenwood", "Blade", "Sentinel", "scooter", "camión", "furgoneta", "vehículo", "coche" },
        g = { "Sweet", "Ryder", "Cesar", "pastel", "rifle", "cargas", "cajita azul", "cajas" },
    },

    -- Contactos del "modo historia" (color del nombre en dialogos y llamadas)
    CONTACTS = {
        sweet = { name = "Sweet",  color = { 87, 190, 99 },  blip = 0 },
        ryder = { name = "Ryder",  color = { 245, 160, 50 }, blip = 0 },
        cesar = { name = "Cesar",  color = { 90, 150, 235 }, blip = 0 },
        smoke = { name = "Big Smoke", color = { 200, 90, 220 }, blip = 0 },
        enemy = { name = "Radio",  color = { 220, 90, 90 },  blip = 0 },
    },

    -- Puntos de inicio por defecto (se pueden mover con /mmover; se guardan en la BD)
    CONTACT_POINTS = {
        sweet = { x = 2495.3, y = -1683.3, z = 13.5 },
        ryder = { x = 2455.4, y = -1704.6, z = 13.5 },
        cesar = { x = 2175.0, y = -1730.0, z = 13.5 },
    },
}

function respectRank(total)
    local best = MISSIONS.RESPECT_RANKS[1]
    for _, r in ipairs(MISSIONS.RESPECT_RANKS) do
        if total >= r.at then best = r end
    end
    return best
end

-- Cantidad de enemigos: Base + (Jugadores - 1) * Factor, ajustado por dificultad
function scaledEnemyCount(base, per, players, diffKey)
    local d = MISSIONS.DIFFICULTY[diffKey] or MISSIONS.DIFFICULTY.normal
    local n = (base or 3) + math.max(0, (players or 1) - 1) * (per or 2)
    return math.max(1, math.floor(n * d.count + 0.5))
end

-- Duracion automatica de una linea de dialogo (ms)
function dialogDuration(line)
    if line.vlen then return line.vlen + 500 end
    return line.dur or math.max(2200, 1200 + #(line.text or "") * 55)
end

-- Horario de los dialogos de una cinematica (estandar: docs/CINEMATICAS.md).
--   line.at      = ms absolutos desde el inicio de la cinematica
--   line.overlap = ms que se SOLAPA con la linea anterior (interrupciones, estilo SA)
--   line.gap     = pausa antes de la linea (por defecto 250 ms; una pausa dramatica puede ser mayor)
function cutsceneSchedule(cutscene)
    local sched, prevEnd = {}, 900
    for i, line in ipairs((cutscene and cutscene.lines) or {}) do
        local s = line.at or (i == 1 and 900 or (prevEnd + (line.gap or 250) - (line.overlap or 0)))
        local e = s + dialogDuration(line)
        sched[i] = { s = s, e = e }
        prevEnd = e
    end
    return sched, prevEnd
end

function totalCutsceneTime(stage)
    local c = stage.cutscene or {}
    local t = 0
    for _, shot in ipairs(c.shots or {}) do t = t + (shot.dur or 3000) end
    local _, linesEnd = cutsceneSchedule(c)
    local actorsEnd = 0
    for _, a in ipairs(c.actors or {}) do actorsEnd = math.max(actorsEnd, (a.t or 0) + (a.walk and a.walk.ms or 0)) end
    return math.max(t, linesEnd, actorsEnd) + (c.tail or 600)
end
