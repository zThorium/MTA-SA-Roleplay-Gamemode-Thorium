--[[
    rp_rides / s_rides.lua
    App de viajes Vroom (servidor).

    Pasajero: pide un viaje (con o sin destino) -> se ofrece a los conductores
    en servicio, primero a los de mejor calificacion -> si nadie lo toma en
    RIDES.SEARCH_TIME segundos, viene un conductor IA.
    Conductor jugador: activa "En servicio" en la app estando al volante,
    acepta un pedido, recoge al pasajero y el viaje termina cuando este se baja.
    Conductor IA: auto y ped del servidor conducidos por el cliente del pasajero
    (setElementSyncer); recoge, lleva y al llegar se aleja hasta desaparecer.

    Pago: la tarifa se cobra del banco (o del efectivo si no alcanza). El
    conductor jugador recibe la tarifa menos la comision en su banco.
    Al final el pasajero califica (1-5) y puede dejar propina; la nota media
    del conductor decide con cuanta prioridad recibe pedidos.
]]

local rides = {}      -- [passenger] = ride
local drivers = {}    -- [player] = { characterId, onDuty, ratingSum, ratingCount, rides, earnings, ride = passenger }
local pendingRate = {}-- [passenger] = { rideId, driverCharacterId, driver, ai, expires, name }
local cooldown = {}
local nextRideId = 0

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) if isElement(p) then exports.rp_notify:notify(p, t, k, d) end end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end

for _, e in ipairs({ "open", "request", "cancel", "setDest", "duty", "accept", "driverCancel", "rate",
    "aiSpawn", "aiArrived", "aiDropoff" }) do
    addEvent("rp:rides:" .. e, true)
end
addEvent("rp:onCharacterLogout", false)

local function throttled(player, ms)
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < (ms or 400) then return true end
    cooldown[player] = now
    return false
end

local function inMap(x, y)
    return type(x) == "number" and type(y) == "number" and x == x and y == y
        and x >= RIDES.MAP_MIN_X and x <= RIDES.MAP_MAX_X and y >= RIDES.MAP_MIN_Y and y <= RIDES.MAP_MAX_Y
end

----------------------------------------------------------------
-- Conductores: calificacion
----------------------------------------------------------------
local function ratingOf(d)
    if not d or d.ratingCount < RIDES.MIN_RATINGS then return RIDES.NEW_DRIVER_RATING, true end
    return d.ratingSum / d.ratingCount, false
end

local function driverInfo(player)
    local d = drivers[player]
    local rating, isNew = ratingOf(d)
    return {
        onDuty = d and d.onDuty or false, rating = math.floor(rating * 10 + 0.5) / 10, isNew = isNew,
        ratings = d and d.ratingCount or 0, rides = d and d.rides or 0, earnings = d and d.earnings or 0,
    }
end

local function loadDriver(player, callback)
    local characterId = characterOf(player)
    if not characterId then return end
    if drivers[player] and drivers[player].characterId == characterId then return callback and callback() end
    dbQuery(function(qh)
        local row = (dbPoll(qh, 0) or {})[1] or {}
        if not isElement(player) then return end
        drivers[player] = {
            characterId = characterId, onDuty = false,
            ratingSum = tonumber(row.rating_sum) or 0, ratingCount = tonumber(row.rating_count) or 0,
            rides = tonumber(row.rides) or 0, earnings = tonumber(row.earnings) or 0,
        }
        if callback then callback() end
    end, db(), "SELECT * FROM ride_drivers WHERE character_id = ?", characterId)
end

local function driverVehicle(player)
    local v = getPedOccupiedVehicle(player)
    if v and getVehicleController(v) == player and (getVehicleMaxPassengers(v) or 0) >= 1 then return v end
    return nil
end

