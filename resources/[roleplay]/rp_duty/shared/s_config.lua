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
