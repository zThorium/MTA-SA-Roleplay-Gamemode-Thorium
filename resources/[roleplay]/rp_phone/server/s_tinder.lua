--[[
    rp_phone / s_tinder.lua
    App Tinder del telefono: perfil, mazo de tarjetas, likes, super likes, matches, chat
    entre jugadores, "Le gustas" y Tinder Gold. En el mazo salen jugadores reales y personas
    simuladas (NPC); todo lo de los NPC (generacion, decisiones, chat con personalidad,
    estudio de fotos) vive en s_tinder_npcs.lua. Las claves de tarjeta son "p<id>" (personaje
    de un jugador) y "n<id>" (NPC).

    Tablas: tinder_profiles, tinder_profile_photos, tinder_swipes (liked 0 nope, 1 like, 2 super),
    tinder_messages (chat entre jugadores) y las de NPC (ver s_tinder_npcs.lua).
]]

Tinder = Tinder or {}
local T = Tinder

addEvent("rp:onCharacterLogout", false)
for _, name in ipairs({ "profile:get", "profile:save", "photo:save", "photo:remove", "deck:get", "swipe", "rewind",
    "matches:get", "chat:open", "chat:send", "unmatch", "likes:get", "card:get", "gold:buy", "tutorial:done", "badge:get" }) do
    addEvent("rp:tinder:" .. name, true)
end

function T.db() return exports.rp_database:getConnection() end
function T.notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
function T.characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
function T.canUse(player)
    return isElement(player) and T.characterOf(player) and not isPedDead(player) and not getElementData(player, "rp:downed")
        and exports.rp_inventory:hasItem(player, "phone", 1)
end
-- MTA puede devolver NULL de la BD como nil o como false
function T.isNull(v) return v == nil or v == false end
function T.firstName(name) return (tostring(name or ""):gsub("_", " "):match("^(%S+)")) or "" end
function T.today() local t = getRealTime() return ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday) end

-- Jugador conectado con ese personaje
function T.playerOf(characterId)
    for _, p in ipairs(getElementsByType("player")) do
        if T.characterOf(p) == characterId then return p end
    end
end

-- Envia a un personaje si esta conectado (el cliente decide si el telefono esta abierto)
function T.push(characterId, event, ...)
    local p = T.playerOf(characterId)
    if p then triggerClientEvent(p, event, resourceRoot, ...) end
    return p
end
function T.pushLatent(characterId, event, ...)
    local p = T.playerOf(characterId)
    if p then triggerLatentClientEvent(p, event, 300000, false, resourceRoot, ...) end
    return p
end

-- Cooldown simple por jugador y accion
local cooldowns = {}
function T.cooldown(player, key, ms)
    local now = getTickCount()
    local c = cooldowns[player]
    if not c then c = {} cooldowns[player] = c end
    if c[key] and now - c[key] < ms then return false end
    c[key] = now
    return true
end

local function validJpeg(s, maxLen)
    return type(s) == "string" and #s >= 100 and #s <= maxLen and s:sub(1, 4) == "/9j/" and s:match("^[%w%+/=]+$") ~= nil
end

local function cleanLine(s, maxLen, allowNewlines)
    if type(s) ~= "string" then return nil end
    if allowNewlines then s = s:gsub("[%z\1-\9\11-\31]", " ") else s = s:gsub("[%z\1-\31]", " ") end
    s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n\n+", "\n")
    if utf8 and utf8.len then
        local len = utf8.len(s)
        if not len or len > maxLen then return nil end
    elseif #s > maxLen * 2 then return nil end
    return s
end

