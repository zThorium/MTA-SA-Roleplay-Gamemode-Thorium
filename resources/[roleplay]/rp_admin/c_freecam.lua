--[[
    rp_admin / c_freecam.lua
    Camara libre para administradores (/freecam).
      W A S D      mover          Espacio / Ctrl izq.   subir / bajar
      Shift        rapido         Alt                    lento
      Raton        mirar (si el cursor esta visible, mantener clic derecho)
    El personaje queda congelado donde estaba.
]]

local active = false
local x, y, z = 0, 0, 0
local yaw, pitch = 0, 0               -- grados
local SENS = 0.15
local lastCursor = nil

local function forward()
    local cy, sy = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    local cp, sp = math.cos(math.rad(pitch)), math.sin(math.rad(pitch))
    return sy * cp, cy * cp, sp
end

local function update(dt)
    dt = math.min(dt, 100) / 1000
    local speed = 20
    if getKeyState("lshift") then speed = 80 elseif getKeyState("lalt") then speed = 4 end

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

local function onMouse(_, _, absX, absY)
    if isCursorShowing() or isMainMenuActive() then return end
    -- Con el cursor oculto MTA lo recentra: el desplazamiento respecto al centro es el giro
    local sw, sh = guiGetScreenSize()
    local dx, dy = absX - sw / 2, absY - sh / 2
    yaw = yaw + dx * SENS
    pitch = math.max(-89, math.min(89, pitch - dy * SENS))
end

local function enable()
    active = true
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    x, y, z = cx, cy, cz
    yaw = math.deg(math.atan2(tx - cx, ty - cy))
    pitch = math.deg(math.atan2(tz - cz, getDistanceBetweenPoints2D(cx, cy, tx, ty)))
    setElementFrozen(localPlayer, true)
    toggleAllControls(false, true, false)
    addEventHandler("onClientPreRender", root, update)
    addEventHandler("onClientCursorMove", root, onMouse)
    exports.rp_notify:notify("Freecam activada: WASD, Espacio/Ctrl, Shift rapido. /freecam para salir.", "info")
end

local function disable()
    active = false
    removeEventHandler("onClientPreRender", root, update)
    removeEventHandler("onClientCursorMove", root, onMouse)
    setElementFrozen(localPlayer, false)
    toggleAllControls(true, true, false)
    setCameraTarget(localPlayer)
    exports.rp_notify:notify("Freecam desactivada.", "info")
end

addEvent("rp:admin:freecam", true)
addEventHandler("rp:admin:freecam", resourceRoot, function()
    if active then disable() else enable() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then disable() end
end)

function isFreecamActive() return active end
