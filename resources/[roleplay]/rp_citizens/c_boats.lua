--[[
    rp_citizens / c_boats.lua
    Trafico maritimo ambiental del lado del cliente (como los autos: cada jugador ve sus propios barcos).
      - Rutas: BOAT_NODES / BOAT_LINKS (c_nodes_boat.lua), los nodos de barcos de GTA SA (bahias, costa, rios).
      - Siempre cinematicos (congelados, sin fisica): siguen la ruta girando con suavidad, frenan en las curvas
        cerradas y flotan sobre el nivel real del agua con un leve vaiven. Cerca del jugador tienen colision.
      - Frenan y tocan la bocina si el jugador (o su barco) se les cruza delante.
      - Si el jugador los embiste o dispara, pasan a fisica real y huyen a toda maquina. Si matan al piloto,
        el barco queda a la deriva. El jugador puede subirse y llevarselo: deja de ser trafico.
      - Modelos segun la zona (marina de lujo, puerto, rio y campo, ciudad) y guardacostas (mas con estrellas).
    Se apagan con el resto de la poblacion (/poblacion, de pasajero, en interiores) via citizensEnabled().
    No usan la marca "rp:citizen" (sweepOrphans de c_citizens.lua borraria los que no estan en su tabla de autos).
]]

----------------------------------------------------------------
-- Configuracion
----------------------------------------------------------------
local CFG = {
    MAX = 4, MAX_NIGHT = 2, MAX_WANTED = 2,   -- barcos a la vez (de noche menos; con estrellas, guardacostas extra)
    SPAWN_MIN = 120, SPAWN_MAX = 280,         -- metros del jugador donde aparecen
    HIDDEN_BELOW = 180,                       -- mas cerca que esto solo aparecen fuera de camara
    DESPAWN = 360,
    SOLID_DIST = 45,                          -- a menos de esto tienen colision
    SPACING = 45,                             -- distancia minima entre barcos al aparecer
    FADE_MS = 2500,                           -- aparecen y se van desvaneciendose (en el agua todo se ve de lejos)
    COAST_CHANCE = 0.1, COAST_CHANCE_WANTED = 0.4,
    FLEE_MS = 15000,
    TICK = 250,                               -- ms entre decisiones (agua, colision, cruce con el jugador)
    SPAWN_TICK = 1000,
}

-- speed: m/s de crucero, turn: grados/s, draft: calado (m bajo el agua desde la base del casco)
local MODELS = {
    [446] = { speed = 15, turn = 40, draft = 0.4 },   -- Squalo
    [452] = { speed = 14, turn = 40, draft = 0.4 },   -- Speeder
    [493] = { speed = 14, turn = 35, draft = 0.5 },   -- Jetmax
    [454] = { speed = 8, turn = 20, draft = 0.8 },    -- Tropic (yate)
    [484] = { speed = 5, turn = 15, draft = 0.9 },    -- Marquis (velero)
    [453] = { speed = 6, turn = 22, draft = 0.6 },    -- Reefer (pesquero)
    [473] = { speed = 8, turn = 45, draft = 0.3 },    -- Dinghy
    [472] = { speed = 11, turn = 30, draft = 0.5 },   -- Coastguard
    [430] = { speed = 12, turn = 28, draft = 0.6 },   -- Predator (policia)
}
local DEFAULT_SPEC = { speed = 8, turn = 25, draft = 0.5 }

