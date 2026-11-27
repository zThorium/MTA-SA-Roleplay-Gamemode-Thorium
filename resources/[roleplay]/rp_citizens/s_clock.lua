--[[
    rp_citizens / s_clock.lua
    Reloj comun y pistas de aterrizaje para el trafico con horario (c_air.lua). Las naves siguen un horario fijo
    calculado con esta hora: todos los jugadores ven el mismo avion en el mismo sitio sin que el servidor envie
    posiciones. El cliente lo pide al arrancar y cada 10 min (rp:citizens:clock) y recibe los ms actuales del
    servidor junto con las pistas.
    Pistas (runways.json): las capturan los admins en el juego con /setrunway; con ellas el cliente genera los
    vuelos que despegan y aterrizan. Al cambiar una pista se reenvian a todos (rp:citizens:runways).
]]

local baseSec = getRealTime().timestamp
local baseTick = getTickCount()

-- ms desde 1970 con precision de tick (el segundo inicial es el mismo para todos los clientes)
local function nowMs()
    return baseSec * 1000 + (getTickCount() - baseTick)
end

----------------------------------------------------------------
-- Pistas
----------------------------------------------------------------
local RUNWAY_FILE = "runways.json"
local AIRPORTS = {   -- id -> nombre (solo estos ids; small = solo avionetas)
    ls = { name = "Los Santos" },
    sf = { name = "San Fierro" },
    lv = { name = "Las Venturas" },
    verdant = { name = "Verdant Meadows", small = true },
}
local RUNWAY_MIN, RUNWAY_MAX = 300, 3000   -- largo valido en metros

local runways = {}   -- [id] = { name, x1, y1, x2, y2, z, small, provisional } (x1, y1 = cabecera: donde empieza el despegue)

local function loadRunways()
    runways = {}
    if not fileExists(RUNWAY_FILE) then return end
    local f = fileOpen(RUNWAY_FILE, true)
    if not f then return end
    local data = fromJSON(fileRead(f, fileGetSize(f)) or "")
    fileClose(f)
    if type(data) ~= "table" then return end
    for id, rw in pairs(data) do
        if AIRPORTS[id] and type(rw) == "table" and tonumber(rw.x1) and tonumber(rw.y1) and tonumber(rw.x2)
            and tonumber(rw.y2) and tonumber(rw.z) then
            runways[id] = { name = AIRPORTS[id].name, small = AIRPORTS[id].small or nil, provisional = rw.provisional or nil,
                x1 = tonumber(rw.x1), y1 = tonumber(rw.y1), x2 = tonumber(rw.x2), y2 = tonumber(rw.y2), z = tonumber(rw.z) }
        end
    end
end

local function saveRunways()
    local f = fileCreate(RUNWAY_FILE)
    if not f then return false end
    fileWrite(f, toJSON(runways, false, "tabs"))
    fileClose(f)
    return true
end

-- Solo las pistas completas (las dos cabeceras) viajan al cliente
local function completeRunways()
    local out = {}
    for id, rw in pairs(runways) do
        if rw.x2 then out[id] = rw end
    end
    return out
end

loadRunways()

----------------------------------------------------------------
-- Reloj
----------------------------------------------------------------
local lastAsk = {}   -- [player] = tick de la ultima peticion (como mucho una cada 2 s)

addEvent("rp:citizens:clock", true)
addEventHandler("rp:citizens:clock", resourceRoot, function()
    if not isElement(client) then return end
    local now = getTickCount()
    if lastAsk[client] and now - lastAsk[client] < 2000 then return end
    lastAsk[client] = now
    triggerClientEvent(client, "rp:citizens:clockRecv", resourceRoot, nowMs(), completeRunways())
end)

addEventHandler("onPlayerQuit", root, function() lastAsk[source] = nil end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

-- /gotoaircraft [ruta] (alias /irvuelo). Lleva al admin debajo de la proxima nave con horario y la marca en el
-- radar. El servidor decide el permiso; el cliente calcula el vuelo (el horario solo existe alli).
local function gotoAircraft(player, _, ...)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local query = table.concat({ ... }, " ")
    if #query > 40 then return notify(player, "Uso: /gotoaircraft [parte del nombre de la ruta, ver /vuelos]", "warning") end
    if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
    setElementInterior(player, 0)
    setElementDimension(player, 0)
    triggerClientEvent(player, "rp:citizens:air:goto", resourceRoot, query)
end
addCommandHandler("gotoaircraft", gotoAircraft)
addCommandHandler("irvuelo", gotoAircraft)

local function airportList()
    local ids = {}
    for id in pairs(AIRPORTS) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, "|")
