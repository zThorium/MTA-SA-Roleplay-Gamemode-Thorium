--[[
    rp_phone / s_messages.lua
    App Mensajes: SMS entre los telefonos de los personajes, con el mismo estilo que el chat de
    Tinder (burbujas, "Leido", aviso con el telefono cerrado y globo de no leidos en el icono).
    Se escribe a un numero (de la agenda o a mano); llega al instante si la otra persona esta
    conectada y queda guardado si no. Borrar una conversacion solo la oculta para ti.

    Tabla: phone_messages. En la app cada conversacion se identifica por el numero del otro.
]]

local T = Tinder

for _, name in ipairs({ "list:get", "chat:open", "send", "delete", "badge:get" }) do
    addEvent("rp:sms:" .. name, true)
end

local MAX_LEN = 400
local sentCount = {}

local function db() return exports.rp_database:getConnection() end
local function isNull(v) return v == nil or v == false end
local function pretty(n) return (tostring(n):gsub("^(%d%d%d)(%d%d%d%d)$", "%1-%2")) end

local function cleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%z\1-\31]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or (utf8.len(s) or #s) > MAX_LEN then return nil end
    return s
end

local function parseNumber(v)
    v = tostring(v or ""):gsub("%D", "")
    if #v ~= 7 then return nil end
    return tonumber(v)
end

local function myNumber(characterId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        callback(rows[1] and tonumber(rows[1].phone_number) or nil)
    end, db(), "SELECT phone_number FROM characters WHERE id = ?", characterId)
end

----------------------------------------------------------------
-- Lista de conversaciones y globo
----------------------------------------------------------------
local function sendList(player)
    local characterId = T.characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        dbQuery(function(qh2)
            local contacts = dbPoll(qh2, 0) or {}
            if not isElement(player) then return end
            local names, contactList = {}, {}
            for _, c in ipairs(contacts) do
                names[tonumber(c.number)] = c.name
                contactList[#contactList + 1] = { number = tostring(c.number), name = c.name }
            end
            local convos, order = {}, {}
            for _, r in ipairs(rows) do
                local mine = tonumber(r.sender_id) == characterId
                local other = mine and tonumber(r.receiver_number) or tonumber(r.sender_number)
                local c = convos[other]
                if not c then
                    c = { number = tostring(other), name = names[other], pretty = pretty(other),
                          last = T.preview(r.body), lastMine = mine, ts = tonumber(r.ts) or 0, unread = 0 }
                    convos[other] = c
                    order[#order + 1] = c
                end
                if not mine and isNull(r.read_at) then c.unread = c.unread + 1 end
            end
            triggerLatentClientEvent(player, "rp:sms:list", 200000, false, resourceRoot, { convos = order, contacts = contactList })
        end, db(), "SELECT name, number FROM phone_contacts WHERE character_id = ? ORDER BY name", characterId)
    end, db(), [[
        SELECT sender_id, sender_number, receiver_number, body, read_at, UNIX_TIMESTAMP(created_at) AS ts
        FROM phone_messages
        WHERE (sender_id = ? AND hidden_sender = 0) OR (receiver_id = ? AND hidden_receiver = 0)
        ORDER BY id DESC LIMIT 600
    ]], characterId, characterId)
end

local function sendBadge(player)
    local characterId = T.characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if isElement(player) then
            triggerClientEvent(player, "rp:sms:badge", resourceRoot, tonumber(rows[1] and rows[1].n) or 0)
        end
    end, db(), "SELECT COUNT(*) AS n FROM phone_messages WHERE receiver_id = ? AND read_at IS NULL AND hidden_receiver = 0", characterId)
end

addEventHandler("rp:sms:list:get", resourceRoot, function()
    if T.canUse(client) and T.cooldown(client, "smsList", 600) then sendList(client) end
end)
addEventHandler("rp:sms:badge:get", resourceRoot, function()
    if T.canUse(client) and T.cooldown(client, "smsBadge", 1500) then sendBadge(client) end
end)

----------------------------------------------------------------
-- Abrir una conversacion (marca como leidos los recibidos)
----------------------------------------------------------------
addEventHandler("rp:sms:chat:open", resourceRoot, function(numberText)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "smsOpen", 300) then return end
    local number = parseNumber(numberText)
    if not number then return end
    local characterId = T.characterOf(player)
    myNumber(characterId, function(mine)
        if not mine or not isElement(player) then return end
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            if not isElement(player) then return end
            local msgs = {}
            for i = #rows, 1, -1 do
                local r = rows[i]
                msgs[#msgs + 1] = { mine = tonumber(r.sender_id) == characterId, body = r.body, ts = tonumber(r.ts), read = not isNull(r.read_at) }
            end
            triggerLatentClientEvent(player, "rp:sms:chat", 200000, false, resourceRoot, { number = tostring(number), messages = msgs })
            dbQuery(function(qh2)
                local _, affected = dbPoll(qh2, 0)
                if not affected or affected < 1 then return end
                -- "Leido" para quien los mando
                dbQuery(function(qh3)
                    local orows = dbPoll(qh3, 0) or {}
                    local other = orows[1] and T.playerOf(tonumber(orows[1].id))
                    if other then triggerClientEvent(other, "rp:sms:read", resourceRoot, tostring(mine)) end
                end, db(), "SELECT id FROM characters WHERE phone_number = ?", number)
            end, db(), "UPDATE phone_messages SET read_at = NOW() WHERE receiver_id = ? AND sender_number = ? AND read_at IS NULL", characterId, number)
        end, db(), [[
            SELECT sender_id, body, read_at, UNIX_TIMESTAMP(created_at) AS ts FROM phone_messages
            WHERE (sender_id = ? AND receiver_number = ? AND hidden_sender = 0)
               OR (receiver_id = ? AND sender_number = ? AND hidden_receiver = 0)
            ORDER BY id DESC LIMIT 100
        ]], characterId, number, characterId, number)
    end)
end)

