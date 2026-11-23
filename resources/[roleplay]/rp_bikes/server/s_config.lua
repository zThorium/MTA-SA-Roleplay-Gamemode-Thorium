--[[
    rp_bikes / s_config.lua  (solo servidor)
    Configuracion del arriendo de bicicletas. Edita aqui puntos, precio y tiempos.
]]

BIKES = {
    DURATION = 60 * 60000,            -- duracion del arriendo (60 min). La bici se elimina al cumplirse.
    WARN_BEFORE = { 5 * 60000, 60000 }, -- avisos antes de que termine (5 min y 1 min)

    -- Precio del arriendo. 0 = gratis.
    PRICE = 150,
    -- De donde se cobra: "cash" (dinero en mano) o "none" (no cobra).
    PAYMENT = "cash",

    -- Modelos de bicicleta que se pueden arrendar (se elige uno al azar).
    -- 481 = BMX, 509 = Bike, 510 = Mountain Bike
    MODELS = { 481, 509, 510 },

    INTERACT_RADIUS = 2.5,            -- distancia al marcador para arrendar (tecla E)
    COOLDOWN = 1500,                  -- ms entre intentos de arriendo por jugador

    MARKER = { r = 245, g = 165, b = 36, a = 140, size = 1.4 },
    -- Blip del mapa. icon 54 = bicicleta descriptiva en el minimapa de rp_hud.
    BLIP = { enabled = true, icon = 54, r = 76, g = 211, b = 138, size = 2, visibleDistance = 400 },

    -- Puntos de arriendo (Los Santos). x, y, z = suelo donde se pone el marcador (la bici aparece
    -- ahi mismo, un poco arriba), rot = hacia donde mira la bici, interior/dimension = 0 en el mundo abierto.
    -- Ajusta las coordenadas en juego si alguna queda sobre un obstaculo.
    POINTS = {
        { name = "Parque Glen",          x = 1953.5, y = -1203.5, z = 25.3, rot = 90,  interior = 0, dimension = 0 },
        { name = "Calle Grove",          x = 2488.0, y = -1655.5, z = 13.3, rot = 90,  interior = 0, dimension = 0 },
        { name = "Plaza Pershing",       x = 1480.5, y = -1683.5, z = 13.5, rot = 180, interior = 0, dimension = 0 },
        { name = "Playa Santa Maria",    x = 369.5,  y = -2038.5, z = 7.7,  rot = 270, interior = 0, dimension = 0 },
    },
}
