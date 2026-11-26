--[[
    rp_chat / s_chat.lua
    Chat de rol. El chat por defecto (T) es "decir" IC por proximidad.

        T / texto normal   decir (15 m)            burbuja sobre la cabeza
        Y  /susurrar [id] texto   susurro (3 m) o al oido de un jugador (alias /w)
        U  /gritar texto          grito (40 m) con animacion          (alias /g)
        B  /b texto               OOC local (15 m), sin burbuja
        /me accion  /do descripcion   rol de accion y entorno (15 m)
        /ame accion               etiqueta sobre la cabeza (vive en rp_nametags)
        /pm <id> texto            mensaje privado OOC (queda en chat_pm_log)
    Admin (nivel 1+):
        /pmlog <id o nombre> [cantidad]   historial de PMs de un jugador

    Las lineas del chat llevan color por partes (nombre, verbo, texto) y se apagan con la
    distancia. Errores y usos van como aviso de rp_notify, no al chat.
    Los PMs son OOC: usar esa informacion IC es MG.
]]

local RANGE = { say = 15, whisper = 3, shout = 40, ooc = 15 }
local MAX_LEN, COOLDOWN_MS = 150, 500
local lastUse = {}      -- [player] = tick
local pmWarned = {}     -- [player] = true (aviso de MG, una vez por sesion)

-- Paleta de las lineas del chat (misma linea visual que rp_notify y las burbujas)
local C = {
    name    = { 242, 244, 248 }, verb = { 142, 150, 164 }, say = { 236, 239, 245 },
    shout   = { 255, 106, 85 },  shoutText = { 255, 232, 222 },
    whisper = { 178, 152, 255 }, whisperText = { 222, 212, 255 },
    ooc     = { 111, 168, 255 }, oocText = { 186, 204, 228 },
    me      = { 255, 150, 190 }, act = { 128, 222, 168 }, actAuthor = { 98, 160, 128 },
    pm      = { 255, 211, 90 },  pmText = { 255, 241, 194 },
}

addEvent("rp:chat:bubble", true)

local function db() return exports.rp_database:getConnection() end
local function charId(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p) return (getPlayerName(p):gsub("#%x%x%x%x%x%x", ""):gsub("_", " ")) end
local function adminLevel(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "warning") end

-- "#RRGGBB" de un color, apagado con la distancia (1 cerca -> 0.6 en el limite)
local function hex(c, d, range)
    local k = (d and range) and (1 - 0.4 * math.min(1, d / range)) or 1
    return ("#%02X%02X%02X"):format(math.floor(c[1] * k), math.floor(c[2] * k), math.floor(c[3] * k))
