--[[
    rp_citizens / c_air.lua
    Trafico con HORARIO COMPARTIDO (cliente), DETERMINISTA: aviones, helicopteros y barcos de linea siguen un
    horario fijo calculado con el reloj del servidor (s_clock.lua). Todos los jugadores ven la misma nave en el
    mismo sitio y a la misma hora sin que el servidor envie posiciones (cada cliente crea su copia solo cerca).
      - Vuelos de crucero entre aeropuertos (LS, SF, LV) y aerodromos, en los dos sentidos.
      - Circuitos cerrados: fumigadora en Red County, avionetas en Verdant Meadows, helicopteros de noticias,
        turisticos y de patrulla sobre las ciudades.
      - Lanzaderas por mar (ferry de la bahia de SF, lancha de LS): van y vuelven por la red de barcos del juego
        (c_nodes_boat.lua), aceleran y frenan al llegar, esperan en el muelle y pitan al salir.
      - Sin colision. No estan congelados: se colocan cada fotograma y llevan la velocidad real, para que suenen
        el motor, giren las helices y los rotores y haya efecto Doppler.
    Modelo de movimiento: cada ruta tiene una tabla tiempo -> distancia recorrida (velocidad por tramo), asi que
    la posicion sale SIEMPRE de la hora (nada se acumula) y no se desincroniza.
    Siguen el interruptor de la poblacion (/poblacion) y piden personaje cargado, fuera de interiores.
]]

----------------------------------------------------------------
-- Configuracion
----------------------------------------------------------------
local CFG = {
    CREATE_DIST = 700,     -- crea la nave cuando su punto de la ruta esta a menos de esto (3D)
    REMOVE_DIST = 800,
    MAX = 6,               -- naves a la vez como mucho (las mas cercanas)
    TICK = 500,            -- ms entre revisiones del horario
    RESYNC_MS = 600000,    -- vuelve a pedir la hora al servidor cada 10 min
    PILOT_SKIN = 61,
    BANK_SIGN = 1,         -- si en juego alabean hacia fuera de la curva, poner -1
    LOD_PLANES = 500,      -- distancia de dibujado de aviones y trenes (setVehiclesLODDistance)
    SHUTTLE_ACCEL = 0.35,  -- m/s2 de las lanzaderas al salir y al llegar
    BOAT_DRAFT = 0.8,      -- calado de los barcos de linea (m)
}

