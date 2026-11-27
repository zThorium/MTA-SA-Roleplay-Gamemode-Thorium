--[[
    rp_clothing / s_clothing.lua

    Tiendas de ropa (tabla clothing_stores). En la puerta hay un pickup de
    camiseta: E para entrar. Cada tienda tiene su interior de GTA en su propia
    dimension. Dentro, E abre el probador: lo que eliges se prueba en vivo sobre
    el personaje (lo ven todos) y solo se guarda si lo compras. Al cerrar sin
    comprar vuelve la ropa guardada. En la puerta de dentro, E para salir.

      - Personajes con cabeza personalizada (hombres): torso, piernas y zapatos de CJ.
      - Personajes con skin (mujeres): skins civiles de su genero.
      - Todas las tiendas venden accesorios (toys, ver s_toys.lua).

    Comandos de administracion (admin_level >= 1):
        /crearropa <tipo> <nombre>          crea una tienda con la puerta en tu posicion
        /borrarropa <id>
        /ropapunto <id> entrada|interior    corrige la puerta o el punto de aparicion dentro
        /tiendasropa                        lista las tiendas
]]

local stores = {}    -- [id] = { row, pickup, col, exitCol, blip }
local fitting = {}   -- [player] = storeId con el probador abierto
local cooldown = {}

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:cloth:enter", true)
addEvent("rp:cloth:exit", true)
addEvent("rp:cloth:open", true)
addEvent("rp:cloth:close", true)
addEvent("rp:cloth:try", true)
addEvent("rp:cloth:buy", true)
addEvent("rp:cloth:buyToy", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local SLOT_TYPES = { torso = 0, legs = 2, shoes = 3 }
local SLOT_COLUMNS = { torso = "clothes_torso", legs = "clothes_legs", shoes = "clothes_shoes" }
local SLOT_NAMES = { torso = "Torso", legs = "Piernas", shoes = "Zapatos" }

local clothesCount = {}
local function countClothes(clothesType)
    if not clothesCount[clothesType] then
        local n = 0
        while getClothesByTypeIndex(clothesType, n) do n = n + 1 end
        clothesCount[clothesType] = n
    end
    return clothesCount[clothesType]
end

local function isInt(n, a, b)
    return type(n) == "number" and n == math.floor(n) and n >= a and n <= b
end

local function throttled(player)
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 150 then return true end
    cooldown[player] = now
    return false
end

----------------------------------------------------------------
-- Tiendas en el mundo
----------------------------------------------------------------
local function dimensionOf(id) return CLOTHING.DIMENSION_BASE + id end

-- Interior de la tienda: el del tipo, con el punto corregido en juego si existe
function getStoreInterior(row)
    local t = CLOTHING_INTERIORS[row.type]
    if not t then return nil end
    local ix = tonumber(row.ix)
    return {
        name = t.name, interior = t.interior, multiplier = t.multiplier,
        x = ix or t.x, y = ix and tonumber(row.iy) or t.y, z = ix and tonumber(row.iz) or t.z,
        rot = ix and (tonumber(row.irot) or 0) or t.rot,
    }
end

-- Tienda en la que esta el jugador (por interior y dimension), o nil
function getPlayerStore(player)
    local id = getElementDimension(player) - CLOTHING.DIMENSION_BASE
    local s = stores[id]
    if not s then return nil end
    local t = getStoreInterior(s.row)
    if not t or getElementInterior(player) ~= t.interior then return nil end
    return id, s, t
end

local function destroyStore(id)
    local s = stores[id]
    if not s then return end
    for _, el in ipairs({ s.pickup, s.col, s.exitCol, s.blip }) do if isElement(el) then destroyElement(el) end end
    stores[id] = nil
end

local function spawnStore(row)
    local id = tonumber(row.id)
    destroyStore(id)
    local t = getStoreInterior(row)
    if not t then return outputDebugString("[rp_clothing] Tipo desconocido en tienda #" .. id, 2) end
    row.x, row.y, row.z = tonumber(row.x), tonumber(row.y), tonumber(row.z)

    local pickup = createPickup(row.x, row.y, row.z, 3, CLOTHING.ENTRANCE_PICKUP, 0)
    local col = createColTube(row.x, row.y, row.z - 2, 1.4, 4)
    local exitCol = createColSphere(t.x, t.y, t.z, CLOTHING.EXIT_RADIUS)
    setElementInterior(exitCol, t.interior)
    setElementDimension(exitCol, dimensionOf(id))
    local blip = createBlip(row.x, row.y, row.z, CLOTHING.BLIP, 2, 255, 255, 255, 255, 0, 250)
    stores[id] = { row = row, pickup = pickup, col = col, exitCol = exitCol, blip = blip }

    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim or not characterOf(el) or isPedInVehicle(el) then return end
        triggerClientEvent(el, "rp:cloth:near", resourceRoot, "door", id, row.name)
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" then triggerClientEvent(el, "rp:cloth:near", resourceRoot, "door", false) end
    end)
    addEventHandler("onColShapeHit", exitCol, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim then return end
        triggerClientEvent(el, "rp:cloth:near", resourceRoot, "exit", id, row.name)
    end)
    addEventHandler("onColShapeLeave", exitCol, function(el)
        if getElementType(el) == "player" then triggerClientEvent(el, "rp:cloth:near", resourceRoot, "exit", false) end
    end)
