--[[
    rp_emergency / c_offroad.lua
    Busqueda de caminos fuera de la red vial, con la colision real del mapa (solo el
    cliente la tiene; el servidor no puede hacer raycasts):

      offroadPath  -> la ambulancia sale de la calle y llega hasta el paciente
                      (parque, plaza, estacionamiento...) con su ancho.
      footPath     -> camino a pie de un paramedico (rodea autos, muros, postes,
                      bancos, la propia ambulancia) hasta su punto.

    Mismo algoritmo para ambos: primero linea recta si esta libre; si no, A* sobre una
    rejilla cuyas celdas se evaluan solo cuando el A* las visita (suelo, escalon maximo,
    holgura a la altura del cuerpo y linea libre con la celda anterior). Despues se
    suaviza uniendo puntos con linea libre (y con el ancho necesario).
]]

local function groundZ(x, y, nearZ)
    local hit, _, _, gz = processLineOfSight(x, y, nearZ + 3, x, y, nearZ - 6, true, false, false, true, false, true, false, false)
    if hit then return gz end
    local g = getGroundPosition(x, y, nearZ + 3)
    if g and g ~= 0 then return g end
end

-- checkVehicles: los autos estacionados cuentan como obstaculo a pie, no al planear la ambulancia
local function solid(x1, y1, z1, x2, y2, z2, vehicles, ignored)
    return not isLineOfSightClear(x1, y1, z1, x2, y2, z2, true, vehicles, false, true, false, false, false, ignored)
end

local function heap()
    local h = { n = 0 }
    function h.push(item, f)
        h.n = h.n + 1
        local i = h.n
        h[i] = { item, f }
        while i > 1 do
            local p = math.floor(i / 2)
            if h[p][2] <= h[i][2] then break end
            h[p], h[i] = h[i], h[p]
            i = p
        end
    end
    function h.pop()
        if h.n == 0 then return nil end
        local top = h[1]
        h[1] = h[h.n]; h[h.n] = nil; h.n = h.n - 1
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if l <= h.n and h[l][2] < h[m][2] then m = l end
            if r <= h.n and h[r][2] < h[m][2] then m = r end
            if m == i then break end
            h[m], h[i] = h[i], h[m]
            i = m
        end
        return top[1]
    end
    return h
end

--[[ o = {
    cell, room (holgura), width (medio ancho del pasillo), height (altura de las pruebas
    sobre el suelo), step (escalon maximo entre celdas), vehicles (autos = obstaculo),
    stop (m antes del destino), maxExp, ignored (elemento a ignorar en los rayos)
} ]]
local function lineClear(o, ax, ay, az, bx, by, bz)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.3 then return true end
    local px, py = -dy / len * o.width, dx / len * o.width
    for _, s in ipairs({ 0, 1, -1 }) do
        if solid(ax + px * s, ay + py * s, az + o.height, bx + px * s, by + py * s, bz + o.height, o.vehicles, o.ignored) then
            return false
        end
    end
    local lastZ = az
    local steps = math.max(1, math.floor(len / (o.cell * 1.2)))
    for i = 1, steps do
        local t = i / steps
        local gz = groundZ(ax + dx * t, ay + dy * t, lastZ)
        if not gz or math.abs(gz - lastZ) > o.step then return false end
        lastZ = gz
    end
    return true
end

local function roomy(o, x, y, z)
    local h, r = z + o.height, o.room
    return not (solid(x, y, h, x + r, y, h, o.vehicles, o.ignored) or solid(x, y, h, x - r, y, h, o.vehicles, o.ignored)
        or solid(x, y, h, x, y + r, h, o.vehicles, o.ignored) or solid(x, y, h, x, y - r, h, o.vehicles, o.ignored))
end

