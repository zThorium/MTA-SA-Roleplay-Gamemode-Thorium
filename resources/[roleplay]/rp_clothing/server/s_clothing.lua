--[[
    rp_clothing / s_clothing.lua

    Tiendas de ropa (tabla clothing_stores). Tres marcadores de rp_markers por tienda,
    todos movibles por un admin con el editor (ALT o M + clic derecho):
      - Puerta (exterior, clave door<id>): E para entrar. Se guarda en clothing_stores.x/y/z.
      - Salida (dentro, clave exit<id>): E para salir. Se guarda en clothing_stores.ix/iy/iz.
      - Mostrador (dentro, clave caja_<tipo>): E abre el estudio. La posicion la guarda rp_markers
        y es la misma para todas las tiendas del mismo tipo (mismo interior de GTA).
    Cada tienda tiene su interior de GTA en su propia dimension. En el estudio lo que eliges se
    prueba en vivo sobre el personaje (lo ven todos) y solo se guarda si lo compras; al cerrar
    sin comprar vuelve la ropa guardada.

      - Personajes con cabeza personalizada (hombres): torso, piernas y zapatos de CJ.
      - Personajes con skin (mujeres): skins civiles de su genero.
      - Todas las tiendas venden accesorios (toys, ver s_toys.lua), que se previsualizan y se
        colocan con el gizmo antes de comprarlos.

    Comandos de administracion (admin_level >= 1):
        /crearropa <tipo> <nombre>          crea una tienda con la puerta en tu posicion
        /borrarropa <id>
        /ropapunto <id> entrada|interior    corrige la puerta o el punto de aparicion dentro
        /tiendasropa                        lista las tiendas
]]

local stores = {}    -- [id] = { row, door, exit, counter, blip }
local fitting = {}   -- [player] = storeId con el estudio abierto
local cooldown = {}
local clientReady = {} -- [player] = true cuando su cliente ya registro los eventos

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:markers:moved")
addEvent("rp:cloth:clientReady", true)
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

-- Mostrador del tipo de tienda: el de la config o el que movio un admin (rp_markers)
local function counterPoint(kind)
    local t = CLOTHING_INTERIORS[kind]
    local c = t and t.counter
    if not c then return nil end
    return exports.rp_markers:placePoint("caja_" .. kind, c[1], c[2], c[3])
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

-- ¿Esta el jugador junto al mostrador de su tienda?
local function atCounter(player)
    local id, s = getPlayerStore(player)
    if not id then return nil end
    local cx, cy, cz = counterPoint(s.row.type)
    if not cx then return nil end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, cx, cy, cz) > CLOTHING.COUNTER_RADIUS then return nil end
    return id, s
end

local function destroyStore(id)
    local s = stores[id]
    if not s then return end
    for _, el in ipairs({ s.door, s.exit, s.counter, s.blip }) do if isElement(el) then destroyElement(el) end end
    stores[id] = nil
end

-- Marcador de rp_markers: x, y, z = punto a la altura del jugador (el cilindro va 1 m mas abajo)
local function makeMarker(x, y, z, interior, dimension, style, key, opts)
    local m = createMarker(x, y, z - 1, "cylinder", CLOTHING.MARKER_SIZE, 255, 255, 255, 120)
    setElementInterior(m, interior)
    setElementDimension(m, dimension)
    exports.rp_markers:setMarkerStyle(m, style)
    opts.point = { x, y, z }
    exports.rp_markers:registerMarker(m, key, opts)
    return m
end

-- Avisa al cliente del marcador que pisa (para el atajo E). kind = door | exit | counter
local function bindNear(marker, kind, id, name)
    addEventHandler("onMarkerHit", marker, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim or not characterOf(el) or isPedInVehicle(el) then return end
        triggerClientEvent(el, "rp:cloth:near", resourceRoot, kind, id, name)
    end)
    addEventHandler("onMarkerLeave", marker, function(el)
        if getElementType(el) == "player" then triggerClientEvent(el, "rp:cloth:near", resourceRoot, kind, false) end
    end)
end

