--[[
    rp_clothing / c_clothing.lua
    - Tecla E: en la puerta entra, en la salida de dentro sale y en el resto de
      la tienda abre el probador.
    - Interfaz CEF (html/index.html) en dos modos: "shop" (probador + accesorios)
      y "wardrobe" (/accesorios: poner, quitar, editar y tirar accesorios).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local mode = nil            -- "shop" | "wardrobe" mientras la interfaz esta abierta
local near = { door = false, exit = false }
local nearName = { door = nil, exit = nil }
local insideStore, insideName = false, nil

addEvent("rp:cloth:near", true)
addEvent("rp:cloth:inside", true)
addEvent("rp:cloth:show", true)
addEvent("rp:toys:list", true)
addEvent("rp:toys:openUI", true)
addEvent("rp:cloth:ui:close", false)
addEvent("rp:cloth:ui:try", false)
addEvent("rp:cloth:ui:buy", false)
addEvent("rp:cloth:ui:buyToy", false)
addEvent("rp:cloth:ui:wear", false)
addEvent("rp:cloth:ui:delete", false)
addEvent("rp:cloth:ui:edit", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

function isClothingUIOpen() return isElement(browserGui) end

function closeClothingUI()
    if not isElement(browserGui) then return end
    if mode == "shop" then triggerServerEvent("rp:cloth:close", resourceRoot) end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS, mode = nil, nil, false, {}, nil
    showCursor(false)
    guiSetInputEnabled(false)
end

local function openUI(newMode)
    if isElement(browserGui) then
        mode = newMode
        return
    end
    mode = newMode
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

local function canOpen()
    return getElementData(localPlayer, "rp:characterId") and not isPedDead(localPlayer)
        and not isCursorShowing() and not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
        and not isToyEditorActive()
end

----------------------------------------------------------------
-- Eventos del servidor
----------------------------------------------------------------
addEventHandler("rp:cloth:near", resourceRoot, function(kind, id, name)
    near[kind], nearName[kind] = id or false, name
end)

addEventHandler("rp:cloth:inside", resourceRoot, function(id, name)
    insideStore, insideName = id or false, name
    near.door, near.exit = false, false
    if not id and mode == "shop" then closeClothingUI() end
end)

addEventHandler("rp:cloth:show", resourceRoot, function(data)
    openUI("shop")
    callJS(("RP.show(%s[0])"):format(toJSON(data, true)))
end)

addEventHandler("rp:toys:openUI", resourceRoot, function()
    if isElement(browserGui) or not canOpen() then return end
    openUI("wardrobe")
    callJS("RP.wardrobeMode()")
    triggerServerEvent("rp:toys:open", resourceRoot)
end)

addEventHandler("rp:toys:list", resourceRoot, function(list, limits)
    if not isElement(browserGui) then return end
    callJS(("RP.setOwned(%s[0], %s[0])"):format(toJSON(list or {}, true), toJSON(limits or {}, true)))
end)

----------------------------------------------------------------
-- Eventos de la interfaz (CEF -> Lua -> servidor)
----------------------------------------------------------------
addEventHandler("rp:cloth:ui:close", root, closeClothingUI)

addEventHandler("rp:cloth:ui:try", root, function(slot, index)
    if mode == "shop" and type(slot) == "string" then triggerServerEvent("rp:cloth:try", resourceRoot, slot, tonumber(index)) end
end)

addEventHandler("rp:cloth:ui:buy", root, function(slot, index)
    if mode == "shop" and type(slot) == "string" then triggerServerEvent("rp:cloth:buy", resourceRoot, slot, tonumber(index)) end
end)

addEventHandler("rp:cloth:ui:buyToy", root, function(key)
    if mode == "shop" and type(key) == "string" then triggerServerEvent("rp:cloth:buyToy", resourceRoot, key) end
end)

addEventHandler("rp:cloth:ui:wear", root, function(id, state)
    triggerServerEvent("rp:toys:wear", resourceRoot, tonumber(id), state == "1" or state == true)
end)

addEventHandler("rp:cloth:ui:delete", root, function(id)
    triggerServerEvent("rp:toys:delete", resourceRoot, tonumber(id))
end)

addEventHandler("rp:cloth:ui:edit", root, function(id)
    closeClothingUI()
    triggerServerEvent("rp:toys:edit", resourceRoot, tonumber(id))
end)

----------------------------------------------------------------
-- Tecla E e indicador en pantalla
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if isElement(browserGui) or not canOpen() or isPedInVehicle(localPlayer) then return end
        if near.exit and insideStore then
            triggerServerEvent("rp:cloth:exit", resourceRoot)
        elseif near.door then
            triggerServerEvent("rp:cloth:enter", resourceRoot, near.door)
        elseif insideStore then
            triggerServerEvent("rp:cloth:open", resourceRoot)
        end
    end)
end)

local function hint(text)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    if isElement(browserGui) or isToyEditorActive() then return end
    if near.exit and insideStore then
        hint("Pulsa E para salir de " .. (insideName or "la tienda"))
    elseif near.door then
        hint("Pulsa E para entrar a " .. (nearName.door or "la tienda"))
    elseif insideStore then
        hint("Pulsa E para abrir el probador")
    end
end)

addEventHandler("onClientPlayerWasted", localPlayer, closeClothingUI)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if isElement(browserGui) then destroyElement(browserGui); showCursor(false); guiSetInputEnabled(false) end
end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then
        closeClothingUI()
        insideStore, near.door, near.exit = false, false, false
    end
end)
