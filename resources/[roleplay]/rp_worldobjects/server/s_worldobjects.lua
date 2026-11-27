--[[
    rp_worldobjects / server/s_worldobjects.lua
    Interaccion con los objetos del mapa original (bancas, sillas, sofas).
    El cliente encuentra el objeto y calcula la plaza (raycast sobre el modelo real); el servidor
    comprueba que la plaza esta sobre un objeto conocido, cerca del jugador y libre, y sincroniza
    la postura para todos.
]]

addEvent("rp:worldobjects:use", true)
addEvent("rp:worldobjects:stand", true)
addEvent("rp:worldobjects:adjust", true)

local seated = {}    -- [player] = { key, x, y, z }
local occupied = {}  -- [key] = player
local lastUse = {}   -- [player] = tick
local animTimers = {}

local function stopAnimTimer(p)
    if animTimers[p] and isTimer(animTimers[p]) then killTimer(animTimers[p]) end
    animTimers[p] = nil
end

local function clearSeat(p)
    local s = seated[p]
    if not s then return end
    if occupied[s.key] == p then occupied[s.key] = nil end
    seated[p] = nil
    if isElement(p) then triggerClientEvent(p, "rp:worldobjects:state", resourceRoot, false) end
end

-- Levantarse. instant = sin animacion (abatido, teletransportado, recurso parando)
local function standUp(p, instant)
    if not seated[p] then return end
    clearSeat(p)
    stopAnimTimer(p)
    if not isElement(p) then return end
    local out = WO.KINDS.sit.animOut
    if instant or isPedDead(p) then
        setPedAnimation(p)
        setElementFrozen(p, false)
        return
    end
    setPedAnimation(p, out[1], out[2], -1, false, false, false, false)
    animTimers[p] = setTimer(function()
        animTimers[p] = nil
        if isElement(p) and not seated[p] then
            setPedAnimation(p)
            setElementFrozen(p, false)
        end
    end, out[3], 1)
end

local function blocked(p)
    if isPedDead(p) or getPedOccupiedVehicle(p) then return true end
    local ok, downed = pcall(function() return exports.rp_injury:isPlayerDowned(p) end)
    if ok and downed then return true end
    local ok2, cuffed = pcall(function() return exports.rp_police:isCuffed(p) end)
    if ok2 and cuffed then return true end
    return false
end

addEventHandler("rp:worldobjects:use", resourceRoot, function(idx, seat, x, y, z, rz)
    local p = client
    if not exports.rp_characters:getPlayerCharacterId(p) then return end
    local now = getTickCount()
    if lastUse[p] and now - lastUse[p] < WO.COOLDOWN then return end
    lastUse[p] = now
    if seated[p] then return standUp(p) end

    idx, seat, x, y, z, rz = tonumber(idx), tonumber(seat), tonumber(x), tonumber(y), tonumber(z), tonumber(rz)
    local o = idx and WO_LIST[idx]
    if not o or not seat or not x or not y or not z or not rz then return end
    if seat < 1 or seat > o.seats or seat % 1 ~= 0 then return end
    local kind = WO.KINDS[WO.MODELS[o.model].kind]
    if not kind then return end
    if blocked(p) then return end
    -- La plaza tiene que estar sobre el objeto y el jugador al lado
    if getElementInterior(p) ~= o.int then return end
    if getDistanceBetweenPoints2D(x, y, o.x, o.y) > o.radius + 0.6 or math.abs(z - o.z) > 2.5 then return end
    local px, py, pz = getElementPosition(p)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > WO.USE_DISTANCE + 1 then return end

    local key = idx .. ":" .. seat
    local other = occupied[key]
    if other and isElement(other) and seated[other] then
        return exports.rp_notify:notify(p, "Ese sitio esta ocupado.", "warning")
    end

    occupied[key] = p
    seated[p] = { key = key, idx = idx, x = x, y = y, z = z }
    stopAnimTimer(p)
    setElementPosition(p, x, y, z, false)
    setElementRotation(p, 0, 0, rz % 360, "default", true)
    setElementFrozen(p, true)
    local a, inn = kind.anim, kind.animIn
    setPedAnimation(p, inn[1], inn[2], -1, false, false, false, true)
    animTimers[p] = setTimer(function()
        animTimers[p] = nil
        if isElement(p) and seated[p] then setPedAnimation(p, a[1], a[2], -1, true, false, false, true) end
    end, inn[3], 1)
    triggerClientEvent(p, "rp:worldobjects:state", resourceRoot, true)
end)