local function spawnStore(row)
    local id = tonumber(row.id)
    destroyStore(id)
    local t = getStoreInterior(row)
    if not t then return outputDebugString("[rp_clothing] Tipo desconocido en tienda #" .. id, 2) end
    row.x, row.y, row.z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    local dim = dimensionOf(id)

    local door = makeMarker(row.x, row.y, row.z, 0, 0, { icon = "clothes", label = row.name },
        "door" .. id, { label = row.name .. " · entrada", ownerSaves = true })
    local exit = makeMarker(t.x, t.y, t.z, t.interior, dim, { icon = "exit", label = "Salir" },
        "exit" .. id, { label = row.name .. " · salida", ownerSaves = true })
    local counter
    local cx, cy, cz = counterPoint(row.type)
    if cx then
        counter = makeMarker(cx, cy, cz, t.interior, dim, { icon = "clothes", label = "Probador y accesorios" },
            "caja_" .. row.type, { label = t.name .. " · mostrador (todas las " .. t.name .. ")" })
    end
    local blip = createBlip(row.x, row.y, row.z, CLOTHING.BLIP, 2, 255, 255, 255, 255, 0, 250)
    stores[id] = { row = row, door = door, exit = exit, counter = counter, blip = blip }

    bindNear(door, "door", id, row.name)
    bindNear(exit, "exit", id, row.name)
    if counter then bindNear(counter, "counter", id, row.name) end
end

local function insertStore(name, kind, x, y, z, callback)
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if ok then spawnStore({ id = id, name = name, type = kind, x = x, y = y, z = z }) end
        if callback then callback(ok and id) end
    end, db(), "INSERT INTO clothing_stores (name, type, x, y, z) VALUES (?, ?, ?, ?, ?)", name, kind, x, y, z)
end

-- Avisa al cliente si el jugador esta dentro de una tienda (cierra el estudio al salir)
local function updateInside(player)
    if not isElement(player) or not clientReady[player] then return end
    local id, s = getPlayerStore(player)
    triggerClientEvent(player, "rp:cloth:inside", resourceRoot, id or false, s and s.row.name or nil)
end

-- Siembra de las tiendas iniciales. Atomica: no inserta si ya hay una tienda del mismo tipo a menos
-- de DUP_RADIUS de esa puerta. Asi dos cargas seguidas (arranque + rp:onDatabaseReady de un reinicio
-- de rp_database) ya no pueden duplicar las tiendas.
local DUP_RADIUS = 3
local function seedStore(name, kind, x, y, z)
    dbQuery(function(qh)
        local ok, affected, id = dbPoll(qh, 0)
        if ok and (tonumber(affected) or 0) > 0 then spawnStore({ id = id, name = name, type = kind, x = x, y = y, z = z }) end
    end, db(), [[
        INSERT INTO clothing_stores (name, type, x, y, z)
        SELECT ?, ?, ?, ?, ? FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM clothing_stores WHERE type = ? AND ABS(x - ?) < ? AND ABS(y - ?) < ?)
    ]], name, kind, x, y, z, kind, x, DUP_RADIUS, y, DUP_RADIUS)
end

-- ¿La puerta esta donde la puso la semilla? (si no, un admin la coloco a mano)
local function atSeed(row)
    for _, s in ipairs(CLOTHING_SEED) do
        if s[2] == row.type and math.abs(s[3] - tonumber(row.x)) < 0.05 and math.abs(s[4] - tonumber(row.y)) < 0.05 then return true end
    end
    return false
end

