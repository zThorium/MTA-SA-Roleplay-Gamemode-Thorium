--[[
    rp_wanted / c_combat.lua
    Tacticas de combate de la policia IA (config: WANTED_COMBAT). Lo usa
    client/c_police.lua para los policias a pie y los tiradores de las patrullas.

      - Punteria con error: segun la distancia, tu velocidad, las estrellas y si
        al policia le acaban de pegar. De cerca aciertan como antes; de lejos o
        corriendo, fallan mas.
      - Ritmo propio: cada policia dispara rafagas con sus pausas y recarga (antes
        todos los de una unidad disparaban y paraban a la vez).
      - Sin fuego amigo: no disparan si un companero o una patrulla esta en medio;
        se desplazan para buscar linea de tiro.
      - Anillo: los policias a pie se reparten alrededor del jugador y se mueven
        hacia su puesto mientras disparan (flanquean en vez de amontonarse).
      - Cobertura: si les apuntas, les pegas o tienen poca vida, corren a un punto
        cercano donde no los ves (detras de una pared o de un auto) y vuelven.
      - Rendicion: quieto y sin apuntar, el mas cercano se acerca a arrestarte y
        los demas te apuntan sin disparar.
      - Atascos: si no avanzan, saltan y se apartan para rodear el obstaculo.

    Globales: combatTickStart, combatAssignSlots, combatAimFire, combatFoot,
              combatDrivebyAim, combatRhythm, combatRun
]]

local P = setmetatable({}, { __mode = "k" })   -- [ped] = estado de combate
local hurtAt = setmetatable({}, { __mode = "k" })
local coverBudget = 1

local function S(ped)
    local s = P[ped]
    if not s then
        s = { ring = nil, slotA = nil }
        P[ped] = s
    end
    return s
end

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end
local function rnd(a, b) return a + math.random() * (b - a) end

local MOVE = { "forwards", "backwards", "left", "right", "sprint", "walk", "jump" }
local function stopMove(ped)
    for _, c in ipairs(MOVE) do setPedControlState(ped, c, false) end
end

-- Una vez por tick: limita las busquedas de cobertura (son varios rayos)
function combatTickStart()
    coverBudget = 1
end

-- Al policia le pego el jugador: apunta peor un momento y busca cobertura
addEventHandler("onClientPedDamage", root, function(attacker)
    if attacker == localPlayer and getElementData(source, "rp:cop") then hurtAt[source] = getTickCount() end
end)

----------------------------------------------------------------
-- Punteria con error y ritmo de disparo
----------------------------------------------------------------
local function speedKmh(el)
    local vx, vy, vz = getElementVelocity(el)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

local function wantedStars() return tonumber(getElementData(localPlayer, "rp:wanted")) or 0 end

-- Punto al que apunta el policia: el objetivo mas un desvio que se renueva cada AIM_REFRESH
local function aimPoint(ped, now, tx, ty, tz, dist)
    local C = WANTED_COMBAT
    local s = S(ped)
    if not s.err or now - s.errAt > C.AIM_REFRESH then
        local pspeed = speedKmh(getPedOccupiedVehicle(localPlayer) or localPlayer)
        local e = C.AIM_BASE + dist * C.AIM_PER_M + pspeed * C.AIM_PER_KMH
        if hurtAt[ped] and now - hurtAt[ped] < 1500 then e = e + C.AIM_HURT end
        e = e * math.max(0.5, 1 - math.max(0, wantedStars() - 2) * C.AIM_LEVEL)
        local a, r = math.random() * math.pi * 2, e * math.sqrt(math.random())
        s.err, s.errAt = { math.cos(a) * r, math.sin(a) * r, rnd(-0.5, 0.5) * e }, now
    end
    return tx + s.err[1], ty + s.err[2], tz + s.err[3]
end

