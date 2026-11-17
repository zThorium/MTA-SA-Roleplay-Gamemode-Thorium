--[[
    rp_inventory / c_inventory.lua
    Tecla I: abre/cierra el inventario (CEF). Mientras esta abierto, el propio
    HTML escucha I o Esc para cerrarlo (con el input de GUI activo los binds
    de MTA no se disparan).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local visible = false
local lastData = nil

addEvent("rp:inv:update", true)
addEvent("rp:inv:ui:close", false)
addEvent("rp:inv:ui:use", false)
addEvent("rp:inv:ui:drop", false)

-- El navegador CEF se crea UNA vez por personaje (oculto) y se reutiliza.
-- Antes se creaba y destruia en cada pulsacion de I (arranque de Chromium +
-- carga de HTML/CSS/JS + viaje al servidor), de ahi el retraso al abrir.
-- Ahora abrir = mostrar la GUI ya cargada, con los datos que el servidor
-- mantiene sincronizados en segundo plano (rp:inv:update).

local function render()
    if not (isElement(browser) and ready and lastData) then return end
    executeBrowserJavascript(browser, ("RP.render(%s[0], %s, %s)"):format(
        toJSON(lastData.items, true), tostring(lastData.weight), tostring(lastData.maxWeight)))
end

local function isOpen()
    return visible and isElement(browserGui)
end

local function destroyBrowser()
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser, ready, visible = nil, nil, false, false
end

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        render()
    end)
end

local function close()
    if not visible then return end
    visible = false
    if isElement(browserGui) then guiSetVisible(browserGui, false) end
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isOpen() then return end
    if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end

    if not isElement(browserGui) then createBrowser() end   -- por si aun no existia
    visible = true
    guiSetVisible(browserGui, true)
    guiBringToFront(browserGui)
    focusBrowser(browser)
    showCursor(true)
    guiSetInputEnabled(true)
    render()
    -- Solo pedimos datos si aun no llegaron (normalmente ya estan sincronizados)
    if not lastData then triggerServerEvent("rp:inv:request", resourceRoot) end
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
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key ~= "rp:characterId" then return end
    if new then
        createBrowser()
    else
        close()
        destroyBrowser()
        lastData = nil
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "rp:characterId") then
        createBrowser()
        triggerServerEvent("rp:inv:request", resourceRoot)
    end
    bindKey("i", "down", function()
        if isOpen() then close() elseif not getElementData(localPlayer, "rp:downed") then open() end
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    close()
    destroyBrowser()
end)

-- Export cliente: permite a otros recursos saber si el inventario esta abierto
function isInventoryOpen()
    return isOpen()
end

function closeInventory()
    close()
end