end

local function insertStore(name, kind, x, y, z, callback)
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if ok then spawnStore({ id = id, name = name, type = kind, x = x, y = y, z = z }) end
        if callback then callback(ok and id) end
    end, db(), "INSERT INTO clothing_stores (name, type, x, y, z) VALUES (?, ?, ?, ?, ?)", name, kind, x, y, z)
end

-- Avisa al cliente si el jugador esta dentro de una tienda (para el atajo E del probador)
local function updateInside(player)
    if not isElement(player) then return end
    local id, s = getPlayerStore(player)
    triggerClientEvent(player, "rp:cloth:inside", resourceRoot, id or false, s and s.row.name or nil)
end

local function loadStores()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then
            for _, seed in ipairs(CLOTHING_SEED) do insertStore(seed[1], seed[2], seed[3], seed[4], seed[5]) end
            return outputDebugString("[rp_clothing] Tiendas de ropa iniciales creadas")
        end
        for _, row in ipairs(rows) do spawnStore(row) end
        outputDebugString(("[rp_clothing] %d tiendas de ropa cargadas"):format(#rows))
        for _, p in ipairs(getElementsByType("player")) do updateInside(p) end
    end, db(), "SELECT * FROM clothing_stores")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadStores() else addEventHandler("rp:onDatabaseReady", root, loadStores) end
end)

-- Si reaparece dentro de una tienda (se desconecto ahi), el cliente necesita saberlo
addEventHandler("rp:onCharacterSpawn", root, function()
    local player = source
    setTimer(updateInside, 1500, 1, player)
end)

----------------------------------------------------------------
-- Entrar y salir
----------------------------------------------------------------
local function closeFitting(player, restore)
    if fitting[player] then
        fitting[player] = nil
        if restore ~= false and isElement(player) then exports.rp_characters:restoreCharacterLook(player) end
    end
end

addEventHandler("rp:cloth:enter", resourceRoot, function(id)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local s = stores[tonumber(id) or -1]
    if not s or not characterOf(player) or isPedInVehicle(player) or throttled(player) then return end
    if getElementDimension(player) ~= 0 or getElementInterior(player) ~= 0 then return end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, s.row.x, s.row.y, s.row.z) > 3.5 then return end

    local t = getStoreInterior(s.row)
    setElementInterior(player, t.interior, t.x, t.y, t.z)
    setElementDimension(player, dimensionOf(s.row.id))
    setElementRotation(player, 0, 0, t.rot)
    setCameraTarget(player, player)
    triggerEvent("rp:clothing:onTeleport", player)
    triggerClientEvent(player, "rp:cloth:inside", resourceRoot, tonumber(s.row.id), s.row.name)
    notify(player, ("Bienvenido a %s. Pulsa E para abrir el probador."):format(s.row.name), "info")
end)

addEventHandler("rp:cloth:exit", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local id, s, t = getPlayerStore(player)
    if not id or throttled(player) then return end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, t.x, t.y, t.z) > CLOTHING.EXIT_RADIUS + 2 then return end

    closeFitting(player)
    setElementInterior(player, 0, s.row.x, s.row.y, s.row.z)
    setElementDimension(player, 0)
    setCameraTarget(player, player)
    triggerEvent("rp:clothing:onTeleport", player)
    triggerClientEvent(player, "rp:cloth:inside", resourceRoot, false)
