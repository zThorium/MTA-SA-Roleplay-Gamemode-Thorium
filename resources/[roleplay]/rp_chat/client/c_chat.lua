--[[
    rp_chat / c_chat.lua
    Teclas (abren el chat con el comando listo), burbujas de diálogo sobre la cabeza
    e indicador de "escribiendo...".
        T decir (por defecto de MTA) - Y susurrar - U gritar - B OOC
    El OOC no genera burbuja (el servidor no la envía).

    Estilo (misma línea que rp_notify): bocadillo oscuro redondeado con sombra que salta
    al aparecer, línea de luz que se abre desde el centro y texto letra a letra.
    Texto en Rubik (OFL, se lee bien en minúsculas); Kenney Future solo en la etiqueta corta.
    Formas suavizadas (sin dientes de sierra) con c_dx.lua.
      - decir: oscuro, línea blanca.
      - susurro: morado, más pequeño, con etiqueta y cola de puntos (como un pensamiento).
      - grito: rojo, letra grande, sacudida y trazos de énfasis que salen del bocadillo.
    Cada jugador apila hasta 3 frases: la nueva abajo, las viejas suben y se apagan.
]]

local MAX_DISTANCE = 25
local TYPING_DISTANCE = 15
local MAX_STACK = 3
local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.3, screenH / 900))
local function px(v) return v * S end

local function font(file, size, fallback)
    return dxCreateFont("fonts/" .. file, math.floor(size * S + 0.5), false, "antialiased") or fallback
end
local F_SAY = font("rubik_medium.ttf", 10.5, "default-bold")
local F_WHISPER = font("rubik_regular.ttf", 9.5, "default")
local F_SHOUT = font("rubik_semibold.ttf", 12, "default-bold")
local F_LABEL = font("kenney_future.ttf", 6.5, "default-bold")

-- Estilo por tipo
local STYLES = {
    say     = { bg = { 12, 14, 20, 228 }, accent = { 236, 239, 245 }, text = { 245, 247, 250 }, font = F_SAY,     maxW = 230, cps = 70 },
    whisper = { bg = { 34, 26, 58, 218 }, accent = { 178, 152, 255 }, text = { 224, 214, 255 }, font = F_WHISPER, maxW = 200, cps = 55, label = "SUSURRO", tail = "dots" },
    shout   = { bg = { 82, 12, 20, 235 }, accent = { 255, 96, 82 },   text = { 255, 255, 255 }, font = F_SHOUT,   maxW = 260, cps = 90, shake = true, burst = true, tail = "spike" },
    -- /r y /d: lo que dice por radio (lo ve quien está al lado); /meg: megáfono
    radio     = { bg = { 14, 40, 26, 228 }, accent = { 120, 220, 140 }, text = { 228, 246, 232 }, font = F_SAY,   maxW = 230, cps = 70, label = "RADIO" },
    megaphone = { bg = { 70, 46, 6, 235 },  accent = { 255, 196, 64 },  text = { 255, 255, 255 }, font = F_SHOUT, maxW = 260, cps = 90, label = "MEGAFONO", shake = true, burst = true, tail = "spike" },
}

-- Clic de la radio al recibir /r o /d (Kenney CC0, ver CREDITOS.md)
addEvent("rp:chat:radioSound", true)
addEventHandler("rp:chat:radioSound", resourceRoot, function()
    local s = playSound("sounds/radio_click.ogg")
    if s then setSoundVolume(s, 0.6) end
end)
local LABEL_H = dxGetFontHeight(1, F_LABEL)

local stacks = {}    -- [player] = { entrada más nueva primero }
local typing = {}    -- [player] = tick en que empezó a escribir
local typingTimer    -- comprueba si el jugador local escribe (ver final del archivo)

----------------------------------------------------------------
-- Utilidades de dibujo (las mismas de rp_notify)
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeIn(t) t = clamp(t, 0, 1); return t * t * t end
local function easeOutBack(t)
    t = clamp(t, 0, 1)
    local c = 1.70158
    return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function rgba(c, a) return tocolor(c[1], c[2], c[3], clamp(a, 0, 255)) end

-- Formas con antialiasing: c_dx.lua (DX.*)
local function circle(cx, cy, r, color) DX.circle(cx, cy, r, color, false) end
local function roundRect(x, y, w, h, r, color) DX.roundRect(x, y, w, h, r, color, false) end
local function tri(x1, y1, x2, y2, x3, y3, color)
    DX.poly({ { x1, y1, color }, { x2, y2, color }, { x3, y3, color } }, false)
end

-- Línea horizontal con degradado: sólida en el centro, transparente en los extremos
local function lightLine(cx, y, half, thick, c, a)
    if half < 1 then return end
    local solid, none = rgba(c, 255 * a), rgba(c, 0)
    dxDrawPrimitive("trianglestrip", false, { cx - half, y, none }, { cx, y, solid }, { cx - half, y + thick, none }, { cx, y + thick, solid })
    dxDrawPrimitive("trianglestrip", false, { cx, y, solid }, { cx + half, y, none }, { cx, y + thick, solid }, { cx + half, y + thick, none })
