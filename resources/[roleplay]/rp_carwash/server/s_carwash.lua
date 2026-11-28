--[[
    rp_carwash · servidor

    Suciedad: el conductor manda lo que acumuló (rp:carwash:dirt); aquí se limita a la tasa máxima posible por el
    tiempo transcurrido, se publica en el elementData "rp:dirt" y, si el auto tiene dueño, se guarda en vehicles.dirt
    (rp_vehicles la carga al crear el auto).

    Lavados: marcadores fijos registrados en rp_markers (los admins los mueven). El conductor pulsa E dentro
    (rp:carwash:ui:wash): se valida que conduce, que está cerca, que el auto está sucio y que tiene el efectivo;
    se cobra, se congela el auto DURATION ms y al final queda limpio.

    Exports: getVehicleDirt(vehicle) -> 0..1, setVehicleDirt(vehicle, dirt) -> bool
]]

local C = CARWASH
local markers = {}      -- [i] = marker
local lastReport = {}   -- [vehicle] = tick del último aporte aceptado
local saved = {}        -- [vehicle] = suciedad guardada en BD
local washing = {}      -- [vehicle] = { player, timer }

addEvent("rp:carwash:dirt", true)
addEvent("rp:carwash:ui:wash", true)

local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end

----------------------------------------------------------------
-- Suciedad
----------------------------------------------------------------
function getVehicleDirt(vehicle)
    return isElement(vehicle) and (tonumber(getElementData(vehicle, "rp:dirt")) or 0) or 0
end

local function save(vehicle, force)
    local id = exports.rp_vehicles:getVehicleDatabaseId(vehicle)
    if not id then return end
    local dirt = getVehicleDirt(vehicle)
    if not force and math.abs(dirt - (saved[vehicle] or 0)) < C.SAVE_STEP then return end
    saved[vehicle] = dirt
    dbExec(exports.rp_database:getConnection(), "UPDATE vehicles SET dirt = ? WHERE id = ?", dirt, id)
end

function setVehicleDirt(vehicle, dirt)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    dirt = tonumber(dirt)
    if not dirt then return false end
    dirt = math.floor(math.max(0, math.min(1, dirt)) * 1000 + 0.5) / 1000
    setElementData(vehicle, "rp:dirt", dirt)
    save(vehicle, false)
    return true
end

addEventHandler("rp:carwash:dirt", resourceRoot, function(vehicle, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 or not isElement(vehicle) or getVehicleController(vehicle) ~= client then return end
    if washing[vehicle] or not C.VEHICLE_TYPES[getVehicleType(vehicle)] then return end
    local now = getTickCount()
    local elapsed = (now - (lastReport[vehicle] or (now - C.SEND_EVERY))) / 1000
    lastReport[vehicle] = now
    -- shortcut: el terreno lo dice el cliente (el servidor no ve superficies); solo se limita la tasa. Es cosmético.
    amount = math.min(amount, C.MAX_RATE * elapsed + 0.01)
    setVehicleDirt(vehicle, getVehicleDirt(vehicle) + amount)
end)

----------------------------------------------------------------
-- Lavados
----------------------------------------------------------------
local function finishWash(vehicle, ok)
    local w = washing[vehicle]
    if not w then return end
    washing[vehicle] = nil
    if isTimer(w.timer) then killTimer(w.timer) end
    if not isElement(vehicle) then return end
    -- el freno de mano y el cepo de rp_vehicles también congelan: se respetan
    setElementFrozen(vehicle, getElementData(vehicle, "rp:handbrake") == true or getElementData(vehicle, "rp:clamp") == true)
    if ok then
        setVehicleDirt(vehicle, 0)
        save(vehicle, true)
        if isElement(w.player) then notify(w.player, "¡Listo! Tu vehículo quedó impecable.", "success") end
    end
    triggerClientEvent(root, "rp:carwash:finish", resourceRoot, vehicle, ok)
end

addEventHandler("rp:carwash:ui:wash", resourceRoot, function(i)
    local player = client
    local m = markers[tonumber(i) or 0]
    local vehicle = getPedOccupiedVehicle(player)
    if not m or not isElement(m) or not vehicle or getVehicleController(vehicle) ~= player then return end
    if not C.VEHICLE_TYPES[getVehicleType(vehicle)] or washing[vehicle] then return end
    local mx, my, mz = getElementPosition(m)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(mx, my, mz, vx, vy, vz) > C.USE_DIST + 1
        or getElementDimension(vehicle) ~= getElementDimension(m) then return end
    if getVehicleDirt(vehicle) < C.MIN_TO_WASH then return notify(player, "Tu vehículo ya está limpio.", "info") end
    if getPlayerMoney(player) < C.PRICE then
        triggerClientEvent(player, "rp:carwash:denied", resourceRoot)
        return notify(player, ("El lavado cuesta $%d en efectivo y no te alcanza."):format(C.PRICE), "error")
    end
    takePlayerMoney(player, C.PRICE)
    setElementFrozen(vehicle, true)
    washing[vehicle] = { player = player, timer = setTimer(finishWash, C.DURATION, 1, vehicle, true) }
    triggerClientEvent(root, "rp:carwash:start", resourceRoot, vehicle, C.DURATION, getVehicleDirt(vehicle))
end)

-- Si el auto desaparece o el conductor se va, se corta (ya pagó: lo justo es que igual quede limpio)
addEventHandler("onVehicleExit", root, function(_, seat)
    if seat == 0 and washing[source] then finishWash(source, true) end
end)

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    if washing[source] then finishWash(source, false) end
    lastReport[source], saved[source] = nil, nil
end)

----------------------------------------------------------------
-- Marcadores (rp_markers: los admins los mueven con el editor)
----------------------------------------------------------------
local function buildMarkers()
    for _, m in pairs(markers) do if isElement(m) then destroyElement(m) end end
    markers = {}
    for i, w in ipairs(C.WASHES) do
        local x, y, z = exports.rp_markers:placePoint(w.key, w.x, w.y, w.z)
        local m = createMarker(x or w.x, y or w.y, z or w.z, "cylinder", C.MARKER_SIZE, 60, 215, 230, 120)
        setElementData(m, "rp:carwash:id", i)
        exports.rp_markers:setMarkerStyle(m, { icon = "car", label = ("%s · $%d"):format(w.name, C.PRICE) })
        exports.rp_markers:registerMarker(m, w.key, { label = w.name, point = { w.x, w.y, w.z } })
        markers[i] = m
    end
end

addEvent("rp:markers:moved")
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then buildMarkers() end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    buildMarkers()
    for _, v in ipairs(getElementsByType("vehicle")) do saved[v] = getVehicleDirt(v) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for v in pairs(washing) do finishWash(v, true) end
    for _, v in ipairs(getElementsByType("vehicle")) do save(v, false) end
end)
