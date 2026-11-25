--[[
    rp_missions / server / s_core.lua

    Nucleo: instancias de mision, sala (lobby), grupo, roles, votacion de dificultad,
    maquina de estados  LOBBY -> LOADING -> IN_PROGRESS -> COMPLETED / FAILED -> CLEANUP
    y vidas compartidas / espectador. Las etapas viven en s_stages.lua, las recompensas en s_finish.lua.

    Comandos:  /misiones (menu, tambien J)   /salirmision (abandonar)
    Admin:     /mskip (salta la etapa)  /mmover <sweet|ryder|cesar> (mueve el punto de inicio del contacto)
    Exports:   getPlayerMission(player) -> instancia o false   getRespect(player[, contacto])   getRespectDiscount(player)
]]

M = M or {}
M.instances = {}
M.playerInst = {}
M.usedDims = {}
M.nextId = 1
M.respect = {}        -- [player] = { sweet = n, ... }
M.progress = {}       -- [player] = { [key] = { n = completaciones, best = ms } }
M.points = {}         -- [contacto] = {x,y,z}
M.invites = {}        -- [jugador] = { inst, expires, from }

local floor, max, min = math.floor, math.max, math.min

for _, ev in ipairs({ "open", "create", "join", "leave", "setrole", "vote", "invite", "start", "hold", "reply", "skip", "kick", "public" }) do
    addEvent("rp:missions:" .. ev, true)
end
addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)

function M.db() return exports.rp_database:getConnection() end
function M.notify(p, t, k, d) pcall(function() exports.rp_notify:notify(p, t, k, d) end) end
function M.characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
function M.nameOf(p) return exports.rp_characters:getPlayerCharacterName(p) or (getPlayerName(p):gsub("_", " ")) end
function M.levelOf(p)
    local ok, lv = pcall(function() return exports.rp_levels:getPlayerLevel(p) end)
    return ok and tonumber(lv) or 1
end
function M.money(n) return "$" .. tostring(floor(n)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "") end

function getPlayerMission(p) local i = M.playerInst[p]; return i and i.id or false end

----------------------------------------------------------------
-- Respeto / progreso (persistente por personaje)
----------------------------------------------------------------
function M.totalRespect(p)
    local t = 0
    for _, v in pairs(M.respect[p] or {}) do t = t + v end
    return min(MISSIONS.RESPECT_MAX, t)
end

function getRespect(p, contact)
    if contact then return (M.respect[p] or {})[contact] or 0 end
    return M.totalRespect(p)
end

function getRespectDiscount(p) return respectRank(M.totalRespect(p)).discount end

function M.applyRespectStat(p)
    if not isElement(p) then return end
    local total = M.totalRespect(p)
    setElementData(p, "rp:respect", total)
    pcall(setPedStat, p, MISSIONS.STAT_RESPECT, total)   -- estadistica nativa de GTA SA (0..1000)
end

local function loadPlayer(p)
    local cid = M.characterOf(p)
    if not cid then return end
    M.respect[p], M.progress[p] = {}, {}
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) or M.characterOf(p) ~= cid then return end
        for _, r in ipairs(rows) do M.respect[p][r.contact] = tonumber(r.respect) or 0 end
        M.applyRespectStat(p)
    end, M.db(), "SELECT contact, respect FROM character_respect WHERE character_id = ?", cid)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) or M.characterOf(p) ~= cid then return end
        for _, r in ipairs(rows) do M.progress[p][r.mission_key] = { n = tonumber(r.completions) or 0, best = tonumber(r.best_ms) } end
    end, M.db(), "SELECT mission_key, completions, best_ms FROM mission_progress WHERE character_id = ?", cid)
end

addEventHandler("rp:onCharacterSpawn", root, function() loadPlayer(source) end)
addEventHandler("onResourceStart", resourceRoot, function()
    local function go() for _, p in ipairs(getElementsByType("player")) do loadPlayer(p) end M.loadPoints() end
    if exports.rp_database:isReady() then go() else addEventHandler("rp:onDatabaseReady", root, go) end
end)

----------------------------------------------------------------
-- Puntos de inicio de contacto (marker + blip)
----------------------------------------------------------------
M.markers = {}

