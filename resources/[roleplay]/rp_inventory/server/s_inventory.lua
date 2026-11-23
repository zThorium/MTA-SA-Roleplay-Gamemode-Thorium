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
addEvent("rp:onDrugUsed", false)   -- lo escucha rp_dealers; se registra aqui para que el trigger no falle sin ese recurso
addEvent("rp:inv:drop", true)
addEvent("rp:onItemUse", false)   -- source = jugador, (itemId)

local methTimers = {}   -- [player] = timer que apaga el efecto de la metanfetamina

local function clearMeth(player)
    if isTimer(methTimers[player]) then killTimer(methTimers[player]) end
    methTimers[player] = nil
    if isElement(player) then setElementData(player, "rp:meth", false) end
end
addEventHandler("rp:onCharacterLogout", root, function() clearMeth(source) end)
addEventHandler("onPlayerQuit", root, function() clearMeth(source) end)

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

-- Animacion + objeto en la mano izquierda (hueso 11 de bone_attach): las animaciones de GTA comen/beben con esa mano.
-- shortcut: modelos y offsets a ojo; ajustar en juego si el objeto se ve mal colocado.
local PROP_MS = 3500
local FOOD_ANIM  = { "FOOD", "EAT_Burger", 12 }        -- comer: mano derecha
local DRINK_ANIM = { "VENDING", "VEND_Drink2_P", 11 }  -- beber: mano izquierda
local consumeProps = {   -- [itemId] = { modelo, anim, x, y, z, rx, ry, rz }
    water    = { 1484, DRINK_ANIM, 0.05, 0.02, 0.1, 0, 90, 0 },
    coffee   = { 1546, DRINK_ANIM, 0.05, 0.02, 0.1, 0, 0, 0 },
    sandwich = { 2880, FOOD_ANIM, 0.05, -0.03, 0.1, 0, -180, 0 },
    burger   = { 2880, FOOD_ANIM, 0.06, -0.01, 0.1, 0, -180, 0 },
}
local propObjects, propTimers = {}, {}

local function clearProp(player)
    if isTimer(propTimers[player]) then killTimer(propTimers[player]) end
    local obj = propObjects[player]
    if isElement(obj) then
        exports.bone_attach:detachElementFromBone(obj)
        destroyElement(obj)
    end
    propObjects[player], propTimers[player] = nil, nil
end
addEventHandler("onPlayerQuit", root, function() clearProp(source) end)

local function playConsumeProp(player, itemId)
    local p = consumeProps[itemId]
    if not p or isPedInVehicle(player) then return end
    clearProp(player)
    local obj = createObject(p[1], 0, 0, 0)
    setElementCollisionsEnabled(obj, false)
    setElementDimension(obj, getElementDimension(player))
    setElementInterior(obj, getElementInterior(player))
    exports.bone_attach:attachElementToBone(obj, player, p[2][3], p[3], p[4], p[5], p[6], p[7], p[8])
    propObjects[player] = obj
    setPedAnimation(player, p[2][1], p[2][2], PROP_MS, false, false, false, false, 250)
    propTimers[player] = setTimer(clearProp, PROP_MS, 1, player)
end

addEventHandler("rp:inv:use", resourceRoot, function(itemId)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
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
    if effect.meth then
        if isTimer(methTimers[player]) then killTimer(methTimers[player]) end   -- volver a consumir reinicia el minuto
        setElementData(player, "rp:meth", true)
        methTimers[player] = setTimer(clearMeth, effect.meth * 1000, 1, player)
    end
    for _, need in ipairs({ "hunger", "thirst", "energy" }) do
        if effect[need] then exports.rp_needs:addNeed(player, need, effect[need]) end
    end
    playConsumeProp(player, itemId)
    notify(player, effect.message or ("Usas " .. def.name .. "."), "success")
    if effect.drug then triggerEvent("rp:onDrugUsed", player, effect.drug) end   -- rp_dealers aplica el efecto
end)

----------------------------------------------------------------
-- Items en el suelo (objetos visibles para todos) y entrega a jugadores
-- shortcut: el suelo vive solo en memoria (se pierde al reiniciar el recurso), pasar a tabla SQL si hace falta persistir
----------------------------------------------------------------
local DROP_RANGE, GIVE_RANGE, PICK_RANGE = 4, 3, 3
local GROUND_LIFETIME = 30 * 60 * 1000
local ground = {}   -- [objeto] = { itemId, amount }

local function setAme(player, text)
    local res = getResourceFromName("rp_nametags")
    if res and getResourceState(res) == "running" then exports.rp_nametags:setAme(player, text, 4500) end
end

local function distanceTo(player, x, y, z)
    local px, py, pz = getElementPosition(player)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z)
end

local function sameWorld(a, b)
    return getElementDimension(a) == getElementDimension(b) and getElementInterior(a) == getElementInterior(b)
end

local function canAct(player)
    return not getElementData(player, "rp:downed") and not isPedDead(player) and not isPedInVehicle(player)
