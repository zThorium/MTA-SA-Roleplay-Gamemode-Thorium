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
    REPAIR_BASE = 100,          -- reparar: base + (1000 - vida) * REPAIR_PER_POINT
    REPAIR_PER_POINT = 2,
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

----------------------------------------------------------------
-- Bencina (server/s_fuel.lua, client/c_fuel.lua)
----------------------------------------------------------------
FUEL = {
    PRICE_PER_LITER = 4,         -- $ por litro
    PER_KM = 0.9,                -- litros por km recorrido (escala de juego: ~60 km por tanque)
    IDLE_PER_MIN = 0.12,         -- litros por minuto con el motor encendido y parado
    TICK = 3000,                 -- ms entre calculos de consumo
    REFUEL_RATE = 3.5,           -- litros por segundo al cargar
    LOW = 0.15,                  -- fraccion del tanque que se considera reserva
    -- Litros del tanque: por modelo, por tipo de vehiculo o por defecto
    CAPACITY_DEFAULT = 55,
    CAPACITY_BY_TYPE = { Bike = 16, Quad = 14, ["Monster Truck"] = 120 },
    CAPACITY_BY_MODEL = {
        [403] = 300, [514] = 300, [515] = 300,                  -- camiones
        [431] = 200, [437] = 200,                               -- buses
        [407] = 150, [427] = 120, [428] = 90, [433] = 150, [455] = 150, [456] = 120, [498] = 90, [499] = 90, [578] = 150,
        [482] = 75, [440] = 70, [418] = 70, [413] = 70, [459] = 70, [582] = 70, [489] = 80, [505] = 80, [579] = 85,
    },
    -- Tipos de vehiculo sin bencina (bicicletas, trenes, remolques, aviones, botes)
    NO_FUEL_TYPES = { BMX = true, Train = true, Trailer = true, Plane = true, Helicopter = true, Boat = true },
    ATTENDANT_SKIN = 50,         -- mecanico con overol
    MARKER_RADIUS = 3.2,
    -- Bencineras: x, y, z = donde se estaciona el auto (marcador);
    -- px, py, pz, prz = donde espera el bombero. Los admins las ajustan con
    -- /moverbencinera y /moverbombero (se guardan en fuel_stations.json).
    STATIONS = {
        { name = "Xoomer Idlewood",      x = 1941.7, y = -1771.3, z = 13.4, px = 1937.6, py = -1775.4, pz = 13.4, prz = 270 },
        { name = "Xoomer Mulholland",    x = 1004.0, y = -937.5,  z = 42.2, px = 1000.6, py = -932.5,  pz = 42.3, prz = 190 },
        { name = "Flint County",         x = -90.5,  y = -1169.4, z = 2.4,  px = -86.0,  py = -1164.2, pz = 2.3,  prz = 160 },
        { name = "Dillimore",            x = 655.6,  y = -565.0,  z = 16.3, px = 660.4,  py = -569.6,  pz = 16.3, prz = 90 },
        { name = "Angel Pine",           x = -2243.9, y = -2560.6, z = 31.9, px = -2238.6, py = -2564.0, pz = 32.0, prz = 60 },
        { name = "Whetstone",            x = -1606.0, y = -2713.7, z = 48.5, px = -1601.6, py = -2709.2, pz = 48.5, prz = 140 },
        { name = "Easter Basin (SF)",    x = -1675.9, y = 412.9,   z = 7.2,  px = -1670.5, py = 416.9,   pz = 7.2,  prz = 130 },
        { name = "Juniper Hollow (SF)",  x = -2410.7, y = 975.6,   z = 45.3, px = -2415.9, py = 977.7,   pz = 45.3, prz = 270 },
        { name = "Come-A-Lot (LV)",      x = 2114.9,  y = 920.0,   z = 10.8, px = 2109.7,  py = 916.2,   pz = 10.8, prz = 270 },
        { name = "Roca Escalante (LV)",  x = 2202.2,  y = 2474.3,  z = 10.8, px = 2197.3,  py = 2479.0,  pz = 10.8, prz = 200 },
        { name = "Spinybed (LV)",        x = 2640.1,  y = 1106.0,  z = 10.8, px = 2645.6,  py = 1109.6,  pz = 10.8, prz = 90 },
        { name = "Redsands (LV)",        x = 1596.3,  y = 2199.4,  z = 10.8, px = 1590.8,  py = 2204.4,  pz = 10.8, prz = 270 },
        { name = "Fort Carson",          x = 70.4,    y = 1218.6,  z = 18.8, px = 65.6,    py = 1222.9,  pz = 18.8, prz = 250 },
        { name = "Tierra Robada",        x = -1328.8, y = 2677.2,  z = 50.1, px = -1324.0, py = 2682.5,  pz = 50.1, prz = 100 },
        { name = "Bone County",          x = 611.9,   y = 1694.4,  z = 7.0,  px = 616.7,   py = 1689.5,  pz = 7.0,  prz = 60 },
    },
}