function M.spawnContactPoint(contact)
    local P = M.points[contact]
    local C = MISSIONS.CONTACTS[contact]
    if not P or not C then return end
    local old = M.markers[contact]
    if old then for _, e in ipairs(old) do if isElement(e) then destroyElement(e) end end end
    local c = C.color
    local mk = createMarker(P.x, P.y, P.z - 0.9, "cylinder", 1.6, c[1], c[2], c[3], 130)
    local bl = createBlip(P.x, P.y, P.z, 0, 2, c[1], c[2], c[3], 255, 0, 350)
    setElementData(mk, "rp:mcontact", contact)
    M.markers[contact] = { mk, bl }
    addEventHandler("onMarkerHit", mk, function(hit, dimOk)
        if getElementType(hit) ~= "player" or not dimOk or isPedInVehicle(hit) then return end
        if not M.characterOf(hit) or M.playerInst[hit] then return end
        M.sendMenu(hit, contact)
    end)
end

function M.loadPoints()
    for contact, p in pairs(MISSIONS.CONTACT_POINTS) do M.points[contact] = { x = p.x, y = p.y, z = p.z } end
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            if M.points[r.contact] then M.points[r.contact] = { x = r.x, y = r.y, z = r.z } end
        end
        for contact in pairs(M.points) do M.spawnContactPoint(contact) end
    end, M.db(), "SELECT contact, x, y, z FROM mission_points")
end

addCommandHandler("mmover", function(player, _, contact)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 2 then return M.notify(player, "No tienes permiso.", "error") end
    if not contact or not M.points[contact] then return M.notify(player, "Uso: /mmover <sweet|ryder|cesar>", "warning") end
    local x, y, z = getElementPosition(player)
    M.points[contact] = { x = x, y = y, z = z }
    dbExec(M.db(), "INSERT INTO mission_points (contact, x, y, z) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z)", contact, x, y, z)
    M.spawnContactPoint(contact)
    M.notify(player, ("Punto de %s movido aqui."):format(MISSIONS.CONTACTS[contact].name), "success")
end)

----------------------------------------------------------------
-- Menu y sala (RF-01)
----------------------------------------------------------------
-- Busqueda policial: no se puede entrar a una mision con estrellas (ni encarcelado)
function M.wantedBlock(p)
    local ok, level = pcall(function() return exports.rp_wanted:getWantedLevel(p) end)
    if ok and (tonumber(level) or 0) > 0 then return "Te busca la policia" end
    local ok2, jailed = pcall(function() return exports.rp_wanted:isPlayerJailed(p) end)
    if ok2 and jailed then return "Estas arrestado" end
end

function M.setWantedHold(p, on)
    pcall(function() exports.rp_wanted:setWantedSuspended(p, on) end)
end

local function playerCanDo(p, def)
    local w = M.wantedBlock(p)
    if w then return w end
    if M.levelOf(p) < (def.minLevel or 1) then return ("Nivel %d"):format(def.minLevel) end
    if M.totalRespect(p) < (def.minRespect or 0) then return ("Respeto %d"):format(def.minRespect) end
    -- Historia: `requires` = claves de misiones que hay que haber completado antes
    for _, key in ipairs(def.requires or {}) do
        local pr = (M.progress[p] or {})[key]
        if not pr or (pr.n or 0) < 1 then
            local title = key
            for _, d in ipairs(MISSION_DEFS) do if d.key == key then title = d.title break end end
            return ("Completa: %s"):format(title)
        end
    end
end

local function leaderCap(p) return respectRank(M.totalRespect(p)).partyCap end

local function missionInfo(p, i, def)
    local prog = (M.progress[p] or {})[def.key]
    local C = MISSIONS.CONTACTS[def.contact]
    return {
        id = i, key = def.key, title = def.title, contact = def.contact, contactName = C.name, color = C.color,
        desc = def.desc, minP = def.minP, maxP = def.maxP, recommended = def.recommended,
        minLevel = def.minLevel, minRespect = def.minRespect, cash = def.cash, respect = def.respect,
        xp = MISSIONS.REWARD.BASE_XP + (def.xpBonus or 0), locked = playerCanDo(p, def),
        done = prog and prog.n or 0, best = prog and prog.best or nil,
    }
end

