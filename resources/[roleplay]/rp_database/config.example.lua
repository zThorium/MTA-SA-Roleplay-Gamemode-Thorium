--[[
    rp_database / config.example.lua

    Copia este archivo como config.lua y pon tus credenciales.
    config.lua esta en .gitignore: nunca lo subas al repositorio.
    Usa un usuario dedicado con permisos solo sobre la base del gamemode.
]]

DB_CONFIG = {
    host     = "127.0.0.1",
    port     = 3306,
    dbname   = "mtarp",
    user     = "mtarp",
    password = "CAMBIA_ESTA_CONTRASENA",
    charset  = "utf8mb4",
}
