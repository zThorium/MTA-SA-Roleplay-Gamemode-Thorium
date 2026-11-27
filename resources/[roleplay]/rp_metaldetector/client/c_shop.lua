--[[
    rp_metaldetector / c_shop.lua  (cliente)

    - Vendedor (ped con elementData rp:mdShop): aviso «Pulsa E · Hablar con el vendedor» cerca de él,
      invulnerable en el cliente; E pide al servidor abrir la tienda (él valida la distancia).
    - Panel CEF (html/): tienda, progreso y colección. El JS solo pide; el servidor revalida y cobra.
]]

local sw, sh = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local nearShop = false
local shopPed

addEvent("rp:metaldetector:panel", true)
addEvent("rp:metaldetector:bought", true)
addEvent("rp:metaldetector:ui:close", false)
addEvent("rp:metaldetector:ui:buy", false)

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
MDX.closePanel = close
function MDX.panelOpen() return isElement(browserGui) end

local function open()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
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

addEventHandler("rp:metaldetector:panel", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    open()
    callJS(("RP.show(%s[0])"):format(toJSON(data, true)))
end)

addEventHandler("rp:metaldetector:bought", resourceRoot, function(kind, index)
    callJS(("RP.bought(%s, %d)"):format(kind == "tier" and "\"tier\"" or "\"shovel\"", tonumber(index) or 0))
end)

addEventHandler("rp:metaldetector:ui:buy", root, function(kind, index)
    if kind ~= "tier" and kind ~= "shovel" then return end
    triggerServerEvent("rp:metaldetector:buy", resourceRoot, kind, tonumber(index) or 0)
end)

addEventHandler("rp:metaldetector:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)

----------------------------------------------------------------
-- Vendedor: cercanía cada 250 ms, aviso dx y E
----------------------------------------------------------------
local function findShopPed()
    if isElement(shopPed) then return shopPed end
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(ped, "rp:mdShop") then shopPed = ped return ped end
    end
end

setTimer(function()
    local ped = findShopPed()
    nearShop = false
    if not ped or getElementDimension(ped) ~= getElementDimension(localPlayer) or getElementInterior(ped) ~= getElementInterior(localPlayer) then return end
    local x, y, z = getElementPosition(localPlayer)
    local px, py, pz = getElementPosition(ped)
    nearShop = getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= METALDETECTOR.SHOP.radius
end, 250, 0)

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if exports.rp_injury:isLocalPlayerDowned() then return false end
    if exports.rp_hud:isHudSuppressed() then return false end
    return not isPedInVehicle(localPlayer)
end

addEventHandler("onClientRender", root, function()
    if not nearShop or MDX.panelOpen() or not canInteract() then return end
    local S = MDX.S
    local font = MDX.font("bold", 14)
    local label = "Hablar con el vendedor · detectores y palas"
    local w = dxGetTextWidth(label, 1, font) + 84 * S
    local x, y = (sw - w) / 2, sh - 200 * S
    MDX.panel(x, y, w, 48 * S)
    dxDrawRectangle(x + 10 * S, y + 45 * S, w - 20 * S, 3 * S, tocolor(245, 165, 36))
    local key = MDX.tex("images/keys/keyboard_e.png")
    if key then dxDrawImage(x + 12 * S, y + 6 * S, 36 * S, 36 * S, key) end
    MDX.text(label, x + 58 * S, y, x + w - 12 * S, y + 48 * S, tocolor(245, 246, 250), font, "left", "center")
end)

local function onE()
    if not nearShop or MDX.panelOpen() or not canInteract() then return end
    triggerServerEvent("rp:metaldetector:openShop", resourceRoot)
end

addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:mdShop") then cancelEvent() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function() bindKey("e", "down", onE) end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("e", "down", onE)
    close()
end)
