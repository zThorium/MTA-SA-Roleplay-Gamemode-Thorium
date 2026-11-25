--[[
    rp_missions / client / c_cinematic.lua

    Motor de cinematicas (estandar: docs/CINEMATICAS.md) y llamadas de radio de los contactos.

    Plano (shot):  from/to (camara), look/lookTo (objetivo), dur, fov/fovTo (zoom),
                   roll/rollTo (angulo holandes, grados), shake (0 = tripode, 1 = normal, 2 = nervioso; por defecto 1),
                   ease = "smooth" | "linear" | "in" | "out".
                   Cualquier punto puede ser {x,y,z}, {npc="sweet", dz=0.6} (sigue a un actor) o {me=true, dz=0.6}.
    Dialogo:       who, text, at / overlap / gap (ver cutsceneSchedule en shared/s_config.lua).
    Cinematica:    letterbox, tail (ms al final), exit = "behind" (por defecto: la camara vuela detras del jugador y entrega el control).
    ENTER omite la cinematica (el servidor lo valida: solo el lider).
]]

local sw, sh = C.sw, C.sh
local lerp = function(a, b, t) return a + (b - a) * t end

local cs = nil             -- cinematica activa
local bars = 0             -- 0..1 animacion de las bandas
local barsTarget = 0
local lastBars = getTickCount()
local call = nil           -- llamada de radio activa { lines, idx, start, contact }
local callQueue = {}
local handoff = nil        -- transicion de la camara hacia el gameplay
local lastCam = nil        -- ultima matriz de camara de la cinematica

----------------------------------------------------------------
-- Voz y texto
----------------------------------------------------------------
local voices = {}          -- sonidos activos (varios a la vez si los dialogos se solapan)
local function stopVoice()
    for _, s in ipairs(voices) do if isElement(s) then destroyElement(s) end end
    voices = {}
