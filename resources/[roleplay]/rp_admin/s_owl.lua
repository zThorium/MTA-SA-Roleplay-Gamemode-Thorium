--[[
    rp_admin / s_owl.lua
    Nucleo de comandos de administracion con la sintaxis de OwlGaming.
    <jugador> = ID o parte del nombre; <cuenta> = jugador en linea o nombre de cuenta.

    Nivel 1 (admin):
        /check <jugador>                    ficha: cuenta, personaje, dinero, posicion, sanciones
        /history <cuenta>                   ultimas sanciones de la cuenta
        /gethere <jugador>                  alias de /get
        /sendto <jugador> <jugador2>        lleva al primero junto al segundo
        /setint <jugador> <interior>        cambia el interior (0-255)
        /setdim <jugador> <dimension>       cambia la dimension (0-65535)
        /recon [jugador]                    espectar a un jugador; sin argumento, dejar de espectar
        /warn <jugador> <motivo>            aviso formal (queda en /history)
        /jail <jugador> <minutos> <motivo>  jail OOC de administracion (persiste al reconectar)
        /unjail <jugador>                   sacar del jail OOC
        /jailed                             jugadores en jail OOC
        /pmute <jugador> <minutos> [motivo] silenciar sus chats OOC (/b y /pm)
        /unmute <jugador>                   quitar el silencio
    Nivel 2 (admin senior):
        /findalts <cuenta>                  cuentas que compartieron serial o IP
        /findip <ip>  /findserial <serial>  cuentas que entraron con esa IP o serial
    Nivel 3 (super admin):
        /oban <cuenta> <horas> [motivo]     banear una cuenta desconectada (por su ultimo serial)
        /unban <cuenta o serial>            quitar los baneos de ese serial

    /pkick /skick /pban /sban estan en s_commands.lua (s = sin aviso en el chat global).
    Todo queda en admin_log.
]]

local LEVEL_SENIOR = 2
local SANCTIONS = { "kick", "ban", "oban", "unban", "warn", "jail", "unjail", "pmute", "unmute" }
local SANCTIONS_IN = ("?,"):rep(#SANCTIONS):sub(1, -2)   -- placeholders para IN (...)

addEvent("rp:onCharacterSpawn", false)

-- Celdas de la comisaria de LS (interior 6) en una dimension propia para el jail OOC
local JAIL = { x = 264.4, y = 77.8, z = 1001.04, interior = 6, dimension = 65000, radius = 8 }
local RELEASE = { x = 1552.5, y = -1675.6, z = 16.2 }   -- puerta de la comisaria de Pershing Square
local JAIL_TICK_MS = 5000

local function accountOf(p) return exports.rp_login:getPlayerAccountId(p) end
local function now() return getRealTime().timestamp end

-- Resuelve una cuenta en linea o por nombre: callback({ id, username, serial, ip, player })
local function resolveAccount(admin, query, usage, callback)
    if not query then return notify(admin, "Uso: " .. usage, "warning") end
    local t = exports.rp_ids:findPlayer(query)
    local id = t and accountOf(t)
    local sql = id and "SELECT id, username, serial, ip FROM accounts WHERE id = ?"
        or "SELECT id, username, serial, ip FROM accounts WHERE username = ?"
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local row = rows and rows[1]
        if not isElement(admin) then return end
        if not row then return notify(admin, "No se encontro ninguna cuenta con ese nombre o ID.", "warning") end
        row.player = t
        callback(row)
    end, db(), sql, id or query)
end

-- admin_log para acciones sobre cuentas desconectadas (logAction necesita al jugador en linea)
local function logAccount(admin, command, account, details)
    outputServerLog(("[rp_admin] %s /%s -> cuenta %s | %s"):format(getPlayerName(admin), command, account.username, details or ""))
    dbExec(db(), [[INSERT INTO admin_log (admin_account_id, admin_name, command, target_account_id, target_name, details)
                   VALUES (NULLIF(?, 0), ?, ?, ?, ?, NULLIF(?, ''))]],
        accountOf(admin) or 0, getPlayerName(admin), command, account.id, account.username, (details or ""):sub(1, 255))
