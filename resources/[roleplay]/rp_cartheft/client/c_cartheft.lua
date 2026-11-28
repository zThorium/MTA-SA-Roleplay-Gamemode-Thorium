--[[
    rp_cartheft / c_cartheft.lua  (cliente)

    - Aviso con la tecla E dibujada junto a la puerta del conductor de un vehiculo cerrado.
    - Minijuegos CEF (cerradura y puente) y guia de cada paso (J para el puente, bocina x2).
    - Alarma de cualquier vehiculo con rp:carAlarm: sirena 3D y luces que parpadean.
    - Policias IA (solo existen en el cliente) que te ven durante el robo -> rp:cartheft:copSeen.
    El cliente solo pide: el servidor revalida todo.
]]

local sw, sh = guiGetScreenSize()
local tex, font = {}, "default-bold"
local doorTarget = nil        -- vehiculo cerrado junto a cuya puerta estas
local stage, stageVehicle = false, nil
local hornTicks = {}

addEvent("rp:cartheft:stage", true)
addEvent("rp:cartheft:chirp", true)
addEvent("rp:cartheft:ui:result", false)
addEvent("rp:cartheft:ui:cancel", false)
addEvent("rp:cartheft:ui:tutorialSeen", false)

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if exports.rp_injury:isLocalPlayerDowned() then return false end
    if exports.rp_hud:isHudSuppressed() then return false end
    return true
end

----------------------------------------------------------------
-- Puerta del conductor: lado izquierdo, un poco por delante del centro
----------------------------------------------------------------
local function doorPosition(v)
    local minX = getElementBoundingBox(v)
    local m = getElementMatrix(v)
    local ox, oy = (minX or -1) - 0.25, 0.35
    return ox * m[1][1] + oy * m[2][1] + m[4][1],
           ox * m[1][2] + oy * m[2][2] + m[4][2],
           ox * m[1][3] + oy * m[2][3] + m[4][3]
end

local function findDoor()
    if stage or isPedInVehicle(localPlayer) then return nil end
    local px, py, pz = getElementPosition(localPlayer)
    local dim = getElementDimension(localPlayer)
    for _, v in ipairs(getElementsWithinRange(px, py, pz, 6, "vehicle")) do
        if isVehicleLocked(v) and getElementData(v, "rp:vehicleOwner") and getElementDimension(v) == dim
            and CARTHEFT.TYPES[getVehicleType(v)] then
            local x, y, z = doorPosition(v)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= CARTHEFT.DOOR_RADIUS then return v end
        end
    end
    return nil
end

setTimer(function() doorTarget = findDoor() end, 250, 0)

----------------------------------------------------------------
-- Avisos dibujados
----------------------------------------------------------------
local function drawWorldPrompt(x, y, z, image, text)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.4)
    if not sx then return end
    local k = image and 42 * (1 + math.sin(getTickCount() / 260) * 0.04) or 0
    if image then dxDrawImage(sx - k / 2, sy - k / 2, k, k, image) end
    local tw = dxGetTextWidth(text, 1, font) + 20
    local ty = sy + k / 2 + 4
    dxDrawRectangle(sx - tw / 2, ty, tw, 26, tocolor(14, 12, 12, 190))
    dxDrawText(text, sx - tw / 2, ty, sx + tw / 2, ty + 26, tocolor(255, 255, 255), 1, font, "center", "center")
end

-- Tecla en la parte baja de la pantalla; si la tecla no tiene imagen, se dibuja su nombre en una caja
local function drawScreenPrompt(image, keyName, text)
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawRectangle(x, y, w, 40, tocolor(14, 12, 12, 190))
    if image then
        dxDrawImage(x + 8, y + 4, 32, 32, image)
    else
        dxDrawRectangle(x + 8, y + 6, 32, 28, tocolor(240, 240, 240, 230))
        dxDrawText(keyName:upper(), x + 8, y + 6, x + 40, y + 34, tocolor(20, 20, 20), 0.8, font, "center", "center")
    end
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end

