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
    MAX_CARS = 16, MAX_CARS_NIGHT = 9,
    MAX_CARS_WANTED = 6,  -- autos extra durante una persecucion (mas trafico que esquivar)
    CAR_SPAWN_AHEAD = 0.7, -- yendo rapido, proporcion de autos que aparecen por delante
    PED_SPAWN_MIN = 40, PED_SPAWN_MAX = 80, PED_DESPAWN = 105,
    CAR_SPAWN_MIN = 70, CAR_SPAWN_MAX = 130, CAR_DESPAWN = 170,
    PED_TICK = 300,      -- ms entre decisiones de peatones
    CAR_TICK = 80,       -- ms entre decisiones de conductores (volante + asistencia de direccion)
    SPAWN_TICK = 1000,
    CAR_SPEED = 50,      -- km/h de crucero
    CORNER_SPEED = 20,
    BRAVE_CHANCE = 0.3,  -- probabilidad de que un peaton responda a los golpes
}

----------------------------------------------------------------
-- Poblacion segun la zona (al estilo de popcycle.dat de GTA SA)
----------------------------------------------------------------
local POP = {
    default = {
        peds = { 7, 14, 15, 17, 20, 21, 22, 23, 24, 26, 29, 32, 34, 35, 37, 43, 44, 46, 47, 48, 57, 58, 59, 60,
            9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 69, 76, 88, 89, 91, 93, 141, 148, 150, 151, 157, 169 },
        cars = { 400, 401, 404, 405, 410, 418, 421, 426, 436, 445, 458, 466, 467, 474, 479, 491, 492, 496,
            507, 516, 517, 518, 526, 527, 529, 540, 542, 546, 547, 549, 550, 551, 554, 566, 585, 589, 600 },
    },
    ghetto = {
        peds = { 7, 14, 15, 21, 22, 28, 29, 30, 47, 66, 67, 79, 134, 135, 136, 143, 144, 176, 180, 183, 13, 41, 56, 63, 69, 190, 195, 207, 238 },
        cars = { 412, 534, 535, 536, 566, 567, 575, 576, 474, 467, 401, 410, 436, 466, 492, 517, 518, 542, 549, 600, 404, 479 },
    },
    rich = {
        peds = { 17, 20, 29, 40, 55, 59, 69, 76, 91, 93, 141, 147, 148, 150, 169, 171, 187, 189, 216, 219, 224, 225, 226, 227, 228, 240 },
        cars = { 402, 411, 415, 429, 451, 477, 506, 541, 558, 559, 560, 562, 565, 580, 587, 602, 603, 445, 507, 421, 426, 551, 579, 400, 489 },
    },
    industrial = {
        peds = { 16, 27, 50, 153, 155, 167, 179, 201, 206, 260, 261, 268, 7, 20, 44 },
        cars = { 413, 414, 422, 440, 456, 478, 482, 498, 499, 543, 554, 578, 600, 418, 459, 609 },
    },
}

local ZONE_PROFILE = {
    ["Ganton"] = "ghetto", ["Idlewood"] = "ghetto", ["East Los Santos"] = "ghetto", ["Willowfield"] = "ghetto",
    ["El Corona"] = "ghetto", ["Jefferson"] = "ghetto", ["Glen Park"] = "ghetto", ["Los Flores"] = "ghetto",
    ["East Beach"] = "ghetto", ["Playa del Seville"] = "ghetto", ["Little Mexico"] = "ghetto", ["Las Colinas"] = "ghetto",
    ["Rodeo"] = "rich", ["Richman"] = "rich", ["Mulholland"] = "rich", ["Vinewood"] = "rich", ["Temple"] = "rich",
    ["Market"] = "rich", ["Marina"] = "rich", ["Santa Maria Beach"] = "rich", ["Verona Beach"] = "rich",
    ["Mulholland Intersection"] = "rich",
    ["Ocean Docks"] = "industrial", ["Los Santos International"] = "industrial", ["Commerce"] = "industrial",
    ["Verdant Bluffs"] = "industrial", ["Linden Side"] = "industrial",
}

-- Bandas por barrio: parte de los peatones son de la banda local
local GANGS = {
    ["Ganton"] = { 105, 106, 107 },                                             -- Grove Street
    ["Idlewood"] = { 102, 103, 104 }, ["Jefferson"] = { 102, 103, 104 }, ["Glen Park"] = { 102, 103, 104 }, -- Ballas
    ["Las Colinas"] = { 108, 109, 110 }, ["Los Flores"] = { 108, 109, 110 },   -- Vagos
    ["El Corona"] = { 114, 115, 116 }, ["Little Mexico"] = { 114, 115, 116 },  -- Aztecas
}