end

local function chat(p, text, r, g, b) outputChatBox(text, p, r or 255, g or 255, b or 255) end

----------------------------------------------------------------
-- Informacion
----------------------------------------------------------------
addCommandHandler("check", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/check <id o nombre>")
    if not t then return end
    local accountId, charId = accountOf(t), exports.rp_characters:getPlayerCharacterId(t)
    local x, y, z = getElementPosition(t)
    chat(player, ("Ficha de %s:"):format(label(t)), 255, 126, 0)
    chat(player, ("   Cuenta: %s (#%s) - admin nivel %d - ping %d"):format(
        tostring(exports.rp_login:getPlayerAccountName(t) or "-"), tostring(accountId or "-"), levelOf(t), getPlayerPing(t)))
    if levelOf(player) >= LEVEL_SENIOR then
        chat(player, ("   Serial: %s - IP: %s"):format(getPlayerSerial(t), getPlayerIP(t)))
    end
    chat(player, ("   Vida %d - chaleco %d - efectivo $%d"):format(math.floor(getElementHealth(t)), math.floor(getPedArmor(t)), getPlayerMoney(t)))
    chat(player, ("   Posicion: %.1f, %.1f, %.1f - interior %d - dimension %d"):format(x, y, z,
        getElementInterior(t), getElementDimension(t)))
    if not accountId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) or not rows then return end
        local r = rows[1] or {}
        chat(player, ("   Personaje #%s - banco $%s - sanciones: %d (detalle con /history %s)"):format(
            tostring(charId or "-"), tostring(r.bank or "-"), tonumber(r.sanctions) or 0, tostring(idOf(t))))
    end, db(), [[SELECT (SELECT bank_money FROM characters WHERE id = ?) AS bank,
                        (SELECT COUNT(*) FROM admin_log WHERE target_account_id = ? AND command IN (]] .. SANCTIONS_IN .. [[)) AS sanctions]],
        charId or 0, accountId, unpack(SANCTIONS))
end)

addCommandHandler("history", function(player, _, query)
    if not guard(player) then return end
    resolveAccount(player, query, "/history <id, nombre o cuenta>", function(acc)
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0)
            if not isElement(player) or not rows then return end
            chat(player, ("Sanciones de la cuenta %s (#%d):"):format(acc.username, acc.id), 255, 126, 0)
            if #rows == 0 then return chat(player, "   Ninguna.") end
            for _, r in ipairs(rows) do
                chat(player, ("   %s  /%s por %s%s"):format(tostring(r.created_at), r.command, r.admin_name,
                    r.details and (" - " .. r.details) or ""))
            end
        end, db(), [[SELECT command, admin_name, details, created_at FROM admin_log
                     WHERE target_account_id = ? AND command IN (]] .. SANCTIONS_IN .. [[) ORDER BY id DESC LIMIT 15]], acc.id, unpack(SANCTIONS))
    end)
end)

