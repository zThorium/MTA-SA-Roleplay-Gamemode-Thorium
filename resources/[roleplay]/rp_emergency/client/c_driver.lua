--[[
    rp_emergency / c_driver.lua
    Conductor IA de la ambulancia. El servidor nos hace "syncer" (persistente) y aqui
    se conduce al NPC con sus controles, como el trafico de rp_citizens:

      - Ruta A* por la red vial (c_graph.lua): carril derecho, curvas en los cruces,
        sin giros en U. Se detiene pegada a la acera junto a quien llamo.
      - Pure pursuit + asistencia de direccion; frena en curvas y cruza los cruces
        con precaucion (con sirena no espera semaforos).
      - Bloqueos: bocina, desvio por el carril contrario o el arcen, marcha atras.
      - Si se sale de la ruta o se atasca, recalcula desde el carril donde esta.
        Nunca se teletransporta a la vista: solo como ultimo recurso, fuera de camara
        y lejos de los jugadores.

    Modos: target (va hasta quien llamo), hospital (lleva al paciente), leave (se aleja).
    Al llegar y quedar parado avisa al servidor con "rp:emergency:arrived".
]]

local ai = nil   -- estado del conductor

local CURB = { target = 1.3, hospital = 1.0, leave = 0 }

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

local function pedals(accel, brake, handbrake)
    local ped = ai.ped
    setPedControlState(ped, "accelerate", accel)
    setPedControlState(ped, "brake_reverse", brake)
    setPedControlState(ped, "handbrake", handbrake or false)
end

local function steerTo(value)
    value = math.max(-1, math.min(1, value or 0))
    setPedAnalogControlState(ai.ped, "vehicle_left", value > 0 and value or 0)
    setPedAnalogControlState(ai.ped, "vehicle_right", value < 0 and -value or 0)
end

-- Bocina: sonido propio. NUNCA el control "horn" del NPC: en un vehiculo de emergencia
-- ese control enciende y apaga la sirena (por eso llegaban sin sirena).
local function horn(on)
    if not on then return end
    local now = getTickCount()
    if now - (ai.hornAt or 0) < 1300 then return end
    ai.hornAt = now
    local x, y, z = getElementPosition(ai.vehicle)
    local snd = playSound3D(":rp_citizens/sounds/horn.wav", x, y, z)
    if snd then
        setSoundMaxDistance(snd, 70)
        attachElements(snd, ai.vehicle)
    end
end

-- Rayo desde el frente (angulo en grados, + = izquierda). wall = solo edificios/muros.
local function ray(vehicle, m, angle, reach, wall)
    local fx, fy = m[2][1], m[2][2]
    if angle ~= 0 then
        local r = math.rad(angle)
        local c, s = math.cos(r), math.sin(r)
        fx, fy = fx * c - fy * s, fx * s + fy * c
    end
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local sx, sy, sz = x + m[2][1] * 3.2, y + m[2][2] * 3.2, z + 0.3
    local hit, hx, hy, _, el = processLineOfSight(sx, sy, sz, sx + fx * reach, sy + fy * reach, sz,
        wall, not wall, not wall, not wall, false, true, false, false, vehicle)
    if hit and (wall or el ~= ai.ped) then return true, el, getDistanceBetweenPoints2D(sx, sy, hx, hy) end
    return false
end

