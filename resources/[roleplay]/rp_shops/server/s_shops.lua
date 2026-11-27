--[[
    rp_shops / s_shops.lua
    Tiendas con NPC guardadas en SQL (tablas shops y shop_items). Al acercarse
    el NPC saluda con un globo; con E se abre el catalogo y lo comprado va al
    inventario del personaje (rp_inventory) descontando el dinero.

    Comandos de administracion (admin_level >= 1 en la tabla accounts):
        /crearshop <nombre>   crea una tienda en tu posicion con el catalogo por defecto
        /borrarshop <id>      elimina una tienda
]]

local INTERACT_RADIUS = 2.5
local MAX_QUANTITY = 10

-- Catalogo con el que se crean las tiendas nuevas (item -> precio)
local DEFAULT_CATALOG = {
    water = 5, coffee = 8, sandwich = 12, burger = 18, cigarettes = 15,
    lighter = 5, medkit = 150, phone = 250, vest = 400,
}

-- Tienda inicial junto al punto de aparicion (estacion Unity)
local DEFAULT_SHOP = { name = "Tienda 24/7 Unity", skin = 211, x = 1746.5, y = -1858.6, z = 13.58, rot = 90 }

local shops = {}     -- [id] = { row, items = { [itemId] = price }, ped, col, blip }
local nearby = {}    -- [player] = shopId
local cooldown = {}  -- [player] = tick

addEvent("rp:shop:open", true)
addEvent("rp:shop:buy", true)
addEvent("rp:shop:onBought", false)   -- aviso a otros recursos (rp_dealers): source = jugador

local function db()
    return exports.rp_database:getConnection()
end

local function notify(player, text, kind)
    exports.rp_notify:notify(player, text, kind)
end

----------------------------------------------------------------
-- Elementos del mundo
----------------------------------------------------------------
local function destroyShop(id)
    local shop = shops[id]
    if not shop then return end
    for _, el in ipairs({ shop.ped, shop.col, shop.blip }) do
        if isElement(el) then destroyElement(el) end
    end
    shops[id] = nil
end

local function spawnShop(row, items)
    local id = tonumber(row.id)
    destroyShop(id)

    local ped = createPed(tonumber(row.ped_skin), row.x, row.y, row.z, row.rotation)
    if not ped then
        outputDebugString("[rp_shops] No se pudo crear el NPC de la tienda #" .. id, 2)
        return
    end
    setElementFrozen(ped, true)
    setElementInterior(ped, row.interior)
    setElementDimension(ped, row.dimension)
    setElementData(ped, "rp:shopId", id)
    setElementData(ped, "rp:shopName", row.name)

    local col = createColSphere(row.x, row.y, row.z, INTERACT_RADIUS)
    setElementInterior(col, row.interior)
    setElementDimension(col, row.dimension)
    attachElements(col, ped)   -- la esfera sigue al NPC si otro recurso lo mueve

    local blip = createBlipAttachedTo(ped, 52, 2, 255, 255, 255, 255, 0, 250)

    shops[id] = { row = row, items = items or {}, ped = ped, col = col, blip = blip }

    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim then return end
        if not exports.rp_characters:getPlayerCharacterId(el) then return end
        nearby[el] = id
        exports.rp_notify:bubble(el, ped, "Hola! Pulsa E para ver lo que tengo.", 4500)
        triggerClientEvent(el, "rp:shop:near", resourceRoot, id, row.name)
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and nearby[el] == id then
            nearby[el] = nil
            triggerClientEvent(el, "rp:shop:near", resourceRoot, false)
        end
    end)
end

