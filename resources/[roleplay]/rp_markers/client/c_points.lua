--[[
    rp_markers / c_points.lua  (cliente)
    Mismo export que el servidor para que la logica de cliente de cada recurso (avisos "Pulsa E",
    distancias) use la posicion movida por un admin:

        local x, y, z = exports.rp_markers:placePoint("loc1", cfg.x, cfg.y, cfg.z)

    Las posiciones movidas llegan en el elementData sincronizado de resourceRoot (s_points.lua).
    Cuando cambian se dispara el evento de cliente rp:markers:moved (recurso, clave) para que el
    recurso dueno vuelva a pedir sus puntos.
]]

addEvent("rp:markers:moved")

local POINTS_DATA = "rp:markers:points"
local BASE_TOLERANCE = 0.5

function placePoint(key, x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local owner = sourceResource and getResourceName(sourceResource)
    local all = getElementData(resourceRoot, POINTS_DATA)
    local p = owner and type(key) == "string" and type(all) == "table" and all[owner .. ":" .. key]
    -- Solo si la base coincide con la config actual (si no, el servidor lo descarta)
    if p and x and getDistanceBetweenPoints3D(x, y, z, p[4], p[5], p[6]) <= BASE_TOLERANCE then
        return p[1], p[2], p[3]
    end
    return x, y, z
end

local function same(a, b)
    if not a or not b then return a == b end
    for i = 1, 6 do if a[i] ~= b[i] then return false end end
    return true
end

addEventHandler("onClientElementDataChange", resourceRoot, function(key, old, new)
    if key ~= POINTS_DATA then return end
    old, new = type(old) == "table" and old or {}, type(new) == "table" and new or {}
    local changed = {}
    for full, p in pairs(new) do if not same(p, old[full]) then changed[full] = true end end
    for full in pairs(old) do if not new[full] then changed[full] = true end end
    for full in pairs(changed) do
        local owner, k = full:match("^([^:]+):(.+)$")
        if owner then triggerEvent("rp:markers:moved", root, owner, k) end
    end
end)
