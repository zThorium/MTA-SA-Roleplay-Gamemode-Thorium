--[[
    rp_train · trenes (servidor)

    El servidor es la verdad: cada tren tiene una distancia "d" sobre la vía (TrainTrack) y una velocidad.
    Recorre el bucle completo de tracks.dat (LS-SF-LV) y para en las 6 estaciones del juego como en el
    modo historia. El de pasajeros sale de Unity Station (Los Santos), ver TRAIN.TRAINS.

    Tres zonas según el jugador más cercano:
    - Más lejos que TRAIN.PLACE_RADIUS: el tren solo existe en memoria; el servidor avanza d y no toca
      los elementos ni manda nada por la red.
    - Entre SYNC_RADIUS y PLACE_RADIUS: el servidor lo recoloca en la vía (fuera de la vista cercana),
      así llega ya en su sitio.
    - A menos de SYNC_RADIUS: se le asigna como sincronizador al jugador más cercano y la física de su
      juego mueve el tren (fluido, sin saltos) a la velocidad que marca el servidor (elementData
      rp:train:v); los demás lo ven por la sincronización normal de MTA. El servidor solo lee su posición.
    El sentido de marcha se fija con setTrainDirection (velocidad siempre positiva): así la locomotora
    tira de los vagones y el juego los coloca detrás.
]]

local trains = {}
local stations = {}       -- { d, node, name } ordenadas por d
local stationByNode = {}  -- [node] = estación
local route = {}          -- estaciones en orden de marcha desde TRAIN.ROUTE_ORIGIN, con km del recorrido

-- Jugadores en la dimensión 0: posiciones (x, y) en un array plano y sus elementos, reutilizados cada paso
local playerPos, playerEl, playerCount = {}, {}, 0

local function heading(ux, uy) return math.deg(math.atan2(-ux, uy)) end