----------------------------------------------------------------
-- Estado hacia los clientes
----------------------------------------------------------------
local function publicRide(ride)
    local info = {
        id = ride.id, state = ride.state, pickup = { ride.px, ride.py }, dest = ride.dest and { ride.dest[1], ride.dest[2] } or false,
        fare = ride.dest and rideFare(ride.px, ride.py, ride.dest[1], ride.dest[2]) or false,
        startedAt = ride.startedAt, searchTime = RIDES.SEARCH_TIME, ai = ride.ai ~= nil,
        passenger = nameOf(ride.passenger),
    }
    if ride.driver and isElement(ride.driver) then
        local v = getPedOccupiedVehicle(ride.driver)
        local di = driverInfo(ride.driver)
        info.driver = { name = nameOf(ride.driver), rating = di.rating, isNew = di.isNew,
            vehicle = v and getVehicleName(v) or "", plate = v and getVehiclePlateText(v) or "" }
    elseif ride.ai then
        info.driver = { name = ride.ai.name, rating = 5, ai = true, vehicle = getVehicleNameFromModel(RIDES.AI_MODEL), plate = "VROOM" }
    end
    return info
end

local function sendState(player)
    if not isElement(player) then return end
    local ride = rides[player]
    local d = drivers[player]
    local driving = d and d.ride and rides[d.ride]
    triggerClientEvent(player, "rp:rides:state", resourceRoot, {
        ride = ride and publicRide(ride) or false,
        driver = driverInfo(player),
        driving = driving and publicRide(driving) or false,
        rate = pendingRate[player] and { name = pendingRate[player].name, ai = pendingRate[player].ai, fare = pendingRate[player].fare } or false,
        money = getPlayerMoney(player),
    })
end

local function sendBoth(ride)
    sendState(ride.passenger)
    if ride.driver then sendState(ride.driver) end
end

----------------------------------------------------------------
-- Fin de un viaje
----------------------------------------------------------------
local function destroyAI(ride, fade)
    local ai = ride.ai
    if not ai then return end
    ride.ai = nil
    if isTimer(ai.timer) then killTimer(ai.timer) end
    local veh, ped = ai.vehicle, ai.ped
    if not fade then
        if isElement(ped) then destroyElement(ped) end
        if isElement(veh) then destroyElement(veh) end
        return
    end
    -- Se desvanece y desaparece (lo ven todos)
    local alpha = 255
    setTimer(function()
        alpha = alpha - 25
        if alpha <= 0 then
            if isElement(ped) then destroyElement(ped) end
            if isElement(veh) then destroyElement(veh) end
        else
            if isElement(veh) then setElementAlpha(veh, alpha) end
            if isElement(ped) then setElementAlpha(ped, alpha) end
        end
    end, 120, 11)
end

local function clearDriverMarks(ride)
    for _, el in ipairs({ ride.blipPassenger, ride.blipDriver, ride.blipDest }) do
        if isElement(el) then destroyElement(el) end
    end
    ride.blipPassenger, ride.blipDriver, ride.blipDest = nil, nil, nil
end

local function endRide(ride, reason)
    if rides[ride.passenger] ~= ride then return end
    rides[ride.passenger] = nil
    if isTimer(ride.timer) then killTimer(ride.timer) end
    clearDriverMarks(ride)
    if ride.driver and drivers[ride.driver] and drivers[ride.driver].ride == ride.passenger then
        drivers[ride.driver].ride = nil
        if isElement(ride.driver) then triggerClientEvent(ride.driver, "rp:rides:driverRoute", resourceRoot, false) end
    end
    if reason then notify(ride.passenger, reason, "info") end
    sendState(ride.passenger)
    if ride.driver then sendState(ride.driver) end
end

local function logTx(characterId, kind, amount, other)
    dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, ?, ?, ?)",
        characterId, kind, amount, other)
end

-- Cobra al pasajero: banco y, si no alcanza, efectivo. callback(pagado)
local function charge(player, characterId, amount, label, callback)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if affected and affected > 0 then
            logTx(characterId, "purchase", amount, label)
            return callback(amount, "banco")
        end
        if isElement(player) and getPlayerMoney(player) >= amount then
            takePlayerMoney(player, amount)
            exports.rp_characters:saveCharacter(player)
            return callback(amount, "efectivo")
        end
        callback(0)
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, characterId, amount)
end

local function payDriver(characterId, amount, label)
    if amount <= 0 then return end
    dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", amount, characterId)
    logTx(characterId, "sale", amount, label)
end

