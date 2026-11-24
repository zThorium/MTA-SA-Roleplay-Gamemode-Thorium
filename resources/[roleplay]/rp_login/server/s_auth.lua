--[[
    rp_login / s_auth.lua
    Registro e inicio de sesion. Todo lo que llega del cliente se valida aqui:
    el cliente nunca es de confianza.

    - Contrasenas con passwordHash(..., "bcrypt") y passwordVerify, ambos en
      modo asincrono (callback) para no bloquear el servidor.
    - Consultas con dbQuery + callback y parametros "?" (sin concatenar SQL).
]]

sessions = {}           -- [player] = { id, username, adminLevel } (cuenta con sesion iniciada)
local pending = {}      -- [player] = true mientras hay una operacion en curso
local failures = {}     -- [player] = intentos fallidos
local timeouts = {}     -- [player] = timer de expulsion por no iniciar sesion
local onlineAccounts = {} -- [accountId] = player

addEvent("rp:auth:login", true)
addEvent("rp:auth:register", true)
-- Eventos de servidor para otros recursos (source = jugador)
addEvent("rp:onAccountLogin", false)   -- (accountId, username)
addEvent("rp:onAccountLogout", false)  -- (accountId)

local function db()
    return exports.rp_database:getConnection()
end

local function reply(player, ok, message, form)
    if isElement(player) then
        triggerClientEvent(player, "rp:auth:result", resourceRoot, ok, message, form)
    end
end

local function validUsername(u)
    return type(u) == "string" and #u >= AUTH.USERNAME_MIN and #u <= AUTH.USERNAME_MAX
        and u:match("^%a[%w_]*$") ~= nil
end

local function validPassword(p)
    return type(p) == "string" and #p >= AUTH.PASSWORD_MIN and #p <= AUTH.PASSWORD_MAX
end

local function logAttempt(accountId, username, player, success)
    dbExec(db(), "INSERT INTO login_log (account_id, username, serial, ip, success) VALUES (?, ?, ?, ?, ?)",
        accountId, username, getPlayerSerial(player), getPlayerIP(player), success and 1 or 0)
end

local function registerFailure(player)
    failures[player] = (failures[player] or 0) + 1
    if failures[player] >= AUTH.MAX_FAILED_ATTEMPTS then
        kickPlayer(player, "Demasiados intentos fallidos de inicio de sesion")
        return true
    end
    return false
end

-- Comprobaciones comunes antes de atender una peticion del cliente
local function canHandle(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if pending[player] then return false end
    if not exports.rp_database:isReady() then
        reply(player, false, "El servidor aun no esta listo, intentalo en unos segundos.", "login")
        return false
    end
    return true
end

----------------------------------------------------------------
-- Sesion
----------------------------------------------------------------
local function completeLogin(player, row)
    if not isElement(player) then return end

    if isTimer(timeouts[player]) then killTimer(timeouts[player]) end
    timeouts[player], failures[player] = nil, nil

    sessions[player] = { id = row.id, username = row.username, adminLevel = tonumber(row.admin_level) or 0 }
    onlineAccounts[row.id] = player
    setElementData(player, "rp:accountId", row.id, "local")

    dbExec(db(), "UPDATE accounts SET last_login = NOW(), serial = ?, ip = ? WHERE id = ?",
        getPlayerSerial(player), getPlayerIP(player), row.id)

    triggerClientEvent(player, "rp:auth:success", resourceRoot, row.username)
    -- rp_characters escucha este evento y muestra la seleccion de personajes
    triggerEvent("rp:onAccountLogin", player, row.id, row.username)
    outputServerLog(("[rp_login] %s inicio sesion (cuenta #%d, serial %s)"):format(row.username, row.id, getPlayerSerial(player)))
end

----------------------------------------------------------------
-- Login
----------------------------------------------------------------
addEventHandler("rp:auth:login", resourceRoot, function(username, password)
    local player = client
    if not canHandle(player) then return end

    if not validUsername(username) or not validPassword(password) then
        reply(player, false, "Usuario o contrasena incorrectos.", "login")
        registerFailure(player)
        return
    end

    pending[player] = true
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end

        local row = rows and rows[1]
        if not row then
            pending[player] = nil
            logAttempt(nil, username, player, false)
            if not registerFailure(player) then
                reply(player, false, "Usuario o contrasena incorrectos.", "login")
            end
            return
        end

        passwordVerify(password, row.password_hash, {}, function(matches)
            if not isElement(player) then return end
            pending[player] = nil

            if not matches then
                logAttempt(row.id, row.username, player, false)
                if not registerFailure(player) then
                    reply(player, false, "Usuario o contrasena incorrectos.", "login")
                end
                return
            end

            if onlineAccounts[row.id] and isElement(onlineAccounts[row.id]) then
                reply(player, false, "Esta cuenta ya esta conectada.", "login")
                return
            end

            logAttempt(row.id, row.username, player, true)
            completeLogin(player, row)
        end)
    end, db(), "SELECT * FROM accounts WHERE username = ? LIMIT 1", username)
end)

