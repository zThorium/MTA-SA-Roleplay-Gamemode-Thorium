--[[
    rp_wanted / c_crimes.lua
    Deteccion de delitos del jugador local. Los peatones y el trafico de
    rp_citizens existen solo en este cliente, asi que los delitos contra ellos
    (y contra las unidades de policia) se avisan desde aqui. El servidor aplica
    los puntos, la cola de 10 s por victima y el limite de avisos.
    Los delitos contra otros jugadores los detecta el servidor (onPlayerDamage).
]]

local sent = {}          -- [clave] = tick: evita repetir avisos dentro de la cola de GTA
local lastHitBy = {}     -- [vehiculo] = tick del ultimo dano causado por el jugador

local function keyOf(el)
    return (tostring(el):gsub("^userdata: ", ""))
end

-- /delitosdebug: muestra en el chat cada delito detectado y enviado al servidor
local debugOn = false
addCommandHandler("delitosdebug", function()
    debugOn = not debugOn
    outputChatBox("Depuracion de delitos " .. (debugOn and "activada." or "desactivada."), 245, 165, 36)
end)
local function dbg(fmt, ...)
    if debugOn then outputChatBox("[delitos] " .. fmt:format(...), 200, 200, 200) end
end

local function report(crime, victim, dontCare)
    local key = crime .. keyOf(victim)
    local now = getTickCount()
    if sent[key] and now - sent[key] < WANTED.QUEUE_TIME then return dbg("%s repetido (cola de 10 s)", crime) end
    sent[key] = now
    dbg("%s -> servidor", crime)
    triggerServerEvent("rp:wanted:crime", resourceRoot, crime, keyOf(victim), dontCare and true or false)
end

setTimer(function()
    local now = getTickCount()
    for k, t in pairs(sent) do if now - t > WANTED.QUEUE_TIME then sent[k] = nil end end
    for v, t in pairs(lastHitBy) do if not isElement(v) or now - t > 10000 then lastHitBy[v] = nil end end
end, 15000, 0)

local function myVehicle()
    local v = getPedOccupiedVehicle(localPlayer)
    if v and getVehicleController(v) == localPlayer then return v end
end

local function isCop(el)
    return getElementData(el, "rp:cop") == true
end

local function isCopCar(v)
    return getElementData(v, "rp:copCar") == true or (WANTED_POLICE_MODELS[getElementModel(v)] and isElementLocal(v) == false
        and getVehicleController(v) and getElementType(getVehicleController(v)) == "ped" and isCop(getVehicleController(v)))
end

local function active()
    return getElementData(localPlayer, "rp:characterId") and not isPedDead(localPlayer)
end

----------------------------------------------------------------
-- Peatones y policias
----------------------------------------------------------------
addEventHandler("onClientPedDamage", root, function(attacker, weapon)
    dbg("dano a ped: atacante=%s arma=%s", attacker and getElementType(attacker) or "nil", tostring(weapon))
    if not active() or not attacker then return end
    local byVehicle = false
    if attacker == myVehicle() then
        attacker, byVehicle = localPlayer, true
    end
    if attacker ~= localPlayer then return end
    local crime = wantedCrimeForPedDamage(weapon, isCop(source), byVehicle)
    if crime then report(crime, source, WANTED_DONT_CARE_SKINS[getElementModel(source)]) end
end)

-- Respaldo: muerte de un ped causada por el jugador o su vehiculo
addEventHandler("onClientPedWasted", root, function(killer, weapon)
    if not active() or not killer then return end
    local byVehicle = killer == myVehicle()
    if killer ~= localPlayer and not byVehicle then return end
    local crime = wantedCrimeForPedDamage(weapon, isCop(source), byVehicle)
    if crime then report(crime, source, WANTED_DONT_CARE_SKINS[getElementModel(source)]) end
end)

