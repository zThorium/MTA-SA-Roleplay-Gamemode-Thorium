--[[
    rp_factions / s_config.lua  (compartido cliente/servidor)

    Permisos de los roles. Cada rol guarda la suma de sus bits en
    faction_ranks.permissions. El lider de la faccion los tiene todos.
    Para agregar un permiso nuevo, usa el siguiente bit libre (1024, 2048...)
    y comprueba con hasFactionPermission(player, "clave") en el servidor.
]]

FACTION_PERMISSIONS = {
    { key = "members",       bit = 1,   label = "Ver miembros",          description = "Ver la lista de miembros y su rol." },
    { key = "invite",        bit = 2,   label = "Invitar",               description = "Invitar jugadores a la faccion." },
    { key = "kick",          bit = 4,   label = "Expulsar",              description = "Expulsar miembros de rol inferior." },
    { key = "set_rank",      bit = 8,   label = "Cambiar rol",           description = "Ascender o degradar miembros de rol inferior." },
    { key = "manage_ranks",  bit = 16,  label = "Gestionar roles",       description = "Crear, editar y borrar roles inferiores, sus permisos y sueldos." },
    { key = "bank_view",     bit = 32,  label = "Ver fondos",            description = "Ver el saldo de la faccion." },
    { key = "bank_deposit",  bit = 64,  label = "Depositar fondos",      description = "Depositar efectivo propio en la faccion." },
    { key = "bank_withdraw", bit = 128, label = "Retirar fondos",        description = "Retirar dinero de la faccion en efectivo." },
    { key = "log_view",      bit = 256, label = "Ver registro",          description = "Ver el historial de actividad." },
    { key = "edit_motd",     bit = 512, label = "Editar anuncio",        description = "Cambiar el anuncio que ven todos los miembros." },
    -- Policia (rp_police): solo tienen efecto en la faccion 1 (tipo policia) y estando de servicio
    { key = "pol_detain",    bit = 1024,  label = "Policia: detener",           description = "Esposar, escoltar, cachear y meter detenidos al vehiculo." },
    { key = "pol_fine",      bit = 2048,  label = "Policia: multar y arrestar", description = "Multar a personas, registrar arrestos y encarcelar." },
    { key = "pol_mdt",       bit = 4096,  label = "Policia: MDT",               description = "Consultar ciudadanos, vehiculos y antecedentes en el MDT." },
    { key = "pol_bolo",      bit = 8192,  label = "Policia: BOLO y ordenes",    description = "Emitir y cancelar BOLO y ordenes de captura." },
    { key = "pol_armory",    bit = 16384, label = "Policia: armeria",           description = "Usar la armeria (cada articulo pide un nivel de rol minimo)." },
    { key = "pol_garage",    bit = 32768, label = "Policia: garaje",            description = "Sacar vehiculos policiales (cada modelo pide un nivel de rol minimo)." },
    { key = "pol_evidence",  bit = 65536, label = "Policia: evidencia",         description = "Recolectar evidencia y usar el laboratorio." },
}

FACTION_PERMISSION_BIT = {}
FACTION_ALL_PERMISSIONS = 0
for _, p in ipairs(FACTION_PERMISSIONS) do
    FACTION_PERMISSION_BIT[p.key] = p.bit
    FACTION_ALL_PERMISSIONS = FACTION_ALL_PERMISSIONS + p.bit
end

-- Tipos de faccion. state = el Estado paga los sueldos (no salen de los fondos de la faccion).
FACTION_TYPES = {
    gobierno = { name = "Gobierno",          state = true,  color = "#4c9aff" },
    policia  = { name = "Policia",           state = true,  color = "#3b6fe0" },
    medicos  = { name = "Servicios medicos", state = true,  color = "#e5484d" },
    bomberos = { name = "Bomberos",          state = true,  color = "#ff6a2b" },   -- rp_firefighters
    empresa  = { name = "Empresa",           state = false, color = "#4cd38a" },
    banda    = { name = "Banda",             state = false, color = "#a35bff" },
    otra     = { name = "Otra",              state = false, color = "#f5a524" },
}

FACTIONS = {
    KEY = "f3",
    MAX_RANKS = 15,
    MAX_SALARY = 5000,          -- sueldo maximo por payday que puede fijar un lider
    MAX_LEVEL = 99,             -- nivel de rol: mas alto = mas autoridad
    INVITE_TIMEOUT = 60000,     -- ms para aceptar una invitacion
    MAX_TRANSACTION = 1000000,  -- maximo por deposito o retiro de fondos
    LOG_ROWS = 40,
    NAME_MIN = 2, NAME_MAX = 24,     -- nombre de rol
    MOTD_MAX = 200,
    -- Roles con los que nace una faccion nueva
    DEFAULT_RANKS = {
        { name = "Lider",    level = 10, salary = 1500, permissions = "all" },
        { name = "Miembro",  level = 1,  salary = 500,  permissions = { "members" } },
    },
}

-- Convierte una lista de claves en el bitmask
function factionPermissionsToMask(list)
    if list == "all" then return FACTION_ALL_PERMISSIONS end
    local mask = 0
    for _, key in ipairs(list or {}) do
        local b = FACTION_PERMISSION_BIT[key]
        if b and bitAnd(mask, b) == 0 then mask = mask + b end
    end
    return mask
end

function factionMaskHas(mask, key)
    local b = FACTION_PERMISSION_BIT[key]
    return b ~= nil and bitAnd(tonumber(mask) or 0, b) ~= 0
end
