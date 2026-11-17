--[[
    rp_rides / c_driver.lua
    Conductor IA del auto de Vroom. El auto y el NPC son del servidor; el
    servidor nos hace "syncer" y aqui se conduce al NPC con sus controles
    (acelerar, frenar, volante) siguiendo los puntos del carril de la ruta A*.

      pickup: va hasta el pasajero (si este se mueve, recalcula)
      ride:   lleva al pasajero hasta el destino
      leave:  se aleja por la calle (el servidor lo hace desaparecer)
]]

local ai = nil   -- { vehicle, ped, mode, wp, idx, dest, timer, ... }

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end
local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

local function speedKmh(el)
    local vx, vy, vz = getElementVelocity(el)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

local function controls(accel, brake, steer, handbrake)
    local ped = ai.ped
    if not isElement(ped) then return end
    setPedControlState(ped, "accelerate", accel)
    setPedControlState(ped, "brake_reverse", brake)
    setPedControlState(ped, "handbrake", handbrake or false)
    steer = math.max(-1, math.min(1, steer or 0))
    setPedAnalogControlState(ped, "vehicle_left", steer > 0 and steer or 0)
    setPedAnalogControlState(ped, "vehicle_right", steer < 0 and -steer or 0)
end

-- Nodo cercano que este por delante del auto (para no dar media vuelta al arrancar)
local function startNodeAhead(vehicle)
    local x, y = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    local fx, fy = m[2][1], m[2][2]
    local best, bestD = nil, math.huge
    for ox = -2, 2 do
        for oy = -2, 2 do
            local n = nearestRoadNode(x + ox * 25, y + oy * 25, 1)
            if n then
                local nx, ny = nodePosition(n)
                local d = getDistanceBetweenPoints2D(x, y, nx, ny)
                local dot = d > 0.1 and ((nx - x) * fx + (ny - y) * fy) / d or 1
                if d < 70 and dot > 0.3 and d < bestD then best, bestD = n, d end
            end
        end
    end
    return best or nearestRoadNode(x, y)
end