-- Rutas. kind: "plane" | "heli" | "boat".
--   Abiertas: salen cada "period" s (+ "offset"); both = tambien en sentido contrario (desfasado medio periodo).
--   loop = circuito cerrado con "n" naves repartidas.
--   shuttle = va de "from" a "to" por la red de barcos y vuelve, con "dwell" s de parada en cada muelle.
-- speed en m/s. pts: x, y, z [, velocidad en ese punto] (se suavizan con Catmull-Rom).
local ROUTES = {
    -- Crucero: entran y salen fuera del mapa (solo existen cerca del jugador)
    { name = "LS-SF", kind = "plane", period = 300, offset = 0, speed = 75, both = true,
      models = { 577, 577, 519, 592 },   -- AT-400, AT-400, Shamal, Andromada
      pts = { { 3600, -2650, 360 }, { 2400, -2493, 270 }, { 1700, -2470, 250 }, { 600, -2350, 290 },
              { -300, -2100, 320 }, { -1000, -1000, 320 }, { -1350, -300, 280 }, { -2200, -200, 320 }, { -3600, -150, 360 } } },
    { name = "LS-LV", kind = "plane", period = 360, offset = 70, speed = 70, both = true,
      models = { 577, 519, 553, 519 },   -- AT-400, Shamal, Nevada, Shamal
      pts = { { 1700, -3600, 360 }, { 1750, -2450, 260 }, { 1650, -1300, 320 }, { 1550, -200, 330 },
              { 1500, 700, 320 }, { 1520, 1500, 270 }, { 1500, 2400, 300 }, { 1400, 3600, 360 } } },
    { name = "SF-LV", kind = "plane", period = 420, offset = 150, speed = 70, both = true,
      models = { 519, 577, 553 },
      pts = { { -3600, 400, 360 }, { -2300, 300, 340 }, { -1400, -250, 280 }, { -900, 600, 330 },
              { -200, 1300, 330 }, { 700, 1450, 320 }, { 1550, 1500, 270 }, { 2500, 1650, 320 }, { 3600, 1700, 360 } } },
    -- Avionetas de un lado a otro de la costa, bajas para que se vean bien. Las alturas de las avionetas
    -- son ~30-40 m sobre el suelo mas alto de cada tramo (nodos de calles y aceras del juego a menos de 150 m)
    { name = "Costa", kind = "plane", period = 480, offset = 230, speed = 42, both = true,
      models = { 593, 511, 593 },        -- Dodo, Beagle
      pts = { { 3600, -1900, 70 },
              { 2900, -2200, 90 },       -- 90 m: gruas de Ocean Docks
              { 2000, -2650, 60 }, { 900, -2750, 55 },
              { 0, -2900, 100 }, { -1200, -2900, 110 }, { -2900, -2900, 90 }, { -3600, -2600, 70 } } },

    -- Circuitos cerrados
    { name = "Fumigadora", kind = "plane", loop = true, n = 1, speed = 35, models = { 512 },
      pts = { { 200, -100, 72 }, { 700, -200, 75 }, { 1250, 150, 65 }, { 750, 380, 60 }, { 250, 220, 60 } } },
    { name = "Verdant Meadows", kind = "plane", loop = true, n = 2, speed = 40, models = { 593, 511 },
      pts = { { 100, 2400, 100 }, { 800, 2400, 75 }, { 850, 2650, 105 }, { 450, 2750, 105 }, { 100, 2700, 100 } } },
    { name = "Noticias LS", kind = "heli", loop = true, n = 1, speed = 22, models = { 488 },
      pts = { { 1750, -1300, 200 }, { 1500, -1050, 200 }, { 1250, -1300, 200 }, { 1500, -1550, 200 } } },
    { name = "Turismo Vinewood", kind = "heli", loop = true, n = 1, speed = 28, models = { 487 },
      pts = { { 1400, -750, 190 }, { 1000, -600, 200 }, { 700, -900, 190 }, { 1000, -1150, 180 }, { 1350, -1000, 180 } } },
    { name = "Patrulla LS", kind = "heli", loop = true, n = 1, speed = 30, models = { 497 }, police = true,
      pts = { { 2300, -1750, 140 }, { 2550, -1350, 140 }, { 2150, -1100, 140 }, { 1850, -1650, 140 } } },
    { name = "Noticias SF", kind = "heli", loop = true, n = 1, speed = 22, models = { 488 },
      pts = { { -1650, 700, 250 }, { -1900, 950, 250 }, { -2150, 700, 250 }, { -1900, 450, 250 } } },
    { name = "Turismo Strip", kind = "heli", loop = true, n = 1, speed = 26, models = { 487 },
      pts = { { 2050, 1000, 180 }, { 2050, 2000, 180 }, { 2250, 2000, 180 }, { 2250, 1000, 180 } } },

    -- Lanzaderas por mar (Tropic): la ruta sale de la red de barcos entre los dos muelles
    { name = "Ferry bahia SF", kind = "boat", shuttle = true, speed = 9, dwell = 45, offset = 0, models = { 454 },
      from = { -2174, 2296 },            -- Bayside
      to = { -1628, 1488 } },            -- Pier 69 (Esplanade North)
    { name = "Lancha Santa Maria", kind = "boat", shuttle = true, speed = 10, dwell = 40, offset = 25, models = { 454 },
      from = { 859, -2149 },             -- muelle de Santa Maria
      to = { 2761, -2677 } },            -- Ocean Docks
}

----------------------------------------------------------------
-- Reloj del servidor
----------------------------------------------------------------
local clockOffset   -- ms del servidor = getTickCount() + clockOffset

addEvent("rp:citizens:clockRecv", true)
addEventHandler("rp:citizens:clockRecv", resourceRoot, function(serverMs)
    if type(serverMs) == "number" then clockOffset = serverMs - getTickCount() end
end)

-- Segundos del servidor (con decimales), o nil si aun no llego la hora
local function airNow()
    if not clockOffset then return nil end
    return (getTickCount() + clockOffset) / 1000
end

