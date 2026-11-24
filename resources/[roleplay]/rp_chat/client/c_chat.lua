--[[
    rp_chat / c_chat.lua
    Teclas (abren el chat con el comando listo) y burbujas de dialogo sobre la cabeza.
        T decir (por defecto de MTA) - Y susurrar - U gritar - B OOC
    El OOC no genera burbuja (el servidor no la envia).
]]

local MAX_DISTANCE = 25
local screenH = select(2, guiGetScreenSize())
local baseScale = math.max(0.8, math.min(1.2, screenH / 900))

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("b", "down", "chatbox", "b")
    bindKey("y", "down", "chatbox", "susurrar")
    bindKey("u", "down", "chatbox", "gritar")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("b", "down", "chatbox")
    unbindKey("y", "down", "chatbox")
    unbindKey("u", "down", "chatbox")
end)

-- Estilo por tipo: fondo, borde, texto, fuente, escala
local STYLES = {
    say     = { bg = { 20, 22, 28, 215 },  edge = { 255, 255, 255 }, text = { 255, 255, 255 }, font = "default-bold", scale = 1.0 },
    whisper = { bg = { 40, 34, 64, 205 },  edge = { 180, 160, 255 }, text = { 215, 205, 255 }, font = "default",      scale = 0.85 },
    shout   = { bg = { 120, 18, 22, 225 }, edge = { 255, 110, 90 },  text = { 255, 255, 255 }, font = "default-bold", scale = 1.25 },
}
local FADE_MS = 300
local bubbles = {}   -- [player] = { text, style, start, duration }

addEvent("rp:chat:bubble", true)
addEventHandler("rp:chat:bubble", resourceRoot, function(player, text, kind)
    if not isElement(player) or not STYLES[kind] then return end
    bubbles[player] = { text = text, style = STYLES[kind], start = getTickCount(), duration = math.max(3500, math.min(9000, #text * 90)) }
end)

addEventHandler("onClientPlayerQuit", root, function() bubbles[source] = nil end)

-- Parte el texto en lineas de ancho maximo maxW
local function wrap(text, scale, font, maxW)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and dxGetTextWidth(try, scale, font) > maxW then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function draw(player, b, cx, cy, cz, myDim, myInt, now)
    local age = now - b.start
    if age > b.duration then bubbles[player] = nil return end
    if isPedDead(player) or getElementDimension(player) ~= myDim or getElementInterior(player) ~= myInt then return end

    local hx, hy, hz = getPedBonePosition(player, 8)
    local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
    if dist > MAX_DISTANCE then return end
    -- Sobre el nametag (0.35 m) y sobre la barra /ame si la hay (0.6 m)
    local lift = (getElementData(player, "rp:ame") and 1.0 or 0.75) - (player == localPlayer and 0.25 or 0)
    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + lift)
    if not sx then return end

    local fade = math.min(1, age / FADE_MS, (b.duration - age) / FADE_MS)
    local alpha = fade * (1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3)))
    local st = b.style
    local scale = baseScale * st.scale * math.max(0.75, 1.15 - dist / MAX_DISTANCE)
    local lines = wrap(b.text, scale, st.font, 230 * scale)
    local lh = dxGetFontHeight(scale, st.font)
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, dxGetTextWidth(l, scale, st.font)) end
    w = w + 16 * scale
    local h = #lines * lh + 8 * scale
    local x, y = sx - w / 2, sy - h - 6   -- 6 px de aire para la punta

    dxDrawRectangle(x - 1, y - 1, w + 2, h + 2, tocolor(st.edge[1], st.edge[2], st.edge[3], 110 * alpha))
    dxDrawRectangle(x, y, w, h, tocolor(st.bg[1], st.bg[2], st.bg[3], st.bg[4] * alpha))
    dxDrawRectangle(x, y, w, 2, tocolor(st.edge[1], st.edge[2], st.edge[3], 230 * alpha))
    -- Punta de la burbuja
    dxDrawRectangle(sx - 3, y + h, 6, 3, tocolor(st.bg[1], st.bg[2], st.bg[3], st.bg[4] * alpha))
    dxDrawRectangle(sx - 1, y + h + 3, 2, 2, tocolor(st.bg[1], st.bg[2], st.bg[3], st.bg[4] * alpha))
    for i, l in ipairs(lines) do
        local ly = y + 4 * scale + (i - 1) * lh
        dxDrawText(l, x + 1, ly + 1, x + w + 1, ly + lh + 1, tocolor(0, 0, 0, 180 * alpha), scale, st.font, "center", "top")
        dxDrawText(l, x, ly, x + w, ly + lh, tocolor(st.text[1], st.text[2], st.text[3], 255 * alpha), scale, st.font, "center", "top")
    end
end

addEventHandler("onClientRender", root, function()
    if not next(bubbles) or getElementData(localPlayer, "rp:hudHidden") then return end
    local cx, cy, cz = getCameraMatrix()
    local myDim, myInt = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local now = getTickCount()
    for player, b in pairs(bubbles) do
        if isElement(player) and isElementStreamedIn(player) then
            draw(player, b, cx, cy, cz, myDim, myInt, now)
        elseif not isElement(player) or now - b.start > b.duration then
            bubbles[player] = nil
        end
    end
end)
