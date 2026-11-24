--[[
    rp_pool / client / c_pool.lua

    Cliente del pool:
      - Crea las bolas (objetos locales) de las mesas cercanas y reproduce los tiros que
        calcula el servidor (replay a 60 fps con rodadura y sonidos).
      - Apuntado como en GTA SA: camara detras de la blanca, raton para girar, mantener
        clic izquierdo para cargar fuerza y soltar para golpear. C cambia a vista cenital.
      - Bola en mano: clic en la mesa para colocar la blanca.
      - HUD: jugadores, bolas restantes, bote de la apuesta, turno y barra de potencia.
      - E junto a una mesa abre el menu de apuestas (CEF); /poolranking abre el ranking.

    Controles: raton = apuntar | clic der. (mantener) = punteria fina | clic izq. = fuerza
               C = vista | Retroceso = abandonar (confirmar con Y)
]]

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.8, math.min(1.3, screenH / 900))
local R = POOL.BALL_R

addEvent("rp:pool:tables", true)
addEvent("rp:pool:state", true)
addEvent("rp:pool:tableRemoved", true)
addEvent("rp:pool:near", true)
addEvent("rp:pool:show", true)
addEvent("rp:pool:waiting", true)
addEvent("rp:pool:matchStart", true)
addEvent("rp:pool:turn", true)
addEvent("rp:pool:replay", true)
addEvent("rp:pool:matchEnd", true)
addEvent("rp:pool:board", true)
addEvent("rp:pool:openBoard", true)
addEvent("rp:pool:aimSync", true)
addEvent("rp:pool:placeDenied", true)
addEvent("rp:pool:ui:create", false)
addEvent("rp:pool:ui:join", false)
addEvent("rp:pool:ui:leave", false)
addEvent("rp:pool:ui:board", false)
addEvent("rp:pool:ui:close", false)

local tablesData = {}    -- [id] = info + estado + balls[0..15] = {u,v,p}
local visual = {}        -- [id] = { balls = {[0..15] = obj}, ax, ay, az = orientacion por bola }
local near = false       -- id de la mesa cercana
local waitingInfo = nil  -- { id, bet } si espero rival
local match = nil        -- { id, idx } mi partida
local replay = nil
local pendingBalls = {}  -- [id] = balls a aplicar al terminar el replay
local remoteAim = {}     -- [id] = { theta, power, tick }
local shotLock = false
local resultBanner = nil
local forfeitAsk = 0
local debugDraw = false

local aim = { theta = 0, power = 0, charging = false, chargeStart = 0, fine = false, cam = 1 }
local cueObj = nil
local stroke = nil       -- animacion del golpe: { t0, from, tid, theta }
local playerHidden = false
local placePos = nil     -- { u, v, ok }
local lastAimSend = 0
local lastMode = nil
local shotSentAt = 0

local sin, cos, atan2, sqrt, abs, floor, rad, deg = math.sin, math.cos, math.atan2, math.sqrt, math.abs, math.floor, math.rad, math.deg

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function ballColor(b)
    local cols = {
        [1] = { 240, 200, 40 }, [2] = { 30, 80, 200 }, [3] = { 210, 40, 40 }, [4] = { 110, 50, 150 },
        [5] = { 235, 120, 30 }, [6] = { 30, 130, 60 }, [7] = { 130, 30, 40 }, [8] = { 25, 25, 25 },
    }
    local n = b > 8 and b - 8 or b
    return cols[n] or { 255, 255, 255 }
end

local function newBallsTable()
    local balls = {}
    for b = 0, 15 do balls[b] = { u = 0, v = 0, p = false } end
    return balls
end

local function tableCenter(T)
    local x, y = poolToWorld(T, 0, 0)
    return x, y, T.z + POOL.FELT_Z
end

local function ballWorld(T, u, v)
    local x, y = poolToWorld(T, u, v)
    return x, y, poolBallZ(T)
end

----------------------------------------------------------------
-- Orientacion de las bolas (rodadura visible)
----------------------------------------------------------------
local function randomOrient()
    local function rv()
        local x, y, z = math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
        local l = sqrt(x * x + y * y + z * z) + 1e-9
        return x / l, y / l, z / l
    end
    -- Gram-Schmidt sobre vectores aleatorios
    local ax, ay, az = rv()
    local bx, by, bz = rv()
    local d = ax * bx + ay * by + az * bz
    bx, by, bz = bx - ax * d, by - ay * d, bz - az * d
    local l = sqrt(bx * bx + by * by + bz * bz) + 1e-9
    bx, by, bz = bx / l, by / l, bz / l
    local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    return { ax, ay, az }, { bx, by, bz }, { cx, cy, cz }
end

local function rotateVec(v, kx, ky, kz, c, s)
    local x, y, z = v[1], v[2], v[3]
    local kv = kx * x + ky * y + kz * z
    local cx, cy, cz = ky * z - kz * y, kz * x - kx * z, kx * y - ky * x
    v[1] = x * c + cx * s + kx * kv * (1 - c)
    v[2] = y * c + cy * s + ky * kv * (1 - c)
    v[3] = z * c + cz * s + kz * kv * (1 - c)
end

-- Gira la bola como si rodara: dx, dy = desplazamiento en el mundo
local function rollBall(vis, b, dx, dy)
    local dist = sqrt(dx * dx + dy * dy)
    if dist < 1e-6 then return end
    -- Aproximacion sencilla: giro acumulado sobre los ejes X e Y del mundo
    vis.rx[b] = (vis.rx[b] + deg(dy / R)) % 360
    vis.ry[b] = (vis.ry[b] - deg(dx / R)) % 360
end

local function setBallObject(vis, b, x, y, z)
    local obj = vis.balls[b]
    if not isElement(obj) then return end
    setElementPosition(obj, x, y, z)
    setElementRotation(obj, vis.rx[b], vis.ry[b], vis.rz[b])
end

----------------------------------------------------------------
-- Objetos de bolas por mesa (se crean solo cerca)
----------------------------------------------------------------
local function destroyVisual(id)
    local vis = visual[id]
    if not vis then return end
    for b = 0, 15 do
        if isElement(vis.balls[b]) then destroyElement(vis.balls[b]) end
    end
    visual[id] = nil
end

