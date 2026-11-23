--[[
    rp_levels / shared / s_config.lua

    Curva de niveles inspirada en GTA Online: cada nivel pide mas XP que el anterior
    (+STEP2 por nivel). XP total para llegar al nivel n:
        xpForLevel(n) = A*n^2 + B*n + C      (nivel 1 = 0 XP)
    Con los valores por defecto: nivel 2 = 800, 3 = 1900, 4 = 3300, 5 = 5000...
]]

LEVELS = {
    MAX_LEVEL = 100,
    A = 150, B = 350, C = -500,

    MAX_GIVE = 100000,     -- tope por llamada a giveXP / /darxp (proteccion ante errores)
}

function xpForLevel(level)
    level = math.max(1, math.floor(level))
    if level == 1 then return 0 end
    return LEVELS.A * level * level + LEVELS.B * level + LEVELS.C
end

-- Devuelve nivel, xp dentro del nivel, xp que pide el nivel actual para el siguiente
function levelFromXP(xp)
    xp = math.max(0, tonumber(xp) or 0)
    local level = 1
    while level < LEVELS.MAX_LEVEL and xp >= xpForLevel(level + 1) do level = level + 1 end
    if level >= LEVELS.MAX_LEVEL then return level, 0, 0 end
    local base = xpForLevel(level)
    return level, xp - base, xpForLevel(level + 1) - base
end
