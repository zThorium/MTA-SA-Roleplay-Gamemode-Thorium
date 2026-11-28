--[[
    rp_ballistics / server / s_ballistics.lua
    Aplica el daño por calibre a los NPC del servidor que avisa el cliente del tirador.
    Valida: que es un ped vivo, que el tirador lleva esa arma, misma dimensión/interior, distancia y ritmo.
]]

addEvent("rp:ballistics:hit", true)

local lastHit = {}   -- [player] = tick

addEventHandler("rp:ballistics:hit", resourceRoot, function(ped, weapon, bodypart)
    local p = client
    if not isElement(ped) or getElementType(ped) ~= "ped" or isPedDead(ped) or isPedDead(p) then return end
    weapon, bodypart = tonumber(weapon), tonumber(bodypart)
    if not weapon or not BALLISTICS.SHOTS[weapon] or getPedWeapon(p) ~= weapon then return end
    if getElementDimension(p) ~= getElementDimension(ped) or getElementInterior(p) ~= getElementInterior(ped) then return end
    local x, y, z = getElementPosition(p)
    local px, py, pz = getElementPosition(ped)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > BALLISTICS.MAX_RANGE then return end
    -- ninguna arma pasa de ~20 balas/s: más rápido es un cliente trucado
    local now = getTickCount()
    if lastHit[p] and now - lastHit[p] < 40 then return end
    lastHit[p] = now

    local kill, health, armor = ballisticsHit(weapon, bodypart, getElementHealth(ped), getPedArmor(ped))
    if kill then
        killPed(ped, p, weapon, bodypart)
    else
        setPedArmor(ped, armor)
        setElementHealth(ped, health)
    end
end)

addEventHandler("onPlayerQuit", root, function() lastHit[source] = nil end)

-- Para pruebas y otros recursos: resultado de un impacto sin aplicarlo
function computeHit(weapon, bodypart, health, armor)
    return ballisticsHit(tonumber(weapon), tonumber(bodypart), tonumber(health) or 100, tonumber(armor) or 0)
end
