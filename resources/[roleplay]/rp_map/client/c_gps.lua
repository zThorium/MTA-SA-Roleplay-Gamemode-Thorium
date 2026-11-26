--[[
    rp_map / client/c_gps.lua  (cliente)
    GPS con rutas por las calles reales de GTA SA (client/c_roads.lua, generado de
    data/Paths/NODES*.DAT):
      - A* sobre el grafo de calles; en coche respeta el sentido de circulacion, a pie no;
      - el calculo se reparte entre frames (corutina) para no congelar el juego;
      - solo el tramo jugador -> calle mas cercana y calle -> destino son rectos (fuera de la red no hay calle);
      - revisa el avance cada medio segundo, recalcula si te desvias o cambias entre coche y a pie,
        y avisa al llegar. Sigue funcionando con el mapa cerrado.
    La ruta se dibuja en el minimapa (exports.rp_hud:setNavRoute), en el mapa F11 y con
    una tarjeta de indicaciones arriba al centro.
]]

local N = #ROAD_XYZ / 3
local OUT = ROAD_OUT
local BOTH = {}          -- vecinos sin sentido (a pie)
local GRID, GRID_SIZE = {}, 100

local function nx(i) return ROAD_XYZ[i * 3 - 2] end
local function ny(i) return ROAD_XYZ[i * 3 - 1] end
local function nz(i) return ROAD_XYZ[i * 3] end

