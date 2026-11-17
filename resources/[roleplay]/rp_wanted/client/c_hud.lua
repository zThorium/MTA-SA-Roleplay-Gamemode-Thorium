--[[
    rp_wanted / c_hud.lua
    Estrellas de busqueda en el HUD, debajo de la hora y el dinero de rp_hud
    (arriba a la derecha, con la misma escala y margenes). Las estrellas se
    dibujan con primitivas (arte propio, sin imagenes de GTA).
      - Solo se muestran con 1 estrella o mas: 6 casillas, las ganadas llenas.
      - Parpadean 3 s cuando cambia el nivel.
      - Laten suave mientras ningun policia esta cerca (la busqueda va bajando).
    Respeta /hud, el mapa abierto y rp:hudHidden, igual que rp_hud.
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))
local MARGIN = math.floor(22 * s)
local enabled = true
local shown, changedAt = 0, 0

local FILL = { 245, 165, 36 }
local EMPTY = tocolor(255, 255, 255, 45)
local SHADOW = tocolor(0, 0, 0, 150)

-- Estrella de 5 puntas centrada en (cx, cy)
local function star(cx, cy, r, color)
    local pts = {}
    for i = 0, 9 do
        local a = math.rad(-90 + i * 36)
        local rr = (i % 2 == 0) and r or r * 0.45
        pts[#pts + 1] = { cx + math.cos(a) * rr, cy + math.sin(a) * rr }
    end
    local verts = {}
    for i = 1, 10 do
        local p, q = pts[i], pts[i % 10 + 1]
        verts[#verts + 1] = { cx, cy, color }
        verts[#verts + 1] = { p[1], p[2], color }
        verts[#verts + 1] = { q[1], q[2], color }
    end
    dxDrawPrimitive("trianglelist", false, unpack(verts))
end

-- Misma posicion vertical que el bloque de hora / dinero / arma de rp_hud
local function topY()
    local y = MARGIN + dxGetFontHeight(2.2 * s, "default-bold") + 2 * s + dxGetFontHeight(1.5 * s, "default-bold") + 4 * s
    local weapon = getPedWeapon(localPlayer)
    if weapon and weapon ~= 0 then y = y + dxGetFontHeight(1.0 * s, "default-bold") + 4 * s end
    return y + 4 * s
end

local function isActive()
    return enabled and getElementData(localPlayer, "rp:characterId") and not isPlayerMapVisible()
        and not getElementData(localPlayer, "rp:hudHidden")
end

addEventHandler("onClientRender", root, function()
    local level = tonumber(getElementData(localPlayer, "rp:wanted")) or 0
    if level ~= shown then shown, changedAt = level, getTickCount() end
    if level <= 0 or not isActive() then return end

    local now = getTickCount()
    local alpha = 255
    if now - changedAt < 3000 and (now - changedAt) % 400 < 180 then
        alpha = 40
    elseif getElementData(localPlayer, "rp:wantedLost") then
        alpha = 150 + math.sin(now / 260) * 100
    end

    local r = 11 * s
    local gap = r * 2.25
    local cy = topY() + r
    local right = screenW - MARGIN - r
    for i = 1, WANTED.MAX_LEVEL do
        -- la 1 a la derecha, como se llenan de derecha a izquierda
        local cx = right - (i - 1) * gap
        star(cx + 1.5, cy + 1.5, r, SHADOW)
        if i <= level then
            star(cx, cy, r, tocolor(FILL[1], FILL[2], FILL[3], alpha))
        else
            star(cx, cy, r * 0.82, EMPTY)
        end
    end
end)

addCommandHandler("hud", function() enabled = not enabled end)
