--[[
    rp_robbery / s_stores.lua
    Tiendas 24/7 robables (tabla robbery_stores): puerta con pickup por fuera,
    interior de GTA en su propia dimension (21000 + id), cajero detras del
    mostrador y 0-3 clientes al azar. Los puntos de dentro salen del tipo
    (shared/s_config.lua) y se corrigen por tienda con /robopunto (columna
    points, JSON).

    Globales para el resto del recurso:
      STORES[id] = { row, points, pickup, col, exitCol, blip, clerk, customers = {} }
      getStorePoint(store, key), storeDimension(id), getPlayerStore(player)
      spawnStorePeds(store), clearStorePeds(store), spawnStore(row), destroyStore(id)
]]

STORES = {}

addEvent("rp:onDatabaseReady", false)
addEvent("rp:robbery:door", true)
addEvent("rp:robbery:exit", true)

local function db() return exports.rp_database:getConnection() end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

function storeDimension(id) return ROBBERY.DIMENSION_BASE + id end

-- Punto de dentro: el corregido en juego (points) o el del tipo
function getStorePoint(store, key)
    local p = store.points and store.points[key]
    if p then return p end
    local t = ROBBERY_TYPES[store.row.type]
    if key == "exit" then return t.entry end
    return t[key]
end

function getPlayerStore(player)
    local id = getElementDimension(player) - ROBBERY.DIMENSION_BASE
    local store = STORES[id]
    if not store then return nil end
    if getElementInterior(player) ~= ROBBERY_TYPES[store.row.type].interior then return nil end
    return store
end

