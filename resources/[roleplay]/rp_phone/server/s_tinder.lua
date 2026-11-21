--[[
    rp_phone / s_tinder.lua
    App Tinder del telefono. PARTE 1: perfil de citas del personaje.
    (Siguientes partes: swipe -> matches -> chat.)

    Tabla: tinder_profiles (por personaje). Edad y genero salen de characters (datos RP),
    el jugador solo edita foto, descripcion, a quien le interesa y si su perfil es visible.
]]

local MAX_PHOTO = 350 * 1024        -- bytes del base64 de la foto
local busy = {}

addEvent("rp:tinder:profile:get", true)
addEvent("rp:tinder:profile:save", true)

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

addEventHandler("onPlayerQuit", root, function() busy[source] = nil end)
