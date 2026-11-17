--[[
    rp_login / c_login.lua
    Muestra la interfaz CEF (html/index.html) y hace de puente entre el
    JavaScript del navegador y los eventos del servidor.

    JS  -> Lua : mta.triggerEvent("rp:ui:login" | "rp:ui:register", user, pass)
    Lua -> JS  : executeBrowserJavascript(browser, "RP.onResult(...)")
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser = nil, nil

-- Camara de fondo mientras el jugador esta en el login (vista de Los Santos)
local CAMERA = { 1468.8, -919.2, 100.2, 1468.4, -918.2, 99.9 }

addEvent("rp:ui:login", false)
addEvent("rp:ui:register", false)
addEvent("rp:auth:result", true)
addEvent("rp:auth:success", true)

-- Convierte un texto Lua en un literal de cadena JavaScript seguro
local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function callJS(code)
    if isElement(browser) then
        executeBrowserJavascript(browser, code)
    end
end

local function showLoginScreen()
    if isElement(browserGui) then return end

    showChat(false)
    setPlayerHudComponentVisible("all", false)
    fadeCamera(true, 1)
    setCameraMatrix(unpack(CAMERA))

    -- guiCreateBrowser gestiona raton y teclado automaticamente (local = true)
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)

    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)

    showCursor(true)
    guiSetInputEnabled(true)
end

-- Solo cierra la interfaz de login; la camara, el HUD y el chat los gestiona
-- rp_characters, que muestra la seleccion de personajes a continuacion.
local function hideLoginScreen()
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser = nil, nil
    showCursor(false)
end

----------------------------------------------------------------
-- Puente JS -> servidor (validacion basica; la real esta en el servidor)
----------------------------------------------------------------
local function forward(serverEvent)
    return function(username, password)
        if type(username) ~= "string" or type(password) ~= "string" then return end
        if #username > 24 or #password > 64 then return end
        triggerServerEvent(serverEvent, resourceRoot, username, password)
    end
end

addEventHandler("rp:ui:login", root, forward("rp:auth:login"))
addEventHandler("rp:ui:register", root, forward("rp:auth:register"))

----------------------------------------------------------------
-- Respuestas del servidor
----------------------------------------------------------------
addEventHandler("rp:auth:result", resourceRoot, function(ok, message, form)
    callJS(("RP.onResult(%s, %s, %s)"):format(ok and "true" or "false", jsString(message), jsString(form)))
end)

addEventHandler("rp:auth:success", resourceRoot, function(username)
    callJS(("RP.onSuccess(%s)"):format(jsString(username)))
    -- deja que la animacion de salida termine antes de cerrar el navegador
    setTimer(hideLoginScreen, 700, 1)
end)

addEventHandler("onClientResourceStart", resourceRoot, showLoginScreen)
addEventHandler("onClientResourceStop", resourceRoot, hideLoginScreen)
