--[[
    rp_achievements / s_achievements.lua  (servidor)

    Logros por personaje. Los demás recursos informan hechos con un evento de servidor
    (no necesitan depender de este recurso: si está parado, el evento no tiene oyente):
        triggerEvent("rp:achievements:progress", jugador, "pizza_delivered", 1)
    Cada estadística (shared/s_achievements.lua) alimenta uno o varios logros, que suben de
    medalla (bronce, plata, oro, platino) al llegar a cada umbral. Cada medalla da puntos y
    los puntos desbloquean hitos con recompensa que se reclaman en el panel (s_rewards.lua).

    Guardado: las estadísticas cambiadas se escriben cada ACH.SAVE_INTERVAL, al cerrar sesión,
    al salir y al parar el recurso; una medalla nueva se escribe al momento.

    Comandos:
        /logros                     abre el panel (también desde la app Logros del teléfono)
    Admin (s_admin.lua; catálogo en rp_adminpanel/server/s_catalog.lua):
        /verlogros, /darlogro, /statlogro, /resetlogros
    Exports (servidor):
        progress(p, stat, n)            suma o sube una estadística (igual que el evento)
        setStat(p, stat, valor)         fija una estadística (admin/pruebas; puede bajarla)
        unlock(p, clave, tier)          da directamente la medalla `tier` de un logro
        getPlayerPoints(p)              puntos de logro del personaje o false
        hasAchievement(p, requisito)    "ach:<clave>[:<tier>]", "points:<n>" o "milestone:<n>"
        getPlayerAchievements(p)        { points, stats, tiers, claimed } o false
        getAchievementStats()           { achievements, stats, milestones } (para pruebas)
]]

Achievements = {}
local state = {}          -- [player] = { characterId, loaded, stats, dirty, tiers, claimed, pending }
local warned = {}         -- estadísticas desconocidas ya avisadas
local saveTimer           -- guardado periódico (y saldo del banco)

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:achievements:progress", false)       -- SOLO servidor: lo lanzan otros recursos

local function db() return exports.rp_database:getConnection() end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function log(msg, level) outputDebugString("[rp_achievements] " .. msg, level or 3) end
Achievements.db, Achievements.log = db, log

function Achievements.get(p) return state[p] end

----------------------------------------------------------------
-- Puntos e hitos
----------------------------------------------------------------
function Achievements.points(s)
    local total = 0
    for key, tier in pairs(s.tiers) do
        local a = ACH.BY_KEY[key]
        if a then total = total + ACH.pointsOf(a, tier) end
    end
    return total
end

