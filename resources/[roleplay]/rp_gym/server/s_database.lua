--[[
    rp_gym / s_database.lua
    Acceso a datos y perfil de cada personaje. La conexion es la unica de rp_database.
    Las stats de cuerpo (musculo, grasa, resistencia) las guarda rp_characters: aqui solo van
    los estilos de combate, el estilo actual, el progreso del dia y el ultimo entrenamiento.
]]

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)

profiles = {}   -- [player] = perfil del personaje activo (ver loadProfile)

function gymDb() return exports.rp_database:getConnection() end
function gymNotify(p, text, kind) exports.rp_notify:notify(p, text, kind) end
function gymCharacter(p) return exports.rp_characters:getPlayerCharacterId(p) end
function gymNow() return getRealTime().timestamp end
function gymIsAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function newProfile(cid)
    return { cid = cid, boxing = 0, kungfu = 0, kickboxing = 0, style = nil,
             day_start = 0, day_fat = 0, day_stamina = 0, day_muscle = 0, locked_until = 0, last_trained = 0 }
end

function saveProfile(player)
    local p = profiles[player]
    if not p or p.loading then return end
    dbExec(gymDb(), [[
        INSERT INTO character_gym (character_id, boxing, kungfu, kickboxing, style, day_start, day_fat, day_stamina,
                                   day_muscle, locked_until, last_trained)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE boxing = VALUES(boxing), kungfu = VALUES(kungfu), kickboxing = VALUES(kickboxing),
            style = VALUES(style), day_start = VALUES(day_start), day_fat = VALUES(day_fat),
            day_stamina = VALUES(day_stamina), day_muscle = VALUES(day_muscle),
            locked_until = VALUES(locked_until), last_trained = VALUES(last_trained)
    ]], p.cid, p.boxing, p.kungfu, p.kickboxing, p.style, p.day_start, p.day_fat, p.day_stamina,
        p.day_muscle, p.locked_until, p.last_trained)
end

-- Aplica el estilo de combate guardado (el estandar si no aprendio ninguno)
function applyFightingStyle(player)
    local p = profiles[player]
    if not isElement(player) then return end
    setPedFightingStyle(player, p and p.style or GYM_STANDARD_STYLE)
end

local function loadProfile(player, cid)
    local p = newProfile(cid)
    p.loading = true
    profiles[player] = p
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or profiles[player] ~= p then return end
        local row = rows[1]
        if row then
            for _, k in ipairs({ "boxing", "kungfu", "kickboxing", "day_start", "day_fat", "day_stamina",
                                 "day_muscle", "locked_until", "last_trained" }) do
                p[k] = tonumber(row[k]) or p[k]
            end
            p.style = tonumber(row.style)
        end
        p.loading = nil
        applyFightingStyle(player)
    end, gymDb(), "SELECT * FROM character_gym WHERE character_id = ?", cid)
end

addEventHandler("rp:onCharacterSpawn", root, function(cid) loadProfile(source, cid) end)
addEventHandler("onPlayerSpawn", root, function()
    if profiles[source] and not profiles[source].loading then applyFightingStyle(source) end
end)
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local cid = gymCharacter(player)
        if cid then loadProfile(player, cid) end
    end
end)

local function unload(player)
    saveProfile(player)
    profiles[player] = nil
end
addEventHandler("rp:onCharacterLogout", root, function() unload(source) end)
addEventHandler("onPlayerQuit", root, function() unload(source) end)
