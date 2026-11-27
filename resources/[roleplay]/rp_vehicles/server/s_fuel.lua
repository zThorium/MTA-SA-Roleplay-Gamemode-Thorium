--[[
    rp_vehicles / s_fuel.lua
    Bencina de los vehiculos y bencineras con bombero.

    Consumo: cada FUEL.TICK ms, los vehiculos con el motor encendido gastan
    bencina segun la distancia recorrida y el tiempo en ralenti. Sin bencina el
    motor se apaga y no vuelve a encender. Los litros se publican en el
    elementData "rp:fuel" (y la capacidad en "rp:fuelMax") para el velocimetro
    de rp_hud. Los autos con dueno guardan la bencina en vehicles.fuel.

    Bencinera (una atencion a la vez por bencinera):
      1. El conductor entra al marcador y pulsa E: el bombero camina a la ventana.
      2. Se elige cuantos litros (o lleno) en el dialogo.
      3. El bombero va a la tapa del tanque y carga de a poco (sube en el velocimetro).
      4. Vuelve a la ventana con el datafono: se paga con tarjeta (clave) o efectivo.
    Si el conductor se baja o se va sin pagar, se cobra lo cargado de su cuenta
    (o en efectivo si no le alcanza).

    Admin: /nearbybencineras [radio], /moverbencinera <n> (en tu auto),
           /moverbombero <n> (a pie, donde quieres que espere), /setfuel [litros] [id]
]]

local fuel = {}       -- [vehicle] = litros
local lastPos = {}    -- [vehicle] = { x, y, z }
local warned = {}     -- [vehicle] = true si ya se aviso de la reserva
local sessions = {}   -- [player] = sesion de carga
local byVehicle = {}  -- [vehicle] = sesion

addEvent("rp:fuel:call", true)
addEvent("rp:fuel:order", true)
addEvent("rp:fuel:cancel", true)
addEvent("rp:fuel:pay", true)

----------------------------------------------------------------
-- Litros por vehiculo
----------------------------------------------------------------
local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

local function publish(vehicle, force)
    local liters = fuel[vehicle]
    if not liters then return end
    local shown = getElementData(vehicle, "rp:fuel")
    if force or not shown or math.abs(shown - liters) >= 0.1 then
        setElementData(vehicle, "rp:fuel", round1(liters))
    end
end

-- liters nil = tanque lleno
function initFuel(vehicle, liters)
    local model = getElementModel(vehicle)
    if not usesFuel(model) then return end
    local cap = getFuelCapacity(model)
    fuel[vehicle] = math.max(0, math.min(cap, tonumber(liters) or cap))
    setElementData(vehicle, "rp:fuelMax", cap)
    publish(vehicle, true)
end

-- Vehiculos sin bencina (bicis, aviones...) devuelven math.huge
function getVehicleFuel(vehicle)
    if not isElement(vehicle) or not usesFuel(getElementModel(vehicle)) then return math.huge end
    if not fuel[vehicle] then initFuel(vehicle) end
    return fuel[vehicle] or math.huge
end

function setVehicleFuel(vehicle, liters)
    if not isElement(vehicle) or not usesFuel(getElementModel(vehicle)) then return false end
    if not fuel[vehicle] then initFuel(vehicle) end
    local cap = getFuelCapacity(getElementModel(vehicle))
    fuel[vehicle] = math.max(0, math.min(cap, liters))
    if fuel[vehicle] > cap * FUEL.LOW then warned[vehicle] = nil end
    publish(vehicle, true)
    return true
end

function isRefueling(vehicle)
    return byVehicle[vehicle] ~= nil
end

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    fuel[source], lastPos[source], warned[source] = nil, nil, nil
end)

-- Los vehiculos creados por otros recursos empiezan con el tanque lleno
addEventHandler("onResourceStart", resourceRoot, function()
    for _, v in ipairs(getElementsByType("vehicle")) do
        if not fuel[v] then initFuel(v, getElementData(v, "rp:fuel")) end
    end
end)

local function runOut(vehicle)
    if setEngine then setEngine(vehicle, false) else setVehicleEngineState(vehicle, false) end
    local driver = getVehicleController(vehicle)
    if driver then notify(driver, "Te quedaste sin bencina. Empuja el auto o llama a alguien que te ayude.", "error") end
end

