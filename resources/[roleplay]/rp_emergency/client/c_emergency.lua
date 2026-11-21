--[[
    rp_emergency / c_emergency.lua
    Menu CEF del 911, punto de aparicion de la ambulancia y movimiento de los
    paramedicos (c_walk.lua). El servidor decide todo; aqui solo se ejecuta lo que ordena.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

addEvent("rp:emergency:show", true)
addEvent("rp:emergency:spawnRequest", true)
addEvent("rp:emergency:drive", true)
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
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)   -- abatido (rp_injury)
addEventHandler("onClientResourceStop", resourceRoot, close)

----------------------------------------------------------------
-- Ambulancia
----------------------------------------------------------------
addEventHandler("rp:emergency:spawnRequest", resourceRoot, function(callId, avoidX, avoidY)
    local x, y, z, rot = pickSpawnPoint(tonumber(avoidX), tonumber(avoidY))
    triggerServerEvent("rp:emergency:spawn", resourceRoot, callId, x, y, z, rot)
end)

addEventHandler("rp:emergency:drive", resourceRoot, function(callId, vehicle, ped, mode, tx, ty, tz)
    if not isElement(vehicle) or not isElement(ped) then return end
    startAIDriver(callId, vehicle, ped, mode, tonumber(tx), tonumber(ty), tonumber(tz))
end)

-- Los paramedicos no mueren ni se les puede herir
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:emergency") then cancelEvent() end
end)

addEventHandler("rp:emergency:stop", resourceRoot, function(callId)
    if isAIDriving(callId) then stopAIDriver() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopAIDriver()
end)
