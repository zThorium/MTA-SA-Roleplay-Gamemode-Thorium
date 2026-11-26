--[[
    rp_train · geometría de la vía (compartida: servidor y cliente)
    Distancia "d" = metros recorridos desde el nodo 1 en el sentido de los nodos. La vía es un bucle:
    d se toma siempre módulo TrainTrack.length.
]]

TrainTrack = {}

local cum, length -- cum[i] = d del nodo i; se calcula una vez
local cum2, length2 -- lo mismo en distancia horizontal: la que usa el juego (setTrainPosition)

local function build()
    if cum then return end
    local n = TRAIN_TRACK
    cum, length, cum2, length2 = { 0 }, 0, { 0 }, 0
    for i = 2, #n + 1 do
        local a, b = n[i - 1], n[(i - 1) % #n + 1]
        local h2 = (b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2
        length = length + math.sqrt(h2 + (b[3] - a[3]) ^ 2)
        length2 = length2 + math.sqrt(h2)
        if i <= #n then cum[i], cum2[i] = length, length2 end
    end
end

function TrainTrack.length() build() return length end
function TrainTrack.nodeD(i) build() return cum[i] end
function TrainTrack.wrap(d) build() return d % length end
function TrainTrack.gameLength() build() return length2 end -- largo del bucle en unidades del juego (~18107)

-- Nodo de la vía principal más cercano a la distancia d: x, y, z exactos.
-- Un tren puesto ahí con setElementPosition queda enganchado a la vía principal (el juego toma la vía
-- del nodo más cercano, y en LS hay otra pegada); después se ajusta con setTrainPosition.
function TrainTrack.nodePoint(d)
    build()
    d = d % length
    local n = TRAIN_TRACK
    local lo, hi = 1, #n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if cum[mid] <= d then lo = mid else hi = mid - 1 end
    end
    local segEnd = lo < #n and cum[lo + 1] or length
    local i = (d - cum[lo] > segEnd - d) and (lo % #n + 1) or lo
    return n[i][1], n[i][2], n[i][3]
end

-- Distancia d (la nuestra) → posición en la vía del juego, para setTrainPosition
function TrainTrack.gameD(d)
    build()
    d = d % length
    local lo, hi = 1, #cum
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if cum[mid] <= d then lo = mid else hi = mid - 1 end
    end
    local segEnd = lo < #cum and cum[lo + 1] or length
    local seg2End = lo < #cum and cum2[lo + 1] or length2
    local t = segEnd > cum[lo] and (d - cum[lo]) / (segEnd - cum[lo]) or 0
    return cum2[lo] + (seg2End - cum2[lo]) * t
end

-- Avance de a hasta b en el sentido de la marcha (0..length)
function TrainTrack.ahead(a, b) build() return (b - a) % length end

-- Punto de la vía en la distancia d: x, y, z y la dirección (ux, uy) del tramo
function TrainTrack.point(d)
    build()
    d = d % length
    local n = TRAIN_TRACK
    local lo, hi = 1, #n
    while lo < hi do -- último nodo con cum <= d
        local mid = math.floor((lo + hi + 1) / 2)
        if cum[mid] <= d then lo = mid else hi = mid - 1 end
    end
    local a, b = n[lo], n[lo % #n + 1]
    local segEnd = lo < #n and cum[lo + 1] or length
    local seg = segEnd - cum[lo]
    local t = seg > 0 and (d - cum[lo]) / seg or 0
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local m = math.sqrt(dx * dx + dy * dy)
    if m == 0 then m = 1 end
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, dx / m, dy / m
end

-- Proyecta un punto del mundo sobre la vía: d y distancia horizontal a la vía.
-- hint (d aproximada) limita la búsqueda a ±30 nodos; sin hint recorre toda la vía.
function TrainTrack.project(x, y, hint)
    build()
    local n = TRAIN_TRACK
    local count = #n
    local first, last = 1, count
    if hint then
        local lo, hi = 1, count
        local hd = hint % length
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            if cum[mid] <= hd then lo = mid else hi = mid - 1 end
        end
        first, last = lo - 30, lo + 30
    end
    local bestD, bestDist = 0, math.huge
    for k = first, last do
        local i = (k - 1) % count + 1
        local a, b = n[i], n[i % count + 1]
        local abx, aby = b[1] - a[1], b[2] - a[2]
        local len2 = abx * abx + aby * aby
        local t = len2 > 0 and ((x - a[1]) * abx + (y - a[2]) * aby) / len2 or 0
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        local px, py = a[1] + abx * t, a[2] + aby * t
        local dist = (x - px) ^ 2 + (y - py) ^ 2
        if dist < bestDist then
            bestDist = dist
            local segEnd = i < count and cum[i + 1] or length
            bestD = cum[i] + (segEnd - cum[i]) * t
        end
    end
    return bestD, math.sqrt(bestDist)
end