setTimer(function()
    local idle = FUEL.IDLE_PER_MIN * FUEL.TICK / 60000
    for _, v in ipairs(getElementsByType("vehicle")) do
        if usesFuel(getElementModel(v)) then
            if not fuel[v] then initFuel(v) end
            local x, y, z = getElementPosition(v)
            local last = lastPos[v]
            lastPos[v] = { x, y, z }
            if getVehicleEngineState(v) and not byVehicle[v] then
                local dist = last and getDistanceBetweenPoints3D(x, y, z, last[1], last[2], last[3]) or 0
                if dist > 400 then dist = 0 end   -- teletransporte
                local before = fuel[v]
                fuel[v] = math.max(0, before - dist / 1000 * FUEL.PER_KM * (getPerfFuelFactor and getPerfFuelFactor(v) or 1) - idle)
                local cap = getFuelCapacity(getElementModel(v))
                if fuel[v] <= 0 then
                    runOut(v)
                elseif fuel[v] <= cap * FUEL.LOW and not warned[v] then
                    warned[v] = true
                    local driver = getVehicleController(v)
                    if driver then notify(driver, "Vas en reserva: carga bencina pronto.", "warning") end
                end
                publish(v)
            end
        end
    end
end, FUEL.TICK, 0)

----------------------------------------------------------------
-- Bencineras
----------------------------------------------------------------
local STATIONS_FILE = "fuel_stations.json"
local stations = {}
local stationElements = {}
local stationOfMarker = {}

local function loadStations()
    stations = {}
    for i, st in ipairs(FUEL.STATIONS) do
        stations[i] = { index = i, name = st.name, x = st.x, y = st.y, z = st.z, px = st.px, py = st.py, pz = st.pz, prz = st.prz or 0 }
    end
    if not fileExists(STATIONS_FILE) then return end
    local f = fileOpen(STATIONS_FILE, true)
    local saved = f and fromJSON(fileRead(f, fileGetSize(f)))
    if f then fileClose(f) end
    if type(saved) ~= "table" then return end
    for k, pos in pairs(saved) do
        local st = stations[tonumber(k)]
        if st and type(pos) == "table" then
            for _, key in ipairs({ "x", "y", "z", "px", "py", "pz", "prz" }) do
                if tonumber(pos[key]) then st[key] = tonumber(pos[key]) end
            end
        end
    end
end

local function saveStations()
    local out = {}
    for i, st in ipairs(stations) do
        out[tostring(i)] = { x = st.x, y = st.y, z = st.z, px = st.px, py = st.py, pz = st.pz, prz = st.prz }
    end
    if fileExists(STATIONS_FILE) then fileDelete(STATIONS_FILE) end
    local f = fileCreate(STATIONS_FILE)
    if f then fileWrite(f, toJSON(out, true)) fileClose(f) end
end

local function spawnAttendant(st)
    if isElement(st.ped) then destroyElement(st.ped) end
    local ped = createPed(FUEL.ATTENDANT_SKIN, st.px, st.py, st.pz, st.prz)
    if not ped then return end
    setElementRotation(ped, 0, 0, st.prz, "default", true)
    -- Sin sincronizador: los clientes animan la caminata y no se pelean por la posicion
    setElementSyncer(ped, false)
    setElementData(ped, "rp:attendant", st.index)
    st.ped = ped
end