function getFuelCapacity(model)
    if FUEL.CAPACITY_BY_MODEL[model] then return FUEL.CAPACITY_BY_MODEL[model] end
    local vtype = getVehicleType(model)
    if vtype and FUEL.CAPACITY_BY_TYPE[vtype] then return FUEL.CAPACITY_BY_TYPE[vtype] end
    return FUEL.CAPACITY_DEFAULT
end

function usesFuel(model)
    local vtype = getVehicleType(model)
    return vtype ~= nil and vtype ~= false and not FUEL.NO_FUEL_TYPES[vtype]
end

----------------------------------------------------------------
-- Rendimiento del tuning (server/s_perf.lua, panel "Rendimiento" del taller)
-- Cada pieza tiene niveles; cada nivel suma bonos y costos a las stats del
-- vehiculo. Los valores son fracciones (0.08 = +8%) sobre el handling de fabrica.
--   accel, speed, brake, grip, steer = beneficios (tienen tope por clase)
--   mass, fuel = costos (mas peso, mas consumo); mass negativo = aligerar
-- El desgaste (0-100%) reduce los beneficios de la pieza; al 100% la pieza
-- empeora el vehiculo por debajo de fabrica (ver perfWearScale).
----------------------------------------------------------------
PERF = {
    TICK = 3000,                -- ms entre calculos de desgaste
    MAX_VELOCITY = 300,         -- tope absoluto de maxVelocity (km/h)
    MAX_STEER = 45,             -- tope absoluto de steeringLock (grados)
    LOWER_PER_LEVEL = 0.012,    -- cada nivel de suspension baja el auto (suspensionLowerLimit)
    WORN_PENALTY = 0.25,        -- al 100% de desgaste la pieza resta este % de su bono
    WARN_AT = 70,               -- % de desgaste al que se avisa al conductor
    BRAKE_USE = 0.012,          -- % extra de desgaste de frenos por muestra frenando fuerte
    BRAKE_MIN_SPEED = 25,       -- km/h minimos para contar un frenazo
    BRAKE_DROP = 25,            -- km/h que debe bajar la velocidad entre muestras (3 s) para contar un frenazo
    SLIP_USE = 0.01,            -- % extra de desgaste de neumaticos por muestra derrapando
    SLIP_SPEED = 0.16,          -- velocidad (unidades de GTA) minima para medir derrape
    SLIP_ANGLE = 18,            -- grados entre la direccion y el movimiento que cuentan como derrape
    IMPACT_MIN = 40,            -- dano de un choque a partir del cual desgasta la suspension
    IMPACT_WEAR = 0.02,         -- % de desgaste de suspension por punto de dano
    TURBO_ENGINE_WEAR = 0.25,   -- el turbo gasta el motor: +25% de desgaste por nivel de turbo
    MAINT_FACTOR = 0.4,         -- mantenimiento = precio de la pieza * desgaste * factor
    MAINT_MIN = 50,

    STAT_ORDER = { "accel", "speed", "brake", "grip", "steer", "mass", "fuel" },
    STAT_NAMES = {
        accel = "Aceleracion", speed = "Velocidad maxima", brake = "Frenos", grip = "Agarre",
        steer = "Direccion", mass = "Peso", fuel = "Consumo",
    },
    COST_STATS = { mass = true, fuel = true },
    COST_DISPLAY_CAP = 0.30,    -- escala de la barra de los costos (solo visual)

    -- Clases: tope de cada beneficio (suma de todas las piezas) y multiplicador de precio
    CLASSES = {
        moto  = { name = "Moto",            price = 0.6, cap = { accel = 0.35, speed = 0.20, brake = 0.35, grip = 0.25, steer = 0.20 } },
        basic = { name = "Compacto / sedan", price = 1.0, cap = { accel = 0.30, speed = 0.15, brake = 0.35, grip = 0.20, steer = 0.15 } },
        suv   = { name = "SUV / todoterreno", price = 1.1, cap = { accel = 0.25, speed = 0.12, brake = 0.30, grip = 0.20, steer = 0.12 } },
        sport = { name = "Deportivo",       price = 1.2, cap = { accel = 0.38, speed = 0.22, brake = 0.50, grip = 0.30, steer = 0.20 } },
        super = { name = "Superdeportivo",  price = 1.5, cap = { accel = 0.42, speed = 0.25, brake = 0.55, grip = 0.35, steer = 0.22 } },
        heavy = { name = "Pesado",          price = 1.3, cap = { accel = 0.20, speed = 0.10, brake = 0.30, grip = 0.15, steer = 0.08 } },
    },
    -- Clase por tipo de vehiculo (getVehicleType). Lo que no esta aqui no se puede mejorar
    -- (bicicletas, botes, aviones, helicopteros, trenes, remolques, monster trucks).
    CLASS_BY_TYPE = { Automobile = "basic", Bike = "moto", Quad = "moto" },
    -- Clase por modelo (gana a CLASS_BY_TYPE)
    CLASS_BY_MODEL = {},
    NO_TUNE_MODELS = { [444] = true, [556] = true, [557] = true },  -- monster trucks

    -- Piezas. wear: km = % de desgaste por km, speed = cuanto pesa ir rapido,
    -- level = desgaste extra por nivel, use = desgaste extra por uso ("brake" / "slip").
    PARTS = {
        { id = "engine", name = "Motor", desc = "Cambia el motor: mas aceleracion y velocidad punta, pero pesa mas y gasta mas bencina. El turbo lo desgasta mas rapido.",
          wear = { km = 0.12, speed = 0.9, level = 0.35 },
          levels = {
              { name = "Stage 1 (admision y ECU)", price = 3500,  stats = { accel = 0.08, speed = 0.04, mass = 0.01, fuel = 0.05 } },
              { name = "Stage 2 (motor reforzado)", price = 7500,  stats = { accel = 0.16, speed = 0.08, mass = 0.02, fuel = 0.10 } },
              { name = "Stage 3 (cambio de motor)", price = 16000, stats = { accel = 0.26, speed = 0.13, mass = 0.03, fuel = 0.18 } },
          } },
        { id = "turbo", name = "Turbo", desc = "Mucha aceleracion extra a cambio de consumo. Cada nivel acelera el desgaste del motor.",
          wear = { km = 0.18, speed = 1.1, level = 0.35 },
          levels = {
              { name = "Turbo pequeno",  price = 4000,  stats = { accel = 0.10, speed = 0.03, fuel = 0.06 } },
              { name = "Turbo doble",    price = 9000,  stats = { accel = 0.18, speed = 0.06, fuel = 0.12 } },
              { name = "Turbo de competicion", price = 18000, stats = { accel = 0.28, speed = 0.09, fuel = 0.20 } },
          } },
        { id = "brakes", name = "Frenos", desc = "Mejor frenada. Las pastillas se gastan con cada frenazo fuerte.",
          wear = { km = 0.15, speed = 0.5, level = 0.30, use = "brake" },
          levels = {
              { name = "Frenos deportivos", price = 1800, stats = { brake = 0.15, mass = 0.005 } },
              { name = "Frenos de alto rendimiento", price = 3800, stats = { brake = 0.30, mass = 0.008 } },
              { name = "Frenos de carbono-ceramica", price = 8000, stats = { brake = 0.50 } },
          } },
        { id = "suspension", name = "Suspension", desc = "Mas agarre y direccion, y el auto baja visiblemente. Los choques fuertes la desgastan.",
          wear = { km = 0.08, speed = 0.4, level = 0.30 },
          levels = {
              { name = "Suspension deportiva", price = 2200, stats = { grip = 0.06, steer = 0.04 } },
              { name = "Suspension Pro", price = 4800, stats = { grip = 0.12, steer = 0.08 } },
              { name = "Suspension de competicion", price = 10000, stats = { grip = 0.18, steer = 0.12, mass = 0.01 } },
          } },
        { id = "tires", name = "Neumaticos", desc = "Agarre y direccion. Los derrapes los desgastan.",
          wear = { km = 0.22, speed = 0.6, level = 0.40, use = "slip" },
          levels = {
              { name = "Neumaticos deportivos", price = 1500, stats = { grip = 0.08 } },
              { name = "Semi-slick", price = 3200, stats = { grip = 0.16, steer = 0.04, fuel = 0.02 } },
              { name = "Slick de competicion", price = 7000, stats = { grip = 0.26, steer = 0.06, fuel = 0.04 } },
          } },
        { id = "weight", name = "Aligeramiento", desc = "Quita peso: acelera mejor pero pierde estabilidad. No se desgasta.",
          levels = {
              { name = "Interior aligerado", price = 2500, stats = { mass = -0.05, accel = 0.03, grip = -0.01 } },
              { name = "Carroceria de fibra", price = 5500, stats = { mass = -0.10, accel = 0.06, grip = -0.02 } },
              { name = "Chasis de competicion", price = 11000, stats = { mass = -0.15, accel = 0.09, grip = -0.04 } },
          } },
    },
}