----------------------------------------------------------------
-- Enviar
----------------------------------------------------------------
addEventHandler("rp:sms:send", resourceRoot, function(numberText, text)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "smsSend", 500) then return end
    local digits = tostring(numberText or ""):gsub("%D", "")
    if digits == "911" or digits == "912" or digits == "913" then
        return T.notify(player, "Para emergencias tienes que llamar desde la app Teléfono.", "warning")
    end
    local number = parseNumber(numberText)
    text = cleanText(text)
    if not number then return T.notify(player, "Escribe un número de 7 dígitos.", "warning") end
    if not text then return end
    local now = getTickCount()
    local s = sentCount[player]
    if not s or now - s.start > 60000 then s = { start = now, count = 0 } sentCount[player] = s end
    s.count = s.count + 1
    if s.count > 30 then return T.notify(player, "Vas muy rápido. Espera un momento.", "warning") end

    local characterId = T.characterOf(player)
    myNumber(characterId, function(mine)
        if not isElement(player) then return end
        if not mine then return T.notify(player, "Tu teléfono aún no tiene número. Ciérralo y ábrelo otra vez.", "warning") end
        if mine == number then return T.notify(player, "No puedes escribirte a ti mismo.", "info") end
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            if not isElement(player) then return end
            local targetId = rows[1] and tonumber(rows[1].id)
            if not targetId then
                triggerClientEvent(player, "rp:sms:failed", resourceRoot, tostring(number))
                return T.notify(player, "El número " .. pretty(number) .. " no existe.", "error")
            end
            dbQuery(function(qh2)
                local _, _, id = dbPoll(qh2, 0)
                if not id or not isElement(player) then return end
                local ts = getRealTime().timestamp
                triggerClientEvent(player, "rp:sms:message", resourceRoot, tostring(number), { mine = true, body = text, ts = ts })
                local other = T.playerOf(targetId)
                if not other then return end
                -- Le llega con el nombre con el que te tiene guardado (o tu numero)
                dbQuery(function(qh3)
                    local crows = dbPoll(qh3, 0) or {}
                    if not isElement(other) then return end
                    triggerClientEvent(other, "rp:sms:message", resourceRoot, tostring(mine),
                        { mine = false, body = text, ts = ts, name = crows[1] and crows[1].name or pretty(mine),
                          hasPhone = exports.rp_inventory:hasItem(other, "phone", 1) == true })
                end, db(), "SELECT name FROM phone_contacts WHERE character_id = ? AND number = ?", targetId, mine)
            end, db(), [[
                INSERT INTO phone_messages (sender_id, receiver_id, sender_number, receiver_number, body) VALUES (?, ?, ?, ?, ?)
            ]], characterId, targetId, mine, number, text)
        end, db(), "SELECT id FROM characters WHERE phone_number = ?", number)
    end)
end)

addEventHandler("rp:sms:delete", resourceRoot, function(numberText)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "smsDelete", 800) then return end
    local number = parseNumber(numberText)
    if not number then return end
    local characterId = T.characterOf(player)
    dbExec(db(), "UPDATE phone_messages SET hidden_sender = 1 WHERE sender_id = ? AND receiver_number = ?", characterId, number)
    dbQuery(function(qh)
        dbPoll(qh, 0)
        if isElement(player) then sendList(player) sendBadge(player) end
    end, db(), "UPDATE phone_messages SET hidden_receiver = 1, read_at = COALESCE(read_at, NOW()) WHERE receiver_id = ? AND sender_number = ?", characterId, number)
end)

addEventHandler("onPlayerQuit", root, function() sentCount[source] = nil end)