-- Indices auxiliares (una vez al cargar)
do
    for i = 1, N do BOTH[i] = {} end
    for i = 1, N do
        for _, j in ipairs(OUT[i]) do
            BOTH[i][j] = true
            BOTH[j][i] = true
        end
        local key = math.floor(nx(i) / GRID_SIZE) .. ":" .. math.floor(ny(i) / GRID_SIZE)
        GRID[key] = GRID[key] or {}
        table.insert(GRID[key], i)
    end
    for i = 1, N do
        local list = {}
        for j in pairs(BOTH[i]) do list[#list + 1] = j end
        BOTH[i] = list
    end
end

-- Nodo de calle mas cercano (busca en anillos de 100 m hasta maxR)
local function nearestNode(x, y, maxR, needOut)
    local gx, gy = math.floor(x / GRID_SIZE), math.floor(y / GRID_SIZE)
    local best, bestD = nil, math.huge
    for ring = 0, math.ceil((maxR or 1500) / GRID_SIZE) do
        for dx = -ring, ring do
            for dy = -ring, ring do
                if math.abs(dx) == ring or math.abs(dy) == ring then
                    for _, i in ipairs(GRID[(gx + dx) .. ":" .. (gy + dy)] or {}) do
                        if not needOut or #OUT[i] > 0 then
                            local d = (nx(i) - x) ^ 2 + (ny(i) - y) ^ 2
                            if d < bestD then best, bestD = i, d end
                        end
                    end
                end
            end
        end
        -- lo encontrado en este anillo ya es lo mas cercano posible si esta dentro del radio cubierto
        if best and math.sqrt(bestD) <= ring * GRID_SIZE then break end
    end
    return best
end

----------------------------------------------------------------
-- A* (montículo binario), cooperativo
----------------------------------------------------------------
local function heapPush(h, node, f)
    h.n = h.n + 1
    local k = h.n
    h.node[k], h.f[k] = node, f
    while k > 1 do
        local p = math.floor(k / 2)
        if h.f[p] <= h.f[k] then break end
        h.node[p], h.node[k] = h.node[k], h.node[p]
        h.f[p], h.f[k] = h.f[k], h.f[p]
        k = p
    end
end

local function heapPop(h)
    local top = h.node[1]
    h.node[1], h.f[1] = h.node[h.n], h.f[h.n]
    h.node[h.n], h.f[h.n] = nil, nil
    h.n = h.n - 1
    local k = 1
    while true do
        local l, r, m = k * 2, k * 2 + 1, k
        if l <= h.n and h.f[l] < h.f[m] then m = l end
        if r <= h.n and h.f[r] < h.f[m] then m = r end
        if m == k then break end
        h.node[m], h.node[k] = h.node[k], h.node[m]
        h.f[m], h.f[k] = h.f[k], h.f[m]
        k = m
    end
    return top
end

local STEPS_PER_FRAME = 2500

-- Devuelve lista de nodos o nil. directed = en coche (respeta sentidos)
local function astar(from, to, directed)
    local adj = directed and OUT or BOTH
    local tx, ty = nx(to), ny(to)
    local g, came, closed = { [from] = 0 }, {}, {}
    local open = { n = 0, node = {}, f = {} }
    heapPush(open, from, 0)
    local steps = 0
    while open.n > 0 do
        local cur = heapPop(open)
        if cur == to then
            local path, c = { to }, to
            while came[c] do c = came[c]; table.insert(path, 1, c) end
            return path
        end
        if not closed[cur] then
            closed[cur] = true
            local cx, cy, gc = nx(cur), ny(cur), g[cur]
            for _, nb in ipairs(adj[cur]) do
                if not closed[nb] then
                    local d = math.sqrt((nx(nb) - cx) ^ 2 + (ny(nb) - cy) ^ 2)
                    local ng = gc + d
                    if not g[nb] or ng < g[nb] then
                        g[nb], came[nb] = ng, cur
                        heapPush(open, nb, ng + math.sqrt((nx(nb) - tx) ^ 2 + (ny(nb) - ty) ^ 2))
                    end
                end
            end
        end
        steps = steps + 1
        if steps % STEPS_PER_FRAME == 0 then coroutine.yield() end
    end
    return nil
end

----------------------------------------------------------------
-- Estado de navegacion
----------------------------------------------------------------
local nav = nil          -- { tx, ty, tz, label, points = {x,y,...}, dist, progress, mode, lastRoute, blip }
local job = nil          -- corutina en curso
local turn = nil         -- { dir = -1|0|1, dist }

local function inVehicle()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v then return false end
    local t = getVehicleType(v)
    return t == "Automobile" or t == "Bike" or t == "Monster Truck" or t == "Quad" or t == "BMX"
end

local function polyLength(pts, fromIdx)
    local d = 0
    for i = (fromIdx or 1), #pts / 2 - 1 do
        d = d + math.sqrt((pts[i * 2 + 1] - pts[i * 2 - 1]) ^ 2 + (pts[i * 2 + 2] - pts[i * 2]) ^ 2)
    end
    return d
end

function MapC.gpsState()
    if not nav then return { active = false } end
    return { active = true, label = nav.label, tx = nav.tx, ty = nav.ty, points = nav.points or {}, dist = nav.dist or 0,
        calculating = job ~= nil }
end

local function pushRoute()
    pcall(function() exports.rp_hud:setNavRoute(nav and nav.points or nil) end)
    MapC.callJS(("RP.route(%s)"):format(toJSON(MapC.gpsState(), true):sub(2, -2)))
end

local function playSfx(file)
    local s = playSound(file)
    if s then setSoundVolume(s, 0.5) end
end

local function buildRoute(px, py)
    local directed = inVehicle()
    local tx, ty = nav.tx, nav.ty
    local from = nearestNode(px, py, 1500, directed)
    local to = nearestNode(tx, ty, 1500)
    local path
    if from and to then
        path = astar(from, to, directed)
        if not path and directed then path = astar(from, to, false) end   -- sin salida respetando sentidos
    end
    if not nav or nav.tx ~= tx or nav.ty ~= ty then return end      -- se cancelo o cambio mientras calculaba
    local pts = { px, py }
    if path then
        for _, i in ipairs(path) do pts[#pts + 1] = nx(i); pts[#pts + 1] = ny(i) end
    end
    pts[#pts + 1] = tx; pts[#pts + 1] = ty
    nav.points, nav.progress, nav.mode, nav.lastRoute = pts, 1, directed, getTickCount()
    nav.dist = polyLength(pts)
    nav.noRoad = path == nil
    pushRoute()
end

local function runJob(px, py)
    job = coroutine.create(function() buildRoute(px, py) end)
end

addEventHandler("onClientRender", root, function()
    if not job then return end
    local ok, err = coroutine.resume(job)
    if not ok then outputDebugString("[rp_map] GPS: " .. tostring(err), 1); job = nil; return end
    if coroutine.status(job) == "dead" then job = nil; pushRoute() end
end)

function MapC.gpsStart(x, y, z, label)
    if MapC.state.settings.gps == 0 then
        return exports.rp_notify:notify("El GPS está desactivado en este servidor.", "warning")
    end
    if x < -3000 or x > 3000 or y < -3000 or y > 3000 then return end
    MapC.gpsStop(false)
    nav = { tx = x, ty = y, tz = z or 0, label = label or "Destino" }
    nav.blip = createBlip(x, y, z or 0, 41, 2, 255, 255, 255, 255, 0, 99999)
    local px, py = getElementPosition(localPlayer)
    runJob(px, py)
    pushRoute()
    playSfx("html/sounds/select_002.ogg")
    exports.rp_notify:notify("GPS: ruta a " .. nav.label .. ". Usa /gps para cancelar.", "info")
end

function MapC.gpsStop(announce)
    if nav and isElement(nav.blip) then destroyElement(nav.blip) end
    local had = nav ~= nil
    nav, job, turn = nil, nil, nil
    pushRoute()
    if announce and had then exports.rp_notify:notify("Navegación cancelada.", "info") end
end

addCommandHandler("gps", function() MapC.gpsStop(true) end)

----------------------------------------------------------------
-- Seguimiento: avance, desvio, llegada e indicaciones
----------------------------------------------------------------
local function distToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
    local qx, qy = ax + dx * t, ay + dy * t
    return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

-- Siguiente giro de mas de 35 grados a partir del punto k de la ruta
local function nextTurn(pts, k, px, py)
    local acc = math.sqrt((pts[k * 2 + 1] - px) ^ 2 + (pts[k * 2 + 2] - py) ^ 2)
    for i = k + 1, #pts / 2 - 1 do
        local ax, ay = pts[i * 2 - 3], pts[i * 2 - 2]
        local bx, by = pts[i * 2 - 1], pts[i * 2]
        local cx, cy = pts[i * 2 + 1], pts[i * 2 + 2]
        local a1 = math.atan2(by - ay, bx - ax)
        local a2 = math.atan2(cy - by, cx - bx)
        local diff = math.deg((a2 - a1 + math.pi) % (2 * math.pi) - math.pi)
        if math.abs(diff) > 35 and acc > 5 then
            return { dir = diff > 0 and -1 or 1, dist = acc }   -- angulo positivo = giro a la izquierda (antihorario)
        end
        acc = acc + math.sqrt((cx - bx) ^ 2 + (cy - by) ^ 2)
        if acc > 1500 then break end
    end
    return { dir = 0, dist = acc }
end

setTimer(function()
    if not nav or job or not nav.points then return end
    local px, py = getElementPosition(localPlayer)
    local pts = nav.points
    local arrive = inVehicle() and MAPA.GPS_ARRIVE_METERS or MAPA.GPS_ARRIVE_METERS / 2
    if getDistanceBetweenPoints2D(px, py, nav.tx, nav.ty) <= arrive then
        local label = nav.label
        MapC.gpsStop(false)
        playSfx("html/sounds/confirmation_003.ogg")
        return exports.rp_notify:notify("Has llegado a " .. label .. ".", "success")
    end
    -- tramo mas cercano dentro de una ventana desde el ultimo avance
    local best, bestK = math.huge, nav.progress
    local last = #pts / 2 - 1
    for k = math.max(1, nav.progress - 2), math.min(last, nav.progress + 40) do
        local d = distToSegment(px, py, pts[k * 2 - 1], pts[k * 2], pts[k * 2 + 1], pts[k * 2 + 2])
        if d < best then best, bestK = d, k end
    end
    nav.progress = bestK
    local now = getTickCount()
    local modeChanged = nav.mode ~= inVehicle()
    if (best > MAPA.GPS_OFFROUTE_METERS or modeChanged) and now - (nav.lastRoute or 0) > MAPA.GPS_REROUTE_MIN_MS
        and getElementInterior(localPlayer) == 0 then
        nav.lastRoute = now
        return runJob(px, py)
    end
    nav.dist = getDistanceBetweenPoints2D(px, py, pts[bestK * 2 + 1], pts[bestK * 2 + 2]) + polyLength(pts, bestK + 1)
    turn = nextTurn(pts, bestK, px, py)
    if MapC.isOpen() then MapC.callJS(("RP.navDist(%d)"):format(math.floor(nav.dist))) end
end, MAPA.GPS_CHECK_MS, 0)

----------------------------------------------------------------
-- Tarjeta de indicaciones (arriba al centro, con el mapa cerrado)
----------------------------------------------------------------
local sw, sh = guiGetScreenSize()
local sc = math.max(0.9, math.min(1.3, sh / 900))
local ROUTE = { 197, 92, 255 }

local function fmtDist(m)
    if m >= 1000 then return ("%.1f km"):format(m / 1000) end
    return ("%d m"):format(math.floor(m / 10 + 0.5) * 10)
end

local function drawArrow(cx, cy, size, dir, color)
    -- flecha hacia arriba girada: dir -1 izquierda, 0 recto, 1 derecha
    local ang = math.rad(dir * 90)
    local function r(x, y) return cx + x * math.cos(ang) - y * math.sin(ang), cy + x * math.sin(ang) + y * math.cos(ang) end
    local ax, ay = r(0, -size)
    local bx, by = r(-size * 0.7, 0)
    local cx2, cy2 = r(size * 0.7, 0)
    dxDrawPrimitive("trianglelist", false, { ax, ay, color }, { bx, by, color }, { cx2, cy2, color })
    local x1, y1 = r(-size * 0.25, 0)
    local x2, y2 = r(size * 0.25, 0)
    local x3, y3 = r(size * 0.25, size * 0.9)
    local x4, y4 = r(-size * 0.25, size * 0.9)
    dxDrawPrimitive("trianglelist", false, { x1, y1, color }, { x2, y2, color }, { x3, y3, color },
        { x1, y1, color }, { x3, y3, color }, { x4, y4, color })
end

addEventHandler("onClientRender", root, function()
    if not nav or MapC.isOpen() or isPlayerMapVisible() then return end
    local ok, hidden = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    if ok and hidden then return end
    local w, h = 330 * sc, 58 * sc
    local x, y = (sw - w) / 2, 18 * sc
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 215))
    dxDrawRectangle(x, y, 4 * sc, h, tocolor(ROUTE[1], ROUTE[2], ROUTE[3], 255))
    local title, sub
    if job then
        title, sub = "Calculando ruta...", nav.label
    elseif nav.noRoad then
        title, sub = "Sin calles cerca: ve en línea recta", nav.label .. " · " .. fmtDist(nav.dist or 0)
    elseif turn and turn.dir ~= 0 and turn.dist < 600 then
        title = (turn.dir < 0 and "Gira a la izquierda" or "Gira a la derecha") .. " en " .. fmtDist(turn.dist)
        sub = nav.label .. " · " .. fmtDist(nav.dist or 0)
    else
        title, sub = "Sigue recto", nav.label .. " · " .. fmtDist(nav.dist or 0)
    end
    drawArrow(x + 30 * sc, y + h / 2 + 2 * sc, 13 * sc, (not job and turn and turn.dist < 600) and turn.dir or 0,
        tocolor(ROUTE[1], ROUTE[2], ROUTE[3], 255))
    dxDrawText(title, x + 56 * sc, y + 8 * sc, x + w - 10 * sc, y + h / 2 + 4 * sc, tocolor(242, 244, 248), 1.15 * sc, "default-bold", "left", "center", true)
    dxDrawText(sub, x + 56 * sc, y + h / 2, x + w - 10 * sc, y + h - 6 * sc, tocolor(154, 163, 178), 1.0 * sc, "default", "left", "center", true)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    pcall(function() exports.rp_hud:setNavRoute(nil) end)
end)
