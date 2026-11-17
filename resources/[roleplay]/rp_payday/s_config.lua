--[[
    rp_payday / s_config.lua
]]

PAYDAY = {
    INTERVAL = 60,        -- minutos de juego por payday
    BASE_SALARY = 300,    -- sueldo base del Estado (sin faccion, rol sin sueldo o faccion sin fondos)
    AFK_MINUTES = 10,     -- tras estos minutos sin moverse, el tiempo deja de contar (0 = desactivado)
    AFK_DISTANCE = 1.0,   -- metros minimos de movimiento por minuto para no contar como AFK
    SAVE_EVERY = 5,       -- guarda los minutos en la base cada N minutos (y siempre al salir)
}
