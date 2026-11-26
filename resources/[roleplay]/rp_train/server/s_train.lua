--[[
    rp_train · trenes (servidor)

    El servidor es la verdad: cada tren tiene una distancia "d" sobre la vía (TrainTrack) y una velocidad.
    - Sin jugadores cerca (nadie lo sincroniza) el tren no existe para ningún cliente: el servidor avanza d
      y lo recoloca en la vía. No hay física ni coste para nadie.
    - Con un jugador cerca, ese cliente lo sincroniza y mueve con la física del juego a la velocidad que
      marca el servidor (elementData rp:train:v); el servidor lee su posición y actualiza d.
    Para en las 6 estaciones del juego como en el modo historia.
]]

local trains = {}
local stations = {} -- { d, node, name } ordenadas por d

local function heading(ux, uy) return math.deg(math.atan2(-ux, uy)) end

local function trainLength(t) return (#t.cars + 1) * TRAIN.CARRIAGE_GAP end

local function spawnDriver(t)
    if isElement(t.driver) then destroyElement(t.driver) end
    local x, y, z = getElementPosition(t.loco)
    t.driver = createPed(TRAIN.DRIVER_SKIN, x, y, z + 3)
    setElementData(t.driver, "rp:train:driver", true)
    warpPedIntoVehicle(t.driver, t.loco, 0)
end

-- Coloca locomotora y vagones en la vía a partir de t.d (solo cuando nadie lo sincroniza)
local function placeTrain(t)
    for i, veh in ipairs(t.wagons) do
        local x, y, z, ux, uy = TrainTrack.point(t.d - (i - 1) * TRAIN.CARRIAGE_GAP)
        setElementPosition(veh, x, y, z + 1, false)
        setElementRotation(veh, 0, 0, heading(ux, uy))
    end
end

local function createTrain(def)
    local t = { def = def, d = TrainTrack.wrap(def.start), v = 0, sign = 1, cars = {}, wagons = {}, back = 0 }
    local x, y, z, ux, uy = TrainTrack.point(t.d)
    t.loco = createVehicle(def.model, x, y, z + 1, 0, 0, heading(ux, uy))
    if not t.loco then return outputDebugString("[rp_train] no se pudo crear la locomotora " .. def.model, 1) end
    t.wagons[1] = t.loco
    local prev = t.loco
    for i, model in ipairs(def.carriages) do
        local cx, cy, cz, cux, cuy = TrainTrack.point(t.d - i * TRAIN.CARRIAGE_GAP)
        local car = createVehicle(model, cx, cy, cz + 1, 0, 0, heading(cux, cuy))
        if car then
            attachTrailerToVehicle(prev, car)
            t.cars[#t.cars + 1] = car
            t.wagons[#t.wagons + 1] = car
            prev = car
        end
    end
    for _, veh in ipairs(t.wagons) do
        setTrainDerailable(veh, false)
        setVehicleDamageProof(veh, true)
        toggleVehicleRespawn(veh, false)
        setElementData(veh, "rp:train:wagon", true)
    end
    setElementData(t.loco, "rp:train", true)
    setElementData(t.loco, "rp:train:v", 0)
    setElementData(t.loco, "rp:train:sign", 1)
    spawnDriver(t)
    trains[#trains + 1] = t
end

-- Próxima estación por delante (sin contar la que acaba de dejar)
local function nextStation(t)
    local best, bestAhead = nil, math.huge
    for _, s in ipairs(stations) do
        if s ~= t.leaving then
            local a = TrainTrack.ahead(t.d, s.d)
            if a < bestAhead then best, bestAhead = s, a end
        end
    end
    return best, bestAhead
end

local function updateSpeed(t, now, dt)
    if t.dwellUntil then
        if now < t.dwellUntil then t.v = 0 return end
        t.dwellUntil = nil
    end
    if t.leaving and TrainTrack.ahead(t.leaving.d, t.d) > 60 and TrainTrack.ahead(t.leaving.d, t.d) < TrainTrack.length() / 2 then
        t.leaving = nil
    end
    local st, dist = nextStation(t)
    if st and dist < 4 and t.v < 3 then -- llegó: espera en el andén
        t.v, t.dwellUntil, t.leaving = 0, now + TRAIN.STATION_STOP_MS, st
        return
    end
    local target = TRAIN.SPEED
    if st then target = math.min(target, math.sqrt(2 * TRAIN.BRAKE * math.max(0, dist - 2)) + 0.5) end
    if t.v < target then
        t.v = math.min(target, t.v + TRAIN.ACCEL * dt)
    else
        t.v = math.max(target, t.v - TRAIN.BRAKE * 2 * dt)
    end
end

local function tickTrain(t, now, dt)
    if not isElement(t.loco) then return end
    if not isElement(t.driver) or isPedDead(t.driver) or getVehicleController(t.loco) ~= t.driver then spawnDriver(t) end

    updateSpeed(t, now, dt)

    if getElementSyncer(t.loco) then
        -- La física la lleva el cliente: se lee dónde está
        local x, y = getElementPosition(t.loco)
        local nd = TrainTrack.project(x, y, t.d)
        local moved = TrainTrack.ahead(t.d, nd)
        if moved > TrainTrack.length() / 2 then -- retrocedió: el signo de setTrainSpeed está al revés
            t.back = t.back + 1
            if t.back >= 2 and t.v > 3 then
                t.sign, t.back = -t.sign, 0
                setElementData(t.loco, "rp:train:sign", t.sign)
            end
        else
            t.back = 0
        end
        t.d = nd
    else
        t.d = TrainTrack.wrap(t.d + t.v * dt)
        placeTrain(t)
    end

    local v = math.floor(t.v * 2 + 0.5) / 2
    if v ~= t.sentV then
        t.sentV = v
        setElementData(t.loco, "rp:train:v", v)
    end
end

-- Lo usan los cruces: ¿algún tren ocupa el tramo [d - antes, d + después]?
function isTrackOccupied(d, before, after)
    for _, t in ipairs(trains) do
        local tail = t.d - trainLength(t) - after
        if TrainTrack.ahead(tail, d) <= trainLength(t) + after + before then return true end
    end
    return false
end

-- Export: estado de los trenes (pruebas y paneles)
function getTrainState()
    local out = {}
    for i, t in ipairs(trains) do
        out[i] = { d = t.d, v = t.v, stopped = t.dwellUntil ~= nil, synced = getElementSyncer(t.loco) and true or false }
    end
    return out
end

function getTrackLength() return TrainTrack.length() end

-- Nadie conduce el tren: solo el asiento de acompañante de la locomotora
addEventHandler("onVehicleStartEnter", root, function(_, seat)
    if seat == 0 and getElementData(source, "rp:train:wagon") then cancelEvent() end
end)

-- El maquinista no se puede sacar a la fuerza
addEventHandler("onVehicleStartExit", root, function(ped)
    if ped and getElementData(ped, "rp:train:driver") then cancelEvent() end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for node, name in pairs(TRAIN.STATION_NAMES) do
        stations[#stations + 1] = { d = TrainTrack.nodeD(node), node = node, name = name }
    end
    table.sort(stations, function(a, b) return a.d < b.d end)
    for _, def in ipairs(TRAIN.TRAINS) do createTrain(def) end
    local last = getTickCount()
    setTimer(function()
        local now = getTickCount()
        local dt = (now - last) / 1000
        last = now
        for _, t in ipairs(trains) do tickTrain(t, now, dt) end
        updateCrossings()
    end, TRAIN.TICK_MS, 0)
    outputDebugString(("[rp_train] %d trenes en la vía (%.0f m, %d estaciones)"):format(#trains, TrainTrack.length(), #stations), 3)
end)
