--[[
    rp_races / server / s_ai.lua

    Pilotos IA (RF-12..RF-15). Cada bot es un ped conductor que sigue los nodos pregrabados de la
    pista {x, y, z, rz, velocidad km/h} con controles simulados (setPedControlState / analogico).

    - Curvas: la velocidad objetivo sale del nodo (ya calculada segun la curvatura) por el factor
      de dificultad; el tiempo de reaccion (react) limita cada cuanto decide.
    - Obstaculos: processLineOfSight es solo de cliente, asi que el rayo frontal se calcula en el
      servidor con geometria contra los demas vehiculos de la carrera (adelantar por un lado o frenar).
    - Sin humanos cerca (>230 m) el motor de GTA deja de simular al ped: ahi el bot avanza
      cinematicamente sobre los nodos para no quedarse parado.
]]

local BOT_NAMES = { "Rex", "Dani", "Mica", "Toro", "Vero", "Chino", "Nico", "Luna", "Kiko", "Sol", "Pipe", "Lalo" }
local BOT_SKINS = { 7, 9, 17, 20, 23, 29, 45, 60, 67, 72, 98, 101 }
local KINEMATIC_RANGE = 230

local abs, sqrt, atan2, deg, rad = math.abs, math.sqrt, math.atan2, math.deg, math.rad

