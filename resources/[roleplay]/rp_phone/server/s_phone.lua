--[[
    rp_phone / s_phone.lua
    Telefono movil (item "phone" de rp_inventory). Se abre usandolo desde el
    inventario o con la tecla P. Apps: Telefono (numeros de emergencia que
    llaman a rp_emergency), Notas, Contactos, Banco (rp_bank) y Fotogram
    (red social con fotos tomadas en el juego).

    Tablas: phone_notes, phone_contacts, social_posts, social_likes y
    characters.phone_number (se asigna la primera vez que se usa el telefono).
]]

local MAX_IMAGE = 350 * 1024       -- bytes del base64 de una foto
local FEED_SIZE = 15

local busy = {}
local lastCall = {}

-- Numeros de emergencia que trae la app Telefono. service = id de rp_emergency.
local EMERGENCY_NUMBERS = {
    { number = "911", service = "ambulance", name = "Ambulancia", desc = "Paramedicos LSMD" },
    { number = "912", service = "police",    name = "Policia",    desc = "LSPD" },
    { number = "913", service = "fire",      name = "Bomberos",   desc = "LSFD" },
}
local BY_NUMBER = {}
for _, e in ipairs(EMERGENCY_NUMBERS) do BY_NUMBER[e.number] = e end

addEvent("rp:onItemUse", false)
addEvent("rp:phone:open", true)
addEvent("rp:phone:note:save", true)
addEvent("rp:phone:note:delete", true)
addEvent("rp:phone:contact:add", true)
addEvent("rp:phone:contact:addPlayer", true)
addEvent("rp:phone:contact:delete", true)
addEvent("rp:phone:call", true)
addEvent("rp:social:feed", true)
addEvent("rp:social:post", true)
addEvent("rp:social:like", true)

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
local function hasPhone(player) return characterOf(player) and exports.rp_inventory:hasItem(player, "phone", 1) end

local function cleanText(s, maxLen, allowNewlines)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if allowNewlines then s = s:gsub("[%z\1-\8\11\12\14-\31]", "") else s = s:gsub("%c", " ") end
    if #s == 0 or #s > maxLen then return nil end
    return s
end

----------------------------------------------------------------
-- Numero de telefono
----------------------------------------------------------------
local function ensureNumber(characterId, callback, attempts)
    attempts = attempts or 0
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local current = rows[1] and tonumber(rows[1].phone_number)
        if current then return callback(current) end
        if attempts > 5 then return callback(false) end
        local number = math.random(5550000, 5559999)
        dbQuery(function(qh2)
            local ok, affected = dbPoll(qh2, 0)
            if ok and affected and affected > 0 then callback(number)
            else ensureNumber(characterId, callback, attempts + 1) end   -- numero repetido: reintenta
        end, db(), "UPDATE characters SET phone_number = ? WHERE id = ? AND phone_number IS NULL", number, characterId)
    end, db(), "SELECT phone_number FROM characters WHERE id = ?", characterId)
end

----------------------------------------------------------------
-- Datos del telefono
----------------------------------------------------------------
local function sendNotes(player)
    local characterId = characterOf(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if isElement(player) then triggerClientEvent(player, "rp:phone:notes", resourceRoot, rows) end
    end, db(), "SELECT id, title, body, DATE_FORMAT(updated_at, '%d/%m %H:%i') AS date FROM phone_notes WHERE character_id = ? ORDER BY updated_at DESC", characterId)
end

local function sendContacts(player)
    local characterId = characterOf(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if isElement(player) then triggerClientEvent(player, "rp:phone:contacts", resourceRoot, rows) end
    end, db(), "SELECT id, name, number FROM phone_contacts WHERE character_id = ? ORDER BY name", characterId)
end

local function openPhone(player)
    if not hasPhone(player) then return notify(player, "No tienes un telefono.", "error") end
    ensureNumber(characterOf(player), function(number)
        if not isElement(player) then return end
        triggerClientEvent(player, "rp:phone:show", resourceRoot, {
            number = number or 0, owner = (getPlayerName(player):gsub("_", " ")),
            emergency = EMERGENCY_NUMBERS,
        })
        sendNotes(player)
        sendContacts(player)
    end)
