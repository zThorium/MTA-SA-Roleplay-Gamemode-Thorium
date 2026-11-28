--[[
    rp_payday / s_payday.lua

    Cada PAYDAY.INTERVAL minutos de juego (acumulados por personaje y guardados
    en characters.payday_minutes, asi no se pierden al desconectar) se paga:
      - El sueldo del rol en su faccion (rp_factions:collectPaydaySalary). Las
        facciones del Estado no gastan fondos; las privadas pagan de sus fondos.
      - Si no tiene faccion, su rol no tiene sueldo o la faccion no tiene fondos:
        el sueldo base del Estado.
    El dinero va a la cuenta bancaria y queda en bank_transactions (tipo payday).
    El tiempo quieto (AFK) no cuenta.

    Comandos:
        /payday                       minutos que faltan
        /forzarpayday <id o nombre>   (admin) paga ahora, para pruebas
]]

local state = {}   -- [player] = { characterId, minutes, ticks, x, y, z, still }

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

local function factionsRunning()
    local res = getResourceFromName("rp_factions")
    return res and getResourceState(res) == "running"
end

local function save(player)
    local s = state[player]
    if s then dbExec(db(), "UPDATE characters SET payday_minutes = ? WHERE id = ?", s.minutes, s.characterId) end
end

local function track(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        local x, y, z = getElementPosition(player)
        state[player] = {
            characterId = characterId, minutes = math.min(tonumber(rows[1] and rows[1].payday_minutes) or 0, PAYDAY.INTERVAL),
            ticks = 0, x = x, y = y, z = z, still = 0,
        }
    end, db(), "SELECT payday_minutes FROM characters WHERE id = ?", characterId)
end

----------------------------------------------------------------
-- Pago
----------------------------------------------------------------
function payPlayer(player)
    local s = state[player]
    if not s or not isElement(player) then return false end

    local amount, label, detail, kind = false, nil, nil, "success"
    local reason, factionName
    if factionsRunning() then
        local a, b, c = exports.rp_factions:collectPaydaySalary(player)
        if a then
            amount, label, detail = a, b, ("Sueldo de %s en %s."):format(c, b)
        else
            reason, factionName = b, c
        end
    end

    if not amount then
        amount, label = PAYDAY.BASE_SALARY, "Estado"
        if reason == "nofunds" then
            detail, kind = ("%s no tiene fondos para tu sueldo; el Estado te paga el sueldo base."):format(factionName), "warning"
        elseif reason == "offduty" then
            detail, kind = ("No estabas de servicio en %s; recibes el sueldo base del Estado."):format(factionName), "warning"
        elseif reason == "nosalary" then
            detail = ("Tu rol en %s no tiene sueldo; recibes el sueldo base del Estado."):format(factionName)
        else
            detail = "Sueldo base del Estado."
        end
    end

    s.minutes, s.ticks = 0, 0
    dbExec(db(), "UPDATE characters SET bank_money = bank_money + ?, payday_minutes = 0 WHERE id = ?", amount, s.characterId)
    dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'payday', ?, ?)", s.characterId, amount, label)
    exports.rp_logs:log("payday", player, label, amount, detail)
    local lv = getResourceFromName("rp_levels")
    if lv and getResourceState(lv) == "running" then exports.rp_levels:giveXP(player, 400, "payday") end
    triggerEvent("rp:achievements:progress", player, "payday_count", 1)   -- logros (rp_achievements)
    exports.rp_notify:popup(player, "Payday", ("Se depositaron $%d en tu cuenta bancaria. %s"):format(amount, detail), kind, 9000)
    outputServerLog(("[rp_payday] %s cobro $%d (%s)"):format(getPlayerName(player), amount, label))
    return amount
end

-- Un minuto de juego
setTimer(function()
    for player, s in pairs(state) do
        if not isElement(player) or characterOf(player) ~= s.characterId then
            state[player] = nil
        elseif not isPedDead(player) then
            local x, y, z = getElementPosition(player)
            local moved = getDistanceBetweenPoints3D(x, y, z, s.x, s.y, s.z) >= PAYDAY.AFK_DISTANCE
            s.x, s.y, s.z = x, y, z
            s.still = moved and 0 or s.still + 1

            if PAYDAY.AFK_MINUTES <= 0 or s.still < PAYDAY.AFK_MINUTES then
                s.minutes = s.minutes + 1
                s.ticks = s.ticks + 1
                if s.minutes >= PAYDAY.INTERVAL then
                    payPlayer(player)
                elseif s.ticks >= PAYDAY.SAVE_EVERY then
                    s.ticks = 0
                    save(player)
                end
            elseif s.still == PAYDAY.AFK_MINUTES then
                notify(player, "Estas inactivo: el tiempo para el payday esta en pausa hasta que te muevas.", "warning", 7000)
            end
        end
    end
end, 60000, 0)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("rp:onCharacterSpawn", root, function() track(source) end)

addEventHandler("rp:onCharacterLogout", root, function()
    save(source)
    state[source] = nil
end)

addEventHandler("onPlayerQuit", root, function()
    save(source)
    state[source] = nil
end)

local function trackOnline()
    for _, player in ipairs(getElementsByType("player")) do track(player) end
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then trackOnline() else addEventHandler("rp:onDatabaseReady", root, trackOnline) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(state) do save(player) end
end)

----------------------------------------------------------------
-- Comandos y exports
----------------------------------------------------------------
function getMinutesToPayday(player)
    local s = state[player]
    return s and (PAYDAY.INTERVAL - s.minutes) or false
end

addCommandHandler("payday", function(player)
    local left = getMinutesToPayday(player)
    if not left then return end
    local text = ("Faltan %d minutos de juego para tu proximo payday."):format(left)
    if state[player].still >= PAYDAY.AFK_MINUTES and PAYDAY.AFK_MINUTES > 0 then
        text = text .. " Ahora esta en pausa porque estas inactivo."
    end
    notify(player, text, "info", 6000)
end)

addCommandHandler("forzarpayday", function(player, _, query)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 1 then
        return notify(player, "No tienes permiso para usar este comando.", "error")
    end
    local target = query and exports.rp_ids:findPlayer(query) or player
    if not target or not state[target] then return notify(player, "Uso: /forzarpayday <id o nombre> (con personaje en juego)", "warning") end
    local amount = payPlayer(target)
    notify(player, ("Payday forzado a %s: $%d."):format((getPlayerName(target):gsub("_", " ")), amount or 0), "success")
end)
