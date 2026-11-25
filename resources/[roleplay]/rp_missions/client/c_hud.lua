--[[
    rp_missions / client / c_hud.lua

    HUD de mision (objetivo, contadores, vidas compartidas, equipo), avisos animados, barra de
    interaccion (mantener E), espectador, invulnerabilidad al reaparecer, pantalla de resultados con
    camara de victoria, e IA de los enemigos (se ejecuta en el cliente que sincroniza a cada ped).
]]

local sw, sh = C.sw, C.sh
local hud = nil
local banner = nil          -- { text, start }  nuevo objetivo
local doneFlash = nil       -- start de "objetivo completado"
local toasts = {}           -- avisos centrales
local diedBanner = nil
local invulnUntil = 0
local progress, progressText, progressShown = nil, nil, 0
local holdIndex = nil
local specTargets, specIdx = {}, 0
local results, resultsAt = nil, 0
local vignette = 0

local WHITE, MUTED = tocolor(242, 244, 248), tocolor(154, 163, 178)

local function panel(x, y, w, h, accent)
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 215))
    if accent then dxDrawRectangle(x, y, 4 * C.sc, h, accent) end
end

----------------------------------------------------------------
-- Identidad visual (estilo GTA SA): contorno negro en todo texto sobre el mundo, etiquetas de color, barras planas
-- con borde negro, fuentes nativas de MTA (diploma, pricedown, bankgothic), caja de ayuda arriba a la izquierda y
-- titulo de mision abajo a la derecha. Todo plano y rectangular (sin degradados ni bordes redondeados).
----------------------------------------------------------------
local OUT8 = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

local function alphaOf(color) return math.floor(color / 16777216) % 256 end

-- Las fuentes decorativas de GTA no garantizan acentos: se quitan solo ahi
local function deaccent(s)
    local map = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ñ"] = "n", ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ñ"] = "N", ["¡"] = "", ["¿"] = "" }
    return (s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch) return map[ch] end) or s)
end

local function shadowText(text, x1, y1, x2, y2, color, scale, font, ax, ay, clip, wrap, thick)
    local k = thick or 1
    local blk = tocolor(0, 0, 0, math.min(235, alphaOf(color)))
    for _, o in ipairs(OUT8) do
        dxDrawText(text, x1 + o[1] * k, y1 + o[2] * k, x2 + o[1] * k, y2 + o[2] * k, blk, scale, font, ax, ay, clip, wrap)
    end
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, ax, ay, clip, wrap)
end

