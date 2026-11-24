--[[
    rp_phone / s_tinder.lua
    App Tinder del telefono. PARTE 1: perfil de citas del personaje. PARTE 2: swipe (like/dislike).
    (Siguientes partes: matches -> chat.)

    Tabla: tinder_profiles (por personaje). Edad y genero salen de characters (datos RP),
    el jugador solo edita foto, descripcion, a quien le interesa y si su perfil es visible.
]]

local MAX_PHOTO = 350 * 1024        -- bytes del base64 de la foto
local busy = {}

addEvent("rp:tinder:profile:get", true)
addEvent("rp:tinder:profile:save", true)
addEvent("rp:tinder:deck:get", true)
addEvent("rp:tinder:swipe", true)

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
local function hasPhone(player) return characterOf(player) and exports.rp_inventory:hasItem(player, "phone", 1) end

local INTERESTED = { m = true, f = true, a = true }

local function sendProfile(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local r = rows[1]
        if not r or not isElement(player) then return end
        triggerLatentClientEvent(player, "rp:tinder:profile", 200000, false, resourceRoot, {
            name = (tostring(r.name):gsub("_", " ")),
            age = tonumber(r.age),
            gender = tonumber(r.gender) == 1 and "f" or "m",
            bio = r.bio or "",
            interested = r.interested or "a",
            photo = r.photo,
            active = r.active == nil and true or tonumber(r.active) == 1,
        })
    end, db(), [[
        SELECT c.name, c.age, c.gender, t.bio, t.interested, t.photo, t.active
        FROM characters c LEFT JOIN tinder_profiles t ON t.character_id = c.id
        WHERE c.id = ?
    ]], characterId)
end

addEventHandler("rp:tinder:profile:get", resourceRoot, function()
    if getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    if hasPhone(client) then sendProfile(client) end
end)

