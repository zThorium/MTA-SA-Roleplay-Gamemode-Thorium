--[[
    rp_logs / s_logs.lua  (servidor)

    Registro de economía y objetos en la tabla economy_log: quién movió dinero, ítems, casas o
    vehículos, a quién, cuánto, desde qué recurso y dónde. Sirve para investigar dupeos y abusos.
    Las filas se acumulan en una cola y se escriben en lote (nunca bloquea el servidor).
    Red de seguridad: cada WATCH_MS mira el efectivo de cada jugador y registra los saltos grandes
    (cash_jump), por si el dinero entró por un sitio que aún no está enganchado.

    Exports (servidor):
        log(tipo, actor, objetivo, cantidad, detalle) -> true | false, motivo
            tipo      clave de LOGS.TYPES (s_config.lua)
            actor     jugador, id de personaje o nil (sistema)
            objetivo  jugador, id de personaje, { id = n, name = "..." } (desconectado),
                      texto (p. ej. "Banco", "Facción 3") o nil
            cantidad  dinero o número de ítems (entero; puede ser negativo)
            detalle   texto libre de hasta 255 caracteres (ítem, id de casa, motivo...)
        flush()     escribe la cola ya (lo usan las pruebas)
        getTypes()  { [tipo] = descripción }
    Admin:
        /logs <nombre o id de personaje> [tipo]   últimos movimientos en el chat (permiso logs.economy)
]]

local queue = {}       -- filas pendientes de escribir
local lastCash = {}    -- [player] = efectivo en la última mirada
local searchCooldown = {}

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)

local function db() return exports.rp_database:getConnection() end
local function debug(msg, level) outputDebugString("[rp_logs] " .. msg, level or 3) end

local COLUMNS = "type, actor_char_id, actor_name, target_char_id, target_name, amount, details, resource, x, y, z, serial"
local ROW_PLACEHOLDERS = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
local PER_ROW = 12

