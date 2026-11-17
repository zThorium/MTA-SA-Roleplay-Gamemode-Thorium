--[[
    rp_citizens / c_citizens.lua
    Poblacion ambiental (peatones y trafico) estilo GTA SA, 100% en el cliente:
      - Cada jugador ve su propia poblacion (sin trafico de red, como en PS2).
      - Solo existen pocos NPC y solo cerca del jugador: aparecen fuera de
        camara y desaparecen al alejarse.
      - Siguen la red de caminos original de GTA SA (c_nodes_ls.lua).
      - Cada NPC es una maquina de estados finita con un tick de IA barato.

    Peatones:  WALK -> IDLE -> WALK ... | FLEE (disparos, arma apuntada, golpes)
               | FIGHT (si es valiente y lo golpeas) | DEAD
    Autos:     DRIVE -> BLOCKED (frena) -> HONK (bocina) -> AVOID (esquiva) -> DRIVE
               | FLEE (lo chocas o disparas: acelera y se va)

    /poblacion  activa o desactiva la poblacion (para comparar rendimiento).
]]

----------------------------------------------------------------
-- Configuracion
----------------------------------------------------------------
local CFG = {
    MAX_PEDS = 14, MAX_PEDS_NIGHT = 7,
    MAX_CARS = 7,  MAX_CARS_NIGHT = 4,
    PED_SPAWN_MIN = 40, PED_SPAWN_MAX = 80, PED_DESPAWN = 105,
    CAR_SPAWN_MIN = 70, CAR_SPAWN_MAX = 130, CAR_DESPAWN = 170,
    PED_TICK = 300,      -- ms entre decisiones de peatones
    CAR_TICK = 120,      -- ms entre decisiones de conductores (necesitan girar el volante)
    SPAWN_TICK = 1000,
    CAR_SPEED = 42,      -- km/h de crucero
    CORNER_SPEED = 20,
    BRAVE_CHANCE = 0.3,  -- probabilidad de que un peaton responda a los golpes
}

local PED_SKINS = { 7, 14, 15, 17, 20, 21, 22, 23, 24, 26, 29, 32, 34, 35, 37, 43, 44, 46, 47, 48, 57, 58, 59, 60,
    9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 69, 76, 88, 89, 91, 93, 141, 148, 150, 151, 157, 169 }
local CAR_MODELS = { 400, 401, 404, 405, 410, 418, 421, 426, 436, 445, 458, 466, 467, 474, 479, 491, 492, 496,
    507, 516, 517, 518, 526, 527, 529, 540, 542, 546, 547, 549, 550, 551, 554, 566, 585, 589, 600 }
local DRIVER_SKINS = { 7, 15, 20, 22, 24, 26, 44, 47, 58, 60, 12, 13, 40, 55, 76, 91 }

