--[[
    rp_wanted / c_police.lua
    IA de las unidades de policia que persiguen al jugador local. El servidor
    crea los elementos y nos hace syncer; aqui se manejan con sus controles,
    como el conductor IA de rp_rides y el trafico de rp_citizens.

    La policia no ve la posicion real del jugador: usa lo que sabe
    (client/c_knowledge.lua): su posicion si lo ve, la ultima proyectada si lo
    acaba de perder y una busqueda por la zona si lo perdio del todo.

    Patrulla:   ROUTE  (A* por la red vial hasta donde saben que esta, se recalcula)
                SEARCH (lo perdieron: barren calles alrededor de la ultima posicion;
                        si iba a pie, se bajan a buscarlo)
                CHASE  (lo ve a menos de 60 m: va directo, predice hacia donde va;
                        desde 3 estrellas lo embiste)
                STOP   (el jugador va a pie o se detuvo cerca: frena y se bajan)
                LEAVE  (termino la busqueda: apaga la sirena y se va)
    A pie:      corre hacia el jugador; si lo alcanza lo arresta; desde 2
                estrellas dispara cuando lo ve; si el jugador se va en auto,
                vuelve a su patrulla.
    Helicoptero: vuela en circulo sobre el jugador; de noche lo sigue con un foco.
    Control de carretera: 2 patrullas atravesadas y policias que esperan.

    Como en GTA SA (CTaskComplexCopInCar / CTaskComplexArrestPed):
      - Si vas en un vehiculo y te detienes, el policia abre tu puerta y te saca: arresto.
      - A pie te persiguen; a 1 estrella te golpean con la porra hasta tirarte al
        suelo; desde 2 disparan. Si estas en el suelo o quieto a su lado: arresto.
      - Si vuelves a moverte en un vehiculo, el policia que esta a menos de 25 m
        de su patrulla corre a ella y sigue la persecucion; si no, sigue a pie.
      - Las patrullas del trafico (rp_citizens) se suman a la persecucion
        (adoptLocalCop): son elementos solo de este cliente y se manejan igual.
]]

local units = {}        -- [id] = unidad
local level = 0
local TICK = 50

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end
local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end
local burstWheel   -- definida mas abajo (disparos a los neumaticos)
local function speedKmh(el)
    local vx, vy, vz = getElementVelocity(el)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

local function controls(ped, accel, brake, steer, handbrake)
    if not isElement(ped) then return end
    setPedControlState(ped, "accelerate", accel)
    setPedControlState(ped, "brake_reverse", brake)
    setPedControlState(ped, "handbrake", handbrake or false)
    steer = math.max(-1, math.min(1, steer or 0))
    setPedAnalogControlState(ped, "vehicle_left", steer > 0 and steer or 0)
    setPedAnalogControlState(ped, "vehicle_right", steer < 0 and -steer or 0)
end

local function releaseFoot(ped)
    for _, c in ipairs({ "forwards", "sprint", "walk", "aim_weapon", "fire" }) do setPedControlState(ped, c, false) end
end

local function levelCfg() return WANTED_LEVELS[level] end

-- Las unidades del servidor se manejan si somos su syncer; las del trafico (locales) siempre
local function controlled(u, el)
    return u.isLocal or isElementSyncer(el)
end

local function playerIsDown()
    local t = getPedSimplestTask(localPlayer)
    return t == "TASK_SIMPLE_FALL" or t == "TASK_SIMPLE_GET_UP" or t == "TASK_SIMPLE_LAND"
end

----------------------------------------------------------------
-- Puntos de aparicion (los pide el servidor)
----------------------------------------------------------------
local function onScreen(x, y, z)
    return getScreenFromWorldPosition(x, y, z + 1, 0, false) ~= false
end

local pathPointAhead
local function carSpawnPoint()
    -- Si te perdieron de vista, los refuerzos llegan a donde te vieron por ultima vez
    local px, py, pz, mode = knowledgeTarget(getTickCount())
    local live = mode == "live"
    -- Va rapido en un vehiculo: la patrulla sale de frente en su ruta probable
    -- (GTA la genera por delante para cortarle el paso)
    if live and pathPointAhead and getPedOccupiedVehicle(localPlayer) and math.random() < 0.6 then
        local x, y, z, rot = pathPointAhead(WANTED_DISPATCH.SPAWN_MIN + 20, WANTED_DISPATCH.SPAWN_MAX + 40, true)
        if x then return x, y, z, (rot + 180) % 360 end
    end
    if loadRoadGraph() then
        -- Si va en vehiculo, mejor por delante (le sale al paso, como en GTA)
        local v = live and getPedOccupiedVehicle(localPlayer)
        local fx, fy = 0, 0
        if v then
            local vx, vy = getElementVelocity(v)
            local len = math.sqrt(vx * vx + vy * vy)
            if len > 0.05 then fx, fy = vx / len, vy / len end
        end
        local best, bestScore, fallback = nil, -math.huge, nil
        for _ = 1, 16 do
            local a, b = roadNodeAround(px, py, WANTED_DISPATCH.SPAWN_MIN, WANTED_DISPATCH.SPAWN_MAX)
            if a then
                local x, y, z, rot = laneStartPoint(a, b)
                fallback = fallback or { x, y, z, rot }
                if not onScreen(x, y, z) then
                    local d = math.max(1, getDistanceBetweenPoints2D(px, py, x, y))
                    local ahead = ((x - px) * fx + (y - py) * fy) / d
                    local toward = math.abs(angleDiff(heading(px - x, py - y), rot)) < 100 and 0.5 or 0
                    local score = ahead + toward + math.random() * 0.2
                    if score > bestScore then best, bestScore = { x, y, z, rot }, score end
                end
            end
        end
        if best or fallback then return unpack(best or fallback) end
    end
    -- Sin red vial: detras de la camara
    local cx, cy = getCameraMatrix()
    local dx, dy = px - cx, py - cy
    local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    local x, y = px - dx / len * 110, py - dy / len * 110
    local gz = getGroundPosition(x, y, pz + 50)
    return x, y, (gz and gz ~= 0) and gz or pz, heading(dx, dy)
end

----------------------------------------------------------------
-- Ruta probable del jugador (se recalcula cada medio segundo)
----------------------------------------------------------------
local pred = { at = 0 }

local function playerPath(now)
    if now - pred.at < 500 then return pred.path end
    pred.at = now
    pred.path = nil
    local v = getPedOccupiedVehicle(localPlayer)
    if not v then return nil end
    local vx, vy = getElementVelocity(v)
    local len = math.sqrt(vx * vx + vy * vy)
    local fx, fy
    if len * 180 > 15 then
        fx, fy = vx / len, vy / len
    else
        local m = getElementMatrix(v)
        fx, fy = m[2][1], m[2][2]
    end
    local x, y = getElementPosition(v)
    pred.path = predictRoadPath(x, y, fx, fy, 400)
    pred.speed = len * 50    -- m/s
    return pred.path
end

-- Punto de la ruta probable entre minD y maxD metros, con el rumbo de la calle
function pathPointAhead(minD, maxD, wantHidden)
    local path = playerPath(getTickCount())
    if not path or #path < 2 then return nil end
    local fallback
    for i = 1, #path - 1 do
        local p, q = path[i], path[i + 1]
        if p[4] >= minD and p[4] <= maxD then
            local rot = heading(q[1] - p[1], q[2] - p[2])
            if not wantHidden or not onScreen(p[1], p[2], p[3]) then return p[1], p[2], p[3], rot end
            fallback = fallback or { p[1], p[2], p[3], rot }
        end
    end
    if fallback then return unpack(fallback) end
end

-- Control de carretera: un nodo de la calle por delante del jugador, en su direccion
local function roadblockPoint()
    local x, y, z, rot = pathPointAhead(WANTED_DISPATCH.ROADBLOCK_AHEAD_MIN, WANTED_DISPATCH.ROADBLOCK_AHEAD_MAX, true)
    if x then return x, y, z, rot end
    return nil
