--[[
    rp_adminpanel / c_adminpanel.lua
    Navegador CEF del panel de administracion. F10 o /adminpanel.
    El servidor decide permisos y envia los datos; el cliente solo reenvia.

    Vista 3D: un ped real (no un render target) en una escena 40 m sobre el jugador, vestido con
    exports.rp_characters:applyPedLook (skin, ropa, cabeza custom, altura y tono). La camara
    se encuadra sola sobre el recuadro #stage del HTML, que es transparente.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

-- Escena: 40 m sobre el jugador. No alejar mas la camara: el juego descarga mapa y colision
-- alrededor del jugador y al volver caeria por el vacio.
local ANCHOR = { x = 0, y = 0, z = 0 }   -- se recalcula en cada escena
local scene = nil   -- { ped, rect = {x,y,w,h}, cx, cz, dist, angle }
local saved = nil   -- hora y clima del jugador, para restaurarlos al salir de la escena

addEvent("rp:adminpanel:show", true)
addEvent("rp:adminpanel:data", true)
addEvent("rp:adminpanel:ui:close", false)
addEvent("rp:adminpanel:ui:copy", false)
addEvent("rp:adminpanel:ui:req", false)
addEvent("rp:adminpanel:ui:preview", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function destroyScenePed()
    if scene and isElement(scene.ped) then
        exports.rp_characters:clearPedLook(scene.ped)
        destroyElement(scene.ped)
    end
end

local function stopScene()
    if not scene then return end
    destroyScenePed()
    scene = nil
    setCameraTarget(localPlayer)
    if saved then
        setTime(saved.h, saved.m); setWeather(saved.w)
        saved = nil
    end
end

local function close()
    stopScene()
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

addEventHandler("rp:adminpanel:show", resourceRoot, open)

-- toJSON(x) devuelve "[ x ]": de ahi el [0]
addEventHandler("rp:adminpanel:data", resourceRoot, function(kind, data)
    if type(kind) ~= "string" then return end
    callJS(("RP.on(%q, %s[0])"):format(kind, toJSON(data, true)))
end)

addEventHandler("rp:adminpanel:ui:req", root, function(kind, a, b, c)
    triggerServerEvent("rp:adminpanel:req", resourceRoot, tostring(kind), a, b, c)
end)

addEventHandler("rp:adminpanel:ui:copy", root, function(text)
    if type(text) ~= "string" or #text > 160 then return end
    setClipboard(text)
    exports.rp_notify:notify("Comando copiado: " .. text, "info")
end)

----------------------------------------------------------------
-- Vista 3D
----------------------------------------------------------------
-- (lookJson, skin, x, y, w, h): el recuadro llega en pixeles de pantalla. w < 10 = ocultar.
addEventHandler("rp:adminpanel:ui:preview", root, function(lookJson, skin, x, y, w, h)
    skin, x, y, w, h = tonumber(skin), tonumber(x), tonumber(y), tonumber(w), tonumber(h)
    if not (skin and x and y and w and h) or w < 10 or h < 10 then return stopScene() end

    destroyScenePed()   -- sin restaurar la camara: evita un parpadeo al cambiar de jugador
    scene = nil
    local ax, ay, az = getElementPosition(localPlayer)
    ANCHOR.x, ANCHOR.y, ANCHOR.z = ax, ay, az + 40
    local ped = createPed(skin, ANCHOR.x, ANCHOR.y, ANCHOR.z, 180)
    if not ped then return setCameraTarget(localPlayer) end
    setElementInterior(ped, getElementInterior(localPlayer))
    setElementDimension(ped, getElementDimension(localPlayer))
    setElementFrozen(ped, true)
    setElementCollisionsEnabled(ped, false)
    local look = type(lookJson) == "string" and lookJson ~= "" and fromJSON(lookJson) or nil
    if type(look) == "table" then exports.rp_characters:applyPedLook(ped, look) end
    scene = { ped = ped, rect = { x = x, y = y, w = w, h = h }, cx = ANCHOR.x, cz = ANCHOR.z + 0.1, dist = 3.6, angle = 180 }
    -- Mediodia y cielo despejado (solo en este cliente) para que el ped no salga oscuro
    if not saved then
        local h, m = getTime()
        saved = { h = h, m = m, w = getWeather() }
        setTime(12, 0); setWeather(0)
    end
end)

-- Cada frame: gira el ped y corrige la camara hasta que el cuerpo entero quede centrado en #stage.
-- Aproximacion: 1 m de ped = (altura_en_pixeles / 1.8) px; la camara mira hacia -Y (derecha = -X).
addEventHandler("onClientRender", root, function()
    if not scene then return end
    if not isElement(scene.ped) then scene = nil return end
    scene.angle = (scene.angle + 0.45) % 360
    setElementRotation(scene.ped, 0, 0, scene.angle)

    local px, py, pz = ANCHOR.x, ANCHOR.y, ANCHOR.z
    setCameraMatrix(scene.cx, py + scene.dist, scene.cz, scene.cx, py, scene.cz, 0, 70)

    local fx, fy = getScreenFromWorldPosition(px, py, pz - 0.95)   -- pies
    local hx, hy = getScreenFromWorldPosition(px, py, pz + 0.85)   -- cabeza
    if not (fx and hx) then return end
    local r = scene.rect
    local pixels = math.abs(fy - hy)
    if pixels < 1 then return end
    local perMeter = pixels / 1.8
    local targetH = r.h * 0.86
    local curX, curY = (fx + hx) / 2, (fy + hy) / 2

    -- desplazar la camara en paralelo; el ped se mueve al reves
    scene.cx = scene.cx + (r.x + r.w / 2 - curX) / perMeter * 0.35
    scene.cz = scene.cz + (r.y + r.h / 2 - curY) / perMeter * 0.35
    scene.dist = math.max(1.5, math.min(9, scene.dist * (1 + (pixels / targetH - 1) * 0.3)))
end)

addEventHandler("rp:adminpanel:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("F10", "down", function()
        if isElement(browserGui) or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:adminpanel:open", resourceRoot)
    end)
end)
