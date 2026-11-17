--[[
    rp_emergency / c_offroad.lua
    Ruta propia fuera de la red vial: cuando el paciente no esta junto a una calle
    (parque, plaza, estacionamiento, patio...), la ambulancia sale de la calle y busca
    su propio camino hasta el, como en la vida real.

    A* sobre una rejilla de 2,5 m alrededor del tramo. Cada celda se evalua solo si
    el A* la visita: debe tener suelo (sin escalones de mas de 1,1 m respecto a la
    anterior), espacio para la ambulancia (sin muros, edificios ni objetos a 1 m de
    altura en 1,4 m a la redonda) y linea libre con la celda anterior. Los vehiculos
    se ignoran al planear (se mueven): los esquiva el conductor con sus sensores.
    Despues se suaviza la ruta uniendo puntos con linea libre y ancha.
]]

local CELL = 2.5
local MAX_STEP = 1.1
local MAX_EXPANSIONS = 2000

local function groundZ(x, y, nearZ)
    local hit, _, _, gz = processLineOfSight(x, y, nearZ + 6, x, y, nearZ - 10, true, false, false, true, false, true, false, false)
    if hit then return gz end
    local g = getGroundPosition(x, y, nearZ + 6)
    if g and g ~= 0 then return g end
end

local function solid(x1, y1, z1, x2, y2, z2)
    return not isLineOfSightClear(x1, y1, z1, x2, y2, z2, true, false, false, true, false, false, false)
end

-- Espacio para la ambulancia en (x, y) apoyada a altura z
local function roomy(x, y, z)
    local h = z + 1.0
    return not (solid(x, y, h, x + 1.4, y, h) or solid(x, y, h, x - 1.4, y, h)
        or solid(x, y, h, x, y + 1.4, h) or solid(x, y, h, x, y - 1.4, h))
end

-- Tramo recto transitable y con el ancho de la ambulancia (centro y ambos costados)
function wideClear(ax, ay, az, bx, by, bz)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return true end
    local px, py = -dy / len * 1.2, dx / len * 1.2
    for _, s in ipairs({ 0, 1, -1 }) do
        if solid(ax + px * s, ay + py * s, az + 0.9, bx + px * s, by + py * s, bz + 0.9) then return false end
    end
    -- suelo continuo cada 3 m (sin precipicios ni escalones grandes)
    local lastZ = az
    local steps = math.max(1, math.floor(len / 3))
    for i = 1, steps do
        local t = i / steps
        local gz = groundZ(ax + dx * t, ay + dy * t, lastZ)
        if not gz or math.abs(gz - lastZ) > MAX_STEP * 1.2 then return false end
        lastZ = gz
    end
    return true
end