-- true si toca disparar: rafaga, pausa y, cada BURSTS_PER_RELOAD rafagas, recarga
function combatRhythm(ped, now)
    local C = WANTED_COMBAT
    local s = S(ped)
    if not s.phaseEnd then
        s.firing, s.bursts = false, 0
        s.phaseEnd = now + rnd(0, C.PAUSE_MAX)   -- desfase inicial: nadie empieza a la vez
    end
    if now >= s.phaseEnd then
        if s.firing then
            s.firing = false
            s.bursts = s.bursts + 1
            if s.bursts >= C.BURSTS_PER_RELOAD then
                s.bursts = 0
                s.phaseEnd = now + C.RELOAD
            else
                s.phaseEnd = now + rnd(C.PAUSE_MIN, C.PAUSE_MAX)
            end
        else
            s.firing = true
            s.phaseEnd = now + rnd(C.BURST_MIN, C.BURST_MAX)
        end
    end
    return s.firing
end

-- Linea de tiro libre de companeros (se mira cada 250 ms)
local function clearShot(ped, now, x, y, z, px, py, pz)
    local s = S(ped)
    if s.shotAt and now - s.shotAt < 250 then return s.shotOk end
    s.shotAt = now
    local pveh = getPedOccupiedVehicle(localPlayer)
    local hit, _, _, _, el = processLineOfSight(x, y, z + 0.6, px, py, pz + 0.5,
        true, true, true, true, false, false, false, true, ped)
    local ok = true
    if hit and el and el ~= localPlayer and el ~= pveh then
        local t = getElementType(el)
        if (t == "ped" and getElementData(el, "rp:cop")) or (t == "vehicle" and getElementData(el, "rp:copCar")) then ok = false end
    end
    s.shotOk = ok
    return ok
end

-- Apunta (con error) y dispara a su ritmo si la linea de tiro esta libre.
-- holdFire: apunta sin disparar (te estas rindiendo). Devuelve si la linea esta libre.
function combatAimFire(ped, now, x, y, z, px, py, pz, dist, holdFire)
    setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
    local ax, ay, az = aimPoint(ped, now, px, py, pz + 0.4, dist)
    setPedAimTarget(ped, ax, ay, az)
    setPedControlState(ped, "aim_weapon", true)
    local ok = clearShot(ped, now, x, y, z, px, py, pz)
    setPedControlState(ped, "fire", ok and not holdFire and combatRhythm(ped, now))
    return ok
end

-- Tirador de una patrulla (drive-by): mismo error de punteria; dz baja el tiro a las llantas
function combatDrivebyAim(ped, now, px, py, pz, dz, dist)
    local ax, ay, az = aimPoint(ped, now, px, py, pz + dz, dist)
    setPedAimTarget(ped, ax, ay, az)
end

----------------------------------------------------------------
-- Moverse con deteccion de atascos
----------------------------------------------------------------
-- Corre (o camina) hacia (tx, ty); si en STUCK_MS no avanzo, salta y se aparta a un lado
function combatRun(ped, now, x, y, tx, ty, sprint)
    local C = WANTED_COMBAT
    local s = S(ped)
    local rot = heading(tx - x, ty - y)
    if s.unstickUntil and now < s.unstickUntil then
        rot = rot + s.unstickSide * 70
    end
    setElementRotation(ped, 0, 0, rot, "default", true)
    setPedControlState(ped, "aim_weapon", false)
    setPedControlState(ped, "fire", false)
    setPedControlState(ped, "backwards", false)
    setPedControlState(ped, "left", false)
    setPedControlState(ped, "right", false)
    setPedControlState(ped, "forwards", true)
    setPedControlState(ped, "sprint", sprint)
    setPedControlState(ped, "walk", not sprint)
    -- atasco: compara con la posicion de hace STUCK_MS
    if not s.mvAt or now - s.mvAt > C.STUCK_MS then
        local moved = s.mvX and getDistanceBetweenPoints2D(x, y, s.mvX, s.mvY) or 99
        s.mvX, s.mvY, s.mvAt = x, y, now
        if moved < 0.8 and getDistanceBetweenPoints2D(x, y, tx, ty) > 2 then
            s.unstickUntil, s.unstickSide = now + 900, math.random() < 0.5 and -1 or 1
            setPedControlState(ped, "jump", true)
            return
        end
    end
    setPedControlState(ped, "jump", false)
