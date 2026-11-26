--[[
    rp_bikes / s_bikes.lua

    Arriendo de bicicletas. En cada punto de BIKES.POINTS hay un marcador + blip + colshape;
    con E el jugador arrienda: se cobra, se crea la bicicleta y queda montado. A los 60 minutos
    (BIKES.DURATION) la bici se elimina (y se baja al jugador si va montado).

    Reglas:
      - Una sola bici activa por jugador.
      - Si el jugador sale, cambia de personaje o queda abatido/muerto, la bici se elimina.
      - Si la bici se destruye, se cierra el arriendo (no hay reembolso).
      - Solo el arrendatario puede conducirla.
      - Todos los timers se limpian al cerrar el arriendo.

    Comandos:
        /devolverbici        devuelve la bici antes de tiempo (no hay reembolso)
        /bicitiempo          muestra cuanto le queda al arriendo
]]

local rentals = {}      -- [player] = { vehicle = v, timers = {..}, expires = tick }
local byVehicle = {}    -- [vehicle] = player
local cooldown = {}     -- [player] = tick
local nearPoint = {}    -- [player] = indice de punto
local points = {}       -- [i] = { cfg, marker, colshape, blip }

addEvent("rp:onCharacterLogout", false)
addEvent("rp:bikes:rent", true)

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

----------------------------------------------------------------
-- Cierre del arriendo (unico punto de limpieza)
----------------------------------------------------------------
local function closeRental(player, reason)
    local rental = rentals[player]
    if not rental then return false end
    rentals[player] = nil

    for _, t in ipairs(rental.timers) do
        if isTimer(t) then killTimer(t) end
    end

    local vehicle = rental.vehicle
    byVehicle[vehicle] = nil
    if isElement(vehicle) then
        -- bajar a quien vaya montado antes de borrar
        for _, occupant in pairs(getVehicleOccupants(vehicle)) do
            if isElement(occupant) then removePedFromVehicle(occupant) end
        end
        destroyElement(vehicle)
    end

    if reason and isElement(player) then
        notify(player, reason, "info")
    end
    return true
end

function hasActiveBikeRental(player)
    return rentals[player] ~= nil
end

function returnBike(player)
    return closeRental(player, "Devolviste la bicicleta.")
end

----------------------------------------------------------------
-- Arriendo
----------------------------------------------------------------
local function charge(player)
    local price = math.floor(tonumber(BIKES.PRICE) or 0)
    if price <= 0 or BIKES.PAYMENT == "none" then return true end

    if getPlayerMoney(player) < price then return false, price end
    takePlayerMoney(player, price)
    exports.rp_characters:saveCharacter(player)
    return true
end

local function refund(player)
    local price = math.floor(tonumber(BIKES.PRICE) or 0)
    if price > 0 and BIKES.PAYMENT ~= "none" and isElement(player) then
        givePlayerMoney(player, price)
        exports.rp_characters:saveCharacter(player)
    end
end

local function isNearPoint(player, index)
    local p = points[index]
    if not p then return false end
    local c = p.cfg
    if getElementDimension(player) ~= (c.dimension or 0) or getElementInterior(player) ~= (c.interior or 0) then return false end
    local px, py, pz = getElementPosition(player)
    return getDistanceBetweenPoints3D(px, py, pz, c.x, c.y, c.z) <= BIKES.INTERACT_RADIUS + 1.5
end

