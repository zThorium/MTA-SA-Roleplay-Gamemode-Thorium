--[[
    rp_clothing / s_toys.lua

    Accesorios (toys) del personaje en character_toys. Los que lleva puestos se
    crean como objetos pegados a un hueso con bone_attach y con su escala por eje.
    Cada jugador ajusta hueso, posicion, rotacion y tamano con el gizmo del estudio
    (cliente, c_gizmo.lua); el servidor recorta los valores con sanitizeToyAdjust
    (CLOTHING.LIMITS) antes de guardarlos, tambien los de la vista previa al comprar.

    Comandos:
        /accesorios  (o /toys)   estudio con tus accesorios: poner, quitar, ajustar, tirar
]]

local owned = {}     -- [player] = { [toyId] = fila }
local objects = {}   -- [player] = { [toyId] = objeto }
local loadedFor = {} -- [player] = characterId

addEvent("rp:toys:open", true)
addEvent("rp:toys:wear", true)
addEvent("rp:toys:delete", true)
addEvent("rp:toys:edit", true)
addEvent("rp:toys:save", true)
addEvent("rp:clothing:onTeleport", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

local NUMERIC = { "bone", "x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz", "worn", "id" }

local function normalize(row)
    for _, k in ipairs(NUMERIC) do row[k] = tonumber(row[k]) or 0 end
    row.worn = row.worn == 1
    return row
end

----------------------------------------------------------------
-- Objetos en el mundo
----------------------------------------------------------------
local function detach(player, toyId)
    local obj = objects[player] and objects[player][toyId]
    if isElement(obj) then
        exports.bone_attach:detachElementFromBone(obj)
        destroyElement(obj)
    end
    if objects[player] then objects[player][toyId] = nil end
end

local function detachAll(player)
    for toyId in pairs(objects[player] or {}) do detach(player, toyId) end
    objects[player] = nil
end

local function attach(player, row)
    detach(player, row.id)
    local def = TOYS[row.toy]
    if not def or not isElement(player) then return end
    local x, y, z = getElementPosition(player)
    local obj = createObject(def.model, x, y, z)
    if not obj then return outputDebugString("[rp_clothing] No se pudo crear el accesorio " .. row.toy, 2) end
    setElementInterior(obj, getElementInterior(player))
    setElementDimension(obj, getElementDimension(player))
    setElementCollisionsEnabled(obj, false)
    setObjectScale(obj, row.sx, row.sy, row.sz)
    setElementData(obj, "rp:toy", row.id)   -- sincronizado: c_headlink.lua lo pega a la cabeza custom en cada cliente
    exports.bone_attach:attachElementToBone(obj, player, row.bone, row.x, row.y, row.z, row.rx, row.ry, row.rz)
    objects[player] = objects[player] or {}
    objects[player][row.id] = obj
end

-- Los objetos siguen al jugador al cambiar de interior o dimension (casas, tiendas...)
local function syncPlayer(player)
    local list = objects[player]
    if not list then return end
    local int, dim = getElementInterior(player), getElementDimension(player)
    for _, obj in pairs(list) do
        if isElement(obj) then
            if getElementInterior(obj) ~= int then setElementInterior(obj, int) end
            if getElementDimension(obj) ~= dim then setElementDimension(obj, dim) end
        end
    end
end

setTimer(function()
    for player in pairs(objects) do
        if isElement(player) then syncPlayer(player) else objects[player] = nil end
    end
end, 1000, 0)

addEventHandler("rp:clothing:onTeleport", root, function() syncPlayer(source) end)

----------------------------------------------------------------
-- Carga
----------------------------------------------------------------
local function loadToys(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        detachAll(player)
        owned[player], loadedFor[player] = {}, characterId
        for _, r in ipairs(rows) do
            local row = normalize(r)
            if TOYS[row.toy] then
                owned[player][row.id] = row
                if row.worn then attach(player, row) end
            end
        end
    end, db(), "SELECT * FROM character_toys WHERE character_id = ? ORDER BY id", characterId)
end

addEventHandler("rp:onCharacterSpawn", root, function() loadToys(source) end)

local function forget(player)
    detachAll(player)
    owned[player], loadedFor[player] = nil, nil
end
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)

addEventHandler("onResourceStart", resourceRoot, function()
    local function loadOnline()
        for _, p in ipairs(getElementsByType("player")) do loadToys(p) end
    end
    if exports.rp_database:isReady() then loadOnline() else addEventHandler("rp:onDatabaseReady", root, loadOnline) end
end)

----------------------------------------------------------------
-- Datos para la interfaz
----------------------------------------------------------------
local function count(player, onlyWorn)
    local n = 0
    for _, row in pairs(owned[player] or {}) do
        if not onlyWorn or row.worn then n = n + 1 end
    end
    return n
end