----------------------------------------------------------------
-- Escritura en lote
----------------------------------------------------------------
function flush()
    if #queue == 0 then return true end
    local conn = db()
    if not conn then return false end
    local rows = queue
    queue = {}
    local holders, args = {}, {}
    for i, r in ipairs(rows) do
        holders[i] = ROW_PLACEHOLDERS
        local base = (i - 1) * PER_ROW
        args[base + 1], args[base + 2], args[base + 3] = r.type, r.actorId, r.actorName
        args[base + 4], args[base + 5], args[base + 6] = r.targetId, r.targetName, r.amount
        args[base + 7], args[base + 8], args[base + 9] = r.details, r.resource, r.x
        args[base + 10], args[base + 11], args[base + 12] = r.y, r.z, r.serial
    end
    local sql = "INSERT INTO economy_log (" .. COLUMNS .. ") VALUES " .. table.concat(holders, ", ")   -- estandar:sql-seguro COLUMNS es texto fijo y holders son "(?, ...)"; los valores van como parámetros
    if not dbExec(conn, sql, unpack(args)) then
        debug(("no se pudieron escribir %d filas"):format(#rows), 1)
        return false
    end
    return true
end

----------------------------------------------------------------
-- Resolver jugador / personaje / texto
----------------------------------------------------------------
local function playerByCharacter(characterId)
    for _, p in ipairs(getElementsByType("player")) do
        if exports.rp_characters:getPlayerCharacterId(p) == characterId then return p end
    end
end

-- Los nombres se guardan siempre con espacios ("Nombre Apellido"), como los muestra el juego
local function displayName(name)
    return (tostring(name):gsub("_", " ")):sub(1, 32)
end

-- Devuelve id de personaje, nombre y, si es un jugador conectado, el jugador.
local function resolve(who)
    if isElement(who) and getElementType(who) == "player" then
        local id = exports.rp_characters:getPlayerCharacterId(who)
        local name = exports.rp_characters:getPlayerCharacterName(who) or getPlayerName(who)
        return id or nil, displayName(name), who
    end
    local id = tonumber(who)
    if id then
        id = math.floor(id)
        local p = playerByCharacter(id)
        local name = p and exports.rp_characters:getPlayerCharacterName(p)
        return id, name and displayName(name) or nil, p
    end
    if type(who) == "table" then   -- { id = personaje, name = "Nombre_Apellido" } (desconectado)
        local tid = tonumber(who.id)
        return tid and math.floor(tid) or nil, who.name and displayName(who.name) or nil, nil
    end
    if type(who) == "string" and who ~= "" then return nil, who:sub(1, 32), nil end
    return nil, nil, nil
end

function log(kind, actor, target, amount, details)
    kind = tostring(kind or "")
    if not LOGS.TYPES[kind] then
        debug(("tipo desconocido '%s' (desde %s)"):format(kind,
            sourceResource and getResourceName(sourceResource) or "?"), 2)
        return false, "tipo desconocido"
    end
    local actorId, actorName, actorPlayer = resolve(actor)
    local targetId, targetName = resolve(target)
    local x, y, z, serial
    if actorPlayer then
        x, y, z = getElementPosition(actorPlayer)
        serial = getPlayerSerial(actorPlayer)
    end
    queue[#queue + 1] = {
        type = kind, actorId = actorId, actorName = actorName, targetId = targetId, targetName = targetName,
        amount = math.floor(tonumber(amount) or 0),
        details = details ~= nil and tostring(details):sub(1, 255) or nil,
        resource = (sourceResource and getResourceName(sourceResource) or getResourceName(resource)):sub(1, 32),
        x = x, y = y, z = z, serial = serial,
    }
    if #queue >= LOGS.FLUSH_ROWS then flush() end
    return true
end

function getTypes() return LOGS.TYPES end

----------------------------------------------------------------
-- Red de seguridad: saltos grandes de efectivo
----------------------------------------------------------------
local function watchCash()
    for _, p in ipairs(getElementsByType("player")) do
        if exports.rp_characters:getPlayerCharacterId(p) then
            local now = getPlayerMoney(p)
            local before = lastCash[p]
            if before and math.abs(now - before) >= LOGS.CASH_JUMP then
                log("cash_jump", p, nil, now - before, ("de %d a %d en %d s"):format(before, now, LOGS.WATCH_MS / 1000))
            end
            lastCash[p] = now
        end
    end
end

-- Al entrar con un personaje la primera mirada no compara (el efectivo se acaba de cargar)
addEventHandler("rp:onCharacterSpawn", root, function() lastCash[source] = nil end)
addEventHandler("rp:onCharacterLogout", root, function() lastCash[source] = nil end)
addEventHandler("onPlayerQuit", root, function()
    lastCash[source] = nil
    searchCooldown[source] = nil
end)

----------------------------------------------------------------
-- /logs <nombre o id> [tipo]
----------------------------------------------------------------
local function canSearch(p)
    local panel = getResourceFromName("rp_adminpanel")
    if panel and getResourceState(panel) == "running" then
        return exports.rp_adminpanel:hasPermission(p, "logs.economy") == true
    end
    return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 2
end

addCommandHandler("logs", function(admin, _, who, kind)
    if not canSearch(admin) then
        return outputChatBox("No tienes permiso para ver el registro de economía.", admin, 255, 80, 80)
    end
    if not who then
        return outputChatBox("Uso: /logs <nombre o id de personaje> [tipo]", admin, 255, 200, 0)
    end
    if kind and not LOGS.TYPES[kind] then
        return outputChatBox("Tipo desconocido. Mira la lista en RECURSOS.md › rp_logs.", admin, 255, 80, 80)
    end
    local now = getTickCount()
    if searchCooldown[admin] and now - searchCooldown[admin] < 2000 then return end
    searchCooldown[admin] = now
    flush()

    local id = tonumber(who)
    local name = (who:gsub("_", " "))
    local sql = [[SELECT l.created_at, l.type, l.actor_name, l.target_name, l.amount, l.details, l.resource
        FROM economy_log l
        WHERE (l.actor_char_id = ? OR l.target_char_id = ? OR l.actor_name = ? OR l.target_name = ?)
          AND (? = '' OR l.type = ?)
        ORDER BY l.id DESC LIMIT ?]]
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(admin) then return end
        if not rows or #rows == 0 then
            return outputChatBox("Sin movimientos registrados para " .. who .. ".", admin, 255, 200, 0)
        end
        outputChatBox(("— Últimos %d movimientos de %s —"):format(#rows, who), admin, 120, 200, 255)
        for i = #rows, 1, -1 do
            local r = rows[i]
            outputChatBox(("%s  %s  %s → %s  %s  %s"):format(tostring(r.created_at):sub(6, 16), r.type,
                r.actor_name or "sistema", r.target_name or "-", tostring(r.amount),
                (r.details or "") .. " [" .. (r.resource or "?") .. "]"), admin, 220, 220, 220)
        end
    end, db(), sql, id or 0, id or 0, name, name, kind or "", kind or "", LOGS.SEARCH_ROWS)
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local timers = {}
local function start()
    if timers.flush and isTimer(timers.flush) then return end
    dbExec(db(), "DELETE FROM economy_log WHERE created_at < NOW() - INTERVAL ? DAY", LOGS.RETENTION_DAYS)
    timers.flush = setTimer(flush, LOGS.FLUSH_MS, 0)
    timers.watch = setTimer(watchCash, LOGS.WATCH_MS, 0)
    watchCash()   -- primera mirada de los que ya están dentro (reinicio en caliente)
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then start() end
end)
addEventHandler("rp:onDatabaseReady", root, start)
addEventHandler("onResourceStop", resourceRoot, function()
    for _, t in pairs(timers) do if isTimer(t) then killTimer(t) end end
    flush()   -- lo que quede en la cola no se pierde
end)
