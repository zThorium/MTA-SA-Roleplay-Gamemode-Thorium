--[[
    rp_levels / s_levels.lua

    Experiencia (RP) y nivel por personaje. El XP total se guarda en character_levels;
    el nivel se calcula con la curva de shared/s_config.lua.
    El cliente dibuja la barra animada (client/c_levels.lua).

    Exports:
        exports.rp_levels:giveXP(player, cantidad, motivo)   -> true/false
        exports.rp_levels:getPlayerLevel(player)             -> nivel
        exports.rp_levels:getPlayerXP(player)                -> xp total

    Comandos:
        /nivel                          tu nivel y XP
        /darxp <id o nombre> <cantidad> (admin) da XP (negativa no permitida)
]]

local state = {}   -- [player] = { characterId, xp }

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

local function sync(player, gained, leveledUp)
    local s = state[player]
    if not s then return end
    local level, cur, need = levelFromXP(s.xp)
    setElementData(player, "rp:level", level)
    triggerClientEvent(player, "rp:levels:update", resourceRoot, level, cur, need, gained or 0, leveledUp and true or false)
end

local function track(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        state[player] = { characterId = characterId, xp = tonumber(rows[1] and rows[1].xp) or 0 }
        sync(player, 0, false)
    end, db(), "SELECT xp FROM character_levels WHERE character_id = ?", characterId)
end

function giveXP(player, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > LEVELS.MAX_GIVE then return false end
    if not isElement(player) then return false end
    local s = state[player]
    if not s or characterOf(player) ~= s.characterId then return false end

    local before = levelFromXP(s.xp)
    s.xp = s.xp + amount
    local after = levelFromXP(s.xp)
    -- Suma atomica: no se pisa el valor si dos recursos dan XP a la vez
    dbExec(db(), "INSERT INTO character_levels (character_id, xp) VALUES (?, ?) ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp)", s.characterId, amount)
    sync(player, amount, after > before)
    if after > before then
        outputServerLog(("[rp_levels] %s subio al nivel %d (%s)"):format(getPlayerName(player), after, tostring(reason or "?")))
    end
    return true
end

function getPlayerLevel(player)
    local s = state[player]
    return s and (levelFromXP(s.xp)) or false
end

function getPlayerXP(player)
    local s = state[player]
    return s and s.xp or false
end

addEventHandler("rp:onCharacterSpawn", root, function() track(source) end)
addEventHandler("rp:onCharacterLogout", root, function() state[source] = nil end)
addEventHandler("onPlayerQuit", root, function() state[source] = nil end)

addEventHandler("onResourceStart", resourceRoot, function()
    local function trackOnline() for _, p in ipairs(getElementsByType("player")) do track(p) end end
    if exports.rp_database:isReady() then trackOnline() else addEventHandler("rp:onDatabaseReady", root, trackOnline) end
end)

addCommandHandler("nivel", function(player)
    local s = state[player]
    if not s then return end
    local level, cur, need = levelFromXP(s.xp)
    if need == 0 then return notify(player, ("Nivel %d (maximo). XP total: %d."):format(level, s.xp), "info", 6000) end
    notify(player, ("Nivel %d: %d / %d XP para el nivel %d."):format(level, cur, need, level + 1), "info", 6000)
end)

addCommandHandler("darxp", function(player, _, query, amount)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 1 then
        return notify(player, "No tienes permiso para usar este comando.", "error")
    end
    amount = math.floor(tonumber(amount) or 0)
    local target = query and exports.rp_ids:findPlayer(query)
    if not target or amount < 1 then return notify(player, "Uso: /darxp <id o nombre> <cantidad>", "warning") end
    if not giveXP(target, amount, "admin") then return notify(player, "Ese jugador no tiene personaje en juego o la cantidad es invalida.", "error") end
    notify(player, ("Diste %d XP a %s."):format(amount, (getPlayerName(target):gsub("_", " "))), "success")
end)
