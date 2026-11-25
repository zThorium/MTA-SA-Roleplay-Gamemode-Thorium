--[[
    rp_shootingrange / s_config.lua  (compartido)

    FIRE (posicion de tiro, interior 7) y DESK (marcador de entrada, interior 4) tomados en juego
    con /pos el 2026-11-25 en el Ammu-Nation Market. Son posiciones de JUGADOR: su z esta ~1 m
    sobre el suelo (FEET_OFFSET lo descuenta para los blancos). La linea de blancos sale en la
    direccion a la que mira FIRE.rot.
    Para otra armeria con campo: anadir una fila a LOCATIONS (id = el de rp_ammunation).
]]
RANGE = {
    INTERACT_RADIUS = 1.3,
    COOLDOWN_MS = 1000,
    DIM_BASE = 23000,           -- una dimension por jugador dentro del campo: DIM_BASE + 1..DIM_SLOTS
    DIM_SLOTS = 500,
    STORE_DIM_BASE = 22000,     -- dimension de cada armeria en rp_ammunation (22000 + id)
    STORE_INTERIOR = 4,

    INTERIOR = 7,
    FIRE = { x = 303.750, y = -142.170, z = 1004.062, rot = 88.0 },
    DESK = { x = 301.859, y = -76.954, z = 1001.516 },
    FEET_OFFSET = 1.0,          -- z de un jugador - z de sus pies (MTA): el suelo de los blancos es FIRE.z - esto

    LOCATIONS = {
        { id = 1, name = "Ammu-Nation Market" },
    },

    MARKER = { r = 245, g = 165, b = 36, a = 120, size = 1.0 },

    -- Blancos: peds locales de cada jugador (skin) con zonas de impacto (esferas, alturas desde los pies)
    -- Skins de los blancos (al azar): pandilleros Ballas, Vagos y Aztecas. El 0 es el cuerpo de CJ
    -- sin ropa y se veia negro. Solo es visual: los impactos usan RANGE.ZONES.
    TARGET_SKINS = { 102, 103, 104, 108, 109, 110, 114, 115, 116 },
    LAG_S = 0.15,               -- holgura por latencia en los blancos que se mueven
    SHOT_MAX_FROM_PLAYER = 6.0, -- el origen del disparo debe estar cerca del jugador
    ZONES = {                   -- orden = prioridad
        { key = "head",  name = "Cabeza", z = 1.58, r = 0.17, points = 100, gain = 6 },
        { key = "torso", name = "Torso",  z = 1.10, r = 0.30, points = 50,  gain = 4 },
        { key = "legs",  name = "Piernas", z = 0.50, r = 0.28, points = 25, gain = 2 },
    },

    -- Pantalla de rondas (como el original: 1 estaticos, 2 avanzan, 3 lateral)
    ROUND_DELAY_MS = 3000,
    ROUNDS = {
        { kind = "static", time = 25, targets = {
            { d = 6, l = -3 }, { d = 9, l = 2 }, { d = 12, l = -1 }, { d = 15, l = 3.5 }, { d = 18, l = 0 } } },
        { kind = "advance", time = 24, targets = {
            { d0 = 24, d1 = 5, l = -2, at = 0, dur = 8 }, { d0 = 24, d1 = 5, l = 2, at = 3, dur = 8 },
            { d0 = 24, d1 = 5, l = 0, at = 6, dur = 8 }, { d0 = 24, d1 = 5, l = -1, at = 9, dur = 8 } } },
        { kind = "lateral", time = 15, targets = {
            { d = 14, amp = 4, period = 5, rearm = 0.6 } } },
    },

    -- Categorias de arma: escala de distancia de los blancos y balas maximas por sesion
    CATEGORIES = {
        pistol  = { name = "Pistolas",   dist = 1.0, ammo = 36 },
        smg     = { name = "Subfusiles", dist = 1.0, ammo = 60 },
        shotgun = { name = "Escopetas",  dist = 0.6, ammo = 18 },
        rifle   = { name = "Fusiles",    dist = 1.3, ammo = 60 },
    },
    -- Armas entrenables: item de rp_inventory -> stat nativa (69-79) y categoria.
    -- El id de arma GTA y la municion salen de la definicion del item en rp_inventory.
    WEAPONS = {
        wpn_colt45  = { stat = 69, category = "pistol" },
        wpn_deagle  = { stat = 71, category = "pistol" },
        wpn_shotgun = { stat = 72, category = "shotgun" },
        wpn_mp5     = { stat = 76, category = "smg" },
        wpn_ak47    = { stat = 77, category = "rifle" },
        wpn_m4      = { stat = 78, category = "rifle" },
        wpn_rifle   = { stat = 79, category = "rifle" },
    },

    -- Habilidad nativa 0-1000: Poor < 500 <= Gangster < 999 <= Hitman
    LEVELS = {
        { key = "poor",     name = "Poor",     from = 0 },
        { key = "gangster", name = "Gangster", from = 500 },
        { key = "hitman",   name = "Hitman",   from = 999 },
    },
    SKILL_MAX = 1000,
    SKILL_MAX_PER_SESSION = 120,   -- tope de puntos de habilidad por sesion (contra el farmeo)

    UI = { title = "Campo de tiro", hint_exit = "F2: salir del entrenamiento" },
}
