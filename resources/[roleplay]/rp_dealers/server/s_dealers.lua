--[[
    rp_dealers / s_dealers.lua

    Traficantes: peds con skin 28, 29 o 30 (Drug Dealer) guardados en la tabla
    dealers. Se acerca uno, saluda con un globo y con E se abre el menu de
    rp_shops (rp_shops:addTempShop) con marihuana, cocaina y LSD; el precio sale
    de DEALERS.CATALOG y la compra la valida rp_shops.

    Si al comprar hay un policia mirando (peaton IA visto por el cliente, o un
    policia jugador cerca) rp_wanted da una estrella (delito "drug_buy").

    Comandos (admin_level >= 1):
        /creartraficante [28|29|30]   crea un traficante en tu posicion
        /borrartraficante <id>        lo elimina
        /traficantes                  lista los traficantes
]]

addEvent("rp:onDatabaseReady", false)
addEvent("rp:shop:onBought", false)       -- de rp_shops
addEvent("rp:dealers:copSeen", true)

local dealers = {}      -- [id] = { row, ped, shopId, blip }
local byShop = {}       -- [shopId] = id
local copSeen = {}      -- [player] = tick

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function registerShop(id)
    local d = dealers[id]
    if not d or not isElement(d.ped) then return end
    if d.shopId then byShop[d.shopId] = nil end
    local ok, shopId = pcall(function() return exports.rp_shops:addTempShop(d.ped, "Traficante", DEALERS.CATALOG) end)
    if ok and shopId then
        d.shopId = shopId
        byShop[shopId] = id
    else
        d.shopId = nil
        outputDebugString("[rp_dealers] rp_shops:addTempShop fallo para el traficante #" .. id, 2)
    end
end

local function destroyDealer(id)
    local d = dealers[id]
    if not d then return end
    if d.shopId then
        pcall(function() exports.rp_shops:removeTempShop(d.shopId) end)
        byShop[d.shopId] = nil
    end
    if isElement(d.ped) then destroyElement(d.ped) end
    dealers[id] = nil
end

local function spawnDealer(row)
    local id = tonumber(row.id)
    destroyDealer(id)
    local ped = createPed(tonumber(row.ped_skin), row.x, row.y, row.z, row.rotation)
    if not ped then return outputDebugString("[rp_dealers] No se pudo crear el traficante #" .. id, 2) end
    setElementFrozen(ped, true)
    setElementInterior(ped, row.interior)
    setElementDimension(ped, row.dimension)
    setElementData(ped, "rp:dealer", id)
    dealers[id] = { row = row, ped = ped }
    registerShop(id)
end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do spawnDealer(row) end
        outputDebugString(("[rp_dealers] %d traficantes cargados"):format(#rows))
    end, db(), "SELECT * FROM dealers")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

-- Si rp_shops se reinicia pierde las tiendas temporales: se vuelven a registrar
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rp_shops" then return end
    setTimer(function() for id in pairs(dealers) do registerShop(id) end end, 1000, 1)
end)

addEventHandler("onPlayerQuit", root, function() copSeen[source] = nil end)

----------------------------------------------------------------
-- Policia a la vista al comprar
----------------------------------------------------------------
addEventHandler("rp:dealers:copSeen", resourceRoot, function()
    local px, py, pz = getElementPosition(client)
    for _, d in pairs(dealers) do   -- solo vale junto a un traficante
        if isElement(d.ped) and getElementDimension(d.ped) == getElementDimension(client)
            and getDistanceBetweenPoints3D(px, py, pz, getElementPosition(d.ped)) <= 10 then
            copSeen[client] = getTickCount()
            return
        end
    end
end)

local function copPlayerNear(player)
    local x, y, z = getElementPosition(player)
    for _, el in ipairs(getElementsWithinRange(x, y, z, DEALERS.COP_RADIUS, "player")) do
        if el ~= player and not isPedDead(el) and getElementDimension(el) == getElementDimension(player)
            and exports.rp_wanted:isWantedPolice(el) then
            return true
        end
    end
    return false
end

addEventHandler("rp:shop:onBought", root, function(shopId)
    local player = source
    local id = byShop[shopId]
    if not id then return end
    local seen = copSeen[player] and getTickCount() - copSeen[player] <= DEALERS.COP_REPORT_MS
    if not seen and not copPlayerNear(player) then return end
    copSeen[player] = nil
    if exports.rp_wanted:reportCrime(player, "drug_buy", id, false, "police") then
        notify(player, "¡Un policia te vio comprando drogas!", "error")
    end
end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
addCommandHandler("creartraficante", function(player, _, skin)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    skin = tonumber(skin) or DEALERS.DEFAULT_SKIN
    if not DEALERS.SKINS[skin] then return notify(player, "Uso: /creartraficante [28|29|30]", "warning") end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local interior, dimension = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local result, _, id = dbPoll(qh, 0)
        if not result then return outputDebugString("[rp_dealers] Error al crear el traficante", 1) end
        spawnDealer({ id = id, ped_skin = skin, x = x, y = y, z = z, rotation = rot, interior = interior, dimension = dimension })
        if isElement(player) then
            setElementPosition(player, x + math.sin(math.rad(rot)) * -1.5, y + math.cos(math.rad(rot)) * 1.5, z)
            notify(player, ("Traficante #%d creado (skin %d)."):format(id, skin), "success")
        end
    end, db(), "INSERT INTO dealers (ped_skin, x, y, z, rotation, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?)",
        skin, x, y, z, rot, interior, dimension)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbydealers, /gotodealer, /deldealer...)
function adminElements()
    local list = {}
    for id, e in pairs(dealers) do
        local row = e.row
        if row then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = row.interior, dimension = row.dimension, label = "Traficante skin " .. tostring(row.ped_skin),
                rot = tonumber(row.rotation) or 0, element = e.ped }
        end
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not dealers[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM dealers WHERE id = ?", id)
    destroyDealer(id)
    return true
end

-- Mover desde el editor de rp_admin (vista ALT): guarda y vuelve a crear el traficante
function adminMove(id, _, x, y, z, rot)
    id = tonumber(id)
    local d = id and dealers[id]
    if not d then return false, "no existe" end
    local row = d.row
    row.x, row.y, row.z, row.rotation = x, y, z, rot
    dbExec(db(), "UPDATE dealers SET x = ?, y = ?, z = ?, rotation = ? WHERE id = ?", x, y, z, rot, id)
    spawnDealer(row)
    return true
end

addCommandHandler("borrartraficante", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrartraficante <id> (ver /traficantes)", "warning") end
    notify(player, ("Traficante #%d eliminado."):format(id), "success")
end)

addCommandHandler("traficantes", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local n = 0
    for id, d in pairs(dealers) do
        n = n + 1
        outputChatBox(("#%d skin %d en %.1f, %.1f, %.1f (int %d)"):format(id, d.row.ped_skin, d.row.x, d.row.y, d.row.z, d.row.interior), player, 255, 255, 255)
    end
    if n == 0 then notify(player, "No hay traficantes.", "info") end
end)
