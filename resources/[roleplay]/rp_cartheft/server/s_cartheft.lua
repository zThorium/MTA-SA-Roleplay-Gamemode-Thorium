--[[
    rp_cartheft / s_cartheft.lua  (servidor)

    Robo de vehiculos con dueno que estan cerrados:
      1. Junto a la puerta del conductor, con una ganzua (rp_shops), E o "Usar" en el inventario
         abre el minijuego de la cerradura. Si fallas, la ganzua puede romperse.
      2. Al abrirse se dispara la alarma (elementData rp:carAlarm: sonido y luces en todos los clientes).
      3. Al volante, J (motor de rp_vehicles) sin llave abre el minijuego del puente.
      4. Con el motor en marcha, dos bocinazos apagan la alarma: robo completo.
    Si un policia (jugador, IA o patrulla) te ve durante el robo, rp_wanted da una estrella (car_steal).
    No guarda nada propio: la cerradura la persiste rp_vehicles (setVehicleLockState).

    Exports (servidor):
        isPlayerStealing(player)    -> true si esta en mitad de un robo
        isVehicleAlarmOn(vehicle)   -> true si la alarma suena
]]

local sessions = {}   -- [player] = { vehicle, stage = "pick"|"open"|"wire"|"horn", started, seen, characterId }
local busy = {}       -- [vehicle] = player   (un ladron por vehiculo a la vez)
local alarms = {}     -- [vehicle] = timer
local cooldown = {}   -- [player] = tick
local counted = {}    -- [characterId .. ":" .. vehicleId] = tick  (logro: un mismo auto cuenta una vez por hora)
local finish          -- robo completo (definida abajo)

addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:onItemUse", false)
addEvent("rp:veh:onEngineNoKey", false)
addEvent("rp:cartheft:try", true)
addEvent("rp:cartheft:pickResult", true)
addEvent("rp:cartheft:wireResult", true)
addEvent("rp:cartheft:horn", true)
addEvent("rp:cartheft:copSeen", true)
addEvent("rp:cartheft:cancel", true)

local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function log(msg, level) outputDebugString("[rp_cartheft] " .. msg, level or 3) end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < CARTHEFT.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

-- Recursos opcionales: si no estan en marcha, ese bloqueo no aplica
-- estandar:dep-opcional rp_police arranca despues (esposado); sin el no hay esposas (pcall)
-- estandar:dep-opcional rp_missions arranca despues (en mision); sin el nadie esta en mision (pcall)
local function try(fn, ...)
    local ok, r = pcall(fn, ...)
    return ok and r
end

local function blockedReason(p)
    if exports.rp_injury:isPlayerDowned(p) then return "No puedes hacer eso ahora." end
    if try(function() return exports.rp_police:isCuffed(p) end) then return "Estas esposado." end
    if try(function() return exports.rp_missions:getPlayerMission(p) end) then return "Estas en una mision." end
    return nil
end

local function near(p, vehicle, radius)
    if not isElement(vehicle) then return false end
    if getElementDimension(p) ~= getElementDimension(vehicle) or getElementInterior(p) ~= getElementInterior(vehicle) then return false end
    local px, py, pz = getElementPosition(p)
    local vx, vy, vz = getElementPosition(vehicle)
    return getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= (radius or CARTHEFT.REACH)
end

local function hasKey(p, vehicle)
    local id = exports.rp_vehicles:getVehicleDatabaseId(vehicle)
    return id and exports.rp_inventory:hasItem(p, "vkey:" .. id, 1)
end

----------------------------------------------------------------
-- Alarma
----------------------------------------------------------------
local function stopAlarm(vehicle, chirp)
    if isTimer(alarms[vehicle]) then killTimer(alarms[vehicle]) end
    alarms[vehicle] = nil
    if isElement(vehicle) and getElementData(vehicle, "rp:carAlarm") then
        setElementData(vehicle, "rp:carAlarm", false)
        if chirp then triggerClientEvent(root, "rp:cartheft:chirp", resourceRoot, vehicle) end
    end
end

