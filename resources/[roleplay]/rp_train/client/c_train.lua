--[[
    rp_train · cliente
    Pensado para PCs de gama baja: solo trabaja con trenes que el juego ya tiene cargados cerca
    (streaming nativo de MTA) y con un temporizador de 250 ms, nunca en onClientRender.

    - Si este cliente sincroniza la locomotora, le aplica la velocidad que marca el servidor (siempre
      positiva: el sentido lo fija el servidor con setTrainDirection).
    - Mantiene cada vagón en la vía principal: en LS corre pegada otra vía (tracks4) y el juego puede
      enganchar ahí un vagón colocado por coordenadas (se veían vagones en la vía de al lado).
    - Bocina nativa del tren (control "horn" del maquinista) si un jugador está en la vía por delante
      o al acercarse a un cruce con las barreras bajadas.
    - Campanas en los cruces cerrados cercanos.
    - Claxon (sounds/claxon.mp3) cuando faltan 10 s para salir de cada estación (rp:train:horn del servidor).
]]

local locos = {}       -- [loco] = true, solo las cargadas (stream in)
local wagons = {}      -- [locomotora o vagón] = estado, cargados: se vigila que sigan en la vía principal
local cars = {}        -- [vagón] = true, cargados: siguen a su locomotora (tickCar)
local hornUntil = {}   -- [loco] = tick en que suelta la bocina
local hornNext = {}    -- [loco] = tick a partir del cual puede volver a tocar
local warnedCross = {} -- [loco .. crossing] = tick del último aviso en ese cruce
local bells = {}       -- [crossing] = sound
local crossingList, crossingListAt = {}, 0

local function honk(loco, now)
    if hornNext[loco] and now < hornNext[loco] then return end
    local driver = getVehicleController(loco)
    if not driver then return end
    setPedControlState(driver, "horn", true)
    hornUntil[loco] = now + TRAIN.HORN_MS
    hornNext[loco] = now + TRAIN.HORN_MS + 900
end

local function crossings(now)
    if now - crossingListAt > 3000 then
        crossingList, crossingListAt = getElementsByType("rp_railcrossing"), now
    end
    return crossingList
end

-- ¿Hay un jugador (a pie o en su vehículo) sobre la vía por delante?
local function someoneOnTrack(lx, ly, lz, fx, fy)
    for _, p in ipairs(getElementsByType("player", root, true)) do
        local veh = getPedOccupiedVehicle(p)
        if not (veh and getElementData(veh, "rp:train:wagon")) then
            local x, y, z = getElementPosition(veh or p)
            local rx, ry = x - lx, y - ly
            local along = rx * fx + ry * fy
            if along > 6 and along < TRAIN.HORN_AHEAD and math.abs(rx * fy - ry * fx) < TRAIN.HORN_WIDTH
                and math.abs(z - lz) < 5 then
                return true
            end
        end
    end
    return false
end

local function tickLoco(loco, now)
    -- Velocidad: solo el cliente que sincroniza mueve el tren
    if isElementSyncer(loco) then
        local v = tonumber(getElementData(loco, "rp:train:v")) or 0
        setTrainSpeed(loco, v / TRAIN.VELOCITY_UNIT) -- siempre positiva: el sentido lo fija el servidor
    end

    if hornUntil[loco] and now >= hornUntil[loco] then
        hornUntil[loco] = nil
        local driver = getVehicleController(loco)
        if driver then setPedControlState(driver, "horn", false) end
    end

    local vx, vy = getElementVelocity(loco)
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed * TRAIN.VELOCITY_UNIT < 2 then return end
    local fx, fy = vx / speed, vy / speed
    local lx, ly, lz = getElementPosition(loco)

    if someoneOnTrack(lx, ly, lz, fx, fy) then return honk(loco, now) end

    for _, c in ipairs(crossings(now)) do
        if isElement(c) and getElementData(c, "closed") then
            local x, y = getElementPosition(c)
            local along = (x - lx) * fx + (y - ly) * fy
            local key = tostring(loco) .. tostring(c)
            if along > 15 and along < 160 and math.abs((x - lx) * fy - (y - ly) * fx) < 25
                and (not warnedCross[key] or now - warnedCross[key] > 20000) then
                warnedCross[key] = now
                hornNext[loco] = nil
                return honk(loco, now)
            end
        end
    end
end

-- Campanas: una por cruce cerrado cerca de la cámara (las barreras de un mismo cruce comparten una)
local function tickBells(now)
    local cx, cy, cz = getCameraMatrix()
    local wanted = {}
    for _, c in ipairs(crossings(now)) do
        if isElement(c) and getElementData(c, "closed") then
            local x, y, z = getElementPosition(c)
            if getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) < TRAIN.BELL_DISTANCE then
                local near = false
                for other in pairs(wanted) do
                    local ox, oy = getElementPosition(other)
                    if getDistanceBetweenPoints2D(x, y, ox, oy) < 30 then near = true break end
                end
                if not near then wanted[c] = true end
            end
        end
    end
    for c, snd in pairs(bells) do
        if not wanted[c] then
            if isElement(snd) then destroyElement(snd) end
            bells[c] = nil
        end
    end
    for c in pairs(wanted) do
        if not bells[c] then
            local x, y, z = getElementPosition(c)
            local snd = playSound3D("sounds/campanas.mp3", x, y, z + 1, true)
            if snd then
                setSoundMinDistance(snd, 15)
                setSoundMaxDistance(snd, TRAIN.BELL_DISTANCE)
                setSoundVolume(snd, TRAIN.BELL_VOLUME)
                setElementDimension(snd, getElementDimension(c))
                setElementInterior(snd, getElementInterior(c))
                bells[c] = snd
            end
        end
    end
