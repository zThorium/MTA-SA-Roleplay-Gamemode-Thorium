--[[
    rp_police / c_police.lua
    Cliente policial:
      - K: cursor de interaccion. Pasa el cursor sobre un jugador o vehiculo (con
        linea de vista) y click derecho: menu contextual que arma el servidor.
      - E: usar punto (vestuario, armeria, garaje, laboratorio) o recolectar evidencia.
      - F6: MDT. O: sirena. Taser, reporte de disparos y radar/ALPR de la patrulla.
]]

local sw, sh = guiGetScreenSize()
local points = {}
local cursorMode = false
local hover = nil
local menu = nil              -- { target, title, options, x, y }
local alpr = {}               -- [vehiculo] = { data, at }
local radar = nil             -- { speed, plate, flags, at }
local lastShot = 0

addEvent("rp:pol:points", true)
addEvent("rp:pol:menuOptions", true)
addEvent("rp:pol:alprResult", true)

local function onDuty() return getElementData(localPlayer, "rp:policeDuty") == true end
local function ready()
    return getElementData(localPlayer, "rp:characterId") and not isPedDead(localPlayer)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rp:pol:requestPoints", resourceRoot)
    bindKey(POLICE.KEY_MDT, "down", function()
        if not ready() or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:pol:openMDT", resourceRoot)
    end)
    bindKey(POLICE.KEY_SIREN, "down", function()
        if getPedOccupiedVehicle(localPlayer) and onDuty() then triggerServerEvent("rp:pol:siren", resourceRoot) end
    end)
    bindKey(POLICE.KEY_USE, "down", function()
        if not ready() or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or getPedOccupiedVehicle(localPlayer) then return end
        local px, py, pz = getElementPosition(localPlayer)
        for _, pt in ipairs(points) do
            if pt.interior == getElementInterior(localPlayer) and getDistanceBetweenPoints3D(px, py, pz, pt.x, pt.y, pt.z) <= POLICE.POINT_RADIUS + 1 then
                return triggerServerEvent("rp:pol:use", resourceRoot, pt.kind)
            end
        end
        if onDuty() then
            for _, m in ipairs(getElementsByType("marker", root, true)) do
                if math.abs(getMarkerSize(m) - 0.7) < 0.02 and getMarkerType(m) == "cylinder" then
                    local x, y, z = getElementPosition(m)
                    if getDistanceBetweenPoints3D(px, py, pz, x, y, z + 0.95) <= POLICE.EVIDENCE_PICKUP then
                        return triggerServerEvent("rp:pol:use", resourceRoot, "evidence")
                    end
                end
            end
        end
    end)
    bindKey(POLICE.KEY_INTERACT, "down", function()
        if menu then menu = nil return end
        if cursorMode then cursorMode = false showCursor(false) hover = nil return end
        if not ready() or not onDuty() or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        cursorMode = true
        showCursor(true)
    end)
end)

addEventHandler("rp:pol:points", resourceRoot, function(list) points = list or {} end)

local function stopCursor()
    if cursorMode or menu then
        cursorMode, menu, hover = false, nil, nil
        showCursor(false)
    end
end
addEventHandler("onClientPlayerWasted", localPlayer, stopCursor)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if (key == "rp:policeDuty" and new ~= true) or (key == "rp:characterId" and not new) then stopCursor() end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if cursorMode or menu then showCursor(false) end
end)

----------------------------------------------------------------
-- Objetivo bajo el cursor
----------------------------------------------------------------
local function pickTarget()
    local cx, cy = getCursorPosition()
    if not cx then return nil end
    cx, cy = cx * sw, cy * sh
    local px, py, pz = getElementPosition(localPlayer)
    local camX, camY, camZ = getCameraMatrix()
    local best, bestD = nil, 9999
    local function consider(el, wx, wy, wz, radius)
        local d3 = getDistanceBetweenPoints3D(px, py, pz, wx, wy, wz)
        if d3 > 7 then return end
        local sx, sy = getScreenFromWorldPosition(wx, wy, wz)
        if not sx then return end
        local d = math.sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
        if d < radius and d < bestD and isLineOfSightClear(camX, camY, camZ, wx, wy, wz, true, false, false, true, false, false, false, localPlayer) then
            best, bestD = el, d
        end
    end
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if p ~= localPlayer and getElementData(p, "rp:characterId") and not getPedOccupiedVehicle(p) then
            local x, y, z = getElementPosition(p)
            consider(p, x, y, z + 0.2, 70)
        end
    end
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local x, y, z = getElementPosition(v)
        consider(v, x, y, z, 110)
    end
    return best
