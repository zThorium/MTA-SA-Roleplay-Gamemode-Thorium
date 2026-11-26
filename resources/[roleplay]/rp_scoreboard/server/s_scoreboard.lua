--[[
    rp_scoreboard / server/s_scoreboard.lua
    - Publica el nombre del servidor y el maximo de jugadores (getServerName solo existe aqui).
    - Perfil del Tab por personaje (tabla scoreboard_profiles): color o degradado del nombre,
      letras animadas, icono animado, bandera y foto pequena.
      Dato publico: setElementData(player, "rp:tabProfile", { c, c2, e, i, f, a = version de la foto }).
      La foto (data URI, hasta 200 KB) no va en el element data: el cliente la pide una vez por version.

    Eventos del cliente (todo se revalida aqui):
      rp:scoreboard:save (json)        guarda color, efecto, icono y bandera
      rp:scoreboard:setAvatar (url)    descarga la foto (https de SB.AVATAR_HOSTS, png/jpg/gif/webp)
      rp:scoreboard:clearAvatar ()
      rp:scoreboard:getAvatar (player) responde rp:scoreboard:avatar (player, version, dataUri)
    Admin: /borrarperfiltab <id o nombre> (vuelve el perfil del Tab a los valores por defecto).
]]

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:scoreboard:save", true)
addEvent("rp:scoreboard:setAvatar", true)
addEvent("rp:scoreboard:clearAvatar", true)
addEvent("rp:scoreboard:getAvatar", true)

local profiles = {}   -- [player] = { charId, c, c2, e, i, f, a, avatar }
local lastSave, lastAvatar = {}, {}

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function isHex(s) return type(s) == "string" and s:match("^#%x%x%x%x%x%x$") ~= nil end

local function publish(player)
    local p = profiles[player]
    if not isElement(player) then return end
    if not p then return setElementData(player, "rp:tabProfile", false) end
    setElementData(player, "rp:tabProfile", { c = p.c, c2 = p.c2, e = p.e, i = p.i, f = p.f, a = p.a })
end

local function defaults(charId)
    return { charId = charId, c = SB.DEFAULT_COLOR, c2 = false, e = "none", i = "", f = "", a = 0 }
end

local function load(player, charId)
    profiles[player] = defaults(charId)
    publish(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local p = profiles[player]
        if not rows or not rows[1] or not p or p.charId ~= charId then return end
        local r = rows[1]
        p.c = isHex(r.name_color) and r.name_color or SB.DEFAULT_COLOR
        p.c2 = isHex(r.name_color2) and r.name_color2 or false
        p.e = SB.EFFECT_BY_KEY[r.name_effect] and r.name_effect or "none"
        p.i = SB.ICON_BY_KEY[r.icon] and r.icon or ""
        p.f = SB.FLAG_BY_KEY[r.flag] and r.flag or ""
        p.avatar = type(r.avatar) == "string" and r.avatar ~= "" and r.avatar or nil
        p.a = p.avatar and tonumber(r.avatar_version) or 0
        publish(player)
    end, db(), "SELECT * FROM scoreboard_profiles WHERE character_id = ?", charId)
end

