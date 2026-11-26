--[[
    rp_vehicles / s_vehicles.lua
    Vehiculos con dueno (tabla vehicles). Se cargan al iniciar el servidor con
    su tuning, se guardan al salir del vehiculo, cada 5 minutos y al detener
    el recurso.

    Llaves: cada vehiculo tiene una llave en el inventario ("vkey:<id>").
    Con la llave se abre / cierra desde fuera (L) y se enciende el motor (J o
    /toggleengine). Cualquiera puede subirse a un vehiculo abierto, pero sin
    la llave no arranca.

    Exports (servidor):
        createOwnedVehicle(player, model, color, x, y, z, rz) -> vehicle | false
        countOwnedVehicles(characterId)                       -> n
        getVehicleOwner(vehicle)                              -> characterId | false
        getVehicleDatabaseId(vehicle)                         -> id | false
        saveVehicle(vehicle)
]]

local vehicles = {}    -- [vehicle] = { id, ownerId, locked, engine, handbrake, clamped, plate, model }
local byId = {}        -- [id] = vehicle

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onItemUse", false)
addEvent("rp:veh:toggleLock", true)
addEvent("rp:veh:engine", true)
addEvent("rp:veh:handbrake", true)
addEvent("rp:veh:indicator", true)

function db() return exports.rp_database:getConnection() end
function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
function displayName(p) return (getPlayerName(p):gsub("_", " ")) end
function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

-- Policia = miembro de una facción de tipo policía (API central de rp_factions)
-- estandar:dep-opcional rp_factions arranca después que rp_vehicles; sin él nadie es policía (pcall)
function isPolice(p)
    local ok, yes = pcall(function() return exports.rp_factions:isPlayerInFaction(p, VEHICLES.POLICE_FACTION_TYPE) end)
    return ok and yes == true
end

function getVehicleData(vehicle) return vehicles[vehicle] end
function getVehicleById(id) return byId[tonumber(id)] end

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

function hasVehicleKey(player, vehicleId)
    if not resourceRunning("rp_inventory") then return false end
    return exports.rp_inventory:hasItem(player, vehicleKeyItem(vehicleId), 1)
end

function vehicleSpeedKmh(vehicle)
    local vx, vy, vz = getElementVelocity(vehicle)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

function distanceTo(a, b)
    if getElementDimension(a) ~= getElementDimension(b) or getElementInterior(a) ~= getElementInterior(b) then return math.huge end
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
end