end

addEventHandler("onClientRender", root, function()
    if not cursorMode then return end
    if not onDuty() then return stopCursor() end
    dxDrawText("INTERACCION POLICIAL  -  click derecho sobre un jugador o vehiculo  -  K para salir",
        0, sh - 60, sw, sh - 30, tocolor(255, 255, 255, 230), 1.0, "default-bold", "center", "center", false, false, true)
    if menu then
        local rowH, w = 30, 230
        local h = #menu.options * rowH + 34
        local x, y = math.min(menu.x, sw - w - 10), math.min(menu.y, sh - h - 10)
        menu.box = { x = x, y = y, w = w, h = h }
        dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 235))
        dxDrawRectangle(x, y, w, 2, tocolor(59, 111, 224, 255))
        dxDrawText(menu.title, x + 12, y + 4, x + w - 8, y + 30, tocolor(255, 255, 255, 255), 1, "default-bold", "left", "center", true)
        local mx, my = getCursorPosition()
        mx, my = (mx or 0) * sw, (my or 0) * sh
        for i, o in ipairs(menu.options) do
            local ry = y + 30 + (i - 1) * rowH
            local over = mx >= x and mx <= x + w and my >= ry and my < ry + rowH
            if over and not o.disabled then dxDrawRectangle(x, ry, w, rowH, tocolor(255, 255, 255, 28)) end
            local a = o.disabled and 110 or 255
            dxDrawText((o.icon or "") .. "  " .. o.label .. (o.hint and ("  (" .. o.hint .. ")") or ""), x + 12, ry, x + w - 8, ry + rowH,
                tocolor(235, 238, 245, a), 0.95, "default", "left", "center", true)
        end
        return
    end
    hover = pickTarget()
    if isElement(hover) then
        local x, y, z = getElementPosition(hover)
        local sx, sy = getScreenFromWorldPosition(x, y, z + (getElementType(hover) == "player" and 1.1 or 1.4))
        if sx then
            local label = getElementType(hover) == "player" and (getPlayerName(hover):gsub("_", " ")) or (getVehicleNameFromModel(getElementModel(hover)) or "Vehiculo")
            dxDrawText("▼ " .. label, sx - 100, sy - 24, sx + 100, sy, tocolor(90, 160, 255, 255), 1, "default-bold", "center", "bottom")
        end
    end
end)

addEventHandler("onClientClick", root, function(button, state)
    if not cursorMode or state ~= "down" then return end
    local mx, my = getCursorPosition()
    if not mx then return end
    mx, my = mx * sw, my * sh
    if menu then
        local b = menu.box
        if button == "left" and b and mx >= b.x and mx <= b.x + b.w then
            local i = math.floor((my - (b.y + 30)) / 30) + 1
            local o = menu.options[i]
            if o and not o.disabled and isElement(menu.target) then
                triggerServerEvent("rp:pol:do", resourceRoot, menu.target, o.id)
            end
        end
        menu = nil
        return
    end
    if button == "right" and isElement(hover) then
        menu = { target = hover, title = "...", options = {}, x = mx, y = my, pending = true }
        triggerServerEvent("rp:pol:menu", resourceRoot, hover)
    end
end)

addEventHandler("rp:pol:menuOptions", resourceRoot, function(target, title, options)
    if not cursorMode or not menu or menu.target ~= target then return end
    menu.title, menu.options, menu.pending = tostring(title), options, nil
end)
-- Un menu sin respuesta (sin opciones) no debe quedar colgado
setTimer(function()
    if menu and menu.pending and #menu.options == 0 then menu = nil end
end, 1500, 0)

----------------------------------------------------------------
-- Taser y disparos
----------------------------------------------------------------
addEventHandler("onClientPlayerDamage", localPlayer, function(attacker, weapon)
    if weapon == 23 and isElement(attacker) and getElementType(attacker) == "player" and attacker ~= localPlayer then
        cancelEvent()
        triggerServerEvent("rp:pol:tased", resourceRoot, attacker)
    end
end)

addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon)
    if weapon < 22 or weapon > 38 or weapon == 23 then return end
    local now = getTickCount()
    if now - lastShot < 1500 then return end
    lastShot = now
    triggerServerEvent("rp:pol:shot", resourceRoot, weapon)
end)

