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
    local out = {}
    for i, def in ipairs(round.targets) do
        local t = { id = i, kind = round.kind, l = def.l, at = math.floor((def.at or 0) * 1000), rearm = math.floor((def.rearm or 0) * 1000) }
        if round.kind == "advance" then
            t.d0, t.d1, t.life = def.d0 * scale, def.d1 * scale, math.floor(def.dur * 1000)
        elseif round.kind == "lateral" then
            t.d, t.amp, t.period, t.life = def.d * scale, def.amp, def.period, round.time * 1000
        else
            t.d, t.life = def.d * scale, round.time * 1000 - t.at
        end
        out[i] = t
    end
    return out
end
