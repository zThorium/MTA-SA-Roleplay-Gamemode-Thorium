--[[
    rp_factionduty / s_config.lua  (compartido cliente/servidor)

    Servicio genérico de facción (#104): vestuario, uniforme y equipo por rol para los tipos
    de FACTION_TYPES (rp_factions) con duty = "rp_factionduty". Policía, bomberos y médicos
    llevan su propio servicio y no pasan por aquí.
]]

FDUTY = {
    INTERACT_RADIUS = 1.6,      -- metros al punto del vestuario para la tecla E
    PANEL_RADIUS = 3.0,         -- el servidor revalida con algo de margen
    MAX_LOADOUTS = 8,           -- equipos por facción
    MAX_ITEMS = 4,              -- objetos distintos por equipo
    NAME_MIN = 2, NAME_MAX = 24,
    COOLDOWN = 600,             -- ms entre acciones del panel
    COLOR = { 76, 154, 255 },   -- color del marcador (autoridad / trámite de facción)

    -- Skins válidas para uniformes (MTA 1.6: 0-312 menos los huecos del juego)
    INVALID_SKINS = { [3] = true, [4] = true, [5] = true, [6] = true, [8] = true, [42] = true, [65] = true,
        [74] = true, [86] = true, [119] = true, [149] = true, [208] = true, [273] = true, [289] = true },
    MAX_SKIN = 312,

    --[[
        Objetos que un líder puede poner en un equipo, por tipo de facción, con el máximo por equipo.
        "*" vale para todos los tipos. Solo equipo de trabajo: nada que se coma o se venda, porque lo
        gastado de servicio no se devuelve. Al crear el recurso de un sistema (mecánicos, noticias...)
        se añaden aquí sus herramientas.
    ]]
    ITEMS = {
        ["*"]     = {},
        gobierno  = { wpn_colt45 = 1, ammo_pistol = 34, vest = 1 },     -- escoltas
        seguridad = { wpn_colt45 = 1, ammo_pistol = 34, vest = 1 },
    },
}

function fdutyIsValidSkin(id)
    id = tonumber(id)
    return id ~= nil and id == math.floor(id) and id >= 0 and id <= FDUTY.MAX_SKIN and not FDUTY.INVALID_SKINS[id]
end

-- Máximo de un objeto en un equipo de ese tipo de facción (0 = no permitido)
function fdutyItemMax(factionType, itemId)
    local own = FDUTY.ITEMS[factionType]
    return (own and own[itemId]) or FDUTY.ITEMS["*"][itemId] or 0
end

-- Lista { id = max } de los objetos permitidos para un tipo
function fdutyAllowedItems(factionType)
    local out = {}
    for id, n in pairs(FDUTY.ITEMS["*"]) do out[id] = n end
    for id, n in pairs(FDUTY.ITEMS[factionType] or {}) do out[id] = n end
    return out
end