----------------------------------------------------------------
-- Registro
----------------------------------------------------------------
addEventHandler("rp:auth:register", resourceRoot, function(username, password)
    local player = client
    if not canHandle(player) then return end

    if not validUsername(username) then
        reply(player, false, ("El usuario debe tener entre %d y %d caracteres, empezar por letra y usar solo letras, numeros o _."):format(AUTH.USERNAME_MIN, AUTH.USERNAME_MAX), "register")
        return
    end
    if not validPassword(password) then
        reply(player, false, ("La contrasena debe tener entre %d y %d caracteres."):format(AUTH.PASSWORD_MIN, AUTH.PASSWORD_MAX), "register")
        return
    end

    pending[player] = true
    local serial = getPlayerSerial(player)

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        rows = rows or {}

        local taken, serialCount = false, 0
        for _, r in ipairs(rows) do
            if r.kind == "name" then taken = true else serialCount = tonumber(r.total) or 0 end
        end

        if taken then
            pending[player] = nil
            reply(player, false, "Ese nombre de usuario ya esta en uso.", "register")
            return
        end
        if serialCount >= AUTH.MAX_ACCOUNTS_PER_SERIAL then
            pending[player] = nil
            reply(player, false, "Has alcanzado el limite de cuentas para este equipo.", "register")
            return
        end

        passwordHash(password, "bcrypt", { cost = AUTH.BCRYPT_COST }, function(hash)
            if not isElement(player) then return end
            if not hash then
                pending[player] = nil
                reply(player, false, "No se pudo procesar la contrasena. Intentalo de nuevo.", "register")
                return
            end
            dbQuery(function(insertQh)
                -- exito: result, filasAfectadas, idInsertado | error: false, codigo, mensaje
                local result, info, insertId = dbPoll(insertQh, 0)
                if not isElement(player) then return end
                pending[player] = nil

                if not result then
                    -- 1062 = clave duplicada (otro jugador registro el nombre a la vez)
                    if info == 1062 then
                        reply(player, false, "Ese nombre de usuario ya esta en uso.", "register")
                    else
                        reply(player, false, "Error al crear la cuenta. Avisa a un administrador.", "register")
                        outputDebugString("[rp_login] Error al registrar " .. username .. ": " .. tostring(insertId), 1)
                    end
                    return
                end

                outputServerLog(("[rp_login] Nueva cuenta %s (#%d)"):format(username, insertId))
                completeLogin(player, { id = insertId, username = username, admin_level = 0 })
            end, db(), "INSERT INTO accounts (username, password_hash, serial, ip) VALUES (?, ?, ?, ?)",
                username, hash, serial, getPlayerIP(player))
        end)
    end, db(),
        "SELECT 'name' AS kind, 1 AS total FROM accounts WHERE username = ? " ..
        "UNION ALL SELECT 'serial' AS kind, COUNT(*) AS total FROM accounts WHERE serial = ?",
        username, serial)
end)

----------------------------------------------------------------
-- Ciclo de vida del jugador
----------------------------------------------------------------
local function startLoginTimeout(player)
    timeouts[player] = setTimer(function()
        if isElement(player) and not sessions[player] then
            kickPlayer(player, "Tiempo de inicio de sesion agotado")
        end
    end, AUTH.LOGIN_TIMEOUT, 1)
end

addEventHandler("onPlayerJoin", root, function()
    startLoginTimeout(source)
end)

addEventHandler("onPlayerQuit", root, function()
    local session = sessions[source]
    if session then
        onlineAccounts[session.id] = nil
        outputServerLog(("[rp_login] %s cerro sesion"):format(session.username))
    end
    if isTimer(timeouts[source]) then killTimer(timeouts[source]) end
    sessions[source], pending[source], failures[source], timeouts[source] = nil, nil, nil, nil
end)

-- El nombre lo controla el gamemode (nombre del personaje), no el jugador
addEventHandler("onPlayerChangeNick", root, function(_, _, byUser)
    if byUser then cancelEvent() end
end)

-- Si el recurso se reinicia con jugadores dentro, vuelven a la pantalla de login
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if not isPedDead(player) then killPed(player) end
        setElementData(player, "rp:accountId", false, "local")
        startLoginTimeout(player)
    end
end)

-- Al detenerse, avisa a otros recursos (rp_characters guarda y cierra el personaje)
addEventHandler("onResourceStop", resourceRoot, function()
    for player, session in pairs(sessions) do
        triggerEvent("rp:onAccountLogout", player, session.id)
    end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function isPlayerLoggedIn(player)
    return sessions[player] ~= nil
end

function getPlayerAccountId(player)
    return sessions[player] and sessions[player].id or false
end

function getPlayerAccountName(player)
    return sessions[player] and sessions[player].username or false
end

function getPlayerAdminLevel(player)
    return sessions[player] and sessions[player].adminLevel or 0
end

-- Cambia el nivel en la sesion activa (el panel de admin lo usa tras escribir en la BD)
function setSessionAdminLevel(player, level)
    if not sessions[player] then return false end
    sessions[player].adminLevel = math.max(0, math.min(255, math.floor(tonumber(level) or 0)))
    return true
end