local function syncVisual(T)
    local vis = visual[T.id]
    if not vis then return end
    for b = 0, 15 do
        local ball = T.balls[b]
        local obj = vis.balls[b]
        if isElement(obj) then
            if ball.p then
                setElementAlpha(obj, 0)
            else
                setElementAlpha(obj, 255)
                local x, y, z = ballWorld(T, ball.u, ball.v)
                setBallObject(vis, b, x, y, z)
            end
        end
    end
end

local function createVisual(T)
    if visual[T.id] then return end
    local vis = { balls = {}, rx = {}, ry = {}, rz = {} }
    for b = 0, 15 do
        local obj = createObject(POOL_BALL_MODELS[b], 0, 0, 0)
        setElementCollisionsEnabled(obj, false)
        setElementInterior(obj, T.interior)
        setElementDimension(obj, T.dimension)
        vis.balls[b] = obj
        vis.rx[b], vis.ry[b], vis.rz[b] = math.random(0, 359), math.random(0, 359), math.random(0, 359)
    end
    visual[T.id] = vis
    syncVisual(T)
end

local function inRange(T)
    if getElementInterior(localPlayer) ~= T.interior or getElementDimension(localPlayer) ~= T.dimension then
        return false
    end
    local px, py, pz = getElementPosition(localPlayer)
    local dx, dy, dz = px - T.x, py - T.y, pz - T.z
    return dx * dx + dy * dy + dz * dz < POOL.STREAM_RANGE ^ 2
end

setTimer(function()
    for id, T in pairs(tablesData) do
        if inRange(T) then
            if not visual[id] then createVisual(T) end
        elseif visual[id] and not (match and match.id == id) then
            destroyVisual(id)
        end
    end
end, 700, 0)

----------------------------------------------------------------
-- Estado desde el servidor
----------------------------------------------------------------
local function decodeBalls(flat)
    local balls = {}
    for b = 0, 15 do
        balls[b] = { u = flat[b * 3 + 1] / 1000, v = flat[b * 3 + 2] / 1000, p = flat[b * 3 + 3] == 1 }
    end
    return balls
end

local function applyState(s, info)
    local T = tablesData[s.id]
    if not T then
        T = { id = s.id, balls = newBallsTable() }
        tablesData[s.id] = T
    end
    if info then
        T.x, T.y, T.z, T.rz = info.x, info.y, info.z, info.rz
        T.interior, T.dimension, T.native = info.interior, info.dimension, info.native
    end
    T.status, T.bet, T.names = s.status, s.bet, s.names
    T.turn, T.groups, T.bih, T.busy = s.turn, s.groups, s.bih, s.busy
    T.left, T.stateAt = s.left, getTickCount()
    local balls = decodeBalls(s.balls)
    if replay and replay.tid == s.id then
        pendingBalls[s.id] = balls      -- se aplica al terminar la animacion
    else
        T.balls = balls
        syncVisual(T)
    end
end

addEventHandler("rp:pool:tables", resourceRoot, function(list, states)
    local byId = {}
    for _, s in ipairs(states or {}) do byId[s.id] = s end
    for _, info in ipairs(list or {}) do
        if byId[info.id] then applyState(byId[info.id], info) end
    end
end)

-- Si llega un estado de una mesa que este cliente no conoce (la lista inicial se perdio o la
-- mesa es nueva), se pide de nuevo al servidor. Sin esto, ese cliente nunca vera las apuestas.
local lastSyncRequest = 0
local function requestSync()
    local now = getTickCount()
    if now - lastSyncRequest < 2000 then return end
    lastSyncRequest = now
    triggerServerEvent("rp:pool:requestSync", resourceRoot)
end

addEventHandler("rp:pool:state", resourceRoot, function(s)
    if tablesData[s.id] and tablesData[s.id].x then applyState(s) else requestSync() end
end)

addEventHandler("rp:pool:tableRemoved", resourceRoot, function(id)
    destroyVisual(id)
    tablesData[id] = nil
    if near == id then near = false end
end)

addEventHandler("rp:pool:near", resourceRoot, function(id)
    near = id
    if id and not (tablesData[id] and tablesData[id].x) then requestSync() end
end)

-- Red de seguridad: resincroniza cada 15 s por si se perdio algun mensaje
setTimer(function() requestSync() end, 15000, 0)

----------------------------------------------------------------
-- Sonidos
----------------------------------------------------------------
local function playAt(T, file, x, y, z, vol)
    local snd = playSound3D("sounds/" .. file, x, y, z, false)
    if snd then
        setSoundVolume(snd, clamp(vol or 0.8, 0.05, 1))
        setSoundMaxDistance(snd, 18)
        setElementInterior(snd, T.interior)
        setElementDimension(snd, T.dimension)
    end
end

----------------------------------------------------------------
-- Taco (cue)
----------------------------------------------------------------
local function ensureCue(T)
    if isElement(cueObj) then
        setElementInterior(cueObj, T.interior)
        setElementDimension(cueObj, T.dimension)
        return
    end
    cueObj = createObject(POOL.CUE_MODEL, 0, 0, 0)
    setElementCollisionsEnabled(cueObj, false)
    setElementInterior(cueObj, T.interior)
    setElementDimension(cueObj, T.dimension)
end

local function hideCue()
    if isElement(cueObj) then destroyElement(cueObj) end
    cueObj = nil
end

-- theta en marco de mesa; pull = distancia de retroceso del taco (m)
local function placeCue(T, theta, pull)
    ensureCue(T)
    local cue = T.balls[0]
    local cx, cy, cz = ballWorld(T, cue.u, cue.v)
    local th = theta + rad(T.rz)
    local dx, dy = cos(th), sin(th)
    local gap = R + 0.012 + pull
    local rz = deg(atan2(dx, -dy))
    setElementPosition(cueObj, cx - dx * gap, cy - dy * gap, cz - 0.008)
    setElementRotation(cueObj, 0, 0, rz)
end

