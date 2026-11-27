--[[
    rp_citizens / c_air.lua
    Trafico aereo ambiental (cliente), DETERMINISTA: aviones y helicopteros siguen un horario fijo calculado con
    el reloj del servidor (s_clock.lua). Todos los jugadores ven el mismo avion en el mismo sitio y a la misma
    hora sin que el servidor envie posiciones (cada cliente crea su copia solo cuando la tiene cerca).
      - Vuelos de crucero entre aeropuertos (LS, SF, LV) y aerodromos, en los dos sentidos, a 250-350 m.
      - Circuitos cerrados a baja altura: fumigadora en Red County, avionetas en Verdant Meadows,
        helicopteros de noticias, turisticos y de patrulla sobre las ciudades.
      - Sin colision (vuelan por encima de todo). No estan congelados: se colocan cada fotograma y llevan la
        velocidad real, para que suenen el motor, giren las helices y los rotores y haya efecto Doppler.
    La posicion en la ruta sale SIEMPRE de la hora (nada se acumula), asi que no se desincronizan.
    Siguen el interruptor de la poblacion (/poblacion) y piden personaje cargado, fuera de interiores.
    Despegues y aterrizajes: fase futura (ver docs/auditorias/rp_citizens.md).
]]

----------------------------------------------------------------
-- Configuracion
----------------------------------------------------------------
local CFG = {
    CREATE_DIST = 700,     -- crea el avion cuando su punto de la ruta esta a menos de esto (3D)
    REMOVE_DIST = 800,
    MAX = 6,               -- aeronaves a la vez como mucho (las mas cercanas)
    TICK = 500,            -- ms entre revisiones del horario
    RESYNC_MS = 600000,    -- vuelve a pedir la hora al servidor cada 10 min
    PILOT_SKIN = 61,
    BANK_SIGN = 1,         -- si en juego alabean hacia fuera de la curva, poner -1
    LOD_PLANES = 500,      -- distancia de dibujado de aviones y trenes (setVehiclesLODDistance)
}

-- Rutas. kind: "plane" | "heli". Abiertas: salen cada "period" s (+ "offset"); both = tambien en sentido
-- contrario (desfasado medio periodo). loop = circuito cerrado con "n" aeronaves repartidas.
-- speed en m/s. pts: x, y, z (se suavizan con Catmull-Rom). Alturas por encima de edificios y montes.
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
    -- Avionetas de un lado a otro de la costa (mas bajas y lentas)
    { name = "Costa", kind = "plane", period = 480, offset = 230, speed = 42, both = true,
      models = { 593, 511, 593 },        -- Dodo, Beagle
      pts = { { 3600, -1900, 180 }, { 2900, -2200, 160 }, { 2000, -2650, 150 }, { 900, -2750, 150 },
              { 0, -2900, 170 }, { -1200, -2900, 190 }, { -2900, -2900, 200 }, { -3600, -2600, 200 } } },

    -- Circuitos cerrados
    { name = "Fumigadora", kind = "plane", loop = true, n = 1, speed = 35, models = { 512 },
      pts = { { 200, -100, 110 }, { 700, -200, 110 }, { 1250, 150, 110 }, { 750, 380, 110 }, { 250, 220, 110 } } },
    { name = "Verdant Meadows", kind = "plane", loop = true, n = 2, speed = 40, models = { 593, 511 },
      pts = { { 100, 2400, 130 }, { 800, 2400, 130 }, { 850, 2650, 140 }, { 450, 2750, 140 }, { 100, 2700, 130 } } },
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
-- Geometria de las rutas (se precalcula al arrancar)
----------------------------------------------------------------
local SAMPLE = 25   -- metros entre puntos de la curva suavizada

local function catmull(p0, p1, p2, p3, t)
    local t2, t3 = t * t, t * t * t
    local r = {}
    for i = 1, 3 do
        r[i] = 0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
            + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
    end
    return r
end

