--[[
    rp_train · torniquetes de las estaciones (cliente)

    Cada elemento rp_traingate (s_stations.lua) es un paso con poste y brazo que mira hacia el andén.
    - Fuera, delante del paso: aparece el boleto (CEF, html/) con la E dibujada. E corta el boleto en el
      servidor, que responde con rp:train:gateResult y sube el brazo. Sin boleto, la UI dice dónde comprarlo.
    - Desde el andén: al acercarse se pide abrir (salida libre).
    - Con el brazo bajado no se puede cruzar desde fuera: el cliente devuelve al jugador a su último punto
      fuera del paso (la colisión del brazo escalado no es fiable). El servidor no se fía de esto: subir al
      tren en una estación con torniquetes exige el pase que da el torniquete.
    El navegador es local y se dibuja con dxDrawImage: no roba el foco ni muestra el cursor.
    Además: las rejas de las estaciones (data rp:train:fence) se hacen irrompibles aquí.
]]

addEvent("rp:train:gateResult", true)

local W, H = guiGetScreenSize()
local BW, BH = 460, 300
local browser, ready = nil, false
local pendingJS = {}
local shown = false

local gate          -- torniquete delante del jugador (lado de fuera)
local busy = false  -- esperando la respuesta del servidor
local hideAt        -- tick en que se oculta la UI tras validar
local blockGate     -- torniquete en cuyo paso (o junto a él) está el jugador: se vigila que no lo cruce cerrado
local lastOutside   -- { x, y, z } último punto fuera del paso
local exitAsked = {} -- [gate] = tick de la última petición de salida

local function frame(el, x, y)
    local gx, gy = getElementPosition(el)
    local r = math.rad(tonumber(getElementData(el, "rot")) or 0)
    local dx, dy = x - gx, y - gy
    return dx * -math.sin(r) + dy * math.cos(r), dx * math.cos(r) + dy * math.sin(r)
end

local function canAct()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if isPedInVehicle(localPlayer) or getElementData(localPlayer, "rp:train:rider") then return false end
    return not getElementData(localPlayer, "rp:downed") and not getElementData(localPlayer, "rp:cuffed")
end

----------------------------------------------------------------
-- Navegador (se crea la primera vez que hace falta)
----------------------------------------------------------------
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
    if isElement(browser) then return end
    browser = createBrowser(BW, BH, true, true)
    if not browser then return end
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local function show(station)
    ensureBrowser()
    shown, busy, hideAt = true, false, nil
    callJS(("RP.show(%s, %d)"):format(jsString(station), TRAIN.TICKET_PRICE))
end

local function hide()
    if not shown then return end
    shown, busy, hideAt = false, false, nil
    callJS("RP.hide()")
end

----------------------------------------------------------------
-- Qué torniquete hay delante (cada 150 ms)
----------------------------------------------------------------
local function scan()
    local x, y, z = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local found, near
    for _, el in ipairs(getElementsByType("rp_traingate")) do
        local gx, gy, gz = getElementPosition(el)
        if getElementDimension(el) == dim and getElementInterior(el) == int and math.abs(z - gz) < 3
            and getDistanceBetweenPoints2D(x, y, gx, gy) < TRAIN.GATE_USE + 2 then
            local along, side = frame(el, x, y)
            if math.abs(side) <= TRAIN.GATE_HALF_WIDTH + 0.6 then
                if math.abs(along) <= TRAIN.GATE_USE then near = el end
                if along < -0.1 and along >= -TRAIN.GATE_USE then
                    found = el
                elseif along > 0.1 and along <= TRAIN.GATE_USE and canAct() and not getElementData(el, "open") then
                    -- salida libre desde el andén
                    local now = getTickCount()
                    if not exitAsked[el] or now - exitAsked[el] > 2500 then
                        exitAsked[el] = now
                        triggerServerEvent("rp:train:gateExit", resourceRoot, el)
                    end
                end
            end
        end
    end

    blockGate = near
    if found and canAct() then
        if found ~= gate or not shown then gate = found; show(getElementData(found, "name") or "Estación") end
    elseif shown and not hideAt then
        hide()
        gate = nil
    end
    if hideAt and getTickCount() >= hideAt then hide(); gate = nil end
end

addEventHandler("rp:train:gateResult", resourceRoot, function(result, a, b)
    busy = false
    if not shown then return end
    if result == "punched" then
        callJS(("RP.punched(%s, %d)"):format(jsString(a), tonumber(b) or 0))
        hideAt = getTickCount() + 3200
    elseif result == "validated" then
        callJS("RP.validated()")
        hideAt = getTickCount() + 2200
    elseif result == "noticket" then
        callJS(("RP.noTicket(%d)"):format(tonumber(a) or TRAIN.TICKET_PRICE))
    else
        callJS("RP.reset()")
    end
end)

----------------------------------------------------------------
-- Paso cerrado: no se cruza desde fuera
----------------------------------------------------------------
addEventHandler("onClientPreRender", root, function()
    local g = blockGate
    if not g or not isElement(g) then lastOutside = nil return end
    local x, y, z = getElementPosition(localPlayer)
    local along, side = frame(g, x, y)
    if math.abs(side) > TRAIN.GATE_HALF_WIDTH then lastOutside = nil return end
    if along <= -0.3 then
        lastOutside = { x, y, z }
    elseif along < 0.5 then
        if getElementData(g, "open") then
            lastOutside = nil -- pasando con el brazo arriba: si baja a mitad, no se le devuelve
        elseif lastOutside then
            setElementPosition(localPlayer, lastOutside[1], lastOutside[2], lastOutside[3], false)
            if shown and not busy then callJS("RP.nudge()") end
        end
    else
        lastOutside = nil
    end
end)

----------------------------------------------------------------
-- Dibujo y tecla
----------------------------------------------------------------
addEventHandler("onClientRender", root, function()
    if not shown or not isElement(browser) or getElementData(localPlayer, "rp:hudHidden") then return end
    dxDrawImage((W - BW) / 2, H - BH - 150, BW, BH, browser)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(scan, 150, 0)
    bindKey("e", "down", function()
        -- E la usan muchos recursos: aquí solo actúa con el boleto en pantalla
        if not shown or busy or hideAt or not gate or not canAct() then return end
        busy = true
        callJS("RP.punching()")
        triggerServerEvent("rp:train:gatePunch", resourceRoot, gate)
        setTimer(function() if busy then busy = false; callJS("RP.reset()") end end, 4000, 1)
    end)
end)

addEventHandler("onClientElementDestroy", root, function()
    if source == gate then hide(); gate = nil end
    exitAsked[source] = nil
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isElement(browser) then destroyElement(browser) end
end)

----------------------------------------------------------------
-- Rejas (data rp:train:fence): irrompibles en cada cliente (los modelos DYN_* del juego se rompen al chocar)
----------------------------------------------------------------
local function fixFence(obj)
    if isElement(obj) and getElementType(obj) == "object" and getElementData(obj, "rp:train:fence") then
        setObjectBreakable(obj, false)
    end
end

addEventHandler("onClientElementStreamIn", root, function() fixFence(source) end)
addEventHandler("onClientElementDataChange", root, function(key) if key == "rp:train:fence" then fixFence(source) end end)
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, obj in ipairs(getElementsByType("object", root, true)) do fixFence(obj) end
end)
