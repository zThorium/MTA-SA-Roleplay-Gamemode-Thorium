--[[
    rp_inventory / c_inventory.lua
    Tecla I: abre/cierra el inventario (CEF). Mientras esta abierto, el propio
    HTML escucha I o Esc para cerrarlo (con el input de GUI activo los binds
    de MTA no se disparan).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local lastData = nil

addEvent("rp:inv:update", true)
addEvent("rp:inv:ui:close", false)
addEvent("rp:inv:ui:use", false)
addEvent("rp:inv:ui:drop", false)

local function render()
    if not (isElement(browser) and ready and lastData) then return end
    executeBrowserJavascript(browser, ("RP.render(%s[0], %s, %s)"):format(
        toJSON(lastData.items, true), tostring(lastData.weight), tostring(lastData.maxWeight)))
end

local function isOpen()
    return isElement(browserGui)
end

local function close()
    if not isOpen() then return end
    destroyElement(browserGui)
    browserGui, browser, ready = nil, nil, false
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isOpen() then return end
    if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end

    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        render()
    end)
    showCursor(true)
    guiSetInputEnabled(true)
    triggerServerEvent("rp:inv:request", resourceRoot)
end

addEventHandler("rp:inv:update", resourceRoot, function(items, weight, maxWeight)
    lastData = { items = items or {}, weight = weight or 0, maxWeight = maxWeight or 0 }
    render()
end)

addEventHandler("rp:inv:ui:close", root, close)

addEventHandler("rp:inv:ui:use", root, function(itemId)
    if type(itemId) == "string" then triggerServerEvent("rp:inv:use", resourceRoot, itemId) end
end)

addEventHandler("rp:inv:ui:drop", root, function(itemId, amount)
    amount = tonumber(amount)
    if type(itemId) == "string" and amount then triggerServerEvent("rp:inv:drop", resourceRoot, itemId, amount) end
end)

-- Cerrar si el personaje muere o sale
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then
        close()
        lastData = nil
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("i", "down", function()
        if isOpen() then close() else open() end
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, close)

-- Export cliente: permite a otros recursos saber si el inventario esta abierto
function isInventoryOpen()
    return isOpen()
end

function closeInventory()
    close()
end