addEventHandler("rp:bikes:rent", resourceRoot, function(index)
    local player = client
    if not player then return end

    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < BIKES.COOLDOWN then return end
    cooldown[player] = now

    index = tonumber(index)
    if not index or index ~= math.floor(index) or not characterOf(player) then return end
    if getElementData(player, "rp:downed") or isPedDead(player) then return end
    if isPedInVehicle(player) then return notify(player, "Bajate del vehiculo para arrendar una bicicleta.", "warning") end
    if not isNearPoint(player, index) then return notify(player, "Estas demasiado lejos del punto de arriendo.", "warning") end
    if rentals[player] then return notify(player, "Ya tienes una bicicleta arrendada. Devuelvela con /devolverbici.", "warning") end

    local ok, price = charge(player)
    if not ok then return notify(player, ("Necesitas $%d en efectivo para arrendar una bicicleta."):format(price), "error") end

    local c = points[index].cfg
    local model = BIKES.MODELS[math.random(#BIKES.MODELS)]
    local vehicle = createVehicle(model, c.x, c.y, c.z + 0.6, 0, 0, c.rot or 0)
    if not vehicle then
        refund(player)
        return notify(player, "No se pudo crear la bicicleta. No se cobro nada.", "error")
    end
    setElementInterior(vehicle, c.interior or 0)
    setElementDimension(vehicle, c.dimension or 0)
    setElementData(vehicle, "rp:bikeRental", characterOf(player))
    warpPedIntoVehicle(player, vehicle)

    local timers = {}
    local rental = { vehicle = vehicle, timers = timers, expires = now + BIKES.DURATION }
    rentals[player] = rental
    byVehicle[vehicle] = player

    -- Avisos previos y fin del arriendo
    for _, before in ipairs(BIKES.WARN_BEFORE) do
        local delay = BIKES.DURATION - before
        if delay > 0 then
            timers[#timers + 1] = setTimer(function()
                if isElement(player) and rentals[player] == rental then
                    notify(player, ("Tu arriendo de bicicleta termina en %d min."):format(math.ceil(before / 60000)), "warning")
                end
            end, delay, 1)
        end
    end
    timers[#timers + 1] = setTimer(function()
        if rentals[player] == rental then
            closeRental(player, "Se acabo el tiempo de arriendo: la bicicleta fue retirada.")
        end
    end, BIKES.DURATION, 1)

    notify(player, ("Arrendaste una bicicleta por %d min%s."):format(
        math.floor(BIKES.DURATION / 60000), (price and price > 0) and (" ($" .. price .. ")") or ""), "success")
end)

----------------------------------------------------------------
-- Proteccion y limpieza
----------------------------------------------------------------
-- Solo el arrendatario conduce su bici
addEventHandler("onVehicleStartEnter", root, function(player, seat)
    local owner = byVehicle[source]
    if owner and seat == 0 and owner ~= player then
        cancelEvent()
        notify(player, "Esta bicicleta esta arrendada por otra persona.", "error")
    end
end)

-- Bici destruida o explotada: cierra el arriendo
addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    local owner = byVehicle[source]
    if owner and rentals[owner] and rentals[owner].vehicle == source then
        local rental = rentals[owner]
        rentals[owner] = nil
        byVehicle[source] = nil
        for _, t in ipairs(rental.timers) do
            if isTimer(t) then killTimer(t) end
        end
        if isElement(owner) then notify(owner, "Tu bicicleta fue destruida y el arriendo termino.", "warning") end
    end
end)

addEventHandler("onVehicleExplode", root, function()
    local owner = byVehicle[source]
    if owner then closeRental(owner) end
end)

addEventHandler("onPlayerQuit", root, function()
    closeRental(source)
    cooldown[source], nearPoint[source] = nil, nil
end)
addEventHandler("rp:onCharacterLogout", root, function() closeRental(source) end)
addEventHandler("onPlayerWasted", root, function() closeRental(source, "Perdiste la bicicleta arrendada.") end)

-- Abatido (rp_injury): pierde la bici
addEventHandler("onElementDataChange", root, function(key, _, new)
    if key == "rp:downed" and new and getElementType(source) == "player" then
        closeRental(source, "Perdiste la bicicleta arrendada.")
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(rentals) do closeRental(player) end
end)

----------------------------------------------------------------
-- Puntos de arriendo: marcador + blip + colshape
----------------------------------------------------------------
local function spawnPoints()
    for i, c in ipairs(BIKES.POINTS) do
        local m = BIKES.MARKER
        local marker = createMarker(c.x, c.y, c.z - 0.9, "cylinder", m.size, m.r, m.g, m.b, m.a)
        exports.rp_markers:setMarkerStyle(marker, { icon = "bike", label = "Arriendo de bicicletas" })
        local shape = createColSphere(c.x, c.y, c.z, BIKES.INTERACT_RADIUS)
        local blip
        if BIKES.BLIP.enabled then
            local b = BIKES.BLIP
            blip = createBlip(c.x, c.y, c.z, b.icon, b.size, b.r, b.g, b.b, 255, 0, b.visibleDistance)
        end
        for _, el in ipairs({ marker, shape }) do
            setElementInterior(el, c.interior or 0)
            setElementDimension(el, c.dimension or 0)
        end
        setElementData(shape, "rp:bikePoint", i, false)
        points[i] = { cfg = c, marker = marker, colshape = shape, blip = blip }
    end
    outputDebugString(("[rp_bikes] %d puntos de arriendo creados"):format(#points))
end

addEventHandler("onColShapeHit", resourceRoot, function(element, matchingDimension)
    if getElementType(element) ~= "player" or not matchingDimension then return end
    local index = getElementData(source, "rp:bikePoint")
    if not index then return end
    nearPoint[element] = index
    triggerClientEvent(element, "rp:bikes:near", resourceRoot, index, points[index].cfg.name, BIKES.PRICE, BIKES.PAYMENT ~= "none")
end)

addEventHandler("onColShapeLeave", resourceRoot, function(element)
    if getElementType(element) ~= "player" then return end
    local index = getElementData(source, "rp:bikePoint")
    if index and nearPoint[element] == index then
        nearPoint[element] = nil
        triggerClientEvent(element, "rp:bikes:near", resourceRoot, false)
    end
end)

addEventHandler("onResourceStart", resourceRoot, spawnPoints)

----------------------------------------------------------------
-- Comandos
----------------------------------------------------------------
addCommandHandler("devolverbici", function(player)
    if not rentals[player] then return notify(player, "No tienes ninguna bicicleta arrendada.", "warning") end
    returnBike(player)
end)

addCommandHandler("bicitiempo", function(player)
    local rental = rentals[player]
    if not rental then return notify(player, "No tienes ninguna bicicleta arrendada.", "warning") end
    local left = math.max(0, rental.expires - getTickCount())
    notify(player, ("Te quedan %d min %02d s de arriendo."):format(math.floor(left / 60000), math.floor(left / 1000) % 60), "info")
end)
