--[[
    rp_agency / c_ui.lua
    Navegador CEF compartido por el dispensador, el tramite en el mostrador y la
    tarjeta del DNI. Se crea al abrir una vista y se destruye al cerrarla.

    Globales para el resto de scripts de cliente del recurso:
        uiOpen(cursor)    crea el navegador (cursor = true muestra el raton)
        uiClose()         lo destruye
        uiCall(code)      ejecuta JS (encola hasta que cargue)
        uiIsOpen()
        uiCursor(bool)    muestra/oculta el cursor sin cerrar
        jsString(s)       string escapado para JS
        jsJSON(t)         tabla Lua como literal JS
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

function jsJSON(t)
    -- toJSON envuelve en [ ]; [0] saca el valor
    return toJSON(t or {}, true):gsub("<", "\\u003c") .. "[0]"
end

function uiCall(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

function uiIsOpen()
    return isElement(browserGui)
end

function uiCursor(state)
    showCursor(state)
    guiSetInputEnabled(state)
end

function uiOpen(cursor)
    if isElement(browserGui) then
        if cursor ~= nil then uiCursor(cursor) end
        return
    end
    if exports.rp_inventory and getResourceFromName("rp_inventory") then
        pcall(function() if exports.rp_inventory:isInventoryOpen() then exports.rp_inventory:closeInventory() end end)
    end
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
    uiCursor(cursor ~= false)
end

function uiClose()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    uiCursor(false)
end

addEventHandler("onClientResourceStop", resourceRoot, uiClose)