----------------------------------------------------------------
-- Rotulos de los puntos
----------------------------------------------------------------
addEventHandler("onClientRender", root, function()
    if #points == 0 or not ready() then return end
    local px, py, pz = getElementPosition(localPlayer)
    local myInt = getElementInterior(localPlayer)
    for _, pt in ipairs(points) do
        local d = getDistanceBetweenPoints3D(px, py, pz, pt.x, pt.y, pt.z)
        if d < 14 and pt.interior == myInt then
            local sx, sy = getScreenFromWorldPosition(pt.x, pt.y, pt.z + 0.4)
            if sx then
                local a = math.floor(255 * (1 - d / 14))
                dxDrawText(pt.label, sx - 100, sy - 20, sx + 100, sy, tocolor(255, 255, 255, a), 1, "default-bold", "center", "bottom")
                if d <= POLICE.POINT_RADIUS + 1 then
                    dxDrawText("Pulsa E", sx - 100, sy, sx + 100, sy + 20, tocolor(255, 215, 120, a), 0.9, "default", "center", "top")
                end
            end
        end
    end
end)

----------------------------------------------------------------
-- Radar de velocidad y lector de matriculas (patrulla de servicio)
----------------------------------------------------------------
local function speedOf(v)
    local vx, vy, vz = getElementVelocity(v)
    return math.floor(math.sqrt(vx * vx + vy * vy + vz * vz) * 180)
end

setTimer(function()
    local car = getPedOccupiedVehicle(localPlayer)
    if not car or not onDuty() or getVehicleController(car) ~= localPlayer or not (getElementData(car, "rp:policeVeh") or POLICE_VEHICLE_MODELS[getElementModel(car)]) then
        radar = nil
        return
    end
    local cx, cy, cz = getElementPosition(car)
    local _, _, rz = getElementRotation(car)
    local fx, fy = -math.sin(math.rad(rz)), math.cos(math.rad(rz))
    local list, nearest, nd = {}, nil, 9999
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if v ~= car then
            local x, y, z = getElementPosition(v)
            local dx, dy = x - cx, y - cy
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 4 and d < 45 and (dx * fx + dy * fy) / d > 0.93 then
                list[#list + 1] = v
                if d < nd then nearest, nd = v, d end
            end
        end
    end
    if #list > 0 then triggerServerEvent("rp:pol:alpr", resourceRoot, list) end
    if nearest then
        local cached = alpr[nearest]
        radar = { speed = speedOf(nearest), plate = getVehiclePlateText(nearest), data = cached and cached.data, at = getTickCount() }
        local d = cached and cached.data
        if d and (d.bolo or d.unpaid > 0) and not cached.beeped then
            cached.beeped = true
            playSoundFrontEnd(d.bolo and 5 or 4)
        end
    else
        radar = nil
    end
end, 600, 0)

addEventHandler("rp:pol:alprResult", resourceRoot, function(v, data)
    if isElement(v) then alpr[v] = { data = data, at = getTickCount(), beeped = alpr[v] and alpr[v].beeped } end
end)

addEventHandler("onClientRender", root, function()
    if not radar or getTickCount() - radar.at > 2500 then return end
    local w, h = 300, 58
    local x, y = sw / 2 - w / 2, sh - 150
    dxDrawRectangle(x, y, w, h, tocolor(8, 10, 16, 215))
    dxDrawRectangle(x, y, 3, h, tocolor(59, 111, 224, 255))
    dxDrawText("RADAR", x + 12, y + 4, x + 80, y + 20, tocolor(120, 150, 210, 255), 0.85, "default-bold")
    dxDrawText(("%d km/h"):format(radar.speed), x + 12, y + 18, x + 150, y + h, tocolor(255, 255, 255, 255), 1.6, "default-bold", "left", "center")
    local d = radar.data
    local line = d and d.plate or radar.plate
    dxDrawText(line, x + 150, y + 6, x + w - 8, y + 26, tocolor(255, 255, 255, 255), 1.0, "default-bold", "right", "center")
    local flag, color = "Sin novedades", tocolor(120, 220, 150, 255)
    if d and d.bolo then flag, color = "BOLO: " .. d.bolo:sub(1, 28), tocolor(255, 90, 90, 255)
    elseif d and d.unpaid > 0 then flag, color = ("Multas $%d"):format(d.unpaid), tocolor(255, 190, 70, 255)
    elseif not d then flag, color = "Sin registro", tocolor(150, 155, 170, 255) end
    dxDrawText(flag, x + 150, y + 28, x + w - 8, y + h - 4, color, 0.9, "default", "right", "center", true)
end)