local function parseInterests(text)
    local list, seen = {}, {}
    for id in tostring(text or ""):gmatch("[^,]+") do
        if TINDER_INTEREST_BY_ID[id] and not seen[id] then seen[id] = true list[#list + 1] = id end
    end
    return list
end
T.parseInterests = parseInterests

----------------------------------------------------------------
-- Perfil del personaje (cache por personaje; se recarga al guardar)
----------------------------------------------------------------
T.profiles = {}   -- [characterId] = perfil

local function buildProfile(r)
    local photos = 0
    if r.photo and r.photo ~= "" then photos = 1 end
    photos = photos + (tonumber(r.extra_photos) or 0)
    local interests = parseInterests(r.interests)
    local bio = r.bio or ""
    local quality = 0.25 + (photos > 0 and 0.25 or 0) + math.min(3, math.max(0, photos - 1)) * 0.07
        + (#bio >= 30 and 0.12 or 0) + (#interests >= 3 and 0.1 or 0) + ((r.job or "") ~= "" and 0.07 or 0)
    local goldLeft = tonumber(r.gold_left) or 0
    return {
        id = tonumber(r.id), name = (tostring(r.name):gsub("_", " ")), age = tonumber(r.age) or 18,
        gender = tonumber(r.gender) == 1 and 1 or 0, exists = not T.isNull(r.has_profile),
        bio = bio, job = r.job or "", interests = interests, interested = r.interested or "a",
        ageMin = tonumber(r.age_min) or 18, ageMax = tonumber(r.age_max) or 70,
        active = T.isNull(r.active) and true or tonumber(r.active) == 1,
        hasPhoto = photos > 0, photos = photos, quality = math.min(1, quality),
        gold = goldLeft > 0, goldLeft = goldLeft,
        quotaDay = r.quota_day and tostring(r.quota_day):sub(1, 10) or nil,
        likesUsed = tonumber(r.likes_used) or 0, supersUsed = tonumber(r.supers_used) or 0,
        tutorial = tonumber(r.tutorial) == 1,
    }
end

-- callback(profile|nil)
function T.loadProfile(characterId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local r = rows and rows[1]
        if not r then return callback(nil) end
        local p = buildProfile(r)
        T.profiles[characterId] = p
        callback(p)
    end, T.db(), [[
        SELECT c.id, c.name, c.age, c.gender, t.character_id AS has_profile, t.bio, t.job, t.interests, t.interested,
               t.age_min, t.age_max, t.photo, t.active, t.quota_day, t.likes_used, t.supers_used, t.tutorial,
               GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), t.gold_until)) AS gold_left,
               (SELECT COUNT(*) FROM tinder_profile_photos x WHERE x.character_id = c.id) AS extra_photos
        FROM characters c LEFT JOIN tinder_profiles t ON t.character_id = c.id WHERE c.id = ?
    ]], characterId)
end

local function withProfile(player, callback)
    local characterId = T.characterOf(player)
    if not characterId then return end
    local cached = T.profiles[characterId]
    if cached then return callback(cached, characterId) end
    T.loadProfile(characterId, function(p)
        if p and isElement(player) and T.characterOf(player) == characterId then callback(p, characterId) end
    end)
end
T.withProfile = withProfile

-- Cupo del dia (likes y super likes)
local function quota(p)
    local today = T.today()
    if p.quotaDay ~= today then p.quotaDay, p.likesUsed, p.supersUsed = today, 0, 0 end
    local likes = p.gold and 9999 or math.max(0, TINDER.FREE_LIKES - p.likesUsed)
    local supers = math.max(0, (p.gold and TINDER.GOLD_SUPERS or TINDER.FREE_SUPERS) - p.supersUsed)
    return likes, supers
end

local function saveQuota(characterId, p)
    dbExec(T.db(), "UPDATE tinder_profiles SET quota_day = ?, likes_used = ?, supers_used = ?, last_active = NOW() WHERE character_id = ?",
        p.quotaDay, p.likesUsed, p.supersUsed, characterId)
end

local function interestCatalog()
    local list = {}
    for _, it in ipairs(TINDER_INTERESTS) do list[#list + 1] = { id = it.id, label = it.label, icon = it.icon } end
    return list
end

local function sendProfile(player)
    local characterId = T.characterOf(player)
    if not characterId then return end
    T.loadProfile(characterId, function(p)
        if not p or not isElement(player) then return end
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            if not isElement(player) then return end
            local photos = {}
            for _, r in ipairs(rows) do photos[tonumber(r.slot)] = r.image end
            local likes, supers = quota(p)
            triggerLatentClientEvent(player, "rp:tinder:profile", 400000, false, resourceRoot, {
                name = p.name, first = T.firstName(p.name), age = p.age, gender = p.gender == 1 and "f" or "m",
                bio = p.bio, job = p.job, interests = p.interests, interested = p.interested,
                ageMin = p.ageMin, ageMax = p.ageMax, active = p.active, exists = p.exists,
                photos = { photos[1] or false, photos[2] or false, photos[3] or false, photos[4] or false },
                gold = p.gold, goldDays = math.ceil(p.goldLeft / 86400), likesLeft = likes, supersLeft = supers,
                tutorial = p.tutorial, catalog = interestCatalog(),
                goldPrice = TINDER.GOLD_PRICE, goldDaysBuy = TINDER.GOLD_DAYS, freeLikes = TINDER.FREE_LIKES,
                quality = math.floor(p.quality * 100),
            })
        end, T.db(), [[
            SELECT 1 AS slot, photo AS image FROM tinder_profiles WHERE character_id = ? AND photo IS NOT NULL
            UNION ALL SELECT slot, image FROM tinder_profile_photos WHERE character_id = ?
        ]], characterId, characterId)
    end)
end
T.sendProfile = sendProfile

addEventHandler("rp:tinder:profile:get", resourceRoot, function()
    if T.canUse(client) and T.cooldown(client, "profile", 600) then sendProfile(client) end
end)

