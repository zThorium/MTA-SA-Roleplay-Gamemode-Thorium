--[[
    rp_driving / s_runs.lua

    Ejecucion de una prueba de la autoescuela. Todo lo que puntua lo mide el
    servidor: tiempo, checkpoints (con marcha atras cuando toca), giro acumulado,
    zona de parada, vida del auto y salida de la pista. El cliente solo dibuja,
    hace la presentacion y avisa de los conos que derriba (el servidor lo
    comprueba por distancia; avisar de menos solo empeoraria su puntaje).

    Cada intento va en una dimension privada con su propio auto y conos. Al
    terminar (o al salir del juego) el jugador vuelve frente al instructor.
]]

local runs = {}          -- [player] = run
local usedSlots = {}     -- [slot] = player
local tickTimer = nil

addEvent("rp:driving:start", true)
addEvent("rp:driving:ready", true)
addEvent("rp:driving:cone", true)
addEvent("rp:driving:abort", true)
addEvent("rp:onCharacterLogout", false)

local function sq(x) return x * x end

function isPlayerInTest(player)
    return runs[player] ~= nil
end

local function speedKmh(el)
    local vx, vy, vz = getElementVelocity(el)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

----------------------------------------------------------------
-- Puntaje (puro: lo usan las pruebas automaticas via export)
----------------------------------------------------------------
--[[
    data = { time = s, healthLost = 0-1000, cones = n, dist = m | nil, angle = grados | nil }
    Devuelve score (0-100 entero), medalla (0-4) y el desglose de lo restado.
]]
function computeScore(test, data)
    local d = DRIVING
    local breakdown = {
        time = math.max(0, (data.time or 0) - test.par) * d.TIME_PENALTY,
        damage = math.max(0, data.healthLost or 0) / 100 * d.DAMAGE_PENALTY,
        cones = (data.cones or 0) * d.CONE_PENALTY,
        position = data.dist and math.max(0, data.dist - d.DIST_FREE) * d.DIST_PENALTY or 0,
        angle = data.angle and math.max(0, math.abs(data.angle) - d.ANGLE_FREE) * d.ANGLE_PENALTY or 0,
    }
    local lost = 0
    for k, v in pairs(breakdown) do
        breakdown[k] = math.floor(v * 10 + 0.5) / 10
        lost = lost + v
    end
    -- Redondeo hacia abajo: el 100 solo con una prueba sin nada que restar
    local score = math.max(0, math.min(100, math.floor(100 - lost + 1e-6)))
    return score, drivingMedalFor(test, score, data.time or 0), breakdown
end

function computeTestScore(testId, data)
    local test = DRIVING_TEST_INDEX[testId]
    if not test or type(data) ~= "table" then return false end
    local score, medal, breakdown = computeScore(test, data)
    return score, medal, breakdown
end

-- Comprueba si (score, time) mejora a best
local function isBetter(score, time, best)
    if not best or best.medal == 0 then return true end
    if score ~= best.score then return score > best.score end
    return time < best.time
end

----------------------------------------------------------------
-- Geometria del intento
----------------------------------------------------------------
local function totalCheckpoints(test)
    return #test.checkpoints * (test.laps or 1)
end

local function checkpointAt(test, index)
    local n = #test.checkpoints
    if n == 0 then return nil end
    return test.checkpoints[((index - 1) % n) + 1]
end

-- Distancia de un punto al segmento (x1,y1)-(x2,y2): detecta el paso aunque el auto vaya rapido
local function segmentDistance(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len = dx * dx + dy * dy
    local t = 0
    if len > 0 then t = math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / len)) end
    return math.sqrt(sq(x1 + t * dx - px) + sq(y1 + t * dy - py))
end