local PROFILES = {
    marina = { 446, 452, 493, 454, 484, 454, 493 },   -- yates y lanchas de lujo
    port = { 453, 453, 454, 473, 472 },               -- pesqueros y trabajo en los muelles
    river = { 473, 473, 453, 452, 493 },              -- rios, lagos y costa rural
    city = { 452, 446, 493, 454, 473, 453, 484 },
}
local ZONE_PROFILE = {
    ["Marina"] = "marina", ["Santa Maria Beach"] = "marina", ["Verona Beach"] = "marina",
    ["Bayside"] = "marina", ["Bayside Marina"] = "marina", ["Esplanade North"] = "marina",
    ["Paradiso"] = "marina", ["Palisades"] = "marina", ["Battery Point"] = "marina",
    ["Ocean Docks"] = "port", ["Playa del Seville"] = "port", ["Easter Basin"] = "port",
    ["Easter Bay Chemicals"] = "port", ["Easter Bay Airport"] = "port", ["Los Santos International"] = "port",
    ["Garver Bridge"] = "port", ["Kincaid Bridge"] = "port",
}
local CITIES = { ["Los Santos"] = true, ["San Fierro"] = true, ["Las Venturas"] = true }

-- Guardacostas: Predator (policia) o Coastguard, con agente de la ciudad
local COAST_MODELS = { 430, 430, 472 }
local COP_SKIN = { ["Los Santos"] = 280, ["San Fierro"] = 281, ["Las Venturas"] = 282 }

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local boats, boatCount = {}, 0
local grid
local CELL = 100

