--[[
    rp_rides / c_graph.lua
    Red vial de todo San Andreas (la misma de rp_citizens, con los cambios del editor)
    y busqueda de rutas A* sobre el grafo dirigido de carriles.
]]

local N, L, LANES, OFF = nil, nil, nil, nil
local grid = nil
local CELL = 100

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

function getRoadGraphData()
    if not loadRoadGraph() then return nil end
    return N, L, LANES
end

function nodePosition(i)
    return N[i * 3 - 2], N[i * 3 - 1], N[i * 3]
end

local function laneInfo(a, b)
    local list = L[a]
    if list then
        for k = 1, #list do
            if list[k] == b then
                return (LANES[a] and LANES[a][k]) or 1, (OFF[a] and OFF[a][k]) or 2.5
            end
        end
    end
    return 0, 2.5
end

local function canDrive(a, b) return laneInfo(a, b) > 0 end

-- Nodo con salida mas cercano a (x, y); busca en anillos crecientes
function nearestRoadNode(x, y, maxRing)
    if not loadRoadGraph() then return nil end
    local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
    local best, bestD = nil, math.huge
    for ring = 1, maxRing or 4 do
        for ox = -ring, ring do
            for oy = -ring, ring do
                local cell = grid[(cx + ox) * 1000 + (cy + oy)]
                if cell then
                    for _, i in ipairs(cell) do
                        local d = (N[i * 3 - 2] - x) ^ 2 + (N[i * 3 - 1] - y) ^ 2
                        if d < bestD then best, bestD = i, d end
                    end
                end
            end
        end
        if best then return best end
    end
    return best
end

-- Nodo de la calle a [minD, maxD] de (x, y), con un enlace transitable (para que aparezca el auto)
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

-- Binary heap para A*
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

-- A* (heuristica: distancia en linea recta). Devuelve la lista de nodos start..goal o nil.
function findRoadRoute(start, goal, maxExpansions)
    if not loadRoadGraph() or not start or not goal then return nil end
    if start == goal then return { start } end
    local gx, gy = nodePosition(goal)
    local open = { n = 0 }
    local cost, parent, closed = { [start] = 0 }, {}, {}
    push(open, start, 0)
    local expansions = 0
    while open.n > 0 do
        local cur = pop(open)
        if cur == goal then
            local route = { cur }
            while parent[cur] do
                cur = parent[cur]
                table.insert(route, 1, cur)
            end
            return route
        end
        if not closed[cur] then
            closed[cur] = true
            expansions = expansions + 1
            if expansions > (maxExpansions or 6000) then return nil end
            local cx, cy = nodePosition(cur)
            for _, n in ipairs(L[cur] or {}) do
                if not closed[n] and canDrive(cur, n) then
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

-- Puntos de conduccion por el carril derecho de cada tramo (cada ~8 m)
function routeWaypoints(route)
    local wp = {}
    for i = 1, #route - 1 do
        local a, b = route[i], route[i + 1]
        local ax, ay, az = nodePosition(a)
        local bx, by, bz = nodePosition(b)
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.5 then
            dx, dy = dx / len, dy / len
            local _, off = laneInfo(a, b)
            local ox, oy = dy * off, -dx * off          -- derecha del sentido de marcha
            local steps = math.max(1, math.floor(len / 8))
            for s = (i == 1) and 0 or 1, steps do
                local t = s / steps
                wp[#wp + 1] = { ax + dx * len * t + ox, ay + dy * len * t + oy, az + (bz - az) * t }
            end
        end
    end
    return wp
end

-- Punto inicial del carril a -> b y su rumbo (para que aparezca el auto)
function laneStartPoint(a, b)
    local ax, ay, az = nodePosition(a)
    local bx, by = nodePosition(b)
    local dx, dy = bx - ax, by - ay
    local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    dx, dy = dx / len, dy / len
    local _, off = laneInfo(a, b)
    return ax + dy * off, ay - dx * off, az, -math.deg(math.atan2(dx, dy))
end
