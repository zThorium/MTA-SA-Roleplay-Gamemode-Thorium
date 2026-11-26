--[[
    rp_ammunation / s_ammunation.lua
    Puerta de entrada/salida (E) y vendedor. La venta la hace rp_shops (addTempShop):
    el precio, el dinero y el peso del inventario los valida alla.
]]
addEvent("rp:ammu:door", true)

local function spawnLocation(loc)
    local dim = ammuDimension(loc)
    local entryM = createMarker(loc.x, loc.y, loc.z - 1, "cylinder", 1.2, 255, 140, 0, 120)
    exports.rp_markers:setMarkerStyle(entryM, { icon = "gun", label = loc.name or "Ammu-Nation" })
    createBlip(loc.x, loc.y, loc.z, 18, 2, 255, 255, 255, 255, 0, 300)
    local e = AMMU.ENTRY
    local exitM = createMarker(e.x, e.y, e.z - 1, "cylinder", 1.2, 255, 140, 0, 120)
    setElementInterior(exitM, AMMU.INTERIOR)
    setElementDimension(exitM, dim)
    exports.rp_markers:setMarkerStyle(exitM, { icon = "exit", label = "Salir" })

    local c = AMMU.CLERK
    local ped = createPed(c.skin, c.x, c.y, c.z, c.rot)
    setElementFrozen(ped, true)
    setElementInterior(ped, AMMU.INTERIOR)
    setElementDimension(ped, dim)
    loc.ped = ped
    exports.rp_shops:addTempShop(ped, loc.name, AMMU.CATALOG)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, loc in ipairs(AMMU.LOCATIONS) do spawnLocation(loc) end
end)

-- rp_shops reiniciado: las tiendas temporales se pierden, se vuelven a registrar
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rp_shops" then return end
    for _, loc in ipairs(AMMU.LOCATIONS) do
        if isElement(loc.ped) then exports.rp_shops:addTempShop(loc.ped, loc.name, AMMU.CATALOG) end
    end
end)

addEventHandler("rp:ammu:door", resourceRoot, function(id)
    local player = client
    if not exports.rp_characters:getPlayerCharacterId(player) or getElementData(player, "rp:downed") then return end
    if isPedInVehicle(player) or isPedDead(player) then return end
    local loc
    for _, l in ipairs(AMMU.LOCATIONS) do if l.id == id then loc = l end end
    if not loc then return end

    local px, py, pz = getElementPosition(player)
    local e = AMMU.ENTRY
    if getElementInterior(player) == AMMU.INTERIOR and getElementDimension(player) == ammuDimension(loc) then
        if getDistanceBetweenPoints3D(px, py, pz, e.x, e.y, e.z) > AMMU.DOOR_DISTANCE + 0.5 then return end
        setElementInterior(player, 0, loc.x, loc.y, loc.z)
        setElementDimension(player, 0)
    else
        if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then return end
        if getDistanceBetweenPoints3D(px, py, pz, loc.x, loc.y, loc.z) > AMMU.DOOR_DISTANCE + 0.5 then return end
        setElementInterior(player, AMMU.INTERIOR, e.x, e.y, e.z)
        setElementDimension(player, ammuDimension(loc))
        setElementRotation(player, 0, 0, e.rot)
    end
end)
