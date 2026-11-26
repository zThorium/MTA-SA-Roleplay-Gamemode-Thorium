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
]]

local locos = {}       -- [loco] = true, solo las cargadas (stream in)
local wagons = {}      -- [locomotora o vagón] = true, cargados: se vigila que sigan en la vía principal
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

-- Si el juego enganchó el vagón a otra vía, se devuelve a la principal en el mismo punto
local function keepOnMainTrack(veh)
    if getTrainTrack(veh) == TRAIN.TRACK_ID then return end
    local x, y = getElementPosition(veh)
    local d = TrainTrack.project(x, y)
    setTrainTrack(veh, TRAIN.TRACK_ID)
    setTrainPosition(veh, TrainTrack.gameD(d))
end

local function track(el)
    if not (isElement(el) and getElementType(el) == "vehicle" and getElementData(el, "rp:train:wagon")) then return end
    wagons[el] = true
    keepOnMainTrack(el)
    if getElementData(el, "rp:train") == true then locos[el] = true end
end

local function untrack(el)
    wagons[el] = nil
    if locos[el] then forget(el) end
end

addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementStreamOut", root, function() untrack(source) end)
addEventHandler("onClientElementDestroy", root, function() untrack(source) end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do track(v) end
    local bellTick = 0
    setTimer(function()
        local now = getTickCount()
        for veh in pairs(wagons) do
            if isElement(veh) then keepOnMainTrack(veh) else wagons[veh] = nil end
        end
        for loco in pairs(locos) do
            if isElement(loco) then tickLoco(loco, now) else forget(loco) end
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
