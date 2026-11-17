--[[
    rp_inventory / s_inventory.lua
    Inventario del personaje activo. Se carga desde SQL al entrar al juego y
    cada cambio se guarda inmediatamente en character_items.

    Exports (servidor):
        giveItem(player, itemId, amount)  -> true | false, motivo
        takeItem(player, itemId, amount)  -> true | false, motivo
        hasItem(player, itemId, amount)   -> bool
        getItemAmount(player, itemId)     -> number
        getInventory(player)              -> { [itemId] = amount }
        getInventoryWeight(player)        -> kg
        canCarry(player, itemId, amount)  -> true | false, motivo
]]

local inventories = {}   -- [player] = { characterId = n, items = { [itemId] = amount } }
local cooldown = {}      -- [player] = tick del ultimo uso (anti spam)

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:inv:request", true)
addEvent("rp:inv:use", true)
addEvent("rp:inv:drop", true)
addEvent("rp:onItemUse", false)   -- source = jugador, (itemId)

local function db()
    return exports.rp_database:getConnection()
end

local function notify(player, text, kind)
    exports.rp_notify:notify(player, text, kind)
end

----------------------------------------------------------------
-- Envio al cliente
----------------------------------------------------------------
local function serialize(player)
    local inv = inventories[player]
    local list = {}
    if inv then
        for itemId, amount in pairs(inv.items) do
            local def = getItemDefinition(itemId)
            if def then
                local note = getItemPrivateNote(itemId, inv.characterId)
                list[#list + 1] = {
                    id = itemId, name = def.name, icon = def.icon,
                    description = note and ((def.description or "") .. " " .. note) or def.description,
                    amount = amount, weight = def.weight, usable = def.use ~= nil,
                }
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
    end
    return list
end

function sendInventory(player)
    if not isElement(player) then return end
    triggerClientEvent(player, "rp:inv:update", resourceRoot, serialize(player), getInventoryWeight(player), INVENTORY.MAX_WEIGHT)
end

----------------------------------------------------------------
-- Carga y descarga
----------------------------------------------------------------
local function loadInventory(player, characterId)
    inventories[player] = { characterId = characterId, items = {}, loading = true }
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local inv = inventories[player]
        if not isElement(player) or not inv or inv.characterId ~= characterId then return end
        for _, row in ipairs(rows) do
            if getItemDefinition(row.item_id) and tonumber(row.amount) > 0 then
                inv.items[row.item_id] = tonumber(row.amount)
            end
        end
        inv.loading = nil
        sendInventory(player)
    end, db(), "SELECT item_id, amount FROM character_items WHERE character_id = ?", characterId)
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    loadInventory(source, characterId)
end)

-- Si el recurso se reinicia con jugadores dentro, recarga sus inventarios
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local characterId = exports.rp_characters:getPlayerCharacterId(player)
        if characterId then loadInventory(player, characterId) end
    end
end)

local function unload(player)
    inventories[player], cooldown[player] = nil, nil
end
addEventHandler("rp:onCharacterLogout", root, function() unload(source) end)
addEventHandler("onPlayerQuit", root, function() unload(source) end)

----------------------------------------------------------------
-- API
----------------------------------------------------------------
local function validAmount(amount)
    return type(amount) == "number" and amount >= 1 and amount == math.floor(amount)
end

function getInventory(player)
    local inv = inventories[player]
    if not inv then return false end
    local copy = {}
    for k, v in pairs(inv.items) do copy[k] = v end
    return copy
end

function getItemAmount(player, itemId)
    local inv = inventories[player]
    return inv and inv.items[itemId] or 0
end

function hasItem(player, itemId, amount)
    return getItemAmount(player, itemId) >= (tonumber(amount) or 1)
end

function getInventoryWeight(player)
    local inv = inventories[player]
    if not inv then return 0 end
    local total = 0
    for itemId, amount in pairs(inv.items) do
        total = total + (getItemDefinition(itemId) and getItemDefinition(itemId).weight or 0) * amount
    end
    return math.floor(total * 100 + 0.5) / 100
end