end

addEventHandler("rp:phone:open", resourceRoot, function()
    if getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    openPhone(client)
end)

-- Usar el item "phone" desde el inventario
addEventHandler("rp:onItemUse", root, function(itemId)
    if itemId == "phone" then openPhone(source) end
end)

----------------------------------------------------------------
-- Notas
----------------------------------------------------------------
addEventHandler("rp:phone:note:save", resourceRoot, function(id, title, body)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not hasPhone(player) then return end
    title, body = cleanText(title, 64, false), cleanText(body or " ", 4000, true) or ""
    if not title then return notify(player, "La nota necesita un titulo (max. 64 caracteres).", "error") end
    local characterId = characterOf(player)
    id = tonumber(id)
    if id then
        dbExec(db(), "UPDATE phone_notes SET title = ?, body = ? WHERE id = ? AND character_id = ?", title, body, id, characterId)
    else
        dbExec(db(), "INSERT INTO phone_notes (character_id, title, body) VALUES (?, ?, ?)", characterId, title, body)
    end
    notify(player, "Nota guardada.", "success")
    sendNotes(player)
end)

addEventHandler("rp:phone:note:delete", resourceRoot, function(id)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not hasPhone(player) or not tonumber(id) then return end
    dbExec(db(), "DELETE FROM phone_notes WHERE id = ? AND character_id = ?", tonumber(id), characterOf(player))
    notify(player, "Nota eliminada.", "info")
    sendNotes(player)
end)

----------------------------------------------------------------
-- Contactos
----------------------------------------------------------------
local function addContact(player, name, number)
    dbQuery(function(qh)
        local ok, code = dbPoll(qh, 0)
        if not isElement(player) then return end
        if ok then
            notify(player, ("%s agregado a tus contactos."):format(name), "success")
        elseif code == 1062 then
            notify(player, "Ese numero ya esta en tus contactos.", "warning")
        else
            notify(player, "No se pudo guardar el contacto.", "error")
        end
        sendContacts(player)
    end, db(), "INSERT INTO phone_contacts (character_id, name, number) VALUES (?, ?, ?)", characterOf(player), name, number)
end

addEventHandler("rp:phone:contact:add", resourceRoot, function(name, number)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not hasPhone(player) then return end
    name, number = cleanText(name, 32, false), tonumber(number)
    if not name or not number or number < 1000000 or number > 9999999 then
        return notify(player, "Escribe un nombre y un numero de 7 digitos.", "error")
    end
    addContact(player, name, number)
end)

-- Agregar a un jugador cercano (comparten numero al estar juntos)
addEventHandler("rp:phone:contact:addPlayer", resourceRoot, function(target)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not hasPhone(player) or not isElement(target) or getElementType(target) ~= "player" or target == player then return end
    local x1, y1, z1 = getElementPosition(player)
    local x2, y2, z2 = getElementPosition(target)
    if getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2) > 6 or getElementDimension(player) ~= getElementDimension(target) then
        return notify(player, "Esa persona esta demasiado lejos.", "warning")
    end
    local targetChar = characterOf(target)
    if not targetChar or not exports.rp_inventory:hasItem(target, "phone", 1) then
        return notify(player, "Esa persona no tiene telefono.", "warning")
    end
    ensureNumber(targetChar, function(number)
        if not isElement(player) or not number then return end
        addContact(player, (getPlayerName(target):gsub("_", " ")), number)
        if isElement(target) then
            notify(target, ("%s guardo tu numero en su agenda."):format((getPlayerName(player):gsub("_", " "))), "info")
        end
    end)
end)

addEventHandler("rp:phone:contact:delete", resourceRoot, function(id)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not hasPhone(player) or not tonumber(id) then return end
    dbExec(db(), "DELETE FROM phone_contacts WHERE id = ? AND character_id = ?", tonumber(id), characterOf(player))
    sendContacts(player)
end)