-- Puntos desde (sx, sy, sz) hasta quedar a stopDist del destino. Cada punto:
-- { x, y, z, 30 (giro: va despacio), nil, true (fuera de la red vial) }. nil si no hay camino.
function offroadPath(sx, sy, sz, tx, ty, tz, stopDist)
    stopDist = stopDist or 7
    local total = getDistanceBetweenPoints2D(sx, sy, tx, ty)
    if total <= stopDist then return {} end
    local ex, ey = tx + (sx - tx) / total * stopDist, ty + (sy - ty) / total * stopDist
    local ez = groundZ(ex, ey, tz or sz) or (tz or sz)

    local function finish(points)
        local out = {}
        for _, p in ipairs(points) do out[#out + 1] = { p[1], p[2], p[3], 30, nil, true } end
        return out
    end

    -- Linea recta libre: la mas rapida
    if wideClear(sx, sy, sz, ex, ey, ez) then
        local pts = {}
        local n = math.max(1, math.floor(total / 6))
        for i = 1, n do
            local t = i / n
            pts[#pts + 1] = { sx + (ex - sx) * t, sy + (ey - sy) * t, sz + (ez - sz) * t }
        end
        return finish(pts)
    end

    -- A* en rejilla (celdas evaluadas bajo demanda)
    local cells = {}            -- [key] = z del suelo o false
    local function key(ix, iy) return ix * 100000 + iy end
    local function center(ix, iy) return sx + ix * CELL, sy + iy * CELL end
    local limit = total + 45
    local mx, my = (sx + tx) / 2, (sy + ty) / 2

    local startKey = key(0, 0)
    cells[startKey] = sz
    local open = { n = 0 }
    local function push(item, f)
        open.n = open.n + 1
        local i = open.n
        open[i] = { item, f }
        while i > 1 do
            local p = math.floor(i / 2)
            if open[p][2] <= open[i][2] then break end
            open[p], open[i] = open[i], open[p]
            i = p
        end
    end
    local function pop()
        if open.n == 0 then return nil end
        local top = open[1]
        open[1] = open[open.n]; open[open.n] = nil; open.n = open.n - 1
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if l <= open.n and open[l][2] < open[m][2] then m = l end
            if r <= open.n and open[r][2] < open[m][2] then m = r end
            if m == i then break end
            open[m], open[i] = open[i], open[m]
            i = m
        end
        return top[1]
    end

    local cost, parent, closed, pos = { [startKey] = 0 }, {}, {}, { [startKey] = { 0, 0 } }
    push(startKey, total)
    local expansions, goal = 0, nil
    while open.n > 0 do
        local cur = pop()
        if not closed[cur] then
            closed[cur] = true
            local ix, iy = pos[cur][1], pos[cur][2]
            local cx, cy = center(ix, iy)
            local cz = cells[cur]
            if getDistanceBetweenPoints2D(cx, cy, tx, ty) <= stopDist + CELL then goal = cur break end
            expansions = expansions + 1
            if expansions > MAX_EXPANSIONS then break end
            for ox = -1, 1 do
                for oy = -1, 1 do
                    if ox ~= 0 or oy ~= 0 then
                        local nx, ny = ix + ox, iy + oy
                        local k = key(nx, ny)
                        if not closed[k] then
                            local wx, wy = center(nx, ny)
                            if getDistanceBetweenPoints2D(wx, wy, mx, my) <= limit / 2 + 10 then
                                if cells[k] == nil then
                                    local gz = groundZ(wx, wy, cz)
                                    cells[k] = (gz and math.abs(gz - cz) <= MAX_STEP and roomy(wx, wy, gz)) and gz or false
                                end
                                local nz = cells[k]
                                if nz and not solid(cx, cy, cz + 0.9, wx, wy, nz + 0.9) then
                                    local g = cost[cur] + CELL * ((ox ~= 0 and oy ~= 0) and 1.414 or 1)
                                    if not cost[k] or g < cost[k] then
                                        cost[k], parent[k], pos[k] = g, cur, { nx, ny }
                                        push(k, g + getDistanceBetweenPoints2D(wx, wy, tx, ty))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not goal then return nil end

    -- Reconstruye y suaviza (une puntos lejanos si hay linea libre y ancha)
    local raw = {}
    local k = goal
    while k do
        local cx, cy = center(pos[k][1], pos[k][2])
        table.insert(raw, 1, { cx, cy, cells[k] })
        k = parent[k]
    end
    local pts, a = {}, 1
    while a < #raw do
        local b = #raw
        while b > a + 1 and not wideClear(raw[a][1], raw[a][2], raw[a][3], raw[b][1], raw[b][2], raw[b][3]) do b = b - 1 end
        -- puntos intermedios cada ~6 m para el seguimiento
        local p, q = raw[a], raw[b]
        local len = getDistanceBetweenPoints2D(p[1], p[2], q[1], q[2])
        local n = math.max(1, math.floor(len / 6))
        for i = 1, n do
            local t = i / n
            pts[#pts + 1] = { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t }
        end
        a = b
    end
    return finish(pts)
end