-- Posicion del auto dentro de la zona: along/across en metros y error de angulo
local function boxMeasure(run, vehicle)
    local box = run.test.box
    local x, y = getElementPosition(vehicle)
    local f, r = drivingToLocal(run.arena, x, y)
    local df, dr = f - box.f, r - box.r
    local a = math.rad(box.a)
    local along = df * math.cos(a) - dr * math.sin(a)
    local across = df * math.sin(a) + dr * math.cos(a)
    local _, _, rz = getElementRotation(vehicle)
    local err = math.abs(drivingWrap(drivingWrap(rz - run.arena.rot) - box.a))
    if box.sym then err = math.min(err, 180 - err) end
    local inside = math.abs(along) <= box.l / 2 and math.abs(across) <= box.w / 2
    return inside, math.sqrt(along * along + across * across), err
end

local function updateMarker(run)
    if isElement(run.marker) then destroyElement(run.marker) end
    run.marker = nil
    local total = totalCheckpoints(run.test)
    if run.cpIndex > total then return end
    local cp = checkpointAt(run.test, run.cpIndex)
    local x, y = drivingToWorld(run.arena, cp[1], cp[2])
    local marker = createMarker(x, y, run.arena.z, "checkpoint", cp[3] or 4, 245, 165, 36, 160, run.player)
    setElementDimension(marker, run.dim)
    local nextCp = run.cpIndex < total and checkpointAt(run.test, run.cpIndex + 1)
    if nextCp then
        local nx, ny = drivingToWorld(run.arena, nextCp[1], nextCp[2])
        setMarkerTarget(marker, nx, ny, run.arena.z)
    elseif run.test.box then
        local bx, by = drivingToWorld(run.arena, run.test.box.f, run.test.box.r)
        setMarkerTarget(marker, bx, by, run.arena.z)
    else
        setMarkerIcon(marker, "finish")
    end
    run.marker = marker
end

----------------------------------------------------------------
-- Limpieza y regreso a la autoescuela
----------------------------------------------------------------
local function destroyRunElements(run)
    for _, t in pairs(run.timers) do if isTimer(t) then killTimer(t) end end
    run.timers = {}
    if isElement(run.marker) then destroyElement(run.marker) end
    for _, c in ipairs(run.cones) do if isElement(c.object) then destroyElement(c.object) end end
    run.cones = {}
    if isElement(run.vehicle) then destroyElement(run.vehicle) end
    if run.slot then usedSlots[run.slot] = nil end
end

local function returnPlayer(run)
    local p = run.player
    if not isElement(p) or not run.schoolId then return end
    local x, y, z, rot, interior, dimension = getSchoolReturnPoint(run.schoolId)
    if isPedInVehicle(p) then removePedFromVehicle(p) end
    setElementInterior(p, interior)
    setElementDimension(p, dimension)
    setElementPosition(p, x, y, z + 0.2)
    setElementRotation(p, 0, 0, rot, "default", true)
    setElementFrozen(p, false)
    setCameraTarget(p, p)
    fadeCamera(p, true, 0.8)
    setElementData(p, "rp:drivingTest", false)
end

local function stopTickIfIdle()
    if next(runs) == nil and isTimer(tickTimer) then
        killTimer(tickTimer)
        tickTimer = nil
    end
end

-- Cierra el intento sin resultado (salida del juego, reinicio del recurso...)
local function dropRun(player, returnToSchool)
    local run = runs[player]
    if not run then return end
    runs[player] = nil
    destroyRunElements(run)
    if returnToSchool then returnPlayer(run) end
    stopTickIfIdle()
end

