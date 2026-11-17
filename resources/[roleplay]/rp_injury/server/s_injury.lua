--[[
    rp_injury / s_injury.lua
    Estado "abatido": en vez de morir, el personaje queda en el suelo desangrandose.

    Flujo:
      1. El cliente intercepta el dano que lo mataria (onClientPlayerDamage) y avisa
         con "rp:injury:down". Si aun asi muere (explosion, /kill, setElementHealth 0...),
         onPlayerWasted lo reaparece donde cayo y lo deja abatido igualmente.
      2. Abatido: animacion en el suelo, controles bloqueados (incluido el chat),
         comandos y chat cancelados en el servidor y las interfaces cerradas en el cliente.
      3. A los INJURY.DOWNED_TIME ms muere, y tras INJURY.RESPAWN_DELAY aparece en el
         hospital con la vida completa y se le cobra INJURY.HOSPITAL_FEE.
      4. El tiempo que le queda se guarda en characters.downed_ms. Si sale del servidor
         (o del personaje) estando abatido, al volver a entrar sigue abatido en el mismo
         sitio y el temporizador continua donde lo dejo: desconectarse no salta la espera.
         Si sale cuando ya murio desangrado, se le cobra el hospital y aparece alli.

    elementData "rp:downed" (solo lo escribe el servidor):
        true      -> abatido
        "dying"   -> murio desangrado, esperando el respawn en el hospital
        false     -> normal

    Eventos de servidor para otros recursos (source = jugador):
        rp:onPlayerDowned       -> acaba de quedar abatido
        rp:onPlayerDownedEnd    -> deja de estar abatido (reanimado, muerto o desconectado)
        rp:onDownedLogout       -> lo dispara rp_characters al cerrar un personaje abatido

    Exports (servidor): isPlayerDowned(player), downPlayer(player), revivePlayer(player)
    Admin (admin_level >= 1): /revivir [jugador], /abatir <jugador>
]]

addEvent("rp:injury:down", true)
addEvent("rp:injury:reanim", true)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:onPlayerDownedEnd", false)
addEvent("rp:onDownedLogout", false)
addEvent("rp:emergency:revive", false)   -- lo dispara rp_emergency al reanimar (paramedicos IA)

local downed = {}      -- [player] = { expires = tick, timer = timer }
local dying = {}       -- [player] = timer del respawn (o true mientras muere)
local lastAnim = {}    -- [player] = tick de la ultima reanimacion pedida
local lastWarn = {}    -- [player] = tick del ultimo aviso de "no puedes"

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
local function isAdmin(player) return (exports.rp_login:getPlayerAdminLevel(player) or 0) >= 1 end

local function warn(player, text)
    local now = getTickCount()
    if lastWarn[player] and now - lastWarn[player] < 2500 then return end
    lastWarn[player] = now
    notify(player, text, "error")
end

function isPlayerDowned(player)
    return downed[player] ~= nil
end

-- Guarda en la base de datos los ms que le quedan abatido (0 = no esta abatido)
local function persist(player, ms)
    local characterId = characterOf(player)
    if not characterId then return end
    dbExec(db(), "UPDATE characters SET downed_ms = ? WHERE id = ?", math.max(0, math.floor(ms or 0)), characterId)
end

local function remainingOf(player)
    local d = downed[player]
    return d and math.max(0, d.expires - getTickCount()) or 0
end

local function applyAnimation(player)
    setPedAnimation(player, INJURY.ANIM_BLOCK, INJURY.ANIM_NAME, -1, true, false, false, true)
end

----------------------------------------------------------------
-- Tarifa del hospital
----------------------------------------------------------------
-- Cobra primero del efectivo (al momento, para que el guardado ya lo refleje) y el
-- resto del banco con un descuento atomico, sin dejar saldo negativo.
-- done(paid, fromCash, fromBank) se llama al terminar (puede ser tras salir el jugador).
local function chargeHospital(player, done)
    local characterId = characterOf(player)
    if not characterId then return done and done(0, 0, 0) end
    local fee = INJURY.HOSPITAL_FEE

    local fromCash = math.max(0, math.min(getPlayerMoney(player), fee))
    if fromCash > 0 then takePlayerMoney(player, fromCash) end

    local rest = fee - fromCash
    if rest <= 0 then return done and done(fromCash, fromCash, 0) end

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local balance = rows and rows[1] and tonumber(rows[1].bank_money) or 0
        local amount = math.max(0, math.min(balance, rest))
        if amount <= 0 then return done and done(fromCash, fromCash, 0) end

        dbQuery(function(qh2)
            local _, affected = dbPoll(qh2, 0)
            local fromBank = (affected and affected > 0) and amount or 0
            if fromBank > 0 then
                dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'hospital', ?, ?)",
                    characterId, fromBank, "Hospital All Saints")
            end
            if done then done(fromCash + fromBank, fromCash, fromBank) end
        end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, characterId, amount)
    end, db(), "SELECT bank_money FROM characters WHERE id = ?", characterId)
