--[[
    rp_seatbelt / c_seatbelt.lua
    Tecla C para el cinturon, aviso en pantalla sin el, deteccion de choques del coche en
    el que vas, vuelo por el parabrisas en camara lenta, pantalla en negro y despertar.
]]

addEvent("rp:seatbelt:changed", true)
addEvent("rp:seatbelt:eject", true)

local sw, sh = guiGetScreenSize()
local u = sh / 1080

local lastKey = 0
local lastSpeed, lastVel = 0, { 0, 0, 0 }   -- del coche en el frame anterior (km/h y vector)
local crashPending, lastCrashTick = false, 0
local launch                                  -- { x, y, z, vx, vy, vz } preparado al pedir la salida
local flight                                  -- { start, prev } durante el vuelo
local screen                                  -- { start } negro y despertar
local scratchStart                            -- rasguno en los bordes
local lastBeep = 0
local hudHeld = false

local function cfg() return SEATBELT end

local function myBeltVehicle()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle and cfg().VEHICLE_TYPES[getVehicleType(vehicle)] then return vehicle end
end

local function belted() return getElementData(localPlayer, "rp:seatbelt") == true end

local function isDowned()
    local res = getResourceFromName("rp_injury")
    return res and getResourceState(res) == "running" and exports.rp_injury:isLocalPlayerDowned()
end

local function hudSuppressed()
    local res = getResourceFromName("rp_hud")
    return res and getResourceState(res) == "running" and exports.rp_hud:isHudSuppressed()
end

local function holdHud(on)
    if hudHeld == on then return end
    hudHeld = on
    local res = getResourceFromName("rp_hud")
    if res and getResourceState(res) == "running" then exports.rp_hud:setHudSuppressed("rp_seatbelt", on) end
end

local function sound(name, volume)
    local s = playSound("sounds/" .. name .. ".ogg")
    if s then setSoundVolume(s, volume or 1) end
end

local function speedOf(element)
    local vx, vy, vz = getElementVelocity(element)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180, vx, vy, vz
end

----------------------------------------------------------------
-- Tecla C
----------------------------------------------------------------
local function toggleBelt()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
    if not myBeltVehicle() or flight or screen or isDowned() then return end
    local now = getTickCount()
    if now - lastKey < cfg().COOLDOWN then return end
    lastKey = now
    triggerServerEvent("rp:seatbelt:toggle", resourceRoot)
end

addEventHandler("rp:seatbelt:changed", resourceRoot, function(on)
    sound(on and "buckle" or "unbuckle", 0.8)
    exports.rp_notify:notify(on and "Te pusiste el cinturon." or "Te quitaste el cinturon.", on and "success" or "info")
end)

----------------------------------------------------------------
-- Choques
----------------------------------------------------------------
-- Donde empieza el vuelo: sobre el capo, delante del parabrisas, hacia donde iba el coche
local function prepareLaunch(vehicle)
    local m = getElementMatrix(vehicle)
    local _, _, _, _, maxY, maxZ = getElementBoundingBox(vehicle)
    local x, y, z = getElementPosition(vehicle)
    local fy, uz = (maxY or 2) * 0.45, (maxZ or 1) + 0.5
    local vx, vy, vz = lastVel[1], lastVel[2], lastVel[3]
    local len = math.sqrt(vx * vx + vy * vy + vz * vz)
    if len < 0.01 then vx, vy, vz, len = m[2][1], m[2][2], m[2][3], 1 end
    local speed = math.min(len * cfg().EJECT.FORCE, cfg().EJECT.MAX_SPEED)
    launch = {
        x = x + m[2][1] * fy + m[3][1] * uz,
        y = y + m[2][2] * fy + m[3][2] * uz,
        z = z + m[2][3] * fy + m[3][3] * uz,
        vx = vx / len * speed, vy = vy / len * speed, vz = vz / len * speed + cfg().EJECT.LIFT,
    }
end

local function evaluateCrash(vehicle, before)
    crashPending = false
    if not isElement(vehicle) or getPedOccupiedVehicle(localPlayer) ~= vehicle or belted() or isDowned() then return end
    local drop = before - speedOf(vehicle)
    if drop >= cfg().EJECT_DROP then
        prepareLaunch(vehicle)
        triggerServerEvent("rp:seatbelt:crash", resourceRoot, "eject")
    elseif drop >= cfg().LIGHT_DROP then
        scratchStart = getTickCount()
        sound("impact", 0.6)
        triggerServerEvent("rp:seatbelt:crash", resourceRoot, "light")
    end
end

addEventHandler("onClientVehicleCollision", root, function(hitElement)
    if source ~= myBeltVehicle() or crashPending or belted() or flight then return end
    -- Atropellar a alguien no cuenta como choque
    if isElement(hitElement) and (getElementType(hitElement) == "ped" or getElementType(hitElement) == "player") then return end
    local now = getTickCount()
    if now - lastCrashTick < cfg().CRASH_COOLDOWN then return end
    lastCrashTick, crashPending = now, true
    setTimer(evaluateCrash, cfg().MEASURE_DELAY, 1, source, lastSpeed)
end)

