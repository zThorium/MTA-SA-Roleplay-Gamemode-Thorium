--[[
    rp_driving / s_schools.lua

    Autoescuelas en el mundo (instructor + blip), menu del instructor (pruebas,
    medallas, licencia y tabla de puntajes) y pizarra de mejores puntajes.

    Comandos (admin):
        /crearautoescuela               crea una autoescuela con el instructor en tu posicion
        /borrarautoescuela <id>         elimina una autoescuela
        /arenaautoescuela <id>          fija la pista de pruebas de esa autoescuela en tu posicion
                                        y rumbo (las pruebas se extienden ~200 m hacia delante)
        /autoescuelas                   lista las autoescuelas
]]

schools = {}              -- [id] = { row, ped, blip }
local cooldown = {}       -- [player] = tick
local boardCache = { overall = {}, perTest = {}, at = 0 }
local BOARD_TTL = 30000

addEvent("rp:onDatabaseReady", false)
addEvent("rp:driving:requestSchools", true)
addEvent("rp:driving:open", true)

function db() return exports.rp_database:getConnection() end
function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
function displayName(name) return (tostring(name or "?"):gsub("_", " ")) end

----------------------------------------------------------------
-- Pista de cada autoescuela
----------------------------------------------------------------
function getSchoolArena(schoolId)
    local s = schools[schoolId]
    local row = s and s.row
    if row and row.arena_x and row.arena_y and row.arena_z then
        return { x = tonumber(row.arena_x), y = tonumber(row.arena_y), z = tonumber(row.arena_z), rot = tonumber(row.arena_rot) or 0 }
    end
    local d = DRIVING.DEFAULT_ARENA
    return { x = d.x, y = d.y, z = d.z, rot = d.rot }
end

-- Punto delante del instructor donde se coloca al jugador al volver de una prueba
function getSchoolReturnPoint(schoolId)
    local s = schools[schoolId]
    if not s then
        local d = DRIVING.DEFAULT_SCHOOL
        return d.x, d.y, d.z, d.rot, 0, 0
    end
    local r = s.row
    local h = math.rad(r.rotation)
    return r.x - math.sin(h) * 2.2, r.y + math.cos(h) * 2.2, r.z, (r.rotation + 180) % 360, r.interior, r.dimension
end

function getNearSchool(player)
    if not isElement(player) then return false end
    local px, py, pz = getElementPosition(player)
    for id, s in pairs(schools) do
        local r = s.row
        if getElementInterior(player) == r.interior and getElementDimension(player) == r.dimension
            and getDistanceBetweenPoints3D(px, py, pz, r.x, r.y, r.z) <= DRIVING.INTERACT_RADIUS + 1.5 then
            return id
        end
    end
    return false
end

