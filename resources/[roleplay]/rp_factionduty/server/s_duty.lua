--[[
    rp_factionduty / s_duty.lua

    Servicio genérico de facción (#104). Para los tipos de FACTION_TYPES con duty = "rp_factionduty"
    (empresas, mecánicos, noticias, taxis, seguridad...):
      - Vestuarios: puntos fijos de una facción que colocan los admins (/makelocker <idFaccion>).
      - Equipos (faction_loadouts): el líder (o quien tenga "Gestionar roles") define nombre, rol mínimo,
        uniforme y objetos desde F3 › Uniformes y equipo.
      - En el vestuario (E) el miembro elige un equipo y entra de servicio: se pone el uniforme y recibe
        los objetos. Al salir de servicio, desconectarse o dejar la facción los devuelve.
      - Lo entregado se apunta en faction_duty_items en el momento: si el servidor cae o el jugador sale
        antes de devolverlo, se le retira al volver a entrar. Mientras está de servicio, rp_inventory no
        deja tirar ni dar ese equipo (elementData de servidor "rp:dutyItems").
      - rp_factions pregunta isOnDuty/hasDuty: con vestuario, el sueldo de rol solo se cobra de servicio.

    Exports (servidor): isOnDuty(p), hasDuty(factionId), getDutyLoadout(p),
                        adminElements(), adminDelete(id), adminMove(id, _, x, y, z)
    Admin: /makelocker <idFaccion> (alias /crearvestuario); /nearbylockers, /dellocker... vía rp_admin.
]]

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:faction:onMembershipChange", false)
addEvent("rp:markers:moved", false)
addEvent("rp:factionduty:use", true)          -- cliente: E junto a un vestuario (id)
addEvent("rp:factionduty:action", true)       -- cliente: acción del panel (accion, datos)
addEvent("rp:factionduty:editorOpen", true)   -- cliente: F3 › Uniformes y equipo
addEvent("rp:factionduty:requestLockers", true)

local lockers = {}     -- [id] = { id, factionId, x, y, z, interior, dimension, marker }
local loadouts = {}    -- [factionId] = { [id] = { id, name, minLevel, skin, items = { { id, amount } } } }
local duty = {}        -- [player] = { factionId, loadoutId, skin, characterId }
local given = {}       -- [player] = { [itemId] = cantidad entregada y no devuelta }
local cooldown = {}

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function fac() return exports.rp_factions end

local function isGenericType(kind)
    local types = fac():getFactionTypes() or {}
    return types[kind] ~= nil and types[kind].duty == "rp_factionduty"
end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < FDUTY.COOLDOWN then return false end
    cooldown[p] = now
    return true
end

local function blocked(p)
    if getElementData(p, "rp:downed") then return "No puedes hacerlo ahora." end
    if isPedDead(p) then return "No puedes hacerlo ahora." end
    if isPedInVehicle(p) then return "Bájate del vehículo." end
end

local function itemName(itemId)
    local def = exports.rp_inventory:getItemDefinition(itemId)
    return def and def.name or itemId
end

----------------------------------------------------------------
-- Equipo entregado (libro en BD + elementData de servidor para rp_inventory)
----------------------------------------------------------------
local function publishGiven(p)
    if not isElement(p) then return end
    local g = given[p]
    setElementData(p, "rp:dutyItems", (g and next(g)) and g or false, false)   -- sin sincronizar: solo lo lee el servidor
end

local function ledgerAdd(p, characterId, itemId, amount)
    given[p] = given[p] or {}
    given[p][itemId] = (given[p][itemId] or 0) + amount
    dbExec(db(), [[
        INSERT INTO faction_duty_items (character_id, item_id, amount) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]], characterId, itemId, amount)
end

--[[
    Retira lo entregado. Lo que el jugador ya no tiene (balas gastadas) se da por gastado.
    Si su inventario no está disponible (sale del juego y rp_inventory ya lo descargó) no se toca:
    queda apuntado en la BD y se retira al volver. Devuelve lo que quedó pendiente, o nil si nada.
]]
local function returnItems(p, characterId, list)
    if not exports.rp_inventory:isInventoryReady(p) then return next(list) and list or nil end
    local pending = {}
    for itemId, amount in pairs(list) do
        local have = exports.rp_inventory:getItemAmount(p, itemId) or 0
        local take = math.min(have, amount)
        if take == 0 or exports.rp_inventory:takeItem(p, itemId, take) then
            dbExec(db(), "DELETE FROM faction_duty_items WHERE character_id = ? AND item_id = ?", characterId, itemId)
        else
            pending[itemId] = amount
        end
    end
    return next(pending) and pending or nil
end

-- Al entrar al juego: recupera el equipo que quedó sin devolver (caída del servidor, salida a mitad)
local function reconcile(p, characterId, tries)
    tries = tries or 0
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 or not isElement(p) or characterOf(p) ~= characterId or duty[p] then return end
        if not exports.rp_inventory:isInventoryReady(p) then
            if tries < 10 then setTimer(reconcile, 1500, 1, p, characterId, tries + 1) end   -- aún se está cargando
            return
        end
        local list = {}
        for _, r in ipairs(rows) do list[r.item_id] = tonumber(r.amount) or 0 end
        given[p] = returnItems(p, characterId, list)
        publishGiven(p)
        if not given[p] then
            notify(p, "Devolviste el equipo de servicio que te llevaste la última vez.", "info", 7000)
        end
    end, db(), "SELECT item_id, amount FROM faction_duty_items WHERE character_id = ?", characterId)
