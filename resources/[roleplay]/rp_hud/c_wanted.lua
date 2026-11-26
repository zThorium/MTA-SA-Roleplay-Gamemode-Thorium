--[[
    rp_hud / c_wanted.lua
    Estrellas de busqueda al estilo de GTA San Andreas: arriba a la derecha,
    debajo del dinero, el banco y el arma (c_hud.lua deja la altura en Hud.starsY),
    6 estrellas alineadas a la derecha.
      - Las ganadas son doradas con borde negro; las que faltan, oscuras.
      - Al ganar una, la nueva rebota con una onda dorada y suena un aviso.
      - Parpadean unos segundos cuando cambia el nivel.
      - Laten suave mientras ningun policia esta cerca (la busqueda va bajando).
    El nivel lo pone rp_wanted en el elementData "rp:wanted" (0-6) y
    "rp:wantedLost". Las estrellas se dibujan con primitivas (arte propio).
    Respeta /hud, setHudHidden, el mapa abierto y rp:hudHidden, igual que c_hud.lua.
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))
local MARGIN = math.floor(22 * s)
local MAX_STARS = 6
local shown, changedAt, gained = 0, 0, false

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

local function topY()
    if Hud.starsY then return Hud.starsY end
    return MARGIN + 110 * s   -- antes del primer frame de c_hud
end

addEventHandler("onClientRender", root, function()
    local level = tonumber(getElementData(localPlayer, "rp:wanted")) or 0
    if level ~= shown then
        gained = level > shown
        if gained and Hud.isActive and Hud.isActive() then Hud.sound("critical", 1500) end
        shown, changedAt = level, getTickCount()
    end
    if level <= 0 or not (Hud.isActive and Hud.isActive()) then return end

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
        local rr = r
        if gained and (MAX_STARS - i) == level - 1 and now - changedAt < 700 then
            local k = (now - changedAt) / 700
            rr = r * (1 + 0.6 * math.sin(k * math.pi) * (1 - k))
            dxDrawCircle(cx, cy, r * (1.2 + 1.8 * k), 0, 360, tocolor(255, 214, 110, 170 * (1 - k)), tocolor(255, 214, 110, 0), 24)
            visible = true
        end
        star(cx, cy, rr + 2.2 * s, OUTLINE)
        if on and visible then
            star(cx, cy, rr, tocolor(232, 168, 32, alpha))
            star(cx - rr * 0.12, cy - rr * 0.12, rr * 0.55, tocolor(255, 214, 110, alpha * 0.55))
        else
            star(cx, cy, rr, OFF)
        end
    end
    Hud.setRect("wanted", right - (MAX_STARS - 1) * gap - r - 4 * s, cy - r - 4 * s, (MAX_STARS - 1) * gap + 2 * r + 8 * s, 2 * r + 8 * s)
end)