end

local function forget(loco)
    locos[loco], hornUntil[loco], hornNext[loco] = nil, nil, nil
end

-- MTA 1.6 no expone la vía de un tren (no hay getTrainTrack/setTrainTrack): el juego la elige por el nodo
-- más cercano. Si el vagón quedó a más de OFF_TRACK de la vía principal, está en otra (en LS corre pegada
-- la de tracks4): se pone en un nodo exacto de la principal y se lleva a su punto con setTrainPosition.
local function keepOnMainTrack(veh, now)
    local st = wagons[veh]
    local x, y = getElementPosition(veh)
    local d, off = TrainTrack.project(x, y, st.d) -- con pista: solo ±30 nodos
    st.d = d
    if off <= TRAIN.OFF_TRACK or (st.fixedAt and now - st.fixedAt < 2000) then return end
    st.fixedAt = now
    local nx, ny, nz = TrainTrack.nodePoint(d)
    setElementPosition(veh, nx, ny, nz + 1, false)
    setTrainPosition(veh, TrainTrack.gameD(d))
end

-- Media longitud de cada modelo (caja del modelo), para dejar los vagones pegados sin solaparse
local halfLen = {}
local function half(veh)
    local m = getElementModel(veh)
    if not halfLen[m] then
        local _, y0, _, _, y1 = getElementBoundingBox(veh)
        if not y0 or y1 <= y0 then return nil end
        halfLen[m] = (y1 - y0) / 2
    end
    return halfLen[m]
end

-- Vagón suelto (sin enganche de MTA): si este cliente lo sincroniza, lo lleva a la velocidad real de su
-- locomotora más una corrección suave hacia su sitio detrás de ella. En la vía del juego la posición
-- crece en el sentido de marcha (el servidor fija el sentido), así que "detrás" es posición - distancia.
local function tickCar(car)
    if not isElementSyncer(car) then return end
    local loco = getElementData(car, "rp:train:of")
    if not isElement(loco) then return end
    if not isElementStreamedIn(loco) then -- sin la locomotora cargada: solo su velocidad
        return setTrainSpeed(car, (tonumber(getElementData(loco, "rp:train:v")) or 0) / TRAIN.VELOCITY_UNIT)
    end
    local idx = tonumber(getElementData(car, "rp:train:idx")) or 1
    local hl, hc = half(loco), half(car)
    local offset = (hl and hc) and (hl + hc * (2 * idx - 1) + idx * TRAIN.COUPLING) or idx * TRAIN.CARRIAGE_GAP
    local L = TrainTrack.gameLength()
    local target = (getTrainPosition(loco) - offset) % L
    local err = (target - getTrainPosition(car) + L / 2) % L - L / 2 -- metros que le faltan (+ = adelantar)
    if math.abs(err) > TRAIN.CAR_SNAP then -- recién aparecido o muy desfasado: a su sitio de una vez
        setTrainPosition(car, target)
        err = 0
    end
    local corr = math.max(-TRAIN.CAR_CATCHUP, math.min(TRAIN.CAR_CATCHUP, err * 0.8))
    setTrainSpeed(car, getTrainSpeed(loco) + corr / TRAIN.VELOCITY_UNIT)
end

local function track(el)
    if not (isElement(el) and getElementType(el) == "vehicle" and getElementData(el, "rp:train:wagon")) then return end
    wagons[el] = {}
    keepOnMainTrack(el, getTickCount())
    if getElementData(el, "rp:train") == true then locos[el] = true
    elseif getElementData(el, "rp:train:of") then cars[el] = true end
end

local function untrack(el)
    wagons[el], cars[el] = nil, nil
    if locos[el] then forget(el) end
end

-- Claxon de salida: el servidor lo marca cuando faltan DEPART_HORN_MS; solo suena si la locomotora está cargada cerca
addEventHandler("onClientElementDataChange", root, function(key)
    if key ~= "rp:train:horn" or not locos[source] then return end
    local x, y, z = getElementPosition(source)
    local snd = playSound3D("sounds/claxon.mp3", x, y, z + 2)
    if not snd then return end
    setSoundMinDistance(snd, 20)
    setSoundMaxDistance(snd, TRAIN.DEPART_HORN_DISTANCE)
    setSoundVolume(snd, TRAIN.DEPART_HORN_VOLUME)
    setElementDimension(snd, getElementDimension(source))
    setElementInterior(snd, getElementInterior(source))
end)

addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementStreamOut", root, function() untrack(source) end)
addEventHandler("onClientElementDestroy", root, function() untrack(source) end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do track(v) end
    local bellTick = 0
    setTimer(function()
        local now = getTickCount()
        for veh in pairs(wagons) do
            if isElement(veh) then keepOnMainTrack(veh, now) else wagons[veh] = nil end
        end
        for loco in pairs(locos) do
            if isElement(loco) then tickLoco(loco, now) else forget(loco) end
        end
        for car in pairs(cars) do
            if isElement(car) then tickCar(car) else cars[car] = nil end
        end
        bellTick = bellTick + 1
        if bellTick % 2 == 0 then tickBells(now) end
    end, TRAIN.HORN_CHECK_MS, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for loco in pairs(hornUntil) do
        local driver = isElement(loco) and getVehicleController(loco)
        if driver then setPedControlState(driver, "horn", false) end
    end
end)