-- Termina un viaje con cobro y abre la calificacion
local function completeRide(ride, dropX, dropY)
    if ride.completed then return end
    ride.completed = true
    local passenger = ride.passenger
    local fare = rideFare(ride.px, ride.py, dropX, dropY)
    local distance = math.floor(getDistanceBetweenPoints2D(ride.px, ride.py, dropX, dropY))
    local driver, driverChar = ride.driver, ride.driverCharacterId
    local ai = ride.ai ~= nil
    local driverName = ai and ride.ai.name or (isElement(driver) and nameOf(driver) or "tu conductor")

    charge(passenger, ride.characterId, fare, "Viaje " .. RIDES.APP_NAME, function(paid, via)
        if paid > 0 then
            notify(passenger, ("Viaje terminado: $%d pagados con %s."):format(paid, via), "success")
        else
            notify(passenger, "No tenias dinero para pagar el viaje.", "error")
        end
        local earned = 0
        if not ai and driverChar and paid > 0 then
            earned = math.floor(paid * (1 - RIDES.COMMISSION))
            payDriver(driverChar, earned, "Viaje " .. RIDES.APP_NAME)
            dbExec(db(), [[
                INSERT INTO ride_drivers (character_id, rides, earnings) VALUES (?, 1, ?)
                ON DUPLICATE KEY UPDATE rides = rides + 1, earnings = earnings + VALUES(earnings)
            ]], driverChar, earned)
            local d = isElement(driver) and drivers[driver]
            if d then d.rides, d.earnings = d.rides + 1, d.earnings + earned end
            if isElement(driver) then notify(driver, ("Viaje completado: ganaste $%d (comision %d%%)."):format(earned, RIDES.COMMISSION * 100), "success") end
        elseif not ai and isElement(driver) then
            notify(driver, "El pasajero no pudo pagar el viaje.", "warning")
        end

        dbQuery(function(qh)
            local ok, _, rideId = dbPoll(qh, 0)
            if not ok or not isElement(passenger) then return end
            pendingRate[passenger] = {
                rideId = rideId, driverCharacterId = not ai and driverChar or nil, driver = not ai and driver or nil,
                ai = ai, name = driverName, fare = paid, expires = getTickCount() + RIDES.RATE_TIME * 1000,
            }
            sendState(passenger)
            triggerClientEvent(passenger, "rp:rides:showApp", resourceRoot, "rate")
        end, db(), "INSERT INTO rides (passenger_id, driver_id, fare, distance) VALUES (?, ?, ?, ?)",
            ride.characterId, not ai and driverChar or nil, paid, distance)
    end)
end

