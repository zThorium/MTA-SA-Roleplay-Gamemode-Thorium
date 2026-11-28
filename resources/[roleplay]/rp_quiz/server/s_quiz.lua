--[[
    rp_quiz / s_quiz.lua  (servidor)

    Cuestionario de rol (#111): una cuenta sin aprobarlo no puede crear personaje (rp_characters
    pregunta hasPassedQuiz). Se abre solo tras iniciar sesión si falta, o al intentar crear un
    personaje. Las respuestas viven en server/s_config.lua; el cliente recibe las opciones
    barajadas y manda los índices que eligió. Se puede repetir (espera QUIZ.RETRY_SECONDS).

    Tutorial jugable: la primera vez que entra un personaje (characters.tutorial_done = 0) el
    cliente guía paso a paso (moverse, hablar, inventario, teléfono, mapa). Al terminarlo se
    marca y da el logro «Primer día» (rp_achievements, estadística tutorial_done).

    Exports (servidor): hasPassedQuiz(p), openQuiz(p)
    Evento público: rp:quiz:passed (source = jugador)
]]

local passed = {}     -- [player] = true | false (nil = aún no se sabe)
local sessions = {}   -- [player] = { order = { [pregunta] = { índices originales en el orden mostrado } } }
local failedAt = {}   -- [player] = tick del último suspenso

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onAccountLogin", false)
addEvent("rp:onAccountLogout", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:quiz:request", true)       -- cliente: abrir el cuestionario
addEvent("rp:quiz:submit", true)        -- cliente: respuestas
addEvent("rp:quiz:tutorialDone", true)  -- cliente: tutorial terminado (true) o saltado (false)
addEvent("rp:quiz:passed", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function accountOf(p) return exports.rp_login:getPlayerAccountId(p) end
local function charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

local function shuffled(n)
    local t = {}
    for i = 1, n do t[i] = i end
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

----------------------------------------------------------------
-- Cuestionario
----------------------------------------------------------------
function hasPassedQuiz(p)
    return passed[p] == true
end

function openQuiz(p)
    if not isElement(p) or not accountOf(p) or passed[p] then return false end
    local wait = failedAt[p] and (QUIZ.RETRY_SECONDS * 1000 - (getTickCount() - failedAt[p])) or 0
    local list, order = {}, {}
    for i, q in ipairs(QUIZ.QUESTIONS) do
        local o = shuffled(#q.options)
        order[i] = o
        local opts = {}
        for k, idx in ipairs(o) do opts[k] = q.options[idx] end
        list[i] = { text = q.text, options = opts }
    end
    sessions[p] = { order = order }
    triggerClientEvent(p, "rp:quiz:open", resourceRoot, { questions = list, pass = QUIZ.PASS, wait = math.max(0, math.ceil(wait / 1000)) })
    return true
end

local function loadAccount(p)
    local accountId = accountOf(p)
    if not accountId then return end
    passed[p] = nil
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) or accountOf(p) ~= accountId then return end
        passed[p] = rows[1] ~= nil and rows[1].quiz_passed_at ~= nil and rows[1].quiz_passed_at ~= false
        -- Recién llegado: el cuestionario sale solo sobre la pantalla de personajes
        if not passed[p] and not charOf(p) then setTimer(openQuiz, 1500, 1, p) end
    end, db(), "SELECT quiz_passed_at FROM accounts WHERE id = ?", accountId)
end

addEventHandler("rp:quiz:request", resourceRoot, function()
    if passed[client] then return notify(client, "Ya aprobaste el cuestionario de rol.", "info") end
    openQuiz(client)
end)

addEventHandler("rp:quiz:submit", resourceRoot, function(answers)
    local p = client
    local s = sessions[p]
    if not s or passed[p] or type(answers) ~= "table" then return end
    if failedAt[p] and getTickCount() - failedAt[p] < QUIZ.RETRY_SECONDS * 1000 then return end
    sessions[p] = nil
    local correct, wrong = 0, {}
    for i, q in ipairs(QUIZ.QUESTIONS) do
        local shown = tonumber(answers[i])
        local original = shown and s.order[i][shown]
        if original == q.answer then correct = correct + 1
        else wrong[#wrong + 1] = { text = q.text, right = q.options[q.answer], why = q.why } end
    end
    local ok = correct >= QUIZ.PASS
    if ok then
        passed[p] = true
        failedAt[p] = nil
        dbExec(db(), "UPDATE accounts SET quiz_passed_at = NOW() WHERE id = ? AND quiz_passed_at IS NULL", accountOf(p))
        triggerEvent("rp:quiz:passed", p)
        outputDebugString(("[rp_quiz] %s aprobó el cuestionario (%d/%d)"):format(getPlayerName(p), correct, #QUIZ.QUESTIONS), 3)
    else
        failedAt[p] = getTickCount()
    end
    triggerClientEvent(p, "rp:quiz:result", resourceRoot, { ok = ok, correct = correct, total = #QUIZ.QUESTIONS,
        pass = QUIZ.PASS, wrong = wrong, wait = ok and 0 or QUIZ.RETRY_SECONDS })
end)

----------------------------------------------------------------
-- Tutorial
----------------------------------------------------------------
addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local p = source
    characterId = tonumber(characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) or charOf(p) ~= characterId or not rows[1] then return end
        if tonumber(rows[1].tutorial_done) == 0 then
            setTimer(function()
                if isElement(p) and charOf(p) == characterId then triggerClientEvent(p, "rp:quiz:tutorial", resourceRoot) end
            end, 4000, 1)
        end
    end, db(), "SELECT tutorial_done FROM characters WHERE id = ?", characterId)
end)

addEventHandler("rp:quiz:tutorialDone", resourceRoot, function(finished)
    local p = client
    local characterId = charOf(p)
    if not characterId then return end
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not affected or affected == 0 or not isElement(p) then return end
        if finished == true then
            triggerEvent("rp:achievements:progress", p, "tutorial_done", 1)   -- logro «Primer día»
        end
    end, db(), "UPDATE characters SET tutorial_done = 1 WHERE id = ? AND tutorial_done = 0", characterId)
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("rp:onAccountLogin", root, function() loadAccount(source) end)
-- Cambio de personaje: el tutorial a medias se corta (vuelve a salir si ese personaje no lo terminó)
addEvent("rp:onCharacterLogout", false)
addEventHandler("rp:onCharacterLogout", root, function()
    triggerClientEvent(source, "rp:quiz:tutorialStop", resourceRoot)
end)
local function forget(p) passed[p], sessions[p], failedAt[p] = nil, nil, nil end
addEventHandler("rp:onAccountLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)

local function boot()
    for _, p in ipairs(getElementsByType("player")) do loadAccount(p) end
end
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)
