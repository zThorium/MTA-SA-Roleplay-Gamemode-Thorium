--[[
    rp_vehicles / s_tuning.lua
    Taller de tuning y persistencia de todo lo aplicado al vehiculo.

    Todo cambio (colores, faros, paintjob, piezas, nitro, hidraulica, ruedas...)
    se guarda en vehicles.tuning (JSON) cada vez que se guarda el vehiculo y se
    vuelve a aplicar al crearlo cuando arranca el servidor:
        { c = {r1, g1, b1, r2, g2, b2}, h = {r, g, b}, p = paintjob, u = {ids} }

    Talleres en TUNING.SHOPS (shared/s_config.lua). El dueno entra con su auto
    al circulo, pulsa E (o /tunear), elige y paga en efectivo.
]]

addEvent("rp:tune:open", true)
addEvent("rp:tune:buy", true)
addEvent("rp:tune:close", true)
addEvent("rp:tune:repair", true)

local shopMarkers = {}   -- [marker] = shop
local tuning = {}        -- [player] = vehicle (panel abierto)

-- Modelos con paintjobs de fabrica (0-2)
local PAINTJOB_MODELS = { [483] = 1, [534] = 3, [535] = 3, [536] = 3, [558] = 3, [559] = 3, [560] = 3, [561] = 3,
    [562] = 3, [565] = 3, [567] = 3, [575] = 2, [576] = 3 }

local UPGRADE_NAMES = {
    [1008] = "Nitro x5", [1009] = "Nitro x2", [1010] = "Nitro x10", [1087] = "Hidraulica", [1086] = "Estereo con bajos",
    [1025] = "Offroad", [1073] = "Shadow", [1074] = "Mega", [1075] = "Rimshine", [1076] = "Wires", [1077] = "Classic",
    [1078] = "Twist", [1079] = "Cutter", [1080] = "Switch", [1081] = "Grove", [1082] = "Import", [1083] = "Dollar",
    [1084] = "Trance", [1085] = "Atomic", [1096] = "Ahab", [1097] = "Virtual", [1098] = "Access",
}

----------------------------------------------------------------
-- Persistencia
----------------------------------------------------------------
function applyTuning(vehicle, json)
    local t = type(json) == "string" and fromJSON(json) or json
    if type(t) ~= "table" then return end
    if type(t.c) == "table" and #t.c >= 6 then setVehicleColor(vehicle, unpack(t.c, 1, 6)) end
    if type(t.h) == "table" and #t.h >= 3 then setVehicleHeadLightColor(vehicle, t.h[1], t.h[2], t.h[3]) end
    if tonumber(t.p) and tonumber(t.p) < 3 then setVehiclePaintjob(vehicle, tonumber(t.p)) end
    if type(t.u) == "table" then
        for _, id in ipairs(t.u) do
            if tonumber(id) then addVehicleUpgrade(vehicle, tonumber(id)) end
        end
    end
end

function captureTuning(vehicle)
    local c = { getVehicleColor(vehicle, true) }
    local r, g, b = getVehicleHeadLightColor(vehicle)
    return {
        c = { c[1], c[2], c[3], c[4], c[5], c[6] },
        h = { r, g, b },
        p = getVehiclePaintjob(vehicle),
        u = getVehicleUpgrades(vehicle) or {},
    }
end

----------------------------------------------------------------
-- Talleres
----------------------------------------------------------------
-- Posiciones de los talleres: las de shared/s_config.lua, salvo las que un
-- admin movio con /taller mover <n> (se guardan en tuning_shops.json)
local SHOPS_FILE = "tuning_shops.json"
local shops = {}
local shopElements = {}

local function loadShops()
    shops = {}
    for i, shop in ipairs(TUNING.SHOPS) do
        shops[i] = { name = shop.name, x = shop.x, y = shop.y, z = shop.z, rz = shop.rz, radius = shop.radius }
    end
    if fileExists(SHOPS_FILE) then
        local f = fileOpen(SHOPS_FILE, true)
        local saved = f and fromJSON(fileRead(f, fileGetSize(f)))
        if f then fileClose(f) end
        if type(saved) == "table" then
            for k, pos in pairs(saved) do
                local i = tonumber(k)
                if shops[i] and type(pos) == "table" and tonumber(pos.x) then
                    shops[i].x, shops[i].y, shops[i].z, shops[i].rz = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z), tonumber(pos.rz)
                end
            end
        end
    end
end