local function randomPlate()
    local letters = "ABCDEFGHJKLMNPRSTUVWXYZ"
    local plate = ""
    for i = 1, 3 do local n = math.random(#letters) plate = plate .. letters:sub(n, n) end
    return plate .. " " .. math.random(100, 999)
end

local function applyColor(vehicle, color)
    local c = type(color) == "string" and fromJSON(color) or color
    if type(c) == "table" and #c >= 3 then
        setVehicleColor(vehicle, c[1], c[2], c[3], c[1], c[2], c[3])
    end
end

-- Congelado si tiene el freno de mano puesto o un cepo de la policia
function updateFrozen(vehicle)
    local data = vehicles[vehicle]
    if not data then return end
    setElementFrozen(vehicle, data.handbrake or data.clamped)
    setElementData(vehicle, "rp:handbrake", data.handbrake)
    setElementData(vehicle, "rp:clamp", data.clamped)
end

local function labelKey(vehicle)
    local data = vehicles[vehicle]
    if not data or not resourceRunning("rp_inventory") then return end
    exports.rp_inventory:setItemLabel(vehicleKeyItem(data.id), "Llave " .. data.plate,
        ("Llave del %s con matricula %s. Usala cerca del vehiculo para abrirlo o cerrarlo."):format(getVehicleNameFromModel(data.model) or "vehiculo", data.plate))
end

local function spawnRow(row)
    local v = createVehicle(row.model, row.x, row.y, row.z, row.rx, row.ry, row.rz, row.plate)
    if not v then return false end
    setElementInterior(v, row.interior)
    setElementDimension(v, row.dimension)
    applyColor(v, row.color)
    setElementHealth(v, math.max(300, tonumber(row.health) or 1000))
    local locked = tonumber(row.locked) == 1
    setVehicleLocked(v, locked)
    setVehicleEngineState(v, false)
    local id = tonumber(row.id)
    vehicles[v] = {
        id = id, ownerId = tonumber(row.owner_id), locked = locked, engine = false,
        handbrake = tonumber(row.handbrake) == 1, clamped = tonumber(row.clamped) == 1,
        plate = row.plate, model = tonumber(row.model),
        lastDriver = row.last_driver_name and { name = row.last_driver_name, at = row.last_driver_at } or nil,
    }
    byId[id] = v
    setElementData(v, "rp:vehicleOwner", tonumber(row.owner_id))
    setElementData(v, "rp:vehicleId", id)
    setElementData(v, "rp:indicator", false)
    if applyTuning then applyTuning(v, row.tuning) end
    if initPerf then initPerf(v, row.perf, row.odometer) end
    if initFuel then initFuel(v, tonumber(row.fuel)) end
    updateFrozen(v)
    labelKey(v)
    return v
end

function saveVehicle(vehicle)
    local data = vehicles[vehicle]
    if not data or not isElement(vehicle) then return end
    local x, y, z = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    local tuning = captureTuning and toJSON(captureTuning(vehicle), true) or nil
    dbExec(db(), [[UPDATE vehicles SET x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ?, interior = ?, dimension = ?, health = ?,
        locked = ?, handbrake = ?, clamped = ?, tuning = ?, fuel = ?, perf = ?, odometer = COALESCE(?, odometer) WHERE id = ?]],
        x, y, z, rx, ry, rz, getElementInterior(vehicle), getElementDimension(vehicle), getElementHealth(vehicle),
        data.locked and 1 or 0, data.handbrake and 1 or 0, data.clamped and 1 or 0, tuning,
        getVehicleFuel and getVehicleFuel(vehicle) or nil,
        capturePerf and capturePerf(vehicle) or nil, getVehicleOdometer and getVehicleOdometer(vehicle) or nil, data.id)
end

local function loadVehicles()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local spawned = 0
        for _, row in ipairs(rows) do
            -- Idempotente: si rp_database se reinicia, rp:onDatabaseReady vuelve a dispararse; no duplicar
            local existing = byId[tonumber(row.id)]
            if not (existing and isElement(existing)) then
                if spawnRow(row) then spawned = spawned + 1 end
            end
        end
        outputDebugString(("[rp_vehicles] %d vehiculos cargados (%d nuevos)"):format(#rows, spawned))
    end, db(), "SELECT * FROM vehicles")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadVehicles() else addEventHandler("rp:onDatabaseReady", root, loadVehicles) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for v in pairs(vehicles) do saveVehicle(v) end
end)

-- Si rp_inventory se reinicia pierde los nombres de las llaves: se vuelven a poner
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "rp_inventory" then
        for v in pairs(vehicles) do labelKey(v) end
    end
end)

setTimer(function() for v in pairs(vehicles) do saveVehicle(v) end end, VEHICLES.SAVE_INTERVAL, 0)

----------------------------------------------------------------
-- Llaves
----------------------------------------------------------------
-- Entrega la llave al dueno. Devuelve true si la pudo poner en el inventario.
local function giveKey(player, vehicleId)
    if not resourceRunning("rp_inventory") then return false end
    local item = vehicleKeyItem(vehicleId)
    if exports.rp_inventory:hasItem(player, item, 1) then return true end
    local ok = exports.rp_inventory:giveItem(player, item, 1)
    return ok == true
end

-- Duenos con vehiculos anteriores al sistema de llaves (o cuya entrega fallo)
local function deliverPendingKeys(player, characterId)
    if not isElement(player) or characterOf(player) ~= characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        for _, row in ipairs(rows) do
            if giveKey(player, row.id) then
                dbExec(db(), "UPDATE vehicles SET key_given = 1 WHERE id = ?", row.id)
                notify(player, ("Recibiste la llave de tu vehiculo %s."):format(row.plate), "info")
            end
        end
    end, db(), "SELECT id, plate FROM vehicles WHERE owner_id = ? AND key_given = 0", characterId)
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local player = source
    -- El inventario se carga en el mismo evento; se espera a que este listo
    setTimer(deliverPendingKeys, 4000, 1, player, characterId)
