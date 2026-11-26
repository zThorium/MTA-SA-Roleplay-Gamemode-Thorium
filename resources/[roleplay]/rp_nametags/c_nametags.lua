--[[
    rp_nametags / c_nametags.lua
    Sustituye los nametags de GTA por "Nombre Apellido" + ID sobre la cabeza, con barra
    de vida y chaleco. Solo jugadores con personaje en juego, a menos de MAX_DISTANCE
    metros y con línea de visión. También dibuja la etiqueta /ame.

    Estilo (misma línea que rp_notify y las burbujas de rp_chat):
      - Nombre en Kenney Future Narrow con sombra y el ID en una pastilla oscura.
      - Barra de vida redondeada que cambia de verde a ámbar y rojo, con "rastro de daño"
        (la parte perdida se queda en blanco un momento y se vacía después).
      - Aparece y desaparece con un fundido, sin saltos, al entrar o salir de la vista.
      - /ame: pastilla oscura con punto rosa (el color de /me), entra con un salto y una
        línea de luz que se abre desde el centro.
]]

local MAX_DISTANCE = 20
local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.3, screenH / 900))
local function px(v) return v * S end

local function font(file, size, fallback)
    return dxCreateFont("fonts/" .. file, math.floor(size * S + 0.5), false, "antialiased") or fallback
end
local F_NAME = font("kenney_future_narrow.ttf", 10.5, "default-bold")
local F_ID = font("kenney_future.ttf", 7, "default-bold")
local F_AME = font("kenney_future_narrow.ttf", 10, "default-bold")
local NAME_H = dxGetFontHeight(1, F_NAME)
local ID_H = dxGetFontHeight(1, F_ID)

local ME_COLOR = { 255, 150, 190 }
local streamed = {}   -- jugadores cercanos (se refresca con un timer, no cada frame)
local vis = {}        -- [player] = alfa actual del nametag (fundido)
local trail = {}      -- [player] = vida "fantasma" que se vacía tras un golpe
local ameStart = {}   -- [player] = tick en que apareció su /ame
local nameCache = {}  -- [player] = { text, idText, nameW, idW }

----------------------------------------------------------------
-- Utilidades de dibujo (las mismas de rp_notify)
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeOutBack(t)
    t = clamp(t, 0, 1)
    local c = 1.70158
    return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function rgba(c, a) return tocolor(c[1], c[2], c[3], clamp(a, 0, 255)) end

local function fan(cx, cy, r, a0, a1, color, seg)
    seg = seg or 8
    local v = { { cx, cy, color } }
    for i = 0, seg do
        local a = math.rad(a0 + (a1 - a0) * i / seg)
        v[#v + 1] = { cx + math.cos(a) * r, cy + math.sin(a) * r, color }
    end
    dxDrawPrimitive("trianglefan", false, unpack(v))
end

local function roundRect(x, y, w, h, r, color)
    if w <= 0 or h <= 0 then return end
    r = math.min(r, w / 2, h / 2)
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    fan(x + r, y + r, r, 180, 270, color)
    fan(x + w - r, y + r, r, 270, 360, color)
    fan(x + w - r, y + h - r, r, 0, 90, color)
    fan(x + r, y + h - r, r, 90, 180, color)
end

local function lightLine(cx, y, half, thick, c, a)
    if half < 1 then return end
    local solid, none = rgba(c, 255 * a), rgba(c, 0)
    dxDrawPrimitive("trianglestrip", false, { cx - half, y, none }, { cx, y, solid }, { cx - half, y + thick, none }, { cx, y + thick, solid })
    dxDrawPrimitive("trianglestrip", false, { cx, y, solid }, { cx + half, y, none }, { cx, y + thick, solid }, { cx + half, y + thick, none })
end

-- Verde (llena) -> ámbar (media) -> rojo (poca)
local function healthColor(ratio)
    if ratio > 0.5 then
        local k = (ratio - 0.5) / 0.5
        return { 255 - (255 - 76) * k, 178 + (221 - 178) * k, 46 + (140 - 46) * k }
    end
    local k = ratio / 0.5
    return { 255, 84 + (178 - 84) * k, 96 - (96 - 46) * k }
end

----------------------------------------------------------------
-- Nametags nativos y lista de cercanos
----------------------------------------------------------------
local function refreshStreamed()
    streamed = getElementsByType("player", root, true)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        setPlayerNametagShowing(player, false)
        if getElementData(player, "rp:ame") then ameStart[player] = getTickCount() - 1000 end
    end
    refreshStreamed()
    setTimer(refreshStreamed, 500, 0)
end)

