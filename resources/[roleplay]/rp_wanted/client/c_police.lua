--[[
    rp_wanted / c_police.lua
    IA de las unidades de policia que persiguen al jugador local. El servidor
    crea los elementos y nos hace syncer; aqui se manejan con sus controles,
    como el conductor IA de rp_rides y el trafico de rp_citizens.

    Patrulla:   ROUTE  (A* por la red vial hasta el jugador, se recalcula)
                CHASE  (lo ve a menos de 60 m: va directo, predice hacia donde va;
                        desde 3 estrellas lo embiste)
                STOP   (el jugador va a pie o se detuvo cerca: frena y se bajan)
                LEAVE  (termino la busqueda: apaga la sirena y se va)
    A pie:      corre hacia el jugador; si lo alcanza lo arresta; desde 2
                estrellas dispara cuando lo ve; si el jugador se va en auto,
                vuelve a su patrulla.
    Helicoptero: vuela en circulo sobre el jugador; de noche lo sigue con un foco.
    Control de carretera: 2 patrullas atravesadas y policias que esperan.
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

----------------------------------------------------------------
-- Puntos de aparicion (los pide el servidor)
----------------------------------------------------------------
local function onScreen(x, y, z)
    return getScreenFromWorldPosition(x, y, z + 1, 0, false) ~= false
end

local function carSpawnPoint()
    local px, py, pz = getElementPosition(localPlayer)
    if loadRoadGraph() then
        local fallback
        for _ = 1, 12 do
            local a, b = roadNodeAround(px, py, WANTED_DISPATCH.SPAWN_MIN, WANTED_DISPATCH.SPAWN_MAX)
            if a then
                local x, y, z, rot = laneStartPoint(a, b)
                -- que el auto mire mas o menos hacia el jugador
                local toward = math.abs(angleDiff(heading(px - x, py - y), rot)) < 100
                if not onScreen(x, y, z) and toward then return x, y, z, rot end
                fallback = fallback or { x, y, z, rot }
            end
        end
        if fallback then return unpack(fallback) end
    end
    -- Sin red vial: detras de la camara
    local cx, cy = getCameraMatrix()
    local dx, dy = px - cx, py - cy
    local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    local x, y = px - dx / len * 110, py - dy / len * 110
    local gz = getGroundPosition(x, y, pz + 50)
    return x, y, (gz and gz ~= 0) and gz or pz, heading(dx, dy)
end

-- Control de carretera: un nodo de la calle por delante del jugador, en su direccion
local function roadblockPoint()
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
    if kind == "car" then
        x, y, z, rot = carSpawnPoint()
    elseif kind == "roadblock" then
        x, y, z, rot = roadblockPoint()
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

local function plan(u, tx, ty)
    u.wp, u.idx, u.planAt = nil, 1, getTickCount()
    if not loadRoadGraph() then return end
    local s = startNodeAhead(u.vehicle)
    local g = nearestRoadNode(tx, ty)
    local route = s and g and findRoadRoute(s, g, 4000)
    if route and #route >= 2 then u.wp = routeWaypoints(route) end
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
    if not driver or not u.pedSet[driver] or isPedDead(driver) or not isElementSyncer(v) then return end
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
        -- El jugador a pie (o detenido) cerca: frena y los policias se bajan
        local stopNear = (not pveh and dist < 24) or (pveh and pspeed < 8 and dist < 16)
        if stopNear then
            controls(driver, false, speed > 0.5, 0, true)
            if speed < 5 and now - (u.dismountAt or 0) > 3000 then
                u.dismountAt = now
                triggerServerEvent("rp:wanted:dismount", resourceRoot, v)
            end
            return
        end

        local los = dist < 60 and isLineOfSightClear(x, y, z + 1, px, py, pz + 0.5, true, false, false, true, false, true, false)
        if los then
            -- CHASE: directo al jugador, adelantandose a donde va
            local tvx, tvy = getElementVelocity(pveh or localPlayer)
            local lead = math.min(1.2, dist / 40)
            tx, ty = px + tvx * 50 * lead, py + tvy * 50 * lead
            if cfg.ram then
                desired = 170
            elseif dist > 18 then
                desired = 150
            else
                desired = math.max(20, pspeed + 3)   -- lo sigue de cerca sin chocarlo
            end
            u.wp = nil
        else
            -- ROUTE: A* hasta el jugador, se recalcula cada 2.5 s
            if not u.wp or now - (u.planAt or 0) > 2500 then plan(u, px, py) end
            desired = 120
            if u.wp and #u.wp > 0 then
                local turn, last
                tx, ty, turn, last = routeTarget(u, x, y, speed)
                if turn > 50 then desired = 35 elseif turn > 25 then desired = 60 end
                if last then tx, ty = px, py end
            else
                tx, ty = px, py
            end
            local gap = obstacleAhead(v, m, speed, pveh)
            if gap and gap < 9 then desired = math.min(desired, 15) end
        end
    end

    local diff = angleDiff(heading(tx - x, ty - y), rz)
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

local function footCop(u, ped, now)
    if not isElementSyncer(ped) or isPedDead(ped) or isPedInVehicle(ped) then return end
    local st = u.foot[ped]
    if not st then st = {} u.foot[ped] = st end
    local x, y, z = getElementPosition(ped)
    local px, py, pz = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
    local pveh = getPedOccupiedVehicle(localPlayer)
    local cfg = levelCfg()
    local car = u.kind == "car" and isElement(u.vehicle) and not isVehicleBlown(u.vehicle) and u.vehicle or nil

    -- Vuelve a su patrulla: termino la busqueda o el jugador se fue en auto
    if car and (u.leaving or not cfg or (pveh and dist > 30)) then
        local cx, cy, cz = getElementPosition(car)
        local d = getDistanceBetweenPoints3D(x, y, z, cx, cy, cz)
        if d < 5 then
            releaseFoot(ped)
            if now - (st.remountAt or 0) > 2000 then
                st.remountAt = now
                triggerServerEvent("rp:wanted:remount", resourceRoot, ped)
            end
        else
            runTo(ped, x, y, cx, cy, d > 8)
        end
        return
    end
    if u.leaving or not cfg then
        return runTo(ped, x, y, x + (x - px), y + (y - py), false)   -- se aleja caminando
    end

    local los = isLineOfSightClear(x, y, z + 0.6, px, py, pz + 0.6, true, false, false, true, false, true, false)
    local weapon = getPedWeapon(ped)

    -- Disparar (desde 2 estrellas, con arma de fuego, viendolo)
    if cfg.shoot and weapon >= 22 and los and dist < 32 and dist > 3 then
        setPedControlState(ped, "forwards", false)
        setPedControlState(ped, "sprint", false)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        setPedAimTarget(ped, px, py, pz + 0.4)
        setPedControlState(ped, "aim_weapon", true)
        setPedControlState(ped, "fire", (now + u.id * 300) % 1300 < 450)   -- rafagas
        st.bustSince = nil
        return
    end

    -- Control de carretera: esperan en su sitio hasta que te acercas
    if u.kind == "roadblock" and dist > 45 then
        releaseFoot(ped)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        return
    end

    if dist > 1.3 then
        runTo(ped, x, y, px, py, dist > 5)
    else
        releaseFoot(ped)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
    end

    -- Arresto: te alcanza a pie, o te quedas quieto en un vehiculo con el al lado
    local close = (not pveh and dist < 2.2) or (pveh and speedKmh(pveh) < 3 and dist < 4.5)
    if close and not isPedDead(localPlayer) then
        st.bustSince = st.bustSince or now
        if now - st.bustSince > 1300 and now - (st.bustSent or 0) > 3000 then
            st.bustSent = now
            triggerServerEvent("rp:wanted:busted", resourceRoot, ped)
        end
    else
        st.bustSince = nil
    end
end

----------------------------------------------------------------
-- Helicoptero
----------------------------------------------------------------
local function isNight()
    local h = getTime()
    return h >= 20 or h < 6
end

local function heliTick(u, now)
    local h = u.vehicle
    if not isElementSyncer(h) or isVehicleBlown(h) then return end
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z = getElementPosition(h)
    local tx, ty, tz
    if u.leaving or level == 0 then
        u.away = u.away or { x + (x - px) * 8, y + (y - py) * 8 }
        tx, ty, tz = u.away[1], u.away[2], z + 30
    else
        local a = now / 1000 * 0.25 + u.id * 2
        tx, ty = px + math.cos(a) * 22, py + math.sin(a) * 22
        local ground = getGroundPosition(px, py, pz + 80)
        tz = math.max(pz, ground or pz) + 30
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
    setElementRotation(h, 0, 0, heading(px - x, py - y))
    setHelicopterRotorSpeed(h, 0.2)

    -- Foco de noche
    if isNight() and not u.leaving then
        if not isElement(u.light) then
            u.light = createSearchLight(x, y, z - 1, px, py, pz - 1, 0.25, 5, true)
        else
            setSearchLightStartPosition(u.light, x, y, z - 1.2)
            setSearchLightEndPosition(u.light, px, py, pz - 1)
        end
    elseif isElement(u.light) then
        destroyElement(u.light)
        u.light = nil
    end
end

----------------------------------------------------------------
-- Bucle
----------------------------------------------------------------
local function tick()
    local now = getTickCount()
    for _, u in pairs(units) do
        if u.kind == "heli" then
            if isElement(u.vehicle) then heliTick(u, now) end
        else
            if u.kind == "car" and isElement(u.vehicle) then driveCar(u, now) end
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
    level = tonumber(lv) or 0
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    level = tonumber(getElementData(localPlayer, "rp:wanted")) or 0
    setTimer(tick, TICK, 0)
    triggerServerEvent("rp:wanted:ready", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, u in pairs(units) do cleanupUnit(u) end
end)