end)

-- Jugadores ya conectados cuando arranca el recurso (p. ej. al actualizarlo)
addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        for _, player in ipairs(getElementsByType("player")) do
            local characterId = characterOf(player)
            if characterId then deliverPendingKeys(player, characterId) end
        end
    end, 6000, 1)
end)

-- Vehiculo para una accion con llave: el que ocupa o el mas cercano del que tenga llave
local function vehicleForKey(player)
    local occupied = getPedOccupiedVehicle(player)
    if occupied and vehicles[occupied] and hasVehicleKey(player, vehicles[occupied].id) then return occupied end
    local best, bestDist = nil, VEHICLES.LOCK_DISTANCE
    for v, data in pairs(vehicles) do
        local d = distanceTo(player, v)
        if d < bestDist and hasVehicleKey(player, data.id) then best, bestDist = v, d end
    end
    return best
end

function setVehicleLockState(vehicle, locked)
    local data = vehicles[vehicle]
    if not data then return end
    data.locked = locked
    setVehicleLocked(vehicle, locked)
    dbExec(db(), "UPDATE vehicles SET locked = ? WHERE id = ?", locked and 1 or 0, data.id)
end

local function toggleLock(player, vehicle)
    if not characterOf(player) then return end
    vehicle = vehicle or vehicleForKey(player)
    if not vehicle then return notify(player, "No tienes la llave de ningun vehiculo cercano.", "warning") end
    local data = vehicles[vehicle]
    setVehicleLockState(vehicle, not data.locked)
    notify(player, data.locked and "Vehiculo cerrado." or "Vehiculo abierto.", data.locked and "info" or "success")
    triggerClientEvent(root, "rp:veh:lockFx", resourceRoot, vehicle, data.locked)
end

addEventHandler("rp:veh:toggleLock", resourceRoot, function()
    if getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    toggleLock(client)
end)

-- Usar la llave desde el inventario
addEventHandler("rp:onItemUse", root, function(itemId)
    local id = type(itemId) == "string" and tonumber(itemId:match("^vkey:(%d+)$"))
    if not id then return end
    local player = source
    local vehicle = byId[id]
    if not vehicle or distanceTo(player, vehicle) > VEHICLES.LOCK_DISTANCE then
        return notify(player, "El vehiculo de esta llave no esta cerca.", "warning")
    end
    toggleLock(player, vehicle)
end)

-- /copiallave: el dueno saca otra llave si perdio la suya o se la dio a alguien
addCommandHandler("copiallave", function(player)
    local characterId = characterOf(player)
    if not characterId then return end
    local vehicle = getPedOccupiedVehicle(player)
    if not (vehicle and vehicles[vehicle] and vehicles[vehicle].ownerId == characterId) then
        vehicle = nil
        for v, data in pairs(vehicles) do
            if data.ownerId == characterId and distanceTo(player, v) <= VEHICLES.LOCK_DISTANCE then vehicle = v break end
        end
    end
    if not vehicle then return notify(player, "Debes estar junto a un vehiculo tuyo.", "warning") end
    local data = vehicles[vehicle]
    if hasVehicleKey(player, data.id) then return notify(player, "Ya tienes la llave de este vehiculo.", "warning") end
    if giveKey(player, data.id) then
        dbExec(db(), "UPDATE vehicles SET key_given = 1 WHERE id = ?", data.id)
        notify(player, ("Hiciste una copia de la llave de %s."):format(data.plate), "success")
    else
        notify(player, "No tienes espacio en el inventario para la llave.", "error")
    end
end)

