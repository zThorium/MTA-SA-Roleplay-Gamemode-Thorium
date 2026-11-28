--[[
    rp_ballistics / client / c_ballistics.lua
    Sustituye el daño de GTA de las armas de fuego de jugadores a NPC por el de BALLISTICS.
    Prioridad "low": corre después de los demás recursos, así respeta a los NPC que ya cancelan el daño
    (dependientes, aliados de misión, blancos del campo de tiro...).
    - NPC local (creado en este cliente, p. ej. peatones de rp_citizens): se aplica aquí.
    - NPC del servidor: se cancela el daño de GTA en todos los clientes y el del tirador avisa al servidor, que valida y aplica.
]]

local lastReport = {}   -- [ped] = tick

addEventHandler("onClientPedDamage", root, function(attacker, weapon, bodypart)
    if wasEventCancelled() or not BALLISTICS.SHOTS[weapon] then return end
    if not isElement(attacker) or getElementType(attacker) ~= "player" then return end
    local ped = source
    if isPedDead(ped) then return end
    cancelEvent()
    if isElementLocal(ped) then
        local kill, health = ballisticsHit(weapon, bodypart, getElementHealth(ped), 0)
        if kill then killPed(ped, attacker, weapon, bodypart) else setElementHealth(ped, health) end
    elseif attacker == localPlayer then
        local now = getTickCount()
        if lastReport[ped] and now - lastReport[ped] < BALLISTICS.REPORT_MS then return end
        lastReport[ped] = now
        triggerServerEvent("rp:ballistics:hit", resourceRoot, ped, weapon, bodypart)
    end
end, true, "low")

addEventHandler("onClientElementDestroy", root, function() lastReport[source] = nil end)
