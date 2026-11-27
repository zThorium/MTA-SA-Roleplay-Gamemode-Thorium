--[[
    rp_3dtext / s_config.lua  (compartido)
]]

TEXT3D = {
    ICON_MODEL     = 1239,   -- icono "i" de informacion de GTA SA
    MAX_LENGTH     = 200,    -- caracteres del texto
    MIN_LENGTH     = 2,
    COOLDOWN_MS    = 2000,   -- entre /create3dtext del mismo admin

    -- Icono (cliente)
    SPIN_DEG_S     = 90,     -- giro por segundo
    BOB_HEIGHT     = 0.08,   -- metros que sube y baja al flotar
    BOB_SPEED      = 2.2,
    GOLD           = { 255, 205, 60 },    -- color del halo, el haz, el anillo y las chispas
    FX_DISTANCE    = 35,     -- metros: mas lejos no se dibujan halo, haz ni chispas
    SPARKS_PER_S   = 9,      -- chispas por segundo y por icono (en calidad alta)
    LOS_MS         = 200,    -- cada cuanto se comprueba si una pared tapa el texto

    -- Calidad (PCs de bajos recursos), igual que rp_pickupfx: arranca segun "Calidad de efectos"
    -- de los ajustes de MTA y baja sola un nivel si los FPS medios caen de MIN_FPS (relativo al
    -- fpslimit del servidor). Nunca sube sola.
    MIN_FPS        = 30,
    FPS_WINDOW_MS  = 3000,
    QUALITY = {
        { maxFx = 4,  animDistance = 25, maxSparks = 0,   sparkRate = 0,   beam = false, wave = false },  -- bajo
        { maxFx = 8,  animDistance = 40, maxSparks = 50,  sparkRate = 0.5, beam = true,  wave = false },  -- medio
        { maxFx = 12, animDistance = 60, maxSparks = 160, sparkRate = 1,   beam = true,  wave = true  },  -- alto
    },

    -- Tarjeta de texto (cliente)
    DRAW_DISTANCE  = 8,      -- metros: mas lejos no se ve
    FADE_DISTANCE  = 5,      -- a partir de aqui se va desvaneciendo
    TEXT_OFFSET_Z  = 0.42,   -- altura de la base de la tarjeta sobre el icono
    WRAP_WIDTH     = 300,    -- px de ancho maximo del texto (a escala 1)
    SOUND_VOLUME   = 0.45,   -- sonido al acercarte y aparecer el texto
}
