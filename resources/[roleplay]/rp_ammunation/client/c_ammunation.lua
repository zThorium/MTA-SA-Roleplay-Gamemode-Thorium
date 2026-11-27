--[[
    rp_ammunation / c_ammunation.lua
    Tecla E en la puerta (fuera o dentro). El servidor vuelve a comprobar todo.
]]
local sw, sh = guiGetScreenSize()

local function nearbyDoor()
    local px, py, pz = getElementPosition(localPlayer)
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for _, loc in ipairs(AMMU.LOCATIONS) do
        local x, y, z, ok = loc.x, loc.y, loc.z, int == 0 and dim == 0
        if int == AMMU.INTERIOR and dim == ammuDimension(loc) then
            x, y, z, ok = AMMU.ENTRY.x, AMMU.ENTRY.y, AMMU.ENTRY.z, true
        end
        if ok and getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= AMMU.DOOR_DISTANCE then return loc end
    end
end

addEvent("rp:markers:moved")
-- Un admin movio una puerta: recalcular las posiciones (rp_markers)
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then ammuResolvePoints() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    ammuResolvePoints()
    bindKey("e", "down", function()
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isPedInVehicle(localPlayer) then return end
        local loc = nearbyDoor()
        if loc then triggerServerEvent("rp:ammu:door", resourceRoot, loc.id) end
    end)
end)

addEventHandler("onClientRender", root, function()
    if isCursorShowing() or not nearbyDoor() then return end
    local text = "Pulsa E para entrar / salir"
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (sw - w) / 2, sh - 190
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)