----------------------------------------------------------------
-- Fotogram (red social)
----------------------------------------------------------------
local function sendFeed(player)
    local characterId = characterOf(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        for _, r in ipairs(rows) do
            r.author = tostring(r.author):gsub("_", " ")
            r.liked = tonumber(r.liked) == 1
            r.mine = tonumber(r.character_id) == characterId
            r.character_id = nil
        end
        -- Evento latente: las fotos pueden pesar varios cientos de KB
        triggerLatentClientEvent(player, "rp:social:feed", 200000, false, resourceRoot, rows)
    end, db(), [[
        SELECT p.id, p.caption, p.image, p.character_id, c.name AS author,
               DATE_FORMAT(p.created_at, '%d/%m %H:%i') AS date,
               (SELECT COUNT(*) FROM social_likes l WHERE l.post_id = p.id) AS likes,
               EXISTS(SELECT 1 FROM social_likes l WHERE l.post_id = p.id AND l.character_id = ?) AS liked
        FROM social_posts p JOIN characters c ON c.id = p.character_id
        ORDER BY p.id DESC LIMIT ?
    ]], characterId, FEED_SIZE)
end

addEventHandler("rp:social:feed", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    if hasPhone(client) then sendFeed(client) end
end)

addEventHandler("rp:social:post", resourceRoot, function(caption, image)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not hasPhone(player) or busy[player] then return end
    caption = cleanText(caption or "", 280, false) or ""
    if type(image) ~= "string" or #image < 100 or #image > MAX_IMAGE or not image:match("^[%w%+/=]+$") then
        return notify(player, "La foto no es valida o es demasiado grande.", "error")
    end
    busy[player] = true
    dbQuery(function(qh)
        busy[player] = nil
        local ok = dbPoll(qh, 0)
        if not isElement(player) then return end
        if ok then
            notify(player, "Publicaste una foto en Fotogram.", "success")
            sendFeed(player)
        else
            notify(player, "No se pudo publicar la foto.", "error")
        end
    end, db(), "INSERT INTO social_posts (character_id, caption, image) VALUES (?, ?, ?)", characterOf(player), caption, image)
end)

addEventHandler("rp:social:like", resourceRoot, function(postId)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    postId = tonumber(postId)
    if not hasPhone(player) or not postId then return end
    local characterId = characterOf(player)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if affected and affected > 0 then
            return   -- se quito el like
        end
        dbExec(db(), "INSERT IGNORE INTO social_likes (post_id, character_id) VALUES (?, ?)", postId, characterId)
    end, db(), "DELETE FROM social_likes WHERE post_id = ? AND character_id = ?", postId, characterId)
end)

----------------------------------------------------------------
-- Telefono: llamadas (por ahora solo a los numeros de emergencia)
----------------------------------------------------------------
addEventHandler("rp:phone:call", resourceRoot, function(number)
    local player = client
    if not hasPhone(player) or getElementData(player, "rp:downed") or isPedDead(player) then return end   -- abatido (rp_injury)
    local now = getTickCount()
    if lastCall[player] and now - lastCall[player] < 3000 then return end
    lastCall[player] = now
    if type(number) ~= "string" or #number > 12 then return end
    local entry = BY_NUMBER[number]
    if not entry then
        triggerClientEvent(player, "rp:phone:callResult", resourceRoot, number, false)
        return notify(player, "El numero marcado no esta disponible.", "info")
    end
    local emergency = getResourceFromName("rp_emergency")
    if not emergency or getResourceState(emergency) ~= "running" then
        triggerClientEvent(player, "rp:phone:callResult", resourceRoot, number, false)
        return notify(player, "No hay servicio de emergencias en este momento.", "error")
    end
    -- rp_emergency valida todo y avisa al jugador si rechaza la llamada
    local ok = exports.rp_emergency:callService(player, entry.service)
    triggerClientEvent(player, "rp:phone:callResult", resourceRoot, number, ok == true)
end)

addEventHandler("onPlayerQuit", root, function() busy[source], lastCall[source] = nil, nil end)
