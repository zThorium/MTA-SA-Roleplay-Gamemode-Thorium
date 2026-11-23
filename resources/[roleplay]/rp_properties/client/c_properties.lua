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
        if isElement(browserGui) or isCursorShowing() or isChatBoxInputActive() or getElementData(localPlayer, "rp:downed") then return end
        if not current then
            if getElementDimension(localPlayer) > 10000 then triggerServerEvent("rp:prop:exit", resourceRoot) end
            return
        end
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

-- Tras salir al exterior: espera a que cargue el suelo y busca una coordenada segura
-- (suelo firme, sin techo encima, sin paredes pegadas) alrededor de la puerta.
addEvent("rp:prop:groundFix", true)
local groundTimer

local function groundAt(x, y, z)
    local hit, _, _, gz = processLineOfSight(x, y, z + 3, x, y, z - 6, true, false, false, true, false, false, false, false, localPlayer)
    return hit and gz or nil
end

local function isSafe(x, y, z)
    local gz = groundAt(x, y, z)
    if not gz or math.abs(gz - z) > 2.5 then return nil end
    local head = gz + 1.0
    -- Sin techo / dentro de un edificio
    if processLineOfSight(x, y, head, x, y, head + 8, true, false, false, true, false, false, false, false, localPlayer) then return nil end
    -- Sin paredes pegadas
    for a = 0, 315, 45 do
        local r = math.rad(a)
        if processLineOfSight(x, y, head, x + math.cos(r) * 0.8, y + math.sin(r) * 0.8, head, true, false, false, true, false, false, false, false, localPlayer) then return nil end
    end
    return gz
end

addEventHandler("rp:prop:groundFix", resourceRoot, function(x, y, z)
    if isTimer(groundTimer) then killTimer(groundTimer) end
    setElementFrozen(localPlayer, true)
    local tries = 0
    groundTimer = setTimer(function()
        tries = tries + 1
        if groundAt(x, y, z) or tries >= 40 then
            killTimer(groundTimer)
            local px, py, pz
            for _, r in ipairs({ 0, 1.2, 2, 3, 4, 5.5, 7 }) do
                local step = r == 0 and 360 or 30
                for a = 0, 359, step do
                    local cx, cy = x + math.cos(math.rad(a)) * r, y + math.sin(math.rad(a)) * r
                    local gz = isSafe(cx, cy, z)
                    if gz then px, py, pz = cx, cy, gz break end
                end
                if px then break end
            end
            if px then setElementPosition(localPlayer, px, py, pz + 1.0) end
            setElementFrozen(localPlayer, false)
        end
    end, 100, 40)
end)
