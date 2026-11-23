--[[
    rp_radio / c_radio.lua

    Reproduce las emisoras de internet de los vehiculos. Cada cliente lee el dato rp:radio
    de los vehiculos cercanos: el tuyo suena en estereo, los demas como sonido 3D adjunto.
    Tecla R (o /radio): panel de emisoras. Siguiente/anterior radio de GTA: cambia de emisora.
]]

addEvent("rp:radio:open", true)
addEvent("rp:radio:ui:select", false)
addEvent("rp:radio:ui:volume", false)
addEvent("rp:radio:ui:close", false)

local PANEL_KEY = "r"
local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

local volume = 0.6          -- volumen local (0..1)
local sounds = {}           -- [vehicle] = { sound = elemento, station = id, own = bool }
local failedUntil = {}      -- [vehicle] = tick hasta el que no se reintenta

----------------------------------------------------------------
-- Reproduccion
----------------------------------------------------------------
local function stopSound(vehicle)
    local info = sounds[vehicle]
    if not info then return end
    if isElement(info.sound) then destroyElement(info.sound) end
    sounds[vehicle] = nil
end

local function startSound(vehicle, stationId, own)
    local st = RADIO_BY_ID[stationId]
    if not st then return end
    local sound
    if own then
        sound = playSound(st.url, false)
        if sound then setSoundVolume(sound, volume) end
    else
        local x, y, z = getElementPosition(vehicle)
        sound = playSound3D(st.url, x, y, z, false)
        if sound then
            attachElements(sound, vehicle)
            setSoundMinDistance(sound, 4)
            setSoundMaxDistance(sound, 45)
            setSoundVolume(sound, volume)
        end
    end
    if not sound then
        failedUntil[vehicle] = getTickCount() + 20000
        return
    end
    sounds[vehicle] = { sound = sound, station = stationId, own = own }
end

local function refreshVehicle(vehicle, mine)
    local stationId = getElementData(vehicle, RADIO_DATA_KEY)
    local info = sounds[vehicle]
    if not stationId or not RADIO_BY_ID[stationId] then
        stopSound(vehicle)
        return
    end
    if info and (info.station ~= stationId or info.own ~= mine or not isElement(info.sound)) then
        stopSound(vehicle)
        info = nil
    end
    if not info then
        if failedUntil[vehicle] and getTickCount() < failedUntil[vehicle] then return end
        startSound(vehicle, stationId, mine)
    end
end

local function reconcile()
    local mineVeh = getPedOccupiedVehicle(localPlayer)
    local seen = {}
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        seen[v] = true
        refreshVehicle(v, v == mineVeh)
    end
    if mineVeh and not seen[mineVeh] then
        seen[mineVeh] = true
        refreshVehicle(mineVeh, true)
    end
    for v in pairs(sounds) do
        if not seen[v] or not isElement(v) then stopSound(v) end
    end
    for v in pairs(failedUntil) do
        if not isElement(v) then failedUntil[v] = nil end
    end
end

local function applyVolume()
    for _, info in pairs(sounds) do
        if isElement(info.sound) then setSoundVolume(info.sound, volume) end
    end
end

----------------------------------------------------------------
-- Panel CEF
----------------------------------------------------------------
local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function closePanel()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function currentStation()
    local v = getPedOccupiedVehicle(localPlayer)
    return v and getElementData(v, RADIO_DATA_KEY) or nil
end

local function canControl()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v then return false end
    local seat = getPedOccupiedVehicleSeat(localPlayer)
    return seat == 0 or seat == 1
end

local function pushState()
    callJS(("RP.setCurrent(%s)"):format(tostring(currentStation() or "null")))
end

local function openPanel()
    if isElement(browserGui) then return end
    if not canControl() then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
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

    local list = {}
    for _, st in ipairs(RADIO_STATIONS) do
        list[#list + 1] = { id = st.id, name = st.name, genre = st.genre }
    end
    callJS(("RP.show(%s[0], %s, %s)"):format(toJSON(list, true), tostring(currentStation() or "null"), tostring(math.floor(volume * 100))))
end

addEventHandler("rp:radio:open", resourceRoot, openPanel)

addEventHandler("rp:radio:ui:select", root, function(id)
    if not canControl() then return end
    -- el CEF manda los argumentos como texto: "0" = apagar
    id = tonumber(id)
    if not id then return end
    if id == 0 then
        triggerServerEvent("rp:radio:set", resourceRoot, false)
    elseif RADIO_BY_ID[id] then
        triggerServerEvent("rp:radio:set", resourceRoot, id)
    end
end)

addEventHandler("rp:radio:ui:volume", root, function(v)
    v = tonumber(v)
    if not v then return end
    volume = math.max(0, math.min(1, v / 100))
    applyVolume()
end)

addEventHandler("rp:radio:ui:close", root, closePanel)
addEventHandler("onClientPlayerWasted", localPlayer, closePanel)
addEventHandler("onClientPlayerVehicleExit", localPlayer, closePanel)

----------------------------------------------------------------
-- Cambio rapido con las teclas de radio de GTA
----------------------------------------------------------------
local function cycle(dir)
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
    if not canControl() then return end
    local cur = currentStation()
    local idx = 0
    for i, st in ipairs(RADIO_STATIONS) do
        if st.id == cur then idx = i break end
    end
    -- 0 = apagada; el ciclo incluye "apagada" entre la ultima y la primera
    local total = #RADIO_STATIONS + 1
    local nextIdx = ((idx + dir) % total)
    if nextIdx == 0 then
        triggerServerEvent("rp:radio:set", resourceRoot, false)
    else
        triggerServerEvent("rp:radio:set", resourceRoot, RADIO_STATIONS[nextIdx].id)
    end
end

addEventHandler("onClientPlayerRadioSwitch", root, function()
    -- anula la radio nativa de GTA: la sustituye la de rp_radio
    cancelEvent()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(PANEL_KEY, "down", function()
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        if not getElementData(localPlayer, "rp:characterId") or getElementData(localPlayer, "rp:downed") then return end
        openPanel()
    end)
    bindKey("radio_next", "down", function() cycle(1) end)
    bindKey("radio_previous", "down", function() cycle(-1) end)
    setTimer(reconcile, 750, 0)
    setTimer(function()
        if getPedOccupiedVehicle(localPlayer) then setRadioChannel(0) end
    end, 1000, 0)
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key ~= RADIO_DATA_KEY or getElementType(source) ~= "vehicle" then return end
    failedUntil[source] = nil
    refreshVehicle(source, source == getPedOccupiedVehicle(localPlayer))
    if source == getPedOccupiedVehicle(localPlayer) then
        pushState()
        local id = getElementData(source, RADIO_DATA_KEY)
        local st = id and RADIO_BY_ID[id]
        exports.rp_notify:notify(st and ("Radio: " .. st.name) or "Radio apagada", "info")
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if getElementType(source) == "vehicle" then
        stopSound(source)
        failedUntil[source] = nil
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, closePanel)
