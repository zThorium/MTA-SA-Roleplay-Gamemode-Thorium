--[[
    rp_properties / c_properties.lua
    Modal de compra / visita (CEF), avisos "Pulsa E" y cuenta atras de la visita.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local current = nil          -- { info, inside, isOwner }
local previewEnd = nil

addEvent("rp:prop:near", true)
addEvent("rp:prop:previewTimer", true)
addEvent("rp:prop:ui:buy", false)
addEvent("rp:prop:ui:preview", false)
addEvent("rp:prop:ui:close", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function closeModal()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function openModal(info)
    if isElement(browserGui) or isCursorShowing() then return end
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
    callJS(("RP.show(%s[0])"):format(toJSON(info, true)))
end

addEventHandler("rp:prop:near", resourceRoot, function(info, inside, isOwner)
    if not info then
        current = nil
        closeModal()
        return
    end
    current = { info = info, inside = inside, isOwner = isOwner }
    if not inside and not info.owner and not previewEnd then
        openModal(info)
    end
end)

addEventHandler("rp:prop:previewTimer", resourceRoot, function(ms)
    previewEnd = ms and (getTickCount() + ms) or nil
end)

addEventHandler("rp:prop:ui:buy", root, function()
    triggerServerEvent("rp:prop:buy", resourceRoot)
    closeModal()
end)
addEventHandler("rp:prop:ui:preview", root, function()
    triggerServerEvent("rp:prop:preview", resourceRoot)
    closeModal()
end)
addEventHandler("rp:prop:ui:close", root, closeModal)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if not current or isElement(browserGui) or isCursorShowing() or isChatBoxInputActive() or getElementData(localPlayer, "rp:downed") then return end
        if current.inside then
            triggerServerEvent("rp:prop:exit", resourceRoot)
        elseif current.info.owner then
            triggerServerEvent("rp:prop:enter", resourceRoot)
        else
            openModal(current.info)
        end
    end)
end)

local function hint(text, r, g, b)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(r, g, b, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    if previewEnd then
        local left = math.max(0, math.ceil((previewEnd - getTickCount()) / 1000))
        local text = ("Visita: %d s"):format(left)
        dxDrawRectangle(screenW / 2 - 80, 30, 160, 40, tocolor(12, 14, 20, 220))
        dxDrawText(text, screenW / 2 - 80, 30, screenW / 2 + 80, 70, tocolor(245, 165, 36), 1.4, "default-bold", "center", "center")
    end
    if not current or isElement(browserGui) then return end
    if current.inside then
        hint("Pulsa E para salir", 245, 165, 36)
    elseif current.info.owner then
        local lock = current.info.locked and not current.isOwner and " (cerrada)" or ""
        hint(("%s - de %s%s. Pulsa E para entrar"):format(current.info.name, current.info.owner, lock), 200, 205, 215)
    else
        hint(("%s - $%s. Pulsa E para ver opciones"):format(current.info.name, current.info.price), 76, 211, 138)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, closeModal)

-- Abatido (rp_injury): se cierra la interfaz
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, closeModal)