end)
addEvent("rp:clothing:onTeleport", false)

----------------------------------------------------------------
-- Probador
----------------------------------------------------------------
local function shopData(player, storeId)
    local s = stores[storeId]
    local t = getStoreInterior(s.row)
    local look = exports.rp_characters:getCharacterLook(player)
    if not look then return nil end

    local data = {
        mode = "shop", store = s.row.name, storeType = t.name, multiplier = t.multiplier, prices = CLOTHING.PRICES,
        money = getPlayerMoney(player), toys = getToyCatalog(t.multiplier), owned = getToysPayload(player),
        limits = { owned = CLOTHING.MAX_TOYS_OWNED, worn = CLOTHING.MAX_TOYS_WORN },
    }
    if look.head then
        data.clothes = {}
        for _, key in ipairs({ "torso", "legs", "shoes" }) do
            data.clothes[#data.clothes + 1] = {
                key = key, name = SLOT_NAMES[key], count = countClothes(SLOT_TYPES[key]),
                current = look[SLOT_COLUMNS[key]] or 0,
            }
        end
    else
        data.skins = { list = exports.rp_characters:getAllowedSkins(look.gender), current = look.skin }
    end
    return data
end

local function sendShop(player)
    local storeId = fitting[player]
    local data = storeId and shopData(player, storeId)
    if data then triggerClientEvent(player, "rp:cloth:show", resourceRoot, data) end
end

addEventHandler("rp:cloth:open", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local id = getPlayerStore(player)
    if not id or not characterOf(player) then return end
    fitting[player] = id
    sendShop(player)
end)

addEventHandler("rp:cloth:close", resourceRoot, function()
    closeFitting(client)
end)

-- Valida una prenda o skin segun el tipo de personaje
local function validChoice(player, slot, index)
    local look = exports.rp_characters:getCharacterLook(player)
    if not look then return false end
    if slot == "skin" then
        if look.head then return false end
        for _, id in ipairs(exports.rp_characters:getAllowedSkins(look.gender)) do
            if id == index then return true, look end
        end
        return false
    end
    if not look.head or not SLOT_TYPES[slot] then return false end
    return isInt(index, 0, countClothes(SLOT_TYPES[slot]) - 1), look
end

addEventHandler("rp:cloth:try", resourceRoot, function(slot, index)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    index = tonumber(index)
    if not fitting[player] or not getPlayerStore(player) then return end
    if not validChoice(player, slot, index) then return end
    if slot == "skin" then
        setElementModel(player, index)
    else
        local clothesType = SLOT_TYPES[slot]
        local texture, model = getClothesByTypeIndex(clothesType, index)
        removePedClothes(player, clothesType)
        if texture then addPedClothes(player, texture, model, clothesType) end
    end
end)

addEventHandler("rp:cloth:buy", resourceRoot, function(slot, index)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    index = tonumber(index)
    local storeId = fitting[player]
    if not storeId or getPlayerStore(player) ~= storeId or throttled(player) then return end
    local ok, look = validChoice(player, slot, index)
    if not ok then return notify(player, "Esa prenda no esta disponible.", "error") end

    local column = slot == "skin" and "skin" or SLOT_COLUMNS[slot]
    if tonumber(look[column]) == index then return notify(player, "Ya llevas puesta esa prenda.", "warning") end

    local price = getClothesPrice(slot, index, getStoreInterior(stores[storeId].row).multiplier)
    if getPlayerMoney(player) < price then return notify(player, ("No tienes suficiente efectivo. Necesitas $%d."):format(price), "error") end

    takePlayerMoney(player, price)
    exports.rp_characters:setCharacterLook(player, { [column] = index })
    exports.rp_characters:saveCharacter(player)
    notify(player, ("Compraste %s por $%d."):format(slot == "skin" and "un nuevo conjunto" or SLOT_NAMES[slot]:lower(), price), "success")
    sendShop(player)
end)

