--[[
    rp_wanted / s_units.lua
    Unidades de policia IA que persiguen a cada jugador buscado.

    Los autos, helicopteros y policias son elementos del servidor (todos los
    ven), pero los conduce el cliente del propio buscado: el servidor lo hace
    "syncer" (setElementSyncer), igual que el auto IA de rp_rides. El cliente
    (client/c_police.lua) elige donde aparecen (en la calle, fuera de la vista,
    con la red vial de rp_citizens) y maneja la persecucion.

    Por estrellas (WANTED_LEVELS): patrullas a la vez, helicopteros, controles
    de carretera y que tipo de patrulla sale (policia de la ciudad, SWAT, FBI,
    ejercito). Al terminar la busqueda apagan la sirena, se van y desaparecen.
]]

local function nowMs() return getTickCount() end

local pursuits = {}      -- [player] = { units = {[id] = unit}, next, pending, fleetIdx, roadblock }
local unitOwner = {}     -- [elemento de la unidad] = { player, unit }
local nextId = 0

for _, e in ipairs({ "spawnAt", "dismount", "remount", "unitLost", "busted", "ready" }) do
    addEvent("rp:wanted:" .. e, true)
end

local function pursuitOf(player)
    local p = pursuits[player]
    if not p then
        p = { units = {}, next = nowMs() + WANTED_DISPATCH.FIRST_DELAY, fleetIdx = 0 }
        pursuits[player] = p
    end
    return p
end

local function levelCfg(player)
    return WANTED_LEVELS[getWantedLevel(player)]
end

local function sendUnit(player, unit)
    local cfg = levelCfg(player)
    triggerClientEvent(player, "rp:wanted:unit", resourceRoot, {
        id = unit.id, kind = unit.kind, vehicle = unit.vehicle, vehicles = unit.vehicles, peds = unit.peds,
        fleet = unit.fleet, leaving = unit.leaving or false,
    })
end

----------------------------------------------------------------
-- Crear y destruir
----------------------------------------------------------------
local function register(player, unit, el)
    unitOwner[el] = { player = player, unit = unit }
    setElementSyncer(el, player)
end