-- Hitos alcanzados y sin reclamar
function Achievements.readyMilestones(s, points)
    points = points or Achievements.points(s)
    local list = {}
    for i, m in ipairs(ACH.MILESTONES) do
        if points >= m.points and not s.claimed[i] then list[#list + 1] = i end
    end
    return list
end

-- Lo que el panel necesita (el catálogo ya lo tiene el cliente)
function Achievements.snapshot(s)
    local progress = {}
    for _, a in ipairs(ACH.CATALOG) do
        progress[a.key] = { t = s.tiers[a.key] or 0, v = s.stats[a.stat] or 0 }
    end
    local claimed = {}
    for i in pairs(s.claimed) do claimed[#claimed + 1] = i end
    return { points = Achievements.points(s), progress = progress, claimed = claimed, max = ACH.maxPoints() }
end

----------------------------------------------------------------
-- Guardado
----------------------------------------------------------------
local function saveStat(s, stat)
    dbExec(db(), [[INSERT INTO character_achievement_stats (character_id, stat_key, value) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE value = VALUES(value)]], s.characterId, stat, s.stats[stat] or 0)
    s.dirty[stat] = nil
end

local function flush(s)
    if not s or not s.loaded then return end
    for stat in pairs(s.dirty) do saveStat(s, stat) end
end
Achievements.flush = flush

local function saveTier(s, key, tier)
    dbExec(db(), [[INSERT INTO character_achievements (character_id, ach_key, tier) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE tier = VALUES(tier), unlocked_at = CURRENT_TIMESTAMP]], s.characterId, key, tier)
end

----------------------------------------------------------------
-- Medallas
----------------------------------------------------------------
-- Pone el logro en `tier` si es mayor que el actual. Devuelve { from, to } o nil si no sube.
local function raise(p, s, a, tier, silent)
    local cur = s.tiers[a.key] or 0
    tier = math.min(tier, #a.tiers)
    if tier <= cur then return nil end
    local before = Achievements.points(s)
    s.tiers[a.key] = tier
    saveTier(s, a.key, tier)
    if s.dirty[a.stat] then saveStat(s, a.stat) end   -- que la BD no quede por detrás de la medalla
    local after = Achievements.points(s)
    log(("%s: %s -> tier %d (+%d puntos)"):format(getPlayerName(p), a.key, tier, after - before))
    if silent then return { from = cur, to = tier } end

    -- Hitos que se acaban de alcanzar con estos puntos
    local newMilestone
    for i, m in ipairs(ACH.MILESTONES) do
        if before < m.points and after >= m.points and not s.claimed[i] then newMilestone = i end
    end
    triggerClientEvent(p, "rp:achievements:unlocked", resourceRoot, a.key, tier, after - before, after, newMilestone or false)
    return { from = cur, to = tier }
end

local function evaluate(p, s, stat, silent)
    local list = ACH.BY_STAT[stat]
    if not list then return 0 end
    local count = 0
    for _, a in ipairs(list) do
        if raise(p, s, a, ACH.tierFor(a, s.stats[stat]), silent) then count = count + 1 end
    end
    return count
end

----------------------------------------------------------------
-- Progreso (export y evento)
----------------------------------------------------------------
local function apply(p, s, stat, amount, exact)
    local def = ACH.STATS[stat]
    local old = s.stats[stat] or 0
    local new
    if exact then new = amount
    elseif def.mode == "max" then new = math.max(old, amount)
    else new = old + amount end
    if new == old then return true end
    s.stats[stat] = new
    s.dirty[stat] = true
    evaluate(p, s, stat, false)
    return true
end

-- Normaliza y valida. Devuelve stat, cantidad o nil.
local function check(p, stat, amount, exact)
    if not isElement(p) or getElementType(p) ~= "player" then return nil end
    if type(stat) ~= "string" then return nil end
    local def = ACH.STATS[stat]
    if not def then
        if not warned[stat] then
            warned[stat] = true
            log(("estadística desconocida '%s' (añádela a ACH.STATS)"):format(stat), 2)
        end
        return nil
    end
    amount = math.floor(tonumber(amount) or 0)
    if exact then
        if amount < 0 then return nil end
        return stat, amount
    end
    if amount <= 0 then return nil end
    return stat, math.min(amount, def.maxPerCall or amount)
end

function progress(p, stat, amount)
    local key, n = check(p, stat, amount, false)
    if not key then return false end
    local s = state[p]
    if not s then return false end
    if not s.loaded then
        s.pending[#s.pending + 1] = { key, n }   -- llegó antes de terminar la carga
        return true
    end
    return apply(p, s, key, n, false)
end

function setStat(p, stat, value)
    local key, n = check(p, stat, value, true)
    if not key then return false end
    local s = state[p]
    if not s or not s.loaded then return false end
    return apply(p, s, key, n, true)
end

function unlock(p, achKey, tier)
    local s = state[p]
    local a = ACH.BY_KEY[achKey]
    if not s or not s.loaded or not a then return false end
    tier = math.floor(tonumber(tier) or #a.tiers)
    if tier < 1 or tier > #a.tiers then return false end
    return raise(p, s, a, tier, false) ~= nil
end

addEventHandler("rp:achievements:progress", root, function(stat, amount)
    if client then return end      -- nunca desde un cliente (además el evento no es remoto)
    progress(source, stat, amount)
end)

----------------------------------------------------------------
-- Lectura (exports)
----------------------------------------------------------------
function getPlayerPoints(p)
    local s = state[p]
    return s and s.loaded and Achievements.points(s) or false
end

function hasAchievement(p, req)
    local s = state[p]
    if not s or not s.loaded or type(req) ~= "string" then return false end
    local kind, a1, a2 = req:match("^(%a+):([%w_]+):?(%d*)$")
    if kind == "ach" then
        local tier = s.tiers[a1] or 0
        return tier >= math.max(1, tonumber(a2) or 1)
    elseif kind == "points" then
        return Achievements.points(s) >= (tonumber(a1) or math.huge)
    elseif kind == "milestone" then
        return s.claimed[tonumber(a1) or 0] == true
    end
    return false
end

function getPlayerAchievements(p)
    local s = state[p]
    if not s or not s.loaded then return false end
    local stats, tiers, claimed = {}, {}, {}
    for k, v in pairs(s.stats) do stats[k] = v end
    for k, v in pairs(s.tiers) do tiers[k] = v end
    for k in pairs(s.claimed) do claimed[#claimed + 1] = k end
    return { points = Achievements.points(s), stats = stats, tiers = tiers, claimed = claimed }
end

-- Resumen y errores del catálogo (lo usa rp_test)
function getAchievementStats()
    local stats, problems, seen = 0, {}, {}
    for _ in pairs(ACH.STATS) do stats = stats + 1 end
    for _, a in ipairs(ACH.CATALOG) do
        if seen[a.key] then problems[#problems + 1] = "clave repetida " .. a.key end
        seen[a.key] = true
        if #a.key > 48 then problems[#problems + 1] = a.key .. ": clave de más de 48 letras" end
        if not ACH.STATS[a.stat] then problems[#problems + 1] = a.key .. ": estadística inexistente " .. tostring(a.stat) end
        if not ACH.CATEGORY_BY_KEY[a.cat] then problems[#problems + 1] = a.key .. ": categoría inexistente " .. tostring(a.cat) end
        if #a.tiers < 1 or #a.tiers > 4 or #a.medals ~= #a.tiers then problems[#problems + 1] = a.key .. ": tiers/medals no cuadran" end
        for i, v in ipairs(a.tiers) do
            if i > 1 and v <= a.tiers[i - 1] then problems[#problems + 1] = a.key .. ": umbrales no crecientes" end
            if ACH.STATS[a.stat] and ACH.STATS[a.stat].mode == "max" and v > ACH.STATS[a.stat].maxPerCall then
                problems[#problems + 1] = a.key .. ": umbral inalcanzable (mayor que maxPerCall)"
            end
        end
        for _, m in ipairs(a.medals) do if not ACH.MEDALS[m] then problems[#problems + 1] = a.key .. ": medalla " .. tostring(m) end end
    end
    for i, m in ipairs(ACH.MILESTONES) do
        if i > 1 and m.points <= ACH.MILESTONES[i - 1].points then problems[#problems + 1] = "hito " .. i .. ": puntos no crecientes" end
        if m.points > ACH.maxPoints() then problems[#problems + 1] = "hito " .. i .. ": inalcanzable" end
    end
    return { achievements = #ACH.CATALOG, stats = stats, milestones = #ACH.MILESTONES, maxPoints = ACH.maxPoints(), problems = problems }
end

----------------------------------------------------------------
-- Datos que ya existen en otros recursos (al entrar): así los logros de nivel, mapa y
-- gimnasio se reconocen aunque se consiguieran antes de existir este recurso.
----------------------------------------------------------------
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function seedFromWorld(p, s)
    local seeds = {}
    if running("rp_levels") then seeds.char_level = exports.rp_levels:getPlayerLevel(p) end
    if running("rp_map") then seeds.map_explored = exports.rp_map:getPlayerExplorationPercent(p) end
    local body = exports.rp_characters:getBodyStats(p)
    if type(body) == "table" then seeds.gym_muscle, seeds.gym_stamina = body.muscle, body.stamina end
    if running("rp_driving") and exports.rp_driving:hasDriverLicense(p) then seeds.driving_license = 1 end
    for stat, v in pairs(seeds) do
        v = math.min(math.floor(tonumber(v) or 0), ACH.STATS[stat].maxPerCall)
        if v > (s.stats[stat] or 0) then
            s.stats[stat] = v
            s.dirty[stat] = true
        end
    end
end

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
local function finishLoad(p, s)
    s.loaded = true
    seedFromWorld(p, s)
    -- Medallas que corresponden a lo que ya tiene (umbrales cambiados, datos sembrados): sin toast
    local gained = 0
    for stat in pairs(ACH.STATS) do gained = gained + evaluate(p, s, stat, true) end
    for _, e in ipairs(s.pending) do apply(p, s, e[1], e[2], false) end
    s.pending = {}
    flush(s)
    Achievements.refreshBalances(p)
    if gained > 0 then
        exports.rp_notify:notify(p, ("Tienes %d medallas de logros nuevas. Míralas con /%s."):format(gained, ACH.COMMAND), "success", 8000)
    elseif #Achievements.readyMilestones(s) > 0 then
        exports.rp_notify:notify(p, ("Tienes recompensas de logros sin reclamar: /%s."):format(ACH.COMMAND), "info", 8000)
    end
end

local function loadPlayer(p, characterId)
    local s = { characterId = characterId, loaded = false, stats = {}, dirty = {}, tiers = {}, claimed = {}, pending = {} }
    state[p] = s
    local function stale() return not isElement(p) or state[p] ~= s end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if stale() then return end
        if not rows then return log("no se pudieron leer las estadísticas de " .. getPlayerName(p), 1) end
        for _, r in ipairs(rows) do s.stats[r.stat_key] = tonumber(r.value) or 0 end
        dbQuery(function(qh2)
            local rows2 = dbPoll(qh2, 0) or {}
            if stale() then return end
            for _, r in ipairs(rows2) do s.tiers[r.ach_key] = tonumber(r.tier) or 0 end
            dbQuery(function(qh3)
                local rows3 = dbPoll(qh3, 0) or {}
                if stale() then return end
                for _, r in ipairs(rows3) do s.claimed[tonumber(r.milestone)] = true end
                finishLoad(p, s)
            end, db(), "SELECT milestone FROM character_achievement_milestones WHERE character_id = ?", characterId)
        end, db(), "SELECT ach_key, tier FROM character_achievements WHERE character_id = ?", characterId)
    end, db(), "SELECT stat_key, value FROM character_achievement_stats WHERE character_id = ?", characterId)
end

local function unloadPlayer(p)
    local s = state[p]
    if not s then return end
    flush(s)
    state[p] = nil
end
Achievements.unload = unloadPlayer
Achievements.load = loadPlayer

addEventHandler("rp:onCharacterSpawn", root, function(characterId) loadPlayer(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() unloadPlayer(source) end)
addEventHandler("onPlayerQuit", root, function() unloadPlayer(source) end)

-- Saldo del banco (logro «Ahorrador», modo max): una sola consulta para todos los conectados.
-- Se lee de characters en vez de enganchar depósitos (ida y vuelta del cajero no cuenta).
function Achievements.refreshBalances(only)
    local ids, byId = {}, {}
    for p, s in pairs(state) do
        if s.loaded and (not only or only == p) then ids[#ids + 1] = s.characterId; byId[s.characterId] = p end
    end
    if #ids == 0 then return end
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            local p = byId[tonumber(r.id)]
            if p and isElement(p) then progress(p, "bank_balance", tonumber(r.bank_money) or 0) end
        end
    end, db(), "SELECT id, bank_money FROM characters WHERE FIND_IN_SET(id, ?)", table.concat(ids, ","))
end

local function boot()
    for _, p in ipairs(getElementsByType("player")) do
        local characterId = characterOf(p)
        if characterId then loadPlayer(p, characterId) end
    end
    if isTimer(saveTimer) then killTimer(saveTimer) end
    saveTimer = setTimer(function()
        for _, s in pairs(state) do flush(s) end
        Achievements.refreshBalances()
    end, ACH.SAVE_INTERVAL, 0)
    log(("%d logros, %d hitos, %d puntos posibles"):format(#ACH.CATALOG, #ACH.MILESTONES, ACH.maxPoints()))
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(saveTimer) then killTimer(saveTimer) end
    for _, s in pairs(state) do flush(s) end
end)