end
-- Linea con codigos de color (el texto del jugador llega sin #RRGGBB, ver clean)
local function line(target, text) outputChatBox(text, target, 255, 255, 255, true) end

-- Limpia texto: sin codigos de color #RRGGBB ni control, recorta y capitaliza
local function clean(text)
    text = tostring(text or ""):gsub("#%x%x%x%x%x%x", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:sub(1, MAX_LEN)
    return (text:gsub("^%l", string.upper))
end

local function canSpeak(player)
    if not charId(player) then return false end
    if getElementData(player, "rp:downed") then
        notify(player, "No puedes hablar mientras estás abatido.", "error")
        return false
    end
    local now = getTickCount()
    if lastUse[player] and now - lastUse[player] < COOLDOWN_MS then return false end
    lastUse[player] = now
    return true
end

-- Jugadores con personaje dentro de "range" metros (misma dimension e interior), con su distancia
local function listeners(player, range)
    local x, y, z = getElementPosition(player)
    local dim, int = getElementDimension(player), getElementInterior(player)
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        if charId(p) and getElementDimension(p) == dim and getElementInterior(p) == int then
            local px, py, pz = getElementPosition(p)
            local d = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
            if d <= range then out[#out + 1] = { p = p, d = d } end
        end
    end
    return out
end

local function gesture(player, block, anim, ms)
    if isPedInVehicle(player) then return end
    setPedAnimation(player, block, anim, ms, false, false, false, false)
end

local function bubble(list, player, text, kind)
    local targets = {}
    for _, l in ipairs(list) do targets[#targets + 1] = l.p end
    triggerClientEvent(targets, "rp:chat:bubble", resourceRoot, player, text, kind)
end

local function say(player, text)
    text = clean(text)
    if text == "" or not canSpeak(player) then return end
    local list = listeners(player, RANGE.say)
    local who = nameOf(player)
    for _, l in ipairs(list) do
        local d, r = l.d, RANGE.say
        line(l.p, ("%s%s %sdice: %s%s"):format(hex(C.name, d, r), who, hex(C.verb, d, r), hex(C.say, d, r), text))
    end
    bubble(list, player, text, "say")
    gesture(player, "PED", "IDLE_chat", math.min(4000, #text * 80))
end

local function shout(player, text)
    text = clean(text)
    if text == "" then return notify(player, "Uso: /gritar <texto>  (tecla U, se oye a 40 m)", "info") end
    if not canSpeak(player) then return end
    local list = listeners(player, RANGE.shout)
    local who = nameOf(player)
    local body = text:gsub("[!%.]+$", "")
    for _, l in ipairs(list) do
        local d, r = l.d, RANGE.shout
        line(l.p, ("%s%s %sgrita: %s%s!"):format(hex(C.name, d, r), who, hex(C.shout, d, r), hex(C.shoutText, d, r), body))
    end
    bubble(list, player, text:upper(), "shout")
    gesture(player, "ON_LOOKERS", "shout_01", 2200)
end

local function whisper(player, targetQuery, text)
    local target
    if targetQuery then
        target = exports.rp_ids:findPlayer(targetQuery)
        if not target or target == player or not charId(target) then
            return notify(player, "No se encontró ese jugador.", "error")
        end
    end
    text = clean(text)
    if text == "" then
        return notify(player, "Uso: /susurrar [id] <texto>  (tecla Y; sin id lo oye quien esté muy cerca)", "info")
    end
    if not canSpeak(player) then return end

    local list = listeners(player, RANGE.whisper)
    local who = nameOf(player)
    local star, nm, vb, tx = hex(C.whisper), hex(C.name), hex(C.verb), hex(C.whisperText)
    if target then
        local near = false
        for _, l in ipairs(list) do if l.p == target then near = true end end
        if not near then return notify(player, "Está demasiado lejos para susurrarle.", "warning") end
        line(target, ("%s* %s%s %ste susurra: %s%s"):format(star, nm, who, vb, tx, text))
        line(player, ("%s* %sLe susurras a %s%s%s: %s%s"):format(star, vb, nm, nameOf(target), vb, tx, text))
        for _, l in ipairs(list) do
            if l.p ~= target and l.p ~= player then
                line(l.p, ("%s* %s%s %sle susurra algo al oído a %s%s%s."):format(star, nm, who, vb, nm, nameOf(target), vb))
            end
        end
        bubble({ { p = target }, { p = player } }, player, text, "whisper")
    else
        for _, l in ipairs(list) do
            if l.p == player then
                line(l.p, ("%s* %sSusurras: %s%s"):format(star, vb, tx, text))
            else
                line(l.p, ("%s* %s%s %ssusurra: %s%s"):format(star, nm, who, vb, tx, text))
            end
        end
        bubble(list, player, text, "whisper")
    end
    gesture(player, "PED", "IDLE_chat", 1800)
end

local function ooc(player, text)
    text = clean(text)
    if text == "" then return notify(player, "Uso: /b <texto>  (chat OOC local, tecla B)", "info") end
    if not canSpeak(player) then return end
    for _, l in ipairs(listeners(player, RANGE.ooc)) do
        line(l.p, ("%s(( %sOOC %s%s: %s%s %s))"):format(hex(C.verb), hex(C.ooc), hex(C.name), nameOf(player), hex(C.oocText), text, hex(C.verb)))
    end
end

-- /me: accion del personaje; /do: descripcion del entorno o resultado (lleva el autor entre parentesis)
local function emote(player, text, isDo)
    text = clean(text)
    if text == "" then
        return notify(player, isDo and "Uso: /do <descripción>  (ej: /do La puerta está cerrada con llave.)"
            or "Uso: /me <acción>  (ej: /me saca su billetera del bolsillo.)", "info")
    end
    if not canSpeak(player) then return end
    for _, l in ipairs(listeners(player, RANGE.say)) do
        local d, r = l.d, RANGE.say
        if isDo then
            line(l.p, ("%s* %s %s(( %s ))"):format(hex(C.act, d, r), text, hex(C.actAuthor, d, r), nameOf(player)))
        else
            line(l.p, ("%s* %s%s %s%s"):format(hex(C.me, d, r), hex(C.name, d, r), nameOf(player), hex(C.me, d, r), (text:gsub("^%u", string.lower))))
        end
    end
end
addCommandHandler("me", function(p, _, ...) emote(p, table.concat({ ... }, " "), false) end)
addCommandHandler("do", function(p, _, ...) emote(p, table.concat({ ... }, " "), true) end)

-- El chat por defecto (T) pasa a ser "decir"
addEventHandler("onPlayerChat", root, function(message, kind)
    cancelEvent()
    -- 0 = say, 1 = /me (MTA lo manda como chat y no siempre como comando; el cooldown evita duplicarlo), 2 = teamsay (no se usa)
    if kind == 0 then say(source, message)
    elseif kind == 1 then emote(source, message, false) end
end)

addCommandHandler("susurrar", function(p, _, a, ...)
    -- Si el primer argumento es un numero es un ID; si no, forma parte del texto
    if a and tonumber(a) then whisper(p, a, table.concat({ ... }, " "))
    else whisper(p, nil, table.concat({ a or "", ... }, " ")) end
end)
addCommandHandler("w", function(p, _, ...) executeCommandHandler("susurrar", p, table.concat({ ... }, " ")) end)
addCommandHandler("gritar", function(p, _, ...) shout(p, table.concat({ ... }, " ")) end)
addCommandHandler("g", function(p, _, ...) shout(p, table.concat({ ... }, " ")) end)
addCommandHandler("b", function(p, _, ...) ooc(p, table.concat({ ... }, " ")) end)

----------------------------------------------------------------
-- PM (OOC)
----------------------------------------------------------------
addCommandHandler("pm", function(player, _, id, ...)
    if not charId(player) then return end
    local text = clean(table.concat({ ... }, " "))
    if not id or text == "" then
        return notify(player, "Uso: /pm <id> <mensaje>  (OOC: usar esta información en rol es MG)", "info")
    end
    local target = exports.rp_ids:getPlayerFromId(id)
    if not target or not charId(target) then
        return notify(player, "No hay ningún jugador con ese ID.", "error")
    end
    if target == player then return notify(player, "No puedes enviarte un PM a ti mismo.", "warning") end
    local now = getTickCount()
    if lastUse[player] and now - lastUse[player] < COOLDOWN_MS then return end
    lastUse[player] = now

    local sid, tid = exports.rp_ids:getPlayerId(player), exports.rp_ids:getPlayerId(target)
    local tag, vb, nm, tx = hex(C.pm), hex(C.verb), hex(C.name), hex(C.pmText)
    line(target, ("%s[PM] %sde %s%s (%d)%s: %s%s"):format(tag, vb, nm, nameOf(player), sid, vb, tx, text))
    line(player, ("%s[PM] %spara %s%s (%d)%s: %s%s"):format(tag, vb, nm, nameOf(target), tid, vb, tx, text))
    notify(target, ("Nuevo PM de %s (%d). Lo tienes en el chat."):format(nameOf(player), sid), "info")
    for _, p in ipairs({ player, target }) do
        if not pmWarned[p] then
            pmWarned[p] = true
            notify(p, "Los PM son OOC: usar su información en rol es MG y se sanciona.", "warning")
        end
    end

    if not exports.rp_database:isReady() then return end   -- el PM ya se entregó; solo no queda en el historial
    dbExec(db(), "INSERT INTO chat_pm_log (sender_char, sender_name, target_char, target_name, message) VALUES (?, ?, ?, ?, ?)",
        charId(player), getPlayerName(player), charId(target), getPlayerName(target), text)
end)

-- /pmlog <id o nombre> [cantidad]: PMs enviados o recibidos por un personaje (admin 1+)
addCommandHandler("pmlog", function(player, _, query, count)
    if adminLevel(player) < 1 then return end
    if not query then return notify(player, "Uso: /pmlog <id o nombre> [cantidad 1-50]", "info") end
    local target = exports.rp_ids:findPlayer(query)
    local name = target and getPlayerName(target) or tostring(query):gsub(" ", "_")
    local limit = math.max(1, math.min(50, tonumber(count) or 15))

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not rows then return notify(player, "Error consultando el historial de PMs.", "error") end
        outputChatBox(("===== PMs de %s (ultimos %d) ====="):format((name:gsub("_", " ")), #rows), player, 255, 220, 90)
        if #rows == 0 then outputChatBox("Sin mensajes.", player, 200, 200, 200) end
        for i = #rows, 1, -1 do   -- del mas viejo al mas nuevo
            local r = rows[i]
            outputChatBox(("#9aa0a6%s #ffffff%s #ffd35a>> #ffffff%s#9aa0a6: #ffffff%s"):format(
                r.created_at, r.sender_name:gsub("_", " "), r.target_name:gsub("_", " "), r.message), player, 255, 255, 255, true)
        end
    end, db(), "SELECT sender_name, target_name, message, created_at FROM chat_pm_log WHERE sender_name = ? OR target_name = ? ORDER BY id DESC LIMIT ?",
        name, name, limit)
    outputServerLog(("[rp_chat] %s consulto /pmlog de %s"):format(getPlayerName(player), name))
end)

addEventHandler("onPlayerQuit", root, function()
    lastUse[source], pmWarned[source] = nil, nil
end)

-- Al cambiar de personaje vuelve a avisar de que los PM son OOC
addEvent("rp:onCharacterLogout", false)
addEventHandler("rp:onCharacterLogout", root, function()
    lastUse[source], pmWarned[source] = nil, nil
end)

----------------------------------------------------------------
-- "Escribiendo...": el cliente avisa y el servidor pone el element data
-- (con elementdata_whitelisted el cliente no puede escribirlo, ver mtaserver.conf)
----------------------------------------------------------------
local typingAt = {}   -- [player] = tick del último cambio (anti spam)

addEvent("rp:chat:typing", true)
addEventHandler("rp:chat:typing", resourceRoot, function(state)
    if not client or not charId(client) then return end
    state = state == true and not getElementData(client, "rp:downed")
    local now = getTickCount()
    -- Apagar siempre se acepta; encender, como mucho cada 200 ms
    if state and typingAt[client] and now - typingAt[client] < 200 then return end
    typingAt[client] = now
    if (getElementData(client, "rp:typing") and true or false) ~= state then
        setElementData(client, "rp:typing", state)
    end
end)

local function clearTyping(player)
    typingAt[player] = nil
    if isElement(player) and getElementData(player, "rp:typing") then setElementData(player, "rp:typing", false) end
end
addEventHandler("onPlayerQuit", root, function() typingAt[source] = nil end)
addEventHandler("rp:onCharacterLogout", root, function() clearTyping(source) end)
addEventHandler("onResourceStop", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do clearTyping(p) end
end)