addEventHandler("onClientPlayerJoin", root, function()
    setPlayerNametagShowing(source, false)
end)

addEventHandler("onClientPlayerQuit", root, function()
    vis[source], trail[source], ameStart[source], nameCache[source] = nil, nil, nil, nil
end)

addEventHandler("onClientPlayerChangeNick", root, function()
    nameCache[source] = nil
end)

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if getElementType(source) ~= "player" then return end
    if key == "rp:ame" then
        ameStart[source] = new and getTickCount() or nil
    elseif key == "id" then
        nameCache[source] = nil
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do setPlayerNametagShowing(player, true) end
end)

----------------------------------------------------------------
-- /ame
----------------------------------------------------------------
local function drawAme(player, cx, cy, cz, myDim, myInt, now)
    local text = getElementData(player, "rp:ame")
    if not text or isPedDead(player) or getElementDimension(player) ~= myDim or getElementInterior(player) ~= myInt then return end
    local hx, hy, hz = getPedBonePosition(player, 8)
    local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
    if dist > MAX_DISTANCE then return end
    -- Más arriba que el nametag (que ocupa ~0.35 m); el local no tiene nametag
    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + (player == localPlayer and 0.4 or 0.6))
    if not sx then return end

    local age = now - (ameStart[player] or now - 1000)
    local alpha = (1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))) * clamp(age / 140, 0, 1)
    local sc = math.max(0.7, 1.2 - dist / MAX_DISTANCE) * (0.65 + 0.35 * easeOutBack(age / 300))
    local textW = dxGetTextWidth(text, sc, F_AME)
    local dot = px(5) * sc
    local w = textW + dot * 2 + px(22) * sc
    local h = px(20) * sc
    local x, y = sx - w / 2, sy - h

    roundRect(x + px(2) * sc, y + px(3) * sc, w, h, h / 2, tocolor(0, 0, 0, 60 * alpha))
    roundRect(x, y, w, h, h / 2, tocolor(14, 12, 18, 225 * alpha))
    fan(x + px(10) * sc + dot / 2, y + h / 2, dot / 2, 0, 360, rgba(ME_COLOR, 255 * alpha), 12)
    lightLine(sx, y + px(1) * sc, (w / 2 - h / 2) * easeOut((age - 60) / 380), math.max(1, px(1.5) * sc), ME_COLOR, alpha)
    dxDrawText(text, x + px(16) * sc + dot, y, x + w, y + h, tocolor(255, 226, 236, 255 * alpha), sc, F_AME, "left", "center", false, false, false, false, true)
end

----------------------------------------------------------------
-- Nametag
----------------------------------------------------------------
local function nameData(player)
    local c = nameCache[player]
    if c then return c end
    local id = getElementData(player, "id")
    local text = getPlayerName(player):gsub("_", " ")
    local idText = id and tostring(id) or nil
    c = { text = text, idText = idText, nameW = dxGetTextWidth(text, 1, F_NAME), idW = idText and dxGetTextWidth(idText, 1, F_ID) or 0 }
    nameCache[player] = c
    return c
end

local function drawBar(x, y, w, h, ratio, ghost, color, alpha)
    roundRect(x, y, w, h, h / 2, tocolor(10, 12, 16, 190 * alpha))
    if ghost and ghost > ratio then
        roundRect(x, y, w * ghost, h, h / 2, tocolor(255, 255, 255, 190 * alpha))
    end
    roundRect(x, y, w * clamp(ratio, 0, 1), h, h / 2, rgba(color, 240 * alpha))
