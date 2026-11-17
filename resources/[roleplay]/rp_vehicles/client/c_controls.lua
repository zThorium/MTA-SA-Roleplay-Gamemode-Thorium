--[[
    rp_vehicles / c_controls.lua
    Teclas del vehiculo (se bindean al cargar el recurso; son comandos, asi
    que cada jugador las puede cambiar en Ajustes > Binds):
        L        /bloquear           abrir / cerrar con la llave
        J        /toggleengine       motor (necesita la llave)
        X        /frenodemano        freno de mano
        Flechas  /intermitente_izq /intermitente_der /balizas

    Intermitentes: 4 luces amarillas (delantera y trasera de cada lado) que
    titilan. Cada una es una corona + una luz real (createLight).
    Tambien reporta al servidor los golpes que este jugador le da a un
    vehiculo con dueno (historial para admins).
]]

addEvent("rp:veh:lockFx", true)

local function canUseKeys()
    return getElementData(localPlayer, "rp:characterId") and not isPedDead(localPlayer)
        and not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
end

local function driving()
    local v = getPedOccupiedVehicle(localPlayer)
    return v and getVehicleController(v) == localPlayer and v or nil
end

local actions = {
    lock = function() triggerServerEvent("rp:veh:toggleLock", resourceRoot) end,
    engine = function()
        if not driving() then return exports.rp_notify:notify("Debes estar al volante.", "warning") end
        triggerServerEvent("rp:veh:engine", resourceRoot)
    end,
    handbrake = function() if driving() then triggerServerEvent("rp:veh:handbrake", resourceRoot) end end,
    left = function() if driving() then triggerServerEvent("rp:veh:indicator", resourceRoot, "left") end end,
    right = function() if driving() then triggerServerEvent("rp:veh:indicator", resourceRoot, "right") end end,
    hazard = function() if driving() then triggerServerEvent("rp:veh:indicator", resourceRoot, "hazard") end end,
}

-- Anti spam: una accion por tecla cada 400 ms
local lastUse = {}
local function run(name)
    if not canUseKeys() then return end
    local now = getTickCount()
    if lastUse[name] and now - lastUse[name] < 400 then return end
    lastUse[name] = now
    actions[name]()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for name, info in pairs(VEHICLES.KEYS) do
        if actions[name] then
            addCommandHandler(info.command, function() run(name) end)
            bindKey(info.key, "down", info.command)
        end
    end
end)

-- Parpadeo de luces y sonido al abrir / cerrar (lo ven los cercanos)
addEventHandler("rp:veh:lockFx", resourceRoot, function(vehicle, locked)
    if not isElement(vehicle) or not isElementStreamedIn(vehicle) then return end
    local px, py, pz = getElementPosition(localPlayer)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > 25 then return end
    playSoundFrontEnd(5)
    local state = getVehicleOverrideLights(vehicle)
    local blinks = locked and 1 or 2
    for i = 0, blinks - 1 do
        setTimer(function() if isElement(vehicle) then setVehicleOverrideLights(vehicle, 2) end end, i * 300 + 1, 1)
        setTimer(function() if isElement(vehicle) then setVehicleOverrideLights(vehicle, state) end end, i * 300 + 150, 1)
    end
end)

----------------------------------------------------------------
-- Intermitentes
----------------------------------------------------------------
local fx = {}         -- [vehicle] = { lamps = { {marker, light, x, y, z, side} } }
local clamped = {}    -- [vehicle] = true

-- Posicion de las luces relativa al vehiculo
local function lampOffsets(vehicle)
    local fx_, fy, fz, rx, ry, rz
    if getVehicleDummyPosition then
        fx_, fy, fz = getVehicleDummyPosition(vehicle, "light_front_main")
        rx, ry, rz = getVehicleDummyPosition(vehicle, "light_rear_main")
    end
    local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(vehicle)
    if not fx_ or (fx_ == 0 and fy == 0) then
        fx_, fy, fz = (maxX or 1) - 0.2, (maxY or 2) - 0.15, ((minZ or -0.5) + (maxZ or 0.5)) * 0.3
    end
    if not rx or (rx == 0 and ry == 0) then
        rx, ry, rz = (maxX or 1) - 0.2, (minY or -2) + 0.15, ((minZ or -0.5) + (maxZ or 0.5)) * 0.3
    end
    fx_, rx = math.abs(fx_), math.abs(rx)
    -- Un poco hacia afuera para que se vean sobre la carroceria
    return {
        { -fx_ - 0.05, fy + 0.05, fz, "left" },
        { -rx - 0.05, ry - 0.05, rz, "left" },
        { fx_ + 0.05, fy + 0.05, fz, "right" },
        { rx + 0.05, ry - 0.05, rz, "right" },
    }
end

