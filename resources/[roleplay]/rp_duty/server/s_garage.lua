--[[
    rp_duty / s_garage.lua  (servidor)

    Vehículos de facción (#105) para los tipos con servicio genérico (rp_duty):
      - Los admins colocan el garaje de cada facción (/makefgarage <id facción>): ahí salen y se guardan.
      - A pie, E en el garaje abre el panel: sacar los vehículos de la facción (de servicio y con el
        nivel de rol mínimo de cada uno); el líder (o "manage_ranks") compra con los fondos de la
        facción (cobro atómico en rp_factions), vende (vuelve el 50 %) y fija el rol mínimo.
      - Al volante de un vehículo de la facción, E en el garaje lo guarda (combustible y daño se guardan).
      - Nadie de fuera (ni un miembro fuera de servicio o sin nivel) puede conducirlo.
      - Abandonado GARAGE.ABANDON_MIN minutos sin nadie dentro: vuelve solo al garaje.

    Exports (servidor): getFactionVehicleInfo(vehicle) -> { id, factionId, minLevel } | false
]]

local garages = {}     -- [id] = { row, marker, col }
local fleet = {}       -- [vehicleId] = row (faction_vehicles)
local out = {}         -- [vehicleId] = vehicle element
local byElement = {}   -- [vehicle] = vehicleId
local lastUsed = {}    -- [vehicleId] = tick de la última vez que alguien iba dentro
local nearGarage = {}  -- [player] = garageId
local cooldown = {}    -- [player] = tick

addEvent("rp:onDatabaseReady", false)
addEvent("rp:duty:garageUse", true)      -- cliente: E en un garaje
addEvent("rp:duty:garageAction", true)   -- cliente: acción del panel del garaje
addEvent("rp:markers:moved")
addEvent("rp:markers:ready")

local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function log(msg) outputDebugString("[rp_duty] " .. msg, 3) end
local function charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function factionOf(p)
    local ok, f = pcall(function() return exports.rp_factions:getPlayerFactionInfo(p) end)
    return ok and type(f) == "table" and f or nil
end

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

local function factionName(fid)
    local ok, info = pcall(function() return exports.rp_factions:getFactionInfo(fid) end)
    return ok and type(info) == "table" and info.name or ("facción " .. tostring(fid))
end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < DUTY.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

local function catalogEntry(kind, model)
    for _, c in ipairs(garageCatalogFor(kind)) do
        if c.model == model then return c end
    end
    return nil
end

local function vehicleName(model)
    for _, c in ipairs(GARAGE.CATALOG) do if c.model == model then return c.name end end
    return getVehicleNameFromModel(model) or ("Modelo " .. model)
end

-- Garaje de la facción en el que está el jugador (o nil)
local function garageOfPlayer(p, factionId)
    local gid = nearGarage[p]
    local g = gid and garages[gid]
    if not g or tonumber(g.row.faction_id) ~= factionId then return nil end
    local r = g.row
    if getElementInterior(p) ~= (tonumber(r.interior) or 0) or getElementDimension(p) ~= (tonumber(r.dimension) or 0) then return nil end
    local x, y, z = getElementPosition(p)
    if getDistanceBetweenPoints3D(x, y, z, tonumber(r.x), tonumber(r.y), tonumber(r.z)) > GARAGE.INTERACT_RADIUS + 2 then return nil end
    return g
end

----------------------------------------------------------------
-- Vehículos: sacar y guardar
----------------------------------------------------------------
local function storeVehicle(id, silent)
    local v = out[id]
    local row = fleet[id]
    out[id], lastUsed[id] = nil, nil
    if not isElement(v) then return end
    byElement[v] = nil
    if row then
        local fuel = exports.rp_vehicles:getVehicleFuel(v)
        row.fuel = (fuel and fuel ~= math.huge) and fuel or nil
        row.health = math.max(300, getElementHealth(v))
        dbExec(db(), "UPDATE faction_vehicles SET fuel = ?, health = ? WHERE id = ?", row.fuel, row.health, id)
    end
    for _, occ in pairs(getVehicleOccupants(v) or {}) do
        if isElement(occ) then removePedFromVehicle(occ) end
    end
    destroyElement(v)
end

local function spawnVehicle(p, g, row)
    local r = g.row
    local x, y, z = tonumber(r.x), tonumber(r.y), tonumber(r.z)
    for _, other in ipairs(getElementsWithinRange(x, y, z, GARAGE.SPAWN_CLEAR, "vehicle", tonumber(r.interior) or 0, tonumber(r.dimension) or 0)) do
        if isElement(other) then return false, "La salida del garaje está ocupada. Espera un momento." end
    end
    local model = tonumber(row.model)
    local v = createVehicle(model, x, y, z + 0.6, 0, 0, tonumber(r.rot) or 0, row.plate)
    if not v then return false, "No se pudo sacar el vehículo." end
    setElementInterior(v, tonumber(r.interior) or 0)
    setElementDimension(v, tonumber(r.dimension) or 0)
    local c = {}
    for n in tostring(row.color or ""):gmatch("%d+") do c[#c + 1] = tonumber(n) end
    if #c >= 3 then setVehicleColor(v, unpack(c)) end
    setElementHealth(v, math.max(300, tonumber(row.health) or 1000))
    if tonumber(row.fuel) then exports.rp_vehicles:setVehicleFuel(v, tonumber(row.fuel)) end
    setElementData(v, "rp:factionVehicle", tonumber(row.faction_id))
    setElementData(v, "rp:factionVehicleId", row.id)
    out[row.id], byElement[v], lastUsed[row.id] = v, row.id, getTickCount()
    warpPedIntoVehicle(p, v)
    setVehicleEngineState(v, true)
    return true
end

-- Al subir de conductor: solo miembros de esa facción, de servicio y con el nivel del vehículo
addEventHandler("onVehicleStartEnter", root, function(p, seat)
    local id = byElement[source]
    if not id or seat ~= 0 then return end
    local row = fleet[id]
    local f = factionOf(p)
    local ok = f and row and f.id == tonumber(row.faction_id)
    local reason = "Este vehículo es de " .. factionName(row and row.faction_id) .. "."
    if ok and not isOnDuty(p) then ok, reason = false, "Entra de servicio en el vestuario para conducirlo." end
    if ok and not f.leader and (f.rankLevel or 0) < (tonumber(row.min_level) or 1) then
        ok, reason = false, ("Necesitas rol de nivel %d para conducirlo."):format(tonumber(row.min_level) or 1)
    end
    if not ok then
        cancelEvent()
        notify(p, reason, "error")
    end
end)

addEventHandler("onVehicleEnter", root, function()
    local id = byElement[source]
    if id then lastUsed[id] = getTickCount() end
end)
addEventHandler("onVehicleExit", root, function()
    local id = byElement[source]
    if id then lastUsed[id] = getTickCount() end
end)
addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    local id = byElement[source]
    if id then byElement[source], out[id], lastUsed[id] = nil, nil, nil end
end)
-- Explotado: vuelve al garaje con el daño reparado a medias (no se pierde el vehículo)
addEventHandler("onVehicleExplode", root, function()
    local id = byElement[source]
    if not id then return end
    local v = source
    setTimer(function()
        if fleet[id] then fleet[id].health = 300 end
        if out[id] == v then storeVehicle(id, true) end
    end, 5000, 1)
end)

-- Abandonados: vuelven solos al garaje
local abandonTimer = setTimer(function()
    local now = getTickCount()
    for id, v in pairs(out) do
        if isElement(v) then
            local occupied = next(getVehicleOccupants(v) or {}) ~= nil
            if occupied then lastUsed[id] = now
            elseif now - (lastUsed[id] or now) > GARAGE.ABANDON_MIN * 60000 then storeVehicle(id) end
        end
    end
end, 60000, 0)

----------------------------------------------------------------
-- Panel del garaje
----------------------------------------------------------------
local function panelData(p, g)
    local f = factionOf(p)
    if not f then return nil end
    local manage = canManage(p, f)
    local list = {}
    for id, row in pairs(fleet) do
        if tonumber(row.faction_id) == f.id then
            list[#list + 1] = { id = id, model = tonumber(row.model), name = vehicleName(tonumber(row.model)),
                plate = row.plate, minLevel = tonumber(row.min_level) or 1, out = out[id] ~= nil,
                health = math.floor((tonumber(row.health) or 1000) / 10), price = tonumber(row.price) or 0,
                allowed = f.leader or (f.rankLevel or 0) >= (tonumber(row.min_level) or 1) }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    local catalog = {}
    if manage then
        for i, c in ipairs(garageCatalogFor(f.type)) do catalog[i] = { model = c.model, name = c.name, price = c.price } end
    end
    local funds = false
    if manage then
        local ok, n = pcall(function() return exports.rp_factions:getFactionFunds(f.id) end)
        funds = ok and tonumber(n) or 0
    end
    return {
        garage = g and tonumber(g.row.id) or false, faction = f.name, tag = f.tag, color = f.color, rank = f.rank,
        onDuty = isOnDuty(p), vehicles = list, manage = manage, catalog = catalog, funds = funds,
        limits = { maxVehicles = GARAGE.MAX_VEHICLES, refund = GARAGE.SELL_REFUND },
    }
end

local function openPanel(p, g)
    local data = panelData(p, g)
    if data then triggerClientEvent(p, "rp:duty:garage", resourceRoot, data) end
end

local actions = {}

actions.take = function(p, f, g, d)
    local id = tonumber(d.id)
    local row = id and fleet[id]
    if not row or tonumber(row.faction_id) ~= f.id then return end
    if not isOnDuty(p) then return notify(p, "Entra de servicio en el vestuario antes de sacar un vehículo.", "warning") end
    if not f.leader and (f.rankLevel or 0) < (tonumber(row.min_level) or 1) then
        return notify(p, ("Necesitas rol de nivel %d para sacarlo."):format(tonumber(row.min_level) or 1), "error")
    end
    if out[id] then return notify(p, "Ese vehículo ya está fuera.", "warning") end
    local ok, why = spawnVehicle(p, g, row)
    if not ok then return notify(p, why, "warning") end
    notify(p, ("Sacas %s (%s). Tráelo aquí y pulsa E al volante para guardarlo."):format(vehicleName(tonumber(row.model)), row.plate), "success")
    triggerClientEvent(p, "rp:duty:garageClose", resourceRoot)
end

actions.buy = function(p, f, g, d)
    if not canManage(p, f) then return notify(p, "Solo el líder o quien gestiona roles puede comprar vehículos.", "error") end
    local c = catalogEntry(f.type, tonumber(d.model))
    if not c then return end
    local count = 0
    for _, row in pairs(fleet) do if tonumber(row.faction_id) == f.id then count = count + 1 end end
    if count >= GARAGE.MAX_VEHICLES then return notify(p, ("Máximo %d vehículos por facción."):format(GARAGE.MAX_VEHICLES), "error") end
    -- Cobro atómico en rp_factions; si el INSERT falla se devuelve
    local paid = exports.rp_factions:takeFactionFunds(f.id, c.price, ("%s compro un %s por $%d"):format(getPlayerName(p), c.name, c.price))
    if not paid then return notify(p, ("La facción no tiene $%d en sus fondos."):format(c.price), "error") end
    local r, gc, b = 255, 255, 255
    local hex = type(f.color) == "string" and f.color:match("^#(%x%x%x%x%x%x)$")
    if hex then r, gc, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) end
    local color = ("%d,%d,%d,255,255,255"):format(r, gc, b)
    dbQuery(function(qh)
        local ok, _, newId = dbPoll(qh, 0)
        if not ok or not newId then
            exports.rp_factions:addFactionFunds(f.id, c.price, "Devolucion: no se pudo registrar el vehiculo")
            return isElement(p) and notify(p, "No se pudo comprar el vehículo; se devolvió el dinero.", "error")
        end
        newId = tonumber(newId)
        local plate = ("%s%d-%d"):format(GARAGE.PLATE_PREFIX, f.id, newId):sub(1, 8)
        dbExec(db(), "UPDATE faction_vehicles SET plate = ? WHERE id = ?", plate, newId)
        fleet[newId] = { id = newId, faction_id = f.id, model = c.model, color = color, min_level = 1, plate = plate,
            fuel = nil, health = 1000, price = c.price }
        if isElement(p) then
            notify(p, ("Compraste %s para la facción por $%d."):format(c.name, c.price), "success")
            openPanel(p, garageOfPlayer(p, f.id))
        end
    end, db(), "INSERT INTO faction_vehicles (faction_id, model, color, min_level, plate, price) VALUES (?, ?, ?, 1, 'NUEVO', ?)",
        f.id, c.model, color, c.price)