----------------------------------------------------------------
-- Replay de un tiro
----------------------------------------------------------------
addEventHandler("rp:pool:replay", resourceRoot, function(p)
    local T = tablesData[p.tableId]
    if not T then return end
    if not visual[T.id] and inRange(T) then createVisual(T) end
    local vis = visual[T.id]
    if not vis then return end

    local tracks = {}
    for _, t in ipairs(p.tracks) do
        local b = t[1]
        local fs, us, vs = {}, {}, {}
        for i = 2, #t, 3 do
            fs[#fs + 1] = t[i]
            us[#us + 1] = t[i + 1] / 1000
            vs[#vs + 1] = t[i + 2] / 1000
        end
        tracks[b] = { f = fs, u = us, v = vs, i = 1, lastU = nil, lastV = nil }
    end
    replay = {
        tid = T.id, tracks = tracks, events = p.events, frames = p.frames,
        t0 = getTickCount() + 180, nextEvent = 1, pocketed = {},
        angle = p.angle, power = p.power, shooter = p.shooter,
    }
    table.sort(replay.events, function(a, b) return a[1] < b[1] end)
    stroke = { t0 = getTickCount(), tid = T.id, theta = p.angle, power = p.power }
    shotLock = true
    resultBanner = nil
end)

local function finishReplay()
    local R_ = replay
    if not R_ then return end
    local T = tablesData[R_.tid]
    replay = nil
    stroke = nil
    if T then
        if pendingBalls[R_.tid] then
            T.balls = pendingBalls[R_.tid]
            pendingBalls[R_.tid] = nil
        end
        syncVisual(T)
    end
    if not (match and match.id == R_.tid) then hideCue() end
end

local function updateReplay(now)
    local R_ = replay
    if not R_ then return end
    local T = tablesData[R_.tid]
    local vis = visual[R_.tid]
    if not T or not vis then replay = nil; stroke = nil; return end
    local t = (now - R_.t0) / 1000 * POOL.FRAME_RATE
    if t < 0 then return end
    local z = poolBallZ(T)

    for b, tr in pairs(R_.tracks) do
        if not R_.pocketed[b] then
            local fs = tr.f
            local n = #fs
            local u, v
            if t <= fs[1] then
                u, v = T.balls[b].u, T.balls[b].v
            elseif t >= fs[n] then
                u, v = tr.u[n], tr.v[n]
            else
                local i = tr.i
                while i < n - 1 and fs[i + 1] <= t do i = i + 1 end
                tr.i = i
                local f0, f1 = fs[i], fs[i + 1]
                local k = (t - f0) / (f1 - f0)
                u = tr.u[i] + (tr.u[i + 1] - tr.u[i]) * k
                v = tr.v[i] + (tr.v[i + 1] - tr.v[i]) * k
            end
            local x, y = poolToWorld(T, u, v)
            if tr.lastU then
                local px, py = poolToWorld(T, tr.lastU, tr.lastV)
                rollBall(vis, b, x - px, y - py)
            end
            tr.lastU, tr.lastV = u, v
            setBallObject(vis, b, x, y, z)
        end
    end

    -- Sonidos y embocadas segun el fotograma
    local ev = R_.events
    while R_.nextEvent <= #ev and ev[R_.nextEvent][1] <= t do
        local e = ev[R_.nextEvent]
        R_.nextEvent = R_.nextEvent + 1
        local x, y = poolToWorld(T, e[3] / 1000, e[4] / 1000)
        local kind, val = e[2], e[5]
        if kind == 1 then
            playAt(T, "ball.wav", x, y, z, 0.25 + val / 400)
        elseif kind == 2 then
            playAt(T, "cushion.wav", x, y, z, 0.2 + val / 400)
        else
            R_.pocketed[val] = true
            local obj = vis.balls[val]
            if isElement(obj) then setElementAlpha(obj, 0) end
            playAt(T, "pocket.wav", x, y, z, 0.9)
        end
    end

    if t >= R_.frames + 6 then finishReplay() end
end

----------------------------------------------------------------
-- Ayudas visuales (guia de tiro y depuracion)
----------------------------------------------------------------
-- Primer impacto de un rayo desde la blanca: devuelve distancia, id de bola o nil (banda), normal
local function traceAim(T, theta)
    local cue = T.balls[0]
    local dx, dy = cos(theta), sin(theta)
    local best, hitBall = 99, nil
    for b = 1, 15 do
        local ball = T.balls[b]
        if not ball.p then
            local fx, fy = ball.u - cue.u, ball.v - cue.v
            local proj = fx * dx + fy * dy
            if proj > 0 then
                local d2 = fx * fx + fy * fy - proj * proj
                local rr = (2 * R) ^ 2
                if d2 < rr then
                    local t = proj - sqrt(rr - d2)
                    if t < best then best, hitBall = t, b end
                end
            end
        end
    end
    local bx, by = POOL.HALF_L - R, POOL.HALF_W - R
    local tw = 99
    if dx > 1e-6 then tw = math.min(tw, (bx - cue.u) / dx) elseif dx < -1e-6 then tw = math.min(tw, (-bx - cue.u) / dx) end
    if dy > 1e-6 then tw = math.min(tw, (by - cue.v) / dy) elseif dy < -1e-6 then tw = math.min(tw, (-by - cue.v) / dy) end
    if tw < best then best, hitBall = tw, nil end
    return best, hitBall
end

local function drawRing(x, y, z, radius, color)
    local steps = 14
    local px, py = x + radius, y
    for i = 1, steps do
        local a = i / steps * math.pi * 2
        local nx, ny = x + cos(a) * radius, y + sin(a) * radius
        dxDrawLine3D(px, py, z, nx, ny, z, color, 2)
        px, py = nx, ny
    end
end

local function drawGuide(T)
    local cue = T.balls[0]
    if cue.p then return end
    local theta = aim.theta
    local dist, hitBall = traceAim(T, theta)
    local dx, dy = cos(theta), sin(theta)
    local gu, gv = cue.u + dx * dist, cue.v + dy * dist
    local x0, y0, z = ballWorld(T, cue.u, cue.v)
    local x1, y1 = poolToWorld(T, gu, gv)
    z = z + 0.002
    dxDrawLine3D(x0, y0, z, x1, y1, z, tocolor(255, 255, 255, 170), 2)
    drawRing(x1, y1, z, R, tocolor(255, 255, 255, 190))
    if hitBall then
        local ball = T.balls[hitBall]
        local nx, ny = ball.u - gu, ball.v - gv
        local l = sqrt(nx * nx + ny * ny)
        if l > 1e-6 then
            nx, ny = nx / l, ny / l
            local ox, oy = poolToWorld(T, ball.u + nx * 0.22, ball.v + ny * 0.22)
            local bx, by = poolToWorld(T, ball.u, ball.v)
            dxDrawLine3D(bx, by, z, ox, oy, z, tocolor(245, 165, 36, 200), 2)
            -- desvio de la blanca (perpendicular a la normal)
            local tx, ty = -ny, nx
            if tx * dx + ty * dy < 0 then tx, ty = -tx, -ty end
            local cx2, cy2 = poolToWorld(T, gu + tx * 0.14, gv + ty * 0.14)
            dxDrawLine3D(x1, y1, z, cx2, cy2, z, tocolor(255, 255, 255, 110), 2)
        end
    else
        local bdx, bdy = dx, dy
        local bx, by = POOL.HALF_L - R, POOL.HALF_W - R
        if abs(gu) >= bx - 0.001 then bdx = -bdx end
        if abs(gv) >= by - 0.001 then bdy = -bdy end
        local rx, ry = poolToWorld(T, gu + bdx * 0.2, gv + bdy * 0.2)
        dxDrawLine3D(x1, y1, z, rx, ry, z, tocolor(255, 255, 255, 90), 2)
    end
end

local function drawDebug(T)
    local z = T.z + POOL.FELT_Z + 0.01
    local corners = { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } }
    for i = 1, 4 do
        local a, b = corners[i], corners[i % 4 + 1]
        local x1, y1 = poolToWorld(T, a[1] * POOL.HALF_L, a[2] * POOL.HALF_W)
        local x2, y2 = poolToWorld(T, b[1] * POOL.HALF_L, b[2] * POOL.HALF_W)
        dxDrawLine3D(x1, y1, z, x2, y2, z, tocolor(255, 60, 60, 255), 2)
    end
    for _, c in ipairs(corners) do
        local x, y = poolToWorld(T, c[1] * POOL.HALF_L, c[2] * POOL.HALF_W)
        drawRing(x, y, z, POOL.MOUTH_CORNER, tocolor(60, 255, 60, 255))
    end
    for _, s in ipairs({ 1, -1 }) do
        local x, y = poolToWorld(T, 0, s * POOL.HALF_W)
        drawRing(x, y, z, POOL.MOUTH_SIDE, tocolor(60, 255, 60, 255))
    end
end

-- Diagnostico: vuelca en el chat el estado de las mesas cercanas
addCommandHandler("poolinfo", function()
    local px, py, pz = getElementPosition(localPlayer)
    outputChatBox(("[pool] yo: %.1f %.1f %.1f int %d dim %d | match=%s mode=%s shotLock=%s replay=%s"):format(
        px, py, pz, getElementInterior(localPlayer), getElementDimension(localPlayer),
        tostring(match and match.id), tostring(match and currentMode(tablesData[match.id])), tostring(shotLock), tostring(replay ~= nil)), 245, 165, 36)
    for id, T in pairs(tablesData) do
        local vis = visual[id]
        local cue = T.balls[0]
        local pocketed = 0
        for b = 0, 15 do if T.balls[b].p then pocketed = pocketed + 1 end end
        outputChatBox(("[pool] mesa %d pos %.1f %.1f %.1f rz %s int %s dim %s estado %s | visual=%s embocadas=%d blanca u=%.3f v=%.3f p=%s"):format(
            id, T.x or 0, T.y or 0, T.z or 0, tostring(T.rz), tostring(T.interior), tostring(T.dimension), tostring(T.status),
            tostring(vis ~= nil), pocketed, cue.u, cue.v, tostring(cue.p)), 255, 255, 255)
        if vis and isElement(vis.balls[0]) then
            local o = vis.balls[0]
            local ox, oy, oz = getElementPosition(o)
            outputChatBox(("[pool]   bola blanca objeto: %.2f %.2f %.2f modelo %d alpha %d int %d dim %d streamedIn=%s"):format(
                ox, oy, oz, getElementModel(o), getElementAlpha(o), getElementInterior(o), getElementDimension(o), tostring(isElementStreamedIn(o))), 255, 255, 255)
        end
    end
end)

addCommandHandler("pooldebug", function()
    debugDraw = not debugDraw
    outputChatBox("Pool debug: " .. (debugDraw and "activado" or "desactivado") .. " (rojo = bandas, verde = bocas de troneras)", 245, 165, 36)
end)

----------------------------------------------------------------
-- Partida local: camara, apuntado, colocacion
----------------------------------------------------------------
local function myTurnNow(T)
    return match and T and T.status == "playing" and T.turn == match.idx
end

local function currentMode(T)
    if not match or not T then return nil end
    if shotLock then return replay and "replay" or "hold" end
    if myTurnNow(T) and not T.busy then
        return T.bih and "place" or "aim"
    end
    return "watch"
end

local savedSlot, lastBoneScan, boneHidden = nil, 0, {}
local opponent = nil   -- jugador rival de mi partida (solo para ocultarlo en mi pantalla)

-- Oculta (solo en mi pantalla) a los dos jugadores de la partida y todo lo que llevan
-- pegado con bone_attach (cabeza custom, ropa, mochila). Se reaplica en cada llamada
-- porque otros recursos pueden devolver el alpha.
local function setHidden(hidden)
    if not hidden and not playerHidden then return end
    local wasHidden = playerHidden
    playerHidden = hidden
    -- rp_heads oculta la cabeza custom propia cuando ve esta marca (local, no se sincroniza)
    setElementData(localPlayer, "rp:hideBody", hidden and true or nil, false)
    local a = hidden and 0 or 255
    local bodies = { localPlayer }
    if isElement(opponent) then bodies[2] = opponent end
    for _, p in ipairs(bodies) do
        setElementAlpha(p, a)
        for _, el in ipairs(getAttachedElements(p)) do
            if getElementType(el) == "object" then setElementAlpha(el, a) end
        end
    end

    if hidden then
        -- El arma en mano no obedece al alpha: se guarda mientras dura la partida
        if not wasHidden then savedSlot = getPedWeaponSlot(localPlayer) end
        if getPedWeaponSlot(localPlayer) ~= 0 then setPedWeaponSlot(localPlayer, 0) end
        local now = getTickCount()
        if not wasHidden or now - lastBoneScan > 500 then
            lastBoneScan = now
            for _, obj in ipairs(getElementsByType("object", root, true)) do
                if not boneHidden[obj] then
                    local ok, owner = pcall(function() return (exports.bone_attach:getElementBoneAttachmentDetails(obj)) end)
                    if ok and owner and (owner == localPlayer or owner == opponent) then
                        boneHidden[obj] = true
                    end
                end
            end
        end
        for obj in pairs(boneHidden) do
            if isElement(obj) then setElementAlpha(obj, 0) else boneHidden[obj] = nil end
        end
    else
        for obj in pairs(boneHidden) do
            if isElement(obj) then setElementAlpha(obj, 255) end
            boneHidden[obj] = nil
        end
        if isElement(opponent) then setElementAlpha(opponent, 255) end
        if savedSlot then setPedWeaponSlot(localPlayer, savedSlot) end
        savedSlot = nil
    end
end

local function topCamera(T, height)
    local cx, cy, cz = tableCenter(T)
    local a = rad(T.rz)
    -- "arriba" en pantalla = eje corto de la mesa, asi el lado largo queda horizontal
    local fx, fy = -sin(a), cos(a)
    setCameraMatrix(cx - fx * 0.06, cy - fy * 0.06, cz + (height or 2.35), cx, cy, cz, 0, 68)
end

local function behindCamera(T)
    local cue = T.balls[0]
    local cx, cy, cz = ballWorld(T, cue.u, cue.v)
    local th = aim.theta + rad(T.rz)
    local dx, dy = cos(th), sin(th)
    setCameraMatrix(cx - dx * 1.35, cy - dy * 1.35, cz + 0.72, cx + dx * 0.6, cy + dy * 0.6, cz - 0.03, 0, 70)
end

local function placeShooter(T)
    local cue = T.balls[0]
    local cx, cy = ballWorld(T, cue.u, cue.v)
    local th = aim.theta + rad(T.rz)
    local dx, dy = cos(th), sin(th)
    setElementPosition(localPlayer, cx - dx * 1.0, cy - dy * 1.0, T.z + 1.0)
    setElementRotation(localPlayer, 0, 0, deg(atan2(-dx, dy)))
end

-- Entradas por tecla (raton, camara, abandono)
local function sendShot()
    if aim.power < 0.02 then
        aim.charging = false
        aim.power = 0
        return
    end
    aim.charging = false
    aim.keep = true
    shotLock = true
    shotSentAt = getTickCount()
    triggerServerEvent("rp:pool:shoot", resourceRoot, aim.theta, aim.power)
end

addEventHandler("onClientKey", root, function(key, press)
    if not match then return end
    if isChatBoxInputActive() or isConsoleActive() or isMTAWindowActive() then return end
    local T = tablesData[match.id]
    if not T then return end
    local mode = currentMode(T)

    if key == "mouse1" then
        if mode == "aim" then
            if press then
                aim.charging, aim.chargeStart, aim.power = true, getTickCount(), 0
            elseif aim.charging then
                sendShot()
            end
        elseif mode == "place" and press and placePos and placePos.ok then
            triggerServerEvent("rp:pool:place", resourceRoot, placePos.u, placePos.v)
        end
        cancelEvent()
    elseif key == "mouse2" then
        aim.fine = press and true or false
    elseif key == "c" and press then
        aim.cam = (aim.cam == 1) and 2 or 1
    elseif key == "backspace" and press then
        if not isChatBoxInputActive() and not isConsoleActive() then forfeitAsk = getTickCount() end
    elseif key == "y" and press and forfeitAsk > 0 and getTickCount() - forfeitAsk < 6000 then
        forfeitAsk = 0
        triggerServerEvent("rp:pool:forfeit", resourceRoot)
    elseif press and forfeitAsk > 0 and key ~= "backspace" and key ~= "y" then
        forfeitAsk = 0
    end
end)

addEventHandler("onClientCursorMove", root, function(_, _, aX)
    if not match or isCursorShowing() or isMTAWindowActive() then return end
    local T = tablesData[match.id]
    if not T or currentMode(T) ~= "aim" then return end
    local dx = aX - screenW / 2
    if dx == 0 then return end
    local sens = (aim.fine and 0.00035 or 0.0016)
    aim.theta = aim.theta - dx * sens
end)

-- Colocacion con el cursor: interseccion del rayo con el plano del fieltro
local function updatePlacement(T)
    local cx, cy, cz = getCameraMatrix()
    if not isCursorShowing() then return end
    local rx, ry = getCursorPosition()
    if not rx then return end
    local wx, wy, wz = getWorldFromScreenPosition(rx * screenW, ry * screenH, 3)
    local planeZ = poolBallZ(T)
    local dz = wz - cz
    if abs(dz) < 1e-6 then return end
    local k = (planeZ - cz) / dz
    local px, py = cx + (wx - cx) * k, cy + (wy - cy) * k
    local u, v = poolFromWorld(T, px, py)
    local bx, by = POOL.HALF_L - R - 0.012, POOL.HALF_W - R - 0.012
    u, v = clamp(u, -bx, bx), clamp(v, -by, by)
    local ok = true
    for b = 1, 15 do
        local ball = T.balls[b]
        if not ball.p then
            local ddx, ddy = ball.u - u, ball.v - v
            if ddx * ddx + ddy * ddy < (2 * R + 0.003) ^ 2 then ok = false end
        end
    end
    local au, av = abs(u), abs(v)
    if au > bx - POOL.MOUTH_CORNER - 0.02 and av > by - POOL.MOUTH_CORNER - 0.02 then ok = false end
    if av > by - 0.02 and au < POOL.MOUTH_SIDE + 0.03 then ok = false end
    placePos = { u = u, v = v, ok = ok }
end

local function leaveMode(prev)
    -- (el cuerpo se mantiene oculto durante toda la partida; ver setHidden)
    if prev == "place" then
        showCursor(false)
        placePos = nil
    end
end

local function enterMode(mode, T)
    if mode == "aim" or mode == "hold" then
        setHidden(true)
        setElementFrozen(localPlayer, true)
        if mode == "aim" then
            aim.power, aim.charging = 0, false
            if T.balls[0].p then return end
            -- Al seguir tirando se conserva el angulo; si no, se apunta al grupo de bolas
            if not aim.keep then
                local cue = T.balls[0]
                local sx, sy, n = 0, 0, 0
                for b = 1, 15 do
                    local ball = T.balls[b]
                    if not ball.p then sx, sy, n = sx + ball.u, sy + ball.v, n + 1 end
                end
                if n > 0 then aim.theta = atan2(sy / n - cue.v, sx / n - cue.u) end
            end
            aim.keep = false
            setPedAnimation(localPlayer, "POOL", "POOL_Idle_Stance", -1, true, false, false, true)
        end
    elseif mode == "place" then
        showCursor(true)
        placePos = nil
        aim.keep = false
    elseif mode == "watch" then
        aim.keep = false
    end
end

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    updateReplay(now)

    -- Seguro: si el servidor rechazo el tiro y no llega replay, se libera el bloqueo
    if shotLock and not replay and now - shotSentAt > 4000 and shotSentAt > 0 then
        shotLock = false
        shotSentAt = 0
    end

    -- Taco de los demas jugadores (apuntado reenviado por el servidor)
    for tid, ra in pairs(remoteAim) do
        local T = tablesData[tid]
        if not T or now - ra.tick > 1500 or T.status ~= "playing" then
            remoteAim[tid] = nil
            if not replay then hideCue() end
        elseif not replay and visual[tid] then
            local selfAiming = match and match.id == tid and (currentMode(T) == "aim" or currentMode(T) == "hold")
            if not selfAiming then placeCue(T, ra.theta, 0.04 + ra.power * 0.3) end
        end
    end

    -- Animacion del golpe (taco hacia la bola) para todos los que ven el tiro
    if stroke then
        local T = tablesData[stroke.tid]
        if T and visual[stroke.tid] and now - stroke.t0 <= 700 then
            local k = clamp((now - stroke.t0) / 180, 0, 1)
            local pull = (0.04 + stroke.power * 0.34) * (1 - k * k)
            placeCue(T, stroke.theta, pull)
        else
            stroke = nil
            hideCue()
        end
    end

    if not match then return end
    local T = tablesData[match.id]
    if not T then return end
    local mode = currentMode(T)
    setHidden(true)
    if mode ~= lastMode then
        leaveMode(lastMode)
        enterMode(mode, T)
        lastMode = mode
    end

    if mode == "aim" then
        -- teclado: flechas giran (Shift = fino)
        local fine = getKeyState("lshift") or aim.fine
        local step = (fine and 0.25 or 1.1) * (1 / 60)
        if getKeyState("arrow_l") then aim.theta = aim.theta + step end
        if getKeyState("arrow_r") then aim.theta = aim.theta - step end

        if aim.charging then
            aim.power = clamp((now - aim.chargeStart) / 1500, 0, 1)
        end
        placeShooter(T)
        if aim.cam == 1 then behindCamera(T) else topCamera(T, 2.0) end
        setHidden(true)
        placeCue(T, aim.theta, 0.04 + aim.power * 0.34)

        if now - lastAimSend > 120 then
            lastAimSend = now
            triggerServerEvent("rp:pool:aim", resourceRoot, aim.theta, aim.power)
        end
    elseif mode == "hold" then
        if aim.cam == 1 then behindCamera(T) else topCamera(T, 2.0) end
    elseif mode == "place" then
        topCamera(T, 2.35)
        updatePlacement(T)
        local vis = visual[T.id]
        if vis and placePos then
            local x, y, z = ballWorld(T, placePos.u, placePos.v)
            setBallObject(vis, 0, x, y, z)
            setElementAlpha(vis.balls[0], placePos.ok and 255 or 110)
        end
    elseif mode == "replay" then
        if stroke and now - stroke.t0 < 260 and aim.cam == 1 and replay and replay.shooter == match.idx then
            behindCamera(T)
        else
            topCamera(T, 2.1)
        end
    else
        topCamera(T, 2.2)
    end
end)

----------------------------------------------------------------
-- Inicio y fin de partida
----------------------------------------------------------------
local function cleanupMatch()
    setHidden(false)
    setElementFrozen(localPlayer, false)
    toggleAllControls(true)
    setPedAnimation(localPlayer)
    showCursor(false)
    setCameraTarget(localPlayer)
    hideCue()
    opponent = nil
    match, replay, stroke, shotLock, placePos, lastMode = nil, nil, nil, false, nil, nil
    aim.charging, aim.power = false, 0
end

addEventHandler("rp:pool:waiting", resourceRoot, function(id, bet)
    waitingInfo = { id = id, bet = bet }
end)

addEventHandler("rp:pool:matchStart", resourceRoot, function(id, idx, rival)
    opponent = isElement(rival) and rival or nil
    waitingInfo = nil
    match = { id = id, idx = idx }
    resultBanner = nil
    shotLock = false
    lastMode = nil
    pendingBalls[id] = nil
    local T = tablesData[id]
    if T and not visual[id] then createVisual(T) end
    toggleAllControls(false, true, false)
    setElementFrozen(localPlayer, true)
    triggerEvent("rp:pool:ui:close", root)
end)

addEventHandler("rp:pool:turn", resourceRoot, function(id, turnIdx, bih)
    if not match or match.id ~= id then return end
    shotLock = false
    shotSentAt = 0
    if not replay then stroke = nil end
end)

addEventHandler("rp:pool:matchEnd", resourceRoot, function(id, winnerIdx, bet, why)
    local wasMatch = match ~= nil
    local idx = match and match.idx
    waitingInfo = nil
    if wasMatch then
        cleanupMatch()
        resultBanner = {
            won = (winnerIdx == idx), bet = bet, why = why or "", tick = getTickCount(),
        }
    end
end)

addEventHandler("rp:pool:aimSync", resourceRoot, function(tid, theta, power)
    remoteAim[tid] = { theta = theta, power = power, tick = getTickCount() }
end)

addEventHandler("rp:pool:placeDenied", resourceRoot, function()
    exports.rp_notify:notify("No puedes colocar la blanca ahí.", "warning")
end)

----------------------------------------------------------------
-- CEF: menu de apuestas y ranking
----------------------------------------------------------------
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local pendingView = nil

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function closeUI()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    if not (match and currentMode(tablesData[match.id]) == "place") then showCursor(false) end
    guiSetInputEnabled(false)
end

local function openUI()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

addEventHandler("rp:pool:show", resourceRoot, function(data)
    openUI()
    callJS(("RP.showTable(%s[0])"):format(toJSON(data or {}, true)))
    triggerServerEvent("rp:pool:requestBoard", resourceRoot)
end)

addEventHandler("rp:pool:openBoard", resourceRoot, function()
    openUI()
    callJS("RP.showBoardTab()")
end)

addEventHandler("rp:pool:board", resourceRoot, function(data)
    callJS(("RP.setBoard(%s[0])"):format(toJSON(data or {}, true)))
end)

addEventHandler("rp:pool:ui:create", root, function(bet)
    bet = tonumber(bet)
    if near and bet then triggerServerEvent("rp:pool:create", resourceRoot, near, bet) end
    closeUI()
end)

addEventHandler("rp:pool:ui:join", root, function()
    if near then triggerServerEvent("rp:pool:join", resourceRoot, near) end
    closeUI()
end)

addEventHandler("rp:pool:ui:leave", root, function()
    triggerServerEvent("rp:pool:leave", resourceRoot)
    waitingInfo = nil
    closeUI()
end)

addEventHandler("rp:pool:ui:board", root, function()
    triggerServerEvent("rp:pool:requestBoard", resourceRoot)
end)

addEventHandler("rp:pool:ui:close", root, closeUI)

----------------------------------------------------------------
-- Entrada: E junto a la mesa
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rp:pool:requestSync", resourceRoot)
    bindKey("e", "down", function()
        if not near or isElement(browserGui) or match then return end
        if getElementData(localPlayer, "rp:downed") then return end
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:pool:open", resourceRoot, near)
    end)
    bindKey("backspace", "down", function()
        if waitingInfo and not match and not isChatBoxInputActive() and not isConsoleActive() then
            triggerServerEvent("rp:pool:leave", resourceRoot)
            waitingInfo = nil
        end
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeUI()
    if match then cleanupMatch() end
    for id in pairs(visual) do destroyVisual(id) end
    hideCue()
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    closeUI()
    if match then cleanupMatch() end
end)

----------------------------------------------------------------
-- HUD
----------------------------------------------------------------
local FONT = "default-bold"
local function sc(v) return floor(v * scale) end

local function drawBallIcon(b, x, y, r, faded)
    local col = ballColor(b)
    local a = faded and 70 or 255
    dxDrawCircle(x, y, r + 1, 0, 360, tocolor(0, 0, 0, a), tocolor(0, 0, 0, a), 24)
    if b == 0 then
        dxDrawCircle(x, y, r, 0, 360, tocolor(245, 245, 245, a), tocolor(245, 245, 245, a), 24)
        return
    end
    dxDrawCircle(x, y, r, 0, 360, tocolor(col[1], col[2], col[3], a), tocolor(col[1], col[2], col[3], a), 24)
    if b > 8 then
        dxDrawRectangle(x - r, y - r * 0.42, r * 2, r * 0.84, tocolor(245, 245, 245, a))
    end
    if not faded then
        dxDrawCircle(x, y, r * 0.5, 0, 360, tocolor(245, 245, 245, 240), tocolor(245, 245, 245, 240), 16)
        dxDrawText(tostring(b), x - r, y - r, x + r, y + r, tocolor(10, 10, 10, 255), 0.55 * scale, FONT, "center", "center")
    end
end

local function money(n)
    local s = tostring(floor(n or 0)):reverse():gsub("(%d%d%d)", "%1."):reverse()
    return "$" .. (s:gsub("^%.", ""))
end

local function drawPlayerBox(T, i, x, y, w, h, align)
    local name = T.names and T.names[i] or "?"
    local active = T.turn == i
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 215))
    dxDrawRectangle(x, y, w, sc(3), active and tocolor(245, 165, 36, 255) or tocolor(255, 255, 255, 40))
    dxDrawText(name, x + sc(10), y + sc(7), x + w - sc(10), y + sc(26), tocolor(242, 244, 248), 1.0 * scale, FONT, align, "top", true)
    local g = T.groups and T.groups[i]
    if g == "solid" or g == "stripe" then
        local from, to = (g == "solid") and 1 or 9, (g == "solid") and 7 or 15
        local n = to - from + 1
        local gap = sc(24)
        local startX = (align == "left") and (x + sc(18)) or (x + w - sc(18) - (n - 1) * gap)
        for k = 0, n - 1 do
            local b = from + k
            drawBallIcon(b, startX + k * gap, y + sc(46), sc(9), T.balls[b].p)
        end
    else
        dxDrawText("Mesa abierta", x + sc(10), y + sc(36), x + w - sc(10), y + h, tocolor(154, 163, 178), 0.9 * scale, "default", align, "top")
    end
