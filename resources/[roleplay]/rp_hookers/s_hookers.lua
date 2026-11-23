--[[
    rp_hookers / s_hookers.lua
    Parte autoritativa del trato: el servidor pone el precio, comprueba el dinero y cobra solo
    cuando empieza el servicio (el cliente solo dibuja peds y animaciones).
    Flujo: ask (bocina) -> offer -> accept -> start (lugar tranquilo, se cobra) -> curacion.
]]

local PRICE_MIN, PRICE_MAX = 50, 150
local SERVICE_MS = 20000        -- duracion total del servicio (cliente: start+loop+end)
local HEAL = 25
local ASK_COOLDOWN = 2500

local sessions = {}             -- [player] = { price, accepted, started }
local lastAsk = {}

for _, e in ipairs({ "rp:hooker:ask", "rp:hooker:accept", "rp:hooker:start", "rp:hooker:cancel" }) do addEvent(e, true) end
addEvent("rp:hooker:offer", true)
addEvent("rp:hooker:go", true)
addEvent("rp:hooker:deny", true)
addEvent("rp:hooker:begin", true)

local function notify(p, t, k) if isElement(p) then exports.rp_notify:notify(p, t, k) end end

local function drivingCar(p)
    local v = getPedOccupiedVehicle(p)
    if v and getVehicleOccupant(v, 0) == p and getVehicleMaxPassengers(v) >= 1 and not getVehicleOccupant(v, 1) then return v end
end

local SKINS = {}
for _, id in ipairs({ 63, 64, 75, 85, 87, 90, 152, 178, 237, 238, 243, 244, 245, 246, 256, 257 }) do SKINS[id] = true end

-- La prostituta del asiento es un ped del servidor (el cliente no puede subir peds a autos del servidor)
local function clear(p)
    local s = sessions[p]
    sessions[p] = nil
    local ped = s and s.ped
    if isElement(ped) then
        if isPedInVehicle(ped) then removePedFromVehicle(ped) end
        setTimer(function() if isElement(ped) then destroyElement(ped) end end, 4000, 1)
    end
end

addEventHandler("rp:hooker:ask", resourceRoot, function()
    local p = client
    local now = getTickCount()
    if now - (lastAsk[p] or 0) < ASK_COOLDOWN or sessions[p] then return end
    lastAsk[p] = now
    if not drivingCar(p) or isPedDead(p) then return end
    if getPlayerMoney(p) < PRICE_MIN then
        notify(p, "No llevas dinero suficiente para ella.", "error")
        return triggerClientEvent(p, "rp:hooker:deny", resourceRoot, "Sin dinero no hay trato, guapo.")
    end
    local price = math.random(PRICE_MIN, PRICE_MAX)
    sessions[p] = { price = price }
    triggerClientEvent(p, "rp:hooker:offer", resourceRoot, price)
end)

addEventHandler("rp:hooker:accept", resourceRoot, function()
    local p = client
    local s = sessions[p]
    if not s or s.accepted or not drivingCar(p) then return clear(p) end
    if getPlayerMoney(p) < s.price then
        clear(p)
        notify(p, "No tienes suficiente dinero en efectivo.", "error")
        return triggerClientEvent(p, "rp:hooker:deny", resourceRoot, "Sin dinero no hay trato.")
    end
    s.accepted = true
    triggerClientEvent(p, "rp:hooker:go", resourceRoot)
end)

addEvent("rp:hooker:board", true)
addEventHandler("rp:hooker:board", resourceRoot, function(skin)
    local p = client
    local s = sessions[p]
    skin = tonumber(skin)
    if not s or not s.accepted or s.ped or not skin or not SKINS[skin] then return end
    local v = drivingCar(p)
    if not v then return clear(p) end
    local x, y, z = getElementPosition(v)
    local ped = createPed(skin, x, y, z + 2)
    if not ped then return clear(p) end
    setElementDimension(ped, getElementDimension(v))
    setElementInterior(ped, getElementInterior(v))
    warpPedIntoVehicle(ped, v, 1)
    s.ped = ped
end)

addEventHandler("rp:hooker:start", resourceRoot, function()
    local p = client
    local s = sessions[p]
    if not s or not s.accepted or s.started then return end
    local v = getPedOccupiedVehicle(p)
    if not v or getVehicleOccupant(v, 0) ~= p then return clear(p) end
    if getPlayerMoney(p) < s.price then
        clear(p)
        notify(p, "Ya no tienes el dinero del trato.", "error")
        return triggerClientEvent(p, "rp:hooker:deny", resourceRoot, "Sin dinero no hay trato.")
    end
    takePlayerMoney(p, s.price)
    s.started = true
    notify(p, ("Pagaste $%d."):format(s.price), "info")
    triggerClientEvent(p, "rp:hooker:begin", resourceRoot)
    setTimer(function()
        if isElement(p) and sessions[p] == s then
            if not isPedDead(p) then setElementHealth(p, math.min(100, getElementHealth(p) + HEAL)) end
            clear(p)
        end
    end, SERVICE_MS, 1)
end)

-- Una vez empezado el servicio ya esta pagado: no se puede cancelar
addEventHandler("rp:hooker:cancel", resourceRoot, function()
    local s = sessions[client]
    if s and not s.started then clear(client) end
end)

addEventHandler("onPlayerQuit", root, function() sessions[source] = nil lastAsk[source] = nil end)
addEventHandler("onPlayerWasted", root, function() local s = sessions[source] if s and not s.started then clear(source) end end)