----------------------------------------------------------------
-- Final del intento
----------------------------------------------------------------
local function saveResult(run, score, medal, timeMs, callback)
    local characterId, test = run.characterId, run.test
    local best = run.scores[test.id]
    local improved = medal > 0 and isBetter(score, timeMs / 1000, best)
    if improved then
        dbExec(db(), [[
            INSERT INTO driving_scores (character_id, test_id, best_score, best_time_ms, medal, attempts) VALUES (?, ?, ?, ?, ?, 1)
            ON DUPLICATE KEY UPDATE best_score = VALUES(best_score), best_time_ms = VALUES(best_time_ms),
                medal = VALUES(medal), attempts = attempts + 1
        ]], characterId, test.id, score, timeMs, medal)
        run.scores[test.id] = { score = score, time = timeMs / 1000, medal = medal, attempts = (best and best.attempts or 0) + 1 }
    else
        dbExec(db(), [[
            INSERT INTO driving_scores (character_id, test_id, attempts) VALUES (?, ?, 1)
            ON DUPLICATE KEY UPDATE attempts = attempts + 1
        ]], characterId, test.id)
    end
    callback(improved)
end

local function finishRun(run, passed, reason, extra)
    if run.phase == "ending" then return end
    run.phase = "ending"
    local player, test = run.player, run.test
    if isElement(run.vehicle) then setElementFrozen(run.vehicle, true) end
    if isElement(run.marker) then destroyElement(run.marker) end

    local timeMs = run.startTick and (getTickCount() - run.startTick) or 0
    local health = isElement(run.vehicle) and getElementHealth(run.vehicle) or 0
    local result = {
        testId = test.id, name = test.name, index = test.index, time = timeMs / 1000, par = test.par,
        platinum = test.platinum, cones = run.coneHits, damage = math.max(0, math.floor(1000 - health)),
        passed = false, reason = reason,
    }

    if passed then
        local score, medal, breakdown = computeScore(test, {
            time = timeMs / 1000, healthLost = 1000 - health, cones = run.coneHits,
            dist = extra and extra.dist, angle = extra and extra.angle,
        })
        result.score, result.medal, result.breakdown = score, medal, breakdown
        result.passed = medal > 0
        result.dist = extra and extra.dist and math.floor(extra.dist * 100 + 0.5) / 100
        result.angle = extra and extra.angle and math.floor(extra.angle + 0.5)
        if not result.passed then result.reason = "Necesitas al menos 70 puntos para aprobar." end
    end

    triggerClientEvent(player, "rp:driving:finish", resourceRoot, result.passed, result.score or 0, result.medal or 0, result.reason)

    local function deliver(improved)
        result.improved = improved
        result.best = run.scores[test.id]
        -- Logros (rp_achievements): pruebas con oro o platino en su mejor marca
        local golds = 0
        for _, sc in pairs(run.scores or {}) do
            if type(sc) == "table" and (tonumber(sc.medal) or 0) >= 3 then golds = golds + 1 end
        end
        triggerEvent("rp:achievements:progress", player, "driving_gold", golds)
        local nextTest = DRIVING_TESTS[test.index + 1]
        if result.passed and nextTest then result.unlocked, result.nextId = nextTest.name, nextTest.id end

        run.timers.back = setTimer(function()
            if not isElement(player) then return end
            fadeCamera(player, false, 0.6)
            run.timers.back2 = setTimer(function()
                if runs[player] ~= run then return end
                dropRun(player, true)
                triggerClientEvent(player, "rp:driving:result", resourceRoot, result)
                if result.passed then afterTestPassed(player, run.characterId, test, run.scores) end
            end, 700, 1)
        end, 2600, 1)
    end

    if not passed then
        dbExec(db(), "INSERT INTO driving_scores (character_id, test_id, attempts) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE attempts = attempts + 1",
            run.characterId, test.id)
        return deliver(false)
    end

    local record = getTestRecord(test.id)
    saveResult(run, result.score, result.medal, timeMs, function(improved)
        if improved and result.passed and (not record or isBetter(result.score, result.time, record)) then
            result.schoolRecord = true
            outputChatBox(("#f5a524[Autoescuela]#ffffff %s bate el record de #f5a524%s#ffffff: %d%% en %.2f s."):format(
                displayName(getPlayerName(player)), test.name, result.score, result.time), root, 255, 255, 255, true)
        end
        if improved then refreshBoard(true) end
        deliver(improved)
    end)
end

local function failRun(run, reason)
    finishRun(run, false, reason)
