--[[
    rp_shootingrange / s_targets.lua  (compartido)
    Geometria de los blancos. Servidor y cliente usan la misma funcion: el cliente solo dibuja,
    el servidor valida los impactos con su propio reloj.

    Los blancos van por el carril RANGE.LANE (de `from`, el punto mas cercano al tirador, a `to`, el
    fondo de la sala; medidos en juego con /pos). Un blanco se define con:
        d = metros desde el inicio del carril hacia el fondo (0 .. largo del carril)
        l = metros a la derecha del centro del carril (negativo = izquierda)
    Antes se colocaban "d metros delante de la posicion de tiro", pero el carril no esta en linea
    recta delante de la cabina y los blancos salian donde el jugador no los veia.
]]

-- Datos del carril: origen, direccion unitaria (hacia el fondo), derecha y largo
local laneCache
function rangeLane()
    if laneCache then return laneCache end
    local A, B = RANGE.LANE.from, RANGE.LANE.to
    local dx, dy = B.x - A.x, B.y - A.y
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / len, dy / len
    laneCache = { ax = A.x, ay = A.y, ux = ux, uy = uy, rx = uy, ry = -ux, len = len,
        az = A.z, bz = B.z }
    return laneCache
end

-- Estado del blanco `t` tras `el` ms desde el inicio de la ronda.
-- Devuelve activo(bool), d, l. t.at y t.life en ms.
function rangeTargetState(t, el)
    if el < t.at or el > t.at + t.life then return false end
    if t.kind == "advance" then
        local k = (el - t.at) / t.life
        return true, t.d0 + (t.d1 - t.d0) * k, t.l
    elseif t.kind == "lateral" then
        return true, t.d, t.amp * math.sin(2 * math.pi * el / (t.period * 1000))
    end
    return true, t.d, t.l
end

-- Posicion del suelo (x, y, z) del blanco. Los puntos del carril son posiciones de jugador
-- (~1 m sobre los pies): FEET_OFFSET lo descuenta.
function rangeWorldPos(d, l)
    local L = rangeLane()
    local k = L.len > 0 and d / L.len or 0
    local z = L.az + (L.bz - L.az) * k - (RANGE.FEET_OFFSET or 1.0)
    return L.ax + L.ux * d + L.rx * l, L.ay + L.uy * d + L.ry * l, z
end

-- Rotacion Z (MTA) para que un blanco en (x, y) mire hacia la posicion de tiro
function rangeFacing(x, y)
    local F = RANGE.FIRE
    return (-math.deg(math.atan2(F.x - x, F.y - y))) % 360
end

-- Construye los blancos de una ronda para una categoria de arma
function rangeBuildRound(index, category)
    local round = RANGE.ROUNDS[index]
    local scale = RANGE.CATEGORIES[category].dist
    local len = rangeLane().len
    local half = RANGE.LANE.halfWidth or 1.0
    local function dist(v) return math.max(0, math.min(len, v)) end             -- siempre dentro del carril
    local function lane(v) return math.max(-half, math.min(half, v or 0)) end
    local out = {}
    for i, def in ipairs(round.targets) do
        local t = { id = i, kind = round.kind, at = math.floor((def.at or 0) * 1000), rearm = math.floor((def.rearm or 0) * 1000) }
        if round.kind == "advance" then
            t.d0, t.d1, t.life = dist(def.d0 * scale), dist(def.d1 * scale), math.floor(def.dur * 1000)
            t.l = lane(def.l)
        elseif round.kind == "lateral" then
            t.d, t.period, t.life = dist(def.d * scale), def.period, round.time * 1000
            t.l, t.amp = 0, math.min(math.abs(def.amp or 0), half)
        else
            t.d, t.life = dist(def.d * scale), round.time * 1000 - t.at
            t.l = lane(def.l)
        end
        out[i] = t
    end
    return out
end