-- Nadie (jugador) lo esta viendo de cerca: unico caso en que se permite recolocar
local function hiddenFromPlayers(vehicle)
    if isElementOnScreen(vehicle) then return false end
    local x, y, z = getElementPosition(vehicle)
    local players = getElementsByType("player", root, true)
    players[#players + 1] = localPlayer
    for _, p in ipairs(players) do
        local px, py, pz = getElementPosition(p)
        if getDistanceBetweenPoints3D(x, y, z, px, py, pz) < 70 then return false end
    end
    return true
end

----------------------------------------------------------------
-- Planificacion
----------------------------------------------------------------
local function straightLine(x, y, z, tx, ty)
    local wp = {}
    local d = getDistanceBetweenPoints2D(x, y, tx, ty)
    local steps = math.max(1, math.floor(d / 6))
    for i = 1, steps do
        local t = i / steps
        wp[#wp + 1] = { x + (tx - x) * t, y + (ty - y) * t, z, 0 }
    end
    return wp
end

-- Ruta desde el carril donde esta la ambulancia hasta el carril mas cercano a (tx, ty)
local function routeTo(tx, ty, curb)
    local vehicle = ai.vehicle
    local x, y, z = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    if not loadRoadGraph() then return nil end
    local from, start = laneAhead(x, y, m[2][1], m[2][2], 50)
    if not from then from, start = laneAhead(x, y, m[2][1], m[2][2], 140) end
    local a, b, t = laneNearest(tx, ty, 120)
    if not from or not a then return nil end

    -- Ya va por el mismo carril y el destino esta delante
    if a == from and b == start then
        local _, tv = laneProject(from, start, x, y)
        if t > tv + 12 then return buildWaypoints({ from, start }, x, y, t, curb) end
    end

    local route = findRoute(from, start, a)
    if route and route[#route - 1] ~= b then
        route[#route + 1] = b
        return buildWaypoints(route, x, y, t, curb)
    end
    -- Llegaria a "a" desde "b": se para en el carril contrario (b -> a), si existe
    if laneDrivable(b, a) then
        route = findRoute(from, start, b)
        if route and route[#route - 1] ~= a then
            route[#route + 1] = a
            return buildWaypoints(route, x, y, laneLength(b, a) - t, curb)
        end
    end
    return nil
end

local function targetZ(nearZ)
    if ai.tz then return ai.tz end
    local g = getGroundPosition(ai.tx, ai.ty, nearZ + 30)
    return (g and g ~= 0) and g or nearZ
end

-- Ruta propia (fuera de la calle) desde donde esta la ambulancia hasta el paciente
local function planOffroad()
    local x, y, z = getElementPosition(ai.vehicle)
    local wp = offroadPath(x, y, z - 0.9, ai.tx, ai.ty, targetZ(z), EMERGENCY.OFFROAD_STOP)
    if not wp then return false end
    if #wp == 0 then wp = { { x, y, z, 0, nil, true } } end
    ai.wp, ai.i, ai.offroad = wp, 1, true
    ai.lastProgress, ai.bestRemaining, ai.nextPlan = getTickCount(), math.huge, nil
    return true
end

local function plan()
    local vehicle = ai.vehicle
    local x, y, z = getElementPosition(vehicle)
    -- Ya fuera de la calle (o el paciente cerca y sin calle): sigue con su propia ruta
    if ai.offroad and ai.mode ~= "leave" and planOffroad() then return true end
    ai.offroad = false
    local wp = routeTo(ai.tx, ai.ty, CURB[ai.mode] or 0)
    if wp and #wp > 0 and ai.mode ~= "leave" then
        -- El paciente no esta junto a la calle: desde el punto de parada arma su propia ruta
        local last = wp[#wp]
        if getDistanceBetweenPoints2D(last[1], last[2], ai.tx, ai.ty) > EMERGENCY.OFFROAD_STOP + 3 then
            local off = offroadPath(last[1], last[2], last[3], ai.tx, ai.ty, targetZ(last[3]), EMERGENCY.OFFROAD_STOP)
            if off then for _, p in ipairs(off) do wp[#wp + 1] = p end end
        end
    end
    if not wp or #wp == 0 then
        -- Sin ruta por la red vial: ruta propia si esta a menos de 160 m
        if ai.mode ~= "leave" and getDistanceBetweenPoints2D(x, y, ai.tx, ai.ty) < 160 and planOffroad() then
            return true
        elseif getDistanceBetweenPoints2D(x, y, ai.tx, ai.ty) < 45 then
            wp = straightLine(x, y, z, ai.tx, ai.ty)
        else
            outputDebugString("[rp_emergency] la ambulancia no encontro ruta por la red vial; reintentando", 2)
            ai.wp, ai.i = {}, 1
            ai.nextPlan = getTickCount() + 2000
            return false
        end
    end
    ai.wp, ai.i = wp, 1
    ai.lastProgress, ai.bestRemaining = getTickCount(), math.huge
    ai.nextPlan = nil
    return true
end

local function remainingDistance(x, y)
    local wp, i = ai.wp, ai.i
    local total = getDistanceBetweenPoints2D(x, y, wp[i][1], wp[i][2])
    for k = i, #wp - 1 do total = total + getDistanceBetweenPoints2D(wp[k][1], wp[k][2], wp[k + 1][1], wp[k + 1][2]) end
    return total
end

-- Ultimo recurso (atasco largo, sin nadie mirando): recoloca unos metros mas adelante en su ruta
local function hopAhead(meters)
    local wp, i = ai.wp, ai.i
    local acc, k = 0, i
    while k < #wp - 2 and acc < meters do
        acc = acc + getDistanceBetweenPoints2D(wp[k][1], wp[k][2], wp[k + 1][1], wp[k + 1][2])
        k = k + 1
    end
    local p, q = wp[k], wp[k + 1] or wp[k]
    setElementPosition(ai.vehicle, p[1], p[2], p[3] + 1.2)
    setElementRotation(ai.vehicle, 0, 0, heading(q[1] - p[1], q[2] - p[2]))
    setElementVelocity(ai.vehicle, 0, 0, 0)
    ai.i = k
    ai.stuckCount = 0
end

-- Desvio provisional por la izquierda (carril contrario) o la derecha (arcen)
local function tryDetour(m)
    local vehicle = ai.vehicle
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local fx, fy = m[2][1], m[2][2]
    local lx, ly = -fy, fx
    local wp = ai.wp
    local rejoin = nil
    for k = ai.i, #wp do
        if getDistanceBetweenPoints2D(x, y, wp[k][1], wp[k][2]) > 26 then rejoin = k break end
    end
    if not rejoin then return false end
    local rx, ry, rz = wp[rejoin][1], wp[rejoin][2], wp[rejoin][3]
    local function clear(x1, y1, x2, y2, z2)
        return isLineOfSightClear(x1, y1, z + 0.6, x2, y2, (z2 or z) + 0.6, true, true, true, true, false, true, false, vehicle)
    end
    for _, side in ipairs({ 5, 7, -4 }) do
        local p1x, p1y = x + fx * 5 + lx * side * 0.6, y + fy * 5 + ly * side * 0.6
        local p2x, p2y = x + fx * 12 + lx * side, y + fy * 12 + ly * side
        local p3x, p3y = x + fx * 19 + lx * side * 0.7, y + fy * 19 + ly * side * 0.7
        local ground = getGroundPosition(p2x, p2y, z + 3)
        local flat = ground and ground ~= 0 and math.abs(ground - (z - 0.6)) < 1.6
        if flat and clear(x, y, p1x, p1y) and clear(p1x, p1y, p2x, p2y) and clear(p2x, p2y, p3x, p3y)
            and clear(p3x, p3y, rx, ry, rz) then
            local new = { { p1x, p1y, z, 25 }, { p2x, p2y, z, 25 }, { p3x, p3y, z, 25 } }
            for k = rejoin, #wp do new[#new + 1] = wp[k] end
            ai.wp, ai.i = new, 1
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- Conduccion
----------------------------------------------------------------
local function tick()
    if not ai then return end
    local vehicle, ped = ai.vehicle, ai.ped
    if not isElement(vehicle) or not isElement(ped) then return stopAIDriver() end
    if not isElementSyncer(vehicle) or not isElementStreamedIn(vehicle) then
        local now = getTickCount()
        if now - (ai.warnAt or 0) > 10000 then
            ai.warnAt = now
            outputDebugString(("[rp_emergency] ambulancia sin control (syncer=%s, cargada=%s)"):format(
                tostring(isElementSyncer(vehicle)), tostring(isElementStreamedIn(vehicle))), 2)
        end
        return
    end

    local now = getTickCount()
    local speed = speedKmh(vehicle)
    local x, y = getElementPosition(vehicle)
    local _, _, rz = getElementRotation(vehicle)
    local m = getElementMatrix(vehicle)

    if ai.reached then
        steerTo(0)
        return pedals(false, speed > 1, true)
    end

    if #ai.wp == 0 then
        steerTo(0)
        pedals(false, speed > 1)
        if now >= (ai.nextPlan or 0) then plan() end
        return
    end

    -- Volcada: se endereza (solo si no la ve nadie de cerca, o tras un rato)
    if m[3][3] < 0.3 then
        ai.flipSince = ai.flipSince or now
        if hiddenFromPlayers(vehicle) or now - ai.flipSince > 6000 then
            setElementRotation(vehicle, 0, 0, rz)
            local vx, vy, vz = getElementPosition(vehicle)
            setElementPosition(vehicle, vx, vy, vz + 1)
            ai.flipSince = nil
        end
        return pedals(false, false)
    end
    ai.flipSince = nil

    -- Maniobra de marcha atras (atasco)
    if ai.reverseUntil then
        if now < ai.reverseUntil then
            horn(false)
            steerTo(-(ai.reverseSteer or 0))
            local vx, vy = getElementVelocity(vehicle)
            local backing = (vx * m[2][1] + vy * m[2][2]) * 180
            return pedals(false, backing > -12)
        end
        ai.reverseUntil = nil
        if ai.stuckCount >= 2 then plan() end   -- vuelve a calcular la ruta desde el carril donde quedo
        if #ai.wp == 0 then return end
    end

    -- Pure pursuit: descarta puntos alcanzados o que quedaron detras
    local wp = ai.wp
    local i = ai.i
    local inCurve = wp[i][4] > 20
    local look = (inCurve and 3.5 or 6.5) + speed * (inCurve and 0.06 or 0.1)
    local fwx, fwy = m[2][1], m[2][2]
    while i < #wp and (getDistanceBetweenPoints2D(x, y, wp[i][1], wp[i][2]) < look
        or ((wp[i][1] - x) * fwx + (wp[i][2] - y) * fwy < 0 and (wp[i + 1][1] - x) * fwx + (wp[i + 1][2] - y) * fwy > -2)) do
        i = i + 1
    end
    ai.i = i

    -- Se salio de la ruta: recalcula (como mucho cada 3 s). Fuera de la calle, con su propia ruta.
    local offroadNow = wp[i][6] == true
    if offroadNow then ai.offroad = true end
    if getDistanceBetweenPoints2D(x, y, wp[i][1], wp[i][2]) > (offroadNow and 12 or 22) and now - (ai.lastPlan or 0) > 3000 then
        ai.lastPlan = now
        plan()
        return
    end

    local remaining = remainingDistance(x, y)
    local last = wp[#wp]

    -- Llegada
    if i >= #wp and getDistanceBetweenPoints2D(x, y, last[1], last[2]) < 5 then
        horn(false)
        steerTo(0)
        if speed < 2 then
            ai.reached = true
            if ai.mode ~= "leave" then triggerServerEvent("rp:emergency:arrived", resourceRoot, ai.callId, ai.mode) end
        end
        return pedals(false, true, speed < 10)
    end

    local t = wp[i]
    local diff = angleDiff(heading(t[1] - x, t[2] - y), rz)

    -- Lo que viene en los proximos metros: mayor giro y cruces
    local upcoming, dist, lx, ly, junctionDist = 0, 0, x, y, nil
    for k = i, math.min(#wp, i + 14) do
        dist = dist + getDistanceBetweenPoints2D(lx, ly, wp[k][1], wp[k][2])
        lx, ly = wp[k][1], wp[k][2]
        if dist > 40 then break end
        if dist <= 30 and wp[k][4] > upcoming then upcoming = wp[k][4] end
        if wp[k][5] and not junctionDist then junctionDist = dist end
    end

    local frontHit, obstacle, gap = ray(vehicle, m, 0, 9 + speed * 0.3, false)
    local wallFront = ray(vehicle, m, 0, 3 + speed * 0.08, true)
    local leftHit = ray(vehicle, m, 25, 3.5 + speed * 0.06, true)
    local rightHit = ray(vehicle, m, -25, 3.5 + speed * 0.06, true)

    local steer = diff / (inCurve and 18 or 25)
    if leftHit and not rightHit then steer = steer - 0.2 end
    if rightHit and not leftHit then steer = steer + 0.2 end
    steerTo(steer)

    -- Asistencia de direccion (igual que el trafico): menos derrape lateral y giro suave
    if speed > 4 then
        local vx, vy, vz = getElementVelocity(vehicle)
        local fx, fy, rx, ry = m[2][1], m[2][2], m[1][1], m[1][2]
        local along, side = vx * fx + vy * fy, vx * rx + vy * ry
        if math.abs(side) > 0.02 then
            setElementVelocity(vehicle, fx * along + rx * side * 0.8, fy * along + ry * side * 0.8, vz)
        end
        local ax, ay, az = getElementAngularVelocity(vehicle)
        local desired = math.max(-0.015, math.min(0.015, math.rad(diff) * 0.025)) * math.min(1, speed / 20)
        setElementAngularVelocity(vehicle, ax, ay, az + (desired - az) * 0.35)
    end

    -- Velocidad objetivo
    local target = EMERGENCY.CRUISE_SPEED
    if upcoming > 70 then target = 26 elseif upcoming > 40 then target = 36 elseif upcoming > 20 then target = 48 end
    if junctionDist and junctionDist < 25 then target = math.min(target, EMERGENCY.JUNCTION_SPEED) end
    if math.abs(diff) > 50 then target = math.min(target, 15) end
    if wallFront then target = math.min(target, 12) end
    if offroadNow then target = math.min(target, EMERGENCY.OFFROAD_SPEED) end
    target = math.min(target, 6 + remaining * 0.8)        -- se acerca despacio al punto de parada
    if ai.mode == "leave" then target = math.min(target, 45) end

    -- Ya junto al destino y alguien (p. ej. quien llamo) esta en el punto de parada: para aqui
    if obstacle and remaining < 18 and ai.mode ~= "leave" then
        horn(false)
        if speed < 2 then
            ai.reached = true
            triggerServerEvent("rp:emergency:arrived", resourceRoot, ai.callId, ai.mode)
        end
        return pedals(false, true, speed < 10)
    end

    -- Algo delante: guarda distancia, toca la bocina y busca un hueco para pasar
    if obstacle then
        local otherSpeed = isElement(obstacle) and getElementType(obstacle) ~= "ped" and speedKmh(obstacle) or 0
        if gap and gap < 4 + speed * 0.12 then target = 0 else target = math.min(target, otherSpeed + 3) end
        -- Va con sirena: adelanta a los lentos por el carril contrario o el arcen en vez de seguirlos
        if isElement(obstacle) and getElementType(obstacle) == "vehicle" and otherSpeed < target - 12
            and ai.mode ~= "leave" and now - (ai.overtakeAt or 0) > 2000 then
            ai.overtakeAt = now
            tryDetour(m)
        end
        if target <= 1 and speed < 3 then
            ai.blockedSince = ai.blockedSince or now
            local waited = now - ai.blockedSince
            horn(waited > 700)
            if waited > 2500 and tryDetour(m) then
                ai.blockedSince = nil
            elseif waited > 5000 then
                ai.reverseUntil, ai.reverseSteer, ai.blockedSince = now + 1000, 0, nil
            end
        end
    else
        ai.blockedSince = nil
        horn(false)
    end

    pedals(speed < target - 1, speed > target + 6 or (target == 0 and speed > 1))

    -- Atasco sin obstaculo visible (pared, bordillo): marcha atras y nueva ruta
    if speed < 2 and target > 5 and not obstacle then
        ai.stuckSince = ai.stuckSince or now
        if now - ai.stuckSince > 3000 then
            ai.stuckCount = ai.stuckCount + 1
            ai.reverseUntil, ai.reverseSteer, ai.stuckSince = now + 1300, steer, nil
            if ai.stuckCount >= 6 and hiddenFromPlayers(vehicle) then hopAhead(25) end
        end
    else
        ai.stuckSince = nil
        if speed > 15 then ai.stuckCount = 0 end
    end

    -- Sin avanzar mucho tiempo: nueva ruta; si sigue igual y nadie mira, recoloca
    if remaining < ai.bestRemaining - 5 then ai.bestRemaining, ai.lastProgress = remaining, now end
    if now - ai.lastProgress > 30000 then
        ai.lastProgress = now
        if hiddenFromPlayers(vehicle) then hopAhead(40) else plan() end
    end
end

function stopAIDriver()
    if not ai then return end
    if isTimer(ai.timer) then killTimer(ai.timer) end
    if isElement(ai.ped) then
        for _, c in ipairs({ "accelerate", "brake_reverse", "handbrake" }) do setPedControlState(ai.ped, c, false) end
        setPedAnalogControlState(ai.ped, "vehicle_left", 0)
        setPedAnalogControlState(ai.ped, "vehicle_right", 0)
    end
    ai = nil
end

function isAIDriving(callId) return ai ~= nil and ai.callId == callId end

local function leaveTarget(x, y)
    local a = roadNodeAround(x, y, 300, 600)
    if a then return nodePosition(a) end
    local ang = math.random() * math.pi * 2
    return x + math.cos(ang) * 400, y + math.sin(ang) * 400
end

function startAIDriver(callId, vehicle, ped, mode, tx, ty, tz)
    local timer = ai and ai.timer
    if ai and ai.vehicle ~= vehicle then stopAIDriver() timer = nil end
    ai = ai or {}
    ai.callId, ai.vehicle, ai.ped, ai.mode = callId, vehicle, ped, mode
    ai.reached, ai.stuckCount, ai.reverseUntil, ai.blockedSince, ai.stuckSince = false, 0, nil, nil, nil
    ai.wp, ai.i = {}, 1
    if not isTimer(timer) then ai.timer = setTimer(tick, 50, 0) else ai.timer = timer end

    local x, y = getElementPosition(vehicle)
    if mode == "leave" then tx, ty = leaveTarget(x, y) end
    if not (tx and ty) then return end
    ai.tx, ai.ty, ai.tz, ai.offroad = tx, ty, tonumber(tz), false
    plan()
end

-- Punto donde aparece la ambulancia: en un carril, fuera de la vista y con ruta hasta el jugador
function pickSpawnPoint()
    local px, py, pz = getElementPosition(localPlayer)
    local lo, hi = EMERGENCY.SPAWN_MIN, EMERGENCY.SPAWN_MAX
    if loadRoadGraph() then
        local ta = laneNearest(px, py, 120)
        local fallback = nil
        for _ = 1, 12 do
            local a, b = roadNodeAround(px, py, lo, hi)
            if a then
                local x, y, z, rot = laneStartPoint(a, b)
                local routable = not ta or findRoute(a, b, ta, 4000) ~= nil
                local hidden = not getScreenFromWorldPosition(x, y, z + 1, 0, false)
                if routable and hidden then return x, y, z, rot end
                if routable and not fallback then fallback = { x, y, z, rot } end
            end
        end
        if fallback then return unpack(fallback) end
    end
    local cx, cy = getCameraMatrix()
    local dx, dy = px - cx, py - cy
    local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    local x, y = px - dx / len * lo, py - dy / len * lo
    local gz = getGroundPosition(x, y, pz + 50)
    return x, y, (gz and gz ~= 0) and gz or pz, heading(dx, dy)
end
