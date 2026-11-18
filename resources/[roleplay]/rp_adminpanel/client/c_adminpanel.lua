--[[
    rp_adminpanel / c_adminpanel.lua
    Navegador CEF del panel de administracion. F10 o /adminpanel.
    El servidor decide si eres admin y envia el catalogo.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

addEvent("rp:adminpanel:show", true)
addEvent("rp:adminpanel:ui:close", false)
addEvent("rp:adminpanel:ui:copy", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
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

addEventHandler("rp:adminpanel:show", resourceRoot, function(catalog)
    if type(catalog) ~= "table" then return end
    open()
    callJS(("RP.show(%s[0])"):format(toJSON(catalog, true)))
end)

addEventHandler("rp:adminpanel:ui:copy", root, function(text)
    if type(text) ~= "string" or #text > 160 then return end
    setClipboard(text)
    exports.rp_notify:notify("Comando copiado: " .. text, "info")
end)

addEventHandler("rp:adminpanel:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("F10", "down", function()
        if isElement(browserGui) or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:adminpanel:open", resourceRoot)
    end)
end)
