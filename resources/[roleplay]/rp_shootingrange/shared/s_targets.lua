--[[
    rp_shootingrange / s_targets.lua  (compartido)
    Geometria de los blancos. El servidor genera las posiciones (rangeBuildRound) y se las manda al
    cliente, que solo las dibuja; el servidor valida los impactos con las mismas funciones.

    La franja de tiro RANGE.LANE va del limite izquierdo (`from`) al derecho (`to`) del campo (medidos
    en juego con /pos). Un blanco se define con:
        d = metros desde el limite izquierdo hacia el derecho (0 .. ancho de la franja)
        l = metros de fondo respecto a la linea (positivo = mas lejos del tirador, recortado a halfWidth)
    Las posiciones salen de ruido Perlin 1D con una semilla por sesion: cada partida es distinta, pero
    la franja se divide en tantos tramos como blancos para que no se amontonen ni dejen huecos.
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
-- Geometria de la franja
----------------------------------------------------------------
local laneCache
function rangeLane()
    if laneCache then return laneCache end
    local A, B = RANGE.LANE.from, RANGE.LANE.to
    local dx, dy = B.x - A.x, B.y - A.y
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / len, dy / len
    -- Normal de la linea que se aleja del tirador (para el "fondo" l)
    local nx, ny = uy, -ux
    local F = RANGE.FIRE
    if (A.x - F.x) * nx + (A.y - F.y) * ny < 0 then nx, ny = -nx, -ny end
    laneCache = { ax = A.x, ay = A.y, ux = ux, uy = uy, nx = nx, ny = ny, len = len, az = A.z, bz = B.z }
    return laneCache
end

-- Estado del blanco `t` tras `el` ms desde el inicio de la ronda.
-- Devuelve activo(bool), d, l. t.at y t.life en ms.
function rangeTargetState(t, el)
    if el < t.at or el > t.at + t.life then return false end
    if t.kind == "advance" then                         -- cruza la franja de un lado a otro
        local k = (el - t.at) / t.life
        return true, t.d0 + (t.d1 - t.d0) * k, t.l
    elseif t.kind == "lateral" then                     -- oscila a lo largo de la franja
        return true, t.d + t.amp * math.sin(2 * math.pi * el / (t.period * 1000)), t.l
    end
    return true, t.d, t.l
end

-- Posicion del suelo (x, y, z). Los puntos de la franja son posiciones de jugador (~1 m sobre los pies).
function rangeWorldPos(d, l)
    local L = rangeLane()
    local k = L.len > 0 and d / L.len or 0
    local z = L.az + (L.bz - L.az) * k - (RANGE.FEET_OFFSET or 1.0)
    return L.ax + L.ux * d + L.nx * l, L.ay + L.uy * d + L.ny * l, z
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
    local L = rangeLane()
    local len, half = L.len, RANGE.LANE.halfWidth or 1.0
    local margin = math.min(1.0, len * 0.05)            -- que nadie quede pegado a las paredes
    local usable = len - margin * 2
    local base = index * 37.3                           -- zona del ruido de esta ronda
    local n = math.max(1, round.count or 1)
    local out = {}

    -- Tramo i de n: centro del tramo + ruido (hasta un 40 % del tramo a cada lado)
    local function spread(i, salt)
        local slot = usable / n
        return margin + slot * (i - 0.5) + slot * 0.4 * noise:at(base + i * 1.618 + salt)
    end
    local function depth(i) return half * noise:at(base + i * 2.71 + 101.7) end

    -- El orden de los tramos se baraja con el ruido: no siempre aparecen de izquierda a derecha
    local order = {}
    for i = 1, n do order[i] = { i = i, k = noise:at(base + i * 3.33 + 55.5) } end
    table.sort(order, function(a, b) return a.k < b.k end)

    for idx, o in ipairs(order) do
        local i = o.i
        local t = { id = idx, kind = round.kind, at = 0, rearm = math.floor((round.rearm or 0) * 1000) }
        if round.kind == "advance" then
            -- Cruza toda la franja; sentido alterno y salida escalonada
            local leftToRight = noise:at(base + i * 4.4 + 9.9) >= 0
            local a, b = margin + usable * 0.05, len - margin - usable * 0.05
            t.d0, t.d1 = leftToRight and a or b, leftToRight and b or a
            t.l = depth(i)
            t.at = math.floor((idx - 1) * (round.every or 3) * 1000)
            t.life = math.floor((round.dur or 8) * 1000)
        elseif round.kind == "lateral" then
            local amp = math.min(round.amp or 4, usable / 2 - 0.5)
            t.d = math.max(margin + amp, math.min(len - margin - amp, spread(i, 7.7)))
            t.amp, t.period, t.l = amp, round.period or 4, depth(i)
            t.life = round.time * 1000
        else
            t.d, t.l = spread(i, 0), depth(i)
            t.life = round.time * 1000
        end
        out[idx] = t
    end
    return out
end