PERF_PART = {}
for _, part in ipairs(PERF.PARTS) do PERF_PART[part.id] = part end

for _, m in ipairs({ 411, 541, 451, 506, 415, 429, 494, 502, 503 }) do PERF.CLASS_BY_MODEL[m] = "super" end
for _, m in ipairs({ 402, 475, 477, 480, 496, 518, 533, 536, 555, 558, 559, 560, 562, 565, 567, 575, 576, 587, 589, 602, 603, 535, 534 }) do PERF.CLASS_BY_MODEL[m] = "sport" end
for _, m in ipairs({ 400, 424, 470, 489, 495, 505, 579, 500, 568, 573 }) do PERF.CLASS_BY_MODEL[m] = "suv" end
for _, m in ipairs({ 403, 514, 515, 431, 437, 408, 455, 456, 414, 498, 499, 609, 578, 524, 532, 406, 407, 544, 601, 427, 428, 433 }) do PERF.CLASS_BY_MODEL[m] = "heavy" end

-- Clase de rendimiento de un modelo (nil = no se puede mejorar)
function getPerfClass(model)
    if PERF.NO_TUNE_MODELS[model] then return nil end
    if PERF.CLASS_BY_MODEL[model] then return PERF.CLASS_BY_MODEL[model] end
    local vtype = getVehicleType(model)
    return vtype and PERF.CLASS_BY_TYPE[vtype] or nil
