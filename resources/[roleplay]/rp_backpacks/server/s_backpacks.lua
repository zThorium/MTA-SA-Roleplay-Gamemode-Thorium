--[[
    rp_backpacks / s_backpacks.lua

    Una mochila equipada amplia el inventario: su contenido (character_backpack + backpack_items) aparece
    dentro del inventario (tecla I) en slots de otro color, y rp_inventory lo cuenta en hasItem/takeItem/giveItem.
    Se ve en la espalda (client/c_visual.lua, elementData "rp:backpack"). Su peso (vacia + contenido) se publica
    en "rp:packWeight" y rp_hud lo usa para frenar al personaje y gastar mas estamina.
    Tirar la mochila deja en el suelo UN solo objeto-mochila que lleva el contenido dentro; quien la recoja
    (sin otra mochila puesta) se la equipa con todo.

    Comandos:
        /tirarmochila     tira la mochila al suelo con todo lo que lleva dentro
        /mochilaoffset    (admin) x y z rx ry rz: ajusta en vivo la posicion de la mochila en la espalda

    Exports (servidor), usados por rp_inventory:
        getBackpack, getPackWeight, getBackpackInfo, getStoredAmount, getBackpackFree,
        storeInBackpack, takeFromBackpack, equipFromGround, dropBackpack
]]

local state = {}      -- [player] = { cid, id, items = { [itemId] = amount }, loading }
local cooldown = {}

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onItemUse", false)

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

-- Mochila lista (equipada y cargada), o nil
local function active(player)
    local s = state[player]
    if s and s.id and not s.loading and BACKPACKS[s.id] then return s end
end

----------------------------------------------------------------
-- Visual en la espalda, peso publicado y refresco del inventario
----------------------------------------------------------------
-- El objeto se crea en cada cliente (client/c_visual.lua); el servidor solo publica que mochila lleva cada uno.
local function setVisual(player, id)
    if isElement(player) then setElementData(player, "rp:backpack", id or nil, true) end
end

local function refreshInventory(player)
    local res = getResourceFromName("rp_inventory")
    if res and getResourceState(res) == "running" then exports.rp_inventory:refreshInventory(player) end
end

-- Admin: /mochilaoffset x y z rx ry rz  ajusta en vivo como se ve la mochila en todos los clientes
-- (vale hasta reiniciar el recurso; luego copia los valores a BACKPACK_OFFSET en shared/s_config.lua).
addCommandHandler("mochilaoffset", function(player, _, ...)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 1 then return end
    local args = { ... }
    local v = {}
    for i, a in ipairs(args) do v[i] = tonumber(a) end
    if #args ~= 6 then
        return notify(player, "Uso: /mochilaoffset x y z rx ry rz (actual: " .. table.concat(BACKPACK_OFFSET, " ") .. ")", "info")
    end
    for i = 1, 6 do
        if not v[i] then return notify(player, "Todos los valores deben ser numeros.", "error") end
    end
    BACKPACK_OFFSET = v
    triggerClientEvent(root, "rp:bp:offset", resourceRoot, v)
    notify(player, "Offset de mochila actualizado: " .. table.concat(v, " "), "success")
end)

local function sync(player)
    local s = state[player]
    local cfg = s and BACKPACKS[s.id]
    if not cfg then
        setElementData(player, "rp:packWeight", nil)
    else
        setElementData(player, "rp:packWeight", round2(cfg.weight + contentsWeight(s)), true)
    end
    refreshInventory(player)
end

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function getBackpack(player)
    local s = state[player]
    return s and s.id or false
end

function getPackWeight(player)
    return tonumber(getElementData(player, "rp:packWeight")) or 0
end

-- Datos para la interfaz del inventario: { id, name, icon, iconImg, capacity, used, slots, items = { [itemId] = amount } }
function getBackpackInfo(player)
    local s = active(player)
    if not s then return false end
    local cfg, d = BACKPACKS[s.id], def(s.id)
    local items = {}
    for itemId, amount in pairs(s.items) do items[itemId] = amount end
    return {
        id = s.id, name = d and d.name or "Mochila", icon = d and d.icon, iconImg = d and d.iconImg,
        capacity = cfg.capacity, used = contentsWeight(s), slots = cfg.slots or 0, items = items,
    }
end

function getStoredAmount(player, itemId)
    local s = active(player)
    return s and s.items[itemId] or 0
end

-- kg libres dentro de la mochila (0 si no lleva)
function getBackpackFree(player)
    local s = active(player)
    if not s then return 0 end
    return math.max(0, round2(BACKPACKS[s.id].capacity - contentsWeight(s)))
end

-- Guarda items en la mochila SIN tocar el inventario (quien llama ya los quito). -> true | false, motivo
function storeInBackpack(player, itemId, amount)
    local s = active(player)
    amount = tonumber(amount)
    if not s then return false, "No llevas ninguna mochila." end
    if type(itemId) ~= "string" or not amount or amount < 1 or amount ~= math.floor(amount) then return false, "Cantidad no valida." end
    local d = def(itemId)
    if not d or BACKPACKS[itemId] then return false, "Eso no cabe en la mochila." end
    if contentsWeight(s) + d.weight * amount > BACKPACKS[s.id].capacity + 1e-6 then return false, "No cabe en la mochila." end
    s.items[itemId] = (s.items[itemId] or 0) + amount
    dbExec(db(), "INSERT INTO backpack_items (character_id, item_id, amount) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)", s.cid, itemId, amount)
    sync(player)
    return true