local function hornKey()
    local keys = getBoundKeys("horn")
    for k in pairs(keys or {}) do return k end
    return "h"
end

addEventHandler("onClientRender", root, function()
    if not canInteract() then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    local driving = veh and veh == stageVehicle and getVehicleController(veh) == localPlayer
    if stage == "open" then
        if driving then
            drawScreenPrompt(tex.j, "j", "Hacer el puente")
        elseif isElement(stageVehicle) then
            local x, y, z = doorPosition(stageVehicle)
            local px, py, pz = getElementPosition(localPlayer)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) < 12 then drawWorldPrompt(x, y, z, nil, "Sube al asiento del conductor") end
        end
    elseif stage == "horn" and driving then
        local k = hornKey()
        local presses = 0
        for _, t in ipairs(hornTicks) do if getTickCount() - t <= CARTHEFT.HORN_WINDOW_MS then presses = presses + 1 end end
        drawScreenPrompt(k == "h" and tex.h or nil, k, ("Toca la bocina dos veces para apagar la alarma (%d/%d)"):format(presses, CARTHEFT.HORN_PRESSES))
    elseif not stage and doorTarget then
        local x, y, z = doorPosition(doorTarget)
        drawWorldPrompt(x, y, z, tex.e, "Forzar cerradura (ganzua)")
    end
end)

local function onKeyE()
    -- E la usan muchos recursos: solo actua junto a la puerta de un vehiculo cerrado
    if stage or not doorTarget or not canInteract() then return end
    triggerServerEvent("rp:cartheft:try", resourceRoot, doorTarget)
end