end

actions.sell = function(p, f, g, d)
    if not canManage(p, f) then return notify(p, "Solo el líder o quien gestiona roles puede vender vehículos.", "error") end
    local id = tonumber(d.id)
    local row = id and fleet[id]
    if not row or tonumber(row.faction_id) ~= f.id then return end
    if out[id] then return notify(p, "Guárdalo en el garaje antes de venderlo.", "warning") end
    fleet[id] = nil
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not affected or affected == 0 then return end   -- ya se había vendido: no se paga dos veces
        local refund = math.floor((tonumber(row.price) or 0) * GARAGE.SELL_REFUND)
        if refund > 0 then
            exports.rp_factions:addFactionFunds(f.id, refund, ("%s vendio el %s (%s) por $%d"):format(getPlayerName(p), vehicleName(tonumber(row.model)), row.plate, refund))
        end
        if isElement(p) then
            notify(p, ("Vendiste %s. Vuelven $%d a los fondos."):format(vehicleName(tonumber(row.model)), refund), "success")
            openPanel(p, garageOfPlayer(p, f.id))
        end
    end, db(), "DELETE FROM faction_vehicles WHERE id = ? AND faction_id = ?", id, f.id)
end

actions.level = function(p, f, g, d)
    if not canManage(p, f) then return end
    local id = tonumber(d.id)
    local row = id and fleet[id]
    local level = math.floor(tonumber(d.level) or 0)
    if not row or tonumber(row.faction_id) ~= f.id or level < 1 or level > 99 then return end
    row.min_level = level
    dbExec(db(), "UPDATE faction_vehicles SET min_level = ? WHERE id = ? AND faction_id = ?", level, id, f.id)
    notify(p, ("%s: ahora pide rol de nivel %d."):format(vehicleName(tonumber(row.model)), level), "success")
    openPanel(p, g)
