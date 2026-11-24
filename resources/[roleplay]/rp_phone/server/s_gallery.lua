--[[
    rp_phone / s_gallery.lua
    Galeria del telefono: cada foto tomada con la camara se guarda por personaje
    (tabla phone_gallery). Fotogram y Tinder podran elegir fotos de aqui.

    Las fotos se piden una a una (rp:gallery:get, latente) para no saturar la red;
    la lista solo lleva ids y fechas.
]]

local MAX_PHOTOS = 60                  -- por personaje; al llegar al limite se borra la mas vieja
local lastSave, lastGet = {}, {}

addEvent("rp:gallery:list", true)
addEvent("rp:gallery:save", true)
addEvent("rp:gallery:get", true)
addEvent("rp:gallery:delete", true)

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
local function canUse(player)
    return characterOf(player) and not getElementData(player, "rp:downed")
        and exports.rp_inventory:hasItem(player, "phone", 1)
end

local function sendList(player, characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows or not isElement(player) then return end
        triggerClientEvent(player, "rp:gallery:list", resourceRoot, rows)
    end, db(), "SELECT id, UNIX_TIMESTAMP(created_at) AS ts FROM phone_gallery WHERE character_id = ? ORDER BY id DESC", characterId)
end

addEventHandler("rp:gallery:list", resourceRoot, function()
    local player = client
    if canUse(player) then sendList(player, characterOf(player)) end
end)

addEventHandler("rp:gallery:save", resourceRoot, function(image)
    local player = client
    if not canUse(player) then return end
    -- JPEG en base64 ("/9j/"), mismo limite que las fotos de Fotogram
    if type(image) ~= "string" or #image < 100 or #image > FOTOGRAM.MAX_IMAGE
        or image:sub(1, 4) ~= "/9j/" or not image:match("^[%w%+/=]+$") then
        return notify(player, "No se pudo guardar la foto en la galeria.", "error")
    end
    local now = getTickCount()
    if lastSave[player] and now - lastSave[player] < 1500 then return end
    lastSave[player] = now

    local characterId = characterOf(player)
    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not id then return notify(player, "No se pudo guardar la foto en la galeria.", "error") end
        -- Borra las fotos que sobren (las mas viejas)
        dbExec(db(), [[
            DELETE FROM phone_gallery WHERE character_id = ? AND id NOT IN
            (SELECT id FROM (SELECT id FROM phone_gallery WHERE character_id = ? ORDER BY id DESC LIMIT ?) keep)
        ]], characterId, characterId, MAX_PHOTOS)
        triggerClientEvent(player, "rp:gallery:saved", resourceRoot, id)
        notify(player, "Foto guardada en la galeria.", "success")
    end, db(), "INSERT INTO phone_gallery (character_id, image) VALUES (?, ?)", characterId, image)
end)

addEventHandler("rp:gallery:get", resourceRoot, function(id)
    local player = client
    id = math.floor(tonumber(id) or 0)
    if id <= 0 or not canUse(player) then return end
    local now = getTickCount()
    local w = lastGet[player]
    if not w or now - w.start > 10000 then w = { start = now, n = 0 }; lastGet[player] = w end
    w.n = w.n + 1
    if w.n > 40 then return end   -- maximo 40 fotos cada 10 s; el telefono reintenta al reabrir
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows or not rows[1] or not isElement(player) then return end
        triggerLatentClientEvent(player, "rp:gallery:image", 200000, false, resourceRoot, id, rows[1].image)
    end, db(), "SELECT image FROM phone_gallery WHERE id = ? AND character_id = ?", id, characterOf(player))
end)

addEventHandler("rp:gallery:delete", resourceRoot, function(id)
    local player = client
    id = math.floor(tonumber(id) or 0)
    if id <= 0 or not canUse(player) then return end
    local characterId = characterOf(player)
    dbQuery(function(qh)
        local _, n = dbPoll(qh, 0)
        if n and n > 0 and isElement(player) then triggerClientEvent(player, "rp:gallery:deleted", resourceRoot, id) end
    end, db(), "DELETE FROM phone_gallery WHERE id = ? AND character_id = ?", id, characterId)
end)

addEventHandler("onPlayerQuit", root, function() lastSave[source], lastGet[source] = nil, nil end)