-- Curva suave muestreada (P = puntos, D = distancia acumulada, L = largo total)
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
    P[#P + 1] = loop and { P[1][1], P[1][2], P[1][3] } or { pts[n][1], pts[n][2], pts[n][3] }
    local D = { 0 }
    for i = 2, #P do
        D[i] = D[i - 1] + math.sqrt((P[i][1] - P[i - 1][1]) ^ 2 + (P[i][2] - P[i - 1][2]) ^ 2 + (P[i][3] - P[i - 1][3]) ^ 2)
    end
    return P, D, D[#D]
end

-- Punto de la curva a la distancia s (busqueda binaria)
local function sampleAt(r, s)
    local P, D = r.P, r.D
    if r.loop then s = s % r.L else s = math.max(0, math.min(r.L, s)) end
    local lo, hi = 1, #D
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if D[mid] <= s then lo = mid else hi = mid end
    end
    local seg = D[hi] - D[lo]
    local k = seg > 0 and (s - D[lo]) / seg or 0
    local a, b = P[lo], P[hi]
    return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end

local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Pose en s: posicion, rumbo, cabeceo, alabeo y vector de velocidad (m/s)
local function poseAt(r, s)
    local x, y, z = sampleAt(r, s)
    local bx, by, bz = sampleAt(r, s - 40)
    local fx, fy, fz = sampleAt(r, s + 40)
    local rz = heading(fx - bx, fy - by)
    local flat = math.max(0.1, getDistanceBetweenPoints2D(bx, by, fx, fy))
    local pitch = math.deg(math.atan2(fz - bz, flat))
    -- alabeo de un giro coordinado: atan(v * omega / g), con el giro medido en una ventana que crece con la
    -- velocidad (los aviones rapidos entran y salen del alabeo con suavidad)
    local w = r.kind == "heli" and 40 or math.max(40, r.speed * 2)
    local wbx, wby = sampleAt(r, s - w)
    local wfx, wfy = sampleAt(r, s + w)
    local omega = math.rad(angleDiff(heading(wfx - x, wfy - y), heading(x - wbx, y - wby))) / (w / r.speed)
    local roll = math.deg(math.atan(r.speed * omega / 9.81)) * CFG.BANK_SIGN
    if r.kind == "heli" then
        roll = clamp(roll, -15, 15)
        pitch = pitch - 6   -- morro abajo en avance
    else
        local maxBank = r.speed >= 60 and 25 or 35   -- reactores de linea: giros suaves
        roll = clamp(roll, -maxBank, maxBank)
    end
    local d = math.max(0.1, math.sqrt((fx - bx) ^ 2 + (fy - by) ^ 2 + (fz - bz) ^ 2))
    local vx, vy, vz = (fx - bx) / d * r.speed, (fy - by) / d * r.speed, (fz - bz) / d * r.speed
    return x, y, z, pitch, roll, rz, vx, vy, vz
end

-- Hash determinista (mismo modelo para el mismo vuelo en todos los clientes)
local function hash(a, b) return (a * 73856093 + b * 19349663) % 1000003 end

local routes = {}

local function prepareRoutes()
    routes = {}
    for _, def in ipairs(ROUTES) do
        local function add(pts, offset, suffix)
            local r = {}
            for k, v in pairs(def) do r[k] = v end
            r.name, r.offset = def.name .. suffix, offset
            r.P, r.D, r.L = buildCurve(pts, def.loop)
            routes[#routes + 1] = r
        end
        add(def.pts, def.offset or 0, "")
        if def.both and not def.loop then
            local rev = {}
            for i = #def.pts, 1, -1 do rev[#rev + 1] = def.pts[i] end
            add(rev, (def.offset or 0) + def.period / 2, " (vuelta)")
        end
    end
end

----------------------------------------------------------------
-- Aeronaves activas: [clave "ruta:vuelo"] = { vehicle, pilot, r, k }
----------------------------------------------------------------
local active, activeCount = {}, 0

-- s (metros recorridos) del vuelo k de la ruta r en el instante t, o nil si no esta en el aire
local function flightS(r, k, t)
    if r.loop then
        return t * r.speed + (k - 1) * r.L / r.n
    end
    local s = (t - (k * r.period + r.offset)) * r.speed
    if s < 0 or s > r.L then return nil end
    return s
end

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

local function placeAircraft(a, t)
    local s = flightS(a.r, a.k, t)
    if not s then return false end
    local x, y, z, pitch, roll, rz, vx, vy, vz = poseAt(a.r, s)
    setElementPosition(a.vehicle, x, y, z)
    setElementRotation(a.vehicle, pitch, roll, rz)
    setElementVelocity(a.vehicle, vx / 50, vy / 50, vz / 50)   -- MTA: unidades por 1/50 s
    return true
end

local function createAircraft(key, r, k, t)
    local idx = 0
    for i, rr in ipairs(routes) do if rr == r then idx = i break end end
    local model = r.models[hash(idx, k) % #r.models + 1]
    local s = flightS(r, k, t)
    local x, y, z, _, _, rz = poseAt(r, s)
    local vehicle = createVehicle(model, x, y, z, 0, 0, rz)
    if not vehicle then return end
    local pilot = createPed(CFG.PILOT_SKIN, x, y, z + 2)
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

-- Revisa el horario: crea los vuelos que pasan cerca y quita los que se alejaron o aterrizaron
local function airTick()
    local t = airNow()
    if not t or not allowed() then
        if activeCount > 0 then clearAir() end
        return
    end
    local px, py, pz = getElementPosition(localPlayer)

    -- vuelos que deberian existir ahora, con su distancia
    local want = {}
    for _, r in ipairs(routes) do
        local first, last
        if r.loop then
            first, last = 1, r.n
        else
            last = math.floor((t - r.offset) / r.period)
            first = math.floor((t - r.offset - r.L / r.speed) / r.period)
        end
        for k = first, last do
            local s = flightS(r, k, t)
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

-- /vuelos: proximas aeronaves que pasaran cerca (diagnostico y para encontrarlas al probar)
addCommandHandler("vuelos", function()
    local t = airNow()
    if not t then return outputChatBox("[Vuelos] Aun no llega la hora del servidor.", 255, 140, 90) end
    local px, py = getElementPosition(localPlayer)
    outputChatBox(("[Vuelos] %d aeronaves cerca, %d rutas."):format(activeCount, #routes), 120, 200, 255)
    for _, r in ipairs(routes) do
        -- distancia minima de la ruta al jugador y cuanto falta para que el proximo vuelo pase por ahi
        local bestS, bestD = 0, math.huge
        for i = 1, #r.P, 4 do
            local d = getDistanceBetweenPoints2D(px, py, r.P[i][1], r.P[i][2])
            if d < bestD then bestD, bestS = d, r.D[i] end
        end
        local wait
        if r.loop then
            local s0 = (t * r.speed) % r.L
            local gap = r.L / r.n
            wait = ((bestS - s0) % gap) / r.speed
        else
            local k = math.ceil((t - r.offset - bestS / r.speed) / r.period)
            wait = k * r.period + r.offset + bestS / r.speed - t
        end
        outputChatBox(("  %s: pasa a %.0f m de ti en %d s"):format(r.name, bestD, math.floor(wait)), 200, 200, 200)
    end
end)
