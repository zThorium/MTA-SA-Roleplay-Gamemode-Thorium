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
local suspended = false   -- true mientras este de pasajero: ve el trafico del conductor (c_sync.lua)
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
    if peds[ped] then peds[ped] = nil pedCount = pedCount - 1 end
    if isElement(ped) then destroyElement(ped) end
end

local function spawnPed(px, py)
    local node, x, y, z = randomNodeAround(PED_NODES, pedGrid, px, py, CFG.PED_SPAWN_MIN, CFG.PED_SPAWN_MAX)
    if not node or visibleFromCamera(x, y, z) then return end
    local target = nextNode(PED_LINKS, node, nil)
    local tx, ty = nodePos(PED_NODES, target)
    local ped = createPed(pickPedSkin(x, y, z), x, y, z + 1, heading(tx - x, ty - y))
    if not ped then return end
    setElementData(ped, "rp:citizen", true, false)
    peds[ped] = { state = "WALK", node = target, prev = node, brave = math.random() < CFG.BRAVE_CHANCE, until_ = 0 }
    pedCount = pedCount + 1
    setWalking(ped, true, false)
end

local pedSnap = {}   -- posiciones de los peatones (una lectura por tick)

-- "from" es el elemento que asusta o una posicion { x, y } (explosion). El miedo se contagia:
-- los peatones a menos de 14 m huyen tambien (hops = saltos de contagio que quedan).
local function startFlee(ped, from, duration, hops)
    local s = peds[ped]
    if not s or s.state == "DEAD" then return end
    setPedAnimation(ped)
    s.state, s.until_ = "FLEE", getTickCount() + (duration or math.random(8000, 12000))
    if type(from) == "table" then s.threat, s.threatPos = nil, from else s.threat, s.threatPos = from, nil end
    setWalking(ped, true, true)
    hops = hops == nil and 1 or hops
    if hops > 0 then
        local x, y = getElementPosition(ped)
        for other, os in pairs(peds) do
            if other ~= ped and os.state ~= "DEAD" and os.state ~= "FLEE" and os.state ~= "FIGHT" and isElement(other) then
                local ox, oy = getElementPosition(other)
                if (ox - x) ^ 2 + (oy - y) ^ 2 < 196 and math.random() < 0.7 then
                    startFlee(other, from, math.random(4000, 7000), hops - 1)
                end
            end
        end
    end
end

-- Hay un auto en movimiento que viene hacia el peaton? Devuelve el rumbo para apartarse y su distancia
local function carDanger(x, y)
    for _, o in ipairs(carSnap) do
        local v = o[1]
        local dx, dy = x - o[2], y - o[3]
        local d2 = dx * dx + dy * dy
        if d2 < 100 and isElement(v) then
            local vx, vy = getElementVelocity(v)
            local sp = math.sqrt(vx * vx + vy * vy) * 180
            if sp > 12 then
                local ux, uy = vx / math.sqrt(vx * vx + vy * vy), vy / math.sqrt(vx * vx + vy * vy)
                local along = dx * ux + dy * uy            -- el peaton esta delante del auto
                local side = dx * uy - dy * ux             -- + = a la derecha del auto
                if along > 0 and math.abs(side) < 2.8 then
                    -- se aparta de lado, hacia donde ya esta
                    local away = heading(side >= 0 and uy or -uy, side >= 0 and -ux or ux)
                    return away, math.sqrt(d2), sp, v
                end
            end
        end
    end
end

local function idleChance()
    local h = getTime()
    if h >= 22 or h < 6 then return 0.03 end
    if h >= 12 and h < 15 then return 0.12 end
    if h >= 17 and h < 20 then return 0.09 end
    return 0.06
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
    s.state, s.node, s.prev, s.threat, s.threatPos = "WALK", n, nil, nil, nil
    setPedControlState(ped, "fire", false)
    setWalking(ped, true, false)
end

local IDLE_ANIMS = {
    { "ped", "IDLE_chat" }, { "COP_AMBIENT", "Coplook_loop" }, { "ped", "XPRESSscratch" }, { "GANGS", "smkcig_prtl" },
}

-- Camino libre delante del peaton: dos rayos (rodilla y pecho) contra edificios, postes, objetos y autos
local function pedClear(x, y, z, rot, dist)
    local r = math.rad(rot)
    local ex, ey = x - math.sin(r) * dist, y + math.cos(r) * dist
    return isLineOfSightClear(x, y, z - 0.5, ex, ey, z - 0.5, true, true, false, true, false, true, false)
        and isLineOfSightClear(x, y, z + 0.4, ex, ey, z + 0.4, true, true, false, true, false, true, false)
end

-- Gira hacia el primer lado libre (45, 90, 135 grados; empieza por el lado preferido) o nil
local function clearDirection(x, y, z, rot, side)
    for _, delta in ipairs({ 45, 90, 135 }) do
        for _, sg in ipairs({ side, -side }) do
            if pedClear(x, y, z, rot + delta * sg, 1.6) then return rot + delta * sg, sg end
        end
    end
end

local function updatePed(ped, s, now, px, py, pz)
    local x, y, z = getElementPosition(ped)

    if s.state == "WALK" then
        local tx, ty = nodePos(PED_NODES, s.node)
        if getDistanceBetweenPoints2D(x, y, tx, ty) < 1.6 then
            -- Llego al nodo: a veces se queda un rato
            if math.random() < idleChance() then
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
        -- Evita a otros peatones que tiene justo delante (se aparta hacia el lado contrario)
        local rr = math.rad(rot)
        local fx, fy = -math.sin(rr), math.cos(rr)
        for i = 1, #pedSnap do
            local o = pedSnap[i]
            if o[1] ~= ped then
                local dx, dy = o[2] - x, o[3] - y
                local along = dx * fx + dy * fy
                if along > 0 and along < 1.6 then
                    local lat = dx * fy - dy * fx   -- + = el otro esta a mi derecha
                    if math.abs(lat) < 0.9 then rot = rot + (lat > 0 and 40 or -40) break end
                end
            end
        end
        -- Un auto viene hacia el: se aparta y acelera el paso; si esta muy cerca, huye
        local away, cdist, csp, cveh = carDanger(x, y)
        local hurry = false
        if away then
            rot, hurry = away, true
            if cdist < 3.5 and csp > 25 then startFlee(ped, cveh, 3500, 0) return end
        end
        -- Obstaculos (postes, bancos, muros, autos parados): si hay algo a ~1.6 m, rodea por el lado libre
        if s.avoidUntil and now < s.avoidUntil then
            rot = s.avoidRot
        elseif not pedClear(x, y, z, rot, 1.6) then
            local nr, sg = clearDirection(x, y, z, rot, s.avoidSide or (math.random() < 0.5 and 1 or -1))
            if nr then
                s.avoidRot, s.avoidSide, s.avoidUntil = nr, sg, now + 1000
                rot = nr
            end
        end
        -- Atascado (apenas avanza en ~2 s): 1) paso lateral  2) da la vuelta  3) se retira o elige otro camino
        if s.lastWalk and now - s.lastWalk > 1000 then s.posAt = nil end   -- venia de otro estado (idle, huida)
        s.lastWalk = now
        if not s.posAt or now - s.posAt > 2000 then
            if s.posX and getDistanceBetweenPoints2D(x, y, s.posX, s.posY) < 0.6 and not hurry then
                if not s.stuckReset or now > s.stuckReset then s.stuckCount = 0 end
                s.stuckCount, s.stuckReset = (s.stuckCount or 0) + 1, now + 20000
                if s.stuckCount == 1 then
                    local nr, sg = clearDirection(x, y, z, rot, math.random() < 0.5 and 1 or -1)
                    s.avoidRot, s.avoidSide, s.avoidUntil = nr or (rot + 90), sg or 1, now + 1600
                    rot = s.avoidRot
                elseif s.stuckCount == 2 then
                    if s.prev then s.node, s.prev = s.prev, s.node end   -- vuelve por donde vino
                    s.avoidUntil = nil
                else
                    s.stuckCount = 0
                    if not isElementOnScreen(ped) then return removePed(ped) end
                    return resumeWalk(ped, s)
                end
            end
            s.posX, s.posY, s.posAt = x, y, now
        end
        setElementRotation(ped, 0, 0, rot, "default", true)
        setWalking(ped, true, hurry)

    elseif s.state == "IDLE" then
        if now > s.until_ then
            setPedAnimation(ped)
            s.state = "WALK"
            setWalking(ped, true, false)
        end

    elseif s.state == "WATCH" then
        -- curioso: se detiene a mirar un suceso (accidente, pelea...) y luego sigue
        if now > s.until_ then
            setPedAnimation(ped)
            return resumeWalk(ped, s)
        end
        setElementRotation(ped, 0, 0, heading(s.lookX - x, s.lookY - y), "default", true)

    elseif s.state == "FLEE" then
        if now > s.until_ or (not s.threatPos and not isElement(s.threat)) then return resumeWalk(ped, s) end
        local hx, hy
        if s.threatPos then hx, hy = s.threatPos[1], s.threatPos[2] else hx, hy = getElementPosition(s.threat) end
        local rot = heading(x - hx, y - hy) + math.random(-20, 20)
        -- no corre contra una pared: si el camino esta cerrado, rodea hacia un lado
        for _, turn in ipairs({ 0, 70, -70 }) do
            local rr = math.rad(rot + turn)
            if isLineOfSightClear(x, y, z + 0.3, x - math.sin(rr) * 3, y + math.cos(rr) * 3, z + 0.3, true, false, false, false, false, false, false) then
                rot = rot + turn
                break
            end
        end
        setElementRotation(ped, 0, 0, rot, "default", true)
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

-- Explosiones (de cualquiera): los peatones a menos de 45 m huyen de ese punto
addEventHandler("onClientExplosion", root, function(x, y)
    for ped, s in pairs(peds) do
        if s.state ~= "DEAD" and s.state ~= "FIGHT" and isElement(ped) then
            local px, py = getElementPosition(ped)
            if (px - x) ^ 2 + (py - y) ^ 2 < 2025 then startFlee(ped, { x, y }, math.random(9000, 13000), 0) end
        end
    end
end)

----------------------------------------------------------------
-- Trafico
----------------------------------------------------------------
local function removeCar(vehicle)
    local s = cars[vehicle]
    if s then cars[vehicle] = nil carCount = carCount - 1 end
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

----------------------------------------------------------------
-- Red principal: los autos solo entran por tramos desde los que se puede volver a la red grande.
-- Se calcula la mayor componente fuertemente conexa del grafo de ARISTAS dirigidas (un tramo a->b
-- pasa a otro b->c si c no es a y el giro es < ~140 grados, igual que las salidas de un cruce). Quedan
-- fuera los tramos de los que no hay salida sin vuelta en U (callejones, sentidos unicos que mueren,
-- barrios mal enlazados): alli los autos entraban y se quedaban atascados.
----------------------------------------------------------------
mainEdge = {}      -- [a * 100000 + b] = true (tramo de la red principal)