end

addEventHandler("rp:duty:garageUse", resourceRoot, function()
    local p = client
    if not charOf(p) or not takeCooldown(p) then return end
    local f = factionOf(p)
    local gid = nearGarage[p]
    local g0 = gid and garages[gid]
    if not g0 then return end
    if not f or f.id ~= tonumber(g0.row.faction_id) then
        return notify(p, "Este garaje es de " .. factionName(tonumber(g0.row.faction_id)) .. ".", "error")
    end
    local g = garageOfPlayer(p, f.id)
    if not g or not usesDuty(f.type) then return end
    if getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") then return end
    -- Al volante de un vehículo de la facción: guardarlo
    local v = getPedOccupiedVehicle(p)
    if v then
        local id = byElement[v]
        if not id or getVehicleController(v) ~= p or tonumber(fleet[id] and fleet[id].faction_id) ~= f.id then
            return notify(p, "Solo se guardan aquí los vehículos de tu facción.", "warning")
        end
        storeVehicle(id)
        return notify(p, "Vehículo guardado en el garaje.", "success")
    end
    openPanel(p, g)
end)

addEventHandler("rp:duty:garageAction", resourceRoot, function(action, d)
    local p = client
    if type(action) ~= "string" or not actions[action] or not charOf(p) or not takeCooldown(p) then return end
    if isPedInVehicle(p) or getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") then return end
    local f = factionOf(p)
    local g = f and garageOfPlayer(p, f.id)
    if not g or not usesDuty(f.type) then return notify(p, "Acércate al garaje de tu facción.", "warning") end
    actions[action](p, f, g, type(d) == "table" and d or {})
end)