local function loadShops()
    -- Items agregados despues de crear la tienda inicial (idempotente)
    dbExec(db(), "INSERT IGNORE INTO shop_items (shop_id, item_id, price) SELECT id, ?, ? FROM shops WHERE id = 1", "coffee", DEFAULT_CATALOG.coffee)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then
            -- Base de datos vacia: crea la tienda inicial
            return createShop(DEFAULT_SHOP.name, DEFAULT_SHOP.skin, DEFAULT_SHOP.x, DEFAULT_SHOP.y, DEFAULT_SHOP.z, DEFAULT_SHOP.rot, 0, 0)
        end
        dbQuery(function(qh2)
            local itemRows = dbPoll(qh2, 0) or {}
            local byShop = {}
            for _, r in ipairs(itemRows) do
                local sid = tonumber(r.shop_id)
                byShop[sid] = byShop[sid] or {}
                byShop[sid][r.item_id] = tonumber(r.price)
            end
            for _, row in ipairs(rows) do
                spawnShop(row, byShop[tonumber(row.id)])
            end
            outputDebugString(("[rp_shops] %d tiendas cargadas"):format(#rows))
        end, db(), "SELECT shop_id, item_id, price FROM shop_items")
    end, db(), "SELECT * FROM shops")
end

-- Crea una tienda en SQL con el catalogo por defecto y la pone en el mundo
function createShop(name, skin, x, y, z, rot, interior, dimension, callback)
    dbQuery(function(qh)
        local result, _, shopId = dbPoll(qh, 0)
        if not result then
            outputDebugString("[rp_shops] Error al crear la tienda " .. tostring(name), 1)
            if callback then callback(false) end
            return
        end
        for itemId, price in pairs(DEFAULT_CATALOG) do
            dbExec(db(), "INSERT INTO shop_items (shop_id, item_id, price) VALUES (?, ?, ?)", shopId, itemId, price)
        end
        local items = {}
        for k, v in pairs(DEFAULT_CATALOG) do items[k] = v end
        spawnShop({ id = shopId, name = name, ped_skin = skin, x = x, y = y, z = z, rotation = rot, interior = interior, dimension = dimension }, items)
        if callback then callback(shopId) end
    end, db(), "INSERT INTO shops (name, ped_skin, x, y, z, rotation, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        name, skin, x, y, z, rot, interior, dimension)
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then
        loadShops()
    else
        addEventHandler("rp:onDatabaseReady", root, loadShops)
    end
end)
addEvent("rp:onDatabaseReady", false)

addEventHandler("onPlayerQuit", root, function()
    nearby[source], cooldown[source] = nil, nil
end)

----------------------------------------------------------------
-- Compra
----------------------------------------------------------------
-- Cerca del vendedor: dentro de la esfera de la tienda (la misma que enciende el "Pulsa E" en el
-- cliente) o a menos de INTERACT_RADIUS + 1.5 m del NPC en planta. La altura se tolera aparte:
-- NPC creados un poco por encima del suelo (eventos, puntos de admin) no deben rechazar la compra.
local function isNear(player, shopId)
    local shop = shops[shopId]
    if not shop or not isElement(shop.ped) then return false end
    if getElementDimension(player) ~= getElementDimension(shop.ped) or getElementInterior(player) ~= getElementInterior(shop.ped) then
        outputDebugString(("[rp_shops] %s lejos de la tienda #%s: dim/int %d/%d vs NPC %d/%d"):format(getPlayerName(player), tostring(shopId),
            getElementDimension(player), getElementInterior(player), getElementDimension(shop.ped), getElementInterior(shop.ped)), 3)
        return false
    end
    if isElement(shop.col) and isElementWithinColShape(player, shop.col) then return true end
    local px, py, pz = getElementPosition(player)
    local sx, sy, sz = getElementPosition(shop.ped)
    local flat = getDistanceBetweenPoints2D(px, py, sx, sy)
    if flat <= INTERACT_RADIUS + 1.5 and math.abs(pz - sz) <= 3 then return true end
    outputDebugString(("[rp_shops] %s lejos de la tienda #%s: %.1f m en planta, %.1f m de altura"):format(
        getPlayerName(player), tostring(shopId), flat, pz - sz), 3)
    return false
end

local function catalogFor(shopId)
    local list = {}
    for itemId, price in pairs(shops[shopId].items) do
        local def = exports.rp_inventory:getItemDefinition(itemId)
        if def then
            local lot = def.lot or 1   -- def.lot: el precio es por lote (p. ej. municion x30)
            list[#list + 1] = { id = itemId, name = lot > 1 and ("%s (x%d)"):format(def.name, lot) or def.name, icon = def.icon, description = def.description, weight = def.weight * lot, price = price }
        end
    end
    table.sort(list, function(a, b) return a.price < b.price end)
    return list
end

addEventHandler("rp:shop:open", resourceRoot, function(shopId)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    shopId = tonumber(shopId)
    if not shopId or not exports.rp_characters:getPlayerCharacterId(player) then return end
    if not isNear(player, shopId) then return notify(player, "Estas demasiado lejos del vendedor.", "warning") end
    triggerClientEvent(player, "rp:shop:show", resourceRoot, shopId, shops[shopId].row.name, catalogFor(shopId), getPlayerMoney(player))
end)

addEventHandler("rp:shop:buy", resourceRoot, function(shopId, itemId, quantity)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    shopId, quantity = tonumber(shopId), tonumber(quantity)
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 400 then return end
    cooldown[player] = now

    if not shopId or type(itemId) ~= "string" or not quantity then return end
    if quantity < 1 or quantity > MAX_QUANTITY or quantity ~= math.floor(quantity) then return end
    if not exports.rp_characters:getPlayerCharacterId(player) then return end
    if not isNear(player, shopId) then return notify(player, "Estas demasiado lejos del vendedor.", "warning") end

    local price = shops[shopId].items[itemId]
    local def = exports.rp_inventory:getItemDefinition(itemId)
    if not price or not def then return notify(player, "Este vendedor no tiene ese articulo.", "error") end

    local total = price * quantity
    if getPlayerMoney(player) < total then
        return notify(player, ("No tienes suficiente dinero. Necesitas $%d."):format(total), "error")
    end

    local units = quantity * (def.lot or 1)
    local canCarry, reason = exports.rp_inventory:canCarry(player, itemId, units)
    if not canCarry then return notify(player, reason, "error") end

    local given = exports.rp_inventory:giveItem(player, itemId, units)
    if not given then return notify(player, "No se pudo completar la compra.", "error") end

    takePlayerMoney(player, total)
    exports.rp_characters:saveCharacter(player)   -- guarda el dinero al momento
    triggerEvent("rp:shop:onBought", player, shopId, itemId, quantity)
    notify(player, ("Compraste %d x %s por $%d."):format(quantity, def.name, total), "success")
    triggerClientEvent(player, "rp:shop:money", resourceRoot, getPlayerMoney(player))
end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
local function isAdmin(player)
    return (exports.rp_login:getPlayerAdminLevel(player) or 0) >= 1
end

addCommandHandler("crearshop", function(player, _, ...)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local name = table.concat({ ... }, " ")
    if #name < 3 or #name > 48 then return notify(player, "Uso: /crearshop <nombre de la tienda>", "warning") end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    createShop(name, 211, x, y, z, rot, getElementInterior(player), getElementDimension(player), function(id)
        if id and isElement(player) then
            -- aparta al admin para que no quede dentro del NPC
            setElementPosition(player, x + math.sin(math.rad(rot)) * -1.5, y + math.cos(math.rad(rot)) * 1.5, z)
            notify(player, ("Tienda #%d '%s' creada."):format(id, name), "success")
        end
    end)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbyshops, /gotoshop, /delshop...)
function adminElements()
    local list = {}
    for id, e in pairs(shops) do
        local row = e.row
        if row and not e.temp then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = row.interior, dimension = row.dimension, label = row.name }
        end
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not shops[id] or shops[id].temp then return false, "no existe" end
    dbExec(db(), "DELETE FROM shops WHERE id = ?", id)
    destroyShop(id)
    return true
end

addCommandHandler("borrarshop", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrarshop <id> (tienda existente)", "warning") end
    notify(player, ("Tienda #%d eliminada."):format(id), "success")
end)

----------------------------------------------------------------
-- Tiendas temporales (sin SQL): otro recurso (p. ej. el mercadillo de rp_events)
-- convierte uno de sus NPC en vendedor durante un rato. Usan el mismo menu y la misma
-- compra validada por el servidor; el precio sale SIEMPRE de este catalogo.
--   addTempShop(ped, nombre, { item = precio, ... } [, saludo]) -> id (negativo) | false
--   removeTempShop(id)
-- El NPC no se destruye aqui: lo gestiona quien lo creo (si desaparece, la tienda se quita sola).
----------------------------------------------------------------
local nextTempId = -1

function removeTempShop(id)
    id = tonumber(id)
    local shop = id and shops[id]
    if not shop or not shop.temp then return false end
    if isElement(shop.col) then destroyElement(shop.col) end
    for player, sid in pairs(nearby) do
        if sid == id then
            nearby[player] = nil
            if isElement(player) then triggerClientEvent(player, "rp:shop:near", resourceRoot, false) end
        end
    end
    shops[id] = nil
    return true
end

function addTempShop(ped, name, catalog, greeting)
    if not isElement(ped) or getElementType(ped) ~= "ped" or type(catalog) ~= "table" then return false end
    local items = {}
    for itemId, price in pairs(catalog) do
        price = tonumber(price)
        if type(itemId) == "string" and price and price > 0 and exports.rp_inventory:getItemDefinition(itemId) then
            items[itemId] = math.floor(price)
        end
    end
    if next(items) == nil then return false end
    name = tostring(name or "Vendedor"):sub(1, 48)

    local id = nextTempId
    nextTempId = nextTempId - 1
    local x, y, z = getElementPosition(ped)
    local col = createColSphere(x, y, z, INTERACT_RADIUS)
    setElementInterior(col, getElementInterior(ped))
    setElementDimension(col, getElementDimension(ped))
    attachElements(col, ped)   -- la esfera sigue al NPC si otro recurso lo mueve
    setElementData(ped, "rp:shopId", id)      -- invulnerable en el cliente (c_shops.lua)
    setElementData(ped, "rp:shopName", name)
    shops[id] = { row = { id = id, name = name }, items = items, ped = ped, col = col, temp = true }

    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim then return end
        if not exports.rp_characters:getPlayerCharacterId(el) then return end
        nearby[el] = id
        exports.rp_notify:bubble(el, ped, type(greeting) == "string" and greeting or "¡Buen provecho! Pulsa E para ver lo que vendo.", 4500)
        triggerClientEvent(el, "rp:shop:near", resourceRoot, id, name)
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and nearby[el] == id then
            nearby[el] = nil
            triggerClientEvent(el, "rp:shop:near", resourceRoot, false)
        end
    end)
    addEventHandler("onElementDestroy", ped, function() removeTempShop(id) end)
    return id
end