-- Texto con etiquetas ~y~ ~r~ ~b~ ~g~ ~w~ (si no trae ninguna se colorea solo con MISSIONS.TAGWORDS)
local function autoTag(text)
    if text:find("~", 1, true) then return text end
    local spans = {}
    for tag, list in pairs(MISSIONS.TAGWORDS or {}) do
        for _, w in ipairs(list) do
            local init = 1
            while true do
                local s, e = text:find(w, init, true)
                if not s then break end
                spans[#spans + 1] = { s = s, e = e, tag = tag, len = e - s }
                init = e + 1
            end
        end
    end
    table.sort(spans, function(a, b) if a.s ~= b.s then return a.s < b.s end return a.len > b.len end)
    local out, pos = {}, 1
    for _, sp in ipairs(spans) do
        if sp.s >= pos then
            out[#out + 1] = text:sub(pos, sp.s - 1)
            out[#out + 1] = "~" .. sp.tag .. "~" .. text:sub(sp.s, sp.e) .. "~w~"
            pos = sp.e + 1
        end
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

local function codedText(text)
    local tags = MISSIONS.TAGS or {}
    return (autoTag(text or ""):gsub("~(%a)~", function(c) return tags[c] or "#FFFFFF" end))
end

local function drawTagged(text, x1, y1, x2, y2, scale, font, ax, ay, clip, wrap, alpha)
    alpha = alpha or 255
    local coded = codedText(text)
    local plain = (coded:gsub("#%x%x%x%x%x%x", ""))
    local blk = tocolor(0, 0, 0, math.min(235, alpha))
    for _, o in ipairs(OUT8) do dxDrawText(plain, x1 + o[1], y1 + o[2], x2 + o[1], y2 + o[2], blk, scale, font, ax, ay, clip, wrap) end
    dxDrawText(coded, x1, y1, x2, y2, tocolor(255, 255, 255, alpha), scale, font, ax, ay, clip, wrap, false, true)
end

-- Barra plana: borde negro de 2 px, fondo del mismo color al 30 % y relleno solido que se reduce de derecha a izquierda
local function flatBar(x, y, w, h, f, r, g, b, a)
    a = a or 255
    dxDrawRectangle(x - 2, y - 2, w + 4, h + 4, tocolor(0, 0, 0, a))
    dxDrawRectangle(x, y, w, h, tocolor(r, g, b, math.floor(77 * a / 255)))
    if f > 0 then dxDrawRectangle(x, y, w * math.min(1, f), h, tocolor(r, g, b, a)) end
end

-- Flecha 3D flotante (invertida, con vaiven) sobre un objetivo
local function arrow3D(x, y, z, r, g, b, now)
    local sx, sy = getScreenFromWorldPosition(x, y, z + math.sin(now / 260) * 0.25)
    if not sx then return end
    local cx, cy, cz = getCameraMatrix()
    local d = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
    local s = math.max(9, math.min(30, 520 / math.max(d, 8))) * C.sc
    local black, col = tocolor(0, 0, 0, 240), tocolor(r, g, b, 255)
    dxDrawPrimitive("trianglefan", false, { sx, sy + 3, black }, { sx - s * 0.8 - 3, sy - s * 1.4 - 3, black }, { sx + s * 0.8 + 3, sy - s * 1.4 - 3, black })
    dxDrawPrimitive("trianglefan", false, { sx, sy, col }, { sx - s * 0.8, sy - s * 1.4, col }, { sx + s * 0.8, sy - s * 1.4, col })
end

-- Caja de ayuda (arriba a la izquierda): rectangulo negro al 75 %, texto blanco pequeno, 5-8 s, con "bip"
local helpBox = nil
local function showHelp(text, ms)
    helpBox = { text = text, start = getTickCount(), dur = ms or 7000 }
    playSoundFrontEnd(5)
end

local titleCard, titleShown = nil, false
local wasInVeh = false

----------------------------------------------------------------
-- Eventos del servidor
----------------------------------------------------------------
C.onEnter = function(info)
    hud, banner, doneFlash, toasts, diedBanner, results = nil, nil, nil, {}, nil, nil
    invulnUntil, progress, holdIndex = 0, nil, nil
    helpBox, titleCard, titleShown, wasInVeh = nil, nil, false, false
end

local prevLeft = C.onLeft
C.onLeft = function()
    if prevLeft then prevLeft() end
    hud, banner, doneFlash, toasts, diedBanner, results, progress, holdIndex = nil, nil, nil, {}, nil, nil, nil, nil
    helpBox, titleCard, titleShown, wasInVeh = nil, nil, false, false
    specTargets, specIdx = {}, 0
    vignette = 0
end

addEventHandler("rp:missions:hud", resourceRoot, function(d) hud = d end)

addEventHandler("rp:missions:stage", resourceRoot, function(idx, total, text)
    banner = { text = text, idx = idx, total = total, start = getTickCount() }
    playSoundFrontEnd(11)
    -- Caja de ayuda de la mecanica de la etapa (arriba a la izquierda)
    local st = C.def and C.def.stages and C.def.stages[idx]
    if st and not st.cutscene then
        if st.interact then
            showHelp(("Mantén [E] cerca del punto marcado para %s."):format((st.interact.text or "interactuar"):lower()))
        elseif st.getin then
            showHelp("Sube al vehículo de la misión. Lo verás marcado en azul en el radar y con una flecha.")
        elseif st.timeLimit then
            showHelp(("Tienes %s para completar este objetivo."):format(C.fmtTime(st.timeLimit)))
        elseif st.deliver then
            showHelp("Lleva el vehículo al destino sin destruirlo. Si lo abandonas, el destino se oculta.")
        end
    end
end)

addEventHandler("rp:missions:stageDone", resourceRoot, function()
    doneFlash = getTickCount()
    playSoundFrontEnd(12)
end)

addEventHandler("rp:missions:flash", resourceRoot, function(text, kind)
    toasts[#toasts + 1] = { text = text, kind = kind or "info", start = getTickCount() }
    if #toasts > 3 then table.remove(toasts, 1) end
    playSoundFrontEnd(kind == "warn" and 4 or 5)
end)

addEventHandler("rp:missions:died", resourceRoot, function(name, lives, last)
    diedBanner = { name = name, lives = lives, last = last, start = getTickCount() }
end)

addEventHandler("rp:missions:respawned", resourceRoot, function(ms)
    invulnUntil = getTickCount() + ms
    setCameraTarget(localPlayer)
end)

addEventHandler("onClientPlayerDamage", localPlayer, function()
    if C.active and getTickCount() < invulnUntil then cancelEvent() end
end)

addEventHandler("rp:missions:progress", resourceRoot, function(pct, text)
    progress, progressText = pct, text
    if not pct then progressShown = 0 end
end)

----------------------------------------------------------------
-- Interaccion: mantener E cerca de un punto
----------------------------------------------------------------
local function nearestPoint()
    if not hud or not hud.points or C.cutscene or C.spectating or isPedInVehicle(localPlayer) then return end
    local px, py, pz = getElementPosition(localPlayer)
    local best, bd
    for i, pt in ipairs(hud.points) do
        if not pt[4] then
            local d = getDistanceBetweenPoints3D(px, py, pz, pt[1], pt[2], pt[3])
            if d <= MISSIONS.HOLD_RANGE and (not bd or d < bd) then best, bd = i, d end
        end
    end
    return best
end

bindKey("e", "down", function()
    if not C.active then return end
    local i = nearestPoint()
    if i then
        holdIndex = i
        triggerServerEvent("rp:missions:hold", resourceRoot, i)
    end
end)
bindKey("e", "up", function()
    if holdIndex then
        holdIndex = nil
        triggerServerEvent("rp:missions:hold", resourceRoot, false)
    end
end)

----------------------------------------------------------------
-- Espectador: flechas izquierda/derecha cambian de companero
----------------------------------------------------------------
addEventHandler("rp:missions:spectate", resourceRoot, function(on)
    C.spectating = on
    specIdx = 0
    if not on then setCameraTarget(localPlayer) end
end)

local function refreshSpec()
    specTargets = {}
    if hud then
        for _, m in ipairs(hud.members) do
            if isElement(m.p) and m.p ~= localPlayer and not m.spec and not isPedDead(m.p) then specTargets[#specTargets + 1] = m.p end
        end
    end
end

local function stepSpec(dir)
    if not C.spectating then return end
    refreshSpec()
    if #specTargets == 0 then return end
    specIdx = ((specIdx - 1 + dir) % #specTargets) + 1
    setCameraTarget(specTargets[specIdx])
end
bindKey("arrow_r", "down", function() stepSpec(1) end)
bindKey("arrow_l", "down", function() stepSpec(-1) end)

setTimer(function()
    if not C.spectating then return end
    refreshSpec()
    local cur = specTargets[specIdx]
    if (not cur or not isElement(cur) or isPedDead(cur)) and #specTargets > 0 then stepSpec(1) end
end, 1000, 0)

----------------------------------------------------------------
-- Resultados
----------------------------------------------------------------
addEventHandler("rp:missions:results", resourceRoot, function(data)
    results, resultsAt = data, getTickCount()
    C.results = data
    C.cutscene = false
    C.setLetterbox(true)
    C.suppressHud("results", true)
    if data.success then playSoundFrontEnd(12) else playSoundFrontEnd(4) end
    if data.success and data.victory then
        C.victoryCamStart = getTickCount()
    end
    if C.spectating then C.spectating = false setCameraTarget(localPlayer) end
end)

local function drawResults(now)
    local r = results
    local sc = C.sc
    local el = now - resultsAt
    local victoryTime = (r.success and r.victory) and r.victoryTime or 0
    if el < victoryTime then
        -- fase de camara de victoria: titulo grande
        local a = C.ease(el / 700)
        local s = 3.1 * sc * (1 + (1 - a) * 0.4)
        -- Centro de pantalla reservado a los anuncios criticos: Diploma amarilla (#E1B02C) con borde negro grueso
        shadowText("MISION SUPERADA", 0, sh * 0.62, sw, sh * 0.62 + 90 * sc, tocolor(225, 176, 44, 255 * a), s * 0.85, "diploma", "center", "top", false, false, 3)
        shadowText(deaccent(r.title):upper(), 0, sh * 0.62 + 84 * sc, sw, sh * 0.62 + 124 * sc, tocolor(255, 255, 255, 255 * a), 1.0 * sc, "bankgothic", "center", "top", false, false, 2)
        return
    end
    local t = el - victoryTime
    local a = C.ease(t / 600)
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 150 * a))
    local w, h = 760 * sc, 440 * sc
    local x, y = sw / 2 - w / 2, sh / 2 - h / 2 + (1 - a) * 60 * sc
    local accent = r.success and tocolor(225, 176, 44, 255 * a) or tocolor(180, 25, 29, 255 * a)
    dxDrawRectangle(x, y, w, h, tocolor(14, 16, 22, 240 * a))
    dxDrawRectangle(x, y, w, 4 * sc, accent)
    -- Diploma: amarilla #E1B02C en exito, roja #B4191D en fracaso
    shadowText(r.success and "MISION SUPERADA" or "MISION FRACASADA", x, y + 14 * sc, x + w, y + 70 * sc,
        r.success and tocolor(225, 176, 44, 255 * a) or tocolor(180, 25, 29, 255 * a), 2.0 * sc, "diploma", "center", "top", false, false, 3)
    dxDrawText(r.title .. "  -  " .. r.contactName, x, y + 66 * sc, x + w, y + 90 * sc, tocolor(220, 224, 232, 255 * a), 1.15 * sc, "default-bold", "center")
    if r.reason and not r.success then
        dxDrawText(r.reason, x, y + 90 * sc, x + w, y + 112 * sc, tocolor(240, 130, 130, 255 * a), 1.05 * sc, "default-bold", "center")
    end
    local dc = r.diffColor or { 245, 165, 36 }
    dxDrawText(("Dificultad %s (x%.2f)    Tiempo %s"):format(r.difficulty, r.mult, C.fmtTime(r.elapsed)), x, y + 112 * sc, x + w, y + 134 * sc,
        tocolor(dc[1], dc[2], dc[3], 255 * a), 1.0 * sc, "default-bold", "center")

    -- tabla
    local cols = { { "Jugador", 0.02 }, { "Rol", 0.28 }, { "Bajas", 0.46 }, { "Obj.", 0.55 }, { "Caidas", 0.64 }, { "XP", 0.76 }, { "Dinero", 0.86 } }
    local ty = y + 150 * sc
    dxDrawRectangle(x + 16 * sc, ty, w - 32 * sc, 24 * sc, tocolor(255, 255, 255, 18 * a))
    for _, c in ipairs(cols) do dxDrawText(c[1], x + w * c[2] + 8 * sc, ty, x + w, ty + 24 * sc, tocolor(154, 163, 178, 255 * a), 0.95 * sc, "default-bold", "left", "center") end
    local count = (t - 500) / 1400   -- animacion de los contadores
    count = math.max(0, math.min(1, count))
    for i, row in ipairs(r.rows) do
        local ry = ty + 28 * sc + (i - 1) * 32 * sc
        local mine = row.name == r.you
        if mine then dxDrawRectangle(x + 16 * sc, ry, w - 32 * sc, 30 * sc, tocolor(245, 165, 36, 28 * a)) end
        local col = mine and tocolor(255, 214, 120, 255 * a) or tocolor(235, 238, 245, 255 * a)
        local vals = {
            row.name, row.role or "-", tostring(math.floor(row.kills * count)), tostring(math.floor(row.objs * count)), tostring(row.deaths),
            ("+%d"):format(math.floor(row.xp * count)), ("$%d"):format(math.floor(row.cash * count)),
        }
        for ci, c in ipairs(cols) do dxDrawText(vals[ci], x + w * c[2] + 8 * sc, ry, x + w - 8 * sc, ry + 30 * sc, col, 1.0 * sc, "default-bold", "left", "center", true) end
    end
    -- recompensas del jugador local en Pricedown (relleno blanco / verde #36682C y contorno negro)
    for _, row in ipairs(r.rows) do
        if row.name == r.you and r.success then
            shadowText(("+$%d"):format(math.floor(row.cash * count)), x, y + h - 112 * sc, x + w / 2, y + h - 66 * sc, tocolor(54, 150, 60, 255 * a), 1.5 * sc, "pricedown", "center", "top", false, false, 2)
            if row.respect > 0 then
                shadowText(("RESPECT +%d"):format(math.floor(row.respect * count)), x + w / 2, y + h - 112 * sc, x + w, y + h - 66 * sc, tocolor(255, 255, 255, 255 * a), 1.5 * sc, "pricedown", "center", "top", false, false, 2)
            end
        end
        if row.name == r.you and row.respect > 0 then
            dxDrawText(("Respeto con %s: +%d"):format(r.contactName, math.floor(row.respect * count)), x, y + h - 62 * sc, x + w, y + h - 40 * sc,
                C.contactColor(r.contact, 255 * a), 1.15 * sc, "default-bold", "center")
        end
    end
    local left = math.max(0, math.ceil((r.wait - (t / 1000) * 1000 + 600) / 1000))
    dxDrawText(("Volviendo al mundo libre en %ds"):format(math.max(0, math.ceil((victoryTime + r.wait - el) / 1000))), x, y + h - 30 * sc, x + w, y + h - 8 * sc,
        tocolor(154, 163, 178, 255 * a), 0.95 * sc, "default", "center")
end

-- camara de victoria: orbita lenta alrededor del grupo
addEventHandler("onClientPreRender", root, function()
    if not results or not results.success or not results.victory or not C.victoryCamStart then return end
    local el = getTickCount() - C.victoryCamStart
    if el > results.victoryTime + 1000 then return end
    local v = results.victory
    local ang = el / 3200
    local cx, cy, cz = v.look[1], v.look[2], v.look[3]
    local dx, dy = v.from[1] - cx, v.from[2] - cy
    local r = math.sqrt(dx * dx + dy * dy)
    local base = math.atan2(dy, dx)
    setCameraMatrix(cx + math.cos(base + ang * 0.35) * r, cy + math.sin(base + ang * 0.35) * r, v.from[3] + el / 2600, cx, cy, cz, 0, 60)
end)

----------------------------------------------------------------
-- Dibujo del HUD
----------------------------------------------------------------
local function drawHud(now)
    if not hud then return end
    local sc = C.sc
    local w = 340 * sc
    local x = sw - w - 22 * sc
    local y = sh * 0.30
    local lines = #hud.counters
    local members = #hud.members
    local h = (96 + lines * 32 + members * 26 + 46 + (hud.timeLeft and 30 or 0)) * sc
    panel(x, y, w, h, C.contactColor(C.def and C.def.contact or "enemy"))
    dxDrawText(("%s"):format(C.def and C.def.title or "Mision"):upper(), x + 16 * sc, y + 8 * sc, x + w - 10 * sc, y + 28 * sc, tocolor(245, 165, 36), 0.95 * sc, "default-bold", "left", "top", true)
    local dc = C.info and C.info.diffColor or { 245, 165, 36 }
    dxDrawText(("%s  |  %s"):format(hud.diffLabel or "", C.fmtTime(hud.elapsed + (now - (hud.syncedAt or now)))), x + 16 * sc, y + 8 * sc, x + w - 12 * sc, y + 28 * sc, tocolor(dc[1], dc[2], dc[3]), 0.95 * sc, "default-bold", "right")
    drawTagged(hud.text or "", x + 16 * sc, y + 30 * sc, x + w - 12 * sc, y + 80 * sc, 1.15 * sc, "default-bold", "left", "top", true, true)
    local cy = y + 86 * sc
    -- Temporizador (Bank Gothic, mayusculas): se vuelve rojo y parpadea con menos de 30 s
    if hud.timeLeft then
        local left = math.max(0, hud.timeLeft - (now - (hud.syncedAt or now)))
        local urgent = left < 30000
        local col = urgent and tocolor(220, 40, 45, 170 + 85 * math.abs(math.sin(now / 200))) or WHITE
        shadowText("TIEMPO", x + 16 * sc, cy, x + w, cy + 26 * sc, MUTED, 0.85 * sc, "bankgothic", "left", "top")
        shadowText(C.fmtTime(left), x, cy - 2 * sc, x + w - 14 * sc, cy + 28 * sc, col, 1.15 * sc, "bankgothic", "right", "top", false, false, 1)
        cy = cy + 30 * sc
    end
    for _, c in ipairs(hud.counters) do
        shadowText(c.label:upper(), x + 16 * sc, cy, x + w, cy + 16 * sc, MUTED, 0.72 * sc, "bankgothic", "left", "top")
        dxDrawText(c.pct and (c.a .. "%") or (c.a .. " / " .. c.b), x, cy, x + w - 14 * sc, cy + 16 * sc, WHITE, 0.95 * sc, "default-bold", "right")
        local f = math.max(0, math.min(1, c.a / math.max(1, c.b)))
        local r, g, b = 225, 176, 44
        if c.pct then
            if f > 0.5 then r, g, b = 76, 211, 138 elseif f > 0.25 then r, g, b = 225, 176, 44 else r, g, b = 180, 25, 29 end
        end
        flatBar(x + 16 * sc, cy + 19 * sc, w - 32 * sc, 6 * sc, f, r, g, b)
        cy = cy + 32 * sc
    end
    -- vidas compartidas
    dxDrawText("VIDAS DEL EQUIPO", x + 16 * sc, cy + 4 * sc, x + w, cy + 20 * sc, MUTED, 0.9 * sc, "default-bold")
    local lives = hud.lives
    local lx = x + w - 16 * sc
    if lives <= 0 then
        dxDrawText("ULTIMA VIDA", x, cy + 3 * sc, x + w - 14 * sc, cy + 20 * sc, tocolor(240, 90, 90, 160 + 95 * math.abs(math.sin(now / 280))), 0.95 * sc, "default-bold", "right")
    else
        for i = 1, math.min(lives, 8) do
            local bx = lx - i * 20 * sc
            dxDrawCircle(bx + 5 * sc, cy + 8 * sc, 6 * sc, 0, 360, tocolor(235, 70, 90), tocolor(235, 70, 90), 16)
            dxDrawCircle(bx + 13 * sc, cy + 8 * sc, 6 * sc, 0, 360, tocolor(235, 70, 90), tocolor(235, 70, 90), 16)
            dxDrawRectangle(bx + 3 * sc, cy + 9 * sc, 12 * sc, 6 * sc, tocolor(235, 70, 90))
        end
    end
    cy = cy + 28 * sc
    -- equipo
    for _, m in ipairs(hud.members) do
        local p = m.p
        local hp = (isElement(p) and not isPedDead(p)) and math.max(0, math.min(100, getElementHealth(p))) or 0
        local col = m.spec and tocolor(110, 114, 124) or WHITE
        dxDrawText(m.name .. (m.spec and "  (espectador)" or ""), x + 16 * sc, cy, x + w - 100 * sc, cy + 22 * sc, col, 0.95 * sc, "default-bold", "left", "center", true)
        if hp > 40 then flatBar(x + w - 96 * sc, cy + 8 * sc, 80 * sc, 6 * sc, hp / 100, 76, 211, 138)
        else flatBar(x + w - 96 * sc, cy + 8 * sc, 80 * sc, 6 * sc, hp / 100, 180, 25, 29) end
        cy = cy + 26 * sc
    end
end

local function drawBanner(now)
    if not banner then return end
    local el = now - banner.start
    if el > 6200 then banner = nil return end
    local sc = C.sc
    local a = math.min(1, el / 350, (6200 - el) / 600)
    -- Subtitulo/objetivo: zona inferior central (8-10 % sobre el borde), etiquetas de color y contorno negro
    local y = sh * 0.865 - (1 - C.ease(el / 400)) * -20 * sc
    shadowText(("OBJETIVO %d/%d"):format(banner.idx, banner.total), 0, y - 24 * sc, sw, y, tocolor(225, 176, 44, 255 * a), 0.8 * sc, "bankgothic", "center")
    drawTagged(banner.text or "", sw * 0.15, y, sw * 0.85, y + 70 * sc, 1.45 * sc, "default-bold", "center", "top", true, true, math.floor(255 * a))
end

-- Caja de ayuda: arriba a la izquierda, rectangulo negro al 75 %
local function drawHelp(now)
    if not helpBox then return end
    local el = now - helpBox.start
    if el > helpBox.dur then helpBox = nil return end
    local sc = C.sc
    local a = math.min(1, el / 200, (helpBox.dur - el) / 400)
    local w = 330 * sc
    local lines = math.ceil(#helpBox.text / 42)
    local h = (16 + lines * 18) * sc
    local x, y = 22 * sc, sh * 0.06
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 191 * a))
    dxDrawText(helpBox.text, x + 10 * sc, y + 8 * sc, x + w - 10 * sc, y + h - 4 * sc, tocolor(255, 255, 255, 255 * a), 0.95 * sc, "default-bold", "left", "top", true, true)
end

-- Titulo de la mision: abajo a la derecha, Diploma amarilla con borde negro, 4-5 s con fundido
local function drawTitleCard(now)
    if not titleCard then return end
    local el = now - titleCard.start
    if el > 4800 then titleCard = nil return end
    local sc = C.sc
    local a = math.min(1, el / 700, (4800 - el) / 800)
    shadowText(deaccent(C.def and C.def.title or ""), sw * 0.35, sh * 0.80, sw - 36 * sc, sh * 0.80 + 80 * sc, tocolor(225, 176, 44, 255 * a), 1.7 * sc, "diploma", "right", "top", false, false, 3)
end

-- Vehiculo de mision fuera de uso: flecha 3D azul sobre el vehiculo (y aviso la primera vez que se baja)
local function drawVehicleHint(now)
    local v = hud and hud.veh
    if not v or not isElement(v) or C.cutscene then wasInVeh = false return end
    if getPedOccupiedVehicle(localPlayer) == v then wasInVeh = true return end
    if wasInVeh then
        wasInVeh = false
        showHelp("Dejaste el vehículo de la misión: vuelve a subir. Lo marca la flecha azul y el radar.", 6000)
    end
    local x, y, z = getElementPosition(v)
    arrow3D(x, y, z + 1.9, 44, 89, 157, now)
end

local function drawDoneFlash(now)
    if not doneFlash then return end
    local el = now - doneFlash
    if el > 1700 then doneFlash = nil return end
    local a = math.min(1, el / 200, (1700 - el) / 500)
    local sc = C.sc
    shadowText("OBJETIVO COMPLETADO", 0, sh * 0.22, sw, sh * 0.22 + 40 * sc, tocolor(120, 235, 160, 255 * a), (1.8 + (1 - C.ease(el / 300)) * 0.5) * sc, "default-bold", "center")
end

local function drawToasts(now)
    local sc = C.sc
    for i = #toasts, 1, -1 do
        local t = toasts[i]
        local el = now - t.start
        if el > 3600 then table.remove(toasts, i) end
    end
    for i, t in ipairs(toasts) do
        local el = now - t.start
        local a = math.min(1, el / 250, (3600 - el) / 400)
        local y = sh * 0.34 + (i - 1) * 34 * sc
        local col = t.kind == "warn" and tocolor(245, 130, 100, 255 * a) or t.kind == "ok" and tocolor(120, 235, 160, 255 * a) or tocolor(235, 238, 245, 255 * a)
        shadowText(t.text, 0, y, sw, y + 30 * sc, col, 1.4 * sc, "default-bold", "center")
    end
end

local function drawProgress(now)
    local sc = C.sc
    local near = nearestPoint()
    if progress then
        progressShown = progressShown + (progress - progressShown) * 0.35
        local w, h = 320 * sc, 14 * sc
        local x, y = sw / 2 - w / 2, sh * 0.72
        dxDrawText((progressText or "Progreso") .. "...", x, y - 28 * sc, x + w, y - 4 * sc, WHITE, 1.2 * sc, "default-bold", "center")
        dxDrawRectangle(x - 3, y - 3, w + 6, h + 6, tocolor(10, 12, 18, 230))
        dxDrawRectangle(x, y, w * progressShown, h, tocolor(245, 165, 36))
        dxDrawText(("%d%%"):format(progressShown * 100), x, y, x + w, y + h, tocolor(20, 14, 4), 0.85 * sc, "default-bold", "center", "center")
    elseif near and not C.cutscene then
        local w = 300 * sc
        local x, y = sw / 2 - w / 2, sh * 0.72
        local pulse = 0.75 + 0.25 * math.sin(now / 220)
        dxDrawRectangle(x, y, w, 40 * sc, tocolor(12, 14, 20, 225))
        dxDrawRectangle(x, y, 4 * sc, 40 * sc, tocolor(245, 165, 36))
        dxDrawText(("Manten  [E]  para %s"):format(((hud and hud.holdText) or "interactuar"):lower()), x + 14 * sc, y, x + w - 8 * sc, y + 40 * sc, tocolor(250, 250, 252, 255 * pulse), 1.1 * sc, "default-bold", "left", "center", true)
    end
end

local function drawDied(now)
    if not diedBanner then return end
    local el = now - diedBanner.start
    if el > 3800 then diedBanner = nil return end
    local sc = C.sc
    local a = math.min(1, el / 250, (3800 - el) / 500)
    local y = sh * 0.42
    shadowText(diedBanner.name .. " cayo", 0, y, sw, y + 40 * sc, tocolor(240, 100, 100, 255 * a), 2.1 * sc, "default-bold", "center")
    local sub = diedBanner.last and "Sin vidas: pasa a modo espectador" or (diedBanner.lives > 0 and ("Reaparece... vidas restantes: " .. diedBanner.lives) or "Reaparece... ULTIMA VIDA")
    shadowText(sub, 0, y + 38 * sc, sw, y + 66 * sc, tocolor(235, 238, 245, 255 * a), 1.2 * sc, "default-bold", "center")
end

local function drawSpectate(now)
    if not C.spectating or C.results then return end
    local sc = C.sc
    local cur = specTargets[specIdx]
    local name = (cur and isElement(cur)) and (getPlayerName(cur):gsub("_", " ")) or "-"
    dxDrawRectangle(0, sh - 90 * sc, sw, 90 * sc, tocolor(0, 0, 0, 150))
    shadowText("MODO ESPECTADOR", 0, sh - 82 * sc, sw, sh - 56 * sc, tocolor(245, 165, 36), 1.3 * sc, "default-bold", "center")
    shadowText("Observando a " .. name .. "     [<]  [>]  cambiar", 0, sh - 52 * sc, sw, sh - 24 * sc, WHITE, 1.15 * sc, "default-bold", "center")
end

addEventHandler("rp:missions:hud", resourceRoot, function() if hud then hud.syncedAt = getTickCount() end end)

addEventHandler("onClientRender", root, function()
    if not C.active then return end
    local now = getTickCount()
    -- viñeta de invulnerabilidad
    if now < invulnUntil then
        local a = math.min(1, (invulnUntil - now) / 600)
        dxDrawRectangle(0, 0, sw, sh * 0.04, tocolor(120, 200, 255, 70 * a))
        dxDrawRectangle(0, sh * 0.96, sw, sh * 0.04, tocolor(120, 200, 255, 70 * a))
    end
    if results then
        drawResults(now)
        return
    end
    if C.cutscene then return end
    if hud and not titleShown then titleShown = true titleCard = { start = now } end   -- el titulo sale al primer fotograma jugable
    drawHud(now)
    drawVehicleHint(now)
    drawHelp(now)
    drawTitleCard(now)
    drawBanner(now)
    drawDoneFlash(now)
    drawToasts(now)
    drawProgress(now)
    drawDied(now)
    drawSpectate(now)
end)

----------------------------------------------------------------
-- IA de enemigos (solo los peds que sincroniza este cliente)
----------------------------------------------------------------
local ai = {}

local function pickTarget(ped)
    local px, py, pz = getElementPosition(ped)
    local dim = getElementDimension(ped)
    local best, bd
    local cands = getElementsByType("player", root, true)
    for _, a in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(a, "rp:mAlly") and not isPedInVehicle(a) then cands[#cands + 1] = a end
    end
    for _, p in ipairs(cands) do
        if getElementDimension(p) == dim and not isPedDead(p) and getElementAlpha(p) > 0 and getElementData(p, "rp:downed") ~= true then
            local x, y, z = getElementPosition(p)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d < 70 and (not bd or d < bd) then best, bd = p, d end
        end
    end
    return best, bd
end

local function think(ped)
    local s = ai[ped]
    if not s then s = { burstUntil = 0, pauseUntil = 0, slot = false }; ai[ped] = s end
    local now = getTickCount()
    if not s.slot then
        setPedWeaponSlot(ped, getSlotFromWeapon(getPedWeapon(ped)))
        s.slot = true
    end
    local target, d = pickTarget(ped)
    if not target then
        setPedControlState(ped, "aim_weapon", false)
        setPedControlState(ped, "fire", false)
        setPedControlState(ped, "forwards", false)
        return
    end
    local acc = getElementData(ped, "rp:mAcc") or 0.5
    local px, py = getElementPosition(ped)
    local tx, ty, tz = getElementPosition(target)
    setPedRotation(ped, -math.deg(math.atan2(tx - px, ty - py)))
    local err = (1 - acc) * d * 0.10
    setPedAimTarget(ped, tx + (math.random() - 0.5) * err, ty + (math.random() - 0.5) * err, tz + 0.1 + (math.random() - 0.5) * err * 0.5)
    setPedControlState(ped, "aim_weapon", true)
    -- avanza si esta lejos, mantiene distancia si esta cerca
    setPedControlState(ped, "forwards", d > 18)
    -- rafagas con pausa (mas agresivas en dificultad alta)
    if now > s.pauseUntil then
        if now > s.burstUntil then
            s.burstUntil = now + 450 + math.random(0, 500)
            s.pauseUntil = s.burstUntil + 700 - acc * 450 + math.random(0, 400)
        end
        setPedControlState(ped, "fire", now < s.burstUntil)
    else
        setPedControlState(ped, "fire", false)
    end
end

setTimer(function()
    if not C.active then return end
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(ped, "rp:mEnemy") and not isPedDead(ped) and isElementSyncer(ped) then
            think(ped)
        end
    end
end, 140, 0)

addEventHandler("onClientElementDestroy", root, function() if ai[source] then ai[source] = nil end end)

----------------------------------------------------------------
-- Aliados (Sweet): siguen al grupo y disparan a los enemigos, tambien desde el auto
----------------------------------------------------------------
local allyState = {}

local function nearestEnemy(ped)
    local px, py, pz = getElementPosition(ped)
    local dim = getElementDimension(ped)
    local best, bd
    for _, e in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(e, "rp:mEnemy") and not isPedDead(e) and getElementDimension(e) == dim then
            local x, y, z = getElementPosition(e)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d < 50 and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best, bd
end

local function thinkAlly(ped)
    local s = allyState[ped]
    if not s then s = { burstUntil = 0, pauseUntil = 0 }; allyState[ped] = s end
    local now = getTickCount()
    local inCar = isPedInVehicle(ped)
    local enemy, d = nearestEnemy(ped)
    if enemy then
        local px, py = getElementPosition(ped)
        local tx, ty, tz = getElementPosition(enemy)
        if inCar then
            setPedDoingGangDriveby(ped, true)
        else
            setPedRotation(ped, -math.deg(math.atan2(tx - px, ty - py)))
        end
        setPedAimTarget(ped, tx + (math.random() - 0.5) * d * 0.04, ty + (math.random() - 0.5) * d * 0.04, tz + 0.2)
        setPedControlState(ped, "aim_weapon", true)
        setPedControlState(ped, "forwards", false)
        if now > s.pauseUntil then
            if now > s.burstUntil then
                s.burstUntil = now + 500 + math.random(0, 400)
                s.pauseUntil = s.burstUntil + 350 + math.random(0, 350)
            end
            setPedControlState(ped, "fire", now < s.burstUntil)
        else
            setPedControlState(ped, "fire", false)
        end
        return
    end
    setPedControlState(ped, "aim_weapon", false)
    setPedControlState(ped, "fire", false)
    if inCar then
        setPedDoingGangDriveby(ped, false)
        return
    end
    -- sin enemigos: seguir al jugador mas cercano
    local px, py, pz = getElementPosition(ped)
    local near, nd
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if getElementDimension(p) == getElementDimension(ped) and not isPedDead(p) then
            local x, y, z = getElementPosition(p)
            local dd = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if not nd or dd < nd then near, nd = p, dd end
        end
    end
    if near and nd > 4.5 then
        local x, y = getElementPosition(near)
        setPedRotation(ped, -math.deg(math.atan2(x - px, y - py)))
        setPedControlState(ped, "forwards", true)
        setPedControlState(ped, "sprint", nd > 14)
    else
        setPedControlState(ped, "forwards", false)
        setPedControlState(ped, "sprint", false)
    end
end

setTimer(function()
    if not C.active or C.cutscene then return end
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(ped, "rp:mAlly") and not isPedDead(ped) and isElementSyncer(ped) then thinkAlly(ped) end
    end
end, 140, 0)

addEventHandler("onClientPedDamage", root, function(attacker, weapon, bodypart)
    if getElementData(source, "rp:mAlly") then cancelEvent() return end
    -- Headshot a un enemigo con arma de fuego: muerte instantanea (el servidor lo valida)
    if bodypart == 9 and attacker == localPlayer and getElementData(source, "rp:mEnemy") and not isPedDead(source)
        and ((weapon >= 22 and weapon <= 34) or weapon == 38) then
        triggerServerEvent("rp:missions:headshot", resourceRoot, source, weapon)
    end
end)

----------------------------------------------------------------
-- Validacion de puntos de aparicion de enemigos (el servidor no tiene colisiones)
-- Un punto es valido si: hay suelo a la altura esperada, no hay techo ni copas encima (rayo vertical desde arriba) y hay
-- linea de vision libre hasta el punto central del grupo (no queda tras una pared o dentro de una casa).
----------------------------------------------------------------
addEvent("rp:missions:validate", true)
addEventHandler("rp:missions:validate", resourceRoot, function(token, gx, gy, gz, cands)
    local ok = {}
    -- La altura z del diseno puede ser aproximada: se busca el suelo real bajo el punto central (techos excluidos al
    -- quedarse con el impacto mas bajo cercano a la altura esperada) y se usa como referencia
    local realZ
    do
        local bestD
        for _, off in ipairs({ { 0, 0 }, { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 }, { 0, -1.5 } }) do
            local hit, _, _, hz = processLineOfSight(gx + off[1], gy + off[2], gz + 25, gx + off[1], gy + off[2], gz - 25, true, false, false, true, false, false, false, false, localPlayer)
            if hit then
                local d = math.abs(hz - gz)
                if not bestD or d < bestD then bestD, realZ = d, hz end
            end
        end
    end
    if realZ then gz = realZ end
    for _, c in ipairs(cands or {}) do
        local x, y = c[1], c[2]
        -- primer impacto desde arriba: si es un tejado/techo, queda muy por encima del suelo esperado
        local hit, hx, hy, hz = processLineOfSight(x, y, gz + 40, x, y, gz - 15, true, false, false, true, true, false, false, false, localPlayer)
        if hit and hz <= gz + 1.8 and hz >= gz - 4 then
            if isLineOfSightClear(hx, hy, hz + 1.0, gx, gy, gz + 1.0, true, false, false, true, false) then
                ok[#ok + 1] = { hx, hy, hz }
            end
        end
    end
    triggerServerEvent("rp:missions:validated", resourceRoot, token, ok, realZ)
end)