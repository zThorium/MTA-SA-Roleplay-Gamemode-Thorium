--[[
    rp_rides / s_config.lua  (compartido cliente/servidor)
    App de viajes "Vroom": los jugadores piden viajes y otros jugadores los
    toman. Si no hay conductores disponibles, viene un conductor IA.
]]

RIDES = {
    APP_NAME = "Vroom",

    -- Tarifa: base + por km de recorrido estimado (distancia en linea recta x ROUTE_FACTOR)
    BASE_FARE = 25,
    PER_KM = 18,
    ROUTE_FACTOR = 1.3,
    MIN_FARE = 25,
    MAX_FARE = 900,
    COMMISSION = 0.2,          -- parte de la tarifa que se queda la app (conductores jugadores)
    MAX_TIP = 500,

    -- Reparto de pedidos segun la calificacion del conductor (mejor nota = lo ve antes)
    -- Cada tramo: nota minima y segundos de espera desde que se pide el viaje.
    PRIORITY = {
        { rating = 4.5, delay = 0 },
        { rating = 3.5, delay = 5 },
        { rating = 0,   delay = 10 },
    },
    NEW_DRIVER_RATING = 4.0,   -- nota con la que se trata a un conductor con menos de MIN_RATINGS
    MIN_RATINGS = 3,

    SEARCH_TIME = 25,          -- segundos buscando conductor antes de enviar uno IA
    BOARD_TIME = 120,          -- segundos para subirse cuando llega el conductor
    RATE_TIME = 90,            -- segundos para calificar al terminar

    -- Conductor IA
    AI_MODEL = 426,            -- Premier
    AI_COLOR = { 15, 15, 18 },
    AI_SKINS = { 17, 59, 147, 171, 187, 240 },
    AI_SPAWN_MIN = 110,        -- metros desde el pasajero donde aparece (fuera de la vista)
    AI_SPAWN_MAX = 170,
    AI_APPROACH_TIMEOUT = 180, -- s: si no llega, se recoloca cerca del pasajero
    AI_CRUISE = 55,            -- km/h
    AI_LEAVE_TIME = 18,        -- s alejandose antes de desaparecer
    AI_PICKUP_RADIUS = 14,     -- m: el auto se considera llegado

    -- Limites del mapa (Los Santos)
    MAP_MIN_X = -100, MAP_MAX_X = 3000,
    MAP_MIN_Y = -2900, MAP_MAX_Y = -600,
}

function rideFare(x1, y1, x2, y2)
    local km = getDistanceBetweenPoints2D(x1, y1, x2, y2) * RIDES.ROUTE_FACTOR / 1000
    local fare = math.floor(RIDES.BASE_FARE + km * RIDES.PER_KM + 0.5)
    return math.max(RIDES.MIN_FARE, math.min(RIDES.MAX_FARE, fare))
end
