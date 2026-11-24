--[[
    rp_gym / s_cooldown.lua
    Limite diario: si en un dia se pierde 40 % de grasa o se gana 20 % de resistencia o de musculo,
    hay que esperar 12 horas antes de volver a entrenar (Grand Theft Wiki: Gym).
    "Un dia" = ventana de 24 h desde el primer entrenamiento tras el ultimo reinicio de la ventana.
]]

-- Segundos que faltan para poder entrenar (0 = puede)
function gymLockRemaining(player)
    local p = profiles[player]
    if not p or p.loading then return 0 end
    return math.max(0, p.locked_until - gymNow())
end

function gymLockText(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.ceil((seconds % 3600) / 60)
    if m == 60 then h, m = h + 1, 0 end
    return ("%d h %d min"):format(h, m)
end

-- Suma lo ganado o perdido en este paso. Devuelve true si con esto se alcanza el limite (entonces ya
-- queda bloqueado y los contadores del dia se reinician para la proxima ventana).
function gymAccount(player, fatLost, staminaGained, muscleGained)
    local p = profiles[player]
    if not p or p.loading then return false end
    local now = gymNow()
    if p.day_start == 0 or now - p.day_start >= GYM.DAY_SECONDS then
        p.day_start, p.day_fat, p.day_stamina, p.day_muscle = now, 0, 0, 0
    end
    p.day_fat = p.day_fat + math.max(0, fatLost)
    p.day_stamina = p.day_stamina + math.max(0, staminaGained)
    p.day_muscle = p.day_muscle + math.max(0, muscleGained)
    p.last_trained = now

    if p.day_fat >= GYM.LIMIT_FAT or p.day_stamina >= GYM.LIMIT_STAMINA or p.day_muscle >= GYM.LIMIT_MUSCLE then
        p.locked_until = now + GYM.LOCK_SECONDS
        p.day_start, p.day_fat, p.day_stamina, p.day_muscle = 0, 0, 0, 0
        return true
    end
    return false
end
