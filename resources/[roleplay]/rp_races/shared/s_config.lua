--[[
    rp_races / shared / s_config.lua
    Parametros del sistema de carreras (se carga en servidor y cliente).
]]

RACE = {
    MAX_PLAYERS    = 8,      -- plazas de la parrilla (humanos + IA)
    LOBBY_TIME     = 90,     -- s que espera una sala antes de empezar sola (RF-04)
    REGROUP_TIME   = 12,     -- s de sala corta al votar otra pista
    COUNTDOWN      = 3,
    DNF_TIME       = 30,     -- s que tienen los demas tras cruzar el primero la meta (RF-16)
    VOTE_TIME      = 25,     -- s de la pantalla de resultados + votacion (RF-18)
    DIM_BASE       = 4000,   -- dimensiones de carrera: DIM_BASE + n (RF-05)
    CP_RADIUS      = 14,     -- radio de checkpoint (m)
    RESPAWN_HOLD   = 1200,   -- ms manteniendo Retroceso para reaparecer (RF-10)
    RESPAWN_CD     = 2500,   -- ms minimos entre reapariciones
    FLIP_TIME      = 3000,   -- ms boca abajo antes de reaparecer solo
    STUCK_TIME     = 4000,   -- ms casi parado antes de reaparecer solo
    GRID_ROW_GAP   = 9,      -- m entre filas de la parrilla
    GRID_SIDE      = 1.7,    -- m a cada lado del eje
    MARKER_SIZE    = 4,
    SLIPSTREAM     = true,   -- RF-11
    SLIP_DIST      = 24,     -- m detras de otro para recibir rebufo
    ADMIN_LEVEL    = 3,

    CLASSES = {
        { id = "compactos",  name = "Compactos",  models = { 496, 602, 589, 401 } },
        { id = "deportivos", name = "Deportivos", models = { 562, 560, 565, 559, 558 } },
        { id = "musculo",    name = "Muscle",     models = { 402, 475, 603, 439 } },
        { id = "super",      name = "Super",      models = { 411, 451, 415, 541, 429, 506 } },
        { id = "motos",      name = "Motos",      models = { 522, 521, 461 } },
    },

    WEATHERS = {
        { id = 0,  name = "Despejado" }, { id = 1, name = "Soleado" }, { id = 7, name = "Nublado" },
        { id = 8,  name = "Lluvia" },    { id = 9, name = "Niebla" },  { id = 19, name = "Tormenta de arena" },
    },
    HOURS = { { h = -1, name = "Hora del servidor" }, { h = 6, name = "Amanecer" }, { h = 12, name = "Mediodia" },
              { h = 18, name = "Atardecer" }, { h = 23, name = "Noche" } },

    -- speed = factor sobre la velocidad objetivo de cada nodo; react = ms entre decisiones; brake = tolerancia
    DIFFICULTY = {
        { name = "Facil",   speed = 0.74, react = 280, lookahead = 2 },
        { name = "Normal",  speed = 0.88, react = 170, lookahead = 3 },
        { name = "Dificil", speed = 1.00, react = 90,  lookahead = 4 },
    },

    -- Recompensas (RF-17)
    REWARD_BASE      = 300,
    REWARD_PER_RACER = 120,
    XP_BASE          = 40,
    XP_PER_RACER     = 10,
    DEFAULTS = { class = 1, laps = 2, hour = -1, weather = 0, ghost = false, ai = true, difficulty = 2, catchup = true },
    MAX_LAPS = 5,
}

function raceClamp(v, a, b) return math.max(a, math.min(b, v)) end