----------------------------------------------------------------
-- Garajes (faction_garages)
----------------------------------------------------------------
local function garageKey(id) return "fgarage" .. id end

local function destroyGarage(id)
    local g = garages[id]
    if not g then return end
    for _, el in ipairs({ g.marker, g.col }) do if isElement(el) then destroyElement(el) end end
    for p, gid in pairs(nearGarage) do
        if gid == id then
            nearGarage[p] = nil
            if isElement(p) then triggerClientEvent(p, "rp:duty:nearGarage", resourceRoot, false) end
        end
    end
    garages[id] = nil
end

local function spawnGarage(row)
    local id = tonumber(row.id)
    destroyGarage(id)
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    local int, dim = tonumber(row.interior) or 0, tonumber(row.dimension) or 0
    local c = GARAGE.MARKER_COLOR
    local label = "Garaje · " .. factionName(tonumber(row.faction_id))
    local marker = createMarker(x, y, z - 1, "cylinder", 3.0, c[1], c[2], c[3], 110)
    setElementInterior(marker, int)
    setElementDimension(marker, dim)
    pcall(function()
        exports.rp_markers:setMarkerStyle(marker, { icon = "car", label = label })
        exports.rp_markers:registerMarker(marker, garageKey(id), { label = label, point = { x, y, z }, ownerSaves = true })
    end)
    local col = createColSphere(x, y, z, GARAGE.INTERACT_RADIUS)
    setElementInterior(col, int)
    setElementDimension(col, dim)
    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if sameDim and getElementType(el) == "player" then
            nearGarage[el] = id
            triggerClientEvent(el, "rp:duty:nearGarage", resourceRoot, id, label)
        end
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and nearGarage[el] == id then
            nearGarage[el] = nil
            triggerClientEvent(el, "rp:duty:nearGarage", resourceRoot, false)
        end
    end)
    garages[id] = { row = row, marker = marker, col = col }
