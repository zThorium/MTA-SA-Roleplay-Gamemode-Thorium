--[[
    rp_pool / shared / s_config.lua

    Configuracion y utilidades compartidas (servidor y cliente) del pool.

    Marco de coordenadas de la mesa ("local"): u = a lo largo de la mesa (lado largo),
    v = a lo ancho, en metros, con (0,0) en el centro del area de juego. La mesa del
    juego (modelo 2964, k_pooltablesm) mide 1.94 x 1.07 m de juego y la bola tiene
    radio 0.037 m; las medidas salen del propio .dff (fieltro a z = 0.90).
]]

POOL = {
    -- Geometria (medida del modelo 2964)
    BALL_R       = 0.037,
    FELT_Z       = 0.90,      -- altura del fieltro sobre el origen del modelo (nivel del area de juego en el .dff)
    CENTER_U     = 0.007,     -- el centro de juego esta desplazado del origen del modelo
    CENTER_V     = 0.011,
    HALF_L       = 0.968,     -- cara de las bandas (mitad del largo de juego)
    HALF_W       = 0.534,     -- cara de las bandas (mitad del ancho de juego)
    MOUTH_CORNER = 0.085,     -- boca de las troneras de esquina
    MOUTH_SIDE   = 0.07,      -- boca de las troneras laterales (semiancho)

    -- Fisica (calibrada para que un tiro fuerte recorra ~7 largos y uno medio ~1.8 m)
    MAX_SPEED    = 5.8,       -- m/s con fuerza 100 %
    MIN_SPEED    = 0.35,      -- m/s con fuerza 0 %
    DECEL        = 1.1,       -- m/s^2 de rozamiento con el fieltro
    STOP_SPEED   = 0.03,
    CUSHION_E    = 0.72,      -- rebote en banda (componente normal)
    CUSHION_T    = 0.985,     -- se conserva la tangencial
    BALL_E       = 0.96,      -- rebote bola-bola
    SIM_DT       = 1 / 240,
    STEPS_PER_FRAME = 4,      -- un fotograma de replay cada 4 pasos = 60 fps
    FRAME_RATE   = 60,
    MAX_SIM_TIME = 30,        -- segundos maximos por tiro

    -- Mesa de juego
    CUE_MODEL    = 3004,      -- k_poolq2
    TABLE_MODEL  = 2964,      -- k_pooltablesm
    INTERACT_RADIUS = 2.6,    -- distancia al centro de la mesa para jugar
    STREAM_RANGE = 45,        -- el cliente crea las bolas si esta a menos de esto

    -- Apuestas
    BETS         = { 0, 10, 50, 100, 250, 500, 1000, 5000 },
    MAX_BET      = 100000,
    TURN_SECONDS = 60,
    MAX_TIMEOUTS = 2,         -- turnos agotados seguidos antes de perder la partida

    -- Ranking
    RANK_SIZE    = 10,

    -- Admin
    ADMIN_LEVEL  = 1,

    -- Local con mesas del juego original: Ten Green Bottles (Ganton), interior 11.
    -- Las 3 mesas ya existen en el interior (native = true: no se crea otro modelo).
    VENUES = {
        {
            name = "Ten Green Bottles",
            exterior = { x = 2309.62, y = -1643.63, z = 13.84, interior = 0, dimension = 0 },
            exteriorSpawn = { x = 2308.12, y = -1643.63, z = 13.84, rot = 93 },
            interior = { x = 501.981, y = -67.75, z = 997.835, interior = 11, dimension = 0 },
            interiorSpawn = { x = 501.981, y = -69.15, z = 997.835, rot = 180 },
        },
    },

    SEED_TABLES = {
        { x = 489.750, y = -80.211, z = 997.734, rz = 90, interior = 11, dimension = 0, native = 1 },
        { x = 506.484, y = -84.836, z = 997.938, rz = 90, interior = 11, dimension = 0, native = 1 },
        { x = 510.102, y = -84.836, z = 997.938, rz = 90, interior = 11, dimension = 0, native = 1 },
    },
}

-- Modelos de bola del juego: 0 = blanca, 1-7 lisas, 8 = negra, 9-15 rayadas
POOL_BALL_MODELS = {
    [0] = 3003,
    [1] = 3002, [2] = 3100, [3] = 3101, [4] = 3102, [5] = 3103, [6] = 3104, [7] = 3105,
    [8] = 3106,
    [9] = 2995, [10] = 2996, [11] = 2997, [12] = 2998, [13] = 2999, [14] = 3000, [15] = 3001,
}

-- Grupo de una bola: "solid" (1-7), "eight" (8), "stripe" (9-15)
function poolGroupOf(b)
    if b == 8 then return "eight" end
    if b >= 1 and b <= 7 then return "solid" end
    if b >= 9 and b <= 15 then return "stripe" end
    return nil
end

-- Tabla local (u, v) -> mundo (x, y). t = { x, y, rz } con rz en grados (sentido antihorario, como MTA).
function poolToWorld(t, u, v)
    local a = math.rad(t.rz or 0)
    local c, s = math.cos(a), math.sin(a)
    local lu, lv = u + POOL.CENTER_U, v + POOL.CENTER_V
    return t.x + lu * c - lv * s, t.y + lu * s + lv * c
end

-- Mundo (x, y) -> tabla local (u, v)
function poolFromWorld(t, x, y)
    local a = math.rad(t.rz or 0)
    local c, s = math.cos(a), math.sin(a)
    local dx, dy = x - t.x, y - t.y
    local lu = dx * c + dy * s
    local lv = -dx * s + dy * c
    return lu - POOL.CENTER_U, lv - POOL.CENTER_V
end

-- Altura (mundo) del centro de una bola sobre la mesa
function poolBallZ(t)
    return t.z + POOL.FELT_Z + POOL.BALL_R
end
