--[[
    rp_admin / s_commands.lua
    Comandos basicos de administracion. <jugador> acepta el ID (el de /id,
    scoreboard y nametags, via rp_ids) o parte del nombre.

    Nivel 1 (admin):
        /goto <jugador>                 ir hasta un jugador
        /get <jugador>                  traer un jugador a tu lado
        /tp <x> <y> <z> [int] [dim]     ir a unas coordenadas
        /pos                            ver tus coordenadas
        /heal <jugador>                 vida al 100
        /sethp <jugador> <0-100>        fijar vida
        /setarmor <jugador> <0-100>     fijar chaleco
        /freeze <jugador>               congelar / descongelar
        /slap <jugador>                 lanzar hacia arriba y quitar 5 de vida
        /kick <jugador> [motivo]        expulsar del servidor
        /givemoney <jugador> <monto>    dar (o quitar, si es negativo) efectivo. Alias: /apagar
        /a <mensaje>                    chat de administradores
        /debug [0-3]                    activar / apagar el debugscript de tu cliente
        /copiardebug [X]                copiar al portapapeles las ultimas X lineas del debug
        /ahelp                          lista de comandos de admin
    Nivel 3 (super admin):
        /setmoney <jugador> <monto>     fijar el efectivo
        /ban <jugador> <horas> [motivo] banear por serial (0 horas = permanente)
    Cualquier jugador:
        /admins                         administradores conectados

    Cada accion queda en server.log y en la tabla admin_log.
    /kick y /ban necesitan que rp_admin este en el grupo Admin de acl.xml.
]]

local LEVEL_ADMIN, LEVEL_SUPER = 1, 3

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) return exports.rp_notify:notify(p, text, kind or "info") end
local function levelOf(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end
local function idOf(p) return exports.rp_ids:getPlayerId(p) or "?" end
local function label(p) return ("%s (ID %s)"):format(nameOf(p), tostring(idOf(p))) end

local function guard(player, level)
    if levelOf(player) >= (level or LEVEL_ADMIN) then return true end
    notify(player, "No tienes permiso para usar este comando.", "error")
    return false
end

-- Busca al objetivo; avisa con el uso correcto si no se encuentra
local function target(player, query, usage)
    if not query then notify(player, "Uso: " .. usage, "warning") return false end
    local t = exports.rp_ids:findPlayer(query)
    if not t then notify(player, "No se encontro un unico jugador con ese nombre o ID.", "warning") end
    return t
end

-- No se puede actuar sobre un admin de nivel superior (salvo uno mismo)
local function outranks(player, t)
    if player == t or levelOf(player) >= levelOf(t) then return true end
    notify(player, "Ese administrador tiene un nivel superior al tuyo.", "error")
    return false
end

local function hasCharacter(player, t)
    if exports.rp_characters:getPlayerCharacterId(t) then return true end
    notify(player, nameOf(t) .. " no tiene un personaje en juego.", "warning")
    return false
end

local function logAction(admin, command, t, details)
    local line = ("[rp_admin] %s (cuenta #%s) /%s%s%s"):format(getPlayerName(admin),
        tostring(exports.rp_login:getPlayerAccountId(admin) or "-"), command,
        t and (" -> " .. getPlayerName(t)) or "", details and (" | " .. details) or "")
    outputServerLog(line)
    local conn = db()
    if not conn then return end
    -- dbExec no admite nil: los valores ausentes van como 0 / "" y NULLIF los guarda como NULL
    dbExec(conn, [[INSERT INTO admin_log (admin_account_id, admin_name, command, target_account_id,
                   target_character_id, target_name, details)
                   VALUES (NULLIF(?, 0), ?, ?, NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, ''), NULLIF(?, ''))]],
        exports.rp_login:getPlayerAccountId(admin) or 0, getPlayerName(admin), command,
        t and exports.rp_login:getPlayerAccountId(t) or 0,
        t and exports.rp_characters:getPlayerCharacterId(t) or 0,
        t and getPlayerName(t) or "", (details or ""):sub(1, 255))
end