end

addEventHandler("rp:markers:moved", root, function(owner, key, x, y, z, admin)
    if owner ~= getResourceName(resource) or not x then return end
    local id = tonumber(tostring(key):match("^fgarage(%d+)$"))
    local g = id and garages[id]
    if not g then return end
    g.row.x, g.row.y, g.row.z = x, y, z
    dbExec(db(), "UPDATE faction_garages SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
    spawnGarage(g.row)
    log(("%s movió el garaje %d con el editor"):format(isElement(admin) and getPlayerName(admin) or "?", id))
end)

addEventHandler("rp:markers:ready", root, function()
    for _, g in pairs(garages) do spawnGarage(g.row) end
end)

local function makeGarage(player, _, factionId)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    factionId = tonumber(factionId)
    local ok, info = pcall(function() return exports.rp_factions:getFactionInfo(factionId) end)
    if not factionId or not ok or type(info) ~= "table" then
        return notify(player, "Uso: /makefgarage <id de facción>  (de pie donde salen los vehículos, mirando hacia la salida)", "warning")
    end
    if not usesDuty(info.type) then
        return notify(player, ("Las facciones de tipo %s no usan este garaje."):format(tostring(info.type)), "warning")
    end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local okq, _, id = dbPoll(qh, 0)
        if not okq or not id then return isElement(player) and notify(player, "No se pudo crear el garaje.", "error") end
        spawnGarage({ id = id, faction_id = factionId, x = x, y = y, z = z, rot = rot, interior = int, dimension = dim, created_by = getPlayerName(player) })
        if isElement(player) then
            notify(player, ("Garaje %d creado para %s. Los vehículos saldrán aquí mirando hacia donde miras."):format(id, info.name), "success")
        end
        log(("%s creó el garaje %d (facción %d)"):format(getPlayerName(player), id, factionId))
    end, db(), "INSERT INTO faction_garages (faction_id, x, y, z, rot, interior, dimension, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        factionId, x, y, z, rot, int, dim, getPlayerName(player))
end
addCommandHandler("makefgarage", makeGarage)
addCommandHandler("creargarajefaccion", makeGarage)

----------------------------------------------------------------
-- Exports y rp_admin (/nearbyfgarages, /delfgarage...)
----------------------------------------------------------------
function getFactionVehicleInfo(vehicle)
    local id = byElement[vehicle]
    local row = id and fleet[id]
    return row and { id = id, factionId = tonumber(row.faction_id), minLevel = tonumber(row.min_level) or 1 } or false
end

function adminGarageElements()
    local list = {}
    for id, g in pairs(garages) do
        local r = g.row
        list[#list + 1] = { id = id, x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
            interior = tonumber(r.interior) or 0, dimension = tonumber(r.dimension) or 0,
            label = "Garaje · " .. factionName(tonumber(r.faction_id)), creator = r.created_by,
            rot = tonumber(r.rot) or 0, element = g.marker }
    end
    return list
end

function adminGarageDelete(id)
    id = tonumber(id)
    if not id or not garages[id] then return false, "no existe" end
    destroyGarage(id)
    dbExec(db(), "DELETE FROM faction_garages WHERE id = ?", id)
    return true
end

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
local function forget(p)
    nearGarage[p], cooldown[p] = nil, nil
end
addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEvent("rp:onCharacterLogout", false)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)

local function boot()
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do spawnGarage(r) end
    end, db(), "SELECT id, faction_id, x, y, z, rot, interior, dimension, created_by FROM faction_garages")
    dbQuery(function(qh)
        fleet = {}
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            r.id = tonumber(r.id)
            fleet[r.id] = r
        end
    end, db(), "SELECT id, faction_id, model, color, min_level, plate, fuel, health, price FROM faction_vehicles")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(abandonTimer) then killTimer(abandonTimer) end
    for id in pairs(out) do storeVehicle(id, true) end
end)
