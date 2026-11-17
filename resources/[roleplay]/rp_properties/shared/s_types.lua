--[[
    rp_properties / s_types.lua  (compartido)
    Tipos de interior: interior de GTA + punto de aparicion dentro.
    Coordenadas de la lista de interiores de GTA SA (wiki de MTA: Interior IDs).
    Cada propiedad usa la dimension 10000 + id para que no se mezclen.
]]

INTERIOR_TYPES = {
    small   = { name = "Casa pequena",     interior = 1,  x = 223.04,   y = 1287.26,  z = 1082.14, rot = 0 },
    grove   = { name = "Casa de Grove",    interior = 3,  x = 2496.05,  y = -1692.73, z = 1014.74, rot = 180 },
    ryder   = { name = "Casa de barrio",   interior = 2,  x = 2468.84,  y = -1698.24, z = 1013.51, rot = 90 },
    medium  = { name = "Casa mediana",     interior = 5,  x = 2233.80,  y = -1115.36, z = 1050.88, rot = 0 },
    modern  = { name = "Casa moderna",     interior = 6,  x = 2196.85,  y = -1204.25, z = 1049.02, rot = 90 },
    family  = { name = "Casa familiar",    interior = 8,  x = 2365.30,  y = -1135.60, z = 1050.88, rot = 0 },
    large   = { name = "Casa grande",      interior = 9,  x = 2317.82,  y = -1026.75, z = 1050.22, rot = 0 },
    villa   = { name = "Villa",            interior = 12, x = 2324.53,  y = -1149.54, z = 1050.71, rot = 0 },
}

PROPERTY = {
    DIMENSION_BASE = 10000,
    PREVIEW_TIME = 60000,       -- ms de visita previa
    MAX_PER_CHARACTER = 3,
    SELL_REFUND = 0.5,          -- se devuelve el 50% al vender
    PICKUP_FOR_SALE = 1273,     -- casa verde
    PICKUP_OWNED = 1318,        -- flecha blanca
}