-- Apuntar con un arma de fuego a alguien
addEventHandler("onClientPlayerTarget", localPlayer, function(target)
    if not target or not active() then return end
    local t = getElementType(target)
    if t ~= "ped" then return end
    local weapon = getPedWeapon(localPlayer)
    if weapon < 22 or weapon > 38 or not getPedControlState(localPlayer, "aim_weapon") then return end
    report("aim_gun", target, WANTED_DONT_CARE_SKINS[getElementModel(target)])
end)

----------------------------------------------------------------
-- Vehiculos
----------------------------------------------------------------
-- Choques: solo cuenta si el jugador es el que embiste (va hacia el otro y no mas lento)
addEventHandler("onClientVehicleCollision", root, function(hit, force)
    local mine = myVehicle()
    if source ~= mine or not hit or not isElement(hit) or not active() then return end
    -- Atropello: el auto del jugador golpea a un peaton (o policia) a pie
    if getElementType(hit) == "ped" then
        local vx, vy, vz = getElementVelocity(mine)
        local kmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
        dbg("choque con ped a %d km/h", kmh)
        if kmh > 12 and not isPedDead(hit) then
            report(isCop(hit) and "cop_runover" or "ped_runover", hit, WANTED_DONT_CARE_SKINS[getElementModel(hit)])
        end
        return
    end
    if getElementType(hit) ~= "vehicle" then return end
    dbg("choque con vehiculo, fuerza %d", force)
    if force < 150 then return end
    local mx, my = getElementPosition(mine)
    local hx, hy = getElementPosition(hit)
    local vx, vy = getElementVelocity(mine)
    local ox, oy = getElementVelocity(hit)
    local mySpeed, otherSpeed = math.sqrt(vx * vx + vy * vy), math.sqrt(ox * ox + oy * oy)
    if (hx - mx) * vx + (hy - my) * vy <= 0 or mySpeed < otherSpeed * 0.7 then return end
    lastHitBy[hit] = getTickCount()
    if isCopCar(hit) then
        if force >= 250 then report("cop_car", hit) end
    elseif getVehicleController(hit) then
        report("car_hit", hit)
    end
end)

-- Disparos a un vehiculo
addEventHandler("onClientVehicleDamage", root, function(attacker, weapon)
    if attacker ~= localPlayer or not weapon or not active() then return end
    lastHitBy[source] = getTickCount()
    if weapon >= 22 and weapon <= 40 then
        report(isCopCar(source) and "cop_car" or "car_damage", source)
    end
end)

addEventHandler("onClientVehicleExplode", root, function()
    local t = lastHitBy[source]
    if not t or getTickCount() - t > 6000 or not active() then return end
    local vt = getVehicleType(source)
    report((vt == "Helicopter" or vt == "Plane") and "heli_destroy" or "car_destroy", source)
end)

-- Sacar a un conductor (trafico o policia) o llevarse una patrulla
addEventHandler("onClientVehicleStartEnter", root, function(player, seat)
    if player ~= localPlayer or seat ~= 0 or not active() then return end
    local driver = getVehicleController(source)
    if (driver and driver ~= localPlayer) or getElementData(source, "rp:copCar") then
        report("car_steal", source)
    end
end)

-- Explosiones provocadas por el jugador
addEventHandler("onClientExplosion", root, function()
    if source == localPlayer and active() then report("explosion", source) end
end)

-- Exceso de velocidad con la policia cerca (GTA solo lo cuenta si te ven)
setTimer(function()
    local v = myVehicle()
    if not v or not active() then return end
    local vx, vy, vz = getElementVelocity(v)
    if math.sqrt(vx * vx + vy * vy + vz * vz) * 180 < 120 then return end
    local x, y, z = getElementPosition(v)
    for _, el in ipairs(getElementsWithinRange(x, y, z, 35, "vehicle")) do
        if el ~= v and getElementData(el, "rp:copCar") then return report("speeding", localPlayer) end
    end
end, 1000, 0)
