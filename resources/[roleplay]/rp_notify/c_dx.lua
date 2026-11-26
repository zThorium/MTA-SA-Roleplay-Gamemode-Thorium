--[[
    c_dx.lua · formas dx con antialiasing (copia idéntica en rp_notify, rp_chat y rp_nametags)

    dxDrawPrimitive y dxDrawLine de MTA no suavizan los bordes: toda diagonal o curva sale
    en "dientes de sierra". Aquí cada forma lleva alrededor un borde de 1 px que pasa de su
    color a transparente (feathering, como NanoVG), así el borde queda suave a cualquier escala.

        DX.circle(cx, cy, r, color, postGUI)
        DX.ring(cx, cy, r, thick, a0, a1, color, postGUI)       -- arco con grosor; grados, -90 = arriba
        DX.line(x1, y1, x2, y2, width, color, postGUI, caps)    -- caps = extremos redondos
        DX.poly({ {x, y, color}, ... }, postGUI)                -- polígono convexo, color por vértice
        DX.roundRect(x, y, w, h, r, color, postGUI)
        DX.fade(color)                                          -- el mismo color con alfa 0

    Si cambias este archivo, cópialo igual a los otros dos recursos.
]]

DX = {}
local F = 0.5   -- medio píxel hacia dentro y medio hacia fuera de cada borde

local cos, sin, rad, sqrt, max, min = math.cos, math.sin, math.rad, math.sqrt, math.max, math.min

function DX.fade(c)
    if c < 0 then c = c + 4294967296 end
    return c % 16777216
end

local function segments(r, span)
    return max(6, min(64, math.floor(r * 0.9 * span / 360 + 6)))
end

-- Banda entre dos radios: color en r1, color2 en r2
local function band(cx, cy, r1, r2, a0, a1, c1, c2, postGUI, seg)
    local v = {}
    for i = 0, seg do
        local a = rad(a0 + (a1 - a0) * i / seg)
        local co, si = cos(a), sin(a)
        v[#v + 1] = { cx + co * r1, cy + si * r1, c1 }
        v[#v + 1] = { cx + co * r2, cy + si * r2, c2 }
    end
    dxDrawPrimitive("trianglestrip", postGUI, unpack(v))
end

local function sector(cx, cy, r, a0, a1, color, postGUI, seg)
    local v = { { cx, cy, color } }
    for i = 0, seg do
        local a = rad(a0 + (a1 - a0) * i / seg)
        v[#v + 1] = { cx + cos(a) * r, cy + sin(a) * r, color }
    end
    dxDrawPrimitive("trianglefan", postGUI, unpack(v))
end

function DX.circle(cx, cy, r, color, postGUI)
    if r <= 0 then return end
    local seg = segments(r, 360)
    if r > F then sector(cx, cy, r - F, 0, 360, color, postGUI, seg) end
    band(cx, cy, max(0, r - F), r + F, 0, 360, color, DX.fade(color), postGUI, seg)
end

function DX.ring(cx, cy, r, thick, a0, a1, color, postGUI)
    if a1 - a0 <= 0.5 or r <= 0 then return end
    local seg = segments(r, a1 - a0)
    local ri = max(0, r - thick)
    local t = DX.fade(color)
    local outerIn, innerIn
    if thick > 2 * F then
        band(cx, cy, ri + F, r - F, a0, a1, color, color, postGUI, seg)   -- núcleo sólido
        outerIn, innerIn = r - F, ri + F
    else
        outerIn = (ri + r) / 2
        innerIn = outerIn
    end
    band(cx, cy, outerIn, r + F, a0, a1, color, t, postGUI, seg)
    band(cx, cy, innerIn, max(0, ri - F), a0, a1, color, t, postGUI, seg)
end

function DX.line(x1, y1, x2, y2, width, color, postGUI, caps)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local nx, ny = -dy / len, dx / len
    local h = width / 2
    local hi, ho = max(0, h - F), h + F
    local t = DX.fade(color)
    dxDrawPrimitive("trianglestrip", postGUI,
        { x1 + nx * ho, y1 + ny * ho, t }, { x2 + nx * ho, y2 + ny * ho, t },
        { x1 + nx * hi, y1 + ny * hi, color }, { x2 + nx * hi, y2 + ny * hi, color },
        { x1 - nx * hi, y1 - ny * hi, color }, { x2 - nx * hi, y2 - ny * hi, color },
        { x1 - nx * ho, y1 - ny * ho, t }, { x2 - nx * ho, y2 - ny * ho, t })
    if caps then
        DX.circle(x1, y1, h, color, postGUI)
        DX.circle(x2, y2, h, color, postGUI)
    end
end

-- Polígono convexo: { {x, y, color}, ... } en orden (horario o antihorario)
function DX.poly(pts, postGUI)
    local n = #pts
    if n < 3 then return end
    local cx, cy = 0, 0
    for i = 1, n do cx, cy = cx + pts[i][1], cy + pts[i][2] end
    cx, cy = cx / n, cy / n
    dxDrawPrimitive("trianglefan", postGUI, unpack(pts))
    for i = 1, n do
        local a, b = pts[i], pts[i % n + 1]
        local ex, ey = b[1] - a[1], b[2] - a[2]
        local len = sqrt(ex * ex + ey * ey)
        if len > 0.01 then
            local nx, ny = -ey / len, ex / len
            -- La normal tiene que apuntar hacia fuera (lejos del centro)
            if (a[1] - cx) * nx + (a[2] - cy) * ny < 0 then nx, ny = -nx, -ny end
            local o = 2 * F
            dxDrawPrimitive("trianglestrip", postGUI,
                { a[1], a[2], a[3] }, { b[1], b[2], b[3] },
                { a[1] + nx * o, a[2] + ny * o, DX.fade(a[3]) }, { b[1] + nx * o, b[2] + ny * o, DX.fade(b[3]) })
        end
    end
end

function DX.roundRect(x, y, w, h, r, color, postGUI)
    if w <= 0 or h <= 0 then return end
    r = max(0, min(r, w / 2, h / 2))
    local t = DX.fade(color)
    -- Cuerpo
    dxDrawRectangle(x + r, y, w - 2 * r, h, color, postGUI)
    if r > 0 then
        dxDrawRectangle(x, y + r, r, h - 2 * r, color, postGUI)
        dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color, postGUI)
    end
    -- Bordes rectos suavizados
    local o = 2 * F
    dxDrawPrimitive("trianglestrip", postGUI, { x + r, y, color }, { x + w - r, y, color }, { x + r, y - o, t }, { x + w - r, y - o, t })
    dxDrawPrimitive("trianglestrip", postGUI, { x + r, y + h, color }, { x + w - r, y + h, color }, { x + r, y + h + o, t }, { x + w - r, y + h + o, t })
    dxDrawPrimitive("trianglestrip", postGUI, { x, y + r, color }, { x, y + h - r, color }, { x - o, y + r, t }, { x - o, y + h - r, t })
    dxDrawPrimitive("trianglestrip", postGUI, { x + w, y + r, color }, { x + w, y + h - r, color }, { x + w + o, y + r, t }, { x + w + o, y + h - r, t })
    -- Esquinas
    if r > 0 then
        local seg = segments(r, 90)
        local corners = { { x + r, y + r, 180 }, { x + w - r, y + r, 270 }, { x + w - r, y + h - r, 0 }, { x + r, y + h - r, 90 } }
        for _, c in ipairs(corners) do
            sector(c[1], c[2], r, c[3], c[3] + 90, color, postGUI, seg)
            band(c[1], c[2], r, r + o, c[3], c[3] + 90, color, t, postGUI, seg)
        end
    end
end