-- Devuelve una lista de { x, y, zSuelo } desde (sx, sy) (sin incluirlo) hasta quedar a o.stop del destino,
-- o nil si no hay camino.
local function gridPath(o, sx, sy, sz, tx, ty, tz)
    local total = getDistanceBetweenPoints2D(sx, sy, tx, ty)
    if total <= o.stop + 0.2 then return {} end
    local ex, ey = tx, ty
    if o.stop > 0 then ex, ey = tx + (sx - tx) / total * o.stop, ty + (sy - ty) / total * o.stop end
    local ez = groundZ(ex, ey, tz or sz) or (tz or sz)

    local function densify(list)
        local out, px, py, pz = {}, sx, sy, sz
        for _, p in ipairs(list) do
            local len = getDistanceBetweenPoints2D(px, py, p[1], p[2])
            local n = math.max(1, math.floor(len / o.spacing))
            for i = 1, n do
                local t = i / n
                out[#out + 1] = { px + (p[1] - px) * t, py + (p[2] - py) * t, pz + (p[3] - pz) * t }
            end
            px, py, pz = p[1], p[2], p[3]
        end
        return out
    end

    if lineClear(o, sx, sy, sz, ex, ey, ez) then return densify({ { ex, ey, ez } }) end

    local C = o.cell
    local cells, pos = { [0] = sz }, { [0] = { 0, 0 } }
    local function key(ix, iy) return ix * 100000 + iy end
    local cost, parent, closed = { [0] = 0 }, {}, {}
    local mx, my, radius = (sx + tx) / 2, (sy + ty) / 2, total / 2 + 25
    local open = heap()
    open.push(0, total)
    local expansions, goal = 0, nil
    while open.n > 0 do
        local cur = open.pop()
        if not closed[cur] then
            closed[cur] = true
            local ix, iy = pos[cur][1], pos[cur][2]
            local cx, cy, cz = sx + ix * C, sy + iy * C, cells[cur]
            if getDistanceBetweenPoints2D(cx, cy, tx, ty) <= o.stop + C then goal = cur break end
            expansions = expansions + 1
            if expansions > o.maxExp then break end
            for ox = -1, 1 do
                for oy = -1, 1 do
                    if ox ~= 0 or oy ~= 0 then
                        local nx, ny = ix + ox, iy + oy
                        local k = key(nx, ny)
                        local wx, wy = sx + nx * C, sy + ny * C
                        if not closed[k] and getDistanceBetweenPoints2D(wx, wy, mx, my) <= radius then
                            if cells[k] == nil then
                                local gz = groundZ(wx, wy, cz)
                                cells[k] = (gz and math.abs(gz - cz) <= o.step and roomy(o, wx, wy, gz)) and gz or false
                            end
                            local nz = cells[k]
                            if nz and not solid(cx, cy, cz + o.height, wx, wy, nz + o.height, o.vehicles, o.ignored) then
                                local g = cost[cur] + C * ((ox ~= 0 and oy ~= 0) and 1.414 or 1)
                                if not cost[k] or g < cost[k] then
                                    cost[k], parent[k], pos[k] = g, cur, { nx, ny }
                                    open.push(k, g + getDistanceBetweenPoints2D(wx, wy, tx, ty))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not goal then return nil end

    local raw, k = {}, goal
    while k do
        table.insert(raw, 1, { sx + pos[k][1] * C, sy + pos[k][2] * C, cells[k] })
        k = parent[k]
    end
    -- Suavizado: desde cada punto salta al mas lejano con linea libre
    local smooth, a = {}, 1
    while a < #raw do
        local b = #raw
        while b > a + 1 and not lineClear(o, raw[a][1], raw[a][2], raw[a][3], raw[b][1], raw[b][2], raw[b][3]) do b = b - 1 end
        smooth[#smooth + 1] = raw[b]
        a = b
    end
    return densify(smooth)
end

local VEHICLE = { cell = 2.5, room = 1.4, width = 1.2, height = 0.9, step = 1.1, vehicles = false, maxExp = 2000, spacing = 6 }
local FOOT = { cell = 1.0, room = 0.35, width = 0.3, height = 0.8, step = 0.75, vehicles = true, maxExp = 1200, spacing = 1.5 }

-- Ambulancia: puntos { x, y, z, 30 (va despacio), nil, true (fuera de la calle) }
function offroadPath(sx, sy, sz, tx, ty, tz, stopDist)
    local o = {}
    for k, v in pairs(VEHICLE) do o[k] = v end
    o.stop = stopDist or 7
    local pts = gridPath(o, sx, sy, sz, tx, ty, tz)
    if not pts then return nil end
    local out = {}
    for _, p in ipairs(pts) do out[#out + 1] = { p[1], p[2], p[3], 30, nil, true } end
    return out
end

-- Paramedico: puntos { x, y, zSuelo } desde su posicion hasta (tx, ty). Si no hay camino
-- (o el destino esta encerrado), linea recta: el ped no atraviesa nada fisicamente, solo
-- sigue los puntos, asi que nunca es peor que lo de antes.
function footPath(ped, tx, ty, tz)
    local x, y, z = getElementPosition(ped)
    local gz = groundZ(x, y, z - 0.5) or (z - 1)
    local o = {}
    for k, v in pairs(FOOT) do o[k] = v end
    o.stop, o.ignored = 0, ped
    local tgz = groundZ(tx, ty, tz) or (tz - 1)
    local pts = gridPath(o, x, y, gz, tx, ty, tgz)
    if not pts or #pts == 0 then pts = { { tx, ty, tgz } } end
    local last = pts[#pts]
    if getDistanceBetweenPoints2D(last[1], last[2], tx, ty) > 0.3 then pts[#pts + 1] = { tx, ty, tgz } end
    return pts
end
