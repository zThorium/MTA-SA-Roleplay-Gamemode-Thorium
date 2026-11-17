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
addEventHandler("onResourceStart", resourceRoot, function()
    for _, shop in ipairs(TUNING.SHOPS) do
        local m = createMarker(shop.x, shop.y, shop.z - 1, "cylinder", shop.radius, 255, 170, 0, 90)
        shopMarkers[m] = shop
        createBlip(shop.x, shop.y, shop.z, 27, 2, 0, 0, 0, 255, 0, 400)
    end
end)

local function ownedDriverVehicle(player)
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player then return nil end
    local data = getVehicleData(v)
    if not data or data.ownerId ~= characterOf(player) then return nil end
    return v, data
end

local function shopOf(vehicle)
    for m, shop in pairs(shopMarkers) do
        if isElementWithinMarker(vehicle, m) then return shop end
    end
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
    if isElement(v) then updateFrozen(v) end
end

addEventHandler("rp:tune:open", resourceRoot, function()
    local player = client
    local v, data = ownedDriverVehicle(player)
    if not v then return notify(player, "Debes estar al volante de tu vehiculo.", "warning") end
    local shop = shopOf(v)
    if not shop then return notify(player, "No estas en un taller.", "warning") end
    if vehicleSpeedKmh(v) > 5 then return notify(player, "Detente para entrar al taller.", "warning") end
    tuning[player] = v
    setElementFrozen(v, true)
    local t = captureTuning(v)
    triggerClientEvent(player, "rp:tune:show", resourceRoot, v, {
        shop = shop.name, name = getVehicleNameFromModel(data.model), plate = data.plate,
        slots = catalog(v), state = t, paintjobs = PAINTJOB_MODELS[data.model] or 0,
        prices = { color = TUNING.PRICE_COLOR, paintjob = TUNING.PRICE_PAINTJOB, remove = TUNING.PRICE_REMOVE },
        money = getPlayerMoney(player),
    })
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
    triggerClientEvent(player, "rp:tune:done", resourceRoot, true)
    close(player)
end)

addEventHandler("onPlayerQuit", root, function() close(source) end)
addEventHandler("onPlayerVehicleExit", root, function() if tuning[source] then close(source) triggerClientEvent(source, "rp:tune:done", resourceRoot, false) end end)