end

----------------------------------------------------------------
-- Servicio
----------------------------------------------------------------
function isOnDuty(p)
    return isElement(p) and duty[p] ~= nil
end

function hasDuty(factionId)
    factionId = tonumber(factionId)
    for _, l in pairs(lockers) do
        if l.factionId == factionId then return true end
    end
    return false
end

function getDutyLoadout(p)
    local d = duty[p]
    if not d then return false end
    local l = loadouts[d.factionId] and loadouts[d.factionId][d.loadoutId]
    return l and l.name or false
end

local function applyUniform(p)
    local d = duty[p]
    if not d or not isElement(p) or isPedDead(p) then return end
    setElementModel(p, d.skin)
    setElementData(p, "rp:head", false)        -- la cabeza personalizada no va sobre el uniforme
end

local function setOffDuty(p, why, silent)
    local d = duty[p]
    if not d then return end
    duty[p] = nil
    local list = given[p] or {}
    given[p] = nil
    if isElement(p) then
        given[p] = returnItems(p, d.characterId, list)   -- lo pendiente sigue bloqueado hasta que se retire
        publishGiven(p)
        if not isPedDead(p) then exports.rp_characters:restoreCharacterLook(p) end
        setElementData(p, "rp:factionDuty", false)
        if not silent then
            notify(p, why or "Sales de servicio y devuelves el equipo.", "info")
        end
    end
end