local function trainLength(t) return (#t.cars + 1) * TRAIN.CARRIAGE_GAP end

local function nearPlayer(x, y)
    if not x then return false end
    local r2 = TRAIN.PLACE_RADIUS * TRAIN.PLACE_RADIUS
    for i = 1, playerCount, 2 do
        local dx, dy = playerPos[i] - x, playerPos[i + 1] - y
        if dx * dx + dy * dy < r2 then return true end
    end
    return false
end

-- Jugador más cercano a (x, y) dentro de r, o nil
local function nearestPlayer(x, y, r)
    local best, bestD2 = nil, r * r
    for i = 1, playerCount, 2 do
        local dx, dy = playerPos[i] - x, playerPos[i + 1] - y
        local d2 = dx * dx + dy * dy
        if d2 < bestD2 then best, bestD2 = playerEl[i], d2 end
    end
    return best
end

local function collectPlayers()
    local n = 0
    for _, p in ipairs(getElementsByType("player")) do
        if getElementDimension(p) == 0 and getElementInterior(p) == 0 then
            local x, y = getElementPosition(p)
            playerPos[n + 1], playerPos[n + 2], playerEl[n + 1] = x, y, p
            n = n + 2
        end
    end
    playerCount = n
end

local function setDirection(t)
    for _, veh in ipairs(t.wagons) do setTrainDirection(veh, t.dir) end
end

-- Sincronizador del tren entero (locomotora y vagones van juntos en la física de un solo cliente).
-- player = elemento jugador, o true para devolverlo a la asignación automática de MTA.
local function setSyncer(t, player)
    for _, veh in ipairs(t.wagons) do
        if isElement(veh) then setElementSyncer(veh, player, player ~= true) end
    end
    t.forcedSyncer = player ~= true and player or nil
end

local function spawnDriver(t)
    if isElement(t.driver) then destroyElement(t.driver) end
    local x, y, z = getElementPosition(t.loco)
    t.driver = createPed(TRAIN.DRIVER_SKIN, x, y, z + 3)
    setElementData(t.driver, "rp:train:driver", true)
    warpPedIntoVehicle(t.driver, t.loco, 0)
end

-- Coloca locomotora y vagones en la vía a partir de t.d (solo cuando nadie lo sincroniza)
-- Cada pieza va primero a un nodo exacto de la vía principal (para que el juego la enganche a esa vía
-- y no a la paralela de LS) y luego a su punto exacto con setTrainPosition (orientación incluida).
local function placeTrain(t)
    for i, veh in ipairs(t.wagons) do
        local d = t.d - (i - 1) * TRAIN.CARRIAGE_GAP
        local nx, ny, nz = TrainTrack.nodePoint(d)
        setElementPosition(veh, nx, ny, nz + 1, false)
        setTrainPosition(veh, TrainTrack.gameD(d))
    end
    t.px, t.py = TrainTrack.point(t.d)
    t.placedD = t.d
end

local function createTrain(def)
    local origin = def.station and stationByNode[def.station]
    if def.station and not origin then
        outputDebugString("[rp_train] estación de salida desconocida: nodo " .. tostring(def.station), 2)
    end
    local t = { def = def, d = TrainTrack.wrap(origin and origin.d or def.start or 0), v = 0, dir = TRAIN.CLOCKWISE,
                cars = {}, wagons = {}, back = 0 }
    if origin then -- espera en el andén y sale
        t.dwellUntil, t.leaving = getTickCount() + TRAIN.STATION_STOP_MS, origin
    end
    -- Se crean sobre nodos exactos de la vía principal (ver placeTrain) y luego se ajustan
    local _, _, _, ux, uy = TrainTrack.point(t.d)
    local x, y, z = TrainTrack.nodePoint(t.d)
    t.loco = createVehicle(def.model, x, y, z + 1, 0, 0, heading(ux, uy))
    if not t.loco then return outputDebugString("[rp_train] no se pudo crear la locomotora " .. def.model, 1) end
    t.wagons[1] = t.loco
    -- Los vagones NO se enganchan (attachTrailerToVehicle): el enganche de trenes de MTA no los arrastraba
    -- (la locomotora se iba y el vagón quedaba en el andén). Cada vagón es un tren suelto en la vía
    -- principal y el cliente que lo sincroniza lo lleva a la velocidad de la locomotora, a su distancia
    -- (c_train.lua, tickCar). rp:train:of y rp:train:idx le dicen a qué tren pertenece y en qué puesto.
    for i, model in ipairs(def.carriages) do
        local cd = t.d - i * TRAIN.CARRIAGE_GAP
        local _, _, _, cux, cuy = TrainTrack.point(cd)
        local cx, cy, cz = TrainTrack.nodePoint(cd)
        local car = createVehicle(model, cx, cy, cz + 1, 0, 0, heading(cux, cuy))
        if car then
            setElementData(car, "rp:train:of", t.loco)
            setElementData(car, "rp:train:idx", #t.cars + 1)
            t.cars[#t.cars + 1] = car
            t.wagons[#t.wagons + 1] = car
        end
    end
    for _, veh in ipairs(t.wagons) do
        setTrainDerailable(veh, false)
        setVehicleDamageProof(veh, true)
        toggleVehicleRespawn(veh, false)
        setElementData(veh, "rp:train:wagon", true)
    end
    setDirection(t)
    setElementData(t.loco, "rp:train", true)
    setElementData(t.loco, "rp:train:v", 0)
    t.sentV = 0
    for i, veh in ipairs(t.wagons) do setTrainPosition(veh, TrainTrack.gameD(t.d - (i - 1) * TRAIN.CARRIAGE_GAP)) end
    t.px, t.py = TrainTrack.point(t.d)
    t.placedD = t.d
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
    if t.leaving then
        local gone = TrainTrack.ahead(t.leaving.d, t.d)
        if gone > 60 and gone < TrainTrack.length() / 2 then t.leaving = nil end
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
    updateSpeed(t, now, dt)

    -- Quién mueve el tren: el jugador más cercano a menos de SYNC_RADIUS, con la física de su juego.
    -- Se mantiene mientras siga cerca (margen de 40 m) para no saltar de un cliente a otro.
    local forced = t.forcedSyncer
    local keep = false
    if forced and isElement(forced) and getElementDimension(forced) == 0 then
        local fx, fy = getElementPosition(forced)
        local dx, dy = fx - t.px, fy - t.py
        keep = dx * dx + dy * dy < (TRAIN.SYNC_RADIUS + 40) ^ 2
    end
    if not keep then
        local near = nearestPlayer(t.px, t.py, TRAIN.SYNC_RADIUS)
        if near then
            -- Si el tren quedó atrás en la vía (llegó alguien de golpe), primero a su sitio
            if not getElementSyncer(t.loco) and t.placedD ~= t.d then placeTrain(t) end
            setSyncer(t, near)
        elseif forced then
            setSyncer(t, true)
        end
    end

    local syncer = getElementSyncer(t.loco)
    if syncer then
        if not isElement(t.driver) or isPedDead(t.driver) or getVehicleController(t.loco) ~= t.driver then spawnDriver(t) end
        -- La física la lleva el cliente: se lee dónde está
        local x, y = getElementPosition(t.loco)
        local nd = TrainTrack.project(x, y, t.d)
        local moved = TrainTrack.ahead(t.d, nd)
        if moved > TrainTrack.length() / 2 then -- retrocede: el juego tiene el sentido al revés
            t.back = t.back + 1
            if t.back >= 2 and t.v > 1 then
                t.dir, t.back = not t.dir, 0
                setDirection(t)
                outputDebugString(("[rp_train] tren %s: sentido corregido (clockwise = %s); ajusta TRAIN.CLOCKWISE"):format(
                    t.def.model, tostring(t.dir)), 2)
            end
        else
            t.back = 0
        end
        t.d, t.px, t.py, t.placedD = nd, x, y, nd

        local v = math.floor(t.v * 2 + 0.5) / 2
        if v ~= t.sentV then
            t.sentV = v
            setElementData(t.loco, "rp:train:v", v)
        end
    else
        t.d = TrainTrack.wrap(t.d + t.v * dt)
        t.sentV = nil -- el próximo que lo sincronice recibe la velocidad al momento
        -- Solo se recoloca si alguien está a menos de PLACE_RADIUS de donde va o de donde quedó (así nunca
        -- aparece un tren quieto y desfasado al acercarse a la vía). Más cerca ya lo mueve un cliente.
        if t.placedD ~= t.d then
            local x, y = TrainTrack.point(t.d)
            if nearPlayer(x, y) or nearPlayer(t.px, t.py) then
                if not isElement(t.driver) or isPedDead(t.driver) then spawnDriver(t) end
                placeTrain(t)
            end
        end
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
        local st, dist = nextStation(t)
        out[i] = { d = t.d, v = t.v, stopped = t.dwellUntil ~= nil, synced = getElementSyncer(t.loco) and true or false,
                   station = t.dwellUntil and t.leaving and t.leaving.name or nil,
                   next = st and st.name, nextIn = dist }
    end
    return out
end

-- Export: el recorrido completo desde la estación de origen (Unity Station), en orden de marcha.
-- { length = metros del bucle, stations = { { name, node, km, x, y, z }, ... } }
function getTrainRoute()
    local out = {}
    for i, s in ipairs(route) do
        out[i] = { name = s.name, node = s.node, km = s.km, x = s.x, y = s.y, z = s.z }
    end
    return { length = TrainTrack.length(), stations = out }
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

-- Estaciones y recorrido: se calculan una sola vez
local function buildRoute()
    for node, name in pairs(TRAIN.STATION_NAMES) do
        local x, y, z = TrainTrack.point(TrainTrack.nodeD(node))
        local s = { d = TrainTrack.nodeD(node), node = node, name = name, x = x, y = y, z = z }
        stations[#stations + 1] = s
        stationByNode[node] = s
    end
    table.sort(stations, function(a, b) return a.d < b.d end)
    local origin = stationByNode[TRAIN.ROUTE_ORIGIN] or stations[1]
    for _, s in ipairs(stations) do
        s.km = TrainTrack.ahead(origin.d, s.d) / 1000
        route[#route + 1] = s
    end
    table.sort(route, function(a, b) return a.km < b.km end)
    local names = {}
    for i, s in ipairs(route) do names[i] = ("%s (%.1f km)"):format(s.name, s.km) end
    return table.concat(names, " > ")
end

addEventHandler("onResourceStart", resourceRoot, function()
    local routeText = buildRoute()
    for _, def in ipairs(TRAIN.TRAINS) do createTrain(def) end
    local last = getTickCount()
    setTimer(function()
        local now = getTickCount()
        local dt = (now - last) / 1000
        last = now
        collectPlayers()
        for _, t in ipairs(trains) do tickTrain(t, now, dt) end
        updateCrossings()
    end, TRAIN.TICK_MS, 0)
    outputDebugString(("[rp_train] %d trenes en la vía (%.0f m, %d estaciones)"):format(#trains, TrainTrack.length(), #stations), 3)
    outputDebugString("[rp_train] recorrido: " .. routeText, 3)
end)