end

-- Saca items de la mochila SIN tocar el inventario (quien llama los entrega). -> true | false, motivo
function takeFromBackpack(player, itemId, amount)
    local s = active(player)
    amount = tonumber(amount)
    if not s then return false, "No llevas ninguna mochila." end
    if type(itemId) ~= "string" or not amount or amount < 1 or amount ~= math.floor(amount) then return false, "Cantidad no valida." end
    local have = s.items[itemId] or 0
    if have < amount then return false, "No hay tantos en la mochila." end
    if have == amount then
        s.items[itemId] = nil
        dbExec(db(), "DELETE FROM backpack_items WHERE character_id = ? AND item_id = ?", s.cid, itemId)
    else
        s.items[itemId] = have - amount
        dbExec(db(), "UPDATE backpack_items SET amount = amount - ? WHERE character_id = ? AND item_id = ?", amount, s.cid, itemId)
    end
    sync(player)
    return true
end

----------------------------------------------------------------
-- Carga / descarga
----------------------------------------------------------------
local function unload(player)
    setVisual(player, nil)
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
            setVisual(player, s.id)
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
    for _, player in ipairs(getElementsByType("player")) do setVisual(player, nil) end
end)

----------------------------------------------------------------
-- Equipar y tirar
----------------------------------------------------------------
local function canAct(player)
    return not getElementData(player, "rp:downed") and not isPedDead(player) and not isPedInVehicle(player)
end

-- Equipa una mochila (con contenido opcional) y persiste. Sin comprobar si ya lleva otra.
local function equip(player, cid, itemId, contents)
    state[player] = { cid = cid, id = itemId, items = {} }
    dbExec(db(), "REPLACE INTO character_backpack (character_id, backpack_id) VALUES (?, ?)", cid, itemId)
    dbExec(db(), "DELETE FROM backpack_items WHERE character_id = ?", cid)
    for id, amount in pairs(contents or {}) do
        if def(id) and not BACKPACKS[id] and tonumber(amount) and amount > 0 then
            state[player].items[id] = amount
            dbExec(db(), "INSERT INTO backpack_items (character_id, item_id, amount) VALUES (?, ?, ?)", cid, id, amount)
        end
    end
    setVisual(player, itemId)
    sync(player)
end

addEventHandler("rp:onItemUse", root, function(itemId)
    local player, cfg = source, BACKPACKS[itemId]
    if not cfg or not canAct(player) then return end
    local cid = exports.rp_characters:getPlayerCharacterId(player)
    local s = state[player]
    if not cid or (s and s.loading) then return end
    if s and s.id then return notify(player, "Ya llevas una mochila puesta. Tirala con /tirarmochila.", "warning") end
    if not exports.rp_inventory:takeItem(player, itemId, 1) then return end

    equip(player, cid, itemId, nil)
    notify(player, "Te pones la mochila. Su contenido aparece en tu inventario (tecla I) en otro color.", "success")
end)

-- Export (lo llama rp_inventory al recoger una mochila del suelo que lleva contenido): la equipa con todo.
-- -> true | false, motivo
function equipFromGround(player, itemId, contents)
    if not BACKPACKS[itemId] or type(contents) ~= "table" then return false, "Mochila no valida." end
    local cid = exports.rp_characters:getPlayerCharacterId(player)
    local s = state[player]
    if not cid or (s and s.loading) then return false, "Tu mochila no esta disponible." end
    if s and s.id then return false, "Ya llevas una mochila puesta. Tirala con /tirarmochila antes de recoger esta." end
    equip(player, cid, itemId, contents)
    return true
end

-- Tira la mochila: un solo objeto en el suelo que lleva el contenido dentro.
function dropBackpack(player)
    local s = active(player)
    if not s or not canAct(player) then return false end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local rad = math.rad(rot)
    local contents = {}
    for itemId, amount in pairs(s.items) do contents[itemId] = amount end

    local ok = exports.rp_inventory:spawnGroundItem(s.id, 1, x + math.sin(rad) * 0.8, y + math.cos(rad) * 0.8, z - 0.9,
        getElementDimension(player), getElementInterior(player), contents)
    if not ok then return false end

    dbExec(db(), "DELETE FROM character_backpack WHERE character_id = ?", s.cid)
    dbExec(db(), "DELETE FROM backpack_items WHERE character_id = ?", s.cid)
    state[player] = nil
    setVisual(player, nil)
    setElementData(player, "rp:packWeight", nil)
    refreshInventory(player)
    setPedAnimation(player, "BOMBER", "BOM_Plant", 1200, false, false, false, false, 250)
    notify(player, "Tiras la mochila al suelo con todo lo que llevaba dentro.", "info")
    return true
end

addCommandHandler("tirarmochila", function(player)
    if exports.rp_characters:getPlayerCharacterId(player) and not throttled(player) then dropBackpack(player) end
end)