end

----------------------------------------------------------------
-- Anillo alrededor del jugador
----------------------------------------------------------------
-- list = { ped, ... } policias a pie en combate. Reparte angulos alrededor del
-- jugador conservando el orden en que ya estan (nadie cruza por delante) y
-- marca al mas cercano como el que arresta si te rindes.
function combatAssignSlots(list)
    local n = #list
    if n == 0 then return end
    local px, py = getElementPosition(localPlayer)
    local entries, nearest, nearestD = {}, nil, math.huge
    for _, ped in ipairs(list) do
        local x, y = getElementPosition(ped)
        local d = getDistanceBetweenPoints2D(x, y, px, py)
        entries[#entries + 1] = { ped = ped, a = math.atan2(y - py, x - px) }
        if d < nearestD then nearest, nearestD = ped, d end
    end
    table.sort(entries, function(a, b) return a.a < b.a end)
    local base = entries[1].a
    for i, e in ipairs(entries) do
        local s = S(e.ped)
        s.slotA = base + (i - 1) * math.pi * 2 / n
        s.ring = s.ring or rnd(WANTED_COMBAT.RING_MIN, WANTED_COMBAT.RING_MAX)
        s.arrester = e.ped == nearest
    end
end

local function slotPoint(ped, px, py)
    local s = S(ped)
    local a = s.slotA or 0
    local r = s.ring or WANTED_COMBAT.RING_MIN
    return px + math.cos(a) * r, py + math.sin(a) * r
end

----------------------------------------------------------------
-- Rendicion: quieto, a pie y sin apuntar
----------------------------------------------------------------
local stillSince
local function playerSurrenders(now)
    local still = not getPedOccupiedVehicle(localPlayer) and speedKmh(localPlayer) < 3
        and not getPedControlState(localPlayer, "aim_weapon") and not getPedControlState(localPlayer, "fire")
    if not still then stillSince = nil return false end
    stillSince = stillSince or now
    return now - stillSince >= WANTED_COMBAT.SURRENDER_MS
end

----------------------------------------------------------------
-- Cobertura
----------------------------------------------------------------
local function findCover(x, y, z, px, py, pz)
    local best, bestScore
    local away = math.atan2(y - py, x - px)
    for _, d in ipairs({ 3, 5, 7 }) do
        for k = 0, 7 do
            local a = away + (k - 3.5) * math.pi / 4
            local cx, cy = x + math.cos(a) * d, y + math.sin(a) * d
            local gz = getGroundPosition(cx, cy, z + 2)
            if gz and gz ~= 0 and math.abs(gz + 1 - z) < 1.5
                and isLineOfSightClear(x, y, z, cx, cy, gz + 1, true, true, false, true, false, true, false)
                and not isLineOfSightClear(px, py, pz + 0.6, cx, cy, gz + 1, true, true, false, true, false, true, false) then
                -- mejor cerca y sin acercarse al jugador
                local score = d - getDistanceBetweenPoints2D(cx, cy, px, py) * 0.3
                if not bestScore or score < bestScore then best, bestScore = { cx, cy }, score end
            end
        end
        if best then return best end
    end
end

local function wantsCover(ped, s, now)
    if now < (s.coverReadyAt or 0) then return false end
    if getPedTarget(localPlayer) == ped and getPedControlState(localPlayer, "aim_weapon") then return true end
    if hurtAt[ped] and now - hurtAt[ped] < 1000 then return true end
    return getElementHealth(ped) < WANTED_COMBAT.COVER_HEALTH and math.random() < 0.02
end

-- Devuelve true mientras el policia esta yendo a cubrirse o cubierto
local function coverTick(ped, s, now, x, y, z, px, py, pz)
    local C = WANTED_COMBAT
    local c = s.cover
    if not c then
        if not wantsCover(ped, s, now) or coverBudget <= 0 then return false end
        coverBudget = coverBudget - 1
        local p = findCover(x, y, z, px, py, pz)
        local hurt = getElementHealth(ped) < C.COVER_HEALTH
        if not p then
            -- sin cobertura: se aparta de lado un momento
            s.coverReadyAt = now + (hurt and C.COVER_COOLDOWN_HURT or C.COVER_COOLDOWN)
            s.dodgeUntil, s.dodgeSide = now + 700, math.random() < 0.5 and "left" or "right"
            return false
        end
        c = { x = p[1], y = p[2], phase = "go", endAt = now + C.COVER_GO_MAX }
        s.cover = c
    end
    if c.phase == "go" then
        if getDistanceBetweenPoints2D(x, y, c.x, c.y) < 1.2 then
            c.phase, c.endAt = "hide", now + C.COVER_HIDE
        elseif now > c.endAt then
            c.phase, c.endAt = "hide", now   -- no llego: termina ya
        else
            combatRun(ped, now, x, y, c.x, c.y, true)
            return true
        end
    end
    if now < c.endAt then
        -- agazapado detras de la cobertura, mirando hacia el jugador
        stopMove(ped)
        setPedControlState(ped, "fire", false)
        setPedControlState(ped, "aim_weapon", false)
        setElementRotation(ped, 0, 0, heading(px - x, py - y), "default", true)
        return true
    end
    s.cover = nil
    s.coverReadyAt = now + (getElementHealth(ped) < C.COVER_HEALTH and C.COVER_COOLDOWN_HURT or C.COVER_COOLDOWN)
    return false
end

----------------------------------------------------------------
-- Policia a pie armado contra el jugador a pie (desde 2 estrellas)
----------------------------------------------------------------
-- Devuelve true si se encargo del policia; false para que c_police.lua siga
-- (acercarse a arrestar, golpe cuerpo a cuerpo, esperar en el control).
function combatFoot(u, ped, now, x, y, z, px, py, pz, dist, los)
    local C = WANTED_COMBAT
    local s = S(ped)
    local post = u.kind == "roadblock" or u.kind == "spikes"
    local surrender = playerSurrenders(now)
    if surrender and s.arrester then return false end   -- este va a esposarte
    if not surrender and coverTick(ped, s, now, x, y, z, px, py, pz) then return true end

    if los and dist < C.RANGE and dist > 3.5 then
        local ok = combatAimFire(ped, now, x, y, z, px, py, pz, dist, surrender)
        -- se mueve mientras apunta: hacia su puesto del anillo, o de lado si un companero tapa el tiro
        local fwd, side = 0, 0
        if s.dodgeUntil and now < s.dodgeUntil then
            side = s.dodgeSide == "left" and -1 or 1
        elseif not ok then
            s.blockSide = s.blockSide or (math.random() < 0.5 and -1 or 1)
            side = s.blockSide
        elseif not post then
            s.blockSide = nil
            local sx, sy = slotPoint(ped, px, py)
            local rz = math.rad(heading(px - x, py - y))
            local fx, fy = -math.sin(rz), math.cos(rz)
            local rx, ry = math.cos(rz), math.sin(rz)
            local dx, dy = sx - x, sy - y
            local along, across = dx * fx + dy * fy, dx * rx + dy * ry
            if along > 1.5 then fwd = 1 elseif along < -1.5 then fwd = -1 end
            if across > 1.5 then side = 1 elseif across < -1.5 then side = -1 end
        end
        setPedControlState(ped, "sprint", false)
        setPedControlState(ped, "walk", false)
        setPedControlState(ped, "jump", false)
        setPedControlState(ped, "forwards", fwd > 0)
        setPedControlState(ped, "backwards", fwd < 0)
        setPedControlState(ped, "right", side > 0)
        setPedControlState(ped, "left", side < 0)
        return true
    end

    -- Sin linea de vision o lejos: va a su puesto del anillo (rodea en vez de ir en fila)
    if post or dist <= 3.5 then return false end
    local sx, sy = slotPoint(ped, px, py)
    if getDistanceBetweenPoints2D(x, y, sx, sy) < 1.5 then sx, sy = px, py end   -- en su puesto y sin verte: se acerca
    combatRun(ped, now, x, y, sx, sy, true)
    return true
end