function canCarry(player, itemId, amount)
    amount = tonumber(amount) or 1
    local inv, def = inventories[player], getItemDefinition(itemId)
    if not inv or inv.loading then return false, "Tu inventario no esta disponible." end
    if not def then return false, "Item desconocido." end
    if not validAmount(amount) then return false, "Cantidad no valida." end
    if (inv.items[itemId] or 0) + amount > def.stack then
        return false, ("Solo puedes llevar %d de %s."):format(def.stack, def.name)
    end
    if getInventoryWeight(player) + def.weight * amount > INVENTORY.MAX_WEIGHT + 1e-6 then
        return false, "No tienes espacio suficiente en tu inventario."
    end
    return true
end

function giveItem(player, itemId, amount)
    amount = tonumber(amount) or 1
    local ok, reason = canCarry(player, itemId, amount)
    if not ok then return false, reason end

    local inv = inventories[player]
    inv.items[itemId] = (inv.items[itemId] or 0) + amount
    dbExec(db(), [[
        INSERT INTO character_items (character_id, item_id, amount) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]], inv.characterId, itemId, amount)
    sendInventory(player)
    return true
end

function takeItem(player, itemId, amount)
    amount = tonumber(amount) or 1
    local inv = inventories[player]
    if not inv or inv.loading then return false, "Tu inventario no esta disponible." end
    if not validAmount(amount) then return false, "Cantidad no valida." end
    local current = inv.items[itemId] or 0
    if current < amount then return false, "No tienes suficientes." end

    if current == amount then
        inv.items[itemId] = nil
        dbExec(db(), "DELETE FROM character_items WHERE character_id = ? AND item_id = ?", inv.characterId, itemId)
    else
        inv.items[itemId] = current - amount
        dbExec(db(), "UPDATE character_items SET amount = amount - ? WHERE character_id = ? AND item_id = ?", amount, inv.characterId, itemId)
    end
    sendInventory(player)
    return true
end

----------------------------------------------------------------
-- Acciones desde la interfaz
----------------------------------------------------------------
local function throttled(player)
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 500 then return true end
    cooldown[player] = now
    return false
end

addEventHandler("rp:inv:request", resourceRoot, function()
    if inventories[client] then sendInventory(client) end
end)

addEventHandler("rp:inv:use", resourceRoot, function(itemId)
    local player = client
    if throttled(player) or type(itemId) ~= "string" then return end
    local def = getItemDefinition(itemId)
    if not def or not def.use then return notify(player, "Ese objeto no se puede usar.", "warning") end
    if not hasItem(player, itemId, 1) then return notify(player, "No tienes ese objeto.", "error") end
    if isPedDead(player) then return end

    local effect = def.use
    -- Items con logica propia en otro recurso (p. ej. el telefono)
    if effect.event then
        triggerEvent("rp:onItemUse", player, itemId)
        return
    end
    if effect.armor and getPedArmor(player) >= effect.armor then
        return notify(player, "Ya llevas un chaleco puesto.", "warning")
    end
    -- Comida y bebida: solo si se necesita (alguna necesidad por debajo de 95)
    local needsUsed = false
    for _, need in ipairs({ "hunger", "thirst", "energy" }) do
        if (effect[need] or 0) > 0 then
            needsUsed = true
            local current = exports.rp_needs:getNeed(player, need)
            if current and current < 95 then needsUsed = "useful" end
        end
    end
    if needsUsed == true then
        return notify(player, "Ahora mismo no lo necesitas.", "warning")
    end
    if not needsUsed and not effect.armor and effect.health and getElementHealth(player) >= 100 then
        return notify(player, "Tu salud ya esta al maximo.", "warning")
    end

    if def.consumable then takeItem(player, itemId, 1) end
    if effect.health then setElementHealth(player, math.min(100, getElementHealth(player) + effect.health)) end
    if effect.armor then setPedArmor(player, effect.armor) end
    for _, need in ipairs({ "hunger", "thirst", "energy" }) do
        if effect[need] then exports.rp_needs:addNeed(player, need, effect[need]) end
    end
    notify(player, effect.message or ("Usas " .. def.name .. "."), "success")
end)

addEventHandler("rp:inv:drop", resourceRoot, function(itemId, amount)
    local player = client
    if throttled(player) or type(itemId) ~= "string" then return end
    amount = tonumber(amount) or 1
    local def = getItemDefinition(itemId)
    if not def then return end
    local ok, reason = takeItem(player, itemId, amount)
    if ok then
        notify(player, ("Tiraste %d x %s."):format(amount, def.name), "info")
    else
        notify(player, reason, "error")
    end
end)
