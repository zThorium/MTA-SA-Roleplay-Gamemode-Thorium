--[[
    rp_citizens / s_clock.lua
    Reloj comun para el trafico aereo (c_air.lua). Los aviones y helicopteros siguen un horario fijo calculado
    con esta hora: todos los jugadores ven el mismo avion en el mismo sitio sin que el servidor envie posiciones.
    El cliente lo pide al arrancar y cada 10 min (rp:citizens:clock) y recibe los ms actuales del servidor.
]]

local baseSec = getRealTime().timestamp
local baseTick = getTickCount()

-- ms desde 1970 con precision de tick (el segundo inicial es el mismo para todos los clientes)
local function nowMs()
    return baseSec * 1000 + (getTickCount() - baseTick)
end

local lastAsk = {}   -- [player] = tick de la ultima peticion (como mucho una cada 2 s)

addEvent("rp:citizens:clock", true)
addEventHandler("rp:citizens:clock", resourceRoot, function()
    if not isElement(client) then return end
    local now = getTickCount()
    if lastAsk[client] and now - lastAsk[client] < 2000 then return end
    lastAsk[client] = now
    triggerClientEvent(client, "rp:citizens:clockRecv", resourceRoot, nowMs())
end)

addEventHandler("onPlayerQuit", root, function() lastAsk[source] = nil end)
