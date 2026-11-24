--[[
    rp_furniture / s_config.lua  (compartido)
    Configuracion del modo construccion: limites, precios, rejilla y materiales.
]]

FURN = {
    DIMENSION_BASE = 10000,          -- igual que PROPERTY.DIMENSION_BASE de rp_properties (dimension = base + id)

    -- Limites de objetos por tipo de casa (suma de pesos del catalogo, ver item.w)
    LIMIT_BY_TYPE = {
        small = 70, ryder = 90, grove = 100, medium = 130, modern = 150, family = 170, large = 210, villa = 280,
    },
    LIMIT_DEFAULT = 110,
    LIMIT_PER_LEVEL = 0.02,          -- +2% de capacidad por nivel del dueno (rp_levels)
    LIMIT_MAX_FACTOR = 1.6,

    -- Zona de construccion alrededor del punto de salida de la casa (metros)
    RADIUS_DEFAULT = 24,
    RADIUS_BY_INTERIOR = { [5] = 34, [8] = 28, [9] = 30, [12] = 34, [6] = 26 },
    Z_BELOW = 4, Z_ABOVE = 9,
    DOOR_CLEAR = 1.3,                -- radio libre alrededor de la salida (no se puede bloquear)

    -- Economia
    SELL_REFUND = 0.5,               -- al vender un mueble ya guardado
    SESSION_REFUND = 1.0,            -- si se retira en la misma sesion en la que se compro
    MAX_ACTIONS_PER_SEC = 12,
    MAX_BATCH = 40,

    -- Escala permitida (los paneles de estructura permiten mas)
    SCALE_MIN = 0.4, SCALE_MAX = 2.5,
    SCALE_STRUCT_MAX = 14,

    -- Ocultar objetos originales del interior
    MAX_HIDDEN_PROPS = 200,

    -- Interaccion
    USE_KEY = "g",
    BUILD_KEY = "F4",
    USE_DISTANCE = 2.6,

    -- Residentes (miembros que pueden construir)
    MAX_MEMBERS = 5,

    -- Planos
    MAX_BLUEPRINTS = 8,

    -- Contenedores (nevera, armario...): peso maximo en kg por mueble
    STORAGE_WEIGHT = 30,

    -- Descarga perezosa: tiempo sin nadie dentro antes de destruir los objetos
    UNLOAD_DELAY = 120000,
}

-- Rejillas disponibles en el editor (metros). 0 = libre
FURN_GRIDS = { 0, 0.05, 0.1, 0.25, 0.5, 1.0 }

-- Pasos de rotacion (grados)
FURN_ROT_STEPS = { 1, 5, 15, 45, 90 }

-- Colores de muestra (paleta tipo Los Sims). Cada uno es RGB 0xRRGGBB. El primero = sin tinte (blanco).
FURN_SWATCHES = {
    0xFFFFFF, 0xE8E2D5, 0xBDBDBD, 0x6E6E6E, 0x2B2B2B,
    0xC0392B, 0xE67E22, 0xF1C40F, 0x8BC34A, 0x27AE60,
    0x16A085, 0x3498DB, 0x2C3E91, 0x8E44AD, 0xE91E8C,
    0x8B5A2B, 0xD2B48C, 0x4E342E, 0xF5CBA7, 0xFFE0B2,
}

-- Materiales procedurales (los genera el cliente con dx, ver client/c_materials.lua)
FURN_MATERIALS = {
    { id = "liso",     name = "Liso" },
    { id = "madera",   name = "Madera" },
    { id = "parquet",  name = "Parquet" },
    { id = "baldosa",  name = "Baldosa" },
    { id = "ajedrez",  name = "Ajedrez" },
    { id = "rayas",    name = "Rayas" },
    { id = "ladrillo", name = "Ladrillo" },
    { id = "concreto", name = "Concreto" },
    { id = "alfombra", name = "Alfombra" },
    { id = "cuadros",  name = "Cuadros" },
}
FURN_MATERIAL_BY_ID = {}
for _, m in ipairs(FURN_MATERIALS) do FURN_MATERIAL_BY_ID[m.id] = m end

-- Emisoras para TV y equipos de musica (se toman de rp_radio: mismas URLs ya probadas)
FURN_STATIONS = {
    { id = 1, name = "LOS40",       url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40AAC.aac" },
    { id = 2, name = "LOS40 Dance", url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_DANCEAAC.aac" },
    { id = 3, name = "LOS40 Urban", url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_URBANAAC.aac" },
    { id = 4, name = "LOS40 Classic", url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_CLASSICAAC.aac" },
    { id = 9, name = "M80 Radio",   url = "https://playerservices.streamtheworld.com/api/livestream-redirect/M80RADIOAAC.aac" },
    { id = 12, name = "Cadena SER", url = "https://playerservices.streamtheworld.com/api/livestream-redirect/CADENASERAAC.aac" },
}
FURN_STATION_BY_ID = {}
for _, s in ipairs(FURN_STATIONS) do FURN_STATION_BY_ID[s.id] = s end
