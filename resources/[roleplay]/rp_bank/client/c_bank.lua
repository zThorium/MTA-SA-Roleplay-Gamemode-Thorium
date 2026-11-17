--[[
    rp_bank / c_bank.lua
    Cajeros: ajusta el objeto al suelo, muestra el aviso "Pulsa E" y abre la
    interfaz del cajero (CEF). La app Banco del telefono vive en rp_phone.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local nearATM = false

addEvent("rp:bank:nearATM", true)
addEvent("rp:bank:data", true)
addEvent("rp:atm:ui:close", false)
addEvent("rp:atm:ui:action", false)

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
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/atm.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

addEventHandler("rp:bank:nearATM", resourceRoot, function(state)
    nearATM = state
    if not state then close() end
end)

addEventHandler("rp:bank:data", root, function(view, data)
    if view ~= "atm" then return end
    open()
    callJS(("RP.render(%s[0])"):format(toJSON(data, true)))
end)

addEventHandler("rp:atm:ui:close", root, close)

addEventHandler("rp:atm:ui:action", root, function(action, amount, target)
    amount = tonumber(amount)
    if not amount then return end
    if action == "deposit" then triggerServerEvent("rp:bank:deposit", resourceRoot, amount, "atm")
    elseif action == "withdraw" then triggerServerEvent("rp:bank:withdraw", resourceRoot, amount)
    elseif action == "transfer" and type(target) == "string" then triggerServerEvent("rp:bank:transfer", resourceRoot, target, amount, "atm") end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if not nearATM or isElement(browserGui) or getElementData(localPlayer, "rp:downed") then return end
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:bank:open", resourceRoot, "atm")
    end)
end)

addEventHandler("onClientRender", root, function()
    if not nearATM or isElement(browserGui) then return end
    local text = "Pulsa E para usar el cajero"
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(76, 211, 138, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)

-- Coloca los cajeros sobre el suelo cuando se cargan
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "object" or not getElementData(source, "rp:atm") then return end
    local x, y, z = getElementPosition(source)
    local ground = getGroundPosition(x, y, z + 2)
    if ground and ground ~= 0 and math.abs(ground - z) < 3 then
        setElementPosition(source, x, y, ground)
    end
end)

addEventHandler("onClientPlayerWasted", localPlayer, close)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)