addEventHandler("rp:worldobjects:stand", resourceRoot, function()
    local p = client
    local now = getTickCount()
    if lastUse[p] and now - lastUse[p] < WO.COOLDOWN then return end
    lastUse[p] = now
    standUp(p)
end)

-- Si alguien sentado acaba lejos de su sitio (teletransporte, admin), se libera
setTimer(function()
    for p, s in pairs(seated) do
        if not isElement(p) then
            seated[p] = nil
        else
            local x, y, z = getElementPosition(p)
            if getDistanceBetweenPoints3D(x, y, z, s.x, s.y, s.z) > 1.5 or blocked(p) then standUp(p, true) end
        end
    end
end, 2000, 0)

addEventHandler("rp:onPlayerDowned", root, function() standUp(source, true) end)
addEventHandler("rp:onCharacterLogout", root, function() standUp(source, true) end)
addEventHandler("onPlayerWasted", root, function() standUp(source, true) end)
addEventHandler("onPlayerQuit", root, function()
    clearSeat(source)
    stopAnimTimer(source)
    lastUse[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(seated) do standUp(p, true) end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    outputDebugString(("[rp_worldobjects] %d objetos del mapa interactivos"):format(#WO_LIST), 3)
end)

-- Export: el jugador esta sentado en un objeto del mapa
function isPlayerSeated(p)
    return seated[p] ~= nil
end

-- Export: levantar al jugador (otro recurso que necesita moverlo)
function standPlayer(p)
    if seated[p] then standUp(p, true) return true end
    return false
end

-- Export: cifras del indice (pruebas de rp_test y diagnostico)
function getWorldObjectStats()
    local seats, models = 0, {}
    for _, o in ipairs(WO_LIST) do
        seats = seats + o.seats
        models[o.model] = true
    end
    local nModels = 0
    for _ in pairs(models) do nModels = nModels + 1 end
    local near = #WO_nearby(-1970, 130, 0, 3)   -- bancas de piedra de Downtown SF
    return { objects = #WO_LIST, seats = seats, models = nModels, nearTest = near }
end

----------------------------------------------------------------
-- PROVISIONAL (admin): /setseatoffset <altura> [respaldo] [giro]
-- Ajusta en vivo la postura sobre el modelo en el que estas sentado y escribe en el chat los valores
-- para pasarlos a WO.MODELS. Sin valores muestra los actuales. Quitar cuando esten todos ajustados.
----------------------------------------------------------------
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

addCommandHandler("setseatoffset", function(p, _, z, back, rot)
    if not isAdmin(p) then return exports.rp_notify:notify(p, "No tienes permiso para usar este comando.", "error") end
    if not seated[p] then return exports.rp_notify:notify(p, "Sientate primero en una banca o silla (E).", "warning") end
    if z == nil then return triggerClientEvent(p, "rp:worldobjects:tune", resourceRoot) end
    z, back, rot = tonumber(z), back and tonumber(back), rot and tonumber(rot)
    if not z or z < -1 or z > 2 or (back and (back < -1 or back > 1)) or (rot and (rot < -180 or rot > 180)) then
        return exports.rp_notify:notify(p, "Uso: /setseatoffset <altura -1..2> [respaldo -1..1] [giro -180..180]", "warning")
    end
    triggerClientEvent(p, "rp:worldobjects:tune", resourceRoot, z, back, rot)
end)

addEventHandler("rp:worldobjects:adjust", resourceRoot, function(x, y, z, rz)
    local p = client
    local s = seated[p]
    if not s or not isAdmin(p) then return end
    x, y, z, rz = tonumber(x), tonumber(y), tonumber(z), tonumber(rz)
    if not x or not y or not z or not rz then return end
    local o = WO_LIST[s.idx]
    if getDistanceBetweenPoints3D(x, y, z, s.x, s.y, s.z) > 1.4 then return end
    if getDistanceBetweenPoints2D(x, y, o.x, o.y) > o.radius + 0.6 or math.abs(z - o.z) > 2.5 then return end
    s.x, s.y, s.z = x, y, z
    setElementPosition(p, x, y, z, false)
    setElementRotation(p, 0, 0, rz % 360, "default", true)
    local a = WO.KINDS.sit.anim
    setPedAnimation(p, a[1], a[2], -1, true, false, false, true)
end)
