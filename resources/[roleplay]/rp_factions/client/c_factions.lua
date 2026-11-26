--[[
    rp_factions / c_factions.lua
    F3 abre o cierra el panel de la faccion (CEF). El servidor decide que datos
    llegan segun los permisos del rol; el HTML solo muestra lo que recibe.
    Con el panel abierto, F3 o Esc dentro del HTML lo cierran.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local lastData = nil

addEvent("rp:fac:data", true)
addEvent("rp:fac:closeUI", true)
addEvent("rp:fac:ui:close", false)
addEvent("rp:fac:ui:action", false)

local function isOpen() return isElement(browserGui) end

local function render()
    if isElement(browser) and ready and lastData then
        executeBrowserJavascript(browser, ("RP.render(%s[0])"):format(toJSON(lastData, true)))
    end
end

local function close(notifyServer)
    if not isOpen() then return end
    destroyElement(browserGui)
    browserGui, browser, ready, lastData = nil, nil, false, nil
    showCursor(false)
    guiSetInputEnabled(false)
    if notifyServer ~= false then triggerServerEvent("rp:fac:close", resourceRoot) end
end

local function open()
    if isOpen() then return end
    if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end
    if not getElementData(localPlayer, "rp:faction") then
        return exports.rp_notify:notify("No perteneces a ninguna faccion.", "warning")
    end

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
    triggerServerEvent("rp:fac:open", resourceRoot)
end

addEventHandler("rp:fac:data", resourceRoot, function(data)
    if not isOpen() then return end
    lastData = data
    render()
end)

addEventHandler("rp:fac:closeUI", resourceRoot, function() close(false) end)
addEventHandler("rp:fac:ui:close", root, function() close() end)

-- El HTML manda un JSON con los datos de la accion; se reenvia tal cual y el servidor valida
addEventHandler("rp:fac:ui:action", root, function(action, json)
    if type(action) ~= "string" or type(json) ~= "string" or #json > 4000 then return end
    local data = fromJSON(json)
    triggerServerEvent("rp:fac:action", resourceRoot, action, type(data) == "table" and data or {})
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(FACTIONS.KEY, "down", function()
        if isOpen() then close() elseif not getElementData(localPlayer, "rp:downed") then open() end
    end)
end)

-- Icono de la faccion en el HUD (rp_hud/c_iconbar.lua): mismas condiciones que F3
addEvent("rp:hud:action", false)
addEventHandler("rp:hud:action", localPlayer, function(id)
    if id ~= "faction" then return end
    if isOpen() then close() elseif not getElementData(localPlayer, "rp:downed") then open() end
end)

addEventHandler("onClientPlayerWasted", localPlayer, function() close() end)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, function() close() end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if (key == "rp:characterId" or key == "rp:faction") and not new then close(false) end
end)
addEventHandler("onClientResourceStop", resourceRoot, function() close(false) end)
