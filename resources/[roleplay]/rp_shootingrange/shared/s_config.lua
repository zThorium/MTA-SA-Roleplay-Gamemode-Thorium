--[[
    rp_shootingrange / s_config.lua  (compartido)

    FIRE (posicion de tiro, interior 7) y DESK (marcador de entrada, interior 4) tomados en juego
    con /pos el 2026-11-25 en el Ammu-Nation Market. Son posiciones de JUGADOR: su z esta ~1 m
    sobre el suelo (FEET_OFFSET lo descuenta para los blancos). Los blancos van por el carril LANE
    (tambien medido en juego) y miran hacia FIRE; FIRE.rot solo orienta al jugador al entrar.
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
    -- Impactos: la parte del cuerpo la da GTA (onClientPedDamage del blanco) y el servidor la valida
    -- contra un disparo real (ver s_session.lua). bodypart de MTA -> zona.
    BODYPART_ZONE = { [9] = "head", [3] = "torso", [4] = "torso", [5] = "torso", [6] = "torso", [7] = "legs", [8] = "legs" },
    HIT_WINDOW_MS = 600,        -- el impacto y su disparo deben llegar con menos de esto de diferencia
    HIT_MAX_MISS = 0.8,         -- la trayectoria del disparo debe pasar a menos de esto (m) del cuerpo
    ZONES = {                   -- puntos y habilidad por zona (z/r ya no deciden el impacto)
        { key = "head",  name = "Cabeza", z = 1.58, r = 0.17, points = 100, gain = 6 },
        { key = "torso", name = "Torso",  z = 1.10, r = 0.30, points = 50,  gain = 4 },
        { key = "legs",  name = "Piernas", z = 0.50, r = 0.28, points = 25, gain = 2 },
    },

    ROUND_DELAY_MS = 3000,
    -- Franja donde aparecen los blancos (medida en juego con /pos): `from` = limite izquierdo del
    -- campo, `to` = limite derecho (~19,1 m). halfWidth = metros de fondo hacia delante/atras de la linea.
    -- Ningun blanco sale de la franja (margen de 1 m a cada pared).
    LANE = {
        from = { x = 292.493, y = -134.273, z = 1004.062 },
        to   = { x = 273.393, y = -134.473, z = 1004.062 },
        halfWidth = 1.0,
    },
    -- Rondas. Las posiciones las genera rangeBuildRound con ruido Perlin (semilla por sesion): cada
    -- partida es distinta. La franja se reparte en `count` tramos (sin amontonar ni dejar huecos).
    --   static:  `count` blancos quietos
    --   advance: `count` blancos que cruzan la franja de lado a lado en `dur` s, uno cada `every` s
    --   lateral: un blanco que va y viene `amp` m cada `period` s; reaparece a los `rearm` s de acertarle
    ROUNDS = {
        { kind = "static",  time = 25, count = 5 },
        { kind = "advance", time = 24, count = 4, dur = 8, every = 3 },
        { kind = "lateral", time = 15, count = 1, amp = 4, period = 4, rearm = 0.6 },
    },

    -- Categorias de arma (nombre en el menu)
    CATEGORIES = {
        pistol  = { name = "Pistolas" },
        smg     = { name = "Subfusiles" },
        shotgun = { name = "Escopetas" },
        rifle   = { name = "Fusiles" },
    },

    -- Municion de entrenamiento: dentro del campo el arma tiene balas "infinitas" que NO salen del
    -- inventario. Es un arma aparte que se retira al terminar la sesion; al salir, rp_ammunation
    -- devuelve el arma equipada con las balas reales del inventario (nunca se suman balas).
    TRAINING_AMMO = 9999,
    REFILL_BELOW = 300,            -- si baja de esto, se rellena hasta TRAINING_AMMO
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
    -- Tope de habilidad en 24 h (todas las armas). Antes las balas costaban dinero y eso frenaba el
    -- farmeo; con municion gratis el limite es este. 0 = sin tope.
    SKILL_MAX_PER_DAY = 300,
    HISTORY_SESSIONS = 15,         -- sesiones que se ven en las graficas de los resultados

    UI = { title = "Campo de tiro", hint_exit = "F2: salir del entrenamiento" },
}
