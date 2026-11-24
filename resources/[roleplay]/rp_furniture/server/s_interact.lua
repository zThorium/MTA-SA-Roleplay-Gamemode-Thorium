--[[
    rp_furniture / s_interact.lua
    Muebles con funcion (tecla G cerca del mueble):
      sleep    cama: ejecuta /dormir (rp_needs)
      sit      sentarse (G otra vez para levantarse)
      light    enciende/apaga (corona de luz); cualquiera dentro puede usarla
      tv/hifi  enciende/apaga y elige emisora (el cliente reproduce el sonido 3D)
      storage  nevera, armario, caja fuerte: guarda items de rp_inventory (FURN.STORAGE_WEIGHT kg)
      sink     beber agua (+sed); toilet / bath: rol
]]

addEvent("rp:furn:use", true)
addEvent("rp:furn:setStation", true)
addEvent("rp:furn:stPut", true)
addEvent("rp:furn:stTake", true)
addEvent("rp:furn:stClose", true)

local houses, inside = RPF.houses, RPF.inside
local sitting = {}      -- [player] = true
local useTick = {}      -- [player] = tick
local openStorage = {}  -- [player] = fid

local function notify(p, t, k) RPF.notify(p, t, k) end

local function nearFurniture(player, fid)
    local pid = inside[player]
    local h = pid and houses[pid]
    local row = h and h.rows[tonumber(fid)]
    local obj = row and h.objs[row.id]
    if not row or not isElement(obj) then return end
    if getElementDimension(player) ~= RPF.dimOf(pid) then return end
    local px, py, pz = getElementPosition(player)
    local ox, oy, oz = getElementPosition(obj)
    -- la distancia se mide al centro del mueble (los grandes tienen el origen lejos del borde)
    if getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz) > FURN.USE_DISTANCE + 1.2 * math.max(row.sx, row.sy) then return end
    return h, row, obj, FURN_ITEMS[row.item_key], pid
end

local function saveState(h, row)
    row.state = RPF.encodeState(row.stateT)
    dbExec(RPF.db(), "UPDATE property_furniture SET state = ? WHERE id = ?", row.state, row.id)
    local obj = h.objs[row.id]
    if isElement(obj) then setElementData(obj, "rp:furn", RPF.publicData(row, row.stateT)) end
    RPF.updateLight(h, row.id)
end

local function standUp(player)
    if not sitting[player] then return end
    sitting[player] = nil
    if isElement(player) then
        setPedAnimation(player)
        setElementFrozen(player, false)
    end
end

