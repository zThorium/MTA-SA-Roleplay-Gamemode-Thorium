--[[
    rp_train · pasajeros (servidor)

    Con un boleto (item TRAIN.TICKET_ITEM, se compra en las boleterías de s_stations.lua) el jugador sube
    al tren de pasajeros pulsando E junto a un vagón mientras el tren está en el andén: el boleto se gasta,
    el personaje va sentado dentro del vagón (attachElements, invisible y sin controles) y el cliente pone
    una cámara que gira con el ratón alrededor del vagón (c_passengers.lua). Solo se baja en una estación,
    con E mientras el tren espera en el andén; queda junto al vagón, del lado del andén.

    El cliente solo pide subir o bajar (y propone dónde pisar al bajar): tren, vagón, andén, boleto y
    distancias se comprueban aquí.
]]

addEvent("rp:train:board", true)
addEvent("rp:train:alight", true)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)

local riders = {}   -- [player] = { t, car, seat }
local cooldown = {} -- [player] = tick de la última petición

local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < 1000 then return false end
    cooldown[p] = now
    return true
end

-- En el andén: nombre de la estación y segundos que faltan para salir; si no, nil
local function stopped(t)
    if t.dwellUntil and t.leaving then return t.leaving.name, math.max(0, math.ceil((t.dwellUntil - getTickCount()) / 1000)) end
end

-- Asiento libre del vagón (0..PASSENGERS_PER_CAR-1) o nil si va lleno
local function freeSeat(car)
    local used = {}
    for _, r in pairs(riders) do if r.car == car then used[r.seat] = true end end
    for i = 0, TRAIN.PASSENGERS_PER_CAR - 1 do if not used[i] then return i end end
end

-- Dos filas a lo largo del vagón
local function seatOffset(i)
    local row = math.floor(i / 2)
    local rows = math.ceil(TRAIN.PASSENGERS_PER_CAR / 2)
    return (i % 2 == 0) and -0.55 or 0.55, (row - (rows - 1) / 2) * 2.6, 0.4
end

-- Punto junto al vagón (lado derecho) por si el cliente no manda uno válido
local function besideCar(car)
    local cx, cy, cz = getElementPosition(car)
    local _, _, rz = getElementRotation(car)
    return cx + math.cos(math.rad(rz)) * TRAIN.ALIGHT_SIDE, cy + math.sin(math.rad(rz)) * TRAIN.ALIGHT_SIDE, cz + 1
end

local function sendState(p, r)
    local station, secs = stopped(r.t)
    triggerClientEvent(p, "rp:train:ride", resourceRoot, r.car, station or false, secs or 0, getTrainNextStop(r.t) or "")
end

-- Termina el viaje. x, y, z = dónde queda (nil: donde esté)
local function release(p, x, y, z)
    local r = riders[p]
    if not r then return end
    riders[p] = nil
    if not isElement(p) then return end
    detachElements(p)
    setPedAnimation(p)
    toggleAllControls(p, true, true, false)
    setElementAlpha(p, 255)
    setElementData(p, "rp:train:rider", false)
    if x then setElementPosition(p, x, y, z) end
    triggerClientEvent(p, "rp:train:ride", resourceRoot, false)
end

local function releaseBeside(p)
    local r = riders[p]
    if r and isElement(r.car) then release(p, besideCar(r.car)) else release(p) end
end

