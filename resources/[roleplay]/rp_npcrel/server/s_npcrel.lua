--[[
    rp_npcrel / s_npcrel.lua

    Vinculos con la gente del barrio, al estilo Los Sims. El jugador habla con un
    peaton (tecla H): charla, bromea, coquetea... y amistad y romance suben segun
    los rasgos de la persona, su humor y lo repetido que sea el jugador.
    Al llegar a "Conocido" la persona se guarda (npc_contacts) y el jugador puede
    volver a verla llamandola por telefono. Si se gustan (romance + amistad)
    su numero se guarda solo en el telefono del jugador (phone_contacts).

    El servidor decide todo (resultado, dinero, etapa, frase); el cliente solo muestra
    camara, animaciones, particulas y el panel CEF. Los peatones del mundo son locales
    de cada cliente (rp_citizens), asi que el servidor no puede comprobar la distancia:
    lo limitan los cooldowns, la fatiga, el tope de conversacion y el de personas
    nuevas por hora.

    Los dialogos viven en s_lines.lua (NPCREL_LINES).

    Comandos:
        /vinculos        panel con tus vinculos (amistad, romance, etapa, telefono)
    Exports:
        callNpc(player, numero)   llamada desde rp_phone a un numero de vinculo
        createDateContact(charId, datos)  cita de Tinder: crea el vinculo con numero (rp_phone)
        getDialogueStats()        conteo y validacion del banco de dialogos (rp_test)
]]

local sessions = {}     -- [player] = conversacion en curso
local playerInfo = {}   -- [player] = { characterId, gender }
local summoned = {}     -- [player] = { id, expires }
local lastBegin = {}    -- [player] = tick
local lastList = {}     -- [player] = tick (/vinculos)
local newPeople = {}    -- [player] = { hourStart, count }
local callAt = {}       -- ["charId:npcId"] = tick de la ultima llamada
local tiredUntil = {}   -- ["charId:npcId"] = tick hasta el que no quiere hablar
local strangerTired = {}-- [player] = tick