local function buildStations()
    for _, el in ipairs(stationElements) do if isElement(el) then destroyElement(el) end end
    for _, st in ipairs(stations) do if isElement(st.ped) then destroyElement(st.ped) end end
    stationElements, stationOfMarker = {}, {}
    for i, st in ipairs(stations) do
        local m = createMarker(st.x, st.y, st.z - 1, "cylinder", FUEL.MARKER_RADIUS, 255, 210, 40, 70)
        setElementData(m, "rp:fuelStation", st.name)
        exports.rp_markers:setMarkerStyle(m, { icon = "fuel", label = st.name })
        exports.rp_markers:registerMarker(m, "station" .. i, { label = "Bencinera · " .. st.name, point = { st.x, st.y, st.z }, ownerSaves = true })
        stationOfMarker[m] = st
        st.marker = m
        stationElements[#stationElements + 1] = m
        stationElements[#stationElements + 1] = createBlip(st.x, st.y, st.z, 51, 2, 0, 0, 0, 255, 0, 600)
        spawnAttendant(st)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadStations()
    buildStations()
end)

-- Un admin movio la bencinera con el editor (rp_admin): se guarda como con /moverbencinera
addEvent("rp:markers:moved")
addEventHandler("rp:markers:moved", root, function(owner, key, x, y, z)
    if owner ~= getResourceName(resource) then return end
    local st = stations[tonumber(tostring(key):match("^station(%d+)$")) or -1]
    if not st or not x then return end
    st.x, st.y, st.z = x, y, z
    saveStations()
    buildStations()
end)

addEventHandler("onPedWasted", resourceRoot, function()
    local index = getElementData(source, "rp:attendant")
    local st = index and stations[index]
    if st then setTimer(function() spawnAttendant(st) end, 5000, 1) end
end)

function getFuelStations() return stations end

local function stationOf(vehicle)
    for m, st in pairs(stationOfMarker) do
        if isElement(m) and isElementWithinMarker(vehicle, m) then return st end
    end
end

local function driverOf(element)
    if getElementType(element) == "vehicle" then return getVehicleController(element) end
    if getElementType(element) == "player" then return element end
end

addEventHandler("onMarkerHit", resourceRoot, function(element, dim)
    local st = stationOfMarker[source]
    local player = st and dim and driverOf(element)
    if not player or getElementType(player) ~= "player" then return end
    local v = getPedOccupiedVehicle(player)
    if v and getVehicleController(v) == player and usesFuel(getElementModel(v)) then
        triggerClientEvent(player, "rp:fuel:near", resourceRoot, st.name)
    end
end)

addEventHandler("onMarkerLeave", resourceRoot, function(element)
    local player = stationOfMarker[source] and driverOf(element)
    if player and getElementType(player) == "player" then
        triggerClientEvent(player, "rp:fuel:near", resourceRoot, false)
    end
end)

----------------------------------------------------------------
-- Bombero: caminar, hablar, animaciones
----------------------------------------------------------------
local WALK_SPEED = 1.5   -- m/s

local function say(st, text)
    if isElement(st.ped) then triggerClientEvent(root, "rp:fuel:say", st.ped, text) end
end

local function lookAt(ped, x, y)
    local px, py = getElementPosition(ped)
    local rz = math.deg(math.atan2(y - py, x - px)) - 90
    setElementRotation(ped, 0, 0, rz, "default", true)
end

-- Camina hasta (x, y, z) y llama a done() al llegar
local function walkTo(st, x, y, z, done)
    local ped = st.ped
    if not isElement(ped) then return done and done() end
    if isTimer(st.walkTimer) then killTimer(st.walkTimer) end
    setPedAnimation(ped)
    local px, py, pz = getElementPosition(ped)
    local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
    local ms = math.floor(math.max(300, math.min(9000, dist / WALK_SPEED * 1000)))
    if dist > 30 then ms = 50 end   -- bombero mal ubicado: aparece directo
    triggerClientEvent(root, "rp:fuel:walk", ped, x, y, z, ms)
    st.walkTimer = setTimer(function()
        if not isElement(ped) then return end
        setElementPosition(ped, x, y, z)
        if done then done() end
    end, ms + 80, 1)
end

local function goHome(st)
    walkTo(st, st.px, st.py, st.pz, function()
        if not isElement(st.ped) then return end
        setPedAnimation(st.ped)
        setElementRotation(st.ped, 0, 0, st.prz, "default", true)
    end)
end

----------------------------------------------------------------
-- Sesion de carga
----------------------------------------------------------------
local function costOf(s) return math.ceil(s.delivered * FUEL.PRICE_PER_LITER) end

local function endSession(s, message, kind)
    if s.ended then return end
    s.ended = true
    if isTimer(s.timer) then killTimer(s.timer) end
    if isTimer(s.timeout) then killTimer(s.timeout) end
    sessions[s.player], byVehicle[s.vehicle] = nil, nil
    s.station.busy = nil
    if isElement(s.vehicle) then
        removeElementData(s.vehicle, "rp:refueling")
        if getVehicleData(s.vehicle) then
            updateFrozen(s.vehicle)
            saveVehicle(s.vehicle)
        else
            setElementFrozen(s.vehicle, false)
        end
        publish(s.vehicle, true)
    end
    if isElement(s.player) then
        triggerClientEvent(s.player, "rp:fuel:finish", resourceRoot)
        if message then notify(s.player, message, kind or "info") end
    end
    goHome(s.station)
end

-- Cobro forzoso de lo ya cargado (se bajo, se fue o se desconecto)
local function chargeLeaving(s)
    local cost = costOf(s)
    if cost <= 0 then return end
    local player = s.player
    local characterId = isElement(player) and characterOf(player)
    if characterId and exports.rp_bank:chargeAccount(characterId, cost, s.station.name) then
        if isElement(player) then notify(player, ("Te fuiste sin pagar: se cobraron $%d de tu cuenta."):format(cost), "warning") end
        return
    end
    if isElement(player) then
        takePlayerMoney(player, math.min(cost, math.max(0, getPlayerMoney(player))))
        exports.rp_characters:saveCharacter(player)
        notify(player, ("Te fuiste sin pagar: se cobraron $%d en efectivo."):format(cost), "warning")
    end
end

local function abort(s)
    if not s or s.ended then return end
    if s.stage == "fueling" or s.stage == "pay" then chargeLeaving(s) end
    say(s.station, "¡Oiga! ...")
    endSession(s)
end

local function windowSpot(s)
    -- Recalcula la ventana con el vehiculo actual (el cliente mando offsets)
    local m = getElementMatrix(s.vehicle)
    local o = s.offsets.window
    return o[1] * m[1][1] + o[2] * m[2][1] + o[3] * m[3][1] + m[4][1],
        o[1] * m[1][2] + o[2] * m[2][2] + o[3] * m[3][2] + m[4][2],
        o[1] * m[1][3] + o[2] * m[2][3] + o[3] * m[3][3] + m[4][3]
end

local function capSpot(s)
    local m = getElementMatrix(s.vehicle)
    local o = s.offsets.cap
    return o[1] * m[1][1] + o[2] * m[2][1] + o[3] * m[3][1] + m[4][1],
        o[1] * m[1][2] + o[2] * m[2][2] + o[3] * m[3][2] + m[4][2],
        o[1] * m[1][3] + o[2] * m[2][3] + o[3] * m[3][3] + m[4][3]
end

local function validOffset(o)
    return type(o) == "table" and tonumber(o[1]) and tonumber(o[2]) and tonumber(o[3])
        and math.abs(o[1]) <= 4 and math.abs(o[2]) <= 8 and math.abs(o[3]) <= 3
end

addEventHandler("rp:fuel:call", resourceRoot, function(offsets)
    local player = client
    if sessions[player] then return end
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player then return notify(player, "Debes estar al volante.", "warning") end
    if not usesFuel(getElementModel(v)) then return notify(player, "Este vehiculo no usa bencina.", "warning") end
    local st = stationOf(v)
    if not st then return notify(player, "Estaciona dentro del marcador de la bencinera.", "warning") end
    if st.busy then return notify(player, "El bombero esta atendiendo a otro cliente. Espera un momento.", "warning") end
    if not isElement(st.ped) then spawnAttendant(st) end
    if vehicleSpeedKmh(v) > 5 then return notify(player, "Detente por completo antes de llamar al bombero.", "warning") end
    if type(offsets) ~= "table" or not validOffset(offsets.window) or not validOffset(offsets.cap) then return end
    local cap = getFuelCapacity(getElementModel(v))
    if getVehicleFuel(v) >= cap - 0.5 then return notify(player, "El tanque ya esta lleno.", "info") end

    local s = { player = player, vehicle = v, station = st, stage = "walk", delivered = 0, offsets = offsets }
    sessions[player], byVehicle[v], st.busy = s, s, player
    if setEngine then setEngine(v, false) else setVehicleEngineState(v, false) end
    setElementFrozen(v, true)
    setElementData(v, "rp:refueling", true)
    triggerClientEvent(player, "rp:fuel:start", resourceRoot, st.ped, v)

    local x, y, z = windowSpot(s)
    walkTo(st, x, y, z, function()
        if s.ended or not isElement(v) then return end
        s.stage = "talk"
        lookAt(st.ped, getElementPosition(v))
        setPedAnimation(st.ped, "GANGS", "prtial_gngtlkA", -1, true, false, false)
        say(st, "¡Buenas! ¿Cuanto le echamos?")
        local cards = exports.rp_bank:getPlayerCards(player) or {}
        triggerClientEvent(player, "rp:fuel:dialog", resourceRoot, {
            station = st.name, fuel = round1(getVehicleFuel(v)), capacity = cap, price = FUEL.PRICE_PER_LITER,
            cash = getPlayerMoney(player), cards = #cards, vehicle = getVehicleName(v),
        })
        -- Si no contesta en un minuto, el bombero se vuelve
        s.timeout = setTimer(function() endSession(s, "El bombero se aburrio de esperar.", "info") end, 60000, 1)
    end)
end)

addEventHandler("rp:fuel:cancel", resourceRoot, function()
    local s = sessions[client]
    if not s or s.stage ~= "talk" then return end
    say(s.station, "Bueno, ¡que le vaya bien!")
    endSession(s)
end)

addEventHandler("rp:fuel:order", resourceRoot, function(liters)
    local player = client
    local s = sessions[player]
    if not s or s.stage ~= "talk" or not isElement(s.vehicle) then return end
    local v = s.vehicle
    local cap = getFuelCapacity(getElementModel(v))
    local room = cap - getVehicleFuel(v)
    liters = liters == "full" and room or tonumber(liters)
    if not liters or liters < 1 then return notify(player, "Elige al menos 1 litro.", "warning") end
    liters = math.min(room, liters)
    local maxCost = math.ceil(liters * FUEL.PRICE_PER_LITER)
    local cards = exports.rp_bank:getPlayerCards(player) or {}
    if #cards == 0 and getPlayerMoney(player) < maxCost then
        return notify(player, ("No llevas tarjeta y no te alcanza el efectivo ($%d)."):format(maxCost), "error")
    end
    if isTimer(s.timeout) then killTimer(s.timeout) end
    s.target, s.stage = liters, "walkcap"
    say(s.station, liters >= room - 0.05 and "¡Lleno, entonces!" or ("%d litros, ¡altiro!"):format(math.floor(liters + 0.5)))
    triggerClientEvent(player, "rp:fuel:ordered", resourceRoot, liters)

    local x, y, z = capSpot(s)
    walkTo(s.station, x, y, z, function()
        if s.ended or not isElement(v) then return end
        s.stage = "fueling"
        lookAt(s.station.ped, getElementPosition(v))
        setPedAnimation(s.station.ped, "INT_HOUSE", "wash_up", -1, true, false, false)
        triggerClientEvent(root, "rp:fuel:hose", s.station.ped, s.station.px, s.station.py, s.station.pz, true)
        local step = FUEL.REFUEL_RATE / 4
        s.timer = setTimer(function()
            if s.ended or not isElement(v) then return end
            local add = math.min(step, s.target - s.delivered)
            s.delivered = s.delivered + add
            fuel[v] = math.min(cap, fuel[v] + add)
            publish(v, true)
            if s.delivered >= s.target - 0.001 then
                killTimer(s.timer)
                if fuel[v] > cap * FUEL.LOW then warned[v] = nil end
                triggerClientEvent(root, "rp:fuel:hose", s.station.ped, 0, 0, 0, false)
                s.stage = "walkpay"
                local wx, wy, wz = windowSpot(s)
                walkTo(s.station, wx, wy, wz, function()
                    if s.ended or not isElement(v) then return end
                    s.stage = "pay"
                    lookAt(s.station.ped, getElementPosition(v))
                    setPedAnimation(s.station.ped, "DEALER", "shop_pay", -1, false, false, false)
                    local cost = costOf(s)
                    say(s.station, ("Listo, son $%d. ¿Con tarjeta?"):format(cost))
                    triggerClientEvent(player, "rp:fuel:pos", resourceRoot, {
                        amount = cost, liters = round1(s.delivered), station = s.station.name,
                        cards = exports.rp_bank:getPlayerCards(player) or {}, cash = getPlayerMoney(player),
                    })
                end)
            end
        end, 250, 0)
    end)
end)

local PAY_ERRORS = {
    card = "SIN TARJETA", locked = "TARJETA BLOQUEADA", pin = "CLAVE INCORRECTA", funds = "FONDOS INSUFICIENTES",
    cash = "EFECTIVO INSUFICIENTE",
}

addEventHandler("rp:fuel:pay", resourceRoot, function(method, ownerId, pin)
    local player = client
    local s = sessions[player]
    if not s or s.stage ~= "pay" or s.paying then return end
    local cost = costOf(s)
    local ok, reason
    s.paying = true
    if method == "cash" then
        if getPlayerMoney(player) >= cost then
            takePlayerMoney(player, cost)
            exports.rp_characters:saveCharacter(player)
            ok = true
        else
            reason = "cash"
        end
    else
        if type(pin) ~= "string" or not pin:match("^%d%d%d%d$") then
            ok, reason = false, "pin"
        else
            ok, reason = exports.rp_bank:payWithCard(player, tonumber(ownerId), pin, cost, s.station.name)
        end
    end
    s.paying = nil
    triggerClientEvent(player, "rp:fuel:payResult", resourceRoot, ok and true or false, ok and "APROBADO" or (PAY_ERRORS[reason] or "RECHAZADO"), method == "cash")
    if not ok then return end
    s.stage = "paid"
    say(s.station, "¡Gracias! Que tenga buen viaje.")
    -- Deja ver la boleta antes de devolver el control
    setTimer(function()
        endSession(s, ("Cargaste %.1f L por $%d."):format(s.delivered, cost), "success")
    end, 3200, 1)
end)

-- Bajarse, morir, desconectarse o perder el vehiculo corta la carga
addEventHandler("onVehicleExit", root, function(player)
    local s = sessions[player]
    if s and s.vehicle == source then abort(s) end
end)
addEventHandler("onPlayerWasted", root, function() abort(sessions[source]) end)
addEventHandler("onPlayerQuit", root, function() abort(sessions[source]) end)
addEventHandler("onElementDestroy", root, function()
    if getElementType(source) == "vehicle" then abort(byVehicle[source]) end
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for _, s in pairs(sessions) do if s.stage == "fueling" or s.stage == "pay" then chargeLeaving(s) end end
end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
addCommandHandler("nearbybencineras", function(player, _, radius)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    radius = tonumber(radius) or 400
    local px, py, pz = getElementPosition(player)
    local any = false
    for i, st in ipairs(stations) do
        local d = getDistanceBetweenPoints3D(px, py, pz, st.x, st.y, st.z)
        if d <= radius then
            any = true
            outputChatBox(("Bencinera %d: %s - %.0f m. /moverbencinera %d (en tu auto) - /moverbombero %d (a pie)"):format(i, st.name, d, i, i), player, 245, 165, 36)
        end
    end
    if not any then outputChatBox(("No hay bencineras a menos de %d m. Prueba /nearbybencineras 3000."):format(radius), player, 245, 165, 36) end
end)

addCommandHandler("moverbencinera", function(player, _, index)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local st = stations[tonumber(index) or -1]
    if not st then return notify(player, "Uso: /moverbencinera <numero> (ver /nearbybencineras)", "warning") end
    if st.busy then return notify(player, "Esa bencinera esta atendiendo a alguien.", "warning") end
    local x, y, z = getElementPosition(getPedOccupiedVehicle(player) or player)
    st.x, st.y, st.z = x, y, z
    saveStations()
    buildStations()
    notify(player, ("Marcador de %s movido a tu posicion."):format(st.name), "success")
end)

addCommandHandler("moverbombero", function(player, _, index)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local st = stations[tonumber(index) or -1]
    if not st then return notify(player, "Uso: /moverbombero <numero> (a pie, mirando hacia donde quieres)", "warning") end
    if getPedOccupiedVehicle(player) then return notify(player, "Bajate del vehiculo para ubicar al bombero.", "warning") end
    if st.busy then return notify(player, "Esa bencinera esta atendiendo a alguien.", "warning") end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    st.px, st.py, st.pz, st.prz = x, y, z, rz
    saveStations()
    spawnAttendant(st)
    notify(player, ("El bombero de %s ahora espera aqui."):format(st.name), "success")
end)

-- /setfuel [litros] [id del vehiculo]: sin litros llena el tanque
addCommandHandler("setfuel", function(player, _, liters, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local v = tonumber(id) and getVehicleById(id) or getPedOccupiedVehicle(player)
    if not v then return notify(player, "Uso: /setfuel [litros] [id] (subido a un vehiculo o con su id)", "warning") end
    if not usesFuel(getElementModel(v)) then return notify(player, "Ese vehiculo no usa bencina.", "warning") end
    local cap = getFuelCapacity(getElementModel(v))
    setVehicleFuel(v, tonumber(liters) or cap)
    if getVehicleData(v) then saveVehicle(v) end
    notify(player, ("Bencina: %.1f / %d L."):format(getVehicleFuel(v), cap), "success")
end)