addEventHandler("rp:train:board", resourceRoot, function(car)
    local p = client
    if riders[p] or not takeCooldown(p) or not exports.rp_characters:getPlayerCharacterId(p) then return end
    if isPedInVehicle(p) or isPedDead(p) or getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") then return end
    if not isElement(car) or getElementType(car) ~= "vehicle" then return end
    local t = getTrainOfWagon(car)
    if not t or not t.def.passenger or car == t.loco then return end
    local station = stopped(t)
    if not station then return notify(p, "Espera a que el tren se detenga en el andén.", "warning") end
    if getElementDimension(p) ~= getElementDimension(car) or getElementInterior(p) ~= getElementInterior(car) then return end
    local px, py, pz = getElementPosition(p)
    local _, _, cz = getElementPosition(car)
    local along, side = TrainTrack.carFrame(car, px, py)
    if math.abs(along) > TRAIN.CAR_HALF_LENGTH + 1 or math.abs(side) > TRAIN.BOARD_SIDE + 1 or math.abs(pz - cz) > 4 then
        return notify(p, "Acércate a la puerta del vagón.", "warning")
    end
    local seat = freeSeat(car)
    if not seat then return notify(p, "Este vagón va lleno: prueba en otro.", "warning") end
    -- Con torniquetes en la estación se sube con el boleto ya validado en ellos (s_stations.lua);
    -- sin torniquetes, el boleto se gasta aquí
    local node = t.leaving and t.leaving.node
    if node and stationHasGates(node) then
        if not useStationPass(p, node) then
            return notify(p, "Primero valida tu boleto en el torniquete de la entrada de la estación.", "error")
        end
    else
        if not exports.rp_inventory:hasItem(p, TRAIN.TICKET_ITEM, 1) then
            return notify(p, ("Necesitas un boleto de tren. Cómpralo en la boletería de la estación ($%d)."):format(TRAIN.TICKET_PRICE), "error")
        end
        local ok, why = exports.rp_inventory:takeItem(p, TRAIN.TICKET_ITEM, 1)
        if not ok then return notify(p, why or "No se pudo usar el boleto.", "error") end
    end

    local r = { t = t, car = car, seat = seat }
    riders[p] = r
    local ox, oy, oz = seatOffset(seat)
    attachElements(p, car, ox, oy, oz)
    setPedAnimation(p, "ped", "SEAT_idle", -1, true, false, false, false)
    toggleAllControls(p, false, true, false)
    setElementAlpha(p, 0) -- shortcut: va oculto dentro del vagón; si se modelan asientos visibles, quitarlo
    setElementData(p, "rp:train:rider", true)
    notify(p, ("Subiste al tren en %s. Próxima parada: %s."):format(station, getTrainNextStop(t) or "?"), "success")
    sendState(p, r)
end)

-- x, y, z: suelo que propone el cliente junto al vagón (lado del andén)
addEventHandler("rp:train:alight", resourceRoot, function(x, y, z)
    local p = client
    local r = riders[p]
    if not r or not takeCooldown(p) then return end
    local station = stopped(r.t)
    if not station then return notify(p, "Solo puedes bajar cuando el tren se detenga en una estación.", "warning") end
    if not isElement(r.car) then return release(p) end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local ok = x and y and z
    if ok then
        local _, _, cz = getElementPosition(r.car)
        local along, side = TrainTrack.carFrame(r.car, x, y)
        ok = math.abs(along) <= TRAIN.CAR_HALF_LENGTH and math.abs(side) <= TRAIN.ALIGHT_SIDE + 1.5 and math.abs(z - cz) <= 4
    end
    if ok then release(p, x, y, z + 1) else releaseBeside(p) end
    notify(p, ("Bajaste en %s."):format(station), "success")
end)

-- Hooks de s_train.lua
function onTrainArrive(t, st)
    for p, r in pairs(riders) do
        if r.t == t then
            sendState(p, r)
            notify(p, ("Llegaste a %s. Pulsa E para bajar."):format(st.name), "info")
        end
    end
end

function onTrainDepart(t)
    for p, r in pairs(riders) do if r.t == t then sendState(p, r) end end
end

addEventHandler("onPlayerQuit", root, function() riders[source], cooldown[source] = nil, nil end)
addEventHandler("rp:onCharacterLogout", root, function() releaseBeside(source) end)
addEventHandler("rp:onPlayerDowned", root, function() releaseBeside(source) end)
addEventHandler("onPlayerWasted", root, function() release(source) end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(riders) do releaseBeside(p) end
end)