-- Calcula la ruta hasta (tx, ty). Devuelve la lista de nodos para el mapa de la app.
local function plan(tx, ty)
    local vehicle = ai.vehicle
    local x, y, z = getElementPosition(vehicle)
    local route = nil
    if loadRoadGraph() then
        local s = startNodeAhead(vehicle)
        local g = nearestRoadNode(tx, ty)
        route = s and g and findRoadRoute(s, g)
    end
    if route and #route >= 2 then
        ai.wp = routeWaypoints(route)
    else
        -- Sin red vial: linea recta (fallback)
        ai.wp = {}
        local d = getDistanceBetweenPoints2D(x, y, tx, ty)
        local steps = math.max(1, math.floor(d / 8))
        for i = 1, steps do
            local t = i / steps
            ai.wp[#ai.wp + 1] = { x + (tx - x) * t, y + (ty - y) * t, z }
        end
        route = nil
    end
    -- ultimo punto: lo mas cerca posible del objetivo, sobre el carril
    ai.idx = 1
    ai.target = { tx, ty }
    ai.legStart = getTickCount()
    ai.lastProgress, ai.bestRemaining = getTickCount(), math.huge
    ai.reached = false
    return route
end

local function remainingDistance()
    local wp = ai.wp
    local last = wp[#wp]
    if not last then return 0 end
    local x, y = getElementPosition(ai.vehicle)
    return getDistanceBetweenPoints2D(x, y, last[1], last[2])
end

-- Recoloca el auto sobre la ruta (atasco largo)
local function warpAhead(steps)
    local wp = ai.wp
    local i = math.min(#wp, ai.idx + (steps or 3))
    local p, q = wp[i], wp[math.min(#wp, i + 1)]
    if not p then return end
    local rot = q and q ~= p and heading(q[1] - p[1], q[2] - p[2]) or select(3, getElementRotation(ai.vehicle))
    setElementPosition(ai.vehicle, p[1], p[2], p[3] + 1.2)
    setElementRotation(ai.vehicle, 0, 0, rot)
    setElementVelocity(ai.vehicle, 0, 0, 0)
    ai.idx = i
    ai.stuckSince, ai.reverseUntil = nil, nil
end

local function obstacleAhead(vehicle, m, speed)
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local fx, fy = m[2][1], m[2][2]
    local reach = 7 + speed * 0.18
    local sx, sy = x + fx * 2.6, y + fy * 2.6
    local hit, hx, hy, _, el = processLineOfSight(sx, sy, z + 0.3, sx + fx * reach, sy + fy * reach, z + 0.3,
        false, true, true, true, false, true, false, false, vehicle)
    if hit and el ~= ai.ped and el ~= localPlayer then
        return getDistanceBetweenPoints2D(sx, sy, hx, hy)
    end
end

local function onReached()
    if ai.mode == "pickup" then
        triggerServerEvent("rp:rides:aiArrived", resourceRoot)
    elseif ai.mode == "ride" then
        triggerServerEvent("rp:rides:aiDropoff", resourceRoot)
    end
end

local function tick()
    if not ai then return end
    local vehicle, ped = ai.vehicle, ai.ped
    if not isElement(vehicle) or not isElement(ped) then return stopAIDriver() end
    if not isElementSyncer(vehicle) then return end   -- el servidor aun no nos dio el control

    local now = getTickCount()
    local x, y, z = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    local _, _, rz = getElementRotation(vehicle)
    local speed = speedKmh(vehicle)
    local wp = ai.wp

    -- El pasajero se movio lejos del punto de recogida: recalcula
    if ai.mode == "pickup" and not ai.reached and now - (ai.replanAt or 0) > 3000 then
        ai.replanAt = now
        local px, py = getElementPosition(localPlayer)
        if getDistanceBetweenPoints2D(px, py, ai.target[1], ai.target[2]) > 30 then plan(px, py) wp = ai.wp end
    end

    -- Esperando parado (llego a recoger o termino de alejarse)
    if ai.reached or #wp == 0 then return controls(false, speed > 1, 0, true) end

    -- Avanza por los puntos ya alcanzados
    while ai.idx < #wp and getDistanceBetweenPoints2D(x, y, wp[ai.idx][1], wp[ai.idx][2]) < 7 do ai.idx = ai.idx + 1 end

    local remaining = remainingDistance()
    local arriveRadius = ai.mode == "pickup" and 10 or 12
    if ai.idx >= #wp and remaining < arriveRadius then
        if ai.mode == "pickup" then
            local px, py = getElementPosition(localPlayer)
            if getDistanceBetweenPoints2D(px, py, x, y) > RIDES.AI_PICKUP_RADIUS + 10 then
                plan(px, py)
                return
            end
        end
        if speed < 3 then
            ai.reached = true
            setPedControlState(ped, "horn", true)
            setTimer(function() if isElement(ped) then setPedControlState(ped, "horn", false) end end, 700, 1)
            if ai.mode ~= "leave" then onReached() end
        end
        return controls(false, true, 0, speed < 8)
    end

    -- Punto objetivo (seguimiento con mirada adelantada)
    local look = 6 + speed * 0.12
    local ti = ai.idx
    while ti < #wp and getDistanceBetweenPoints2D(x, y, wp[ti][1], wp[ti][2]) < look do ti = ti + 1 end
    local t = wp[ti]
    local diff = angleDiff(heading(t[1] - x, t[2] - y), rz)

    -- Velocidad deseada: crucero, mas lento en curvas y al llegar
    local desired = RIDES.AI_CRUISE
    local a1, a2 = wp[math.min(#wp, ti + 1)], wp[math.min(#wp, ti + 4)]
    if a1 and a2 and a1 ~= a2 then
        local turn = math.abs(angleDiff(heading(a2[1] - a1[1], a2[2] - a1[2]), heading(t[1] - x, t[2] - y)))
        if turn > 50 then desired = 18 elseif turn > 25 then desired = 28 end
    end
    if math.abs(diff) > 40 then desired = math.min(desired, 15) end
    desired = math.min(desired, 8 + remaining * 0.9)

    local obstacle = obstacleAhead(vehicle, m, speed)
    if obstacle and obstacle < 9 then
        desired = 0
        ai.blockedSince = ai.blockedSince or now
        if now - ai.blockedSince > 5000 then setPedControlState(ped, "horn", (now % 1400) < 400) end
    else
        ai.blockedSince = nil
        setPedControlState(ped, "horn", false)
    end

    -- Marcha atras corta si esta atascado contra algo
    if ai.reverseUntil and now < ai.reverseUntil then
        return controls(false, true, -diff / 35)
    end

    local steer = diff / 30
    if desired == 0 then
        controls(false, speed > 0.5, steer)
    elseif speed < desired - 3 then
        controls(true, false, steer)
    elseif speed > desired + 6 then
        controls(false, true, steer)
    else
        controls(false, false, steer)
    end

    -- Atasco: acelera y no se mueve (sin obstaculo delante que lo explique)
    if desired > 0 and speed < 2.5 then
        ai.stuckSince = ai.stuckSince or now
        if now - ai.stuckSince > 3500 then
            ai.stuckCount = (ai.stuckCount or 0) + 1
            ai.stuckSince = nil
            if ai.stuckCount >= 3 then
                ai.stuckCount = 0
                warpAhead(3)
            else
                ai.reverseUntil = now + 1400
            end
        end
    else
        ai.stuckSince = nil
    end

    -- Sin progreso mucho tiempo (o tramo demasiado largo): se recoloca sobre la ruta
    if remaining < ai.bestRemaining - 5 then ai.bestRemaining, ai.lastProgress = remaining, now end
    if now - ai.lastProgress > 25000 or now - ai.legStart > RIDES.AI_APPROACH_TIMEOUT * 1000 then
        ai.lastProgress, ai.legStart = now, now
        warpAhead(ai.mode == "pickup" and math.max(3, #wp - ai.idx - 4) or 6)
    end
end

function stopAIDriver()
    if not ai then return end
    if isTimer(ai.timer) then killTimer(ai.timer) end
    if isElement(ai.ped) then
        for _, c in ipairs({ "accelerate", "brake_reverse", "handbrake", "horn" }) do setPedControlState(ai.ped, c, false) end
    end
    ai = nil
end

-- Destino aleatorio lejos (para irse)
local function leaveTarget(x, y)
    local n = roadNodeAround(x, y, 300, 600)
    if n then return nodePosition(n) end
    local a = math.random() * math.pi * 2
    return x + math.cos(a) * 400, y + math.sin(a) * 400
end

-- Empieza a conducir. Devuelve la ruta (lista de nodos) para el mapa, o nil.
function startAIDriver(vehicle, ped, mode, tx, ty)
    local timer = ai and ai.timer
    if ai and ai.vehicle ~= vehicle then stopAIDriver() timer = nil end
    ai = ai or {}
    ai.vehicle, ai.ped, ai.mode = vehicle, ped, mode
    ai.reached, ai.stuckCount, ai.reverseUntil, ai.blockedSince = false, 0, nil, nil
    if not isTimer(timer) then ai.timer = setTimer(tick, 50, 0) end

    local x, y = getElementPosition(vehicle)
    if mode == "pickup" then
        tx, ty = getElementPosition(localPlayer)
    elseif mode == "leave" then
        tx, ty = leaveTarget(x, y)
    end
    if not (tx and ty) then return nil end
    return plan(tx, ty)
end

function getAIDriverProgress()
    if not ai or not isElement(ai.vehicle) then return nil end
    local x, y = getElementPosition(ai.vehicle)
    return x, y, remainingDistance(), ai.mode
end

-- Punto donde aparece el auto: en la calle, a 110-170 m, fuera de la vista si se puede
function pickAISpawnPoint()
    local px, py, pz = getElementPosition(localPlayer)
    if loadRoadGraph() then
        for _ = 1, 8 do
            local a, b = roadNodeAround(px, py, RIDES.AI_SPAWN_MIN, RIDES.AI_SPAWN_MAX)
            if a then
                local x, y, z, rot = laneStartPoint(a, b)
                local onScreen = getScreenFromWorldPosition(x, y, z + 1, 0, false)
                if not onScreen then return x, y, z, rot end
            end
        end
        local a, b = roadNodeAround(px, py, RIDES.AI_SPAWN_MIN, RIDES.AI_SPAWN_MAX)
        if a then return laneStartPoint(a, b) end
    end
    -- Sin red vial: detras de la camara
    local cx, cy = getCameraMatrix()
    local dx, dy = px - cx, py - cy
    local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    local x, y = px - dx / len * 120, py - dy / len * 120
    local gz = getGroundPosition(x, y, pz + 50)
    return x, y, (gz and gz ~= 0) and gz or pz, heading(dx, dy)
end
