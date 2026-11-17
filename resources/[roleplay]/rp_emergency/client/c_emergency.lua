--[[
    rp_emergency / c_emergency.lua
    Menu CEF del 911, punto de aparicion de la ambulancia y movimiento de los
    paramedicos. El servidor decide todo; aqui solo se ejecuta lo que ordena.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

addEvent("rp:emergency:show", true)
addEvent("rp:emergency:spawnRequest", true)
addEvent("rp:emergency:drive", true)
addEvent("rp:emergency:walk", true)
addEvent("rp:emergency:stop", true)
addEvent("rp:emergency:ui:call", false)
addEvent("rp:emergency:ui:close", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function close()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isElement(browserGui) then return end
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
end

addEventHandler("rp:emergency:show", resourceRoot, function(services, busy)
    if type(services) ~= "table" then return end
    open()
    callJS(("RP.show(%s[0], %s)"):format(toJSON(services, true), tostring(busy == true)))
end)

addEventHandler("rp:emergency:ui:call", root, function(id)
    if type(id) ~= "string" then return end
    triggerServerEvent("rp:emergency:call", resourceRoot, id)
    close()
end)

addEventHandler("rp:emergency:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)

----------------------------------------------------------------
-- Ambulancia
----------------------------------------------------------------
addEventHandler("rp:emergency:spawnRequest", resourceRoot, function(callId)
    local x, y, z, rot = pickSpawnPoint()
    triggerServerEvent("rp:emergency:spawn", resourceRoot, callId, x, y, z, rot)
end)

addEventHandler("rp:emergency:drive", resourceRoot, function(callId, vehicle, ped, mode, tx, ty)
    if not isElement(vehicle) or not isElement(ped) then return end
    startAIDriver(callId, vehicle, ped, mode, tonumber(tx), tonumber(ty))
end)

-- Los paramedicos no mueren ni se les puede herir
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:emergency") then cancelEvent() end
end)

----------------------------------------------------------------
-- Caminar de los paramedicos (el servidor corrige si no llegan)
----------------------------------------------------------------
local walking = nil   -- { callId, token, list, started, timer }

local function stopWalking(report)
    if not walking then return end
    local w = walking
    walking = nil
    if isTimer(w.timer) then killTimer(w.timer) end
    for _, o in ipairs(w.list) do
        if isElement(o[1]) then
            for _, k in ipairs({ "forward", "sprint", "walk" }) do setPedControlState(o[1], k, false) end
        end
    end
    if report then triggerServerEvent("rp:emergency:walked", resourceRoot, w.callId, w.token) end
end

local function walkTick()
    if not walking then return end
    local pending = 0
    for _, o in ipairs(walking.list) do
        local ped, tx, ty = o[1], o[2], o[3]
        if isElement(ped) and isElementStreamedIn(ped) then
            local x, y = getElementPosition(ped)
            local d = getDistanceBetweenPoints2D(x, y, tx, ty)
            if d > EMERGENCY.WALK_ARRIVE_DIST then
                pending = pending + 1
                setElementRotation(ped, 0, 0, -math.deg(math.atan2(tx - x, ty - y)))
                setPedControlState(ped, "forward", true)
                setPedControlState(ped, "sprint", d > 8 and not getPedAnimation(ped))
            else
                setPedControlState(ped, "forward", false)
                setPedControlState(ped, "sprint", false)
            end
        end
    end
    if pending == 0 or getTickCount() - walking.started > EMERGENCY.WALK_TIMEOUT * 1000 then stopWalking(true) end
end

addEventHandler("rp:emergency:walk", resourceRoot, function(callId, token, list)
    if type(list) ~= "table" then return end
    stopWalking(false)
    walking = { callId = callId, token = token, list = list, started = getTickCount() }
    walking.timer = setTimer(walkTick, 100, 0)
end)

addEventHandler("rp:emergency:stop", resourceRoot, function(callId)
    if isAIDriving(callId) then stopAIDriver() end
    if walking and walking.callId == callId then stopWalking(false) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopAIDriver()
    stopWalking(false)
end)
