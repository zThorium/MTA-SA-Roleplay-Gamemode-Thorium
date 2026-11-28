--[[
    rp_duty / s_config.lua  (compartido)

    Servicio genérico de facción: vestuario, uniforme y equipo por rol para los tipos de
    rp_factions que tienen duty = "rp_duty" en FACTION_TYPES (médicos, gobierno, mecánicos,
    noticias, transporte, logística, seguros, seguridad, concesionaria).
    Policía y bomberos siguen con su propio vestuario (rp_police, rp_firefighters).
]]

DUTY = {
    ELEMENT_DATA = "rp:factionDuty",   -- true/false en el jugador (lo lee rp_factions en el cliente)
    INTERACT_RADIUS = 1.6,             -- metros del vestuario para pulsar E
    COOLDOWN_MS = 800,                 -- entre acciones del panel
    MAX_LOADOUTS = 10,                 -- uniformes por facción
    MAX_ITEMS = 6,                     -- objetos distintos por uniforme
    MAX_AMOUNT = 20,                   -- cantidad máxima de cada objeto
    NAME_MIN = 2, NAME_MAX = 32,
    SKIN_MIN = 1, SKIN_MAX = 312,
    -- Skins que no existen en GTA SA (huecos de la lista)
    BAD_SKINS = { [3] = true, [4] = true, [5] = true, [6] = true, [8] = true, [42] = true, [65] = true, [74] = true,
        [86] = true, [119] = true, [149] = true, [208] = true, [273] = true, [289] = true },
    MARKER_COLOR = { 90, 170, 255 },
}

-- Garaje de facción (#105): vehículos comprados con los fondos de la facción
GARAGE = {
    INTERACT_RADIUS = 4.0,       -- metros del punto del garaje (a pie abre el panel, al volante guarda)
    SPAWN_CLEAR = 4.0,           -- la salida debe estar libre en este radio
    MAX_VEHICLES = 15,           -- por facción
    SELL_REFUND = 0.5,           -- al vender vuelve a los fondos este % del precio
    ABANDON_MIN = 15,            -- minutos sin nadie dentro: vuelve solo al garaje
    PLATE_PREFIX = "F",          -- matrícula F<id facción>-<id vehículo>
    MARKER_COLOR = { 90, 170, 255 },
    -- Catálogo: types = tipos de facción que lo pueden comprar ("*" = todos los que usan rp_duty)
    CATALOG = {
        { model = 482, name = "Furgoneta Burrito", price = 25000, types = { "*" } },
        { model = 413, name = "Furgoneta Pony",    price = 22000, types = { "*" } },
        { model = 416, name = "Ambulancia",        price = 60000, types = { "medicos" } },
        { model = 525, name = "Grua",              price = 45000, types = { "mecanicos" } },
        { model = 552, name = "Furgon de servicio", price = 30000, types = { "mecanicos", "gobierno" } },
        { model = 582, name = "Furgon de noticias", price = 40000, types = { "noticias" } },
        { model = 488, name = "Helicoptero de noticias", price = 250000, types = { "noticias" } },
        { model = 420, name = "Taxi",              price = 25000, types = { "transporte" } },
        { model = 438, name = "Taxi Cabbie",       price = 25000, types = { "transporte" } },
        { model = 431, name = "Autobus",           price = 80000, types = { "transporte" } },
        { model = 437, name = "Autobus de linea",  price = 90000, types = { "transporte" } },
        { model = 499, name = "Camion Benson",     price = 40000, types = { "logistica" } },
        { model = 414, name = "Camion Mule",       price = 35000, types = { "logistica" } },
        { model = 456, name = "Camion Yankee",     price = 50000, types = { "logistica" } },
        { model = 428, name = "Blindado",          price = 70000, types = { "seguridad" } },
        { model = 426, name = "Sedan Premier",     price = 30000, types = { "gobierno", "seguros", "concesionaria" } },
        { model = 409, name = "Limusina",          price = 80000, types = { "gobierno" } },
    },
}

function garageCatalogFor(kind)
    local out = {}
    for _, c in ipairs(GARAGE.CATALOG) do
        for _, t in ipairs(c.types) do
            if t == "*" or t == kind then out[#out + 1] = c break end
        end
    end
    return out
end

-- "id:n,id:n" <-> { { id = "id", amount = n }, ... }
function dutyParseItems(text)
    local list = {}
    for id, n in tostring(text or ""):gmatch("([%w_]+):(%d+)") do
        list[#list + 1] = { id = id, amount = tonumber(n) }
    end
    return list
end

function dutyFormatItems(list)
    local parts = {}
    for _, it in ipairs(list or {}) do parts[#parts + 1] = ("%s:%d"):format(it.id, it.amount) end
    return table.concat(parts, ",")
end

function dutyValidSkin(skin)
    skin = tonumber(skin)
    return skin ~= nil and skin == math.floor(skin) and skin >= DUTY.SKIN_MIN and skin <= DUTY.SKIN_MAX and not DUTY.BAD_SKINS[skin]
end