-- Guarda los datos (las fotos van aparte: photo:save / photo:remove)
addEventHandler("rp:tinder:profile:save", resourceRoot, function(data)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "save", 1500) or type(data) ~= "table" then return end
    local bio = cleanLine(data.bio, TINDER.BIO_MAX, true)
    local job = cleanLine(data.job or "", TINDER.JOB_MAX, false)
    if not bio then return T.notify(player, "La descripción es demasiado larga.", "error") end
    if not job then return T.notify(player, "El trabajo es demasiado largo.", "error") end
    local interested = ({ m = "m", f = "f", a = "a" })[data.interested] or "a"
    local ageMin = math.floor(math.max(18, math.min(90, tonumber(data.ageMin) or 18)))
    local ageMax = math.floor(math.max(ageMin, math.min(90, tonumber(data.ageMax) or 70)))
    local list, seen = {}, {}
    if type(data.interests) == "table" then
        for _, id in ipairs(data.interests) do
            id = tostring(id)
            if TINDER_INTEREST_BY_ID[id] and not seen[id] and #list < TINDER.MAX_INTERESTS then seen[id] = true list[#list + 1] = id end
        end
    end
    local active = data.active == false and 0 or 1
    local characterId = T.characterOf(player)
    dbQuery(function(qh)
        local ok = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not ok then return T.notify(player, "No se pudo guardar el perfil.", "error") end
        T.profiles[characterId] = nil
        T.notify(player, "Perfil de Tinder guardado.", "success")
        sendProfile(player)
    end, T.db(), [[
        INSERT INTO tinder_profiles (character_id, bio, job, interests, interested, age_min, age_max, active, last_active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE bio = VALUES(bio), job = VALUES(job), interests = VALUES(interests),
            interested = VALUES(interested), age_min = VALUES(age_min), age_max = VALUES(age_max),
            active = VALUES(active), last_active = NOW()
    ]], characterId, bio, job, table.concat(list, ","), interested, ageMin, ageMax, active)
end)

-- Foto del perfil: slot 1 = principal (con miniatura para las listas), 2..4 = extra
addEventHandler("rp:tinder:photo:save", resourceRoot, function(slot, image, thumb)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "photo", 1200) then return end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 or slot > TINDER.MAX_PHOTOS then return end
    if not validJpeg(image, TINDER.PHOTO_MAX) then return T.notify(player, "La foto no es válida o es demasiado grande.", "error") end
    if slot == 1 and not validJpeg(thumb, TINDER.THUMB_MAX) then thumb = nil end
    local characterId = T.characterOf(player)
    local function done(qh)
        local ok = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not ok then return T.notify(player, "No se pudo guardar la foto.", "error") end
        T.profiles[characterId] = nil
        sendProfile(player)
    end
    if slot == 1 then
        dbQuery(done, T.db(), [[
            INSERT INTO tinder_profiles (character_id, photo, thumb, last_active) VALUES (?, ?, NULLIF(?, ''), NOW())
            ON DUPLICATE KEY UPDATE photo = VALUES(photo), thumb = VALUES(thumb), last_active = NOW()
        ]], characterId, image, thumb or "")
    else
        -- Las extra solo si ya hay perfil con foto principal
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            if not isElement(player) then return end
            if not rows[1] then return T.notify(player, "Primero pon tu foto principal.", "warning") end
            dbQuery(done, T.db(), [[
                INSERT INTO tinder_profile_photos (character_id, slot, image) VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE image = VALUES(image)
            ]], characterId, slot, image)
        end, T.db(), "SELECT 1 FROM tinder_profiles WHERE character_id = ? AND photo IS NOT NULL", characterId)
    end
end)

addEventHandler("rp:tinder:photo:remove", resourceRoot, function(slot)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "photo", 800) then return end
    slot = math.floor(tonumber(slot) or 0)
    if slot < 2 or slot > TINDER.MAX_PHOTOS then
        return T.notify(player, "La foto principal no se puede quitar, solo cambiar.", "info")
    end
    local characterId = T.characterOf(player)
    dbQuery(function(qh)
        dbPoll(qh, 0)
        if not isElement(player) then return end
        T.profiles[characterId] = nil
        sendProfile(player)
    end, T.db(), "DELETE FROM tinder_profile_photos WHERE character_id = ? AND slot = ?", characterId, slot)
end)

addEventHandler("rp:tinder:tutorial:done", resourceRoot, function()
    local characterId = T.characterOf(client)
    if not characterId then return end
    dbExec(T.db(), [[
        INSERT INTO tinder_profiles (character_id, tutorial) VALUES (?, 1) ON DUPLICATE KEY UPDATE tutorial = 1
    ]], characterId)
    if T.profiles[characterId] then T.profiles[characterId].tutorial = true end
end)

----------------------------------------------------------------
-- Tarjetas de jugadores
----------------------------------------------------------------
-- Condiciones para que el candidato c/t y yo (me/mp) seamos compatibles
local ELIGIBLE = [[
    t.active = 1 AND t.photo IS NOT NULL AND mp.active = 1 AND mp.photo IS NOT NULL
    AND t.character_id <> mp.character_id
    AND (mp.interested = 'a' OR mp.interested = IF(c.gender = 1, 'f', 'm'))
    AND (t.interested = 'a' OR t.interested = IF(me.gender = 1, 'f', 'm'))
    AND c.age BETWEEN mp.age_min AND mp.age_max
]]

