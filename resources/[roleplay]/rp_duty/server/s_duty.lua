--[[
    rp_duty / s_duty.lua  (servidor)

    Vestuario genérico de facción (#104):
      - Los admins colocan vestuarios por facción (/makelocker <id facción>, alias /crearvestuario).
      - Un miembro pulsa E en el vestuario de SU facción: panel para elegir uniforme (los que su
        nivel de rol permite) y entrar o salir de servicio.
      - De servicio: skin del uniforme y su equipo (ítems de rp_inventory, también armas). Al salir,
        al desconectar o al dejar la facción se devuelve el equipo. Lo entregado se apunta en
        faction_duty_items: si el servidor se cae, se recoge al volver a entrar (sin duplicar ítems).
      - El líder (o quien tenga el permiso "manage_ranks") crea y edita los uniformes en el mismo panel.
      - rp_factions pregunta isOnDuty(p) para los tipos con duty = "rp_duty" (sueldo solo de servicio).

    Exports (servidor): isOnDuty(p), getDutyLoadout(p), adminElements(), adminDelete(id)
]]

local lockers = {}     -- [id] = { row, marker, col }
local loadouts = {}    -- [factionId] = { [id] = row }
local duty = {}        -- [player] = { factionId, loadoutId, items = { {id, amount} }, characterId }
local nearLocker = {}  -- [player] = lockerId
local cooldown = {}    -- [player] = tick

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:duty:use", true)       -- cliente: E en un vestuario
addEvent("rp:duty:action", true)    -- cliente: acción del panel
addEvent("rp:markers:moved")
addEvent("rp:markers:ready")

----------------------------------------------------------------
-- Atajos
----------------------------------------------------------------
local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function log(msg, level) outputDebugString("[rp_duty] " .. msg, level or 3) end
local function charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function factionOf(p)
    local ok, f = pcall(function() return exports.rp_factions:getPlayerFactionInfo(p) end)
    return ok and type(f) == "table" and f or nil
end

-- ¿El tipo de esta facción usa el vestuario genérico?
local function usesDuty(kind)
    local ok, types = pcall(function() return exports.rp_factions:getFactionTypes() end)
    local t = ok and type(types) == "table" and types[kind]
    return t and t.duty == getResourceName(resource) or false
end

local function canManage(p, f)
    if not f then return false end
    if f.leader then return true end
    local ok, yes = pcall(function() return exports.rp_factions:hasFactionPermission(p, "manage_ranks") end)
    return ok and yes == true
end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < DUTY.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

local function blocked(p)
    return isPedDead(p) or getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") or isPedInVehicle(p)
end

local function factionLog(factionId, text)
    dbExec(db(), "INSERT INTO faction_log (faction_id, text) VALUES (?, ?)", factionId, tostring(text):sub(1, 255))
end

local function itemName(id)
    local ok, def = pcall(function() return exports.rp_inventory:getItemDefinition(id) end)
    return ok and type(def) == "table" and def.name or id
end

----------------------------------------------------------------
-- Equipo: entregar y recoger
----------------------------------------------------------------
-- Recoge lo entregado (lo que aún tenga). Devuelve cuántas unidades faltaban.
local function takeBack(p, items)
    local missing = 0
    for _, it in ipairs(items or {}) do
        local ok, have = pcall(function() return exports.rp_inventory:getItemAmount(p, it.id) end)
        have = ok and tonumber(have) or 0
        local n = math.min(have, it.amount)
        if n > 0 then exports.rp_inventory:takeItem(p, it.id, n) end
        missing = missing + (it.amount - n)
    end
    return missing
end

local function inventoryReady(p)
    local ok, inv = pcall(function() return exports.rp_inventory:getInventory(p) end)
    return ok and type(inv) == "table"
end

-- Equipo que quedó de una sesión cortada (caída o reinicio): se recoge cuando el inventario esté listo
local function collectLeftovers(p, characterId, tries)
    tries = tries or 0
    if not isElement(p) or charOf(p) ~= characterId or duty[p] then return end
    if not inventoryReady(p) then
        if tries < 20 then setTimer(collectLeftovers, 1500, 1, p, characterId, tries + 1) end
        return
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local r = rows[1]
        if not r or not isElement(p) or charOf(p) ~= characterId or duty[p] then return end
        takeBack(p, dutyParseItems(r.items))
        dbExec(db(), "DELETE FROM faction_duty_items WHERE character_id = ?", characterId)
        notify(p, "Devolviste el equipo de servicio que te quedó de la última vez.", "info")
    end, db(), "SELECT items FROM faction_duty_items WHERE character_id = ?", characterId)