end

local function drawMatchHUD(T)
    if not T.names or not T.names[2] then return end
    local w, h = sc(255), sc(64)
    local cx = screenW / 2
    local top = sc(16)
    drawPlayerBox(T, 1, cx - sc(150) - w, top, w, h, "left")
    drawPlayerBox(T, 2, cx + sc(150), top, w, h, "right")

    -- Centro: bote y tiempo
    local cw = sc(290)
    dxDrawRectangle(cx - cw / 2, top, cw, h, tocolor(12, 14, 20, 225))
    dxDrawRectangle(cx - cw / 2, top, cw, sc(3), tocolor(245, 165, 36, 255))
    dxDrawText("POOL  -  BOTE", cx - cw / 2, top + sc(7), cx + cw / 2, top + sc(24), tocolor(154, 163, 178), 0.85 * scale, FONT, "center", "top")
    dxDrawText(T.bet and T.bet > 0 and money(T.bet * 2) or "Amistoso", cx - cw / 2, top + sc(22), cx + cw / 2, top + h, tocolor(76, 211, 138), 1.45 * scale, FONT, "center", "top")
    local left = T.left
    if left and T.stateAt then
        left = math.max(0, left - floor((getTickCount() - T.stateAt) / 1000))
        dxDrawText(("Turno: %ds"):format(left), cx - cw / 2, top + h - sc(18), cx + cw / 2, top + h - sc(2),
            left <= 10 and tocolor(255, 107, 107) or tocolor(200, 205, 214), 0.85 * scale, "default", "center", "top")
    end