local function activeLabel(online, minutesAgo, gender)
    local o = gender == 1 and "a" or "o"
    if online then return "En línea", true end
    minutesAgo = tonumber(minutesAgo)
    if not minutesAgo then return nil end
    if minutesAgo < 60 then return "Activ" .. o .. " recientemente" end
    if minutesAgo < 60 * 24 then return ("Activ%s hace %d h"):format(o, math.floor(minutesAgo / 60)) end
    if minutesAgo < 60 * 24 * 7 then return ("Activ%s hace %d d"):format(o, math.floor(minutesAgo / 1440)) end
    return nil
end
T.activeLabel = activeLabel

function T.distanceKm(player, x, y)
    if not isElement(player) then return nil end
    local px, py = getElementPosition(player)
    if getElementInterior(player) ~= 0 then return nil end
    return math.max(1, math.floor(getDistanceBetweenPoints2D(px, py, x, y) / 350 + 0.5))
end

local function sharedOf(mine, theirs)
    local set, out = {}, {}
    for _, id in ipairs(mine) do set[id] = true end
    for _, id in ipairs(theirs) do if set[id] then out[#out + 1] = id end end
    return out
end
T.sharedOf = sharedOf

-- Tarjeta completa de un jugador (con fotos). callback(card|nil)
local function playerCard(viewer, me, targetId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local r = rows[1]
        if not r then return callback(nil) end
        dbQuery(function(qh2)
            local extra = dbPoll(qh2, 0) or {}
            local photos = { { img = r.photo } }
            for _, e in ipairs(extra) do photos[#photos + 1] = { img = e.image } end
            local interests = parseInterests(r.interests)
            local target = T.playerOf(targetId)
            local label, online = activeLabel(target ~= nil, r.idle, tonumber(r.gender))
            local km
            if target and isElement(viewer) and getElementInterior(target) == 0 then
                local tx, ty = getElementPosition(target)
                km = T.distanceKm(viewer, tx, ty)
            end
            callback({
                key = "p" .. targetId, kind = "p", id = targetId, name = T.firstName(r.name), age = tonumber(r.age),
                gender = tonumber(r.gender) == 1 and "f" or "m", bio = r.bio or "", job = r.job or "",
                interests = interests, shared = sharedOf(me.interests, interests), prompts = {},
                photos = photos, active = label, online = online == true, km = km, verified = true,
                superLiked = tonumber(r.their_swipe) == 2, likedYou = tonumber(r.their_swipe or 0) >= 1,
            })
        end, T.db(), "SELECT image FROM tinder_profile_photos WHERE character_id = ? ORDER BY slot", targetId)
    end, T.db(), [[
        SELECT c.name, c.age, c.gender, t.bio, t.job, t.interests, t.photo,
               TIMESTAMPDIFF(MINUTE, t.last_active, NOW()) AS idle,
               (SELECT s.liked FROM tinder_swipes s WHERE s.swiper_id = c.id AND s.target_id = ?) AS their_swipe
        FROM tinder_profiles t JOIN characters c ON c.id = t.character_id
        WHERE t.character_id = ? AND t.photo IS NOT NULL
    ]], me.id, targetId)
end
T.playerCard = playerCard

-- Un candidato jugador al azar (o nil). Los que ya te dieron like salen antes.
-- estandar:sql-seguro ELIGIBLE es texto fijo y marks = ", ?" por cada id; los ids van como parametros
local function nextPlayerCandidate(me, exclude, callback)
    local params, marks = { me.id }, ""
    for id in pairs(exclude) do
        params[#params + 1] = id
        marks = marks .. ", ?"
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        callback(rows[1] and tonumber(rows[1].id) or nil)
    end, T.db(), [[
        SELECT t.character_id AS id
        FROM tinder_profiles mp
        JOIN characters me ON me.id = mp.character_id
        JOIN tinder_profiles t ON t.character_id <> mp.character_id
        JOIN characters c ON c.id = t.character_id
        WHERE mp.character_id = ? AND ]] .. ELIGIBLE .. [[
          AND NOT EXISTS (SELECT 1 FROM tinder_swipes s WHERE s.swiper_id = mp.character_id AND s.target_id = t.character_id)
          AND t.character_id NOT IN (0]] .. marks .. [[)
        ORDER BY EXISTS (SELECT 1 FROM tinder_swipes l WHERE l.swiper_id = t.character_id AND l.target_id = mp.character_id AND l.liked >= 1) DESC,
                 RAND() LIMIT 1
    ]], unpack(params))
end

----------------------------------------------------------------
-- Mazo
----------------------------------------------------------------
local function parseExclude(list)
    local players, npcs = {}, {}
    if type(list) == "table" then
        for i = 1, math.min(#list, 12) do
            local kind, id = tostring(list[i]):match("^([pn])(%d+)$")
            id = tonumber(id)
            if id then
                if kind == "p" then players[id] = true else npcs[id] = true end
            end
        end
    end
    return players, npcs
end

addEventHandler("rp:tinder:deck:get", resourceRoot, function(exclude)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "deck", 350) then return end
    withProfile(player, function(me)
        if not me.hasPhoto then
            return triggerClientEvent(player, "rp:tinder:deck", resourceRoot, { needPhoto = true })
        end
        local exPlayers, exNpcs = parseExclude(exclude)
        nextPlayerCandidate(me, exPlayers, function(playerId)
            if not isElement(player) then return end
            -- Mezcla: los jugadores reales salen a menudo, pero no siempre (si no, el mazo seria solo de NPC o solo de gente)
            local usePlayer = playerId and (math.random() < 0.5)
            local function sendPlayer()
                playerCard(player, me, playerId, function(card)
                    if not isElement(player) then return end
                    if card then triggerLatentClientEvent(player, "rp:tinder:deck", 400000, false, resourceRoot, card)
                    else triggerClientEvent(player, "rp:tinder:deck", resourceRoot, { empty = true }) end
                end)
            end
            if usePlayer then return sendPlayer() end
            T.npcNextCard(player, me, exNpcs, function(card)
                if not isElement(player) then return end
                if card then return triggerLatentClientEvent(player, "rp:tinder:deck", 400000, false, resourceRoot, card) end
                if playerId then return sendPlayer() end
                triggerClientEvent(player, "rp:tinder:deck", resourceRoot, { empty = true })
            end)
        end)
    end)
end)

-- Ver la tarjeta completa de alguien (desde el chat o "Le gustas")
addEventHandler("rp:tinder:card:get", resourceRoot, function(key)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "card", 500) then return end
    local kind, id = tostring(key or ""):match("^([pn])(%d+)$")
    id = tonumber(id)
    if not id then return end
    withProfile(player, function(me)
        local function send(card)
            if card and isElement(player) then triggerLatentClientEvent(player, "rp:tinder:card", 400000, false, resourceRoot, card) end
        end
        if kind == "n" then T.npcCard(player, me, id, send) else playerCard(player, me, id, send) end
    end)
end)

----------------------------------------------------------------
-- Swipe
----------------------------------------------------------------
local lastSwipe = {}   -- [player] = { kind, id, action } para "deshacer" (Gold)

local function matchPayload(card)
    return { key = card.key, kind = card.kind, id = card.id, name = card.name, thumb = card.thumb, scene = card.scene }
end

function T.announceMatch(characterId, info)
    local p = T.push(characterId, "rp:tinder:match", info)
    if p then T.notify(p, "🔥 ¡Es un match con " .. tostring(info.name) .. "!", "success") end
end

local function swipePlayer(player, me, targetId, action)
    local liked = action == "super" and 2 or (action == "like" and 1 or 0)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(player) or not affected or affected < 1 or liked == 0 then return end
        if liked == 2 then
            local other = T.playerOf(targetId)
            if other then T.notify(other, "⭐ Alguien te dio un Super Like en Tinder.", "info") end
        end
        -- ¿Like de vuelta? Es match
        dbQuery(function(qh2)
            local rows = dbPoll(qh2, 0) or {}
            local r = rows[1]
            if not r or not isElement(player) then return end
            T.announceMatch(me.id, { key = "p" .. targetId, kind = "p", id = targetId, name = T.firstName(r.name), thumb = r.thumb })
            T.announceMatch(targetId, { key = "p" .. me.id, kind = "p", id = me.id, name = T.firstName(me.name), thumb = r.my_thumb })
        end, T.db(), [[
            SELECT c.name, t.thumb, (SELECT thumb FROM tinder_profiles WHERE character_id = ?) AS my_thumb
            FROM tinder_swipes s JOIN characters c ON c.id = s.swiper_id
            LEFT JOIN tinder_profiles t ON t.character_id = c.id
            WHERE s.swiper_id = ? AND s.target_id = ? AND s.liked >= 1
        ]], me.id, targetId, me.id)
    end, T.db(), [[
        INSERT INTO tinder_swipes (swiper_id, target_id, liked)
        SELECT mp.character_id, t.character_id, ?
        FROM tinder_profiles mp
        JOIN characters me ON me.id = mp.character_id
        JOIN tinder_profiles t ON t.character_id = ?
        JOIN characters c ON c.id = t.character_id
        WHERE mp.character_id = ? AND t.active = 1 AND t.photo IS NOT NULL AND mp.photo IS NOT NULL
          AND t.character_id <> mp.character_id
          AND (mp.interested = 'a' OR mp.interested = IF(c.gender = 1, 'f', 'm'))
          AND (t.interested = 'a' OR t.interested = IF(me.gender = 1, 'f', 'm'))
        ON DUPLICATE KEY UPDATE liked = VALUES(liked), created_at = NOW()
    ]], liked, targetId, me.id)
