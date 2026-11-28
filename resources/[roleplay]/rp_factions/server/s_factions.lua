--[[
    rp_factions / s_factions.lua

    Facciones con roles definidos por el lider. Cada rol tiene nivel (autoridad),
    sueldo de payday y permisos. El panel (F3) solo recibe y muestra lo que el
    rol del jugador permite; cada accion se vuelve a comprobar aqui.

    Reglas de jerarquia (el lider se las salta todas):
      - Solo se actua sobre miembros con rol de nivel inferior al propio.
      - Solo se crean/editan roles de nivel inferior al propio.
      - Solo se conceden permisos que uno mismo tiene.

    Comandos de jugador:
        F3                     panel de la faccion
        /f <texto>             chat de la faccion
        /finvitar <id>         invitar (permiso "invite")
        /aceptarfaccion        aceptar una invitacion
        /salirfaccion          dejar la faccion (el lider no puede)

    Comandos de administracion (admin_level >= 1):
        /crearfaccion <tipo> <siglas> <nombre...>   tipos: ver FACTION_TYPES
        /borrarfaccion <id>
        /setlider <id o nombre> <idFaccion>
        /darfondos <idFaccion> <cantidad>
        /facciones                                  lista
]]

local factions = {}     -- [id] = { id, name, tag, type, color, state_funded, bank, motd, leader_id, ranks = { [rankId] = rank } }
local members = {}      -- [player] = { factionId, rankId, characterId }
local dashboards = {}   -- [player] = true mientras tiene el panel abierto
local invites = {}      -- [player] = { factionId, by, expires }
local cooldown = {}     -- [player] = tick

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:fac:open", true)
addEvent("rp:fac:close", true)
addEvent("rp:fac:action", true)
addEvent("rp:faction:onMembershipChange", false) -- público: lo escuchan otros recursos

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function displayName(name) return (tostring(name or ""):gsub("_", " ")) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function isInt(n, a, b)
    return type(n) == "number" and n == math.floor(n) and n >= a and n <= b
end

local function validText(s, minLen, maxLen)
    return type(s) == "string" and #s >= minLen and #s <= maxLen and not s:find("[%c<>]")
end

local function hexToRGB(hex)
    local r, g, b = tostring(hex or ""):match("#?(%x%x)(%x%x)(%x%x)")
    if not r then return 245, 165, 36 end
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

----------------------------------------------------------------
-- Consultas en memoria
----------------------------------------------------------------
local function getFaction(player)
    local m = members[player]
    local f = m and factions[m.factionId]
    if not f then return nil end
    return f, m
end

local function isLeader(player)
    local f, m = getFaction(player)
    return f ~= nil and tonumber(f.leader_id) == m.characterId
end

local function rankOf(player)
    local f, m = getFaction(player)
    return f and m.rankId and f.ranks[m.rankId] or nil
end

-- Nivel de autoridad: el lider esta por encima de cualquier rol
local function levelOf(player)
    if isLeader(player) then return math.huge end
    local rank = rankOf(player)
    return rank and rank.level or 0
end

local function maskOf(player)
    if isLeader(player) then return FACTION_ALL_PERMISSIONS end
    local rank = rankOf(player)
    return rank and rank.permissions or 0
end

local function can(player, key)
    return factionMaskHas(maskOf(player), key)
end

local function sortedRanks(f)
    local list = {}
    for _, r in pairs(f.ranks) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.id < b.id
    end)
    return list
end

local function lowestRank(f, exceptId)
    local list = sortedRanks(f)
    for i = #list, 1, -1 do
        if list[i].id ~= exceptId then return list[i] end
    end
end

local function playerOfCharacter(characterId)
    for player, m in pairs(members) do
        if m.characterId == characterId and isElement(player) then return player end
    end
    for _, player in ipairs(getElementsByType("player")) do
        if characterOf(player) == characterId then return player end
    end
end