local function startAlarm(vehicle)
    stopAlarm(vehicle)
    setElementData(vehicle, "rp:carAlarm", true)
    alarms[vehicle] = setTimer(function()
        alarms[vehicle] = nil
        -- se agoto con el motor ya en marcha: el robo esta hecho igual
        local p = busy[vehicle]
        if p and sessions[p] and sessions[p].stage == "horn" then return finish(p) end
        stopAlarm(vehicle)
    end, CARTHEFT.ALARM_MS, 1)
end

----------------------------------------------------------------
-- Sesiones
----------------------------------------------------------------
local function endSession(p, reason)
    local s = sessions[p]
    if not s then return end
    sessions[p] = nil
    if busy[s.vehicle] == p then busy[s.vehicle] = nil end
    if isElement(p) then
        if s.stage == "pick" and not isPedInVehicle(p) then setPedAnimation(p) end
        triggerClientEvent(p, "rp:cartheft:stage", resourceRoot, false)
        if reason then notify(p, reason, "warning") end
    end
end

local function setStage(p, stage)
    local s = sessions[p]
    s.stage, s.started = stage, getTickCount()
    triggerClientEvent(p, "rp:cartheft:stage", resourceRoot, stage, s.vehicle)
end

-- Un policia te sorprendio: una estrella (rp_wanted decide; no cuenta en mision ni para policias de servicio)
local function caught(p)
    local s = sessions[p]
    if not s or s.seen then return end
    s.seen = true
    local id = exports.rp_vehicles:getVehicleDatabaseId(s.vehicle) or 0
    if try(function() return exports.rp_wanted:reportCrime(p, "car_steal", "veh:" .. id, false, "police") end) then
        notify(p, "¡Un policia te sorprendio robando el vehiculo!", "error")
        log(("%s sorprendido robando el vehiculo %s"):format(getPlayerName(p), tostring(id)))
    end
end

-- Policias jugadores y patrullas cerca (los policias IA solo existen en el cliente: rp:cartheft:copSeen)
local function playerCopNear(p, radius)
    local x, y, z = getElementPosition(p)
    local dim = getElementDimension(p)
    for _, el in ipairs(getElementsWithinRange(x, y, z, radius, "player")) do
        if el ~= p and not isPedDead(el) and getElementDimension(el) == dim
            and try(function() return exports.rp_wanted:isWantedPolice(el) end) then
            return true
        end
    end
    return false
end

setTimer(function()
    for p, s in pairs(sessions) do
        if not isElement(s.vehicle) then
            endSession(p, "El vehiculo ya no esta.")
        elseif not s.seen then
            local radius = getElementData(s.vehicle, "rp:carAlarm") and CARTHEFT.COP_RADIUS_ALARM or CARTHEFT.COP_RADIUS
            if playerCopNear(p, radius) then caught(p) end
        end
    end
end, 1000, 0)

addEventHandler("rp:cartheft:copSeen", resourceRoot, function()
    local s = sessions[client]
    if s and near(client, s.vehicle, 8) then caught(client) end
end)

