--[[
    rp_hud / c_wanted.lua
    Estrellas de busqueda al estilo de GTA San Andreas: arriba a la derecha,
    debajo del dinero (y del arma), 6 estrellas alineadas a la derecha.
      - Las ganadas son doradas con borde negro; las que faltan, oscuras.
      - Parpadean unos segundos cuando cambia el nivel.
      - Laten suave mientras ningun policia esta cerca (la busqueda va bajando).
    El nivel lo pone rp_wanted en el elementData "rp:wanted" (0-6) y
    "rp:wantedLost". Las estrellas se dibujan con primitivas (arte propio).
    Respeta /hud, el mapa abierto y rp:hudHidden, igual que c_hud.lua.
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))
local MARGIN = math.floor(22 * s)
local MAX_STARS = 6
local enabled = true
local shown, changedAt = 0, 0

local OUTLINE = tocolor(0, 0, 0, 230)
local OFF = tocolor(20, 20, 24, 170)

-- Estrella de 5 puntas centrada en (cx, cy)
local function star(cx, cy, r, color)
    local pts = {}
    for i = 0, 9 do
        local a = math.rad(-90 + i * 36)
        local rr = (i % 2 == 0) and r or r * 0.46
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

-- Misma altura que el bloque hora / dinero / arma de c_hud.lua
local function topY()
    local y = MARGIN + dxGetFontHeight(2.2 * s, "default-bold") + 2 * s + dxGetFontHeight(1.5 * s, "default-bold") + 4 * s
    local weapon = getPedWeapon(localPlayer)
    if weapon and weapon ~= 0 then y = y + dxGetFontHeight(1.0 * s, "default-bold") + 4 * s end
    return y + 6 * s
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
    local visible, alpha = true, 255
    if now - changedAt < 4000 then
        visible = (now - changedAt) % 500 < 300          -- parpadeo al cambiar de nivel
    elseif getElementData(localPlayer, "rp:wantedLost") then
        alpha = 170 + math.sin(now / 260) * 85             -- sin policia cerca
    end

    local r = 13 * s
    local gap = r * 2.15
    local cy = topY() + r
    local right = screenW - MARGIN - r
    for i = 1, MAX_STARS do
        local cx = right - (MAX_STARS - i) * gap
        local on = (MAX_STARS - i) < level                -- se llenan de derecha a izquierda
        star(cx, cy, r + 2.2 * s, OUTLINE)
        if on and visible then
            star(cx, cy, r, tocolor(232, 168, 32, alpha))
            star(cx - r * 0.12, cy - r * 0.12, r * 0.55, tocolor(255, 214, 110, alpha * 0.55))
        else
            star(cx, cy, r, OFF)
        end
    end
end)

addCommandHandler("hud", function() enabled = not enabled end)