-- Entra de servicio (o cambia de equipo) con un equipo de su facción
local function setOnDuty(p, factionId, loadout)
    local characterId = characterOf(p)
    if not characterId then return end
    -- Si cambia de equipo, primero devuelve el anterior; luego comprueba que cabe todo lo nuevo
    if duty[p] then setOffDuty(p, nil, true) end
    for _, it in ipairs(loadout.items) do
        local ok, why = exports.rp_inventory:canCarry(p, it.id, it.amount)
        if not ok then return notify(p, ("No puedes llevar el equipo: %s"):format(why or itemName(it.id)), "error") end
    end
    duty[p] = { factionId = factionId, loadoutId = loadout.id, skin = loadout.skin, characterId = characterId }
    local names = {}
    for _, it in ipairs(loadout.items) do
        if exports.rp_inventory:giveItem(p, it.id, it.amount) then
            ledgerAdd(p, characterId, it.id, it.amount)
            names[#names + 1] = ("%d x %s"):format(it.amount, itemName(it.id))
        end
    end
    publishGiven(p)
    applyUniform(p)
    setElementData(p, "rp:factionDuty", true)
    notify(p, ("Entras de servicio con el equipo %s%s. Vuelve al vestuario para salir."):format(
        loadout.name, #names > 0 and (": " .. table.concat(names, ", ")) or ""), "success", 7000)
end

----------------------------------------------------------------
-- Vestuarios (marcadores fijos movibles con el editor de rp_admin)
----------------------------------------------------------------
local function lockersForClient()
    local out = {}
    for id, l in pairs(lockers) do
        out[#out + 1] = { id = id, factionId = l.factionId, x = l.x, y = l.y, z = l.z, interior = l.interior, dimension = l.dimension }
    end
    return out
end

local function broadcastLockers()
    triggerClientEvent(root, "rp:factionduty:lockers", resourceRoot, lockersForClient())
end

local function lockerLabel(l)
    local info = fac():getFactionInfo(l.factionId)
    return "Vestuario" .. (info and (" · " .. info.tag) or "")
end

local function spawnLocker(l)
    if isElement(l.marker) then destroyElement(l.marker) end
    local c = FDUTY.COLOR
    l.marker = createMarker(l.x, l.y, l.z - 1, "cylinder", 1.2, c[1], c[2], c[3], 140)
    setElementInterior(l.marker, l.interior)
    setElementDimension(l.marker, l.dimension)
    local label = lockerLabel(l)
    pcall(function()
        exports.rp_markers:setMarkerStyle(l.marker, { icon = "clothes", label = label })
        exports.rp_markers:registerMarker(l.marker, "locker" .. l.id, { label = label, point = { l.x, l.y, l.z }, ownerSaves = true })
    end)
end

local function destroyLocker(id)
    local l = lockers[id]
    if not l then return end
    if isElement(l.marker) then destroyElement(l.marker) end
    lockers[id] = nil
    -- Sin vestuario la facción deja de tener servicio: quien estaba de servicio lo deja
    if not hasDuty(l.factionId) then
        for p, d in pairs(duty) do
            if d.factionId == l.factionId then setOffDuty(p, "Tu facción ya no tiene vestuario: sales de servicio.") end
        end
    end
end

local function nearLocker(p, id)
    local l = lockers[tonumber(id) or -1]
    if not l then return nil end
    if getElementInterior(p) ~= l.interior or getElementDimension(p) ~= l.dimension then return nil end
    local x, y, z = getElementPosition(p)
    if getDistanceBetweenPoints3D(x, y, z, l.x, l.y, l.z) > FDUTY.PANEL_RADIUS then return nil end
    return l
end

-- Un admin lo movió con el editor (ALT o M + clic derecho): se guarda y se rehace
addEventHandler("rp:markers:moved", root, function(owner, key, x, y, z)
    if owner ~= getResourceName(resource) or type(key) ~= "string" or not x then return end
    local id = tonumber(key:match("^locker(%d+)$"))
    local l = id and lockers[id]
    if not l then return end
    l.x, l.y, l.z = x, y, z
    dbExec(db(), "UPDATE faction_lockers SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
    spawnLocker(l)
    broadcastLockers()
end)

----------------------------------------------------------------
-- Equipos
----------------------------------------------------------------
local function loadoutFromRow(r)
    local items = {}
    for _, it in ipairs(fromJSON(r.items or "[]") or {}) do
        if type(it) == "table" and type(it.id) == "string" and tonumber(it.amount) then
            items[#items + 1] = { id = it.id, amount = math.floor(tonumber(it.amount)) }
        end
    end
    return { id = tonumber(r.id), name = r.name, minLevel = tonumber(r.min_level) or 1, skin = tonumber(r.skin) or 0, items = items }
end

local function sortedLoadouts(factionId)
    local list = {}
    for _, l in pairs(loadouts[factionId] or {}) do list[#list + 1] = l end
    table.sort(list, function(a, b)
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.id < b.id
    end)
    return list
end

local function describeItems(items)
    local out = {}
    for _, it in ipairs(items) do
        local def = exports.rp_inventory:getItemDefinition(it.id)
        out[#out + 1] = { id = it.id, amount = it.amount, name = def and def.name or it.id, icon = def and def.icon or "" }
    end
    return out
end

----------------------------------------------------------------
-- Panel del vestuario
----------------------------------------------------------------
local function lockerData(p, l)
    local info = fac():getPlayerFactionInfo(p)
    local level = fac():getPlayerRankLevel(p) or 0
    local d = duty[p]
    local list = {}
    for _, lo in ipairs(sortedLoadouts(l.factionId)) do
        list[#list + 1] = {
            id = lo.id, name = lo.name, minLevel = lo.minLevel, skin = lo.skin,
            items = describeItems(lo.items), locked = lo.minLevel > level,
        }
    end
    return {
        mode = "locker", lockerId = l.id,
        faction = { name = info.name, tag = info.tag, color = info.color },
        rank = info.rank, level = level,
        onDuty = d ~= nil, current = d and d.loadoutId or false,
        loadouts = list,
        canEdit = fac():hasFactionPermission(p, "manage_ranks") == true,
    }
end

local function openLocker(p, l)
    triggerClientEvent(p, "rp:factionduty:panel", resourceRoot, lockerData(p, l))
end

addEventHandler("rp:factionduty:use", resourceRoot, function(id)
    local p = client
    if not characterOf(p) or not takeCooldown(p) then return end
    local l = nearLocker(p, id)
    if not l then return end
    if fac():getPlayerFactionId(p) ~= l.factionId then return notify(p, "Este vestuario es solo para miembros de su facción.", "error") end
    local why = blocked(p)
    if why then return notify(p, why, "warning") end
    openLocker(p, l)
end)

----------------------------------------------------------------
-- Editor de equipos (F3 › Uniformes y equipo)
----------------------------------------------------------------
local function canEdit(p)
    local factionId = fac():getPlayerFactionId(p)
    if not factionId or not isGenericType(fac():getPlayerFactionType(p)) then return nil end
    if not fac():hasFactionPermission(p, "manage_ranks") then return nil end
    return factionId
end

local function editorData(p, factionId)
    local info = fac():getPlayerFactionInfo(p)
    local allowed = {}
    for id, max in pairs(fdutyAllowedItems(info.type)) do
        local def = exports.rp_inventory:getItemDefinition(id)
        if def then allowed[#allowed + 1] = { id = id, name = def.name, icon = def.icon or "", max = max } end
    end
    table.sort(allowed, function(a, b) return a.name < b.name end)
    local list = {}
    for _, lo in ipairs(sortedLoadouts(factionId)) do
        list[#list + 1] = { id = lo.id, name = lo.name, minLevel = lo.minLevel, skin = lo.skin, items = describeItems(lo.items) }
    end
    return {
        mode = "editor",
        faction = { name = info.name, tag = info.tag, color = info.color },
        maxLevel = fac():getPlayerRankLevel(p) or 1, loadouts = list, allowed = allowed,
        maxLoadouts = FDUTY.MAX_LOADOUTS, maxItems = FDUTY.MAX_ITEMS, hasLocker = hasDuty(factionId),
    }
end

local function openEditor(p, factionId)
    triggerClientEvent(p, "rp:factionduty:panel", resourceRoot, editorData(p, factionId))
end

addEventHandler("rp:factionduty:editorOpen", resourceRoot, function()
    local p = client
    if not characterOf(p) or not takeCooldown(p) then return end
    local factionId = canEdit(p)
    if not factionId then return notify(p, "Tu rol no puede gestionar los equipos de servicio.", "error") end
    openEditor(p, factionId)
end)

-- Valida y limpia un equipo que llega del panel
local function cleanLoadout(p, d)
    local name = type(d.name) == "string" and d.name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if #name < FDUTY.NAME_MIN or #name > FDUTY.NAME_MAX or name:find("[%c<>]") then
        return nil, ("El nombre debe tener entre %d y %d caracteres."):format(FDUTY.NAME_MIN, FDUTY.NAME_MAX)
    end
    local level = tonumber(d.minLevel)
    local myLevel = fac():getPlayerRankLevel(p) or 1
    if not level or level ~= math.floor(level) or level < 1 or level > myLevel then
        return nil, ("El rol mínimo va de 1 a %d (tu nivel)."):format(myLevel)
    end
    if not fdutyIsValidSkin(d.skin) then return nil, "Ese uniforme (skin) no existe." end
    local kind = fac():getPlayerFactionType(p)
    local items, seen = {}, {}
    for _, it in ipairs(type(d.items) == "table" and d.items or {}) do
        local id, amount = type(it) == "table" and it.id, type(it) == "table" and tonumber(it.amount)
        if type(id) ~= "string" or seen[id] then return nil, "Objeto repetido o no válido." end
        local max = fdutyItemMax(kind, id)
        if max <= 0 then return nil, "Tu facción no puede entregar ese objeto." end
        if not amount or amount ~= math.floor(amount) or amount < 1 or amount > max then
            return nil, ("%s: cantidad de 1 a %d."):format(itemName(id), max)
        end
        seen[id] = true
        items[#items + 1] = { id = id, amount = amount }
    end
    if #items > FDUTY.MAX_ITEMS then return nil, ("Máximo %d objetos por equipo."):format(FDUTY.MAX_ITEMS) end
    return { name = name, minLevel = level, skin = tonumber(d.skin), items = items }
end

local editorActions = {}

editorActions.save = function(p, factionId, d)
    local lo, why = cleanLoadout(p, d)
    if not lo then return notify(p, why, "error") end
    local id = tonumber(d.id)
    local list = loadouts[factionId] or {}
    loadouts[factionId] = list
    local json = toJSON(lo.items, true)
    if id then
        local existing = list[id]
        if not existing then return notify(p, "Ese equipo ya no existe.", "error") end
        dbExec(db(), "UPDATE faction_loadouts SET name = ?, min_level = ?, skin = ?, items = ? WHERE id = ? AND faction_id = ?",
            lo.name, lo.minLevel, lo.skin, json, id, factionId)
        existing.name, existing.minLevel, existing.skin, existing.items = lo.name, lo.minLevel, lo.skin, lo.items
        notify(p, ("Equipo %s guardado. Se aplica la próxima vez que alguien lo elija."):format(lo.name), "success")
        return openEditor(p, factionId)
    end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count >= FDUTY.MAX_LOADOUTS then return notify(p, ("Máximo %d equipos por facción."):format(FDUTY.MAX_LOADOUTS), "error") end
    dbQuery(function(qh)
        local ok, _, newId = dbPoll(qh, 0)
        if not ok then return isElement(p) and notify(p, "No se pudo crear el equipo.", "error") end
        lo.id = newId
        list[newId] = lo
        if isElement(p) then
            notify(p, ("Equipo %s creado."):format(lo.name), "success")
            openEditor(p, factionId)
        end
    end, db(), "INSERT INTO faction_loadouts (faction_id, name, min_level, skin, items) VALUES (?, ?, ?, ?, ?)",
        factionId, lo.name, lo.minLevel, lo.skin, json)
end

editorActions.delete = function(p, factionId, d)
    local id = tonumber(d.id)
    local list = loadouts[factionId]
    local lo = id and list and list[id]
    if not lo then return end
    list[id] = nil
    dbExec(db(), "DELETE FROM faction_loadouts WHERE id = ? AND faction_id = ?", id, factionId)
    -- Quien lo llevaba puesto sale de servicio y devuelve el equipo
    for q, dd in pairs(duty) do
        if dd.factionId == factionId and dd.loadoutId == id then setOffDuty(q, "Tu equipo de servicio fue eliminado: sales de servicio.") end
    end
    notify(p, ("Equipo %s eliminado."):format(lo.name), "success")
    openEditor(p, factionId)
end

----------------------------------------------------------------
-- Acciones del panel
----------------------------------------------------------------
addEventHandler("rp:factionduty:action", resourceRoot, function(action, d)
    local p = client
    if type(action) ~= "string" or type(d) ~= "table" or not characterOf(p) or not takeCooldown(p) then return end

    if editorActions[action] then
        local factionId = canEdit(p)
        if not factionId then return notify(p, "Tu rol no puede gestionar los equipos de servicio.", "error") end
        return editorActions[action](p, factionId, d)
    end

    -- Acciones del vestuario: se revalida cercanía, facción y estado
    local l = nearLocker(p, d.lockerId)
    if not l or fac():getPlayerFactionId(p) ~= l.factionId then return end
    local why = blocked(p)
    if why then return notify(p, why, "warning") end

    if action == "on" then
        local lo = loadouts[l.factionId] and loadouts[l.factionId][tonumber(d.loadoutId) or -1]
        if not lo then return notify(p, "Ese equipo ya no existe.", "error") end
        if lo.minLevel > (fac():getPlayerRankLevel(p) or 0) then
            return notify(p, "Tu rol no alcanza para ese equipo.", "error")
        end
        setOnDuty(p, l.factionId, lo)
    elseif action == "off" then
        if not duty[p] then return end
        setOffDuty(p)
    else
        return
    end
    openLocker(p, l)
end)

----------------------------------------------------------------
-- Ciclo de vida del jugador
----------------------------------------------------------------
local function forget(p)
    if duty[p] then setOffDuty(p, nil, true) end
    given[p], cooldown[p] = nil, nil
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    reconcile(source, tonumber(characterId) or characterOf(source))
end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)

-- Revivido o reaparecido en el hospital: rp_characters le devuelve su ropa; se vuelve a uniformar
addEventHandler("onPlayerSpawn", root, function()
    if duty[source] then setTimer(applyUniform, 600, 1, source) end
end)

-- Deja la facción, lo expulsan o cambia de facción: sale de servicio
addEventHandler("rp:faction:onMembershipChange", root, function(newId)
    local d = duty[source]
    if d and newId ~= d.factionId then setOffDuty(source, "Ya no perteneces a la facción: sales de servicio y devuelves el equipo.") end
end)

----------------------------------------------------------------
-- Administración (sintaxis de OwlGaming; el resto lo genera rp_admin con WORLD_TYPES)
----------------------------------------------------------------
local function makeLocker(player, _, factionId)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    factionId = tonumber(factionId)
    local info = factionId and fac():getFactionInfo(factionId)
    if not info then return notify(player, "Uso: /makelocker <idFaccion> (mira los ids con /facciones)", "warning") end
    if not isGenericType(info.type) then
        return notify(player, ("%s lleva su propio servicio (%s): su vestuario no va aquí."):format(info.name, info.type), "error")
    end
    local x, y, z = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if not ok then return isElement(player) and notify(player, "No se pudo crear el vestuario.", "error") end
        local l = { id = id, factionId = factionId, x = x, y = y, z = z, interior = int, dimension = dim }
        lockers[id] = l
        spawnLocker(l)
        broadcastLockers()
        outputDebugString(("[rp_factionduty] %s creo el vestuario #%d de %s"):format(getPlayerName(player), id, info.name))
        if isElement(player) then
            notify(player, ("Vestuario #%d de %s creado. Muévelo con ALT; bórralo con /dellocker %d."):format(id, info.name, id), "success", 8000)
        end
    end, db(), "INSERT INTO faction_lockers (faction_id, x, y, z, interior, dimension) VALUES (?, ?, ?, ?, ?, ?)",
        factionId, x, y, z, int, dim)
end
addCommandHandler("makelocker", makeLocker)
addCommandHandler("crearvestuario", makeLocker)

function adminElements()
    local list = {}
    for id, l in pairs(lockers) do
        list[#list + 1] = { id = id, x = l.x, y = l.y, z = l.z, interior = l.interior, dimension = l.dimension,
            label = lockerLabel(l), noRot = true, element = l.marker, info = ("Facción #%d"):format(l.factionId) }
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not lockers[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM faction_lockers WHERE id = ?", id)
    destroyLocker(id)
    broadcastLockers()
    return true
end

function adminMove(id, _, x, y, z)
    id = tonumber(id)
    local l = id and lockers[id]
    if not l then return false, "no existe" end
    l.x, l.y, l.z = x, y, z
    dbExec(db(), "UPDATE faction_lockers SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
    spawnLocker(l)
    broadcastLockers()
    return true
end

addEventHandler("rp:factionduty:requestLockers", resourceRoot, function()
    triggerClientEvent(client, "rp:factionduty:lockers", resourceRoot, lockersForClient())
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            local l = { id = tonumber(r.id), factionId = tonumber(r.faction_id), x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
                interior = tonumber(r.interior) or 0, dimension = tonumber(r.dimension) or 0 }
            lockers[l.id] = l
            spawnLocker(l)
        end
        broadcastLockers()
    end, db(), "SELECT * FROM faction_lockers")
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            local fid = tonumber(r.faction_id)
            loadouts[fid] = loadouts[fid] or {}
            local lo = loadoutFromRow(r)
            loadouts[fid][lo.id] = lo
        end
    end, db(), "SELECT * FROM faction_loadouts")
    -- Reinicio en caliente: nadie queda de servicio; lo que quedó sin devolver se retira ahora
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, "rp:factionDuty", false)
        local characterId = characterOf(p)
        if characterId then reconcile(p, characterId) end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(duty) do
        if isElement(p) then setOffDuty(p, "El servicio se reinicia: devuelves el equipo.") end
    end
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, "rp:factionDuty", false)
        setElementData(p, "rp:dutyItems", false, false)
    end
end)
