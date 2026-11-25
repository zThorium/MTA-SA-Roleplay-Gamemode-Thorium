--[[
    rp_shootingrange / s_targets.lua  (compartido)
    Geometria de los blancos. El servidor genera las posiciones (rangeBuildRound) y se las manda al
    cliente, que solo las dibuja; el servidor valida los impactos con las mismas funciones.

    El campo es el rectangulo RANGE.AREA (medido en juego con /pos): profundidad del frente al fondo
    y ancho de la pared izquierda a la derecha (vistas desde la cabina). Un blanco se define con:
        d = metros desde el frente hacia el fondo   (0 .. profundidad)
        l = metros desde la pared izquierda          (0 .. ancho)
    Posiciones con ruido Perlin y semilla por sesion: cada blanco tiene su propio tramo del ancho
    (repartidos de pared a pared) y una profundidad propia. Si desde la cabina no se veria (fuera del
    angulo VIEW_HALF_ANGLE), se empuja al fondo, donde la vista es mas ancha, y si hace falta hacia el centro.
]]

----------------------------------------------------------------
-- Ruido Perlin 1D (gradientes +-1, interpolacion quintica, 2 octavas)
----------------------------------------------------------------
local Perlin = {}
Perlin.__index = Perlin

-- Tabla de permutacion barajada con un generador lineal propio: misma semilla = mismo ruido,
-- sin tocar el math.random global.
function rangeNewNoise(seed)
    local state = (math.floor(tonumber(seed) or 1) % 2147483647)
    if state <= 0 then state = state + 2147483646 end
    local function rnd(n)                 -- Park-Miller: entero en [1, n]
        state = (state * 16807) % 2147483647
        return state % n + 1
    end
    local p = {}
    for i = 0, 255 do p[i] = i end
    for i = 255, 1, -1 do
        local j = rnd(i + 1) - 1
        p[i], p[j] = p[j], p[i]
    end
    return setmetatable({ p = p }, Perlin)
end

local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end

function Perlin:raw(x)
    local i = math.floor(x)
    local f = x - i
    local p = self.p
    local g0 = (p[i % 256] % 2 == 0) and f or -f
    local g1 = (p[(i + 1) % 256] % 2 == 0) and (f - 1) or -(f - 1)
    return (g0 + (g1 - g0) * fade(f)) * 2              -- ~[-1, 1]
end

-- Dos octavas: forma suave + algo de detalle. Resultado recortado a [-1, 1].
function Perlin:at(x)
    local v = self:raw(x) * 0.7 + self:raw(x * 2.3 + 17.1) * 0.3
    return math.max(-1, math.min(1, v))
end

----------------------------------------------------------------
-- Geometria del campo
----------------------------------------------------------------
local areaCache
function rangeArea()
    if areaCache then return areaCache end
    local A = RANGE.AREA
    local F = RANGE.FIRE
    local r = math.rad(F.rot)
    areaCache = {
        depth = math.abs(A.back - A.front), width = math.abs(A.right - A.left),
        sd = A.back >= A.front and 1 or -1, sl = A.right >= A.left and 1 or -1,
        fx = -math.sin(r), fy = math.cos(r),                         -- hacia donde mira el tirador
        cosView = math.cos(math.rad(RANGE.VIEW_HALF_ANGLE or 35)),
        margin = A.margin or 1.0,
    }
    return areaCache
end

-- Posicion del suelo (x, y, z). Profundidad sobre X y ancho sobre Y (la sala esta alineada con los ejes).
function rangeWorldPos(d, l)
    local A, G = RANGE.AREA, rangeArea()
    return A.front + G.sd * d, A.left + G.sl * l, A.z - (RANGE.FEET_OFFSET or 1.0)
end

-- ¿Se ve desde la cabina? (dentro del angulo de vision y no demasiado cerca)
function rangeVisible(d, l)
    local G, F = rangeArea(), RANGE.FIRE
    local x, y = rangeWorldPos(d, l)
    local vx, vy = x - F.x, y - F.y
    local dist = math.sqrt(vx * vx + vy * vy)
    if dist < (RANGE.MIN_TARGET_DIST or 8) then return false end
    return (vx * G.fx + vy * G.fy) / dist >= G.cosView
end

-- Tramo [l1, l2] del ancho que se ve a la profundidad d (o nil si no se ve nada)
local function visibleSpan(d)
    local G = rangeArea()
    local l1, l2
    for l = G.margin, G.width - G.margin, 0.25 do
        if rangeVisible(d, l) then l1 = l1 or l; l2 = l end
    end
    return l1, l2
end

-- Ajusta (d, l) hasta que se vea: primero mas al fondo, despues hacia el tramo visible
local function makeVisible(d, l)
    local G = rangeArea()
    local maxD = G.depth - G.margin
    for _ = 1, 40 do
        if rangeVisible(d, l) then return d, l end
        if d < maxD then
            d = math.min(maxD, d + 0.5)
        else
            local l1, l2 = visibleSpan(d)
            if not l1 then return d, l end
            return d, math.max(l1, math.min(l2, l))
        end
    end
    return d, l