end

-- Parte el texto en líneas (al recibirlo, nunca por frame)
local function wrap(text, fnt, maxW)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and dxGetTextWidth(try, 1, fnt) > maxW then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

----------------------------------------------------------------
-- Teclas
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    -- "chatbox" abre la caja de chat con el comando escrito; MTA no dispara estos binds con el chat abierto
    bindKey("b", "down", "chatbox", "b")
    bindKey("y", "down", "chatbox", "susurrar")
    bindKey("u", "down", "chatbox", "gritar")
    -- Quien ya estaba escribiendo cuando arrancó el recurso
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= localPlayer and getElementData(p, "rp:typing") then typing[p] = getTickCount() end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("b", "down", "chatbox")
    unbindKey("y", "down", "chatbox")
    unbindKey("u", "down", "chatbox")
    if isTimer(typingTimer) then killTimer(typingTimer) end
end)

----------------------------------------------------------------
-- Burbujas
----------------------------------------------------------------
addEvent("rp:chat:bubble", true)
addEventHandler("rp:chat:bubble", resourceRoot, function(player, text, kind)
    local st = STYLES[kind]
    if not isElement(player) or not st or type(text) ~= "string" then return end
    local lines = wrap(text, st.font, px(st.maxW))
    local lh = dxGetFontHeight(1, st.font)
    local widths, w = {}, 0
    for n, l in ipairs(lines) do
        widths[n] = dxGetTextWidth(l, 1, st.font)
        w = math.max(w, widths[n])
    end
    if st.label then w = math.max(w, dxGetTextWidth(st.label, 1, F_LABEL)) end
    local top = px(8) + (st.label and (LABEL_H + px(2)) or 0)

    local list = stacks[player] or {}
    stacks[player] = list
    table.insert(list, 1, {
        st = st, lines = lines, widths = widths, lh = lh, top = top,
        w = w + px(24), h = top + #lines * lh + px(8),
        start = getTickCount(), duration = math.max(3500, math.min(9000, #text * 90)),
        off = nil,
    })
    -- Las que sobran se van (las más viejas)
    for i = #list, MAX_STACK + 1, -1 do table.remove(list, i) end
    typing[player] = nil   -- acaba de hablar: fuera el "escribiendo..."
end)

addEventHandler("onClientPlayerQuit", root, function()
    stacks[source], typing[source] = nil, nil
end)

local function drawBubble(b, sx, baseY, sc, alpha, now, older)
    local st = b.st
    local age = now - b.start
    local outK = easeIn((age - (b.duration - 300)) / 300)
    local pop = easeOutBack(age / 300)
    local k = sc * (0.6 + 0.4 * pop) * (older and 0.88 or 1)
    local a = alpha * clamp(age / 120, 0, 1) * (1 - outK) * (older and 0.6 or 1)
    if a <= 0.01 then return end

    local w, h = b.w * k, b.h * k
    local x = sx - w / 2
    if st.shake and age < 420 then x = x + math.sin(age * 0.11) * px(5) * k * (1 - age / 420) end
    local y = baseY - h
    local r = px(10) * k
    local bg = rgba(st.bg, st.bg[4] * a)

    -- Sombra, cuerpo y cola
    roundRect(x + px(2) * k, y + px(3) * k, w, h, r, tocolor(0, 0, 0, 70 * a))
    roundRect(x, y, w, h, r, bg)
    local cx = x + w / 2
    if not older then
        if st.tail == "dots" then
            circle(cx - px(3) * k, y + h + px(4) * k, px(3) * k, bg)
            circle(cx - px(7) * k, y + h + px(10) * k, px(2) * k, bg)
        elseif st.tail == "spike" then
            tri(cx - px(10) * k, y + h - 1, cx + px(2) * k, y + h - 1, cx - px(9) * k, y + h + px(14) * k, bg)
        else
            tri(cx - px(8) * k, y + h - 1, cx + px(4) * k, y + h - 1, cx - px(3) * k, y + h + px(9) * k, bg)
        end
    end

    -- Línea de luz arriba que se abre desde el centro
    lightLine(cx, y + px(1) * k, (w / 2 - r * 0.5) * easeOut((age - 60) / 380), math.max(1, px(1.5) * k), st.accent, a)

    -- Grito: trazos de énfasis que salen del bocadillo
    if st.burst and age < 520 and not older then
        local e = easeOut(age / 520)
        local col = rgba(st.accent, 230 * (1 - e) * a)
        local rx, ry = w / 2 + px(6) * k, h / 2 + px(6) * k
        local cy = y + h / 2
        for i = 0, 7 do
            local ang = math.rad(i * 45 + 22.5)
            local c, s = math.cos(ang), math.sin(ang)
            local d0, d1 = 1 + 0.15 * e, 1 + 0.15 * e + 0.25
            DX.line(cx + c * rx * d0, cy + s * ry * d0, cx + c * rx * d1, cy + s * ry * d1, math.max(1.5, px(2) * k), col, false, true)
        end
    end

    -- Etiqueta (susurro) y texto letra a letra
    if st.label then
        dxDrawText(st.label, x, y + px(7) * k, x + w, 0, rgba(st.accent, 230 * a), k, F_LABEL, "center", "top")
    end
    local left = math.floor((age - 80) * st.cps / 1000)
    if older then left = math.huge end
    local textCol = rgba(st.text, 255 * a)
    for n, line in ipairs(b.lines) do
        if left <= 0 then break end
        local len = utf8.len(line) or #line
        local shown = left >= len and line or utf8.sub(line, 1, left)
        left = left - len - 1
        local lx = cx - b.widths[n] * k / 2
        local ly = y + b.top * k + (n - 1) * b.lh * k
        dxDrawText(shown, lx + 1, ly + 1, 0, 0, tocolor(0, 0, 0, 150 * a), k, st.font, "left", "top")
        dxDrawText(shown, lx, ly, 0, 0, textCol, k, st.font, "left", "top")
    end
    return h
end

-- "Escribiendo...": píldora con tres puntos que saltan
local function drawTyping(sx, baseY, sc, alpha, now, since)
    local a = alpha * easeOut((now - since) / 200)
    local w, h = px(44) * sc, px(20) * sc
    local x, y = sx - w / 2, baseY - h
    roundRect(x + px(2) * sc, y + px(3) * sc, w, h, h / 2, tocolor(0, 0, 0, 60 * a))
    roundRect(x, y, w, h, h / 2, tocolor(12, 14, 20, 215 * a))
    for i = 0, 2 do
        local ph = (now / 160) - i * 0.9
        local jump = math.max(0, math.sin(ph)) * px(3.5) * sc
        local brightness = 150 + 105 * math.max(0, math.sin(ph))
        circle(sx + (i - 1) * px(10) * sc, y + h / 2 - jump, px(2.6) * sc, tocolor(brightness, brightness, brightness + 8, 255 * a))
    end
    return h
end

local lastFrame = getTickCount()
local function drawPlayer(player, list, since, cx, cy, cz, myDim, myInt, now, dt)
    -- Limpia las caducadas
    if list then
        for i = #list, 1, -1 do
            if now - list[i].start > list[i].duration then table.remove(list, i) end
        end
        if #list == 0 then stacks[player], list = nil, nil end
    end
    if not list and not since then return end
    if not isElementStreamedIn(player) or isPedDead(player)
        or getElementDimension(player) ~= myDim or getElementInterior(player) ~= myInt then return end

    local hx, hy, hz = getPedBonePosition(player, 8)
    local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
    if dist > MAX_DISTANCE then return end
    -- Sobre el nametag (0.35 m) y sobre la barra /ame si la hay (0.6 m)
    local lift = (getElementData(player, "rp:ame") and 1.0 or 0.75) - (player == localPlayer and 0.25 or 0)
    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + lift)
    if not sx then return end

    local alpha = 1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))
    local sc = math.max(0.7, 1.15 - dist / MAX_DISTANCE)
    local y = sy

    if since and dist <= TYPING_DISTANCE then
        y = y - drawTyping(sx, y, sc, alpha, now, since) - px(6) * sc
    end
    if list then
        -- Cada frase sube suave a su sitio cuando llega una nueva debajo
        local target = 0
        for i, b in ipairs(list) do
            b.off = b.off and (b.off + (target - b.off) * clamp(dt / 110, 0, 1)) or target
            local h = drawBubble(b, sx, y - b.off, sc, alpha, now, i > 1) or 0
            target = target + b.h * sc * (i > 1 and 0.88 or 1) + px(14) * sc
        end
    end