end

local function drawTag(player, sx, sy, dist, alpha, dt)
    local sc = math.max(0.7, 1.2 - dist / MAX_DISTANCE)
    local d = nameData(player)

    -- Nombre + pastilla con el ID
    local gap = px(6) * sc
    local chipW = d.idText and (d.idW * sc + px(10) * sc) or 0
    local total = d.nameW * sc + (d.idText and (gap + chipW) or 0)
    local x = sx - total / 2
    local nameY = sy - NAME_H * sc
    dxDrawText(d.text, x + 1, nameY + 1, 0, 0, tocolor(0, 0, 0, 190 * alpha), sc, F_NAME, "left", "top")
    dxDrawText(d.text, x, nameY, 0, 0, tocolor(245, 247, 250, 255 * alpha), sc, F_NAME, "left", "top")
    if d.idText then
        local chipH = ID_H * sc + px(4) * sc
        local cx = x + d.nameW * sc + gap
        local cy = nameY + (NAME_H * sc - chipH) / 2
        roundRect(cx, cy, chipW, chipH, chipH / 2, tocolor(12, 14, 20, 200 * alpha))
        dxDrawText(d.idText, cx, cy, cx + chipW, cy + chipH, tocolor(170, 178, 192, 255 * alpha), sc, F_ID, "center", "center")
    end

    -- Vida (con rastro de daño) y chaleco
    local hp = clamp(getElementHealth(player) / 100, 0, 1)
    local g = trail[player] or hp
    if g < hp then g = hp else g = g + (hp - g) * clamp(dt / 450, 0, 1) end
    trail[player] = g
    local w, h = px(64) * sc, math.max(3, px(4.5) * sc)
    local bx, by = sx - w / 2, sy + px(4) * sc
    drawBar(bx, by, w, h, hp, g, healthColor(hp), alpha)
    local armor = getPedArmor(player)
    if armor > 0 then
        drawBar(bx, by + h + px(3) * sc, w, math.max(2, h * 0.7), armor / 100, nil, { 170, 196, 230 }, alpha)
    end
end

local lastFrame = getTickCount()
addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(now - lastFrame, 100)
    lastFrame = now
    if getElementData(localPlayer, "rp:hudHidden") then return end   -- p. ej. cámara de Fotogram (rp_phone)
    local cx, cy, cz = getCameraMatrix()
    local myDim, myInt = getElementDimension(localPlayer), getElementInterior(localPlayer)

    drawAme(localPlayer, cx, cy, cz, myDim, myInt, now)
    for _, player in ipairs(streamed) do
        if isElement(player) and player ~= localPlayer and getElementData(player, "rp:characterId") then
            drawAme(player, cx, cy, cz, myDim, myInt, now)
        end
    end

    for _, player in ipairs(streamed) do
        if isElement(player) and player ~= localPlayer then
            local show, hx, hy, hz, dist = false
            if getElementData(player, "rp:characterId")
                and not isPedDead(player)
                and getElementDimension(player) == myDim and getElementInterior(player) == myInt
                and getElementAlpha(player) > 0 then
                hx, hy, hz = getPedBonePosition(player, 8)
                dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
                show = dist <= MAX_DISTANCE and isLineOfSightClear(cx, cy, cz, hx, hy, hz, true, false, false, true, false, false, false, localPlayer)
            end
            -- Fundido de entrada y salida en vez de aparecer de golpe
            local v = vis[player] or 0
            v = clamp(v + (show and 1 or -1) * dt / 180, 0, 1)
            vis[player] = v
            if v > 0 and hx then
                local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.35)
                if sx then
                    local alpha = (1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))) * easeOut(v)
                    drawTag(player, sx, sy, dist, alpha, dt)
                end
            end
        end
    end
end)
