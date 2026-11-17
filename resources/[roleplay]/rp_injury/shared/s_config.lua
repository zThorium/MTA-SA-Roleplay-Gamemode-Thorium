--[[
    rp_injury / s_config.lua
    Ajustes del estado "abatido".
]]

INJURY = {
    DOWNED_TIME   = 2 * 60000,   -- tiempo abatido antes de morir (ms)
    DOWNED_HEALTH = 10,          -- vida que muestra el jugador abatido
    REVIVE_HEALTH = 30,          -- vida con la que queda al ser reanimado
    RESPAWN_DELAY = 5000,        -- espera tras morir antes de aparecer en el hospital (ms)
    HOSPITAL_FEE  = 500,         -- tarifa del hospital (efectivo primero, el resto del banco)

    -- Animacion en el suelo (sincronizada por el servidor)
    ANIM_BLOCK = "SWEET",
    ANIM_NAME  = "Sweet_injuredloop",

    -- Comandos de servidor que un jugador abatido puede usar (los admins pueden usar todos)
    ALLOWED_COMMANDS = {},
}
