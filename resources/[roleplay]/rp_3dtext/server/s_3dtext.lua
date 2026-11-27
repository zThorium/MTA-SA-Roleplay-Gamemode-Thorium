--[[
    rp_3dtext / s_3dtext.lua  (servidor)

    Textos 3D que colocan los admins: el icono de info (modelo 1239, como objeto que el cliente anima) en la
    posicion del admin y un texto que el cliente dibuja solo cuando te acercas.
    La fila de `text3d` es la verdad; el mundo se reconstruye desde ella al arrancar.
    Borrar no elimina la fila (deleted_at/deleted_by) y cada cambio queda en `text3d_log`
    con la cuenta, el nombre del admin y la hora.

    Admin (catalogo en rp_adminpanel/server/s_catalog.lua):
        /create3dtext <texto>          crea un texto 3D donde estas (usa \n para saltar de linea)
        /edit3dtext <id> <texto>       cambia el texto de uno existente
        /3dtextinfo <id>               quien lo creo, cuando, y su historial (tambien los borrados)
        /nearby3dtexts, /goto3dtext, /del3dtext, /delthis3dtext...  gramatica Owl de rp_admin
    Exports (servidor): adminElements(), adminDelete(id, kind, admin)
]]

local texts = {}      -- [id] = { row = fila, icon = objeto }
local cooldown = {}   -- [admin] = tick del ultimo /create3dtext

addEvent("rp:onDatabaseReady", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function log(msg, level) outputDebugString("[rp_3dtext] " .. msg, level or 3) end

local function noPerm(p) notify(p, "No tienes permiso para usar este comando.", "error") end

-- Quien hace la accion: id de cuenta (0 = desconocido), nombre de cuenta y nombre en juego
local function who(admin)
    if not isElement(admin) then return 0, "sistema", "sistema" end
    return exports.rp_login:getPlayerAccountId(admin) or 0,
        exports.rp_login:getPlayerAccountName(admin) or "?",
        getPlayerName(admin)
end

-- Limpia el texto: sin espacios sobrantes, sin codigos de color ni caracteres de control
local function cleanText(text)
    text = tostring(text or ""):gsub("#%x%x%x%x%x%x", ""):gsub("%c", ""):gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function validText(text)
    local n = utf8.len(text) or #text
    return n >= TEXT3D.MIN_LENGTH and n <= TEXT3D.MAX_LENGTH
end

local function addLog(id, action, text, admin)
    local accId, accName, name = who(admin)
    dbExec(db(), [[INSERT INTO text3d_log (text3d_id, action, text, admin_account_id, admin_account, admin_name)
                   VALUES (?, ?, ?, NULLIF(?, 0), ?, ?)]], id, action, text, accId, accName, name)
end

----------------------------------------------------------------
-- Mundo
----------------------------------------------------------------
local function destroyText(id)
    local t = texts[id]
    if not t then return end
    if isElement(t.icon) then destroyElement(t.icon) end
    texts[id] = nil
end

local function spawnText(row)
    local id = tonumber(row.id)
    destroyText(id)
    -- Objeto (no pickup) con el modelo del icono: asi el cliente puede animarlo y ponerle shader
    local icon = createObject(TEXT3D.ICON_MODEL, tonumber(row.x), tonumber(row.y), tonumber(row.z))
    if not icon then return log(("no se pudo crear el icono del texto #%d"):format(id), 1) end
    setElementInterior(icon, tonumber(row.interior) or 0)
    setElementDimension(icon, tonumber(row.dimension) or 0)
    setElementData(icon, "rp:text3d", row.text)
    texts[id] = { row = row, icon = icon }
end

local function loadTexts()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return log("no se pudieron cargar los textos 3D", 1) end
        for _, row in ipairs(rows) do spawnText(row) end
        log(("%d textos 3D cargados"):format(#rows))
    end, db(), "SELECT id, text, x, y, z, interior, dimension FROM text3d WHERE deleted_at IS NULL")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadTexts() else addEventHandler("rp:onDatabaseReady", root, loadTexts) end
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)

----------------------------------------------------------------
-- Comandos de admin
----------------------------------------------------------------
addCommandHandler("create3dtext", function(player, _, ...)
    if not isAdmin(player) then return noPerm(player) end
    local text = cleanText(table.concat({ ... }, " "))
    if not validText(text) then
        return notify(player, ("Uso: /create3dtext <texto> (%d-%d caracteres, \\n para saltar de linea)")
            :format(TEXT3D.MIN_LENGTH, TEXT3D.MAX_LENGTH), "warning")
    end
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < TEXT3D.COOLDOWN_MS then
        return notify(player, "Espera un momento antes de crear otro texto.", "warning")
    end
    cooldown[player] = now

    local x, y, z = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    local accId, accName, name = who(player)
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId or insertId == 0 then
            if isElement(player) then notify(player, "No se pudo guardar el texto 3D.", "error") end
            return log("fallo el INSERT de un texto 3D", 1)
        end
        spawnText({ id = insertId, text = text, x = x, y = y, z = z, interior = int, dimension = dim })
        addLog(insertId, "create", text, player)
        log(("%s (cuenta %s) creo el texto 3D #%d"):format(name, accName, insertId))
        if isElement(player) then notify(player, ("Texto 3D #%d creado."):format(insertId), "success") end
    end, db(), [[INSERT INTO text3d (text, x, y, z, interior, dimension, created_by_account_id, created_by_account, created_by_name)
                 VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, 0), ?, ?)]], text, x, y, z, int, dim, accId, accName, name)