----------------------------------------------------------------
-- Reparto de pedidos (prioridad por calificacion)
----------------------------------------------------------------
local function priorityDelay(player)
    local rating = ratingOf(drivers[player])
    for _, tier in ipairs(RIDES.PRIORITY) do
        if rating >= tier.rating then return tier.delay end
    end
    return RIDES.PRIORITY[#RIDES.PRIORITY].delay
end

local function availableDrivers(except)
    local list = {}
    for player, d in pairs(drivers) do
        if isElement(player) and player ~= except and d.onDuty and not d.ride and not rides[player]
            and characterOf(player) == d.characterId and driverVehicle(player) then
            list[#list + 1] = player
        end
    end
    return list
end

local function offerInfo(ride, driver)
    local dx, dy = getElementPosition(driver)
    return {
        id = ride.id, passenger = nameOf(ride.passenger), pickup = { ride.px, ride.py },
        distance = math.floor(getDistanceBetweenPoints2D(dx, dy, ride.px, ride.py)),
        dest = ride.dest and { ride.dest[1], ride.dest[2] } or false,
        fare = ride.dest and math.floor(rideFare(ride.px, ride.py, ride.dest[1], ride.dest[2]) * (1 - RIDES.COMMISSION)) or false,
    }
end

local dispatchAI

local function searchTick(ride)
    if rides[ride.passenger] ~= ride or ride.state ~= "searching" then return end
    local elapsed = (getTickCount() - ride.startedAt) / 1000
    for _, driver in ipairs(availableDrivers(ride.passenger)) do
        if not ride.offered[driver] and elapsed >= priorityDelay(driver) then
            ride.offered[driver] = true
            triggerClientEvent(driver, "rp:rides:offer", resourceRoot, offerInfo(ride, driver))
            notify(driver, ("%s: nuevo pedido de viaje. Abre la app para aceptarlo."):format(RIDES.APP_NAME), "info")
        end
    end
    if elapsed >= RIDES.SEARCH_TIME then
        for driver in pairs(ride.offered) do
            if isElement(driver) then triggerClientEvent(driver, "rp:rides:offerGone", resourceRoot, ride.id) end
        end
        dispatchAI(ride)
    end
end

local function findRideById(id)
    for _, ride in pairs(rides) do
        if ride.id == id then return ride end
    end
end

----------------------------------------------------------------
-- Pasajero
----------------------------------------------------------------
local function hasPhone(player)
    return characterOf(player) and exports.rp_inventory:hasItem(player, "phone", 1)
end

addEventHandler("rp:rides:open", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not characterOf(player) then return end
    loadDriver(player, function() sendState(player) end)
end)

addEventHandler("rp:rides:request", resourceRoot, function(dx, dy)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local characterId = characterOf(player)
    if not characterId or rides[player] or throttled(player, 1500) then return end
    if not hasPhone(player) then return notify(player, "Necesitas un telefono para pedir un viaje.", "error") end
    if pendingRate[player] then pendingRate[player] = nil end
    if drivers[player] and drivers[player].ride then return notify(player, "Estas haciendo un viaje como conductor.", "error") end
    if isPedInVehicle(player) then return notify(player, "Bajate del vehiculo para pedir un viaje.", "error") end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then return notify(player, "Sal a la calle para pedir un viaje.", "error") end
    local px, py, pz = getElementPosition(player)
    if not inMap(px, py) then return notify(player, RIDES.APP_NAME .. " solo funciona en Los Santos.", "error") end
    dx, dy = tonumber(dx), tonumber(dy)
    local dest = (dx and dy and inMap(dx, dy)) and { dx, dy } or nil
    if dest and getDistanceBetweenPoints2D(px, py, dx, dy) < 60 then return notify(player, "El destino esta demasiado cerca.", "warning") end

    nextRideId = nextRideId + 1
    local ride = {
        id = nextRideId, passenger = player, characterId = characterId, px = px, py = py, pz = pz,
        dest = dest, state = "searching", startedAt = getTickCount(), offered = {},
    }
    rides[player] = ride
    ride.timer = setTimer(searchTick, 1000, 0, ride)
    searchTick(ride)
    sendState(player)
end)

addEventHandler("rp:rides:cancel", resourceRoot, function()
    local player = client
    local ride = rides[player]
    if not ride or ride.state == "riding" then return end
    for driver in pairs(ride.offered or {}) do
        if isElement(driver) then triggerClientEvent(driver, "rp:rides:offerGone", resourceRoot, ride.id) end
    end
    if ride.driver then notify(ride.driver, "El pasajero cancelo el viaje.", "warning") end
    destroyAI(ride, true)
    endRide(ride, "Viaje cancelado.")
end)

addEventHandler("rp:rides:setDest", resourceRoot, function(dx, dy)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local ride = rides[player]
    dx, dy = tonumber(dx), tonumber(dy)
    if not ride or not inMap(dx, dy) or throttled(player) then return end
    local x, y = getElementPosition(player)
    if getDistanceBetweenPoints2D(x, y, dx, dy) < 60 then return notify(player, "El destino esta demasiado cerca.", "warning") end
    ride.dest = { dx, dy }
    if ride.driver and isElement(ride.driver) then
        if isElement(ride.blipDest) then destroyElement(ride.blipDest) end
        ride.blipDest = createBlip(dx, dy, 0, 41, 2, 255, 255, 255, 255, 0, 99999, ride.driver)
        triggerClientEvent(ride.driver, "rp:rides:driverRoute", resourceRoot, { dx, dy })
        notify(ride.driver, "El pasajero marco su destino en tu mapa.", "info")
    end
    if ride.ai and ride.state == "riding" then
        triggerClientEvent(player, "rp:rides:aiDrive", resourceRoot, ride.ai.vehicle, ride.ai.ped, "ride", dx, dy)
    end
    sendBoth(ride)
end)

addEventHandler("rp:rides:rate", resourceRoot, function(stars, tip)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local p = pendingRate[player]
    stars, tip = tonumber(stars), math.floor(tonumber(tip) or 0)
    if not p or not stars or stars ~= math.floor(stars) or stars < 1 or stars > 5 then return end
    pendingRate[player] = nil
    tip = math.max(0, math.min(RIDES.MAX_TIP, tip))
    if p.ai then tip = 0 end

    dbExec(db(), "UPDATE rides SET rating = ? WHERE id = ?", stars, p.rideId)
    if p.driverCharacterId then
        dbExec(db(), [[
            INSERT INTO ride_drivers (character_id, rating_sum, rating_count) VALUES (?, ?, 1)
            ON DUPLICATE KEY UPDATE rating_sum = rating_sum + VALUES(rating_sum), rating_count = rating_count + 1
        ]], p.driverCharacterId, stars)
        local d = isElement(p.driver) and drivers[p.driver]
        if d and d.characterId == p.driverCharacterId then d.ratingSum, d.ratingCount = d.ratingSum + stars, d.ratingCount + 1 end
        if isElement(p.driver) then notify(p.driver, ("Tu pasajero te califico con %d estrella%s."):format(stars, stars == 1 and "" or "s"), "info") end
    end

    local characterId = characterOf(player)
    if tip > 0 and characterId and p.driverCharacterId then
        charge(player, characterId, tip, "Propina " .. RIDES.APP_NAME, function(paid)
            if paid > 0 then
                payDriver(p.driverCharacterId, paid, "Propina " .. RIDES.APP_NAME)
                dbExec(db(), "UPDATE rides SET tip = ? WHERE id = ?", paid, p.rideId)
                notify(player, ("Gracias. Dejaste $%d de propina."):format(paid), "success")
                if isElement(p.driver) then notify(p.driver, ("Recibiste $%d de propina."):format(paid), "success") end
            else
                notify(player, "No tienes dinero para la propina.", "error")
            end
            sendState(player)
        end)
    else
        notify(player, "Gracias por calificar tu viaje.", "success")
        sendState(player)
    end
end)

----------------------------------------------------------------
-- Conductor jugador
----------------------------------------------------------------
addEventHandler("rp:rides:duty", resourceRoot, function(state)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not characterOf(player) or throttled(player) then return end
    if state == true and not hasPhone(player) then return notify(player, "Necesitas un telefono.", "error") end
    loadDriver(player, function()
        local d = drivers[player]
        if state == true then
            if not driverVehicle(player) then return notify(player, "Debes estar al volante de un vehiculo con asientos para pasajeros.", "error") end
            d.onDuty = true
            notify(player, ("Estas en servicio en %s. Los pedidos llegan antes cuanto mejor sea tu calificacion."):format(RIDES.APP_NAME), "success", 7000)
            -- Pedidos que ya estan buscando
            for _, ride in pairs(rides) do
                if ride.state == "searching" then searchTick(ride) end
            end
        else
            if d.ride then return notify(player, "Termina o cancela tu viaje actual primero.", "error") end
            d.onDuty = false
            notify(player, "Saliste de servicio.", "info")
        end
        sendState(player)
    end)
end)

addEventHandler("rp:rides:accept", resourceRoot, function(rideId)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local d = drivers[player]
    local ride = findRideById(tonumber(rideId))
    if not d or not d.onDuty or d.ride or throttled(player) then return end
    if not ride or ride.state ~= "searching" or not ride.offered[player] then
        return notify(player, "Ese pedido ya no esta disponible.", "warning")
    end
    local vehicle = driverVehicle(player)
    if not vehicle then return notify(player, "Debes estar al volante para aceptar.", "error") end

    ride.state = "assigned"
    ride.driver, ride.driverCharacterId, ride.vehicle = player, d.characterId, vehicle
    d.ride = ride.passenger
    for other in pairs(ride.offered) do
        if other ~= player and isElement(other) then triggerClientEvent(other, "rp:rides:offerGone", resourceRoot, ride.id) end
    end
    ride.blipPassenger = createBlipAttachedTo(ride.passenger, 0, 3, 245, 165, 36, 255, 0, 99999, player)
    ride.blipDriver = createBlipAttachedTo(vehicle, 0, 3, 76, 211, 138, 255, 0, 99999, ride.passenger)
    if ride.dest then ride.blipDest = createBlip(ride.dest[1], ride.dest[2], 0, 41, 2, 255, 255, 255, 255, 0, 99999, player) end
    triggerClientEvent(player, "rp:rides:driverRoute", resourceRoot, { ride.px, ride.py }, true)
    notify(player, ("Aceptaste el viaje de %s. Ve a buscarlo (marca en el mapa)."):format(nameOf(ride.passenger)), "success", 7000)
    exports.rp_notify:popup(ride.passenger, RIDES.APP_NAME, ("%s acepto tu viaje y va en camino en un %s."):format(nameOf(player), getVehicleName(vehicle)), "success")
    sendBoth(ride)
end)

addEventHandler("rp:rides:driverCancel", resourceRoot, function()
    local player = client
    local d = drivers[player]
    local ride = d and d.ride and rides[d.ride]
    if not ride or ride.state == "riding" then return end
    notify(ride.passenger, "El conductor cancelo. Buscando otro...", "warning")
    clearDriverMarks(ride)
    d.ride = nil
    ride.driver, ride.driverCharacterId, ride.vehicle = nil, nil, nil
    ride.state, ride.startedAt, ride.offered = "searching", getTickCount(), { [player] = true }
    triggerClientEvent(player, "rp:rides:driverRoute", resourceRoot, false)
    sendBoth(ride)
    sendState(player)
end)

----------------------------------------------------------------
-- Conductor IA
----------------------------------------------------------------
local AI_NAMES = { "Marco", "Lucia", "Andres", "Sofia", "Diego", "Valeria", "Tomas", "Camila" }

dispatchAI = function(ride)
    if ride.state ~= "searching" then return end
    ride.state = "ai_spawning"
    if isTimer(ride.timer) then killTimer(ride.timer) end
    ride.timer = nil
    -- El cliente del pasajero conoce la red vial y elige un punto de la calle fuera de la vista
    triggerClientEvent(ride.passenger, "rp:rides:aiSpawnRequest", resourceRoot, ride.id)
    sendState(ride.passenger)
    -- Si el cliente no responde, se cancela
    ride.timer = setTimer(function()
        if rides[ride.passenger] == ride and ride.state == "ai_spawning" then
            endRide(ride, "No hay conductores disponibles ahora. Intentalo de nuevo.")
        end
    end, 10000, 1)
end

addEventHandler("rp:rides:aiSpawn", resourceRoot, function(rideId, x, y, z, rot, clientErr)
    local player = client
    local ride = rides[player]
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot) or 0
    if not ride or ride.id ~= rideId or ride.state ~= "ai_spawning" then
        return outputServerLog("[rp_rides] aiSpawn ignorado: viaje/estado no coincide")
    end
    local px, py, pz = getElementPosition(player)
    if not (x and y and z) then
        -- El cliente no pudo elegir un punto (p. ej. sin red vial): aparece a 120 m en linea recta
        outputServerLog("[rp_rides] el cliente no envio punto de aparicion (" .. tostring(clientErr) .. "); se usa uno de reserva")
        local a = math.random() * math.pi * 2
        x, y, z, rot = px + math.cos(a) * 120, py + math.sin(a) * 120, pz, math.deg(a) + 90
    end
    local dist = getDistanceBetweenPoints2D(px, py, x, y)
    if dist < 30 or dist > 300 then
        return outputServerLog(("[rp_rides] aiSpawn rechazado: distancia %.0f m fuera de 30-300"):format(dist))
    end
    if isTimer(ride.timer) then killTimer(ride.timer) end

    local vehicle = createVehicle(RIDES.AI_MODEL, x, y, z + 0.6, 0, 0, rot, "VROOM")
    if not vehicle then return endRide(ride, "No se pudo enviar el conductor.") end
    local c = RIDES.AI_COLOR
    setVehicleColor(vehicle, c[1], c[2], c[3], c[1], c[2], c[3])
    setVehicleDamageProof(vehicle, true)
    setVehicleEngineState(vehicle, true)
    setElementData(vehicle, "rp:rides:ai", ride.id)
    local ped = createPed(RIDES.AI_SKINS[math.random(#RIDES.AI_SKINS)], x, y, z + 1)
    warpPedIntoVehicle(ped, vehicle, 0)
    setElementData(ped, "rp:rides:ai", ride.id)
    -- El cliente del pasajero conduce al NPC
    -- persist = true: si no, MTA quita el control a mas de 100 m del ped y el auto no arranca
    setElementSyncer(vehicle, player, true)
    setElementSyncer(ped, player, true)

    ride.ai = { vehicle = vehicle, ped = ped, name = AI_NAMES[math.random(#AI_NAMES)] .. " (" .. RIDES.APP_NAME .. " Auto)" }
    ride.state = "assigned"
    ride.blipDriver = createBlipAttachedTo(vehicle, 0, 3, 76, 211, 138, 255, 0, 99999, player)
    triggerClientEvent(player, "rp:rides:aiDrive", resourceRoot, vehicle, ped, "pickup")
    exports.rp_notify:popup(player, RIDES.APP_NAME, "No hay conductores cerca: un auto automatico de " .. RIDES.APP_NAME .. " va en camino.", "info")
    sendState(player)
end)

addEventHandler("rp:rides:aiArrived", resourceRoot, function()
    local player = client
    local ride = rides[player]
    if not ride or not ride.ai or ride.state ~= "assigned" then return end
    local vx, vy, vz = getElementPosition(ride.ai.vehicle)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(vx, vy, vz, px, py, pz) > 40 then return end
    ride.state = "arrived"
    ride.px, ride.py = px, py
    exports.rp_notify:popup(player, RIDES.APP_NAME, "Tu auto llego. Subete en un asiento de pasajero (G).", "success")
    ride.timer = setTimer(function()
        if rides[player] == ride and ride.state == "arrived" then
            destroyAI(ride, true)
            endRide(ride, "No subiste a tiempo y el viaje se cancelo.")
        end
    end, RIDES.BOARD_TIME * 1000, 1)
    sendState(player)
end)

addEventHandler("rp:rides:aiDropoff", resourceRoot, function()
    local player = client
    local ride = rides[player]
    if not ride or not ride.ai or ride.state ~= "riding" or not ride.dest then return end
    local vehicle = ride.ai.vehicle
    if getPedOccupiedVehicle(player) ~= vehicle then return end
    local vx, vy = getElementPosition(vehicle)
    if getDistanceBetweenPoints2D(vx, vy, ride.dest[1], ride.dest[2]) > 60 then return end

    -- Baja al pasajero por la derecha (lado de la acera)
    local m = getElementMatrix(vehicle)
    local x, y, z = getElementPosition(vehicle)
    removePedFromVehicle(player)
    setElementPosition(player, x + m[1][1] * 2.4, y + m[1][2] * 2.4, z + 0.3)
    ride.dropped = true
    completeRide(ride, ride.dest[1], ride.dest[2])
    -- ride.dropped evita que onPlayerVehicleExit lo cobre dos veces; el viaje se cierra aqui
    local ai = ride.ai
    endRide(ride)
    triggerClientEvent(player, "rp:rides:aiDrive", resourceRoot, ai.vehicle, ai.ped, "leave")
    ride.ai = ai
    ai.timer = setTimer(destroyAI, RIDES.AI_LEAVE_TIME * 1000, 1, ride, true)
end)

----------------------------------------------------------------
-- Subir y bajar
----------------------------------------------------------------
-- Autos IA: solo el pasajero del viaje y solo en asientos de pasajero
addEventHandler("onVehicleStartEnter", root, function(player, seat)
    local rideId = getElementData(source, "rp:rides:ai")
    if not rideId then return end
    local ride = rides[player]
    if seat == 0 or not ride or ride.id ~= rideId or ride.state ~= "arrived" then
        cancelEvent()
        if seat == 0 then notify(player, "Este es un auto automatico de " .. RIDES.APP_NAME .. ".", "warning") end
    end
end)

local function startRiding(ride)
    ride.state = "riding"
    if isTimer(ride.timer) then killTimer(ride.timer) end
    local px, py = getElementPosition(ride.passenger)
    ride.px, ride.py = px, py
    if ride.ai then
        if ride.dest then
            triggerClientEvent(ride.passenger, "rp:rides:aiDrive", resourceRoot, ride.ai.vehicle, ride.ai.ped, "ride", ride.dest[1], ride.dest[2])
        else
            notify(ride.passenger, "Elige tu destino en el mapa de la app.", "info")
        end
        triggerClientEvent(ride.passenger, "rp:rides:showApp", resourceRoot, ride.dest and "ride" or "pick")
    else
        if isElement(ride.blipPassenger) then destroyElement(ride.blipPassenger) end
        if isElement(ride.blipDriver) then destroyElement(ride.blipDriver) end
        triggerClientEvent(ride.driver, "rp:rides:driverRoute", resourceRoot, ride.dest and { ride.dest[1], ride.dest[2] } or false)
        notify(ride.driver, ride.dest and "El pasajero subio. Llevalo a la marca del mapa." or "El pasajero subio y esta eligiendo destino.", "info")
        notify(ride.passenger, "Buen viaje. El viaje termina cuando te bajes.", "info")
        triggerClientEvent(ride.passenger, "rp:rides:showApp", resourceRoot, ride.dest and "ride" or "pick")
    end
    sendBoth(ride)
end

addEventHandler("onPlayerVehicleEnter", root, function(vehicle, seat)
    local ride = rides[source]
    if not ride or seat == 0 then return end
    if ride.ai and vehicle == ride.ai.vehicle and ride.state == "arrived" then return startRiding(ride) end
    if ride.driver and ride.state == "assigned" and getVehicleController(vehicle) == ride.driver then return startRiding(ride) end
end)

addEventHandler("onPlayerVehicleExit", root, function(vehicle)
    local player = source
    local ride = rides[player]
    if ride and ride.state == "riding" and not ride.dropped then
        local x, y = getElementPosition(player)
        local ai = ride.ai
        completeRide(ride, x, y)
        endRide(ride)
        if ai then
            ride.ai = ai
            triggerClientEvent(player, "rp:rides:aiDrive", resourceRoot, ai.vehicle, ai.ped, "leave")
            ai.timer = setTimer(destroyAI, RIDES.AI_LEAVE_TIME * 1000, 1, ride, true)
        end
        return
    end
    -- El conductor se bajo de su vehiculo con un viaje en curso
    local d = drivers[player]
    local dRide = d and d.ride and rides[d.ride]
    if dRide and dRide.state == "riding" and dRide.vehicle == vehicle then
        local x, y = getElementPosition(dRide.passenger)
        completeRide(dRide, x, y)
        endRide(dRide, "El conductor termino el viaje.")
    end
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
local function forget(player)
    local ride = rides[player]
    if ride then
        if ride.driver then notify(ride.driver, "El pasajero se desconecto.", "warning") end
        destroyAI(ride, false)
        endRide(ride)
    end
    local d = drivers[player]
    if d and d.ride and rides[d.ride] then
        local r = rides[d.ride]
        if r.state == "riding" then
            local x, y = getElementPosition(r.passenger)
            completeRide(r, x, y)
            endRide(r, "El conductor se desconecto. El viaje termino.")
        else
            notify(r.passenger, "El conductor se desconecto. Buscando otro...", "warning")
            clearDriverMarks(r)
            r.driver, r.driverCharacterId, r.vehicle = nil, nil, nil
            r.state, r.startedAt, r.offered = "searching", getTickCount(), {}
            if not isTimer(r.timer) then r.timer = setTimer(searchTick, 1000, 0, r) end
            sendState(r.passenger)
        end
    end
    drivers[player], pendingRate[player], cooldown[player] = nil, nil, nil
end

addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
local function cancelOnDeath()
    local ride = rides[source]
    if ride and ride.state ~= "riding" then
        destroyAI(ride, true)
        endRide(ride, "Tu viaje se cancelo.")
    end
end
addEventHandler("onPlayerWasted", root, cancelOnDeath)
addEvent("rp:onPlayerDowned", false)
addEventHandler("rp:onPlayerDowned", root, cancelOnDeath)   -- abatido (rp_injury)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, ride in pairs(rides) do destroyAI(ride, false) end
end)

-- Fuera de servicio si deja de conducir
setTimer(function()
    for player, d in pairs(drivers) do
        if not isElement(player) then
            drivers[player] = nil
        elseif d.onDuty and not d.ride and not driverVehicle(player) then
            d.onDuty = false
            notify(player, "Saliste de servicio en " .. RIDES.APP_NAME .. " (ya no conduces).", "info")
            sendState(player)
        end
    end
end, 5000, 0)

addCommandHandler("vroom", function(player)
    if not characterOf(player) then return end
    if not hasPhone(player) then return notify(player, "Necesitas un telefono.", "error") end
    triggerClientEvent(player, "rp:rides:showApp", resourceRoot, "toggle")
end)