function getToysPayload(player)
    local list = {}
    for _, row in pairs(owned[player] or {}) do
        local def = TOYS[row.toy]
        list[#list + 1] = { id = row.id, toy = row.toy, name = def.name, icon = def.icon, worn = row.worn,
            adjust = { bone = row.bone, x = row.x, y = row.y, z = row.z, rx = row.rx, ry = row.ry, rz = row.rz, sx = row.sx, sy = row.sy, sz = row.sz } }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function getToyCatalog(multiplier)
    local list = {}
    for key, def in pairs(TOYS) do
        list[#list + 1] = { id = key, name = def.name, icon = def.icon, price = getToyPrice(key, multiplier) }
    end
    table.sort(list, function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        return a.name < b.name
    end)
    return list
end

local function sendWardrobe(player)
    triggerClientEvent(player, "rp:toys:list", resourceRoot, getToysPayload(player),
        { owned = CLOTHING.MAX_TOYS_OWNED, worn = CLOTHING.MAX_TOYS_WORN })
end

----------------------------------------------------------------
-- Compra (desde s_clothing.lua)
----------------------------------------------------------------
-- adjust = como lo dejo en la vista previa (gizmo); si no vale, la posicion del catalogo.
-- Si le queda hueco, sale de la tienda puesto.
function buyToy(player, toyKey, multiplier, adjust, callback)
    local characterId = characterOf(player)
    local def = type(toyKey) == "string" and TOYS[toyKey]
    if not characterId or not def or loadedFor[player] ~= characterId then return end
    if count(player) >= CLOTHING.MAX_TOYS_OWNED then
        return notify(player, ("Ya tienes %d accesorios. Tira alguno en «Mis accesorios»."):format(CLOTHING.MAX_TOYS_OWNED), "error")
    end
    local price = getToyPrice(toyKey, multiplier)
    if getPlayerMoney(player) < price then return notify(player, ("No tienes suficiente efectivo. Necesitas $%d."):format(price), "error") end

    local a = sanitizeToyAdjust(adjust) or getToyDefaults(toyKey)
    local wear = count(player, true) < CLOTHING.MAX_TOYS_WORN
    takePlayerMoney(player, price)
    exports.rp_characters:saveCharacter(player)
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not ok then
            givePlayerMoney(player, price)
            return notify(player, "No se pudo completar la compra.", "error")
        end
        owned[player] = owned[player] or {}
        local row = normalize({ id = id, toy = toyKey, bone = a.bone, x = a.x, y = a.y, z = a.z,
            rx = a.rx, ry = a.ry, rz = a.rz, sx = a.sx, sy = a.sy, sz = a.sz, worn = wear and 1 or 0 })
        owned[player][id] = row
        if wear then attach(player, row) end
        triggerEvent("rp:achievements:progress", player, "clothes_bought", 1)   -- logros (rp_achievements)
        notify(player, wear and ("Compraste %s por $%d. Ya lo llevas puesto."):format(def.name, price)
            or ("Compraste %s por $%d. Quitate otro accesorio para ponertelo."):format(def.name, price), "success")
        if callback then callback() end
    end, db(), [[
        INSERT INTO character_toys (character_id, toy, bone, x, y, z, rx, ry, rz, sx, sy, sz, worn)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], characterId, toyKey, a.bone, a.x, a.y, a.z, a.rx, a.ry, a.rz, a.sx, a.sy, a.sz, wear and 1 or 0)
end

----------------------------------------------------------------
-- Acciones del jugador
----------------------------------------------------------------
local function ownedToy(player, toyId)
    return owned[player] and owned[player][tonumber(toyId) or -1]
end

addEventHandler("rp:toys:open", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    if characterOf(client) then sendWardrobe(client) end
end)

addEventHandler("rp:toys:wear", resourceRoot, function(toyId, state, view)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local row = ownedToy(player, toyId)
    if not row then return end
    state = state == true
    if state and not row.worn and count(player, true) >= CLOTHING.MAX_TOYS_WORN then
        return notify(player, ("Solo puedes llevar %d accesorios a la vez."):format(CLOTHING.MAX_TOYS_WORN), "error")
    end
    row.worn = state
    dbExec(db(), "UPDATE character_toys SET worn = ? WHERE id = ?", state and 1 or 0, row.id)
    if state then attach(player, row) else detach(player, row.id) end
    sendWardrobe(player)
end)

addEventHandler("rp:toys:delete", resourceRoot, function(toyId)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local row = ownedToy(player, toyId)
    if not row then return end
    detach(player, row.id)
    owned[player][row.id] = nil
    dbExec(db(), "DELETE FROM character_toys WHERE id = ?", row.id)
    notify(player, ("Tiraste %s."):format(TOYS[row.toy].name), "info")
    sendWardrobe(player)
end)

addEventHandler("rp:toys:edit", resourceRoot, function(toyId)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local row = ownedToy(player, toyId)
    if not row then return end
    if not row.worn then
        if count(player, true) >= CLOTHING.MAX_TOYS_WORN then
            return notify(player, ("Quitate otro accesorio primero (maximo %d puestos)."):format(CLOTHING.MAX_TOYS_WORN), "error")
        end
        row.worn = true
        dbExec(db(), "UPDATE character_toys SET worn = 1 WHERE id = ?", row.id)
        attach(player, row)
    end
    triggerClientEvent(player, "rp:toys:editStart", resourceRoot, row, objects[player] and objects[player][row.id] or false)
end)

addEventHandler("rp:toys:save", resourceRoot, function(toyId, v)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local row = ownedToy(player, toyId)
    local vals = row and sanitizeToyAdjust(v)
    if not vals then return end

    for k, n in pairs(vals) do row[k] = n end
    dbExec(db(), [[
        UPDATE character_toys SET bone = ?, x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ?, sx = ?, sy = ?, sz = ? WHERE id = ?
    ]], row.bone, row.x, row.y, row.z, row.rx, row.ry, row.rz, row.sx, row.sy, row.sz, row.id)
    if row.worn then attach(player, row) end
    notify(player, ("%s ajustado y guardado."):format(TOYS[row.toy].name), "success")
    sendWardrobe(player)
end)

local function openWardrobe(player)
    if not characterOf(player) then return end
    triggerClientEvent(player, "rp:toys:openUI", resourceRoot)
end
addCommandHandler("accesorios", openWardrobe)
addCommandHandler("toys", openWardrobe)