end)

addCommandHandler("edit3dtext", function(player, _, id, ...)
    if not isAdmin(player) then return noPerm(player) end
    id = tonumber(id)
    local text = cleanText(table.concat({ ... }, " "))
    if not id or not validText(text) then
        return notify(player, "Uso: /edit3dtext <id> <texto nuevo>", "warning")
    end
    local t = texts[id]
    if not t then return notify(player, ("No existe el texto 3D #%d."):format(id), "error") end
    t.row.text = text
    if isElement(t.icon) then setElementData(t.icon, "rp:text3d", text) end
    dbExec(db(), "UPDATE text3d SET text = ?, updated_at = NOW() WHERE id = ?", text, id)
    addLog(id, "edit", text, player)
    notify(player, ("Texto 3D #%d actualizado."):format(id), "success")
end)

addCommandHandler("3dtextinfo", function(player, _, id)
    if not isAdmin(player) then return noPerm(player) end
    id = tonumber(id)
    if not id then return notify(player, "Uso: /3dtextinfo <id>", "warning") end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not rows or #rows == 0 then return notify(player, ("No existe el texto 3D #%d."):format(id), "error") end
        local first = rows[1]
        outputChatBox(("Texto 3D #%d %s: \"%s\""):format(id, first.deleted_at and "(BORRADO)" or "", first.text),
            player, 255, 126, 0)
        for _, r in ipairs(rows) do
            if r.action then
                outputChatBox(("   %s  %s por %s (cuenta %s)"):format(r.at, r.action, r.admin_name, r.admin_account),
                    player, 255, 255, 255)
            end
        end
    end, db(), [[SELECT t.text, t.deleted_at, l.action, l.admin_name, l.admin_account,
                        DATE_FORMAT(l.created_at, '%Y-%m-%d %H:%i:%s') AS at
                 FROM text3d t LEFT JOIN text3d_log l ON l.text3d_id = t.id
                 WHERE t.id = ? ORDER BY l.id]], id)
end)

----------------------------------------------------------------
-- Exports para la gramatica Owl de rp_admin
----------------------------------------------------------------
function adminElements()
    local list = {}
    for id, t in pairs(texts) do
        if isElement(t.icon) then
            local x, y, z = getElementPosition(t.icon)
            local label = t.row.text
            if utf8.len(label) > 40 then label = utf8.sub(label, 1, 40) .. "..." end
            list[#list + 1] = { id = id, x = x, y = y, z = z, interior = getElementInterior(t.icon),
                dimension = getElementDimension(t.icon), label = label }
        end
    end
    return list
end

-- admin: jugador que borra (rp_admin lo pasa); si falta, queda como "sistema"
function adminDelete(id, _, admin)
    id = tonumber(id)
    local t = id and texts[id]
    if not t then return false, "no existe" end
    local text = t.row.text
    destroyText(id)
    local accId, _, name = who(admin)
    dbExec(db(), [[UPDATE text3d SET deleted_at = NOW(), deleted_by_account_id = NULLIF(?, 0), deleted_by_name = ?
                   WHERE id = ? AND deleted_at IS NULL]], accId, name, id)
    addLog(id, "delete", text, admin)
    return true
end