local function pick(list) return list[math.random(#list)] end

local function population(x, y, z)
    local zone = getZoneName(x, y, z, false)
    return POP[ZONE_PROFILE[zone] or "default"], zone
end

local function pickPedSkin(x, y, z)
    local pop, zone = population(x, y, z)
    local gang = GANGS[zone]
    -- de noche hay mas presencia de bandas
    if gang and math.random() < ((getTime() >= 20 or getTime() < 6) and 0.5 or 0.3) then return pick(gang) end
    return pick(pop.peds)
end

-- Motos (como en popcycle de GTA SA, una parte del trafico va en moto)
local BIKES = {
    default = { 461, 462, 463, 468, 521, 581, 586 },
    ghetto = { 462, 463, 468, 586 },
    rich = { 461, 521, 522, 581 },
    industrial = { 462, 463, 468, 586 },
}
local BIKE_CHANCE = 0.15

-- Patrullas de la policia en el trafico (sin persecucion: patrullan con las
-- luces apagadas). Modelo y agente segun la ciudad; tambien motos de policia.
local POLICE_CHANCE = 0.08       -- proporcion de autos de policia en el trafico
local POLICE_CHANCE_WANTED = 0.4 -- con el jugador buscado
local POLICE_BIKE_CHANCE = 0.35  -- de esas patrullas, cuantas son motos (HPV1000)
local POLICE_BY_CITY = {
    ["Los Santos"] = { 596, 280 }, ["San Fierro"] = { 597, 281 }, ["Las Venturas"] = { 598, 282 },
}
local POLICE_RURAL = { 599, 283 }
local POLICE_BIKE = { 523, 284 }

local function pickCarModel(x, y, z)
    if math.random() < BIKE_CHANCE then
        local zone = getZoneName(x, y, z, false)
        return pick(BIKES[ZONE_PROFILE[zone] or "default"])
    end
    return pick(population(x, y, z).cars)
end

-- Devuelve modelo y skin de una patrulla, o nil si este auto no es de policia
local function playerWanted()
    return (tonumber(getElementData(localPlayer, "rp:wanted")) or 0) > 0
end

local function pickPolice(x, y, z)
    -- Con estrellas aparecen muchas mas patrullas (GTA genera policia al estar buscado)
    if math.random() >= (playerWanted() and POLICE_CHANCE_WANTED or POLICE_CHANCE) then return nil end
    if math.random() < POLICE_BIKE_CHANCE then return POLICE_BIKE[1], POLICE_BIKE[2] end
    local p = POLICE_BY_CITY[getZoneName(x, y, z, true)] or POLICE_RURAL
    return p[1], p[2]
end

-- Personalidad del conductor: prudente, normal o agresivo (velocidad y distancia)
local function newDriverStyle()
    local r = math.random()
    local base = r < 0.2 and { speed = 0.8, gap = 1.4 } or r > 0.85 and { speed = 1.2, gap = 0.75 } or { speed = 1.0, gap = 1.0 }
    return { speed = base.speed * (0.95 + math.random() * 0.1), gap = base.gap }
end

local function pickDriverSkin(x, y, z)
    local pop = population(x, y, z)
    return pick(pop.peds)
end

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
    local ped = createPed(pickPedSkin(x, y, z), x, y, z + 1, heading(tx - x, ty - y))
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

-- Semaforo al final del tramo a -> b (0 = no hay)
local function getLight(a, b)
    local list = VEH_LINKS[a]
    if list and VEH_LIGHT and VEH_LIGHT[a] then
        for k = 1, #list do
            if list[k] == b then return VEH_LIGHT[a][k] or 0 end
        end
    end
    return 0
end

-- Estado de los semaforos de GTA (getTrafficLightState):
-- 0 N-S verde | 1 N-S amarillo | 2 todo rojo | 3 E-O verde | 4 E-O amarillo | 5 todo rojo
-- 6/7/9 intermitente o apagado (se pasa con precaucion) | 8 todo rojo
local function lightFor(axis)
    local st = getTrafficLightState()
    if st == 6 or st == 7 or st == 9 then return "green" end
    if axis == "ns" then
        if st == 0 then return "green" elseif st == 1 then return "yellow" end
    else
        if st == 3 then return "green" elseif st == 4 then return "yellow" end
    end
    return "red"
end

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

-- Eleccion en cada cruce, como GTA SA: al azar entre los enlaces permitidos
-- (respeta sentidos unicos), con preferencia por seguir recto y sin giros en U.
-- Peso: recto x4, giro suave x2, giro cerrado x1.
-- Devuelve las salidas posibles ordenadas al azar segun su peso (la primera es la
-- elegida; las demas son alternativas si la primera resulta bloqueada).
local function exitCandidates(node, prev)
    local px, py = nodePos(VEH_NODES, prev)
    local nx, ny = nodePos(VEH_NODES, node)
    local d1x, d1y = dir(px, py, nx, ny)
    local options = {}
    -- solo enlaces viales reales que salen de este nodo, en un sentido permitido
    for _, n in ipairs(VEH_LINKS[node] or {}) do
        if n ~= prev and canDrive(node, n) then
            local qx, qy = nodePos(VEH_NODES, n)
            local d2x, d2y = dir(nx, ny, qx, qy)
            local dot = d1x * d2x + d1y * d2y
            if dot > -0.75 then
                local w = dot > 0.85 and 4 or dot > 0.3 and 2 or 1
                -- orden aleatorio ponderado (Efraimidis-Spirakis): mayor peso -> antes
                options[#options + 1] = { n, math.random() ^ (1 / w) }
            end
        end
    end
    table.sort(options, function(a, b) return a[2] > b[2] end)
    local list = {}
    for i, o in ipairs(options) do list[i] = o[1] end
    if #list == 0 and canDrive(node, prev) then list[1] = prev end   -- calle sin salida
    return list
end

local function chooseExit(node, prev)
    return exitCandidates(node, prev)[1]
end

-- Una maniobra es valida si su recorrido no atraviesa edificios ni muros
-- (si la colision de la zona aun no esta cargada, se acepta).
local function maneuverClear(pts, sx, sy, sz)
    local lx, ly, lz = sx, sy, sz
    for i = 1, #pts, 2 do
        local p = pts[i]
        if lx and not isLineOfSightClear(lx, ly, lz + 1.0, p[1], p[2], p[3] + 1.0, true, false, false, false, false, true, false) then
            return false
        end
        lx, ly, lz = p[1], p[2], p[3]
    end
    local p = pts[#pts]
    return isLineOfSightClear(lx, ly, lz + 1.0, p[1], p[2], p[3] + 1.0, true, false, false, false, false, true, false)
end

-- Sin destinos lejanos ni A*: cada cruce se decide localmente (coste casi nulo).
-- findRoute queda disponible para usos futuros (persecuciones, taxis...).
local routeBudget = 0

local function nextOnRoute(s)
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

-- Puntos de la maniobra A -> B -> C: E (fin del carril de entrada), la curva
-- Bezier cuadratica hasta X (inicio del carril de salida). Cada punto:
-- { x, y, z, giro, cruce }. Tambien la usa el editor para dibujar las curvas.
function computeTurnPoints(A, B, C)
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

    local pts = {}
    local ex, ey = bx - d1x * R + d1y * off1, by - d1y * R - d1x * off1
    local xx, xy = bx + d2x * R + d2y * off2, by + d2y * R - d2x * off2
    -- Si el tramo termina en un semaforo, E es la linea de detencion (campo 6 = eje)
    local axis = nil
    if getLight(A, B) > 0 then axis = math.abs(d1x) > math.abs(d1y) and "ew" or "ns" end
    pts[1] = { ex, ey, bz, 0, junction, axis }
    if turn < 10 then
        pts[2] = { xx, xy, bz, 0, junction }
    else
        local qx, qy = intersect(ex, ey, d1x, d1y, xx, xy, -d2x, -d2y)
        if not qx then qx, qy = bx + (d1y * off1 + d2y * off2) / 2, by - (d1x * off1 + d2x * off2) / 2 end
        local steps = math.max(5, math.ceil(turn / 10))
        for i = 1, steps do
            local t = i / steps
            local u = 1 - t
            pts[#pts + 1] = { u * u * ex + 2 * u * t * qx + t * t * xx, u * u * ey + 2 * u * t * qy + t * t * xy, bz, turn, junction }
        end
    end
    return pts, turn
end

local STEP = 6   -- metros entre puntos en los tramos rectos (seguimiento preciso del carril)

local function planSegment(s)
    local A, B = s.prev, s.node
    -- elige la salida y comprueba que su curva no atraviese muros; si lo hace,
    -- prueba la siguiente opcion (nunca "sigue recto" por un camino que no existe)
    local candidates = exitCandidates(B, A)
    if #candidates == 0 then return false end
    local bx0, by0, bz0 = nodePos(VEH_NODES, B)
    local C, pts = nil, nil
    for _, cand in ipairs(candidates) do
        local p = computeTurnPoints(A, B, cand)
        if maneuverClear(p, p[1][1], p[1][2], p[1][3]) then C, pts = cand, p break end
    end
    if not C then
        C = candidates[1]
        pts = computeTurnPoints(A, B, C)
    end
    local wp = s.wp

    -- Tramo recto desde el ultimo punto (o el inicio del carril) hasta el inicio de la curva
    local last = wp[#wp]
    local sx, sy, sz
    if last then
        sx, sy, sz = last[1], last[2], last[3]
    else
        local ax, ay, az = nodePos(VEH_NODES, A)
        local bx, by = nodePos(VEH_NODES, B)
        local dx, dy = dir(ax, ay, bx, by)
        local _, off = getLaneInfo(A, B)
        sx, sy, sz = ax + dy * off, ay - dx * off, az
    end
    local ex, ey, ez = pts[1][1], pts[1][2], pts[1][3]
    local len = getDistanceBetweenPoints2D(sx, sy, ex, ey)
    local n = math.floor(len / STEP)
    for i = 1, n - 1 do
        local t = i / n
        wp[#wp + 1] = { sx + (ex - sx) * t, sy + (ey - sy) * t, sz + (ez - sz) * t, 0, nil }
    end
    for _, p in ipairs(pts) do wp[#wp + 1] = p end
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

-- Tramo de carril para volver a la ruta: debe ir en el MISMO sentido que el auto
-- y su nodo destino debe estar POR DELANTE (nunca un punto que obligue a volver
-- atras). Puntua por la distancia lateral del auto al tramo.
local nearestLaneAligned
local function nearestLane(x, y, fx, fy)
    -- primero un carril casi paralelo; si no hay, uno en un angulo mayor (hasta ~75 grados)
    local n, t = nearestLaneAligned(x, y, fx, fy, 0.6)
    if n then return n, t end
    return nearestLaneAligned(x, y, fx, fy, 0.25)
end

function nearestLaneAligned(x, y, fx, fy, minAlign)
    local best, bestTarget, bestScore = nil, nil, math.huge
    local cx, cy = math.floor(x / 100), math.floor(y / 100)
    for ox = -1, 1 do
        for oy = -1, 1 do
            local cell = vehGrid[(cx + ox) * 1000 + (cy + oy)]
            if cell then
                for _, n in ipairs(cell) do
                    local nx, ny = nodePos(VEH_NODES, n)
                    if getDistanceBetweenPoints2D(x, y, nx, ny) < 80 then
                        for _, m in ipairs(VEH_LINKS[n] or {}) do
                            if canDrive(n, m) then
                                local mx, my = nodePos(VEH_NODES, m)
                                local dx, dy, len = dir(nx, ny, mx, my)
                                local aligned = dx * fx + dy * fy
                                local ahead = (mx - x) * fx + (my - y) * fy
                                if aligned > minAlign and ahead > 4 then
                                    -- distancia del auto a la recta del tramo (lateral) y si queda dentro del tramo
                                    local t = ((x - nx) * dx + (y - ny) * dy)
                                    local px, py = nx + dx * math.max(0, math.min(len, t)), ny + dy * math.max(0, math.min(len, t))
                                    local score = getDistanceBetweenPoints2D(x, y, px, py) + (1 - aligned) * 15
                                    if score < bestScore then best, bestTarget, bestScore = n, m, score end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestTarget
end

-- Yendo rapido en un vehiculo: los autos aparecen por delante (en la direccion
-- de marcha), donde el jugador se los va a cruzar. Lejos (> 110 m) se aceptan
-- aunque se vean: a esa distancia no se nota que aparecen.
local function aheadSpawnNode(px, py)
    local v = getPedOccupiedVehicle(localPlayer)
    if not v then return end
    local vx, vy = getElementVelocity(v)
    local len = math.sqrt(vx * vx + vy * vy)
    if len * 180 < 40 or math.random() > CFG.CAR_SPAWN_AHEAD then return end
    local base = math.atan2(vy, vx)
    for _ = 1, 6 do
        local a = base + (math.random() - 0.5) * 1.6
        local d = 110 + math.random() * 50
        local tx, ty = px + math.cos(a) * d, py + math.sin(a) * d
        local cell = vehGrid[math.floor(tx / CELL) * 1000 + math.floor(ty / CELL)]
        if cell then
            local i = cell[math.random(#cell)]
            local x, y, z = nodePos(VEH_NODES, i)
            local dd = getDistanceBetweenPoints2D(px, py, x, y)
            if dd >= 105 and dd <= CFG.CAR_DESPAWN - 10 then return i, x, y, z end
        end
    end
end

-- 1 para un auto normal (~4.6 m); 0.6-0.9 para vehiculos largos (menor radio de giro disponible)
function vehicleLenFactor(vehicle)
    local _, y1, _, _, y2 = getElementBoundingBox(vehicle)
    local len = y1 and (y2 - y1) or 4.6
    if len < 4.6 then return 1 end
    return math.max(0.6, 4.6 / len)
end

-- Hay algun vehiculo (de cualquier tipo) a menos de "radius" metros de (x, y)?
function spotOccupied(x, y, radius)
    local r2 = radius * radius
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local vx, vy = getElementPosition(v)
        if (vx - x) ^ 2 + (vy - y) ^ 2 < r2 then return true end
    end
    -- los autos lejanos (dummies) pueden no estar cargados: tambien la poblacion propia
    for v in pairs(cars) do
        if isElement(v) then
            local vx, vy = getElementPosition(v)
            if (vx - x) ^ 2 + (vy - y) ^ 2 < r2 then return true end
        end
    end
    return false
end

local function spawnCar(px, py)
    local node, x, y, z = aheadSpawnNode(px, py)
    if not node then
        node, x, y, z = randomNodeAround(VEH_NODES, vehGrid, px, py, CFG.CAR_SPAWN_MIN, CFG.CAR_SPAWN_MAX)
        if not node or visibleFromCamera(x, y, z) then return end
    end
    local target
    for _, n in ipairs(VEH_LINKS[node] or {}) do
        if canDrive(node, n) then target = n break end
    end
    if not target then return end
    local sx, sy, sz, dx, dy = laneStart(node, target)
    -- no aparece encima de otro auto (poblacion, jugador, o cualquier vehiculo cargado)
    if spotOccupied(sx, sy, 9) then return end

    local policeModel, policeSkin = pickPolice(sx, sy, sz)
    local vehicle = createVehicle(policeModel or pickCarModel(sx, sy, sz), sx, sy, sz + 1.2, 0, 0, heading(dx, dy))
    if not vehicle then return end
    local driver = createPed(policeSkin or pickDriverSkin(sx, sy, sz), sx, sy, sz + 2)
    if not driver then destroyElement(vehicle) return end
    warpPedIntoVehicle(driver, vehicle)
    setVehicleEngineState(vehicle, true)
    if isNight() then setVehicleOverrideLights(vehicle, 2) end
    if policeModel then
        -- rp_wanted los reconoce como policia (delitos contra ellos, exceso de velocidad)
        setElementData(vehicle, "rp:copCar", true, false)
        setElementData(driver, "rp:cop", true, false)
    end

    cars[vehicle] = {
        driver = driver, prev = node, node = target, wp = {}, police = policeModel ~= nil, style = newDriverStyle(), lenF = vehicleLenFactor(vehicle),
        state = "DRIVE", blockedSince = 0, stuckSince = 0, until_ = 0, recoverUntil = 0,
    }
    carCount = carCount + 1
    -- aparece lejos: empieza como "dummy" (sin fisica) a velocidad de crucero
    makeDummy(vehicle, cars[vehicle], CFG.CAR_SPEED / 3.6)
end

----------------------------------------------------------------
-- LOD de simulacion (como los "dummies" de GTA SA):
--   lejos o fuera de camara -> sin fisica ni colisiones, se desliza sobre su
--   ruta interpolando cada frame (muy barato); cerca -> fisica completa.
----------------------------------------------------------------
local REAL_DIST, DUMMY_DIST = 55, 80

-- Modo fantasma: sin colision con otros autos unos segundos (para deshacer solapes y atascos).
-- Se vuelve solido cuando ya no hay ningun auto cerca (ver carTick).
function ghostCar(vehicle, s, ms)
    s.ghost, s.ghostUntil = true, getTickCount() + ms
    setElementCollisionsEnabled(vehicle, false)
end

-- Hay otro auto de la poblacion (o el del jugador si withPlayer) a menos de "radius" m?
function nearOtherCar(vehicle, radius, withPlayer)
    local x, y = getElementPosition(vehicle)
    local r2 = radius * radius
    for _, o in ipairs(carSnap) do
        if o[1] ~= vehicle and (o[2] - x) ^ 2 + (o[3] - y) ^ 2 < r2 then return true end
    end
    if withPlayer and playerSnap[2] and playerSnap[1] ~= vehicle and (playerSnap[2] - x) ^ 2 + (playerSnap[3] - y) ^ 2 < r2 then
        return true
    end
    return false
end

function makeDummy(vehicle, s, speedMs)
    s.ghost = nil
    s.lod = "dummy"
    s.dSpeed = speedMs or 0
    s.dTarget = s.dSpeed
    s.baseZ = vehicleBaseZ(vehicle)
    setElementFrozen(vehicle, true)
    setElementCollisionsEnabled(vehicle, false)
end

-- Altura del centro del auto sobre el suelo (si el modelo aun no esta cargado,
-- la funcion devuelve 0: se usa un valor tipico de auto)
function vehicleBaseZ(vehicle)
    local d = getElementDistanceFromCentreOfMassToBaseOfModel(vehicle)
    if not d or d < 0.3 or d > 3 then return 0.95 end
    return d
end

-- Suelo real bajo (x, y), buscando cerca de la altura esperada; nil si no hay colision cargada
function groundAt(x, y, nearZ)
    -- solo el mapa (calzada, aceras): sin objetos, para no "apoyarse" en postes o semaforos
    local hit, _, _, gz = processLineOfSight(x, y, nearZ + 4, x, y, nearZ - 6, true, false, false, false, false, true, false, false)
    if hit then return gz end
    return nil
end

local function makeReal(vehicle, s)
    s.lod = "real"
    -- lo apoya sobre el suelo real antes de activar la fisica (nunca dentro del asfalto)
    local x, y, z = getElementPosition(vehicle)
    local gz = groundAt(x, y, z)
    if gz then setElementPosition(vehicle, x, y, gz + vehicleBaseZ(vehicle) + 0.15) end
    -- sin alabeo heredado del dummy: solo el rumbo y una pendiente suave
    local rx, _, rz = getElementRotation(vehicle)
    if rx > 180 then rx = rx - 360 end
    setElementRotation(vehicle, math.max(-15, math.min(15, rx)), 0, rz)
    setElementCollisionsEnabled(vehicle, true)
    setElementFrozen(vehicle, false)
    -- conserva la velocidad que llevaba el dummy (MTA: unidades de 1/50 s)
    local m = getElementMatrix(vehicle)
    local v = (s.dSpeed or 0) / 50
    setElementVelocity(vehicle, m[2][1] * v, m[2][2] * v, 0)
    s.stuckSince, s.blockedSince = 0, 0
end

-- Vuelve al carril mas cercano y descarta la ruta (se recalcula desde ahi)
local function reattach(vehicle, s, teleport)
    releaseLocks(vehicle)
    local x, y = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    local n, target = nearestLane(x, y, m[2][1], m[2][2])
    if not n then
        -- ningun carril por delante en su sentido: si no se ve, se recoloca; si se ve, sigue y reintenta luego
        if isElementOnScreen(vehicle) then return end
        return removeCar(vehicle)
    end
    s.prev, s.node, s.wp, s.route, s.lastPassed = n, target, {}, nil, nil
    if not teleport then
        -- primer punto: la proyeccion del auto sobre su carril, unos metros por delante
        -- (si no, el primer punto podria quedar detras y el auto daria la vuelta)
        local sx, sy, sz, dx, dy = laneStart(n, target)
        local nx2, ny2 = nodePos(VEH_NODES, target)
        local len = math.max(1, getDistanceBetweenPoints2D(sx, sy, nx2, ny2))
        local t = math.max(0, math.min(len - 8, (x - sx) * dx + (y - sy) * dy + 8))
        s.wp[1] = { sx + dx * t, sy + dy * t, sz, 0, nil }
    end
    if teleport then
        local sx, sy, sz, dx, dy = laneStart(n, target)
        setElementPosition(vehicle, sx, sy, sz + 1.2)
        setElementRotation(vehicle, 0, 0, heading(dx, dy))
        setElementVelocity(vehicle, 0, 0, 0)
    end
end

-- Atascado o volcado (como GTA SA): el conductor se baja y huye; el auto queda
-- como obstaculo y se elimina cuando ya no se ve.
-- Patrulla del trafico: pasa a rp_wanted (persigue al jugador buscado). Devuelve true si la tomo.
local function handOverPolice(vehicle, s)
    if not s.police or not playerWanted() or not isElement(s.driver) or isPedDead(s.driver) then return false end
    local ok, adopted = pcall(function() return exports.rp_wanted:adoptLocalCop(vehicle, s.driver) end)
    if not ok or not adopted then return false end
    releaseLocks(vehicle)
    if s.lod == "dummy" then makeReal(vehicle, s) end
    cars[vehicle] = nil
    carCount = carCount - 1
    return true
end

function abandonCar(vehicle, s)
    if s.state == "ABANDONED" then return end
    if handOverPolice(vehicle, s) then return end
    releaseLocks(vehicle)
    s.state = "ABANDONED"
    local driver = s.driver
    s.driver = nil
    if isElement(driver) then
        setPedControlState(driver, "accelerate", false)
        setPedControlState(driver, "brake_reverse", false)
        removePedFromVehicle(driver)
        local x, y, z = getElementPosition(vehicle)
        local m = getElementMatrix(vehicle)
        setElementPosition(driver, x - m[1][1] * 2, y - m[1][2] * 2, z + 0.5)
        peds[driver] = { state = "WALK", node = nil, prev = nil, brave = false, until_ = 0 }
        pedCount = pedCount + 1
        startFlee(driver, vehicle, 7000)
    end
end

-- Persecuciones (para futuras facciones / policia): eleccion voraz en cada cruce,
-- el enlace cuyo nodo mas acerca al objetivo. Sin A*, como en GTA SA.
function chooseExitTowards(node, prev, tx, ty)
    local best, bestD = nil, math.huge
    for _, n in ipairs(VEH_LINKS[node] or {}) do
        if n ~= prev and canDrive(node, n) then
            local nx, ny = nodePos(VEH_NODES, n)
            local d = getDistanceBetweenPoints2D(nx, ny, tx, ty)
            if d < bestD then best, bestD = n, d end
        end
    end
    return best or (canDrive(node, prev) and prev or nil)
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

----------------------------------------------------------------
-- Seguimiento de trayectoria: devuelve el error de rumbo (grados, + = girar a la izquierda)
-- respecto de la ruta unos metros por delante, corregido por la distancia lateral (tipo Stanley).
function pathTrack(s, wp, x, y, speed, rz)
    local pts = {}
    if s.lastPassed then pts[1] = s.lastPassed end
    for i = 1, math.min(#wp, 12) do pts[#pts + 1] = wp[i] end
    if #pts < 2 then return nil end
    -- tramo mas cercano
    local bi, bt, bd = 1, 0, math.huge
    for i = 1, #pts - 1 do
        local ax, ay = pts[i][1], pts[i][2]
        local sx, sy = pts[i + 1][1] - ax, pts[i + 1][2] - ay
        local l2 = sx * sx + sy * sy
        local t = l2 > 0.01 and math.max(0, math.min(1, ((x - ax) * sx + (y - ay) * sy) / l2)) or 0
        local d = (x - (ax + sx * t)) ^ 2 + (y - (ay + sy * t)) ^ 2
        if d < bd then bi, bt, bd = i, t, d end
    end
    -- error lateral con signo respecto del tramo mas cercano (+ = el auto esta a la izquierda)
    local ax, ay = pts[bi][1], pts[bi][2]
    local ux, uy = dir(ax, ay, pts[bi + 1][1], pts[bi + 1][2])
    local e = (x - ax) * -uy + (y - ay) * ux
    -- avanza por la ruta una distancia de mirada para tomar el rumbo de ese tramo
    local remain = 3 + speed * 0.1
    local i, t = bi, bt
    while i < #pts - 1 do
        local seg = getDistanceBetweenPoints2D(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
        local left = seg * (1 - t)
        if remain <= left then break end
        remain = remain - left
        i, t = i + 1, 0
    end
    local vx, vy = dir(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
    local pathHeading = heading(vx, vy)
    local desired = pathHeading - math.deg(math.atan(1.5 * e / (speed / 3.6 + 2)))
    return angleDiff(desired, rz)
end

-- Velocidad maxima (km/h) para entrar a una curva de "turn" grados que esta a "dist" m:
-- la velocidad dentro de la curva (cuanto mas cerrada, menos) mas lo que se puede
-- frenar en esa distancia (~4 m/s2), para que empiece a frenar con tiempo suficiente.
-- Asi nunca llega a un giro cerrado demasiado rapido y se sale recto.
function curveCap(turn, dist, lenF)
    -- lenF < 1 en vehiculos largos (camiones, buses): giran mas abierto, entran mas despacio
    local inside = math.max(turn >= 70 and 8 or 10, CFG.CAR_SPEED * (1 - turn / 115)) * (lenF or 1)
    return math.sqrt(inside * inside + 100 * math.max(0, dist - 2))
end

-- Vehiculos con sirena (se refresca cada 500 ms) y posiciones de los autos
-- (una sola lectura por tick en vez de N x N para los dummies)
----------------------------------------------------------------
local sirenList = {}
carSnap, playerSnap = {}, { false }

function refreshSnapshots(now)
    carSnap = {}
    for v in pairs(cars) do
        if isElement(v) then
            local x, y = getElementPosition(v)
            carSnap[#carSnap + 1] = { v, x, y }
        end
    end
    local pe = getPedOccupiedVehicle(localPlayer) or localPlayer
    local x, y = getElementPosition(pe)
    playerSnap = { pe, x, y }
    if not getVehicleSirensOn or now - (sirenList.at or 0) < 500 then return end
    local list = { at = now }
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if not cars[v] and getVehicleSirensOn(v) and speedOf(v) > 3 then
            local mm = getElementMatrix(v)
            list[#list + 1] = { v, mm[4][1], mm[4][2], mm[2][1], mm[2][2] }
        end
    end
    sirenList = list
end

-- Distancia a una sirena que viene por detras en nuestro mismo sentido (nil si no hay)
function sirenBehind(vehicle, x, y, m)
    local fx, fy = m[2][1], m[2][2]
    local best
    for i = 1, #sirenList do
        local o = sirenList[i]
        if o[1] ~= vehicle then
            local dx, dy = o[2] - x, o[3] - y
            local along = dx * fx + dy * fy
            local lateral = math.abs(dx * fy - dy * fx)
            if along < -3 and along > -70 and lateral < 8 and (o[4] * fx + o[5] * fy) > 0.3 then
                if not best or -along < best then best = -along end
            end
        end
    end
    return best
end

----------------------------------------------------------------
-- Bocina: control del NPC + sonido propio (el del NPC no siempre se oye)
----------------------------------------------------------------
local function honk(vehicle, s, now)
    setPedControlState(s.driver, "horn", true)
    if not s.hornAt or now - s.hornAt > 1400 then
        s.hornAt = now
        local x, y, z = getElementPosition(vehicle)
        local snd = playSound3D("sounds/horn.wav", x, y, z)
        if snd then
            setSoundMaxDistance(snd, 60)
            setSoundVolume(snd, 0.9)
            attachElements(snd, vehicle)
        end
    end
end

----------------------------------------------------------------
-- Desvio provisional: rodea al jugador por la izquierda (carril contrario) o la
-- derecha (arcen) si el camino esta libre, y se reincorpora a su ruta.
----------------------------------------------------------------
local function clearPath(x1, y1, z1, x2, y2, z2, vehicle)
    return isLineOfSightClear(x1, y1, z1 + 0.6, x2, y2, z2 + 0.6, true, true, true, true, false, true, false, vehicle)
end

local function tryDetour(vehicle, s, m)
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local fx, fy = m[2][1], m[2][2]
    local lx, ly = -fy, fx                          -- izquierda del auto
    local wp = s.wp
    -- punto de reincorporacion: el primero de la ruta a mas de 24 m
    local rejoin = nil
    for i = 1, #wp do
        if getDistanceBetweenPoints2D(x, y, wp[i][1], wp[i][2]) > 24 then rejoin = i break end
    end
    if not rejoin then return false end
    local rx, ry, rz = wp[rejoin][1], wp[rejoin][2], wp[rejoin][3]

    for _, side in ipairs({ 5, 7, -4.5 }) do
        local p1x, p1y = x + fx * 4 + lx * side * 0.6, y + fy * 4 + ly * side * 0.6
        local p2x, p2y = x + fx * 11 + lx * side, y + fy * 11 + ly * side
        local p3x, p3y = x + fx * 18 + lx * side * 0.7, y + fy * 18 + ly * side * 0.7
        local ground = getGroundPosition(p2x, p2y, z + 3)
        local flat = ground and ground ~= 0 and math.abs(ground - (z - 0.5)) < 1.5
        if flat and clearPath(x, y, z, p1x, p1y, z, vehicle) and clearPath(p1x, p1y, z, p2x, p2y, z, vehicle)
            and clearPath(p2x, p2y, z, p3x, p3y, z, vehicle) and clearPath(p3x, p3y, z, rx, ry, rz, vehicle) then
            -- reemplaza el tramo bloqueado por el desvio (giro 25 = va despacio)
            for _ = 1, rejoin - 1 do table.remove(wp, 1) end s.lastPassed = nil
            table.insert(wp, 1, { p3x, p3y, z, 25 })
            table.insert(wp, 1, { p2x, p2y, z, 25 })
            table.insert(wp, 1, { p1x, p1y, z, 25 })
            return true
        end
    end
    return false
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
    local rx, ry, rz = getElementRotation(vehicle)
    local m = getElementMatrix(vehicle)

    -- Volcado: el conductor huye y el auto queda abandonado
    if m[3][3] < 0.3 then return abandonCar(vehicle, s) end
    -- Inclinado sobre dos ruedas (montado sobre otro auto) y casi parado: tambien se abandona
    if m[3][3] < 0.6 and speed < 6 then
        s.tiltSince = s.tiltSince or now
        if now - s.tiltSince > 3000 then return abandonCar(vehicle, s) end
    else
        s.tiltSince = nil
    end

    -- Marcha atras corta (como mucho ~1 s / 3-4 m) solo cuando esta atascado de verdad.
    -- No se reengancha al terminar: sigue con su ruta (solo se recalcula si se alejo de ella).
    if now < s.recoverUntil then
        setPedControlState(driver, "horn", false)
        steerTo(driver, -(s.recoverSteer or 0))
        local vx, vy = getElementVelocity(vehicle)
        local backing = (vx * m[2][1] + vy * m[2][2]) * 180
        setPedal(driver, false, backing > -12)       -- no supera ~12 km/h marcha atras
        return
    end
    if s.needReattach then reattach(vehicle, s, false) end
    s.needReattach = nil

    -- Cola de puntos: siempre algunos por delante (planifica cruce a cruce)
    local wp = s.wp
    local guard = 0
    while #wp < 18 and guard < 4 do
        if not planSegment(s) then break end
        guard = guard + 1
    end
    -- Como en GTA SA no se recalcula nada: el controlador sigue apuntando al punto
    -- de su carril. Si queda sin camino o muy lejos de el, desaparece cuando no
    -- se ve (el spawn crea otro en una ruta valida).
    if #wp == 0 then
        -- sin ruta (callejon sin salida en los datos): se detiene, intenta reengancharse y si no, se retira
        if not s.noRouteSince and (offLogCount or 0) < 60 then
            offLogCount = (offLogCount or 0) + 1
            local lk = {}
            for _, n in ipairs(VEH_LINKS[s.node] or {}) do lk[#lk + 1] = ("%d(L%d)"):format(n, (getLaneInfo(s.node, n))) end
            outputDebugString(("[rp_citizens] sin ruta: nodos %s->%s enlaces del nodo: %s"):format(tostring(s.prev), tostring(s.node), table.concat(lk, " ")), 1)
        end
        s.noRouteSince = s.noRouteSince or now
        steerTo(driver, 0)
        setPedal(driver, false, speed > 1)
        if now - s.noRouteSince > 800 and now - (s.lastReattach or 0) > 2000 then
            s.lastReattach = now
            reattach(vehicle, s, false)
            if not cars[vehicle] then return end
        end
        if now - s.noRouteSince > 6000 then
            if isElementOnScreen(vehicle) then return abandonCar(vehicle, s) end
            return removeCar(vehicle)
        end
        return
    end
    s.noRouteSince = nil
    -- Fuera de su carril (esquive, choque, derrape): tras 1.5 s se reengancha al carril mas
    -- cercano por delante; si sigue muy lejos de la ruta, se elimina aunque se vea (reaparece otro)
    -- desviacion = distancia al tramo entre el ultimo punto pasado y el siguiente (no solo al siguiente:
    -- en un cruce recto hay hasta ~24 m entre puntos y eso no es salirse de la ruta)
    local dev = getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2])
    local lp = s.lastPassed
    if not lp then dev = math.min(dev, 14) end   -- recien creado/reenganchado: aun no hay tramo de referencia
    if lp then
        local sx, sy = wp[1][1] - lp[1], wp[1][2] - lp[2]
        local len2 = sx * sx + sy * sy
        if len2 > 0.01 then
            local t = math.max(0, math.min(1, ((x - lp[1]) * sx + (y - lp[2]) * sy) / len2))
            dev = math.min(dev, getDistanceBetweenPoints2D(x, y, lp[1] + sx * t, lp[2] + sy * t))
        end
    end
    if dev > 25 and not isElementOnScreen(vehicle) then
        return removeCar(vehicle)
    end
    if dev > 18 and not (s.detourUntil and now < s.detourUntil) then
        if not s.offSince and (offLogCount or 0) < 60 then
            -- diagnostico: se sale de su ruta (ver clientscript.log, lineas "[rp_citizens] fuera de ruta")
            offLogCount = (offLogCount or 0) + 1
            local w1 = wp[1]
            local dgn = angleDiff(heading(w1[1] - x, w1[2] - y), rz)
            local pts = {}
            for k = 1, math.min(#wp, 6) do pts[#pts + 1] = ("(%.0f,%.0f,g%.0f)"):format(wp[k][1], wp[k][2], wp[k][4]) end
            outputDebugString(("[rp_citizens] fuera de ruta: modelo %d nodos %s->%s pos (%.1f,%.1f) rumbo %.0f vel %.0f dev %.1f dif %.0f estado %s lenF %.2f wp: %s")
                :format(getElementModel(vehicle), tostring(s.prev), tostring(s.node), x, y, rz, speed, dev, dgn, tostring(s.state), s.lenF or 1, table.concat(pts, " ")), 1)
        end
        s.offSince = s.offSince or now
        if now - s.offSince > 1500 and now - (s.lastReattach or 0) > 3000 then
            s.lastReattach = now
            s.slowUntil = now + 5000   -- al reengancharse va despacio (nunca a tope por la acera)
            reattach(vehicle, s, false)
            if not cars[vehicle] then return end
            wp = s.wp
            if #wp == 0 then return end
        end
        if dev > 40 and now - s.offSince > 5000 then return removeCar(vehicle) end
    else
        s.offSince = nil
    end

    -- Pure pursuit: descarta los puntos ya alcanzados y apunta al primero por delante
    -- Si hay un giro cerrado en los proximos 14 m de ruta, mira solo unos metros adelante:
    -- con la mirada larga de las rectas el auto apunta "por la tangente" de la curva y se sale recto
    local curveSoon, cd, clx, cly = false, 0, x, y
    for i = 1, math.min(#wp, 8) do
        cd = cd + getDistanceBetweenPoints2D(clx, cly, wp[i][1], wp[i][2])
        clx, cly = wp[i][1], wp[i][2]
        if cd > 14 then break end
        if wp[i][4] > 40 then curveSoon = true break end
    end
    -- (tambien unos metros despues de salir de la curva: el seguimiento de trayectoria lo realinea con el
    -- carril; si no, la velocidad de giro que traia lo saca hacia la acera)
    local lpd = s.lastPassed
    local justLeftCurve = lpd and lpd[4] > 20 and wp[1][4] <= 20 and getDistanceBetweenPoints2D(x, y, lpd[1], lpd[2]) < 12
    local inCurve = curveSoon or wp[1][4] > 20 or justLeftCurve
    local lookahead = curveSoon and (2.5 + speed * 0.05) or (inCurve and 3.5 or 6) + speed * (inCurve and 0.06 or 0.1)
    -- tambien descarta los que quedaron DETRAS del auto (nunca se da la vuelta por un punto pasado)
    local fwx, fwy = m[2][1], m[2][2]
    while #wp > 1 and (getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2]) < lookahead
        or ((wp[1][1] - x) * fwx + (wp[1][2] - y) * fwy < 0 and (wp[2][1] - x) * fwx + (wp[2][2] - y) * fwy > -2
            and getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2]) < 12)) do
        local passed = table.remove(wp, 1)
        s.lastPassed = passed
        -- libera el cruce cuando ya no quedan puntos de el
        if passed[5] and (not wp[1][5] or wp[1][5] ~= passed[5]) then
            local l = junctionLock[passed[5]]
            if l and l[1] == vehicle then junctionLock[passed[5]] = nil end
        end
    end
    local tx, ty = wp[1][1], wp[1][2]
    local diff = angleDiff(heading(tx - x, ty - y), rz)
    -- En curvas: seguimiento de la trayectoria (rumbo de la ruta + correccion de la distancia lateral)
    -- en vez de apuntar a un punto, que en un arco cerrado casi no se desvia del rumbo actual
    local trackDiff = nil
    if inCurve then
        trackDiff = pathTrack(s, wp, x, y, speed, rz)
        if trackDiff then diff = trackDiff end
    end

    -- Lo que viene: mayor giro, cruce y semaforo en los proximos metros
    local upcoming, dist, lx, ly = 0, 0, x, y
    local curveLimit = 999
    local junctionAhead, junctionDist, lightAxis, lightDist = nil, 0, nil, 0
    for i = 1, math.min(#wp, 14) do
        dist = dist + getDistanceBetweenPoints2D(lx, ly, wp[i][1], wp[i][2])
        lx, ly = wp[i][1], wp[i][2]
        if dist > 60 then break end
        if wp[i][4] > 15 then curveLimit = math.min(curveLimit, curveCap(wp[i][4], dist, s.lenF)) end
        if dist > 45 then break end
        if dist <= 30 and wp[i][4] > upcoming then upcoming = wp[i][4] end
        if wp[i][5] and not junctionAhead and dist <= 30 then junctionAhead, junctionDist = wp[i][5], dist end
        if wp[i][6] and not lightAxis then lightAxis, lightDist = wp[i][6], dist end
    end

    -- Sensores: frente (vehiculos/peatones/objetos) y bigotes laterales (solo paredes)
    local reach = 8 + speed * 0.3
    local frontHit, obstacle, gap = ray(vehicle, m, 0, reach, false)
    -- abanico: dos rayos de +-8 grados ven lo que queda medio carril al lado (motos, peatones)
    for _, a in ipairs({ 8, -8 }) do
        local h, e, g = ray(vehicle, m, a, reach * 0.8, false)
        if h and e and (not frontHit or not obstacle or (g and gap and g < gap)) then
            frontHit, obstacle, gap = h, e, g
        end
    end
    -- en modo fantasma (sin colision, para salir de un atasco) no ve autos delante
    if s.ghost then frontHit, obstacle, gap = false, nil, nil end
    local wallFront = ray(vehicle, m, 0, 3 + speed * 0.08, true)
    local leftHit = ray(vehicle, m, 25, 3.5 + speed * 0.06, true)
    local rightHit = ray(vehicle, m, -25, 3.5 + speed * 0.06, true)

    -- en curvas cerradas gira con mas decision (volante a tope antes)
    local steer = diff / (inCurve and ((curveSoon or wp[1][4] > 60) and 12 or 18) or 25)
    if leftHit and not rightHit then steer = steer - 0.2 end
    if rightHit and not leftHit then steer = steer + 0.2 end
    -- Sirena detras: se arrima un poco a la derecha (salvo en un cruce o con algo al lado)
    local sirenDist = sirenBehind(vehicle, x, y, m)
    if sirenDist and not junctionAhead and not rightHit then steer = steer - 0.12 end
    steerTo(driver, steer)

    -- Asistencia de direccion suave: ayuda al volante (sin imponer el giro) y
    -- reduce solo parte del derrape lateral, para no frenar ni hacer patinar.
    if speed > 4 then
        local vx, vy, vz = getElementVelocity(vehicle)
        local fx, fy = m[2][1], m[2][2]
        local rx, ry = m[1][1], m[1][2]
        local along = vx * fx + vy * fy
        local side = vx * rx + vy * ry
        if math.abs(side) > 0.02 then
            setElementVelocity(vehicle, fx * along + rx * side * 0.8, fy * along + ry * side * 0.8, vz)
        end
        -- En una curva cerrada NO se limita el giro: esta asistencia fijaba la velocidad angular
        -- al valor de un apuntado casi recto (la mirada corta sobre el arco apenas se desvia), y
        -- el auto no podia girar lo que pide el radio del cruce y se salia recto.
        if inCurve then
            -- el giro necesario para recuperar el rumbo de la ruta en ~0.4 s, limitado a lo que
            -- el vehiculo puede girar de verdad (radio minimo ~4.5 m)
            if trackDiff then
                local ax, ay, az = getElementAngularVelocity(vehicle)
                local maxW = math.min(0.03, (speed / 3.6) / 4.5 / 50)
                local want = math.max(-maxW, math.min(maxW, math.rad(trackDiff) / 0.4 / 50))
                setElementAngularVelocity(vehicle, ax, ay, az + (want - az) * 0.6)
            end
        else
            local ax, ay, az = getElementAngularVelocity(vehicle)
            -- velocidad angular de MTA en radianes por 1/50 s (0.015 ~ 43 grados/s)
            local desired = math.max(-0.015, math.min(0.015, math.rad(diff) * 0.025)) * math.min(1, speed / 20)
            setElementAngularVelocity(vehicle, ax, ay, az + (desired - az) * 0.35)
        end
    end

    if s.state == "FLEE" then
        setPedControlState(driver, "horn", false)
        setPedal(driver, not obstacle or speed < 5, (obstacle ~= nil or wallFront) and speed > 20)
        if now > s.until_ then s.state = "DRIVE" end
        return
    end

    -- Velocidad objetivo
    local target = CFG.CAR_SPEED * (s.style and s.style.speed or 1)
    target = math.min(target, curveLimit)
    -- fuera de su ruta o recien reenganchado: despacio hasta estar de nuevo en el carril
    if s.offSince or (s.slowUntil and now < s.slowUntil) then target = math.min(target, 15) end
    if sirenDist then target = math.min(target, sirenDist < 30 and 6 or 18) end
    if math.abs(diff) > 50 then target = math.min(target, 16) end
    if wallFront then target = math.min(target, 15) end
    if s.detourUntil and now < s.detourUntil then target = math.min(target, 18) end
    local waiting = false

    -- Semaforo: frena hasta la linea de detencion en rojo (en amarillo si aun puede)
    if lightAxis then
        local light = lightFor(lightAxis)
        if light == "red" or (light == "yellow" and lightDist > 12) then
            if lightDist < 3 then target = 0 else target = math.min(target, math.max(4, (lightDist - 3) * 1.6)) end
            waiting = true
            s.state = "RED"
        end
    end

    -- Cruce: pide paso; si otro auto lo tiene, espera antes de entrar
    local yielding = false
    if not waiting and junctionAhead and junctionDist < 14 then
        if not tryLock(junctionAhead, vehicle, now) then
            yielding = true
            target = junctionDist > 7 and 8 or 0
        end
    end

    -- Distancia de seguimiento con lo que tenga delante
    local isPlayerThing = obstacle and (obstacle == localPlayer or obstacle == getPedOccupiedVehicle(localPlayer))
    if obstacle then
        local otherSpeed = isElement(obstacle) and getElementType(obstacle) ~= "ped" and speedOf(obstacle) or 0
        local safeGap = (4 + speed * 0.12) * (s.style and s.style.gap or 1)
        if gap and gap < safeGap then target = 0 else target = math.min(target, otherSpeed + 3) end
        -- tiempo hasta el choque: si se cierra demasiado rapido, frena a fondo
        local closing = (speed - otherSpeed) / 3.6
        if gap and closing > 1 and gap / closing < 2.0 then target = 0 end

        if target <= 1 and speed < 3 then
            if s.blockedSince == 0 then s.blockedSince = now end
            local waited = now - s.blockedSince
            if isPlayerThing then
                -- 1) bocina  2) busca un desvio  3) si no hay hueco, retrocede un poco y vuelve a intentar
                if waited > 900 then honk(vehicle, s, now) end
                if waited > 2800 and not waiting then
                    if tryDetour(vehicle, s, m) then
                        s.detourUntil, s.blockedSince = now + 6000, 0
                        setPedControlState(driver, "horn", false)
                    elseif waited > 4500 then
                        -- sin hueco: retrocede un instante (~1 s) para abrir angulo y reintenta
                        s.recoverUntil, s.recoverSteer, s.blockedSince = now + 900, 0, now - 2000
                    end
                end
            elseif waited > 8000 and otherSpeed < 1 and not yielding and not waiting then
                -- objeto o auto averiado (no una cola): lo rodea. Nunca adelanta a autos
                -- de la poblacion que esperan en un semaforo, cruce o cola.
                local queued = cars[obstacle] and (cars[obstacle].state == "RED" or cars[obstacle].state == "FOLLOW"
                    or cars[obstacle].state == "YIELD" or cars[obstacle].state == "DRIVE")
                if not queued and tryDetour(vehicle, s, m) then s.detourUntil, s.blockedSince = now + 6000, 0 end
            end
        end
        if s.state ~= "RED" then s.state = "FOLLOW" end
    else
        s.blockedSince = 0
        setPedControlState(driver, "horn", false)
        if not waiting then s.state = yielding and "YIELD" or (s.detourUntil and now < s.detourUntil and "DETOUR" or "DRIVE") end
    end

    setPedal(driver, speed < target - 1, speed > target + 6 or (target == 0 and speed > 1))

    -- Atascado sin motivo (pared, otro auto cruzado): marcha atras y reenganche
    -- (en cola, semaforo o cruce NUNCA cuenta como atasco)
    -- Parado demasiado tiempo (cruce bloqueado, dos autos de frente): pasa a modo fantasma
    -- unos segundos para atravesar el atasco. Nunca con el jugador de por medio.
    if speed < 2 and s.state ~= "RED" and not isPlayerThing and target < 5 then
        s.slowSince = s.slowSince or now
        if now - s.slowSince > 25000 then
            s.slowSince = nil
            ghostCar(vehicle, s, 7000)
        end
    else
        s.slowSince = nil
    end
    local stopped = waiting or yielding or obstacle ~= nil or s.state == "RED" or s.state == "FOLLOW"
    if speed < 2 and not stopped and target > 5 then
        if s.stuckSince == 0 then s.stuckSince = now end
        if now - s.stuckSince > 3000 then
            s.recoverUntil, s.recoverSteer, s.stuckSince = now + 1100, steer, 0
            s.stuckCount = (s.stuckCount or 0) + 1
            -- atascado de verdad: el conductor se baja y se va; el auto queda como obstaculo
            if s.stuckCount > 3 then abandonCar(vehicle, s) end
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
            -- el que va detras frena un momento (sin marcha atras); el de delante sigue.
            -- Si alguno quedo fuera de su ruta, el control de distancia lo reengancha.
            local m = getElementMatrix(source)
            local hx, hy = getElementPosition(hit)
            local x, y = getElementPosition(source)
            local ahead = (hx - x) * m[2][1] + (hy - y) * m[2][2] > 0
            if ahead then
                s.blockedSince = now
                setPedal(s.driver, false, true)
            end
        end
    end
end)

-- Presupuesto de rutas A*: se renueva en cada tick de conduccion
function refillRouteBudget()
    routeBudget = 2   -- como maximo dos rutas A* por tick (~5 ms cada una en el peor caso)
end

-- Para el editor (/nodos): lo que planea cada auto de la poblacion
function getCitizenCarPlans()
    local list = {}
    for vehicle, s in pairs(cars) do
        if isElement(vehicle) and s.wp then
            list[#list + 1] = { vehicle = vehicle, wp = s.wp, state = s.state, lod = s.lod }
        end
    end
    return list
end

----------------------------------------------------------------
-- Dummies: decision cada tick (velocidad objetivo) y movimiento cada frame
----------------------------------------------------------------
local function dummyDecide(vehicle, s)
    local wp = s.wp
    local guard = 0
    while #wp < 18 and guard < 4 do
        if not planSegment(s) then break end
        guard = guard + 1
    end
    if #wp == 0 then s.dTarget = 0 return end

    local x, y = getElementPosition(vehicle)
    local target = CFG.CAR_SPEED * (s.style and s.style.speed or 1)
    local upcoming, dist, lx, ly = 0, 0, x, y
    local curveLimit = 999
    for i = 1, math.min(#wp, 14) do
        dist = dist + getDistanceBetweenPoints2D(lx, ly, wp[i][1], wp[i][2])
        lx, ly = wp[i][1], wp[i][2]
        if dist > 60 then break end
        if wp[i][4] > 15 then curveLimit = math.min(curveLimit, curveCap(wp[i][4], dist, s.lenF)) end
        if dist > 45 then break end
        if dist <= 30 and wp[i][4] > upcoming then upcoming = wp[i][4] end
        if wp[i][6] then
            local light = lightFor(wp[i][6])
            if light == "red" or (light == "yellow" and dist > 12) then
                target = dist < 3 and 0 or math.min(target, math.max(4, (dist - 3) * 1.6))
                s.state = "RED"
            end
            break
        end
    end
    target = math.min(target, curveLimit)

    -- auto delante (de la poblacion o del jugador) en el mismo sentido: mantiene distancia
    local m = getElementMatrix(vehicle)
    local fx, fy = m[2][1], m[2][2]
    local function checkAheadAt(other, ox, oy)
        if other == vehicle or not ox then return end
        local dx, dy = ox - x, oy - y
        local along = dx * fx + dy * fy
        local lateral = math.abs(dx * fy - dy * fx)
        if along > 0 and along < 14 and lateral < 2.5 then
            target = along < 7 and 0 or math.min(target, (along - 7) * 3)
        end
    end
    for _, o in ipairs(carSnap) do checkAheadAt(o[1], o[2], o[3]) end
    checkAheadAt(playerSnap[1], playerSnap[2], playerSnap[3])

    if target > 0 and s.state == "RED" then s.state = "DRIVE" end
    s.dTarget = target / 3.6
    if target == 0 and s.state ~= "RED" then s.state = "FOLLOW" elseif target > 0 then s.state = "DRIVE" end
end

local function moveDummies(dt)
    dt = math.min(dt, 100) / 1000
    for vehicle, s in pairs(cars) do
        if s.lod == "dummy" and isElement(vehicle) and s.wp and #s.wp > 0 then
            -- acelera / frena con suavidad
            local accel = s.dTarget > s.dSpeed and 3 or 7
            if s.dTarget > s.dSpeed then s.dSpeed = math.min(s.dTarget, s.dSpeed + accel * dt)
            else s.dSpeed = math.max(s.dTarget, s.dSpeed - accel * dt) end

            local x, y, z = getElementPosition(vehicle)
            local step = s.dSpeed * dt
            local wp = s.wp
            while step > 0 and #wp > 0 do
                local tx, ty, tz = wp[1][1], wp[1][2], wp[1][3] + s.baseZ
                local d = getDistanceBetweenPoints2D(x, y, tx, ty)
                if d <= step then
                    x, y, z = tx, ty, tz
                    step = step - d
                    table.remove(wp, 1) s.lastPassed = nil
                else
                    local k = step / d
                    x, y, z = x + (tx - x) * k, y + (ty - y) * k, z + (tz - z) * math.min(1, k * 2)
                    step = 0
                end
            end
            -- Altura y pendiente desde el suelo real (si su colision esta cargada);
            -- si no, la altura del nodo + la del chasis.
            local _, _, rz = getElementRotation(vehicle)
            if #wp > 0 then
                rz = rz + angleDiff(heading(wp[1][1] - x, wp[1][2] - y), rz) * math.min(1, dt * 6)
            end
            local pitch = 0
            s.groundTick = (s.groundTick or 0) + 1
            if s.groundTick % 2 == 0 or not s.lastGround then
                local r = math.rad(rz)
                local fx, fy = -math.sin(r), math.cos(r)
                local gz = groundAt(x, y, z)
                local gf = groundAt(x + fx * 2, y + fy * 2, z)
                local gb = groundAt(x - fx * 2, y - fy * 2, z)
                if gz then
                    s.lastGround = gz
                    if gf and gb then s.lastPitch = math.max(-15, math.min(15, math.deg(math.atan2(gf - gb, 4)))) end
                end
            end
            if s.lastGround and math.abs(s.lastGround - (z - s.baseZ)) < 4 then
                z = s.lastGround + s.baseZ
                pitch = s.lastPitch or 0
            end
            if s.baseZ == 0.95 and isElementStreamedIn(vehicle) then s.baseZ = vehicleBaseZ(vehicle) end
            setElementPosition(vehicle, x, y, z)
            setElementRotation(vehicle, pitch, 0, rz)
        end
    end
end-- Si el jugador choca o dispara a un auto, el conductor se asusta y acelera
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
            local d = getDistanceBetweenPoints2D(px, py, x, y)
            local far = d > CFG.CAR_DESPAWN
            -- los abandonados (atascados/volcados) se eliminan en cuanto dejan de verse
            local gone = s.state == "ABANDONED" and d > 25 and not isElementOnScreen(v)
            if (far or gone) and getVehicleController(v) ~= localPlayer then removeCar(v) end
        end
    end

    -- Spawn hasta el limite (uno por tick para repartir el coste)
    local night = isNight()
    if pedCount < (night and CFG.MAX_PEDS_NIGHT or CFG.MAX_PEDS) then spawnPed(px, py) end
    local maxCars = (night and CFG.MAX_CARS_NIGHT or CFG.MAX_CARS) + (playerWanted() and CFG.MAX_CARS_WANTED or 0)
    -- hasta 2 por tick cuando faltan muchos (yendo rapido se despawnean seguido)
    for _ = 1, (maxCars - carCount > 4) and 2 or 1 do
        if carCount < maxCars then spawnCar(px, py) end
    end
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
    local now = getTickCount()
    local px, py, pz = getElementPosition(localPlayer)
    refreshSnapshots(now)
    for v, s in pairs(cars) do
        -- Patrulla del trafico (aunque el agente se haya caido de la moto) cerca de un
        -- jugador buscado: se suma a la persecucion de rp_wanted y deja de ser trafico
        local handed = false
        if s.police and isElement(v) then
            local x, y, z = getElementPosition(v)
            handed = getDistanceBetweenPoints3D(px, py, pz, x, y, z) < 150 and handOverPolice(v, s)
        end
        if handed then
            -- nada
        elseif isElement(v) and s.state ~= "ABANDONED" then
            local x, y, z = getElementPosition(v)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            do
            -- cambio de LOD: fisica completa cerca; dummy lejos y fuera de camara
            if s.lod == "dummy" and d < REAL_DIST then
                makeReal(v, s)
                -- los dummies no chocan entre si: al hacerse solido puede quedar encima de otro auto
                if nearOtherCar(v, 3, true) then ghostCar(v, s, 4000) end
            elseif s.lod ~= "dummy" and d > DUMMY_DIST and not isElementOnScreen(v) then
                makeDummy(v, s, speedOf(v) / 3.6)
            end
            if s.lod ~= "dummy" then
                if s.ghost then
                    -- vuelve a ser solido cuando no queda ningun auto encima
                    if now > s.ghostUntil then
                        if nearOtherCar(v, 4.2, true) then
                            s.ghostUntil = now + 1000
                        else
                            s.ghost = nil
                            setElementCollisionsEnabled(v, true)
                        end
                    end
                elseif nearOtherCar(v, 2.4, false) then
                    -- dos autos superpuestos mas de 2 s: uno pasa a fantasma
                    s.overlapSince = s.overlapSince or now
                    if now - s.overlapSince > 2000 then ghostCar(v, s, 5000) s.overlapSince = nil end
                else
                    s.overlapSince = nil
                end
            end
            if s.lod == "dummy" then
                dummyDecide(v, s)
            elseif isElementStreamedIn(v) then
                updateCar(v, s, now)
            end
            end
        elseif isElement(v) and s.lod == "dummy" then
            makeReal(v, s)   -- un auto abandonado vuelve a tener fisica
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    pedGrid = buildGrid(PED_NODES, PED_LINKS)
    vehGrid = buildGrid(VEH_NODES, VEH_LINKS)
    setPedsLODDistance(60)
    setTimer(spawnTick, CFG.SPAWN_TICK, 0)
    setTimer(pedTick, CFG.PED_TICK, 0)
    setTimer(carTick, CFG.CAR_TICK, 0)
    -- solo mueve dummies (pocos calculos por auto); sin dummies no hace nada
    addEventHandler("onClientPreRender", root, moveDummies)
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

----------------------------------------------------------------
-- Export: red vial actual (incluye los cambios del editor) para otros
-- recursos, p. ej. rp_rides (conductor IA y mapa de rutas).
----------------------------------------------------------------
function getRoadGraph()
    return VEH_NODES, VEH_LINKS, VEH_LANES, VEH_OFFSET
end
