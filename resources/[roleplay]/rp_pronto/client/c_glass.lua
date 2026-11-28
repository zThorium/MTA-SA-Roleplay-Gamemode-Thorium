--[[
    rp_pronto · vidrio de la tienda (cliente)

    El vidrio NO es un modelo de GTA: los triángulos de las vidrieras (c_glass_data.lua, generado por
    tools/build_pronto.py) se dibujan cada cuadro con dxDrawPrimitive3D en la etapa "prefx", después del mundo y con
    profundidad. Como modelo, GTA no garantiza el orden entre un objeto con alfa y los edificios (ver skill mapeado-3d).

    El tinte sigue la hora: claro de día y cálido de noche (el interior está encendido).
]]

local C = PRONTO
local G = C.GLASS
local verts = {}        -- { x, y, z, color } por vértice
local lastColor

local function lerp(a, b, t) return a + (b - a) * t end

-- 0 de día, 1 de noche, con transición al amanecer y al atardecer
local function nightFactor()
    local h, m = getTime()
    local t = h + m / 60
    local d0, d1, n0, n1 = G.DAWN[1], G.DAWN[2], G.DUSK[1], G.DUSK[2]
    if t >= d1 and t <= n0 then return 0 end
    if t > n0 and t < n1 then return (t - n0) / (n1 - n0) end
    if t > d0 and t < d1 then return 1 - (t - d0) / (d1 - d0) end
    return 1
end

local function currentColor()
    local k = nightFactor()
    local c = {}
    for i = 1, 4 do c[i] = math.floor(lerp(G.DAY[i], G.NIGHT[i], k) + 0.5) end
    return tocolor(c[1], c[2], c[3], c[4])
end

local function build(color)
    verts = {}
    local d = PRONTO_GLASS
    for i = 1, #d, 3 do
        verts[#verts + 1] = { d[i], d[i + 1], d[i + 2], color }
    end
    lastColor = color
end

local function draw()
    if getElementInterior(localPlayer) ~= 0 then return end
    local cx, cy = getCameraMatrix()
    local o = C.ORIGIN
    if (cx - o.x) ^ 2 + (cy - o.y) ^ 2 > G.DRAW_DISTANCE ^ 2 then return end
    local color = currentColor()
    if color ~= lastColor then build(color) end
    dxDrawPrimitive3D("trianglelist", "prefx", unpack(verts))
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    if type(PRONTO_GLASS) ~= "table" or #PRONTO_GLASS == 0 then
        outputDebugString("[rp_pronto] falta c_glass_data.lua (vidrio)", 2)
        return
    end
    build(currentColor())
    addEventHandler("onClientRender", root, draw)
end)