local function onlineMembers(factionId)
    local list = {}
    for player, m in pairs(members) do
        if m.factionId == factionId and isElement(player) then list[#list + 1] = player end
    end
    return list
end

local function addLog(factionId, text)
    dbExec(db(), "INSERT INTO faction_log (faction_id, text) VALUES (?, ?)", factionId, text:sub(1, 255))
end

-- Avisa a los demás recursos cuando un jugador entra, sale o cambia de facción:
-- rp:faction:onMembershipChange (source = jugador; idNuevo|false, tipoNuevo|false, idAnterior|false)
local publishedId = {}  -- [player] = id de facción publicado (o false)
local function announceChange(player, f)
    local newId = f and f.id or false
    local old = publishedId[player] or false
    if newId == old then return end
    publishedId[player] = newId
    triggerEvent("rp:faction:onMembershipChange", player, newId, f and f.type or false, old)
end

-- Dato publico (nametags, scoreboard u otros recursos)
local function publishMembership(player)
    if not isElement(player) then return end
    local f, m = getFaction(player)
    announceChange(player, f)
    if not f then return setElementData(player, "rp:faction", false) end
    local rank = f.ranks[m.rankId]
    setElementData(player, "rp:faction", {
        id = f.id, name = f.name, tag = f.tag, color = f.color, type = f.type,
        rank = rank and rank.name or "", leader = isLeader(player),
    })
end

----------------------------------------------------------------
-- Carga
----------------------------------------------------------------
local function rankFromRow(r)
    return {
        id = tonumber(r.id), factionId = tonumber(r.faction_id), name = r.name,
        level = tonumber(r.level) or 1, salary = tonumber(r.salary) or 0, permissions = tonumber(r.permissions) or 0,
    }
end

local function factionFromRow(r)
    return {
        id = tonumber(r.id), name = r.name, tag = r.tag, type = r.type, color = r.color,
        state_funded = tonumber(r.state_funded) == 1, bank = tonumber(r.bank) or 0, motd = r.motd or "",
        leader_id = tonumber(r.leader_id), ranks = {},
    }
end

local function loadMembership(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        local row = rows[1]
        local f = row and factions[tonumber(row.faction_id)]
        if not f then
            members[player] = nil
            return publishMembership(player)
        end
        local rankId = tonumber(row.rank_id)
        if not rankId or not f.ranks[rankId] then
            -- Rol borrado o nulo: pasa al rol mas bajo
            local low = lowestRank(f)
            rankId = low and low.id
            if rankId then dbExec(db(), "UPDATE faction_members SET rank_id = ? WHERE character_id = ?", rankId, characterId) end
        end
        members[player] = { factionId = f.id, rankId = rankId, characterId = characterId }
        publishMembership(player)
        if f.motd ~= "" then
            notify(player, ("[%s] %s"):format(f.tag, f.motd), "info", 8000)
        end
    end, db(), "SELECT faction_id, rank_id FROM faction_members WHERE character_id = ? LIMIT 1", characterId)
end

local function loadFactions()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        factions = {}
        for _, r in ipairs(rows) do
            local f = factionFromRow(r)
            factions[f.id] = f
        end
        dbQuery(function(qh2)
            local rankRows = dbPoll(qh2, 0) or {}
            for _, r in ipairs(rankRows) do
                local rank = rankFromRow(r)
                local f = factions[rank.factionId]
                if f then f.ranks[rank.id] = rank end
            end
            outputDebugString(("[rp_factions] %d facciones cargadas"):format(#rows))
            for _, player in ipairs(getElementsByType("player")) do
                loadMembership(player)
            end
        end, db(), "SELECT * FROM faction_ranks")
    end, db(), "SELECT * FROM factions")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadFactions() else addEventHandler("rp:onDatabaseReady", root, loadFactions) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        setElementData(player, "rp:faction", false)
    end
end)

addEventHandler("rp:onCharacterSpawn", root, function()
    loadMembership(source)
end)

local function forget(player)
    members[player], dashboards[player], invites[player], cooldown[player] = nil, nil, nil, nil
end

addEventHandler("rp:onCharacterLogout", root, function()
    forget(source)
    if isElement(source) then
        announceChange(source, nil)
        setElementData(source, "rp:faction", false)
    end
end)
addEventHandler("onPlayerQuit", root, function() forget(source) publishedId[source] = nil end)

----------------------------------------------------------------
-- Panel F3
----------------------------------------------------------------
local function permissionKeys(mask)
    local list = {}
    for _, p in ipairs(FACTION_PERMISSIONS) do
        if bitAnd(mask, p.bit) ~= 0 then list[#list + 1] = p.key end
    end
    return list
end

local function sendDashboard(player)
    local f, m = getFaction(player)
    if not f then
        dashboards[player] = nil
        triggerClientEvent(player, "rp:fac:closeUI", resourceRoot)
        return notify(player, "No perteneces a ninguna faccion.", "warning")
    end

    local rank = f.ranks[m.rankId]
    local myLevel = levelOf(player)
    local myMask = maskOf(player)
    local data = {
        faction = {
            id = f.id, name = f.name, tag = f.tag, color = f.color,
            typeName = (FACTION_TYPES[f.type] or FACTION_TYPES.otra).name,
            stateFunded = f.state_funded, motd = f.motd,
            online = #onlineMembers(f.id),
            bank = can(player, "bank_view") and f.bank or false,
        },
        me = {
            characterId = m.characterId, name = displayName(getPlayerName(player)),
            rank = rank and rank.name or "Sin rol", level = rank and rank.level or 0,
            salary = rank and rank.salary or 0, leader = isLeader(player),
            perms = permissionKeys(myMask), cash = getPlayerMoney(player),
        },
        permissions = {},
        ranks = {},
        members = false,
        log = false,
    }

    -- Solo se envian los permisos que el jugador puede conceder
    for _, p in ipairs(FACTION_PERMISSIONS) do
        if bitAnd(myMask, p.bit) ~= 0 then
            data.permissions[#data.permissions + 1] = { key = p.key, label = p.label, description = p.description }
        end
    end

    local seeRanks = can(player, "manage_ranks") or can(player, "set_rank")
    if seeRanks then
        local full = can(player, "manage_ranks")
        for _, r in ipairs(sortedRanks(f)) do
            data.ranks[#data.ranks + 1] = {
                id = r.id, name = r.name, level = r.level,
                salary = full and r.salary or nil,
                perms = full and permissionKeys(r.permissions) or nil,
                editable = r.level < myLevel,
            }
        end
    end

    local function finish()
        if isElement(player) and dashboards[player] then
            triggerClientEvent(player, "rp:fac:data", resourceRoot, data)
        end
    end

    local function loadLog()
        if not can(player, "log_view") then return finish() end
        dbQuery(function(qh)
            data.log = dbPoll(qh, 0) or {}
            finish()
        end, db(), [[
            SELECT text, DATE_FORMAT(created_at, '%d/%m %H:%i') AS date
            FROM faction_log WHERE faction_id = ? ORDER BY id DESC LIMIT ?
        ]], f.id, FACTIONS.LOG_ROWS)
    end

    if not can(player, "members") then return loadLog() end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local online = {}
        for p, mm in pairs(members) do
            if mm.factionId == f.id and isElement(p) then online[mm.characterId] = true end
        end
        local list = {}
        for _, r in ipairs(rows) do
            local cid = tonumber(r.character_id)
            local rk = f.ranks[tonumber(r.rank_id) or -1]
            local leader = cid == tonumber(f.leader_id)
            list[#list + 1] = {
                characterId = cid, name = displayName(r.name), rankId = rk and rk.id or false,
                rank = rk and rk.name or "Sin rol", level = rk and rk.level or 0,
                leader = leader, online = online[cid] == true, lastPlayed = r.last_played or "",
                -- Puede actuar sobre el si su autoridad es inferior a la propia
                manageable = cid ~= m.characterId and not leader and (rk and rk.level or 0) < myLevel,
            }
        end
        table.sort(list, function(a, b)
            if a.leader ~= b.leader then return a.leader end
            if a.level ~= b.level then return a.level > b.level end
            return a.name < b.name
        end)
        data.members = list
        loadLog()
    end, db(), [[
        SELECT fm.character_id, fm.rank_id, c.name, DATE_FORMAT(c.last_played, '%d/%m/%Y') AS last_played
        FROM faction_members fm JOIN characters c ON c.id = fm.character_id
        WHERE fm.faction_id = ?
    ]], f.id)
end

-- Actualiza el panel de todos los miembros que lo tengan abierto
local function refreshFaction(factionId)
    for player in pairs(dashboards) do
        local m = members[player]
        if isElement(player) and m and m.factionId == factionId then sendDashboard(player) end
    end
end

addEventHandler("rp:fac:open", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    if not characterOf(player) then return end
    if not getFaction(player) then return notify(player, "No perteneces a ninguna faccion.", "warning") end
    dashboards[player] = true
    sendDashboard(player)
end)

addEventHandler("rp:fac:close", resourceRoot, function()
    dashboards[client] = nil
end)

----------------------------------------------------------------
-- Acciones
----------------------------------------------------------------
local actions = {}

-- Lee la membresia de un personaje (puede estar desconectado) y comprueba jerarquia
local function withTarget(player, characterId, callback)
    local f, m = getFaction(player)
    if not f or not isInt(characterId, 1, 4294967295) then return end
    if characterId == m.characterId then return notify(player, "No puedes hacer eso contigo mismo.", "error") end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        local row = rows[1]
        if not row or tonumber(row.faction_id) ~= f.id then return notify(player, "Esa persona no es de tu faccion.", "error") end
        if characterId == tonumber(f.leader_id) then return notify(player, "No puedes actuar sobre el lider.", "error") end
        local rank = f.ranks[tonumber(row.rank_id) or -1]
        if (rank and rank.level or 0) >= levelOf(player) then
            return notify(player, "Solo puedes actuar sobre miembros de rol inferior al tuyo.", "error")
        end
        callback(f, row)
    end, db(), [[
        SELECT fm.faction_id, fm.rank_id, c.name FROM faction_members fm
        JOIN characters c ON c.id = fm.character_id WHERE fm.character_id = ? LIMIT 1
    ]], characterId)
end

actions.motd = function(player, d)
    if not can(player, "edit_motd") then return end
    local text = type(d.text) == "string" and d.text:gsub("^%s+", ""):gsub("%s+$", "") or nil
    if not text or #text > FACTIONS.MOTD_MAX or text:find("[%c<>]") then
        return notify(player, ("El anuncio admite hasta %d caracteres."):format(FACTIONS.MOTD_MAX), "error")
    end
    local f = getFaction(player)
    f.motd = text
    dbExec(db(), "UPDATE factions SET motd = ? WHERE id = ?", text, f.id)
    addLog(f.id, ("%s cambio el anuncio."):format(displayName(getPlayerName(player))))
    notify(player, "Anuncio actualizado.", "success")
    refreshFaction(f.id)
end

local function invite(player, query)
    if not can(player, "invite") then return notify(player, "Tu rol no puede invitar.", "error") end
    local f = getFaction(player)
    local target = query and exports.rp_ids:findPlayer(query)
    if not target or not characterOf(target) then return notify(player, "Jugador no encontrado (usa su ID).", "error") end
    if target == player then return end
    if members[target] then return notify(player, "Esa persona ya pertenece a una faccion.", "error") end
    invites[target] = { factionId = f.id, by = player, expires = getTickCount() + FACTIONS.INVITE_TIMEOUT }
    notify(player, ("Invitaste a %s a %s."):format(displayName(getPlayerName(target)), f.name), "success")
    exports.rp_notify:popup(target, "Invitacion de faccion",
        ("%s te invita a unirte a %s. Escribe /aceptarfaccion en menos de %d segundos."):format(
            displayName(getPlayerName(player)), f.name, FACTIONS.INVITE_TIMEOUT / 1000), "info")
end

actions.invite = function(player, d)
    invite(player, d.target ~= nil and tostring(d.target) or nil)
end

actions.kick = function(player, d)
    if not can(player, "kick") then return end
    withTarget(player, tonumber(d.characterId), function(f, row)
        local cid = tonumber(d.characterId)
        dbExec(db(), "DELETE FROM faction_members WHERE character_id = ? AND faction_id = ?", cid, f.id)
        local target = playerOfCharacter(cid)
        if target then
            members[target], dashboards[target] = nil, nil
            publishMembership(target)
            triggerClientEvent(target, "rp:fac:closeUI", resourceRoot)
            notify(target, ("Has sido expulsado de %s."):format(f.name), "warning")
        end
        addLog(f.id, ("%s expulso a %s."):format(displayName(getPlayerName(player)), displayName(row.name)))
        notify(player, ("%s fue expulsado."):format(displayName(row.name)), "success")
        refreshFaction(f.id)
    end)
end

actions.setRank = function(player, d)
    if not can(player, "set_rank") then return end
    local f = getFaction(player)
    local rank = f.ranks[tonumber(d.rankId) or -1]
    if not rank then return notify(player, "Ese rol no existe.", "error") end
    if rank.level >= levelOf(player) then return notify(player, "Solo puedes asignar roles inferiores al tuyo.", "error") end
    withTarget(player, tonumber(d.characterId), function(_, row)
        local cid = tonumber(d.characterId)
        dbExec(db(), "UPDATE faction_members SET rank_id = ? WHERE character_id = ?", rank.id, cid)
        local target = playerOfCharacter(cid)
        if target and members[target] then
            members[target].rankId = rank.id
            publishMembership(target)
            notify(target, ("Tu rol en %s ahora es %s."):format(f.name, rank.name), "info")
        end
        addLog(f.id, ("%s asigno el rol %s a %s."):format(displayName(getPlayerName(player)), rank.name, displayName(row.name)))
        notify(player, ("%s ahora es %s."):format(displayName(row.name), rank.name), "success")
        refreshFaction(f.id)
    end)
end

actions.rankSave = function(player, d)
    if not can(player, "manage_ranks") then return end
    local f = getFaction(player)
    local myLevel, myMask = levelOf(player), maskOf(player)
    local name = type(d.name) == "string" and d.name:gsub("^%s+", ""):gsub("%s+$", "") or nil
    local level, salary = tonumber(d.level), tonumber(d.salary)

    if not validText(name, FACTIONS.NAME_MIN, FACTIONS.NAME_MAX) then
        return notify(player, ("El nombre del rol debe tener entre %d y %d caracteres."):format(FACTIONS.NAME_MIN, FACTIONS.NAME_MAX), "error")
    end
    if not isInt(level, 1, FACTIONS.MAX_LEVEL) then return notify(player, ("El nivel va de 1 a %d."):format(FACTIONS.MAX_LEVEL), "error") end
    if level >= myLevel then return notify(player, "El nivel debe ser inferior al de tu rol.", "error") end
    if not isInt(salary, 0, FACTIONS.MAX_SALARY) then return notify(player, ("El sueldo va de $0 a $%d."):format(FACTIONS.MAX_SALARY), "error") end

    local keys = type(d.perms) == "table" and d.perms or {}
    local clean = {}
    for _, k in ipairs(keys) do if type(k) == "string" then clean[#clean + 1] = k end end
    local mask = factionPermissionsToMask(clean)
    if bitAnd(mask, myMask) ~= mask then return notify(player, "No puedes conceder permisos que tu rol no tiene.", "error") end

    local id = tonumber(d.id)
    local existing = id and f.ranks[id]
    if id and not existing then return notify(player, "Ese rol no existe.", "error") end
    if existing and existing.level >= myLevel then return notify(player, "No puedes editar un rol igual o superior al tuyo.", "error") end
    if existing then
        -- Los permisos que el editor no tiene (los dio el lider) no los ve ni los puede quitar: se conservan
        local kept = 0
        for _, p in ipairs(FACTION_PERMISSIONS) do
            if bitAnd(myMask, p.bit) == 0 and bitAnd(existing.permissions, p.bit) ~= 0 then kept = kept + p.bit end
        end
        mask = mask + kept
    end
    for _, r in pairs(f.ranks) do
        if r.name:lower() == name:lower() and r.id ~= id then return notify(player, "Ya existe un rol con ese nombre.", "error") end
    end

    local who = displayName(getPlayerName(player))
    if existing then
        dbExec(db(), "UPDATE faction_ranks SET name = ?, level = ?, salary = ?, permissions = ? WHERE id = ?", name, level, salary, mask, id)
        existing.name, existing.level, existing.salary, existing.permissions = name, level, salary, mask
        addLog(f.id, ("%s edito el rol %s (nivel %d, sueldo $%d)."):format(who, name, level, salary))
        notify(player, ("Rol %s guardado."):format(name), "success")
        for _, p in ipairs(onlineMembers(f.id)) do publishMembership(p) end
        return refreshFaction(f.id)
    end

    local count = 0
    for _ in pairs(f.ranks) do count = count + 1 end
    if count >= FACTIONS.MAX_RANKS then return notify(player, ("Maximo %d roles por faccion."):format(FACTIONS.MAX_RANKS), "error") end

    dbQuery(function(qh)
        local ok, _, newId = dbPoll(qh, 0)
        if not ok then return isElement(player) and notify(player, "No se pudo crear el rol.", "error") end
        f.ranks[newId] = { id = newId, factionId = f.id, name = name, level = level, salary = salary, permissions = mask }
        addLog(f.id, ("%s creo el rol %s (nivel %d, sueldo $%d)."):format(who, name, level, salary))
        if isElement(player) then notify(player, ("Rol %s creado."):format(name), "success") end
        refreshFaction(f.id)
    end, db(), "INSERT INTO faction_ranks (faction_id, name, level, salary, permissions) VALUES (?, ?, ?, ?, ?)", f.id, name, level, salary, mask)
end

actions.rankDelete = function(player, d)
    if not can(player, "manage_ranks") then return end
    local f = getFaction(player)
    local rank = f.ranks[tonumber(d.id) or -1]
    if not rank then return end
    if rank.level >= levelOf(player) then return notify(player, "No puedes borrar un rol igual o superior al tuyo.", "error") end
    local fallback = lowestRank(f, rank.id)
    if not fallback then return notify(player, "La faccion necesita al menos un rol.", "error") end

    -- Los miembros con ese rol pasan al rol mas bajo que quede
    dbExec(db(), "UPDATE faction_members SET rank_id = ? WHERE rank_id = ?", fallback.id, rank.id)
    dbExec(db(), "DELETE FROM faction_ranks WHERE id = ?", rank.id)
    f.ranks[rank.id] = nil
    for _, p in ipairs(onlineMembers(f.id)) do
        if members[p].rankId == rank.id then
            members[p].rankId = fallback.id
            notify(p, ("Tu rol fue eliminado; ahora eres %s."):format(fallback.name), "info")
        end
        publishMembership(p)
    end
    addLog(f.id, ("%s elimino el rol %s."):format(displayName(getPlayerName(player)), rank.name))
    notify(player, ("Rol %s eliminado."):format(rank.name), "success")
    refreshFaction(f.id)
end

actions.deposit = function(player, d)
    if not can(player, "bank_deposit") then return end
    local f = getFaction(player)
    local amount = tonumber(d.amount)
    if not isInt(amount, 1, FACTIONS.MAX_TRANSACTION) then return notify(player, "Cantidad no valida.", "error") end
    if getPlayerMoney(player) < amount then return notify(player, "No llevas tanto efectivo.", "error") end
    takePlayerMoney(player, amount)
    f.bank = f.bank + amount
    dbExec(db(), "UPDATE factions SET bank = bank + ? WHERE id = ?", amount, f.id)
    exports.rp_characters:saveCharacter(player)
    addLog(f.id, ("%s deposito $%d."):format(displayName(getPlayerName(player)), amount))
    notify(player, ("Depositaste $%d en los fondos de %s."):format(amount, f.name), "success")
    refreshFaction(f.id)
end

actions.withdraw = function(player, d)
    if not can(player, "bank_withdraw") then return end
    local f = getFaction(player)
    local amount = tonumber(d.amount)
    if not isInt(amount, 1, FACTIONS.MAX_TRANSACTION) then return notify(player, "Cantidad no valida.", "error") end
    if f.bank < amount then return notify(player, "La faccion no tiene fondos suficientes.", "error") end
    f.bank = f.bank - amount
    dbExec(db(), "UPDATE factions SET bank = bank - ? WHERE id = ?", amount, f.id)
    givePlayerMoney(player, amount)
    exports.rp_characters:saveCharacter(player)
    addLog(f.id, ("%s retiro $%d."):format(displayName(getPlayerName(player)), amount))
    notify(player, ("Retiraste $%d de los fondos de %s."):format(amount, f.name), "success")
    refreshFaction(f.id)
end

local function leave(player)
    local f, m = getFaction(player)
    if not f then return notify(player, "No perteneces a ninguna faccion.", "warning") end
    if isLeader(player) then return notify(player, "El lider no puede salir; pide a un administrador que asigne otro lider.", "error") end
    dbExec(db(), "DELETE FROM faction_members WHERE character_id = ?", m.characterId)
    members[player], dashboards[player] = nil, nil
    publishMembership(player)
    triggerClientEvent(player, "rp:fac:closeUI", resourceRoot)
    addLog(f.id, ("%s dejo la faccion."):format(displayName(getPlayerName(player))))
    notify(player, ("Dejaste %s."):format(f.name), "info")
    refreshFaction(f.id)
end

actions.leave = function(player) leave(player) end

addEventHandler("rp:fac:action", resourceRoot, function(action, d)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 350 then return end
    cooldown[player] = now
    if type(action) ~= "string" or not actions[action] or not getFaction(player) then return end
    actions[action](player, type(d) == "table" and d or {})
end)

----------------------------------------------------------------
-- Comandos de jugador
----------------------------------------------------------------
addCommandHandler("f", function(player, _, ...)
    local f, m = getFaction(player)
    if not f then return notify(player, "No perteneces a ninguna faccion.", "warning") end
    local text = table.concat({ ... }, " ")
    if #text == 0 or #text > 180 then return notify(player, "Uso: /f <mensaje>", "warning") end
    local rank = f.ranks[m.rankId]
    local r, g, b = hexToRGB(f.color)
    local line = ("[%s] %s %s: %s"):format(f.tag, rank and rank.name or "", displayName(getPlayerName(player)), text)
    for _, p in ipairs(onlineMembers(f.id)) do outputChatBox(line, p, r, g, b, false) end
end)

addCommandHandler("finvitar", function(player, _, query)
    if not getFaction(player) then return notify(player, "No perteneces a ninguna faccion.", "warning") end
    if not query then return notify(player, "Uso: /finvitar <id o nombre>", "warning") end
    invite(player, query)
end)

addCommandHandler("aceptarfaccion", function(player)
    local inv = invites[player]
    invites[player] = nil
    local characterId = characterOf(player)
    if not inv or getTickCount() > inv.expires or not characterId then return notify(player, "No tienes invitaciones pendientes.", "warning") end
    if members[player] then return notify(player, "Ya perteneces a una faccion.", "error") end
    local f = factions[inv.factionId]
    local rank = f and lowestRank(f)
    if not rank then return notify(player, "Esa faccion ya no existe.", "error") end

    dbQuery(function(qh)
        local ok = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not ok then return notify(player, "No se pudo unir a la faccion.", "error") end
        members[player] = { factionId = f.id, rankId = rank.id, characterId = characterId }
        publishMembership(player)
        local who = isElement(inv.by) and displayName(getPlayerName(inv.by)) or "alguien"
        addLog(f.id, ("%s se unio (invitado por %s)."):format(displayName(getPlayerName(player)), who))
        exports.rp_notify:popup(player, f.name, ("Ahora eres %s. Pulsa F3 para abrir el panel."):format(rank.name), "success")
        for _, p in ipairs(onlineMembers(f.id)) do
            if p ~= player then notify(p, ("%s se unio a la faccion."):format(displayName(getPlayerName(player))), "info") end
        end
        refreshFaction(f.id)
    end, db(), "INSERT INTO faction_members (character_id, faction_id, rank_id) VALUES (?, ?, ?)", characterId, f.id, rank.id)
end)

addCommandHandler("salirfaccion", function(player) leave(player) end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
local function denied(player)
    notify(player, "No tienes permiso para usar este comando.", "error")
end

addCommandHandler("crearfaccion", function(player, _, kind, tag, ...)
    if not isAdmin(player) then return denied(player) end
    local name = table.concat({ ... }, " ")
    local t = kind and FACTION_TYPES[kind:lower()]
    if not t or not tag or not tag:match("^%w%w?%w?%w?%w?%w?%w?%w?$") or #tag < 2 or not validText(name, 3, 48) then
        local types = {}
        for k in pairs(FACTION_TYPES) do types[#types + 1] = k end
        table.sort(types)
        return notify(player, "Uso: /crearfaccion <tipo> <siglas 2-8> <nombre>. Tipos: " .. table.concat(types, ", "), "warning", 9000)
    end
    kind, tag = kind:lower(), tag:upper()

    dbQuery(function(qh)
        local ok, code, factionId = dbPoll(qh, 0)
        if not ok then
            return isElement(player) and notify(player, code == 1062 and "Ya existe una faccion con ese nombre." or "No se pudo crear la faccion.", "error")
        end
        local f = factionFromRow({ id = factionId, name = name, tag = tag, type = kind, color = t.color, state_funded = t.state and 1 or 0, bank = 0, motd = "" })
        factions[factionId] = f
        for _, r in ipairs(FACTIONS.DEFAULT_RANKS) do
            local mask = factionPermissionsToMask(r.permissions)
            dbQuery(function(qh2)
                local ok2, _, rankId = dbPoll(qh2, 0)
                if ok2 then f.ranks[rankId] = { id = rankId, factionId = factionId, name = r.name, level = r.level, salary = r.salary, permissions = mask } end
            end, db(), "INSERT INTO faction_ranks (faction_id, name, level, salary, permissions) VALUES (?, ?, ?, ?, ?)", factionId, r.name, r.level, r.salary, mask)
        end
        addLog(factionId, "Faccion creada por la administracion.")
        if isElement(player) then
            notify(player, ("Faccion #%d %s [%s] creada. Asigna un lider con /setlider <jugador> %d."):format(factionId, name, tag, factionId), "success", 9000)
        end
    end, db(), "INSERT INTO factions (name, tag, type, color, state_funded) VALUES (?, ?, ?, ?, ?)", name, tag, kind, t.color, t.state and 1 or 0)
end)

addCommandHandler("borrarfaccion", function(player, _, id)
    if not isAdmin(player) then return denied(player) end
    local f = factions[tonumber(id) or -1]
    if not f then return notify(player, "Uso: /borrarfaccion <id>", "warning") end
    dbExec(db(), "DELETE FROM factions WHERE id = ?", f.id)
    for _, p in ipairs(onlineMembers(f.id)) do
        members[p], dashboards[p] = nil, nil
        publishMembership(p)
        triggerClientEvent(p, "rp:fac:closeUI", resourceRoot)
        notify(p, ("La faccion %s fue disuelta."):format(f.name), "warning")
    end
    factions[f.id] = nil
    notify(player, ("Faccion #%d eliminada."):format(f.id), "success")
end)

addCommandHandler("setlider", function(player, _, query, id)
    if not isAdmin(player) then return denied(player) end
    local f = factions[tonumber(id) or -1]
    local target = query and exports.rp_ids:findPlayer(query)
    local characterId = target and characterOf(target)
    if not f or not characterId then return notify(player, "Uso: /setlider <id o nombre> <idFaccion>", "warning") end
    local top = sortedRanks(f)[1]
    if not top then return notify(player, "La faccion no tiene roles.", "error") end

    local previous = members[target] and members[target].factionId
    dbExec(db(), [[
        INSERT INTO faction_members (character_id, faction_id, rank_id) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE faction_id = VALUES(faction_id), rank_id = VALUES(rank_id)
    ]], characterId, f.id, top.id)
    dbExec(db(), "UPDATE factions SET leader_id = ? WHERE id = ?", characterId, f.id)
    f.leader_id = characterId
    members[target] = { factionId = f.id, rankId = top.id, characterId = characterId }
    publishMembership(target)
    for _, p in ipairs(onlineMembers(f.id)) do publishMembership(p) end
    addLog(f.id, ("La administracion nombro lider a %s."):format(displayName(getPlayerName(target))))
    exports.rp_notify:popup(target, f.name, "Ahora eres el lider. Pulsa F3 para gestionar roles, permisos y sueldos.", "success")
    notify(player, ("%s es ahora lider de %s."):format(displayName(getPlayerName(target)), f.name), "success")
    refreshFaction(f.id)
    if previous and previous ~= f.id then refreshFaction(previous) end
end)

addCommandHandler("darfondos", function(player, _, id, amount)
    if not isAdmin(player) then return denied(player) end
    local f = factions[tonumber(id) or -1]
    amount = tonumber(amount)
    if not f or not amount or amount ~= math.floor(amount) or amount == 0 then
        return notify(player, "Uso: /darfondos <idFaccion> <cantidad> (negativa para quitar)", "warning")
    end
    f.bank = math.max(0, f.bank + amount)
    dbExec(db(), "UPDATE factions SET bank = ? WHERE id = ?", f.bank, f.id)
    addLog(f.id, ("La administracion ajusto los fondos en $%d."):format(amount))
    notify(player, ("Fondos de %s: $%d."):format(f.name, f.bank), "success")
    refreshFaction(f.id)
end)

addCommandHandler("facciones", function(player)
    if not isAdmin(player) then return denied(player) end
    local list = {}
    for _, f in pairs(factions) do list[#list + 1] = f end
    table.sort(list, function(a, b) return a.id < b.id end)
    if #list == 0 then return outputChatBox("No hay facciones. Crea una con /crearfaccion.", player, 200, 200, 200) end
    for _, f in ipairs(list) do
        local r, g, b = hexToRGB(f.color)
        outputChatBox(("#%d [%s] %s - %s - fondos $%d - %d en linea"):format(
            f.id, f.tag, f.name, (FACTION_TYPES[f.type] or FACTION_TYPES.otra).name, f.bank, #onlineMembers(f.id)), player, r, g, b)
    end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
--[[
    API central de facciones. Es la ÚNICA forma en que otros recursos saben de facciones:
    nadie lee la tabla faction_members ni el elementData "rp:faction" para decidir algo en el servidor.

    "which" en estas funciones es un id de facción (número) o un TIPO (texto: "policia", "bomberos"...).
    Para sistemas de una profesión (policía, bomberos, médicos) se pregunta SIEMPRE por el tipo:
    así sirven igual con una o con varias facciones de ese tipo.

        isPlayerInFaction(p [, which])     ¿pertenece? (sin which: a cualquiera)
        isPlayerOnDuty(p [, which])        ¿pertenece y está de servicio? (lo responde el recurso
                                           FACTION_TYPES[tipo].duty; tipos sin servicio: false)
        getPlayerFactionId(p), getPlayerFactionType(p), isPlayerFactionLeader(p)
        getPlayerFactionInfo(p)            tabla { id, name, tag, type, color, stateFunded, rank, rankLevel, leader }
        getFactionInfo(id)                 tabla { id, name, tag, type, color, stateFunded, leaderId, online }
        getFactions([tipo])                lista de getFactionInfo
        getFactionPlayers(which [, soloDeServicio])   jugadores conectados
        getCharacterFaction(characterId)   id, tipo del personaje si está conectado; false si no
    Evento: rp:faction:onMembershipChange (source = jugador; idNuevo|false, tipoNuevo|false, idAnterior|false)
]]
local function matches(f, which)
    if which == nil or which == true then return true end
    local n = tonumber(which)
    if n then return f.id == n end
    return f.type == tostring(which):lower()
end

local function dutyResource(f)
    local t = FACTION_TYPES[f.type]
    local name = t and t.duty
    local res = name and getResourceFromName(name)
    if res and getResourceState(res) == "running" then return res end
    return nil, name ~= nil
end

-- Servicio según el recurso de ese tipo; nil si el tipo no tiene servicio
local function onDuty(player, f)
    local res, hasDuty = dutyResource(f)
    if not res then return hasDuty and false or nil end
    local ok, on = pcall(call, res, "isOnDuty", player)
    return ok and on == true
end

local function factionInfo(f)
    return {
        id = f.id, name = f.name, tag = f.tag, type = f.type, color = f.color,
        stateFunded = f.state_funded, leaderId = f.leader_id, online = #onlineMembers(f.id),
    }
end

function isPlayerInFaction(player, which)
    local f = getFaction(player)
    return f ~= nil and matches(f, which)
end

function isPlayerOnDuty(player, which)
    local f = getFaction(player)
    if not f or not matches(f, which) then return false end
    return onDuty(player, f) == true
end

function getPlayerFactionId(player)
    local f = getFaction(player)
    return f and f.id or false
end

function getPlayerFactionType(player)
    local f = getFaction(player)
    return f and f.type or false
end

function isPlayerFactionLeader(player)
    return isLeader(player)
end

function getPlayerFactionInfo(player)
    local f, m = getFaction(player)
    if not f then return false end
    local rank = f.ranks[m.rankId]
    local duty = onDuty(player, f)   -- nil = su tipo no tiene servicio
    return {
        id = f.id, name = f.name, tag = f.tag, type = f.type, color = f.color, stateFunded = f.state_funded,
        rank = rank and rank.name or "", rankLevel = getPlayerRankLevel(player), leader = isLeader(player),
        hasDuty = duty ~= nil, onDuty = duty == true,
    }
end

function getFactionInfo(factionId)
    local f = factions[tonumber(factionId)]
    return f and factionInfo(f) or false
end

function getFactions(kind)
    local list = {}
    for _, f in pairs(factions) do
        if matches(f, kind) then list[#list + 1] = factionInfo(f) end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function getFactionPlayers(which, dutyOnly)
    local list = {}
    for player, m in pairs(members) do
        local f = factions[m.factionId]
        if f and isElement(player) and matches(f, which) and (not dutyOnly or onDuty(player, f) == true) then
            list[#list + 1] = player
        end
    end
    return list
end

function getCharacterFaction(characterId)
    characterId = tonumber(characterId)
    if not characterId then return false end
    local player = playerOfCharacter(characterId)
    local f = player and getFaction(player)
    if not f then return false end
    return f.id, f.type
end

-- Devuelve id de faccion, nombre, rol y si es lider; false si no tiene faccion
function getPlayerFaction(player)
    local f, m = getFaction(player)
    if not f then return false end
    local rank = f.ranks[m.rankId]
    return f.id, f.name, rank and rank.name or "", isLeader(player), f.type
end

-- Nivel de autoridad del rol (el lider cuenta como el maximo)
function getPlayerRankLevel(player)
    local f, m = getFaction(player)
    if not f then return 0 end
    if isLeader(player) then return FACTIONS.MAX_LEVEL end
    local rank = f.ranks[m.rankId]
    return rank and rank.level or 0
end

-- rp_police ajusta los roles de la faccion 1 directo en la BD y pide recargar
function reloadFactions()
    loadFactions()
    return true
end

function hasFactionPermission(player, key)
    return getFaction(player) ~= nil and can(player, key)
end

function getFactionMembersOnline(factionId)
    return onlineMembers(tonumber(factionId))
end

--[[
    Usado por rp_payday. Cobra el sueldo del rol del jugador:
      - Faccion del Estado: lo paga el Estado.
      - Faccion privada: sale de los fondos de la faccion (si no alcanza, no se paga).
    Devuelve (cantidad, nombreFaccion, nombreRol) o (false, motivo, nombreFaccion)
    motivo: "none" sin faccion, "nosalary" rol sin sueldo, "nofunds" faccion sin fondos
]]
function collectPaydaySalary(player)
    local f, m = getFaction(player)
    if not f then return false, "none" end
    local rank = f.ranks[m.rankId]
    local salary = rank and rank.salary or 0
    -- Tipos con servicio (FACTION_TYPES[tipo].duty: policía, bomberos...): sueldo solo de servicio.
    -- Si el recurso del servicio no está en marcha se paga como siempre.
    if dutyResource(f) and not onDuty(player, f) then return false, "offduty", f.name end
    if salary <= 0 then return false, "nosalary", f.name end
    if not f.state_funded then
        if f.bank < salary then
            addLog(f.id, ("Sin fondos para pagar el sueldo de %s ($%d)."):format(displayName(getPlayerName(player)), salary))
            return false, "nofunds", f.name
        end
        f.bank = f.bank - salary
        dbExec(db(), "UPDATE factions SET bank = bank - ? WHERE id = ?", salary, f.id)
    end
    return salary, f.name, rank.name
end