function M.sendMenu(p, contact)
    local list = {}
    for i, def in ipairs(MISSION_DEFS) do
        if not contact or def.contact == contact then list[#list + 1] = missionInfo(p, i, def) end
    end
    local lobbies = {}
    for _, inst in pairs(M.instances) do
        if inst.state == "LOBBY" and inst.public and #inst.members < inst.maxP then
            lobbies[#lobbies + 1] = { id = inst.id, title = inst.def.title, leader = M.nameOf(inst.leader), count = #inst.members, max = inst.maxP, contact = inst.def.contact }
        end
    end
    local total = M.totalRespect(p)
    local rank = respectRank(total)
    triggerClientEvent(p, "rp:missions:menu", resourceRoot, {
        missions = list, lobbies = lobbies, contact = contact,
        level = M.levelOf(p), respect = total, rank = rank.name, partyCap = rank.partyCap, discount = rank.discount,
        byContact = M.respect[p] or {},
    })
end

local function voteCounts(inst)
    local c = { easy = 0, normal = 0, hard = 0 }
    for _, v in pairs(inst.votes) do c[v] = (c[v] or 0) + 1 end
    return c
end

function M.pickDifficulty(inst)
    local c = voteCounts(inst)
    local best, bestN = nil, -1
    for _, k in ipairs(MISSIONS.DIFFICULTY_ORDER) do
        if c[k] > bestN then best, bestN = k, c[k] end
    end
    -- empate: gana el voto del lider si es de los empatados; si no, el mas facil
    local lv = inst.votes[inst.leader]
    if lv and c[lv] == bestN then return lv end
    return best
end

function M.sendLobby(inst)
    local roleTaken = {}
    for _, r in pairs(inst.roles) do roleTaken[r] = (roleTaken[r] or 0) + 1 end
    local members, roleDefs = {}, {}
    for _, m in ipairs(inst.members) do
        members[#members + 1] = {
            name = M.nameOf(m), leader = m == inst.leader, role = inst.roles[m], vote = inst.votes[m],
            level = M.levelOf(m), respect = M.totalRespect(m),
        }
    end
    for _, r in ipairs(inst.def.roles) do
        roleDefs[#roleDefs + 1] = { id = r.id, name = r.name, desc = r.desc, max = r.max, taken = roleTaken[r.id] or 0 }
    end
    -- jugadores cercanos al lider (candidatos a invitar)
    local cand, list = {}, {}
    if isElement(inst.leader) then
        local lx, ly, lz = getElementPosition(inst.leader)
        for _, p in ipairs(getElementsByType("player")) do
            if p ~= inst.leader and M.characterOf(p) and not M.playerInst[p] and getElementDimension(p) == getElementDimension(inst.leader) then
                local x, y, z = getElementPosition(p)
                if getDistanceBetweenPoints3D(lx, ly, lz, x, y, z) <= MISSIONS.LOBBY_RANGE then
                    cand[#cand + 1] = p
                    list[#list + 1] = { i = #cand, name = M.nameOf(p), id = exports.rp_ids:getPlayerId(p) }
                end
            end
        end
    end
    inst.cand = cand
    local info = missionInfo(inst.leader, 0, inst.def)
    for _, m in ipairs(inst.members) do
        triggerClientEvent(m, "rp:missions:lobby", resourceRoot, {
            id = inst.id, title = inst.def.title, desc = inst.def.desc, contact = inst.def.contact, contactName = info.contactName, color = info.color,
            minP = inst.def.minP, maxP = inst.maxP, members = members, roles = roleDefs, you = M.nameOf(m),
            isLeader = m == inst.leader, myRole = inst.roles[m], myVote = inst.votes[m], counts = voteCounts(inst),
            nearby = m == inst.leader and list or {}, public = inst.public,
            cash = inst.def.cash, respect = inst.def.respect, xp = MISSIONS.REWARD.BASE_XP + (inst.def.xpBonus or 0),
        })
    end
end

local function allocDim()
    for i = 0, MISSIONS.DIM_COUNT - 1 do
        if not M.usedDims[i] then M.usedDims[i] = true; return MISSIONS.DIM_BASE + i end
    end
end

local function newInstance(def, leader)
    local id = M.nextId
    M.nextId = M.nextId + 1
    local inst = {
        id = id, def = def, leader = leader, state = "LOBBY", members = { leader }, roles = {}, votes = {},
        maxP = min(def.maxP, leaderCap(leader)), public = true, stage = 0, lives = 0, spec = {}, stats = {}, snap = {},
        entities = { vehicles = {}, peds = {}, markers = {}, blips = {}, objects = {} }, timers = {}, pendingRespawn = {},
        saved = {}, rt = nil, createdAt = getTickCount(),
    }
    M.instances[id] = inst
    M.playerInst[leader] = inst
    return inst
end

function M.inLobby(p) local i = M.playerInst[p]; return i and i.state == "LOBBY" and i end

addEventHandler("rp:missions:open", resourceRoot, function()
    local p = client
    if not M.characterOf(p) then return end
    local inst = M.playerInst[p]
    if inst and inst.state == "LOBBY" then return M.sendLobby(inst) end
    if inst then return M.notify(p, "Ya estas en una mision. Usa /salirmision para abandonar.", "warning") end
    M.sendMenu(p)
end)
addCommandHandler("misiones", function(p)
    if not M.characterOf(p) then return end
    local inst = M.playerInst[p]
    if inst and inst.state == "LOBBY" then return M.sendLobby(inst) end
    if inst then return M.notify(p, "Ya estas en una mision. Usa /salirmision para abandonar.", "warning") end
    M.sendMenu(p)
end)

addEventHandler("rp:missions:create", resourceRoot, function(index)
    local p = client
    index = tonumber(index)
    local def = index and MISSION_DEFS[index]
    if not def or not M.characterOf(p) or M.playerInst[p] then return end
    if isPedDead(p) or getElementData(p, "rp:downed") then return M.notify(p, "No puedes iniciar una mision ahora.", "error") end
    local why = playerCanDo(p, def)
    if why then return M.notify(p, "Aun no puedes hacer esta mision: " .. why .. ".", "error") end
    local inst = newInstance(def, p)
    inst.votes[p] = "normal"
    M.sendLobby(inst)
end)

addEventHandler("rp:missions:join", resourceRoot, function(id)
    local p = client
    local inst = M.instances[tonumber(id)]
    if not inst or inst.state ~= "LOBBY" or not inst.public or M.playerInst[p] or not M.characterOf(p) then return end
    M.joinLobby(p, inst)
end)

function M.joinLobby(p, inst)
    if #inst.members >= inst.maxP then return M.notify(p, "La sala esta llena.", "error") end
    local why = playerCanDo(p, inst.def)
    if why then return M.notify(p, "No cumples el requisito: " .. why .. ".", "error") end
    inst.members[#inst.members + 1] = p
    inst.votes[p] = "normal"
    M.playerInst[p] = inst
    M.invites[p] = nil
    for _, m in ipairs(inst.members) do
        if m ~= p then M.notify(m, M.nameOf(p) .. " se unio al grupo.", "info") end
    end
    M.sendLobby(inst)
end

addEventHandler("rp:missions:public", resourceRoot, function(flag)
    local inst = M.inLobby(client)
    if not inst or inst.leader ~= client then return end
    inst.public = flag == true
    M.sendLobby(inst)
end)

addEventHandler("rp:missions:setrole", resourceRoot, function(roleId)
    local p = client
    local inst = M.inLobby(p)
    if not inst then return end
    if roleId == false or roleId == "" or roleId == nil then inst.roles[p] = nil return M.sendLobby(inst) end
    local role
    for _, r in ipairs(inst.def.roles) do if r.id == roleId then role = r end end
    if not role then return end
    local taken = 0
    for m, r in pairs(inst.roles) do if r == roleId and m ~= p then taken = taken + 1 end end
    if taken >= role.max then return M.notify(p, "Ese rol ya esta ocupado.", "warning") end
    inst.roles[p] = roleId
    M.sendLobby(inst)
end)

addEventHandler("rp:missions:vote", resourceRoot, function(diff)
    local inst = M.inLobby(client)
    if not inst or not MISSIONS.DIFFICULTY[diff] then return end
    inst.votes[client] = diff
    M.sendLobby(inst)
end)

addEventHandler("rp:missions:invite", resourceRoot, function(query)
    local p = client
    local inst = M.inLobby(p)
    if not inst or inst.leader ~= p then return end
    if #inst.members >= inst.maxP then return M.notify(p, "El grupo esta lleno (tu rango de respeto permite " .. inst.maxP .. ").", "warning") end
    local target
    if type(query) == "number" then target = inst.cand and inst.cand[floor(query)]
    elseif type(query) == "string" then target = exports.rp_ids:findPlayer(query) end
    if not isElement(target) or target == p or not M.characterOf(target) then return M.notify(p, "Jugador no encontrado.", "error") end
    if M.playerInst[target] then return M.notify(p, "Ese jugador ya esta en una mision.", "error") end
    local why = playerCanDo(target, inst.def)
    if why then return M.notify(p, "Ese jugador no cumple el requisito: " .. why .. ".", "error") end
    M.invites[target] = { inst = inst.id, expires = getTickCount() + MISSIONS.INVITE_TIME, from = p }
    triggerClientEvent(target, "rp:missions:invite", resourceRoot, M.nameOf(p), inst.def.title, inst.def.contact, MISSIONS.INVITE_TIME)
    M.notify(p, "Invitacion enviada a " .. M.nameOf(target) .. ".", "success")
end)

addEventHandler("rp:missions:reply", resourceRoot, function(accept)
    local p = client
    local inv = M.invites[p]
    M.invites[p] = nil
    if not inv or inv.expires < getTickCount() then return end
    if accept ~= true then
        if isElement(inv.from) then M.notify(inv.from, M.nameOf(p) .. " rechazo la invitacion.", "info") end
        return
    end
    local inst = M.instances[inv.inst]
    if not inst or inst.state ~= "LOBBY" or M.playerInst[p] then return M.notify(p, "La invitacion ya no es valida.", "warning") end
    M.joinLobby(p, inst)
end)

addEventHandler("rp:missions:kick", resourceRoot, function(name)
    local inst = M.inLobby(client)
    if not inst or inst.leader ~= client or type(name) ~= "string" then return end
    for _, m in ipairs(inst.members) do
        if m ~= client and M.nameOf(m) == name then
            M.removeMember(inst, m, "Te expulsaron de la sala.")
            return
        end
    end
end)

addEventHandler("rp:missions:leave", resourceRoot, function()
    local inst = M.playerInst[client]
    if inst then M.removeMember(inst, client, "Abandonaste la mision.") end
end)
addCommandHandler("salirmision", function(p)
    local inst = M.playerInst[p]
    if not inst then return M.notify(p, "No estas en ninguna mision.", "error") end
    M.removeMember(inst, p, "Abandonaste la mision.")
end)

----------------------------------------------------------------
-- Instantanea del jugador (para devolverlo intacto a la dimension 0)
----------------------------------------------------------------
local function takeSnapshot(p)
    local x, y, z = getElementPosition(p)
    local _, _, rot = getElementRotation(p)
    local weapons = {}
    for slot = 0, 12 do
        local w = getPedWeapon(p, slot)
        if w and w > 0 then weapons[#weapons + 1] = { w, getPedTotalAmmo(p, slot) } end
    end
    return {
        x = x, y = y, z = z, rot = rot, interior = getElementInterior(p), dim = getElementDimension(p),
        health = max(20, getElementHealth(p)), armor = getPedArmor(p), weapons = weapons,
    }
end

function M.restorePlayer(inst, p)
    local s = inst.saved[p]
    if not s or not isElement(p) then return end
    M.setWantedHold(p, false)
    setElementData(p, "rp:noNeckFix", nil)
    inst.saved[p] = nil
    if isPedDead(p) then
        spawnPlayer(p, s.x, s.y, s.z, s.rot, getElementModel(p), s.interior, s.dim)
        pcall(function() exports.rp_characters:restoreCharacterLook(p) end)
    end
    pcall(function() exports.rp_injury:revivePlayer(p) end)
    removePedFromVehicle(p)
    setPedAnimation(p)
    setElementFrozen(p, false)
    setElementAlpha(p, 255)
    setElementCollisionsEnabled(p, true)
    toggleAllControls(p, true, true, true)
    setElementInterior(p, s.interior)
    setElementDimension(p, s.dim)
    setElementPosition(p, s.x, s.y, s.z)
    setElementRotation(p, 0, 0, s.rot)
    setElementHealth(p, s.health)
    setPedArmor(p, s.armor)
    takeAllWeapons(p)
    for _, w in ipairs(s.weapons) do giveWeapon(p, w[1], w[2], false) end
    setCameraTarget(p, p)
    fadeCamera(p, true, 1)
    triggerClientEvent(p, "rp:missions:left", resourceRoot)
end

----------------------------------------------------------------
-- Alta / baja de integrantes
----------------------------------------------------------------
local function indexOf(list, v) for i, x in ipairs(list) do if x == v then return i end end end

function M.sendAll(inst, event, ...)
    for _, m in ipairs(inst.members) do
        if isElement(m) then triggerClientEvent(m, event, resourceRoot, ...) end
    end
end

function M.alive(inst)
    local list = {}
    for _, m in ipairs(inst.members) do
        if isElement(m) and not inst.spec[m] and not isPedDead(m) then list[#list + 1] = m end
    end
    return list
end

function M.removeMember(inst, p, message)
    local i = indexOf(inst.members, p)
    if not i then return end
    table.remove(inst.members, i)
    M.playerInst[p] = nil
    inst.roles[p], inst.votes[p], inst.spec[p] = nil, nil, nil
    if inst.rt and inst.rt.holders then inst.rt.holders[p] = nil end
    if isElement(p) then
        if inst.saved[p] then M.restorePlayer(inst, p) else triggerClientEvent(p, "rp:missions:left", resourceRoot) end
        if message then M.notify(p, message, "info") end
        triggerClientEvent(p, "rp:missions:close", resourceRoot)
    end
    if #inst.members == 0 then return M.destroyInstance(inst) end
    if inst.leader == p then
        inst.leader = inst.members[1]
        M.notify(inst.leader, "Ahora eres el lider del grupo.", "info")
    end
    for _, m in ipairs(inst.members) do M.notify(m, (isElement(p) and M.nameOf(p) or "Un integrante") .. " salio del grupo.", "warning") end
    if inst.state == "LOBBY" then M.sendLobby(inst)
    elseif inst.state == "IN_PROGRESS" or inst.state == "LOADING" then
        M.checkWipe(inst)
        if inst.state == "IN_PROGRESS" then M.syncHud(inst) end
    end
end

function M.destroyInstance(inst)
    if inst.destroyed then return end
    inst.destroyed = true
    for _, t in pairs(inst.timers) do if isTimer(t) then killTimer(t) end end
    if M.cleanupEntities then M.cleanupEntities(inst) end
    for _, m in ipairs(inst.members) do
        M.playerInst[m] = nil
        if inst.saved[m] then M.restorePlayer(inst, m) end
    end
    if inst.dim then M.usedDims[inst.dim - MISSIONS.DIM_BASE] = nil end
    M.instances[inst.id] = nil
end

addEventHandler("onPlayerQuit", root, function()
    M.invites[source] = nil
    local inst = M.playerInst[source]
    if inst then M.removeMember(inst, source) end   -- restaura posicion antes de que rp_characters guarde
    M.respect[source], M.progress[source] = nil, nil
end, true, "high")

addEventHandler("rp:onCharacterLogout", root, function()
    local inst = M.playerInst[source]
    if inst then M.removeMember(inst, source) end
end, true, "high")

addEventHandler("onResourceStop", resourceRoot, function()
    for _, inst in pairs(M.instances) do M.destroyInstance(inst) end
end)

----------------------------------------------------------------
-- Inicio: LOADING -> IN_PROGRESS
----------------------------------------------------------------
addEventHandler("rp:missions:start", resourceRoot, function()
    local p = client
    local inst = M.inLobby(p)
    if not inst or inst.leader ~= p then return end
    if #inst.members < inst.def.minP then
        return M.notify(p, ("Esta mision necesita al menos %d jugadores."):format(inst.def.minP), "warning")
    end
    for _, m in ipairs(inst.members) do
        if isPedDead(m) or getElementData(m, "rp:downed") then
            return M.notify(p, "Todos deben estar en pie para empezar.", "warning")
        end
        local why = M.wantedBlock(m)
        if why then
            for _, q in ipairs(inst.members) do M.notify(q, ("No se puede iniciar: %s (%s)."):format(M.nameOf(m), why:lower()), "error") end
            return
        end
    end
    M.beginLoading(inst)
end)

local function assignRoles(inst)
    local count = {}
    for _, r in pairs(inst.roles) do count[r] = (count[r] or 0) + 1 end
    for _, m in ipairs(inst.members) do
        if not inst.roles[m] then
            for _, r in ipairs(inst.def.roles) do
                if (count[r.id] or 0) < r.max then inst.roles[m] = r.id; count[r.id] = (count[r.id] or 0) + 1; break end
            end
            if not inst.roles[m] then inst.roles[m] = inst.def.roles[#inst.def.roles].id end
        end
    end
end

function M.roleDef(inst, p)
    for _, r in ipairs(inst.def.roles) do if r.id == inst.roles[p] then return r end end
    return inst.def.roles[1]
end

function M.giveLoadout(inst, p)
    takeAllWeapons(p)
    for _, w in ipairs(M.roleDef(inst, p).weapons or {}) do giveWeapon(p, w[1], w[2], false) end
end

function M.beginLoading(inst)
    inst.state = "LOADING"
    inst.dim = allocDim()
    if not inst.dim then
        inst.state = "LOBBY"
        return M.notify(inst.leader, "No hay instancias libres. Intenta en un momento.", "error")
    end
    inst.difficulty = M.pickDifficulty(inst)
    inst.diff = MISSIONS.DIFFICULTY[inst.difficulty]
    inst.lives = inst.diff.lives
    assignRoles(inst)
    for _, m in ipairs(inst.members) do
        inst.stats[m] = { kills = 0, objs = 0, deaths = 0 }
        triggerClientEvent(m, "rp:missions:close", resourceRoot)
        fadeCamera(m, false, 1)
    end
    inst.timers.load = setTimer(function()
        if inst.destroyed then return end
        for idx, m in ipairs(inst.members) do
            if isElement(m) then
                inst.saved[m] = takeSnapshot(m)
                M.setWantedHold(m, true)   -- sin estrellas dentro de la mision
                pcall(function() exports.rp_injury:revivePlayer(m) end)
                removePedFromVehicle(m)
                setElementInterior(m, inst.def.interior or 0)
                setElementDimension(m, inst.dim)
                local s = inst.def.spawns[min(idx, #inst.def.spawns)]
                setElementPosition(m, s[1], s[2], s[3])
                setElementRotation(m, 0, 0, s[4])
                setElementHealth(m, 100)
                setPedArmor(m, 0)
                M.giveLoadout(inst, m)
                triggerClientEvent(m, "rp:missions:enter", resourceRoot, {
                    id = inst.id, key = inst.def.key, title = inst.def.title, contact = inst.def.contact, difficulty = inst.difficulty,
                    diffLabel = inst.diff.label, diffColor = inst.diff.color, hour = inst.def.hour, weather = inst.def.weather,
                    role = M.roleDef(inst, m).name, lives = inst.lives,
                })
            end
        end
        inst.startedAt = getTickCount()
        inst.state = "IN_PROGRESS"
        inst.snapPoint = inst.def.snap
        inst.timers.begin = setTimer(function()
            if inst.destroyed then return end
            for _, m in ipairs(inst.members) do if isElement(m) then fadeCamera(m, true, 1.2) end end
            M.startStage(inst, 1)
        end, 900, 1)
        inst.timers.tick = setTimer(function() M.tick(inst) end, MISSIONS.TICK, 0)
    end, 1300, 1)
end

----------------------------------------------------------------
-- Vidas compartidas y espectador (RF-03)
----------------------------------------------------------------
function M.checkWipe(inst)
    if inst.state ~= "IN_PROGRESS" then return end
    for _, m in ipairs(inst.members) do
        if isElement(m) and not inst.spec[m] then return end
    end
    M.finish(inst, false, "Todo el equipo cayo.")
end

local function setSpectator(inst, p, on)
    inst.spec[p] = on or nil
    setElementAlpha(p, on and 0 or 255)
    setElementCollisionsEnabled(p, not on)
    setElementFrozen(p, on and true or false)
    triggerClientEvent(p, "rp:missions:spectate", resourceRoot, on and true or false)
end

function M.reviveAndPlace(inst, p, asSpectator)
    if not isElement(p) or inst.destroyed or inst.state ~= "IN_PROGRESS" then return end
    inst.pendingRespawn[p] = nil
    local sp = inst.snapPoint or inst.def.snap
    local idx = indexOf(inst.members, p) or 1
    local ok = pcall(function() exports.rp_injury:revivePlayer(p) end)
    if isPedDead(p) or not ok then
        spawnPlayer(p, sp[1], sp[2], sp[3], sp[4], getElementModel(p), inst.def.interior or 0, inst.dim)
        pcall(function() exports.rp_characters:restoreCharacterLook(p) end)
    end
    removePedFromVehicle(p)
    setPedAnimation(p)
    toggleAllControls(p, true, true, true)
    setElementInterior(p, inst.def.interior or 0)
    setElementDimension(p, inst.dim)
    local a = math.rad(idx * 70)
    setElementPosition(p, sp[1] + math.cos(a) * 1.4, sp[2] + math.sin(a) * 1.4, sp[3] + 0.3)
    setElementHealth(p, 100)
    setPedArmor(p, 0)
    if asSpectator then
        setSpectator(inst, p, true)
        M.checkWipe(inst)
    else
        M.giveLoadout(inst, p)
        triggerClientEvent(p, "rp:missions:respawned", resourceRoot, MISSIONS.INVULN_TIME)
    end
    M.syncHud(inst)
end

function M.onMemberDown(inst, p)
    if inst.state ~= "IN_PROGRESS" or inst.spec[p] or inst.pendingRespawn[p] then return end
    inst.pendingRespawn[p] = true
    inst.stats[p].deaths = inst.stats[p].deaths + 1
    if inst.rt and inst.rt.holders and inst.rt.holders[p] then M.releaseHold(inst, p) end
    local lastLife = inst.lives <= 0
    if not lastLife then inst.lives = inst.lives - 1 end
    M.sendAll(inst, "rp:missions:died", M.nameOf(p), inst.lives, lastLife)
    M.syncHud(inst)
    setTimer(function() M.reviveAndPlace(inst, p, lastLife) end, MISSIONS.RESPAWN_DELAY, 1)
end

addEventHandler("rp:onPlayerDowned", root, function()
    local inst = M.playerInst[source]
    if inst then M.onMemberDown(inst, source) end
end)

-- Respaldo si rp_injury no esta activo: muerte normal
addEventHandler("onPlayerWasted", root, function()
    local inst = M.playerInst[source]
    if inst and inst.state == "IN_PROGRESS" and not getElementData(source, "rp:downed") then M.onMemberDown(inst, source) end
end)

-- Corrige la posicion guardada en la BD (el autoguardado de rp_characters ocurre con el jugador en la mision)
setTimer(function()
    for _, inst in pairs(M.instances) do
        if inst.state ~= "LOBBY" then
            for p, s in pairs(inst.saved) do
                local cid = isElement(p) and M.characterOf(p)
                if cid then
                    dbExec(M.db(), "UPDATE characters SET pos_x = ?, pos_y = ?, pos_z = ?, rotation = ?, interior = ?, dimension = ?, health = ?, armor = ? WHERE id = ?",
                        s.x, s.y, s.z, s.rot, s.interior, s.dim, s.health, s.armor, cid)
                end
            end
        end
    end
end, 30000, 0)

----------------------------------------------------------------
-- Espectador: pedir lista de companeros vivos (el cliente cicla la camara)
----------------------------------------------------------------
function M.spectateTargets(inst)
    local t = {}
    for _, m in ipairs(M.alive(inst)) do t[#t + 1] = m end
    return t
end

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
addEventHandler("rp:missions:skip", resourceRoot, function()
    local p = client
    local inst = M.playerInst[p]
    if not inst or inst.state ~= "IN_PROGRESS" or not inst.rt then return end
    if inst.rt.cutscene and inst.leader == p then M.completeStage(inst, true) end
end)

addCommandHandler("mskip", function(p)
    if (exports.rp_login:getPlayerAdminLevel(p) or 0) < 1 then return M.notify(p, "No tienes permiso.", "error") end
    local inst = M.playerInst[p]
    if not inst or inst.state ~= "IN_PROGRESS" then return M.notify(p, "No estas en una mision en curso.", "error") end
    M.completeStage(inst, true)
    M.notify(p, "Etapa saltada.", "success")
end)

-- Si rp_wanted se reinicia con misiones en curso, se vuelve a suspender la busqueda de sus integrantes
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rp_wanted" then return end
    for _, inst in pairs(M.instances) do
        for p in pairs(inst.saved) do if isElement(p) then M.setWantedHold(p, true) end end
    end
end)