local function destroyUnitElements(unit)
    local list = {}
    for _, ped in ipairs(unit.peds) do list[#list + 1] = ped end
    for _, v in ipairs(unit.vehicles) do list[#list + 1] = v end
    for _, el in ipairs(list) do
        unitOwner[el] = nil
        if isElement(el) then destroyElement(el) end
    end
end

local function removeUnit(player, unit, fade)
    local p = pursuits[player]
    if not p or not p.units[unit.id] then return end
    p.units[unit.id] = nil
    if p.roadblock == unit then p.roadblock = nil end
    if isTimer(unit.timer) then killTimer(unit.timer) end
    if isElement(player) then triggerClientEvent(player, "rp:wanted:unitRemoved", resourceRoot, unit.id) end
    if not fade then return destroyUnitElements(unit) end
    -- Se desvanece (lo ven todos) y desaparece
    local alpha = 255
    setTimer(function()
        alpha = alpha - 25
        for _, list in ipairs({ unit.peds, unit.vehicles }) do
            for _, el in ipairs(list) do
                if isElement(el) then setElementAlpha(el, math.max(0, alpha)) end
            end
        end
        if alpha <= 0 then destroyUnitElements(unit) end
    end, 100, 11)
end

local function newUnit(kind, fleet)
    nextId = nextId + 1
    return { id = nextId, kind = kind, fleet = fleet, peds = {}, vehicles = {}, created = nowMs() }
end

-- Que patrulla sale: la flota del nivel en orden ciclico; "police" segun la ciudad
local function resolveFleet(name, x, y, z)
    local f = WANTED_FLEET[name]
    if name ~= "police" then return f.model, f.skin, f.crew, f.weapon end
    local city = WANTED_FLEET.police[getZoneName(x, y, z, true)] or WANTED_FLEET.police.rural
    return city.model, city.skin, f.crew, f.weapon
end

local function armCop(ped, weapon, level)
    -- A 1 estrella la policia no dispara: solo porra
    if level <= 1 or not weapon then
        giveWeapon(ped, WANTED_FLEET.police.melee, 1, true)
    else
        giveWeapon(ped, weapon, 9999, true)
    end
    setElementData(ped, "rp:cop", true)
end

local function spawnCar(player, x, y, z, rot)
    local p = pursuitOf(player)
    local cfg = levelCfg(player)
    if not cfg then return end
    p.fleetIdx = p.fleetIdx + 1
    local fleetName = cfg.fleet[(p.fleetIdx - 1) % #cfg.fleet + 1]
    local model, skin, crew, weapon = resolveFleet(fleetName, x, y, z)
    local level = getWantedLevel(player)
    if level <= 1 then crew = WANTED_CREW_AT_ONE_STAR end

    local vehicle = createVehicle(model, x, y, z + 0.8, 0, 0, rot)
    if not vehicle then return end
    local unit = newUnit("car", fleetName)
    unit.vehicle = vehicle
    unit.vehicles[1] = vehicle
    setVehicleEngineState(vehicle, true)
    setVehicleSirensOn(vehicle, true)
    setElementData(vehicle, "rp:copCar", true)
    register(player, unit, vehicle)
    local seats = math.max(1, getVehicleMaxPassengers(vehicle) + 1)
    for seat = 0, math.min(crew, seats) - 1 do
        local ped = createPed(skin, x, y, z + 1)
        if ped then
            warpPedIntoVehicle(ped, vehicle, seat)
            armCop(ped, weapon, level)
            unit.peds[#unit.peds + 1] = ped
            register(player, unit, ped)
        end
    end
    p.units[unit.id] = unit
    sendUnit(player, unit)
    return unit
end

local function spawnHeli(player)
    local px, py, pz = getElementPosition(player)
    local a = math.random() * math.pi * 2
    local x, y = px + math.cos(a) * WANTED_DISPATCH.HELI_SPAWN, py + math.sin(a) * WANTED_DISPATCH.HELI_SPAWN
    local z = pz + 60
    local f = WANTED_FLEET.heli
    local heli = createVehicle(f.model, x, y, z, 0, 0, -math.deg(math.atan2(px - x, py - y)))
    if not heli then return end
    local unit = newUnit("heli", "heli")
    unit.vehicle = heli
    unit.vehicles[1] = heli
    setVehicleEngineState(heli, true)
    setElementData(heli, "rp:copCar", true)
    register(player, unit, heli)
    local ped = createPed(f.skin, x, y, z)
    if ped then
        warpPedIntoVehicle(ped, heli, 0)
        setElementData(ped, "rp:cop", true)
        unit.peds[1] = ped
        register(player, unit, ped)
    end
    pursuitOf(player).units[unit.id] = unit
    sendUnit(player, unit)
end

-- Control de carretera: 2 patrullas atravesadas y 2 policias a pie detras
local function spawnRoadblock(player, x, y, z, rot)
    local p = pursuitOf(player)
    local level = getWantedLevel(player)
    local model, skin, _, weapon = resolveFleet("police", x, y, z)
    local unit = newUnit("roadblock", "police")
    local r = math.rad(rot)
    local fx, fy = -math.sin(r), math.cos(r)   -- sentido de la calle (hacia donde va el jugador)
    local rx, ry = fy, -fx                     -- derecha
    for i, side in ipairs({ -2.8, 2.8 }) do
        local v = createVehicle(model, x + rx * side, y + ry * side, z + 0.8, 0, 0, rot + (i == 1 and 90 or -90))
        if v then
            setVehicleSirensOn(v, true)
            setVehicleEngineState(v, false)
            setElementData(v, "rp:copCar", true)
            unit.vehicles[#unit.vehicles + 1] = v
            register(player, unit, v)
        end
    end
    unit.vehicle = unit.vehicles[1]
    for _, side in ipairs({ -2.2, 2.2 }) do
        local ped = createPed(skin, x + fx * 4 + rx * side, y + fy * 4 + ry * side, z + 1, rot + 180)
        if ped then
            armCop(ped, weapon, level)
            unit.peds[#unit.peds + 1] = ped
            register(player, unit, ped)
        end
    end
    p.units[unit.id] = unit
    p.roadblock = unit
    unit.timer = setTimer(function() removeUnit(player, unit, true) end, WANTED_DISPATCH.ROADBLOCK_LIFE, 1)
    sendUnit(player, unit)
end

----------------------------------------------------------------
-- Despacho: cada TICK ms se manda (como mucho) una unidad nueva
----------------------------------------------------------------
local function aliveCount(unit)
    local n = 0
    for _, ped in ipairs(unit.peds) do
        if isElement(ped) and not isPedDead(ped) then n = n + 1 end
    end
    return n
end

local function unitDistance(player, unit)
    local px, py, pz = getElementPosition(player)
    local best = math.huge
    for _, list in ipairs({ unit.vehicles, unit.peds }) do
        for _, el in ipairs(list) do
            if isElement(el) then
                local x, y, z = getElementPosition(el)
                best = math.min(best, getDistanceBetweenPoints3D(px, py, pz, x, y, z))
            end
        end
    end
    return best
end

local function leaveAll(player, p)
    for _, unit in pairs(p.units) do
        if not unit.leaving then
            unit.leaving = true
            for _, v in ipairs(unit.vehicles) do
                if isElement(v) then setVehicleSirensOn(v, false) end
            end
            sendUnit(player, unit)
            if isTimer(unit.timer) then killTimer(unit.timer) end
            unit.timer = setTimer(function() removeUnit(player, unit, true) end, WANTED_DISPATCH.LEAVE_TIME, 1)
        end
    end
end

local function dispatch(player, p)
    local level = getWantedLevel(player)
    if level <= 0 or isPlayerBusted(player) then return leaveAll(player, p) end
    -- En interiores u otra dimension no hay persecucion (GTA: la policia no entra)
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then return end
    local cfg = WANTED_LEVELS[level]
    local now = nowMs()

    -- Limpieza: muy lejos, sin policias vivos o sobrantes al bajar de nivel
    local cars, helis = {}, 0
    for _, unit in pairs(p.units) do
        if not unit.leaving then
            local d = unitDistance(player, unit)
            if d > WANTED_DISPATCH.LOST_DISTANCE + 80 then
                removeUnit(player, unit, false)
            elseif aliveCount(unit) == 0 and unit.kind ~= "roadblock" then
                unit.leaving = true   -- los cuerpos quedan; se borra mas tarde
                unit.timer = setTimer(function() removeUnit(player, unit, false) end, WANTED_DISPATCH.BODY_TIME, 1)
            elseif unit.kind == "car" then
                cars[#cars + 1] = { unit = unit, d = d }
            elseif unit.kind == "heli" then
                helis = helis + 1
                if helis > cfg.heli then
                    unit.leaving = true
                    sendUnit(player, unit)
                    unit.timer = setTimer(function() removeUnit(player, unit, true) end, WANTED_DISPATCH.LEAVE_TIME, 1)
                end
            end
        end
    end
    table.sort(cars, function(a, b) return a.d < b.d end)
    for i = cfg.cars + 1, #cars do
        local unit = cars[i].unit
        unit.leaving = true
        for _, v in ipairs(unit.vehicles) do if isElement(v) then setVehicleSirensOn(v, false) end end
        sendUnit(player, unit)
        unit.timer = setTimer(function() removeUnit(player, unit, true) end, WANTED_DISPATCH.LEAVE_TIME, 1)
    end

    if now < p.next or p.pending then return end
    p.next = now + WANTED_DISPATCH.TICK

    if #cars < cfg.cars then
        p.pending = { kind = "car", at = now }
        triggerClientEvent(player, "rp:wanted:spawnRequest", resourceRoot, "car")
    elseif helis < cfg.heli then
        spawnHeli(player)
    elseif cfg.roadblock > 0 and not p.roadblock and math.random(100) <= cfg.roadblock then
        local v = getPedOccupiedVehicle(player)
        if v then
            local vx, vy = getElementVelocity(v)
            if math.sqrt(vx * vx + vy * vy) * 180 > 40 then
                p.pending = { kind = "roadblock", at = now }
                triggerClientEvent(player, "rp:wanted:spawnRequest", resourceRoot, "roadblock")
            end
        end
    end
end

setTimer(function()
    local now = nowMs()
    for player, p in pairs(pursuits) do
        if not isElement(player) then
            for _, unit in pairs(p.units) do destroyUnitElements(unit) end
            pursuits[player] = nil
        else
            if p.pending and now - p.pending.at > 6000 then p.pending = nil end
            dispatch(player, p)
            if getWantedLevel(player) == 0 and next(p.units) == nil then pursuits[player] = nil end
        end
    end
end, 1000, 0)

addEventHandler("rp:onWantedLevelChange", root, function(level, old)
    local player = source
    if level > 0 then
        local p = pursuitOf(player)
        if old == 0 then p.next = nowMs() + WANTED_DISPATCH.FIRST_DELAY end
        -- Armas de los policias segun el nuevo nivel (a 1 estrella no disparan)
        for _, unit in pairs(p.units) do
            if unit.kind ~= "heli" and not unit.leaving then
                local _, _, _, weapon = resolveFleet(unit.fleet, getElementPosition(player))
                for _, ped in ipairs(unit.peds) do
                    if isElement(ped) and not isPedDead(ped) and level > 1 and old <= 1 then
                        giveWeapon(ped, weapon, 9999, true)
                    end
                end
            end
        end
    end
    if isElement(player) then
        triggerClientEvent(player, "rp:wanted:level", resourceRoot, level)
        if pursuits[player] then dispatch(player, pursuits[player]) end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    local p = pursuits[source]
    if p then
        for _, unit in pairs(p.units) do destroyUnitElements(unit) end
        pursuits[source] = nil
    end
end)

----------------------------------------------------------------
-- Cliente -> servidor (solo el dueno de la unidad)
----------------------------------------------------------------
local function ownedBy(player, el)
    local o = isElement(el) and unitOwner[el]
    return o and o.player == player and o.unit or nil
end

addEventHandler("rp:wanted:spawnAt", resourceRoot, function(kind, x, y, z, rot)
    local player = client
    local p = pursuits[player]
    if not p or not p.pending or p.pending.kind ~= kind then return end
    p.pending = nil
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot) or 0
    if not (x and y and z) or getWantedLevel(player) <= 0 then return end
    local px, py = getElementPosition(player)
    local d = getDistanceBetweenPoints2D(px, py, x, y)
    if d < 30 or d > 320 then return end
    if kind == "car" then
        spawnCar(player, x, y, z, rot)
    elseif kind == "roadblock" and not p.roadblock then
        spawnRoadblock(player, x, y, z, rot)
    end
end)

-- Los policias se bajan del auto junto a su puerta
addEventHandler("rp:wanted:dismount", resourceRoot, function(vehicle)
    local player = client
    local unit = ownedBy(player, vehicle)
    if not unit or unit.vehicle ~= vehicle then return end
    local _, _, rz = getElementRotation(vehicle)
    local r = math.rad(rz)
    local rx, ry = math.cos(r), math.sin(r)
    local vx, vy, vz = getElementPosition(vehicle)
    for _, ped in ipairs(unit.peds) do
        if isElement(ped) and not isPedDead(ped) and getPedOccupiedVehicle(ped) == vehicle then
            local seat = getPedOccupiedVehicleSeat(ped) or 0
            local side = (seat % 2 == 0) and -1.9 or 1.9
            removePedFromVehicle(ped)
            setElementPosition(ped, vx + rx * side, vy + ry * side, vz + 0.2)
            setElementRotation(ped, 0, 0, rz)
        end
    end
    unit.onFoot = true
end)

-- Vuelve a subir (cerca de su auto)
addEventHandler("rp:wanted:remount", resourceRoot, function(ped)
    local player = client
    local unit = ownedBy(player, ped)
    local vehicle = unit and unit.kind == "car" and unit.vehicle
    if not vehicle or not isElement(vehicle) or isPedDead(ped) or isPedInVehicle(ped) then return end
    local x, y, z = getElementPosition(ped)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(x, y, z, vx, vy, vz) > 7 or isVehicleBlown(vehicle) then return end
    local maxSeat = getVehicleMaxPassengers(vehicle) or 1
    for seat = 0, maxSeat do
        if not getVehicleOccupant(vehicle, seat) then
            warpPedIntoVehicle(ped, vehicle, seat)
            setElementSyncer(ped, player)
            return
        end
    end
end)

-- Una unidad lejos o atascada fuera de la vista: se retira y el despacho manda otra
addEventHandler("rp:wanted:unitLost", resourceRoot, function(id)
    local p = pursuits[client]
    local unit = p and p.units[tonumber(id) or -1]
    if unit and unit.kind ~= "roadblock" then removeUnit(client, unit, false) end
end)

-- Un policia te alcanzo: arresto (se comprueba la distancia en el servidor)
addEventHandler("rp:wanted:busted", resourceRoot, function(ped)
    local player = client
    if not ownedBy(player, ped) or isPedDead(ped) or isPedDead(player) then return end
    local x, y, z = getElementPosition(ped)
    local px, py, pz = getElementPosition(player)
    local limit = isPedInVehicle(player) and 5 or 3.2
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > limit then return end
    if bustPlayer(player, ped) then
        local p = pursuits[player]
        if p then leaveAll(player, p) end
    end
end)

-- El cliente (re)inicia el recurso: se le reenvian sus unidades
addEventHandler("rp:wanted:ready", resourceRoot, function()
    local p = pursuits[client]
    triggerClientEvent(client, "rp:wanted:level", resourceRoot, getWantedLevel(client))
    if p then for _, unit in pairs(p.units) do sendUnit(client, unit) end end
end)

-- Policia muerto: queda el cuerpo y se borra despues
addEventHandler("onPedWasted", root, function()
    local o = unitOwner[source]
    if not o then return end
    local ped = source
    setTimer(function()
        if isElement(ped) and unitOwner[ped] then setElementAlpha(ped, 0) end
    end, WANTED_DISPATCH.BODY_TIME, 1)
end)

addEventHandler("onVehicleExplode", root, function()
    local o = unitOwner[source]
    if o and isElement(o.player) and o.unit.kind ~= "roadblock" then
        local player, unit = o.player, o.unit
        unit.leaving = true
        if isTimer(unit.timer) then killTimer(unit.timer) end
        unit.timer = setTimer(function() removeUnit(player, unit, false) end, WANTED_DISPATCH.BODY_TIME, 1)
        sendUnit(player, unit)
    end
end)

-- Robar una patrulla: deja de ser de la policia
addEventHandler("onVehicleEnter", root, function(player, seat)
    local o = unitOwner[source]
    if o and seat == 0 and getElementType(player) == "player" then
        local unit = o.unit
        for i, v in ipairs(unit.vehicles) do
            if v == source then table.remove(unit.vehicles, i) break end
        end
        if unit.vehicle == source then unit.vehicle = nil end
        unitOwner[source] = nil
        setElementData(source, "rp:copCar", false)
        if isElement(o.player) then sendUnit(o.player, unit) end
        -- se borra cuando lo abandona y nadie lo usa
        local v = source
        local t
        t = setTimer(function()
            if not isElement(v) then return killTimer(t) end
            if not getVehicleController(v) then
                local vx, vy, vz = getElementPosition(v)
                local near = false
                for _, p in ipairs(getElementsWithinRange(vx, vy, vz, 150, "player")) do near = true break end
                if not near then killTimer(t) destroyElement(v) end
            end
        end, 30000, 0)
    end
end)

----------------------------------------------------------------
-- Presencia policial (para el decaimiento de s_wanted.lua)
----------------------------------------------------------------
function wantedUnitsNear(x, y, z, radius)
    for el, o in pairs(unitOwner) do
        if isElement(el) and not o.unit.leaving then
            local alive = getElementType(el) == "ped" and not isPedDead(el)
                or getElementType(el) == "vehicle" and not isVehicleBlown(el)
            if alive then
                local ex, ey, ez = getElementPosition(el)
                if getDistanceBetweenPoints3D(x, y, z, ex, ey, ez) < radius then return true end
            end
        end
    end
    return false
end

addEventHandler("onResourceStop", resourceRoot, function()
    for _, p in pairs(pursuits) do
        for _, unit in pairs(p.units) do destroyUnitElements(unit) end
    end
end)
