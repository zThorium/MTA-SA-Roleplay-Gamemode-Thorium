--[[
    rp_shootingrange / c_main.lua  (cliente)
    E en el mostrador de la armeria abre el menu (CEF). El navegador es de pantalla completa y
    transparente: ventana de menu/resultados con cursor y, en pleno entrenamiento, solo el HUD de la
    esquina (sin cursor). El cliente solo pide y dibuja; el servidor decide todo.
]]
local sw, sh = guiGetScreenSize()
local browserGui, browser, ready, pendingJS = nil, nil, false, {}
local inside, training, nearDesk = false, false, false

addEvent("rp:range:menu", true)
addEvent("rp:range:start", true)
addEvent("rp:range:round", true)
addEvent("rp:range:hit", true)
addEvent("rp:range:hud", true)
addEvent("rp:range:results", true)
addEvent("rp:range:close", true)
addEvent("rp:range:ui:train", false)
addEvent("rp:range:ui:again", false)
addEvent("rp:range:ui:close", false)

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function ensureBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
    browser = guiGetBrowser(browserGui)
    ready, pendingJS = false, {}
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local function destroyUI()
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function interactiveUI(on)
    showCursor(on)
    guiSetInputEnabled(on)
end

local function json(t) return toJSON(t, true) .. "[0]" end

----------------------------------------------------------------
-- Servidor -> cliente
----------------------------------------------------------------
addEventHandler("rp:range:menu", resourceRoot, function(data)
    inside, training = data.inside, false
    ensureBrowser()
    interactiveUI(true)
    callJS(("RP.menu(%s, %s)"):format(json(data), json(RANGE.UI)))
end)

addEventHandler("rp:range:start", resourceRoot, function(info)
    -- La sesion solo empieza dentro del campo: sin esto "Salir" en los resultados solo cerraba la
    -- ventana (inside seguia en false desde el menu del mostrador) y el jugador quedaba dentro.
    inside, training = true, true
    interactiveUI(false)
    callJS(("RP.start(%s)"):format(json(info)))
end)

addEventHandler("rp:range:round", resourceRoot, function(index, total, kind, targets, delayMs, timeMs)
    rangeTargetsStart(targets, delayMs)
    callJS(("RP.round(%d, %d, %s, %d, %d)"):format(index, total, jsString(kind), delayMs, timeMs))
end)

addEventHandler("rp:range:hit", resourceRoot, function(id, zoneKey, zoneName, points, rearmMs)
    rangeTargetsHit(id, rearmMs)
    playSoundFrontEnd(zoneKey == "head" and 40 or 38)
    callJS(("RP.hit(%s, %s, %d)"):format(jsString(zoneKey), jsString(zoneName), points))
end)

addEventHandler("rp:range:hud", resourceRoot, function(h) callJS(("RP.hud(%s)"):format(json(h))) end)

addEventHandler("rp:range:results", resourceRoot, function(r)
    training = false
    rangeTargetsClear()
    ensureBrowser()
    interactiveUI(true)
    callJS(("RP.results(%s)"):format(json(r)))
end)

addEventHandler("rp:range:close", resourceRoot, function()
    inside, training = false, false
    rangeTargetsClear()
    destroyUI()
end)

----------------------------------------------------------------
-- CEF -> servidor
----------------------------------------------------------------
addEventHandler("rp:range:ui:train", root, function(item)
    if type(item) == "string" then triggerServerEvent("rp:range:train", resourceRoot, item) end
end)
addEventHandler("rp:range:ui:again", root, function() triggerServerEvent("rp:range:reopen", resourceRoot) end)
addEventHandler("rp:range:ui:close", root, function()
    if inside then triggerServerEvent("rp:range:exit", resourceRoot) else destroyUI() end
end)

----------------------------------------------------------------
-- Mostrador de la armeria
----------------------------------------------------------------
local function atDesk()
    if getElementInterior(localPlayer) ~= RANGE.STORE_INTERIOR then return false end
    local dim = getElementDimension(localPlayer)
    local ok = false
    for _, l in ipairs(RANGE.LOCATIONS) do if dim == RANGE.STORE_DIM_BASE + l.id then ok = true end end
    if not ok then return false end
    local px, py, pz = getElementPosition(localPlayer)
    local D = RANGE.DESK
    return getDistanceBetweenPoints3D(px, py, pz, D.x, D.y, D.z) <= RANGE.INTERACT_RADIUS
end

local function canInteract()
    return not (isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
        or isPedInVehicle(localPlayer) or inside or exports.rp_injury:isLocalPlayerDowned())
end

setTimer(function() nearDesk = atDesk() end, 250, 0)

addEventHandler("onClientRender", root, function()
    if not nearDesk or not canInteract() then return end
    local text = "Pulsa E para el campo de tiro"
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (sw - w) / 2, sh - 230
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)

addEvent("rp:markers:moved")
-- Un admin movio el mostrador: recalcular su posicion (rp_markers)
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then rangeResolveDesk() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    rangeResolveDesk()
    bindKey("e", "down", function()
        if not nearDesk or not canInteract() then return end
        triggerServerEvent("rp:range:open", resourceRoot)
    end)
    bindKey("f2", "down", function()
        if training then triggerServerEvent("rp:range:abort", resourceRoot) end
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    rangeTargetsClear()
    destroyUI()
end)
