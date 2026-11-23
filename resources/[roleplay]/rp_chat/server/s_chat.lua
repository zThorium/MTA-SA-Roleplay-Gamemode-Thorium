--[[
    rp_chat / s_chat.lua
    Chat de rol. El chat por defecto (T) es "decir" IC por proximidad.

        T / texto normal   decir (15 m)            burbuja sobre la cabeza
        Y  /susurrar [id] texto   susurro (3 m) o al oido de un jugador (alias /w)
        U  /gritar texto          grito (40 m) con animacion          (alias /g)
        B  /b texto               OOC local (15 m), sin burbuja
        /me accion  /do descripcion   rol de accion y entorno (15 m)
        /ame accion               barra roja sobre la cabeza (vive en rp_nametags)
        /pm <id> texto            mensaje privado OOC (queda en chat_pm_log)
    Admin (nivel 1+):
        /pmlog <id o nombre> [cantidad]   historial de PMs de un jugador

    Los PMs son OOC: usar esa informacion IC es MG.
]]

local RANGE = { say = 15, whisper = 3, shout = 40, ooc = 15 }
local MAX_LEN, COOLDOWN_MS = 150, 500
local lastUse = {}      -- [player] = tick
local pmWarned = {}     -- [player] = true (aviso de MG, una vez por sesion)

addEvent("rp:chat:bubble", true)

