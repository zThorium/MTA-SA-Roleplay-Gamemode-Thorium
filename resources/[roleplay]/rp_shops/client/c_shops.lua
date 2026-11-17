--[[
    rp_shops / c_shops.lua
    - Hace invulnerables a los NPC vendedores.
    - Cerca de una tienda, la tecla E abre el catalogo (CEF).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local nearShop, nearName = false, nil
local pendingJS = {}
local currentShop = nil

addEvent("rp:shop:near", true)
addEvent("rp:shop:show", true)
addEvent("rp:shop:money", true)
addEvent("rp:shop:ui:buy", false)
addEvent("rp:shop:ui:close", false)

local function callJS(code)
    if isElement(browser) and ready then
        executeBrowserJavascript(browser, code)
    else
        pendingJS[#pendingJS + 1] = code
    end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function close()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS, currentShop = nil, nil, false, {}, nil
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

----------------------------------------------------------------
addEventHandler("rp:shop:near", resourceRoot, function(shopId, name)
    nearShop, nearName = shopId, name
    if not shopId then close() end
end)

addEventHandler("rp:shop:show", resourceRoot, function(shopId, name, catalog, money)
    currentShop = shopId
    open()
    callJS(("RP.show(%s, %s[0], %d)"):format(jsString(name), toJSON(catalog or {}, true), tonumber(money) or 0))
end)

addEventHandler("rp:shop:money", resourceRoot, function(money)
    callJS(("RP.setMoney(%d)"):format(tonumber(money) or 0))
end)

addEventHandler("rp:shop:ui:buy", root, function(itemId, quantity)
    quantity = tonumber(quantity)
    if currentShop and type(itemId) == "string" and quantity then
        triggerServerEvent("rp:shop:buy", resourceRoot, currentShop, itemId, quantity)
    end
end)

addEventHandler("rp:shop:ui:close", root, close)

-- Tecla E junto al vendedor
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if not nearShop or isElement(browserGui) or getElementData(localPlayer, "rp:downed") then return end
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:shop:open", resourceRoot, nearShop)
    end)
end)

-- Indicador en pantalla mientras estas cerca
addEventHandler("onClientRender", root, function()
    if not nearShop or isElement(browserGui) then return end
    local text = "Pulsa E para comprar en " .. (nearName or "la tienda")
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)

-- NPC vendedores invulnerables
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:shopId") then cancelEvent() end
end)

addEventHandler("onClientPlayerWasted", localPlayer, close)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)