----------------------------------------------------------------
-- 1. Forzar la cerradura
----------------------------------------------------------------
local function tryPick(p, vehicle)
    if sessions[p] or not characterOf(p) or not takeCooldown(p) then return end
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return end
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end
    if isPedInVehicle(p) then return notify(p, "Bajate del vehiculo.", "warning") end
    if not near(p, vehicle) then return notify(p, "Acercate a la puerta del conductor.", "warning") end
    if not CARTHEFT.TYPES[getVehicleType(vehicle)] or not exports.rp_vehicles:getVehicleOwner(vehicle) then
        return notify(p, "Este vehiculo no tiene una cerradura que puedas forzar.", "warning")
    end
    if not isVehicleLocked(vehicle) then return notify(p, "Ese vehiculo ya esta abierto.", "info") end
    if hasKey(p, vehicle) then return notify(p, "Tienes la llave: abrelo con L.", "info") end
    if busy[vehicle] then return notify(p, "Alguien ya esta forzando ese vehiculo.", "warning") end
    if not exports.rp_inventory:hasItem(p, CARTHEFT.ITEM, 1) then
        return notify(p, "Necesitas una ganzua. Las venden en las tiendas 24/7.", "warning")
    end
    sessions[p] = { vehicle = vehicle, characterId = characterOf(p) }
    busy[vehicle] = p
    setPedAnimation(p, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
    setStage(p, "pick")
end

addEventHandler("rp:cartheft:try", resourceRoot, function(vehicle) tryPick(client, vehicle) end)

-- Usar la ganzua desde el inventario: el vehiculo cerrado mas cercano
addEventHandler("rp:onItemUse", root, function(itemId)
    if itemId ~= CARTHEFT.ITEM then return end
    local p = source
    local x, y, z = getElementPosition(p)
    local best, bestD = nil, CARTHEFT.REACH
    for _, v in ipairs(getElementsWithinRange(x, y, z, CARTHEFT.REACH, "vehicle")) do
        local d = getDistanceBetweenPoints3D(x, y, z, getElementPosition(v))
        if d < bestD and isVehicleLocked(v) and getElementDimension(v) == getElementDimension(p) then best, bestD = v, d end
    end
    if not best then return notify(p, "Usala junto a la puerta de un vehiculo cerrado.", "warning") end
    tryPick(p, best)
end)

addEventHandler("rp:cartheft:pickResult", resourceRoot, function(ok)
    local p = client
    local s = sessions[p]
    if not s or s.stage ~= "pick" then return end
    setPedAnimation(p)
    if ok ~= true then
        endSession(p)
        if math.random() < CARTHEFT.BREAK_CHANCE and exports.rp_inventory:takeItem(p, CARTHEFT.ITEM, 1) then
            return notify(p, "La ganzua se rompio dentro de la cerradura.", "error")
        end
        return notify(p, "No lograste abrirla. La ganzua sigue entera.", "warning")
    end
    -- validar: tiempo creible, aun junto al vehiculo, aun con ganzua y aun cerrado
    if getTickCount() - s.started < CARTHEFT.PICK.MIN_MS or not near(p, s.vehicle)
        or not exports.rp_inventory:hasItem(p, CARTHEFT.ITEM, 1) or not isVehicleLocked(s.vehicle) then
        return endSession(p, "La cerradura no cedio.")
    end
    exports.rp_vehicles:setVehicleLockState(s.vehicle, false)
    startAlarm(s.vehicle)
    setStage(p, "open")
    notify(p, "¡Abierta! La alarma se disparo: sube y haz el puente rapido.", "success")
end)

----------------------------------------------------------------
-- 2. Puente: rp_vehicles avisa de que intentas encender sin llave
----------------------------------------------------------------
addEventHandler("rp:veh:onEngineNoKey", root, function(vehicle)
    local p = source
    local s = sessions[p]
    -- tambien sirve en un auto que forzo otro (o cuya sesion se corto): basta con que lo hayan forzado
    if not s and getElementData(vehicle, "rp:carAlarm") and not busy[vehicle] and characterOf(p) then
        sessions[p] = { vehicle = vehicle, characterId = characterOf(p), stage = "open", started = getTickCount() }
        busy[vehicle] = p
        s = sessions[p]
    end
    if not s or s.vehicle ~= vehicle or (s.stage ~= "open" and s.stage ~= "wire") then return end
    cancelEvent()
    if blockedReason(p) then return end
    setStage(p, "wire")
end)

addEventHandler("rp:cartheft:wireResult", resourceRoot, function(ok)
    local p = client
    local s = sessions[p]
    if not s or s.stage ~= "wire" then return end
    if ok ~= true then
        s.stage = "open"
        triggerClientEvent(p, "rp:cartheft:stage", resourceRoot, "open", s.vehicle)
        return notify(p, "Soltaste los cables. Pulsa J para intentarlo otra vez.", "warning")
    end
    local v = getPedOccupiedVehicle(p)
    if v ~= s.vehicle or getVehicleController(v) ~= p or getTickCount() - s.started < CARTHEFT.WIRE.MIN_MS then
        return endSession(p, "El puente no funciono.")
    end
    exports.rp_vehicles:setVehicleHotwired(v, true)
    if getElementData(v, "rp:carAlarm") then
        setStage(p, "horn")
        notify(p, "¡Motor en marcha! Toca la bocina dos veces para apagar la alarma.", "success")
    else
        finish(p)   -- la alarma ya se apago sola: robo completo
    end
end)

----------------------------------------------------------------
-- 3. Dos bocinazos apagan la alarma: robo completo
----------------------------------------------------------------
function finish(p)
    local s = sessions[p]
    if not s then return end
    local v = s.vehicle
    stopAlarm(v, true)
    endSession(p)
    notify(p, "Alarma apagada. El vehiculo es tuyo... por ahora.", "success")
    try(function() return exports.rp_levels:giveXP(p, CARTHEFT.XP, "Robo de vehiculo") end)
    -- logro: solo autos de otro personaje y un mismo auto una vez por hora
    local id = exports.rp_vehicles:getVehicleDatabaseId(v)
    local owner = exports.rp_vehicles:getVehicleOwner(v)
    local key = s.characterId .. ":" .. tostring(id)
    local now = getTickCount()
    if id and owner ~= s.characterId and (not counted[key] or now - counted[key] > 3600000) then
        counted[key] = now
        triggerEvent("rp:achievements:progress", p, "cars_stolen", 1)
    end
    log(("%s robo el vehiculo %s"):format(getPlayerName(p), tostring(id)))
end

addEventHandler("rp:cartheft:horn", resourceRoot, function()
    local p = client
    local s = sessions[p]
    if not s or s.stage ~= "horn" then return end
    local v = getPedOccupiedVehicle(p)
    if v ~= s.vehicle or getVehicleController(v) ~= p or not getVehicleEngineState(v) then return end
    finish(p)
end)

-- El jugador sale con Esc del minijuego
addEventHandler("rp:cartheft:cancel", resourceRoot, function()
    local s = sessions[client]
    if not s then return end
    if s.stage == "pick" then
        endSession(client, "Dejaste la cerradura.")
    elseif s.stage == "wire" then
        s.stage = "open"
        triggerClientEvent(client, "rp:cartheft:stage", resourceRoot, "open", s.vehicle)
    end
end)

-- Al subir al auto forzado: guia para el puente
addEventHandler("onVehicleEnter", root, function(p, seat)
    local s = sessions[p]
    if s and s.vehicle == source and seat == 0 and s.stage == "open" then
        notify(p, "Pulsa J para hacer el puente.", "info")
    end
end)

-- Te bajas en mitad del puente o de la bocina: la sesion sigue (vuelves a subir y sigues)
addEventHandler("onVehicleExit", root, function(p)
    local s = sessions[p]
    if s and s.vehicle == source and (s.stage == "wire" or s.stage == "horn") then
        if s.stage == "wire" then s.stage = "open" end
        triggerClientEvent(p, "rp:cartheft:stage", resourceRoot, s.stage, s.vehicle)
    end
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("rp:onCharacterLogout", root, function() endSession(source) end)
addEventHandler("rp:onPlayerDowned", root, function() endSession(source) end)
addEventHandler("onPlayerWasted", root, function() endSession(source) end)
addEventHandler("onPlayerQuit", root, function() endSession(source); cooldown[source] = nil end)

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    if isTimer(alarms[source]) then killTimer(alarms[source]) end
    alarms[source] = nil
    local p = busy[source]
    if p then endSession(p, "El vehiculo ya no esta.") end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(sessions) do endSession(p) end
    for v in pairs(alarms) do stopAlarm(v) end
    -- alarmas que quedaron de un reinicio anterior
    for _, v in ipairs(getElementsByType("vehicle")) do
        if getElementData(v, "rp:carAlarm") then setElementData(v, "rp:carAlarm", false) end
    end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function isPlayerStealing(p) return sessions[p] ~= nil end
function isVehicleAlarmOn(v) return isElement(v) and getElementData(v, "rp:carAlarm") == true end
