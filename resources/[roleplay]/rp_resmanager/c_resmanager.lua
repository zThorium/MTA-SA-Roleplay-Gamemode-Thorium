--[[
    rp_resmanager / c_resmanager.lua
    UI (CEF) del gestor de recursos. F10 o /recursos. El servidor valida todo:
    el cliente solo pide abrir y el servidor responde si eres super admin.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready, visible = nil, nil, false, false
local pending = nil

addEvent("rp:resmgr:list", true)
addEvent("rp:resmgr:toggle", true)
addEvent("rp:resmgr:ui:action", false)
addEvent("rp:resmgr:ui:close", false)
addEvent("rp:resmgr:ui:refresh", false)

local function push(list)
    if not (isElement(browser) and ready) then pending = list return end
    executeBrowserJavascript(browser, ("RM.render(%s[0])"):format(toJSON(list, true)))
end

local function close()
    if not visible then return end
    triggerServerEvent("rp:resmgr:open", resourceRoot, false)
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser, ready, visible, pending = nil, nil, false, false, nil
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if visible then return end
    visible = true
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        if pending then push(pending) pending = nil end
    end)
    showCursor(true)
    guiSetInputEnabled(true)
    triggerServerEvent("rp:resmgr:open", resourceRoot, true)
    triggerServerEvent("rp:resmgr:request", resourceRoot)
end

addEventHandler("rp:resmgr:toggle", resourceRoot, function()
    if visible then close() else open() end
end)

addEventHandler("rp:resmgr:list", resourceRoot, function(list)
    if visible then push(list) end
end)

addEventHandler("rp:resmgr:ui:action", root, function(action, name)
    triggerServerEvent("rp:resmgr:action", resourceRoot, tostring(action), tostring(name or ""))
end)
addEventHandler("rp:resmgr:ui:refresh", root, function()
    triggerServerEvent("rp:resmgr:action", resourceRoot, "refresh", "")
end)
addEventHandler("rp:resmgr:ui:close", root, close)

bindKey("F10", "down", function()
    if visible then close() return end
    triggerServerEvent("rp:resmgr:tryOpen", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if visible then showCursor(false) guiSetInputEnabled(false) end
end)
