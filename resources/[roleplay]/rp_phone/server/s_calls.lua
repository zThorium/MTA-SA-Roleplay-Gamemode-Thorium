--[[
    rp_phone / s_calls.lua  (servidor)

    Llamadas entre jugadores (#115):
      - Marcar el número de otro personaje: suena (25 s), contesta o cuelga. Ocupado si ya está en
        otra llamada; sin cobertura si no tiene teléfono, está abatido o muerto. Si no contesta o
        no hay cobertura, el buzón le deja una «llamada perdida» por SMS.
      - En llamada, lo que dices por el chat (rp_chat llama a relayCallSpeech) le llega al otro con
        estilo de teléfono; quien está a tu lado te sigue oyendo. /altavoz: los de cerca del que lo
        activa oyen también al otro lado.
      - 911/912/913: suena primero a los jugadores de servicio del tipo (médicos, policía,
        bomberos); el primero que contesta la atiende. Si nadie contesta en CALLS.EMERGENCY_RING_S,
        la central IA de rp_emergency hace lo de siempre.
      - Historial en phone_calls (pestaña Recientes de la app Teléfono).

    Comandos: /contestar, /colgar, /altavoz
    Exports (servidor): isInCall(p), relayCallSpeech(p, texto)
]]

CALLS = {
    RING_S = 25,                 -- segundos sonando antes de ir al buzón
    EMERGENCY_RING_S = 20,       -- segundos sonando a los de servicio antes de la central IA
    SPEAKER_RANGE = 8,           -- metros que oyen el altavoz
    EMERGENCY_TYPES = { ambulance = "medicos", police = "policia", fire = "bomberos" },
}

local calls = {}       -- [player] = { peer, state = "ringing"|"active", outgoing, label, number, logId, started, speaker, emergency }
local emergencies = {} -- [caller] = { entry, candidates = { [player] = true }, expires, logId }

addEvent("rp:phone:answer", true)
addEvent("rp:phone:hangup", true)
addEvent("rp:phone:speaker", true)
addEvent("rp:phone:recent", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end
local function pretty(n) return (tostring(n):gsub("^(%d%d%d)(%d%d%d%d)$", "%1-%2")) end

local function reachable(p)
    return isElement(p) and charOf(p) and exports.rp_inventory:hasItem(p, "phone", 1)
        and not isPedDead(p) and not getElementData(p, "rp:downed")
end

local function playerOfCharacter(characterId)
    for _, p in ipairs(getElementsByType("player")) do
        if charOf(p) == characterId then return p end
    end
end

local function sendState(p, state, extra)
    if not isElement(p) then return end
    local c = calls[p]
    local d = extra or {}
    d.state = state
    d.name = d.name or (c and c.label) or ""
    d.number = d.number or (c and c.number) or ""
    d.speaker = c and c.speaker or false
    triggerClientEvent(p, "rp:phone:callState", resourceRoot, d)
end

-- Cómo ve `viewer` al número `number`: nombre de su agenda o el número
local function labelFor(viewer, number, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        callback(rows[1] and rows[1].name or pretty(number))
    end, db(), "SELECT name FROM phone_contacts WHERE character_id = ? AND number = ?", charOf(viewer) or 0, tonumber(number) or 0)
end

local function logCall(callerId, calleeId, callerNumber, calleeNumber, status, callback)
    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        if callback then callback(tonumber(id)) end
    end, db(), "INSERT INTO phone_calls (caller_id, callee_id, caller_number, callee_number, status) VALUES (NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, 0), ?, ?)",
        callerId or 0, calleeId or 0, tonumber(callerNumber) or 0, tostring(calleeNumber), status)
end

local function setLog(id, status, duration)
    if id then dbExec(db(), "UPDATE phone_calls SET status = ?, duration = ? WHERE id = ?", status, duration or 0, id) end
end

-- Buzón: «llamada perdida» como SMS del que llamó
local function voicemail(callerId, callerNumber, calleeId, calleeNumber)
    if not callerId or not calleeId or not callerNumber then return end
    dbExec(db(), "INSERT INTO phone_messages (sender_id, receiver_id, sender_number, receiver_number, body) VALUES (?, ?, ?, ?, ?)",
        callerId, calleeId, callerNumber, calleeNumber, "📞 Llamada perdida")
end

----------------------------------------------------------------
-- Terminar
----------------------------------------------------------------
local function endCall(p, reason, quiet)
    local c = calls[p]
    if not c then return end
    local peer = c.peer
    calls[p] = nil
    local pc = isElement(peer) and calls[peer]
    if pc and pc.peer == p then calls[peer] = nil end
    local duration = c.state == "active" and math.floor((getTickCount() - c.started) / 1000) or 0
    if c.state == "active" then setLog(c.logId, "answered", duration) end
    if not quiet then sendState(p, "ended", { text = reason or "Llamada finalizada" }) end
    if pc then
        sendState(peer, "ended", { text = c.state == "active" and "Colgaron" or (reason or "Llamada finalizada"), name = pc.label, number = pc.number })
    end
end

----------------------------------------------------------------
-- Llamar a un jugador (s_phone.lua lo usa antes de los números especiales)
----------------------------------------------------------------
function handlePlayerCall(player, number, myNumber)
    number = tonumber(number)
    if not number or number < 1000000 or number > 9999999 then return false end
    if calls[player] or emergencies[player] then notify(player, "Ya estás en una llamada. Usa /colgar.", "warning") return true end
    local myId = charOf(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        local targetId = rows[1] and tonumber(rows[1].id)
        if not targetId then
            return triggerClientEvent(player, "rp:phone:callResult", resourceRoot, tostring(number), false)
        end
        if targetId == myId then
            sendState(player, "ended", { text = "No puedes llamarte a ti mismo", number = pretty(number) })
            return
        end
        local target = playerOfCharacter(targetId)
        labelFor(player, number, function(label)
            if not isElement(player) then return end
            if not target or not reachable(target) then
                logCall(myId, targetId, myNumber, number, "missed")
                voicemail(myId, myNumber, targetId, number)
                return sendState(player, "ended", { name = label, number = pretty(number),
                    text = "El teléfono está apagado o fuera de cobertura. Dejaste una llamada perdida." })
            end
            if calls[target] or emergencies[target] then
                logCall(myId, targetId, myNumber, number, "busy")
                return sendState(player, "ended", { name = label, number = pretty(number), text = "Comunica: está en otra llamada." })
            end
            labelFor(target, myNumber, function(myLabel)
                if not isElement(player) or not isElement(target) or calls[player] or calls[target] then return end
                calls[player] = { peer = target, state = "ringing", outgoing = true, label = label, number = pretty(number), started = getTickCount() }
                calls[target] = { peer = player, state = "ringing", outgoing = false, label = myLabel, number = pretty(myNumber), started = getTickCount() }
                logCall(myId, targetId, myNumber, number, "missed", function(id)
                    if calls[player] then calls[player].logId = id end
                    if calls[target] then calls[target].logId = id end
                end)
                sendState(player, "ringing-out")
                sendState(target, "ringing-in")
                -- Suena: los de cerca lo oyen
                local x, y, z = getElementPosition(target)
                for _, near in ipairs(getElementsWithinRange(x, y, z, 10, "player")) do
                    if near ~= target then outputChatBox(("* Suena el teléfono de %s."):format(nameOf(target)), near, 194, 162, 218) end
                end
                setTimer(function()
                    local c = calls[player]
                    if c and c.peer == target and c.state == "ringing" then
                        voicemail(myId, myNumber, targetId, number)
                        endCall(player, "No contesta. Dejaste una llamada perdida.")
                    end
                end, CALLS.RING_S * 1000, 1)
            end)
        end)
    end, db(), "SELECT id FROM characters WHERE phone_number = ?", number)
    return true
end

----------------------------------------------------------------
-- Emergencias: primero los jugadores de servicio
----------------------------------------------------------------
local function emergencyFallback(caller)
    local e = emergencies[caller]
    emergencies[caller] = nil
    if not e then return end
    for p in pairs(e.candidates) do if isElement(p) and not calls[p] then sendState(p, "ended", { text = "Otra unidad o la central atendió la llamada" }) end end
    if not isElement(caller) then return end
    local ok = false
    local emergency = getResourceFromName("rp_emergency")
    if emergency and getResourceState(emergency) == "running" then ok = exports.rp_emergency:callService(caller, e.entry.service) end
    triggerClientEvent(caller, "rp:phone:callResult", resourceRoot, e.entry.number, ok == true)
end

function handleEmergencyCall(player, entry, myNumber)
    local kind = CALLS.EMERGENCY_TYPES[entry.service]
    if not kind then return false end
    local ok, list = pcall(function() return exports.rp_factions:getFactionPlayers(kind, true) end)
    local candidates, n = {}, 0
    for _, p in ipairs(ok and type(list) == "table" and list or {}) do
        if p ~= player and reachable(p) and not calls[p] then candidates[p] = true; n = n + 1 end
    end
    if n == 0 then return false end                  -- nadie de servicio: la central IA (s_phone)
    if calls[player] or emergencies[player] then return true end
    emergencies[player] = { entry = entry, candidates = candidates, myNumber = myNumber }
    local x, y, z = getElementPosition(player)
    local zone = getZoneName(x, y, z)
    sendState(player, "ringing-out", { name = entry.name .. " (" .. entry.number .. ")", number = entry.number })
    for p in pairs(candidates) do
        triggerClientEvent(p, "rp:phone:callState", resourceRoot, { state = "ringing-in", emergency = true,
            name = ("%s · %s"):format(entry.number, nameOf(player)), number = zone, speaker = false })
    end
    setTimer(function() if emergencies[player] then emergencyFallback(player) end end, CALLS.EMERGENCY_RING_S * 1000, 1)
    return true
end

local function answerEmergency(p)
    for caller, e in pairs(emergencies) do
        if e.candidates[p] then
            emergencies[caller] = nil
            if not isElement(caller) then return true end
            for other in pairs(e.candidates) do
                if other ~= p and isElement(other) then sendState(other, "ended", { text = nameOf(p) .. " atendió la llamada" }) end
            end
            local label = ("%s · %s"):format(e.entry.number, nameOf(caller))
            calls[caller] = { peer = p, state = "active", outgoing = true, label = e.entry.name, number = e.entry.number, started = getTickCount() }
            calls[p] = { peer = caller, state = "active", outgoing = false, label = label, number = "", started = getTickCount(), emergency = true }
            logCall(charOf(caller), charOf(p), e.myNumber, e.entry.number, "answered", function(id)
                if calls[caller] then calls[caller].logId = id end
                if calls[p] then calls[p].logId = id end
            end)
            sendState(caller, "active")
            sendState(p, "active")
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- Contestar, colgar, altavoz
----------------------------------------------------------------
local function answer(p)
    local c = calls[p]
    if not c then
        if answerEmergency(p) then return end
        return notify(p, "No tienes ninguna llamada entrante.", "info")
    end
    if c.state ~= "ringing" or c.outgoing then return end
    if not reachable(p) then return notify(p, "No puedes contestar ahora.", "warning") end
    local peer = c.peer
    c.state, c.started = "active", getTickCount()
    if calls[peer] then calls[peer].state, calls[peer].started = "active", getTickCount() end
    sendState(p, "active")
    sendState(peer, "active")
    exports.rp_notify:notify(p, "En llamada: habla por el chat (T). /colgar para terminar, /altavoz para que te oigan los de cerca.", "info")
end

local function hangup(p)
    if calls[p] then
        local c = calls[p]
        if c.state == "ringing" and not c.outgoing then
            setLog(c.logId, "rejected")
            return endCall(p, "Rechazaste la llamada")
        end
        return endCall(p)
    end
    if emergencies[p] then
        emergencies[p] = nil
        return sendState(p, "ended", { text = "Llamada cancelada" })
    end
    for caller, e in pairs(emergencies) do
        if e.candidates[p] then e.candidates[p] = nil; sendState(p, "ended", { text = "Llamada rechazada" }) return end
    end
end

local function speaker(p)
    local c = calls[p]
    if not c or c.state ~= "active" then return notify(p, "No estás en una llamada.", "info") end
    c.speaker = not c.speaker
    sendState(p, "active")
    notify(p, c.speaker and "Altavoz activado: los de cerca oyen la llamada." or "Altavoz desactivado.", "info")
end

addCommandHandler("contestar", function(p) answer(p) end)
addCommandHandler("colgar", function(p) hangup(p) end)
addCommandHandler("altavoz", function(p) speaker(p) end)
addEventHandler("rp:phone:answer", resourceRoot, function() answer(client) end)
addEventHandler("rp:phone:hangup", resourceRoot, function() hangup(client) end)
addEventHandler("rp:phone:speaker", resourceRoot, function() speaker(client) end)

----------------------------------------------------------------
-- Hablar por teléfono (rp_chat)
----------------------------------------------------------------
function isInCall(p)
    local c = calls[p]
    return c ~= nil and c.state == "active"
end

function relayCallSpeech(p, text)
    local c = calls[p]
    if not c or c.state ~= "active" or type(text) ~= "string" then return false end
    local peer = c.peer
    local pc = isElement(peer) and calls[peer]
    if not pc then return false end
    text = text:gsub("#%x%x%x%x%x%x", ""):sub(1, 150)
    local line = ("#C2A2DA[Teléfono] #F2F4F8%s#C2A2DA: #E6E9F0%s"):format(pc.label ~= "" and pc.label or "Voz", text)
    outputChatBox(line, peer, 255, 255, 255, true)
    if pc.speaker then
        local x, y, z = getElementPosition(peer)
        for _, near in ipairs(getElementsWithinRange(x, y, z, CALLS.SPEAKER_RANGE, "player")) do
            if near ~= peer and near ~= p then
                outputChatBox(("#C2A2DA[Altavoz de %s] #E6E9F0%s"):format(nameOf(peer), text), near, 255, 255, 255, true)
            end
        end
    end
    return true
end

----------------------------------------------------------------
-- Historial (pestaña Recientes)
----------------------------------------------------------------
local lastRecent = {}
addEventHandler("rp:phone:recent", resourceRoot, function()
    local p = client
    local id = charOf(p)
    if not id or (lastRecent[p] and getTickCount() - lastRecent[p] < 1000) then return end
    lastRecent[p] = getTickCount()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) then return end
        local out = {}
        for _, r in ipairs(rows) do
            local outgoing = tonumber(r.caller_id) == id
            out[#out + 1] = { outgoing = outgoing, status = r.status, duration = tonumber(r.duration) or 0, date = r.date,
                number = outgoing and tostring(r.callee_number) or tostring(r.caller_number or ""), name = r.name }
        end
        triggerClientEvent(p, "rp:phone:recentList", resourceRoot, out)
    end, db(), [[
        SELECT c.caller_id, c.callee_number, c.caller_number, c.status, c.duration,
               DATE_FORMAT(c.created_at, '%d/%m %H:%i') AS date,
               (SELECT pc.name FROM phone_contacts pc WHERE pc.character_id = ?
                  AND pc.number = IF(c.caller_id = ?, c.callee_number, c.caller_number) LIMIT 1) AS name
        FROM phone_calls c WHERE c.caller_id = ? OR c.callee_id = ? ORDER BY c.id DESC LIMIT 30
    ]], id, id, id, id)
end)

----------------------------------------------------------------
-- Pierde la cobertura (abatido, sin teléfono, muerto) o se va
----------------------------------------------------------------
local coverageTimer = setTimer(function()
    for p, c in pairs(calls) do
        if not isElement(p) then calls[p] = nil
        elseif not reachable(p) then endCall(p, "Se cortó la llamada") end
    end
    for caller in pairs(emergencies) do
        if not isElement(caller) then emergencies[caller] = nil end
    end
end, 2000, 0)

local function forget(p)
    if calls[p] then endCall(p, nil, true) end
    emergencies[p] = nil
    for _, e in pairs(emergencies) do e.candidates[p] = nil end
    lastRecent[p] = nil
end
addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEvent("rp:onCharacterLogout", false)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(coverageTimer) then killTimer(coverageTimer) end
end)