end

-- Estado del blanco `t` tras `el` ms desde el inicio de la ronda.
-- Devuelve activo(bool), d, l. t.at y t.life en ms.
function rangeTargetState(t, el)
    if el < t.at or el > t.at + t.life then return false end
    if t.kind == "advance" then                         -- cruza el campo de pared a pared
        local k = (el - t.at) / t.life
        return true, t.d, t.l0 + (t.l1 - t.l0) * k
    elseif t.kind == "lateral" then                     -- va y viene a lo ancho
        return true, t.d, t.l + t.amp * math.sin(2 * math.pi * el / (t.period * 1000))
    end
    return true, t.d, t.l
end

-- Rotacion Z (MTA) para que un blanco en (x, y) mire hacia la posicion de tiro
function rangeFacing(x, y)
    local F = RANGE.FIRE
    return (-math.deg(math.atan2(F.x - x, F.y - y))) % 360
end

----------------------------------------------------------------
-- Rondas (solo servidor: las posiciones se envian al cliente)
----------------------------------------------------------------
-- noise = rangeNewNoise(semilla de la sesion). Cada ronda lee otra zona del ruido.
function rangeBuildRound(index, noise)
    local round = RANGE.ROUNDS[index]
    local G = rangeArea()
    local m = G.margin
    local base = index * 37.3
    local n = math.max(1, round.count or 1)
    local function u(i, salt) return 0.5 + 0.5 * noise:at(base + i * 1.618 + salt) end   -- [0, 1]
    local function depthAt(i, salt) return m + (G.depth - 2 * m) * u(i, salt) end
    local out = {}

    -- Orden de aparicion barajado por el ruido
    local order = {}
    for i = 1, n do order[i] = { i = i, k = noise:at(base + i * 3.33 + 55.5) } end
    table.sort(order, function(a, b) return a.k < b.k end)

    -- Hipercubo latino: el tramo de ancho i recibe un tramo de profundidad distinto (barajado por el
    -- ruido), asi siempre hay blancos cerca, a media distancia y al fondo, y nunca dos en fila.
    local dRank, ranked = {}, {}
    for i = 1, n do ranked[i] = { i = i, k = noise:at(base + i * 5.17 + 88.8) } end
    table.sort(ranked, function(a, b) return a.k < b.k end)
    for r, e in ipairs(ranked) do dRank[e.i] = r end
    local function stratifiedDepth(i)
        local slot = (G.depth - 2 * m) / n
        return m + slot * (dRank[i] - 0.5) + slot * 0.35 * noise:at(base + i * 2.9 + 21.9)
    end

    for idx, o in ipairs(order) do
        local i = o.i
        local t = { id = idx, kind = round.kind, at = 0, rearm = math.floor((round.rearm or 0) * 1000) }
        if round.kind == "advance" then
            -- Cada uno a una profundidad distinta; cruza todo el tramo visible a esa profundidad
            local d = makeVisible(m + (G.depth - 2 * m) * ((i - 0.5) / n + 0.35 / n * noise:at(base + i * 2.2 + 3.1)), G.width / 2)
            local l1, l2 = visibleSpan(d)
            l1, l2 = l1 or G.width / 2, l2 or G.width / 2
            local leftToRight = noise:at(base + i * 4.4 + 9.9) >= 0
            t.d, t.l0, t.l1 = d, leftToRight and l1 or l2, leftToRight and l2 or l1
            t.at = math.floor((idx - 1) * (round.every or 3) * 1000)
            t.life = math.floor((round.dur or 8) * 1000)
        elseif round.kind == "lateral" then
            local d = makeVisible(depthAt(i, 7.7), G.width / 2)
            local l1, l2 = visibleSpan(d)
            l1, l2 = l1 or G.width / 2, l2 or G.width / 2
            local amp = math.min(round.amp or 4, (l2 - l1) / 2)
            t.d, t.amp, t.period = d, amp, round.period or 4
            t.l = l1 + amp + (l2 - l1 - 2 * amp) * u(i, 12.3)
            t.life = round.time * 1000
        else
            -- Tramo propio del ancho (de pared a pared) + profundidad propia
            local slot = (G.width - 2 * m) / n
            local l = m + slot * (i - 0.5) + slot * 0.4 * noise:at(base + i * 1.618)
            t.d, t.l = makeVisible(stratifiedDepth(i), l)
            t.life = round.time * 1000
        end
        out[idx] = t
    end

    -- Que dos blancos fijos no queden pegados (uno tapando al otro): se separan en profundidad
    if round.kind == "static" then
        for a = 1, #out do
            for b = a + 1, #out do
                local A, B = out[a], out[b]
                if math.abs(A.l - B.l) < 1.5 and math.abs(A.d - B.d) < 2 then
                    B.d = math.min(G.depth - m, A.d + 2.5)
                end
            end
        end
    end
    return out
end