end

----------------------------------------------------------------
-- Estado
----------------------------------------------------------------
-- Quita el estado abatido. keepLocked: deja los controles bloqueados (muerte final).
-- keepSaved: no borra el tiempo guardado (sale del servidor y lo retoma al volver)
local function clearDowned(player, keepLocked, keepSaved)
    local d = downed[player]
    if not d then return false end
    if isTimer(d.timer) then killTimer(d.timer) end
    if not keepSaved then persist(player, 0) end
    downed[player] = nil
    if isElement(player) then
        setElementData(player, "rp:downed", false)
        if not keepLocked then
            toggleAllControls(player, true, true, true)
            setPedAnimation(player)
        end
        triggerClientEvent(player, "rp:injury:state", resourceRoot, false)
        triggerEvent("rp:onPlayerDownedEnd", player)
    end
    return true
end

local function respawnAtHospital(player)
    dying[player] = nil
    if not isElement(player) or not characterOf(player) then return end
    setElementData(player, "rp:downed", false)
    toggleAllControls(player, true, true, true)
    exports.rp_characters:respawnAtHospital(player)
    triggerEvent("rp:onPlayerDownedEnd", player)   -- p. ej. rp_needs vuelve a aplicar el cansancio

    chargeHospital(player, function(paid, fromCash, fromBank)
        if not isElement(player) then return end
        exports.rp_characters:saveCharacter(player)
        if paid >= INJURY.HOSPITAL_FEE then
            local how = fromBank > 0 and (fromCash > 0 and " (efectivo y banco)" or " (banco)") or ""
            exports.rp_notify:popup(player, "Hospital All Saints",
                ("Te atendieron en el hospital. Tarifa cobrada: $%d%s."):format(paid, how), "info", 7000)
        else
            exports.rp_notify:popup(player, "Hospital All Saints",
                ("Te atendieron en el hospital. Solo pudiste pagar $%d de $%d."):format(paid, INJURY.HOSPITAL_FEE), "warning", 7000)
        end
    end)
    triggerClientEvent(player, "rp:injury:state", resourceRoot, false)
end

-- Se acabo el tiempo: muere de verdad
local function bleedOut(player)
    if not isElement(player) or not downed[player] then return end
    clearDowned(player, true)
    dying[player] = true
    setElementData(player, "rp:downed", "dying")
    triggerClientEvent(player, "rp:injury:state", resourceRoot, "dying")
    setPedAnimation(player)
    killPed(player)
    -- Si por algo no murio, el respawn se hace igual
    setTimer(function()
        if isElement(player) and dying[player] == true then
            dying[player] = setTimer(respawnAtHospital, INJURY.RESPAWN_DELAY, 1, player)
        end
    end, 500, 1)
end

-- Saca al jugador del vehiculo y lo deja a un lado (puerta del conductor)
local function ejectFromVehicle(player)
    local vehicle = getPedOccupiedVehicle(player)
    if not vehicle then return end
    removePedFromVehicle(player)
    local x, y, z = getElementPosition(vehicle)
    local _, _, rz = getElementRotation(vehicle)
    local a = math.rad(rz)
    setElementPosition(player, x - math.cos(a) * 2.2, y - math.sin(a) * 2.2, z + 0.2)
end