local function onHorn()
    if stage ~= "horn" then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh ~= stageVehicle or getVehicleController(veh) ~= localPlayer then return end
    local now = getTickCount()
    local fresh = {}
    for _, t in ipairs(hornTicks) do if now - t <= CARTHEFT.HORN_WINDOW_MS then fresh[#fresh + 1] = t end end
    fresh[#fresh + 1] = now
    hornTicks = fresh
    if #hornTicks >= CARTHEFT.HORN_PRESSES then
        hornTicks = {}
        triggerServerEvent("rp:cartheft:horn", resourceRoot)
    end
end

----------------------------------------------------------------
-- Minijuegos (CEF)
----------------------------------------------------------------
local browserGui, browser, ready, pendingJS = nil, nil, false, {}

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function closeGame()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

-- La primera vez de cada minijuego se muestra el tutorial (archivo privado del cliente)
local function tutorialSeen(mode)
    return fileExists("@tutorial_" .. mode)
end

local function openGame(mode)
    closeGame()
    browserGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
    local cfg = mode == "pick" and CARTHEFT.PICK or CARTHEFT.WIRE
    callJS(("RP.start(%q, %s[0], %s)"):format(mode, toJSON(cfg, true), tutorialSeen(mode) and "false" or "true"))
end

addEventHandler("rp:cartheft:ui:result", root, function(mode, ok)
    closeGame()
    if mode == "pick" and stage == "pick" then
        triggerServerEvent("rp:cartheft:pickResult", resourceRoot, ok == true)
    elseif mode == "wire" and stage == "wire" then
        triggerServerEvent("rp:cartheft:wireResult", resourceRoot, ok == true)
    end
end)

addEventHandler("rp:cartheft:ui:cancel", root, function()
    closeGame()
    triggerServerEvent("rp:cartheft:cancel", resourceRoot)
end)

addEventHandler("rp:cartheft:ui:tutorialSeen", root, function(mode)
    if (mode == "pick" or mode == "wire") and not tutorialSeen(mode) then
        local f = fileCreate("@tutorial_" .. mode)
        if f then fileClose(f) end
    end
end)

addEventHandler("rp:cartheft:stage", resourceRoot, function(newStage, vehicle)
    stage, stageVehicle = newStage or false, vehicle
    hornTicks = {}
    if newStage == "pick" or newStage == "wire" then openGame(newStage) else closeGame() end
end)

----------------------------------------------------------------
-- Policias IA a la vista durante el robo
----------------------------------------------------------------
local function copSees(px, py, pz, radius)
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if (CARTHEFT.COP_SKINS[getElementModel(ped)] or getElementData(ped, "rp:cop")) and not isPedDead(ped) then
            local x, y, z = getElementPosition(ped)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= radius
                and isLineOfSightClear(px, py, pz + 0.6, x, y, z + 0.6, true, false, false, true, false, false, false, ped) then
                return true
            end
        end
    end
    -- patrullas conducidas por IA
    for _, v in ipairs(getElementsWithinRange(px, py, pz, radius, "vehicle")) do
        local d = getVehicleController(v)
        if CARTHEFT.POLICE_CAR_MODELS[getElementModel(v)] and d and getElementType(d) == "ped" then return true end
    end
    return false
end

setTimer(function()
    if not stage or not isElement(stageVehicle) then return end
    local radius = getElementData(stageVehicle, "rp:carAlarm") and CARTHEFT.COP_RADIUS_ALARM or CARTHEFT.COP_RADIUS
    local px, py, pz = getElementPosition(localPlayer)
    if copSees(px, py, pz, radius) then triggerServerEvent("rp:cartheft:copSeen", resourceRoot) end
end, 1000, 0)

----------------------------------------------------------------
-- Alarma: sirena 3D y luces (para cualquier vehiculo con rp:carAlarm)
----------------------------------------------------------------
local alarms = {}   -- [vehicle] = sound

local function stopAlarmFx(v)
    local snd = alarms[v]
    alarms[v] = nil
    if isElement(snd) then destroyElement(snd) end
    if isElement(v) then setVehicleOverrideLights(v, 0) end
end

local function startAlarmFx(v)
    if alarms[v] or not isElementStreamedIn(v) then return end
    local x, y, z = getElementPosition(v)
    local snd = playSound3D("sounds/alarma_auto.wav", x, y, z, true)
    if snd then
        setSoundMaxDistance(snd, CARTHEFT.ALARM_SOUND_DISTANCE)
        setSoundMinDistance(snd, 8)
        setElementDimension(snd, getElementDimension(v))
        setElementInterior(snd, getElementInterior(v))
        attachElements(snd, v)
    end
    alarms[v] = snd or true
end

local function syncAlarm(v)
    if getElementData(v, "rp:carAlarm") and isElementStreamedIn(v) then startAlarmFx(v) else stopAlarmFx(v) end
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:carAlarm" and getElementType(source) == "vehicle" then syncAlarm(source) end
end)
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" and getElementData(source, "rp:carAlarm") then startAlarmFx(source) end
end)
addEventHandler("onClientElementStreamOut", root, function()
    if alarms[source] then stopAlarmFx(source) end
end)
addEventHandler("onClientElementDestroy", root, function()
    if alarms[source] then stopAlarmFx(source) end
end)

-- Luces que parpadean al ritmo de la sirena
local flash = false
setTimer(function()
    flash = not flash
    for v in pairs(alarms) do
        if isElement(v) then setVehicleOverrideLights(v, flash and 2 or 1) end
    end
end, 400, 0)

addEventHandler("rp:cartheft:chirp", resourceRoot, function(v)
    if not isElement(v) or not isElementStreamedIn(v) then return end
    local x, y, z = getElementPosition(v)
    local snd = playSound3D("sounds/alarma_chirp.wav", x, y, z)
    if snd then setSoundMaxDistance(snd, 40) end
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.e = dxCreateTexture("images/keys/keyboard_e.png", "argb", true, "clamp")
    tex.j = dxCreateTexture("images/keys/keyboard_j.png", "argb", true, "clamp")
    tex.h = dxCreateTexture("images/keys/keyboard_h.png", "argb", true, "clamp")
    font = dxCreateFont("fonts/rubik_medium.ttf", 11) or "default-bold"
    bindKey("e", "down", onKeyE)
    bindKey("horn", "down", onHorn)
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementData(v, "rp:carAlarm") then startAlarmFx(v) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeGame()
    for v in pairs(alarms) do stopAlarmFx(v) end
end)