end

local function dropAt(player, itemId, amount, x, y, z)
    local def = getItemDefinition(itemId)
    if not def then return end
    if def.document then return notify(player, "No puedes tirar documentos.", "warning") end
    if not validAmount(amount) then return end
    if distanceTo(player, x, y, z) > DROP_RANGE or math.abs(z - select(3, getElementPosition(player))) > 3 then
        return notify(player, "Ese lugar queda demasiado lejos.", "warning")
    end
    local ok, reason = takeItem(player, itemId, amount)
    if not ok then return notify(player, reason, "error") end

    local model, scale = getItemGroundModel(itemId)
    local object = createObject(model, x, y, z + 0.1)
    setObjectScale(object, scale)
    setElementCollisionsEnabled(object, false)
    setElementDimension(object, getElementDimension(player))
    setElementInterior(object, getElementInterior(player))
    setElementData(object, "rp:ground", { name = def.name, icon = def.icon, amount = amount })
    ground[object] = { itemId = itemId, amount = amount }
    setTimer(function()
        if isElement(object) then ground[object] = nil; destroyElement(object) end
    end, GROUND_LIFETIME, 1)

    setPedAnimation(player, "BOMBER", "BOM_Plant", 1200, false, false, false, false, 250)
    setAme(player, ("deja %s en el suelo"):format(def.name:lower()))
    notify(player, ("Dejaste %d x %s en el suelo."):format(amount, def.name), "info")
end

-- Boton "Tirar" (sin arrastrar): lo deja delante del personaje
addEventHandler("rp:inv:drop", resourceRoot, function(itemId, amount)
    local player = client
    if not canAct(player) or throttled(player) or type(itemId) ~= "string" then return end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local rad = math.rad(rot)
    dropAt(player, itemId, tonumber(amount) or 1, x + math.sin(rad) * 0.8, y + math.cos(rad) * 0.8, z - 0.9)
end)

addEvent("rp:inv:dropAt", true)
addEventHandler("rp:inv:dropAt", resourceRoot, function(itemId, amount, x, y, z)
    local player = client
    if not canAct(player) or throttled(player) or type(itemId) ~= "string" then return end
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end
    dropAt(player, itemId, tonumber(amount) or 1, x, y, z)
end)

addEvent("rp:inv:pickup", true)
addEventHandler("rp:inv:pickup", resourceRoot, function(object)
    local player = client
    if not canAct(player) or throttled(player) then return end
    local entry = isElement(object) and ground[object]
    if not entry then return end
    local x, y, z = getElementPosition(object)
    if not sameWorld(player, object) or distanceTo(player, x, y, z) > PICK_RANGE then return end

    local def = getItemDefinition(entry.itemId)
    local ok, reason = canCarry(player, entry.itemId, entry.amount)
    if not ok then return notify(player, reason, "error") end

    ground[object] = nil
    destroyElement(object)
    giveItem(player, entry.itemId, entry.amount)
    setPedAnimation(player, "CARRY", "liftup", 800, false, false, false, false, 250)
    setAme(player, ("recoge %s del suelo"):format(def.name:lower()))
    notify(player, ("Recogiste %d x %s."):format(entry.amount, def.name), "success")
end)

addEvent("rp:inv:give", true)
addEventHandler("rp:inv:give", resourceRoot, function(itemId, amount, targetId)
    local player = client
    if not canAct(player) or throttled(player) or type(itemId) ~= "string" then return end
    amount, targetId = tonumber(amount) or 1, tonumber(targetId)
    local def = getItemDefinition(itemId)
    if not def or not targetId or not validAmount(amount) then return end

    local target
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= player and getElementData(p, "id") == targetId and getElementData(p, "rp:characterId") then target = p end
    end
    local x, y, z = getElementPosition(player)
    if not target or isPedDead(target) or not sameWorld(player, target) or distanceTo(target, x, y, z) > GIVE_RANGE then
        return notify(player, "Esa persona no esta cerca de ti.", "warning")
    end
    if not hasItem(player, itemId, amount) then return notify(player, "No tienes suficientes.", "error") end
    local ok, reason = canCarry(target, itemId, amount)
    if not ok then return notify(player, "No puede cargar eso: " .. reason, "error") end

    takeItem(player, itemId, amount)
    if not giveItem(target, itemId, amount) then giveItem(player, itemId, amount) return end   -- reembolso
    local giver, receiver = getPlayerName(player):gsub("_", " "), getPlayerName(target):gsub("_", " ")
    setPedAnimation(player, "DEALER", "DEALER_DEAL", 1500, false, false, false, false, 250)
    setAme(player, ("entrega %s a %s"):format(def.name:lower(), receiver))
    notify(player, ("Entregaste %d x %s a %s."):format(amount, def.name, receiver), "success")
    notify(target, ("%s te entrego %d x %s."):format(giver, amount, def.name), "success")
end)
