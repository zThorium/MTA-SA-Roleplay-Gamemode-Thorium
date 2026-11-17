--[[
    rp_emergency / c_graph.lua
    Red vial de Los Santos: la misma de rp_citizens (con los cambios del editor /nodos).
    Aqui se calcula la ruta de la ambulancia con A* sobre el grafo dirigido de carriles
    (respeta sentidos y nunca da la vuelta en U en un nodo) y se convierte en puntos de
    conduccion por el carril derecho, con curvas Bezier en cada cruce, igual que el
    trafico de rp_citizens.
]]

local N, L, LANES, OFF = nil, nil, nil, nil
local grid = nil
local CELL = 100
local STEP = 6            -- m entre puntos en los tramos rectos
local DEFAULT_OFFSET = 2.5

function loadRoadGraph()
    if N then return true end
    local ok, nodes, links, lanes, offsets = pcall(function() return exports.rp_citizens:getRoadGraph() end)
    if not ok or type(nodes) ~= "table" or type(links) ~= "table" then return false end
    N, L, LANES, OFF = nodes, links, lanes or {}, offsets or {}
    grid = {}
    for i = 1, #N / 3 do
        if L[i] and #L[i] > 0 then
            local key = math.floor(N[i * 3 - 2] / CELL) * 1000 + math.floor(N[i * 3 - 1] / CELL)
            grid[key] = grid[key] or {}
            table.insert(grid[key], i)
        end
    end
    return true
end

function nodePosition(i) return N[i * 3 - 2], N[i * 3 - 1], N[i * 3] end

