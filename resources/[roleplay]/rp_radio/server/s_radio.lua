--[[
    rp_radio / s_radio.lua

    La radio de cada vehiculo es un dato sincronizado (rp:radio = id de emisora). El servidor
    solo valida quien puede cambiarla; cada cliente reproduce el stream por su cuenta.
    Pueden cambiarla el conductor y el copiloto (asientos 0 y 1).

    Comandos:
        /radio              abre el panel de emisoras (dentro de un vehiculo)
        /radio apagar       apaga la radio del vehiculo
]]

addEvent("rp:radio:set", true)

local cooldown = {}   -- [player] = tick

local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end

local function canControl(player, vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    if getPedOccupiedVehicle(player) ~= vehicle then return false end
    local seat = getPedOccupiedVehicleSeat(player)
    return seat == 0 or seat == 1
end

local function applyStation(vehicle, id)
    -- false (no nil) = apagada: asi el cambio se sincroniza siempre a los clientes
    setElementData(vehicle, RADIO_DATA_KEY, id or false, true)
    -- una sola fuente por vehiculo: al encender la radio se apaga la musica del telefono (rp_phone)
    if id then pcall(function() exports.rp_phone:stopVehicleMusic(vehicle) end) end
end

function getVehicleStation(vehicle)
    if not isElement(vehicle) then return false end
    return getElementData(vehicle, RADIO_DATA_KEY) or false
end

function setVehicleStation(vehicle, id)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    id = tonumber(id)
    if id and not RADIO_BY_ID[id] then return false end
    applyStation(vehicle, id)
    return true
end

addEventHandler("rp:radio:set", resourceRoot, function(id)
    local player = client
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 400 then return end
    cooldown[player] = now

    local vehicle = getPedOccupiedVehicle(player)
    if not canControl(player, vehicle) then
        notify(player, "Solo el conductor o el copiloto controlan la radio.", "warning")
        return
    end

    if id == false or id == nil then
        applyStation(vehicle, nil)
        return
    end
    id = tonumber(id)
    if not id or not RADIO_BY_ID[id] then return end
    applyStation(vehicle, id)
end)

addCommandHandler("radio", function(player, _, arg)
    if not getElementData(player, "rp:characterId") then return end
    local vehicle = getPedOccupiedVehicle(player)
    if not canControl(player, vehicle) then
        notify(player, "Debes ir de conductor o copiloto para usar la radio.", "warning")
        return
    end
    if arg == "apagar" then
        applyStation(vehicle, nil)
        return
    end
    triggerClientEvent(player, "rp:radio:open", resourceRoot)
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)
