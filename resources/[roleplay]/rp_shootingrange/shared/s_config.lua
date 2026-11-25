--[[
    rp_shootingrange / s_config.lua  (compartido)

    VERIFICAR EN JUEGO (no se pudieron comprobar contra los IPL/IDE del juego):
      - RANGE.INTERIOR, FIRE (posicion de tiro) y FIRE.rot: la sala del campo en el interior 7
        (Ammu-Nation 5 de la wiki de MTA). Si los blancos salen en la pared o al reves, ajusta
        FIRE.x/y/z y FIRE.rot (la linea de blancos sale en la direccion a la que mira FIRE.rot).
      - DESK: mostrador del campo dentro de la tienda (interior 4). Esta entre la puerta y el vendedor.
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
    FIRE = { x = 298.5, y = -141.6, z = 1004.05, rot = 90 },
    DESK = { x = 289.0, y = -84.5, z = 1001.52 },

    LOCATIONS = {
        { id = 1, name = "Ammu-Nation Market" },
    },

    MARKER = { r = 245, g = 165, b = 36, a = 120, size = 1.0 },

    -- Blancos: peds locales de cada jugador (skin) con zonas de impacto (esferas, alturas desde los pies)
    TARGET_SKIN = 0,
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