end

----------------------------------------------------------------
-- Bucle de comprobacion (servidor)
----------------------------------------------------------------
local function updateRun(run)
    local player, vehicle, test = run.player, run.vehicle, run.test
    if not isElement(player) then return dropRun(player) end
    if not isElement(vehicle) or isVehicleBlown(vehicle) or getElementHealth(vehicle) < 300 then
        return failRun(run, "El auto quedo destrozado.")
    end
    if getPedOccupiedVehicle(player) ~= vehicle then return failRun(run, "Te bajaste del auto.") end
    if isPedDead(player) or getElementData(player, "rp:downed") then return failRun(run, "Resultaste herido.") end

    local now = getTickCount()
    local elapsed = (now - run.startTick) / 1000
    if elapsed > test.limit then return failRun(run, "Se acabo el tiempo.") end

    local x, y = getElementPosition(vehicle)
    local f, r = drivingToLocal(run.arena, x, y)
    if math.sqrt(f * f + r * r) > DRIVING.ARENA_RADIUS then return failRun(run, "Te saliste de la pista.") end

    -- Volcado
    local rx, ry, rz = getElementRotation(vehicle)
    if math.abs(drivingWrap(rx)) > 70 or math.abs(drivingWrap(ry)) > 70 then
        run.flippedSince = run.flippedSince or now
        if now - run.flippedSince > DRIVING.FLIP_TIME then return failRun(run, "Volcaste el auto.") end
    else
        run.flippedSince = nil
    end

    -- Giro acumulado (trompo)
    if run.lastYaw then run.spin = run.spin + drivingWrap(rz - run.lastYaw) end
    run.lastYaw = rz

    -- Checkpoints
    local total = totalCheckpoints(test)
    if run.cpIndex <= total then
        local cp = checkpointAt(test, run.cpIndex)
        local cx, cy = drivingToWorld(run.arena, cp[1], cp[2])
        local lx, ly = run.lastX or x, run.lastY or y
        if segmentDistance(cx, cy, lx, ly, x, y) <= (cp[3] or 4) then
            local ok = true
            if cp.reverse then
                local vx, vy = getElementVelocity(vehicle)
                local h = math.rad(rz)
                ok = (vx * -math.sin(h) + vy * math.cos(h)) < 0
                if not ok and run.warnedCp ~= run.cpIndex then
                    run.warnedCp = run.cpIndex
                    triggerClientEvent(player, "rp:driving:warn", resourceRoot, "¡En marcha atras! Ese punto no cuenta.")
                end
            end
            if ok then
                run.cpIndex = run.cpIndex + 1
                triggerClientEvent(player, "rp:driving:checkpoint", resourceRoot, run.cpIndex - 1, total)
                updateMarker(run)
                if run.cpIndex > total and not test.box then
                    run.lastX, run.lastY = x, y
                    return finishRun(run, true)
                end
            end
        end
    end
    run.lastX, run.lastY = x, y

    -- Zona de parada
    if test.box and run.cpIndex > total and (not test.spin or math.abs(run.spin) >= test.spin) then
        local inside, dist, angle = boxMeasure(run, vehicle)
        if inside and speedKmh(vehicle) < DRIVING.STOP_SPEED then
            run.stoppedSince = run.stoppedSince or now
            if now - run.stoppedSince >= DRIVING.STOP_HOLD then
                return finishRun(run, true, nil, { dist = dist, angle = angle })
            end
        else
            run.stoppedSince = nil
        end
    end
end

local function ensureTick()
    if isTimer(tickTimer) then return end
    tickTimer = setTimer(function()
        for _, run in pairs(runs) do
            if run.phase == "running" then
                local ok, err = pcall(updateRun, run)
                if not ok then
                    outputDebugString("[rp_driving] Error en la prueba: " .. tostring(err), 1)
                    failRun(run, "Error interno de la prueba.")
                end
            end
        end
    end, DRIVING.TICK, 0)