end

local function drawPowerBar(power)
    local bw, bh = sc(26), sc(280)
    local x, y = screenW - sc(70), (screenH - bh) / 2
    dxDrawRectangle(x - 3, y - 3, bw + 6, bh + 6, tocolor(0, 0, 0, 200))
    dxDrawRectangle(x, y, bw, bh, tocolor(40, 44, 54, 255))
    local fh = bh * power
    local r = clamp(floor(power * 2 * 255), 0, 255)
    local g = clamp(floor((1 - power) * 2 * 255), 0, 255)
    dxDrawRectangle(x, y + bh - fh, bw, fh, tocolor(r, g, 40, 255))
    dxDrawText("FUERZA", x - sc(20), y + bh + sc(8), x + bw + sc(20), y + bh + sc(26), tocolor(230, 232, 238), 0.85 * scale, FONT, "center", "top")
    dxDrawText(("%d%%"):format(floor(power * 100)), x - sc(20), y - sc(24), x + bw + sc(20), y - sc(6), tocolor(230, 232, 238), 0.9 * scale, FONT, "center", "top")
end

local function drawHint(text)
    local w = dxGetTextWidth(text, 1.0 * scale, "default-bold") + sc(40)
    local x, y = (screenW - w) / 2, screenH - sc(70)
    dxDrawRectangle(x, y, w, sc(34), tocolor(12, 14, 20, 215))
    dxDrawRectangle(x, y, sc(3), sc(34), tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + sc(34), tocolor(242, 244, 248), 1.0 * scale, "default-bold", "center", "center")