end

addEventHandler("rp:tinder:swipe", resourceRoot, function(key, action)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "swipe", 220) then return end
    if action ~= "like" and action ~= "nope" and action ~= "super" then return end
    local kind, id = tostring(key or ""):match("^([pn])(%d+)$")
    id = tonumber(id)
    if not id then return end
    withProfile(player, function(me, characterId)
        if kind == "p" and id == characterId then return end
        local likes, supers = quota(me)
        if action == "like" and likes <= 0 then
            triggerClientEvent(player, "rp:tinder:outOfLikes", resourceRoot, "likes")
            return
        end
        if action == "super" and supers <= 0 then
            triggerClientEvent(player, "rp:tinder:outOfLikes", resourceRoot, "supers")
            return
        end
        if action == "like" then me.likesUsed = me.likesUsed + 1 end
        if action == "super" then me.supersUsed = me.supersUsed + 1 end
        if action ~= "nope" then saveQuota(characterId, me) end
        lastSwipe[player] = { kind = kind, id = id, action = action }
        local l, s = quota(me)
        triggerClientEvent(player, "rp:tinder:quota", resourceRoot, l, s)
        if kind == "p" then swipePlayer(player, me, id, action)
        else T.npcSwipe(player, me, id, action) end
    end)
end)

-- Deshacer el ultimo "nope" (Tinder Gold)
addEventHandler("rp:tinder:rewind", resourceRoot, function()
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "rewind", 1000) then return end
    withProfile(player, function(me, characterId)
        if not me.gold then return triggerClientEvent(player, "rp:tinder:needGold", resourceRoot, "rewind") end
        local last = lastSwipe[player]
        if not last or last.action ~= "nope" then return T.notify(player, "Solo puedes deshacer el último que descartaste.", "info") end
        lastSwipe[player] = nil
        local function resend()
            local function send(card)
                if card and isElement(player) then triggerLatentClientEvent(player, "rp:tinder:rewound", 400000, false, resourceRoot, card) end
            end
            if last.kind == "n" then T.npcCard(player, me, last.id, send) else playerCard(player, me, last.id, send) end
        end
        if last.kind == "p" then
            dbQuery(function(qh) dbPoll(qh, 0) resend() end, T.db(),
                "DELETE FROM tinder_swipes WHERE swiper_id = ? AND target_id = ? AND liked = 0", characterId, last.id)
        else
            dbQuery(function(qh) dbPoll(qh, 0) resend() end, T.db(),
                "UPDATE tinder_npc_links SET player_swipe = NULL, swiped_at = NULL WHERE character_id = ? AND npc_id = ? AND player_swipe = 0",
                characterId, last.id)
        end
    end)
