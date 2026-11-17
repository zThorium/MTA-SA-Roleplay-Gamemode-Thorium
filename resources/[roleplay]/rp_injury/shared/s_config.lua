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

    -- Efecto de pantalla del abatido (client/c_screen.lua + files/downed.fx)
    SCREEN = {
        FADE_IN  = 2500,          -- ms hasta el gris total y el desenfoque completo
        FADE_OUT = 3000,          -- ms para recuperar los colores al ser reanimado
        BLUR_MAX = 0.018,         -- largo maximo del desenfoque (fraccion del ancho de pantalla)
        BLUR_IDLE = 0.0022,       -- desenfoque que queda con la camara quieta
        BLUR_FULL_SPEED = 200,    -- grados/s de giro de camara que dan el desenfoque maximo
        BLUR_RISE = 8,            -- rapidez con la que aparece al mover la camara (1/s)
        BLUR_DECAY = 1.5,         -- rapidez con la que se recupera la nitidez al parar (1/s)
        CAMERA_CUT_SPEED = 3000,  -- giros mas rapidos se ignoran (corte de camara, spawn)
    },

    -- Comandos de servidor que un jugador abatido puede usar (los admins pueden usar todos)
    ALLOWED_COMMANDS = {},
}
