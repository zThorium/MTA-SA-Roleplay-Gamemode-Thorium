--[[
    rp_gym / s_stats.lua
    Cambia musculo, grasa y resistencia del personaje. Quien las guarda y aplica es rp_characters
    (setBodyStats); aqui se calcula el cambio real (tras los limites 0-1000) y se contabiliza para
    el limite diario.
]]

-- Aplica una variacion en unidades 0-1000. Devuelve true si el limite diario se alcanzo con este paso.
function gymApplyDelta(player, dStamina, dMuscle, dFat, rebuild)
    local stats = exports.rp_characters:getBodyStats(player)
    if not stats then return false end
    local function clamp(v) return math.max(0, math.min(1000, v)) end
    local stamina, muscle, fat = clamp(stats.stamina + dStamina), clamp(stats.muscle + dMuscle), clamp(stats.fat + dFat)

    exports.rp_characters:setBodyStats(player, fat, muscle, stamina, rebuild)
    local reached = gymAccount(player, stats.fat - fat, stamina - stats.stamina, muscle - stats.muscle)
    if reached then saveProfile(player) end
    return reached
end

-- Estadisticas de records del juego (DIST_TREADMILL, LONGEST_TREADMILL_TIME, HEAVIEST_WEIGHT_*, VISITS_TO_GYM)
function gymBumpStat(player, stat, value, asMax)
    local current = getPedStat(player, stat) or 0
    if asMax then
        if value > current then setPedStat(player, stat, math.min(1000, value)) end
    else
        setPedStat(player, stat, math.min(1000, current + value))
    end
end
