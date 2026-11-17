--[[
    rp_rides / c_rides.lua
    Interfaz de la app Vroom (CEF con forma de telefono, abajo a la derecha).

    El navegador se crea una vez y se oculta en lugar de destruirse, asi el
    mapa y el estado del viaje se conservan. Dos modos:
      - interactivo: con cursor (pedir viaje, elegir destino, calificar...)
      - pasivo: visible sin cursor mientras viajas (mapa con la ruta y el auto).
        La tecla M cambia entre los dos.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local visible, interactive = false, false
local lastState = nil
local driverMarker = nil

addEvent("rp:rides:state", true)
addEvent("rp:rides:offer", true)
addEvent("rp:rides:offerGone", true)
addEvent("rp:rides:showApp", true)
addEvent("rp:rides:aiSpawnRequest", true)
addEvent("rp:rides:aiDrive", true)
addEvent("rp:rides:driverRoute", true)
addEvent("rp:rides:openApp", false)   -- desde rp_phone (icono de la app)
for _, e in ipairs({ "ready", "close", "request", "cancel", "setDest", "duty", "accept", "driverCancel", "rate", "passive" }) do
    addEvent("rp:rides:ui:" .. e, false)
end

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end
local function json(v) return toJSON(v, true) .. "[0]" end

local function ensureBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    guiSetVisible(browserGui, false)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local function setInteractive(state)
    interactive = state
    showCursor(state)
    guiSetInputEnabled(state)
    callJS(("RP.setInteractive(%s)"):format(tostring(state)))
end

local function hide()
    if not visible then return end
    visible = false
    if isElement(browserGui) then guiSetVisible(browserGui, false) end
    if interactive then setInteractive(false) end
end

local function show(isInteractive)
    if not getElementData(localPlayer, "rp:characterId") then return end
    ensureBrowser()
    visible = true
    guiSetVisible(browserGui, true)
    if isInteractive ~= interactive then setInteractive(isInteractive) end
    triggerServerEvent("rp:rides:open", resourceRoot)
end

local function rideActive()
    local r = lastState and lastState.ride
    return r and (r.state == "riding" or r.state == "assigned" or r.state == "arrived")
end

----------------------------------------------------------------
-- Servidor -> app
----------------------------------------------------------------
addEventHandler("rp:rides:state", resourceRoot, function(state)
    lastState = state
    callJS(("RP.state(%s)"):format(json(state)))
    -- Sin viaje ni calificacion pendiente: si estaba en modo pasivo, se oculta
    if visible and not interactive and not state.ride and not state.rate and not state.driving then hide() end
end)

addEventHandler("rp:rides:offer", resourceRoot, function(info)
    callJS(("RP.offer(%s)"):format(json(info)))
    playSoundFrontEnd(11)
end)

addEventHandler("rp:rides:offerGone", resourceRoot, function(id)
    callJS(("RP.offerGone(%d)"):format(tonumber(id) or 0))
end)

addEventHandler("rp:rides:showApp", resourceRoot, function(screen)
    if screen == "toggle" then
        if visible then hide() else show(true) end
    elseif screen == "rate" or screen == "pick" then
        show(true)
        callJS(("RP.screen(%q)"):format(screen))
    elseif screen == "ride" then
        if not visible then show(false) end
    end
end)

addEventHandler("rp:rides:openApp", root, function()
    if not visible or not interactive then show(true) end
end)

-- El servidor pide un punto de la calle para que aparezca el auto IA
addEventHandler("rp:rides:aiSpawnRequest", resourceRoot, function(rideId)
    local x, y, z, rot = pickAISpawnPoint()
    triggerServerEvent("rp:rides:aiSpawn", resourceRoot, rideId, x, y, z, rot)
end)

-- Envia una ruta (lista de nodos) a la app para dibujarla; animate = mostrar la busqueda A*
local function sendRoute(route, animate, kind)
    if not route or #route < 2 then return callJS("RP.route(null)") end
    callJS(("RP.route(%s, %s, %q)"):format(json(route), tostring(animate), kind or "ride"))
end

addEventHandler("rp:rides:aiDrive", resourceRoot, function(vehicle, ped, mode, dx, dy)
    if not isElement(vehicle) or not isElement(ped) then return end
    local route = startAIDriver(vehicle, ped, mode, tonumber(dx), tonumber(dy))
    if mode == "ride" then
        if not visible then show(false) end
        sendRoute(route, true, "ride")
    elseif mode == "pickup" then
        sendRoute(route, false, "pickup")
    else
        callJS("RP.route(null)")
    end
end)

-- Conductor jugador: marca en el mundo y ruta en la app hasta el pasajero o el destino
addEventHandler("rp:rides:driverRoute", resourceRoot, function(target, isPickup)
    if isElement(driverMarker) then destroyElement(driverMarker) end
    driverMarker = nil
    if not target then return callJS("RP.route(null)") end
    local tx, ty = tonumber(target[1]), tonumber(target[2])
    if not (tx and ty) then return end
    local gz = getGroundPosition(tx, ty, 200)
    driverMarker = createMarker(tx, ty, (gz and gz ~= 0) and gz or 13, "checkpoint", 4, isPickup and 245 or 76, isPickup and 165 or 211, isPickup and 36 or 138, 160)
    local x, y = getElementPosition(localPlayer)
    local route = loadRoadGraph() and findRoadRoute(nearestRoadNode(x, y), nearestRoadNode(tx, ty))
    sendRoute(route, true, isPickup and "pickup" or "ride")
end)

----------------------------------------------------------------
-- App -> servidor
----------------------------------------------------------------
addEventHandler("rp:rides:ui:ready", root, function()
    local nodes, links, lanes = getRoadGraphData()
    if nodes then
        callJS(("RP.graph(%s, %s, %s)"):format(json(nodes), json(links), json(lanes)))
    else
        callJS("RP.graph(null)")
    end
    if lastState then callJS(("RP.state(%s)"):format(json(lastState))) end
end)

addEventHandler("rp:rides:ui:close", root, function()
    -- Con un viaje en curso, cerrar deja la app en modo pasivo (mapa visible)
    if rideActive() then setInteractive(false) else hide() end
end)
addEventHandler("rp:rides:ui:passive", root, function() if visible then setInteractive(false) end end)

addEventHandler("rp:rides:ui:request", root, function(dx, dy)
    triggerServerEvent("rp:rides:request", resourceRoot, tonumber(dx), tonumber(dy))
end)
addEventHandler("rp:rides:ui:cancel", root, function() triggerServerEvent("rp:rides:cancel", resourceRoot) end)
addEventHandler("rp:rides:ui:setDest", root, function(dx, dy)
    triggerServerEvent("rp:rides:setDest", resourceRoot, tonumber(dx), tonumber(dy))
end)
addEventHandler("rp:rides:ui:duty", root, function(state) triggerServerEvent("rp:rides:duty", resourceRoot, state == "1") end)
addEventHandler("rp:rides:ui:accept", root, function(id) triggerServerEvent("rp:rides:accept", resourceRoot, tonumber(id)) end)
addEventHandler("rp:rides:ui:driverCancel", root, function() triggerServerEvent("rp:rides:driverCancel", resourceRoot) end)
addEventHandler("rp:rides:ui:rate", root, function(stars, tip)
    triggerServerEvent("rp:rides:rate", resourceRoot, tonumber(stars), tonumber(tip) or 0)
end)

----------------------------------------------------------------
-- Posiciones en el mapa (2 veces por segundo mientras se ve)
----------------------------------------------------------------
setTimer(function()
    if not visible or not ready then return end
    local x, y = getElementPosition(localPlayer)
    local _, _, rot = getElementRotation(getPedOccupiedVehicle(localPlayer) or localPlayer)
    local cx, cy, remaining, mode = getAIDriverProgress()
    callJS(("RP.positions(%.1f, %.1f, %.0f, %s)"):format(x, y, rot,
        cx and ("[%.1f, %.1f, %.0f, %q]"):format(cx, cy, remaining or 0, mode or "") or "null"))
end, 500, 0)

----------------------------------------------------------------
-- Teclas
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("m", "down", function()
        if not visible or isChatBoxInputActive() or isConsoleActive() then return end
        if not interactive and isCursorShowing() then return end   -- otra interfaz tiene el cursor
        setInteractive(not interactive)
    end)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if interactive then setInteractive(false) end
end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then
        hide()
        stopAIDriver()
        lastState = nil
    end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if interactive then showCursor(false) guiSetInputEnabled(false) end
end)
