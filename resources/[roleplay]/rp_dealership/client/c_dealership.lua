--[[
    rp_dealership / c_dealership.lua
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local nearEntry = nil

addEvent("rp:dealer:near", true)
addEvent("rp:dealer:show", true)
addEvent("rp:dealer:ui:buy", false)
addEvent("rp:dealer:ui:close", false)

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
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

addEventHandler("rp:dealer:near", resourceRoot, function(entry)
    nearEntry = entry or nil
    if not entry then close() end
end)

addEventHandler("rp:dealer:show", resourceRoot, function(data)
    open()
    callJS(("RP.show(%s[0])"):format(toJSON(data, true)))
end)

addEventHandler("rp:dealer:ui:buy", root, function(spot, color)
    triggerServerEvent("rp:dealer:buy", resourceRoot, tonumber(spot), tonumber(color))
    close()
end)
addEventHandler("rp:dealer:ui:close", root, close)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if not nearEntry or isElement(browserGui) or isCursorShowing() or isChatBoxInputActive() then return end
        triggerServerEvent("rp:dealer:open", resourceRoot)
    end)
end)

addEventHandler("onClientRender", root, function()
    if not nearEntry or isElement(browserGui) then return end
    local text = ("%s - $%s. Pulsa E para ver"):format(nearEntry.name, nearEntry.price)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(70, 150, 255, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)

-- Autos en exhibicion: sin danos ni colisiones raras al empujarlos
addEventHandler("onClientVehicleDamage", root, function()
    if getElementData(source, "rp:dealer") then cancelEvent() end
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