----------------------------------------------------------------
-- Mundo
----------------------------------------------------------------
local function schoolsForClient()
    local list = {}
    for id, s in pairs(schools) do
        local r = s.row
        list[#list + 1] = { id = id, x = r.x, y = r.y, z = r.z, rot = r.rotation, interior = r.interior, dimension = r.dimension }
    end
    return list
end

function broadcastSchools(target)
    triggerClientEvent(target or root, "rp:driving:schools", resourceRoot, schoolsForClient(), boardCache.overall)
end

local function destroySchool(id)
    local s = schools[id]
    if not s then return end
    if isElement(s.ped) then destroyElement(s.ped) end
    if isElement(s.blip) then destroyElement(s.blip) end
    schools[id] = nil
end

local function spawnSchool(row)
    destroySchool(row.id)
    row.x, row.y, row.z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    row.rotation, row.interior, row.dimension = tonumber(row.rotation) or 0, tonumber(row.interior) or 0, tonumber(row.dimension) or 0
    local ped = createPed(DRIVING.PED_SKIN, row.x, row.y, row.z, row.rotation)
    setElementInterior(ped, row.interior)
    setElementDimension(ped, row.dimension)
    setElementFrozen(ped, true)
    setElementData(ped, "rp:drivingSchool", row.id)
    local blip = createBlipAttachedTo(ped, DRIVING.BLIP, 2, 255, 255, 255, 255, 0, 300)
    setElementInterior(blip, row.interior)
    setElementDimension(blip, row.dimension)
    schools[row.id] = { row = row, ped = ped, blip = blip }
end

local function loadSchools()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return outputDebugString("[rp_driving] No se pudieron cargar las autoescuelas", 1) end
        if #rows == 0 then
            local d = DRIVING.DEFAULT_SCHOOL
            dbQuery(function(qh2)
                local ok, _, insertId = dbPoll(qh2, 0)
                if not ok then return outputDebugString("[rp_driving] No se pudo crear la autoescuela inicial", 1) end
                spawnSchool({ id = insertId, x = d.x, y = d.y, z = d.z, rotation = d.rot, interior = 0, dimension = 0 })
                outputDebugString("[rp_driving] Autoescuela inicial creada (id " .. insertId .. ")")
                refreshBoard(true)
            end, db(), "INSERT INTO driving_schools (x, y, z, rotation) VALUES (?, ?, ?, ?)", d.x, d.y, d.z, d.rot)
            return
        end
        for _, row in ipairs(rows) do spawnSchool(row) end
        outputDebugString(("[rp_driving] %d autoescuela(s) cargada(s)"):format(#rows))
        refreshBoard(true)
    end, db(), "SELECT * FROM driving_schools")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadSchools() else addEventHandler("rp:onDatabaseReady", root, loadSchools) end
end)

addEventHandler("rp:driving:requestSchools", resourceRoot, function()
    broadcastSchools(client)
end)

----------------------------------------------------------------
-- Tabla de puntajes (cache compartida por el menu y la pizarra)
----------------------------------------------------------------
-- Ranking general: suma de los mejores puntajes de cada prueba; desempata el tiempo total
local OVERALL_SQL = [[
    SELECT c.name, SUM(s.best_score) AS total, SUM(s.best_time_ms) AS time_ms,
           COUNT(*) AS tests, MIN(s.medal) AS min_medal, SUM(s.medal >= 3) AS golds
    FROM driving_scores s JOIN characters c ON c.id = s.character_id
    WHERE s.medal > 0
    GROUP BY s.character_id, c.name
    ORDER BY total DESC, time_ms ASC
    LIMIT 10
]]

local PER_TEST_SQL = [[
    SELECT test_id, name, best_score, best_time_ms, medal FROM (
        SELECT s.test_id, c.name, s.best_score, s.best_time_ms, s.medal,
               ROW_NUMBER() OVER (PARTITION BY s.test_id ORDER BY s.best_score DESC, s.best_time_ms ASC) AS rn
        FROM driving_scores s JOIN characters c ON c.id = s.character_id
        WHERE s.medal > 0
    ) ranked WHERE rn <= 5 ORDER BY test_id, rn
]]

function refreshBoard(force, callback)
    if not force and getTickCount() - boardCache.at < BOARD_TTL then
        if callback then callback() end
        return
    end
    dbQuery(function(qh)
        local overall = dbPoll(qh, 0)
        dbQuery(function(qh2)
            local perRows = dbPoll(qh2, 0)
            if overall then
                local list = {}
                for i, r in ipairs(overall) do
                    list[i] = {
                        name = displayName(r.name), total = tonumber(r.total) or 0, time = (tonumber(r.time_ms) or 0) / 1000,
                        tests = tonumber(r.tests) or 0, medal = tonumber(r.min_medal) or 0, golds = tonumber(r.golds) or 0,
                    }
                end
                boardCache.overall = list
            end
            if perRows then
                local per = {}
                for _, r in ipairs(perRows) do
                    per[r.test_id] = per[r.test_id] or {}
                    table.insert(per[r.test_id], {
                        name = displayName(r.name), score = tonumber(r.best_score) or 0,
                        time = (tonumber(r.best_time_ms) or 0) / 1000, medal = tonumber(r.medal) or 0,
                    })
                end
                boardCache.perTest = per
            end
            boardCache.at = getTickCount()
            if force then broadcastSchools() end
            if callback then callback() end
        end, db(), PER_TEST_SQL)
    end, db(), OVERALL_SQL)
end

function getTestRecord(testId)
    local list = boardCache.perTest[testId]
    return list and list[1] or nil
end

----------------------------------------------------------------
-- Menu del instructor
----------------------------------------------------------------
-- Datos del personaje: mejores resultados por prueba
function loadCharacterScores(characterId, callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local scores = {}
        for _, r in ipairs(rows) do
            scores[r.test_id] = {
                score = tonumber(r.best_score) or 0, time = (tonumber(r.best_time_ms) or 0) / 1000,
                medal = tonumber(r.medal) or 0, attempts = tonumber(r.attempts) or 0,
            }
        end
        callback(scores)
    end, db(), "SELECT test_id, best_score, best_time_ms, medal, attempts FROM driving_scores WHERE character_id = ?", characterId)
end

-- Una prueba esta desbloqueada si se aprobo la anterior
function isTestUnlocked(scores, test)
    if test.index == 1 then return true end
    local prev = DRIVING_TESTS[test.index - 1]
    return scores[prev.id] ~= nil and scores[prev.id].medal > 0
end

function allTestsPassed(scores)
    for _, t in ipairs(DRIVING_TESTS) do
        if not (scores[t.id] and scores[t.id].medal > 0) then return false end
    end
    return true
end

function sendMenu(player, view)
    local characterId = characterOf(player)
    if not characterId then return end
    loadCharacterScores(characterId, function(scores)
        getLicenseRow(characterId, function(license)
            refreshBoard(false, function()
                if not isElement(player) or characterOf(player) ~= characterId then return end
                local tests, total, totalTime, minMedal = {}, 0, 0, 4
                for _, t in ipairs(DRIVING_TESTS) do
                    local best = scores[t.id]
                    if best and best.medal > 0 then
                        total, totalTime = total + best.score, totalTime + best.time
                    end
                    minMedal = math.min(minMedal, best and best.medal or 0)
                    tests[#tests + 1] = {
                        id = t.id, index = t.index, name = t.name, short = t.short, par = t.par, platinum = t.platinum,
                        unlocked = isTestUnlocked(scores, t), best = best, record = getTestRecord(t.id),
                    }
                end
                local lic = { status = "none", reprintPrice = DRIVING.REPRINT_PRICE }
                if license then
                    lic.status, lic.number, lic.issued = license.status, license.number, license.issued
                    lic.reason = license.revoked_reason
                    lic.hasItem = exports.rp_inventory:hasItem(player, "driver_license", 1)
                    lic.pending = pendingDelivery[characterId] == true
                end
                triggerClientEvent(player, "rp:driving:menu", resourceRoot, {
                    view = view, tests = tests, license = lic,
                    me = { total = total, time = totalTime, medal = minMedal, max = #DRIVING_TESTS * 100 },
                    overall = boardCache.overall, perTest = boardCache.perTest,
                    medals = DRIVING.MEDALS,
                })
            end)
        end)
    end)
end

addEventHandler("rp:driving:open", resourceRoot, function()
    local player = client
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 800 then return end
    cooldown[player] = now
    if not characterOf(player) or getElementData(player, "rp:downed") or isPedInVehicle(player) then return end
    if isPlayerInTest(player) then return end
    if not getNearSchool(player) then return end
    sendMenu(player)
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)

----------------------------------------------------------------
-- Comandos de admin
----------------------------------------------------------------
addCommandHandler("crearautoescuela", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local interior, dimension = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local ok, _, insertId = dbPoll(qh, 0)
        if not ok then return notify(player, "No se pudo crear la autoescuela.", "error") end
        spawnSchool({ id = insertId, x = x, y = y, z = z, rotation = rot, interior = interior, dimension = dimension })
        broadcastSchools()
        -- Aparta al admin para que no quede dentro del instructor
        if isElement(player) then
            local h = math.rad(rot)
            setElementPosition(player, x - math.sin(h) * 2, y + math.cos(h) * 2, z)
        end
        notify(player, ("Autoescuela %d creada. Usa /arenaautoescuela %d en un terreno plano para su pista."):format(insertId, insertId), "success")
    end, db(), "INSERT INTO driving_schools (x, y, z, rotation, interior, dimension) VALUES (?, ?, ?, ?, ?, ?)",
        x, y, z, rot, interior, dimension)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbyschools, /gotoschool, /delschool...)
function adminElements()
    local list = {}
    for id, e in pairs(schools) do
        local row = e.row
        if row then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = row.interior, dimension = row.dimension, label = "Autoescuela" }
        end
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not schools[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM driving_schools WHERE id = ?", id)
    destroySchool(id)
    broadcastSchools()
    return true
end

addCommandHandler("borrarautoescuela", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrarautoescuela <id> (ver /autoescuelas)", "warning") end
    notify(player, ("Autoescuela %d eliminada."):format(id), "success")
end)

addCommandHandler("arenaautoescuela", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not schools[id] then return notify(player, "Uso: /arenaautoescuela <id> (de pie o en un auto, mirando hacia donde iran las pruebas)", "warning") end
    if getElementInterior(player) ~= 0 then return notify(player, "La pista tiene que estar en el exterior.", "error") end
    local el = getPedOccupiedVehicle(player) or player
    local x, y, z = getElementPosition(el)
    local _, _, rot = getElementRotation(el)
    if el ~= player then z = z - 0.5 else z = z - 1 end   -- al nivel del suelo
    dbExec(db(), "UPDATE driving_schools SET arena_x = ?, arena_y = ?, arena_z = ?, arena_rot = ? WHERE id = ?", x, y, z, rot, id)
    local row = schools[id].row
    row.arena_x, row.arena_y, row.arena_z, row.arena_rot = x, y, z, rot
    notify(player, ("Pista de la autoescuela %d fijada aqui (rumbo %d). Las pruebas ocupan ~200 m hacia delante y 30 m a cada lado."):format(id, math.floor(rot)), "success")
end)

addCommandHandler("autoescuelas", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local any = false
    for id, s in pairs(schools) do
        any = true
        local r, a = s.row, getSchoolArena(id)
        outputChatBox(("#f5a524[%d]#ffffff instructor %.1f, %.1f, %.1f (int %d, dim %d) - pista %.1f, %.1f, %.1f rumbo %d%s"):format(
            id, r.x, r.y, r.z, r.interior, r.dimension, a.x, a.y, a.z, math.floor(a.rot), r.arena_x and "" or " (por defecto)"), player, 255, 255, 255, true)
    end
    if not any then notify(player, "No hay autoescuelas.", "info") end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for id in pairs(schools) do destroySchool(id) end
end)

----------------------------------------------------------------
-- Exports (ranking)
----------------------------------------------------------------
-- Ranking en cache: { overall = {...}, perTest = { [testId] = {...} } }
function getLeaderboard()
    return { overall = boardCache.overall, perTest = boardCache.perTest }
end

-- Fuerza recargar el ranking desde la BD (asincrono)
function refreshLeaderboard()
    refreshBoard(true)
    return true
end

function getSchoolCount()
    local n = 0
    for _ in pairs(schools) do n = n + 1 end
    return n
end
