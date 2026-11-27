--[[
    rp_pizzeria / c_pizzeria.lua
    Marcador de contratacion (comedor), turno, estaciones con E y los dos navegadores CEF:
      - HUD: navegador de dx (sin entrada) con comandas, hornos, freidora, mano y resultados.
      - Paneles: navegador de GUI con cursor (contratar, armar, cortar, freidora, despensa).
    Todo lo que se pulsa se reenvia al servidor, que lo valida.
]]
local sw, sh = guiGetScreenSize()

Pz = Pz or {}
Pz.onShift, Pz.dim, Pz.state = false, nil, nil

local hireMarker, leaveMarker
local hud, hudReady, hudQueue = nil, false, {}
local panelGui, panel, panelReady, panelQueue, panelKind = nil, nil, false, {}, nil

for _, e in ipairs({ "shift", "state", "panel", "closePanel", "fx" }) do addEvent("rp:pizzeria:" .. e, true) end
for _, e in ipairs({ "close", "hire", "assemble", "cut", "fry", "restock", "discard", "leave" }) do addEvent("rp:pizzeria:ui:" .. e, false) end

----------------------------------------------------------------
-- Utilidades JS
----------------------------------------------------------------
local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function json(t) return toJSON(t or {}, true) .. "[0]" end

local function hudJS(code)
    if isElement(hud) and hudReady then executeBrowserJavascript(hud, code) else hudQueue[#hudQueue + 1] = code end
end

local function panelJS(code)
    if isElement(panel) and panelReady then executeBrowserJavascript(panel, code) else panelQueue[#panelQueue + 1] = code end
end

function Pz.hud(code) hudJS(code) end

----------------------------------------------------------------
-- HUD (navegador dx, sin entrada)
----------------------------------------------------------------
local function createHud()
    if isElement(hud) then return end
    hud = createBrowser(sw, sh, true, true)
    hudReady, hudQueue = false, {}
    addEventHandler("onClientBrowserCreated", hud, function()
        loadBrowserURL(source, "http://mta/local/html/index.html#hud")
    end)
    addEventHandler("onClientBrowserDocumentReady", hud, function()
        hudReady = true
        for _, c in ipairs(hudQueue) do executeBrowserJavascript(source, c) end
        hudQueue = {}
    end)
end

local function destroyHud()
    if isElement(hud) then destroyElement(hud) end
    hud, hudReady, hudQueue = nil, false, {}
end

----------------------------------------------------------------
-- Paneles (navegador de GUI con cursor)
----------------------------------------------------------------
local function closePanel(notifyServer)
    if not isElement(panelGui) then return end
    destroyElement(panelGui)
    panelGui, panel, panelReady, panelQueue, panelKind = nil, nil, false, {}, nil
    showCursor(false)
    Pz.hud("PZ.tutorialHidden(false)")
    guiSetInputEnabled(false)
    if notifyServer ~= false then triggerServerEvent("rp:pizzeria:closePanel", resourceRoot) end
end

local function openPanel(kind, data)
    if not isElement(panelGui) then
        panelGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
        panel = guiGetBrowser(panelGui)
        panelReady, panelQueue = false, {}
        addEventHandler("onClientBrowserCreated", panel, function()
            loadBrowserURL(source, "http://mta/local/html/index.html#panel")
        end)
        addEventHandler("onClientBrowserDocumentReady", panel, function()
            panelReady = true
            for _, c in ipairs(panelQueue) do executeBrowserJavascript(source, c) end
            panelQueue = {}
        end)
        showCursor(true)
        Pz.hud("PZ.tutorialHidden(true)")
        guiSetInputEnabled(true)
    end
    panelKind = kind
    panelJS(("PZ.panel(%s, %s)"):format(jsString(kind), json(data)))
end

addEventHandler("rp:pizzeria:panel", resourceRoot, function(kind, data)
    if kind ~= "hire" and not Pz.onShift then return end
    openPanel(kind, data)
end)
addEventHandler("rp:pizzeria:closePanel", resourceRoot, function() closePanel(false) end)
addEventHandler("onClientPlayerWasted", localPlayer, function() closePanel() end)

-- Eventos que manda el JS
addEventHandler("rp:pizzeria:ui:close", root, function() closePanel() end)
addEventHandler("rp:pizzeria:ui:hire", root, function(action)
    if action == "hire" or action == "start" or action == "tutorial" or action == "quit" then
        triggerServerEvent("rp:pizzeria:hireAction", resourceRoot, action)
    end
end)
addEventHandler("rp:pizzeria:ui:leave", root, function()
    closePanel(false)
    triggerServerEvent("rp:pizzeria:leave", resourceRoot)
end)
addEventHandler("rp:pizzeria:ui:assemble", root, function(orderId, sauce, cheese, piecesJSON)
    local pieces = type(piecesJSON) == "string" and fromJSON(piecesJSON) or nil
    if type(pieces) ~= "table" then return end
    triggerServerEvent("rp:pizzeria:assemble", resourceRoot, tonumber(orderId), tonumber(sauce), tonumber(cheese), pieces)
end)
addEventHandler("rp:pizzeria:ui:cut", root, function(cutsJSON)
    local cuts = type(cutsJSON) == "string" and fromJSON(cutsJSON) or nil
    if type(cuts) ~= "table" then return end
    triggerServerEvent("rp:pizzeria:cut", resourceRoot, cuts)
end)
addEventHandler("rp:pizzeria:ui:fry", root, function(action, arg)
    triggerServerEvent("rp:pizzeria:fry", resourceRoot, tostring(action), tonumber(arg))
end)
addEventHandler("rp:pizzeria:ui:restock", root, function(id)
    triggerServerEvent("rp:pizzeria:restock", resourceRoot, tostring(id))
end)
addEventHandler("rp:pizzeria:ui:discard", root, function()
    triggerServerEvent("rp:pizzeria:discard", resourceRoot)
end)

----------------------------------------------------------------
-- Turno
----------------------------------------------------------------
local function destroyLeave()
    if isElement(leaveMarker) then destroyElement(leaveMarker) end
    leaveMarker = nil
end

addEventHandler("rp:pizzeria:shift", resourceRoot, function(on, dim)
    Pz.onShift, Pz.dim = on and true or false, on and dim or nil
    -- en el turno solo se ve el HUD de la pizzeria: el de rp_hud (minimapa, necesidades...) se oculta como con F7
    pcall(function() exports.rp_hud:setHudHidden("rp_pizzeria", Pz.onShift) end)
    destroyLeave()
    closePanel(false)
    if on then
        createHud()
        if not Pz.keyE then Pz.keyE = dxCreateTexture("images/keys/keyboard_e.png", "argb", true, "clamp") end
        if (PIZZERIA.MUSIC_VOLUME or 0) > 0 then hudJS(("PZ.music(%s)"):format(PIZZERIA.MUSIC_VOLUME)) end
        local l = PIZZERIA.LEAVE
        leaveMarker = createMarker(l.x, l.y, l.z - 1, "cylinder", 1.1, 230, 80, 70, 120)
        setElementInterior(leaveMarker, PIZZERIA.INTERIOR)
        setElementDimension(leaveMarker, dim)
        exports.rp_markers:setMarkerStyle(leaveMarker, { icon = "exit", label = "Terminar turno" })
        addEventHandler("onClientMarkerHit", leaveMarker, function(el, sameDim)
            if el == localPlayer and sameDim and not isPedInVehicle(localPlayer) then openPanel("leave", {}) end
        end)
    else
        Pz.state = nil
        destroyHud()
    end
    if Pz.onShiftChanged then Pz.onShiftChanged(Pz.onShift, dim) end
end)

addEventHandler("rp:pizzeria:state", resourceRoot, function(state)
    Pz.state = state
    Pz.stateTick = getTickCount()
    hudJS(("PZ.state(%s)"):format(json(state)))
    if panelKind == "fryer" or panelKind == "assembly" or panelKind == "pantry" then
        panelJS(("PZ.stock(%s)"):format(json(state.stock)))
    end
    if Pz.onState then Pz.onState(state) end
end)

addEventHandler("rp:pizzeria:fx", resourceRoot, function(kind, data)
    hudJS(("PZ.fx(%s, %s)"):format(jsString(kind), json(data)))
    if Pz.onFx then Pz.onFx(kind, data) end
end)

----------------------------------------------------------------
-- Marcador de contratacion (maletin)
----------------------------------------------------------------
-- La posicion puede haberla movido un admin con el editor (rp_markers): se rehace en rp:markers:moved
local function spawnHireMarker()
    if isElement(hireMarker) then destroyElement(hireMarker) end
    pizzeriaResolveHire()
    local h = PIZZERIA.HIRE
    hireMarker = createMarker(h.x, h.y, h.z - 1, "cylinder", 1.2, 200, 60, 50, 120)
    setElementInterior(hireMarker, PIZZERIA.INTERIOR)
    setElementDimension(hireMarker, h.dimension)
    exports.rp_markers:setMarkerStyle(hireMarker, { icon = "job", label = "Trabajo de pizzero" })
    addEventHandler("onClientMarkerHit", hireMarker, function(el, sameDim)
        if el ~= localPlayer or not sameDim or isPedInVehicle(localPlayer) or Pz.onShift then return end
        triggerServerEvent("rp:pizzeria:hireOpen", resourceRoot)
    end)
end

addEvent("rp:markers:moved")
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then spawnHireMarker() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    spawnHireMarker()

    bindKey("e", "down", function()
        if not Pz.onShift or isElement(panelGui) then return end
        if isChatBoxInputActive() or isConsoleActive() or isCursorShowing() then return end
        if getElementData(localPlayer, "rp:downed") then return end
        local st = Pz.nearStation()
        if st then triggerServerEvent("rp:pizzeria:station", resourceRoot, st.id) end
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if Pz.onShift then pcall(function() exports.rp_hud:setHudHidden("rp_pizzeria", false) end) end
    if isElement(panelGui) then showCursor(false) guiSetInputEnabled(false) end
end)

----------------------------------------------------------------
-- Estaciones: la mas cercana y que pasaria al pulsar E
----------------------------------------------------------------
function Pz.nearStation()
    if getElementInterior(localPlayer) ~= PIZZERIA.INTERIOR or getElementDimension(localPlayer) ~= Pz.dim then return nil end
    local px, py, pz = getElementPosition(localPlayer)
    -- con la pizza empacada en la mano, todo el mostrador sirve para entregar (tiene prioridad sobre la caja)
    local hand = Pz.state and Pz.state.hand
    local z = PIZZERIA.COUNTER
    if hand and hand.kind == "boxed" and px >= z.x1 and px <= z.x2 and py >= z.y1 and py <= z.y2 then
        return PIZZERIA.STATION_BY_ID.pickup
    end
    local best, bestD
    for _, st in ipairs(PIZZERIA.STATIONS) do
        local d = getDistanceBetweenPoints2D(px, py, st.x, st.y)
        if st.kind ~= "pickup" and d <= PIZZERIA.STATION_RADIUS and math.abs(pz - st.z) < 2 and (not bestD or d < bestD) then
            best, bestD = st, d
        end
    end
    return best
end

local function orderById(id)
    if not Pz.state then return nil end
    for _, o in ipairs(Pz.state.orders) do if o.id == id then return o end end
end

local function stationHint(st)
    local s = Pz.state
    if not s then return st.label end
    local hand = s.hand
    if st.kind == "order" then
        local o = orderById(s.queue[1])
        if not o then return "Caja · no hay nadie en la fila" end
        if o.arriveIn - (getTickCount() - (Pz.stateTick or 0)) > 0 then
            return ("Caja · %s viene llegando"):format(o.name)
        end
        return ("Caja · tomar el pedido de %s"):format(o.name)
    elseif st.kind == "pickup" then
        if hand and hand.kind == "boxed" then
            local o = orderById(hand.order)
            return ("Entregar la pizza a %s"):format(o and o.name or "?")
        end
        return "Entregas · trae una pizza empacada"
    elseif st.kind == "assembly" then
        return hand and "Mesa de armado · tienes las manos ocupadas" or "Mesa de armado · armar una pizza"
    elseif st.kind == "oven" then
        local ov = s.ovens[st.slot]
        if ov then
            local elapsed = ov.ago + (getTickCount() - (Pz.stateTick or getTickCount()))
            local r = elapsed / ov.target
            local how = r < 0.85 and "cruda" or r <= 1.15 and "¡en su punto!" or r < PIZZERIA.BURN_AT and "pasándose" or "quemada"
            return ("%s · sacar la pizza (%s)"):format(st.label, how)
        end
        return hand and hand.kind == "raw" and ("%s · meter la pizza"):format(st.label) or ("%s · vacío"):format(st.label)
    elseif st.kind == "cut" then
        return hand and hand.kind == "baked" and "Corte y empaque · cortar la pizza" or "Corte y empaque · trae una pizza horneada"
    elseif st.kind == "fryer" then
        return "Freidora · guarniciones"
    elseif st.kind == "pantry" then
        return "Despensa · reponer ingredientes"
    end
    return st.label
end

addEventHandler("onClientRender", root, function()
    if not Pz.onShift then return end
    local hidden = getElementData(localPlayer, "rp:hudHidden")
    if isElement(hud) and hudReady and not hidden then dxDrawImage(0, 0, sw, sh, hud) end
    if isElement(panelGui) or hidden or isCursorShowing() then return end
    local st = Pz.nearStation()
    if not st then return end
    -- aviso con la tecla E dibujada (Kenney Input Prompts, CC0)
    local text = stationHint(st)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 70
    local x, y = (sw - w) / 2, sh - 190
    dxDrawRectangle(x, y, w, 40, tocolor(12, 14, 20, 215))
    dxDrawRectangle(x, y, 3, 40, tocolor(230, 80, 60, 255))
    if Pz.keyE then dxDrawImage(x + 10, y + 4, 32, 32, Pz.keyE) end
    dxDrawText(text, x + 48, y, x + w - 10, y + 40, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)