end)

----------------------------------------------------------------
-- Matches y conversaciones
----------------------------------------------------------------
local function preview(body)
    body = tostring(body or "")
    if #body > 60 then body = body:sub(1, 57):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "..." end
    return body
end
T.preview = preview

local function playerMatches(characterId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local list = {}
        for _, r in ipairs(rows) do
            local id = tonumber(r.id)
            list[#list + 1] = {
                key = "p" .. id, kind = "p", id = id, name = T.firstName(r.name), age = tonumber(r.age), thumb = r.thumb,
                last = r.last_body and preview(r.last_body) or nil, lastMine = tonumber(r.last_sender) == characterId,
                ts = tonumber(r.ts) or 0, unread = tonumber(r.unread) or 0, online = T.playerOf(id) ~= nil,
            }
        end
        callback(list)
    end, T.db(), [[
        SELECT c.id, c.name, c.age, t.thumb,
               m.body AS last_body, m.sender_id AS last_sender,
               UNIX_TIMESTAMP(COALESCE(m.created_at, GREATEST(a.created_at, b.created_at))) AS ts,
               (SELECT COUNT(*) FROM tinder_messages u WHERE u.sender_id = c.id AND u.receiver_id = a.swiper_id AND u.read_at IS NULL) AS unread
        FROM tinder_swipes a
        JOIN tinder_swipes b ON b.swiper_id = a.target_id AND b.target_id = a.swiper_id AND b.liked >= 1
        JOIN characters c ON c.id = a.target_id
        LEFT JOIN tinder_profiles t ON t.character_id = c.id
        LEFT JOIN tinder_messages m ON m.id = (
            SELECT MAX(x.id) FROM tinder_messages x
            WHERE (x.sender_id = a.swiper_id AND x.receiver_id = c.id) OR (x.sender_id = c.id AND x.receiver_id = a.swiper_id))
        WHERE a.swiper_id = ? AND a.liked >= 1
        LIMIT 60
    ]], characterId)
end

addEventHandler("rp:tinder:matches:get", resourceRoot, function()
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "matches", 700) then return end
    local characterId = T.characterOf(player)
    playerMatches(characterId, function(list)
        T.npcMatches(characterId, function(npcList)
            if not isElement(player) then return end
            for _, m in ipairs(npcList) do list[#list + 1] = m end
            table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
            triggerLatentClientEvent(player, "rp:tinder:matches", 400000, false, resourceRoot, list)
        end)
    end)
end)

