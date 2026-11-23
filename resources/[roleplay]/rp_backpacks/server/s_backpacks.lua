--[[
    rp_backpacks / s_backpacks.lua

    Una mochila equipada da un segundo inventario (character_backpack + backpack_items) y se ve en la
    espalda. Su peso (vacia + contenido) se publica en el elementData "rp:packWeight" y rp_hud lo usa
    para frenar al personaje y gastar mas estamina. Tirar la mochila deja en el suelo ella y todo su contenido.

    Comandos:
        /mochila          abre o cierra el contenido de la mochila (tecla O)
        /tirarmochila     tira la mochila al suelo con todo lo que lleva dentro
]]

local state = {}      -- [player] = { cid, id, items = { [itemId] = amount }, loading }
local visuals = {}    -- [player] = objeto en la espalda
local cooldown = {}

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onItemUse", false)
addEvent("rp:bp:request", true)
addEvent("rp:bp:put", true)
addEvent("rp:bp:take", true)
addEvent("rp:bp:drop", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function def(itemId) return exports.rp_inventory:getItemDefinition(itemId) end
local function round2(n) return math.floor(n * 100 + 0.5) / 100 end

local function contentsWeight(s)
    local total = 0
    for itemId, amount in pairs(s.items) do
        local d = def(itemId)
        total = total + (d and d.weight or 0) * amount
    end
    return round2(total)
end

local function throttled(player)
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 300 then return true end
    cooldown[player] = now
    return false
end

----------------------------------------------------------------
-- Visual en la espalda y peso publicado
----------------------------------------------------------------
local function clearVisual(player)
    local obj = visuals[player]
    if isElement(obj) then
        exports.bone_attach:detachElementFromBone(obj)
        destroyElement(obj)
    end
    visuals[player] = nil
end

local function makeVisual(player, cfg)
    clearVisual(player)
    local obj = createObject(cfg.model, 0, 0, 0)
    setObjectScale(obj, cfg.scale)
    setElementCollisionsEnabled(obj, false)
    setElementDimension(obj, getElementDimension(player))
    setElementInterior(obj, getElementInterior(player))
    local o = BACKPACK_OFFSET
    exports.bone_attach:attachElementToBone(obj, player, BACKPACK_BONE, o[1], o[2], o[3], o[4], o[5], o[6])
    visuals[player] = obj
end

-- El objeto no cambia de dimension/interior solo
setTimer(function()
    for player, obj in pairs(visuals) do
        if isElement(player) and isElement(obj) then
            local d, i = getElementDimension(player), getElementInterior(player)
            if getElementDimension(obj) ~= d then setElementDimension(obj, d) end
            if getElementInterior(obj) ~= i then setElementInterior(obj, i) end
        end
    end
end, 1000, 0)

local function payload(player)
    local s = state[player]
    local cfg = s and BACKPACKS[s.id]
    if not cfg then return false end
    local items, inv = {}, {}
    for itemId, amount in pairs(s.items) do
        local d = def(itemId)
        if d then items[#items + 1] = { id = itemId, name = d.name, icon = d.icon, amount = amount, weight = d.weight } end
    end
    for itemId, amount in pairs(exports.rp_inventory:getInventory(player) or {}) do
        local d = def(itemId)
        if d and not BACKPACKS[itemId] then inv[#inv + 1] = { id = itemId, name = d.name, icon = d.icon, amount = amount, weight = d.weight } end
    end
    local byName = function(a, b) return a.name < b.name end
    table.sort(items, byName)
    table.sort(inv, byName)
    local bpDef = def(s.id)
    return { name = bpDef and bpDef.name or "Mochila", capacity = cfg.capacity, used = contentsWeight(s), items = items, inv = inv }
end

local function sync(player)
    local s = state[player]
    local cfg = s and BACKPACKS[s.id]
    if not cfg then
        setElementData(player, "rp:packWeight", nil)
        return
    end
    setElementData(player, "rp:packWeight", round2(cfg.weight + contentsWeight(s)), true)
    triggerClientEvent(player, "rp:bp:update", resourceRoot, payload(player))
end

function getBackpack(player)
    local s = state[player]
    return s and s.id or false
end

function getPackWeight(player)
    return tonumber(getElementData(player, "rp:packWeight")) or 0
end

----------------------------------------------------------------
-- Carga / descarga
----------------------------------------------------------------
local function unload(player)
    clearVisual(player)
    state[player], cooldown[player] = nil, nil
    if isElement(player) then setElementData(player, "rp:packWeight", nil) end
end
addEventHandler("rp:onCharacterLogout", root, function() unload(source) end)
addEventHandler("onPlayerQuit", root, function() unload(source) end)

local function load(player, cid)
    unload(player)
    local s = { cid = cid, items = {}, loading = true }
    state[player] = s
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or state[player] ~= s then return end
        local row = rows[1]
        if not (row and BACKPACKS[row.backpack_id]) then state[player] = nil return end
        s.id = row.backpack_id
        dbQuery(function(qh2)
            local items = dbPoll(qh2, 0) or {}
            if not isElement(player) or state[player] ~= s then return end
            for _, r in ipairs(items) do
                if def(r.item_id) and tonumber(r.amount) > 0 then s.items[r.item_id] = tonumber(r.amount) end
            end
            s.loading = nil
            makeVisual(player, BACKPACKS[s.id])
            sync(player)
        end, db(), "SELECT item_id, amount FROM backpack_items WHERE character_id = ?", cid)
    end, db(), "SELECT backpack_id FROM character_backpack WHERE character_id = ?", cid)
end

addEventHandler("rp:onCharacterSpawn", root, function(cid) load(source, cid) end)
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local cid = exports.rp_characters:getPlayerCharacterId(player)
        if cid then load(player, cid) end
    end
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(visuals) do clearVisual(player) end
end)

----------------------------------------------------------------
-- Equipar (usar el item) y tirar
----------------------------------------------------------------
local function canAct(player)
    return not getElementData(player, "rp:downed") and not isPedDead(player) and not isPedInVehicle(player)
end

addEventHandler("rp:onItemUse", root, function(itemId)
    local player, cfg = source, BACKPACKS[itemId]
    if not cfg or not canAct(player) then return end
    local cid = exports.rp_characters:getPlayerCharacterId(player)
    local s = state[player]
    if not cid or (s and s.loading) then return end
    if s and s.id then return notify(player, "Ya llevas una mochila puesta. Tirala con /tirarmochila.", "warning") end
    if not exports.rp_inventory:takeItem(player, itemId, 1) then return end

    state[player] = { cid = cid, id = itemId, items = {} }
    dbExec(db(), "REPLACE INTO character_backpack (character_id, backpack_id) VALUES (?, ?)", cid, itemId)
    dbExec(db(), "DELETE FROM backpack_items WHERE character_id = ?", cid)
    makeVisual(player, cfg)
    sync(player)
    notify(player, "Te pones la mochila. Abre su contenido con O o /mochila.", "success")
end)

local function dropBackpack(player)
    local s = state[player]
    if not (s and s.id) or s.loading or not canAct(player) then return end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local rad = math.rad(rot)
    local dim, int = getElementDimension(player), getElementInterior(player)
    local n = 0
    local function spot()   -- cada objeto en un punto distinto delante del personaje
        n = n + 1
        local a, r = n * 2.4, 0.8 + 0.15 * math.floor(n / 6)
        return x + math.sin(rad) * 0.8 + math.cos(a) * r * 0.5, y + math.cos(rad) * 0.8 + math.sin(a) * r * 0.5
    end
    for itemId, amount in pairs(s.items) do
        local px, py = spot()
        exports.rp_inventory:spawnGroundItem(itemId, amount, px, py, z - 0.9, dim, int)
    end
    local px, py = spot()
    exports.rp_inventory:spawnGroundItem(s.id, 1, px, py, z - 0.9, dim, int)

    dbExec(db(), "DELETE FROM character_backpack WHERE character_id = ?", s.cid)
    dbExec(db(), "DELETE FROM backpack_items WHERE character_id = ?", s.cid)
    clearVisual(player)
    state[player] = nil
    setElementData(player, "rp:packWeight", nil)
    triggerClientEvent(player, "rp:bp:update", resourceRoot, false)
    setPedAnimation(player, "BOMBER", "BOM_Plant", 1200, false, false, false, false, 250)
    notify(player, "Tiras la mochila y todo su contenido al suelo.", "info")
end

addCommandHandler("tirarmochila", function(player)
    if exports.rp_characters:getPlayerCharacterId(player) and not throttled(player) then dropBackpack(player) end
end)
addEventHandler("rp:bp:drop", resourceRoot, function()
    if not throttled(client) then dropBackpack(client) end
end)

----------------------------------------------------------------
-- Mover items entre inventario y mochila
----------------------------------------------------------------
addEventHandler("rp:bp:request", resourceRoot, function()
    local s = state[client]
    if s and s.id and not s.loading then
        triggerClientEvent(client, "rp:bp:update", resourceRoot, payload(client))
    else
        notify(client, "No llevas ninguna mochila puesta.", "warning")
    end
end)

local function validMove(player, itemId, amount)
    local s = state[player]
    amount = tonumber(amount)
    if not (s and s.id) or s.loading or throttled(player) or not canAct(player) then return end
    if type(itemId) ~= "string" or not amount or amount < 1 or amount ~= math.floor(amount) then return end
    local d = def(itemId)
    if not d or BACKPACKS[itemId] then return end
    return s, d, amount
end

addEventHandler("rp:bp:put", resourceRoot, function(itemId, amount)
    local player = client
    local s, d, n = validMove(player, itemId, amount)
    if not s then return end
    if not exports.rp_inventory:hasItem(player, itemId, n) then return notify(player, "No tienes suficientes.", "error") end
    if contentsWeight(s) + d.weight * n > BACKPACKS[s.id].capacity + 1e-6 then
        return notify(player, "No cabe en la mochila.", "warning")
    end
    if not exports.rp_inventory:takeItem(player, itemId, n) then return end
    s.items[itemId] = (s.items[itemId] or 0) + n
    dbExec(db(), "INSERT INTO backpack_items (character_id, item_id, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)", s.cid, itemId, n)
    sync(player)
end)

addEventHandler("rp:bp:take", resourceRoot, function(itemId, amount)
    local player = client
    local s, _, n = validMove(player, itemId, amount)
    if not s then return end
    local have = s.items[itemId] or 0
    if have < n then return notify(player, "No hay tantos en la mochila.", "error") end
    local ok, reason = exports.rp_inventory:giveItem(player, itemId, n)
    if not ok then return notify(player, reason, "error") end
    if have == n then
        s.items[itemId] = nil
        dbExec(db(), "DELETE FROM backpack_items WHERE character_id = ? AND item_id = ?", s.cid, itemId)
    else
        s.items[itemId] = have - n
        dbExec(db(), "UPDATE backpack_items SET amount = amount - ? WHERE character_id = ? AND item_id = ?", n, s.cid, itemId)
    end
    sync(player)
end)