local function destroyFx(vehicle)
    local f = fx[vehicle]
    if not f then return end
    for _, lamp in ipairs(f.lamps) do
        if isElement(lamp.marker) then destroyElement(lamp.marker) end
        if isElement(lamp.light) then destroyElement(lamp.light) end
    end
    fx[vehicle] = nil
end

local function createFx(vehicle)
    destroyFx(vehicle)
    local r, g, b = unpack(VEHICLES.INDICATOR_COLOR)
    local lamps = {}
    for _, o in ipairs(lampOffsets(vehicle)) do
        local x, y, z = getElementPosition(vehicle)
        local marker = createMarker(x, y, z, "corona", 0.35, r, g, b, 0)
        local light = createLight and createLight(0, x, y, z, 2.2, 0, 0, 0) or nil
        if marker then
            setElementDimension(marker, getElementDimension(vehicle))
            setElementInterior(marker, getElementInterior(vehicle))
        end
        if light then
            setElementDimension(light, getElementDimension(vehicle))
            setElementInterior(light, getElementInterior(vehicle))
        end
        lamps[#lamps + 1] = { marker = marker, light = light, x = o[1], y = o[2], z = o[3], side = o[4] }
    end
    fx[vehicle] = { lamps = lamps }
end

-- Revisa los vehiculos cercanos 4 veces por segundo
local function scan()
    local px, py, pz = getElementPosition(localPlayer)
    local seen = {}
    clamped = {}
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local vx, vy, vz = getElementPosition(v)
        local near = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= VEHICLES.INDICATOR_STREAM
        if near and getElementData(v, "rp:indicator") then
            seen[v] = true
            if not fx[v] then createFx(v) end
        end
        if near and getElementData(v, "rp:clamp") then clamped[v] = true end
    end
    for v in pairs(fx) do
        if not seen[v] or not isElement(v) then destroyFx(v) end
    end
end
setTimer(scan, 250, 0)

local function worldOffset(m, x, y, z)
    return x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
           x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
           x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
end

addEventHandler("onClientPreRender", root, function()
    if not next(fx) then return end
    local on = math.floor(getTickCount() / VEHICLES.INDICATOR_BLINK) % 2 == 0
    local r, g, b = unpack(VEHICLES.INDICATOR_COLOR)
    for v, f in pairs(fx) do
        if isElement(v) then
            local side = getElementData(v, "rp:indicator")
            local m = getElementMatrix(v)
            for _, lamp in ipairs(f.lamps) do
                local active = on and (side == "hazard" or side == lamp.side)
                local x, y, z = worldOffset(m, lamp.x, lamp.y, lamp.z)
                if isElement(lamp.marker) then
                    setElementPosition(lamp.marker, x, y, z)
                    setMarkerColor(lamp.marker, r, g, b, active and 230 or 0)
                end
                if isElement(lamp.light) then
                    setElementPosition(lamp.light, x, y, z)
                    if active then setLightColor(lamp.light, r, g, b) else setLightColor(lamp.light, 0, 0, 0) end
                end
            end
        end
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if fx[source] then destroyFx(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if fx[source] then destroyFx(source) end
end)

-- Aviso del cepo sobre el vehiculo
addEventHandler("onClientRender", root, function()
    if not next(clamped) then return end
    for v in pairs(clamped) do
        if isElement(v) and isElementOnScreen(v) then
            local x, y, z = getElementPosition(v)
            local sx, sy = getScreenFromWorldPosition(x, y, z + 1.2)
            if sx then
                dxDrawText("CEPO POLICIAL", sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200), 1.2, "default-bold", "center", "center")
                dxDrawText("CEPO POLICIAL", sx, sy, sx, sy, tocolor(255, 200, 40, 255), 1.2, "default-bold", "center", "center")
            end
        end
    end
end)

----------------------------------------------------------------
-- Golpes a vehiculos con dueno (solo los que causa este jugador)
----------------------------------------------------------------
local pendingHits = {}   -- [vehicle] = { loss, weapon }

addEventHandler("onClientVehicleDamage", root, function(attacker, weapon, loss)
    if not getElementData(source, "rp:vehicleId") or not getElementData(localPlayer, "rp:characterId") then return end
    local mine = attacker == localPlayer
        or (isElement(attacker) and getElementType(attacker) == "vehicle" and getVehicleController(attacker) == localPlayer)
        or (not attacker and getVehicleController(source) == localPlayer)   -- choque del propio conductor
    if not mine or (tonumber(loss) or 0) <= 0 then return end
    local p = pendingHits[source] or { loss = 0, weapon = weapon or 0 }
    p.loss = p.loss + loss
    p.weapon = weapon or p.weapon
    pendingHits[source] = p
end)

setTimer(function()
    for v, p in pairs(pendingHits) do
        if isElement(v) and p.loss >= VEHICLES.HIT_MIN_LOSS then
            triggerServerEvent("rp:veh:hit", resourceRoot, v, p.weapon, math.min(1000, p.loss))
        end
    end
    pendingHits = {}
end, 1000, 0)
