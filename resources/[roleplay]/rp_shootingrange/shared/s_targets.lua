--[[
    rp_shootingrange / s_targets.lua  (compartido)
    Geometria de los blancos. Servidor y cliente usan la misma funcion: el cliente solo dibuja,
    el servidor decide los impactos con su propio reloj.
    Un blanco se define en el plano de la linea de tiro: d = metros hacia delante, l = metros a la derecha.
]]

-- Vectores unitarios (delante, derecha) de la linea de tiro segun FIRE.rot (rotacion Z de MTA)
function rangeAxes()
    local r = math.rad(RANGE.FIRE.rot)
    return -math.sin(r), math.cos(r), math.cos(r), math.sin(r)   -- fx, fy, rx, ry
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

-- Posicion del suelo (x, y, z) del blanco en el mundo. FIRE.z es la altura de un jugador de pie
-- (~1 m sobre el suelo): antes se usaba tal cual como suelo y los blancos salian 1 m mas arriba,
-- enterrados en el techo, y las zonas de impacto del servidor quedaban igual de desplazadas.
function rangeWorldPos(d, l)
    local fx, fy, rx, ry = rangeAxes()
    local F = RANGE.FIRE
    return F.x + fx * d + rx * l, F.y + fy * d + ry * l, F.z - (RANGE.FEET_OFFSET or 1.0)
end

-- Construye los blancos de una ronda para una categoria de arma
function rangeBuildRound(index, category)
    local round = RANGE.ROUNDS[index]
    local scale = RANGE.CATEGORIES[category].dist
    local half, cone = RANGE.LANE_HALF_WIDTH or 1.2, RANGE.VIEW_CONE or 0.075
    local minD = RANGE.MIN_TARGET_DIST or 6
    local maxD = RANGE.MAX_TARGET_DIST or 24
    local function dist(v) return math.max(minD, math.min(maxD, v)) end
    -- Desvio lateral visible desde la cabina a la distancia d (embudo) y nunca fuera del carril
    local function lane(v, d)
        local m = math.min(half, d * cone)
        return math.max(-m, math.min(m, v or 0))
    end
    local out = {}
    for i, def in ipairs(round.targets) do
        local t = { id = i, kind = round.kind, at = math.floor((def.at or 0) * 1000), rearm = math.floor((def.rearm or 0) * 1000) }
        if round.kind == "advance" then
            t.d0, t.d1, t.life = dist(def.d0 * scale), dist(def.d1 * scale), math.floor(def.dur * 1000)
            t.l = lane(def.l, math.min(t.d0, t.d1))          -- el punto mas cercano es el que decide
        elseif round.kind == "lateral" then
            t.d, t.period, t.life = dist(def.d * scale), def.period, round.time * 1000
            t.l, t.amp = 0, math.min(math.abs(def.amp or 0), half, t.d * cone)
        else
            t.d, t.life = dist(def.d * scale), round.time * 1000 - t.at
            t.l = lane(def.l, t.d)
        end
        out[i] = t
    end
    return out
end