----------------------------------------------------------------
-- Grafo de caminos
----------------------------------------------------------------
local CELL = 100
local function buildGrid(nodes, links)
    local grid = {}
    for i = 1, #nodes / 3 do
        -- los nodos sin enlaces (borrados en el editor) no se usan
        if links[i] and #links[i] > 0 then
            local x, y = nodes[i * 3 - 2], nodes[i * 3 - 1]
            local key = math.floor(x / CELL) * 1000 + math.floor(y / CELL)
            local cell = grid[key]
            if not cell then cell = {} grid[key] = cell end
            cell[#cell + 1] = i
        end
    end
    return grid
end

local pedGrid, vehGrid

local function nodePos(nodes, i)
    return nodes[i * 3 - 2], nodes[i * 3 - 1], nodes[i * 3]
end

-- Busca un nodo al azar a una distancia [minD, maxD] del jugador
local function randomNodeAround(nodes, grid, px, py, minD, maxD)
    for _ = 1, 6 do
        local angle = math.random() * math.pi * 2
        local dist = minD + math.random() * (maxD - minD)
        local tx, ty = px + math.cos(angle) * dist, py + math.sin(angle) * dist
        local cell = grid[math.floor(tx / CELL) * 1000 + math.floor(ty / CELL)]
        if cell then
            local i = cell[math.random(#cell)]
            local x, y, z = nodePos(nodes, i)
            local d = getDistanceBetweenPoints2D(px, py, x, y)
            if d >= minD and d <= maxD then return i, x, y, z end
        end
    end
end

local function nearestNode(nodes, grid, x, y)
    local best, bestD = nil, math.huge
    local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
    for ox = -1, 1 do
        for oy = -1, 1 do
            local cell = grid[(cx + ox) * 1000 + (cy + oy)]
            if cell then
                for _, i in ipairs(cell) do
                    local nx, ny = nodes[i * 3 - 2], nodes[i * 3 - 1]
                    local d = (nx - x) ^ 2 + (ny - y) ^ 2
                    if d < bestD then best, bestD = i, d end
                end
            end
        end
    end
    return best
end

-- Siguiente nodo evitando volver atras si hay alternativa
local function nextNode(links, current, previous)
    local list = links[current]
    if not list or #list == 0 then return previous end
    if #list == 1 then return list[1] end
    for _ = 1, 4 do
        local n = list[math.random(#list)]
        if n ~= previous then return n end
    end
    return list[1]
end

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local enabled = true
local peds, cars = {}, {}          -- [ped] = estado | [vehicle] = estado
local pedCount, carCount = 0, 0

local function heading(dx, dy)     -- rotacion Z de GTA (0 = norte, antihorario)
    return -math.deg(math.atan2(dx, dy))
end

local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

local function isNight()
    local h = getTime()
    return h >= 22 or h < 6
end

local function visibleFromCamera(x, y, z)
    local sx = getScreenFromWorldPosition(x, y, z + 1, 0, false)
    if not sx then return false end
    local cx, cy, cz = getCameraMatrix()
    return isLineOfSightClear(cx, cy, cz, x, y, z + 1, true, false, false, true, false, false, false)
end

local function playerIsActive()
    return getElementInterior(localPlayer) == 0 and getElementDimension(localPlayer) == 0
end

----------------------------------------------------------------
-- Peatones
----------------------------------------------------------------
local function setWalking(ped, walk, sprint)
    setPedControlState(ped, "forwards", walk)
    setPedControlState(ped, "walk", walk and not sprint)
    setPedControlState(ped, "sprint", sprint and true or false)
end

local function removePed(ped)
    peds[ped] = nil
    pedCount = pedCount - 1
    if isElement(ped) then destroyElement(ped) end
end

local function spawnPed(px, py)
    local node, x, y, z = randomNodeAround(PED_NODES, pedGrid, px, py, CFG.PED_SPAWN_MIN, CFG.PED_SPAWN_MAX)
    if not node or visibleFromCamera(x, y, z) then return end
    local target = nextNode(PED_LINKS, node, nil)
    local tx, ty = nodePos(PED_NODES, target)
    local ped = createPed(PED_SKINS[math.random(#PED_SKINS)], x, y, z + 1, heading(tx - x, ty - y))
    if not ped then return end
    peds[ped] = { state = "WALK", node = target, prev = node, brave = math.random() < CFG.BRAVE_CHANCE, until_ = 0 }
    pedCount = pedCount + 1
    setWalking(ped, true, false)
end

local function startFlee(ped, from, duration)
    local s = peds[ped]
    if not s or s.state == "DEAD" then return end
    setPedAnimation(ped)
    s.state, s.threat, s.until_ = "FLEE", from, getTickCount() + (duration or math.random(8000, 12000))
    setWalking(ped, true, true)
end

local function startFight(ped, target)
    local s = peds[ped]
    if not s or s.state == "DEAD" then return end
    setPedAnimation(ped)
    s.state, s.threat, s.until_ = "FIGHT", target, getTickCount() + 20000
end

local function resumeWalk(ped, s)
    local x, y = getElementPosition(ped)
    local n = nearestNode(PED_NODES, pedGrid, x, y)
    if not n then return removePed(ped) end
    s.state, s.node, s.prev, s.threat = "WALK", n, nil, nil
    setPedControlState(ped, "fire", false)
    setWalking(ped, true, false)
end

local IDLE_ANIMS = {
    { "ped", "IDLE_chat" }, { "COP_AMBIENT", "Coplook_loop" }, { "ped", "XPRESSscratch" }, { "GANGS", "smkcig_prtl" },
}

local function updatePed(ped, s, now, px, py, pz)
    local x, y, z = getElementPosition(ped)

    if s.state == "WALK" then
        local tx, ty = nodePos(PED_NODES, s.node)
        if getDistanceBetweenPoints2D(x, y, tx, ty) < 1.6 then
            -- Llego al nodo: a veces se queda un rato
            if math.random() < 0.06 then
                s.state, s.until_ = "IDLE", now + math.random(4000, 9000)
                setWalking(ped, false)
                local a = IDLE_ANIMS[math.random(#IDLE_ANIMS)]
                setPedAnimation(ped, a[1], a[2], -1, true, false, false, false)
                return
            end
            s.prev, s.node = s.node, nextNode(PED_LINKS, s.node, s.prev)
            tx, ty = nodePos(PED_NODES, s.node)
        end
        local rot = heading(tx - x, ty - y)
        -- Si el jugador esta justo delante, lo rodea
        local dpx, dpy = px - x, py - y
        local distP = math.sqrt(dpx * dpx + dpy * dpy)
        if distP < 1.8 and math.abs(angleDiff(heading(dpx, dpy), rot)) < 40 then
            rot = rot + 50
        end
        setElementRotation(ped, 0, 0, rot, "default", true)
        setWalking(ped, true, false)

    elseif s.state == "IDLE" then
        if now > s.until_ then
            setPedAnimation(ped)
            s.state = "WALK"
            setWalking(ped, true, false)
        end

    elseif s.state == "FLEE" then
        if now > s.until_ or not isElement(s.threat) then return resumeWalk(ped, s) end
        local hx, hy = getElementPosition(s.threat)
        setElementRotation(ped, 0, 0, heading(x - hx, y - hy) + math.random(-20, 20), "default", true)
        setWalking(ped, true, true)

    elseif s.state == "FIGHT" then
        if not isElement(s.threat) or isPedDead(s.threat) or now > s.until_ then return resumeWalk(ped, s) end
        local hx, hy, hz = getElementPosition(s.threat)
        local d = getDistanceBetweenPoints3D(x, y, z, hx, hy, hz)
        if d > 25 then return resumeWalk(ped, s) end
        setElementRotation(ped, 0, 0, heading(hx - x, hy - y), "default", true)
        if d > 1.5 then
            setPedControlState(ped, "fire", false)
            setWalking(ped, true, d > 4)
        else
            setWalking(ped, false)
            -- golpes intermitentes
            setPedControlState(ped, "fire", not getPedControlState(ped, "fire"))
        end
    end
end

-- Golpes / disparos a un peaton
addEventHandler("onClientPedDamage", root, function(attacker)
    local s = peds[source]
    if not s or s.state == "DEAD" then return end
    if attacker and isElement(attacker) and getElementType(attacker) == "vehicle" then attacker = getVehicleController(attacker) end
    if not attacker or not isElement(attacker) then return end
    local weapon = getPedWeapon(attacker)
    if s.brave and (weapon == 0 or weapon == 1) and s.state ~= "FIGHT" then
        startFight(source, attacker)
    elseif s.state ~= "FIGHT" then
        startFlee(source, attacker)
    end
end)

addEventHandler("onClientPedWasted", root, function()
    local s = peds[source]
    if not s then return end
    s.state = "DEAD"
    setWalking(source, false)
    local ped = source
    setTimer(function() if peds[ped] then removePed(ped) end end, 15000, 1)
end)

-- Disparos del jugador: el que este cerca huye
addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon)
    if weapon < 22 then return end
    local x, y, z = getElementPosition(localPlayer)
    for ped, s in pairs(peds) do
        if s.state ~= "DEAD" and s.state ~= "FIGHT" then
            local px, py, pz = getElementPosition(ped)
            if getDistanceBetweenPoints3D(x, y, z, px, py, pz) < 35 then startFlee(ped, localPlayer) end
        end
    end
    for v, s in pairs(cars) do
        local vx, vy, vz = getElementPosition(v)
        if getDistanceBetweenPoints3D(x, y, z, vx, vy, vz) < 40 then s.state, s.until_ = "FLEE", getTickCount() + 10000 end
    end
end)

----------------------------------------------------------------
-- Trafico
----------------------------------------------------------------
local function removeCar(vehicle)
    local s = cars[vehicle]
    cars[vehicle] = nil
    carCount = carCount - 1
    if s and isElement(s.driver) then destroyElement(s.driver) end
    if isElement(vehicle) then destroyElement(vehicle) end
end

-- Direccion normalizada de a hacia b
local function dir(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return 0, 1, 0 end
    return dx / len, dy / len, len
end

----------------------------------------------------------------
-- Carriles: la red de GTA es la linea central de cada calle. Cada enlace
-- a->b tiene sus carriles en ese sentido (VEH_LANES, 0 = sentido prohibido)
-- y un desplazamiento a la derecha (VEH_OFFSET), sacados de los nodos de
-- navegacion de GTA SA. Enlaces nuevos del editor: 1 carril, 2.5 m.
----------------------------------------------------------------
local DEFAULT_OFFSET = 2.5

function getLaneInfo(a, b)
    local list = VEH_LINKS[a]
    if list then
        for k = 1, #list do
            if list[k] == b then
                local lanes = VEH_LANES[a] and VEH_LANES[a][k]
                local off = VEH_OFFSET[a] and VEH_OFFSET[a][k]
                return lanes or 1, off or DEFAULT_OFFSET
            end
        end
    end
    return 0, DEFAULT_OFFSET
end

local function canDrive(a, b) return getLaneInfo(a, b) > 0 end

local function isJunction(n)
    local list = VEH_LINKS[n]
    return list and #list >= 3
end

----------------------------------------------------------------
-- Rutas: A* sobre el grafo dirigido de carriles
----------------------------------------------------------------
local function heapPush(h, item, f)
    h.n = h.n + 1
    local i = h.n
    h[i] = { item, f }
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p][2] <= h[i][2] then break end
        h[p], h[i] = h[i], h[p]
        i = p
    end
end

local function heapPop(h)
    if h.n == 0 then return nil end
    local top = h[1]
    h[1] = h[h.n]
    h[h.n] = nil
    h.n = h.n - 1
    local i = 1
    while true do
        local l, r, m = i * 2, i * 2 + 1, i
        if l <= h.n and h[l][2] < h[m][2] then m = l end
        if r <= h.n and h[r][2] < h[m][2] then m = r end
        if m == i then break end
        h[m], h[i] = h[i], h[m]
        i = m
    end
    return top[1]
end

local MAX_EXPANSIONS = 3000

-- Devuelve la lista de nodos desde "start" (sin incluirlo) hasta "goal", llegando a start desde "from"
local function findRoute(from, start, goal)
    local gx, gy = nodePos(VEH_NODES, goal)
    local open = { n = 0 }
    local cost, parent, closed = { [start] = 0 }, { [start] = from }, {}
    heapPush(open, start, 0)
    local expansions = 0
    while open.n > 0 do
        local cur = heapPop(open)
        if cur == goal then
            local route = {}
            while cur ~= start do
                table.insert(route, 1, cur)
                cur = parent[cur]
            end
            return route
        end
        if not closed[cur] then
            closed[cur] = true
            expansions = expansions + 1
            if expansions > MAX_EXPANSIONS then return nil end
            local cx, cy = nodePos(VEH_NODES, cur)
            for _, n in ipairs(VEH_LINKS[cur] or {}) do
                -- sentido permitido y sin media vuelta en el nodo de salida
                if not closed[n] and n ~= parent[cur] and canDrive(cur, n) then
                    local nx, ny = nodePos(VEH_NODES, n)
                    local g = cost[cur] + getDistanceBetweenPoints2D(cx, cy, nx, ny)
                    if not cost[n] or g < cost[n] then
                        cost[n], parent[n] = g, cur
                        heapPush(open, n, g + getDistanceBetweenPoints2D(nx, ny, gx, gy))
                    end
                end
            end
        end
    end
    return nil
end

-- Destino aleatorio a 250-700 m (nodo vial con salida)
local function pickDestination(x, y)
    for _ = 1, 8 do
        local angle = math.random() * math.pi * 2
        local dist = 250 + math.random() * 450
        local n = nearestNode(VEH_NODES, vehGrid, x + math.cos(angle) * dist, y + math.sin(angle) * dist)
        if n then return n end
    end
end

-- Salida al azar (si no hay ruta): respeta sentidos y evita giros en U
local function chooseExit(node, prev)
    local px, py = nodePos(VEH_NODES, prev)
    local nx, ny = nodePos(VEH_NODES, node)
    local d1x, d1y = dir(px, py, nx, ny)
    local options = {}
    for _, n in ipairs(VEH_LINKS[node] or {}) do
        if n ~= prev and canDrive(node, n) then
            local qx, qy = nodePos(VEH_NODES, n)
            local d2x, d2y = dir(nx, ny, qx, qy)
            if d1x * d2x + d1y * d2y > -0.75 then options[#options + 1] = n end
        end
    end
    if #options == 0 then return canDrive(node, prev) and prev or nil end
    return options[math.random(#options)]
end

-- Presupuesto de calculos de ruta por tick (rendimiento)
local routeBudget = 0

local function nextOnRoute(s)
    if s.route and #s.route > 0 then
        local n = table.remove(s.route, 1)
        -- la ruta puede haber quedado invalida (editor): comprobar
        if canDrive(s.node, n) then return n end
        s.route = nil
    end
    -- sin ruta: calcula una nueva hacia un destino (si queda presupuesto)
    if routeBudget > 0 then
        routeBudget = routeBudget - 1
        local x, y = nodePos(VEH_NODES, s.node)
        local goal = pickDestination(x, y)
        local route = goal and goal ~= s.node and findRoute(s.prev, s.node, goal)
        if route and #route > 0 then
            s.route = route
            return table.remove(s.route, 1)
        end
    end
    return chooseExit(s.node, s.prev)
end

----------------------------------------------------------------
-- Puntos de conduccion: carril de entrada -> curva Bezier -> carril de salida
----------------------------------------------------------------
local function intersect(px, py, dx, dy, qx, qy, ex, ey)
    local den = dx * ey - dy * ex
    if math.abs(den) < 0.05 then return nil end
    local t = ((qx - px) * ey - (qy - py) * ex) / den
    if t < 0 or t > 30 then return nil end
    return px + dx * t, py + dy * t
end

local function planSegment(s)
    local A, B = s.prev, s.node
    local C = nextOnRoute(s)
    if not C then return false end
    local ax, ay = nodePos(VEH_NODES, A)
    local bx, by, bz = nodePos(VEH_NODES, B)
    local cx, cy = nodePos(VEH_NODES, C)
    local d1x, d1y, len1 = dir(ax, ay, bx, by)
    local d2x, d2y, len2 = dir(bx, by, cx, cy)
    local _, off1 = getLaneInfo(A, B)
    local _, off2 = getLaneInfo(B, C)
    local turn = math.deg(math.acos(math.max(-1, math.min(1, d1x * d2x + d1y * d2y))))
    -- radio de la curva: mayor en cruces para que el giro sea amplio y claro
    local R = math.min(isJunction(B) and 12 or 9, len1 * 0.48, len2 * 0.48)
    if C == A then R = math.min(R, 4) end
    local junction = isJunction(B) and B or nil

    local wp = s.wp
    local ex, ey = bx - d1x * R + d1y * off1, by - d1y * R - d1x * off1
    local xx, xy = bx + d2x * R + d2y * off2, by + d2y * R - d2x * off2
    wp[#wp + 1] = { ex, ey, bz, 0, junction }
    if turn < 10 then
        wp[#wp + 1] = { xx, xy, bz, 0, junction }
    else
        local qx, qy = intersect(ex, ey, d1x, d1y, xx, xy, -d2x, -d2y)
        if not qx then qx, qy = bx + (d1y * off1 + d2y * off2) / 2, by - (d1x * off1 + d2x * off2) / 2 end
        local steps = turn > 50 and 7 or 5
        for i = 1, steps do
            local t = i / steps
            local u = 1 - t
            wp[#wp + 1] = { u * u * ex + 2 * u * t * qx + t * t * xx, u * u * ey + 2 * u * t * qy + t * t * xy, bz, turn, junction }
        end
    end
    s.prev, s.node = B, C
    return true
end

----------------------------------------------------------------
-- Reserva de cruces (solo local): pasa un auto a la vez por orden de llegada
----------------------------------------------------------------
local junctionLock = {}    -- [nodo] = { vehicle, tick }
local LOCK_TIMEOUT = 7000

local function tryLock(node, vehicle, now)
    local l = junctionLock[node]
    if l and l[1] ~= vehicle and isElement(l[1]) and cars[l[1]] and now - l[2] < LOCK_TIMEOUT then
        return false
    end
    junctionLock[node] = { vehicle, l and l[1] == vehicle and l[2] or now }
    return true
end

local function releaseLocks(vehicle)
    for node, l in pairs(junctionLock) do
        if l[1] == vehicle then junctionLock[node] = nil end
    end
end

----------------------------------------------------------------
-- Aparicion y reenganche
----------------------------------------------------------------
local function laneStart(prev, node)
    local ax, ay, az = nodePos(VEH_NODES, prev)
    local bx, by = nodePos(VEH_NODES, node)
    local dx, dy = dir(ax, ay, bx, by)
    local _, off = getLaneInfo(prev, node)
    return ax + dy * off, ay - dx * off, az, dx, dy
end

-- Nodo + sentido mas cercano al auto y alineado con su rumbo (para volver a la ruta)
local function nearestLane(x, y, fx, fy)
    local best, bestTarget, bestScore = nil, nil, math.huge
    local cx, cy = math.floor(x / 100), math.floor(y / 100)
    for ox = -1, 1 do
        for oy = -1, 1 do
            local cell = vehGrid[(cx + ox) * 1000 + (cy + oy)]
            if cell then
                for _, n in ipairs(cell) do
                    local nx, ny = nodePos(VEH_NODES, n)
                    local d = getDistanceBetweenPoints2D(x, y, nx, ny)
                    if d < 60 then
                        for _, m in ipairs(VEH_LINKS[n] or {}) do
                            if canDrive(n, m) then
                                local mx, my = nodePos(VEH_NODES, m)
                                local dx, dy = dir(nx, ny, mx, my)
                                -- distancia + penalizacion si el sentido no coincide con el rumbo
                                local score = d + (1 - (dx * fx + dy * fy)) * 25
                                if score < bestScore then best, bestTarget, bestScore = n, m, score end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestTarget
end

local function spawnCar(px, py)
    local node, x, y, z = randomNodeAround(VEH_NODES, vehGrid, px, py, CFG.CAR_SPAWN_MIN, CFG.CAR_SPAWN_MAX)
    if not node or visibleFromCamera(x, y, z) then return end
    local target
    for _, n in ipairs(VEH_LINKS[node] or {}) do
        if canDrive(node, n) then target = n break end
    end
    if not target then return end
    local sx, sy, sz, dx, dy = laneStart(node, target)

    local vehicle = createVehicle(CAR_MODELS[math.random(#CAR_MODELS)], sx, sy, sz + 1.2, 0, 0, heading(dx, dy))
    if not vehicle then return end
    local driver = createPed(DRIVER_SKINS[math.random(#DRIVER_SKINS)], sx, sy, sz + 2)
    if not driver then destroyElement(vehicle) return end
    warpPedIntoVehicle(driver, vehicle)
    setVehicleEngineState(vehicle, true)
    if isNight() then setVehicleOverrideLights(vehicle, 2) end

    cars[vehicle] = {
        driver = driver, prev = node, node = target, wp = {},
        state = "DRIVE", blockedSince = 0, stuckSince = 0, until_ = 0, recoverUntil = 0,
    }
    carCount = carCount + 1
end

-- Vuelve al carril mas cercano y descarta la ruta (se recalcula desde ahi)
local function reattach(vehicle, s, teleport)
    releaseLocks(vehicle)
    local x, y = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    local n, target = nearestLane(x, y, m[2][1], m[2][2])
    if not n then return removeCar(vehicle) end
    s.prev, s.node, s.wp, s.route = n, target, {}, nil
    if teleport then
        local sx, sy, sz, dx, dy = laneStart(n, target)
        setElementPosition(vehicle, sx, sy, sz + 1.2)
        setElementRotation(vehicle, 0, 0, heading(dx, dy))
        setElementVelocity(vehicle, 0, 0, 0)
    end
end

----------------------------------------------------------------
-- Conduccion
----------------------------------------------------------------
local function setPedal(driver, accel, brake)
    setPedControlState(driver, "accelerate", accel)
    setPedControlState(driver, "brake_reverse", brake)
end

local function steerTo(driver, value)
    value = math.max(-1, math.min(1, value))
    setPedAnalogControlState(driver, "vehicle_left", value > 0 and value or 0)
    setPedAnalogControlState(driver, "vehicle_right", value < 0 and -value or 0)
end

-- Rayo desde el frente del auto en un angulo (grados, + = izquierda).
-- wall = true: solo paredes/edificios (bigotes); false: vehiculos, peatones y objetos.
-- Los bigotes NO ven autos: si los vieran, un auto del carril de al lado
-- empujaria al nuestro hacia la acera.
local function ray(vehicle, m, angle, reach, wall)
    local fx, fy = m[2][1], m[2][2]
    if angle ~= 0 then
        local r = math.rad(angle)
        local c, sn = math.cos(r), math.sin(r)
        fx, fy = fx * c - fy * sn, fx * sn + fy * c
    end
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local sx, sy, sz = x + m[2][1] * 2.4, y + m[2][2] * 2.4, z + 0.2
    local hit, hx, hy, _, el = processLineOfSight(sx, sy, sz, sx + fx * reach, sy + fy * reach, sz,
        wall, not wall, not wall, not wall, false, true, false, false, vehicle)
    if hit then return true, el, getDistanceBetweenPoints2D(sx, sy, hx, hy) end
    return false
end

local function speedOf(el)
    local vx, vy, vz = getElementVelocity(el)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

local function updateCar(vehicle, s, now)
    local driver = s.driver
    if not isElement(driver) or isPedDead(driver) or getVehicleController(vehicle) ~= driver then
        -- conductor muerto o sacado del auto: el auto queda abandonado y se borra al alejarse
        if s.state ~= "ABANDONED" then releaseLocks(vehicle) end
        s.state = "ABANDONED"
        return
    end
    if s.state == "ABANDONED" then return end

    local speed = speedOf(vehicle)
    local x, y = getElementPosition(vehicle)
    local _, _, rz = getElementRotation(vehicle)
    local m = getElementMatrix(vehicle)

    -- Rescate: marcha atras con el volante al reves; al terminar, reengancha el carril
    if now < s.recoverUntil then
        setPedControlState(driver, "horn", false)
        steerTo(driver, -(s.recoverSteer or 0))
        setPedal(driver, false, true)
        s.needReattach = true
        return
    end
    if s.needReattach then
        s.needReattach = nil
        reattach(vehicle, s, false)
    end

    -- Cola de puntos: siempre algunos por delante (planifica cruce a cruce)
    local wp = s.wp
    local guard = 0
    while #wp < 10 and guard < 4 do
        if not planSegment(s) then break end
        guard = guard + 1
    end
    if #wp == 0 then return reattach(vehicle, s, not isElementOnScreen(vehicle)) end

    -- Muy lejos de su ruta (empujado, chocado): reengancha y recalcula
    if getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2]) > 30 then
        return reattach(vehicle, s, false)
    end

    -- Pure pursuit: descarta los puntos ya alcanzados y apunta al primero por delante
    local inCurve = wp[1][4] > 20
    local lookahead = (inCurve and 3 or 5) + speed * (inCurve and 0.06 or 0.1)
    while #wp > 1 and getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2]) < lookahead do
        local passed = table.remove(wp, 1)
        -- libera el cruce cuando ya no quedan puntos de el
        if passed[5] and (not wp[1][5] or wp[1][5] ~= passed[5]) then
            local l = junctionLock[passed[5]]
            if l and l[1] == vehicle then junctionLock[passed[5]] = nil end
        end
    end
    local tx, ty = wp[1][1], wp[1][2]
    local diff = angleDiff(heading(tx - x, ty - y), rz)

    -- Lo que viene: mayor giro y cruce en los proximos ~30 m
    local upcoming, dist, lx, ly, junctionAhead, junctionDist = 0, 0, x, y, nil, 0
    for i = 1, math.min(#wp, 12) do
        dist = dist + getDistanceBetweenPoints2D(lx, ly, wp[i][1], wp[i][2])
        lx, ly = wp[i][1], wp[i][2]
        if dist > 30 then break end
        if wp[i][4] > upcoming then upcoming = wp[i][4] end
        if wp[i][5] and not junctionAhead then junctionAhead, junctionDist = wp[i][5], dist end
    end

    -- Sensores: frente (vehiculos/peatones/objetos) y bigotes laterales (tambien paredes)
    local frontHit, obstacle, gap = ray(vehicle, m, 0, 8 + speed * 0.3, false)
    local wallFront = ray(vehicle, m, 0, 3 + speed * 0.08, true)
    local leftHit = ray(vehicle, m, 25, 3.5 + speed * 0.06, true)
    local rightHit = ray(vehicle, m, -25, 3.5 + speed * 0.06, true)

    local steer = diff / (inCurve and 18 or 25)
    if leftHit and not rightHit then steer = steer - 0.25 end
    if rightHit and not leftHit then steer = steer + 0.25 end
    steerTo(driver, steer)

    if s.state == "FLEE" then
        setPedControlState(driver, "horn", false)
        setPedal(driver, not obstacle or speed < 5, (obstacle ~= nil or wallFront) and speed > 20)
        if now > s.until_ then s.state = "DRIVE" end
        return
    end

    -- Velocidad objetivo
    local target = CFG.CAR_SPEED
    if upcoming > 70 then target = 14 elseif upcoming > 40 then target = 20 elseif upcoming > 20 then target = 30 end
    if math.abs(diff) > 45 then target = math.min(target, 12) end
    if wallFront or leftHit or rightHit or s.avoiding then target = math.min(target, 15) end

    -- Cruce: pide paso; si otro auto lo tiene, espera antes de entrar
    local yielding = false
    if junctionAhead and junctionDist < 14 then
        if not tryLock(junctionAhead, vehicle, now) then
            yielding = true
            target = junctionDist > 7 and 8 or 0
        end
    end

    -- Distancia de seguimiento con lo que tenga delante
    local isPlayerThing = obstacle and (obstacle == localPlayer or obstacle == getPedOccupiedVehicle(localPlayer))
    if obstacle then
        local otherSpeed = isElement(obstacle) and getElementType(obstacle) ~= "ped" and speedOf(obstacle) or 0
        local safeGap = 4 + speed * 0.12
        if gap and gap < safeGap then
            target = 0
        else
            target = math.min(target, otherSpeed + 3)
        end
        if target <= 1 and speed < 3 then
            if s.blockedSince == 0 then s.blockedSince = now end
            local waited = now - s.blockedSince
            if isPlayerThing and waited > 1200 then
                setPedControlState(driver, "horn", (math.floor(now / 500) % 2) == 0)   -- bocina intermitente
            end
            -- obstaculo quieto mucho rato (no el cruce): esquiva por la izquierda
            if waited > 5000 and not s.avoiding and otherSpeed < 1 and not yielding then
                s.avoiding, s.until_ = true, now + 3500
                local fx, fy = m[2][1], m[2][2]
                for i = 1, math.min(#wp, 4) do
                    wp[i][1], wp[i][2] = wp[i][1] - fy * 4, wp[i][2] + fx * 4
                end
                s.blockedSince = now
            end
        end
        s.state = "FOLLOW"
    else
        s.blockedSince = 0
        setPedControlState(driver, "horn", false)
        s.state = yielding and "YIELD" or "DRIVE"
    end
    if s.avoiding and now > s.until_ then s.avoiding = nil end

    setPedal(driver, speed < target - 1, speed > target + 6 or (target == 0 and speed > 1))

    -- Atascado sin motivo (pared, otro auto cruzado): marcha atras y reenganche
    local waiting = yielding or (obstacle and target == 0)
    if speed < 2 and not waiting then
        if s.stuckSince == 0 then s.stuckSince = now end
        if now - s.stuckSince > 2500 then
            s.recoverUntil, s.recoverSteer, s.stuckSince = now + 2000, steer, 0
            s.stuckCount = (s.stuckCount or 0) + 1
            if s.stuckCount > 3 and not isElementOnScreen(vehicle) then
                reattach(vehicle, s, true)
                s.stuckCount = 0
            end
        end
    else
        s.stuckSince = 0
    end
end

-- Choques entre autos de la poblacion: maniobra corta y reenganche al carril
addEventHandler("onClientVehicleCollision", root, function(hit, force)
    local s = cars[source]
    if not s or s.state == "ABANDONED" or not hit or force < 150 then return end
    if getElementType(hit) == "vehicle" and cars[hit] then
        local now = getTickCount()
        if now > s.recoverUntil + 1500 then
            -- el que va detras retrocede; el de delante sigue
            local m = getElementMatrix(source)
            local hx, hy = getElementPosition(hit)
            local x, y = getElementPosition(source)
            local ahead = (hx - x) * m[2][1] + (hy - y) * m[2][2] > 0
            if ahead then
                s.recoverUntil, s.recoverSteer = now + 1200, 0
            else
                s.needReattach = true
            end
        end
    end
end)

-- Presupuesto de rutas A*: se renueva en cada tick de conduccion
function refillRouteBudget()
    routeBudget = 1   -- como maximo una ruta A* por tick (~5 ms en el peor caso)
end

-- Si el jugador choca o dispara a un auto, el conductor se asusta y acelera
addEventHandler("onClientVehicleDamage", root, function(attacker)
    local s = cars[source]
    if not s or s.state == "ABANDONED" then return end
    if attacker == localPlayer or attacker == getPedOccupiedVehicle(localPlayer) then
        s.state, s.until_ = "FLEE", getTickCount() + 8000
        setPedControlState(s.driver, "horn", true)
        setTimer(function() if isElement(s.driver) then setPedControlState(s.driver, "horn", false) end end, 1200, 1)
    end
end)

-- Bajarse de un auto: el jugador puede robarlo; el auto deja de ser trafico
addEventHandler("onClientVehicleEnter", root, function(player, seat)
    local s = cars[source]
    if s and player == localPlayer and seat == 0 then
        if isElement(s.driver) then destroyElement(s.driver) end
        s.state = "ABANDONED"
    end
end)

----------------------------------------------------------------
-- Bucles (temporizadores baratos, nada en onClientRender)
----------------------------------------------------------------
local function clearAll()
    for ped in pairs(peds) do if isElement(ped) then destroyElement(ped) end end
    for v, s in pairs(cars) do
        if isElement(s.driver) then destroyElement(s.driver) end
        if isElement(v) and getVehicleController(v) ~= localPlayer then destroyElement(v) end
    end
    peds, cars, pedCount, carCount = {}, {}, 0, 0
end

local function spawnTick()
    if not enabled or not getElementData(localPlayer, "rp:characterId") or not playerIsActive() then
        if pedCount > 0 or carCount > 0 then clearAll() end
        return
    end
    local px, py, pz = getElementPosition(localPlayer)

    -- Despawn de lo lejano (y de lo que no se ve)
    for ped in pairs(peds) do
        if not isElement(ped) then
            removePed(ped)
        else
            local x, y = getElementPosition(ped)
            if getDistanceBetweenPoints2D(px, py, x, y) > CFG.PED_DESPAWN then removePed(ped) end
        end
    end
    for v, s in pairs(cars) do
        if not isElement(v) then
            removeCar(v)
        else
            local x, y = getElementPosition(v)
            local far = getDistanceBetweenPoints2D(px, py, x, y) > CFG.CAR_DESPAWN
            if far and getVehicleController(v) ~= localPlayer then removeCar(v) end
        end
    end

    -- Spawn hasta el limite (uno por tick para repartir el coste)
    local night = isNight()
    if pedCount < (night and CFG.MAX_PEDS_NIGHT or CFG.MAX_PEDS) then spawnPed(px, py) end
    if carCount < (night and CFG.MAX_CARS_NIGHT or CFG.MAX_CARS) then spawnCar(px, py) end
end

local function pedTick()
    if pedCount == 0 then return end
    local now = getTickCount()
    local px, py, pz = getElementPosition(localPlayer)
    local aimTarget = getPedTarget(localPlayer)
    for ped, s in pairs(peds) do
        if isElement(ped) and s.state ~= "DEAD" then
            -- Le apuntan con un arma de fuego: huye
            if aimTarget == ped and getPedWeapon(localPlayer) >= 22 and s.state ~= "FLEE" and s.state ~= "FIGHT" then
                startFlee(ped, localPlayer)
            end
            if isElementStreamedIn(ped) then updatePed(ped, s, now, px, py, pz) end
        end
    end
end

local function carTick()
    if carCount == 0 then return end
    refillRouteBudget()
    local now = getTickCount()
    for v, s in pairs(cars) do
        if isElement(v) and isElementStreamedIn(v) then updateCar(v, s, now) end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    pedGrid = buildGrid(PED_NODES, PED_LINKS)
    vehGrid = buildGrid(VEH_NODES, VEH_LINKS)
    setPedsLODDistance(60)
    setTimer(spawnTick, CFG.SPAWN_TICK, 0)
    setTimer(pedTick, CFG.PED_TICK, 0)
    setTimer(carTick, CFG.CAR_TICK, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, clearAll)

-- Usadas por el editor de nodos (c_editor.lua) al cambiar el grafo
function rebuildCitizenGrids()
    pedGrid = buildGrid(PED_NODES, PED_LINKS)
    vehGrid = buildGrid(VEH_NODES, VEH_LINKS)
end

function clearCitizens()
    clearAll()
end

function setCitizensEnabled(state)
    enabled = state and true or false
    if not enabled then clearAll() end
end

addCommandHandler("poblacion", function()
    enabled = not enabled
    if not enabled then clearAll() end
    exports.rp_notify:notify(enabled and "Poblacion activada." or "Poblacion desactivada.", "info")
end)

-- Diagnostico: /poblacioninfo
addCommandHandler("poblacioninfo", function()
    outputChatBox(("Peatones: %d  Autos: %d  Nodos: %d peatonales, %d viales"):format(pedCount, carCount, #PED_NODES / 3, #VEH_NODES / 3), 120, 200, 255)
end)
