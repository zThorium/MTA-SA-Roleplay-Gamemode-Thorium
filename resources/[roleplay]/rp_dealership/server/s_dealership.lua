--[[
    rp_dealership / s_dealership.lua
    Concesionario: cada ROTATION_INTERVAL se eligen al azar autos del catalogo
    y se exhiben en los puestos fijos. Al comprar, el auto se crea en el punto
    de entrega (comprobando que no caiga bajo el mapa) y el jugador queda
    montado. Se paga desde la cuenta bancaria.

    Admin:
        /dealer puesto <1-n>   mueve ese puesto a tu posicion (o la de tu vehiculo)
        /dealer entrega        mueve el punto de entrega a tu posicion
        /dealer rotar          cambia los autos ahora
]]

local SPOTS_FILE = "dealer_spots.json"
local spots = nil
local display = {}       -- [index] = { vehicle, col, entry }
local nearSpot = {}      -- [player] = index
local nextRotation = 0
local busy = {}

addEvent("rp:dealer:open", true)
addEvent("rp:dealer:buy", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

----------------------------------------------------------------
-- Puestos (configurables en juego)
----------------------------------------------------------------
local function loadSpots()
    if fileExists(SPOTS_FILE) then
        local f = fileOpen(SPOTS_FILE, true)
        local data = f and fromJSON(fileRead(f, fileGetSize(f)))
        if f then fileClose(f) end
        if type(data) == "table" and data.display and data.delivery then return data end
    end
    return DEFAULT_SPOTS
end

local function saveSpots()
    if fileExists(SPOTS_FILE) then fileDelete(SPOTS_FILE) end
    local f = fileCreate(SPOTS_FILE)
    if f then
        fileWrite(f, toJSON(spots, true))
        fileClose(f)
    end
end

----------------------------------------------------------------
-- Rotacion de autos
----------------------------------------------------------------
local function clearDisplay()
    for _, d in pairs(display) do
        if isElement(d.vehicle) then destroyElement(d.vehicle) end
        if isElement(d.col) then destroyElement(d.col) end
    end
    display = {}
    for player in pairs(nearSpot) do
        if isElement(player) then triggerClientEvent(player, "rp:dealer:near", resourceRoot, false) end
    end
    nearSpot = {}
end

local function shuffledCatalog()
    local list = {}
    for i, c in ipairs(CATALOG) do list[i] = c end
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function rotate()
    clearDisplay()
    local picks = shuffledCatalog()
    for i, s in ipairs(spots.display) do
        local c = picks[i]
        if not c then break end
        local v = createVehicle(c[1], s[1], s[2], s[3], s[4] or 0, s[5] or 0, s[6] or 0, "VENTA")
        if v then
            local color = COLORS[math.random(#COLORS)]
            setVehicleColor(v, color[2], color[3], color[4], color[2], color[3], color[4])
            setVehicleLocked(v, true)
            setVehicleDamageProof(v, true)
            setVehicleEngineState(v, false)
            setVehicleOverrideLights(v, 1)
            local entry = { model = c[1], name = c[2], price = c[3], category = c[4], spot = i }
            setElementData(v, "rp:dealer", entry)

            local col = createColSphere(s[1], s[2], s[3], DEALER.VIEW_RADIUS)
            display[i] = { vehicle = v, col = col, entry = entry }
            addEventHandler("onColShapeHit", col, function(el, sameDim)
                if getElementType(el) == "player" and sameDim and not isPedInVehicle(el) and characterOf(el) then
                    nearSpot[el] = i
                    triggerClientEvent(el, "rp:dealer:near", resourceRoot, entry)
                end
            end)
            addEventHandler("onColShapeLeave", col, function(el)
                if getElementType(el) == "player" and nearSpot[el] == i then
                    nearSpot[el] = nil
                    triggerClientEvent(el, "rp:dealer:near", resourceRoot, false)
                end
            end)
        end
    end
    nextRotation = getTickCount() + DEALER.ROTATION_INTERVAL
    setElementData(resourceRoot, "rp:dealer:nextRotation", getRealTime().timestamp + math.floor(DEALER.ROTATION_INTERVAL / 1000))
end

addEventHandler("onResourceStart", resourceRoot, function()
    spots = loadSpots()
    rotate()
    setTimer(rotate, DEALER.ROTATION_INTERVAL, 0)
    local s = spots.display[1]
    createBlip(s[1], s[2], s[3], 55, 2, 255, 255, 255, 255, 0, 500)
end)

----------------------------------------------------------------
-- Compra
----------------------------------------------------------------
-- Comprueba durante unos segundos que el vehiculo no atraviese el suelo
local function guardFall(vehicle, x, y, z)
    local checks = 0
    setTimer(function()
        checks = checks + 1
        if not isElement(vehicle) then return end
        local _, _, vz = getElementPosition(vehicle)
        if vz < z - 6 then
            setElementVelocity(vehicle, 0, 0, 0)
            setElementPosition(vehicle, x, y, z + 1.5)
        end
    end, 500, 8)
end

addEventHandler("rp:dealer:open", resourceRoot, function()
    local player = client
    local i = nearSpot[player]
    if not i or not display[i] then return end
    local e = display[i].entry
    local handling = getModelHandling(e.model)
    triggerClientEvent(player, "rp:dealer:show", resourceRoot, {
        spot = i, model = e.model, name = e.name, price = e.price, category = e.category,
        maxSpeed = handling and math.floor(handling.maxVelocity) or 0,
        seats = getVehicleMaxPassengers(display[i].vehicle) + 1,
        colors = COLORS,
        nextRotation = math.max(0, math.ceil((nextRotation - getTickCount()) / 60000)),
    })
end)

addEventHandler("rp:dealer:buy", resourceRoot, function(spot, colorIndex)
    local player = client
    spot, colorIndex = tonumber(spot), tonumber(colorIndex) or 1
    local characterId = characterOf(player)
    if not characterId or busy[player] or nearSpot[player] ~= spot or not display[spot] then return end
    local entry = display[spot].entry
    local color = COLORS[colorIndex] or COLORS[1]

    if exports.rp_vehicles:countOwnedVehicles(characterId) >= DEALER.MAX_VEHICLES then
        return notify(player, ("Solo puedes tener %d vehiculos."):format(DEALER.MAX_VEHICLES), "error")
    end

    busy[player] = true
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        busy[player] = nil
        if not isElement(player) then return end
        if not affected or affected == 0 then
            return notify(player, ("Necesitas $%d en tu cuenta bancaria."):format(entry.price), "error")
        end

        local d = spots.delivery
        local vehicle = exports.rp_vehicles:createOwnedVehicle(player, entry.model, { color[2], color[3], color[4] }, d[1], d[2], d[3], d[6] or 0)
        if not vehicle then
            dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", entry.price, characterId)
            return notify(player, "No se pudo entregar el vehiculo. Se te devolvio el dinero.", "error")
        end
        dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'purchase', ?, ?)", characterId, entry.price, entry.name)

        guardFall(vehicle, d[1], d[2], d[3])
        triggerClientEvent(player, "rp:dealer:near", resourceRoot, false)
        nearSpot[player] = nil
        fadeCamera(player, false, 0.4)
        setTimer(function()
            if not isElement(player) or not isElement(vehicle) then return end
            removePedFromVehicle(player)
            warpPedIntoVehicle(player, vehicle, 0)
            setCameraTarget(player, player)
            fadeCamera(player, true, 0.8)
            exports.rp_notify:popup(player, "Vehiculo comprado", entry.name .. " ya es tuyo. La llave esta en tu inventario: J enciende el motor y L lo abre o cierra.", "success")
        end, 500, 1)
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", entry.price, characterId, entry.price)
end)

-- Los autos en exhibicion no se pueden conducir
addEventHandler("onVehicleStartEnter", root, function(player)
    if getElementData(source, "rp:dealer") then cancelEvent() end
end)

addEventHandler("onPlayerQuit", root, function() nearSpot[source], busy[source] = nil, nil end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
addCommandHandler("dealer", function(player, _, action, index)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 1 then
        return notify(player, "No tienes permiso para usar este comando.", "error")
    end
    local el = getPedOccupiedVehicle(player) or player
    local x, y, z = getElementPosition(el)
    local _, _, rz = getElementRotation(el)
    if action == "puesto" then
        index = tonumber(index)
        if not index or index < 1 or index > #spots.display + 1 then
            return notify(player, ("Uso: /dealer puesto <1-%d>"):format(#spots.display + 1), "warning")
        end
        spots.display[index] = { x, y, z + 0.6, 0, 0, rz }
        saveSpots()
        rotate()
        notify(player, ("Puesto %d guardado."):format(index), "success")
    elseif action == "entrega" then
        spots.delivery = { x, y, z + 0.8, 0, 0, rz }
        saveSpots()
        notify(player, "Punto de entrega guardado.", "success")
    elseif action == "rotar" then
        rotate()
        notify(player, "Autos del concesionario renovados.", "success")
    else
        notify(player, "Uso: /dealer puesto <n> | entrega | rotar", "warning")
    end
end)