----------------------------------------------------------------
-- Geometria y tiempos de las rutas (se precalcula al arrancar)
----------------------------------------------------------------
local SAMPLE = 25   -- metros entre puntos de la curva suavizada

local function catmull(p0, p1, p2, p3, t)
    local t2, t3 = t * t, t * t * t
    local r = {}
    for i = 1, 3 do
        r[i] = 0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
            + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
    end
    r[4] = p1[4] + (p2[4] - p1[4]) * t   -- velocidad: lineal entre puntos
    return r
end

-- Curva suave muestreada (P = puntos x, y, z, v; D = distancia acumulada; L = largo total)
local function buildCurve(pts, loop)
    local n = #pts
    local function at(i)
        if loop then return pts[(i - 1) % n + 1] end
        return pts[math.max(1, math.min(n, i))]
    end
    local P = {}
    local last = loop and n or n - 1
    for i = 1, last do
        local a, b = at(i), at(i + 1)
        local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
        local steps = math.max(1, math.floor(len / SAMPLE))
        for s = 0, steps - 1 do P[#P + 1] = catmull(at(i - 1), a, b, at(i + 2), s / steps) end
    end
    local e = loop and P[1] or pts[n]
    P[#P + 1] = { e[1], e[2], e[3], e[4] }
    local D = { 0 }
    for i = 2, #P do
        D[i] = D[i - 1] + math.sqrt((P[i][1] - P[i - 1][1]) ^ 2 + (P[i][2] - P[i - 1][2]) ^ 2 + (P[i][3] - P[i - 1][3]) ^ 2)
    end
    return P, D, D[#D]
end

-- Tabla de tiempos: T[i] = segundos desde el inicio hasta el punto i (velocidad media de cada tramo)
local function buildTimes(r)
    local T = { 0 }
    for i = 2, #r.P do
        local v = math.max(0.5, (r.P[i - 1][4] + r.P[i][4]) / 2)
        T[i] = T[i - 1] + (r.D[i] - r.D[i - 1]) / v
    end
    r.T, r.dur = T, T[#T]
end

-- Busqueda binaria del tramo de una tabla creciente
local function findSeg(tbl, v)
    local lo, hi = 1, #tbl
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if tbl[mid] <= v then lo = mid else hi = mid end
    end
    return lo, hi
end

-- Distancia recorrida a los tau segundos de empezar la ruta
local function sAtTime(r, tau)
    tau = math.max(0, math.min(r.dur, tau))
    local lo, hi = findSeg(r.T, tau)
    local seg = r.T[hi] - r.T[lo]
    return r.D[lo] + (r.D[hi] - r.D[lo]) * (seg > 0 and (tau - r.T[lo]) / seg or 0)
end

-- Segundos que tarda en llegar a la distancia s
local function timeAtS(r, s)
    s = math.max(0, math.min(r.L, s))
    local lo, hi = findSeg(r.D, s)
    local seg = r.D[hi] - r.D[lo]
    return r.T[lo] + (r.T[hi] - r.T[lo]) * (seg > 0 and (s - r.D[lo]) / seg or 0)
end

-- Punto de la curva a la distancia s: x, y, z, velocidad
local function sampleAt(r, s)
    local P, D = r.P, r.D
    if r.loop then s = s % r.L else s = math.max(0, math.min(r.L, s)) end
    local lo, hi = findSeg(D, s)
    local seg = D[hi] - D[lo]
    local k = seg > 0 and (s - D[lo]) / seg or 0
    local a, b = P[lo], P[hi]
    return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, a[4] + (b[4] - a[4]) * k
end

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end

local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Pose en s: posicion, rumbo, cabeceo, alabeo, vector de velocidad (m/s) y velocidad.
-- back = recorre la ruta al reves (vuelta de una lanzadera); v = velocidad actual (0 parado en el muelle)
local function poseAt(r, s, back, v)
    local x, y, z, vs = sampleAt(r, s)
    v = v or vs
    local bx, by, bz = sampleAt(r, s - 40)
    local fx, fy, fz = sampleAt(r, s + 40)
    if back then bx, by, bz, fx, fy, fz = fx, fy, fz, bx, by, bz end
    local rz = heading(fx - bx, fy - by)
    local flat = math.max(0.1, getDistanceBetweenPoints2D(bx, by, fx, fy))
    local pitch = math.deg(math.atan2(fz - bz, flat))
    -- alabeo de un giro coordinado: atan(v * omega / g), con el giro medido en una ventana que crece con la
    -- velocidad (los aviones rapidos entran y salen del alabeo con suavidad)
    local w = r.kind == "plane" and math.max(40, r.speed * 2) or 40
    local wbx, wby = sampleAt(r, s - w)
    local wfx, wfy = sampleAt(r, s + w)
    if back then wbx, wby, wfx, wfy = wfx, wfy, wbx, wby end
    local omega = math.rad(angleDiff(heading(wfx - x, wfy - y), heading(x - wbx, y - wby))) / (w / math.max(1, v))
    local roll = math.deg(math.atan(v * omega / 9.81)) * CFG.BANK_SIGN
    if r.kind == "heli" then
        roll = clamp(roll, -15, 15)
        pitch = pitch - 6   -- morro abajo en avance
    elseif r.kind == "boat" then
        roll, pitch = clamp(roll * 0.3, -5, 5), 0
    else
        local maxBank = r.speed >= 60 and 25 or 35   -- reactores de linea: giros suaves
        roll = clamp(roll, -maxBank, maxBank)
    end
    local d = math.max(0.1, math.sqrt((fx - bx) ^ 2 + (fy - by) ^ 2 + (fz - bz) ^ 2))
    return x, y, z, pitch, roll, rz, (fx - bx) / d * v, (fy - by) / d * v, (fz - bz) / d * v, v
end

-- Hash determinista (mismo modelo para el mismo vuelo en todos los clientes)
local function hash(a, b) return (a * 73856093 + b * 19349663) % 1000003 end

-- Camino mas corto por la red de barcos entre los nodos mas cercanos a dos puntos (Dijkstra; deterministico)
local function boatPath(from, to)
    if not BOAT_NODES or not BOAT_LINKS then return nil end
    local n = #BOAT_NODES / 3
    local function nearest(x, y)
        local best, bd
        for i = 1, n do
            if BOAT_LINKS[i] and #BOAT_LINKS[i] > 0 then
                local d = (BOAT_NODES[i * 3 - 2] - x) ^ 2 + (BOAT_NODES[i * 3 - 1] - y) ^ 2
                if not bd or d < bd then best, bd = i, d end
            end
        end
        return best
    end
    local a, b = nearest(from[1], from[2]), nearest(to[1], to[2])
    if not a or not b then return nil end
    local dist, prev, done = { [a] = 0 }, {}, {}
    while true do
        local u, ud
        for i, d in pairs(dist) do
            if not done[i] and (not ud or d < ud or (d == ud and i < u)) then u, ud = i, d end
        end
        if not u or u == b then break end
        done[u] = true
        local ux, uy = BOAT_NODES[u * 3 - 2], BOAT_NODES[u * 3 - 1]
        for _, w in ipairs(BOAT_LINKS[u] or {}) do
            local nd = ud + math.sqrt((BOAT_NODES[w * 3 - 2] - ux) ^ 2 + (BOAT_NODES[w * 3 - 1] - uy) ^ 2)
            if not dist[w] or nd < dist[w] then dist[w], prev[w] = nd, u end
        end
    end
    if not dist[b] then return nil end
    local path, i = {}, b
    while i do
        table.insert(path, 1, { BOAT_NODES[i * 3 - 2], BOAT_NODES[i * 3 - 1], BOAT_NODES[i * 3] })
        i = prev[i]
    end
    return path
end

local routes = {}

local function prepareRoutes()
    routes = {}
    for _, def in ipairs(ROUTES) do
        local function add(pts, offset, suffix)
            local r = {}
            for k, v in pairs(def) do r[k] = v end
            r.name, r.offset = def.name .. suffix, offset
            local full = {}
            for i, p in ipairs(pts) do full[i] = { p[1], p[2], p[3], p[4] or def.speed } end
            r.P, r.D, r.L = buildCurve(full, def.loop)
            if def.shuttle then
                -- acelera al salir y frena al llegar: v(s) = min(crucero, sqrt(v0^2 + 2 a d)) desde cada extremo
                for i, p in ipairs(r.P) do
                    local d = math.min(r.D[i], r.L - r.D[i])
                    p[4] = math.min(def.speed, math.sqrt(1 + 2 * CFG.SHUTTLE_ACCEL * d))
                end
            end
            buildTimes(r)
            routes[#routes + 1] = r
        end
        if def.shuttle then
            local path = boatPath(def.from, def.to)
            if path and #path >= 2 then
                add(path, def.offset or 0, "")
            else
                outputDebugString("[rp_citizens] sin camino por mar para la ruta " .. def.name, 2)
            end
        else
            add(def.pts, def.offset or 0, "")
            if def.both and not def.loop then
                local rev = {}
                for i = #def.pts, 1, -1 do rev[#rev + 1] = def.pts[i] end
                add(rev, (def.offset or 0) + def.period / 2, " (vuelta)")
            end
        end
    end
end

----------------------------------------------------------------
-- Horario: que naves hay en una ruta en el instante t y donde van
----------------------------------------------------------------

-- Numeros de nave que pueden existir en el instante t
local function instancesAt(r, t)
    if r.shuttle then return 1, 1 end
    if r.loop then return 1, r.n end
    return math.floor((t - r.offset - r.dur) / r.period), math.floor((t - r.offset) / r.period)
end

-- Estado de la nave k de la ruta r en t: s (metros), back (va al reves; atracada: sentido en que saldra),
-- v (m/s), docked, dockFrac (0..1 de la parada); nil si no existe
local function stateAt(r, k, t)
    if r.shuttle then
        local cycle = 2 * (r.dur + r.dwell)
        local p = (t - r.offset) % cycle
        if p < r.dwell then return 0, false, 0, true, p / r.dwell end
        p = p - r.dwell
        if p < r.dur then
            local s = sAtTime(r, p)
            return s, false, select(4, sampleAt(r, s)), false
        end
        p = p - r.dur
        if p < r.dwell then return r.L, true, 0, true, p / r.dwell end
        p = p - r.dwell
        local s = r.L - sAtTime(r, p)   -- el perfil de velocidad es simetrico: la vuelta es la ida al reves
        return s, true, select(4, sampleAt(r, s)), false
    end
    local tau
    if r.loop then
        tau = (t + (k - 1) * r.dur / r.n) % r.dur
    else
        tau = t - (k * r.period + r.offset)
        if tau < 0 or tau > r.dur then return nil end
    end
    local s = sAtTime(r, tau)
    return s, false, select(4, sampleAt(r, s)), false
end

----------------------------------------------------------------
-- Naves activas: [clave "ruta:numero"] = { vehicle, pilot, r, k }
----------------------------------------------------------------
local active, activeCount = {}, 0

local function isNight()
    local h = getTime()
    return h >= 21 or h < 6
end

local function destroyAircraft(key)
    local a = active[key]
    if not a then return end
    active[key] = nil
    activeCount = activeCount - 1
    if isElement(a.pilot) then destroyElement(a.pilot) end
    if isElement(a.vehicle) then destroyElement(a.vehicle) end
end

local function clearAir()
    for key in pairs(active) do destroyAircraft(key) end
end

-- Altura del centro de un barco sobre el agua (base del casco menos el calado); nil si el modelo no cargo
local function boatLift(vehicle)
    if not isElementStreamedIn(vehicle) then return nil end
    local _, _, minZ = getElementBoundingBox(vehicle)
    if not minZ or minZ >= 0 or minZ < -6 then return nil end
    return -minZ - CFG.BOAT_DRAFT
end

local function honk(a, ms)
    if not isElement(a.pilot) then return end
    setPedControlState(a.pilot, "horn", true)
    setTimer(function() if isElement(a.pilot) then setPedControlState(a.pilot, "horn", false) end end, ms, 1)
end

local function placeAircraft(a, t)
    local s, back, v, docked, frac = stateAt(a.r, a.k, t)
    if not s then return false end
    local x, y, z, pitch, roll, rz, vx, vy, vz = poseAt(a.r, s, back, v)
    if docked then
        -- atracada: da la vuelta despacio (mitad central de la parada) del rumbo de llegada al de salida
        local arr = select(6, poseAt(a.r, s, not back, 0))
        local u = clamp((frac - 0.2) / 0.6, 0, 1)
        rz = arr + angleDiff(rz, arr) * u * u * (3 - 2 * u)
    end
    if a.r.kind == "boat" then
        -- flota sobre el agua real con vaiven; el agua se consulta cada medio segundo
        a.frame = (a.frame or 0) + 1
        if a.frame % 30 == 1 or not a.water then a.water = getWaterLevel(x, y, (a.water or z) + 3) or a.water or z end
        a.lift = a.lift or boatLift(a.vehicle)
        local ph = t * 1.2 + a.k
        z = a.water + (a.lift or 0.8) + math.sin(ph) * 0.06
        pitch = math.sin(ph * 0.8) * 0.8 + v * 0.25
        roll = roll + math.sin(ph * 0.9) * 1.0
        vz = 0
        if docked then
            -- parado en el muelle: motor al ralenti
            if isElement(a.pilot) and a.gas ~= false then setPedControlState(a.pilot, "accelerate", false) a.gas = false end
        else
            if a.gas == false and isElement(a.pilot) then
                setPedControlState(a.pilot, "accelerate", true)
                a.gas = true
                honk(a, 1500)   -- sale del muelle
            end
        end
    end
    setElementPosition(a.vehicle, x, y, z)
    setElementRotation(a.vehicle, pitch, roll, rz)
    setElementVelocity(a.vehicle, vx / 50, vy / 50, vz / 50)   -- MTA: unidades por 1/50 s
    return true
end

local function createAircraft(key, r, k, t)
    local idx = 0
    for i, rr in ipairs(routes) do if rr == r then idx = i break end end
    local model = r.models[hash(idx, k) % #r.models + 1]
    local s, back, v = stateAt(r, k, t)
    if not s then return end
    local x, y, z, _, _, rz = poseAt(r, s, back, v)
    local vehicle = createVehicle(model, x, y, z, 0, 0, rz)
    if not vehicle then return end
    local skin = r.kind == "boat" and (citizenPickSkin and citizenPickSkin(x, y, z) or 7) or CFG.PILOT_SKIN
    local pilot = createPed(skin, x, y, z + 2)
    if not pilot then destroyElement(vehicle) return end
    setElementData(vehicle, "rp:citizenAir", true, false)
    warpPedIntoVehicle(pilot, vehicle)
    setElementCollisionsEnabled(vehicle, false)
    setVehicleEngineState(vehicle, true)
    setVehicleDamageProof(vehicle, true)
    setPedControlState(pilot, "accelerate", true)   -- motor a fondo: sonido de crucero
    if getVehicleType(vehicle) == "Plane" then setVehicleLandingGearDown(vehicle, false) end
    if isNight() then setVehicleOverrideLights(vehicle, 2) end
    if r.police then setElementData(vehicle, "rp:copCar", true, false) end
    active[key] = { vehicle = vehicle, pilot = pilot, r = r, k = k }
    activeCount = activeCount + 1
    placeAircraft(active[key], t)
end

local function allowed()
    return citizenPopulationEnabled and citizenPopulationEnabled() and getElementData(localPlayer, "rp:characterId")
        and getElementInterior(localPlayer) == 0 and getElementDimension(localPlayer) == 0
end

-- Revisa el horario: crea las naves que pasan cerca y quita las que se alejaron o terminaron
local function airTick()
    local t = airNow()
    if not t or not allowed() then
        if activeCount > 0 then clearAir() end
        return
    end
    local px, py, pz = getElementPosition(localPlayer)

    local want = {}
    for _, r in ipairs(routes) do
        local first, last = instancesAt(r, t)
        for k = first, last do
            local s = stateAt(r, k, t)
            if s then
                local x, y, z = sampleAt(r, s)
                local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                local key = r.name .. ":" .. k
                if d < (active[key] and CFG.REMOVE_DIST or CFG.CREATE_DIST) then
                    want[#want + 1] = { key = key, r = r, k = k, d = d }
                end
            end
        end
    end
    table.sort(want, function(a, b) return a.d < b.d end)
    local keep = {}
    for i = 1, math.min(#want, CFG.MAX) do keep[want[i].key] = want[i] end

    for key, a in pairs(active) do
        if not keep[key] or not isElement(a.vehicle) then destroyAircraft(key) end
    end
    for key, w in pairs(keep) do
        if not active[key] then createAircraft(key, w.r, w.k, t) end
    end
    -- helicopteros: rotor siempre girando aunque la fisica no lo mantenga
    for _, a in pairs(active) do
        if getVehicleType(a.vehicle) == "Helicopter" then setHelicopterRotorSpeed(a.vehicle, 0.2) end
    end
end

-- Cada fotograma: la posicion sale de la hora (sin acumular), asi que no se desincroniza
local function moveAir()
    if activeCount == 0 then return end
    local t = airNow()
    if not t then return end
    for key, a in pairs(active) do
        if isElement(a.vehicle) then
            if not placeAircraft(a, t) then destroyAircraft(key) end
        end
    end
end

----------------------------------------------------------------
-- Arranque
----------------------------------------------------------------
local timers = {}
local prevLod

addEventHandler("onClientResourceStart", resourceRoot, function()
    prepareRoutes()
    triggerServerEvent("rp:citizens:clock", resourceRoot)
    timers.sync = setTimer(function() triggerServerEvent("rp:citizens:clock", resourceRoot) end, CFG.RESYNC_MS, 0)
    timers.tick = setTimer(airTick, CFG.TICK, 0)
    addEventHandler("onClientPreRender", root, moveAir)
    -- aviones visibles de mas lejos (sin tocar la distancia de los autos)
    local veh, planes = getVehiclesLODDistance()
    if planes and planes < CFG.LOD_PLANES then
        prevLod = { veh, planes }
        setVehiclesLODDistance(veh, CFG.LOD_PLANES)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, t in pairs(timers) do if isTimer(t) then killTimer(t) end end
    clearAir()
    if prevLod then setVehiclesLODDistance(prevLod[1], prevLod[2]) end
end)

-- Para /poblacioninfo y /vuelos
function citizenAirCount()
    return activeCount, #routes
end

----------------------------------------------------------------
-- /gotoaircraft [ruta] (alias /irvuelo, solo admins: el servidor comprueba el permiso y manda este evento).
-- Elige una nave que siga en ruta dentro de LEAD s, lleva al admin al suelo justo bajo el punto por donde
-- pasara entonces y la sigue en el radar con un blip hasta que sale del mapa (como mucho 3 min).
----------------------------------------------------------------
local GOTO = { LEAD = 30, BLIP_MS = 180000, MAP = 2950 }
local follow   -- { blip, r, k, untilT, timer }

local function stopFollow()
    if not follow then return end
    if isElement(follow.blip) then destroyElement(follow.blip) end
    if isTimer(follow.timer) then killTimer(follow.timer) end
    follow = nil
end

local function insideMap(x, y) return math.abs(x) < GOTO.MAP and math.abs(y) < GOTO.MAP end

-- Mejor nave: con nombre, la que mas tiempo siga en el mapa de las que coincidan; sin nombre, los vuelos de
-- linea primero (son los dificiles de encontrar) y, entre ellos, el que mas tiempo le queda en el mapa
local function pickFlight(query, t)
    local best
    local tt = t + GOTO.LEAD
    for _, r in ipairs(routes) do
        if query == "" or r.name:lower():find(query, 1, true) then
            local first, last = instancesAt(r, tt)
            for k = first, last do
                local s = stateAt(r, k, tt)
                if s then
                    local x, y, z = sampleAt(r, s)
                    if insideMap(x, y) then
                        local left = math.huge
                        if not r.loop and not r.shuttle then
                            -- tiempo que seguira dentro del mapa desde ese punto
                            local exitS = r.L
                            for ss = s, r.L, 50 do
                                local xx, yy = sampleAt(r, ss)
                                if not insideMap(xx, yy) then exitS = ss break end
                            end
                            left = timeAtS(r, exitS) - timeAtS(r, s)
                        end
                        local score = ((r.loop or r.shuttle) and 0 or 1e6) + math.min(left, 1e5)
                        if not best or score > best.score then
                            best = { r = r, k = k, x = x, y = y, z = z, score = score }
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Baja al admin al suelo (o al agua) cuando carga la colision de la zona
local function landAt(x, y, zAir, tries)
    tries = tries or 0
    local gz = getGroundPosition(x, y, zAir)
    local wz = getWaterLevel(x, y, (gz and gz ~= 0) and gz or 0)
    if (gz and gz ~= 0) or wz or tries >= 10 then
        local z = math.max(gz or 0, wz or -1000)
        if z <= -1000 then z = 20 end
        setElementPosition(localPlayer, x, y, z + 1)
        setElementFrozen(localPlayer, false)
        return
    end
    setTimer(landAt, 500, 1, x, y, zAir, tries + 1)
end

addEvent("rp:citizens:air:goto", true)
addEventHandler("rp:citizens:air:goto", resourceRoot, function(query)
    local t = airNow()
    if not t then return exports.rp_notify:notify("Aun no llega la hora del servidor; prueba en unos segundos.", "warning") end
    if #routes == 0 then return end
    query = tostring(query or ""):lower()
    local f = pickFlight(query, t)
    if not f then
        return exports.rp_notify:notify(query == "" and "Ningun vuelo cruza el mapa ahora mismo; prueba en un minuto o con /vuelos."
            or "Ninguna ruta con ese nombre esta en marcha ahora (mira /vuelos).", "warning")
    end
    -- arriba primero (la colision del suelo aun no esta cargada) y luego al suelo; los barcos, en el muelle o
    -- en el agua: se baja desde 40 m por encima
    local above = f.r.kind == "boat" and f.z + 40 or f.z - 60
    setElementFrozen(localPlayer, true)
    setElementPosition(localPlayer, f.x, f.y, above)
    setTimer(landAt, 800, 1, f.x, f.y, math.max(above, f.z))

    stopFollow()
    follow = { r = f.r, k = f.k, untilT = getTickCount() + GOTO.BLIP_MS }
    follow.blip = createBlip(f.x, f.y, f.z, f.r.kind == "boat" and 9 or 5, 2, 255, 255, 255, 255, 0, 99999)
    follow.timer = setTimer(function()
        local now = airNow()
        local s = now and follow and stateAt(follow.r, follow.k, now)
        if not s or getTickCount() > follow.untilT then return stopFollow() end
        local x, y, z = sampleAt(follow.r, s)
        if not insideMap(x, y) then return stopFollow() end
        setElementPosition(follow.blip, x, y, z)
    end, 250, 0)

    local msg = f.r.kind == "boat" and ("%s pasara junto a ti en unos %d s. Lo tienes en el radar."):format(f.r.name, GOTO.LEAD)
        or ("%s pasara sobre ti en unos %d s, a %d m de altura. Lo tienes en el radar."):format(f.r.name, GOTO.LEAD, math.floor(f.z))
    exports.rp_notify:notify(msg, "info")
end)

-- /vuelos: cuando pasa cerca cada ruta (diagnostico y para encontrarlas al probar)
addCommandHandler("vuelos", function()
    local t = airNow()
    if not t then return outputChatBox("[Vuelos] Aun no llega la hora del servidor.", 255, 140, 90) end
    local px, py = getElementPosition(localPlayer)
    outputChatBox(("[Vuelos] %d naves cerca, %d rutas."):format(activeCount, #routes), 120, 200, 255)
    for _, r in ipairs(routes) do
        -- punto de la ruta mas cercano al jugador y cuanto falta para que la proxima nave pase por ahi
        local bestS, bestD = 0, math.huge
        for i = 1, #r.P, 4 do
            local d = getDistanceBetweenPoints2D(px, py, r.P[i][1], r.P[i][2])
            if d < bestD then bestD, bestS = d, r.D[i] end
        end
        local tau0 = timeAtS(r, bestS)
        local line
        if r.shuttle then
            line = ("  %s: a %.0f m de ti; va y vuelve cada %d s (%d s de parada en cada muelle)"):format(
                r.name, bestD, math.floor(2 * (r.dur + r.dwell)), r.dwell)
        else
            local wait
            if r.loop then
                wait = (tau0 - t) % (r.dur / r.n)
            else
                local k = math.ceil((t - r.offset - tau0) / r.period)
                wait = k * r.period + r.offset + tau0 - t
            end
            line = ("  %s: pasa a %.0f m de ti en %d s"):format(r.name, bestD, math.floor(wait))
        end
        outputChatBox(line, 200, 200, 200)
    end
end)