function computeMainEdges()
    local ids, from, to, count = {}, {}, {}, 0
    for a = 1, #VEH_NODES / 3 do
        for _, b in ipairs(VEH_LINKS[a] or {}) do
            if canDrive(a, b) then
                count = count + 1
                ids[a * 100000 + b], from[count], to[count] = count, a, b
            end
        end
    end
    local succ = {}
    for i = 1, count do
        local a, b = from[i], to[i]
        local ax, ay = nodePos(VEH_NODES, a)
        local bx, by = nodePos(VEH_NODES, b)
        local d1x, d1y = dir(ax, ay, bx, by)
        local s = {}
        for _, c in ipairs(VEH_LINKS[b] or {}) do
            local j = c ~= a and ids[b * 100000 + c]
            if j then
                local cx, cy = nodePos(VEH_NODES, c)
                local d2x, d2y = dir(bx, by, cx, cy)
                if d1x * d2x + d1y * d2y > -0.75 then s[#s + 1] = j end
            end
        end
        succ[i] = s
    end
    -- Tarjan iterativo
    local index, low, onStack, comp, compSize = {}, {}, {}, {}, {}
    local stack, counter, ncomp = {}, 0, 0
    for root = 1, count do
        if not index[root] then
            counter = counter + 1
            index[root], low[root] = counter, counter
            stack[#stack + 1], onStack[root] = root, true
            local work = { { root, 1 } }
            while #work > 0 do
                local frame = work[#work]
                local v, children = frame[1], succ[frame[1]]
                local ci = frame[2]
                if ci <= #children then
                    frame[2] = ci + 1
                    local w = children[ci]
                    if not index[w] then
                        counter = counter + 1
                        index[w], low[w] = counter, counter
                        stack[#stack + 1], onStack[w] = w, true
                        work[#work + 1] = { w, 1 }
                    elseif onStack[w] and index[w] < low[v] then
                        low[v] = index[w]
                    end
                else
                    if low[v] == index[v] then
                        ncomp = ncomp + 1
                        local size = 0
                        while true do
                            local w = stack[#stack]
                            stack[#stack] = nil
                            onStack[w] = false
                            comp[w] = ncomp
                            size = size + 1
                            if w == v then break end
                        end
                        compSize[ncomp] = size
                    end
                    work[#work] = nil
                    local parent = work[#work]
                    if parent and low[v] < low[parent[1]] then low[parent[1]] = low[v] end
                end
            end
        end
    end
    local best, bestSize = nil, 0
    for c, size in pairs(compSize) do
        if size > bestSize then best, bestSize = c, size end
    end
    local result = {}
    for i = 1, count do
        if comp[i] == best then result[from[i] * 100000 + to[i]] = true end
    end
    mainEdge = result
    outputDebugString(("[rp_citizens] red vial principal: %d de %d tramos"):format(bestSize, count), 3)
end

local function isMainEdge(a, b)
    return next(mainEdge) == nil or mainEdge[a * 100000 + b] == true
end

-- Tramos cortados por obstaculos fijos (postes caidos, escombros): los autos que se quedan
-- atascados contra algo que no se mueve marcan su tramo y los demas lo evitan un rato.
local blockedEdge = {}
local BLOCK_MS = 180000

function markEdgeBlocked(a, b)
    if a and b then blockedEdge[a * 100000 + b] = getTickCount() + BLOCK_MS end
end

local function isBlockedEdge(a, b)
    local k = a * 100000 + b
    local t = blockedEdge[k]
    if not t then return false end
    if getTickCount() > t then blockedEdge[k] = nil return false end
    return true
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
    -- solo enlaces viales reales que salen de este nodo, en un sentido permitido; primero sin giros mayores
    -- de ~120 grados (casi vueltas en U) y solo si no queda ninguna salida se aceptan hasta ~140.
    -- Si el auto va por la red principal, solo elige salidas que tambien sean de la red principal
    -- (nunca entra a callejones ni barrios sin salida); si no hay ninguna, usa cualquiera.
    local onMain = next(mainEdge) ~= nil and mainEdge[prev * 100000 + node] == true
    -- tramos cortados (postes caidos, obstaculos fijos): se evitan si hay otra salida
    for _, avoid in ipairs({ true, false }) do
    for _, onlyMain in ipairs(onMain and { true, false } or { false }) do
        for _, limit in ipairs({ -0.5, -0.75 }) do
            for _, n in ipairs(VEH_LINKS[node] or {}) do
                if n ~= prev and canDrive(node, n) and (not onlyMain or isMainEdge(node, n)) and not (avoid and isBlockedEdge(node, n)) then
                    local qx, qy = nodePos(VEH_NODES, n)
                    local d2x, d2y = dir(nx, ny, qx, qy)
                    local dot = d1x * d2x + d1y * d2y
                    if dot > limit then
                        local w = dot > 0.85 and 4 or dot > 0.3 and 2 or 1
                        -- orden aleatorio ponderado (Efraimidis-Spirakis): mayor peso -> antes
                        options[#options + 1] = { n, math.random() ^ (1 / w) }
                    end
                end
            end
            if #options > 0 then break end
        end
        if #options > 0 then break end
    end
    if #options > 0 then break end
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
-- half > 0: comprueba tambien dos lineas paralelas a +-half m (el ancho del auto), para que la
-- trayectoria no roce postes, semaforos ni esquinas.
local function maneuverClear(pts, sx, sy, sz, half)
    local offs = (half and half > 0) and { 0, half, -half } or { 0 }
    local function segClear(ax, ay, az, bx, by, bz)
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        local nx, ny = 0, 0
        if len > 0.01 then nx, ny = -dy / len, dx / len end
        for _, o in ipairs(offs) do
            if not isLineOfSightClear(ax + nx * o, ay + ny * o, az + 1.0, bx + nx * o, by + ny * o, bz + 1.0,
                true, false, false, false, false, true, false) then
                return false
            end
        end
        return true
    end
    local lx, ly, lz = sx, sy, sz
    for i = 1, #pts, 2 do
        local p = pts[i]
        if lx and not segClear(lx, ly, lz, p[1], p[2], p[3]) then return false end
        lx, ly, lz = p[1], p[2], p[3]
    end
    local p = pts[#pts]
    return segClear(lx, ly, lz, p[1], p[2], p[3])
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
function computeTurnPoints(A, B, C, rScale)
    local ax, ay = nodePos(VEH_NODES, A)
    local bx, by, bz = nodePos(VEH_NODES, B)
    local cx, cy = nodePos(VEH_NODES, C)
    local d1x, d1y, len1 = dir(ax, ay, bx, by)
    local d2x, d2y, len2 = dir(bx, by, cx, cy)
    local _, off1 = getLaneInfo(A, B)
    local _, off2 = getLaneInfo(B, C)
    local turn = math.deg(math.acos(math.max(-1, math.min(1, d1x * d2x + d1y * d2y))))
    -- radio de la curva: mayor en cruces para que el giro sea amplio y claro
    -- Giro a la derecha: radio original (un arco mas amplio corta la esquina y mete al auto en la acera
    -- o la bencinera). Giro a la izquierda: algo mas amplio por el centro del cruce.
    local leftTurn = (d1x * d2y - d1y * d2x) > 0.2
    -- En tramos cortos (cruces con muchos nodos, giros en S) el limite de 0.48 x largo dejaba arcos de
    -- 3-4 m de radio, menos de lo que el auto puede girar: se salia recto. Se permite hasta 0.6 x largo
    -- (y 8 m como piso) para mantener un radio realista; el solape entre dos arcos seguidos es minimo.
    local cap1 = math.max(len1 * 0.48, math.min(len1 * 0.6, 8))
    local cap2 = math.max(len2 * 0.48, math.min(len2 * 0.6, 8))
    local R = math.min((isJunction(B) and (leftTurn and 14 or 12) or 9) * (rScale or 1), cap1, cap2)
    if C == A then R = math.min(R, 4) end
    local junction = isJunction(B) and B or nil

    local pts = {}
    local ex, ey = bx - d1x * R + d1y * off1, by - d1y * R - d1x * off1
    local xx, xy = bx + d2x * R + d2y * off2, by + d2y * R - d2x * off2
    -- Si el tramo termina en un semaforo, E es la linea de detencion (campo 6 = eje)
    local axis = nil
    if getLight(A, B) > 0 then axis = math.abs(d1x) > math.abs(d1y) and "ew" or "ns" end
    local man = junction and { d1x, d1y, d2x, d2y, turn } or nil   -- maniobra (para la prioridad en cruces)
    pts[1] = { ex, ey, bz, 0, junction, axis, man }
    if turn < 10 then
        pts[2] = { xx, xy, bz, 0, junction, nil, man }
    else
        local qx, qy = intersect(ex, ey, d1x, d1y, xx, xy, -d2x, -d2y)
        if not qx then qx, qy = bx + (d1y * off1 + d2y * off2) / 2, by - (d1x * off1 + d2x * off2) / 2 end
        local steps = math.max(5, math.ceil(turn / 10))
        for i = 1, steps do
            local t = i / steps
            local u = 1 - t
            pts[#pts + 1] = { u * u * ex + 2 * u * t * qx + t * t * xx, u * u * ey + 2 * u * t * qy + t * t * xy, bz, turn, junction, nil, man }
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
    -- 1) con el ancho del auto (no roza postes ni semaforos de la esquina); la salida preferida prueba
    --    ademas arcos mas abiertos o cerrados  2) solo con la linea central (como antes)
    for pass = 1, 2 do
        for k, cand in ipairs(candidates) do
            for _, sc in ipairs((pass == 1 and k == 1) and { 1, 1.35, 0.75 } or { 1 }) do
                local p = computeTurnPoints(A, B, cand, sc)
                if maneuverClear(p, p[1][1], p[1][2], p[1][3], pass == 1 and 1.1 or 0) then C, pts = cand, p break end
            end
            if C then break end
        end
        if C then break end
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
-- Prioridad real: pueden estar varios a la vez si sus trayectorias no se cruzan
-- (misma direccion de entrada; dos autos de frente que van recto o giran a la derecha).
-- Un giro a la izquierda cede ante el que viene de frente; los cruces perpendiculares
-- se turnan por orden de llegada.
local junctionLock = {}    -- [nodo] = { [vehiculo] = { man = maniobra, t = tick } }
local LOCK_TIMEOUT = 5000   -- ms sin moverse (se renueva mientras el titular avanza)
local junctionWait = {}    -- [nodo] = { [vehiculo] = { since, seen, man } } turnos de espera (el que llego antes pasa antes)

-- man = { d1x, d1y, d2x, d2y, turn }: direccion de entrada y de salida del cruce
local function maneuversConflict(a, b)
    if not a or not b then return true end
    local e = a[1] * b[1] + a[2] * b[2]
    if e > 0.8 then return false end                 -- misma direccion: hacen cola, no se cruzan
    if e < -0.8 then                                  -- de frente: solo choca un giro a la izquierda
        local la = a[1] * a[4] - a[2] * a[3] > 0.35
        local lb = b[1] * b[4] - b[2] * b[3] > 0.35
        return la or lb
    end
    return true                                       -- perpendiculares u otros: se turnan
end

-- moving: el titular avanza (renueva su reserva; si se queda parado, la pierde pasado LOCK_TIMEOUT)
local function tryLock(node, vehicle, now, man, moving)
    local holders = junctionLock[node]
    if not holders then holders = {} junctionLock[node] = holders end
    local mine = holders[vehicle]
    if mine then
        -- ya esta dentro del cruce: no se le vuelve a negar el paso
        mine.man = man
        if moving then mine.t = now end
        return true
    end
    for v, h in pairs(holders) do
        if not isElement(v) or not cars[v] or now - h.t > LOCK_TIMEOUT then
            holders[v] = nil
        elseif maneuversConflict(man, h.man) then
            -- tambien deja constancia de que espera (para el turno)
            local waits = junctionWait[node]
            if not waits then waits = {} junctionWait[node] = waits end
            local w = waits[vehicle]
            if not w then w = { since = now } waits[vehicle] = w end
            w.seen, w.man = now, man
            return false
        end
    end
    -- Turno: si otro auto con maniobra incompatible espera desde antes, pasa primero
    local waits = junctionWait[node]
    if not waits then waits = {} junctionWait[node] = waits end
    local w = waits[vehicle]
    if not w then w = { since = now } waits[vehicle] = w end
    w.seen, w.man = now, man
    for v, o in pairs(waits) do
        if v ~= vehicle then
            if not isElement(v) or not cars[v] or now - o.seen > 700 then
                waits[v] = nil
            elseif o.since < w.since - 400 and maneuversConflict(man, o.man) then
                return false
            end
        end
    end
    waits[vehicle] = nil
    holders[vehicle] = { man = man, t = now }
    return true
end

local function releaseLocks(vehicle)
    for _, holders in pairs(junctionLock) do holders[vehicle] = nil end
    for _, waits in pairs(junctionWait) do waits[vehicle] = nil end
end

-- "No bloquear el cruce": hay un auto justo despues de la salida del cruce? Entonces no entra
-- (se quedaria parado en medio y bloquearia a todos). Devuelve true si la salida esta ocupada.
local function exitBlocked(vehicle, wp, node)
    local last
    for i = 1, #wp do
        if wp[i][5] == node then last = i elseif last then break end
    end
    if not last then return false end
    local ex, ey = wp[last][1], wp[last][2]
    local nx, ny = ex, ey
    local nxt = wp[last + 1]
    if nxt then
        local dx, dy = dir(ex, ey, nxt[1], nxt[2])
        nx, ny = ex + dx * 5, ey + dy * 5
    end
    local r2 = 5.5 * 5.5
    for _, o in ipairs(carSnap) do
        if o[1] ~= vehicle and ((o[2] - nx) ^ 2 + (o[3] - ny) ^ 2 < r2 or (o[2] - ex) ^ 2 + (o[3] - ey) ^ 2 < r2) then return true end
    end
    local ps = playerSnap
    if ps[2] and ps[1] ~= vehicle and ((ps[2] - nx) ^ 2 + (ps[3] - ny) ^ 2 < r2 or (ps[2] - ex) ^ 2 + (ps[3] - ey) ^ 2 < r2) then return true end
    return false
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
    -- Nunca salta a una via lejana: primero carriles a menos de 7 m (casi paralelos y luego hasta ~75
    -- grados); solo si no hay ninguno, hasta 22 m.
    for _, p in ipairs({ { 0.6, 7 }, { 0.25, 7 }, { 0.6, 22 }, { 0.25, 22 } }) do
        local n, t = nearestLaneAligned(x, y, fx, fy, p[1], p[2])
        if n then return n, t end
    end
    return nil
end

function nearestLaneAligned(x, y, fx, fy, minAlign, maxLat)
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
                            if canDrive(n, m) and isMainEdge(n, m) and not isBlockedEdge(n, m) then
                                local mx, my = nodePos(VEH_NODES, m)
                                local dx, dy, len = dir(nx, ny, mx, my)
                                local aligned = dx * fx + dy * fy
                                local ahead = (mx - x) * fx + (my - y) * fy
                                if aligned > minAlign and ahead > -3 then
                                    -- distancia del auto a la recta del tramo (lateral) y si queda dentro del tramo
                                    local t = ((x - nx) * dx + (y - ny) * dy)
                                    local px, py = nx + dx * math.max(0, math.min(len, t)), ny + dy * math.max(0, math.min(len, t))
                                    local lat = getDistanceBetweenPoints2D(x, y, px, py)
                                    local score = lat + (1 - aligned) * 15
                                    if lat <= maxLat and score < bestScore then best, bestTarget, bestScore = n, m, score end
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
    -- motos: se inclinan y pierden el agarre antes que un auto; entran mas despacio a las curvas
    local vt = getVehicleType(vehicle)
    if vt == "Bike" or vt == "BMX" or vt == "Quad" then return 0.75 end
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
        if canDrive(node, n) and isMainEdge(node, n) and not isBlockedEdge(node, n) then target = n break end
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
    setElementData(vehicle, "rp:citizen", true, false)
    setElementData(driver, "rp:citizen", true, false)
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

function clearSignal(vehicle, s)
    if s.signalApplied then setElementData(vehicle, "rp:indicator", false, false) end
    s.signal, s.signalApplied, s.signalClearAt = nil, nil, nil
end

function makeDummy(vehicle, s, speedMs)
    clearSignal(vehicle, s)
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

----------------------------------------------------------------
-- ARBITRO DE MANIOBRAS: un solo responsable de "que esta haciendo el auto ahora".
-- Maniobras que alteran la ruta o el movimiento (REVERSE, REJOIN, DETOUR): solo una activa a la vez,
-- por prioridad, con tiempo de enfriamiento entre repeticiones. Antes cada regla (atasco, choque, fuera de
-- ruta, obstaculo...) las disparaba por su cuenta y se pisaban entre si: retroceder + reenganchar + desviar
-- al mismo tiempo, vueltas atras, etc. Todas pasan ahora por manCan / manSet / manEnd.
--   prioridad: REVERSE 4 > REJOIN 3 > DETOUR 2  (una de mayor prioridad interrumpe a la menor)
----------------------------------------------------------------
local MAN_PRI = { DETOUR = 2, REJOIN = 3, REVERSE = 4 }
local MAN_COOLDOWN = { REVERSE = 1200, REJOIN = 2000, DETOUR = 2500 }   -- ms tras terminar la misma maniobra

local function manActive(s, now)
    local m = s.man
    if m and now >= m.untilT then
        s.manEnded = s.manEnded or {}
        s.manEnded[m.kind] = now
        s.man = nil
        return nil
    end
    return m
end

-- Puede empezar la maniobra "kind" ahora?
local function manCan(s, kind, now)
    if s.state == "ABANDONED" then return false end
    local act = manActive(s, now)
    if act and act.kind == kind then return true end                       -- refrescar la misma
    if act and MAN_PRI[act.kind] >= MAN_PRI[kind] then return false end    -- hay una igual o mas importante
    local last = s.manEnded and s.manEnded[kind]
    if last and now - last < (MAN_COOLDOWN[kind] or 0) then return false end
    return true
end

local function manSet(s, kind, now, ms)
    local act = manActive(s, now)
    s.man = { kind = kind, since = (act and act.kind == kind) and act.since or now, untilT = now + ms }
end

local function manEnd(s, kind, now)
    if s.man and s.man.kind == kind then
        s.manEnded = s.manEnded or {}
        s.manEnded[kind] = now
        s.man = nil
    end
end

-- Esta activa ahora la maniobra "kind"?
local function manIs(s, kind, now)
    local m = s.man
    return m ~= nil and m.kind == kind and now < m.untilT
end

local clearPath   -- se define mas abajo (linea libre con el ancho del auto)

-- Trayectoria suave para volver al carril desde donde esta el auto: va cerrando el error lateral
-- poco a poco (perfil suave) a lo largo del carril, en vez de apuntar recto a un punto del carril
-- (eso lo hacia cruzar bordillos, postes y semaforos como atraido por un iman).
-- Prueba largos cada vez mayores hasta encontrar uno sin obstaculos; nil si ninguno esta libre.
local function rejoinPoints(vehicle, x, y, z, n, target)
    local sx, sy, sz, dx, dy = laneStart(n, target)
    local tx, ty = nodePos(VEH_NODES, target)
    local len = math.max(1, getDistanceBetweenPoints2D(sx, sy, tx, ty))
    local t0 = (x - sx) * dx + (y - sy) * dy          -- avance del auto sobre el carril
    local e = (x - sx) * -dy + (y - sy) * dx           -- error lateral con signo (+ = izquierda del carril)
    local nx, ny = -dy, dx
    local ae = math.abs(e)
    local STEPS = 5
    for _, L in ipairs({ 8 + ae * 2, 14 + ae * 3, 22 + ae * 4 }) do
        local pts, ok = {}, true
        local px, py = x, y
        for i = 1, STEPS do
            local f = i / STEPS
            local t = math.min(t0 + L * f, len - 2)
            local k = f * (2 - f)                       -- cierra el error lateral pronto y llega suave al carril
            local qx = sx + dx * t + nx * e * (1 - k)
            local qy = sy + dy * t + ny * e * (1 - k)
            if not clearPath(px, py, z, qx, qy, z, vehicle) then ok = false break end
            pts[#pts + 1] = { qx, qy, sz, 25, nil }
            px, py = qx, qy
        end
        if ok then return pts end
    end
    return nil
end

-- Vuelve al carril mas cercano y descarta la ruta (se recalcula desde ahi)
local function reattach(vehicle, s, teleport, force)
    -- el reenganche normal pasa por el arbitro (no mientras retrocede, ni repetido sin pausa);
    -- "force" (sin ruta) y el teletransporte lo saltan
    if not teleport and not force and not manCan(s, "REJOIN", getTickCount()) then return end
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
        manSet(s, "REJOIN", getTickCount(), 4000)
        local _, _, vz0 = getElementPosition(vehicle)
        local pts = rejoinPoints(vehicle, x, y, vz0, n, target)
        if pts then
            s.wp = pts
        else
            local sx, sy, sz, dx, dy = laneStart(n, target)
            local nx2, ny2 = nodePos(VEH_NODES, target)
            local len = math.max(1, getDistanceBetweenPoints2D(sx, sy, nx2, ny2))
            local t = math.max(0, math.min(len - 8, (x - sx) * dx + (y - sy) * dy + 8))
            s.wp[1] = { sx + dx * t, sy + dy * t, sz, 0, nil }
        end
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
    clearSignal(vehicle, s)
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
-- brake_reverse es freno si el auto avanza, pero MARCHA ATRAS si esta parado o rodando hacia atras:
-- por eso nunca se usa como freno cuando el auto no avanza (ver "fwd" en updateCar). El freno de mano
-- detiene un auto que rueda hacia atras sin querer.
-- accel / brake: true/false o un valor 0..1 (parcial = control analogico, mas suave que todo o nada)
local function setPedalAxis(driver, control, v)
    v = (v == true and 1) or (v == false and 0) or (tonumber(v) or 0)
    if v >= 0.95 then
        setPedControlState(driver, control, true)
    elseif v > 0.05 then
        setPedControlState(driver, control, false)
        setPedAnalogControlState(driver, control, v)
    else
        setPedControlState(driver, control, false)
    end
end

local function setPedal(driver, accel, brake, handbrake)
    setPedalAxis(driver, "accelerate", accel)
    setPedalAxis(driver, "brake_reverse", brake)
    setPedControlState(driver, "handbrake", handbrake or false)
end

local function steerTo(driver, value)
    value = math.max(-1, math.min(1, value))
    setPedAnalogControlState(driver, "vehicle_left", value > 0 and value or 0)
    setPedAnalogControlState(driver, "vehicle_right", value < 0 and -value or 0)
end

----------------------------------------------------------------
-- ACTUADOR UNICO: es el unico sitio donde se escriben volante y pedales de un auto de la poblacion.
-- El resto de updateCar solo DECIDE (modo, velocidad objetivo, volante deseado); aqui se ejecuta.
----------------------------------------------------------------
-- Acelerador y freno proporcionales al error de velocidad (arranque y frenada progresivos).
-- Si rueda hacia atras sin que sea una maniobra: lo frena y, si quiere avanzar, acelera hacia delante
-- (NUNCA pisa marcha atras).
local function pedalsFor(fwd, target, inCurve)
    if fwd < -1.5 then return target > 5, false, target <= 5 end
    local err = target - fwd
    local accel, brake = 0, 0
    if target == 0 then
        brake = fwd > 1 and 1 or 0
    elseif err > 1 then
        accel = math.min(1, 0.3 + err / 12)
    elseif err < (inCurve and -3 or -6) then
        brake = math.min(1, (-err - (inCurve and 3 or 6)) / 15 + 0.2)
    end
    return accel, brake, false
end

local function actuate(driver, s, accel, brake, hand, steerOverride)
    steerTo(driver, steerOverride or s.steerOut or 0)
    setPedal(driver, accel, brake, hand)
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
-- Hay algo (auto, peaton, objeto o pared) justo detras del auto? Tres rayos: centro y esquinas.
function rearBlocked(vehicle, m, reach)
    local fx, fy = m[2][1], m[2][2]
    local sx, sy, sz = m[4][1] - fx * 2.4, m[4][2] - fy * 2.4, m[4][3] + 0.3
    for _, off in ipairs({ 0, 0.9, -0.9 }) do
        local ox, oy = m[1][1] * off, m[1][2] * off
        if processLineOfSight(sx + ox, sy + oy, sz, sx + ox - fx * reach, sy + oy - fy * reach, sz,
            true, true, true, true, false, true, false, false, vehicle) then
            return true
        end
    end
    return false
end

-- Empieza una marcha atras corta solo si detras esta libre
function startReverse(vehicle, s, now, ms, steer, m)
    if not manCan(s, "REVERSE", now) then return false end
    if rearBlocked(vehicle, m, 3.5) then return false end
    manSet(s, "REVERSE", now, ms + 300)
    s.recoverUntil, s.recoverSteer, s.recoverPos = now + ms, steer, nil
    return true
end

-- Seguimiento de trayectoria: devuelve el error de rumbo (grados, + = girar a la izquierda)
-- respecto de la ruta unos metros por delante, corregido por la distancia lateral (tipo Stanley).
-- Rastro de los ultimos puntos que el auto dejo atras (hasta 6, en orden). Los puntos se descartan cuando
-- quedan a menos de la distancia de mirada DELANTE del auto (hasta ~10 m a 40 km/h), asi que "el ultimo
-- punto pasado" puede estar bastante por delante de el. Medir la desviacion o el rumbo contra una recta que
-- empieza en ese punto daba 8-10 m de desviacion falsa en pleno carril (frenaba y reenganchaba sin motivo).
-- Con el rastro, la poligonal sigue pasando por el auto.
local function pushPassed(s, p)
    s.lastPassed = p
    local t = s.trail
    if not t then t = {} s.trail = t end
    t[#t + 1] = p
    if #t > 6 then table.remove(t, 1) end
end

function pathTrack(s, wp, x, y, speed, rz)
    local pts = {}
    if s.trail and s.lastPassed then
        for _, tp in ipairs(s.trail) do pts[#pts + 1] = tp end
    elseif s.lastPassed then
        pts[1] = s.lastPassed
    end
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
    return angleDiff(desired, rz), e, ux, uy   -- tambien el error lateral y la direccion del tramo (para pegarse a la linea)
end

-- Velocidad maxima (km/h) para entrar a una curva de "turn" grados que esta a "dist" m:
-- la velocidad dentro de la curva (cuanto mas cerrada, menos) mas lo que se puede
-- frenar en esa distancia (~4 m/s2), para que empiece a frenar con tiempo suficiente.
-- Asi nunca llega a un giro cerrado demasiado rapido y se sale recto.
function curveCap(turn, dist, lenF)
    -- lenF < 1 en vehiculos largos (camiones, buses): giran mas abierto, entran mas despacio
    local inside = math.max(turn >= 70 and 8 or 10, CFG.CAR_SPEED * (1 - turn / 115)) * (lenF or 1)
    return math.sqrt(inside * inside + 60 * math.max(0, dist - 2))
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
-- Linea libre con el ancho del auto: tres rayos paralelos (centro y a +-1.1 m). Con uno solo se
-- colaban postes, semaforos y bordes a los lados del trazado.
function clearPath(x1, y1, z1, x2, y2, z2, vehicle)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return true end
    local nx, ny = -dy / len, dx / len
    for _, off in ipairs({ 0, 1.1, -1.1 }) do
        if not isLineOfSightClear(x1 + nx * off, y1 + ny * off, z1 + 0.6, x2 + nx * off, y2 + ny * off, z2 + 0.6,
            true, true, true, true, false, true, false, vehicle) then
            return false
        end
    end
    return true
end

-- Perfil lateral suave (0 -> 1) para entrar y salir del desvio sin quiebres
local function smooth(t) t = math.max(0, math.min(1, t)) return t * t * (3 - 2 * t) end

local function tryDetour(vehicle, s, m)
    if not manCan(s, "DETOUR", getTickCount()) then return false end
    local x, y, z = m[4][1], m[4][2], m[4][3]
    local fx, fy = m[2][1], m[2][2]
    local lx, ly = -fy, fx                          -- izquierda del auto
    local wp = s.wp
    -- Sin desvios cerca de un cruce o una curva: el desvio se reincorpora a un punto a mas de 30 m y
    -- se salta los puntos de la curva en medio, dejando una recta diagonal a traves del cruce (que el
    -- auto sigue aunque no sea el camino). En esos casos se espera, se retrocede o se atraviesa.
    do
        local dd, qx, qy = 0, x, y
        for i = 1, #wp do
            dd = dd + getDistanceBetweenPoints2D(qx, qy, wp[i][1], wp[i][2])
            qx, qy = wp[i][1], wp[i][2]
            if dd > 45 then break end
            if wp[i][4] > 15 or wp[i][5] then return false end
        end
    end
    -- punto de reincorporacion: el primero de la ruta a mas de 30 m (margen para volver con calma)
    local rejoin = nil
    for i = 1, #wp do
        if getDistanceBetweenPoints2D(x, y, wp[i][1], wp[i][2]) > 30 then rejoin = i break end
    end
    if not rejoin then return false end
    local rx, ry, rz = wp[rejoin][1], wp[rejoin][2], wp[rejoin][3]

    -- Cada candidato: separacion lateral maxima. Los puntos siguen un perfil suave (entra, mantiene y
    -- vuelve al carril) a 4, 9, 14, 19 y 24 m; el ultimo queda casi sobre la ruta original.
    local STEPS = { { 4, 0.25 }, { 9, 0.75 }, { 14, 1.0 }, { 19, 0.75 }, { 24, 0.25 } }
    for _, side in ipairs({ 4.5, 6.5, -4, -6.5, 8.5 }) do
        local pts, ok = {}, true
        local px, py = x, y
        for _, st in ipairs(STEPS) do
            local qx, qy = x + fx * st[1] + lx * side * smooth(st[2]), y + fy * st[1] + ly * side * smooth(st[2])
            -- el suelo debe estar a la altura de la calzada (sin bordillos altos ni zanjas)
            local ground = getGroundPosition(qx, qy, z + 3)
            if not (ground and ground ~= 0 and math.abs(ground - (z - 0.5)) < 1.2) then ok = false break end
            if not clearPath(px, py, z, qx, qy, z, vehicle) then ok = false break end
            pts[#pts + 1] = { qx, qy, z, 25 }
            px, py = qx, qy
        end
        if ok and clearPath(px, py, z, rx, ry, rz, vehicle) then
            -- reemplaza el tramo bloqueado por el desvio (giro 25 = va despacio)
            for _ = 1, rejoin - 1 do table.remove(wp, 1) end
            manSet(s, "DETOUR", getTickCount(), 6000)
            s.lastPassed = nil
            for k = #pts, 1, -1 do table.insert(wp, 1, pts[k]) end
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- CONDUCCION POR ETAPAS (cada auto, cada tick de IA):
--   senseSelf     lee la fisica del auto (velocidad, posicion, rumbo)
--   stageGuards   volcado / inclinacion / choque con algo fijo (pide retroceso al arbitro)
--   stageReverse  ejecuta la maniobra REVERSE si esta activa (toma el control del tick)
--   stageRoute    PERCEPCION de la ruta: puntos, desviacion, nodos saltados, rumbo deseado
--   stageAhead    PERCEPCION de lo que viene y de los sensores: curvas, cruce, semaforo, obstaculos
--   stageAssist   ayudas de fisica (intermitentes, derrape, giro asistido)
--   stageDecide   DECISION: volante, modo, velocidad objetivo, cruces, obstaculos, atascos
--   actuate       ACTUADOR: unico sitio que escribe volante y pedales
-- Las etapas se pasan los datos en la tabla "f" (s.f, reutilizada cada tick). Devuelven false si el auto
-- fue retirado o abandonado y el tick debe terminar.
----------------------------------------------------------------
----------------------------------------------------------------
-- TELEMETRIA DE FALLOS (/trafico_tel): cada auto guarda las ultimas ~2 s de decisiones (25 muestras, una por
-- tick de IA). Cuando falla (se sale de la linea poco despues de una curva, choca con algo fijo) o cuando lo
-- pides con "/trafico_tel dump" (auto de la poblacion mas cercano), escribe UNA linea en clientscript.log:
--   [rp_citizens][TEL] motivo ... | muestras: ms-antes km/h volante dev dif objetivo modo curva giro
-- Con eso se ve si fallo por velocidad de entrada, volante saturado, geometria de la curva o un obstaculo.
----------------------------------------------------------------
local TEL = { on = true, dumps = 0, MAX = 80, N = 25 }

local function telRecord(s, now, speed, diff, target, inCurve, wpTurn, rz)
    local t = s.tel
    if not t then t = { n = 0, i = 0 } s.tel = t end
    t.i = t.i % TEL.N + 1
    t.n = math.min(t.n + 1, TEL.N)
    t[t.i] = { now, speed, s.steerOut or 0, s.devNow or 0, diff or 0, target or 0, s.state or "?", inCurve and 1 or 0, wpTurn or 0, rz or 0 }
end

local function telDump(vehicle, s, why, now, force)
    if not TEL.on and not force then return end
    if not force and (TEL.dumps >= TEL.MAX or now - (s.telLast or -1e9) < 15000) then return end
    local t = s.tel
    if not t or t.n == 0 then return end
    s.telLast = now
    TEL.dumps = TEL.dumps + 1
    local out = {}
    for k = t.n, 1, -1 do
        local idx = (t.i - (k - 1) - 1) % TEL.N + 1
        local e = t[idx]
        if e then
            out[#out + 1] = ("-%d %.0f %.2f %.1f %.0f %.0f %s %d %.0f r%.0f"):format(now - e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10])
        end
    end
    local x, y, _, rz = 0, 0, 0, 0
    if isElement(vehicle) then
        x, y = getElementPosition(vehicle)
        local _, _, r = getElementRotation(vehicle)
        rz = r
    end
    local wp = s.wp or {}
    local pts = {}
    for k = 1, math.min(#wp, 4) do pts[#pts + 1] = ("(%.0f,%.0f,g%.0f)"):format(wp[k][1], wp[k][2], wp[k][4]) end
    local lp = s.lastPassed
    outputDebugString(("[rp_citizens][TEL] %s modelo %d%s nodos %s->%s pos (%.0f,%.0f) rumbo %.0f lenF %.2f man %s lp %s wp %s | muestras(ms km/h volante dev dif obj modo curva giro rumbo): %s")
        :format(why, isElement(vehicle) and getElementModel(vehicle) or 0, s.bike and " (moto)" or "", tostring(s.prev), tostring(s.node), x, y, rz, s.lenF or 1,
            s.man and s.man.kind or "-", lp and ("(%.0f,%.0f,g%.0f)"):format(lp[1], lp[2], lp[4]) or "nil", table.concat(pts, " "), table.concat(out, " | ")), 3)
end

addCommandHandler("trafico_tel", function(_, arg)
    if arg == "dump" then
        -- el auto de la poblacion mas cercano (a menos de 60 m)
        local px, py = getElementPosition(localPlayer)
        local best, bs, bd = nil, nil, 3600
        for v, st in pairs(cars) do
            if isElement(v) then
                local x, y = getElementPosition(v)
                local d = (x - px) ^ 2 + (y - py) ^ 2
                if d < bd then best, bs, bd = v, st, d end
            end
        end
        if best then
            telDump(best, bs, "manual", getTickCount(), true)
            outputChatBox("[Trafico] Telemetria del auto mas cercano escrita en clientscript.log ([rp_citizens][TEL]).", 120, 200, 255)
        else
            outputChatBox("[Trafico] No hay autos de la poblacion a menos de 60 m.", 255, 140, 90)
        end
    else
        TEL.on = not TEL.on
        outputChatBox(("[Trafico] Telemetria de fallos: %s (%d registros). Usa /trafico_tel dump para el auto mas cercano.")
            :format(TEL.on and "ACTIVADA" or "apagada", TEL.dumps), 120, 200, 255)
    end
end)

local function senseSelf(vehicle, f)
    local speed = speedOf(vehicle)
    local x, y = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    local m = getElementMatrix(vehicle)
    -- velocidad con signo: > 0 avanza, < 0 rueda hacia atras
    local fvx, fvy = getElementVelocity(vehicle)
    f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m = speed, x, y, rx, ry, rz, m
    f.fwd = (fvx * m[2][1] + fvy * m[2][2]) * 180
end

local function stageGuards(vehicle, s, f, now)
    local speed, x, y, rx, ry, rz, m, fwd = f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m, f.fwd
    -- Volcado: el conductor huye y el auto queda abandonado
    if m[3][3] < 0.3 then abandonCar(vehicle, s) return false end
    -- Inclinado sobre dos ruedas (montado sobre otro auto) y casi parado: tambien se abandona
    if m[3][3] < 0.6 and speed < 6 then
        s.tiltSince = s.tiltSince or now
        if now - s.tiltSince > 3000 then abandonCar(vehicle, s) return false end
    else
        s.tiltSince = nil
    end

    -- Choco con algo fijo (poste, pared) y casi se detuvo: retrocede enseguida y se reengancha al carril
    -- (antes seguia empujando contra el poste hasta que el temporizador de atasco, 3 s, reaccionaba).
    if s.wallHitAt then
        if now - s.wallHitAt > 900 then
            s.wallHitAt = nil
        elseif speed < 12 and now > s.recoverUntil then
            s.wallHitAt = nil
            telDump(vehicle, s, "choque_fijo", now)
            if startReverse(vehicle, s, now, 1000, s.steerOut or 0, m) then
                s.needReattach = true
                s.stuckSince = 0
            end
        end
    end

    return true
end

-- true = la marcha atras tomo el control de este tick
local function stageReverse(vehicle, s, f, now)
    local driver = s.driver
    local speed, x, y, rx, ry, rz, m, fwd = f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m, f.fwd
    -- Marcha atras corta (como mucho ~1 s / 3-4 m) solo cuando esta atascado de verdad.
    -- No se reengancha al terminar: sigue con su ruta (solo se recalcula si se alejo de ella).
    if now < s.recoverUntil then
        setPedControlState(driver, "horn", false)
        local revSteer = -(s.recoverSteer or 0)
        local vx, vy = getElementVelocity(vehicle)
        local backing = (vx * m[2][1] + vy * m[2][2]) * 180
        s.recoverPos = s.recoverPos or { x, y }
        -- la marcha atras es corta (como mucho ~2.5 m) y se corta al instante si aparece algo detras
        -- (auto, peaton, objeto o pared); despues se busca otra forma de pasar (desvio o nueva ruta)
        if getDistanceBetweenPoints2D(x, y, s.recoverPos[1], s.recoverPos[2]) > 2.5
            or rearBlocked(vehicle, m, 1.8 + math.max(0, -backing) * 0.06) then
            s.recoverUntil, s.recoverPos, s.afterReverse = 0, nil, now
            manEnd(s, "REVERSE", now)
            actuate(driver, s, backing < -1, false, false, revSteer)
            return true
        end
        actuate(driver, s, false, backing > -10, false, revSteer)       -- no supera ~10 km/h marcha atras
        return true
    end
    s.recoverPos = nil
    -- fin del retroceso (por tiempo): libera la maniobra para que el reenganche pendiente pueda empezar
    if now >= s.recoverUntil then manEnd(s, "REVERSE", now) end
    if s.needReattach and manCan(s, "REJOIN", now) then
        reattach(vehicle, s, false)
        s.needReattach = nil
    elseif s.needReattach and now - (s.needReattachAt or now) > 3000 then
        s.needReattach = nil   -- no pudo empezar en 3 s: se descarta (otra regla ya se ocupa)
    end
    if s.needReattach then s.needReattachAt = s.needReattachAt or now else s.needReattachAt = nil end

    return false
end

local function stageRoute(vehicle, s, f, now)
    local driver = s.driver
    local speed, x, y, rx, ry, rz, m, fwd = f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m, f.fwd
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
        actuate(driver, s, false, fwd > 1, fwd < -1, 0)
        if now - s.noRouteSince > 800 and now - (s.lastReattach or 0) > 2000 then
            s.lastReattach = now
            reattach(vehicle, s, false)
            if not cars[vehicle] then return false end
        end
        if now - s.noRouteSince > 6000 then
            if isElementOnScreen(vehicle) then abandonCar(vehicle, s) return false end
            removeCar(vehicle) return false
        end
        return false
    end
    s.noRouteSince = nil
    -- Fuera de su carril (esquive, choque, derrape): tras 1.5 s se reengancha al carril mas
    -- cercano por delante; si sigue muy lejos de la ruta, se elimina aunque se vea (reaparece otro)
    -- desviacion = distancia al tramo entre el ultimo punto pasado y el siguiente (no solo al siguiente:
    -- en un cruce recto hay hasta ~24 m entre puntos y eso no es salirse de la ruta)
    -- Distancia al camino: minimo sobre la poligonal (ultimo punto pasado, si esta cerca) + proximos puntos
    local lp = s.lastPassed
    if lp and getDistanceBetweenPoints2D(x, y, lp[1], lp[2]) > 60 then lp = nil end
    if not lp then s.trail = nil end
    -- desviacion = distancia del auto a la poligonal (rastro de puntos pasados + proximos 4 puntos);
    -- ver pushPassed: el rastro evita medir contra un ultimo punto que esta por delante del auto
    local dev = math.huge
    local chain = {}
    if lp and s.trail then
        for _, tp in ipairs(s.trail) do chain[#chain + 1] = tp end
    elseif lp then
        chain[1] = lp
    end
    for k = 1, math.min(#wp, 4) do chain[#chain + 1] = wp[k] end
    local cpx, cpy = nil, nil
    for k = 1, #chain do
        local qx, qy = chain[k][1], chain[k][2]
        if cpx then
            local sx, sy = qx - cpx, qy - cpy
            local len2 = sx * sx + sy * sy
            local t = len2 > 0.01 and math.max(0, math.min(1, ((x - cpx) * sx + (y - cpy) * sy) / len2)) or 0
            dev = math.min(dev, getDistanceBetweenPoints2D(x, y, cpx + sx * t, cpy + sy * t))
        else
            dev = math.min(dev, getDistanceBetweenPoints2D(x, y, qx, qy))
        end
        cpx, cpy = qx, qy
    end
    if not lp then dev = math.min(dev, 14) end   -- recien creado/reenganchado: aun no hay tramo de referencia
    if dev > 25 and not isElementOnScreen(vehicle) then
        removeCar(vehicle) return false
    end
    -- el reenganche termina cuando el auto ya esta sobre su carril (o pasados unos segundos)
    if s.man and s.man.kind == "REJOIN" and lp and dev < 1.5 and now - s.man.since > 800 then manEnd(s, "REJOIN", now) end
    s.devNow = lp and dev or 0   -- desviacion fiable (solo con tramo de referencia): frena si se aleja del carril
    if dev > 18 and not manIs(s, "DETOUR", now) then
        if not s.offSince and (offLogCount or 0) < 60 then
            -- diagnostico: se sale de su ruta (ver clientscript.log, lineas "[rp_citizens] fuera de ruta")
            offLogCount = (offLogCount or 0) + 1
            local w1 = wp[1]
            local dgn = angleDiff(heading(w1[1] - x, w1[2] - y), rz)
            local pts = {}
            for k = 1, math.min(#wp, 6) do pts[#pts + 1] = ("(%.0f,%.0f,g%.0f)"):format(wp[k][1], wp[k][2], wp[k][4]) end
            outputDebugString(("[rp_citizens] fuera de ruta: modelo %d nodos %s->%s pos (%.1f,%.1f) rumbo %.0f vel %.0f dev %.1f dif %.0f estado %s lenF %.2f lp %s wp: %s")
                :format(getElementModel(vehicle), tostring(s.prev), tostring(s.node), x, y, rz, speed, dev, dgn, tostring(s.state), s.lenF or 1, s.lastPassed and ("(%.0f,%.0f)"):format(s.lastPassed[1], s.lastPassed[2]) or "nil", table.concat(pts, " ")), 1)
        end
        s.offSince = s.offSince or now
        if now - s.offSince > 1000 and now - (s.lastReattach or 0) > 2500 then
            s.lastReattach = now
            reattach(vehicle, s, false)
            if not cars[vehicle] then return false end
            wp = s.wp
            if #wp == 0 then return false end
        end
        -- sigue lejos de cualquier carril tras varios intentos: lejos del jugador desaparece (sin que se note);
        -- cerca, el conductor se baja (en vez de seguir corriendo por aceras o contra muros)
        if dev > 25 and now - s.offSince > 6000 then
            local ppx, ppy = getElementPosition(localPlayer)
            if getDistanceBetweenPoints2D(ppx, ppy, x, y) > 50 or not isElementOnScreen(vehicle) then removeCar(vehicle) return false end
            abandonCar(vehicle, s) return false
        end
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
    -- Reintegro rapido: si el auto lleva ~0.7 s a mas de 4.5 m de su carril (acera, bencinera, otro carril)
    -- se calcula YA una trayectoria suave de vuelta; no espera a estar a 18 m ni a 1.5 s (eso era para casos graves).
    if s.devNow > 4.5 and (not inCurve or s.devNow > 7) and not manIs(s, "DETOUR", now) then
        s.sideSince = s.sideSince or now
        if now - s.sideSince > 700 and now - (s.lastReattach or 0) > 2000 then
            s.lastReattach, s.sideSince = now, nil
            reattach(vehicle, s, false)
            if not cars[vehicle] then return false end
            wp = s.wp
            if #wp == 0 then return false end
            inCurve = wp[1][4] > 20
        end
    else
        s.sideSince = nil
    end
    local lookahead = curveSoon and (2.5 + speed * 0.05) or (inCurve and 3.5 or 6) + speed * (inCurve and 0.06 or 0.1)
    -- tambien descarta los que quedaron DETRAS del auto (nunca se da la vuelta por un punto pasado)
    local fwx, fwy = m[2][1], m[2][2]
    while #wp > 1 and (getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2]) < lookahead
        or ((wp[1][1] - x) * fwx + (wp[1][2] - y) * fwy < 0 and (wp[2][1] - x) * fwx + (wp[2][2] - y) * fwy > -2
            and getDistanceBetweenPoints2D(x, y, wp[1][1], wp[1][2]) < 12)) do
        local passed = table.remove(wp, 1)
        pushPassed(s, passed)
        -- libera el cruce cuando ya no quedan puntos de el
        if passed[5] and (not wp[1][5] or wp[1][5] ~= passed[5]) then
            local hs = junctionLock[passed[5]]
            if hs then hs[vehicle] = nil end
        end
    end
    -- Nodo saltado: si el auto paso de largo de un punto (por el lado, mas lejos que la mirada), ese punto
    -- ya no se persigue: se descarta y sigue con el siguiente. Antes intentaba volver atras (retroceder o
    -- dar la vuelta) hasta alcanzarlo. Se descarta si (a) el auto ya avanzo mas alla del punto siguiendo la
    -- direccion del tramo, o (b) el punto queda detras del auto (mas de 100 grados de su rumbo).
    while #wp > 1 do
        local a, b = wp[1], wp[2]
        local sx2, sy2 = b[1] - a[1], b[2] - a[2]
        local l2 = sx2 * sx2 + sy2 * sy2
        local ahead = (a[1] - x) * fwx + (a[2] - y) * fwy
        local passedAlong = l2 > 0.01 and ((x - a[1]) * sx2 + (y - a[2]) * sy2) / l2 > 0
        local behindHead = ahead < 0 and math.abs(angleDiff(heading(a[1] - x, a[2] - y), rz)) > 100
        if not ((passedAlong and ahead < 2) or behindHead) then break end
        local passed = table.remove(wp, 1)
        pushPassed(s, passed)
        if passed[5] and (not wp[1][5] or wp[1][5] ~= passed[5]) then
            local hs = junctionLock[passed[5]]
            if hs then hs[vehicle] = nil end
        end
    end
    local tx, ty = wp[1][1], wp[1][2]
    local diff = angleDiff(heading(tx - x, ty - y), rz)
    -- En curvas: seguimiento de la trayectoria (rumbo de la ruta + correccion de la distancia lateral)
    -- en vez de apuntar a un punto, que en un arco cerrado casi no se desvia del rumbo actual
    local trackDiff, trackErr, tux, tuy = nil
    if inCurve or dev > 1.5 then   -- tambien al volver al carril: corrige el error lateral de forma progresiva
        trackDiff, trackErr, tux, tuy = pathTrack(s, wp, x, y, speed, rz)
        if trackDiff then diff = trackDiff end
    end

    f.wp, f.lp, f.dev, f.curveSoon, f.inCurve, f.diff, f.trackDiff, f.trackErr, f.tux, f.tuy = wp, lp, dev, curveSoon, inCurve, diff, trackDiff, trackErr, tux, tuy
    return true
end

local function stageAhead(vehicle, s, f, now)
    local driver = s.driver
    local speed, x, y, rx, ry, rz, m, fwd, wp, lp, dev, curveSoon, inCurve, diff, trackDiff, trackErr, tux, tuy = f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m, f.fwd, f.wp, f.lp, f.dev, f.curveSoon, f.inCurve, f.diff, f.trackDiff, f.trackErr, f.tux, f.tuy
    -- Lo que viene: mayor giro, cruce y semaforo en los proximos metros
    local upcoming, dist, lx, ly = 0, 0, x, y
    local curveLimit = 999
    local junctionAhead, junctionDist, lightAxis, lightDist, junctionMan = nil, 0, nil, 0, nil
    local wantSignal, signalLead = nil, math.max(18, math.min(40, speed * 0.55))
    for i = 1, math.min(#wp, 14) do
        dist = dist + getDistanceBetweenPoints2D(lx, ly, wp[i][1], wp[i][2])
        lx, ly = wp[i][1], wp[i][2]
        if dist > 60 then break end
        if wp[i][4] > 15 then curveLimit = math.min(curveLimit, curveCap(wp[i][4], dist, s.lenF)) end
        -- Intermitente: giro de cruce de >= 30 grados dentro de ~2 s de camino (entre 18 y 40 m)
        if not wantSignal and wp[i][7] and wp[i][4] >= 30 and dist <= signalLead then
            local mv = wp[i][7]
            wantSignal = (mv[1] * mv[4] - mv[2] * mv[3]) > 0 and "left" or "right"   -- + = giro a la izquierda
        end
        if dist > 45 then break end
        if dist <= 30 and wp[i][4] > upcoming then upcoming = wp[i][4] end
        if wp[i][5] and not junctionAhead and dist <= 30 then junctionAhead, junctionDist, junctionMan = wp[i][5], dist, wp[i][7] end
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
    -- Girando (a la izquierda o a la derecha): tambien mira hacia donde va a barrer el auto (rayos hacia
    -- el rumbo de la ruta). Con solo el rayo recto no veia los autos parados en el carril que cruza
    -- y se les metia encima a mitad del giro.
    if inCurve and math.abs(diff) > 12 and speed > 2 then
        local a = math.max(-50, math.min(50, diff))
        for _, k in ipairs({ 1, 0.5 }) do
            local h, e, g = ray(vehicle, m, a * k, math.min(reach, 9), false)
            if h and e and (not frontHit or not obstacle or (g and gap and g < gap)) then
                frontHit, obstacle, gap = h, e, g
            end
        end
    end
    -- en modo fantasma (sin colision, para salir de un atasco) no ve autos delante
    if s.ghost then frontHit, obstacle, gap = false, nil, nil end
    local wallFront, _, wallDist = ray(vehicle, m, 0, 4 + speed * 0.1, true)
    -- al esquivar (desvio activo o volviendo a la ruta) los bigotes son mas largos y mas abiertos:
    -- postes, bordes y muros a los lados se ven antes
    local careful = manIs(s, "DETOUR", now) or manIs(s, "REJOIN", now) or s.offSince
    local whiskerAngle, whiskerReach = careful and 38 or 25, (careful and 5.5 or 3.5) + speed * (careful and 0.09 or 0.06)
    local leftHit = ray(vehicle, m, whiskerAngle, whiskerReach, true)
    local rightHit = ray(vehicle, m, -whiskerAngle, whiskerReach, true)

    f.curveLimit, f.junctionAhead, f.junctionDist, f.lightAxis, f.lightDist, f.junctionMan, f.wantSignal, f.upcoming, f.frontHit, f.obstacle, f.gap, f.wallFront, f.wallDist, f.careful, f.leftHit, f.rightHit = curveLimit, junctionAhead, junctionDist, lightAxis, lightDist, junctionMan, wantSignal, upcoming, frontHit, obstacle, gap, wallFront, wallDist, careful, leftHit, rightHit
    return true
end

local function stageAssist(vehicle, s, f, now)
    local driver = s.driver
    local speed, x, y, rx, ry, rz, m, fwd, wp, lp, dev, curveSoon, inCurve, diff, trackDiff, trackErr, tux, tuy, wantSignal = f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m, f.fwd, f.wp, f.lp, f.dev, f.curveSoon, f.inCurve, f.diff, f.trackDiff, f.trackErr, f.tux, f.tuy, f.wantSignal
    -- Intermitentes (recurso rp_vehicles: dato local "rp:indicator" = "left" | "right"):
    -- se encienden antes de girar y se apagan al terminar la curva
    if wantSignal then
        s.signal, s.signalClearAt = wantSignal, nil
    elseif s.signal and not inCurve then
        s.signalClearAt = s.signalClearAt or (now + 700)
        if now > s.signalClearAt then s.signal, s.signalClearAt = nil, nil end
    end
    if s.signal ~= s.signalApplied then
        s.signalApplied = s.signal
        setElementData(vehicle, "rp:indicator", s.signal or false, false)
    end

    -- Asistencia de direccion suave: ayuda al volante (sin imponer el giro) y
    -- reduce solo parte del derrape lateral, para no frenar ni hacer patinar.
    if speed > 4 then
        -- Las ayudas solo entran a medida que el auto se aleja de lo que deberia hacer (error de rumbo o
        -- lateral). Mientras sigue bien la linea, giran solo el volante y la fisica del auto, como en GTA SA
        -- (sin rotaciones forzadas); si se desvia, la ayuda crece de forma gradual (failK 0 -> 1).
        if s.bike == nil then
            local vt = getVehicleType(vehicle)
            s.bike = (vt == "Bike" or vt == "BMX" or vt == "Quad")
        end
        local errLat = trackErr and math.abs(trackErr) or 0
        local lo, span = (s.bike and 18 or 28), (s.bike and 22 or 25)   -- en una curva normal el error de rumbo hacia la mirada ronda 20-25 grados
        local failK = math.max(math.max(0, math.min(1, (math.abs(diff) - lo) / span)), math.max(0, math.min(1, (errLat - 0.8) / 1.5)))
        local vx, vy, vz = getElementVelocity(vehicle)
        local fx, fy = m[2][1], m[2][2]
        local rx, ry = m[1][1], m[1][2]
        local along = vx * fx + vy * fy
        local side = vx * rx + vy * ry
        if math.abs(side) > 0.02 then
            -- en curva corrige mas el derrape lateral (agarre de neumaticos): el auto sigue la linea en vez de patinar
            local keep = 0.8 - (inCurve and 0.7 * failK or 0)
            setElementVelocity(vehicle, fx * along + rx * side * keep, fy * along + ry * side * keep, vz)
        end
        -- En una curva cerrada NO se limita el giro: esta asistencia fijaba la velocidad angular
        -- al valor de un apuntado casi recto (la mirada corta sobre el arco apenas se desvia), y
        -- el auto no podia girar lo que pide el radio del cruce y se salia recto.
        if inCurve then
            -- el giro necesario para recuperar el rumbo de la ruta en ~0.4 s, limitado a lo que
            -- el vehiculo puede girar de verdad (radio minimo ~4.5 m)
            if trackDiff then
                local ax, ay, az = getElementAngularVelocity(vehicle)
                -- radio minimo ~4.5 m; el derrape lateral se elimina casi por completo (keep) y la velocidad
                -- de entrada la limita curveCap, asi que el auto sigue la linea como "sobre rieles"
                local vms = math.max(speed / 3.6, 1)
                local maxW = math.min(0.03, vms / 4.5 / 50)
                local want = math.max(-maxW, math.min(maxW, math.rad(trackDiff) / 0.4 / 50))
                setElementAngularVelocity(vehicle, ax, ay, az + (want - az) * 0.6 * failK)
            end
        else
            local ax, ay, az = getElementAngularVelocity(vehicle)
            -- velocidad angular de MTA en radianes por 1/50 s (0.015 ~ 43 grados/s)
            local desired = math.max(-0.015, math.min(0.015, math.rad(diff) * 0.025)) * math.min(1, speed / 20)
            setElementAngularVelocity(vehicle, ax, ay, az + (desired - az) * 0.35)
        end
        -- Motos: la fisica de dos ruedas se resiste a la ayuda de giro (empiezan a girar y siguen de largo).
        -- Se les gira el rumbo directamente hacia la trayectoria, a una velocidad limitada por su radio
        -- minimo, y sin derrape lateral; conservan la inclinacion y el cabeceo.
        -- "Sobre rieles" en las curvas (autos y motos): el rumbo se corrige directamente hacia la
        -- trayectoria y el auto se acerca a la linea si se va saliendo (como mucho 0.3 m por tick), para
        -- que no se desvie poco a poco hasta pasar de largo. No actua tras un choque ni en modo fantasma.
        -- La IA (cada 80 ms) solo decide cuanto hay que girar (grados/s) y acercarse a la linea (m/s);
        -- applyRails() lo aplica en cada fotograma de forma suave (ver mas abajo), sin escalones.
        local onRails = inCurve and trackDiff and not s.ghost and not (s.hitUntil and now < s.hitUntil)
        if (onRails or (s.bike and trackDiff)) and failK > 0.05 then
            local vms = math.max(speed / 3.6, 1)
            local wmax = math.min(0.03, vms / 4.5 / 50)                       -- rad por 1/50 s
            local rateMax = math.deg(wmax * 50)                               -- grados por segundo
            s.railRate = math.max(-rateMax, math.min(rateMax, diff * 7)) * failK
            s.railLat, s.railNx, s.railNy = 0, 0, 0
            if onRails and trackErr and tux and dev < 8 and math.abs(trackErr) > 0.3 then
                s.railLat = math.max(-1.5, math.min(1.5, trackErr * 1.2)) * failK   -- m/s hacia la linea
                s.railNx, s.railNy = tuy, -tux
            end
            s.railUntil = now + 200
        else
            s.railUntil = nil
        end
    end

end

local function stageDecide(vehicle, s, f, now)
    local driver = s.driver
    local speed, x, y, rx, ry, rz, m, fwd, wp, lp, dev, curveSoon, inCurve, diff, trackDiff, trackErr, tux, tuy, curveLimit, junctionAhead, junctionDist, lightAxis, lightDist, junctionMan, wantSignal, upcoming, frontHit, obstacle, gap, wallFront, wallDist, careful, leftHit, rightHit = f.speed, f.x, f.y, f.rx, f.ry, f.rz, f.m, f.fwd, f.wp, f.lp, f.dev, f.curveSoon, f.inCurve, f.diff, f.trackDiff, f.trackErr, f.tux, f.tuy, f.curveLimit, f.junctionAhead, f.junctionDist, f.lightAxis, f.lightDist, f.junctionMan, f.wantSignal, f.upcoming, f.frontHit, f.obstacle, f.gap, f.wallFront, f.wallDist, f.careful, f.leftHit, f.rightHit
    -- en curvas cerradas gira con mas decision (volante a tope antes)
    local steer = diff / (inCurve and ((curveSoon or wp[1][4] > 60) and 12 or 18) or 25)
    local push = careful and 0.35 or 0.2
    -- Algo fijo (poste, semaforo, esquina) justo delante de la trayectoria: esquiva hacia el lado mas
    -- despejado, con mas fuerza cuanto mas cerca, en vez de seguir la linea hasta chocar con el.
    if wallFront and wallDist then
        local lh, _, ld = ray(vehicle, m, 40, 6, true)
        local rh, _, rd = ray(vehicle, m, -40, 6, true)
        ld, rd = lh and ld or 6, rh and rd or 6
        local urgency = math.max(0.3, 1 - wallDist / (4 + speed * 0.1))
        steer = steer + (ld >= rd and 1 or -1) * 0.8 * urgency   -- + = izquierda
    end
    if leftHit and not rightHit then steer = steer - push end
    if rightHit and not leftHit then steer = steer + push end
    -- Sirena detras: se arrima un poco a la derecha (salvo en un cruce o con algo al lado)
    local sirenDist = sirenBehind(vehicle, x, y, m)
    if sirenDist and not junctionAhead and not rightHit then steer = steer - 0.12 end
    -- Filtro del volante: no salta de golpe (mas natural); en curvas cerradas responde casi al instante
    local prevSteer = s.steerOut or 0
    s.steerOut = prevSteer + (math.max(-1, math.min(1, steer)) - prevSteer) * (inCurve and 0.8 or 0.5)

    if s.state == "FLEE" then
        setPedControlState(driver, "horn", false)
        if fwd < -1.5 then
            actuate(driver, s, true, false)            -- rueda hacia atras: acelera hacia delante, nunca marcha atras
        else
            actuate(driver, s, not obstacle or fwd < 5, (obstacle ~= nil or wallFront) and fwd > 20)
        end
        if now > s.until_ then s.state = "DRIVE" end
        return false
    end

    -- Velocidad objetivo
    local target = CFG.CAR_SPEED * (s.style and s.style.speed or 1)
    target = math.min(target, curveLimit)
    -- fuera de su ruta o recien reenganchado: despacio hasta estar de nuevo en el carril
    if s.offSince or manIs(s, "REJOIN", now) then target = math.min(target, 15) end
    if sirenDist then target = math.min(target, sirenDist < 30 and 6 or 18) end
    if math.abs(diff) > 50 then target = math.min(target, 16) elseif math.abs(diff) > 30 then target = math.min(target, 28) end
    -- se aleja del carril (derrape, empujon): baja la velocidad para recuperar la trayectoria
    -- en vez de seguir de largo hacia la acera o los muros
    if s.devNow > 6 then target = math.min(target, 15) elseif s.devNow > 3.5 then target = math.min(target, 28) end
    if wallFront then target = math.min(target, (wallDist and wallDist < 3) and 6 or 12) end
    if manIs(s, "DETOUR", now) then target = math.min(target, 18) end
    local waiting = false
    local mode = "DRIVE"   -- modo de este tick: se decide aqui y se asigna UNA vez (s.state = mode)

    -- Semaforo: frena hasta la linea de detencion en rojo (en amarillo si aun puede)
    -- Ya dentro de un cruce (entre la linea de detencion y la salida de la curva) NO se frena por el
    -- semaforo siguiente aunque este en rojo: en cruces grandes con varios nodos la segunda linea de
    -- detencion queda a pocos metros y el auto se quedaba parado a medio giro, atravesado.
    local lpb = s.lastPassed
    local inBox = lpb and lpb[5] ~= nil
    if lightAxis and not (inBox and lightDist < 30) then
        local light = lightFor(lightAxis)
        if light == "red" or (light == "yellow" and lightDist > 12) then
            if lightDist < 3 then target = 0 else target = math.min(target, math.max(4, (lightDist - 3) * 1.6)) end
            waiting = true
            mode = "RED"
        end
    end

    -- Cruce: pide paso; si otro auto lo tiene, espera antes de entrar
    local yielding = false
    -- Un auto en modo fantasma (saliendo de un atasco) no cede el paso.
    -- Si esta en cola lejos del cruce (algo delante), no reserva el cruce: no lo bloquea a los demas.
    local holdsLock = junctionAhead and junctionLock[junctionAhead] and junctionLock[junctionAhead][vehicle]
    -- Ya dentro del cruce (paso el primer punto de este cruce): NUNCA cede el paso ni se queda parado
    -- esperando; mantiene su reserva mientras siga dentro. Despejar el cruce es lo primero.
    local lp0 = s.lastPassed
    local inside = junctionAhead and lp0 and lp0[5] == junctionAhead
    if inside then
        local hs = junctionLock[junctionAhead]
        if not hs then hs = {} junctionLock[junctionAhead] = hs end
        hs[vehicle] = { man = junctionMan, t = now }
        s.exitWaitSince = nil
    elseif not waiting and junctionAhead and not s.ghost and (junctionDist < 10 or holdsLock) then
        if obstacle and not holdsLock and junctionDist > 5 and speed < 3 then
            -- espera en la cola: el seguimiento de distancia lo detiene
            if junctionLock[junctionAhead] then junctionLock[junctionAhead][vehicle] = nil end
        else
            local blocked = false
            if not holdsLock and junctionDist > 2 then
                -- no entra si la salida esta ocupada (maximo 8 s: despues se arriesga a pasar)
                if exitBlocked(vehicle, wp, junctionAhead) then
                    s.exitWaitSince = s.exitWaitSince or now
                    blocked = now - s.exitWaitSince < 8000
                else
                    s.exitWaitSince = nil
                end
            end
            if blocked or not tryLock(junctionAhead, vehicle, now, junctionMan, speed > 3) then
                yielding = true
                target = junctionDist > 7 and 8 or 0
            end
        end
    else
        s.exitWaitSince = nil
    end

    -- Distancia de seguimiento con lo que tenga delante
    -- Rodeando un obstaculo (desvio activo): lo sigue viendo de frente mientras gira, pero no debe frenar por el
    -- hasta que este realmente encima; si no, se queda parado "esperando" aunque su ruta nueva ya este libre
    if obstacle and manIs(s, "DETOUR", now) and gap and gap > 2.2 + speed * 0.04 then
        obstacle, frontHit = nil, false
    end
    local isPlayerThing = obstacle and (obstacle == localPlayer or obstacle == getPedOccupiedVehicle(localPlayer))
    if obstacle then
        local otherSpeed = isElement(obstacle) and getElementType(obstacle) ~= "ped" and speedOf(obstacle) or 0
        local safeGap = (4 + speed * 0.12) * (s.style and s.style.gap or 1)
        if gap and gap < safeGap then target = 0 else target = math.min(target, otherSpeed + 3) end
        -- tiempo hasta el choque: si se cierra demasiado rapido, frena a fondo
        local closing = (speed - otherSpeed) / 3.6
        if gap and closing > 1 and gap / closing < 2.0 then target = 0 end

        -- Tras una marcha atras corta: intenta rodear el obstaculo en vez de repetir lo mismo
        if s.afterReverse then
            if now - s.afterReverse > 5000 then
                s.afterReverse = nil
            elseif speed < 3 and not waiting and not yielding and tryDetour(vehicle, s, m) then
                s.blockedSince, s.afterReverse = 0, nil
                setPedControlState(driver, "horn", false)
            end
        end
        if target <= 1 and speed < 3 then
            if s.blockedSince == 0 then s.blockedSince = now end
            local waited = now - s.blockedSince
            if isPlayerThing then
                -- 1) bocina  2) busca un desvio  3) si no hay hueco, retrocede un poco y vuelve a intentar
                if waited > 900 then honk(vehicle, s, now) end
                -- bloqueado mucho tiempo sin poder rodear ni retroceder: si no se ve, desaparece;
                -- si se ve, pasa unos segundos sin colision (nunca embiste al jugador)
                if waited > 20000 then
                    s.blockedSince = now
                    if not isElementOnScreen(vehicle) then removeCar(vehicle) return false end
                    ghostCar(vehicle, s, 6000)
                end
                if waited > 2800 and not waiting then
                    if tryDetour(vehicle, s, m) then
                        s.blockedSince = 0
                        setPedControlState(driver, "horn", false)
                    elseif waited > 4500 then
                        -- sin hueco: retrocede un instante (~1 s) para abrir angulo y reintenta
                        -- (solo si no hay nada detras; si lo hay, espera)
                        if startReverse(vehicle, s, now, 900, 0, m) then s.blockedSince = now - 2000 end
                    end
                end
            elseif not cars[obstacle] and isElement(obstacle) and getElementType(obstacle) ~= "ped"
                and getElementType(obstacle) ~= "vehicle" and waited > 2500 and not yielding and not waiting then
                -- Obstaculo fijo (poste caido, escombros): 1) intenta rodearlo  2) si no hay hueco, marca el
                -- tramo como cortado (los demas lo evitan) y lo atraviesa en modo fantasma para no bloquear la calle
                if waited > 2500 and not s.detourTried then
                    s.detourTried = true
                    if tryDetour(vehicle, s, m) then s.blockedSince = 0 end
                elseif waited > 5000 then
                    local ln, lt = nearestLane(x, y, m[2][1], m[2][2])
                    markEdgeBlocked(ln, lt)
                    s.detourTried = nil
                    s.blockedSince = now
                    ghostCar(vehicle, s, 5000)
                end
            elseif waited > 8000 and otherSpeed < 1 and not yielding and not waiting then
                -- objeto o auto averiado (no una cola): lo rodea. Nunca adelanta a autos
                -- de la poblacion que esperan en un semaforo, cruce o cola.
                local queued = cars[obstacle] and (cars[obstacle].state == "RED" or cars[obstacle].state == "FOLLOW"
                    or cars[obstacle].state == "YIELD" or cars[obstacle].state == "DRIVE")
                if not queued and tryDetour(vehicle, s, m) then s.blockedSince = 0 end
            end
        end
        if mode ~= "RED" then mode = "FOLLOW" end
    else
        s.blockedSince = 0
        s.detourTried = nil
        setPedControlState(driver, "horn", false)
        if not waiting then mode = yielding and "YIELD" or (manIs(s, "DETOUR", now) and "DETOUR" or "DRIVE") end
    end
    s.state = mode
    -- Choque reciente con otro auto de la poblacion: frena un momento (lo marca el evento de colision)
    if s.holdBrakeUntil and now < s.holdBrakeUntil then target = 0 end

    do
        local accel, brake, hand = pedalsFor(fwd, target, inCurve)
        actuate(driver, s, accel, brake, hand)
    end

    -- Atascado sin motivo (pared, otro auto cruzado): marcha atras y reenganche
    -- (en cola, semaforo o cruce NUNCA cuenta como atasco)
    -- Parado demasiado tiempo (cruce bloqueado, dos autos de frente): pasa a modo fantasma
    -- unos segundos para atravesar el atasco. Nunca con el jugador de por medio.
    if speed < 2 and s.state ~= "RED" and not isPlayerThing and target < 5 then
        s.slowSince = s.slowSince or now
        -- parado en cruce/atasco: 9 s; en cola detras de otro auto (puede ser un semaforo largo): 25 s
        if now - s.slowSince > (s.state == "FOLLOW" and 25000 or 9000) then
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
            s.stuckSince = 0
            if startReverse(vehicle, s, now, 1100, steer, m) then
                s.stuckCount = (s.stuckCount or 0) + 1
                s.stuckBlockedSince = nil
                -- de cada dos intentos, uno recalcula la ruta desde el carril mas cercano
                if s.stuckCount % 2 == 0 then s.needReattach = true end
                -- se atasca una y otra vez en el mismo sitio sin ver que lo frena (poste a ras de suelo,
                -- escombros): marca el tramo como cortado y lo atraviesa sin colision
                if s.stuckCount >= 2 then
                    local ln, lt = nearestLane(x, y, m[2][1], m[2][2])
                    markEdgeBlocked(ln, lt)
                    s.needReattach = nil
                    s.stuckCount = 0
                    ghostCar(vehicle, s, 5000)
                end
                -- atascado de verdad: el conductor se baja y se va; el auto queda como obstaculo
                if s.stuckCount > 5 then abandonCar(vehicle, s) end
            else
                -- algo detras: no retrocede; si dura, pasa unos segundos sin colision
                s.stuckBlockedSince = s.stuckBlockedSince or now
                if now - s.stuckBlockedSince > 8000 then
                    s.stuckBlockedSince = nil
                    ghostCar(vehicle, s, 5000)
                end
            end
        end
    else
        s.stuckSince = 0
    end

    -- Telemetria: guarda la muestra y, si se salio de la linea poco despues de una curva, vuelca el historial
    telRecord(s, now, speed, diff, target, inCurve, wp[1] and wp[1][4], rz)
    if inCurve then s.telCurveAt = now end
    if s.devNow > 5 and s.telCurveAt and now - s.telCurveAt < 3000 then
        telDump(vehicle, s, "fuera_de_linea_en_curva", now)
    end
    return true
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

    local f = s.f
    if not f then f = {} s.f = f end
    senseSelf(vehicle, f)
    if not stageGuards(vehicle, s, f, now) then return end
    if stageReverse(vehicle, s, f, now) then return end
    if not stageRoute(vehicle, s, f, now) then return end
    stageAhead(vehicle, s, f, now)
    stageAssist(vehicle, s, f, now)
    stageDecide(vehicle, s, f, now)
end

-- Choques entre autos de la poblacion: maniobra corta y reenganche al carril
addEventHandler("onClientVehicleCollision", root, function(hit, force)
    local s = cars[source]
    if not s or s.state == "ABANDONED" or force < 150 then return end
    if not hit or getElementType(hit) ~= "vehicle" then
        -- choque con el mundo (poste, pared, objeto): marca el golpe para retroceder en el siguiente tick
        if force > 250 then s.wallHitAt = getTickCount() end
        return
    end
    if getElementType(hit) == "vehicle" and cars[hit] then
        local now = getTickCount()
        -- choque entre autos de la poblacion: durante un momento no puede salir hacia arriba ni dar vueltas
        s.hitUntil = now + 700
        if now > s.recoverUntil + 1500 then
            -- el que va detras frena un momento (sin marcha atras); el de delante sigue.
            -- Si alguno quedo fuera de su ruta, el control de distancia lo reengancha.
            local m = getElementMatrix(source)
            local hx, hy = getElementPosition(hit)
            local x, y = getElementPosition(source)
            local ahead = (hx - x) * m[2][1] + (hy - y) * m[2][2] > 0
            if ahead then
                s.blockedSince = now
                s.holdBrakeUntil = now + 500   -- updateCar frena (solo si avanza) a traves del actuador
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
            list[#list + 1] = { vehicle = vehicle, wp = s.wp, state = s.state .. (s.man and ("/" .. s.man.kind) or ""), lod = s.lod }
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

-- Aplica la correccion de rumbo y de posicion de las curvas "sobre rieles" en cada fotograma. La tasa
-- de giro se suaviza (filtro de primer orden) para que el auto entre y salga de la curva sin sacudidas,
-- como si el volante girara de verdad, en vez de rotar a saltos cada tick de IA.
local function applyRails(dt)
    local dts = math.min(dt, 100) / 1000
    for vehicle, s in pairs(cars) do
        if s.lod ~= "dummy" and s.railRate and isElement(vehicle) then
            local live = s.railUntil and getTickCount() < s.railUntil
            local target = live and s.railRate or 0
            local sm = (s.railSm or 0) + (target - (s.railSm or 0)) * math.min(1, dts * 7)
            s.railSm = sm
            if not live and math.abs(sm) < 0.5 then
                s.railRate, s.railSm = nil, nil
            else
                local rx, ry, rz = getElementRotation(vehicle)
                setElementRotation(vehicle, rx, ry, rz + sm * dts)
                if live and s.railLat and s.railLat ~= 0 then
                    local px, py, pz = getElementPosition(vehicle)
                    local lat = s.railLat * dts
                    setElementPosition(vehicle, px + s.railNx * lat, py + s.railNy * lat, pz)
                end
            end
        end
    end
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

----------------------------------------------------------------
-- Salud del sistema: errores, atascos y estadisticas
--   1) guarded(): cada entidad se actualiza dentro de pcall; un error Lua no rompe al resto. Al pasar
--      ERR_LIMIT errores esa entidad se elimina.
--   2) Interruptor de seguridad: demasiados errores por minuto apagan la poblacion un rato.
--   3) Vigilante (carWatchdog / pedWatchdog): atascos, agua, fuera del mapa, vueltas en circulos.
--      Se elimina fuera de vista; si se ve y esta cerca, se desvanece en ~1 s.
--   4) Huerfanos: autos y peatones propios que ya no estan en las tablas se destruyen.
--   5) Estadisticas por causa y nodos problematicos (/traficostats) y reduccion de poblacion con FPS bajos.
----------------------------------------------------------------
local HEALTH = {
    ERR_LIMIT = 3,                                  -- errores de una entidad antes de eliminarla
    BREAKER_ERRORS = 30, BREAKER_WINDOW = 60000, BREAKER_PAUSE = 60000,
    CAR_IDLE_VISIBLE = 60000, CAR_IDLE_HIDDEN = 25000,   -- ms sin avanzar antes de eliminar un auto
    PED_IDLE_VISIBLE = 45000, PED_IDLE_HIDDEN = 20000,
    FADE_MS = 1200,
    LOG_EVERY = 5000,                               -- un aviso de error cada 5 s como maximo
}
local stats = { despawn = {}, errors = {}, since = getTickCount() }
local problemNodes = {}      -- [nodo] = veces que un auto fue eliminado por problemas cerca de el
local errorTimes, breakerUntil, lastErrLog = {}, 0, 0
local fpsMs, popScale = 16, 1   -- tiempo medio de fotograma y factor de poblacion

local function noteDespawn(reason, node)
    stats.despawn[reason] = (stats.despawn[reason] or 0) + 1
    if node then problemNodes[node] = (problemNodes[node] or 0) + 1 end
end

-- Ejecuta fn(...) protegida. Devuelve true si no hubo error. "s" lleva el contador de errores de la entidad.
local function guarded(label, s, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return true end
    local now = getTickCount()
    stats.errors[label] = (stats.errors[label] or 0) + 1
    if s then s.errCount = (s.errCount or 0) + 1 end
    errorTimes[#errorTimes + 1] = now
    if now - lastErrLog > HEALTH.LOG_EVERY then
        lastErrLog = now
        outputDebugString(("[rp_citizens] error en %s: %s"):format(label, tostring(err)), 1)
    end
    return false
end

local function breakerActive() return getTickCount() < breakerUntil end

-- Revisa el interruptor (una vez por segundo desde spawnTick)
local function checkBreaker(now)
    local keep = {}
    for _, t in ipairs(errorTimes) do
        if now - t < HEALTH.BREAKER_WINDOW then keep[#keep + 1] = t end
    end
    errorTimes = keep
    if #errorTimes >= HEALTH.BREAKER_ERRORS and now >= breakerUntil then
        breakerUntil = now + HEALTH.BREAKER_PAUSE
        errorTimes = {}
        stats.despawn["interruptor"] = (stats.despawn["interruptor"] or 0) + 1
        clearAll()
        outputDebugString("[rp_citizens] demasiados errores: poblacion apagada 60 s (revisa el log del cliente)", 1)
        outputChatBox("[Trafico] Demasiados errores en la IA de trafico y peatones: se apaga 60 s y se reinicia sola. Avisa a un admin.", 255, 120, 80)
    end
end

-- Elimina un auto por "reason". Si se ve y esta cerca de la camara se desvanece en ~1 s.
local function despawnCar(vehicle, s, reason, soft)
    if not isElement(vehicle) then return removeCar(vehicle) end
    noteDespawn(reason, s.node or s.prev)
    if soft and isElementOnScreen(vehicle) then
        local x, y = getElementPosition(vehicle)
        local px, py = getElementPosition(localPlayer)
        if getDistanceBetweenPoints2D(px, py, x, y) < 90 then
            if not s.fadeStart then
                s.fadeStart = getTickCount()
                setElementCollisionsEnabled(vehicle, false)
                if s.driver and isElement(s.driver) then
                    setPedControlState(s.driver, "accelerate", false)
                    setPedControlState(s.driver, "handbrake", true)
                end
            end
            return
        end
    end
    removeCar(vehicle)
end

-- Desvanecimiento de un auto marcado para eliminar (true si ya se elimino)
local function fadeStep(vehicle, s)
    local k = (getTickCount() - s.fadeStart) / HEALTH.FADE_MS
    if k >= 1 then
        removeCar(vehicle)
        return true
    end
    local a = math.floor(255 * (1 - k))
    setElementAlpha(vehicle, a)
    if s.driver and isElement(s.driver) then setElementAlpha(s.driver, a) end
    return false
end

-- Vigilante de un auto con fisica o lejano
local function carWatchdog(v, s, now)
    local x, y, z = getElementPosition(v)
    if z < -30 or z > 500 then return despawnCar(v, s, "fuera_del_mapa") end
    if isElementInWater(v) then
        s.waterSince = s.waterSince or now
        if now - s.waterSince > 2500 then return despawnCar(v, s, "agua", true) end
    else
        s.waterSince = nil
    end
    -- Antivuelo: autos con fisica nunca salen disparados (choques entre fantasmas que vuelven a ser
    -- solidos, empujones, rampas). Limita velocidad, ascenso y giro en el aire; si sigue volando, se retira.
    if s.lod ~= "dummy" and s.state ~= "ABANDONED" and not s.fadeStart then
        local vx, vy, vz = getElementVelocity(v)
        local kmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
        local limit = s.state == "FLEE" and 90 or CFG.CAR_SPEED * 1.5
        local hit = s.hitUntil and now < s.hitUntil
        local nvx, nvy, nvz, changed = vx, vy, vz, false
        if kmh > limit then
            local k = limit / kmh
            nvx, nvy, nvz, changed = vx * k, vy * k, vz * k, true
        end
        local vzMax = hit and 0.02 or 0.08
        if nvz > vzMax then nvz, changed = vzMax, true end
        if changed then setElementVelocity(v, nvx, nvy, nvz) end
        local ax, ay, az = getElementAngularVelocity(v)
        if hit or math.abs(ax) > 0.05 or math.abs(ay) > 0.05 then
            if math.abs(ax) > 0.02 or math.abs(ay) > 0.02 then setElementAngularVelocity(v, ax * 0.3, ay * 0.3, az) end
        end
        if now - (s.airAt or 0) >= 250 then
            s.airAt = now
            s.baseZ = s.baseZ or vehicleBaseZ(v)
            local gz = groundAt(x, y, z)
            if gz and z - gz - s.baseZ > 1.3 then
                s.airSince = s.airSince or now
                if now - s.airSince > 600 then
                    -- lo endereza y lo empuja al suelo
                    local cvx, cvy, cvz = getElementVelocity(v)
                    local aax, aay, aaz = getElementAngularVelocity(v)
                    setElementAngularVelocity(v, 0, 0, aaz)
                    setElementVelocity(v, cvx * 0.6, cvy * 0.6, math.min(cvz, -0.02))
                    local _, _, rz = getElementRotation(v)
                    setElementRotation(v, 0, 0, rz)
                end
                if now - s.airSince > 2500 then return despawnCar(v, s, "volando", true) end
            else
                s.airSince = nil
            end
        end
    end
    -- cada 5 s: avance y recorrido
    if not s.wdAt then
        s.wdX, s.wdY, s.wdAt, s.idleMs, s.pathLen = x, y, now, 0, 0
        s.anchorX, s.anchorY, s.anchorAt = x, y, now
        return
    end
    if now - s.wdAt >= 5000 then
        local moved = getDistanceBetweenPoints2D(x, y, s.wdX, s.wdY)
        local legit = s.state == "RED"            -- esperando un semaforo no es atasco
        if moved < 1.5 and not legit then s.idleMs = s.idleMs + (now - s.wdAt) else s.idleMs = 0 end
        s.pathLen = s.pathLen + moved
        s.wdX, s.wdY, s.wdAt = x, y, now
        -- vueltas en circulos: un minuto recorriendo mucho sin alejarse de un mismo punto
        if now - s.anchorAt >= 60000 then
            local net = getDistanceBetweenPoints2D(x, y, s.anchorX, s.anchorY)
            if net < 30 and s.pathLen > 120 then return despawnCar(v, s, "vueltas", true) end
            s.anchorX, s.anchorY, s.anchorAt, s.pathLen = x, y, now, 0
        end
    end
    local queued = s.state == "FOLLOW" or s.state == "YIELD"   -- en cola: se tolera el doble
    local limit = isElementOnScreen(v) and HEALTH.CAR_IDLE_VISIBLE or HEALTH.CAR_IDLE_HIDDEN
    if queued then limit = limit * 2 end
    if s.idleMs > limit then return despawnCar(v, s, "atascado", true) end
end

-- Vigilante de un peaton que camina o huye
local function pedWatchdog(ped, s, now)
    local x, y, z = getElementPosition(ped)
    if z < -30 or z > 500 then
        noteDespawn("ped_fuera_del_mapa")
        return removePed(ped)
    end
    if isElementInWater(ped) then
        s.waterSince = s.waterSince or now
        if now - s.waterSince > 2500 then
            noteDespawn("ped_agua")
            return removePed(ped)
        end
    else
        s.waterSince = nil
    end
    if s.state ~= "WALK" and s.state ~= "FLEE" then
        s.wdAt = nil
        return
    end
    if not s.wdAt then
        s.wdX, s.wdY, s.wdAt, s.idleMs = x, y, now, 0
        return
    end
    if now - s.wdAt >= 5000 then
        if getDistanceBetweenPoints2D(x, y, s.wdX, s.wdY) < 1.5 then s.idleMs = s.idleMs + (now - s.wdAt) else s.idleMs = 0 end
        s.wdX, s.wdY, s.wdAt = x, y, now
    end
    local limit = isElementOnScreen(ped) and HEALTH.PED_IDLE_VISIBLE or HEALTH.PED_IDLE_HIDDEN
    if s.idleMs > limit then
        noteDespawn("ped_atascado")
        return removePed(ped)
    end
end

-- Autos y peatones creados por este recurso que ya no estan en las tablas (se marcan con rp:citizen)
local function sweepOrphans()
    for _, v in ipairs(getElementsByType("vehicle", resourceRoot)) do
        if not cars[v] and getElementData(v, "rp:citizen") and not getElementData(v, "rp:copCar")
            and getVehicleController(v) ~= localPlayer then
            stats.despawn["huerfano"] = (stats.despawn["huerfano"] or 0) + 1
            destroyElement(v)
        end
    end
    for _, p in ipairs(getElementsByType("ped", resourceRoot)) do
        if not peds[p] and getElementData(p, "rp:citizen") and not getElementData(p, "rp:cop") then
            local veh = getPedOccupiedVehicle(p)
            if not (veh and cars[veh]) then
                stats.despawn["huerfano"] = (stats.despawn["huerfano"] or 0) + 1
                destroyElement(p)
            end
        end
    end
end

-- /traficostats: estado de la poblacion, causas de eliminacion, errores y nodos problematicos
-- /objetoscerca: objetos (elementos MTA) a menos de 25 m. Sirve para saber si los postes y semaforos
-- caidos son elementos que se pueden quitar desde el script o parte del mapa del juego.
addCommandHandler("objetoscerca", function()
    local px, py, pz = getElementPosition(localPlayer)
    local n = 0
    for _, o in ipairs(getElementsByType("object", root, true)) do
        local x, y, z = getElementPosition(o)
        local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
        if d < 25 then
            n = n + 1
            if n <= 15 then
                outputChatBox(("[Objetos] modelo %d a %.0f m, colision: %s, z %.1f"):format(
                    getElementModel(o), d, tostring(getElementCollisionsEnabled(o)), z), 200, 200, 120)
            end
        end
    end
    outputChatBox(("[Objetos] %d objetos a menos de 25 m"):format(n), 200, 200, 120)
end)

addCommandHandler("traficostats", function()
    local now = getTickCount()
    outputChatBox(("[Trafico] Autos %d  Peatones %d  Poblacion x%.1f  Fotograma %.0f ms  Interruptor: %s"):format(
        carCount, pedCount, popScale, fpsMs, breakerActive() and "APAGADO" or "ok"), 120, 200, 255)
    local parts = {}
    for k, n in pairs(stats.despawn) do parts[#parts + 1] = k .. "=" .. n end
    table.sort(parts)
    outputChatBox("[Trafico] Eliminados (" .. math.floor((now - stats.since) / 60000) .. " min): "
        .. (#parts > 0 and table.concat(parts, ", ") or "ninguno"), 120, 200, 255)
    local errs = {}
    for k, n in pairs(stats.errors) do errs[#errs + 1] = k .. "=" .. n end
    if #errs > 0 then outputChatBox("[Trafico] Errores Lua: " .. table.concat(errs, ", "), 255, 140, 90) end
    local list = {}
    for node, n in pairs(problemNodes) do list[#list + 1] = { node, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(5, #list) do
        local x, y = nodePos(VEH_NODES, list[i][1])
        outputChatBox(("[Trafico] Nodo problematico #%d: %d veces cerca de (%.0f, %.0f) -> revisalo con /nodos"):format(
            list[i][1], list[i][2], x, y), 255, 200, 90)
    end
end)

local function spawnTick()
    -- pasajero: no se crea nada; lo que queda se desvanece solo (ver setCitizensSuspended)
    if suspended and enabled and getElementData(localPlayer, "rp:characterId") and playerIsActive() then return end
    if not enabled or suspended or not getElementData(localPlayer, "rp:characterId") or not playerIsActive() then
        if pedCount > 0 or carCount > 0 then clearAll() end
        return
    end
    local px, py, pz = getElementPosition(localPlayer)

    -- Salud: interruptor de seguridad, limpieza de huerfanos y poblacion segun los FPS
    local nowH = getTickCount()
    checkBreaker(nowH)
    if breakerActive() then
        if pedCount > 0 or carCount > 0 then clearAll() end
        return
    end
    if nowH - (stats.lastSweep or 0) > 20000 then
        stats.lastSweep = nowH
        guarded("huerfanos", nil, sweepOrphans)
    end
    if fpsMs > 40 then popScale = 0.6 elseif fpsMs < 30 then popScale = 1 end   -- < 25 FPS: menos poblacion

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
    -- rp_events (c_scenes.lua): hora punta, lluvia y escenas activas ajustan los cupos
    local pedMul, carMul = 1, 1
    if eventPopScale then pedMul, carMul = eventPopScale() end
    local maxPeds = math.floor((night and CFG.MAX_PEDS_NIGHT or CFG.MAX_PEDS) * pedMul * popScale + 0.5)
    local scenePeds = sceneExtraPeds and sceneExtraPeds() or 0
    -- siempre quedan al menos 4 peatones caminando aunque haya muchos grupos quietos
    if pedCount + math.min(scenePeds, math.max(0, maxPeds - 4)) < maxPeds then spawnPed(px, py) end
    local maxCars = math.floor((night and CFG.MAX_CARS_NIGHT or CFG.MAX_CARS) * carMul * popScale + 0.5) + (playerWanted() and CFG.MAX_CARS_WANTED or 0)
    -- hasta 2 por tick cuando faltan muchos (yendo rapido se despawnean seguido)
    for _ = 1, (maxCars - carCount > 4) and 2 or 1 do
        if carCount < maxCars then spawnCar(px, py) end
    end
end

local function pedTick()
    if pedCount == 0 or breakerActive() then return end
    local now = getTickCount()
    local px, py, pz = getElementPosition(localPlayer)
    local aimTarget = getPedTarget(localPlayer)
    pedSnap = {}
    for p in pairs(peds) do
        if isElement(p) then
            local sx, sy = getElementPosition(p)
            pedSnap[#pedSnap + 1] = { p, sx, sy }
        end
    end
    for ped, s in pairs(peds) do
        local fading = false
        if s.fadeStart and isElement(ped) then
            -- marcado para retirar (el jugador pasa a ver el trafico de otro): se desvanece y se borra
            fading = true
            local k = (now - s.fadeStart) / 1200
            if k >= 1 then removePed(ped) else setElementAlpha(ped, math.floor(255 * (1 - k))) end
        end
        if not fading and isElement(ped) and s.state ~= "DEAD" then
            -- Le apuntan con un arma de fuego: huye
            if aimTarget == ped and getPedWeapon(localPlayer) >= 22 and s.state ~= "FLEE" and s.state ~= "FIGHT" then
                startFlee(ped, localPlayer)
            end
            if isElementStreamedIn(ped) then
                if not guarded("peaton", s, updatePed, ped, s, now, px, py, pz) and (s.errCount or 0) >= HEALTH.ERR_LIMIT then
                    noteDespawn("ped_error")
                    removePed(ped)
                elseif peds[ped] then
                    guarded("peaton", s, pedWatchdog, ped, s, now)
                end
            end
        end
    end
end

local function carTick()
    if carCount == 0 or breakerActive() then return end
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
                if nearOtherCar(v, 4.8, true) then ghostCar(v, s, 4000) end
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
            if s.fadeStart then
                fadeStep(v, s)   -- marcado para eliminar: se desvanece y se borra
            else
                local ok
                if s.lod == "dummy" then
                    ok = guarded("auto_lejano", s, dummyDecide, v, s)
                elseif isElementStreamedIn(v) then
                    ok = guarded("auto", s, updateCar, v, s, now)
                end
                if ok == false and (s.errCount or 0) >= HEALTH.ERR_LIMIT then
                    despawnCar(v, s, "error")
                elseif cars[v] then
                    guarded("auto_vigilante", s, carWatchdog, v, s, now)
                end
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
    computeMainEdges()
    setPedsLODDistance(60)
    setTimer(spawnTick, CFG.SPAWN_TICK, 0)
    setTimer(pedTick, CFG.PED_TICK, 0)
    setTimer(carTick, CFG.CAR_TICK, 0)
    -- solo mueve dummies (pocos calculos por auto); sin dummies no hace nada
    addEventHandler("onClientPreRender", root, function(dt)
        fpsMs = fpsMs * 0.97 + math.min(dt or 16, 200) * 0.03   -- tiempo medio de fotograma
        if breakerActive() then return end
        guarded("auto_lejano_mov", nil, moveDummies, dt)
        guarded("auto_curvas", nil, applyRails, dt)
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, clearAll)

-- Usadas por el editor de nodos (c_editor.lua) al cambiar el grafo
function rebuildCitizenGrids()
    pedGrid = buildGrid(PED_NODES, PED_LINKS)
    vehGrid = buildGrid(VEH_NODES, VEH_LINKS)
    computeMainEdges()
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

----------------------------------------------------------------
-- API para rp_events (escenas ambientales en c_scenes.lua y eventos
-- compartidos). Todo barato: busquedas puntuales sobre las rejillas.
----------------------------------------------------------------

function citizensEnabled()
    return enabled and not suspended
end

function citizenCounts()
    return pedCount, carCount
end

function citizenPickSkin(x, y, z)
    return pickPedSkin(x, y, z)
end

function citizenPickCar(x, y, z)
    return pickCarModel(x, y, z)
end

-- Punto de acera a [minD, maxD] del jugador. hidden = fuera de la camara.
-- Devuelve x, y, z, rotacion (siguiendo el camino) o nil.
function citizenWalkSpot(minD, maxD, hidden)
    if not pedGrid then return end
    local px, py = getElementPosition(localPlayer)
    for _ = 1, 4 do
        local node, x, y, z = randomNodeAround(PED_NODES, pedGrid, px, py, minD, maxD)
        if node and not (hidden and visibleFromCamera(x, y, z)) then
            local target = nextNode(PED_LINKS, node, nil)
            local tx, ty = nodePos(PED_NODES, target)
            return x, y, z, heading(tx - x, ty - y)
        end
    end
end

-- Punto de calzada (carril derecho) con la direccion de la via. Con minD <= 0 busca
-- el nodo mas cercano al jugador (uso de admin). Devuelve x, y, z, rotacion o nil.
function citizenRoadSpot(minD, maxD, hidden)
    if not vehGrid then return end
    local px, py = getElementPosition(localPlayer)
    for _ = 1, 5 do
        local node, x, y, z
        if minD <= 0 then
            node = nearestNode(VEH_NODES, vehGrid, px, py)
            if node then x, y, z = nodePos(VEH_NODES, node) end
            if not node or getDistanceBetweenPoints2D(px, py, x, y) > 60 then return end
        else
            node, x, y, z = randomNodeAround(VEH_NODES, vehGrid, px, py, minD, maxD)
        end
        if node and not (hidden and visibleFromCamera(x, y, z)) then
            local target
            for _, n in ipairs(VEH_LINKS[node] or {}) do
                if canDrive(node, n) and isMainEdge(node, n) and not isBlockedEdge(node, n) then target = n break end
            end
            if target then
                local sx, sy, sz, dx, dy = laneStart(node, target)
                if not spotOccupied(sx, sy, 12) then return sx, sy, sz, heading(dx, dy) end
            end
        end
        if minD <= 0 then return end
    end
end

-- Los peatones a menos de "radius" de (x, y) se paran a mirar durante "ms" (max. 6 por llamada)
function citizenWatch(x, y, radius, ms)
    if pedCount == 0 then return 0 end
    local now, r2, n = getTickCount(), radius * radius, 0
    for ped, s in pairs(peds) do
        if (s.state == "WALK" or s.state == "IDLE") and isElement(ped) and n < 6 then
            local px, py = getElementPosition(ped)
            if (px - x) ^ 2 + (py - y) ^ 2 < r2 and math.random() < 0.6 then
                n = n + 1
                setPedAnimation(ped)
                setWalking(ped, false)
                s.state, s.lookX, s.lookY = "WATCH", x, y
                s.until_ = now + ms * (0.6 + math.random() * 0.8)
                if math.random() < 0.3 then setPedAnimation(ped, "ped", "phone_talk", -1, true, false, false, false) end
            end
        end
    end
    return n
end

-- Barrio de un punto: perfil ("ghetto", "rich", "industrial", "default"), nombre de zona y
-- skins de la banda local (o nil). Lo usa c_hangouts.lua.
function citizenZoneInfo(x, y, z)
    local zone = getZoneName(x, y, z, false)
    return ZONE_PROFILE[zone] or "default", zone, GANGS[zone]
end

function citizenProfileSkin(profile)
    return pick((POP[profile] or POP.default).peds)
end

-- Vector unitario que se aleja de la calzada mas cercana (hacia las casas), o nil
function citizenAwayFromRoad(x, y)
    if not vehGrid then return end
    local n = nearestNode(VEH_NODES, vehGrid, x, y)
    if not n then return end
    local rx, ry = nodePos(VEH_NODES, n)
    local dx, dy = x - rx, y - ry
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 or len > 40 then return end
    return dx / len, dy / len
end

function citizenIsVisible(x, y, z)
    return visibleFromCamera(x, y, z)
end

function citizenWantedLevel()
    return playerWanted() and true or false
end

----------------------------------------------------------------
-- Sincronizacion entre jugadores del mismo auto (c_sync.lua)
-- Conductor: envia los autos y peatones cercanos (getNearbyForSync).
-- Pasajero: suspende su poblacion local y muestra la del conductor.
----------------------------------------------------------------
function setCitizensSuspended(state)
    state = state and true or false
    if suspended == state then return end
    suspended = state
    if not suspended then return end
    -- Los que se ven se desvanecen en ~1 s (no desaparecen de golpe); los que no se ven se borran ya
    local now = getTickCount()
    for v, s in pairs(cars) do
        if isElement(v) and getVehicleController(v) ~= localPlayer and isElementOnScreen(v) then
            if not s.fadeStart then
                s.fadeStart = now
                setElementCollisionsEnabled(v, false)
                if isElement(s.driver) then setPedControlState(s.driver, "handbrake", true) end
            end
        else
            removeCar(v)
        end
    end
    for p, s in pairs(peds) do
        if isElement(p) and isElementOnScreen(p) then s.fadeStart = s.fadeStart or now else removePed(p) end
    end
end

-- El pasajero deja de serlo: la copia de un auto del conductor pasa a ser un auto real de su poblacion
-- (conserva posicion, rumbo y velocidad y se engancha al carril mas cercano). false si no se pudo.
function adoptMirrorCar(vehicle, driver, speedMs)
    if cars[vehicle] or not isElement(vehicle) or not isElement(driver) or carCount >= CFG.MAX_CARS + 4 then return false end
    local x, y = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    local n, target = nearestLane(x, y, m[2][1], m[2][2])
    if not n then return false end
    setElementData(vehicle, "rp:citizen", true, false)
    setElementData(driver, "rp:citizen", true, false)
    local s = {
        driver = driver, prev = n, node = target, wp = {}, police = false, style = newDriverStyle(),
        lenF = vehicleLenFactor(vehicle), state = "DRIVE", blockedSince = 0, stuckSince = 0, until_ = 0, recoverUntil = 0,
    }
    cars[vehicle] = s
    carCount = carCount + 1
    s.dSpeed = speedMs or 0
    makeReal(vehicle, s)            -- fisica, apoya sobre el suelo y conserva la velocidad
    -- primer punto: proyeccion sobre el carril elegido, unos metros por delante
    local sx, sy, sz, dx, dy = laneStart(n, target)
    local nx2, ny2 = nodePos(VEH_NODES, target)
    local len = math.max(1, getDistanceBetweenPoints2D(sx, sy, nx2, ny2))
    local t = math.max(0, math.min(len - 8, (x - sx) * dx + (y - sy) * dy + 8))
    s.wp[1] = { sx + dx * t, sy + dy * t, sz, 0, nil }
    return true
end

-- Igual para un peaton copiado: sigue caminando desde donde esta
function adoptMirrorPed(ped)
    if peds[ped] or not isElement(ped) or pedCount >= CFG.MAX_PEDS + 4 then return false end
    setElementData(ped, "rp:citizen", true, false)
    local s = { state = "WALK", node = nil, prev = nil, brave = math.random() < CFG.BRAVE_CHANCE, until_ = 0 }
    peds[ped] = s
    pedCount = pedCount + 1
    setElementCollisionsEnabled(ped, true)
    setPedControlState(ped, "forwards", false)
    setPedControlState(ped, "walk", false)
    setPedControlState(ped, "sprint", false)
    resumeWalk(ped, s)              -- elige el nodo peatonal mas cercano (o lo retira si no hay)
    return peds[ped] ~= nil
end

local nextSid = 0

-- Lista plana de numeros: por entidad { tipo (1 auto, 2 peaton), id, modelo, x, y, z, rx, ry, rz, vx, vy, vz, colores(6), skin conductor, variantes(2), luces }
function getNearbyForSync(px, py, radius, maxCars, maxPeds)
    local r2 = radius * radius
    local function nearest(tbl, limit, keep)
        local found = {}
        for el, s in pairs(tbl) do
            if isElement(el) and keep(el, s) then
                local x, y = getElementPosition(el)
                local d2 = (x - px) ^ 2 + (y - py) ^ 2
                if d2 < r2 then found[#found + 1] = { d2, el, s } end
            end
        end
        table.sort(found, function(a, b) return a[1] < b[1] end)
        for i = #found, limit + 1, -1 do found[i] = nil end
        return found
    end
    local out = {}
    local function emit(kind, el, s)
        if not s.sid then
            nextSid = nextSid + 1
            s.sid = nextSid
        end
        local x, y, z = getElementPosition(el)
        local rx, ry, rz = getElementRotation(el)
        local vx, vy, vz = getElementVelocity(el)
        local i = #out
        out[i + 1], out[i + 2], out[i + 3] = kind, s.sid, getElementModel(el)
        out[i + 4], out[i + 5], out[i + 6] = x, y, z
        out[i + 7], out[i + 8], out[i + 9] = rx, ry, rz
        out[i + 10], out[i + 11], out[i + 12] = vx, vy, vz
        -- 13-22: colores (2 x RGB), skin del conductor, variantes, luces (solo autos; ceros en peatones)
        if kind == 1 then
            local r1, g1, b1, r2, g2, b2 = getVehicleColor(el, true)
            local drv = getVehicleController(el)
            local v1, v2 = getVehicleVariant(el)
            out[i + 13], out[i + 14], out[i + 15] = r1 or 0, g1 or 0, b1 or 0
            out[i + 16], out[i + 17], out[i + 18] = r2 or 0, g2 or 0, b2 or 0
            out[i + 19] = drv and getElementModel(drv) or 0
            out[i + 20], out[i + 21] = v1 or 255, v2 or 255
            out[i + 22] = getVehicleOverrideLights(el) or 0
        else
            for k = 13, 22 do out[i + k] = 0 end
        end
    end
    for _, f in ipairs(nearest(cars, maxCars, function() return true end)) do emit(1, f[2], f[3]) end
    for _, f in ipairs(nearest(peds, maxPeds, function(p, s) return s.state ~= "DEAD" end)) do emit(2, f[2], f[3]) end
    return out
end
