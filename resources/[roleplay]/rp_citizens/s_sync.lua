--[[
    rp_citizens / s_sync.lua
    Retransmite el trafico y los peatones que ve el CONDUCTOR de un vehiculo a sus pasajeros, para que
    todos los ocupantes vean lo mismo (el trafico es local a cada cliente). Solo hace de relevo:
      - acepta paquetes del conductor del vehiculo (asiento 0) y nada mas,
      - limita la frecuencia (como mucho uno cada 150 ms por conductor) y el tamano,
      - valida que todo sean numeros y los reenvia solo a los demas jugadores del mismo vehiculo.
    Coste: ~4 paquetes por segundo y por vehiculo con pasajeros, de unos 1-2 KB cada uno.
]]

addEvent("rp:citizens:snap", true)

local MAX_NUMBERS = 22 * 28      -- 28 entidades como maximo (22 numeros cada una)
local lastSnap = {}              -- [conductor] = tick del ultimo paquete

addEventHandler("rp:citizens:snap", resourceRoot, function(list)
    local driver = client
    if not isElement(driver) or type(list) ~= "table" or #list > MAX_NUMBERS or #list % 22 ~= 0 then return end
    local veh = getPedOccupiedVehicle(driver)
    if not veh or getVehicleOccupant(veh, 0) ~= driver then return end
    local now = getTickCount()
    if now - (lastSnap[driver] or 0) < 150 then return end
    lastSnap[driver] = now
    for i = 1, #list do
        local v = list[i]
        if type(v) ~= "number" or v ~= v or math.abs(v) > 100000 then return end
    end
    local targets = {}
    for _, occupant in pairs(getVehicleOccupants(veh)) do
        if occupant ~= driver and getElementType(occupant) == "player" then targets[#targets + 1] = occupant end
    end
    if #targets > 0 then triggerClientEvent(targets, "rp:citizens:snapRecv", resourceRoot, list) end
end)

addEventHandler("onPlayerQuit", root, function() lastSnap[source] = nil end)