end

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(now - lastFrame, 100)
    lastFrame = now
    if (not next(stacks) and not next(typing)) or getElementData(localPlayer, "rp:hudHidden") then return end
    local cx, cy, cz = getCameraMatrix()
    local myDim, myInt = getElementDimension(localPlayer), getElementInterior(localPlayer)

    for player in pairs(typing) do
        if not isElement(player) then typing[player] = nil end
    end
    for player, list in pairs(stacks) do
        if isElement(player) then
            drawPlayer(player, list, typing[player], cx, cy, cz, myDim, myInt, now, dt)
        else
            stacks[player] = nil
        end
    end
    for player, since in pairs(typing) do
        if not stacks[player] then drawPlayer(player, nil, since, cx, cy, cz, myDim, myInt, now, dt) end
    end
end)

----------------------------------------------------------------
-- Indicador "escribiendo..." (solo se avisa al cambiar)
-- El servidor tiene elementdata_whitelisted: el cliente no puede escribir element data,
-- así que avisa con rp:chat:typing y el servidor pone "rp:typing" (s_chat.lua).
----------------------------------------------------------------
local amTyping = false
typingTimer = setTimer(function()
    local now = isChatBoxInputActive() and getElementData(localPlayer, "rp:characterId") and true or false
    if now ~= amTyping then
        amTyping = now
        triggerServerEvent("rp:chat:typing", resourceRoot, now)
    end
end, 250, 0)

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if key ~= "rp:typing" or source == localPlayer or getElementType(source) ~= "player" then return end
    typing[source] = new and getTickCount() or nil
end)
