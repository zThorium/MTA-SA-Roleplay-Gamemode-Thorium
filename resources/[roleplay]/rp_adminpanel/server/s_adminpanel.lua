--[[
    rp_adminpanel / s_adminpanel.lua

    Panel CEF de administracion (F10, /adminpanel, /apanel): jugadores en linea
    con vista 3D y acciones, cuentas, IAM (RBAC), registro y catalogo de comandos.
    Cada peticion se revalida aqui con hasPermission (s_rbac.lua).

    Exports: hasPermission(player, perm)
]]

local cooldown = {}   -- [player] = tick
local sendDashboard   -- se define mas abajo

addEvent("rp:adminpanel:open", true)
addEvent("rp:adminpanel:req", true)

local function notify(p, t, k) exports.rp_notify:notify(p, t, k or "info") end
local function db() return exports.rp_database:getConnection() end
local function send(p, kind, data) triggerClientEvent(p, "rp:adminpanel:data", resourceRoot, kind, data) end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end

local function logAction(admin, command, targetAccount, targetName, details)
    outputServerLog(("[rp_adminpanel] %s: %s -> %s | %s"):format(getPlayerName(admin), command,
        tostring(targetName), tostring(details or "")))
    dbExec(db(), [[INSERT INTO admin_log (admin_account_id, admin_name, command, target_account_id, target_name, details)
                   VALUES (NULLIF(?, 0), ?, ?, NULLIF(?, 0), NULLIF(?, ''), NULLIF(?, ''))]],
        exports.rp_login:getPlayerAccountId(admin) or 0, getPlayerName(admin), ("ap:" .. command):sub(1, 32),
        targetAccount or 0, targetName or "", (details or ""):sub(1, 255))
end

----------------------------------------------------------------
-- Datos
----------------------------------------------------------------
local function playerRow(p)
    local x, y, z = getElementPosition(p)
    return {
        id = exports.rp_ids:getPlayerId(p) or 0,
        name = nameOf(p),
        account = exports.rp_login:getPlayerAccountName(p) or "-",
        level = levelOf(p),
        skin = getElementModel(p),
        hp = math.floor(getElementHealth(p)), armor = math.floor(getPedArmor(p)),
        money = getPlayerMoney(p), ping = getPlayerPing(p),
        x = math.floor(x), y = math.floor(y), z = math.floor(z),
        zone = getZoneName(x, y, z), int = getElementInterior(p), dim = getElementDimension(p),
        frozen = isElementFrozen(p),
        loggedIn = exports.rp_login:isPlayerLoggedIn(p),
        look = exports.rp_characters:getCharacterLook(p) or false,
        char = exports.rp_characters:getPlayerCharacterName(p) or false,
    }
end

local function sendPlayers(admin)
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do list[#list + 1] = playerRow(p) end
    table.sort(list, function(a, b) return a.id < b.id end)
    send(admin, "players", list)
end

local function sendOpen(admin)
    send(admin, "open", {
        me = { name = nameOf(admin), level = levelOf(admin), role = ROLE_NAMES[levelOf(admin)] or "?", perms = effectivePerms(admin) },
        catalog = hasPermission(admin, "commands.view") and ADMIN_CATALOG or {},
    })
    sendDashboard(admin)
    if hasPermission(admin, "players.view") then sendPlayers(admin) end
end

local function sendAccounts(admin, query)
    query = tostring(query or ""):sub(1, 24)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local online = {}
        for _, p in ipairs(getElementsByType("player")) do
            local id = exports.rp_login:getPlayerAccountId(p)
            if id then online[id] = true end
        end
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { id = tonumber(r.id), username = r.username, level = tonumber(r.admin_level) or 0,
                last = r.last_login and tostring(r.last_login) or "", online = online[tonumber(r.id)] == true }
        end
        if isElement(admin) then send(admin, "accounts", out) end
    end, db(), "SELECT id, username, admin_level, last_login FROM accounts WHERE username LIKE ? ORDER BY admin_level DESC, username LIMIT 40",
        "%" .. query:gsub("[%%_\\]", "\\%0") .. "%")
end