----------------------------------------------------------------
-- NPCs
----------------------------------------------------------------
local function pick(list) return list[math.random(#list)] end

local function makePed(store, skin, p, role)
    local ped = createPed(skin, p.x, p.y, p.z, p.rot or 0)
    if not ped then return nil end
    setElementInterior(ped, ROBBERY_TYPES[store.row.type].interior)
    setElementDimension(ped, storeDimension(store.row.id))
    setElementFrozen(ped, true)
    setElementData(ped, "rp:robberyPed", role)          -- "clerk" | "customer" | "cop" | "negotiator"
    setElementData(ped, "rp:robberyStore", store.row.id)
    return ped
end

function clearStorePeds(store)
    if isElement(store.clerk) then destroyElement(store.clerk) end
    for _, ped in ipairs(store.customers or {}) do
        if isElement(ped) then destroyElement(ped) end
    end
    store.clerk, store.customers = nil, {}
end

function spawnStorePeds(store)
    clearStorePeds(store)
    store.clerk = makePed(store, pick(ROBBERY.CLERK_SKINS), getStorePoint(store, "clerk"), "clerk")
    local spots = {}
    for _, p in ipairs(getStorePoint(store, "customers") or {}) do spots[#spots + 1] = p end
    local count = math.random(0, math.min(ROBBERY.MAX_CUSTOMERS, #spots))
    for i = 1, count do
        local p = table.remove(spots, math.random(#spots))
        local ped = makePed(store, pick(ROBBERY.CUSTOMER_SKINS), p, "customer")
        if ped then store.customers[#store.customers + 1] = ped end
    end
end

----------------------------------------------------------------
-- Tiendas en el mundo
----------------------------------------------------------------
function destroyStore(id)
    local store = STORES[id]
    if not store then return end
    clearStorePeds(store)
    for _, el in ipairs({ store.pickup, store.col, store.exitCol, store.blip }) do
        if isElement(el) then destroyElement(el) end
    end
    STORES[id] = nil
end

function spawnStore(row)
    local id = tonumber(row.id)
    destroyStore(id)
    local t = ROBBERY_TYPES[row.type]
    if not t then return outputDebugString("[rp_robbery] Tipo desconocido en tienda #" .. id, 2) end
    row.id = id
    row.x, row.y, row.z, row.rot = tonumber(row.x), tonumber(row.y), tonumber(row.z), tonumber(row.rot) or 0
    local points = type(row.points) == "string" and fromJSON(row.points) or nil

    local store = { row = row, points = type(points) == "table" and points or {}, customers = {} }
    STORES[id] = store

    store.pickup = createPickup(row.x, row.y, row.z, 3, ROBBERY.ENTRANCE_PICKUP, 0)
    store.col = createColTube(row.x, row.y, row.z - 2, ROBBERY.DOOR_RADIUS, 4)
    store.blip = createBlip(row.x, row.y, row.z, ROBBERY.BLIP, 2, 255, 255, 255, 255, 0, 250)
    local exit = getStorePoint(store, "exit")
    store.exitCol = createColSphere(exit.x, exit.y, exit.z, ROBBERY.EXIT_RADIUS)
    setElementInterior(store.exitCol, t.interior)
    setElementDimension(store.exitCol, storeDimension(id))

    addEventHandler("onColShapeHit", store.col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim or not characterOf(el) or isPedInVehicle(el) then return end
        triggerClientEvent(el, "rp:robbery:near", resourceRoot, "door", id, row.name)
    end)
    addEventHandler("onColShapeLeave", store.col, function(el)
        if getElementType(el) == "player" then triggerClientEvent(el, "rp:robbery:near", resourceRoot, "door", false) end
    end)
    addEventHandler("onColShapeHit", store.exitCol, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim then return end
        triggerClientEvent(el, "rp:robbery:near", resourceRoot, "exit", id, row.name)
    end)
    addEventHandler("onColShapeLeave", store.exitCol, function(el)
        if getElementType(el) == "player" then triggerClientEvent(el, "rp:robbery:near", resourceRoot, "exit", false) end
    end)

    spawnStorePeds(store)
    return store
end

function insertStore(name, kind, x, y, z, rot, callback)
    dbQuery(function(qh)
        local ok, _, insertId = dbPoll(qh, 0)
        if ok and insertId then spawnStore({ id = insertId, name = name, type = kind, x = x, y = y, z = z, rot = rot }) end
        if callback then callback(ok and insertId) end
    end, db(), "INSERT INTO robbery_stores (name, type, x, y, z, rot) VALUES (?, ?, ?, ?, ?, ?)", name, kind, x, y, z, rot)
end

function saveStorePoints(store)
    dbExec(db(), "UPDATE robbery_stores SET points = ? WHERE id = ?", toJSON(store.points, true), store.row.id)
end

local function loadStores()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return outputDebugString("[rp_robbery] No se pudo leer robbery_stores", 1) end
        if #rows == 0 then
            for _, seed in ipairs(ROBBERY_SEED) do
                insertStore(seed.name, seed.type, seed.x, seed.y, seed.z, seed.rot)
            end
            return outputDebugString("[rp_robbery] Tienda inicial creada")
        end
        for _, row in ipairs(rows) do spawnStore(row) end
        outputDebugString(("[rp_robbery] %d tiendas cargadas"):format(#rows))
    end, db(), "SELECT * FROM robbery_stores")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadStores() else addEventHandler("rp:onDatabaseReady", root, loadStores) end
end)

----------------------------------------------------------------
-- Entrar y salir
----------------------------------------------------------------
local throttle = {}
local function throttled(player)
    local now = getTickCount()
    if throttle[player] and now - throttle[player] < 600 then return true end
    throttle[player] = now
    return false
end
addEventHandler("onPlayerQuit", root, function() throttle[source] = nil end)

function teleportInside(player, store)
    local t = ROBBERY_TYPES[store.row.type]
    local e = getStorePoint(store, "exit")
    setElementInterior(player, t.interior, e.x, e.y, e.z)
    setElementDimension(player, storeDimension(store.row.id))
    setElementRotation(player, 0, 0, e.rot or 0)
    setCameraTarget(player, player)
end

function teleportOutside(player, store)
    local r = math.rad(store.row.rot)
    -- un metro por delante de la puerta, mirando a la calle
    local x, y = store.row.x - math.sin(r) * 1.2, store.row.y + math.cos(r) * 1.2
    setElementInterior(player, 0, x, y, store.row.z)
    setElementDimension(player, 0)
    setElementRotation(player, 0, 0, store.row.rot)
    setCameraTarget(player, player)
end

addEventHandler("rp:robbery:door", resourceRoot, function(id)
    local player = client
    local store = STORES[tonumber(id) or -1]
    if not store or not characterOf(player) or isPedInVehicle(player) or throttled(player) then return end
    if getElementData(player, "rp:downed") then return end
    if getElementDimension(player) ~= 0 or getElementInterior(player) ~= 0 then return end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, store.row.x, store.row.y, store.row.z) > 3.5 then return end
    if not canEnterStore(player, store) then return end
    teleportInside(player, store)
end)

addEventHandler("rp:robbery:exit", resourceRoot, function()
    local player = client
    if throttled(player) or getElementData(player, "rp:downed") then return end
    local store = getPlayerStore(player)
    if not store then return end
    local e = getStorePoint(store, "exit")
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, e.x, e.y, e.z) > 3.5 then return end
    teleportOutside(player, store)
    onPlayerLeftStore(player, store)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for id in pairs(STORES) do destroyStore(id) end
end)