end

-- Respaldo del control de carretera (sin ruta probable): en linea recta por delante
local function roadblockPointStraight()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or not loadRoadGraph() then return end
    local m = getElementMatrix(v)
    local fx, fy = m[2][1], m[2][2]
    local px, py = getElementPosition(v)
    local _, L = getRoadGraphData()
    for d = WANTED_DISPATCH.ROADBLOCK_AHEAD_MIN, WANTED_DISPATCH.ROADBLOCK_AHEAD_MAX, 20 do
        local n = nearestRoadNode(px + fx * d, py + fy * d, 1)
        if n then
            local nx, ny, nz = nodePosition(n)
            local along = (nx - px) * fx + (ny - py) * fy
            if along > WANTED_DISPATCH.ROADBLOCK_AHEAD_MIN * 0.8 then
                -- direccion de la calle mas parecida a la del jugador
                local best, bestDot = nil, 0.5
                for _, k in ipairs(L[n] or {}) do
                    local kx, ky = nodePosition(k)
                    local dx, dy = kx - nx, ky - ny
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len > 1 then
                        local sign = (dx * fx + dy * fy) >= 0 and 1 or -1
                        local dot = math.abs((dx * fx + dy * fy) / len)
                        if dot > bestDot then best, bestDot = heading(dx * sign, dy * sign), dot end
                    end
                end
                if best then return nx, ny, nz, best end
            end
        end
    end
end

addEvent("rp:wanted:spawnRequest", true)
addEventHandler("rp:wanted:spawnRequest", resourceRoot, function(kind)
    local x, y, z, rot
    -- Controles y pinchos van en tu ruta: solo si saben por donde vas
    if (kind == "roadblock" or kind == "spikes") and knowledgeMode(getTickCount()) ~= "live" then return end
    if kind == "car" then
        x, y, z, rot = carSpawnPoint()
    elseif kind == "roadblock" then
        x, y, z, rot = roadblockPoint()
        if not x then x, y, z, rot = roadblockPointStraight() end
    elseif kind == "spikes" then
        x, y, z, rot = pathPointAhead(WANTED_SPIKES.AHEAD_MIN, WANTED_SPIKES.AHEAD_MAX, false)
    elseif kind == "boat" then
        -- agua navegable de la red de barcos de rp_citizens (opcional: sin el recurso no salen lanchas)
        local ok, bx, by, bz, brot = pcall(function()
            return exports.rp_citizens:citizenBoatSpot(WANTED_BOAT.SPAWN_MIN, WANTED_BOAT.SPAWN_MAX)
        end)
        if ok and bx then x, y, z, rot = bx, by, bz, brot end
    end
    if x then triggerServerEvent("rp:wanted:spawnAt", resourceRoot, kind, x, y, z, rot) end
end)

----------------------------------------------------------------
-- Rutas
----------------------------------------------------------------
local function startNodeAhead(vehicle)
    local x, y = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    local fx, fy = m[2][1], m[2][2]
    local best, bestD = nil, math.huge
    for ox = -1, 1 do
        for oy = -1, 1 do
            local n = nearestRoadNode(x + ox * 30, y + oy * 30, 1)
            if n then
                local nx, ny = nodePosition(n)
                local d = getDistanceBetweenPoints2D(x, y, nx, ny)
                local dot = d > 0.1 and ((nx - x) * fx + (ny - y) * fy) / d or 1
                if d < 70 and dot > 0.2 and d < bestD then best, bestD = n, d end
            end
        end
    end
    return best or nearestRoadNode(x, y)
end

-- A* es caro: como mucho una busqueda por tick entre todas las unidades, y si
-- falla no se repite enseguida (antes se reintentaba cada 50 ms y trababa el juego)
local planBudget = 1
local function plan(u, tx, ty, goal)
    if planBudget <= 0 then return false end
    planBudget = planBudget - 1
    u.wp, u.idx, u.planAt = nil, 1, getTickCount()
    if not loadRoadGraph() then return true end
    local s = startNodeAhead(u.vehicle)
    local g = goal or nearestRoadNode(tx, ty)
    local route = s and g and findRoadRoute(s, g, 2500)
    if route and #route >= 2 then u.wp = routeWaypoints(route) end
    return true
end

local function needPlan(u, now, every)
    local age = now - (u.planAt or 0)
    return (not u.wp and age > 1200) or age > (every or 2500)
end

