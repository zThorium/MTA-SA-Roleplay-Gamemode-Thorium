--[[
    rp_vehicles / s_interaction.lua
    Menu de click derecho sobre un vehiculo (tecla M para el cursor):
        - Maletero (si esta abierto o tienes la llave)
        - Ver matricula
        - Multas (dueno)
        - Panel de administracion: vista 3D, golpes del ultimo dia, ultimo
          conductor y quien se subio de copiloto / pasajero
        - Policia (faccion reservada): ver s_police.lua

    Golpes y ocupantes se guardan en vehicle_hits / vehicle_entries y se
    borran pasadas LOG_RETENTION_HOURS (limpieza cada hora).
]]

addEvent("rp:veh:menu", true)
addEvent("rp:veh:action", true)
addEvent("rp:veh:hit", true)

local trunks = {}        -- [vehicleId] = { items = { [itemId] = amount }, loading = bool, viewers = { [player] = true } }
local lastAction = {}    -- [player] = tick (anti spam)
local lastHit = {}       -- [vehicleId .. ":" .. characterId] = { rowId, tick }
local lastHitReport = {} -- [player] = tick

local function throttled(player, ms)
    local now = getTickCount()
    if lastAction[player] and now - lastAction[player] < (ms or 250) then return true end
    lastAction[player] = now
    return false
end

local function vehicleName(vehicle)
    return getVehicleNameFromModel(getElementModel(vehicle)) or "Vehiculo"
end

local function canReach(player, vehicle)
    return isElement(vehicle) and getElementType(vehicle) == "vehicle"
        and distanceTo(player, vehicle) <= VEHICLES.INTERACT_DISTANCE + 1
end

local function trunkAccess(player, vehicle)
    local data = getVehicleData(vehicle)
    if not data or getTrunkCapacity(data.model) <= 0 then return false end
    return not data.locked or hasVehicleKey(player, data.id)
end

