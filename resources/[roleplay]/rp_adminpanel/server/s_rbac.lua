--[[
    rp_adminpanel / s_rbac.lua
    RBAC del panel de administracion.

    - Rangos: accounts.admin_level (1 Admin, 2 Admin senior, 3 Super admin).
    - Permisos por rango: tabla admin_role_perms (editable desde el panel).
    - Excepciones por cuenta: tabla admin_account_perms (permitir / denegar).
    - El Super admin (nivel >= SUPER_LEVEL) siempre tiene todo: no se puede dejar sin acceso.

    Orden de decision: excepcion de la cuenta > permiso del rango.
    Los comandos de chat de otros recursos siguen usando admin_level; este RBAC
    gobierna las acciones del panel. Otros recursos pueden usar
    exports.rp_adminpanel:hasPermission(player, "clave").

    shortcut: el sembrado inicial solo corre con admin_role_perms vacia; un permiso
    nuevo en PERMS hay que asignarlo a mano desde la pestana IAM.
]]

SUPER_LEVEL = 3
ROLE_NAMES = { [0] = "Jugador", [1] = "Admin", [2] = "Admin senior", [3] = "Super admin" }

-- key, grupo, etiqueta, nivel minimo por defecto
PERMS = {
    { key = "players.view",   group = "Jugadores", label = "Ver jugadores en linea",        min = 1 },
    { key = "players.goto",   group = "Jugadores", label = "Ir hasta un jugador",           min = 1 },
    { key = "players.bring",  group = "Jugadores", label = "Traer a un jugador",            min = 1 },
    { key = "players.heal",   group = "Jugadores", label = "Curar (vida y chaleco)",        min = 1 },
    { key = "players.freeze", group = "Jugadores", label = "Congelar / descongelar",        min = 1 },
    { key = "players.kick",   group = "Jugadores", label = "Expulsar del servidor",         min = 1 },
    { key = "accounts.view",  group = "Cuentas",   label = "Buscar cuentas (incluye fuera de linea)", min = 2 },
    { key = "logs.view",      group = "Auditoria", label = "Ver el registro de acciones",   min = 2 },
    { key = "vehicles.create", group = "Vehiculos", label = "Crear vehiculos con dueno (/makeveh)", min = 3 },
    { key = "commands.view",  group = "Panel",    label = "Ver el catalogo de comandos",   min = 1 },
    { key = "iam.manage",     group = "IAM",       label = "Gestionar rangos, permisos y niveles (solo super admin)", min = 3, locked = true },
}
PERM_BY_KEY = {}
for _, p in ipairs(PERMS) do PERM_BY_KEY[p.key] = p end

local rolePerms = {}   -- [level] = { [perm] = true }
local overrides = {}   -- [accountId] = { [perm] = true|false }

local function conn() return exports.rp_database:getConnection() end

function levelOf(player) return exports.rp_login:getPlayerAdminLevel(player) or 0 end

function hasPermission(player, perm)
    if not isElement(player) or not PERM_BY_KEY[perm] then return false end
    local level = levelOf(player)
    if level >= SUPER_LEVEL then return true end
    if level < 1 or PERM_BY_KEY[perm].locked then return false end
    local id = exports.rp_login:getPlayerAccountId(player)
    local o = id and overrides[id]
    if o and o[perm] ~= nil then return o[perm] end
    return rolePerms[level] and rolePerms[level][perm] == true or false
end

-- Lista de permisos efectivos para el cliente
function effectivePerms(player)
    local list = {}
    for _, p in ipairs(PERMS) do
        if hasPermission(player, p.key) then list[#list + 1] = p.key end
    end
    return list
end

function setRolePerm(level, perm, allow)
    if not PERM_BY_KEY[perm] or PERM_BY_KEY[perm].locked then return false end
    if level < 1 or level >= SUPER_LEVEL then return false end
    rolePerms[level] = rolePerms[level] or {}
    rolePerms[level][perm] = allow and true or nil
    if allow then
        dbExec(conn(), "INSERT IGNORE INTO admin_role_perms (level, perm) VALUES (?, ?)", level, perm)
    else
        dbExec(conn(), "DELETE FROM admin_role_perms WHERE level = ? AND perm = ?", level, perm)
    end
    return true
end

-- state: "allow" | "deny" | "inherit"
function setOverride(accountId, perm, state)
    if not PERM_BY_KEY[perm] or PERM_BY_KEY[perm].locked then return false end
    overrides[accountId] = overrides[accountId] or {}
    if state == "inherit" then
        overrides[accountId][perm] = nil
        dbExec(conn(), "DELETE FROM admin_account_perms WHERE account_id = ? AND perm = ?", accountId, perm)
    elseif state == "allow" or state == "deny" then
        local allow = state == "allow"
        overrides[accountId][perm] = allow
        dbExec(conn(), [[INSERT INTO admin_account_perms (account_id, perm, allowed) VALUES (?, ?, ?)
                         ON DUPLICATE KEY UPDATE allowed = VALUES(allowed)]], accountId, perm, allow and 1 or 0)
    else
        return false
    end
    return true
end

function getRolePerms() return rolePerms end
function getOverrides(accountId) return overrides[accountId] or {} end

local function seed()
    for _, p in ipairs(PERMS) do
        for level = 1, SUPER_LEVEL - 1 do
            if not p.locked and level >= p.min then
                dbExec(conn(), "INSERT IGNORE INTO admin_role_perms (level, perm) VALUES (?, ?)", level, p.key)
            end
        end
    end
end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        rolePerms = {}
        for _, r in ipairs(rows) do
            local lv = tonumber(r.level)
            rolePerms[lv] = rolePerms[lv] or {}
            rolePerms[lv][r.perm] = true
        end
        dbQuery(function(qh2)
            overrides = {}
            for _, r in ipairs(dbPoll(qh2, 0) or {}) do
                local id = tonumber(r.account_id)
                overrides[id] = overrides[id] or {}
                overrides[id][r.perm] = tonumber(r.allowed) == 1
            end
        end, conn(), "SELECT account_id, perm, allowed FROM admin_account_perms")
    end, conn(), "SELECT level, perm FROM admin_role_perms")
end

local function init()
    local c = conn()
    dbExec(c, [[CREATE TABLE IF NOT EXISTS admin_role_perms (
        level TINYINT UNSIGNED NOT NULL,
        perm  VARCHAR(48)      NOT NULL,
        PRIMARY KEY (level, perm)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    dbExec(c, [[CREATE TABLE IF NOT EXISTS admin_account_perms (
        account_id INT UNSIGNED NOT NULL,
        perm       VARCHAR(48)  NOT NULL,
        allowed    TINYINT(1)   NOT NULL,
        PRIMARY KEY (account_id, perm)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then seed() end
        -- dbExec es asincrono pero ordenado en la misma conexion: la lectura ve el sembrado
        load()
    end, c, "SELECT 1 FROM admin_role_perms LIMIT 1")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then init() else addEventHandler("rp:onDatabaseReady", root, init) end
end)