local function saveRow(p)
    dbExec(db(), [[INSERT INTO scoreboard_profiles (character_id, name_color, name_color2, name_effect, icon, flag, avatar, avatar_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name_color = VALUES(name_color), name_color2 = VALUES(name_color2), name_effect = VALUES(name_effect),
        icon = VALUES(icon), flag = VALUES(flag), avatar = VALUES(avatar), avatar_version = VALUES(avatar_version)]],
        p.charId, p.c, p.c2 or "", p.e, p.i, p.f, p.avatar or "", p.a)
end

addEventHandler("rp:onCharacterSpawn", root, function(charId) load(source, charId) end)
addEventHandler("rp:onCharacterLogout", root, function()
    profiles[source] = nil
    publish(source)
end)
addEventHandler("onPlayerQuit", root, function()
    profiles[source], lastSave[source], lastAvatar[source] = nil, nil, nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setElementData(resourceRoot, "server:name", getServerName())
    setElementData(resourceRoot, "server:maxPlayers", getMaxPlayers())
    -- reinicio del recurso con gente dentro (la BD ya esta lista si hay personajes en juego)
    if not exports.rp_database:isReady() then return end
    for _, player in ipairs(getElementsByType("player")) do
        local charId = exports.rp_characters:getPlayerCharacterId(player)
        if charId then load(player, charId) end
    end
end)

addEventHandler("rp:scoreboard:save", resourceRoot, function(json)
    local p = profiles[client]
    if not p or type(json) ~= "string" or #json > 512 then return end
    local now = getTickCount()
    if lastSave[client] and now - lastSave[client] < SB.SAVE_COOLDOWN then
        return notify(client, "Espera un momento antes de volver a guardar.", "warning")
    end
    local t = fromJSON(json)
    if type(t) ~= "table" then return end
    if not isHex(t.c) or (t.c2 and t.c2 ~= false and not isHex(t.c2)) then return end
    if not SB.EFFECT_BY_KEY[t.e] then return end
    if t.i ~= "" and not SB.ICON_BY_KEY[t.i] then return end
    if t.f ~= "" and not SB.FLAG_BY_KEY[t.f] then return end
    lastSave[client] = now
    p.c, p.c2, p.e, p.i, p.f = t.c:lower(), t.c2 and t.c2:lower() or false, t.e, t.i, t.f
    saveRow(p)
    publish(client)
    notify(client, "Perfil del Tab guardado.", "success")
end)

-- Tipo real del archivo por sus primeros bytes (no por la extension de la URL)
local function imageMime(body)
    if body:sub(1, 8) == "\137PNG\r\n\26\n" then return "image/png" end
    if body:sub(1, 3) == "\255\216\255" then return "image/jpeg" end
    if body:sub(1, 4) == "GIF8" then return "image/gif" end
    if body:sub(1, 4) == "RIFF" and body:sub(9, 12) == "WEBP" then return "image/webp" end
end

addEventHandler("rp:scoreboard:setAvatar", resourceRoot, function(url)
    local player, p = client, profiles[client]
    if not p or type(url) ~= "string" or #url > 400 then return end
    local host = url:match("^https://([%w%.%-]+)/[^%s\"'<>]+$")
    if not host or not SB.AVATAR_HOSTS[host:lower()] then
        return notify(player, "Usa un enlace directo https de imgur, ibb, postimg, discord, tenor o giphy.", "error")
    end
    local now = getTickCount()
    if lastAvatar[player] and now - lastAvatar[player] < SB.AVATAR_COOLDOWN then
        return notify(player, "Espera unos segundos antes de cambiar la foto otra vez.", "warning")
    end
    lastAvatar[player] = now
    -- sin redirecciones: el host validado es el que responde
    fetchRemote(url, { connectTimeout = 6000, maxRedirects = 0 }, function(body, info)
        local ok = type(info) == "table" and info.success or tonumber(info) == 0 or tonumber(info) == 200
        local cur = profiles[player]
        if not isElement(player) or cur ~= p then return end
        if not ok or type(body) ~= "string" or body == "" then
            return notify(player, "No se pudo descargar la imagen. Comprueba el enlace.", "error")
        end
        if #body > SB.AVATAR_MAX_BYTES then
            return notify(player, "La imagen pesa demasiado (máximo 200 KB).", "error")
        end
        local mime = imageMime(body)
        if not mime then return notify(player, "Ese enlace no es una imagen PNG, JPG, GIF o WEBP.", "error") end
        p.avatar = "data:" .. mime .. ";base64," .. base64Encode(body)
        p.a = getRealTime().timestamp   -- version unica: los clientes ven que cambio
        saveRow(p)
        publish(player)
        triggerClientEvent(player, "rp:scoreboard:avatar", resourceRoot, player, p.a, p.avatar)
        notify(player, "Foto del Tab actualizada.", "success")
    end)
end)

addEventHandler("rp:scoreboard:clearAvatar", resourceRoot, function()
    local p = profiles[client]
    if not p or not p.avatar then return end
    p.avatar, p.a = nil, 0
    saveRow(p)
    publish(client)
end)

addEventHandler("rp:scoreboard:getAvatar", resourceRoot, function(target)
    local p = isElement(target) and profiles[target]
    if not p or not p.avatar then return end
    triggerClientEvent(client, "rp:scoreboard:avatar", resourceRoot, target, p.a, p.avatar)
end)

addCommandHandler("borrarperfiltab", function(player, _, query)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    if not target then return notify(player, "Uso: /borrarperfiltab <id o nombre>", "warning") end
    local p = profiles[target]
    if not p then return notify(player, "Ese jugador no tiene un personaje en juego.", "warning") end
    profiles[target] = defaults(p.charId)
    dbExec(db(), "DELETE FROM scoreboard_profiles WHERE character_id = ?", p.charId)
    publish(target)
    notify(target, "Un administrador ha restablecido tu perfil del Tab.", "warning")
    notify(player, ("Perfil del Tab de %s restablecido."):format((getPlayerName(target):gsub("_", " "))), "success")
end)