-- /darllave <jugador>: entrega la llave del vehiculo en el que estas (o el mas cercano)
addCommandHandler("darllave", function(player, _, query)
    if not characterOf(player) then return end
    local target = query and exports.rp_ids:findPlayer(query)
    if not target or target == player or not characterOf(target) then
        return notify(player, "Uso: /darllave <id o nombre del jugador>", "warning")
    end
    if distanceTo(player, target) > 3 then return notify(player, "Esa persona esta demasiado lejos.", "warning") end
    local vehicle = vehicleForKey(player)
    if not vehicle then return notify(player, "No tienes la llave de ningun vehiculo cercano.", "warning") end
    local item = vehicleKeyItem(vehicles[vehicle].id)
    local ok, reason = exports.rp_inventory:canCarry(target, item, 1)
    if not ok then return notify(player, reason or "No puede llevar la llave.", "error") end
    if exports.rp_inventory:takeItem(player, item, 1) and exports.rp_inventory:giveItem(target, item, 1) then
        notify(player, ("Le diste la llave de %s a %s."):format(vehicles[vehicle].plate, displayName(target)), "success")
        notify(target, ("%s te dio la llave de %s."):format(displayName(player), vehicles[vehicle].plate), "info")
    end
end)

-- /allave <id vehiculo> <jugador> (admin): da una llave de cualquier vehiculo
addCommandHandler("allave", function(player, _, vehicleId, query)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    vehicleId = tonumber(vehicleId)
    local target = query and exports.rp_ids:findPlayer(query)
    if not vehicleId or not byId[vehicleId] or not target then
        return notify(player, "Uso: /allave <id del vehiculo> <jugador>", "warning")
    end
    if giveKey(target, vehicleId) then
        notify(player, ("Llave del vehiculo %d entregada a %s."):format(vehicleId, displayName(target)), "success")
        notify(target, "Un administrador te dio una llave de vehiculo.", "info")
    else
        notify(player, "No se pudo dar la llave (inventario lleno o no disponible).", "error")
    end
end)

----------------------------------------------------------------
-- Motor, freno de mano e intermitentes
----------------------------------------------------------------
local function driverVehicle(player)
    local v = getPedOccupiedVehicle(player)
    if v and getVehicleController(v) == player then return v end
    return nil
end

addEventHandler("rp:veh:engine", resourceRoot, function()
    local player = client
    local v = driverVehicle(player)
    if not v then return notify(player, "Debes estar al volante.", "warning") end
    local data = vehicles[v]
    local starting = not (data and data.engine or (not data and getVehicleEngineState(v)))
    if starting and getVehicleFuel and getVehicleFuel(v) <= 0 then
        return notify(player, "El vehiculo no tiene bencina. Llevalo a una bencinera.", "error")
    end
    if starting and isRefueling and isRefueling(v) then
        return notify(player, "Espera a que terminen de cargar la bencina.", "warning")
    end
    if not data then
        -- Vehiculos sin dueno (admin, trabajos...): motor libre
        return setVehicleEngineState(v, not getVehicleEngineState(v))
    end
    if not data.engine then
        if not hasVehicleKey(player, data.id) then return notify(player, "No tienes la llave de este vehiculo.", "error") end
        if data.clamped then return notify(player, "El vehiculo tiene un cepo de la policia.", "error") end
        if getElementHealth(v) <= 300 then return notify(player, "El motor esta demasiado danado.", "error") end
    end
    data.engine = not data.engine
    setVehicleEngineState(v, data.engine)
    notify(player, data.engine and "Motor encendido." or "Motor apagado.", "info")
end)

addEventHandler("rp:veh:handbrake", resourceRoot, function()
    local player = client
    local v = driverVehicle(player)
    if not v then return end
    local data = vehicles[v]
    if not data then return end
    if not data.handbrake and vehicleSpeedKmh(v) > VEHICLES.HANDBRAKE_MAX_SPEED then
        return notify(player, "Frena antes de poner el freno de mano.", "warning")
    end
    data.handbrake = not data.handbrake
    updateFrozen(v)
    dbExec(db(), "UPDATE vehicles SET handbrake = ? WHERE id = ?", data.handbrake and 1 or 0, data.id)
    notify(player, data.handbrake and "Freno de mano puesto." or "Freno de mano quitado.", "info")
end)

