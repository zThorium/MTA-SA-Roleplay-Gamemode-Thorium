--[[
    rp_admin / c_freecam.lua
    Camara libre para super administradores (/freecam).
      W A S D        mover          Espacio / Ctrl izq.   subir / bajar
      Shift          rapido         Alt                    lento
      Rueda raton    velocidad base (+/-)
      F              teletransportar al punto de la camara y salir
      Raton          mirar (si el cursor esta visible, mantener clic derecho)
    El personaje queda congelado donde estaba (mismo interior y dimension).
]]

local active = false
local x, y, z = 0, 0, 0
local yaw, pitch = 0, 0               -- grados
local SENS = 0.15
local lastCursor = nil
local baseSpeed = 20
local SPEED_MIN, SPEED_MAX = 2, 200
local lastTp = 0

local function forward()
    local cy, sy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local cp, sp = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
    return sy * cp, cy * cp, sp
end

local function update(dt)
    dt = math.min(dt, 100) / 1000
    local speed = baseSpeed
    if getKeyState("lshift") then speed = baseSpeed * 4 elseif getKeyState("lalt") then speed = baseSpeed / 5 end

    -- Girar: con cursor visible (p. ej. editor de rutas) solo manteniendo clic derecho
    if isCursorShowing() then
        local cx, cy = getCursorPosition()
        if getKeyState("mouse2") and cx and lastCursor then
            yaw = yaw + (cx - lastCursor[1]) * 360 * SENS * 3
            pitch = math.max(-89, math.min(89, pitch - (cy - lastCursor[2]) * 180 * SENS * 3))
        end
        lastCursor = cx and { cx, cy } or nil
    end

    local fx, fy, fz = forward()
    local rx, ry = math.cos(math.rad(yaw)), -math.sin(math.rad(yaw))
    local move = speed * dt
    if getKeyState("w") then x, y, z = x + fx * move, y + fy * move, z + fz * move end
    if getKeyState("s") then x, y, z = x - fx * move, y - fy * move, z - fz * move end
    if getKeyState("d") then x, y = x + rx * move, y + ry * move end
    if getKeyState("a") then x, y = x - rx * move, y - ry * move end
    if getKeyState("space") then z = z + move end
    if getKeyState("lctrl") then z = z - move end

    setCameraMatrix(x, y, z, x + fx * 10, y + fy * 10, z + fz * 10)
end

-- HUD: coordenadas y velocidad
local function drawHud()
    local sw, sh = guiGetScreenSize()
    local text = ("FREECAM  |  X %.1f  Y %.1f  Z %.1f  |  Velocidad %d (rueda)  |  F: teletransportar"):format(x, y, z, baseSpeed)
    dxDrawText(text, 1, sh - 29, sw + 1, sh - 9, tocolor(0, 0, 0, 220), 1, "default-bold", "center", "center")
    dxDrawText(text, 0, sh - 30, sw, sh - 10, tocolor(255, 255, 255, 235), 1, "default-bold", "center", "center")
end

local function onMouse(_, _, absX, absY)
    if isCursorShowing() or isMainMenuActive() then return end
    -- Con el cursor oculto MTA lo recentra: el desplazamiento respecto al centro es el giro
    local sw, sh = guiGetScreenSize()
    local dx, dy = absX - sw / 2, absY - sh / 2
    yaw = yaw + dx * SENS
    pitch = math.max(-89, math.min(89, pitch - dy * SENS))
end

local function speedUp() baseSpeed = math.min(SPEED_MAX, math.floor(baseSpeed * 1.25 + 0.5)) end
local function speedDown() baseSpeed = math.max(SPEED_MIN, math.floor(baseSpeed * 0.8 + 0.5)) end

local function teleportToFreecam()
    if not active or isChatBoxInputActive() then return end
    if getTickCount() - lastTp < 1500 then return end
    lastTp = getTickCount()
    -- Si la camara esta en el aire y hay suelo cargado debajo, aterrizar encima del suelo
    local tz = z
    local gz = getGroundPosition(x, y, z)
    if gz and gz ~= 0 and gz < z and z - gz < 60 then tz = gz + 1 end
    triggerServerEvent("rp:admin:freecam:teleport", resourceRoot, x, y, tz)
end

local function enable()
    active = true
    bindKey("f", "down", teleportToFreecam)
    bindKey("mouse_wheel_up", "down", speedUp)
    bindKey("mouse_wheel_down", "down", speedDown)
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    x, y, z = cx, cy, cz
    yaw = math.deg(math.atan2(tx - cx, ty - cy))
    pitch = math.deg(math.atan2(tz - cz, getDistanceBetweenPoints2D(cx, cy, tx, ty)))
    setElementFrozen(localPlayer, true)
    toggleAllControls(false, true, false)
    addEventHandler("onClientPreRender", root, update)
    addEventHandler("onClientRender", root, drawHud)
    addEventHandler("onClientCursorMove", root, onMouse)
    triggerServerEvent("rp:admin:freecam:active", resourceRoot, true)
    exports.rp_notify:notify("Freecam activada: WASD, Espacio/Ctrl, Shift rapido, rueda = velocidad. F teletransporta y sale. /freecam para salir.", "info")
end

local function disable()
    active = false
    unbindKey("f", "down", teleportToFreecam)
    unbindKey("mouse_wheel_up", "down", speedUp)
    unbindKey("mouse_wheel_down", "down", speedDown)
    removeEventHandler("onClientPreRender", root, update)
    removeEventHandler("onClientRender", root, drawHud)
    removeEventHandler("onClientCursorMove", root, onMouse)
    setElementFrozen(localPlayer, false)
    toggleAllControls(true, true, false)
    setCameraTarget(localPlayer)
    triggerServerEvent("rp:admin:freecam:active", resourceRoot, false)
    exports.rp_notify:notify("Freecam desactivada.", "info")
end

addEvent("rp:admin:freecam", true)
addEventHandler("rp:admin:freecam", resourceRoot, function()
    if active then disable() else enable() end
end)

-- El servidor confirma el teleport: parpadeo de camara como confirmacion visual
addEvent("rp:admin:freecam:teleported", true)
addEventHandler("rp:admin:freecam:teleported", resourceRoot, function()
    fadeCamera(false, 0.15)
    setTimer(function() fadeCamera(true, 0.35) end, 250, 1)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then disable() end
end)

function isFreecamActive() return active end
