--[[
    rp_vehicles / c_interaction.lua
    Tecla M (/interactuar): muestra el cursor. Con el cursor, click derecho
    sobre un vehiculo abre el menu de opciones (CEF): maletero, matricula,
    multas, policia y admin. El panel de admin muestra el auto en 3D con
    object_preview (Ren712) si la tarjeta grafica lo soporta.

    Tambien maneja el panel del taller de tuning (vista previa local).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local cursorMode = false
local currentVehicle = nil
local tuneNear, tuneState = false, nil
local preview = { clone = nil, element = nil, angle = 0 }

addEvent("rp:veh:showMenu", true)
addEvent("rp:veh:showTrunk", true)
addEvent("rp:veh:showPlate", true)
addEvent("rp:veh:showAdmin", true)
addEvent("rp:veh:showPolice", true)
addEvent("rp:veh:showFines", true)
addEvent("rp:tune:near", true)
addEvent("rp:tune:show", true)
addEvent("rp:tune:done", true)

-- Eventos que dispara el HTML
addEvent("rp:veh:ui:close", false)
addEvent("rp:veh:ui:action", false)
addEvent("rp:veh:ui:preview", false)
addEvent("rp:veh:ui:tunePreview", false)
addEvent("rp:veh:ui:tuneBuy", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function js(fn, view, data)
    callJS(("RPV.%s(%q, %s[0])"):format(fn, view, toJSON(data or {}, true)))
end

----------------------------------------------------------------
-- Vista 3D (object_preview)
----------------------------------------------------------------
local function destroyPreview()
    if isElement(preview.element) then
        local res = getResourceFromName("object_preview")
        if res and getResourceState(res) == "running" then exports.object_preview:destroyObjectPreview(preview.element) end
    end
    if isElement(preview.clone) then destroyElement(preview.clone) end
    preview.clone, preview.element = nil, nil
end

local function previewSupported()
    local res = getResourceFromName("object_preview")
    if not res or getResourceState(res) ~= "running" then return false end
    local status = dxGetStatus()
    return (tonumber(status.VideoCardNumRenderTargets) or 1) > 1
end

local function createPreview(vehicle, x, y, w, h)
    destroyPreview()
    if not isElement(vehicle) then return end
    if not previewSupported() then return callJS("RPV.previewUnsupported()") end
    local cx, cy, cz = getCameraMatrix()
    local clone = createVehicle(getElementModel(vehicle), cx, cy, cz - 50)
    if not clone then return callJS("RPV.previewUnsupported()") end
    setElementDimension(clone, getElementDimension(localPlayer))
    setElementInterior(clone, getElementInterior(localPlayer))
    setElementCollisionsEnabled(clone, false)
    setElementFrozen(clone, true)
    setVehicleColor(clone, getVehicleColor(vehicle, true))
    setVehiclePaintjob(clone, getVehiclePaintjob(vehicle))
    setVehiclePlateText(clone, getVehiclePlateText(vehicle))
    for _, id in ipairs(getVehicleUpgrades(vehicle) or {}) do addVehicleUpgrade(clone, id) end
    preview.clone, preview.angle = clone, 200
    preview.element = exports.object_preview:createObjectPreview(clone, 0, 0, preview.angle, x, y, w, h, false, true, true)
    if not preview.element then destroyPreview() callJS("RPV.previewUnsupported()") end
end

addEventHandler("onClientRender", root, function()
    if not isElement(preview.element) then return end
    preview.angle = (preview.angle + 0.4) % 360
    exports.object_preview:setRotation(preview.element, -10, 0, preview.angle)
end)

----------------------------------------------------------------
-- Navegador
----------------------------------------------------------------
local restoreTuning

-- El navegador CEF se crea una sola vez (oculto) y se reutiliza: crear y
-- destruir navegadores seguido carga al driver de video.
local panelOpen = false

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local function closePanel()
    destroyPreview()
    if tuneState then
        restoreTuning()
        triggerServerEvent("rp:tune:close", resourceRoot)
        tuneState = nil
    end
    if panelOpen then
        panelOpen = false
        callJS("RPV.hide()")
        if isElement(browserGui) then guiSetVisible(browserGui, false) end
        triggerServerEvent("rp:veh:action", resourceRoot, currentVehicle, "trunk_close")
    end
    currentVehicle = nil
    guiSetInputEnabled(false)
    showCursor(cursorMode)
end

local function openPanel()
    if panelOpen then return end
    if getResourceFromName("rp_inventory") and getResourceState(getResourceFromName("rp_inventory")) == "running"
        and exports.rp_inventory:isInventoryOpen() then
        exports.rp_inventory:closeInventory()
    end
    createBrowser()
    panelOpen = true
    guiSetVisible(browserGui, true)
    guiBringToFront(browserGui)
    focusBrowser(browser)
    showCursor(true)
    guiSetInputEnabled(true)
end

local function show(view, vehicle, data)
    currentVehicle = vehicle
    openPanel()
    js("show", view, data)
end

addEventHandler("rp:veh:ui:close", root, closePanel)

addEventHandler("rp:veh:ui:action", root, function(action, a, b)
    if type(action) ~= "string" or not isElement(currentVehicle) then return end
    if action ~= "trunk_put" and action ~= "trunk_take" and action ~= "police_fine" then destroyPreview() end
    triggerServerEvent("rp:veh:action", resourceRoot, currentVehicle, action, a, b)
end)

addEventHandler("rp:veh:ui:preview", root, function(x, y, w, h)
    x, y, w, h = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
    if not (x and y and w and h) or w < 20 or h < 20 then return destroyPreview() end
    createPreview(currentVehicle, x, y, w, h)
end)

----------------------------------------------------------------
-- Respuestas del servidor
----------------------------------------------------------------
addEventHandler("rp:veh:showMenu", resourceRoot, function(vehicle, data)
    local cx, cy = getCursorPosition()
    data.x, data.y = math.floor((cx or 0.5) * screenW), math.floor((cy or 0.5) * screenH)
    show("menu", vehicle, data)
end)

for event, view in pairs({ ["rp:veh:showTrunk"] = "trunk", ["rp:veh:showPlate"] = "plate", ["rp:veh:showAdmin"] = "admin",
                           ["rp:veh:showPolice"] = "police", ["rp:veh:showFines"] = "fines" }) do
    addEventHandler(event, resourceRoot, function(vehicle, data)
        if not panelOpen then return end   -- respuesta tardia con el panel ya cerrado
        if view ~= "trunk" and view ~= "police" and view ~= "fines" then destroyPreview() end
        show(view, vehicle, data)
    end)
end

----------------------------------------------------------------
-- Modo cursor (M) y click derecho
----------------------------------------------------------------
local function toggleCursorMode()
    if panelOpen then return closePanel() end
    if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    if not cursorMode and isCursorShowing() then return end   -- otro panel abierto
    cursorMode = not cursorMode
    showCursor(cursorMode)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local k = VEHICLES.KEYS.interact
    addCommandHandler(k.command, toggleCursorMode)
    bindKey(k.key, "down", k.command)
end)

local function vehicleUnderCursor(clicked, wx, wy, wz)
    if isElement(clicked) and getElementType(clicked) == "vehicle" then return clicked end
    local cx, cy, cz = getCameraMatrix()
    local hit, _, _, _, element = processLineOfSight(cx, cy, cz, wx, wy, wz, false, true, false, false, false)
    if hit and isElement(element) and getElementType(element) == "vehicle" then return element end
end

addEventHandler("onClientClick", root, function(button, state, _, _, wx, wy, wz, clicked)
    if not cursorMode or panelOpen or button ~= "right" or state ~= "down" then return end
    local vehicle = vehicleUnderCursor(clicked, wx, wy, wz)
    if not vehicle then return end
    local px, py, pz = getElementPosition(localPlayer)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > VEHICLES.INTERACT_DISTANCE then
        return exports.rp_notify:notify("Acercate mas al vehiculo.", "warning")
    end
    triggerServerEvent("rp:veh:menu", resourceRoot, vehicle)
end)

-- Cerrar todo si muere o cambia de personaje
addEventHandler("onClientPlayerWasted", localPlayer, function()
    cursorMode = false
    closePanel()
end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then
        cursorMode = false
        closePanel()
    end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    destroyPreview()
    if cursorMode or panelOpen then showCursor(false) guiSetInputEnabled(false) end
end)

----------------------------------------------------------------
-- Taller de tuning
----------------------------------------------------------------
local tuneVehicle = nil

local function applyLocal(vehicle, state)
    if not isElement(vehicle) or type(state) ~= "table" then return end
    for _, id in ipairs(getVehicleUpgrades(vehicle) or {}) do removeVehicleUpgrade(vehicle, id) end
    for _, id in ipairs(state.u or {}) do addVehicleUpgrade(vehicle, id) end
    if state.c and #state.c >= 6 then setVehicleColor(vehicle, unpack(state.c, 1, 6)) end
    if state.h and #state.h >= 3 then setVehicleHeadLightColor(vehicle, unpack(state.h, 1, 3)) end
    if state.p then setVehiclePaintjob(vehicle, state.p) end
end

restoreTuning = function()
    if tuneState and isElement(tuneVehicle) then applyLocal(tuneVehicle, tuneState) end
end

addEventHandler("rp:tune:near", resourceRoot, function(shopName)
    tuneNear = shopName or false
end)

addEventHandler("onClientRender", root, function()
    if not tuneNear or panelOpen then return end
    local text = ("%s - pulsa E o escribe /tunear"):format(tuneNear)
    dxDrawText(text, 1, screenH * 0.78 + 1, screenW + 1, screenH * 0.78 + 1, tocolor(0, 0, 0, 200), 1.4, "default-bold", "center")
    dxDrawText(text, 0, screenH * 0.78, screenW, screenH * 0.78, tocolor(255, 190, 60, 255), 1.4, "default-bold", "center")
end)

local function requestTuning()
    if tuneNear and not panelOpen then triggerServerEvent("rp:tune:open", resourceRoot) end
end
addCommandHandler("tunear", requestTuning)
bindKey("e", "down", function()
    if tuneNear and not isChatBoxInputActive() and not isConsoleActive() then requestTuning() end
end)

addEventHandler("rp:tune:show", resourceRoot, function(vehicle, data)
    tuneVehicle = vehicle
    tuneState = data.state
    show("tuning", vehicle, data)
end)

-- El HTML manda el carrito (JSON) para verlo en el auto antes de pagar
local function parseCart(json)
    local cart = type(json) == "string" and fromJSON("[" .. json .. "]")
    return type(cart) == "table" and cart or nil
end

addEventHandler("rp:veh:ui:tunePreview", root, function(json)
    local cart = parseCart(json)
    if not cart or not tuneState or not isElement(tuneVehicle) then return end
    -- Estado original + cambios del carrito (full = lista completa de piezas deseadas)
    local state = { c = cart.colors or tuneState.c, h = cart.headlight or tuneState.h, p = cart.paintjob or tuneState.p,
        u = type(cart.full) == "table" and cart.full or tuneState.u }
    applyLocal(tuneVehicle, state)
end)

addEventHandler("rp:veh:ui:tuneBuy", root, function(json)
    local cart = parseCart(json)
    if cart then triggerServerEvent("rp:tune:buy", resourceRoot, cart) end
end)

-- Compra hecha o cancelada por el servidor: el servidor ya sincronizo el estado real
addEventHandler("rp:tune:done", resourceRoot, function(bought)
    if not bought then restoreTuning() end
    tuneState = nil
    tuneNear = false
    closePanel()
end)
