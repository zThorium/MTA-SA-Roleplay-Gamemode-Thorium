--[[
    rp_vehicles / s_vehicles.lua
    Vehiculos con dueno (tabla vehicles). Se cargan al iniciar, se guardan al
    salir del vehiculo, cada 5 minutos y al detener el recurso.
    Solo el dueno puede conducirlos; tecla L (o /bloquear) abre y cierra.

    Exports (servidor):
        createOwnedVehicle(player, model, color, x, y, z, rz) -> vehicle | false
        countOwnedVehicles(characterId)                       -> n
        getVehicleOwner(vehicle) -> characterId | false
]]

local vehicles = {}    -- [vehicle] = { id, ownerId, locked }
local SAVE_INTERVAL = 5 * 60000

addEvent("rp:veh:toggleLock", true)
addEvent("rp:onDatabaseReady", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

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
    vehicles[v] = { id = tonumber(row.id), ownerId = tonumber(row.owner_id), locked = locked }
    setElementData(v, "rp:vehicleOwner", tonumber(row.owner_id))
    return v
end

function saveVehicle(vehicle)
    local data = vehicles[vehicle]
    if not data or not isElement(vehicle) then return end
    local x, y, z = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    dbExec(db(), "UPDATE vehicles SET x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ?, interior = ?, dimension = ?, health = ?, locked = ? WHERE id = ?",
        x, y, z, rx, ry, rz, getElementInterior(vehicle), getElementDimension(vehicle), getElementHealth(vehicle), data.locked and 1 or 0, data.id)
end

local function loadVehicles()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do spawnRow(row) end
        outputDebugString(("[rp_vehicles] %d vehiculos cargados"):format(#rows))
    end, db(), "SELECT * FROM vehicles")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadVehicles() else addEventHandler("rp:onDatabaseReady", root, loadVehicles) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for v in pairs(vehicles) do saveVehicle(v) end
end)

setTimer(function() for v in pairs(vehicles) do saveVehicle(v) end end, SAVE_INTERVAL, 0)

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
    return spawnRow({ id = id, owner_id = characterId, model = model, plate = plate, color = colorJSON,
        x = x, y = y, z = z, rx = 0, ry = 0, rz = rz, interior = 0, dimension = 0, health = 1000, locked = 0 })
end

function getVehicleOwner(vehicle)
    return vehicles[vehicle] and vehicles[vehicle].ownerId or false
end

----------------------------------------------------------------
-- Acceso y llaves
----------------------------------------------------------------
addEventHandler("onVehicleStartEnter", root, function(player, seat)
    local data = vehicles[source]
    if not data then return end
    if seat == 0 and data.ownerId ~= characterOf(player) then
        cancelEvent()
        notify(player, "No tienes las llaves de este vehiculo.", "error")
    end
end)

addEventHandler("onVehicleEnter", root, function(player, seat)
    if seat == 0 and vehicles[source] then setVehicleEngineState(source, true) end
end)

addEventHandler("onVehicleExit", root, function(player, seat)
    if seat == 0 and vehicles[source] then
        setVehicleEngineState(source, false)
        saveVehicle(source)
    end
end)

local function toggleLock(player)
    local characterId = characterOf(player)
    if not characterId then return end
    local px, py, pz = getElementPosition(player)
    local best, bestDist = nil, 6
    for v, data in pairs(vehicles) do
        if data.ownerId == characterId and getElementDimension(v) == getElementDimension(player) then
            local vx, vy, vz = getElementPosition(v)
            local d = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
            if d < bestDist then best, bestDist = v, d end
        end
    end
    if not best then return notify(player, "No hay ningun vehiculo tuyo cerca.", "warning") end
    local data = vehicles[best]
    data.locked = not data.locked
    setVehicleLocked(best, data.locked)
    dbExec(db(), "UPDATE vehicles SET locked = ? WHERE id = ?", data.locked and 1 or 0, data.id)
    notify(player, data.locked and "Vehiculo cerrado." or "Vehiculo abierto.", data.locked and "info" or "success")
    triggerClientEvent(player, "rp:veh:lockFx", resourceRoot, best)
end

addEventHandler("rp:veh:toggleLock", resourceRoot, function()
    if getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    toggleLock(client)
end)
addCommandHandler("bloquear", toggleLock)

addEventHandler("onElementDestroy", root, function()
    if vehicles[source] then vehicles[source] = nil end
end)