local function dir(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return 0, 1, 0 end
    return dx / len, dy / len, len
end

local function laneInfo(a, b)
    local list = L[a]
    if list then
        for k = 1, #list do
            if list[k] == b then
                return (LANES[a] and LANES[a][k]) or 1, (OFF[a] and OFF[a][k]) or DEFAULT_OFFSET
            end
        end
    end
    return 0, DEFAULT_OFFSET
end

local function canDrive(a, b) return laneInfo(a, b) > 0 end
local function isJunction(n) return L[n] and #L[n] >= 3 end

-- Punto del carril a -> b a t metros de a (t se limita al tramo)
local function lanePoint(a, b, t)
    local ax, ay, az = nodePosition(a)
    local bx, by, bz = nodePosition(b)
    local dx, dy, len = dir(ax, ay, bx, by)
    local _, off = laneInfo(a, b)
    t = math.max(0, math.min(len, t))
    local k = len > 0 and t / len or 0
    return ax + dx * t + dy * off, ay + dy * t - dx * off, az + (bz - az) * k, dx, dy, len
end

local function cellsAround(x, y, radius)
    local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
    local r = math.max(1, math.ceil(radius / CELL))
    local out = {}
    for ox = -r, r do
        for oy = -r, r do
            local cell = grid[(cx + ox) * 1000 + (cy + oy)]
            if cell then for _, n in ipairs(cell) do out[#out + 1] = n end end
        end
    end
    return out
end

-- Proyeccion de (x, y) sobre el carril a -> b: distancia lateral y metros desde a
local function projectOnLane(a, b, x, y)
    local ax, ay = nodePosition(a)
    local bx, by = nodePosition(b)
    local dx, dy, len = dir(ax, ay, bx, by)
    local _, off = laneInfo(a, b)
    local lx, ly = ax + dy * off, ay - dx * off
    local t = (x - lx) * dx + (y - ly) * dy
    local tc = math.max(0, math.min(len, t))
    return getDistanceBetweenPoints2D(x, y, lx + dx * tc, ly + dy * tc), t, len, dx, dy
end

function laneProject(a, b, x, y) return projectOnLane(a, b, x, y) end
function laneDrivable(a, b) return loadRoadGraph() and canDrive(a, b) end
function laneLength(a, b)
    local ax, ay = nodePosition(a)
    local bx, by = nodePosition(b)
    return getDistanceBetweenPoints2D(ax, ay, bx, by)
end

-- Nodo con salida mas cercano a (x, y)
function nearestRoadNode(x, y, maxRing)
    if not loadRoadGraph() then return nil end
    local best, bestD = nil, math.huge
    for _, i in ipairs(cellsAround(x, y, (maxRing or 2) * CELL)) do
        local d = (N[i * 3 - 2] - x) ^ 2 + (N[i * 3 - 1] - y) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return best
end

-- Tramo a -> b en el que va el vehiculo: mismo sentido que su rumbo (fx, fy) y con b
-- por delante. Devuelve a, b. Es el punto de partida de la ruta (nunca obliga a girar en U).
function laneAhead(x, y, fx, fy, radius)
    if not loadRoadGraph() then return nil end
    local best, bestB, bestScore = nil, nil, math.huge
    for _, n in ipairs(cellsAround(x, y, radius or 80)) do
        local nx, ny = nodePosition(n)
        if getDistanceBetweenPoints2D(x, y, nx, ny) < (radius or 80) then
            for _, m in ipairs(L[n] or {}) do
                if canDrive(n, m) then
                    local lateral, t, len, dx, dy = projectOnLane(n, m, x, y)
                    local aligned = dx * fx + dy * fy
                    if aligned > 0.5 and t < len - 3 then
                        local score = lateral + (1 - aligned) * 15 + (t < -5 and -t or 0)
                        if score < bestScore then best, bestB, bestScore = n, m, score end
                    end
                end
            end
        end
    end
    return best, bestB, bestScore
end

-- Carril mas cercano a un punto (donde debe detenerse la ambulancia). Devuelve a, b, t.
function laneNearest(x, y, radius)
    if not loadRoadGraph() then return nil end
    local best, bestB, bestT, bestD = nil, nil, 0, math.huge
    for _, n in ipairs(cellsAround(x, y, radius or 100)) do
        for _, m in ipairs(L[n] or {}) do
            if canDrive(n, m) then
                local lateral, t, len = projectOnLane(n, m, x, y)
                if t > -2 and t < len + 2 and lateral < bestD then best, bestB, bestT, bestD = n, m, t, lateral end
            end
        end
    end
    return best, bestB, bestT, bestD
end

-- Nodo de la calle a [minD, maxD] de (x, y) con un enlace transitable
function roadNodeAround(x, y, minD, maxD)
    if not loadRoadGraph() then return nil end
    for _ = 1, 30 do
        local angle = math.random() * math.pi * 2
        local dist = minD + math.random() * (maxD - minD)
        local n = nearestRoadNode(x + math.cos(angle) * dist, y + math.sin(angle) * dist, 1)
        if n then
            local nx, ny = nodePosition(n)
            local d = getDistanceBetweenPoints2D(x, y, nx, ny)
            if d >= minD and d <= maxD then
                for _, m in ipairs(L[n]) do
                    if canDrive(n, m) then return n, m end
                end
            end
        end
    end
end

-- Inicio del carril a -> b y su rumbo (para que aparezca la ambulancia)
function laneStartPoint(a, b)
    local x, y, z, dx, dy = lanePoint(a, b, 4)
    return x, y, z, -math.deg(math.atan2(dx, dy))
end

----------------------------------------------------------------
-- A*
----------------------------------------------------------------
local function push(h, item, f)
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

local function pop(h)
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

-- Ruta from -> start -> ... -> goal (se llega a start desde from: sin giro en U).
-- Devuelve { from, start, ..., goal } o nil.
function findRoute(from, start, goal, maxExpansions)
    if not loadRoadGraph() or not start or not goal then return nil end
    if start == goal then return { from, start } end
    local gx, gy = nodePosition(goal)
    local open = { n = 0 }
    local cost, parent, closed = { [start] = 0 }, { [start] = from }, {}
    push(open, start, 0)
    local expansions = 0
    while open.n > 0 do
        local cur = pop(open)
        if cur == goal then
            local route = { cur }
            while cur ~= start do
                cur = parent[cur]
                table.insert(route, 1, cur)
            end
            table.insert(route, 1, from)
            return route
        end
        if not closed[cur] then
            closed[cur] = true
            expansions = expansions + 1
            if expansions > (maxExpansions or 8000) then return nil end
            local cx, cy = nodePosition(cur)
            for _, n in ipairs(L[cur] or {}) do
                if not closed[n] and n ~= parent[cur] and canDrive(cur, n) then
                    local nx, ny = nodePosition(n)
                    local g = cost[cur] + getDistanceBetweenPoints2D(cx, cy, nx, ny)
                    if not cost[n] or g < cost[n] then
                        cost[n], parent[n] = g, cur
                        push(open, n, g + getDistanceBetweenPoints2D(nx, ny, gx, gy))
                    end
                end
            end
        end
    end
    return nil
end

----------------------------------------------------------------
-- Puntos de conduccion: { x, y, z, giro (grados), nodo de cruce }
----------------------------------------------------------------
local function intersect(px, py, dx, dy, qx, qy, ex, ey)
    local den = dx * ey - dy * ex
    if math.abs(den) < 0.05 then return nil end
    local t = ((qx - px) * ey - (qy - py) * ex) / den
    if t < 0 or t > 30 then return nil end
    return px + dx * t, py + dy * t
end

-- Maniobra A -> B -> C: fin del carril de entrada, curva Bezier, inicio del de salida
local function turnPoints(A, B, C)
    local ax, ay = nodePosition(A)
    local bx, by, bz = nodePosition(B)
    local cx, cy = nodePosition(C)
    local d1x, d1y, len1 = dir(ax, ay, bx, by)
    local d2x, d2y, len2 = dir(bx, by, cx, cy)
    local _, off1 = laneInfo(A, B)
    local _, off2 = laneInfo(B, C)
    local turn = math.deg(math.acos(math.max(-1, math.min(1, d1x * d2x + d1y * d2y))))
    local R = math.min(isJunction(B) and 12 or 9, len1 * 0.48, len2 * 0.48)
    local junction = isJunction(B) and B or nil
    local pts = {}
    local ex, ey = bx - d1x * R + d1y * off1, by - d1y * R - d1x * off1
    local xx, xy = bx + d2x * R + d2y * off2, by + d2y * R - d2x * off2
    pts[1] = { ex, ey, bz, 0, junction }
    if turn < 10 then
        pts[2] = { xx, xy, bz, 0, junction }
    else
        local qx, qy = intersect(ex, ey, d1x, d1y, xx, xy, -d2x, -d2y)
        if not qx then qx, qy = bx + (d1y * off1 + d2y * off2) / 2, by - (d1x * off1 + d2x * off2) / 2 end
        local steps = math.max(5, math.ceil(turn / 10))
        for i = 1, steps do
            local t = i / steps
            local u = 1 - t
            pts[#pts + 1] = { u * u * ex + 2 * u * t * qx + t * t * xx, u * u * ey + 2 * u * t * qy + t * t * xy, bz, turn, junction }
        end
    end
    return pts
end

local function straight(wp, tx, ty, tz)
    local last = wp[#wp]
    if not last then wp[1] = { tx, ty, tz, 0 } return end
    local len = getDistanceBetweenPoints2D(last[1], last[2], tx, ty)
    local n = math.max(1, math.floor(len / STEP))
    for i = 1, n do
        local t = i / n
        wp[#wp + 1] = { last[1] + (tx - last[1]) * t, last[2] + (ty - last[2]) * t, last[3] + (tz - last[3]) * t, 0 }
    end
end

-- route = { n1, n2, ..., nk }; empieza en (sx, sy) sobre el carril n1 -> n2 y termina
-- en el carril n(k-1) -> nk a stopT metros de n(k-1), pegado a la acera (curb metros extra).
function buildWaypoints(route, sx, sy, stopT, curb)
    local wp = {}
    if #route < 2 then return wp end
    local _, t0 = projectOnLane(route[1], route[2], sx, sy)
    local x, y, z = lanePoint(route[1], route[2], t0 + 2)
    wp[1] = { x, y, z, 0 }
    for i = 2, #route - 1 do
        local pts = turnPoints(route[i - 1], route[i], route[i + 1])
        straight(wp, pts[1][1], pts[1][2], pts[1][3])
        for k = 2, #pts do wp[#wp + 1] = pts[k] end
    end
    local a, b = route[#route - 1], route[#route]
    local fx, fy, fz, dx, dy, len = lanePoint(a, b, stopT or math.huge)
    if curb and curb > 0 then fx, fy = fx + dy * curb, fy - dx * curb end
    -- si la curva ya paso el punto de parada (tramo corto), no se retrocede
    local last = wp[#wp]
    if (fx - last[1]) * dx + (fy - last[2]) * dy > 1 then straight(wp, fx, fy, fz) end
    return wp, len
end