-- Cuentas que entraron con alguno de estos valores de serial o IP
local function listAccounts(player, title, sql, ...)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) or not rows then return end
        chat(player, title, 255, 126, 0)
        if #rows == 0 then return chat(player, "   Ninguna.") end
        for i, r in ipairs(rows) do
            if i > 20 then return chat(player, ("   ... y %d mas."):format(#rows - 20), 180, 180, 180) end
            chat(player, ("   #%d %s - ultima vez %s"):format(r.id, r.username, tostring(r.last_seen)))
        end
    end, db(), sql, ...)
end

local ALTS_SQL = [[SELECT a.id, a.username, MAX(l.created_at) AS last_seen FROM login_log l
                   JOIN accounts a ON a.id = l.account_id
                   WHERE l.success = 1 AND (%s) GROUP BY a.id, a.username ORDER BY last_seen DESC LIMIT 50]]

addCommandHandler("findalts", function(player, _, query)
    if not guard(player, LEVEL_SENIOR) then return end
    resolveAccount(player, query, "/findalts <id, nombre o cuenta>", function(acc)
        listAccounts(player, ("Cuentas que compartieron serial o IP con %s:"):format(acc.username),
            ALTS_SQL:format([[l.serial IN (SELECT serial FROM login_log WHERE account_id = ? AND serial IS NOT NULL)
                              OR l.ip IN (SELECT ip FROM login_log WHERE account_id = ? AND ip IS NOT NULL)]]), acc.id, acc.id)
        logAction(player, "findalts", nil, acc.username)
    end)
end)

addCommandHandler("findip", function(player, _, ip)
    if not guard(player, LEVEL_SENIOR) then return end
    if not ip or #ip > 45 then return notify(player, "Uso: /findip <ip>", "warning") end
    listAccounts(player, "Cuentas que entraron con la IP " .. ip .. ":", ALTS_SQL:format("l.ip = ?"), ip)
    logAction(player, "findip", nil, ip)
end)

addCommandHandler("findserial", function(player, _, serial)
    if not guard(player, LEVEL_SENIOR) then return end
    if not serial or #serial ~= 32 then return notify(player, "Uso: /findserial <serial de 32 caracteres>", "warning") end
    listAccounts(player, "Cuentas que entraron con ese serial:", ALTS_SQL:format("l.serial = ?"), serial:upper())
    logAction(player, "findserial", nil, serial)
end)

----------------------------------------------------------------
-- Teletransporte e interiores
----------------------------------------------------------------
addCommandHandler("gethere", function(player, _, query) executeCommandHandler("get", player, query) end)

addCommandHandler("sendto", function(player, _, q1, q2)
    if not guard(player) then return end
    local usage = "/sendto <jugador> <jugador destino>"
    local t = target(player, q1, usage)
    local dest = t and target(player, q2, usage)
    if not dest or t == dest or not outranks(player, t) then return end
    local x, y, z = besides(dest)
    moveTo(t, x, y, z, getElementInterior(dest), getElementDimension(dest))
    notify(player, ("Llevaste a %s junto a %s."):format(label(t), label(dest)), "success")
    notify(t, "Un administrador te teletransporto.", "info")
    logAction(player, "sendto", t, label(dest))
end)

local function setWorld(player, cmd, query, value, max, apply)
    if not guard(player) then return end
    local usage = ("/%s <id o nombre> <0-%d>"):format(cmd, max)
    local t = target(player, query, usage)
    value = tonumber(value)
    if not t then return end
    if not value or value < 0 or value > max or value ~= math.floor(value) then return notify(player, "Uso: " .. usage, "warning") end
    if not outranks(player, t) then return end
    local veh = getPedOccupiedVehicle(t)
    if veh and getVehicleController(veh) == t then
        apply(veh, value)
        for _, occ in pairs(getVehicleOccupants(veh)) do apply(occ, value) end
    else
        if veh then removePedFromVehicle(t) end
        apply(t, value)
    end
    notify(player, ("%s de %s fijado en %d."):format(cmd == "setint" and "Interior" or "Dimension", label(t), value), "success")
    logAction(player, cmd, t, tostring(value))
end
addCommandHandler("setint", function(p, cmd, q, v) setWorld(p, cmd, q, v, 255, setElementInterior) end)
addCommandHandler("setdim", function(p, cmd, q, v) setWorld(p, cmd, q, v, 65535, setElementDimension) end)

----------------------------------------------------------------
-- /recon: el admin queda invisible y pegado bajo el objetivo; la camara lo sigue
----------------------------------------------------------------
local recon = {}   -- [admin] = { target, x, y, z, interior, dimension, timer }

local function stopRecon(admin)
    local r = recon[admin]
    if not r then return end
    recon[admin] = nil
    if isTimer(r.timer) then killTimer(r.timer) end
    if not isElement(admin) then return end
    detachElements(admin)
    setElementInterior(admin, r.interior)
    setElementDimension(admin, r.dimension)
    setElementPosition(admin, r.x, r.y, r.z)
    setElementAlpha(admin, 255)
    setElementCollisionsEnabled(admin, true)
    setElementFrozen(admin, false)
    setCameraInterior(admin, r.interior)
    setCameraTarget(admin, admin)
end

local function follow(admin, t)
    setElementInterior(admin, getElementInterior(t))
    setElementDimension(admin, getElementDimension(t))
    setCameraInterior(admin, getElementInterior(t))
    attachElements(admin, t, 0, 0, -6)
    setCameraTarget(admin, t)
end

addCommandHandler("recon", function(player, _, query)
    if not guard(player) then return end
    if not query then
        if not recon[player] then return notify(player, "Uso: /recon <id o nombre> (sin argumento deja de espectar)", "warning") end
        stopRecon(player)
        return notify(player, "Dejaste de espectar.", "success")
    end
    local t = target(player, query, "/recon <id o nombre>")
    if not t or t == player then return end
    if getPedOccupiedVehicle(player) then return notify(player, "Bajate del vehiculo antes de espectar.", "warning") end
    if not recon[player] then
        local x, y, z = getElementPosition(player)
        recon[player] = { x = x, y = y, z = z, interior = getElementInterior(player), dimension = getElementDimension(player) }
        setElementAlpha(player, 0)
        setElementCollisionsEnabled(player, false)
        setElementFrozen(player, true)
    end
    local r = recon[player]
    r.target = t
    follow(player, t)
    if isTimer(r.timer) then killTimer(r.timer) end
    r.timer = setTimer(function()
        if not isElement(t) then
            stopRecon(player)
            return notify(player, "El jugador espectado se desconecto.", "info")
        end
        if getElementInterior(player) ~= getElementInterior(t) or getElementDimension(player) ~= getElementDimension(t) then
            follow(player, t)
        end
    end, 1000, 0)
    notify(player, ("Espectando a %s. /recon para salir."):format(label(t)), "success")
    logAction(player, "recon", t)
end)

-- shortcut: si el admin sale espectando, rp_characters puede guardar la posicion bajo el objetivo;
-- si pasa, mover el guardado de posicion a despues de este handler.
addEventHandler("onPlayerQuit", root, function()
    stopRecon(source)
    for admin, r in pairs(recon) do
        if r.target == source then stopRecon(admin) notify(admin, "El jugador espectado se desconecto.", "info") end
    end
end)

----------------------------------------------------------------
-- Avisos
----------------------------------------------------------------
addCommandHandler("warn", function(player, _, query, ...)
    if not guard(player) then return end
    local t = target(player, query, "/warn <id o nombre> <motivo>")
    local reason = table.concat({ ... }, " ")
    if not t then return end
    if #reason < 3 then return notify(player, "Uso: /warn <id o nombre> <motivo>", "warning") end
    if t == player or not outranks(player, t) then return end
    exports.rp_notify:popup(t, "Aviso de administracion", ("%s te dio un aviso: %s"):format(nameOf(player), reason), "warning")
    chat(t, ("[Aviso] %s: %s"):format(nameOf(player), reason), 255, 120, 120)
    notify(player, ("Avisaste a %s. Motivo: %s"):format(label(t), reason), "success")
    logAction(player, "warn", t, reason)
end)

----------------------------------------------------------------
-- Jail OOC
----------------------------------------------------------------
local jailed = {}   -- [jugador] = { minutes, reason, ticks }

local function putInCell(p)
    if getPedOccupiedVehicle(p) then removePedFromVehicle(p) end
    setElementInterior(p, JAIL.interior)
    setElementDimension(p, JAIL.dimension)
    setElementPosition(p, JAIL.x, JAIL.y, JAIL.z)
end

local function saveJail(p, minutes, reason)
    local id = accountOf(p)
    if id then dbExec(db(), "UPDATE accounts SET ojail_minutes = ?, ojail_reason = ? WHERE id = ?", minutes, reason, id) end
end

local function jail(p, minutes, reason)
    jailed[p] = { minutes = minutes, reason = reason, ticks = 0 }
    putInCell(p)
    notify(p, ("Estas en jail OOC %d min. Motivo: %s"):format(minutes, reason), "warning", 10000)
end

local function release(p)
    jailed[p] = nil
    saveJail(p, 0, nil)
    setElementInterior(p, 0)
    setElementDimension(p, 0)
    setElementPosition(p, RELEASE.x, RELEASE.y, RELEASE.z)
    notify(p, "Cumpliste el jail OOC. Respeta las normas.", "success")
end

-- Cada 5 s devuelve a la celda a quien salga; cada minuto descuenta (solo cuenta el tiempo conectado)
setTimer(function()
    for p, j in pairs(jailed) do
        if not isElement(p) then
            jailed[p] = nil
        else
            local x, y, z = getElementPosition(p)
            if getElementDimension(p) ~= JAIL.dimension or getElementInterior(p) ~= JAIL.interior
                or getDistanceBetweenPoints3D(x, y, z, JAIL.x, JAIL.y, JAIL.z) > JAIL.radius then
                putInCell(p)
            end
            j.ticks = j.ticks + 1
            if j.ticks >= 60000 / JAIL_TICK_MS then
                j.ticks = 0
                j.minutes = j.minutes - 1
                if j.minutes <= 0 then release(p) else saveJail(p, j.minutes, j.reason) end
            end
        end
    end
end, JAIL_TICK_MS, 0)

addCommandHandler("jail", function(player, _, query, minutes, ...)
    if not guard(player) then return end
    local usage = "/jail <id o nombre> <minutos 1-1440> <motivo>"
    local t = target(player, query, usage)
    minutes = tonumber(minutes)
    local reason = table.concat({ ... }, " "):sub(1, 128)
    if not t then return end
    if not minutes or minutes < 1 or minutes > 1440 or minutes ~= math.floor(minutes) or #reason < 3 then
        return notify(player, "Uso: " .. usage, "warning")
    end
    if t == player or not outranks(player, t) then return end
    if not hasCharacter(player, t) then return end
    jail(t, minutes, reason)
    saveJail(t, minutes, reason)
    outputChatBox(("[Admin] %s fue enviado al jail OOC %d min. Motivo: %s"):format(label(t), minutes, reason), root, 255, 120, 120)
    logAction(player, "jail", t, ("%d min | %s"):format(minutes, reason))
end)

addCommandHandler("unjail", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/unjail <id o nombre>")
    if not t then return end
    if not jailed[t] then return notify(player, label(t) .. " no esta en jail OOC.", "warning") end
    release(t)
    notify(player, ("Sacaste a %s del jail OOC."):format(label(t)), "success")
    logAction(player, "unjail", t)
end)

addCommandHandler("jailed", function(player)
    if not guard(player) then return end
    chat(player, "Jugadores en jail OOC:", 255, 126, 0)
    local n = 0
    for p, j in pairs(jailed) do
        if isElement(p) then
            n = n + 1
            chat(player, ("   %s - %d min - %s"):format(label(p), j.minutes, j.reason or ""))
        end
    end
    if n == 0 then chat(player, "   Ninguno.") end
end)

----------------------------------------------------------------
-- Silencio de chats OOC. rp_chat lee la elementData "rp:mutedUntil" (timestamp, sin sincronizar).
----------------------------------------------------------------
local function setMute(p, untilTs)
    if untilTs then setElementData(p, "rp:mutedUntil", untilTs, false) else removeElementData(p, "rp:mutedUntil") end
    local id = accountOf(p)
    if id then
        dbExec(db(), "UPDATE accounts SET mute_until = IF(? = 0, NULL, FROM_UNIXTIME(?)) WHERE id = ?", untilTs or 0, untilTs or 0, id)
    end
end

addCommandHandler("pmute", function(player, _, query, minutes, ...)
    if not guard(player) then return end
    local usage = "/pmute <id o nombre> <minutos 1-10080> [motivo]"
    local t = target(player, query, usage)
    minutes = tonumber(minutes)
    if not t then return end
    if not minutes or minutes < 1 or minutes > 10080 or minutes ~= math.floor(minutes) then return notify(player, "Uso: " .. usage, "warning") end
    if t == player or not outranks(player, t) then return end
    local reason = table.concat({ ... }, " ")
    setMute(t, now() + minutes * 60)
    notify(t, ("Un administrador silencio tus chats OOC (/b, /pm) %d min.%s"):format(minutes,
        reason ~= "" and (" Motivo: " .. reason) or ""), "warning", 8000)
    notify(player, ("Silenciaste a %s %d min."):format(label(t), minutes), "success")
    logAction(player, "pmute", t, ("%d min%s"):format(minutes, reason ~= "" and (" | " .. reason) or ""))
end)

addCommandHandler("unmute", function(player, _, query)
    if not guard(player) then return end
    local t = target(player, query, "/unmute <id o nombre>")
    if not t then return end
    setMute(t, nil)
    notify(t, "Ya puedes usar los chats OOC.", "info")
    notify(player, ("Quitaste el silencio a %s."):format(label(t)), "success")
    logAction(player, "unmute", t)
end)

-- Al entrar: recupera silencio y jail pendientes de la cuenta
addEventHandler("rp:onCharacterSpawn", root, function()
    local p, id = source, accountOf(source)
    if not id then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local r = rows and rows[1]
        if not r or not isElement(p) then return end
        local mute = tonumber(r.mute_ts)
        if mute and mute > now() then setElementData(p, "rp:mutedUntil", mute, false) end
        local minutes = tonumber(r.ojail_minutes) or 0
        if minutes > 0 and not jailed[p] then jail(p, minutes, r.ojail_reason or "") end
    end, db(), "SELECT ojail_minutes, ojail_reason, UNIX_TIMESTAMP(mute_until) AS mute_ts FROM accounts WHERE id = ?", id)
end)