addEvent("rp:onCharacterLogout", false)
addEvent("rp:npcrel:ui:begin", true)
addEvent("rp:npcrel:ui:act", true)
addEvent("rp:npcrel:ui:end", true)
addEvent("rp:npcrel:ui:list", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function hasPhone(p) return exports.rp_inventory:hasItem(p, "phone", 1) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function pick(list) return list[math.random(#list)] end
local function firstName(name) return (tostring(name or ""):match("^(%S+)")) or tostring(name or "") end
-- estandar:dep-opcional rp_levels  XP al subir de etapa; se comprueba con running()
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local ACTION_BY_ID = {}
for _, a in ipairs(NPCREL_ACTIONS) do ACTION_BY_ID[a.id] = a end

----------------------------------------------------------------
-- Generacion de personas
----------------------------------------------------------------
local FIRST = {
    [0] = { "Carlos", "Diego", "Mateo", "Luis", "Andrés", "Javier", "Marco", "Rafael", "Tomás", "Julián",
            "Esteban", "Gabriel", "Nicolás", "Iván", "Sergio", "Damián", "Joaquín", "Emilio", "Bruno", "Hugo",
            "Ramiro", "Óscar", "Felipe", "Adrián" },
    [1] = { "Sofía", "Valeria", "Camila", "Lucía", "Daniela", "Mariana", "Isabel", "Carolina", "Paula", "Renata",
            "Andrea", "Natalia", "Fernanda", "Elena", "Bianca", "Jimena", "Ximena", "Regina", "Abril", "Martina",
            "Gabriela", "Noelia", "Lorena", "Alma" },
}
local LAST = { "Rojas", "Mendoza", "Vega", "Castillo", "Herrera", "Ortega", "Salazar", "Cruz", "Navarro", "Ibarra",
               "Paredes", "Fuentes", "Montoya", "Quiroga", "Lara", "Rivas", "Acosta", "Benítez", "Cabrera", "Duarte",
               "Escobar", "Guzmán", "Medina", "Solís" }

-- A quien le gusta: 84% el genero opuesto, 8% el mismo, 8% todos
local function rollLikes(gender)
    local r = math.random()
    if r < 0.08 then return "a" end
    local same = r < 0.16
    local target = same and gender or (1 - gender)
    return target == 1 and "f" or "m"
end

local function newStranger(skin)
    local gender = NPCREL_SKIN_GENDER[skin]
    local t1 = pick(NPCREL_TRAIT_IDS)
    local t2 = t1
    while t2 == t1 do t2 = pick(NPCREL_TRAIT_IDS) end
    return {
        id = nil, name = pick(FIRST[gender]) .. " " .. pick(LAST), gender = gender, skin = skin,
        traits = { t1, t2 }, likes = rollLikes(gender),
        friendship = 0, romance = 0, dating = 0, numberShared = false, phone = nil, interactions = 0, idleDays = 0,
    }
end

local function npcFromRow(r)
    local traits = {}
    for t in tostring(r.traits or ""):gmatch("[^,]+") do if NPCREL_TRAITS[t] then traits[#traits + 1] = t end end
    local friendship, romance, dating = tonumber(r.friendship) or 0, tonumber(r.romance) or 0, tonumber(r.dating) or 0
    -- Se enfria si pasa mucho tiempo sin hablar
    local idle = tonumber(r.idle_days) or 0
    local extra = idle - NPCREL.DECAY_FREE_DAYS
    if extra > 0 then
        local f = dating == 1 and 0.5 or 1
        romance = clamp(romance - math.floor(extra * NPCREL.DECAY_ROMANCE * f), 0, NPCREL_RULES.MAX)
        friendship = clamp(friendship - math.floor(extra * NPCREL.DECAY_FRIENDSHIP * f), 0, NPCREL_RULES.MAX)
    end
    return {
        id = tonumber(r.id), name = r.name, gender = tonumber(r.gender) or 0, skin = tonumber(r.skin),
        traits = traits, likes = r.likes or "a", phone = tonumber(r.phone_number),
        friendship = friendship, romance = romance, dating = dating,
        numberShared = tonumber(r.number_shared) == 1, interactions = tonumber(r.interactions) or 0,
        idleDays = idle,
    }
end

----------------------------------------------------------------
-- Dialogos (banco en s_lines.lua)
----------------------------------------------------------------
local function tierOf(stage)
    if stage >= 5 then return "hi" end
    if stage >= 3 then return "mid" end
    return "lo"
end

-- Une "any" y el nivel de confianza; una lista simple se devuelve tal cual
local function poolOf(group, tier)
    if type(group) ~= "table" then return nil end
    if group[1] then return group end
    local out = {}
    for _, t in ipairs(group.any or {}) do out[#out + 1] = t end
    for _, t in ipairs(group[tier] or {}) do out[#out + 1] = t end
    if #out == 0 then for _, t in ipairs(group.lo or {}) do out[#out + 1] = t end end
    return #out > 0 and out or nil
end

local function fill(text, npc, session)
    local pg = session and session.playerGender or 0
    local pname = session and session.playerName or ""
    text = text:gsub("{n}", firstName(npc.name)):gsub("{p}", pname ~= "" and pname or "tú")
    text = text:gsub("{o}", npc.gender == 1 and "a" or "o"):gsub("{e}", pg == 1 and "a" or "o")
    return text
end

-- Elige una frase del grupo para esta persona y etapa
local function say(session, group, stage)
    local npc = session.npc
    stage = stage or npcrelStage(npc.friendship, npc.romance, npc.dating)
    local pool = poolOf(group, tierOf(stage))
    if not pool then return "" end
    return fill(pick(pool), npc, session)
end

-- A veces la reaccion sale con el caracter de la persona
local function traitFlavor(session, outcome)
    if math.random() > 0.3 then return nil end
    local trait = pick(session.npc.traits)
    local set = trait and NPCREL_LINES.traits[trait]
    local pool = set and set[outcome == "bad" and "bad" or "good"]
    return pool and fill(pick(pool), session.npc, session) or nil
end

local function greeting(session, visit)
    local npc = session.npc
    local stage = npcrelStage(npc.friendship, npc.romance, npc.dating)
    local G = NPCREL_LINES.greet
    if visit and math.random() < 0.7 then return say(session, G.visit, stage) end
    if npc.id and npc.idleDays > NPCREL.DECAY_FREE_DAYS and math.random() < 0.7 then return say(session, G.absent, stage) end
    local hour = getRealTime().hour
    if stage <= 2 and math.random() < 0.3 then
        if hour >= 6 and hour < 11 then return say(session, G.morning, stage) end
        if hour >= 21 or hour < 4 then return say(session, G.night, stage) end
    end
    local key = ({ "stranger", "known", "friend", "crush", "couple", "couple" })[stage]
    return say(session, G[key], stage)
end

----------------------------------------------------------------
-- Estado del jugador
----------------------------------------------------------------
local function withPlayerInfo(player, callback)
    local characterId = characterOf(player)
    if not characterId then return end
    local info = playerInfo[player]
    if info and info.characterId == characterId then return callback(info) end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or not rows[1] or characterOf(player) ~= characterId then return end
        playerInfo[player] = {
            characterId = characterId, gender = tonumber(rows[1].gender) or 0,
            name = firstName((tostring(rows[1].name or getPlayerName(player)):gsub("_", " "))),
        }
        callback(playerInfo[player])
    end, db(), "SELECT gender, name FROM characters WHERE id = ?", characterId)
end

local function dbReady() return exports.rp_database:isReady() == true end

local function canInteract(player)
    return isElement(player) and characterOf(player) and not isPedDead(player)
        and not getElementData(player, "rp:downed") and not isPedInVehicle(player)
end

local function compatible(npc, playerGender)
    if npc.likes == "a" then return true end
    return (npc.likes == "m" and playerGender == 0) or (npc.likes == "f" and playerGender == 1)
end

----------------------------------------------------------------
-- Datos para el cliente
----------------------------------------------------------------
local function needText(a)
    if a.id == "kiss" then return "Hay que ser pareja" end
    if a.id == "askout" then return "Romance " .. NPCREL_RULES.ASK_OUT_ROMANCE .. "+" end
    if a.min == 2 then return "Amistad " .. NPCREL_RULES.KNOWN .. "+" end
    if a.min == 3 then return "Amistad " .. NPCREL_RULES.FRIEND .. "+" end
    if a.min == 4 then return "Que se gusten" end
    return ""
end

local function actionAvailable(a, npc, stage)
    if stage < a.min then return false end
    if a.id == "kiss" and npc.dating ~= 1 then return false end
    if a.id == "askout" and (npc.dating == 1 or npc.romance < NPCREL_RULES.ASK_OUT_ROMANCE) then return false end
    return true
end

-- Lo que la accion suele dar, para que el jugador elija sabiendo
local function effectText(a)
    if a.id == "number" then return "Guarda su número" end
    if a.id == "askout" then return "Ser pareja" end
    if a.id == "bye" then return "Terminar la charla" end
    local parts = {}
    if (a.friendship or 0) > 0 then parts[#parts + 1] = "+Amistad" end
    if (a.romance or 0) > 0 then parts[#parts + 1] = "+Romance" end
    return table.concat(parts, " ")
end

local function buildActions(session, stage)
    local npc = session.npc
    local list = {}
    for _, a in ipairs(NPCREL_ACTIONS) do
        local ok = actionAvailable(a, npc, stage)
        local hint
        if not ok then
            hint = (a.id == "askout" and npc.dating == 1) and "Ya son pareja" or needText(a)
        elseif session.noRomance and (a.kind == "romance" or a.id == "askout") then
            hint = "Solo te ve como amig" .. (session.playerGender == 1 and "a" or "o")
        else
            hint = a.cost and ("$" .. NPCREL.GIFT_PRICE) or ""
        end
        list[#list + 1] = {
            id = a.id, label = a.label, icon = a.icon, kind = a.kind, enabled = ok,
            risky = a.risky == true, hint = hint, effect = effectText(a),
            tired = ok and #(session.history[a.id] or {}) >= 2,
        }
    end
    return list
end

local function revealedTraits(npc, stage)
    local out = {}
    local n = stage >= 3 and 2 or (stage >= 2 and 1 or 0)
    for i = 1, math.min(n, #npc.traits) do out[#out + 1] = NPCREL_TRAITS[npc.traits[i]].label end
    return out
end

local function moodLabel(mood, gender)
    local g = gender == 1 and "a" or "o"
    if mood >= 1.12 then return "Animad" .. g, "happy" end
    if mood <= 0.88 then return "Apagad" .. g, "sad" end
    return "Tranquil" .. g, "calm"
end

-- Que le falta al jugador para la siguiente etapa (una sola meta, la mas cercana)
local function nextGoal(npc, stage, session)
    local R = NPCREL_RULES
    if session and session.noRomance and stage >= 3 then return "Te ve como amig" .. (session.playerGender == 1 and "a" or "o") .. ": cuida la amistad." end
    if stage == 1 then return ("Amistad %d para que te recuerde."):format(R.KNOWN) end
    if stage == 2 then
        if npc.romance >= R.CRUSH_ROMANCE * 0.5 then return ("Romance %d y amistad %d para gustarse."):format(R.CRUSH_ROMANCE, R.CRUSH_FRIENDSHIP) end
        return ("Amistad %d para ser amigos."):format(R.FRIEND)
    end
    if stage == 3 then return ("Romance %d para gustarse."):format(R.CRUSH_ROMANCE) end
    if stage == 4 then
        if npc.romance >= R.ASK_OUT_ROMANCE then return "¡Ya puedes pedirle salir!" end
        return ("Romance %d para pedirle salir."):format(R.ASK_OUT_ROMANCE)
    end
    if stage == 5 then return ("Romance %d y amistad %d: pareja estable."):format(R.STABLE_ROMANCE, R.STABLE_FRIENDSHIP) end
    return "Su relación está en lo más alto."
end

local function snapshot(session)
    local npc = session.npc
    local stage = npcrelStage(npc.friendship, npc.romance, npc.dating)
    local mood, moodKey = moodLabel(session.mood, npc.gender)
    return {
        name = npc.name, gender = npc.gender, skin = npc.skin, id = npc.id,
        friendship = npc.friendship, romance = npc.romance, dating = npc.dating == 1,
        stage = stage, stageName = NPCREL_STAGES[stage].name,
        traits = revealedTraits(npc, stage), traitCount = #npc.traits,
        mood = mood, moodKey = moodKey,
        actions = buildActions(session, stage),
        left = NPCREL.SESSION_ACTIONS - session.count, total = NPCREL.SESSION_ACTIONS,
        goal = nextGoal(npc, stage, session), saved = npc.id ~= nil, numberShared = npc.numberShared,
        rules = { known = NPCREL_RULES.KNOWN, friend = NPCREL_RULES.FRIEND, crush = NPCREL_RULES.CRUSH_ROMANCE,
                  askout = NPCREL_RULES.ASK_OUT_ROMANCE, stable = NPCREL_RULES.STABLE_ROMANCE },
    }
end

----------------------------------------------------------------
-- Persistencia
----------------------------------------------------------------
local function takeNewPersonSlot(player)
    local now = getTickCount()
    local n = newPeople[player]
    if not n or now - n.hourStart > 3600000 then n = { hourStart = now, count = 0 } newPeople[player] = n end
    if n.count >= NPCREL.NEW_PEOPLE_PER_HOUR then return false end
    n.count = n.count + 1
    return true
end

-- Guarda a la persona la primera vez (con numero de telefono unico). callback(ok)
local function persistNew(player, session, callback, attempt)
    local npc, characterId = session.npc, session.characterId
    attempt = attempt or 0
    if attempt > 6 then return callback(false) end
    local number = math.random(NPCREL.NUMBER_MIN, NPCREL.NUMBER_MAX)
    dbQuery(function(qh)
        local ok, affected, insertId = dbPoll(qh, 0)
        if ok then
            npc.id, npc.phone = tonumber(insertId), number
            return callback(true)
        end
        if affected == 1062 then return persistNew(player, session, callback, attempt + 1) end   -- numero repetido
        callback(false)
    end, db(), [[
        INSERT INTO npc_contacts (character_id, name, gender, skin, traits, likes, phone_number, friendship, romance, dating, interactions)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], characterId, npc.name, npc.gender, npc.skin, table.concat(npc.traits, ","), npc.likes, number,
        npc.friendship, npc.romance, npc.dating, npc.interactions)
end

local function persistUpdate(session)
    local npc = session.npc
    if not npc.id then return end
    dbExec(db(), [[
        UPDATE npc_contacts SET friendship = ?, romance = ?, dating = ?, interactions = ?, last_interaction = NOW()
        WHERE id = ? AND character_id = ?
    ]], npc.friendship, npc.romance, npc.dating, npc.interactions, npc.id, session.characterId)
end

-- Guarda el numero de la persona en el telefono del jugador
local function shareNumber(player, session, auto)
    local npc = session.npc
    if npc.numberShared or not npc.id or not npc.phone then return end
    npc.numberShared = true
    local characterId = session.characterId
    dbExec(db(), "UPDATE npc_contacts SET number_shared = 1 WHERE id = ? AND character_id = ?", npc.id, characterId)
    dbQuery(function(qh)
        dbPoll(qh, 0)
        if not isElement(player) then return end
        local first = firstName(npc.name)
        if auto then
            exports.rp_notify:popup(player, "¡Se gustan!", first .. " te dio su número. Quedó guardado en tu teléfono.", "success", 6500)
        else
            notify(player, first .. " te dio su número. Quedó guardado en tu teléfono.", "success")
        end
        if not hasPhone(player) then notify(player, "Necesitas un teléfono para verlo en tus contactos.", "warning") end
        triggerClientEvent(player, "rp:npcrel:numberShared", resourceRoot, npc.name, auto == true)
    end, db(), [[
        INSERT INTO phone_contacts (character_id, name, number) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name)
    ]], characterId, npc.name, npc.phone)
end

----------------------------------------------------------------
-- Resolver una accion
----------------------------------------------------------------
local function hourFactor()
    local hour = getRealTime().hour
    if hour >= 20 or hour < 4 then return 0.15 end
    if hour >= 6 and hour < 10 then return -0.15 end
    return 0
end

local function newMood(kind)
    local m = 1 + (math.random() - 0.5) * 0.3
    if kind == "romance" then m = m + hourFactor() end
    return clamp(m, 0.7, 1.3)
end

local function fatigueFor(session, actionId, now)
    local list = session.history[actionId] or {}
    local fresh = {}
    for _, t in ipairs(list) do if now - t < NPCREL.FATIGUE_WINDOW then fresh[#fresh + 1] = t end end
    session.history[actionId] = fresh
    return math.max(0.2, 1 - NPCREL.FATIGUE_STEP * #fresh), #fresh
end

local function traitRisk(npc)
    local risk = 0
    for _, t in ipairs(npc.traits) do risk = risk + (NPCREL_TRAITS[t].risk or 0) end
    return risk
end

local function traitMult(npc, actionId)
    local m = 1
    for _, t in ipairs(npc.traits) do m = m * ((NPCREL_TRAITS[t].mult or {})[actionId] or 1) end
    return m
end

-- Devuelve el resultado (sin tocar la BD): { outcome, text, playerText, ended }
local function resolve(player, session, a, playerGender)
    local npc, now = session.npc, getTickCount()
    local L = NPCREL_LINES
    local before = npcrelStage(npc.friendship, npc.romance, npc.dating)
    local res = { action = a.id, outcome = "good", ended = false }
    res.playerText = say(session, L.player[a.id], before)

    if a.id == "bye" then
        res.text, res.ended = say(session, L.bye.good, before), true
        return res, before
    end

    local wantsRomance = a.kind == "romance" or a.id == "askout"
    if wantsRomance and not compatible(npc, playerGender) then
        session.noRomance = true
        res.outcome, res.text, res.reject = "bad", say(session, L.notInterested, before), "romance"
        npc.friendship = clamp(npc.friendship + 1, 0, NPCREL_RULES.MAX)   -- la amistad no se pierde
        return res, before
    end

    local fatigue, repeats = fatigueFor(session, a.id, now)
    local mood = session.mood

    if a.id == "number" then
        if npc.numberShared then res.text = say(session, L.number.have, before) return res, before end
        local chance = before >= 3 and 1 or (npc.friendship >= 25 and 0.6 or 0.25)
        if math.random() <= chance * math.min(1.15, mood) then
            res.wantNumber, res.text = true, say(session, L.number.good, before)
        else
            res.outcome, res.text = "bad", say(session, L.number.bad, before)
        end
        return res, before
    end

    if a.id == "askout" then
        local chance = npc.romance >= 75 and 0.85 or 0.65
        if math.random() <= chance * math.min(1.15, mood) then
            npc.dating = 1
            res.outcome, res.celebrate, res.text = "great", true, say(session, L.askout.great, before)
        else
            npc.romance = clamp(npc.romance - 3, 0, NPCREL_RULES.MAX)
            res.outcome, res.text = "bad", say(session, L.askout.bad, before)
            res.gain = { friendship = 0, romance = -3 }
        end
        return res, before
    end

    -- Acciones normales: puede salir mal segun el tipo, el rasgo y el humor
    local chance = 0.92
    if a.kind == "romance" and a.id ~= "kiss" then
        chance = 0.62 + npc.friendship / 250 + (mood - 1) - traitRisk(npc)
        if a.risky then chance = chance - 0.05 end
    elseif a.kind == "friend" then
        chance = 0.9 + (mood - 1) * 0.3 - traitRisk(npc) * 0.5
    end
    if math.random() > clamp(chance, 0.15, 0.98) then
        npc.friendship = clamp(npc.friendship - 1, 0, NPCREL_RULES.MAX)
        local dr = 0
        if a.kind == "romance" then dr = -2 npc.romance = clamp(npc.romance - 2, 0, NPCREL_RULES.MAX) end
        res.outcome = "bad"
        res.text = traitFlavor(session, "bad") or say(session, L[a.id].bad, before)
        res.gain = { friendship = -1, romance = dr }
        return res, before
    end

    local mult = traitMult(npc, a.id) * fatigue * mood
    local df = math.floor((a.friendship or 0) * mult + 0.5)
    local dr = math.floor((a.romance or 0) * mult + 0.5)
    if (a.friendship or 0) > 0 and df < 1 then df = 1 end
    if (a.romance or 0) > 0 and dr < 1 and fatigue > 0.5 then dr = 1 end
    npc.friendship = clamp(npc.friendship + df, 0, NPCREL_RULES.MAX)
    npc.romance = clamp(npc.romance + dr, 0, NPCREL_RULES.MAX)
    res.gain = { friendship = df, romance = dr }
    local total = df + dr
    res.outcome = total >= 6 and "great" or "good"
    if repeats >= 2 and total <= 2 then
        res.text, res.bored = say(session, L.repeat_, before), true
    else
        local group = (res.outcome == "great" and L[a.id].great) or L[a.id].good
        res.text = (res.outcome == "good" and traitFlavor(session, "good")) or say(session, group, before)
    end
    session.history[a.id][#session.history[a.id] + 1] = now
    return res, before
end

local function finishAction(player, session, res, before)
    local npc = session.npc
    npc.interactions = npc.interactions + 1
    local stage = npcrelStage(npc.friendship, npc.romance, npc.dating)
    res.stageUp = stage > before and stage or nil
    if res.stageUp then
        local pool = NPCREL_LINES.stageUp[stage]
        if pool then res.stageText = fill(pick(pool), npc, session) end
    end

    if session.count >= NPCREL.SESSION_ACTIONS and not res.ended then
        res.ended = true
        res.tiredText = say(session, NPCREL_LINES.tired, stage)
    end
    if res.ended then
        if npc.id then tiredUntil[session.characterId .. ":" .. npc.id] = getTickCount() + NPCREL.SESSION_PAUSE
        else strangerTired[player] = getTickCount() + 2 * 60000 end
    end

    local function send()
        if not isElement(player) or sessions[player] ~= session then return end
        session.busy = false
        res.state = snapshot(session)
        triggerClientEvent(player, "rp:npcrel:result", resourceRoot, res)
        if res.ended then sessions[player] = nil end
    end

    local function afterPersist()
        persistUpdate(session)
        if res.stageUp and running("rp_levels") then
            pcall(function() exports.rp_levels:giveXP(player, math.min(40, res.stageUp * 5), "vinculo") end)
        end
        if res.wantNumber then shareNumber(player, session, false)
        elseif stage >= 4 and not npc.numberShared then
            res.autoNumber = true
            shareNumber(player, session, true)
        end
        send()
    end

    -- Se guarda al llegar a "Conocido"
    if not npc.id and stage >= 2 then
        persistNew(player, session, function(ok)
            if not isElement(player) then return end
            if ok then
                res.saved = true
                afterPersist()
            else
                npc.friendship = math.min(npc.friendship, NPCREL_RULES.KNOWN - 1)
                notify(player, "No logras recordar bien a esta persona.", "warning")
                send()
            end
        end)
    elseif not npc.id then
        send()
    else
        afterPersist()
    end
end

----------------------------------------------------------------
-- Eventos del cliente
----------------------------------------------------------------
addEventHandler("rp:npcrel:ui:begin", resourceRoot, function(skin, npcId)
    local player = client
    local now = getTickCount()
    if lastBegin[player] and now - lastBegin[player] < 1500 then return end
    lastBegin[player] = now
    if not canInteract(player) or not dbReady() then return end
    skin, npcId = tonumber(skin), tonumber(npcId)
    if not skin or not NPCREL_SKIN_GENDER[skin] then return end
    if sessions[player] then sessions[player] = nil end

    withPlayerInfo(player, function(info)
        if not canInteract(player) then return end
        local function open(npc, kind, visit)
            local session = {
                npc = npc, characterId = info.characterId, playerGender = info.gender, playerName = info.name,
                count = 0, mood = newMood(kind), history = {}, lastAct = 0,
            }
            for _, a in ipairs(NPCREL_ACTIONS) do session.history[a.id] = {} end
            sessions[player] = session
            local data = snapshot(session)
            data.greeting = greeting(session, visit)
            triggerClientEvent(player, "rp:npcrel:open", resourceRoot, data)
        end

        if npcId then
            local s = summoned[player]
            if not s or s.id ~= npcId or now > s.expires then return end
            local key = info.characterId .. ":" .. npcId
            if tiredUntil[key] and now < tiredUntil[key] then
                return notify(player, "Hoy ya no tiene más ganas de hablar. Llámale más tarde.", "info")
            end
            dbQuery(function(qh)
                local rows = dbPoll(qh, 0) or {}
                if not rows[1] or not canInteract(player) or characterOf(player) ~= info.characterId then return end
                open(npcFromRow(rows[1]), "romance", true)
            end, db(), [[
                SELECT *, DATEDIFF(NOW(), last_interaction) AS idle_days
                FROM npc_contacts WHERE id = ? AND character_id = ?
            ]], npcId, info.characterId)
        else
            if strangerTired[player] and now < strangerTired[player] then
                return notify(player, "Esa persona tiene prisa y no quiere hablar.", "info")
            end
            if not takeNewPersonSlot(player) then
                return notify(player, "Hoy has hablado con mucha gente. Ya te cuesta recordar caras nuevas.", "warning")
            end
            open(newStranger(skin), "friend", false)
        end
    end)
end)

addEventHandler("rp:npcrel:ui:act", resourceRoot, function(actionId)
    local player = client
    local session = sessions[player]
    if not session or session.busy or type(actionId) ~= "string" then return end
    if not canInteract(player) then sessions[player] = nil return end
    local a = ACTION_BY_ID[actionId]
    if not a then return end
    local now = getTickCount()
    if now - session.lastAct < NPCREL.ACTION_COOLDOWN then return end

    local npc = session.npc
    local stage = npcrelStage(npc.friendship, npc.romance, npc.dating)
    if not actionAvailable(a, npc, stage) then return end

    if a.cost then
        if getPlayerMoney(player) < NPCREL.GIFT_PRICE then
            return notify(player, ("Un regalo cuesta $%d y no te alcanza."):format(NPCREL.GIFT_PRICE), "error")
        end
        takePlayerMoney(player, NPCREL.GIFT_PRICE)
        pcall(function() exports.rp_characters:saveCharacter(player) end)
    end

    session.lastAct = now
    session.busy = true
    session.count = session.count + 1
    local res, before = resolve(player, session, a, session.playerGender)
    finishAction(player, session, res, before)
end)

addEventHandler("rp:npcrel:ui:end", resourceRoot, function()
    sessions[client] = nil
end)

local function cleanup(player)
    sessions[player], playerInfo[player], summoned[player], lastBegin[player] = nil, nil, nil, nil
    newPeople[player], strangerTired[player], lastList[player] = nil, nil, nil
end
addEventHandler("rp:onCharacterLogout", root, function() cleanup(source) end)
addEventHandler("onPlayerQuit", root, function() cleanup(source) end)

----------------------------------------------------------------
-- Llamadas desde rp_phone: la persona viene a verte
----------------------------------------------------------------
function callNpc(player, number)
    number = tonumber(number)
    if not isElement(player) or not number or not canInteract(player) or not dbReady() then return false end
    local characterId = characterOf(player)
    -- El evento lo escucha el cliente de rp_phone en su propio resourceRoot
    local function result(ok)
        local phone = getResourceFromName("rp_phone")
        local root_ = phone and getResourceRootElement(phone)
        if root_ and isElement(player) then triggerClientEvent(player, "rp:phone:callResult", root_, tostring(number), ok == true) end
    end

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        local r = rows[1]
        if not r then
            notify(player, "El número marcado no está disponible.", "info")
            return result(false)
        end
        local npc = npcFromRow(r)
        local key = characterId .. ":" .. npc.id
        local now = getTickCount()
        if callAt[key] and now - callAt[key] < NPCREL.CALL_COOLDOWN then
            notify(player, "Acabas de hablar con esa persona. Dale un rato.", "info")
            return result(false)
        end
        callAt[key] = now
        local stage = npcrelStage(npc.friendship, npc.romance, npc.dating)
        local pickup = npc.dating == 1 and 1 or (stage >= 3 and 0.9 or 0.7)
        local fake = { npc = npc, playerGender = playerInfo[player] and playerInfo[player].gender or 0,
                       playerName = playerInfo[player] and playerInfo[player].name or "" }
        if math.random() > pickup then
            notify(player, fill(pick(NPCREL_LINES.phoneNoAnswer), npc, fake), "warning")
            return result(false)
        end
        result(true)
        notify(player, firstName(npc.name) .. ": \"" .. say(fake, NPCREL_LINES.phonePickup, stage) .. "\"", "success")
        summoned[player] = { id = npc.id, expires = now + 15000 + NPCREL.SUMMON_TIME }
        setTimer(function()
            if not isElement(player) or characterOf(player) ~= characterId then return end
            local s = summoned[player]
            if not s or s.id ~= npc.id then return end
            triggerClientEvent(player, "rp:npcrel:summon", resourceRoot, {
                id = npc.id, name = npc.name, skin = npc.skin, gender = npc.gender,
                stage = stage, dating = npc.dating == 1, stay = NPCREL.SUMMON_TIME,
            })
        end, math.random(8000, 14000), 1)
    end, db(), [[
        SELECT *, DATEDIFF(NOW(), last_interaction) AS idle_days
        FROM npc_contacts WHERE character_id = ? AND phone_number = ? AND number_shared = 1
    ]], characterId, number)
    return true
end

----------------------------------------------------------------
-- Citas de Tinder (rp_phone): la persona del chat pasa a ser un vinculo con su numero
-- guardado en el telefono. Al llamarla viene a verte, como cualquier vinculo.
-- Responde con el evento de servidor "rp:npcrel:dateContact" (ref, numero|nil).
----------------------------------------------------------------
addEvent("rp:npcrel:dateContact", false)

function createDateContact(characterId, data)
    characterId = tonumber(characterId)
    if not characterId or type(data) ~= "table" or not dbReady() then return false end
    local gender = tonumber(data.gender) == 1 and 1 or 0
    local skin = tonumber(data.skin)
    if not skin then return false end
    local traits = {}
    if type(data.traits) == "table" then
        for _, t in ipairs(data.traits) do
            if NPCREL_TRAITS[t] and #traits < 2 then traits[#traits + 1] = t end
        end
    end
    if #traits == 0 then traits = { pick(NPCREL_TRAIT_IDS) } end
    local likes = ({ m = "m", f = "f", a = "a" })[data.likes] or "a"
    local session = {
        characterId = characterId,
        npc = {
            id = nil, name = tostring(data.name or "Alguien"):sub(1, 48), gender = gender, skin = skin, traits = traits, likes = likes,
            friendship = clamp(tonumber(data.friendship) or 25, 0, NPCREL_RULES.MAX),
            romance = clamp(tonumber(data.romance) or 30, 0, NPCREL_RULES.MAX),
            dating = 0, numberShared = false, interactions = 1, idleDays = 0,
        },
    }
    local ref = data.ref
    persistNew(nil, session, function(ok)
        local npc = session.npc
        if not ok or not npc.phone then return triggerEvent("rp:npcrel:dateContact", root, ref, nil) end
        dbExec(db(), "UPDATE npc_contacts SET number_shared = 1 WHERE id = ? AND character_id = ?", npc.id, characterId)
        dbExec(db(), [[
            INSERT INTO phone_contacts (character_id, name, number) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name)
        ]], characterId, npc.name:sub(1, 32), npc.phone)
        triggerEvent("rp:npcrel:dateContact", root, ref, npc.phone)
    end)
    return true
end

----------------------------------------------------------------
-- /vinculos: panel con todas tus personas
----------------------------------------------------------------
local function sendList(player)
    local characterId = characterOf(player)
    if not characterId or not dbReady() then return end
    local now = getTickCount()
    if lastList[player] and now - lastList[player] < 1500 then return end
    lastList[player] = now
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        local list = {}
        for _, r in ipairs(rows) do
            local npc = npcFromRow(r)
            local stage = npcrelStage(npc.friendship, npc.romance, npc.dating)
            list[#list + 1] = {
                name = npc.name, gender = npc.gender, stage = stage, stageName = NPCREL_STAGES[stage].name,
                friendship = npc.friendship, romance = npc.romance, dating = npc.dating == 1,
                phone = npc.numberShared and npc.phone or nil, traits = revealedTraits(npc, stage),
                idleDays = npc.idleDays, cooling = npc.idleDays > NPCREL.DECAY_FREE_DAYS,
                interactions = npc.interactions, goal = nextGoal(npc, stage, nil),
            }
        end
        table.sort(list, function(a, b)
            if a.stage ~= b.stage then return a.stage > b.stage end
            return a.friendship + a.romance > b.friendship + b.romance
        end)
        triggerClientEvent(player, "rp:npcrel:list", resourceRoot, list, NPCREL.MAX_CONTACTS, NPCREL.DECAY_FREE_DAYS)
    end, db(), [[
        SELECT id, name, gender, skin, traits, likes, phone_number, friendship, romance, dating, number_shared, interactions,
               DATEDIFF(NOW(), last_interaction) AS idle_days
        FROM npc_contacts WHERE character_id = ? ORDER BY romance + friendship DESC LIMIT ?
    ]], characterId, NPCREL.MAX_CONTACTS)
end

addCommandHandler("vinculos", function(player) sendList(player) end)
addEventHandler("rp:npcrel:ui:list", resourceRoot, function() sendList(client) end)

----------------------------------------------------------------
-- Prueba de humo: el banco de dialogos esta completo y las marcas se sustituyen
----------------------------------------------------------------
function getDialogueStats()
    local L = NPCREL_LINES
    local total, missing = 0, {}
    local function count(group)
        if type(group) ~= "table" then return 0 end
        if group[1] then return #group end
        local n = 0
        for _, list in pairs(group) do n = n + #list end
        return n
    end
    for _, a in ipairs(NPCREL_ACTIONS) do
        if count(L.player[a.id]) == 0 then missing[#missing + 1] = "player." .. a.id end
        local set = L[a.id]
        if not set then missing[#missing + 1] = a.id
        else
            if count(set.good or set.great) == 0 then missing[#missing + 1] = a.id .. ".good" end
            if a.id ~= "bye" and a.id ~= "askout" and count(set.bad) == 0 then missing[#missing + 1] = a.id .. ".bad" end
        end
    end
    for stage = 2, #NPCREL_STAGES do if count(L.stageUp[stage]) == 0 then missing[#missing + 1] = "stageUp." .. stage end end
    -- Recorre todas las frases sustituyendo marcas: ninguna debe quedar sin reemplazar
    local fake = { npc = { name = "Ana Prueba", gender = 1 }, playerGender = 0, playerName = "Leo" }
    local leftovers = 0
    local function walk(t)
        for _, v in pairs(t) do
            if type(v) == "string" then
                total = total + 1
                if fill(v, fake.npc, fake):find("[{}]") then leftovers = leftovers + 1 end
            elseif type(v) == "table" then walk(v) end
        end
    end
    walk(L)
    return { lines = total, missing = missing, leftovers = leftovers }
end