-- ¿Sigue siendo match con ese jugador? callback(bool, name)
local function isPlayerMatch(a, b, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        callback(rows[1] ~= nil, rows[1] and T.firstName(rows[1].name))
    end, T.db(), [[
        SELECT c.name FROM tinder_swipes x JOIN tinder_swipes y ON y.swiper_id = x.target_id AND y.target_id = x.swiper_id AND y.liked >= 1
        JOIN characters c ON c.id = x.target_id
        WHERE x.swiper_id = ? AND x.target_id = ? AND x.liked >= 1
    ]], a, b)
end

addEventHandler("rp:tinder:chat:open", resourceRoot, function(key)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "chat", 300) then return end
    local kind, id = tostring(key or ""):match("^([pn])(%d+)$")
    id = tonumber(id)
    if not id then return end
    local characterId = T.characterOf(player)
    if kind == "n" then return T.npcChatOpen(player, characterId, id) end
    isPlayerMatch(characterId, id, function(ok, name)
        if not ok or not isElement(player) then return end
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            if not isElement(player) then return end
            local msgs = {}
            for i = #rows, 1, -1 do
                local r = rows[i]
                msgs[#msgs + 1] = { mine = tonumber(r.sender_id) == characterId, body = r.body, ts = tonumber(r.ts), read = not T.isNull(r.read_at) }
            end
            local other = T.playerOf(id)
            triggerLatentClientEvent(player, "rp:tinder:chat", 300000, false, resourceRoot, {
                key = key, kind = "p", id = id, name = name, messages = msgs, online = other ~= nil,
            })
            dbExec(T.db(), "UPDATE tinder_messages SET read_at = NOW() WHERE sender_id = ? AND receiver_id = ? AND read_at IS NULL", id, characterId)
            if other then triggerClientEvent(other, "rp:tinder:read", resourceRoot, "p" .. characterId) end
        end, T.db(), [[
            SELECT sender_id, body, read_at, UNIX_TIMESTAMP(created_at) AS ts FROM tinder_messages
            WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
            ORDER BY id DESC LIMIT 80
        ]], characterId, id, id, characterId)
    end)
end)

local sent = {}   -- [player] = { start, count } tope de mensajes por minuto

addEventHandler("rp:tinder:chat:send", resourceRoot, function(key, text)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "send", 600) then return end
    local kind, id = tostring(key or ""):match("^([pn])(%d+)$")
    id = tonumber(id)
    text = cleanLine(text, TINDER.MESSAGE_MAX, false)
    if not id or not text or text == "" then return end
    local now = getTickCount()
    local s = sent[player]
    if not s or now - s.start > 60000 then s = { start = now, count = 0 } sent[player] = s end
    s.count = s.count + 1
    if s.count > 25 then return T.notify(player, "Vas muy rápido. Espera un momento.", "warning") end

    local characterId = T.characterOf(player)
    dbExec(T.db(), "UPDATE tinder_profiles SET last_active = NOW() WHERE character_id = ?", characterId)
    if kind == "n" then return T.npcChatSend(player, characterId, id, text) end
    isPlayerMatch(characterId, id, function(ok)
        if not ok or not isElement(player) then return end
        dbQuery(function(qh)
            local _, _, insertId = dbPoll(qh, 0)
            if not insertId or not isElement(player) then return end
            local ts = getRealTime().timestamp
            triggerClientEvent(player, "rp:tinder:message", resourceRoot, key, { mine = true, body = text, ts = ts })
            local other = T.playerOf(id)
            if other then
                triggerClientEvent(other, "rp:tinder:message", resourceRoot, "p" .. characterId,
                    { mine = false, body = text, ts = ts, name = T.firstName(getPlayerName(player)) })
            end
        end, T.db(), "INSERT INTO tinder_messages (sender_id, receiver_id, body) VALUES (?, ?, ?)", characterId, id, text)
    end)
end)

addEventHandler("rp:tinder:unmatch", resourceRoot, function(key)
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "unmatch", 800) then return end
    local kind, id = tostring(key or ""):match("^([pn])(%d+)$")
    id = tonumber(id)
    if not id then return end
    local characterId = T.characterOf(player)
    if kind == "n" then
        dbExec(T.db(), "UPDATE tinder_npc_links SET state = 'unmatched', reply_at = NULL WHERE character_id = ? AND npc_id = ?", characterId, id)
        triggerClientEvent(player, "rp:tinder:unmatched", resourceRoot, key)
        return T.notify(player, "Match deshecho.", "success")
    end
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(player) or not affected or affected < 1 then return end
        T.notify(player, "Match deshecho.", "success")
        triggerClientEvent(player, "rp:tinder:unmatched", resourceRoot, key)
        T.push(id, "rp:tinder:unmatched", "p" .. characterId)
    end, T.db(), "UPDATE tinder_swipes SET liked = 0 WHERE swiper_id = ? AND target_id = ? AND liked >= 1", characterId, id)
end)