addEventHandler("rp:cloth:buyToy", resourceRoot, function(toyKey)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local storeId = fitting[player]
    if not storeId or getPlayerStore(player) ~= storeId or throttled(player) then return end
    buyToy(player, toyKey, getStoreInterior(stores[storeId].row).multiplier, function() sendShop(player) end)
end)

local function forget(player)
    fitting[player], cooldown[player] = nil, nil
end
addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerWasted", root, function() closeFitting(source, false) end)
addEvent("rp:onPlayerDowned", false)
addEventHandler("rp:onPlayerDowned", root, function() closeFitting(source, false) end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
local function denied(p) notify(p, "No tienes permiso para usar este comando.", "error") end

local function typeList()
    local list = {}
    for k in pairs(CLOTHING_INTERIORS) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ", ")
end

addCommandHandler("crearropa", function(player, _, kind, ...)
    if not isAdmin(player) then return denied(player) end
    local name = table.concat({ ... }, " ")
    kind = kind and kind:lower()
    if not kind or not CLOTHING_INTERIORS[kind] or #name < 3 or #name > 48 then
        return notify(player, "Uso: /crearropa <tipo> <nombre>. Tipos: " .. typeList(), "warning", 8000)
    end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        return notify(player, "La puerta debe estar en el exterior (interior 0, dimension 0).", "error")
    end
    local x, y, z = getElementPosition(player)
    insertStore(name, kind, x, y, z, function(id)
        if id and isElement(player) then notify(player, ("Tienda de ropa #%d '%s' creada."):format(id, name), "success") end
    end)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbyclothingstores, /gotoclothingstore, /delclothingstore...)
function adminElements()
    local list = {}
    for id, e in pairs(stores) do
        local row = e.row
        if row then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = 0, dimension = 0, label = row.name,
                noRot = true, element = e.pickup }
        end
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not stores[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM clothing_stores WHERE id = ?", id)
    destroyStore(id)
    return true
end

-- Mover la entrada desde el editor de rp_admin (vista ALT). La tabla no guarda giro.
function adminMove(id, _, x, y, z)
    id = tonumber(id)
    local s = id and stores[id]
    if not s then return false, "no existe" end
    local row = s.row
    row.x, row.y, row.z = x, y, z
    dbExec(db(), "UPDATE clothing_stores SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
    spawnStore(row)
    return true
end

addCommandHandler("borrarropa", function(player, _, id)
    if not isAdmin(player) then return denied(player) end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrarropa <id>", "warning") end
    notify(player, ("Tienda de ropa #%d eliminada."):format(id), "success")
end)

addCommandHandler("ropapunto", function(player, _, id, which)
    if not isAdmin(player) then return denied(player) end
    id = tonumber(id)
    local s = id and stores[id]
    if not s or (which ~= "entrada" and which ~= "interior") then
        return notify(player, "Uso: /ropapunto <id> entrada|interior (parado en el punto correcto)", "warning")
    end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    if which == "entrada" then
        if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
            return notify(player, "Para la entrada, parate en la puerta por fuera.", "error")
        end
        dbExec(db(), "UPDATE clothing_stores SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
        s.row.x, s.row.y, s.row.z = x, y, z
    else
        local t = CLOTHING_INTERIORS[s.row.type]
        if getElementInterior(player) ~= t.interior then
            return notify(player, ("Entra al interior %d (el de %s) y parate junto a la puerta."):format(t.interior, t.name), "error")
        end
        dbExec(db(), "UPDATE clothing_stores SET ix = ?, iy = ?, iz = ?, irot = ? WHERE id = ?", x, y, z, rot, id)
        s.row.ix, s.row.iy, s.row.iz, s.row.irot = x, y, z, rot
    end
    spawnStore(s.row)
    notify(player, ("Punto de %s de la tienda #%d actualizado."):format(which, id), "success")
end)

addCommandHandler("tiendasropa", function(player)
    if not isAdmin(player) then return denied(player) end
    local ids = {}
    for id in pairs(stores) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then return outputChatBox("No hay tiendas de ropa.", player, 200, 200, 200) end
    for _, id in ipairs(ids) do
        local r = stores[id].row
        outputChatBox(("#%d %s (%s) - %.1f, %.1f, %.1f"):format(id, r.name, r.type, r.x, r.y, r.z), player, 120, 200, 255)
    end
end)