local function pick(list) return list[math.random(#list)] end

local function heading(dx, dy)     -- rotacion Z de GTA (0 = norte, antihorario)
    return -math.deg(math.atan2(dx, dy))
end

local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function nodeXYZ(i)
    return BOAT_NODES[i * 3 - 2], BOAT_NODES[i * 3 - 1], BOAT_NODES[i * 3]
end

local function buildGrid()
    grid = {}
    for i = 1, #BOAT_NODES / 3 do
        if BOAT_LINKS[i] and #BOAT_LINKS[i] > 0 then
            local x, y = BOAT_NODES[i * 3 - 2], BOAT_NODES[i * 3 - 1]
            local key = math.floor(x / CELL) * 1000 + math.floor(y / CELL)
            grid[key] = grid[key] or {}
            table.insert(grid[key], i)
        end
    end
end

-- Nodo de barco al azar a [minD, maxD] del jugador (la red es escasa: mas intentos que en tierra)
local function randomNodeAround(px, py, minD, maxD)
    for _ = 1, 12 do
        local a = math.random() * math.pi * 2
        local d = minD + math.random() * (maxD - minD)
        local cell = grid[math.floor((px + math.cos(a) * d) / CELL) * 1000 + math.floor((py + math.sin(a) * d) / CELL)]
        if cell then
            local i = cell[math.random(#cell)]
            local x, y, z = nodeXYZ(i)
            local dd = getDistanceBetweenPoints2D(px, py, x, y)
            if dd >= minD and dd <= maxD then return i, x, y, z end
        end
    end
end

-- Siguiente nodo sin volver atras si hay alternativa (al final de un rio da la vuelta)
local function nextNode(current, previous)
    local list = BOAT_LINKS[current]
    if not list or #list == 0 then return previous end
    if #list == 1 then return list[1] end
    for _ = 1, 4 do
        local n = list[math.random(#list)]
        if n ~= previous then return n end
    end
    return list[1]
end

local function waterAt(x, y, nearZ)
    local w = getWaterLevel(x, y, nearZ + 3)
    return w or nil
end

local function isNight()
    local h = getTime()
    return h >= 22 or h < 6
end

local function wanted()
    return citizenWantedLevel and citizenWantedLevel() or false
end

local function allowed()
    return citizensEnabled and citizensEnabled() and getElementData(localPlayer, "rp:characterId")
        and getElementInterior(localPlayer) == 0 and getElementDimension(localPlayer) == 0
end

-- Altura del centro del barco sobre el agua: lo que sobresale la base del casco menos el calado
local function liftOf(vehicle, spec)
    if not isElementStreamedIn(vehicle) then return nil end
    local _, _, minZ = getElementBoundingBox(vehicle)
    if not minZ or minZ >= 0 or minZ < -6 then return nil end
    return -minZ - spec.draft
end

local function pickBoat(x, y, z)
    local city = getZoneName(x, y, z, true)
    if math.random() < (wanted() and CFG.COAST_CHANCE_WANTED or CFG.COAST_CHANCE) then
        return pick(COAST_MODELS), COP_SKIN[city] or 283, true
    end
    local profile = ZONE_PROFILE[getZoneName(x, y, z, false)] or (CITIES[city] and "city" or "river")
    local skin = citizenPickSkin and citizenPickSkin(x, y, z) or 7
    return pick(PROFILES[profile]), skin, false
end

local function nearOtherBoat(x, y, dist)
    for v, s in pairs(boats) do
        if isElement(v) and getDistanceBetweenPoints2D(x, y, s.x, s.y) < dist then return true end
    end
    return false
end

----------------------------------------------------------------
-- Crear y quitar
----------------------------------------------------------------
local function removeBoat(vehicle)
    local s = boats[vehicle]
    if not s then return end
    boats[vehicle] = nil
    boatCount = boatCount - 1
    -- el barco que lleva el jugador no se destruye (se olvida y ya)
    local mine = isElement(vehicle) and getPedOccupiedVehicle(localPlayer) == vehicle
    if isElement(s.driver) and not (mine and getVehicleController(vehicle) == localPlayer) then destroyElement(s.driver) end
    if isElement(s.passenger) and not mine then destroyElement(s.passenger) end
    if isElement(vehicle) and not mine then destroyElement(vehicle) end
end

local function clearBoats()
    for v in pairs(boats) do removeBoat(v) end
end

local function spawnBoat(px, py)
    local node, x, y, z = randomNodeAround(px, py, CFG.SPAWN_MIN, CFG.SPAWN_MAX)
    if not node or nearOtherBoat(x, y, CFG.SPACING) then return end
    if getDistanceBetweenPoints2D(px, py, x, y) < CFG.HIDDEN_BELOW and citizenIsVisible and citizenIsVisible(x, y, z) then return end
    local water = waterAt(x, y, z)
    if not water then return end
    local nxt = nextNode(node, nil)
    if not nxt then return end
    local tx, ty = nodeXYZ(nxt)

    local model, skin, coast = pickBoat(x, y, z)
    local rz = heading(tx - x, ty - y)
    local vehicle = createVehicle(model, x, y, water + 1, 0, 0, rz)
    if not vehicle then return end
    local driver = createPed(skin, x, y, water + 3)
    if not driver then destroyElement(vehicle) return end
    setElementData(vehicle, "rp:citizenBoat", true, false)
    warpPedIntoVehicle(driver, vehicle)
    setElementFrozen(vehicle, true)
    setElementCollisionsEnabled(vehicle, false)
    setElementAlpha(vehicle, 0)
    setElementAlpha(driver, 0)
    setVehicleEngineState(vehicle, true)
    if isNight() then setVehicleOverrideLights(vehicle, 2) end
    if coast then
        -- rp_wanted los trata como policia (testigos de delitos)
        setElementData(vehicle, "rp:copCar", true, false)
        setElementData(driver, "rp:cop", true, false)
    end
    -- yates y lanchas grandes: a veces un acompanante
    local passenger
    if not coast and (getVehicleMaxPassengers(vehicle) or 0) > 0 and math.random() < 0.4 then
        passenger = createPed(citizenPickSkin and citizenPickSkin(x, y, z) or 7, x, y, water + 3)
        if passenger then
            warpPedIntoVehicle(passenger, vehicle, 1)
            setElementAlpha(passenger, 0)
        end
    end

    local spec = MODELS[model] or DEFAULT_SPEC
    local speed = spec.speed * (0.7 + math.random() * 0.3)
    boats[vehicle] = {
        driver = driver, passenger = passenger, prev = node, node = nxt, spec = spec,
        x = x, y = y, rz = rz, water = water, lift = nil,
        speed = speed, cur = speed * 0.8, slow = 1, yawRate = 0,
        phase = math.random() * math.pi * 2, born = getTickCount(), state = "CRUISE", coast = coast,
        fadeIn = true,   -- empieza transparente y se va mostrando
    }
    boatCount = boatCount + 1
end

----------------------------------------------------------------
-- Fisica real: huir (embestido o tiroteado) o quedar a la deriva (piloto muerto)
----------------------------------------------------------------
local function setAlphaAll(vehicle, s, a)
    setElementAlpha(vehicle, a)
    if isElement(s.driver) then setElementAlpha(s.driver, a) end
    if isElement(s.passenger) then setElementAlpha(s.passenger, a) end
end

local function goPhysical(vehicle, s)
    if s.physical then return end
    s.physical = true
    setAlphaAll(vehicle, s, 255)
    s.fadeIn = nil
    setElementCollisionsEnabled(vehicle, true)
    setElementFrozen(vehicle, false)
    local r = math.rad(s.rz)
    local v = s.cur / 50   -- MTA: unidades por 1/50 s
    setElementVelocity(vehicle, -math.sin(r) * v, math.cos(r) * v, 0)
end

local function startFlee(vehicle, s)
    if s.state ~= "CRUISE" then return end
    goPhysical(vehicle, s)
    s.state, s.until_ = "FLEE", getTickCount() + CFG.FLEE_MS
    if isElement(s.driver) then
        setPedControlState(s.driver, "accelerate", true)
        setPedControlState(s.driver, "horn", true)
        setTimer(function() if isElement(s.driver) then setPedControlState(s.driver, "horn", false) end end, 1000, 1)
    end
end

local function releaseControls(s)
    if not isElement(s.driver) then return end
    for _, c in ipairs({ "accelerate", "vehicle_left", "vehicle_right", "horn" }) do setPedControlState(s.driver, c, false) end
end

local function byPlayer(attacker)
    return attacker == localPlayer or (attacker and attacker == getPedOccupiedVehicle(localPlayer))
end

addEventHandler("onClientVehicleDamage", root, function(attacker)
    local s = boats[source]
    if s and byPlayer(attacker) then startFlee(source, s) end
end)

addEventHandler("onClientPedDamage", root, function(attacker)
    if not byPlayer(attacker) then return end
    for v, s in pairs(boats) do
        if s.driver == source or s.passenger == source then startFlee(v, s) return end
    end
end)

addEventHandler("onClientPedWasted", root, function()
    for v, s in pairs(boats) do
        if s.driver == source and s.state ~= "ABANDONED" then
            goPhysical(v, s)
            s.state = "ADRIFT"
            return
        end
    end
end)

-- El jugador se sube: el barco se para y deja de ser trafico
addEventHandler("onClientVehicleStartEnter", root, function(player)
    local s = boats[source]
    if s and player == localPlayer and s.state ~= "ABANDONED" then
        releaseControls(s)
        s.cur = 0
        goPhysical(source, s)
        setElementVelocity(source, 0, 0, 0)
        s.state = "ABANDONED"
    end
end)

addEventHandler("onClientVehicleEnter", root, function(player, seat)
    local s = boats[source]
    if s and player == localPlayer and seat == 0 and isElement(s.driver) and getVehicleController(source) ~= s.driver then
        destroyElement(s.driver)
    end
end)

----------------------------------------------------------------
-- Movimiento cinematico (cada fotograma, solo unos pocos barcos)
----------------------------------------------------------------
local function moveBoats(dt)
    if boatCount == 0 then return end
    local dts = math.min(dt, 100) / 1000
    local now = getTickCount()
    local t = now / 1000
    for v, s in pairs(boats) do
        if isElement(v) and not s.physical then
            -- rumbo hacia el nodo siguiente, con giro limitado (el barco traza la curva)
            local tx, ty = nodeXYZ(s.node)
            local dx, dy = tx - s.x, ty - s.y
            if dx * dx + dy * dy < math.max(12, s.cur * 1.5) ^ 2 then
                s.prev, s.node = s.node, nextNode(s.node, s.prev)
                tx, ty = nodeXYZ(s.node)
                dx, dy = tx - s.x, ty - s.y
            end
            local diff = angleDiff(heading(dx, dy), s.rz)
            local maxTurn = s.spec.turn * dts
            local turn = clamp(diff, -maxTurn, maxTurn)
            s.rz = (s.rz + turn) % 360
            s.yawRate = s.yawRate + ((dts > 0 and turn / dts or 0) - s.yawRate) * math.min(1, dts * 4)

            -- velocidad: frena para las curvas cerradas y cuando algo se cruza delante (s.slow)
            local ad = math.abs(diff)
            local target = s.speed * (ad > 60 and 0.35 or ad > 25 and 0.7 or 1) * s.slow
            if target > s.cur then s.cur = math.min(target, s.cur + 1.5 * dts)
            else s.cur = math.max(target, s.cur - 3 * dts) end

            local r = math.rad(s.rz)
            s.x, s.y = s.x - math.sin(r) * s.cur * dts, s.y + math.cos(r) * s.cur * dts

            -- flotacion: altura del agua + vaiven; proa arriba con la velocidad, escora hacia dentro en las curvas
            local lift = s.lift or 0.6
            local z = s.water + lift + math.sin(t * 1.3 + s.phase) * 0.07
            local pitch = (s.cur / s.spec.speed) * 3 + math.sin(t * 0.9 + s.phase) * 0.8
            local roll = clamp(-s.yawRate * 0.12, -6, 6) + math.sin(t * 1.1 + s.phase) * 1.2
            setElementPosition(v, s.x, s.y, z)
            setElementRotation(v, pitch, roll, s.rz)

            if s.fadeIn then
                local a = math.min(255, (now - s.born) / CFG.FADE_MS * 255)
                setAlphaAll(v, s, a)
                if a >= 255 then s.fadeIn = nil end
            end
        end
        if isElement(v) and s.fadeOut then
            local a = 255 - math.min(255, (now - s.fadeOut) / 1500 * 255)
            setAlphaAll(v, s, a)
        end
    end
end

----------------------------------------------------------------
-- Decisiones (cada 250 ms): agua, colision cerca, cruce con el jugador, huida
----------------------------------------------------------------
local function playerAhead(s, px, py)
    local r = math.rad(s.rz)
    local fx, fy = -math.sin(r), math.cos(r)
    local dx, dy = px - s.x, py - s.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 35 or d < 0.1 then return false end
    return (dx * fx + dy * fy) / d > 0.7
end

local function boatTick()
    if boatCount == 0 then return end
    local now = getTickCount()
    local px, py = getElementPosition(localPlayer)
    for v, s in pairs(boats) do
        if not isElement(v) then
            removeBoat(v)
        elseif not s.physical then
            local d = getDistanceBetweenPoints2D(px, py, s.x, s.y)
            s.water = waterAt(s.x, s.y, s.water) or s.water
            if not s.lift then s.lift = liftOf(v, s.spec) end
            -- colision solo cerca del jugador (de lejos no hay nada con que chocar y sale mas barato)
            local solid = d < CFG.SOLID_DIST
            if solid ~= s.solid then
                s.solid = solid
                setElementCollisionsEnabled(v, solid)
            end
            -- el jugador o su barco delante: frena y pita una vez
            local block = playerAhead(s, px, py)
            if not block then
                for o, os in pairs(boats) do
                    if o ~= v and playerAhead(s, os.x, os.y) and getDistanceBetweenPoints2D(s.x, s.y, os.x, os.y) < 25 then block = true break end
                end
            end
            s.slow = block and 0.15 or 1
            if block and d < 35 and now - (s.honked or 0) > 6000 and isElement(s.driver) then
                s.honked = now
                setPedControlState(s.driver, "horn", true)
                setTimer(function() if isElement(s.driver) then setPedControlState(s.driver, "horn", false) end end, 800, 1)
            end
        elseif s.state == "FLEE" and isElement(s.driver) then
            -- se aleja del jugador a toda maquina
            if now > s.until_ then
                releaseControls(s)
                s.state = "ADRIFT"
            else
                local vx, vy = getElementPosition(v)
                local _, _, rz = getElementRotation(v)
                local diff = angleDiff(heading(vx - px, vy - py), rz)
                setPedControlState(s.driver, "vehicle_left", diff > 15)
                setPedControlState(s.driver, "vehicle_right", diff < -15)
            end
        end
    end
end

----------------------------------------------------------------
-- Aparecer y desaparecer (cada segundo)
----------------------------------------------------------------
local function spawnTick()
    if not allowed() then
        if boatCount > 0 then clearBoats() end
        return
    end
    local px, py = getElementPosition(localPlayer)
    local now = getTickCount()
    for v, s in pairs(boats) do
        if not isElement(v) then
            removeBoat(v)
        else
            local x, y = getElementPosition(v)
            local d = getDistanceBetweenPoints2D(px, py, x, y)
            if s.fadeOut then
                if now - s.fadeOut > 1500 then removeBoat(v) end
            elseif s.state == "ABANDONED" or s.physical then
                -- robados, a la deriva o tras huir: se quitan cuando dejan de verse
                if getPedOccupiedVehicle(localPlayer) ~= v and d > 80 and not isElementOnScreen(v) then removeBoat(v) end
            elseif d > CFG.DESPAWN then
                if isElementOnScreen(v) then s.fadeOut = now else removeBoat(v) end
            end
        end
    end
    local max = (isNight() and CFG.MAX_NIGHT or CFG.MAX) + (wanted() and CFG.MAX_WANTED or 0)
    if boatCount < max then spawnBoat(px, py) end
end

----------------------------------------------------------------
-- Arranque
----------------------------------------------------------------
local timers = {}

addEventHandler("onClientResourceStart", resourceRoot, function()
    if not BOAT_NODES or not BOAT_LINKS then
        outputDebugString("[rp_citizens] c_nodes_boat.lua no cargado: sin trafico maritimo", 2)
        return
    end
    buildGrid()
    timers.spawn = setTimer(spawnTick, CFG.SPAWN_TICK, 0)
    timers.tick = setTimer(boatTick, CFG.TICK, 0)
    addEventHandler("onClientPreRender", root, moveBoats)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, t in pairs(timers) do if isTimer(t) then killTimer(t) end end
    clearBoats()
end)

-- Export (cliente): punto de agua navegable sobre la red de barcos a [minD, maxD] m del jugador, de preferencia
-- fuera de la vista. Devuelve x, y, z (nivel del agua), rumbo hacia el jugador; nil si no hay agua cerca.
-- Lo usa rp_wanted para que aparezcan las lanchas de la policia.
function citizenBoatSpot(minD, maxD)
    if not grid then return nil end
    local px, py = getElementPosition(localPlayer)
    minD, maxD = tonumber(minD) or 100, tonumber(maxD) or 220
    local fallback
    for _ = 1, 8 do
        local node, x, y, z = randomNodeAround(px, py, minD, maxD)
        if node then
            local water = waterAt(x, y, z)
            if water then
                local spot = { x, y, water, heading(px - x, py - y) }
                if not (citizenIsVisible and citizenIsVisible(x, y, water)) then return unpack(spot) end
                fallback = fallback or spot
            end
        end
    end
    if fallback then return unpack(fallback) end
end

-- Para /poblacioninfo y diagnosticos
function citizenBoatCount()
    return boatCount, BOAT_NODES and #BOAT_NODES / 3 or 0
end
