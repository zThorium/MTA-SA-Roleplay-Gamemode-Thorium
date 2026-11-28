--[[
    rp_turbus · servidor

    Quita el edificio original de Unity Station (y su LOD, detalles y los árboles/faroles que estorban) para todos
    los jugadores y pone los props nativos (conos, bancas). El terminal en sí (modelos propios) lo crea cada cliente
    en c_terminal.lua: los IDs de engineRequestModel son locales de cada cliente.

    Export:
        getTerminalInfo() -> { origin, hallBox, removed = n, props = n }
]]

local C = TURBUS
local props = {}

local function applyRemovals(remove)
    for _, r in ipairs(C.REMOVE) do
        if remove then
            removeWorldModel(r[1], r[2], r[3], r[4], r[5])
        else
            restoreWorldModel(r[1], r[2], r[3], r[4], r[5])
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    applyRemovals(true)
    for _, p in ipairs(C.PROPS) do
        local obj = createObject(p[1], p[2], p[3], p[4], 0, 0, p[5] or 0)
        if obj then
            setElementFrozen(obj, true)
            props[#props + 1] = obj
        end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    applyRemovals(false)
end)

function getTerminalInfo()
    local hb = C.HALL_BOX
    return {
        origin = { C.ORIGIN.x, C.ORIGIN.y, C.ORIGIN.z },
        hallBox = { hb.x0, hb.y0, hb.z0, hb.x1, hb.y1, hb.z1 },
        removed = #C.REMOVE,
        props = #props,
    }
end