-- Tiendas duplicadas (mismo tipo y puerta a menos de DUP_RADIUS): se queda la que un admin coloco
-- a mano y, si no, la de id menor. Las demas se borran de la BD.
local function removeDuplicates(rows)
    local keep = {}
    for _, row in ipairs(rows) do row._seed = atSeed(row) end
    table.sort(rows, function(a, b)
        if a._seed ~= b._seed then return not a._seed end
        return tonumber(a.id) < tonumber(b.id)
    end)
    for _, row in ipairs(rows) do
        local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
        local dup
        for _, k in ipairs(keep) do
            if k.type == row.type and getDistanceBetweenPoints3D(x, y, z, tonumber(k.x), tonumber(k.y), tonumber(k.z)) < DUP_RADIUS then
                dup = k
                break
            end
        end
        if dup then
            outputDebugString(("[rp_clothing] Tienda #%s '%s' duplicada de la #%s: se elimina"):format(row.id, row.name, dup.id), 2)
            dbExec(db(), "DELETE FROM clothing_stores WHERE id = ?", row.id)
        else
            keep[#keep + 1] = row
        end
    end
    return keep
end

local function loadStores()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then
            for _, seed in ipairs(CLOTHING_SEED) do seedStore(seed[1], seed[2], seed[3], seed[4], seed[5]) end
            return outputDebugString("[rp_clothing] Tiendas de ropa iniciales creadas")
        end
        rows = removeDuplicates(rows)
        for _, row in ipairs(rows) do spawnStore(row) end
        outputDebugString(("[rp_clothing] %d tiendas de ropa cargadas"):format(#rows))
        for p in pairs(clientReady) do if isElement(p) then updateInside(p) end end
    end, db(), "SELECT * FROM clothing_stores")
end

-- El cliente avisa cuando ya cargo sus scripts: antes no se le pueden mandar eventos
-- (tras un restart, el servidor arranca antes que la descarga del cliente).
addEventHandler("rp:cloth:clientReady", resourceRoot, function()
    clientReady[client] = true
    if characterOf(client) then updateInside(client) end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadStores() else addEventHandler("rp:onDatabaseReady", root, loadStores) end
end)

-- Un admin movio un marcador con el editor: se guarda (puerta y salida) y se rehace la tienda
addEventHandler("rp:markers:moved", root, function(owner, key, x, y, z)
    if owner ~= "rp_clothing" or type(key) ~= "string" then return end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local door, exit, kind = tonumber(key:match("^door(%d+)$")), tonumber(key:match("^exit(%d+)$")), key:match("^caja_(%a+)$")
    if door and stores[door] and x then
        local row = stores[door].row
        row.x, row.y, row.z = x, y, z
        dbExec(db(), "UPDATE clothing_stores SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, door)
        spawnStore(row)
    elseif exit and stores[exit] and x then
        local row = stores[exit].row
        local rot = getStoreInterior(row).rot
        row.ix, row.iy, row.iz, row.irot = x, y, z, rot
        dbExec(db(), "UPDATE clothing_stores SET ix = ?, iy = ?, iz = ?, irot = ? WHERE id = ?", x, y, z, rot, exit)
        spawnStore(row)
    elseif kind then
        for _, s in pairs(stores) do
            if s.row.type == kind then spawnStore(s.row) end
        end
    end
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
    notify(player, ("Bienvenido a %s. Ve al mostrador (marcador con la camiseta) para probarte ropa y accesorios."):format(s.row.name), "info")
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
-- Estudio (probador + accesorios)
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
    if not characterOf(player) or isPedInVehicle(player) then return end
    local id = atCounter(player)
    if not id then return notify(player, "Acercate al mostrador de la tienda.", "warning") end
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

-- Sigue con el estudio abierto y junto al mostrador de esa misma tienda
local function stillFitting(player)
    local storeId = fitting[player]
    return storeId and atCounter(player) == storeId and storeId or nil
end

addEventHandler("rp:cloth:try", resourceRoot, function(slot, index)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    index = tonumber(index)
    if not stillFitting(player) then return end
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
    local storeId = stillFitting(player)
    if not storeId or throttled(player) then return end
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
    triggerClientEvent(player, "rp:cloth:bought", resourceRoot, "clothes")
    triggerEvent("rp:achievements:progress", player, "clothes_bought", 1)   -- logros (rp_achievements)
    sendShop(player)
end)

-- adjust = ajuste del gizmo hecho en la vista previa (opcional; el servidor lo recorta)
addEventHandler("rp:cloth:buyToy", resourceRoot, function(toyKey, adjust)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local storeId = stillFitting(player)
    if not storeId or throttled(player) then return end
    buyToy(player, toyKey, getStoreInterior(stores[storeId].row).multiplier, adjust, function()
        triggerClientEvent(player, "rp:cloth:bought", resourceRoot, "toy", toyKey)
        sendShop(player)
    end)
end)

local function forget(player)
    fitting[player], cooldown[player] = nil, nil
end
addEventHandler("onPlayerQuit", root, function()
    forget(source)
    clientReady[source] = nil
end)
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
                noRot = true, element = e.door }
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