end

-- /setrunway <aeropuerto> <start|end> (alias /pista): a pie sobre el eje de la pista. start = cabecera donde
-- empiezan los despegues y aterrizan los aviones; end = el otro extremo. La altura es la de tus pies.
local function setRunway(player, _, id, which)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = id and id:lower()
    which = which and which:lower()
    if which == "inicio" then which = "start" elseif which == "fin" then which = "end" end
    if not id or not AIRPORTS[id] or (which ~= "start" and which ~= "end") then
        return notify(player, "Uso: /setrunway <" .. airportList() .. "> <start|end> (a pie sobre el eje de la pista)", "warning")
    end
    if getPedOccupiedVehicle(player) then return notify(player, "Bajate del vehiculo: la altura de la pista se toma de tus pies.", "warning") end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        return notify(player, "Las pistas solo pueden estar en el mundo exterior.", "warning")
    end
    local x, y, z = getElementPosition(player)
    local feet = z - 1.0   -- el centro del personaje esta ~1 m sobre el suelo
    local rw = runways[id] or { name = AIRPORTS[id].name, small = AIRPORTS[id].small or nil }
    rw.provisional = nil
    if which == "start" then
        rw.x1, rw.y1, rw.z1 = x, y, feet
        -- una cabecera nueva invalida el extremo anterior si quedo demasiado cerca o lejos
        if rw.x2 then
            local len = getDistanceBetweenPoints2D(rw.x1, rw.y1, rw.x2, rw.y2)
            if len < RUNWAY_MIN or len > RUNWAY_MAX then rw.x2, rw.y2, rw.z2 = nil, nil, nil end
        end
    else
        if not rw.x1 then return notify(player, "Primero marca la cabecera: /setrunway " .. id .. " start", "warning") end
        local len = getDistanceBetweenPoints2D(rw.x1, rw.y1, x, y)
        if len < RUNWAY_MIN or len > RUNWAY_MAX then
            return notify(player, ("La pista mediria %d m: tiene que estar entre %d y %d m."):format(len, RUNWAY_MIN, RUNWAY_MAX), "warning")
        end
        rw.x2, rw.y2, rw.z2 = x, y, feet
    end
    rw.z = rw.z2 and ((rw.z1 or rw.z2) + rw.z2) / 2 or rw.z1
    runways[id] = rw
    if not saveRunways() then return notify(player, "No se pudo guardar runways.json.", "error") end
    if rw.x2 then
        triggerClientEvent(root, "rp:citizens:runways", resourceRoot, completeRunways())
        notify(player, ("Pista de %s guardada (%d m). Los vuelos se rehacen para todos."):format(
            rw.name, getDistanceBetweenPoints2D(rw.x1, rw.y1, rw.x2, rw.y2)), "success")
    else
        notify(player, "Cabecera guardada. Ahora ve al otro extremo por el eje y usa /setrunway " .. id .. " end", "success")
    end
    outputServerLog(("[rp_citizens] %s marco la pista %s (%s): %.1f, %.1f, %.1f"):format(getPlayerName(player), id, which, x, y, feet))
end
addCommandHandler("setrunway", setRunway)
addCommandHandler("pista", setRunway)

-- /delrunway <aeropuerto>: quita la pista (sus vuelos dejan de existir)
addCommandHandler("delrunway", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = id and id:lower()
    if not id or not runways[id] then return notify(player, "Uso: /delrunway <" .. airportList() .. "> (ver /runways)", "warning") end
    runways[id] = nil
    saveRunways()
    triggerClientEvent(root, "rp:citizens:runways", resourceRoot, completeRunways())
    notify(player, "Pista de " .. AIRPORTS[id].name .. " borrada.", "success")
end)

-- /runways: pistas guardadas
addCommandHandler("runways", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local any = false
    for _, id in ipairs({ "ls", "sf", "lv", "verdant" }) do
        local rw = runways[id]
        if rw then
            any = true
            local len = rw.x2 and getDistanceBetweenPoints2D(rw.x1, rw.y1, rw.x2, rw.y2)
            outputChatBox(("[Pistas] %s (%s): %s%s"):format(rw.name, id,
                len and ("%d m, cabecera %.0f, %.0f, z %.1f"):format(len, rw.x1, rw.y1, rw.z) or "solo cabecera (falta /setrunway " .. id .. " end)",
                rw.provisional and " - PROVISIONAL, vuelve a capturarla" or ""), player, 120, 200, 255)
        end
    end
    if not any then notify(player, "No hay pistas. Usa /setrunway <aeropuerto> start y end.", "info") end
end)
