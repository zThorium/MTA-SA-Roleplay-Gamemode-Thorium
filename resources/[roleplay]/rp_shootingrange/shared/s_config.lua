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
    -- Campo de tiro (rectangulo medido en juego con /pos, posiciones de jugador): profundidad sobre X
    -- del frente (x 292,49) al fondo (x 273,39) = 19,1 m; ancho sobre Y de la pared izquierda
    -- (y -144,34) a la derecha (y -126,05) = 18,3 m, vistas desde la cabina. margin = distancia minima
    -- a las paredes.
    AREA = { front = 292.493, back = 273.393, left = -144.336, right = -126.051, z = 1004.062, margin = 1.0 },
    -- Desde la cabina solo se ve lo que cae dentro de este angulo a cada lado de FIRE.rot; un blanco
    -- que caeria fuera se empuja hacia el fondo (vista mas ancha) y, si hace falta, hacia el centro.
    VIEW_HALF_ANGLE = 35,
    MIN_TARGET_DIST = 8.0,      -- ningun blanco mas cerca del tirador que esto
    -- Rondas. Las posiciones las genera rangeBuildRound con ruido Perlin (semilla por sesion): cada
    -- partida es distinta. El ancho se reparte en `count` tramos (de pared a pared) y la profundidad
    -- tambien sale del ruido: dispersos en todo el campo, nunca en fila.
    --   static:  `count` blancos quietos
    --   advance: `count` blancos, cada uno a una profundidad distinta, que cruzan el campo de pared a
    --            pared en `dur` s, uno cada `every` s
    --   lateral: un blanco que va y viene `amp` m a lo ancho cada `period` s; reaparece a los `rearm` s
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

-- Posicion efectiva del mostrador: la de arriba o la que movio un admin con el editor (rp_markers).
-- Servidor y cliente la llaman al arrancar y en rp:markers:moved.
function rangeResolveDesk()
    local D = RANGE.DESK
    D.base = D.base or { D.x, D.y, D.z }
    local ok, x, y, z = pcall(function() return exports.rp_markers:placePoint("desk", D.base[1], D.base[2], D.base[3]) end)
    if ok and x then D.x, D.y, D.z = x, y, z end
end
