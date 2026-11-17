--[[
    rp_vehicles / s_config.lua  (compartido cliente/servidor)
    Ajustes de vehiculos personales: teclas, maletero, retencion de registros,
    policia y precios del taller de tuning.
]]

VEHICLES = {
    -- Teclas que se bindean al entrar con un personaje. Son comandos, asi que
    -- cada jugador puede cambiarlas en Ajustes > Binds de MTA.
    KEYS = {
        lock        = { key = "l",       command = "bloquear",          label = "Abrir / cerrar vehiculo" },
        engine      = { key = "j",       command = "toggleengine",      label = "Encender / apagar motor" },
        handbrake   = { key = "x",       command = "frenodemano",       label = "Freno de mano" },
        left        = { key = "arrow_l", command = "intermitente_izq",  label = "Intermitente izquierdo" },
        right       = { key = "arrow_r", command = "intermitente_der",  label = "Intermitente derecho" },
        hazard      = { key = "arrow_d", command = "balizas",           label = "Balizas (los dos)" },
        interact    = { key = "m",       command = "interactuar",       label = "Cursor para interactuar" },
    },

    LOCK_DISTANCE = 6,          -- metros para abrir / cerrar con la llave
    INTERACT_DISTANCE = 6,      -- metros para el menu de click derecho
    HANDBRAKE_MAX_SPEED = 8,    -- km/h: por encima no se puede poner el freno de mano
    SAVE_INTERVAL = 5 * 60000,

    -- Intermitentes
    INDICATOR_BLINK = 380,      -- ms encendido / apagado
    INDICATOR_COLOR = { 255, 170, 0 },
    INDICATOR_STREAM = 120,     -- metros a los que se dibujan
    -- Ademas de la corona amarilla, cada intermitente puede iluminar el entorno
    -- con createLight. Viene apagado: en algunas GPU NVIDIA (Optimus) las luces
    -- dinamicas moviendose cada frame coincidieron con crashes del driver.
    INDICATOR_REAL_LIGHTS = false,

    -- Maletero: kg por categoria (0 = sin maletero). El resto usa TRUNK_DEFAULT.
    TRUNK_DEFAULT = 30,
    TRUNK_BY_TYPE = { Bike = 0, BMX = 0, Quad = 5, Boat = 20, Helicopter = 15, Plane = 20 },
    TRUNK_BY_MODEL = { [482] = 80, [498] = 120, [499] = 120, [609] = 120, [413] = 80, [440] = 80, [459] = 80, [422] = 60, [478] = 50, [543] = 50, [554] = 60, [600] = 50, [605] = 50 },

    -- Registros de golpes y ocupantes: se borran pasado este tiempo
    LOG_RETENTION_HOURS = 24,
    LOG_CLEANUP_INTERVAL = 60 * 60000,
    HIT_MERGE_SECONDS = 10,     -- golpes seguidos del mismo jugador se agrupan en una fila
    HIT_MIN_LOSS = 5,           -- dano minimo para registrar un golpe
    PANEL_ROWS = 40,

    -- Policia: faccion reservada (ver rp_database/schema.lua)
    POLICE_FACTION_ID = 1,
    FINE_MIN = 50,
    FINE_MAX = 50000,
    FINE_REASON_MAX = 128,
}

-- Taller de tuning. Los puntos se pueden agregar aqui (x, y, z, radio).
TUNING = {
    SHOPS = {
        { name = "Transfender",      x = 1041.6, y = -1021.3, z = 32.1, radius = 4 },
        { name = "Loco Low Co.",     x = 2644.9, y = -2040.3, z = 13.6, radius = 4 },
        { name = "Wheel Arch Angels", x = -2711.3, y = 217.6, z = 4.3,  radius = 4 },
        { name = "Transfender SF",   x = -1936.1, y = 237.6,  z = 34.3, radius = 4 },
        { name = "Transfender LV",   x = 2386.7, y = 1050.3,  z = 10.8, radius = 4 },
    },
    PRICE_COLOR = 150,          -- cada cambio de color (primario, secundario o faros)
    PRICE_PAINTJOB = 1500,
    PRICE_REMOVE = 50,          -- quitar una pieza
    -- Precio por slot de mejora (getVehicleUpgradeSlotName). El resto usa PRICE_UPGRADE.
    PRICE_UPGRADE = 400,
    PRICE_BY_SLOT = {
        [8] = 2500,   -- Nitro
        [9] = 3000,   -- Hidraulica
        [12] = 1200,  -- Ruedas
        [13] = 600,   -- Escape
        [2] = 900,    -- Aleron
        [10] = 800,   -- Estereo (bajos)
    },
    -- Precios fijos por id de mejora (opcional, ganan a PRICE_BY_SLOT)
    PRICE_BY_UPGRADE = { [1008] = 1500, [1009] = 1000, [1010] = 2500 },
}

-- Nombres en espanol de los slots de mejora
TUNING_SLOT_NAMES = {
    [0] = "Capo", [1] = "Toma de aire", [2] = "Aleron", [3] = "Faldones", [4] = "Defensa delantera",
    [5] = "Defensa trasera", [6] = "Faros", [7] = "Techo", [8] = "Nitro", [9] = "Hidraulica",
    [10] = "Estereo", [11] = "Otros", [12] = "Ruedas", [13] = "Escape", [14] = "Paragolpes delantero",
    [15] = "Paragolpes trasero", [16] = "Misc",
}

function getTrunkCapacity(model)
    if VEHICLES.TRUNK_BY_MODEL[model] then return VEHICLES.TRUNK_BY_MODEL[model] end
    local vtype = getVehicleType(model)
    if vtype and VEHICLES.TRUNK_BY_TYPE[vtype] then return VEHICLES.TRUNK_BY_TYPE[vtype] end
    return VEHICLES.TRUNK_DEFAULT
end

function getUpgradePrice(upgrade, slot)
    return TUNING.PRICE_BY_UPGRADE[upgrade] or TUNING.PRICE_BY_SLOT[slot] or TUNING.PRICE_UPGRADE
end

-- Id de la llave de un vehiculo en el inventario (familia "vkey:" de rp_inventory)
function vehicleKeyItem(vehicleId)
    return "vkey:" .. tostring(vehicleId)
end