end

local function drawPrompt(text)
    local w = dxGetTextWidth(text, 1.1 * scale, "default-bold") + sc(40)
    local x, y = (screenW - w) / 2, screenH - sc(140)
    dxDrawRectangle(x, y, w, sc(36), tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, sc(3), sc(36), tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + sc(36), tocolor(242, 244, 248), 1.1 * scale, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    -- Ayudas 3D
    if debugDraw then
        for id, T in pairs(tablesData) do
            if visual[id] then drawDebug(T) end
        end
    end

    -- Textos sobre mesas con alguien esperando
    for id, T in pairs(tablesData) do
        if T.status == "waiting" and visual[id] and not match then
            local cx, cy, cz = tableCenter(T)
            local sx, sy = getScreenFromWorldPosition(cx, cy, cz + 0.55)
            if sx then
                local who = T.names and T.names[1] or "Alguien"
                local txt = ("%s busca rival\nApuesta: %s"):format(who, (T.bet or 0) > 0 and money(T.bet) or "amistoso")
                dxDrawText(txt, sx - 150 + 1, sy + 1, sx + 150 + 1, sy + 60, tocolor(0, 0, 0, 220), 1.0 * scale, FONT, "center", "top")
                dxDrawText(txt, sx - 150, sy, sx + 150, sy + 60, tocolor(245, 165, 36, 255), 1.0 * scale, FONT, "center", "top")
            end
        end
    end

    local T = match and tablesData[match.id]
    if T then
        local mode = currentMode(T)
        if mode == "aim" and aim.cam >= 1 then drawGuide(T) end
        drawMatchHUD(T)
        if mode == "aim" then
            drawPowerBar(aim.power)
            drawHint("Ratón: apuntar   |   Mantén clic izq.: fuerza y suelta   |   Clic der.: puntería fina   |   C: vista   |   Retroceso: abandonar")
        elseif mode == "place" then
            drawHint(placePos and not placePos.ok and "No cabe ahí: elige otro sitio" or "Bola en mano: haz clic en la mesa para colocar la blanca")
        elseif mode == "watch" then
            local who = T.names and T.names[T.turn or 1] or "Tu rival"
            drawHint(("Turno de %s"):format(who))
        end
        if forfeitAsk > 0 then
            if getTickCount() - forfeitAsk > 6000 then
                forfeitAsk = 0
            else
                local txt = "¿Abandonar la partida? Perderás tu apuesta.   Y: confirmar   |   cualquier otra tecla: seguir"
                local w = dxGetTextWidth(txt, 1.1 * scale, FONT) + sc(40)
                dxDrawRectangle((screenW - w) / 2, screenH / 2 - sc(24), w, sc(48), tocolor(60, 14, 18, 235))
                dxDrawText(txt, (screenW - w) / 2, screenH / 2 - sc(24), (screenW + w) / 2, screenH / 2 + sc(24),
                    tocolor(255, 255, 255), 1.1 * scale, FONT, "center", "center")
            end
        end
    else
        if waitingInfo then
            drawPrompt(("Esperando rival... apuesta %s   |   Retroceso: cancelar"):format(waitingInfo.bet > 0 and money(waitingInfo.bet) or "amistosa"))
        elseif near and not isElement(browserGui) then
            local N = tablesData[near]
            if N and N.status == "waiting" then
                drawPrompt(("Pulsa E para unirte a %s (apuesta %s)"):format(N.names and N.names[1] or "la partida", (N.bet or 0) > 0 and money(N.bet) or "amistosa"))
            elseif N and N.status == "playing" then
                drawPrompt("Mesa ocupada")
            else
                drawPrompt("Pulsa E para jugar al pool")
            end
        end
    end

    -- Resultado
    if resultBanner then
        local age = getTickCount() - resultBanner.tick
        if age > 6000 then
            resultBanner = nil
        else
            local alpha = clamp(255 - (age - 4500) / 1500 * 255, 0, 255)
            local won = resultBanner.won
            local title = won and "¡VICTORIA!" or "DERROTA"
            local col = won and { 76, 211, 138 } or { 255, 107, 107 }
            local y = screenH * 0.3
            dxDrawText(title, 3, y + 3, screenW + 3, y + sc(80) + 3, tocolor(0, 0, 0, alpha), 3.2 * scale, FONT, "center", "top")
            dxDrawText(title, 0, y, screenW, y + sc(80), tocolor(col[1], col[2], col[3], alpha), 3.2 * scale, FONT, "center", "top")
            local sub = ""
            if resultBanner.bet > 0 then
                sub = won and ("Cobras " .. money(resultBanner.bet * 2) .. " (ganancia " .. money(resultBanner.bet) .. ")") or ("Pierdes " .. money(resultBanner.bet))
            end
            if resultBanner.why ~= "" then sub = (sub ~= "" and (sub .. "\n") or "") .. resultBanner.why end
            dxDrawText(sub, 0, y + sc(84), screenW, y + sc(150), tocolor(240, 242, 246, alpha), 1.3 * scale, FONT, "center", "top")
        end
    end
end)