local function db() return exports.rp_database:getConnection() end
local function charId(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end
local function adminLevel(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end

-- Limpia texto: sin codigos de color #RRGGBB ni control, recorta y capitaliza
local function clean(text)
    text = tostring(text or ""):gsub("#%x%x%x%x%x%x", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:sub(1, MAX_LEN)
    return (text:gsub("^%l", string.upper))
end

local function canSpeak(player)
    if not charId(player) then return false end
    if getElementData(player, "rp:downed") then
        outputChatBox("No puedes hablar abatido.", player, 255, 120, 120)
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

-- Gris cuanto mas lejos: 255 cerca -> 140 en el limite
local function shade(d, range)
    local v = math.floor(255 - 115 * math.min(1, d / range))
    return v, v, v
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
        outputChatBox(("%s dice: %s"):format(who, text), l.p, shade(l.d, RANGE.say))
    end
    bubble(list, player, text, "say")
    gesture(player, "PED", "IDLE_chat", math.min(4000, #text * 80))
end

local function shout(player, text)
    text = clean(text)
    if text == "" or not canSpeak(player) then return end
    local list = listeners(player, RANGE.shout)
    local who = nameOf(player)
    for _, l in ipairs(list) do
        outputChatBox(("%s grita: %s!"):format(who, text:gsub("[!%.]+$", "")), l.p, 255, 150 + math.floor(60 * l.d / RANGE.shout), 120)
    end
    bubble(list, player, text:upper(), "shout")
    gesture(player, "ON_LOOKERS", "shout_01", 2200)
end

local function whisper(player, targetQuery, text)
    local target
    if targetQuery then
        target = exports.rp_ids:findPlayer(targetQuery)
        if not target or target == player or not charId(target) then
            return outputChatBox("No se encontro ese jugador.", player, 255, 120, 120)
        end
    end
    text = clean(text)
    if text == "" then
        return outputChatBox("Uso: /susurrar [id] <texto>  (sin id: lo oye quien este muy cerca)", player, 255, 200, 80)
    end
    if not canSpeak(player) then return end

    local list = listeners(player, RANGE.whisper)
    local who = nameOf(player)
    if target then
        local near = false
        for _, l in ipairs(list) do if l.p == target then near = true end end
        if not near then return outputChatBox("Esta demasiado lejos para susurrarle.", player, 255, 120, 120) end
        outputChatBox(("* %s te susurra: %s"):format(who, text), target, 190, 170, 255)
        outputChatBox(("* Le susurras a %s: %s"):format(nameOf(target), text), player, 160, 140, 220)
        for _, l in ipairs(list) do
            if l.p ~= target and l.p ~= player then
                outputChatBox(("* %s le susurra algo al oido a %s."):format(who, nameOf(target)), l.p, 200, 160, 255)
            end
        end
        bubble({ { p = target }, { p = player } }, player, text, "whisper")
    else
        for _, l in ipairs(list) do
            if l.p == player then
                outputChatBox(("* Susurras: %s"):format(text), l.p, 160, 140, 220)
            else
                outputChatBox(("* %s susurra: %s"):format(who, text), l.p, 190, 170, 255)
            end
        end
        bubble(list, player, text, "whisper")
    end
    gesture(player, "PED", "IDLE_chat", 1800)
end

local function ooc(player, text)
    text = clean(text)
    if text == "" then return outputChatBox("Uso: /b <texto>  (chat OOC local)", player, 255, 200, 80) end
    if not canSpeak(player) then return end
    for _, l in ipairs(listeners(player, RANGE.ooc)) do
        outputChatBox(("(( [OOC] %s: %s ))"):format(nameOf(player), text), l.p, 130, 190, 255)
    end
end

-- /me: accion del personaje; /do: descripcion del entorno o resultado (lleva el autor entre parentesis)
local function emote(player, text, isDo)
    text = clean(text)
    if text == "" then
        return outputChatBox(isDo and "Uso: /do <descripcion>  (ej: /do La puerta esta cerrada con llave.)"
            or "Uso: /me <accion>  (ej: /me saca su billetera del bolsillo.)", player, 255, 200, 80)
    end
    if not canSpeak(player) then return end
    for _, l in ipairs(listeners(player, RANGE.say)) do
        if isDo then
            outputChatBox(("* %s (( %s ))"):format(text, nameOf(player)), l.p, 120, 210, 160)
        else
            outputChatBox(("* %s %s"):format(nameOf(player), (text:gsub("^%u", string.lower))), l.p, 255, 150 + math.floor(60 * l.d / RANGE.say), 190)
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
        return outputChatBox("Uso: /pm <id> <mensaje>  (OOC: usar esta informacion IC es MG)", player, 255, 200, 80)
    end
    local target = exports.rp_ids:getPlayerFromId(id)
    if not target or not charId(target) then
        return outputChatBox("No hay ningun jugador con ese ID.", player, 255, 120, 120)
    end
    if target == player then return outputChatBox("No puedes enviarte un PM a ti mismo.", player, 255, 120, 120) end
    local now = getTickCount()
    if lastUse[player] and now - lastUse[player] < COOLDOWN_MS then return end
    lastUse[player] = now

    local sid, tid = exports.rp_ids:getPlayerId(player), exports.rp_ids:getPlayerId(target)
    outputChatBox(("[PM de %s (%d)] %s"):format(nameOf(player), sid, text), target, 255, 220, 90)
    outputChatBox(("[PM para %s (%d)] %s"):format(nameOf(target), tid, text), player, 255, 190, 60)
    for _, p in ipairs({ player, target }) do
        if not pmWarned[p] then
            pmWarned[p] = true
            outputChatBox("Los PM son OOC: usar su informacion en rol (IC) es MG y se sanciona.", p, 255, 90, 90)
        end
    end

    dbExec(db(), "INSERT INTO chat_pm_log (sender_char, sender_name, target_char, target_name, message) VALUES (?, ?, ?, ?, ?)",
        charId(player), getPlayerName(player), charId(target), getPlayerName(target), text)
end)

-- /pmlog <id o nombre> [cantidad]: PMs enviados o recibidos por un personaje (admin 1+)
addCommandHandler("pmlog", function(player, _, query, count)
    if adminLevel(player) < 1 then return end
    if not query then return outputChatBox("Uso: /pmlog <id o nombre> [cantidad 1-50]", player, 255, 200, 80) end
    local target = exports.rp_ids:findPlayer(query)
    local name = target and getPlayerName(target) or tostring(query):gsub(" ", "_")
    local limit = math.max(1, math.min(50, tonumber(count) or 15))

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not rows then return outputChatBox("Error consultando el historial.", player, 255, 120, 120) end
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
