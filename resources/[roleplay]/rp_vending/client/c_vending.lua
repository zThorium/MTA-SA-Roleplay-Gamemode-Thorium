--[[
    rp_vending / c_vending.lua  (cliente)

    Aviso "Pulsa E" junto a una maquina y la maquina dibujada en HTML (html/vending.*): vitrina
    con codigos, teclado, datafono (mismo minijuego de tarjeta que la bencinera de rp_vehicles)
    y caida del producto a la bandeja. El cliente solo reenvia
    lo que elige el jugador; el servidor decide producto, precio y cobro.
]]

addEvent("rp:vending:near", true)
addEvent("rp:vending:menu", true)
addEvent("rp:vending:pos", true)
addEvent("rp:vending:payResult", true)
addEvent("rp:vending:close", true)
addEvent("rp:vending:ui:choose", false)
addEvent("rp:vending:ui:pay", false)
addEvent("rp:vending:ui:cancel", false)
addEvent("rp:vending:ui:back", false)
addEvent("rp:vending:ui:sound", false)

local W, H = guiGetScreenSize()
local nearKind = nil      -- "drink" | "food" | nil
local open = false        -- menu o datafono abiertos

----------------------------------------------------------------
-- Navegador (uno solo, se crea la primera vez y luego se muestra/oculta)
----------------------------------------------------------------
local browserGui, browser, ready, pending = nil, nil, false, {}

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pending[#pending + 1] = code end
end

local function json(data) return toJSON(data, true):sub(2, -2) end

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, W, H, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/vending.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pending) do executeBrowserJavascript(source, code) end
        pending = {}
    end)
end

local function showUI(visible)
    open = visible
    if not isElement(browserGui) then return end
    guiSetVisible(browserGui, visible)
    showCursor(visible)
    toggleAllControls(not visible, true, false)
    if visible then
        guiBringToFront(browserGui)
        focusBrowser(browser)
    else
        focusBrowser(nil)
    end
end

----------------------------------------------------------------
-- Sonidos del datafono (copiados de rp_vehicles: sounds/pos_*.wav)
----------------------------------------------------------------
local SOUNDS = { beep = "sounds/pos_beep.wav", swipe = "sounds/pos_swipe.wav", print = "sounds/pos_print.wav",
    error = "sounds/pos_error.wav", ok = "sounds/pos_ok.wav" }

local function play(name)
    local path = SOUNDS[name]
    if not path then return end
    local snd = playSound(path)
    if snd then setSoundVolume(snd, name == "print" and 0.9 or 0.6) end
end

addEventHandler("rp:vending:ui:sound", root, function(name) play(name) end)

----------------------------------------------------------------
-- Aviso y tecla E
----------------------------------------------------------------
addEventHandler("rp:vending:near", resourceRoot, function(kind)
    nearKind = kind or nil
end)

local function canInteract()
    if open or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if exports.rp_injury:isLocalPlayerDowned() then return false end
    if exports.rp_hud:isHudSuppressed() then return false end
    return true
end

addEventHandler("onClientRender", root, function()
    if not nearKind or not canInteract() then return end
    local t = VENDING.TYPES[nearKind]
    if not t then return end
    local text = ("Pulsa E para usar la %s"):format(t.name)
    dxDrawText(text, 1, 1, W + 1, H * 0.85 + 1, tocolor(0, 0, 0, 200), 1.2, "default-bold", "center", "bottom")
    dxDrawText(text, 0, 0, W, H * 0.85, tocolor(255, 255, 255, 235), 1.2, "default-bold", "center", "bottom")
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        -- E la usan muchos recursos: fuera de una maquina no hace nada
        if not nearKind or not canInteract() then return end
        triggerServerEvent("rp:vending:open", resourceRoot)
    end)
end)

----------------------------------------------------------------
-- Flujo: menu -> datafono -> resultado
----------------------------------------------------------------
addEventHandler("rp:vending:menu", resourceRoot, function(data)
    createBrowser()
    callJS(("RPV.menu(%s)"):format(json(data)))
    showUI(true)
end)

-- Codigo de la espiral marcado en el teclado de la maquina (11, 12, 13, 21...)
addEventHandler("rp:vending:ui:choose", root, function(code)
    if not open then return end
    triggerServerEvent("rp:vending:choose", resourceRoot, tonumber(code))
end)

-- "Cancelar" en el datafono: se vuelve a la maquina
addEventHandler("rp:vending:ui:back", root, function()
    if open then triggerServerEvent("rp:vending:back", resourceRoot) end
end)

addEventHandler("rp:vending:pos", resourceRoot, function(data)
    if not open then return end
    callJS(("RPV.pos(%s)"):format(json(data)))
end)

addEventHandler("rp:vending:ui:pay", root, function(method, owner, pin)
    if not open then return end
    triggerServerEvent("rp:vending:pay", resourceRoot, method == "cash" and "cash" or "card", tonumber(owner), tostring(pin or ""))
end)

addEventHandler("rp:vending:payResult", resourceRoot, function(ok, text, cash)
    play(ok and "print" or "error")
    callJS(("RPV.result(%s, %q, %s)"):format(ok and "true" or "false", tostring(text or ""), cash and "true" or "false"))
end)

addEventHandler("rp:vending:ui:cancel", root, function()
    if open then triggerServerEvent("rp:vending:cancel", resourceRoot) end
end)

local function close()
    if not open then return end
    callJS("RPV.hide()")
    showUI(false)
end

addEventHandler("rp:vending:close", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if open then
        showCursor(false)
        toggleAllControls(true, true, false)
    end
end)