local function saveShops()
    local out = {}
    for i, shop in ipairs(shops) do out[tostring(i)] = { x = shop.x, y = shop.y, z = shop.z, rz = shop.rz } end
    if fileExists(SHOPS_FILE) then fileDelete(SHOPS_FILE) end
    local f = fileCreate(SHOPS_FILE)
    if f then fileWrite(f, toJSON(out, true)) fileClose(f) end
end

local function buildShops()
    for _, el in ipairs(shopElements) do if isElement(el) then destroyElement(el) end end
    shopElements, shopMarkers = {}, {}
    for _, shop in ipairs(shops) do
        local m = createMarker(shop.x, shop.y, shop.z - 1, "cylinder", shop.radius, 255, 170, 0, 90)
        shopMarkers[m] = shop
        exports.rp_markers:setMarkerStyle(m, { icon = "wrench", label = shop.name and ("Taller " .. shop.name) or "Taller" })
        shopElements[#shopElements + 1] = m
        shopElements[#shopElements + 1] = createBlip(shop.x, shop.y, shop.z, 27, 2, 0, 0, 0, 255, 0, 99999)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    loadShops()
    buildShops()
end)

function getTuningShops() return shops end

-- Mueve el taller n a donde esta el auto del admin (con su orientacion).
-- Elige un lugar abierto: ahi se pone el auto al tunear.
local function moveShop(player, index)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    index = tonumber(index)
    if not index or not shops[index] then return notify(player, "Uso: /movertaller <numero> (ver /nearbytalleres)", "warning") end
    local el = getPedOccupiedVehicle(player) or player
    local x, y, z = getElementPosition(el)
    local _, _, rz = getElementRotation(el)
    local shop = shops[index]
    shop.x, shop.y, shop.z, shop.rz = x, y, z, rz
    saveShops()
    buildShops()
    notify(player, ("Taller %s movido a tu posicion."):format(shop.name), "success")
end

addCommandHandler("movertaller", function(player, _, index) moveShop(player, index) end)
addCommandHandler("taller", function(player, _, action, index)
    if action == "mover" then return moveShop(player, index) end
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    for i, shop in ipairs(shops) do
        outputChatBox(("%d. %s (%.1f, %.1f, %.1f)"):format(i, shop.name, shop.x, shop.y, shop.z), player, 245, 165, 36)
    end
end)

local function ownedDriverVehicle(player)
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player then return nil end
    local data = getVehicleData(v)
    if not data or data.ownerId ~= characterOf(player) then return nil end
    return v, data
end

local hiddenMarker = {} -- [player] = marker oculto mientras tunea

local function shopOf(vehicle)
    for m, shop in pairs(shopMarkers) do
        if isElementWithinMarker(vehicle, m) then return shop, m end
    end
end

-- Oculta el marker del taller para todos mientras alguien lo usa (taller ocupado)
local markerUsers = {} -- [marker] = jugadores tuneando
local function hideShopMarker(player, marker)
    if not marker then return end
    hiddenMarker[player] = marker
    markerUsers[marker] = (markerUsers[marker] or 0) + 1
    setElementVisibleTo(marker, root, false)
end

local function showShopMarker(player)
    local marker = hiddenMarker[player]
    hiddenMarker[player] = nil
    if not marker then return end
    markerUsers[marker] = math.max(0, (markerUsers[marker] or 1) - 1)
    if markerUsers[marker] == 0 and isElement(marker) then setElementVisibleTo(marker, root, true) end
end

-- El marcador puede detectar al vehiculo o al jugador; se usa siempre al conductor
local function driverOf(element)
    if getElementType(element) == "vehicle" then return getVehicleController(element) end
    if getElementType(element) == "player" then return element end
end

addEventHandler("onMarkerHit", resourceRoot, function(element, dim)
    local hit = dim and driverOf(element)
    local shop = shopMarkers[source]
    if not hit or not shop then return end
    if ownedDriverVehicle(hit) then
        triggerClientEvent(hit, "rp:tune:near", resourceRoot, shop.name)
    elseif getPedOccupiedVehicle(hit) then
        notify(hit, "Solo el dueno puede tunear el vehiculo.", "warning")
    end
end)

addEventHandler("onMarkerLeave", resourceRoot, function(element)
    local left = driverOf(element)
    if shopMarkers[source] and left then
        triggerClientEvent(left, "rp:tune:near", resourceRoot, false)
    end
end)

-- Piezas compatibles por slot: { [slot] = { ids } } y { [id] = slot }
local function compatibleBySlot(vehicle)
    local bySlot, slotOf = {}, {}
    for slot = 0, 16 do
        local list = getVehicleCompatibleUpgrades(vehicle, slot)
        if list and #list > 0 then
            bySlot[slot] = list
            for _, id in ipairs(list) do slotOf[id] = slot end
        end
    end
    return bySlot, slotOf
end

local function catalog(vehicle)
    local out = {}
    local bySlot = compatibleBySlot(vehicle)
    for slot, ids in pairs(bySlot) do
        local list = {}
        for i, id in ipairs(ids) do
            list[#list + 1] = { id = id, name = UPGRADE_NAMES[id] or ((TUNING_SLOT_NAMES[slot] or "Pieza") .. " " .. i), price = getUpgradePrice(id, slot) }
        end
        out[#out + 1] = { slot = slot, name = TUNING_SLOT_NAMES[slot] or ("Slot " .. slot), upgrades = list,
            current = getVehicleUpgradeOnSlot(vehicle, slot) or 0 }
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

local function close(player)
    local v = tuning[player]
    tuning[player] = nil
    showShopMarker(player)
    if isElement(v) then updateFrozen(v) end
end

-- Para s_perf.lua: vehiculo que el jugador esta tuneando y taller donde esta
function getTuningVehicle(player) return tuning[player] end
function getVehicleTuningShop(vehicle) return (shopOf(vehicle)) end
function isVehicleInTuningShop(vehicle) return shopOf(vehicle) ~= nil end

-- Reparacion: base + segun el dano del motor (vida de 1000 a 0)
function repairPrice(v)
    local health = getElementHealth(v)
    if health >= 999 then return TUNING.REPAIR_BASE end
    return math.floor(TUNING.REPAIR_BASE + (1000 - health) * TUNING.REPAIR_PER_POINT)
end

-- Datos del panel (al entrar y tras cada compra, para seguir tuneando)
function sendTuning(player, v, shop)
    local data = getVehicleData(v)
    triggerClientEvent(player, "rp:tune:show", resourceRoot, v, {
        shop = shop.name, name = getVehicleNameFromModel(data.model), plate = data.plate,
        slots = catalog(v), state = captureTuning(v), paintjobs = PAINTJOB_MODELS[data.model] or 0,
        prices = { color = TUNING.PRICE_COLOR, paintjob = TUNING.PRICE_PAINTJOB, remove = TUNING.PRICE_REMOVE },
        money = getPlayerMoney(player), health = math.floor(getElementHealth(v) / 10), repair = repairPrice(v),
        repaired = getElementHealth(v) >= 999,
        perf = getPerfPanel and getPerfPanel(v) or nil,
    })
end

addEventHandler("rp:tune:open", resourceRoot, function()
    local player = client
    local v, data = ownedDriverVehicle(player)
    if not v then return notify(player, "Debes estar al volante de tu vehiculo.", "warning") end
    local shop, marker = shopOf(v)
    if not shop then return notify(player, "No estas en un taller.", "warning") end
    if vehicleSpeedKmh(v) > 5 then return notify(player, "Detente para entrar al taller.", "warning") end
    tuning[player] = v
    hideShopMarker(player, marker)
    setElementFrozen(v, true)
    -- Si el taller tiene orientacion guardada, el auto queda justo en el punto
    if shop.rz then
        setElementPosition(v, shop.x, shop.y, shop.z + 0.3)
        setElementRotation(v, 0, 0, shop.rz)
    end
    sendTuning(player, v, shop)
end)

addEventHandler("rp:tune:close", resourceRoot, function() close(client) end)

local function validColor(c)
    if type(c) ~= "table" then return false end
    for i = 1, #c do
        local n = tonumber(c[i])
        if not n or n < 0 or n > 255 or n ~= math.floor(n) then return false end
    end
    return true
end

local function sameColor(a, b, n)
    for i = 1, n do if tonumber(a[i]) ~= tonumber(b[i]) then return false end end
    return true
end

addEventHandler("rp:tune:buy", resourceRoot, function(cart)
    local player = client
    local v = tuning[player]
    if not v or not isElement(v) or getPedOccupiedVehicle(player) ~= v or type(cart) ~= "table" then return end
    local data = getVehicleData(v)
    if not data or data.ownerId ~= characterOf(player) or not shopOf(v) then return close(player) end

    local current = captureTuning(v)
    local total, changes = 0, {}

    -- Colores de carroceria (primario + secundario)
    if cart.colors ~= nil then
        if not validColor(cart.colors) or #cart.colors ~= 6 then return end
        if not sameColor(cart.colors, current.c, 3) then total = total + TUNING.PRICE_COLOR end
        if not sameColor({ cart.colors[4], cart.colors[5], cart.colors[6] }, { current.c[4], current.c[5], current.c[6] }, 3) then
            total = total + TUNING.PRICE_COLOR
        end
        changes.colors = cart.colors
    end
    if cart.headlight ~= nil then
        if not validColor(cart.headlight) or #cart.headlight ~= 3 then return end
        if not sameColor(cart.headlight, current.h, 3) then total = total + TUNING.PRICE_COLOR end
        changes.headlight = cart.headlight
    end
    if cart.paintjob ~= nil then
        local pj = tonumber(cart.paintjob)
        local max = PAINTJOB_MODELS[data.model] or 0
        if not pj or pj ~= math.floor(pj) or pj < 0 or (pj > max - 1 and pj ~= 3) then return end
        if pj ~= current.p then
            total = total + TUNING.PRICE_PAINTJOB
            changes.paintjob = pj
        end
    end

    -- Piezas nuevas: deben ser compatibles y no estar ya puestas
    local _, slotOf = compatibleBySlot(v)
    changes.add = {}
    if type(cart.upgrades) == "table" then
        local usedSlots = {}
        for _, id in ipairs(cart.upgrades) do
            id = tonumber(id)
            local slot = id and slotOf[id]
            if not slot then return notify(player, "Esa pieza no es compatible.", "error") end
            if usedSlots[slot] then return end
            usedSlots[slot] = true
            if getVehicleUpgradeOnSlot(v, slot) ~= id then
                total = total + getUpgradePrice(id, slot)
                changes.add[#changes.add + 1] = id
            end
        end
    end
    changes.remove = {}
    if type(cart.remove) == "table" then
        for _, slot in ipairs(cart.remove) do
            slot = tonumber(slot)
            local installed = slot and getVehicleUpgradeOnSlot(v, slot)
            if installed and installed ~= 0 then
                total = total + TUNING.PRICE_REMOVE
                changes.remove[#changes.remove + 1] = installed
            end
        end
    end

    if total <= 0 then return notify(player, "No elegiste ningun cambio.", "warning") end
    if getPlayerMoney(player) < total then
        return notify(player, ("Necesitas $%d en efectivo."):format(total), "error")
    end
    takePlayerMoney(player, total)

    for _, id in ipairs(changes.remove) do removeVehicleUpgrade(v, id) end
    for _, id in ipairs(changes.add) do addVehicleUpgrade(v, id) end
    if changes.colors then setVehicleColor(v, unpack(changes.colors, 1, 6)) end
    if changes.headlight then setVehicleHeadLightColor(v, unpack(changes.headlight, 1, 3)) end
    if changes.paintjob then setVehiclePaintjob(v, changes.paintjob) end
    saveVehicle(v)
    exports.rp_characters:saveCharacter(player)

    notify(player, ("Tuning aplicado por $%d."):format(total), "success")
    triggerClientEvent(player, "rp:tune:sound", resourceRoot, "install")
    -- Sigue en el taller con el estado nuevo
    sendTuning(player, v, shopOf(v) or { name = "Taller" })
end)

addEventHandler("onPlayerQuit", root, function() close(source) end)
addEventHandler("onPlayerVehicleExit", root, function() if tuning[source] then close(source) triggerClientEvent(source, "rp:tune:done", resourceRoot, false) end end)

addEventHandler("rp:tune:repair", resourceRoot, function()
    local player = client
    local v = tuning[player]
    if not v or not isElement(v) or getPedOccupiedVehicle(player) ~= v or not shopOf(v) then return end
    -- Ya al 100%: no se cobra (el panel tambien lo deshabilita, pero el servidor valida)
    if getElementHealth(v) >= 999 then return notify(player, "Tu vehiculo ya esta reparado.", "warning") end
    local price = repairPrice(v)
    if getPlayerMoney(player) < price then return notify(player, ("Necesitas $%d en efectivo."):format(price), "error") end
    takePlayerMoney(player, price)
    fixVehicle(v)
    saveVehicle(v)
    exports.rp_characters:saveCharacter(player)
    notify(player, ("Vehiculo reparado por $%d."):format(price), "success")
    sendTuning(player, v, shopOf(v) or { name = "Taller" })
end)
