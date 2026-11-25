--[[
    rp_shootingrange / s_skills.lua  (servidor)
    Habilidad nativa de arma (stats 69-79, 0-1000). Se guarda en weapon_skills por personaje y se
    restaura con setPedStat al entrar. Solo se guardan las stats entrenadas aqui; no se tocan las demas.
]]
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onDatabaseReady", false)

local function db() return exports.rp_database:getConnection() end

-- Nivel, progreso real hacia el siguiente umbral (0-1) y nombre del siguiente nivel
function skillInfo(value)
    value = math.max(0, math.min(RANGE.SKILL_MAX, tonumber(value) or 0))
    local idx = 1
    for i, lv in ipairs(RANGE.LEVELS) do if value >= lv.from then idx = i end end
    local cur, nxt = RANGE.LEVELS[idx], RANGE.LEVELS[idx + 1]
    local progress = 1
    if nxt then progress = (value - cur.from) / (nxt.from - cur.from) end
    return { value = value, key = cur.key, level = cur.name, progress = progress, nextLevel = nxt and nxt.name or false }
end

function skillSave(characterId, stat, value)
    dbExec(db(), "INSERT INTO weapon_skills (character_id, stat_id, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)",
        characterId, stat, math.floor(value))
end

-- Restaura al entrar: solo sube el valor nativo (nunca lo baja)
local function restore(player, characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or exports.rp_characters:getPlayerCharacterId(player) ~= characterId then return end
        for _, row in ipairs(rows) do
            local stat, value = tonumber(row.stat_id), tonumber(row.value)
            if stat and value and stat >= 69 and stat <= 79 and value > (getPedStat(player, stat) or 0) then
                setPedStat(player, stat, math.min(RANGE.SKILL_MAX, value))
            end
        end
    end, db(), "SELECT stat_id, value FROM weapon_skills WHERE character_id = ?", characterId)
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) restore(source, characterId) end)

addEventHandler("onResourceStart", resourceRoot, function()
    local function boot()
        for _, p in ipairs(getElementsByType("player")) do
            local id = exports.rp_characters:getPlayerCharacterId(p)
            if id then restore(p, id) end
        end
    end
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)
