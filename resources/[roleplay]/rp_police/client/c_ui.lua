--[[
    rp_police / c_ui.lua
    Panel CEF unico (MDT, cacheo, armeria, garaje, laboratorio y formularios).
    El servidor manda el modo y los datos; el HTML solo muestra y reenvia acciones,
    que el servidor vuelve a validar. Esc o la X lo cierran.
]]

local sw, sh = guiGetScreenSize()
local gui, browser, ready = nil, nil, false
local pending = {}

addEvent("rp:pol:ui:open", true)
addEvent("rp:pol:ui:update", true)
addEvent("rp:pol:ui:close", true)
addEvent("rp:pol:ui:cancel", false)      -- desde el HTML
addEvent("rp:pol:ui:action", false)      -- desde el HTML

local function isOpen() return isElement(gui) end

local function run(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pending[#pending + 1] = code end
end

local function close(tellServer)
    if not isOpen() then return end
    destroyElement(gui)
    gui, browser, ready, pending = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
    if tellServer ~= false then triggerServerEvent("rp:pol:uiClosed", resourceRoot) end
end

local function open()
    if isOpen() then return end
    if getResourceFromName("rp_inventory") and getResourceState(getResourceFromName("rp_inventory")) == "running"
        and exports.rp_inventory:isInventoryOpen() then
        exports.rp_inventory:closeInventory()
    end
    gui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
    browser = guiGetBrowser(gui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pending) do executeBrowserJavascript(source, code) end
        pending = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

addEventHandler("rp:pol:ui:open", resourceRoot, function(mode, data)
    if isPedDead(localPlayer) then return end
    open()
    run(("RP.open(%q, %s[0])"):format(mode, toJSON(data or {}, true)))
end)

addEventHandler("rp:pol:ui:update", resourceRoot, function(kind, data)
    if not isOpen() then return end
    run(("RP.update(%q, %s[0])"):format(kind, toJSON(data or {}, true)))
end)

addEventHandler("rp:pol:ui:close", resourceRoot, function() close(true) end)
addEventHandler("rp:pol:ui:cancel", root, function() close() end)

addEventHandler("rp:pol:ui:action", root, function(action, json)
    if type(action) ~= "string" or type(json) ~= "string" or #json > 3000 then return end
    local data = fromJSON(json)
    if type(data) ~= "table" then data = {} end
    triggerServerEvent("rp:pol:ui", resourceRoot, action, data)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function() close() end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then close(false) end
end)
addEventHandler("onClientResourceStop", resourceRoot, function() close(false) end)