end

----------------------------------------------------------------
-- Inicio
----------------------------------------------------------------
local function startRunning(run)
    if run.phase ~= "intro" then return end
    run.phase = "countdown"
    if isTimer(run.timers.intro) then killTimer(run.timers.intro) end
    triggerClientEvent(run.player, "rp:driving:countdown", resourceRoot, DRIVING.COUNTDOWN)
    run.timers.go = setTimer(function()
        if runs[run.player] ~= run or not isElement(run.vehicle) then return end
        setElementFrozen(run.vehicle, false)
        setVehicleEngineState(run.vehicle, true)
        run.phase = "running"
        run.startTick = getTickCount()
        local _, _, rz = getElementRotation(run.vehicle)
        run.lastYaw, run.spin = rz, 0
        triggerClientEvent(run.player, "rp:driving:go", resourceRoot)
        ensureTick()
    end, DRIVING.COUNTDOWN * 1000, 1)
end

local function freeSlot(player)
    for i = 1, DRIVING.MAX_RUNS do
        if not usedSlots[i] then
            usedSlots[i] = player
            return i
        end
    end
end

local function setupRun(player, test, schoolId, characterId, scores)
    local slot = freeSlot(player)
    if not slot then return notify(player, "La pista esta llena, prueba en un momento.", "warning") end
    local arena = getSchoolArena(schoolId)
    local run = {
        player = player, test = test, schoolId = schoolId, characterId = characterId, scores = scores,
        arena = arena, slot = slot, dim = DRIVING.DIMENSION_BASE + slot, phase = "loading",
        cones = {}, coneHits = 0, cpIndex = 1, spin = 0, timers = {},
    }
    runs[player] = run
    setElementData(player, "rp:drivingTest", test.id)
    triggerClientEvent(player, "rp:driving:closeMenu", resourceRoot)
    fadeCamera(player, false, 0.5)

    run.timers.setup = setTimer(function()
        if runs[player] ~= run or not isElement(player) then return end
        local s = test.start
        local x, y = drivingToWorld(arena, s[1], s[2])
        local rot = (arena.rot + (s[3] or 0)) % 360
        local vehicle = createVehicle(test.model, x, y, arena.z + 1, 0, 0, rot, "ESCUELA")
        if not vehicle then
            dropRun(player, true)
            return notify(player, "No se pudo preparar el auto de la prueba.", "error")
        end
        run.vehicle = vehicle
        setElementDimension(vehicle, run.dim)
        setVehicleColor(vehicle, 255, 255, 255, 220, 40, 40)
        setVehicleDamageProof(vehicle, false)
        setElementHealth(vehicle, 1000)
        setElementData(vehicle, "rp:drivingSchool", true)
        setElementFrozen(vehicle, true)

        for i, c in ipairs(test.cones) do
            local cx, cy = drivingToWorld(arena, c[1], c[2])
            local obj = createObject(1238, cx, cy, arena.z + 0.3)
            setElementDimension(obj, run.dim)
            run.cones[i] = { object = obj, x = cx, y = cy }
        end

        if isPedInVehicle(player) then removePedFromVehicle(player) end
        setElementInterior(player, 0)
        setElementDimension(player, run.dim)
        setElementPosition(player, x, y, arena.z + 2)
        warpPedIntoVehicle(player, vehicle)
        updateMarker(run)
        fadeCamera(player, true, 0.8)

        run.phase = "intro"
        triggerClientEvent(player, "rp:driving:begin", resourceRoot, test.id, arena, vehicle, #run.cones)
        run.timers.intro = setTimer(function() startRunning(run) end, DRIVING.INTRO_TIMEOUT, 1)
    end, 600, 1)
end

addEventHandler("rp:driving:start", resourceRoot, function(testId)
    local player = client
    if type(testId) ~= "string" or runs[player] then return end
    local test = DRIVING_TEST_INDEX[testId]
    local characterId = characterOf(player)
    if not test or not characterId then return end
    if getElementData(player, "rp:downed") or isPedDead(player) then return end
    if isPedInVehicle(player) then return notify(player, "Bajate del vehiculo para hablar con el instructor.", "warning") end
    local schoolId = getNearSchool(player)
    if not schoolId then return notify(player, "Tienes que estar junto al instructor.", "warning") end

    runs[player] = { pending = true, timers = {}, cones = {} }   -- reserva mientras llega la BD
    loadCharacterScores(characterId, function(scores)
        if not isElement(player) or characterOf(player) ~= characterId or not (runs[player] and runs[player].pending) then return end
        runs[player] = nil
        if not isTestUnlocked(scores, test) then
            return notify(player, "Primero aprueba la prueba anterior.", "warning")
        end
        setupRun(player, test, schoolId, characterId, scores)
    end)
end)

addEventHandler("rp:driving:ready", resourceRoot, function()
    local run = runs[client]
    if run and run.phase == "intro" then startRunning(run) end
end)

addEventHandler("rp:driving:abort", resourceRoot, function()
    local run = runs[client]
    if not run or run.pending then return end
    if run.phase == "running" or run.phase == "countdown" or run.phase == "intro" then
        if run.phase ~= "running" then run.startTick = getTickCount() end
        failRun(run, "Abandonaste la prueba.")
    end
end)

-- El cliente avisa del cono que golpeo; el servidor lo acepta una vez y si el auto esta cerca
addEventHandler("rp:driving:cone", resourceRoot, function(index)
    local run = runs[client]
    index = tonumber(index)
    if not run or run.phase ~= "running" or not index then return end
    local cone = run.cones[index]
    if not cone or cone.hit or not isElement(run.vehicle) then return end
    local x, y = getElementPosition(run.vehicle)
    if getDistanceBetweenPoints2D(x, y, cone.x, cone.y) > 8 then return end
    cone.hit = true
    run.coneHits = run.coneHits + 1
    triggerClientEvent(client, "rp:driving:coneHit", resourceRoot, run.coneHits)
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
-- Salir del juego o del personaje en plena prueba: rp_characters guarda la posicion al
-- cerrar el personaje. Se devuelve al jugador frente al instructor (por si nuestro
-- handler corre antes) y se corrige la fila (por si corre despues), para que nunca
-- aparezca en la pista privada.
local function leaveDuringRun(player, characterId)
    local run = runs[player]
    if not run then return end
    characterId = characterId or run.characterId
    if run.schoolId and characterId then
        local x, y, z, rot, interior, dimension = getSchoolReturnPoint(run.schoolId)
        dbExec(db(), "UPDATE characters SET pos_x = ?, pos_y = ?, pos_z = ?, rotation = ?, interior = ?, dimension = ? WHERE id = ?",
            x, y, z, rot, interior, dimension, characterId)
    end
    dropRun(player, true)
end

addEventHandler("rp:onCharacterLogout", root, function(characterId) leaveDuringRun(source, characterId) end)
addEventHandler("onPlayerQuit", root, function() leaveDuringRun(source) end)

addEventHandler("onPlayerWasted", root, function()
    local run = runs[source]
    if run and not run.pending and run.phase ~= "ending" then failRun(run, "Resultaste herido.") end
end)

addEventHandler("onVehicleStartExit", root, function(player)
    local run = runs[player]
    if run and run.vehicle == source and run.phase ~= "ending" then cancelEvent() end
end)

-- Nadie mas puede subirse al auto de la prueba
addEventHandler("onVehicleStartEnter", root, function(player)
    if getElementData(source, "rp:drivingSchool") then
        local run = runs[player]
        if not run or run.vehicle ~= source then cancelEvent() end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(runs) do
        if isElement(player) then dropRun(player, true) end
    end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function isPlayerInDrivingTest(player)
    return runs[player] ~= nil
end

function getTestCount()
    return #DRIVING_TESTS
end