end

-- Escala del beneficio de una pieza segun su desgaste: 1 (nueva) -> -WORN_PENALTY (100%)
function perfWearScale(wear)
    wear = math.max(0, math.min(100, tonumber(wear) or 0))
    return 1 - (1 + PERF.WORN_PENALTY) * wear / 100
end

-- Suma las stats de las piezas instaladas. parts = { engine = 2, ... }, wear = { engine = 14.5, ... }
-- Solo los beneficios positivos se gastan con el desgaste; los costos (peso, consumo) no.
function computePerfStats(parts, wear)
    local s = {}
    for _, stat in ipairs(PERF.STAT_ORDER) do s[stat] = 0 end
    for _, def in ipairs(PERF.PARTS) do
        local level = def.levels[tonumber(parts and parts[def.id]) or 0]
        if level then
            local scale = perfWearScale(wear and wear[def.id])
            for stat, v in pairs(level.stats) do
                if v > 0 and not PERF.COST_STATS[stat] then s[stat] = s[stat] + v * scale else s[stat] = s[stat] + v end
            end
        end
    end
    return s
end

-- true si ninguna stat supera el tope de la clase (se calcula con piezas nuevas, sin desgaste)
function perfWithinCap(classId, stats)
    local class = PERF.CLASSES[classId]
    if not class then return false end
    for stat, cap in pairs(class.cap) do
        if (stats[stat] or 0) > cap + 0.00001 then return false, stat end
    end
    return true
end

function perfLevelPrice(classId, level)
    return math.floor(level.price * PERF.CLASSES[classId].price)
end

function perfMaintenancePrice(classId, partId, level, wear)
    local def = PERF_PART[partId]
    if not def or not def.wear or level <= 0 or (wear or 0) < 0.5 then return 0 end
    local price = perfLevelPrice(classId, def.levels[level])
    return math.max(PERF.MAINT_MIN, math.ceil(price * wear / 100 * PERF.MAINT_FACTOR))
end
