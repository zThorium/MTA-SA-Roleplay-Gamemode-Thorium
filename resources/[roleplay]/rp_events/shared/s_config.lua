--[[
    rp_events / s_config.lua  (compartido cliente/servidor)
    Configuracion del mundo vivo: reloj, clima y director de eventos.
    Todos los tiempos en segundos reales salvo que se indique ms.
]]

WORLD = {
    -- 24 h de juego = 6 h reales (1 minuto de juego = 15 s). La hora sale del reloj real,
    -- asi que sigue avanzando de forma continua aunque se reinicie el servidor.
    MINUTE_MS = 15000,

    -- Estados de clima. ids = ids de MTA (se elige uno al azar al entrar al estado).
    -- dwell = {min, max} segundos reales que dura. next = pesos de la siguiente transicion.
    WEATHER = {
        sun    = { label = "Soleado",   ids = { 0, 1 },  dwell = { 1500, 3000 }, rain = false,
                   next = { sun = 1, smog = 2, cloudy = 3 } },
        smog   = { label = "Bruma",     ids = { 2, 3 },  dwell = { 900, 1800 },  rain = false,
                   next = { sun = 3, cloudy = 3, fog = 1 } },
        cloudy = { label = "Nublado",   ids = { 4, 7 },  dwell = { 900, 1800 },  rain = false,
                   next = { sun = 3, rain = 3, smog = 1, fog = 1 } },
        rain   = { label = "Lluvia",    ids = { 8 },     dwell = { 600, 1500 },  rain = true,
                   next = { cloudy = 4, storm = 1, sun = 1 } },
        storm  = { label = "Tormenta",  ids = { 16 },    dwell = { 300, 720 },   rain = true,
                   next = { rain = 4, cloudy = 2 } },
        fog    = { label = "Niebla",    ids = { 9 },     dwell = { 600, 1200 },  rain = false,
                   next = { cloudy = 3, sun = 3, smog = 1 } },
    },
    START_WEATHER = "sun",
}

EVENTS = {
    DEFAULT_INTENSITY = 2,        -- 0 apagado, 1 tranquilo, 2 normal, 3 movido
    TICK = 20,                    -- s entre decisiones del director
    MAINTAIN_TICK = 5,            -- s entre revisiones de los eventos activos

    MAX_ACTIVE = 4,               -- eventos compartidos simultaneos
    MAX_ELEMENTS = 48,            -- elementos (vehiculos, peds, objetos) creados por eventos en total
    BUDGET_MAX = 6,               -- presupuesto de "drama" acumulable
    BUDGET_START = 3,
    -- Presupuesto que se recupera por minuto segun la intensidad (se escala por jugadores conectados)
    BUDGET_REGEN = { 0.0, 0.9, 1.8, 3.0 },
    HISTORY = 4,                  -- ultimos eventos que pesan menos (variedad)
    HISTORY_MULT = 0.3,

    LOCATE_TIMEOUT = 6,           -- s que espera el punto que elige el cliente
    MIN_SPAWN_DIST = 40,          -- m al ancla (se valida en el servidor)
    MAX_SPAWN_DIST = 190,
    EVENT_SPACING = 140,          -- m minimos entre eventos activos
    ABANDON_AFTER = 75,           -- s sin ningun jugador cerca -> el evento se retira
    NEAR_RADIUS = 220,            -- m para contar jugadores "cerca" de un evento
    NOTIFY_RADIUS = 90,           -- m para avisar a un jugador de lo que ocurre
}

-- Mercadillo: ajustes de los puestos (calibrables en juego con /mercadoajuste <dz> <rotacion>)
MARKET = {
    CART_DZ = 1.0,        -- m que se sube el puesto (el origen del modelo 1340 queda enterrado); calibrado en juego
    CART_ROT = 0,         -- grados extra para que el frente del puesto mire a la calle (0, 90, 180, 270)
    STALL_GAP = 3.8,      -- m entre puestos a lo largo de la acera
    -- Productos por tipo de puesto (item del inventario = precio), algo mas baratos que el 24/7
    STALLS = {
        { name = "Puesto de comida", items = { burger = 16, sandwich = 10, water = 4 } },
        { name = "Puesto de bebidas", items = { water = 4, coffee = 7 } },
        { name = "Puesto de tabaco", items = { cigarettes = 13, lighter = 4 } },
    },
}
