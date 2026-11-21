--[[
    rp_help / s_reports.lua
    Reportes enviados desde el panel F1. Se guardan en la tabla `reports`
    y se avisa al instante a los administradores conectados.

    La tabla se crea aqui (CREATE TABLE IF NOT EXISTS) y no en
    rp_database/schema.lua para que el recurso sea independiente.

    Admin (nivel >= HELP.REPORT_ADMIN_LEVEL):
      /reportes                  lista los reportes abiertos o en atencion
      /atender <id>              toma el reporte (avisa al que reporto)
      /cerrarreporte <id> [nota] lo cierra con una nota opcional
]]

local REPORTS_TABLE = [[
CREATE TABLE IF NOT EXISTS reports (
    id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    reporter_account_id INT UNSIGNED NULL,
    reporter_name       VARCHAR(32)  NOT NULL,
    target_account_id   INT UNSIGNED NULL,
    target_name         VARCHAR(32)  NULL,
    category            VARCHAR(16)  NOT NULL,
    text                VARCHAR(700) NOT NULL,
    status              ENUM('open','attending','closed') NOT NULL DEFAULT 'open',
    handled_by          VARCHAR(24)  NULL,
    admin_note          VARCHAR(255) NULL,
    created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at           DATETIME     NULL,
    PRIMARY KEY (id),
    KEY idx_reports_status (status, id),
    KEY idx_reports_reporter (reporter_account_id, id),
    KEY idx_reports_target (target_account_id),
    CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_account_id) REFERENCES accounts (id) ON DELETE SET NULL,
    CONSTRAINT fk_reports_target FOREIGN KEY (target_account_id) REFERENCES accounts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local STATUS_LABEL = { open = "Abierto", attending = "En atencion", closed = "Cerrado" }
local lastReport = {}   -- [accountId] = getTickCount() del ultimo reporte
local tableReady = false

addEvent("rp:onDatabaseReady", false)
addEvent("rp:help:report", true)
addEvent("rp:help:myReports", true)

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function accountOf(player) return exports.rp_login:getPlayerAccountId(player) end
local function adminLevel(player) return exports.rp_login:getPlayerAdminLevel(player) or 0 end
local function isStaff(player) return adminLevel(player) >= HELP.REPORT_ADMIN_LEVEL end
local function displayName(player) return (getPlayerName(player):gsub("_", " ")) end
local function playerId(player) return exports.rp_ids:getPlayerId(player) or "?" end

local function cleanText(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%z\1-\9\11\12\14-\31]", ""):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s == 0 or #s > maxLen then return nil end
    return s
end

local function forEachStaff(fn)
    for _, p in ipairs(getElementsByType("player")) do
        if isStaff(p) then fn(p) end
    end
end

local function findOnlineByAccount(accountId)
    if not accountId then return nil end
    for _, p in ipairs(getElementsByType("player")) do
        if accountOf(p) == accountId then return p end
    end
end

local function createTable()
    dbQuery(function(qh)
        local ok, _, err = dbPoll(qh, 0)
        tableReady = ok and true or false
        if not ok then outputDebugString("[rp_help] No se pudo crear la tabla reports: " .. tostring(err), 1) end
    end, db(), REPORTS_TABLE)
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then createTable() else addEventHandler("rp:onDatabaseReady", root, createTable) end
end)

----------------------------------------------------------------
-- Mis reportes (pestana Reportar)
----------------------------------------------------------------
local function sendMyReports(player)
    local accountId = accountOf(player)
    if not accountId or not tableReady then return end
    dbQuery(function(qh)
        if not isElement(player) then return end
        local rows = dbPoll(qh, 0) or {}
        local list = {}
        for _, r in ipairs(rows) do
            list[#list + 1] = {
                id = r.id, target = r.target_name or "", category = getReportCategoryLabel(r.category) or r.category,
                text = r.text, status = r.status, statusLabel = STATUS_LABEL[r.status] or r.status,
                handledBy = r.handled_by or "", note = r.admin_note or "", date = tostring(r.created_at),
            }
        end
        triggerClientEvent(player, "rp:help:myReports", resourceRoot, list)
    end, db(), "SELECT id, target_name, category, text, status, handled_by, admin_note, created_at FROM reports WHERE reporter_account_id = ? ORDER BY id DESC LIMIT 10", accountId)
end

addEventHandler("rp:help:myReports", resourceRoot, function() sendMyReports(client) end)

----------------------------------------------------------------
-- Nuevo reporte
----------------------------------------------------------------
local function reply(player, ok, message)
    triggerClientEvent(player, "rp:help:reportResult", resourceRoot, ok, message)
end

addEventHandler("rp:help:report", resourceRoot, function(category, target, text)
    local player = client
    local accountId = accountOf(player)
    if not accountId then return reply(player, false, "Tienes que iniciar sesion para reportar.") end
    if not tableReady then return reply(player, false, "Los reportes no estan disponibles ahora. Intentalo en un momento.") end

    local now = getTickCount()
    local last = lastReport[accountId]
    if last and now - last < HELP.REPORT_COOLDOWN * 1000 then
        local wait = math.ceil((HELP.REPORT_COOLDOWN * 1000 - (now - last)) / 1000)
        return reply(player, false, ("Espera %d segundos antes de enviar otro reporte."):format(wait))
    end

    if type(category) ~= "string" or not getReportCategoryLabel(category) then
        return reply(player, false, "Elige un motivo valido.")
    end

    text = cleanText(text, HELP.REPORT_MAX_TEXT)
    if not text or (utf8.len(text) or #text) < HELP.REPORT_MIN_TEXT then
        return reply(player, false, ("Describe lo ocurrido (entre %d y %d caracteres)."):format(HELP.REPORT_MIN_TEXT, HELP.REPORT_MAX_TEXT))
    end

    -- Objetivo opcional (un reporte de bug puede no tener jugador)
    if target ~= nil and target ~= false then
        if not isElement(target) or getElementType(target) ~= "player" then
            return reply(player, false, "Ese jugador ya no esta conectado.")
        end
        if target == player then return reply(player, false, "No puedes reportarte a ti mismo.") end
    else
        target = nil
    end

    lastReport[accountId] = now
    local reporterName = displayName(player)
    local targetName = target and displayName(target) or nil
    local targetAccount = target and accountOf(target) or nil
    local reporterId, targetId = playerId(player), target and playerId(target) or nil

    dbQuery(function(qh)
        local ok, _, insertId = dbPoll(qh, 0)
        if not ok then
            lastReport[accountId] = nil
            if isElement(player) then reply(player, false, "No se pudo guardar el reporte. Avisa a un administrador.") end
            return
        end

        local label = getReportCategoryLabel(category)
        local who = targetName and ("contra %s (ID %s)"):format(targetName, tostring(targetId)) or "sin jugador"
        forEachStaff(function(admin)
            outputChatBox(("[REPORTE #%d] %s (ID %s) %s - %s"):format(insertId, reporterName, tostring(reporterId), who, label), admin, 255, 120, 80)
            outputChatBox(("   %s"):format(text:sub(1, 200)), admin, 230, 230, 230)
            outputChatBox(("   /atender %d  |  /cerrarreporte %d [nota]  |  /reportes"):format(insertId, insertId), admin, 160, 160, 160)
            exports.rp_notify:popup(admin, "Nuevo reporte #" .. insertId, reporterName .. " " .. who, "warning")
        end)

        if isElement(player) then
            reply(player, true, ("Reporte #%d enviado. Un administrador lo revisara pronto."):format(insertId))
            sendMyReports(player)
        end
    end, db(), "INSERT INTO reports (reporter_account_id, reporter_name, target_account_id, target_name, category, text) VALUES (?, ?, ?, ?, ?, ?)",
        accountId, reporterName, targetAccount, targetName, category, text)
end)

addEventHandler("onPlayerQuit", root, function()
    -- el cooldown es por cuenta y se mantiene aunque salga; solo se limpian entradas viejas
    local now = getTickCount()
    for id, t in pairs(lastReport) do
        if now - t > HELP.REPORT_COOLDOWN * 1000 then lastReport[id] = nil end
    end
end)

----------------------------------------------------------------
-- Comandos de jugador
----------------------------------------------------------------
addCommandHandler("ayuda", function(player) triggerClientEvent(player, "rp:help:open", resourceRoot, "home") end)
addCommandHandler("reportar", function(player) triggerClientEvent(player, "rp:help:open", resourceRoot, "report") end)

----------------------------------------------------------------
-- Comandos de administracion
----------------------------------------------------------------
local function requireStaff(player)
    if isStaff(player) then return true end
    notify(player, "No tienes permiso para usar este comando.", "error")
    return false
end

addCommandHandler("reportes", function(player)
    if not requireStaff(player) or not tableReady then return end
    dbQuery(function(qh)
        if not isElement(player) then return end
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then return outputChatBox("No hay reportes pendientes.", player, 120, 220, 140) end
        outputChatBox(("Reportes pendientes (%d):"):format(#rows), player, 255, 200, 80)
        for _, r in ipairs(rows) do
            local state = r.status == "attending" and (" [" .. tostring(r.handled_by) .. "]") or ""
            outputChatBox(("#%d %s -> %s | %s%s | %s"):format(r.id, r.reporter_name, r.target_name or "-",
                getReportCategoryLabel(r.category) or r.category, state, tostring(r.text):sub(1, 70)), player, 220, 220, 220)
        end
    end, db(), "SELECT id, reporter_name, target_name, category, text, status, handled_by FROM reports WHERE status <> 'closed' ORDER BY id ASC LIMIT 15")
end)

local function updateReport(admin, reportId, status, note)
    local adminName = exports.rp_login:getPlayerAccountName(admin) or getPlayerName(admin)
    local sql = status == "closed"
        and "UPDATE reports SET status = 'closed', handled_by = ?, admin_note = ?, closed_at = NOW() WHERE id = ? AND status <> 'closed'"
        or  "UPDATE reports SET status = 'attending', handled_by = ? WHERE id = ? AND status = 'open'"
    local params = status == "closed" and { adminName, note, reportId } or { adminName, reportId }

    dbQuery(function(qh)
        local ok, affected = dbPoll(qh, 0)
        if not isElement(admin) then return end
        if not ok or (affected or 0) == 0 then
            return notify(admin, ("El reporte #%d no existe o ya fue %s."):format(reportId, status == "closed" and "cerrado" or "tomado"), "error")
        end
        dbQuery(function(qh2)
            local rows = dbPoll(qh2, 0) or {}
            local r = rows[1]
            if not r then return end
            local verb = status == "closed" and "cerro" or "esta atendiendo"
            forEachStaff(function(p)
                outputChatBox(("[REPORTE #%d] %s %s el reporte de %s."):format(reportId, adminName, verb, r.reporter_name), p, 255, 160, 90)
            end)
            local reporter = findOnlineByAccount(tonumber(r.reporter_account_id))
            if reporter then
                if status == "closed" then
                    local msg = ("Tu reporte #%d fue cerrado por %s."):format(reportId, adminName)
                    if note and note ~= "" then msg = msg .. " Nota: " .. note end
                    exports.rp_notify:popup(reporter, "Reporte cerrado", msg, "info", 7000)
                else
                    exports.rp_notify:popup(reporter, "Reporte en atencion", ("%s esta atendiendo tu reporte #%d."):format(adminName, reportId), "success", 6000)
                end
                sendMyReports(reporter)
            end
        end, db(), "SELECT reporter_account_id, reporter_name FROM reports WHERE id = ?", reportId)
    end, db(), sql, unpack(params))
end

addCommandHandler("atender", function(player, _, id)
    if not requireStaff(player) or not tableReady then return end
    id = tonumber(id)
    if not id then return notify(player, "Uso: /atender <id>", "info") end
    updateReport(player, id, "attending")
end)

addCommandHandler("cerrarreporte", function(player, _, id, ...)
    if not requireStaff(player) or not tableReady then return end
    id = tonumber(id)
    if not id then return notify(player, "Uso: /cerrarreporte <id> [nota]", "info") end
    local note = cleanText(table.concat({ ... }, " "), 255) or ""
    updateReport(player, id, "closed", note)
end)
