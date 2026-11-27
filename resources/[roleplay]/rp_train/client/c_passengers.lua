--[[
    rp_train · pasajeros (cliente)

    - Junto a un vagón del tren de pasajeros parado en el andén: aviso con la E dibujada para subir
      (el servidor comprueba el boleto, s_passengers.lua).
    - Viajando: cámara alrededor del vagón que gira con el ratón; aviso de la próxima parada y, en el
      andén, E para bajar con la cuenta atrás de la salida. Al bajar propone el suelo más alto a cada lado
      del vagón (el andén) y el servidor lo valida.
    - Los jugadores que viajan (rp:train:rider) no chocan con el vagón en ningún cliente.
]]

addEvent("rp:train:ride", true)

local W, H = guiGetScreenSize()
local keyE, mouseMove        -- texturas de las teclas dibujadas (se crean una vez)
local boardCar, boardStation -- vagón al que se puede subir ahora
local ride                   -- { car, station = nombre|false, leavesAt = tick, nextStop }
local yaw, pitch = 0, 0.3

local function textures()
    if not keyE then
        keyE = dxCreateTexture("images/keys/keyboard_e.png", "argb", true, "clamp")
        mouseMove = dxCreateTexture("images/keys/mouse_move.png", "argb", true, "clamp")
    end
end

local function canAct()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    return not getElementData(localPlayer, "rp:downed")
end

-- Vagón de pasajeros parado en el andén junto al jugador, y el nombre de la estación
local function findBoardCar()
    if ride or isPedInVehicle(localPlayer) or getElementDimension(localPlayer) ~= 0 then return nil end
    local px, py, pz = getElementPosition(localPlayer)
    for _, car in ipairs(getElementsByType("vehicle", root, true)) do
        local loco = getElementData(car, "rp:train:of")
        if isElement(loco) and getElementData(loco, "rp:train:passenger") then
            local station = getElementData(loco, "rp:train:dwell")
            if station then
                local _, _, cz = getElementPosition(car)
                local along, side = TrainTrack.carFrame(car, px, py)
                if math.abs(along) <= TRAIN.CAR_HALF_LENGTH and math.abs(side) <= TRAIN.BOARD_SIDE and math.abs(pz - cz) < 4 then
                    return car, station
                end
            end
        end
    end
end

-- Suelo junto al vagón: el lado más alto es el andén
local function exitPoint(car)
    local cx, cy, cz = getElementPosition(car)
    local _, _, rz = getElementRotation(car)
    local rx, ry = math.cos(math.rad(rz)), math.sin(math.rad(rz))
    local best
    for _, s in ipairs({ 1, -1 }) do
        local x, y = cx + rx * s * TRAIN.ALIGHT_SIDE, cy + ry * s * TRAIN.ALIGHT_SIDE
        local gz = getGroundPosition(x, y, cz + 3)
        if gz and gz ~= 0 and (not best or gz > best[3]) then best = { x, y, gz } end
    end
    return best
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(function()
        boardCar, boardStation = findBoardCar()
        if boardCar then textures() end
    end, 250, 0)

    bindKey("e", "down", function()
        -- E la usan muchos recursos: aquí solo actúa junto a un vagón o viajando
        if not canAct() then return end
        if ride then
            if not ride.station then
                return exports.rp_notify:notify(("Solo puedes bajar en una estación. Próxima parada: %s."):format(ride.nextStop), "warning")
            end
            local pt = isElement(ride.car) and exitPoint(ride.car)
            if pt then triggerServerEvent("rp:train:alight", resourceRoot, pt[1], pt[2], pt[3])
            else triggerServerEvent("rp:train:alight", resourceRoot) end
        elseif boardCar then
            triggerServerEvent("rp:train:board", resourceRoot, boardCar)
        end
    end)

    for _, p in ipairs(getElementsByType("player", root, true)) do
        if getElementData(p, "rp:train:rider") then setElementCollisionsEnabled(p, false) end
    end
end)

----------------------------------------------------------------
-- Viaje: estado que manda el servidor y cámara
----------------------------------------------------------------
local function stopRide()
    if not ride then return end
    ride = nil
    setCameraTarget(localPlayer)
end

addEventHandler("rp:train:ride", resourceRoot, function(car, station, secs, nextStop)
    if not car then return stopRide() end
    if not ride then -- empieza mirando desde detrás del vagón
        local _, _, rz = getElementRotation(car)
        yaw, pitch = math.rad(rz) - math.pi / 2, 0.3
    end
    textures()
    ride = { car = car, station = station, leavesAt = getTickCount() + (tonumber(secs) or 0) * 1000, nextStop = nextStop or "" }
end)

-- El ratón (sin cursor) gira la cámara alrededor del vagón
addEventHandler("onClientCursorMove", root, function(rx, ry)
    if not ride or isCursorShowing() or isMainMenuActive() then return end
    yaw = yaw - (rx - 0.5) * 5
    pitch = math.max(0.05, math.min(1.2, pitch + (ry - 0.5) * 3))
end)

addEventHandler("onClientPreRender", root, function()
    if not ride then return end
    if not isElement(ride.car) then return stopRide() end
    local cx, cy, cz = getElementPosition(ride.car)
    local d = TRAIN.CAM_DISTANCE
    setCameraMatrix(cx + d * math.cos(pitch) * math.cos(yaw), cy + d * math.cos(pitch) * math.sin(yaw),
        cz + TRAIN.CAM_HEIGHT + d * math.sin(pitch), cx, cy, cz + 1)
end)

----------------------------------------------------------------
-- Avisos con la tecla dibujada (UX-01)
----------------------------------------------------------------
local function hint(icon, text)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 70
    local x, y = (W - w) / 2, H - 190
    dxDrawRectangle(x, y, w, 40, tocolor(12, 14, 20, 215))
    dxDrawRectangle(x, y, 3, 40, tocolor(230, 60, 40, 255))
    if icon then dxDrawImage(x + 10, y + 4, 32, 32, icon) end
    dxDrawText(text, x + 48, y, x + w - 10, y + 40, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    if not (ride or boardCar) or not canAct() or getElementData(localPlayer, "rp:hudHidden") then return end
    if ride then
        if ride.station then
            local left = math.max(0, math.ceil((ride.leavesAt - getTickCount()) / 1000))
            hint(keyE, ("Bajar en %s · el tren sale en %d s"):format(ride.station, left))
        else
            hint(mouseMove, ("Próxima parada: %s · mueve el ratón para mirar"):format(ride.nextStop))
        end
    else
        hint(keyE, ("Subir al tren en %s (gasta 1 boleto)"):format(boardStation))
    end
end)

----------------------------------------------------------------
-- Pasajeros (de cualquier jugador): sin colisión con el vagón
----------------------------------------------------------------
addEventHandler("onClientElementDataChange", root, function(key, _, value)
    if key == "rp:train:rider" and getElementType(source) == "player" then setElementCollisionsEnabled(source, not value) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" and getElementData(source, "rp:train:rider") then
        setElementCollisionsEnabled(source, false)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if ride then setCameraTarget(localPlayer) end
end)