local INDICATOR_SIDES = { left = true, right = true, hazard = true }
addEventHandler("rp:veh:indicator", resourceRoot, function(side)
    local player = client
    local v = driverVehicle(player)
    if not v or not INDICATOR_SIDES[side] then return end
    local current = getElementData(v, "rp:indicator")
    setElementData(v, "rp:indicator", current ~= side and side or false)
end)

-- Enciende o apaga el motor desde otro script (p. ej. sin bencina o en la bencinera)
function setEngine(vehicle, on)
    local data = vehicles[vehicle]
    if data then data.engine = on and true or false end
    setVehicleEngineState(vehicle, on and true or false)
end

----------------------------------------------------------------
-- Entrar y salir
----------------------------------------------------------------
-- Los autos con dueno conservan el estado del motor: GTA lo enciende solo al subir
addEventHandler("onVehicleEnter", root, function(player, seat)
    local data = vehicles[source]
    if not data then
        -- Sin dueno: GTA enciende el motor solo, salvo que no tenga bencina
        if seat == 0 and getVehicleFuel and getVehicleFuel(source) <= 0 then
            local v = source
            setTimer(function() if isElement(v) then setVehicleEngineState(v, false) end end, 100, 1)
            notify(player, "El vehiculo no tiene bencina.", "warning")
        end
        return
    end
    if seat == 0 then
        setVehicleEngineState(source, data.engine)
        if not data.engine and hasVehicleKey(player, data.id) then
            notify(player, ("Pulsa %s o /toggleengine para encender el motor."):format(VEHICLES.KEYS.engine.key:upper()), "info")
        end
    end
    if onOwnedVehicleEnter then onOwnedVehicleEnter(source, player, seat) end
end)

addEventHandler("onVehicleExit", root, function(player, seat)
    local data = vehicles[source]
    if not data then return end
    if seat == 0 then
        setVehicleEngineState(source, data.engine)
        -- Las balizas quedan puestas al bajarse; los intermitentes se apagan
        if getElementData(source, "rp:indicator") ~= "hazard" then setElementData(source, "rp:indicator", false) end
        saveVehicle(source)
    end
end)

----------------------------------------------------------------
-- API
----------------------------------------------------------------
-- Nota: las funciones no se pueden pasar por exports, asi que estas dos son
-- sincronas (dbPoll con espera). Son consultas pequenas y poco frecuentes (compras).
function countOwnedVehicles(characterId)
    local rows = dbPoll(dbQuery(db(), "SELECT COUNT(*) AS total FROM vehicles WHERE owner_id = ?", characterId), -1) or {}
    return tonumber(rows[1] and rows[1].total) or 0
end

function createOwnedVehicle(player, model, color, x, y, z, rz)
    local characterId = characterOf(player)
    if not characterId then return false end
    local plate = randomPlate()
    local colorJSON = toJSON(color or { 245, 245, 245 }, true)
    local ok, _, id = dbPoll(dbQuery(db(),
        "INSERT INTO vehicles (owner_id, model, plate, color, x, y, z, rz, locked) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)",
        characterId, model, plate, colorJSON, x, y, z, rz), -1)
    if not ok then return false end
    local vehicle = spawnRow({ id = id, owner_id = characterId, model = model, plate = plate, color = colorJSON,
        x = x, y = y, z = z, rx = 0, ry = 0, rz = rz, interior = 0, dimension = 0, health = 1000, locked = 0 })
    if vehicle then
        if giveKey(player, id) then
            dbExec(db(), "UPDATE vehicles SET key_given = 1 WHERE id = ?", id)
        else
            notify(player, "No tienes espacio para la llave: la recibiras al volver a entrar o con /copiallave.", "warning")
        end
    end
    return vehicle
end

function getVehicleOwner(vehicle)
    return vehicles[vehicle] and vehicles[vehicle].ownerId or false
end

function getVehicleDatabaseId(vehicle)
    return vehicles[vehicle] and vehicles[vehicle].id or false
end

addEventHandler("onElementDestroy", root, function()
    local data = vehicles[source]
    if data then
        byId[data.id] = nil
        vehicles[source] = nil
    end
end)
