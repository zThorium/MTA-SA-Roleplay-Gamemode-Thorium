--[[
    rp_admin / s_admin.lua
    Herramientas de administracion. Por ahora: /freecam (solo super admin, nivel 3).
    En freecam, F teletransporta al punto de la camara (mismo interior y dimension).
]]

local LEVEL_SUPER = 3

local function isSuper(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= LEVEL_SUPER end

local freecamActive = {}

addCommandHandler("freecam", function(player)
    if not isSuper(player) then
        return exports.rp_notify:notify(player, "El freecam es solo para super administradores.", "error")
    end
    triggerClientEvent(player, "rp:admin:freecam", resourceRoot)
end)

addEvent("rp:admin:freecam:active", true)
addEventHandler("rp:admin:freecam:active", resourceRoot, function(active)
    if not client or not isSuper(client) then return end
    freecamActive[client] = active == true
end)

addEvent("rp:admin:freecam:teleport", true)
addEventHandler("rp:admin:freecam:teleport", resourceRoot, function(x, y, z)
    local player = client
    if not player then return end
    if not isSuper(player) or not freecamActive[player] then return end

    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z
        or math.abs(x) >= 30000 or math.abs(y) >= 30000 or z < -100 or z > 5000 then
        exports.rp_notify:notify(player, "Posicion del freecam invalida.", "error")
        return
    end

    local interior = getElementInterior(player)
    local dimension = getElementDimension(player)
    local vehicle = getPedOccupiedVehicle(player)

    if vehicle and getVehicleController(vehicle) == player then
        setElementInterior(vehicle, interior)
        setElementDimension(vehicle, dimension)
        setElementPosition(vehicle, x, y, z + 1)
        setElementVelocity(vehicle, 0, 0, 0)
        for _, occupant in pairs(getVehicleOccupants(vehicle)) do
            setElementInterior(occupant, interior)
            setElementDimension(occupant, dimension)
        end
    else
        if vehicle then removePedFromVehicle(player) end
        setElementInterior(player, interior)
        setElementDimension(player, dimension)
        setElementPosition(player, x, y, z)
    end

    outputServerLog(("[rp_admin] %s uso freecam-tp a %.1f, %.1f, %.1f (int %d, dim %d)")
        :format(getPlayerName(player), x, y, z, interior, dimension))

    freecamActive[player] = false
    triggerClientEvent(player, "rp:admin:freecam:teleported", resourceRoot)
    triggerClientEvent(player, "rp:admin:freecam", resourceRoot)   -- sale del freecam
    exports.rp_notify:notify(player, "Teletransportado al punto del freecam.", "success")
end)

addEventHandler("onPlayerQuit", root, function() freecamActive[source] = nil end)
