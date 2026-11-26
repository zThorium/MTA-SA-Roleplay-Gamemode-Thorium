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
local history, historyVehicle = {}, nil     -- velocidades recientes del coche: { t, s, vx, vy, vz }
local hitTick, lastCrashTick = nil, 0        -- golpe pendiente de medir / ultimo choque que conto
local launch                                  -- { x, y, z, vx, vy, vz } preparado al pedir la salida
local flight                                  -- { start, prev } durante el vuelo
local screen                                  -- { start } negro y despertar
local scratchStart                            -- rojo en los bordes (choque leve)
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

local function sound(name, volume, ext)
    local s = playSound("sounds/" .. name .. "." .. (ext or "ogg"))
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
local function prepareLaunch(vehicle, before)
    local m = getElementMatrix(vehicle)
    local _, _, _, _, maxY, maxZ = getElementBoundingBox(vehicle)
    local x, y, z = getElementPosition(vehicle)
    local fy, uz = (maxY or 2) * 0.45, (maxZ or 1) + 0.5
    local vx, vy, vz = before.vx, before.vy, before.vz
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

-- La velocidad "de antes" es la mayor de los ultimos frames previos al golpe: el evento de
-- colision puede llegar cuando el frame ya registro la velocidad tras el choque.
local function peakBefore(tick)
    local best
    for _, e in ipairs(history) do
        if e.t <= tick and tick - e.t <= 400 and (not best or e.s > best.s) then best = e end
    end
    return best
end

local function evaluateCrash(vehicle)
    local tick = hitTick
    hitTick = nil
    if not tick or not isElement(vehicle) or getPedOccupiedVehicle(localPlayer) ~= vehicle or belted() or isDowned() then return end
    local before = peakBefore(tick)
    if not before then return end
    local drop = before.s - speedOf(vehicle)
    -- Para calibrar los umbrales con /debugscript 3
    outputDebugString(("[rp_seatbelt] choque: %.0f km/h antes, perdio %.0f km/h"):format(before.s, drop), 3)
    if drop < cfg().LIGHT_DROP then return end
    lastCrashTick = getTickCount()
    if drop >= cfg().EJECT_DROP then
        prepareLaunch(vehicle, before)
        triggerServerEvent("rp:seatbelt:crash", resourceRoot, "eject")
    else
        scratchStart = getTickCount()
        sound("impact", 0.6)
        triggerServerEvent("rp:seatbelt:crash", resourceRoot, "light")
    end
end

addEventHandler("onClientVehicleCollision", root, function(hitElement)
    if source ~= myBeltVehicle() or hitTick or belted() or flight then return end
    -- Atropellar a alguien no cuenta como choque
    if isElement(hitElement) and (getElementType(hitElement) == "ped" or getElementType(hitElement) == "player") then return end
    local now = getTickCount()
    if now - lastCrashTick < cfg().CRASH_COOLDOWN then return end
    hitTick = now
    setTimer(evaluateCrash, cfg().MEASURE_DELAY, 1, source)
end)

----------------------------------------------------------------
-- Vuelo y despertar
----------------------------------------------------------------
-- Inconsciente: silencio total (sonidos del mundo, radio y sonidos de cualquier recurso)
local muted   -- [sonido] = volumen anterior
local function muteAll(on)
    local radio = getResourceFromName("rp_radio")
    if radio and getResourceState(radio) == "running" then exports.rp_radio:setRadioSuppressed("rp_seatbelt", on) end
    if on then
        if muted then return end
        muted = {}
        for group = 0, 44 do setWorldSoundEnabled(group, false) end
        setAmbientSoundEnabled("general", false)
        setAmbientSoundEnabled("gunfire", false)
        for _, s in ipairs(getElementsByType("sound")) do
            muted[s] = getSoundVolume(s)
            setSoundVolume(s, 0)
        end
    elseif muted then
        resetWorldSounds()
        resetAmbientSounds()
        for s, volume in pairs(muted) do
            if isElement(s) then setSoundVolume(s, volume) end
        end
        muted = nil
    end
end

local function endFlight()
    if not flight then return end
    flight = nil
    setGameSpeed(1)
    muteAll(true)
    screen = { start = getTickCount() }
    holdHud(true)
    triggerServerEvent("rp:seatbelt:landed", resourceRoot)
end

addEventHandler("rp:seatbelt:eject", resourceRoot, function()
    if not launch then return end
    local l = launch
    launch = nil
    sound("glass", 1, "mp3")
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
    if vehicle ~= historyVehicle then history, historyVehicle = {}, vehicle end
    if vehicle then
        local now = getTickCount()
        local s, vx, vy, vz = speedOf(vehicle)
        history[#history + 1] = { t = now, s = s, vx = vx, vy = vy, vz = vz }
        while history[1] and now - history[1].t > 600 do table.remove(history, 1) end
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
    muteAll(false)   -- el sonido vuelve al abrir los ojos
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
        else dxDrawImage(0, 0, sw, sh, "images/border.png", 0, 0, 0, tocolor(255, 255, 255, math.floor(255 * (1 - k * k)))) end
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
    muteAll(false)
    holdHud(false)
end)
