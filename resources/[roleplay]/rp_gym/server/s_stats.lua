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
    -- Cada punto entero (1 % = 10 unidades) ganado, o de grasa perdido, se muestra un momento en pantalla
    local changes = {}
    for _, c in ipairs({ { "muscle", stats.muscle, muscle }, { "stamina", stats.stamina, stamina }, { "fat", stats.fat, fat } }) do
        local diff = math.floor(c[3] / 10) - math.floor(c[2] / 10)
        if (c[1] == "fat" and diff < 0) or (c[1] ~= "fat" and diff > 0) then
            changes[#changes + 1] = { stat = c[1], value = c[3], diff = diff }
        end
    end
    if #changes > 0 then triggerClientEvent(player, "rp:gym:statChange", resourceRoot, changes) end
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