----------------------------------------------------------------
-- Menu
----------------------------------------------------------------
addEventHandler("rp:veh:menu", resourceRoot, function(vehicle)
    local player = client
    if throttled(player) or not characterOf(player) or not canReach(player, vehicle) then return end
    local data = getVehicleData(vehicle)
    local options = {}
    if data then
        if getTrunkCapacity(data.model) > 0 then
            options[#options + 1] = { id = "trunk", label = "Maletero", icon = "📦", disabled = not trunkAccess(player, vehicle),
                hint = trunkAccess(player, vehicle) and nil or "Cerrado con llave" }
        end
        options[#options + 1] = { id = "plate", label = "Ver matricula", icon = "🔖" }
        if data.ownerId == characterOf(player) then
            options[#options + 1] = { id = "fines", label = "Multas del vehiculo", icon = "🧾" }
        end
        if isPolice(player) then
            options[#options + 1] = { id = "police", label = "Policia: cepo, multas e historial", icon = "🚓", group = "police" }
        end
        if isAdmin(player) then
            options[#options + 1] = { id = "admin", label = "Admin: golpes y ocupantes", icon = "🛡️", group = "admin" }
        end
    else
        options[#options + 1] = { id = "plate", label = "Ver matricula", icon = "🔖" }
    end
    triggerClientEvent(player, "rp:veh:showMenu", resourceRoot, vehicle, {
        name = vehicleName(vehicle), plate = getVehiclePlateText(vehicle), options = options,
    })
end)

----------------------------------------------------------------
-- Maletero
----------------------------------------------------------------
local function itemDef(itemId)
    return exports.rp_inventory:getItemDefinition(itemId)
end

local function trunkWeight(trunk)
    local total = 0
    for itemId, amount in pairs(trunk.items) do
        local def = itemDef(itemId)
        total = total + (def and def.weight or 0) * amount
    end
    return math.floor(total * 100 + 0.5) / 100
end

local function itemList(items)
    local list = {}
    for itemId, amount in pairs(items or {}) do
        local def = itemDef(itemId)
        if def then
            list[#list + 1] = { id = itemId, name = def.name, icon = def.icon, amount = amount, weight = def.weight }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function sendTrunk(player, vehicle)
    local data = getVehicleData(vehicle)
    local trunk = data and trunks[data.id]
    if not trunk or trunk.loading or not isElement(player) then return end
    triggerClientEvent(player, "rp:veh:showTrunk", resourceRoot, vehicle, {
        plate = data.plate, name = vehicleName(vehicle),
        trunk = itemList(trunk.items), weight = trunkWeight(trunk), capacity = getTrunkCapacity(data.model),
        inventory = itemList(exports.rp_inventory:getInventory(player) or {}),
    })
end

local function refreshViewers(vehicle)
    local data = getVehicleData(vehicle)
    local trunk = data and trunks[data.id]
    if not trunk then return end
    for viewer in pairs(trunk.viewers) do
        if isElement(viewer) and canReach(viewer, vehicle) then sendTrunk(viewer, vehicle) else trunk.viewers[viewer] = nil end
    end
end

local function openTrunk(player, vehicle)
    local data = getVehicleData(vehicle)
    if not trunkAccess(player, vehicle) then return notify(player, "El maletero esta cerrado.", "warning") end
    local trunk = trunks[data.id]
    if trunk then
        trunk.viewers[player] = true
        return sendTrunk(player, vehicle)
    end
    trunk = { items = {}, loading = true, viewers = { [player] = true } }
    trunks[data.id] = trunk
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do
            if tonumber(row.amount) > 0 then trunk.items[row.item_id] = tonumber(row.amount) end
        end
        trunk.loading = nil
        if isElement(vehicle) then refreshViewers(vehicle) end
    end, db(), "SELECT item_id, amount FROM vehicle_items WHERE vehicle_id = ?", data.id)
end

local function validAmount(n)
    return type(n) == "number" and n >= 1 and n == math.floor(n) and n <= 1000
end

local function trunkPut(player, vehicle, itemId, amount)
    local data = getVehicleData(vehicle)
    local trunk = data and trunks[data.id]
    if not trunk or trunk.loading or not trunk.viewers[player] then return end
    if not trunkAccess(player, vehicle) then return notify(player, "El maletero esta cerrado.", "warning") end
    if type(itemId) ~= "string" or not validAmount(amount) then return end
    local def = itemDef(itemId)
    if not def then return end
    if not exports.rp_inventory:hasItem(player, itemId, amount) then return notify(player, "No tienes tantos.", "error") end
    if trunkWeight(trunk) + def.weight * amount > getTrunkCapacity(data.model) + 1e-6 then
        return notify(player, "No cabe en el maletero.", "error")
    end
    if not exports.rp_inventory:takeItem(player, itemId, amount) then return end
    trunk.items[itemId] = (trunk.items[itemId] or 0) + amount
    dbExec(db(), [[INSERT INTO vehicle_items (vehicle_id, item_id, amount) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)]], data.id, itemId, amount)
    refreshViewers(vehicle)
end

local function trunkTake(player, vehicle, itemId, amount)
    local data = getVehicleData(vehicle)
    local trunk = data and trunks[data.id]
    if not trunk or trunk.loading or not trunk.viewers[player] then return end
    if not trunkAccess(player, vehicle) then return notify(player, "El maletero esta cerrado.", "warning") end
    if type(itemId) ~= "string" or not validAmount(amount) then return end
    local current = trunk.items[itemId] or 0
    if current < amount then return notify(player, "No hay tantos en el maletero.", "error") end
    local ok, reason = exports.rp_inventory:canCarry(player, itemId, amount)
    if not ok then return notify(player, reason or "No puedes llevar eso.", "error") end
    -- Primero se quita del maletero (en memoria) para que nadie lo duplique
    if current == amount then
        trunk.items[itemId] = nil
        dbExec(db(), "DELETE FROM vehicle_items WHERE vehicle_id = ? AND item_id = ?", data.id, itemId)
    else
        trunk.items[itemId] = current - amount
        dbExec(db(), "UPDATE vehicle_items SET amount = amount - ? WHERE vehicle_id = ? AND item_id = ?", amount, data.id, itemId)
    end
    if not exports.rp_inventory:giveItem(player, itemId, amount) then
        -- No deberia pasar (se comprobo canCarry), pero se devuelve al maletero
        trunk.items[itemId] = (trunk.items[itemId] or 0) + amount
        dbExec(db(), [[INSERT INTO vehicle_items (vehicle_id, item_id, amount) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)]], data.id, itemId, amount)
    end
    refreshViewers(vehicle)
end

----------------------------------------------------------------
-- Panel de administracion
----------------------------------------------------------------
local WEAPON_NAMES = { [49] = "Choque", [50] = "Aspas", [51] = "Explosion", [37] = "Fuego", [54] = "Caida" }
local function weaponLabel(id)
    id = tonumber(id) or 0
    if WEAPON_NAMES[id] then return WEAPON_NAMES[id] end
    if id == 0 then return "Punos" end
    return getWeaponNameFromID(id) or ("Arma " .. id)
end

local function sendAdmin(player, vehicle)
    local data = getVehicleData(vehicle)
    local hours = VEHICLES.LOG_RETENTION_HOURS
    dbQuery(function(qh)
        local hits = dbPoll(qh, 0) or {}
        dbQuery(function(qh2)
            local entries = dbPoll(qh2, 0) or {}
            dbQuery(function(qh3)
                local owner = (dbPoll(qh3, 0) or {})[1]
                if not isElement(player) or not isElement(vehicle) then return end
                for _, h in ipairs(hits) do h.weapon_name = weaponLabel(h.weapon) end
                local lastPassenger = nil
                for _, e in ipairs(entries) do
                    if tonumber(e.seat) > 0 then lastPassenger = e break end
                end
                triggerClientEvent(player, "rp:veh:showAdmin", resourceRoot, vehicle, {
                    id = data.id, plate = data.plate, name = vehicleName(vehicle),
                    owner = owner and owner.name and owner.name:gsub("_", " ") or "?",
                    health = math.floor(getElementHealth(vehicle) / 10), locked = data.locked, engine = data.engine,
                    lastDriver = data.lastDriver, lastPassenger = lastPassenger,
                    hits = hits, entries = entries, retention = hours,
                })
            end, db(), "SELECT name FROM characters WHERE id = ?", data.ownerId)
        end, db(), [[SELECT character_name, seat, DATE_FORMAT(created_at, '%d/%m %H:%i') AS at FROM vehicle_entries
            WHERE vehicle_id = ? AND created_at >= NOW() - INTERVAL ? HOUR ORDER BY id DESC LIMIT ?]], data.id, hours, VEHICLES.PANEL_ROWS)
    end, db(), [[SELECT character_name, weapon, ROUND(loss) AS loss, hits, DATE_FORMAT(created_at, '%d/%m %H:%i') AS at FROM vehicle_hits
        WHERE vehicle_id = ? AND created_at >= NOW() - INTERVAL ? HOUR ORDER BY id DESC LIMIT ?]], data.id, hours, VEHICLES.PANEL_ROWS)
end

----------------------------------------------------------------
-- Acciones del menu
----------------------------------------------------------------
addEventHandler("rp:veh:action", resourceRoot, function(vehicle, action, a, b)
    local player = client
    if throttled(player) or not characterOf(player) or type(action) ~= "string" then return end
    if action == "trunk_close" then
        for _, trunk in pairs(trunks) do trunk.viewers[player] = nil end
        return
    end
    if not canReach(player, vehicle) then return notify(player, "Estas demasiado lejos del vehiculo.", "warning") end
    local data = getVehicleData(vehicle)

    if action == "plate" then
        return triggerClientEvent(player, "rp:veh:showPlate", resourceRoot, vehicle, {
            plate = getVehiclePlateText(vehicle), name = vehicleName(vehicle),
        })
    end
    if not data then return end

    if action == "trunk" then openTrunk(player, vehicle)
    elseif action == "trunk_put" then trunkPut(player, vehicle, a, tonumber(b))
    elseif action == "trunk_take" then trunkTake(player, vehicle, a, tonumber(b))
    elseif action == "admin" then
        if not isAdmin(player) then return end
        sendAdmin(player, vehicle)
    elseif onPoliceAction then
        onPoliceAction(player, vehicle, data, action, a, b)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    for _, trunk in pairs(trunks) do trunk.viewers[source] = nil end
    lastAction[source], lastHitReport[source] = nil, nil
end)

-- Libera de memoria los maleteros sin nadie mirando
setTimer(function()
    for id, trunk in pairs(trunks) do
        if not trunk.loading and not next(trunk.viewers) then trunks[id] = nil end
    end
end, 10 * 60000, 0)

----------------------------------------------------------------
-- Registro de ocupantes (lo llama s_vehicles al subir)
----------------------------------------------------------------
function onOwnedVehicleEnter(vehicle, player, seat)
    local data = getVehicleData(vehicle)
    local characterId = characterOf(player)
    if not data or not characterId then return end
    local name = getPlayerName(player)
    dbExec(db(), "INSERT INTO vehicle_entries (vehicle_id, character_id, character_name, seat) VALUES (?, ?, ?, ?)",
        data.id, characterId, name, seat)
    if seat == 0 then
        local r = getRealTime()
        data.lastDriver = { name = name, at = ("%02d/%02d %02d:%02d"):format(r.monthday, r.month + 1, r.hour, r.minute) }
        dbExec(db(), "UPDATE vehicles SET last_driver_id = ?, last_driver_name = ?, last_driver_at = NOW() WHERE id = ?",
            characterId, name, data.id)
    end
end

----------------------------------------------------------------
-- Golpes (los reporta el cliente que los causa)
----------------------------------------------------------------
addEventHandler("rp:veh:hit", resourceRoot, function(vehicle, weapon, loss)
    local player = client
    local characterId = characterOf(player)
    if not characterId or not isElement(vehicle) then return end
    local data = getVehicleData(vehicle)
    loss, weapon = tonumber(loss), tonumber(weapon) or 0
    if not data or not loss or loss < VEHICLES.HIT_MIN_LOSS or loss > 1000 then return end
    if distanceTo(player, vehicle) > 80 then return end
    local now = getTickCount()
    if lastHitReport[player] and now - lastHitReport[player] < 500 then return end
    lastHitReport[player] = now

    local key = data.id .. ":" .. characterId
    local prev = lastHit[key]
    if prev and prev.rowId and now - prev.tick < VEHICLES.HIT_MERGE_SECONDS * 1000 then
        prev.tick = now
        return dbExec(db(), "UPDATE vehicle_hits SET hits = hits + 1, loss = loss + ?, weapon = ?, created_at = NOW() WHERE id = ?",
            loss, weapon, prev.rowId)
    end
    local entry = { tick = now }
    lastHit[key] = entry
    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        entry.rowId = tonumber(id)
    end, db(), "INSERT INTO vehicle_hits (vehicle_id, character_id, character_name, weapon, loss) VALUES (?, ?, ?, ?, ?)",
        data.id, characterId, getPlayerName(player), weapon, loss)
end)

----------------------------------------------------------------
-- Limpieza: borra golpes y ocupantes de mas de un dia
----------------------------------------------------------------
local function cleanupLogs()
    local hours = VEHICLES.LOG_RETENTION_HOURS
    dbExec(db(), "DELETE FROM vehicle_hits WHERE created_at < NOW() - INTERVAL ? HOUR", hours)
    dbExec(db(), "DELETE FROM vehicle_entries WHERE created_at < NOW() - INTERVAL ? HOUR", hours)
    local now = getTickCount()
    for key, h in pairs(lastHit) do
        if now - h.tick > VEHICLES.HIT_MERGE_SECONDS * 1000 then lastHit[key] = nil end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        if exports.rp_database:isReady() then cleanupLogs() end
    end, 15000, 1)
end)
setTimer(cleanupLogs, VEHICLES.LOG_CLEANUP_INTERVAL, 0)
