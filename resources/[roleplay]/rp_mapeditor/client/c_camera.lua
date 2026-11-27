--[[
    rp_mapeditor / c_camera.lua
    Cámara libre del editor con el cursor siempre visible.
        W A S D        mover            Q / E         bajar / subir
        Mayús / Alt    rápido / lento   Rueda         velocidad (si no hay nada que girar)
        Clic derecho mantenido          mirar alrededor
    El personaje (congelado e invisible) sigue a la cámara para que el juego cargue las colisiones
    y los objetos de la zona.
]]

MECam = { active = false, x = 0, y = 0, z = 0, yaw = 0, pitch = -20, speed = 1, looking = false }

local screenW, screenH = guiGetScreenSize()
local lastSync = 0
local lookFrom = nil

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

function MECam.dir()
    local yr, pr = math.rad(MECam.yaw), math.rad(MECam.pitch)
    return math.cos(pr) * math.sin(yr), math.cos(pr) * math.cos(yr), math.sin(pr)
end

function MECam.start(x, y, z, yaw, pitch)
    MECam.x, MECam.y, MECam.z = x, y, z
    MECam.yaw, MECam.pitch = yaw or 0, pitch or -25
    MECam.active = true
end

function MECam.stop()
    MECam.active, MECam.looking, lookFrom = false, false, nil
    setCameraTarget(localPlayer)
end

-- Coloca la cámara mirando a un punto desde cierta distancia
function MECam.focus(x, y, z, dist)
    dist = dist or 10
    local dx, dy, dz = MECam.dir()
    MECam.x, MECam.y, MECam.z = x - dx * dist, y - dy * dist, z - dz * dist
end

function MECam.typing()
    return (MEEditor and MEEditor.isTyping and MEEditor.isTyping()) or (MEUI and MEUI.modalOpen and MEUI.modalOpen())
end

addEventHandler("onClientPreRender", root, function(ms)
    if not MECam.active then return end
    local dt = math.min(ms, 100) / 1000
    if not MECam.typing() and not isChatBoxInputActive() and not isConsoleActive() then
        local fx, fy, fz = MECam.dir()
        local rx, ry = math.cos(math.rad(MECam.yaw)), -math.sin(math.rad(MECam.yaw))
        local mx, my, mz = 0, 0, 0
        if getKeyState("w") then mx, my, mz = mx + fx, my + fy, mz + fz end
        if getKeyState("s") then mx, my, mz = mx - fx, my - fy, mz - fz end
        if getKeyState("d") then mx, my = mx + rx, my + ry end
        if getKeyState("a") then mx, my = mx - rx, my - ry end
        -- Ctrl queda para atajos (Ctrl+Z...): Q y E bajan y suben
        if not (getKeyState("lctrl") or getKeyState("rctrl")) then
            if getKeyState("e") then mz = mz + 1 end
            if getKeyState("q") then mz = mz - 1 end
        end
        local len = math.sqrt(mx * mx + my * my + mz * mz)
        if len > 0 then
            local C = MAPEDIT
            local sp = C.CAM_SPEED * MECam.speed
            if getKeyState("lshift") or getKeyState("rshift") then sp = sp * C.CAM_FAST end
            if getKeyState("lalt") then sp = sp * C.CAM_SLOW end
            MECam.x = MECam.x + mx / len * sp * dt
            MECam.y = MECam.y + my / len * sp * dt
            MECam.z = clamp(MECam.z + mz / len * sp * dt, MAPEDIT.Z_MIN, MAPEDIT.Z_MAX)
        end
    end
    local fx, fy, fz = MECam.dir()
    setCameraMatrix(MECam.x, MECam.y, MECam.z, MECam.x + fx * 10, MECam.y + fy * 10, MECam.z + fz * 10)

    local now = getTickCount()
    if now - lastSync > 250 then
        lastSync = now
        setElementPosition(localPlayer, MECam.x, MECam.y, MECam.z - 2, false)
    end
end)

-- Mirar con el clic derecho mantenido (el cursor vuelve a su sitio)
function MECam.beginLook()
    local cx, cy = getCursorPosition()
    if not cx then return end
    MECam.looking, lookFrom = true, { cx * screenW, cy * screenH }
end

function MECam.endLook() MECam.looking, lookFrom = false, nil end

addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
    if not (MECam.active and MECam.looking and lookFrom) then return end
    local dx, dy = ax - lookFrom[1], ay - lookFrom[2]
    if dx == 0 and dy == 0 then return end
    MECam.yaw = (MECam.yaw + dx * 0.18) % 360
    MECam.pitch = clamp(MECam.pitch - dy * 0.18, -89, 89)
    setCursorPosition(lookFrom[1], lookFrom[2])
end)

function MECam.wheel(up)
    MECam.speed = clamp(MECam.speed * (up and 1.25 or 0.8), 0.05, 20)
    return MECam.speed
end
