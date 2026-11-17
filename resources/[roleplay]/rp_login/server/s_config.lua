--[[
    rp_login / s_config.lua
    Parametros del sistema de cuentas.
]]

AUTH = {
    USERNAME_MIN = 3,
    USERNAME_MAX = 24,
    PASSWORD_MIN = 6,
    PASSWORD_MAX = 64,          -- bcrypt solo usa los primeros 72 bytes
    BCRYPT_COST = 10,           -- 10-12 es un buen equilibrio seguridad/CPU

    MAX_FAILED_ATTEMPTS = 5,    -- intentos fallidos antes de expulsar
    LOGIN_TIMEOUT = 5 * 60000,  -- ms para iniciar sesion antes de ser expulsado
    MAX_ACCOUNTS_PER_SERIAL = 3,
}
