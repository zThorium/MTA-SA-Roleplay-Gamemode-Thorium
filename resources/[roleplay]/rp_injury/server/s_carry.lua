--[[
    rp_injury / s_carry.lua
    /cargar <ID>: carga al hombro a un jugador abatido cercano (attachElements).
      - /cargar sin ID o /soltar: lo deja en el suelo.
      - Al subir el cargador a un vehiculo, el herido se sienta en un asiento libre.
      - /cargar <ID> sobre un herido sentado en un vehiculo lo baja y lo carga.
    elementData "rp:carried" (solo servidor): true mientras va al hombro.
    elementData "rp:loaded": true si va dentro de un vehiculo (exento de la expulsion de abatidos).
]]

local carrying = {}   -- [cargador] = herido
local carried = {}    -- [herido] = cargador

local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end

local function drop(carrier, target)
    carrying[carrier], carried[target] = nil, nil
    if not isElement(target) then return end
    detachElements(target)
    setTimer(function() if isElement(target) and not carried[target] and not isPedInVehicle(target) then setElementCollisionsEnabled(target, true) end end, 300, 1)
    setElementData(target, "rp:carried", false)
    if isElement(carrier) then
        local x, y, z = getElementPosition(carrier)
        local _, _, rz = getElementRotation(carrier)
        local a = math.rad(rz)
        setElementPosition(target, x - math.sin(a) * -0.9, y + math.cos(a) * -0.9, z - 0.2)
        setElementRotation(target, 0, 0, rz)
        setElementInterior(target, getElementInterior(carrier))
        setElementDimension(target, getElementDimension(carrier))
    end
    if getElementData(target, "rp:downed") == true then
        setPedAnimation(target, INJURY.ANIM_BLOCK, INJURY.ANIM_NAME, -1, true, false, false, true)
    end
end

local function dropByCarrier(carrier) if carrying[carrier] then drop(carrier, carrying[carrier]) end end
local function dropByTarget(target) if carried[target] then drop(carried[target], target) end end

local function pick(carrier, target)
    local C = INJURY.CARRY
    local v = getPedOccupiedVehicle(target)
    if v then removePedFromVehicle(target) end
    setElementData(target, "rp:loaded", false)
    setElementInterior(target, getElementInterior(carrier))
    setElementDimension(target, getElementDimension(carrier))
    setElementCollisionsEnabled(target, false)
    attachElements(target, carrier, C.X, C.Y, C.Z, C.RX, C.RY, C.RZ)
    setPedAnimation(target, INJURY.ANIM_BLOCK, INJURY.ANIM_NAME, -1, true, false, false, true)
    carrying[carrier], carried[target] = target, carrier
    setElementData(target, "rp:carried", true)
end

addCommandHandler("cargar", function(player, _, query)
    if carrying[player] then return drop(player, carrying[player]) end
    if not query then return notify(player, "Uso: /cargar <ID>", "error") end
    if getElementData(player, "rp:downed") or isPedDead(player) or isPedInVehicle(player) then
        return notify(player, "No puedes cargar a nadie ahora.", "error")
    end
    local target = exports.rp_ids:findPlayer(query)
    if not target or target == player then return notify(player, "Jugador no encontrado.", "error") end
    if getElementData(target, "rp:downed") ~= true then return notify(player, "Solo puedes cargar a alguien abatido.", "error") end
    if carried[target] then return notify(player, "Ya lo esta cargando alguien.", "error") end
    local x, y, z = getElementPosition(player)
    local tx, ty, tz = getElementPosition(target)
    if getElementInterior(player) ~= getElementInterior(target) or getElementDimension(player) ~= getElementDimension(target)
        or getDistanceBetweenPoints3D(x, y, z, tx, ty, tz) > INJURY.CARRY.RANGE then
        return notify(player, "Estas muy lejos de esa persona.", "error")
    end
    pick(player, target)
    notify(player, ("Cargas a %s. Usa /soltar para dejarlo."):format(nameOf(target)), "success")
    notify(target, ("%s te carga en brazos."):format(nameOf(player)), "info")
end)

addCommandHandler("soltar", function(player)
    if carrying[player] then drop(player, carrying[player]) else notify(player, "No cargas a nadie.", "error") end
end)

-- El cargador sube a un vehiculo: el herido se sienta en un asiento libre
-- Al EMPEZAR a subir el cargador (no al terminar): con el herido enganchado durante la animacion el auto levitaba
addEventHandler("onVehicleStartEnter", root, function(carrier, enterSeat)
    local vehicle = source
    local target = carrying[carrier]
    if not target then return end
    for seat = 0, getVehicleMaxPassengers(vehicle) do
        if seat ~= enterSeat and not getVehicleOccupant(vehicle, seat) then
            drop(carrier, target)
            warpPedIntoVehicle(target, vehicle, seat)
            setElementData(target, "rp:loaded", true)
            return notify(carrier, ("%s va sentado en el vehiculo."):format(nameOf(target)), "success")
        end
    end
    notify(carrier, "No hay asientos libres: lo dejas en el suelo.", "warning")
    drop(carrier, target)
end)

addEventHandler("rp:onPlayerDownedEnd", root, function()
    dropByTarget(source)
    dropByCarrier(source)
    setElementData(source, "rp:loaded", false)
    setElementCollisionsEnabled(source, true)
end)
addEventHandler("rp:onPlayerDowned", root, function() dropByCarrier(source) end)
addEventHandler("onPlayerWasted", root, function() dropByCarrier(source); dropByTarget(source) end)
addEventHandler("onPlayerQuit", root, function() dropByCarrier(source); dropByTarget(source) end)

-- attachElements no sincroniza interior/dimension (puertas, warps)
setTimer(function()
    for carrier, target in pairs(carrying) do
        if isElement(carrier) and isElement(target) then
            setElementInterior(target, getElementInterior(carrier))
            setElementDimension(target, getElementDimension(carrier))
        end
    end
end, 1000, 0)

addEventHandler("onResourceStop", resourceRoot, function()
    for carrier, target in pairs(carrying) do drop(carrier, target) end
end)