-- remaining: ms que le quedan (para conservar el tiempo si vuelve a "morir" abatido)
function downPlayer(player, remaining)
    if not isElement(player) or isPedDead(player) or not characterOf(player) or dying[player] then return false end
    if downed[player] then
        if isTimer(downed[player].timer) then killTimer(downed[player].timer) end
    end
    remaining = math.max(1000, math.floor(tonumber(remaining) or INJURY.DOWNED_TIME))

    ejectFromVehicle(player)
    setElementFrozen(player, false)
    setElementHealth(player, INJURY.DOWNED_HEALTH)
    toggleAllControls(player, false, true, true)
    applyAnimation(player)

    local first = not downed[player]
    downed[player] = {
        expires = getTickCount() + remaining,
        timer = setTimer(bleedOut, remaining, 1, player),
    }
    setElementData(player, "rp:downed", true)
    persist(player, remaining)
    triggerClientEvent(player, "rp:injury:state", resourceRoot, true, remaining)
    if first then
        triggerEvent("rp:onPlayerDowned", player)
        notify(player, "Estas abatido. Si nadie te atiende, te desangraras.", "error")
    end
    return true
end

function revivePlayer(player)
    if not clearDowned(player) then return false end
    setElementHealth(player, INJURY.REVIVE_HEALTH)
    notify(player, "Te han reanimado.", "success")
    return true
end

-- Paramedicos de rp_emergency: ellos ponen la vida y sueltan la animacion; aqui se
-- cancela el temporizador y el tiempo guardado
addEventHandler("rp:emergency:revive", root, function()
    if downed[source] then
        clearDowned(source)
        notify(source, "Los paramedicos te reanimaron.", "success")
    end
end)

----------------------------------------------------------------
-- Entrada al estado
----------------------------------------------------------------
-- El cliente cancelo el dano mortal y pide quedar abatido
addEventHandler("rp:injury:down", resourceRoot, function(attacker, weapon)
    local player = client
    if not player or downed[player] or dying[player] or isPedDead(player) then return end
    if not characterOf(player) then return end
    local by = (isElement(attacker) and getElementType(attacker) == "player" and attacker ~= player) and getPlayerName(attacker) or "-"
    outputServerLog(("[rp_injury] %s abatido (atacante: %s, arma: %s)"):format(getPlayerName(player), by, tostring(weapon)))
    downPlayer(player)
end)

-- Muertes que el cliente no pudo interceptar: reaparece en el sitio, abatido
addEventHandler("onPlayerWasted", root, function()
    local player = source
    if not characterOf(player) then return end

    if dying[player] then
        if isTimer(dying[player]) then return end
        dying[player] = setTimer(respawnAtHospital, INJURY.RESPAWN_DELAY, 1, player)
        return
    end

    local remaining = downed[player] and (downed[player].expires - getTickCount()) or nil
    if downed[player] and isTimer(downed[player].timer) then killTimer(downed[player].timer) end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local interior, dimension = getElementInterior(player), getElementDimension(player)
    setTimer(function()
        if not isElement(player) or not characterOf(player) or not isPedDead(player) or dying[player] then return end
        spawnPlayer(player, x, y, z + 0.5, rot, getElementModel(player), interior, dimension)
        exports.rp_characters:restoreCharacterLook(player)
        setCameraTarget(player, player)
        fadeCamera(player, true, 0.5)
        if remaining and remaining <= 0 then
            downed[player] = { expires = getTickCount() }
            bleedOut(player)
        else
            downPlayer(player, remaining)
        end
    end, 1500, 1)
end)

-- El cliente detecta que la animacion se corto (stream, colision...) y pide reponerla
addEventHandler("rp:injury:reanim", resourceRoot, function()
    local player = client
    if not player or not downed[player] then return end
    local now = getTickCount()
    if lastAnim[player] and now - lastAnim[player] < 1500 then return end
    lastAnim[player] = now
    ejectFromVehicle(player)
    applyAnimation(player)
end)

----------------------------------------------------------------
-- Bloqueos: chat y comandos
----------------------------------------------------------------
addEventHandler("onPlayerChat", root, function()
    if getElementData(source, "rp:downed") then
        cancelEvent()
        warn(source, "No puedes hablar mientras estas abatido.")
    end
end)

-- Tambien atrapa "say", "teamsay" y "me", porque el chat pasa por comandos
addEventHandler("onPlayerCommand", root, function(command)
    if not getElementData(source, "rp:downed") then return end
    if INJURY.ALLOWED_COMMANDS[command] or isAdmin(source) then return end
    cancelEvent()
    if command == "say" or command == "teamsay" or command == "me" then
        warn(source, "No puedes hablar mientras estas abatido.")
    else
        warn(source, "No puedes hacer nada mientras estas abatido.")
    end
end)

