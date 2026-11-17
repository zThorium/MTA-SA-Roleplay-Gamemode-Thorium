--[[
    rp_vehicles / c_vehicles.lua
    Tecla L: abrir / cerrar tu vehiculo mas cercano (con parpadeo de luces).
]]

addEvent("rp:veh:lockFx", true)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("l", "down", function()
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        if not getElementData(localPlayer, "rp:characterId") or getElementData(localPlayer, "rp:downed") then return end
        triggerServerEvent("rp:veh:toggleLock", resourceRoot)
    end)
end)

addEventHandler("rp:veh:lockFx", resourceRoot, function(vehicle)
    if not isElement(vehicle) then return end
    playSoundFrontEnd(5)
    local state = getVehicleOverrideLights(vehicle)
    setVehicleOverrideLights(vehicle, 2)
    setTimer(function()
        if isElement(vehicle) then setVehicleOverrideLights(vehicle, state) end
    end, 400, 1)
end)