addEventHandler("onPlayerQuit", root, function() jailed[source] = nil end)

----------------------------------------------------------------
-- Baneos de cuentas desconectadas
----------------------------------------------------------------
addCommandHandler("oban", function(player, _, query, hours, ...)
    if not guard(player, LEVEL_SUPER) then return end
    local usage = "/oban <cuenta> <horas, 0 = permanente> [motivo]"
    hours = tonumber(hours)
    if not hours or hours < 0 then return notify(player, "Uso: " .. usage, "warning") end
    local reason = table.concat({ ... }, " ")
    if reason == "" then reason = "Sin motivo" end
    resolveAccount(player, query, usage, function(acc)
        if acc.player then return notify(player, "Esa cuenta esta en linea: usa /ban.", "warning") end
        if not acc.serial then return notify(player, "Esa cuenta no tiene serial guardado.", "error") end
        if not addBan(nil, nil, acc.serial, player, reason, math.floor(hours * 3600)) then
            return notify(player, "No se pudo banear: agrega resource.rp_admin al grupo Admin en acl.xml.", "error")
        end
        local length = hours == 0 and "permanente" or (hours .. " h")
        logAccount(player, "oban", acc, ("%s | %s | serial %s"):format(length, reason, acc.serial))
        notify(player, ("Baneaste la cuenta %s (%s). Motivo: %s"):format(acc.username, length, reason), "success")
    end)
end)

addCommandHandler("unban", function(player, _, query)
    if not guard(player, LEVEL_SUPER) then return end
    local usage = "/unban <cuenta o serial>"
    local function liftSerialBans(serial, acc)
        local n = 0
        for _, ban in ipairs(getBans()) do
            if getBanSerial(ban) == serial then
                removeBan(ban, player)
                n = n + 1
            end
        end
        if n == 0 then return notify(player, "No hay baneos para ese serial.", "info") end
        if acc then logAccount(player, "unban", acc, serial) else logAction(player, "unban", nil, serial) end
        notify(player, ("Quitaste %d baneo(s) del serial %s."):format(n, serial), "success")
    end
    if query and #query == 32 and query:match("^%x+$") then return liftSerialBans(query:upper()) end
    resolveAccount(player, query, usage, function(acc)
        if not acc.serial then return notify(player, "Esa cuenta no tiene serial guardado.", "error") end
        liftSerialBans(acc.serial, acc)
    end)
end)