local function normAng(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

function raceBotName(i) return "IA " .. BOT_NAMES[((i - 1) % #BOT_NAMES) + 1] end
function raceBotSkin(i) return BOT_SKINS[((i - 1) % #BOT_SKINS) + 1] end

-- Nodo mas cercano que queda por delante (segun el rumbo del vehiculo)
function aiNearestAhead(track, x, y, rz)
    local nodes, best, bi = track.nodes, math.huge, 1
    for i = 1, #nodes do
        local dx, dy = nodes[i][1] - x, nodes[i][2] - y
        local d = dx * dx + dy * dy
        if d < best then best, bi = d, i end
    end
    local n = nodes[bi]
    local fx, fy = -math.sin(rad(rz)), math.cos(rad(rz))
    if (n[1] - x) * fx + (n[2] - y) * fy < 0 then bi = bi % #nodes + 1 end
    return bi
end

-- setPedControlState no existe en el servidor: el servidor decide y el cliente que sincroniza al ped
-- aplica los controles (setPedControlState / setPedAnalogControlState de cliente, ver c_races.lua).
-- Los comandos se agrupan por cliente y se envian una vez por tick (aiFlush).
local function aiCtl(E, steer, acc, brake, hand)
    local race, ped = E.race, E.ped
    if not race or not isElement(ped) then return end
    race.aiBatch = race.aiBatch or {}
    local cmd = { ped, steer, acc, brake and 1 or 0, hand and 1 or 0 }
    local sy = getElementSyncer(ped)
    if sy and race.byPlayer[sy] then
        local b = race.aiBatch[sy] or {}
        race.aiBatch[sy] = b
        b[#b + 1] = cmd
    else
        for p in pairs(race.byPlayer) do
            local b = race.aiBatch[p] or {}
            race.aiBatch[p] = b
            b[#b + 1] = cmd
        end
    end
end

function aiFlush(race)
    local batch = race.aiBatch
    if not batch then return end
    race.aiBatch = nil
    for p, list in pairs(batch) do
        if isElement(p) then triggerClientEvent(p, "rp:races:aiCtl", resourceRoot, list) end
    end
end

function aiStop(E) aiCtl(E, 0, 0, false, true) end

function aiStart(E)
    aiCtl(E, 0, 0, false, false)
    E.lastThink = 0
end

-- Rayo frontal (RF-14): devuelve distancia al obstaculo, lado de esquiva (-1 der / 1 izq) y su velocidad
local function frontObstacle(race, E, x, y, fx, fy)
    local bestD, side, ovx, ovy
    for _, O in ipairs(race.entities) do
        if O ~= E and isElement(O.veh) then
            local ox, oy = getElementPosition(O.veh)
            local rx, ry = ox - x, oy - y
            local along = rx * fx + ry * fy
            if along > 1 and along < 20 then
                local lateral = rx * -fy + ry * fx   -- positivo = a la izquierda
                if abs(lateral) < 3.2 and (not bestD or along < bestD) then
                    bestD, side = along, lateral >= 0 and -1 or 1
                    ovx, ovy = getElementVelocity(O.veh)
                end
            end
        end
    end
    return bestD, side, ovx and sqrt(ovx * ovx + ovy * ovy) * 180 or nil
end

local function kinematicStep(race, E, nodes, dt, tgtKmh)
    local veh = E.veh
    local x, y, z = getElementPosition(veh)
    local n = nodes[E.ni]
    local dx, dy = n[1] - x, n[2] - y
    local d = sqrt(dx * dx + dy * dy)
    local step = tgtKmh / 3.6 * dt
    if d <= step then
        E.ni = E.ni % #nodes + 1
        n = nodes[E.ni]
        dx, dy = n[1] - x, n[2] - y
        d = sqrt(dx * dx + dy * dy)
    end
    if d < 0.01 then return end
    if not isElementFrozen(veh) then setElementFrozen(veh, true) end
    local k = math.min(1, step / d)
    setElementPosition(veh, x + dx * k, y + dy * k, n[3] + 0.8)
    setElementRotation(veh, 0, 0, deg(atan2(-dx, dy)))
    E.kmh = tgtKmh
    E.kinematic = true
end

function aiThink(race, E, now)
    local veh, ped = E.veh, E.ped
    if not isElement(veh) or not isElement(ped) then return end
    local diff = RACE.DIFFICULTY[race.s.difficulty] or RACE.DIFFICULTY[2]
    if E.lastThink and now - E.lastThink < diff.react then return end
    local dt = E.lastThink and E.lastThink > 0 and (now - E.lastThink) / 1000 or 0.1
    E.lastThink = now

    local nodes = race.track.nodes
    local count = #nodes
    local x, y, z = getElementPosition(veh)

    -- humano cerca que sincronice al ped? si no, avance cinematico
    local near = false
    local sy = getElementSyncer(ped)
    if sy and race.byPlayer[sy] then
        for _, hp in ipairs(race.humanPos or {}) do
            local dx, dy = hp[1] - x, hp[2] - y
            if dx * dx + dy * dy < KINEMATIC_RANGE * KINEMATIC_RANGE then near = true break end
        end
    end

    -- avanzar nodo cuando se pasa por encima / resincronizar si se perdio
    local ni = E.ni or 2
    for _ = 1, 6 do
        local n = nodes[ni]
        local dx, dy = n[1] - x, n[2] - y
        if dx * dx + dy * dy < 196 then ni = ni % count + 1 else break end
    end
    local n0 = nodes[ni]
    if (n0[1] - x) ^ 2 + (n0[2] - y) ^ 2 > 3600 and not E.kinematic then
        local _, _, rz = getElementRotation(veh)
        ni = aiNearestAhead(race.track, x, y, rz)
    end
    E.ni = ni

    -- velocidad objetivo: minimo de los proximos nodos (frenar antes de la curva)
    local tgt = 999
    for k = 0, 4 do
        local s = nodes[(ni - 1 + k) % count + 1][5]
        if s < tgt then tgt = s end
    end
    tgt = tgt * diff.speed

    if not near then
        kinematicStep(race, E, nodes, dt, tgt * 0.92)
        return
    end
    if E.kinematic then
        E.kinematic = false
        setElementFrozen(veh, false)
        local _, _, rz = getElementRotation(veh)
        local r = rad(rz)
        local v = tgt / 180 * 0.8
        setElementVelocity(veh, -math.sin(r) * v, math.cos(r) * v, 0)
    end

    local vx, vy, vz = getElementVelocity(veh)
    local kmh = sqrt(vx * vx + vy * vy + vz * vz) * 180
    E.kmh = kmh
    local _, _, rz = getElementRotation(veh)
    local fx, fy = -math.sin(rad(rz)), math.cos(rad(rz))

    -- punto al que apuntar: lo bastante lejos segun la velocidad
    local aim = nodes[ni]
    local want = 8 + kmh * 0.16
    for k = 0, diff.lookahead + 2 do
        local nn = nodes[(ni - 1 + k) % count + 1]
        aim = nn
        local dx, dy = nn[1] - x, nn[2] - y
        if dx * dx + dy * dy >= want * want then break end
    end
    local tAng = deg(atan2(-(aim[1] - x), aim[2] - y))
    local d = normAng(tAng - rz)

    -- obstaculo delante: rodear por un lado o frenar
    local od, side, ospeed = frontObstacle(race, E, x, y, fx, fy)
    if od then
        if od < 7 then tgt = math.min(tgt, (ospeed or 0) * 0.75) else d = d + side * 14 end
    end

    -- curva cerrada: bajar velocidad
    tgt = tgt * (1 - 0.55 * math.min(1, abs(d) / 70))

    local steer = raceClamp(d / 32, -1, 1)
    if kmh < tgt - 2 then
        aiCtl(E, steer, raceClamp((tgt - kmh) / 14, 0.35, 1), false, false)
    elseif kmh > tgt + 7 then
        aiCtl(E, steer, 0, true, false)
    else
        aiCtl(E, steer, 0, false, false)
    end
end