-- Solo el servidor decide si alguien esta abatido
addEventHandler("onElementDataChange", root, function(key, oldValue)
    if key == "rp:downed" and client then
        setElementData(source, key, oldValue)
    end
end)

----------------------------------------------------------------
-- Salida del personaje / del servidor
----------------------------------------------------------------
-- rp_characters lo dispara antes de guardar un personaje abatido (o muriendo)
addEventHandler("rp:onDownedLogout", root, function()
    local player = source
    if dying[player] then
        -- Ya murio desangrado: paga el hospital y aparecera alli
        chargeHospital(player)
        persist(player, 0)
        if isTimer(dying[player]) then killTimer(dying[player]) end
        dying[player] = nil
        outputServerLog(("[rp_injury] %s salio tras desangrarse: tarifa cobrada"):format(getPlayerName(player)))
    elseif downed[player] then
        -- Sigue abatido: se guarda lo que le queda y lo retoma al volver a entrar
        local left = math.max(1000, remainingOf(player))
        persist(player, left)
        clearDowned(player, false, true)
        outputServerLog(("[rp_injury] %s salio abatido (%d s pendientes)"):format(getPlayerName(player), math.ceil(left / 1000)))
    end
end)

-- Si el personaje tenia tiempo abatido pendiente, vuelve a quedar abatido donde estaba
local function resumeDowned(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local left = rows and rows[1] and tonumber(rows[1].downed_ms) or 0
        if left <= 0 or not isElement(player) or characterOf(player) ~= characterId then return end
        if downed[player] or dying[player] or isPedDead(player) then return end
        if downPlayer(player, left) then
            notify(player, "Sigues abatido: el tiempo continua donde lo dejaste.", "warning")
        end
    end, db(), "SELECT downed_ms FROM characters WHERE id = ?", characterId)
end

addEventHandler("rp:onCharacterSpawn", root, function()
    local player = source
    if downed[player] then clearDowned(player, false, true) end
    dying[player] = nil
    setElementData(player, "rp:downed", false)
    -- Pequena espera para que termine el spawn (camara, apariencia)
    setTimer(function() if isElement(player) then resumeDowned(player) end end, 1000, 1)
end)

-- Copia de seguridad del tiempo restante (por si el servidor se cae)
setTimer(function()
    for player in pairs(downed) do
        if isElement(player) then persist(player, math.max(1000, remainingOf(player))) end
    end
end, 10000, 0)

-- Al reiniciar el recurso, los que tenian tiempo pendiente vuelven a quedar abatidos
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if characterOf(player) then resumeDowned(player) end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    if downed[source] and isTimer(downed[source].timer) then killTimer(downed[source].timer) end
    if isTimer(dying[source]) then killTimer(dying[source]) end
    downed[source], dying[source], lastAnim[source], lastWarn[source] = nil, nil, nil, nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(downed) do
        if isElement(player) then
            persist(player, math.max(1000, remainingOf(player)))   -- se retoma al volver a iniciar
            setElementData(player, "rp:downed", false)
            toggleAllControls(player, true, true, true)
            setPedAnimation(player)
        end
    end
    for player in pairs(dying) do
        if isElement(player) then
            if isTimer(dying[player]) then killTimer(dying[player]) end
            respawnAtHospital(player)
        end
    end
end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
local function targetFrom(admin, query)
    if not query then return admin end
    local target = exports.rp_ids:findPlayer(query)
    if not target then notify(admin, "Jugador no encontrado (o el nombre es ambiguo).", "error") end
    return target
end

addCommandHandler("revivir", function(admin, _, query)
    if not isAdmin(admin) then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local target = targetFrom(admin, query)
    if not target then return end
    if not revivePlayer(target) then return notify(admin, "Ese jugador no esta abatido.", "error") end
    setElementHealth(target, 100)
    notify(admin, ("Reanimaste a %s."):format((getPlayerName(target):gsub("_", " "))), "success")
end)

addCommandHandler("abatir", function(admin, _, query)
    if not isAdmin(admin) then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local target = targetFrom(admin, query)
    if not target then return end
    if downed[target] or not downPlayer(target) then return notify(admin, "No se puede abatir a ese jugador ahora.", "error") end
    notify(admin, ("Abatiste a %s."):format((getPlayerName(target):gsub("_", " "))), "success")
end)
