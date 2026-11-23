--[[
    rp_backpacks / c_backpacks.lua
    Tecla O o /mochila: panel CEF con el contenido de la mochila y el inventario.
    El navegador se crea al abrir y se destruye al cerrar. El servidor valida todos los movimientos.
]]

local screenW, screenH = guiGetScreenSize()
local gui, browser, ready, data = nil, nil, false, nil

addEvent("rp:bp:update", true)
addEvent("rp:bp:ui:close", false)
addEvent("rp:bp:ui:put", false)
addEvent("rp:bp:ui:take", false)
addEvent("rp:bp:ui:drop", false)

local function render()
    if isElement(browser) and ready and data then
        executeBrowserJavascript(browser, ("RP.render(%s[0])"):format(toJSON(data, true)))
    end
end

local function close()
    if isElement(gui) then destroyElement(gui) end
    gui, browser, ready = nil, nil, false
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isElement(gui) then return close() end
    if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end
    data = nil
    gui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(gui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function() ready = true render() end)
    focusBrowser(browser)
    showCursor(true)
    guiSetInputEnabled(true)
    triggerServerEvent("rp:bp:request", resourceRoot)
end

addEventHandler("rp:bp:update", resourceRoot, function(payload)
    if payload == false then return close() end   -- ya no hay mochila
    data = payload
    render()
end)

addEventHandler("rp:bp:ui:close", root, close)
addEventHandler("rp:bp:ui:put", root, function(itemId, amount)
    if type(itemId) == "string" and tonumber(amount) then triggerServerEvent("rp:bp:put", resourceRoot, itemId, tonumber(amount)) end
end)
addEventHandler("rp:bp:ui:take", root, function(itemId, amount)
    if type(itemId) == "string" and tonumber(amount) then triggerServerEvent("rp:bp:take", resourceRoot, itemId, tonumber(amount)) end
end)
addEventHandler("rp:bp:ui:drop", root, function() triggerServerEvent("rp:bp:drop", resourceRoot) end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("o", "down", function() open() end)
    addCommandHandler("mochila", open)
end)
addEventHandler("onClientResourceStop", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
