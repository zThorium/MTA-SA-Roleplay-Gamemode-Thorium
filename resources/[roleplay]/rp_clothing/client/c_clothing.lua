--[[
    rp_clothing / c_clothing.lua
    - Tecla E en los marcadores de la tienda (rp_markers): puerta = entrar, salida = salir,
      mostrador = abrir el estudio de compra (c_studio.lua).
    - Aviso "Pulsa E" con la tecla dibujada.
    - /accesorios abre el estudio solo con tus accesorios (lo pide el servidor).
]]

local screenW, screenH = guiGetScreenSize()
local near = { door = false, exit = false, counter = false }
local nearName = {}
local insideStore = false
local keyTex, font = nil, nil

addEvent("rp:cloth:near", true)
addEvent("rp:cloth:inside", true)
addEvent("rp:cloth:show", true)
addEvent("rp:cloth:bought", true)
addEvent("rp:toys:list", true)
addEvent("rp:toys:openUI", true)

-- Compatibilidad con quien preguntaba por la interfaz antigua
function isClothingUIOpen() return isStudioOpen() end
function isToyEditorActive() return isStudioOpen() end

local function canOpen()
    return getElementData(localPlayer, "rp:characterId") and not isPedDead(localPlayer)
        and not isCursorShowing() and not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
        and not isStudioOpen() and not isPedInVehicle(localPlayer) and not getElementData(localPlayer, "rp:downed")
end

----------------------------------------------------------------
-- Eventos del servidor
----------------------------------------------------------------
addEventHandler("rp:cloth:near", resourceRoot, function(kind, id, name)
    if near[kind] == nil then return end
    near[kind], nearName[kind] = id or false, name
end)

addEventHandler("rp:cloth:inside", resourceRoot, function(id)
    insideStore = id or false
    near.door, near.exit, near.counter = false, false, false
    if not id and getStudioMode() == "shop" then closeStudio() end
end)

addEventHandler("rp:cloth:show", resourceRoot, function(data)
    if type(data) == "table" then studioShowShop(data) end
end)

addEventHandler("rp:cloth:bought", resourceRoot, function(kind, toyKey) studioBought(kind, toyKey) end)

addEventHandler("rp:toys:openUI", resourceRoot, function()
    if canOpen() then studioWardrobe() end
end)

addEventHandler("rp:toys:list", resourceRoot, function(list, limits) studioSetOwned(list, limits) end)

----------------------------------------------------------------
-- Tecla E y aviso en pantalla
----------------------------------------------------------------
local function onKeyE()
    if not canOpen() then return end
    if near.exit and insideStore then
        triggerServerEvent("rp:cloth:exit", resourceRoot)
    elseif near.counter and insideStore then
        triggerServerEvent("rp:cloth:open", resourceRoot)
    elseif near.door then
        triggerServerEvent("rp:cloth:enter", resourceRoot, near.door)
    end
end

local function hint(text)
    local f = font or "default-bold"
    local w = dxGetTextWidth(text, 1, f) + 74
    local h = 46
    local x, y = (screenW - w) / 2, screenH - 150
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, h, tocolor(245, 165, 36, 255))
    if keyTex then dxDrawImage(x + 12, y + 6, 34, 34, keyTex) end
    dxDrawText(text, x + 54, y, x + w - 12, y + h, tocolor(242, 244, 248), 1, f, "left", "center")
end

addEventHandler("onClientRender", root, function()
    if isStudioOpen() or isPedInVehicle(localPlayer) then return end
    if near.exit and insideStore then
        hint("Salir de la tienda")
    elseif near.counter and insideStore then
        hint("Probarte ropa y accesorios")
    elseif near.door then
        hint("Entrar a " .. (nearName.door or "la tienda"))
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    keyTex = dxCreateTexture("images/keys/keyboard_e.png", "argb", true, "clamp")
    font = dxCreateFont("fonts/rubik_medium.ttf", 11) or "default-bold"
    bindKey("e", "down", onKeyE)
    triggerServerEvent("rp:cloth:clientReady", resourceRoot)
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then
        insideStore, near.door, near.exit, near.counter = false, false, false, false
    end
end)