end

local function applyUniform(p)
    local d = duty[p]
    local l = d and loadouts[d.factionId] and loadouts[d.factionId][d.loadoutId]
    if not l or not isElement(p) or isPedDead(p) then return end
    local skin = tonumber(l.skin)
    if skin then
        setElementModel(p, skin)
        setElementData(p, "rp:head", false)     -- la cabeza personalizada no va sobre el uniforme
    end
end

local function setDuty(p, on, loadoutId, silent)
    local d = duty[p]
    if not on then
        if not d then return end
        duty[p] = nil
        -- Si rp_inventory ya descargó el inventario (desconexión), el registro se queda y el equipo
        -- se recoge la próxima vez que entre ese personaje (collectLeftovers)
        local collected = isElement(p) and inventoryReady(p)
        if collected then
            local missing = takeBack(p, d.items)
            if missing > 0 then
                factionLog(d.factionId, ("%s salió de servicio sin %d unidad(es) del equipo"):format(getPlayerName(p), missing))
            end
        end
        if isElement(p) then
            if not isPedDead(p) then exports.rp_characters:restoreCharacterLook(p) end
            setElementData(p, DUTY.ELEMENT_DATA, false)
            if not silent then notify(p, "Sales de servicio y devuelves el equipo.", "info") end
        end
        if collected then dbExec(db(), "DELETE FROM faction_duty_items WHERE character_id = ?", d.characterId) end
        return true
    end

    local f = factionOf(p)
    local l = f and loadouts[f.id] and loadouts[f.id][loadoutId]
    if not l then return false, "Ese uniforme ya no existe." end
    if (f.rankLevel or 0) < (tonumber(l.min_level) or 1) and not f.leader then
        return false, "Tu rol no puede usar ese uniforme."
    end
    -- Antes de dar nada: ¿cabe todo?
    local items = dutyParseItems(l.items)
    for _, it in ipairs(items) do
        local ok, why = exports.rp_inventory:canCarry(p, it.id, it.amount)
        if not ok then return false, ("No te cabe %s: %s"):format(itemName(it.id), tostring(why or "")) end
    end
    local given = {}
    for _, it in ipairs(items) do
        if exports.rp_inventory:giveItem(p, it.id, it.amount) then given[#given + 1] = it end
    end
    local characterId = charOf(p)
    duty[p] = { factionId = f.id, loadoutId = l.id, items = given, characterId = characterId }
    dbExec(db(), "REPLACE INTO faction_duty_items (character_id, faction_id, items) VALUES (?, ?, ?)",
        characterId, f.id, dutyFormatItems(given))
    applyUniform(p)
    setElementData(p, DUTY.ELEMENT_DATA, true)
    if not silent then
        notify(p, ("Entras de servicio con el uniforme «%s»%s."):format(l.name,
            #given > 0 and " y tu equipo está en el inventario (I)" or ""), "success")
    end
    return true
end

----------------------------------------------------------------
-- Uniformes (faction_loadouts)
----------------------------------------------------------------
local function loadoutList(factionId, level, all)
    local list = {}
    for _, l in pairs(loadouts[factionId] or {}) do
        local allowed = (tonumber(l.min_level) or 1) <= level
        if all or allowed then
            local items = {}
            for i, it in ipairs(dutyParseItems(l.items)) do items[i] = { id = it.id, amount = it.amount, name = itemName(it.id) } end
            list[#list + 1] = { id = l.id, name = l.name, minLevel = tonumber(l.min_level) or 1,
                skin = tonumber(l.skin) or false, items = items, allowed = allowed }
        end
    end
    table.sort(list, function(a, b) return a.minLevel == b.minLevel and a.id < b.id or a.minLevel < b.minLevel end)
    return list
end

-- Catálogo de objetos que se pueden poner en un uniforme (para el editor)
local function itemCatalog()
    local out = {}
    local ok, list = pcall(function() return exports.rp_inventory:getItemList() end)
    if ok and type(list) == "table" then
        for k, v in pairs(list) do
            local id = type(v) == "table" and (v.id or k) or k
            local name = type(v) == "table" and v.name or tostring(v)
            if type(id) == "string" then out[#out + 1] = { id = id, name = name } end
        end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

local function panelData(p, lockerId)
    local f = factionOf(p)
    if not f then return nil end
    local manage = canManage(p, f)
    local level = f.leader and 999 or (f.rankLevel or 0)
    local d = duty[p]
    return {
        locker = lockerId, faction = f.name, tag = f.tag, color = f.color, rank = f.rank,
        onDuty = d ~= nil, current = d and d.loadoutId or false,
        loadouts = loadoutList(f.id, level, false),
        manage = manage,
        all = manage and loadoutList(f.id, level, true) or false,
        catalog = manage and itemCatalog() or false,
        limits = { maxItems = DUTY.MAX_ITEMS, maxAmount = DUTY.MAX_AMOUNT, maxLoadouts = DUTY.MAX_LOADOUTS },
    }
end

local function openPanel(p, lockerId)
    local data = panelData(p, lockerId)
    if data then triggerClientEvent(p, "rp:duty:panel", resourceRoot, data) end
end

local function loadLoadouts(callback)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        loadouts = {}
        for _, r in ipairs(rows) do
            local fid = tonumber(r.faction_id)
            r.id = tonumber(r.id)
            loadouts[fid] = loadouts[fid] or {}
            loadouts[fid][r.id] = r
        end
        if callback then callback() end
    end, db(), "SELECT id, faction_id, name, min_level, skin, items FROM faction_loadouts")
end

-- Valida un uniforme que llega del panel. Devuelve fila limpia o nil, motivo
local function cleanLoadout(d)
    if type(d) ~= "table" then return nil, "Datos no válidos." end
    local name = tostring(d.name or ""):gsub("#%x%x%x%x%x%x", ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #name < DUTY.NAME_MIN or #name > DUTY.NAME_MAX then
        return nil, ("El nombre debe tener entre %d y %d letras."):format(DUTY.NAME_MIN, DUTY.NAME_MAX)
    end
    local level = math.floor(tonumber(d.minLevel) or 1)
    if level < 1 or level > 99 then return nil, "El nivel de rol va de 1 a 99." end
    local skin = d.skin
    if skin == false or skin == nil or skin == "" then skin = nil
    elseif not dutyValidSkin(skin) then return nil, "Esa skin no existe (1 a 312)."
    else skin = math.floor(tonumber(skin)) end
    local items, seen = {}, {}
    for _, it in ipairs(type(d.items) == "table" and d.items or {}) do
        local id = type(it) == "table" and tostring(it.id or "") or ""
        local n = math.floor(tonumber(type(it) == "table" and it.amount) or 0)
        if id ~= "" then
            local ok, def = pcall(function() return exports.rp_inventory:getItemDefinition(id) end)
            if not ok or type(def) ~= "table" or not id:match("^[%w_]+$") then return nil, "Hay un objeto que no existe." end
            if n < 1 or n > DUTY.MAX_AMOUNT then return nil, ("La cantidad va de 1 a %d."):format(DUTY.MAX_AMOUNT) end
            if seen[id] then return nil, "Hay un objeto repetido." end
            seen[id] = true
            items[#items + 1] = { id = id, amount = n }
        end
    end
    if #items > DUTY.MAX_ITEMS then return nil, ("Máximo %d objetos por uniforme."):format(DUTY.MAX_ITEMS) end
    return { name = name, min_level = level, skin = skin, items = dutyFormatItems(items) }
end

----------------------------------------------------------------
-- Vestuarios (faction_lockers)
----------------------------------------------------------------
local function destroyLocker(id)
    local l = lockers[id]
    if not l then return end
    for _, el in ipairs({ l.marker, l.col }) do if isElement(el) then destroyElement(el) end end
    for p, lid in pairs(nearLocker) do
        if lid == id then
            nearLocker[p] = nil
            if isElement(p) then triggerClientEvent(p, "rp:duty:near", resourceRoot, false) end
        end
    end
    lockers[id] = nil
end

local function lockerKey(id) return "locker" .. id end

local function factionName(fid)
    local ok, info = pcall(function() return exports.rp_factions:getFactionInfo(fid) end)
    return ok and type(info) == "table" and info.name or ("facción " .. fid)
end

local function spawnLocker(row)
    local id = tonumber(row.id)
    destroyLocker(id)
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    local int, dim = tonumber(row.interior) or 0, tonumber(row.dimension) or 0
    local c = DUTY.MARKER_COLOR
    local label = "Vestuario · " .. factionName(tonumber(row.faction_id))
    local marker = createMarker(x, y, z - 1, "cylinder", 1.2, c[1], c[2], c[3], 140)
    setElementInterior(marker, int)
    setElementDimension(marker, dim)
    pcall(function()
        exports.rp_markers:setMarkerStyle(marker, { icon = "clothes", label = label })
        exports.rp_markers:registerMarker(marker, lockerKey(id), { label = label, point = { x, y, z }, ownerSaves = true })
    end)
    local col = createColSphere(x, y, z, DUTY.INTERACT_RADIUS)
    setElementInterior(col, int)
    setElementDimension(col, dim)
    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if sameDim and getElementType(el) == "player" then
            nearLocker[el] = id
            triggerClientEvent(el, "rp:duty:near", resourceRoot, id, label)
        end
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and nearLocker[el] == id then
            nearLocker[el] = nil
            triggerClientEvent(el, "rp:duty:near", resourceRoot, false)
        end
    end)
    lockers[id] = { row = row, marker = marker, col = col }
end

local function isNear(p, id)
    local l = lockers[id]
    if not l or nearLocker[p] ~= id then return false end
    local r = l.row
    if getElementInterior(p) ~= (tonumber(r.interior) or 0) or getElementDimension(p) ~= (tonumber(r.dimension) or 0) then return false end
    local x, y, z = getElementPosition(p)
    return getDistanceBetweenPoints3D(x, y, z, tonumber(r.x), tonumber(r.y), tonumber(r.z)) <= DUTY.INTERACT_RADIUS + 1.5
end

local function loadLockers()
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do spawnLocker(r) end
    end, db(), "SELECT id, faction_id, x, y, z, interior, dimension, created_by FROM faction_lockers")
end

-- Un admin movió el vestuario con el editor (ALT o M + clic derecho): se guarda aquí
addEventHandler("rp:markers:moved", root, function(owner, key, x, y, z, admin)
    if owner ~= getResourceName(resource) or not x then return end
    local id = tonumber(tostring(key):match("^locker(%d+)$"))
    local l = id and lockers[id]
    if not l then return end
    l.row.x, l.row.y, l.row.z = x, y, z
    dbExec(db(), "UPDATE faction_lockers SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
    spawnLocker(l.row)
    log(("%s movió el vestuario %d con el editor"):format(isElement(admin) and getPlayerName(admin) or "?", id))
end)

----------------------------------------------------------------
-- Eventos del cliente
----------------------------------------------------------------
addEventHandler("rp:duty:use", resourceRoot, function(lockerId)
    local p = client
    lockerId = tonumber(lockerId)
    if not lockerId or not charOf(p) or not takeCooldown(p) or not isNear(p, lockerId) then return end
    if blocked(p) then return notify(p, "No puedes cambiarte ahora.", "warning") end
    local f = factionOf(p)
    local l = lockers[lockerId]
    if not f or f.id ~= tonumber(l.row.faction_id) then
        return notify(p, "Este vestuario es de " .. factionName(tonumber(l.row.faction_id)) .. ".", "error")
    end
    if not usesDuty(f.type) then return notify(p, "Tu facción tiene su propio vestuario.", "warning") end
    openPanel(p, lockerId)
end)

local actions = {}

actions.dutyOn = function(p, f, d)
    local id = tonumber(d.id)
    if duty[p] then setDuty(p, false, nil, true) end
    local ok, why = setDuty(p, true, id)
    if not ok then notify(p, why or "No se pudo entrar de servicio.", "error") end
end

actions.dutyOff = function(p)
    if not duty[p] then return end
    setDuty(p, false)
end

actions.save = function(p, f, d)
    if not canManage(p, f) then return notify(p, "Solo el líder o quien gestiona roles puede editar uniformes.", "error") end
    local row, why = cleanLoadout(d)
    if not row then return notify(p, why, "error") end
    local id = tonumber(d.id)
    if id then
        local l = loadouts[f.id] and loadouts[f.id][id]
        if not l then return notify(p, "Ese uniforme ya no existe.", "error") end
        dbExec(db(), "UPDATE faction_loadouts SET name = ?, min_level = ?, skin = ?, items = ? WHERE id = ? AND faction_id = ?",
            row.name, row.min_level, row.skin, row.items, id, f.id)
        l.name, l.min_level, l.skin, l.items = row.name, row.min_level, row.skin, row.items
        factionLog(f.id, ("%s editó el uniforme %s"):format(getPlayerName(p), row.name))
        notify(p, "Uniforme guardado. Se aplica la próxima vez que alguien entre de servicio.", "success")
        return openPanel(p, nearLocker[p])
    end
    local count = 0
    for _ in pairs(loadouts[f.id] or {}) do count = count + 1 end
    if count >= DUTY.MAX_LOADOUTS then return notify(p, ("Máximo %d uniformes por facción."):format(DUTY.MAX_LOADOUTS), "error") end
    dbQuery(function(qh)
        local ok, _, newId = dbPoll(qh, 0)
        if not ok or not newId then return isElement(p) and notify(p, "No se pudo crear el uniforme.", "error") end
        row.id, row.faction_id = tonumber(newId), f.id
        loadouts[f.id] = loadouts[f.id] or {}
        loadouts[f.id][row.id] = row
        factionLog(f.id, ("%s creó el uniforme %s"):format(getPlayerName(p), row.name))
        if isElement(p) then
            notify(p, "Uniforme creado.", "success")
            openPanel(p, nearLocker[p])
        end
    end, db(), "INSERT INTO faction_loadouts (faction_id, name, min_level, skin, items) VALUES (?, ?, ?, ?, ?)",
        f.id, row.name, row.min_level, row.skin, row.items)
end

actions.delete = function(p, f, d)
    if not canManage(p, f) then return notify(p, "Solo el líder o quien gestiona roles puede borrar uniformes.", "error") end
    local id = tonumber(d.id)
    local l = id and loadouts[f.id] and loadouts[f.id][id]
    if not l then return end
    for q, dd in pairs(duty) do
        if dd.factionId == f.id and dd.loadoutId == id then return notify(p, "Alguien está de servicio con ese uniforme ahora.", "warning") end
    end
    dbExec(db(), "DELETE FROM faction_loadouts WHERE id = ? AND faction_id = ?", id, f.id)
    loadouts[f.id][id] = nil
    factionLog(f.id, ("%s borró el uniforme %s"):format(getPlayerName(p), l.name))
    notify(p, "Uniforme borrado.", "success")
    openPanel(p, nearLocker[p])
end

addEventHandler("rp:duty:action", resourceRoot, function(action, d)
    local p = client
    if type(action) ~= "string" or not actions[action] or not charOf(p) or not takeCooldown(p) then return end
    local lockerId = nearLocker[p]
    if not lockerId or not isNear(p, lockerId) or blocked(p) then return notify(p, "Acércate al vestuario.", "warning") end
    local f = factionOf(p)
    if not f or f.id ~= tonumber(lockers[lockerId].row.faction_id) or not usesDuty(f.type) then return end
    actions[action](p, f, type(d) == "table" and d or {})
    if action == "dutyOn" or action == "dutyOff" then openPanel(p, lockerId) end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function isOnDuty(p)
    return isElement(p) and duty[p] ~= nil
end

function getDutyLoadout(p)
    local d = duty[p]
    local l = d and loadouts[d.factionId] and loadouts[d.factionId][d.loadoutId]
    return l and { id = l.id, name = l.name, factionId = d.factionId } or false
end

-- rp_admin (s_world.lua): /nearbylockers, /dellocker... (kind "locker") y /nearbyfgarages,
-- /delfgarage... (kind "garage", en s_garage.lua)
function adminElements(kind)
    if kind == "garage" then return adminGarageElements() end
    local list = {}
    for id, l in pairs(lockers) do
        local r = l.row
        list[#list + 1] = { id = id, x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
            interior = tonumber(r.interior) or 0, dimension = tonumber(r.dimension) or 0,
            label = "Vestuario · " .. factionName(tonumber(r.faction_id)), creator = r.created_by,
            noRot = true, element = l.marker }
    end
    return list
end

function adminDelete(id, kind)
    if kind == "garage" then return adminGarageDelete(id) end
    id = tonumber(id)
    if not id or not lockers[id] then return false, "no existe" end
    destroyLocker(id)
    dbExec(db(), "DELETE FROM faction_lockers WHERE id = ?", id)
    return true
end

----------------------------------------------------------------
-- Comandos de admin
----------------------------------------------------------------
local function makeLocker(player, _, factionId)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    factionId = tonumber(factionId)
    local ok, info = pcall(function() return exports.rp_factions:getFactionInfo(factionId) end)
    if not factionId or not ok or type(info) ~= "table" then
        return notify(player, "Uso: /makelocker <id de facción>  (mira los ids con /facciones)", "warning")
    end
    if not usesDuty(info.type) then
        return notify(player, ("Las facciones de tipo %s no usan este vestuario."):format(tostring(info.type)), "warning")
    end
    local x, y, z = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local okq, _, id = dbPoll(qh, 0)
        if not okq or not id then return isElement(player) and notify(player, "No se pudo crear el vestuario.", "error") end
        spawnLocker({ id = id, faction_id = factionId, x = x, y = y, z = z, interior = int, dimension = dim, created_by = getPlayerName(player) })
        if isElement(player) then
            notify(player, ("Vestuario %d creado para %s. Muévelo con ALT o M + clic derecho."):format(id, info.name), "success")
        end
        log(("%s creó el vestuario %d (facción %d)"):format(getPlayerName(player), id, factionId))
    end, db(), "INSERT INTO faction_lockers (faction_id, x, y, z, interior, dimension, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)",
        factionId, x, y, z, int, dim, getPlayerName(player))
end
addCommandHandler("makelocker", makeLocker)
addCommandHandler("crearvestuario", makeLocker)

----------------------------------------------------------------
-- Ciclo de vida del jugador
----------------------------------------------------------------
local function forget(p)
    if duty[p] then setDuty(p, false, nil, true) end
    nearLocker[p], cooldown[p] = nil, nil
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    setElementData(source, DUTY.ELEMENT_DATA, false)
    collectLeftovers(source, tonumber(characterId))
end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)

-- Revivido o reaparecido: rp_injury/rp_characters le devuelven su ropa; se vuelve a uniformar
addEventHandler("onPlayerSpawn", root, function()
    if duty[source] then setTimer(applyUniform, 600, 1, source) end
end)

-- Si deja la facción (o la cambian de tipo), sale de servicio
local membershipTimer = setTimer(function()
    for p, d in pairs(duty) do
        if not isElement(p) then
            duty[p] = nil
        else
            local f = factionOf(p)
            if not f or f.id ~= d.factionId or not usesDuty(f.type) then setDuty(p, false) end
        end
    end
end, 5000, 0)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    loadLoadouts()
    loadLockers()
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, DUTY.ELEMENT_DATA, false)
        local characterId = charOf(p)
        if characterId then collectLeftovers(p, characterId) end   -- equipo de antes del reinicio
    end
end

-- rp_markers se reinició: vuelve a registrar los vestuarios para que sigan siendo movibles
addEventHandler("rp:markers:ready", root, function()
    for _, l in pairs(lockers) do spawnLocker(l.row) end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(membershipTimer) then killTimer(membershipTimer) end
    for p in pairs(duty) do
        if isElement(p) then setDuty(p, false, nil, true) end
    end
end)