local function ensureTable()
    dbExec(db(), [[
        CREATE TABLE IF NOT EXISTS admin_log (
            id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
            admin_account_id    INT UNSIGNED NULL,
            admin_name          VARCHAR(64)  NOT NULL,
            command             VARCHAR(32)  NOT NULL,
            target_account_id   INT UNSIGNED NULL,
            target_character_id INT UNSIGNED NULL,
            target_name         VARCHAR(64)  NULL,
            details             VARCHAR(255) NULL,
            created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_admin_log_admin (admin_account_id),
            KEY idx_admin_log_target (target_account_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then ensureTable() else addEventHandler("rp:onDatabaseReady", root, ensureTable) end
end)

-- Mueve a un jugador (o su vehiculo si lo conduce) a una posicion
local function moveTo(p, x, y, z, interior, dimension)
    local veh = getPedOccupiedVehicle(p)
    if veh and getVehicleController(veh) == p then
        setElementInterior(veh, interior)
        setElementDimension(veh, dimension)
        setElementPosition(veh, x, y, z + 1)
        setElementVelocity(veh, 0, 0, 0)
        for _, occ in pairs(getVehicleOccupants(veh)) do
            setElementInterior(occ, interior)
            setElementDimension(occ, dimension)
        end
        return
    end
    if veh then removePedFromVehicle(p) end
    setElementInterior(p, interior)
    setElementDimension(p, dimension)
    setElementPosition(p, x, y, z)
end

-- Punto 1.5 m a la derecha del jugador
local function besides(p)
    local x, y, z = getElementPosition(p)
    local _, _, rot = getElementRotation(p)
    local r = math.rad(rot)
    return x + math.cos(r) * 1.5, y + math.sin(r) * 1.5, z
end

----------------------------------------------------------------
-- Teletransporte
----------------------------------------------------------------
addCommandHandler("goto", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/goto <id o nombre>")
    if not t or t == player then return end
    local x, y, z = besides(t)
    moveTo(player, x, y, z, getElementInterior(t), getElementDimension(t))
    notify(player, "Fuiste hasta " .. label(t) .. ".", "success")
    logAction(player, "goto", t)
end)

addCommandHandler("get", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/get <id o nombre>")
    if not t or t == player or not outranks(player, t) then return end
    local x, y, z = besides(player)
    moveTo(t, x, y, z, getElementInterior(player), getElementDimension(player))
    notify(player, "Trajiste a " .. label(t) .. ".", "success")
    notify(t, "Un administrador te teletransporto.", "info")
    logAction(player, "get", t)
end)

addCommandHandler("tp", function(player, _, x, y, z, interior, dimension)
    if not guard(player) then return end
    x, y, z = tonumber(x and (x:gsub(",", ""))), tonumber(y and (y:gsub(",", ""))), tonumber(z and (z:gsub(",", "")))
    if not (x and y and z) then return notify(player, "Uso: /tp <x> <y> <z> [interior] [dimension]", "warning") end
    interior = tonumber(interior) or getElementInterior(player)
    dimension = tonumber(dimension) or getElementDimension(player)
    moveTo(player, x, y, z, interior, dimension)
    notify(player, ("Teletransportado a %.1f, %.1f, %.1f."):format(x, y, z), "success")
    logAction(player, "tp", nil, ("%.2f %.2f %.2f int %d dim %d"):format(x, y, z, interior, dimension))
end)

addCommandHandler("pos", function(player)
    if not guard(player) then return end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    outputChatBox(("Posicion: %.3f, %.3f, %.3f  rot %.1f  int %d  dim %d"):format(x, y, z, rot,
        getElementInterior(player), getElementDimension(player)), player, 245, 165, 36)
end)

----------------------------------------------------------------
-- Vida, chaleco, congelar, slap
----------------------------------------------------------------
addCommandHandler("heal", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query or tostring(idOf(player)), "/heal <id o nombre>")
    if not t then return end
    if isPedDead(t) then return notify(player, label(t) .. " esta muerto.", "warning") end
    setElementHealth(t, 100)
    notify(player, "Curaste a " .. label(t) .. ".", "success")
    if t ~= player then notify(t, "Un administrador te curo.", "info") end
    logAction(player, "heal", t)
end)

addCommandHandler("sethp", function(player, _, query, value)
    if not guard(player) then return end
    local t = target(player, query, "/sethp <id o nombre> <0-100>")
    value = tonumber(value)
    if not t then return end
    if not value or value < 0 or value > 100 then return notify(player, "Uso: /sethp <id o nombre> <0-100>", "warning") end
    if not outranks(player, t) then return end
    if isPedDead(t) then return notify(player, label(t) .. " esta muerto.", "warning") end
    if value == 0 then killPed(t) else setElementHealth(t, value) end
    notify(player, ("Vida de %s fijada en %d."):format(label(t), value), "success")
    logAction(player, "sethp", t, tostring(value))
end)

addCommandHandler("setarmor", function(player, _, query, value)
    if not guard(player) then return end
    local t = target(player, query, "/setarmor <id o nombre> <0-100>")
    value = tonumber(value)
    if not t then return end
    if not value or value < 0 or value > 100 then return notify(player, "Uso: /setarmor <id o nombre> <0-100>", "warning") end
    setPedArmor(t, value)
    notify(player, ("Chaleco de %s fijado en %d."):format(label(t), value), "success")
    logAction(player, "setarmor", t, tostring(value))
end)

addCommandHandler("freeze", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/freeze <id o nombre>")
    if not t or not outranks(player, t) then return end
    local frozen = not isElementFrozen(t)
    setElementFrozen(t, frozen)
    toggleAllControls(t, not frozen, true, false)
    local veh = getPedOccupiedVehicle(t)
    if veh and getVehicleController(veh) == t then setElementFrozen(veh, frozen) end
    notify(player, (frozen and "Congelaste a " or "Descongelaste a ") .. label(t) .. ".", "success")
    notify(t, frozen and "Un administrador te congelo." or "Un administrador te descongelo.", "info")
    logAction(player, frozen and "freeze" or "unfreeze", t)
end)

addCommandHandler("slap", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/slap <id o nombre>")
    if not t or not outranks(player, t) then return end
    if isPedDead(t) then return end
    local veh = getPedOccupiedVehicle(t)
    if veh then removePedFromVehicle(t) end
    local x, y, z = getElementPosition(t)
    setElementPosition(t, x, y, z + 4)
    setElementHealth(t, math.max(1, getElementHealth(t) - 5))
    notify(player, "Abofeteaste a " .. label(t) .. ".", "success")
    logAction(player, "slap", t)
end)

----------------------------------------------------------------
-- Expulsiones
----------------------------------------------------------------
addCommandHandler("kick", function(player, _, query, ...)
    if not guard(player) then return end
    local t = target(player, query, "/kick <id o nombre> [motivo]")
    if not t or t == player or not outranks(player, t) then return end
    local reason = table.concat({ ... }, " ")
    if reason == "" then reason = "Sin motivo" end
    local who = label(t)
    logAction(player, "kick", t, reason)
    if not kickPlayer(t, player, reason) then
        logAction(player, "kick_fallido", t, "sin permiso ACL")
        return notify(player, "No se pudo expulsar: agrega resource.rp_admin al grupo Admin en acl.xml.", "error")
    end
    outputChatBox(("%s fue expulsado por un administrador. Motivo: %s"):format(who, reason), root, 255, 120, 120)
end)

addCommandHandler("ban", function(player, _, query, hours, ...)
    if not guard(player, LEVEL_SUPER) then return end
    local t = target(player, query, "/ban <id o nombre> <horas, 0 = permanente> [motivo]")
    hours = tonumber(hours)
    if not t then return end
    if not hours or hours < 0 then return notify(player, "Uso: /ban <id o nombre> <horas, 0 = permanente> [motivo]", "warning") end
    if t == player or not outranks(player, t) then return end
    local reason = table.concat({ ... }, " ")
    if reason == "" then reason = "Sin motivo" end
    local who = label(t)
    logAction(player, "ban", t, ("%s h | %s | serial %s"):format(hours == 0 and "perm" or tostring(hours), reason, getPlayerSerial(t)))
    if not banPlayer(t, false, false, true, player, reason, math.floor(hours * 3600)) then
        logAction(player, "ban_fallido", t, "sin permiso ACL")
        return notify(player, "No se pudo banear: agrega resource.rp_admin al grupo Admin en acl.xml.", "error")
    end
    outputChatBox(("%s fue baneado %s. Motivo: %s"):format(who,
        hours == 0 and "permanentemente" or ("por " .. hours .. " h"), reason), root, 255, 120, 120)
end)

----------------------------------------------------------------
-- Dinero (efectivo). Para la cuenta bancaria esta /dardinero (rp_bank).
----------------------------------------------------------------
local function giveMoney(player, cmd, query, amount)
    if not guard(player) then return end
    local t = target(player, query, "/" .. cmd .. " <id o nombre> <monto>")
    amount = tonumber(amount)
    if not t then return end
    if not amount or amount == 0 or amount ~= math.floor(amount) or math.abs(amount) > 10000000 then
        return notify(player, "Uso: /" .. cmd .. " <id o nombre> <monto> (entero, negativo para quitar)", "warning")
    end
    if not hasCharacter(player, t) then return end
    local before = getPlayerMoney(t)
    setPlayerMoney(t, math.max(0, before + amount))
    exports.rp_characters:saveCharacter(t)
    local after = getPlayerMoney(t)
    notify(player, ("%s $%d en efectivo a %s (ahora tiene $%d)."):format(amount > 0 and "Diste" or "Quitaste",
        math.abs(amount), label(t), after), "success")
    if t ~= player then
        notify(t, amount > 0 and ("Un administrador te dio $%d en efectivo."):format(amount)
            or ("Un administrador te quito $%d en efectivo."):format(-amount), "info")
    end
    logAction(player, cmd, t, ("%+d (antes $%d, ahora $%d)"):format(amount, before, after))
end
addCommandHandler("givemoney", giveMoney)
addCommandHandler("apagar", giveMoney)

addCommandHandler("setmoney", function(player, _, query, amount)
    if not guard(player, LEVEL_SUPER) then return end
    local t = target(player, query, "/setmoney <id o nombre> <monto>")
    amount = tonumber(amount)
    if not t then return end
    if not amount or amount < 0 or amount ~= math.floor(amount) or amount > 100000000 then
        return notify(player, "Uso: /setmoney <id o nombre> <monto>", "warning")
    end
    if not hasCharacter(player, t) then return end
    local before = getPlayerMoney(t)
    setPlayerMoney(t, amount)
    exports.rp_characters:saveCharacter(t)
    notify(player, ("Efectivo de %s fijado en $%d."):format(label(t), amount), "success")
    if t ~= player then notify(t, ("Un administrador fijo tu efectivo en $%d."):format(amount), "info") end
    logAction(player, "setmoney", t, ("$%d -> $%d"):format(before, amount))
end)

----------------------------------------------------------------
-- Chat y listas
----------------------------------------------------------------
local function onlineAdmins()
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if levelOf(p) >= LEVEL_ADMIN then list[#list + 1] = p end
    end
    return list
end

addCommandHandler("a", function(player, _, ...)
    if not guard(player) then return end
    local text = table.concat({ ... }, " ")
    if text == "" then return notify(player, "Uso: /a <mensaje>", "warning") end
    local line = ("[Admin %d] %s: %s"):format(levelOf(player), label(player), text)
    for _, p in ipairs(onlineAdmins()) do outputChatBox(line, p, 255, 200, 80) end
    outputServerLog("[rp_admin] " .. line)
end)

addCommandHandler("admins", function(player)
    local list = onlineAdmins()
    if #list == 0 then return outputChatBox("No hay administradores conectados.", player, 200, 200, 200) end
    outputChatBox(("Administradores conectados (%d):"):format(#list), player, 245, 165, 36)
    for _, p in ipairs(list) do
        outputChatBox(("  %s - nivel %d"):format(label(p), levelOf(p)), player, 255, 255, 255)
    end
end)

local HELP = {
    { LEVEL_ADMIN, "Jugadores: /goto /get /tp /pos /heal /sethp /setarmor /freeze /slap /kick" },
    { LEVEL_ADMIN, "Dinero: /givemoney (/apagar) efectivo, /dardinero banco" },
    { LEVEL_ADMIN, "Otros: /a (chat admin) /admins /freecam /forzarpayday" },
    { LEVEL_ADMIN, "Mundo: /crearatm /crearshop /crearcasa /crearropa /crearfaccion /dealer (y sus /borrar...)" },
    { LEVEL_ADMIN, "Debug: /debug [0-3] activa o apaga el debugscript de tu cliente" },
    { LEVEL_ADMIN, "Debug: /copiardebug [X] copia al portapapeles las ultimas X lineas del debug (antes /debug 3)" },
    { LEVEL_SUPER, "Super admin: /setmoney /ban" },
}

-- /debug [0-3]: activa el debugscript del cliente del admin (0 = apagado, 3 = errores, avisos e info).
-- Es un comando del gamemode con permiso por admin_level: no hace falta meter cuentas en acl.xml.
local debugLevels = {}   -- [jugador] = true mientras tiene el debug activado
addCommandHandler("debug", function(player, _, level)
    if not guard(player) then return end
    local n = tonumber(level)
    if level == nil then n = debugLevels[player] and 0 or 3 end
    if not n or n < 0 or n > 3 or n ~= math.floor(n) then
        return notify(player, "Uso: /debug [0-3]  (sin numero: alterna entre 3 y 0)", "warning")
    end
    setPlayerScriptDebugLevel(player, n)
    debugLevels[player] = n > 0 or nil
    notify(player, ("Debugscript %s (nivel %d)."):format(n == 0 and "apagado" or "activado", n), "success")
end)
-- /copiardebug [X]: copia al portapapeles del admin las ultimas X lineas del debugscript (tope 100).
-- El buffer vive en el cliente (c_debug.lua); aqui solo se valida el permiso.
addEvent("rp:admin:copyDebug", true)
addCommandHandler("copiardebug", function(player, _, count)
    if not guard(player) then return end
    local n = count and tonumber(count) or 10
    if not n or n < 1 then
        return notify(player, "Uso: /copiardebug [lineas] (1-100, por defecto 10). Antes activa el debug con /debug 3.", "warning")
    end
    triggerClientEvent(player, "rp:admin:copyDebug", resourceRoot, math.min(math.floor(n), 100))
end)
addCommandHandler("ahelp", function(player)
    if not guard(player) then return end
    local lvl = levelOf(player)
    outputChatBox(("Comandos de admin (tu nivel: %d). <jugador> = ID o nombre."):format(lvl), player, 245, 165, 36)
    for _, h in ipairs(HELP) do
        if lvl >= h[1] then outputChatBox("  " .. h[2], player, 255, 255, 255) end
    end
end)