----------------------------------------------------------------
-- "Le gustas": quien te dio like y aun no has visto. Con Gold se ven las fotos.
----------------------------------------------------------------
addEventHandler("rp:tinder:likes:get", resourceRoot, function()
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "likes", 800) then return end
    withProfile(player, function(me, characterId)
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            local list = {}
            for _, r in ipairs(rows) do
                list[#list + 1] = { key = "p" .. r.id, name = T.firstName(r.name), age = tonumber(r.age), thumb = r.thumb, super = tonumber(r.liked) == 2 }
            end
            T.npcLikesYou(characterId, function(npcList)
                if not isElement(player) then return end
                for _, m in ipairs(npcList) do list[#list + 1] = m end
                triggerLatentClientEvent(player, "rp:tinder:likes", 400000, false, resourceRoot, { gold = me.gold, list = list })
            end)
        end, T.db(), [[
            SELECT c.id, c.name, c.age, t.thumb, s.liked FROM tinder_swipes s
            JOIN characters c ON c.id = s.swiper_id JOIN tinder_profiles t ON t.character_id = c.id
            WHERE s.target_id = ? AND s.liked >= 1 AND t.active = 1
              AND NOT EXISTS (SELECT 1 FROM tinder_swipes m WHERE m.swiper_id = s.target_id AND m.target_id = s.swiper_id)
            LIMIT 30
        ]], characterId)
    end)
end)

----------------------------------------------------------------
-- Tinder Gold: se paga con el banco
----------------------------------------------------------------
addEventHandler("rp:tinder:gold:buy", resourceRoot, function()
    local player = client
    if not T.canUse(player) or not T.cooldown(player, "gold", 3000) then return end
    local characterId = T.characterOf(player)
    -- chargeAccount es sincrono (export del banco): una sola llamada, con cooldown
    local ok = exports.rp_bank:chargeAccount(characterId, TINDER.GOLD_PRICE, "Tinder Gold")
    if not ok then return T.notify(player, "No tienes saldo suficiente en el banco para Tinder Gold.", "error") end
    dbQuery(function(qh)
        dbPoll(qh, 0)
        if not isElement(player) then return end
        T.profiles[characterId] = nil
        exports.rp_notify:popup(player, "Tinder Gold", ("Activado por %d días: likes ilimitados, %d Super Likes al día, ver quién te dio like y deshacer."):format(TINDER.GOLD_DAYS, TINDER.GOLD_SUPERS), "success", 7000)
        sendProfile(player)
    end, T.db(), [[
        INSERT INTO tinder_profiles (character_id, gold_until) VALUES (?, NOW() + INTERVAL ? DAY)
        ON DUPLICATE KEY UPDATE gold_until = GREATEST(COALESCE(gold_until, NOW()), NOW()) + INTERVAL ? DAY
    ]], characterId, TINDER.GOLD_DAYS, TINDER.GOLD_DAYS)
end)

----------------------------------------------------------------
-- Globo del icono: mensajes sin leer + likes nuevos
----------------------------------------------------------------
function T.sendBadge(player)
    local characterId = T.characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        local r = rows[1] or {}
        triggerClientEvent(player, "rp:tinder:badge", resourceRoot, {
            unread = (tonumber(r.p) or 0) + (tonumber(r.n) or 0), likes = (tonumber(r.l) or 0) + (tonumber(r.pl) or 0),
        })
    end, T.db(), [[
        SELECT (SELECT COUNT(*) FROM tinder_messages WHERE receiver_id = ? AND read_at IS NULL) AS p,
               (SELECT COUNT(*) FROM tinder_npc_messages m JOIN tinder_npc_links k ON k.character_id = m.character_id AND k.npc_id = m.npc_id
                WHERE m.character_id = ? AND m.from_npc = 1 AND m.delivered = 1 AND m.read_at IS NULL AND k.state <> 'unmatched') AS n,
               (SELECT COUNT(*) FROM tinder_npc_links WHERE character_id = ? AND npc_swipe >= 1 AND player_swipe IS NULL
                AND npc_decide_at IS NULL) AS l,
               (SELECT COUNT(*) FROM tinder_swipes s WHERE s.target_id = ? AND s.liked >= 1
                AND NOT EXISTS (SELECT 1 FROM tinder_swipes m WHERE m.swiper_id = s.target_id AND m.target_id = s.swiper_id)) AS pl
    ]], characterId, characterId, characterId, characterId)
end

addEventHandler("rp:tinder:badge:get", resourceRoot, function()
    if T.canUse(client) and T.cooldown(client, "badge", 1500) then T.sendBadge(client) end
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
local function cleanup(player)
    cooldowns[player], lastSwipe[player], sent[player] = nil, nil, nil
    local characterId = T.characterOf(player)
    if characterId then T.profiles[characterId] = nil end
end
addEventHandler("onPlayerQuit", root, function() cleanup(source) end)
addEventHandler("rp:onCharacterLogout", root, function(characterId)
    cleanup(source)
    if characterId then T.profiles[characterId] = nil end
end)
