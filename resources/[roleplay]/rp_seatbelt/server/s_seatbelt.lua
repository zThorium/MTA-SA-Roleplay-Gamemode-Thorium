--[[
    rp_seatbelt / s_seatbelt.lua
    Cinturon de seguridad (tecla C dentro de un coche) y choques sin cinturon.

    Flujo de un choque (lo detecta el cliente del ocupante y aqui se valida):
      leve   -> "rp:seatbelt:crash" "light": quita SEATBELT.LIGHT_DAMAGE de vida (nunca baja de LIGHT_MIN_HEALTH).
      fuerte -> "rp:seatbelt:crash" "eject": rompe el parabrisas, saca al jugador del coche y avisa a su
                cliente para lanzarlo en camara lenta. Cuando el cuerpo choca, el cliente manda
                "rp:seatbelt:landed" y queda abatido (rp_injury). Si no llega, lo abate un temporizador.

    Solo el propio jugador puede pedir su choque: un tramposo solo se hace dano a si mismo.

    elementData "rp:seatbelt" (lo escribe solo el servidor): true con el cinturon puesto.
]]

addEvent("rp:seatbelt:toggle", true)
addEvent("rp:seatbelt:crash", true)
addEvent("rp:seatbelt:landed", true)

local lastToggle = {}   -- [player] = tick
local lastCrash = {}    -- [player] = tick
local ejecting = {}     -- [player] = timer de respaldo

local function hasBeltSeat(vehicle)
    return isElement(vehicle) and SEATBELT.VEHICLE_TYPES[getVehicleType(vehicle)] == true
end

local function setBelt(player, on)
    if isElement(player) then setElementData(player, "rp:seatbelt", on and true or false) end
end

local function isBelted(player)
    return getElementData(player, "rp:seatbelt") == true
end

addEventHandler("rp:seatbelt:toggle", resourceRoot, function()
    local player = client
    if not player or not exports.rp_characters:getPlayerCharacterId(player) then return end
    local now = getTickCount()
    if lastToggle[player] and now - lastToggle[player] < SEATBELT.COOLDOWN then return end
    lastToggle[player] = now
    if not hasBeltSeat(getPedOccupiedVehicle(player)) or ejecting[player] then return end
    if exports.rp_injury:isPlayerDowned(player) then return end
    local on = not isBelted(player)
    setBelt(player, on)
    triggerClientEvent(player, "rp:seatbelt:changed", resourceRoot, on)
end)

-- Queda abatido al terminar el vuelo
local function land(player)
    local timer = ejecting[player]
    if not timer then return end
    if isTimer(timer) then killTimer(timer) end
    ejecting[player] = nil
    if not isElement(player) or isPedDead(player) then return end
    setPedAnimation(player)
    if not exports.rp_injury:isPlayerDowned(player) then exports.rp_injury:downPlayer(player) end
    outputServerLog(("[rp_seatbelt] %s salio por el parabrisas y quedo abatido"):format(getPlayerName(player)))
end

addEventHandler("rp:seatbelt:crash", resourceRoot, function(kind)
    local player = client
    if not player or (kind ~= "light" and kind ~= "eject") then return end
    if not exports.rp_characters:getPlayerCharacterId(player) or isPedDead(player) then return end
    local now = getTickCount()
    if lastCrash[player] and now - lastCrash[player] < SEATBELT.CRASH_COOLDOWN then return end
    local vehicle = getPedOccupiedVehicle(player)
    if not hasBeltSeat(vehicle) or isBelted(player) or ejecting[player] then return end
    if exports.rp_injury:isPlayerDowned(player) then return end
    lastCrash[player] = now

    if kind == "light" then
        local health = getElementHealth(player)
        if health > SEATBELT.LIGHT_MIN_HEALTH then
            setElementHealth(player, math.max(SEATBELT.LIGHT_MIN_HEALTH, health - SEATBELT.LIGHT_DAMAGE))
        end
        return
    end

    setVehiclePanelState(vehicle, 4, 3)   -- parabrisas roto
    removePedFromVehicle(player)
    setPedAnimation(player, SEATBELT.EJECT.ANIM_BLOCK, SEATBELT.EJECT.ANIM_NAME, -1, false, true, false, true)
    ejecting[player] = setTimer(land, SEATBELT.EJECT.SERVER_TIMEOUT, 1, player)
    triggerClientEvent(player, "rp:seatbelt:eject", resourceRoot, vehicle)
end)

addEventHandler("rp:seatbelt:landed", resourceRoot, function()
    if client and ejecting[client] then land(client) end
end)

-- Al bajar del coche (o al salir disparado) el cinturon se suelta solo
addEventHandler("onPlayerVehicleExit", root, function() setBelt(source, false) end)
addEventHandler("onPlayerWasted", root, function() setBelt(source, false) end)
addEventHandler("rp:onCharacterLogout", root, function() setBelt(source, false) end)

addEventHandler("onPlayerQuit", root, function()
    if isTimer(ejecting[source]) then killTimer(ejecting[source]) end
    ejecting[source], lastToggle[source], lastCrash[source] = nil, nil, nil
end)

-- Si se reinicia el recurso a mitad de un vuelo, queda abatido igual
addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(ejecting) do land(player) end
    for _, player in ipairs(getElementsByType("player")) do setBelt(player, false) end
end)

-- Nadie mas que el servidor cambia el cinturon
addEventHandler("onElementDataChange", root, function(key, oldValue)
    if key == "rp:seatbelt" and client then setElementData(source, key, oldValue) end
end)