local function storageContents(fid, cb)
    dbQuery(function(q)
        local list, weight = {}, 0
        for _, r in ipairs(dbPoll(q, 0) or {}) do
            local def = exports.rp_inventory:getItemDefinition(r.item_id)
            local amount = tonumber(r.amount) or 0
            if def and amount > 0 then
                list[#list + 1] = { id = r.item_id, name = def.name, icon = def.icon, amount = amount, weight = def.weight }
                weight = weight + def.weight * amount
            end
        end
        cb(list, weight)
    end, RPF.db(), "SELECT item_id, amount FROM furniture_storage WHERE furniture_id = ?", fid)
end

local function sendStorage(player, fid, title)
    storageContents(fid, function(list, weight)
        if not isElement(player) then return end
        local mine = {}
        for id, amount in pairs(exports.rp_inventory:getInventory(player) or {}) do
            local def = exports.rp_inventory:getItemDefinition(id)
            if def and amount > 0 and not (def.use and def.use.event == "backpack") then
                mine[#mine + 1] = { id = id, name = def.name, icon = def.icon, amount = amount, weight = def.weight }
            end
        end
        triggerClientEvent(player, "rp:furn:storage", resourceRoot, { fid = fid, title = title, items = list, mine = mine, weight = weight, cap = FURN.STORAGE_WEIGHT })
    end)
end

addEventHandler("rp:furn:use", resourceRoot, function(fid)
    local player = client
    if not RPF.cidOf(player) then return end
    local now = getTickCount()
    if useTick[player] and now - useTick[player] < 500 then return end
    useTick[player] = now
    if sitting[player] then return standUp(player) end
    if getElementData(player, "rp:downed") or isPedDead(player) then return end

    local h, row, obj, def, pid = nearFurniture(player, fid)
    if not h or not def or not def.act then return end

    local act = def.act
    if act == "sleep" then
        executeCommandHandler("dormir", player)
    elseif act == "sit" then
        local ox, oy, oz = getElementPosition(obj)
        local _, _, rz = getElementRotation(obj)
        setElementPosition(player, ox, oy, oz + 0.75 * math.max(0.6, row.sz))
        setElementRotation(player, 0, 0, rz)
        setElementFrozen(player, true)
        setPedAnimation(player, "ped", "SEAT_idle", -1, true, false, false, true)
        sitting[player] = true
        notify(player, "Pulsa G para levantarte.", "info")
    elseif act == "light" or act == "tv" or act == "hifi" then
        row.stateT.on = not row.stateT.on or nil
        if act ~= "light" and row.stateT.on and not row.stateT.st then row.stateT.st = FURN_STATIONS[1].id end
        saveState(h, row)
        notify(player, row.stateT.on and "Encendido." or "Apagado.", "info")
    elseif act == "storage" then
        openStorage[player] = row.id
        sendStorage(player, row.id, def.name)
    elseif act == "sink" then
        exports.rp_needs:addNeed(player, "thirst", 15)
        notify(player, "Bebes un poco de agua del grifo.", "info")
    elseif act == "toilet" then
        notify(player, "Usas el bano. /me para rolearlo.", "info")
    elseif act == "bath" then
        notify(player, "Te das una ducha. /me para rolearlo.", "info")
    end
end)

addEventHandler("rp:furn:setStation", resourceRoot, function(fid, stationId)
    local player = client
    local h, row, obj, def = nearFurniture(player, fid)
    stationId = tonumber(stationId)
    if not h or not def or (def.act ~= "tv" and def.act ~= "hifi") or not FURN_STATION_BY_ID[stationId] then return end
    row.stateT.st, row.stateT.on = stationId, true
    saveState(h, row)
end)

local function validStorage(player, fid)
    if openStorage[player] ~= tonumber(fid) then return end
    local h, row, obj, def = nearFurniture(player, fid)
    if not h or def.act ~= "storage" then return end
    return row, def
end

addEventHandler("rp:furn:stPut", resourceRoot, function(fid, itemId, amount)
    local player = client
    amount = math.floor(tonumber(amount) or 0)
    if type(itemId) ~= "string" or amount < 1 or amount > 999 then return end
    if not validStorage(player, fid) then return end
    local def = exports.rp_inventory:getItemDefinition(itemId)
    if not def or (def.use and def.use.event == "backpack") or not exports.rp_inventory:hasItem(player, itemId, amount) then return end
    storageContents(fid, function(_, weight)
        if not isElement(player) or openStorage[player] ~= tonumber(fid) then return end
        if weight + def.weight * amount > FURN.STORAGE_WEIGHT + 1e-6 then return notify(player, "No cabe mas en este mueble.", "warning") end
        local ok = exports.rp_inventory:takeItem(player, itemId, amount)
        if not ok then return end
        dbQuery(function(q)
            local res = dbPoll(q, 0)
            if res == false or res == nil then exports.rp_inventory:giveItem(player, itemId, amount) return end
            sendStorage(player, tonumber(fid), (FURN_ITEMS[houses[inside[player]].rows[tonumber(fid)].item_key] or {}).name)
        end, RPF.db(), "INSERT INTO furniture_storage (furniture_id, item_id, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + ?",
            tonumber(fid), itemId, amount, amount)
    end)
end)

addEventHandler("rp:furn:stTake", resourceRoot, function(fid, itemId, amount)
    local player = client
    amount = math.floor(tonumber(amount) or 0)
    if type(itemId) ~= "string" or amount < 1 or amount > 999 then return end
    if not validStorage(player, fid) then return end
    local can = exports.rp_inventory:canCarry(player, itemId, amount)
    if not can then return notify(player, "No puedes cargar tanto.", "warning") end
    dbQuery(function(q)
        local _, affected = dbPoll(q, 0)
        if not isElement(player) or not affected or affected == 0 then return end
        exports.rp_inventory:giveItem(player, itemId, amount)
        dbExec(RPF.db(), "DELETE FROM furniture_storage WHERE furniture_id = ? AND amount = 0", tonumber(fid))
        sendStorage(player, tonumber(fid), (FURN_ITEMS[houses[inside[player]].rows[tonumber(fid)].item_key] or {}).name)
    end, RPF.db(), "UPDATE furniture_storage SET amount = amount - ? WHERE furniture_id = ? AND item_id = ? AND amount >= ?", amount, tonumber(fid), itemId, amount)
end)

addEventHandler("rp:furn:stClose", resourceRoot, function() openStorage[client] = nil end)

addEventHandler("onPlayerQuit", root, function() sitting[source], useTick[source], openStorage[source] = nil, nil, nil end)
addEventHandler("onPlayerWasted", root, function() sitting[source] = nil end)