-- Punto de la ruta a seguir (mirada adelantada) y giro que viene
local function routeTarget(u, x, y, speed)
    local wp = u.wp
    while u.idx < #wp and getDistanceBetweenPoints2D(x, y, wp[u.idx][1], wp[u.idx][2]) < 8 do u.idx = u.idx + 1 end
    local look = 7 + speed * 0.14
    local ti = u.idx
    while ti < #wp and getDistanceBetweenPoints2D(x, y, wp[ti][1], wp[ti][2]) < look do ti = ti + 1 end
    local t = wp[ti]
    local turn = 0
    local a1, a2 = wp[math.min(#wp, ti + 1)], wp[math.min(#wp, ti + 4)]
    if a1 and a2 and a1 ~= a2 then
        turn = math.abs(angleDiff(heading(a2[1] - a1[1], a2[2] - a1[2]), heading(t[1] - x, t[2] - y)))
    end
    return t[1], t[2], turn, ti >= #wp
end

local function obstacleAhead(vehicle, m, speed, ignore)
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local fx, fy = m[2][1], m[2][2]
    local reach = 6 + speed * 0.15
    local sx, sy = x + fx * 2.6, y + fy * 2.6
    local hit, hx, hy, _, el = processLineOfSight(sx, sy, z + 0.3, sx + fx * reach, sy + fy * reach, z + 0.3,
        false, true, false, true, false, true, false, false, vehicle)
    if hit and el ~= ignore then return getDistanceBetweenPoints2D(sx, sy, hx, hy) end
end

-- Recoloca la patrulla mas adelante en su ruta (solo si no se ve)
local function warpAhead(u)
    local wp = u.wp
    if not wp or isElementOnScreen(u.vehicle) then return false end
    local i = math.min(#wp, u.idx + 4)
    local p, q = wp[i], wp[math.min(#wp, i + 1)]
    if not p then return false end
    local rot = (q and q ~= p) and heading(q[1] - p[1], q[2] - p[2]) or select(3, getElementRotation(u.vehicle))
    setElementPosition(u.vehicle, p[1], p[2], p[3] + 1.2)
    setElementRotation(u.vehicle, 0, 0, rot)
    setElementVelocity(u.vehicle, 0, 0, 0)
    u.idx = i
    return true
end

----------------------------------------------------------------
-- Conduccion de la patrulla
----------------------------------------------------------------
local function driveCar(u, now)
    local v = u.vehicle
    local driver = getVehicleController(v)
    if not driver or not u.pedSet[driver] or isPedDead(driver) or not controlled(u, v) then return end
    if isVehicleBlown(v) then return end

    local x, y, z = getElementPosition(v)
    local m = getElementMatrix(v)
    local _, _, rz = getElementRotation(v)
    local speed = speedKmh(v)
    local px, py, pz = getElementPosition(localPlayer)
    local pveh = getPedOccupiedVehicle(localPlayer)
    local pspeed = speedKmh(pveh or localPlayer)
    local dist = getDistanceBetweenPoints2D(x, y, px, py)
    local cfg = levelCfg()

    -- Muy lejos y fuera de la vista: se retira y el servidor manda otra mas cerca
    if not u.leaving and dist > WANTED_DISPATCH.LOST_DISTANCE and not isElementOnScreen(v) and not u.lostSent then
        u.lostSent = true
        if u.isLocal then return removeLocalUnit(u) end
        return triggerServerEvent("rp:wanted:unitLost", resourceRoot, u.id)
    end

    local tx, ty, desired
    if u.leaving or not cfg then
        if not u.leaveTarget then
            local n = loadRoadGraph() and roadNodeAround(x, y, 250, 450)
            u.leaveTarget = n and { nodePosition(n) } or { x + (x - px) * 5, y + (y - py) * 5 }
            plan(u, u.leaveTarget[1], u.leaveTarget[2])
        end
        desired = 60
        if u.wp and #u.wp > 0 then
            local turn
            tx, ty, turn = routeTarget(u, x, y, speed)
            if turn > 40 then desired = 30 end
        else
            tx, ty = u.leaveTarget[1], u.leaveTarget[2]
        end
    else
        -- Lo que sabe la policia: si esta patrulla te ve, ya saben donde estas
        local los = dist < 70 and isLineOfSightClear(x, y, z + 1, px, py, pz + 0.5, true, false, false, true, false, true, false)
        u.los = los
        if los then knowledgeSeen(now) end
        local kx, ky, _, mode = knowledgeTarget(now)
        local live = mode == "live"
        local kdist = getDistanceBetweenPoints2D(x, y, kx, ky)

        -- El jugador a pie (o detenido) cerca: frena y los policias se bajan
        local stopNear = live and ((not pveh and dist < 24) or (pveh and pspeed < 8 and dist < 16))
        if stopNear then
            controls(driver, false, speed > 0.5, 0, true)
            if speed < 5 and now - (u.dismountAt or 0) > 3000 then
                u.dismountAt = now
                if u.isLocal then dismountLocal(u) else triggerServerEvent("rp:wanted:dismount", resourceRoot, v) end
            end
            return
        end

        local icpt = live and u.role == "intercept" and pveh and dist > 30 and u.icpt
        if mode == "search" then
            -- SEARCH: te perdieron. Van a tu ultima posicion y despues barren calles cada vez mas lejos
            local sp = knowledgeSearchPoint(u, now, x, y, false)
            -- llegaron a donde te vieron a pie: se bajan a buscarte (una vez por cada vez que te pierden)
            if knowledgeLastSeenOnFoot() and kdist < 25 and u.dismountSeq ~= u.spSeq then
                controls(driver, false, speed > 0.5, 0, true)
                if speed < 5 then
                    u.dismountSeq = u.spSeq
                    if u.isLocal then dismountLocal(u) else triggerServerEvent("rp:wanted:dismount", resourceRoot, v) end
                end
                return
            end
            if u.searchPlanned ~= sp or needPlan(u, now, 6000) then
                if plan(u, sp[1], sp[2]) then u.searchPlanned = sp end
            end
            desired = WANTED_SEARCH.SPEED
            if u.wp and #u.wp > 0 then
                local turn, last
                tx, ty, turn, last = routeTarget(u, x, y, speed)
                if turn > 50 then desired = 30 elseif turn > 25 then desired = 45 end
                if last then tx, ty = sp[1], sp[2] end
            else
                tx, ty = sp[1], sp[2]
            end
            local gap = obstacleAhead(v, m, speed, pveh)
            if gap and gap < 9 then desired = math.min(desired, 15) end
        elseif icpt then
            -- INTERCEPT: va a un punto de la ruta probable del jugador por donde
            -- pasara despues que la patrulla; al llegar se cruza y espera
            local d = getDistanceBetweenPoints2D(x, y, icpt[1], icpt[2])
            if d < 16 then
                if not isElementOnScreen(v) and speed < 60 and not u.blockTurned then
                    -- cruzada en la calle (fuera de la vista, como GTA)
                    u.blockTurned = true
                    setElementPosition(v, icpt[1], icpt[2], icpt[3] + 1)
                    setElementRotation(v, 0, 0, icpt[4] + 90)
                    setElementVelocity(v, 0, 0, 0)
                end
                return controls(driver, false, speed > 1, 0, true)
            end
            u.blockTurned = nil
            if u.icptPlanned ~= icpt or needPlan(u, now, 3000) then
                if plan(u, icpt[1], icpt[2], icpt[5]) then u.icptPlanned = icpt end
            end
            desired = 170
            if u.wp and #u.wp > 0 then
                local turn
                tx, ty, turn = routeTarget(u, x, y, speed)
                if turn > 55 then desired = 45 elseif turn > 30 then desired = 75 end
            else
                tx, ty = icpt[1], icpt[2]
            end
        elseif los then
            -- CHASE: directo al jugador, adelantandose a donde va
            local tvx, tvy = getElementVelocity(pveh or localPlayer)
            local lead = math.min(1.5, dist / 30)
            tx, ty = px + tvx * 50 * lead, py + tvy * 50 * lead
            if cfg.ram and pveh then
                desired = math.max(pspeed + 30, 90)
                if dist < 16 then
                    -- PIT: apunta a la esquina trasera del auto del jugador, del lado
                    -- por donde viene la patrulla, y la empuja para hacerlo girar
                    local pm = getElementMatrix(pveh)
                    local side = ((x - px) * pm[1][1] + (y - py) * pm[1][2]) >= 0 and 1 or -1
                    tx = px - pm[2][1] * 1.6 + pm[1][1] * side * 0.9 + tvx * 12
                    ty = py - pm[2][2] * 1.6 + pm[1][2] * side * 0.9 + tvy * 12
                end
            elseif cfg.ram then
                desired = 120
            elseif dist > 18 then
                desired = 160
            else
                desired = math.max(20, pspeed + 3)   -- lo sigue de cerca sin chocarlo
            end
            u.wp = nil
        else
            -- ROUTE: A* hasta donde saben que estas (o estaras), se recalcula cada 2.5 s
            if needPlan(u, now) then plan(u, kx, ky) end
            -- Lejos y sin que se vea: se adelanta por su ruta hasta quedar cerca (GTA genera las
            -- patrullas cerca del jugador; asi la persecucion no se pierde por la distancia).
            -- Solo mientras te ven: si te perdieron, no hacen trampa.
            if live and u.wp and dist > WANTED_DISPATCH.CATCHUP_DISTANCE and not isElementOnScreen(v)
                and now - (u.catchAt or 0) > 3000 then
                u.catchAt = now
                for j = u.idx, #u.wp do
                    local p = u.wp[j]
                    if getDistanceBetweenPoints2D(p[1], p[2], px, py) <= WANTED_DISPATCH.CATCHUP_TO
                        and not onScreen(p[1], p[2], p[3]) then
                        local q = u.wp[math.min(#u.wp, j + 1)]
                        local rot = (q ~= p) and heading(q[1] - p[1], q[2] - p[2]) or rz
                        setElementPosition(v, p[1], p[2], p[3] + 1.2)
                        setElementRotation(v, 0, 0, rot)
                        local sp = math.min(90, 40 + pspeed) / 180
                        setElementVelocity(v, -math.sin(math.rad(rot)) * sp, math.cos(math.rad(rot)) * sp, 0)
                        u.idx = j
                        break
                    end
                end
            end
            desired = 120
            if u.wp and #u.wp > 0 then
                local turn, last
                tx, ty, turn, last = routeTarget(u, x, y, speed)
                if turn > 50 then desired = 35 elseif turn > 25 then desired = 60 end
                if last then tx, ty = kx, ky end
            else
                tx, ty = kx, ky
            end
            local gap = obstacleAhead(v, m, speed, pveh)
            if gap and gap < 9 then desired = math.min(desired, 15) end
        end
    end

    local diff = angleDiff(heading(tx - x, ty - y), rz)

    -- Esquiva el trafico: si hay algo delante (que no sea el jugador), prueba
    -- por la izquierda y por la derecha y gira hacia el lado libre
    if not u.leaving and speed > 25 and now - (u.avoidAt or 0) > 150 then
        u.avoidAt = now
        u.avoid = nil
        local gap = obstacleAhead(v, m, speed, pveh)
        if gap and gap < 6 + speed * 0.12 then
            local reach = 8 + speed * 0.12
            local best, bestFree = nil, -1
            for _, side in ipairs({ -1, 1 }) do
                local a = math.rad(rz + side * 25)
                local dx, dy = -math.sin(a), math.cos(a)
                local hit, hx, hy = processLineOfSight(x, y, z + 0.3, x + dx * reach, y + dy * reach, z + 0.3,
                    true, true, false, true, false, true, false, false, v)
                local free = hit and getDistanceBetweenPoints2D(x, y, hx, hy) or reach
                if free > bestFree then best, bestFree = side, free end
            end
            if best and bestFree > gap then u.avoid = best * 30 end
        end
    end
    if u.avoid then diff = diff + u.avoid end
    if math.abs(diff) > 60 then desired = math.min(desired, 30) end

    -- Marcha atras corta para salir de un atasco
    if u.reverseUntil and now < u.reverseUntil then
        return controls(driver, false, true, -diff / 30)
    end

    local steer = diff / 25
    if speed < desired - 3 then
        controls(driver, true, false, steer)
    elseif speed > desired + 8 then
        controls(driver, false, true, steer)
    else
        controls(driver, false, false, steer)
    end

    -- Persecucion: acelera mas que un auto comun mientras va por detras (como el
    -- "rubber band" de GTA), sin pasarse de la velocidad deseada
    if not u.leaving and cfg and speed > 20 and speed < desired - 5 and (dist > 20 or (cfg.ram and pveh)) then
        local vx, vy, vz = getElementVelocity(v)
        local k = isElementOnScreen(v) and 1.008 or 1.02
        setElementVelocity(v, vx * k, vy * k, vz)
    end

    -- Asistencia: menos derrape lateral para que no se cruce en las curvas
    if speed > 4 then
        local vx, vy, vz = getElementVelocity(v)
        local fx, fy, rx, ry = m[2][1], m[2][2], m[1][1], m[1][2]
        local along, side = vx * fx + vy * fy, vx * rx + vy * ry
        if math.abs(side) > 0.02 then
            setElementVelocity(v, fx * along + rx * side * 0.75, fy * along + ry * side * 0.75, vz)
        end
    end

    -- Atasco: acelera y no avanza
    if desired > 5 and speed < 2.5 then
        u.stuckSince = u.stuckSince or now
        if now - u.stuckSince > 2500 then
            u.stuckSince = nil
            u.stuckCount = (u.stuckCount or 0) + 1
            if u.stuckCount >= 3 and warpAhead(u) then
                u.stuckCount = 0
            else
                u.reverseUntil = now + 1300
            end
        end
    else
        u.stuckSince = nil
        if speed > 15 then u.stuckCount = 0 end
    end
end

----------------------------------------------------------------
-- Policias a pie
----------------------------------------------------------------
local function runTo(ped, x, y, tx, ty, sprint)
    setElementRotation(ped, 0, 0, heading(tx - x, ty - y), "default", true)
    setPedControlState(ped, "aim_weapon", false)
    setPedControlState(ped, "fire", false)
    setPedControlState(ped, "forwards", true)
    setPedControlState(ped, "sprint", sprint)
    setPedControlState(ped, "walk", not sprint)
end

-- Arresto: se pide al servidor (que comprueba la distancia en sus unidades)
-- Animaciones del arresto: mientras el policia las hace no se lo mueve
local BUST_ANIMS = { car_open_lhs = true, car_pullout_lhs = true, arrestgun = true }
local function inBustAnim(ped)
    local _, anim = getPedAnimation(ped)
    return anim and BUST_ANIMS[anim:lower()] or false
end

local function localAnim(ped, anim, time, loop)
    if isElement(ped) and not isPedDead(ped) then
        setPedAnimation(ped, "ped", anim, time, loop or false, false, false, true)
    end
end

local function tryBust(u, ped, st, now, holdMs)
    st.bustSince = st.bustSince or now
    if now - st.bustSince < holdMs or now - (st.bustSent or 0) < 2500 then return end
    st.bustSent = now
    local inVeh = isPedInVehicle(localPlayer)
    if u.isLocal then
        -- policia del trafico (solo existe aqui): las animaciones las hace este cliente
        if inVeh then
            localAnim(ped, "CAR_open_LHS", 700)
            setTimer(localAnim, 700, 1, ped, "CAR_pullout_LHS", 1200)
            setTimer(localAnim, 1900, 1, ped, "ARRESTgun", 2600, true)
        else
            localAnim(ped, "ARRESTgun", 4000, true)
        end
        triggerServerEvent("rp:wanted:bustedLocal", resourceRoot, inVeh)
    else
        triggerServerEvent("rp:wanted:busted", resourceRoot, ped, inVeh)
    end
end

-- El servidor confirmo el arresto: se abre la puerta y, si el auto es del
-- trafico (el servidor no lo ve), este cliente saca al jugador
addEvent("rp:wanted:bustSequence", true)
addEventHandler("rp:wanted:bustSequence", resourceRoot, function(cop, inVeh)
    local v = getPedOccupiedVehicle(localPlayer)
    if not v then return end
    setElementVelocity(v, 0, 0, 0)
    if isElementLocal(v) then setVehicleDoorOpenRatio(v, 2, 1, 500) end
    setTimer(function()
        local veh = getPedOccupiedVehicle(localPlayer)
        if not veh then return end
        local m = getElementMatrix(veh)
        local x, y, z = getElementPosition(veh)
        if removePedFromVehicle then pcall(removePedFromVehicle, localPlayer) end
        if isPedInVehicle(localPlayer) then
            -- teletransportar a un ped lo baja del vehiculo
            setElementPosition(localPlayer, x - m[1][1] * 1.7, y - m[1][2] * 1.7, z + 0.2, true)
        end
        setElementVelocity(veh, 0, 0, 0)
        if isElementLocal(veh) then
            setTimer(function() if isElement(veh) then setVehicleDoorOpenRatio(veh, 2, 0, 400) end end, 3500, 1)
        end
    end, 700, 1)
end)

local function remount(u, ped, st, now)
    if now - (st.remountAt or 0) < 1500 then return end
    st.remountAt = now
    if u.isLocal then remountLocal(u, ped) else triggerServerEvent("rp:wanted:remount", resourceRoot, ped) end
end

local function footCop(u, ped, now)
    if not controlled(u, ped) or isPedDead(ped) or isPedInVehicle(ped) then return end
    if inBustAnim(ped) then return releaseFoot(ped) end
    local st = u.foot[ped]
    if not st then st = {} u.foot[ped] = st end
    local x, y, z = getElementPosition(ped)
    local px, py, pz = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
    local pveh = getPedOccupiedVehicle(localPlayer)
    local pvSpeed = pveh and speedKmh(pveh) or speedKmh(localPlayer)
    local cfg = levelCfg()
    local car = u.kind == "car" and isElement(u.vehicle) and not isVehicleBlown(u.vehicle) and u.vehicle or nil
    local carDist = math.huge
    if car then
        local cx, cy, cz = getElementPosition(car)
        carDist = getDistanceBetweenPoints3D(x, y, z, cx, cy, cz)
    end

    -- Termino la busqueda: vuelve a su vehiculo (o se va caminando)
    if u.leaving or not cfg then
        st.bustSince = nil
        if car and carDist < 60 then
            if carDist < 4 then releaseFoot(ped) return remount(u, ped, st, now) end
            local cx, cy = getElementPosition(car)
            return runTo(ped, x, y, cx, cy, false)
        end
        return runTo(ped, x, y, x + (x - px), y + (y - py), false)
    end

    local los = dist < 70 and isLineOfSightClear(x, y, z + 0.6, px, py, pz + 0.6, true, false, false, true, false, true, false)
    if los then knowledgeSeen(now) end
    local kx, ky, _, mode = knowledgeTarget(now)

    -- Te perdieron de vista: van a donde te vieron y despues barren la zona a pie
    if mode ~= "live" then
        st.bustSince = nil
        -- los controles de carretera y los pinchos no dejan su puesto
        if u.kind == "roadblock" or u.kind == "spikes" then return releaseFoot(ped) end
        -- te vieron por ultima vez en un vehiculo: vuelven a su patrulla para buscarte en auto
        if not knowledgeLastSeenOnFoot() and car and carDist < 25 then
            if carDist < 4 then releaseFoot(ped) return remount(u, ped, st, now) end
            local cx, cy = getElementPosition(car)
            return runTo(ped, x, y, cx, cy, true)
        end
        local sx, sy
        if mode == "predict" then
            sx, sy = kx, ky
        else
            local sp = knowledgeSearchPoint(st, now, x, y, true)
            sx, sy = sp[1], sp[2]
        end
        if getDistanceBetweenPoints2D(x, y, sx, sy) < 2 then return releaseFoot(ped) end
        return runTo(ped, x, y, sx, sy, mode == "predict")
    end

    -- El jugador se escapa en un vehiculo (o se aleja mucho a pie): si su patrulla esta
    -- a menos de 25 m, corre a ella y sigue en auto; si no, sigue a pie (GTA)
    local escaping = (pveh and (pvSpeed > 8 or dist > 12)) or (not pveh and dist > 50)
    if escaping and car and carDist < 25 then
        st.bustSince = nil
        if carDist < 4 then releaseFoot(ped) return remount(u, ped, st, now) end
        local cx, cy = getElementPosition(car)
        return runTo(ped, x, y, cx, cy, true)
    end

    local weapon = getPedWeapon(ped)
    local armed = weapon >= 22

    -- En un vehiculo detenido: va a la puerta y lo saca (arresto)
    if pveh then
        -- puerta del conductor (lado izquierdo, un poco adelante del centro)
        local m = getElementMatrix(pveh)
        local isBike = getVehicleType(pveh) == "Bike" or getVehicleType(pveh) == "BMX" or getVehicleType(pveh) == "Quad"
        local side = isBike and 0.9 or 1.45
        local doorX = px - m[1][1] * side + m[2][1] * 0.25
        local doorY = py - m[1][2] * side + m[2][2] * 0.25
        local doorDist = getDistanceBetweenPoints2D(x, y, doorX, doorY)
        if pvSpeed < 6 and doorDist < 1.3 and math.abs(z - pz) < 2 then
            -- esta en la puerta: mira al auto y la abre (el servidor hace el resto)
            releaseFoot(ped)
            setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
            return tryBust(u, ped, st, now, 500)
        end
        st.bustSince = nil
        if cfg.shoot and armed and los and dist < 35 and dist > 6 then
            setPedControlState(ped, "forwards", false)
            setPedControlState(ped, "sprint", false)
            setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
            setPedAimTarget(ped, px, py, pz + 0.3)
            setPedControlState(ped, "aim_weapon", true)
            setPedControlState(ped, "fire", (now + (tonumber(u.id) or 0) * 300) % 1300 < 450)
            return
        end
        return runTo(ped, x, y, doorX, doorY, doorDist > 4)
    end

    -- A pie: en el suelo o quieto a su lado -> arresto
    if dist < 3 and playerIsDown() then
        releaseFoot(ped)
        return tryBust(u, ped, st, now, 400)
    end
    if dist < 1.9 and pvSpeed < 7 then
        releaseFoot(ped)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        return tryBust(u, ped, st, now, 1200)
    end
    st.bustSince = nil

    -- Desde 2 estrellas dispara si te ve
    if cfg.shoot and armed and los and dist < 32 and dist > 3.5 then
        setPedControlState(ped, "forwards", false)
        setPedControlState(ped, "sprint", false)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        setPedAimTarget(ped, px, py, pz + 0.4)
        setPedControlState(ped, "aim_weapon", true)
        setPedControlState(ped, "fire", (now + (tonumber(u.id) or 0) * 300) % 1300 < 450)
        return
    end

    -- Control de carretera: esperan en su sitio hasta que te acercas
    if (u.kind == "roadblock" or u.kind == "spikes") and dist > 45 then
        releaseFoot(ped)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        return
    end

    -- Cuerpo a cuerpo (porra a 1 estrella, culatazo si esta muy cerca): te tira al suelo
    if dist < 1.7 then
        setPedControlState(ped, "forwards", false)
        setPedControlState(ped, "sprint", false)
        setPedControlState(ped, "aim_weapon", false)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        setPedControlState(ped, "fire", (now % 700) < 250)
        return
    end
    runTo(ped, x, y, px, py, dist > 4)
end

----------------------------------------------------------------
-- Helicoptero
----------------------------------------------------------------
local function isNight()
    local h = getTime()
    return h >= 20 or h < 6
end

----------------------------------------------------------------
-- Tirador del helicoptero (desde 4 estrellas): rafagas de M4 simuladas en este
-- cliente (los NPC no disparan desde un helicoptero). Fogonazo, trazadoras e
-- impactos; si acierta, el dano se aplica al jugador o a su vehiculo.
----------------------------------------------------------------
local tracers = {}

local function damageLocal(amount)
    local armor = getPedArmor(localPlayer)
    if armor > 0 then
        local used = math.min(armor, amount)
        setPedArmor(localPlayer, armor - used)
        amount = amount - used
    end
    if amount > 0 then setElementHealth(localPlayer, math.max(0, getElementHealth(localPlayer) - amount)) end
end

local function heliGun(u, now, h, x, y, z, px, py, pz)
    local H = WANTED_HELI
    if level < H.SHOOT_LEVEL or u.leaving or isPedDead(localPlayer) then return end
    if (now + (tonumber(u.id) or 0) * 700) % H.CYCLE > H.BURST then return end
    if now - (u.shotAt or 0) < H.SHOT_EVERY then return end
    u.shotAt = now
    local dist = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
    if dist > H.RANGE then return end
    local sx, sy, sz = x, y, z - 1.4
    if not isLineOfSightClear(sx, sy, sz, px, py, pz + 0.5, true, false, false, true, false, true, false) then return end
    local pveh = getPedOccupiedVehicle(localPlayer)
    local speed = speedKmh(pveh or localPlayer)
    local acc = H.ACCURACY * (1 - math.min(0.6, speed / 250)) * (dist < 60 and 1 or 0.7)
    local hit = math.random() < acc
    local spread = hit and 0.4 or (1.5 + math.random() * 3)
    local a = math.random() * math.pi * 2
    local tx, ty, tz = px + math.cos(a) * spread, py + math.sin(a) * spread, pz + (hit and 0.3 or -0.8)
    local dx, dy, dz = tx - sx, ty - sy, tz - sz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / len, dy / len, dz / len
    fxAddGunshot(sx, sy, sz, dx, dy, dz, true)
    local hitAny, ix, iy, iz = processLineOfSight(sx, sy, sz, sx + dx * (len + 20), sy + dy * (len + 20), sz + dz * (len + 20),
        true, true, false, true, false, false, false, false, h)
    if hitAny then
        fxAddBulletImpact(ix, iy, iz, -dx, -dy, -dz, 1, 4, 1)
        tracers[#tracers + 1] = { sx, sy, sz, ix, iy, iz, now }
    else
        tracers[#tracers + 1] = { sx, sy, sz, tx, ty, tz, now }
    end
    if not hit then return end
    if pveh and getVehicleController(pveh) == localPlayer then
        setElementHealth(pveh, math.max(0, getElementHealth(pveh) - H.DAMAGE_VEHICLE))
        if math.random() < H.TIRE_CHANCE then burstWheel(pveh) end
        -- en moto o descapotable tambien pega en el conductor
        local vt = getVehicleType(pveh)
        if vt == "Bike" or vt == "BMX" or vt == "Quad" then damageLocal(H.DAMAGE_PED) end
    elseif not pveh then
        damageLocal(H.DAMAGE_PED)
    end
end

addEventHandler("onClientRender", root, function()
    if #tracers == 0 then return end
    local now = getTickCount()
    for i = #tracers, 1, -1 do
        local t = tracers[i]
        if now - t[7] > 70 then
            table.remove(tracers, i)
        else
            dxDrawLine3D(t[1], t[2], t[3], t[4], t[5], t[6], tocolor(255, 220, 120, 200), 1.2)
        end
    end
end)

----------------------------------------------------------------
-- SWAT a rapel desde el helicoptero
----------------------------------------------------------------
local function wantsSwatDrop(u, now)
    if level < WANTED_HELI.SWAT_LEVEL or u.leaving or getElementInterior(localPlayer) ~= 0 then return false end
    if now - (u.dropReqAt or 0) < WANTED_HELI.SWAT_COOLDOWN then return false end
    for _, o in pairs(units) do
        if o.kind == "swat" and not o.leaving then return false end
    end
    return speedKmh(getPedOccupiedVehicle(localPlayer) or localPlayer) < WANTED_HELI.SWAT_MAX_SPEED
end

local function rappelTick(u, now)
    if not u.rappel then return end
    local done = true
    local step = WANTED_HELI.RAPPEL_SPEED * TICK / 1000
    for _, ped in ipairs(u.peds) do
        if isElement(ped) and not isPedDead(ped) and controlled(u, ped) and not u.landed[ped] then
            local x, y, z = getElementPosition(ped)
            local ground = getGroundPosition(x, y, z + 1)
            if not ground or ground == 0 then ground = z - 50 end
            if z - step <= ground + 1.05 then
                u.landed[ped] = true
                setElementFrozen(ped, false)
                setPedAnimation(ped)
                setElementPosition(ped, x, y, ground + 1.05)
            else
                done = false
                setElementFrozen(ped, true)
                setElementPosition(ped, x, y, z - step)
                local _, anim = getPedAnimation(ped)
                if not anim or anim:lower() ~= "abseil" then
                    setPedAnimation(ped, "ped", "ABSEIL", -1, true, false, false, true)
                end
            end
        end
    end
    if done then u.rappel = nil end
end

-- Cuerdas del rapel
addEventHandler("onClientRender", root, function()
    for _, u in pairs(units) do
        if u.rappel and isElement(u.drop) then
            local hx, hy, hz = getElementPosition(u.drop)
            for _, ped in ipairs(u.peds) do
                if isElement(ped) and not u.landed[ped] then
                    local x, y, z = getElementPosition(ped)
                    dxDrawLine3D(hx, hy, hz - 1, x, y, z + 0.8, tocolor(40, 40, 40, 255), 2)
                end
            end
        end
    end
end)

local function heliTick(u, now)
    local h = u.vehicle
    if not isElementSyncer(h) or isVehicleBlown(h) then return end
    -- Vuela sobre donde saben que estas; si te perdieron (tunel, puente, techo), barre la zona con el foco
    local px, py, pz, mode = knowledgeTarget(now)
    local live = mode == "live"
    local lightX, lightY, lightZ = px, py, pz
    local x, y, z = getElementPosition(h)
    local tx, ty, tz
    local dropping = false
    if u.leaving or level == 0 then
        u.away = u.away or { x + (x - px) * 8, y + (y - py) * 8 }
        tx, ty, tz = u.away[1], u.away[2], z + 30
    else
        local ground = getGroundPosition(px, py, pz + 80)
        ground = math.max(pz - 2, (ground and ground ~= 0) and ground or pz)
        -- Equipo SWAT: baja hasta quedar justo encima del jugador y lo suelta
        local squad
        for _, o in pairs(units) do
            if o.kind == "swat" and o.rappel and o.drop == h then squad = o end
        end
        if mode == "search" and not squad then
            -- orbita amplia sobre la ultima posicion; el foco recorre la zona en espiral
            local r = math.min(120, knowledgeSearchRadius(now) * 0.5)
            local a = now / 1000 * 0.12 + (tonumber(u.id) or 0) * 2
            tx, ty, tz = px + math.cos(a) * r, py + math.sin(a) * r, ground + 40
            local b, lr = now / 1000 * 0.7, r * (0.4 + 0.6 * math.abs(math.sin(now / 7000)))
            lightX, lightY = px + math.cos(b) * lr, py + math.sin(b) * lr
            local gz = getGroundPosition(lightX, lightY, ground + 60)
            lightZ = (gz and gz ~= 0) and gz + 1 or ground + 1
        elseif squad or (live and wantsSwatDrop(u, now)) then
            dropping = true
            tx, ty, tz = px + 4, py + 4, ground + WANTED_HELI.HOVER_HEIGHT
            if not squad and getDistanceBetweenPoints2D(x, y, tx, ty) < 12 and math.abs(z - tz) < 5 then
                u.dropReqAt = now
                triggerServerEvent("rp:wanted:heliDrop", resourceRoot, h)
            end
        else
            local a = now / 1000 * 0.25 + (tonumber(u.id) or 0) * 2
            tx, ty = px + math.cos(a) * 22, py + math.sin(a) * 22
            tz = ground + 30
        end
        if not dropping and live then heliGun(u, now, h, x, y, z, getElementPosition(localPlayer)) end
    end
    local dx, dy, dz = tx - x, ty - y, tz - z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d > 0.5 then
        local k = math.min(0.7, d * 0.02) / d
        setElementVelocity(h, dx * k, dy * k, dz * k)
    else
        setElementVelocity(h, 0, 0, 0)
    end
    setElementAngularVelocity(h, 0, 0, 0)
    setElementRotation(h, 0, 0, heading(lightX - x, lightY - y))
    if setVehicleRotorSpeed then setVehicleRotorSpeed(h, 0.2) end

    -- Foco de noche
    if isNight() and not u.leaving then
        if not isElement(u.light) then
            u.light = createSearchLight(x, y, z - 1, lightX, lightY, lightZ - 1, 0.25, 5, true)
        else
            setSearchLightStartPosition(u.light, x, y, z - 1.2)
            setSearchLightEndPosition(u.light, lightX, lightY, lightZ - 1)
        end
    elseif isElement(u.light) then
        destroyElement(u.light)
        u.light = nil
    end
end

----------------------------------------------------------------
-- Bucle
----------------------------------------------------------------
----------------------------------------------------------------
-- Patrullas del trafico (rp_citizens) que se suman a la persecucion
----------------------------------------------------------------
local localSeq = 0

local function armLocal(ped)
    if not givePedWeapon then return end
    if level >= 2 then givePedWeapon(ped, 22, 500, true) else givePedWeapon(ped, 3, 1, true) end
end

-- Llamado por rp_citizens: devuelve true si la unidad pasa a la policia de rp_wanted
function adoptLocalCop(vehicle, ped)
    if level <= 0 or not isElement(ped) or isPedDead(ped) then return false end
    -- persecucion retenida por un robo negociado (rp_robbery): el trafico tampoco persigue
    if getElementData(localPlayer, "rp:wantedHeld") then return false end
    local count = 0
    for _, u in pairs(units) do if u.isLocal and not u.leaving then count = count + 1 end end
    if count >= 3 then return false end
    localSeq = localSeq + 1
    local u = {
        id = "L" .. localSeq, isLocal = true, kind = "car", fleet = "police", foot = {},
        vehicle = isElement(vehicle) and vehicle or nil, vehicles = { isElement(vehicle) and vehicle or nil },
        peds = { ped }, pedSet = { [ped] = true }, created = getTickCount(),
    }
    if isElement(vehicle) then setVehicleSirensOn(vehicle, true) end
    armLocal(ped)
    units[u.id] = u
    return true
end

function dismountLocal(u)
    local v = u.vehicle
    if not isElement(v) then return end
    local m = getElementMatrix(v)
    for _, ped in ipairs(u.peds) do
        if isElement(ped) and getPedOccupiedVehicle(ped) == v then
            local seat = getPedOccupiedVehicleSeat(ped) or 0
            local side = (seat % 2 == 0) and -1.9 or 1.9
            local x, y, z = getElementPosition(v)
            removePedFromVehicle(ped)
            setElementPosition(ped, x + m[1][1] * side, y + m[1][2] * side, z + 0.3)
        end
    end
end

function remountLocal(u, ped)
    local v = u.vehicle
    if not isElement(v) or isVehicleBlown(v) or isPedInVehicle(ped) then return end
    for seat = 0, getVehicleMaxPassengers(v) or 0 do
        if not getVehicleOccupant(v, seat) then
            warpPedIntoVehicle(ped, v, seat)
            return
        end
    end
end

function removeLocalUnit(u)
    units[u.id] = nil
    if isElement(u.light) then destroyElement(u.light) end
    for _, ped in ipairs(u.peds) do if isElement(ped) then destroyElement(ped) end end
    for _, v in ipairs(u.vehicles) do
        if isElement(v) and getVehicleController(v) ~= localPlayer and not getVehicleOccupant(v, 1) then destroyElement(v) end
    end
end

-- Limpieza de las locales: se van al terminar la busqueda y desaparecen sin que se vea
local function localHousekeeping(u, now)
    local px, py, pz = getElementPosition(localPlayer)
    local alive, nearest, seen = 0, math.huge, false
    for _, list in ipairs({ u.peds, u.vehicles }) do
        for _, el in ipairs(list) do
            if isElement(el) then
                local x, y, z = getElementPosition(el)
                nearest = math.min(nearest, getDistanceBetweenPoints3D(px, py, pz, x, y, z))
                seen = seen or isElementOnScreen(el)
                if getElementType(el) == "ped" and not isPedDead(el) then alive = alive + 1 end
            end
        end
    end
    if alive == 0 then
        u.deadAt = u.deadAt or now
        if now - u.deadAt > WANTED_DISPATCH.BODY_TIME then removeLocalUnit(u) end
        return
    end
    if u.leaving then
        u.leaveAt = u.leaveAt or now
        if (nearest > 120 and not seen) or now - u.leaveAt > 60000 then removeLocalUnit(u) end
    end
end

----------------------------------------------------------------
-- Tactica de grupo: la patrulla mas cercana persigue; las demas se adelantan
-- por la ruta probable del jugador para cortarle el paso
----------------------------------------------------------------
local roleAt = 0
local function chooseIntercept(u, path, pspeedMs)
    local v = u.vehicle
    local x, y = getElementPosition(v)
    local copMs = 38   -- ~135 km/h
    local last
    for _, p in ipairs(path) do
        if p[4] > 45 then
            local copTime = getDistanceBetweenPoints2D(x, y, p[1], p[2]) * 1.35 / copMs
            local playerTime = p[4] / math.max(6, pspeedMs)
            last = p
            if copTime < playerTime * 0.85 then return p end
        end
    end
    return last
end

local function assignRoles(now)
    if now - roleAt < 1000 then return end
    roleAt = now
    -- cortar el paso solo tiene sentido si saben por donde vas
    local pveh = getPedOccupiedVehicle(localPlayer)
    local path = pveh and knowledgeMode(now) == "live" and playerPath(now)
    local px, py = getElementPosition(localPlayer)
    local list = {}
    for _, u in pairs(units) do
        if u.kind == "car" and not u.leaving and isElement(u.vehicle) and controlled(u, u.vehicle) then
            local x, y = getElementPosition(u.vehicle)
            list[#list + 1] = { u = u, d = getDistanceBetweenPoints2D(x, y, px, py) }
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    for i, e in ipairs(list) do
        local u = e.u
        local was = u.icpt
        local wasRole = u.role
        u.role, u.icpt = "chase", nil
        -- la primera persigue; el resto intercepta si hay ruta probable y va rapido
        local cfg = levelCfg()
        if i > (cfg and cfg.chasers or 1) and path and #path > 3 and (pred.speed or 0) > 9 then
            local p = chooseIntercept(u, path, pred.speed)
            if p then
                u.role = "intercept"
                -- conserva el punto si sigue en la ruta (para no replanear siempre)
                if was then
                    for _, q in ipairs(path) do
                        if q[5] == was[5] and q[4] > 25 then p = was break end
                    end
                end
                local nxt
                for k, q in ipairs(path) do if q == p then nxt = path[k + 1] end end
                p[6] = p[6] or (nxt and heading(nxt[1] - p[1], nxt[2] - p[2])) or 0
                u.icpt = { p[1], p[2], p[3], p[6], p[5] }
                if was and was[5] == p[5] then u.icpt = was end
            end
        end
        if wasRole == "intercept" and u.role == "chase" then u.wp, u.planAt, u.icptPlanned = nil, 0, nil end
    end
end

----------------------------------------------------------------
-- Disparos desde la ventanilla (drive-by) desde 2 estrellas
----------------------------------------------------------------
local function setDriveby(ped, on)
    if setPedDoingGangDriveby then setPedDoingGangDriveby(ped, on) end
    if not on then
        setPedControlState(ped, "vehicle_fire", false)
        setPedControlState(ped, "fire", false)
    end
end

local wheelAt = 0
function burstWheel(veh)
    -- Condicion negociada en un robo (rp_robbery): no disparan a las llantas
    if getElementData(localPlayer, "rp:wantedNoTires") then return end
    local states = { getVehicleWheelStates(veh) }
    local good = {}
    for i = 1, 4 do if states[i] == 0 then good[#good + 1] = i end end
    if #good == 0 then return end
    states[good[math.random(#good)]] = 1
    setVehicleWheelStates(veh, states[1], states[2], states[3], states[4])
end

local function carGunners(u, now)
    local v = u.vehicle
    if not isElement(v) or isVehicleBlown(v) then return end
    local cfg = levelCfg()
    local pveh = getPedOccupiedVehicle(localPlayer)
    local x, y, z = getElementPosition(v)
    local px, py, pz = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
    local firing = cfg and cfg.shoot and not u.leaving and dist < 45
        and isLineOfSightClear(x, y, z + 1, px, py, pz + 0.5, true, false, false, true, false, true, false)
    u.driveby = u.driveby or {}
    for _, ped in ipairs(u.peds) do
        if isElement(ped) and getPedOccupiedVehicle(ped) == v and controlled(u, ped) then
            local seat = getPedOccupiedVehicleSeat(ped) or 0
            if firing and seat > 0 and not isPedDead(ped) and getPedWeapon(ped) >= 22 then
                if not u.driveby[ped] then u.driveby[ped] = true setDriveby(ped, true) end
                -- a los neumaticos si vas en vehiculo
                setPedAimTarget(ped, px, py, pz + (pveh and -0.4 or 0.3))
                local burst = (now + seat * 250) % 1100 < 500
                setPedControlState(ped, "vehicle_fire", burst)
                setPedControlState(ped, "fire", burst)
            elseif u.driveby[ped] then
                u.driveby[ped] = nil
                setDriveby(ped, false)
            end
        end
    end
    -- Ademas de las balas que pegan: cada tanto le revientan un neumatico
    if firing and pveh and dist < 30 and getVehicleController(pveh) == localPlayer and now - wheelAt > 1500 then
        wheelAt = now
        for ped in pairs(u.driveby) do
            if math.random() < WANTED_TIRE_SHOT_CHANCE then burstWheel(pveh) end
            break
        end
    end
end

-- Balas de la policia contra tu vehiculo: pueden reventar un neumatico
addEventHandler("onClientVehicleDamage", root, function(attacker, weapon)
    if source ~= getPedOccupiedVehicle(localPlayer) or getVehicleController(source) ~= localPlayer then return end
    if not attacker or not isElement(attacker) or getElementType(attacker) ~= "ped" then return end
    if not getElementData(attacker, "rp:cop") or not weapon or weapon < 22 or weapon > 34 then return end
    if math.random() < WANTED_TIRE_HIT_CHANCE then burstWheel(source) end
end)

----------------------------------------------------------------
-- Pinchos: si el vehiculo del jugador cruza la tira, revientan los neumaticos
----------------------------------------------------------------
local lastPos
local function checkSpikes()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer then lastPos = nil return end
    local x, y = getElementPosition(v)
    local prev = lastPos
    lastPos = { x, y }
    if not prev then return end
    for _, u in pairs(units) do
        local sp = u.kind == "spikes" and u.spike
        if sp and not u.leaving then
            local r = math.rad(sp.rot)
            local fx, fy = -math.sin(r), math.cos(r)
            local rx, ry = fy, -fx
            local s0 = (prev[1] - sp.x) * fx + (prev[2] - sp.y) * fy
            local s1 = (x - sp.x) * fx + (y - sp.y) * fy
            local lat = (x - sp.x) * rx + (y - sp.y) * ry
            if (s0 > 0) ~= (s1 > 0) and math.abs(lat) < sp.half + 1 then
                setVehicleWheelStates(v, 1, 1, 1, 1)
                pcall(function() exports.rp_notify:notify("Pisaste los pinchos de la policia.", "error") end)
            end
        end
    end
end

-- El avistamiento (rp:wanted:seen) y la ultima posicion conocida estan en client/c_knowledge.lua

----------------------------------------------------------------
-- Lancha (persecucion por mar): en el agua no hay red vial; va directa hacia donde estara el jugador.
-- Por debajo de WANTED_BOAT.RAM_LEVEL lo ronda a CHASE_DIST (el tirador dispara con carGunners);
-- desde RAM_LEVEL lo embiste. Si se queda atascada contra la orilla, da marcha atras.
----------------------------------------------------------------
local function boatTick(u, now)
    local v = u.vehicle
    if isVehicleBlown(v) then return end
    local driver = getVehicleController(v)
    if not driver or not u.pedSet[driver] or isPedDead(driver) or not controlled(u, v) then return end
    local x, y = getElementPosition(v)
    local _, _, rz = getElementRotation(v)
    local px, py = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints2D(x, y, px, py)
    local speed = speedKmh(v)

    -- Muy lejos y fuera de la vista: se retira y el servidor manda otra mas cerca
    if not u.leaving and dist > WANTED_DISPATCH.LOST_DISTANCE and not isElementOnScreen(v) and not u.lostSent then
        u.lostSent = true
        return triggerServerEvent("rp:wanted:unitLost", resourceRoot, u.id)
    end

    -- Atascada (contra la orilla o un muelle): marcha atras un momento girando
    if u.reverseUntil and now < u.reverseUntil then
        return controls(driver, false, true, u.reverseSteer or 0)
    end

    local tx, ty
    local cruise = true
    if u.leaving or not levelCfg() then
        tx, ty = x + (x - px), y + (y - py)   -- se aleja del jugador
    else
        -- hacia donde saben que estas; si te ven, a donde estaras en ~1,5 s (MTA: velocidad en unidades por 1/50 s)
        local kx, ky, _, mode = knowledgeTarget(now)
        local vx, vy = 0, 0
        if mode == "live" then vx, vy = getElementVelocity(getPedOccupiedVehicle(localPlayer) or localPlayer) end
        px, py = kx, ky
        dist = getDistanceBetweenPoints2D(x, y, px, py)
        tx, ty = px + vx * 75, py + vy * 75
        if level < WANTED_BOAT.RAM_LEVEL and dist < WANTED_BOAT.CHASE_DIST * 2 then
            -- ronda: apunta a un punto a CHASE_DIST del jugador, girando a su alrededor
            local ox, oy = (x - px) / math.max(dist, 1), (y - py) / math.max(dist, 1)
            tx = px + (ox * 0.6 - oy) * WANTED_BOAT.CHASE_DIST
            ty = py + (oy * 0.6 + ox) * WANTED_BOAT.CHASE_DIST
            cruise = speed < 35
        end
    end
    local diff = angleDiff(heading(tx - x, ty - y), rz)

    if cruise and speed < 4 then
        u.stuckSince = u.stuckSince or now
        if now - u.stuckSince > 2500 then
            u.stuckSince = nil
            u.reverseUntil, u.reverseSteer = now + 1800, diff > 0 and -1 or 1
        end
    else
        u.stuckSince = nil
    end
    controls(driver, cruise, false, diff / 35)
end

local function tick()
    local now = getTickCount()
    planBudget = 1
    assignRoles(now)
    checkSpikes()
    for _, u in pairs(units) do
        if u.isLocal then
            if level == 0 and not u.leaving then
                u.leaving, u.wp, u.leaveTarget = true, nil, nil
                if isElement(u.vehicle) then setVehicleSirensOn(u.vehicle, false) end
            end
            localHousekeeping(u, now)
        end
    end
    for _, u in pairs(units) do
        if u.kind == "heli" then
            if isElement(u.vehicle) then heliTick(u, now) end
        elseif u.kind == "boat" then
            if isElement(u.vehicle) then
                boatTick(u, now)
                carGunners(u, now)
            end
        elseif u.kind == "swat" and u.rappel then
            rappelTick(u, now)
        else
            if u.kind == "car" and isElement(u.vehicle) then
                driveCar(u, now)
                carGunners(u, now)
            end
            for _, ped in ipairs(u.peds) do
                if isElement(ped) then footCop(u, ped, now) end
            end
        end
    end
end

local function cleanupUnit(u)
    if isElement(u.light) then destroyElement(u.light) end
    for _, ped in ipairs(u.peds) do
        if isElement(ped) then
            releaseFoot(ped)
            for _, c in ipairs({ "accelerate", "brake_reverse", "handbrake" }) do setPedControlState(ped, c, false) end
        end
    end
end

addEvent("rp:wanted:unit", true)
addEventHandler("rp:wanted:unit", resourceRoot, function(data)
    if type(data) ~= "table" or not data.id then return end
    local u = units[data.id] or { foot = {} }
    u.id, u.kind, u.fleet = data.id, data.kind, data.fleet
    u.vehicle, u.vehicles, u.peds = data.vehicle, data.vehicles or {}, data.peds or {}
    if data.leaving and not u.leaving then u.wp, u.leaveTarget = nil, nil end
    u.leaving = data.leaving
    u.spike = data.spike
    if data.drop and not u.drop then
        u.drop, u.rappel, u.landed = data.drop, true, {}
    end
    u.created = u.created or getTickCount()
    u.pedSet = {}
    for _, ped in ipairs(u.peds) do u.pedSet[ped] = true end
    units[data.id] = u
end)

addEvent("rp:wanted:unitRemoved", true)
addEventHandler("rp:wanted:unitRemoved", resourceRoot, function(id)
    local u = units[id]
    if u then cleanupUnit(u) end
    units[id] = nil
end)

addEvent("rp:wanted:level", true)
addEventHandler("rp:wanted:level", resourceRoot, function(lv)
    local old = level
    level = tonumber(lv) or 0
    -- A 2 estrellas las patrullas del trafico sacan la pistola
    if old < 2 and level >= 2 then
        for _, u in pairs(units) do
            if u.isLocal then for _, ped in ipairs(u.peds) do if isElement(ped) then armLocal(ped) end end end
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    level = tonumber(getElementData(localPlayer, "rp:wanted")) or 0
    setTimer(tick, TICK, 0)
    triggerServerEvent("rp:wanted:ready", resourceRoot)
    -- Garajes del juego que contienen un Pay 'n' Spray (el servidor abre su porton)
    local ids = {}
    for id = 0, 49 do
        local west, east, south, north = getGarageBoundingBox(id)
        if west then
            for _, spot in ipairs(WANTED.SPRAYS) do
                if spot.x >= west - 3 and spot.x <= east + 3 and spot.y >= south - 3 and spot.y <= north + 3 then
                    ids[#ids + 1] = id
                end
            end
        end
    end
    if #ids > 0 then triggerServerEvent("rp:wanted:garages", resourceRoot, ids) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, u in pairs(units) do
        if u.isLocal then removeLocalUnit(u) else cleanupUnit(u) end
    end
end)