addEventHandler("rp:tinder:profile:save", resourceRoot, function(bio, interested, active, photo)
    local player = client
    if getElementData(player, "rp:downed") then return end
    if not hasPhone(player) or busy[player] then return end

    if type(bio) ~= "string" then return end
    bio = bio:gsub("[%z\1-\31]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #bio > 200 then return notify(player, "La descripcion es demasiado larga (max. 200).", "error") end
    if not INTERESTED[interested] then return end
    active = active and 1 or 0

    -- La foto es opcional en cada guardado: nil/"" = conservar la actual
    if photo == "" then photo = nil end
    if photo ~= nil and (type(photo) ~= "string" or #photo < 100 or #photo > MAX_PHOTO or not photo:match("^[%w%+/=]+$")) then
        return notify(player, "La foto no es valida o es demasiado grande.", "error")
    end

    busy[player] = true
    dbQuery(function(qh)
        busy[player] = nil
        local ok = dbPoll(qh, 0)
        if not isElement(player) then return end
        if ok then
            notify(player, "Perfil de Tinder guardado.", "success")
            sendProfile(player)
        else
            notify(player, "No se pudo guardar el perfil.", "error")
        end
    end, db(), [[
        INSERT INTO tinder_profiles (character_id, bio, interested, photo, active) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE bio = VALUES(bio), interested = VALUES(interested), active = VALUES(active),
                                photo = COALESCE(VALUES(photo), photo)
    ]], characterOf(player), bio, interested, photo, active)
end)


----------------------------------------------------------------
-- PARTE 2: swipe
-- Candidatos: perfiles activos con foto, con interes mutuo por genero, que no sean el propio
-- ni hayan sido votados ya. El cliente pide de a una tarjeta (la foto pesa) y precarga la siguiente.
-- Un match = like mutuo en tinder_swipes (la parte 3 los lista y abre el chat).
----------------------------------------------------------------
local lastSwipe = {}
local lastDeck = {}

-- Condiciones de elegibilidad (me = mp/me, candidato = t/c). Se reutilizan al pedir y al votar.
local ELIGIBLE = [[
    t.active = 1 AND t.photo IS NOT NULL AND mp.active = 1 AND mp.photo IS NOT NULL
    AND t.character_id <> mp.character_id
    AND (mp.interested = 'a' OR mp.interested = IF(c.gender = 1, 'f', 'm'))
    AND (t.interested = 'a' OR t.interested = IF(me.gender = 1, 'f', 'm'))
]]

addEventHandler("rp:tinder:deck:get", resourceRoot, function(exclude)
    local player = client
    if getElementData(player, "rp:downed") or not hasPhone(player) then return end
    local now = getTickCount()
    if lastDeck[player] and now - lastDeck[player] < 400 then return end
    lastDeck[player] = now

    local me = characterOf(player)
    local params = { me }
    local marks = ""
    if type(exclude) == "table" then
        for i = 1, math.min(#exclude, 5) do
            local id = tonumber(exclude[i])
            if id then
                params[#params + 1] = math.floor(id)
                marks = marks .. ", ?"
            end
        end
    end

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        local r = rows and rows[1]
        if not r then
            -- nil = hubo un error; {} = no quedan perfiles (la interfaz lo distingue)
            return triggerClientEvent(player, "rp:tinder:deck", resourceRoot, rows and { empty = true } or nil)
        end
        triggerLatentClientEvent(player, "rp:tinder:deck", 200000, false, resourceRoot, {
            id = tonumber(r.id),
            name = (tostring(r.name):gsub("_", " ")),
            age = tonumber(r.age),
            gender = tonumber(r.gender) == 1 and "f" or "m",
            bio = r.bio or "",
            photo = r.photo,
        })
    end, db(), [[
        SELECT t.character_id AS id, c.name, c.age, c.gender, t.bio, t.photo
        FROM tinder_profiles mp
        JOIN characters me ON me.id = mp.character_id
        JOIN tinder_profiles t ON t.character_id <> mp.character_id
        JOIN characters c ON c.id = t.character_id
        WHERE mp.character_id = ? AND ]] .. ELIGIBLE .. [[
          AND NOT EXISTS (SELECT 1 FROM tinder_swipes s WHERE s.swiper_id = mp.character_id AND s.target_id = t.character_id)
          AND t.character_id NOT IN (0]] .. marks .. [[)
        ORDER BY RAND() LIMIT 1
    ]], unpack(params))
end)

local function onlinePlayerOf(characterId)
    for _, p in ipairs(getElementsByType("player")) do
        if characterOf(p) == characterId then return p end
    end
end

addEventHandler("rp:tinder:swipe", resourceRoot, function(targetId, liked)
    local player = client
    if getElementData(player, "rp:downed") or not hasPhone(player) then return end
    targetId = math.floor(tonumber(targetId) or 0)
    if targetId <= 0 then return end
    local now = getTickCount()
    if lastSwipe[player] and now - lastSwipe[player] < 250 then return end
    lastSwipe[player] = now

    local me = characterOf(player)
    liked = liked == true and 1 or 0

    -- Solo se registra si el objetivo sigue siendo elegible (evita votar ids arbitrarios)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(player) or not affected or affected < 1 then return end
        if liked == 0 then return end
        -- ¿Me dio like de vuelta?
        dbQuery(function(qh2)
            local rows = dbPoll(qh2, 0) or {}
            local r = rows[1]
            if not r or not isElement(player) then return end
            local theirName = (tostring(r.name):gsub("_", " "))
            triggerClientEvent(player, "rp:tinder:match", resourceRoot, { id = targetId, name = theirName, photo = nil })
            notify(player, "¡Es un match con " .. theirName .. "!", "success")
            local other = onlinePlayerOf(targetId)
            if other and hasPhone(other) then
                notify(other, "¡Tienes un nuevo match en Tinder!", "success")
            end
        end, db(), [[
            SELECT c.name FROM tinder_swipes s JOIN characters c ON c.id = s.swiper_id
            WHERE s.swiper_id = ? AND s.target_id = ? AND s.liked = 1
        ]], targetId, me)
    end, db(), [[
        INSERT INTO tinder_swipes (swiper_id, target_id, liked)
        SELECT mp.character_id, t.character_id, ?
        FROM tinder_profiles mp
        JOIN characters me ON me.id = mp.character_id
        JOIN tinder_profiles t ON t.character_id = ?
        JOIN characters c ON c.id = t.character_id
        WHERE mp.character_id = ? AND ]] .. ELIGIBLE .. [[
        ON DUPLICATE KEY UPDATE liked = VALUES(liked)
    ]], liked, targetId, me)
end)

addEventHandler("onPlayerQuit", root, function()
    busy[source] = nil
    lastSwipe[source] = nil
    lastDeck[source] = nil
end)