local function sendIam(admin)
    dbQuery(function(qh)
        local admins = {}
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            local id = tonumber(r.id)
            admins[#admins + 1] = { id = id, username = r.username, level = tonumber(r.admin_level), ov = getOverrides(id) }
        end
        if not isElement(admin) then return end
        local perms = {}
        for _, p in ipairs(PERMS) do perms[#perms + 1] = { key = p.key, group = p.group, label = p.label, locked = p.locked } end
        -- claves como texto: toJSON convertiria tablas numericas con huecos en arrays
        local roles, names = {}, {}
        for lv, set in pairs(getRolePerms()) do roles[tostring(lv)] = set end
        for lv, nm in pairs(ROLE_NAMES) do names[tostring(lv)] = nm end
        local data = { perms = perms, roles = roles, roleNames = names, super = SUPER_LEVEL, admins = admins, builders = {} }
        -- rol builder: cuentas con excepcion "permitir" de world.build (pueden no ser admins)
        dbQuery(function(qh2)
            for _, r in ipairs(dbPoll(qh2, 0) or {}) do
                data.builders[#data.builders + 1] = { id = tonumber(r.id), username = r.username, level = tonumber(r.admin_level) or 0 }
            end
            if isElement(admin) then send(admin, "iam", data) end
        end, db(), [[SELECT a.id, a.username, a.admin_level FROM admin_account_perms ap
                     JOIN accounts a ON a.id = ap.account_id
                     WHERE ap.perm = 'world.build' AND ap.allowed = 1 ORDER BY a.username]])
    end, db(), "SELECT id, username, admin_level FROM accounts WHERE admin_level >= 1 ORDER BY admin_level DESC, username")
end

-- Dar o quitar el rol builder por nombre de cuenta
local function setBuilder(admin, username, add)
    username = tostring(username or ""):sub(1, 32)
    if #username < 2 then return notify(admin, "Escribe el nombre de la cuenta.", "warning") end
    dbQuery(function(qh)
        local row = (dbPoll(qh, 0) or {})[1]
        if not isElement(admin) then return end
        if not row then return notify(admin, "No existe la cuenta " .. username .. ".", "error") end
        local id = tonumber(row.id)
        if setOverride(id, "world.build", add and "allow" or "inherit") then
            logAction(admin, add and "builder+" or "builder-", id, row.username, "world.build")
            for _, p in ipairs(getElementsByType("player")) do
                if exports.rp_login:getPlayerAccountId(p) == id then
                    notify(p, add and "Ahora tienes el rol builder: usa /mapeditor." or "Ya no tienes el rol builder.", "info")
                end
            end
            notify(admin, ("%s %s builder."):format(row.username, add and "ahora es" or "ya no es"), "success")
            sendIam(admin)
        end
    end, db(), "SELECT id, username FROM accounts WHERE username = ? LIMIT 1", username)
end

local function sendLogs(admin)
    dbQuery(function(qh)
        local out = {}
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            out[#out + 1] = { time = tostring(r.created_at), admin = r.admin_name, cmd = r.command,
                target = r.target_name or "", details = r.details or "" }
        end
        if isElement(admin) then send(admin, "logs", out) end
    end, db(), "SELECT created_at, admin_name, command, target_name, details FROM admin_log ORDER BY id DESC LIMIT 80")
end

-- Registro de economía (rp_logs): por personaje (id exacto o parte del nombre) y tipo; vacío = lo último
local function sendEconomy(admin, query, kind)
    query = tostring(query or ""):sub(1, 32):gsub("_", " "):gsub("[%%\\]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local types = {}
    local logsRes = getResourceFromName("rp_logs")
    if logsRes and getResourceState(logsRes) == "running" then
        types = exports.rp_logs:getTypes() or {}
        exports.rp_logs:flush()
    end
    kind = tostring(kind or "")
    if not types[kind] then kind = "" end
    local id = tonumber(query)
    local like = query == "" and "" or ("%" .. query .. "%")
    dbQuery(function(qh)
        local out = {}
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            out[#out + 1] = { time = tostring(r.created_at), type = r.type, actor = r.actor_name or "sistema",
                actorId = r.actor_char_id or "", target = r.target_name or "", targetId = r.target_char_id or "",
                amount = tonumber(r.amount) or 0, details = r.details or "", res = r.resource or "" }
        end
        if isElement(admin) then send(admin, "economy", { rows = out, types = types, query = query, kind = kind }) end
    end, db(), [[SELECT created_at, type, actor_char_id, actor_name, target_char_id, target_name, amount, details, resource
        FROM economy_log
        WHERE (? = '' OR actor_char_id = ? OR target_char_id = ? OR actor_name LIKE ? OR target_name LIKE ?)
          AND (? = '' OR type = ?)
        ORDER BY id DESC LIMIT 100]], query, id or 0, id or 0, like, like, kind, kind)
end

----------------------------------------------------------------
-- Dashboard (metricas). Todo agregado; no expone datos privados.
----------------------------------------------------------------
local startedAt = getRealTime().timestamp

local function runningResources()
    local n, total = 0, 0
    for _, res in ipairs(getResources()) do
        total = total + 1
        if getResourceState(res) == "running" then n = n + 1 end
    end
    return n, total
end

-- Rellena los ultimos 7 dias (hoy incluido) con 0 donde no hay filas
local function series(rows)
    local byDay = {}
    for _, r in ipairs(rows or {}) do byDay[tostring(r.d)] = tonumber(r.n) or 0 end
    local out = {}
    for i = 6, 0, -1 do
        local t = getRealTime(getRealTime().timestamp - i * 86400)
        local key = ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday)
        out[#out + 1] = { d = key:sub(6), n = byDay[key] or 0 }
    end
    return out
end

sendDashboard = function(admin)
    local players, pingSum, levels = getElementsByType("player"), 0, { ["0"] = 0, ["1"] = 0, ["2"] = 0, ["3"] = 0 }
    for _, p in ipairs(players) do
        pingSum = pingSum + getPlayerPing(p)
        local l = tostring(math.min(3, levelOf(p))); levels[l] = levels[l] + 1
    end
    local running, total = runningResources()
    local data = {
        online = #players, maxPlayers = getMaxPlayers(),
        pingAvg = #players > 0 and math.floor(pingSum / #players) or 0,
        levels = levels, resRunning = running, resTotal = total,
        uptime = getRealTime().timestamp - startedAt,
    }
    local c = db()
    dbQuery(function(qh)
        local r = (dbPoll(qh, 0) or {})[1] or {}
        for k, v in pairs(r) do data[k] = tonumber(v) or 0 end
        dbQuery(function(q2)
            data.regs = series(dbPoll(q2, 0))
            dbQuery(function(q3)
                data.logins = series(dbPoll(q3, 0))
                dbQuery(function(q4)
                    data.actions = series(dbPoll(q4, 0))
                    if isElement(admin) then send(admin, "dash", data) end
                end, c, "SELECT DATE(created_at) d, COUNT(*) n FROM admin_log WHERE created_at >= CURDATE() - INTERVAL 6 DAY GROUP BY d")
            end, c, "SELECT DATE(created_at) d, COUNT(*) n FROM login_log WHERE success = 1 AND created_at >= CURDATE() - INTERVAL 6 DAY GROUP BY d")
        end, c, "SELECT DATE(created_at) d, COUNT(*) n FROM accounts WHERE created_at >= CURDATE() - INTERVAL 6 DAY GROUP BY d")
    end, c, [[SELECT
        (SELECT COUNT(*) FROM accounts) accounts,
        (SELECT COUNT(*) FROM characters) characters,
        (SELECT COALESCE(SUM(money), 0) FROM characters) cash,
        (SELECT COALESCE(SUM(bank_money), 0) FROM characters) bank,
        (SELECT COUNT(*) FROM vehicles) vehicles,
        (SELECT COUNT(*) FROM properties) properties,
        (SELECT COUNT(*) FROM factions) factions,
        (SELECT COUNT(*) FROM admin_log WHERE created_at >= CURDATE()) actionsToday]])
end

----------------------------------------------------------------
-- Acciones sobre jugadores
----------------------------------------------------------------
local ACTIONS = {
    goto = "players.goto", bring = "players.bring", heal = "players.heal",
    freeze = "players.freeze", kick = "players.kick",
}

local function act(admin, action, targetId, arg)
    local perm = ACTIONS[action]
    if not perm then return end
    if not hasPermission(admin, perm) then return notify(admin, "No tienes el permiso " .. perm .. ".", "error") end
    local t = exports.rp_ids:getPlayerFromId(targetId)
    if not t then return notify(admin, "Ese jugador ya no esta conectado.", "warning") end
    if t ~= admin and levelOf(t) > levelOf(admin) then
        return notify(admin, "Ese administrador tiene un nivel superior al tuyo.", "error")
    end
    local tName, tAcc = nameOf(t), exports.rp_login:getPlayerAccountId(t)

    if action == "goto" or action == "bring" then
        if t == admin then return end
        local mover, dest = admin, t
        if action == "bring" then mover, dest = t, admin end
        local x, y, z = getElementPosition(dest)
        local el = getPedOccupiedVehicle(mover) or mover
        setElementInterior(el, getElementInterior(dest)); setElementDimension(el, getElementDimension(dest))
        setElementPosition(el, x + 1, y, z)
        if el ~= mover then setElementInterior(mover, getElementInterior(dest)); setElementDimension(mover, getElementDimension(dest)) end
    elseif action == "heal" then
        setElementHealth(t, 100); setPedArmor(t, 100)
    elseif action == "freeze" then
        setElementFrozen(t, not isElementFrozen(t))
        toggleAllControls(t, isElementFrozen(t) == false, true, false)
    elseif action == "kick" then
        if t == admin then return end
        local reason = tostring(arg or ""):sub(1, 80)
        if reason == "" then reason = "Sin motivo" end
        logAction(admin, action, tAcc, tName, reason)
        kickPlayer(t, admin, reason)
        notify(admin, tName .. " fue expulsado.", "success")
        return sendPlayers(admin)
    end
    logAction(admin, action, tAcc, tName)
    notify(admin, ("%s: %s"):format(action, tName), "success")
    sendPlayers(admin)
end

----------------------------------------------------------------
-- IAM
----------------------------------------------------------------
local function setLevel(admin, accountId, level)
    accountId, level = tonumber(accountId), tonumber(level)
    if not accountId or not level or level ~= math.floor(level) or level < 0 or level > SUPER_LEVEL then return end
    if accountId == exports.rp_login:getPlayerAccountId(admin) then
        return notify(admin, "No puedes cambiar tu propio nivel.", "error")
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not rows[1] or not isElement(admin) then return end
        dbExec(db(), "UPDATE accounts SET admin_level = ? WHERE id = ?", level, accountId)
        for _, p in ipairs(getElementsByType("player")) do
            if exports.rp_login:getPlayerAccountId(p) == accountId then
                exports.rp_login:setSessionAdminLevel(p, level)
                notify(p, "Tu rango ahora es: " .. (ROLE_NAMES[level] or level), "info")
            end
        end
        logAction(admin, "setlevel", accountId, rows[1].username, ("%s -> %d"):format(rows[1].admin_level, level))
        notify(admin, ("%s ahora es %s."):format(rows[1].username, ROLE_NAMES[level]), "success")
        sendIam(admin)
    end, db(), "SELECT username, admin_level FROM accounts WHERE id = ?", accountId)
end

----------------------------------------------------------------
-- Despacho de peticiones
----------------------------------------------------------------
local function need(admin, perm)
    if hasPermission(admin, perm) then return true end
    notify(admin, "No tienes el permiso " .. perm .. ".", "error")
    return false
end

addEventHandler("rp:adminpanel:req", resourceRoot, function(kind, a, b, c)
    local admin = client
    if levelOf(admin) < 1 then return end
    local now = getTickCount()
    if cooldown[admin] and now - cooldown[admin] < 150 then return end
    cooldown[admin] = now
    kind = tostring(kind)

    if kind == "dash" then
        sendDashboard(admin)
    elseif kind == "players" then
        if need(admin, "players.view") then sendPlayers(admin) end
    elseif kind == "act" then
        act(admin, tostring(a), tonumber(b), c)
    elseif kind == "accounts" then
        if need(admin, "accounts.view") then sendAccounts(admin, a) end
    elseif kind == "logs" then
        if need(admin, "logs.view") then sendLogs(admin) end
    elseif kind == "economy" then
        if need(admin, "logs.economy") then sendEconomy(admin, a, b) end
    elseif kind == "iam" then
        if need(admin, "iam.manage") then sendIam(admin) end
    elseif kind == "setlevel" then
        if need(admin, "iam.manage") then setLevel(admin, a, b) end
    elseif kind == "roleperm" then
        if not need(admin, "iam.manage") then return end
        local level, perm, allow = tonumber(a), tostring(b), tostring(c) == "1"
        if level and setRolePerm(level, perm, allow) then
            logAction(admin, "roleperm", nil, ROLE_NAMES[level], (allow and "+" or "-") .. perm)
            sendIam(admin)
        end
    elseif kind == "builder" then
        if need(admin, "iam.manage") then setBuilder(admin, a, tostring(b) == "add") end
    elseif kind == "override" then
        if not need(admin, "iam.manage") then return end
        local id, perm = tonumber(a), tostring(b)
        if id and setOverride(id, perm, tostring(c)) then
            logAction(admin, "override", id, nil, perm .. "=" .. tostring(c))
            for _, p in ipairs(getElementsByType("player")) do
                if exports.rp_login:getPlayerAccountId(p) == id then notify(p, "Tus permisos de admin cambiaron; reabre el panel.", "info") end
            end
            sendIam(admin)
        end
    end
end)

local function open(player)
    if levelOf(player) < 1 then
        return notify(player, "No tienes permiso para usar este comando.", "error")
    end
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 400 then return end
    cooldown[player] = now
    triggerClientEvent(player, "rp:adminpanel:show", resourceRoot)
    sendOpen(player)
end

addCommandHandler("adminpanel", open)
addCommandHandler("apanel", open)
addEventHandler("rp:adminpanel:open", resourceRoot, function() open(client) end)
addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)
