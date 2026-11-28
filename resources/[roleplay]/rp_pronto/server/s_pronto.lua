--[[
    rp_pronto · servidor

    Quita la gasolinera original de Idlewood (laepetrol1a y su LOD) para todos los jugadores y la restaura al
    parar. La bencinera nueva (modelos propios y muebles del interior) la crea cada cliente en c_pronto.lua:
    los IDs de engineRequestModel son locales de cada cliente.

    Export:
        getStationInfo() -> { origin, shopBox, door, removed = n, props = n }
]]

local C = PRONTO

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
end)

addEventHandler("onResourceStop", resourceRoot, function()
    applyRemovals(false)
end)

function getStationInfo()
    local b = C.SHOP_BOX
    return {
        origin = { C.ORIGIN.x, C.ORIGIN.y, C.ORIGIN.z },
        shopBox = { b.x0, b.y0, b.z0, b.x1, b.y1, b.z1 },
        door = { C.DOOR.x, C.DOOR.y, C.DOOR.z },
        removed = #C.REMOVE,
        props = type(PRONTO_PROPS) == "table" and #PRONTO_PROPS or 0,
    }
end