end
local function playVoice(line, exclusive)
    if exclusive then stopVoice() end
    if line and line.voice then
        local s = playSound(line.voice, false)
        if s then setSoundVolume(s, 1.0) voices[#voices + 1] = s end
    end
end
local function perChar(line) return line.vlen and math.max(14, line.vlen * 0.85 / math.max(1, #line.text)) or 28 end

local function typed(text, elapsed, per)
    local n = math.min(#text, math.floor(elapsed / (per or 28)))
    -- evita cortar a mitad de un caracter UTF-8
    while n > 0 and n < #text and text:byte(n + 1) and text:byte(n + 1) >= 128 and text:byte(n + 1) < 192 do n = n + 1 end
    return text:sub(1, n)
end

local function speakerName(who)
    if who == "me" then return (getPlayerName(localPlayer):gsub("_", " ")) end
    return (MISSIONS.CONTACTS[who] or MISSIONS.CONTACTS.enemy).name
end

local function speakerColor(who, a)
    if who == "me" then return tocolor(255, 224, 140, a or 255) end
    return C.contactColor(who, a)
end

local function drawSubtitle(who, text, elapsed, alpha, per, rank)
    local sc = C.sc
    local w = math.min(sw * 0.62, 900 * sc)
    local x = sw / 2 - w / 2
    local y = sh * 0.80 - (rank or 0) * 74 * sc      -- las lineas solapadas se apilan hacia arriba
    local a = alpha or 255
    if (rank or 0) == 0 then
        for i = 0, 6 do
            dxDrawRectangle(0, y - 26 * sc + i * 5 * sc, sw, 5 * sc, tocolor(0, 0, 0, (i + 1) * 10 * a / 255))
        end
        dxDrawRectangle(0, y + 9 * sc, sw, 110 * sc, tocolor(0, 0, 0, 90 * a / 255))
    end
    dxDrawText(speakerName(who), x + 1, y - 8 * sc + 1, x + w, y + 20 * sc, tocolor(0, 0, 0, a), 1.35 * sc, "default-bold")
    dxDrawText(speakerName(who), x, y - 8 * sc, x + w, y + 20 * sc, speakerColor(who, a), 1.35 * sc, "default-bold")
    local shown = typed(text, elapsed, per)
    dxDrawText(shown, x + 1, y + 20 * sc + 1, x + w, y + 100 * sc, tocolor(0, 0, 0, a), 1.3 * sc, "default-bold", "left", "top", true, true)
    dxDrawText(shown, x, y + 20 * sc, x + w, y + 100 * sc, tocolor(245, 246, 250, a), 1.3 * sc, "default-bold", "left", "top", true, true)
end

----------------------------------------------------------------
-- Camara
----------------------------------------------------------------
local EASE = {
    smooth = function(t) return C.ease(t) end,
    linear = function(t) return math.max(0, math.min(1, t)) end,
    ["in"] = function(t) t = math.max(0, math.min(1, t)); return t * t end,
    out = function(t) t = math.max(0, math.min(1, t)); return 1 - (1 - t) * (1 - t) end,
}

local npcCache = {}
local function findNpc(key)
    local p = npcCache[key]
    if isElement(p) then return p end
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(ped, "rp:mNpc") == key then npcCache[key] = ped return ped end
    end
end

-- Punto fijo o dinamico: {x,y,z} | {npc="sweet", dz=} | {me=true, dz=} y, relativo a hacia donde MIRA el actor,
-- {npc="sweet", fwd=2.4, right=0.7, dz=0.25}  (fwd = hacia delante del actor, right = a su derecha, dz = altura sobre su cabeza)
local function relPoint(el, p)
    local ex, ey, ez = getElementPosition(el)
    local _, _, rz = getElementRotation(el)
    local a = math.rad(rz)
    local fx, fy = -math.sin(a), math.cos(a)
    local rx, ry = math.cos(a), math.sin(a)
    local _, _, hz = getPedBonePosition(el, 8)
    local f, r = p.fwd or 0, p.right or 0
    return ex + fx * f + rx * r + (p.dx or 0), ey + fy * f + ry * r + (p.dy or 0), (hz or (ez + 0.9)) + (p.dz or 0)
end

local function resolve(p)
    if not p then return nil end
    local el
    if p.npc then el = findNpc(p.npc) elseif p.me then el = localPlayer end
    if p.npc or p.me then
        if not el then return nil end
        if p.fwd or p.right then return relPoint(el, p) end
        local x, y, z = getPedBonePosition(el, 8)       -- cabeza
        if x then return x + (p.dx or 0), y + (p.dy or 0), z + (p.dz or 0) - 0.15 end
        x, y, z = getElementPosition(el)
        return x + (p.dx or 0), y + (p.dy or 0), z + (p.dz or 0.6)
    end
    return p[1], p[2], p[3]
end
local function startShot(i)
    cs.shotIdx, cs.shotStart = i, getTickCount()
end

-- Balanceo de camara en mano: suma de senos lentos incomensurables (nunca se repite del todo)
local function handheld(now, amp)
    local t = now / 1000
    return (math.sin(t * 1.3) + 0.6 * math.sin(t * 2.9 + 1.1)) * 0.035 * amp,
           (math.cos(t * 1.1) + 0.5 * math.sin(t * 3.3 + 0.4)) * 0.035 * amp,
           (math.sin(t * 1.9 + 2.0) + 0.5 * math.cos(t * 4.1)) * 0.022 * amp
end

local function updateCamera(now)
    if not cs or cs.shotIdx == 0 then return end
    local shot = cs.shots[cs.shotIdx]
    local el = now - cs.shotStart
    if el >= (shot.dur or 3000) and cs.shots[cs.shotIdx + 1] then
        startShot(cs.shotIdx + 1)
        shot, el = cs.shots[cs.shotIdx], 0
    end
    local t = (EASE[shot.ease or "smooth"] or EASE.smooth)(el / (shot.dur or 3000))
    local fx, fy, fz = resolve(shot.from)
    local tx, ty, tz = resolve(shot.to or shot.from)
    local lx, ly, lz = resolve(shot.look)
    local ltx, lty, ltz = resolve(shot.lookTo or shot.look)
    if not (fx and lx) then return end
    tx, ty, tz = tx or fx, ty or fy, tz or fz
    ltx, lty, ltz = ltx or lx, lty or ly, ltz or lz
    local amp = shot.shake == nil and 1 or shot.shake
    local sx, sy, sz = handheld(now, amp)
    local cx, cy, cz = lerp(fx, tx, t) + sx, lerp(fy, ty, t) + sy, lerp(fz, tz, t) + sz
    local ax, ay, az = lerp(lx, ltx, t) + sx * 0.5, lerp(ly, lty, t) + sy * 0.5, lerp(lz, ltz, t)
    local roll = lerp(shot.roll or 0, shot.rollTo or shot.roll or 0, t) + math.sin(now / 900) * 0.25 * amp
    local fov = lerp(shot.fov or 70, shot.fovTo or shot.fov or 70, t)
    setCameraMatrix(cx, cy, cz, ax, ay, az, roll, fov)
    lastCam = { cx, cy, cz, ax, ay, az, roll, fov }
end

-- Fin de la cinematica: la camara vuela hasta quedar detras del jugador y entrega el control sin corte brusco
local function beginHandoff()
    if lastCam and (cs and cs.data.exit or "behind") == "behind" then
        handoff = { t0 = getTickCount(), from = lastCam, dur = 900 }
    else
        handoff = nil
        setCameraTarget(localPlayer)
    end
end

local function updateHandoff(now)
    if not handoff then return end
    local t = (now - handoff.t0) / handoff.dur
    if t >= 1 or isPedDead(localPlayer) then
        handoff = nil
        setCameraTarget(localPlayer)
        return
    end
    t = C.ease(t)
    local px, py, pz = getElementPosition(localPlayer)
    local rz = math.rad(select(3, getElementRotation(localPlayer)))
    local fx, fy = -math.sin(rz), math.cos(rz)
    local tx, ty, tz = px - fx * 4.2, py - fy * 4.2, pz + 1.7
    local lx, ly, lz = px + fx * 5, py + fy * 5, pz + 0.9
    local f = handoff.from
    setCameraMatrix(lerp(f[1], tx, t), lerp(f[2], ty, t), lerp(f[3], tz, t), lerp(f[4], lx, t), lerp(f[5], ly, t), lerp(f[6], lz, t),
        lerp(f[7], 0, t), lerp(f[8], 70, t))
end

----------------------------------------------------------------
-- Cinematica
----------------------------------------------------------------
addEventHandler("rp:missions:cutscene", resourceRoot, function(stageIdx)
    if not C.def then return end
    local st = C.def.stages[stageIdx]
    if not st or not st.cutscene then return end
    handoff = nil
    npcCache = {}
    local data = st.cutscene
    cs = {
        data = data, stage = stageIdx, t0 = getTickCount(), shotIdx = 0, shotStart = 0,
        lines = data.lines or {}, shots = data.shots or {}, fired = {}, active = {},
    }
    cs.sched = cutsceneSchedule(data)
    -- el ultimo plano se alarga hasta cubrir todo el dialogo (con voz dura mas que los planos)
    do
        local sum, copy = 0, {}
        for i, s in ipairs(cs.shots) do sum = sum + (s.dur or 3000); copy[i] = s end
        local _, linesEnd = cutsceneSchedule(data)
        if #copy > 0 and linesEnd + 600 > sum then
            local last = {}
            for k, v in pairs(copy[#copy]) do last[k] = v end
            last.dur = (last.dur or 3000) + (linesEnd + 600 - sum)
            copy[#copy] = last
        end
        cs.shots = copy
    end
    C.cutscene = true
    barsTarget = 1
    if #cs.shots > 0 then startShot(1) end
    C.suppressHud("cinematic", true)
    playSoundFrontEnd(12)
end)

addEventHandler("rp:missions:cutsceneEnd", resourceRoot, function()
    stopVoice()
    -- la ultima cinematica va seguida de la pantalla de resultados: sin vuelo hacia el gameplay
    if cs and C.def and cs.stage == #C.def.stages then handoff = nil else beginHandoff() end
    cs = nil
    C.cutscene = false
    barsTarget = 0
    C.suppressHud("cinematic", false)
end)

bindKey("enter", "down", function()
    if cs then triggerServerEvent("rp:missions:skip", resourceRoot) end
end)

local function updateLines(now)
    if not cs then return end
    local el = now - cs.t0
    for i, sch in ipairs(cs.sched) do
        if not cs.fired[i] and el >= sch.s then
            cs.fired[i] = true
            cs.active[#cs.active + 1] = i
            playVoice(cs.lines[i], false)
        end
    end
    for k = #cs.active, 1, -1 do
        if el >= cs.sched[cs.active[k]].e then table.remove(cs.active, k) end
    end
end

----------------------------------------------------------------
-- Llamada de radio (no bloquea el juego)
----------------------------------------------------------------
addEventHandler("rp:missions:radio", resourceRoot, function(stageIdx, lines)
    -- las lineas del cliente traen voz/duracion (shared/s_voice.lua)
    local st = C.def and C.def.stages[stageIdx]
    if st and st.radio then lines = st.radio end
    if not lines or #lines == 0 then return end
    callQueue[#callQueue + 1] = lines
end)

local function nextCall(now)
    local lines = table.remove(callQueue, 1)
    call = { lines = lines, idx = 1, start = now, contact = lines[1].who, intro = now, lineStart = now + 700 }
    playSoundFrontEnd(40)
end

local function drawCall(now)
    if C.cutscene or C.results then return end
    if not call and #callQueue > 0 then nextCall(now) end
    if not call then return end
    local line = call.lines[call.idx]
    local el = now - call.start
    local sc = C.sc
    local slide = C.ease(el / 400)
    local x, y = 20 * sc - (1 - slide) * 400 * sc, sh * 0.28
    local w, h = 390 * sc, 108 * sc
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 225))
    dxDrawRectangle(x, y, 4 * sc, h, C.contactColor(line.who))
    -- "retrato": circulo con inicial y anillo de llamada pulsante
    local cx, cy = x + 46 * sc, y + 42 * sc
    local pulse = (now % 1100) / 1100
    local col = (MISSIONS.CONTACTS[line.who] or MISSIONS.CONTACTS.enemy).color
    local ring = tocolor(col[1], col[2], col[3], 140 * (1 - pulse))
    dxDrawCircle(cx, cy, (22 + pulse * 10) * sc, 0, 360, ring, ring, 32)
    dxDrawCircle(cx, cy, 22 * sc, 0, 360, C.contactColor(line.who, 255), C.contactColor(line.who, 255), 32)
    dxDrawText(speakerName(line.who):sub(1, 1):upper(), cx - 22 * sc, cy - 22 * sc, cx + 22 * sc, cy + 22 * sc, tocolor(10, 10, 14), 1.8 * sc, "default-bold", "center", "center")
    dxDrawText(speakerName(line.who), x + 84 * sc, y + 14 * sc, x + w, y + 36 * sc, C.contactColor(line.who), 1.25 * sc, "default-bold")
    dxDrawText("RADIO", x + 84 * sc, y + 34 * sc, x + w, y + 52 * sc, tocolor(154, 163, 178), 0.85 * sc, "default-bold")
    -- ecualizador
    for i = 0, 6 do
        local hh = (4 + math.abs(math.sin(now / 130 + i * 1.7)) * 12) * sc
        dxDrawRectangle(x + 134 * sc + i * 7 * sc, cy + 8 * sc - hh, 4 * sc, hh, tocolor(245, 165, 36, 220))
    end
    local le = now - call.lineStart
    if le >= 0 and call.played ~= call.idx then call.played = call.idx playVoice(line, true) end
    if le >= 0 then
        dxDrawText(typed(line.text, le, perChar(line)), x + 14 * sc, y + 66 * sc, x + w - 12 * sc, y + h - 6 * sc, tocolor(242, 244, 248), 1.05 * sc, "default-bold", "left", "top", true, true)
    end
    if le > dialogDuration(line) then
        call.idx = call.idx + 1
        call.lineStart = now
        if call.idx > #call.lines then call = nil end
    end
end

----------------------------------------------------------------
-- Bandas de cine y render
----------------------------------------------------------------
function C.drawLetterbox(now)
    local dt = (now - lastBars) / 1000
    lastBars = now
    if bars < barsTarget then bars = math.min(barsTarget, bars + dt * 1.6)
    elseif bars > barsTarget then bars = math.max(barsTarget, bars - dt * 1.6) end
    if bars <= 0 then return end
    local h = sh * 0.12 * C.ease(bars)
    dxDrawRectangle(0, 0, sw, h, tocolor(0, 0, 0, 255))
    dxDrawRectangle(0, sh - h, sw, h, tocolor(0, 0, 0, 255))
end

function C.setLetterbox(on) barsTarget = on and 1 or 0 end

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    if cs then updateCamera(now) end
    updateHandoff(now)
end)

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    if cs then
        updateLines(now)
        local el = now - cs.t0
        -- la linea mas reciente abajo; las anteriores (solapadas) apiladas encima
        for rank = 0, #cs.active - 1 do
            local i = cs.active[#cs.active - rank]
            local sch, line = cs.sched[i], cs.lines[i]
            local le = el - sch.s
            local fade = math.min(1, le / 220, (sch.e - el) / 220)
            drawSubtitle(line.who, line.text, le, 255 * math.max(0, fade), perChar(line), rank)
        end
        local title = C.def and C.def.title
        if title and now - cs.t0 < 3800 then
            local a = math.min(1, (now - cs.t0) / 500, (3800 - (now - cs.t0)) / 500)
            local sc = C.sc
            dxDrawText(title, 0 + 2, sh * 0.15 + 2, sw + 2, sh * 0.15 + 52 + 2, tocolor(0, 0, 0, 255 * a), 2.4 * sc, "default-bold", "center")
            dxDrawText(title, 0, sh * 0.15, sw, sh * 0.15 + 52, tocolor(245, 165, 36, 255 * a), 2.4 * sc, "default-bold", "center")
            dxDrawText(speakerName(C.def.contact) .. "  -  " .. (C.info and C.info.diffLabel or ""), 0, sh * 0.15 + 42 * sc, sw, sh * 0.15 + 70 * sc, tocolor(220, 224, 232, 255 * a), 1.1 * sc, "default-bold", "center")
        end
        dxDrawText("ENTER  Omitir", sw - 220 * C.sc, sh * 0.92, sw - 30 * C.sc, sh * 0.96, tocolor(200, 205, 215, 190), 0.95 * C.sc, "default-bold", "right")
    end
    drawCall(now)
    C.drawLetterbox(now)
end)

function C.resetCinematic()
    cs, call, callQueue, handoff, lastCam = nil, nil, {}, nil, nil
    stopVoice()
    barsTarget, bars = 0, 0
end

local prevLeft = C.onLeft
C.onLeft = function() C.resetCinematic() if prevLeft then prevLeft() end end