----------------------------------------------------------------
-- Vuelo y despertar
----------------------------------------------------------------
local function endFlight()
    if not flight then return end
    flight = nil
    setGameSpeed(1)
    sound("impact", 1)
    screen = { start = getTickCount() }
    holdHud(true)
    triggerServerEvent("rp:seatbelt:landed", resourceRoot)
end

addEventHandler("rp:seatbelt:eject", resourceRoot, function()
    if not launch then return end
    local l = launch
    launch = nil
    sound("glass", 1)
    -- Un instante para que el servidor termine de sacarlo del coche
    setTimer(function()
        setElementPosition(localPlayer, l.x, l.y, l.z, false)
        setElementVelocity(localPlayer, l.vx, l.vy, l.vz)
        setGameSpeed(cfg().EJECT.SLOWMO)
        flight = { start = getTickCount(), prev = speedOf(localPlayer) }
    end, 60, 1)
end)

-- Mientras vuela y esta en negro no recibe dano (lo decide el servidor al aterrizar)
addEventHandler("onClientPlayerDamage", localPlayer, function()
    if flight or screen then cancelEvent() end
end, true, "high+10")

addEventHandler("onClientPreRender", root, function()
    local vehicle = myBeltVehicle()
    if vehicle then
        local s, vx, vy, vz = speedOf(vehicle)
        if not crashPending then lastSpeed, lastVel = s, { vx, vy, vz } end
    end

    if flight then
        local elapsed = getTickCount() - flight.start
        local s = speedOf(localPlayer)
        local stopped = s < flight.prev * 0.45 or (isPedOnGround(localPlayer) and s < 15)
        flight.prev = s
        if (elapsed > cfg().EJECT.MIN_FLIGHT and stopped) or elapsed > cfg().EJECT.MAX_FLIGHT then endFlight() end
    end
end)

-- Apertura de ojos (0 cerrado, 1 abierto del todo) con dos parpadeos antes de abrir
local WAKE = { { 0, 0 }, { 0.18, 0.28 }, { 0.30, 0.04 }, { 0.48, 0.55 }, { 0.60, 0.22 }, { 0.80, 0.85 }, { 1, 1.25 } }
local function eyeOpening(t)
    for i = 2, #WAKE do
        local a, b = WAKE[i - 1], WAKE[i]
        if t <= b[1] then
            local k = (t - a[1]) / (b[1] - a[1])
            k = k * k * (3 - 2 * k)
            return a[2] + (b[2] - a[2]) * k
        end
    end
    return WAKE[#WAKE][2]
end

local function drawScreen()
    local elapsed = getTickCount() - screen.start
    local c = cfg()
    if elapsed < c.BLACK_TIME then
        dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 255), true)
        return
    end
    local t = (elapsed - c.BLACK_TIME) / c.WAKE_TIME
    if t >= 1 then
        screen = nil
        holdHud(false)
        return
    end
    local open = eyeOpening(t)
    local w, h = sw * 1.6, sh * 1.7 * open
    local y = (sh - h) / 2
    dxDrawImage((sw - w) / 2, y, w, h, "images/eyelid.png", 0, 0, 0, tocolor(255, 255, 255, 255), true)
    if y > 0 then
        dxDrawRectangle(0, 0, sw, y + 1, tocolor(0, 0, 0, 255), true)
        dxDrawRectangle(0, y + h - 1, sw, sh - y - h + 2, tocolor(0, 0, 0, 255), true)
    end
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, math.floor(140 * (1 - t))), true)   -- sigue aturdido
end

local function drawIndicator(vehicle)
    local pulse = 0.55 + 0.45 * math.abs(math.sin(getTickCount() / 350))
    local size = 44 * u
    local text = "Ponte el cinturon"
    local tw = dxGetTextWidth(text, 1.1 * u, "default-bold")
    local x = (sw - size - 10 * u - tw) / 2
    local y = sh - 150 * u
    dxDrawRectangle(x - 12 * u, y - 6 * u, size + tw + 34 * u, size + 12 * u, tocolor(10, 10, 14, 170))
    dxDrawImage(x, y, size, size, "images/key_c.png", 0, 0, 0, tocolor(255, 255, 255, 255))
    dxDrawText(text, x + size + 10 * u, y, x + size + 10 * u + tw, y + size, tocolor(255, 90, 80, math.floor(255 * pulse)), 1.1 * u, "default-bold", "left", "center")

    -- Pitido de aviso si el coche va rapido sin cinturon
    local now = getTickCount()
    if speedOf(vehicle) > 30 and now - lastBeep > 4000 then
        lastBeep = now
        sound("warning", 0.35)
    end
end

addEventHandler("onClientRender", root, function()
    if scratchStart then
        local k = (getTickCount() - scratchStart) / cfg().SCRATCH_TIME
        if k >= 1 then scratchStart = nil
        else dxDrawImage(0, 0, sw, sh, "images/scratch.png", 0, 0, 0, tocolor(255, 255, 255, math.floor(255 * (1 - k * k)))) end
    end
    if screen then return drawScreen() end
    local vehicle = myBeltVehicle()
    if vehicle and not belted() and not flight and not hudSuppressed() and not isDowned() then drawIndicator(vehicle) end
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(SEATBELT.KEY, "down", toggleBelt)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if flight then setGameSpeed(1) end
    holdHud(false)
end)
