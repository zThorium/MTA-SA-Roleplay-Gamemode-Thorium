--[[
    rp_vehicles / c_tuning.lua
    Taller de tuning con camara libre:
      - Al entrar: fundido a negro, toma cinematografica que gira alrededor
        del auto y se acerca, y el nombre del taller en pantalla.
      - Panel lateral (CEF a la izquierda): el resto de la pantalla muestra
        el auto con los cambios aplicados al momento (vista previa local).
      - Camara: arrastra con el click izquierdo para girar, rueda del mouse
        para acercar / alejar, flechas o A / D para girar.
      - Cada categoria mueve la camara a donde se ve la pieza (aleron atras,
        capo arriba, ruedas de costado, etc.).
      - Esc o Retroceso: salir del taller.
]]

local W, H = guiGetScreenSize()
local PANEL_W = math.max(340, math.min(440, math.floor(W * 0.3)))

local browserGui, browser, ready, pending = nil, nil, false, {}
local active = false          -- dentro del taller
local leaving = false
local vehicle, state, shopName = nil, nil, nil
local near = false
local cam = { yaw = 35, pitch = 12, dist = 1, tYaw = 35, tPitch = 12, tDist = 1, focus = nil }
local intro = nil             -- { start, duration }
local dragging, lastX, lastY = false, 0, 0
local lastFrame = getTickCount()

addEvent("rp:tune:near", true)
addEvent("rp:tune:show", true)
addEvent("rp:tune:done", true)
addEvent("rp:tune:ui:preview", false)
addEvent("rp:tune:ui:buy", false)
addEvent("rp:tune:ui:exit", false)
addEvent("rp:tune:ui:camera", false)
addEvent("rp:tune:ui:repair", false)

-- Vistas por categoria. yaw: 0 = delante del auto, 90 = lado derecho, 180 = detras.
-- pitch: altura en grados. dist: multiplicador de la distancia base. focus: componente a mirar.
local VIEWS = {
    colors   = { yaw = 35,  pitch = 14, dist = 1.0 },
    lights   = { yaw = 8,   pitch = 6,  dist = 0.8 },
    paintjob = { yaw = 90,  pitch = 10, dist = 1.0 },
    [0]  = { yaw = 15,  pitch = 38, dist = 0.8 },   -- capo
    [1]  = { yaw = 25,  pitch = 38, dist = 0.8 },   -- toma de aire
    [2]  = { yaw = 160, pitch = 26, dist = 0.85 },  -- aleron
    [3]  = { yaw = 90,  pitch = 4,  dist = 0.85 },  -- faldones
    [4]  = { yaw = 10,  pitch = 8,  dist = 0.8 },   -- defensa delantera
    [5]  = { yaw = 170, pitch = 8,  dist = 0.8 },   -- defensa trasera
    [6]  = { yaw = 15,  pitch = 8,  dist = 0.75 },  -- faros
    [7]  = { yaw = 45,  pitch = 62, dist = 0.9 },   -- techo
    [8]  = { yaw = 150, pitch = 30, dist = 0.9 },   -- nitro
    [9]  = { yaw = 70,  pitch = 4,  dist = 0.95 },  -- hidraulica
    [10] = { yaw = 150, pitch = 30, dist = 0.9 },   -- estereo
    [11] = { yaw = 35,  pitch = 14, dist = 1.0 },
    [12] = { yaw = 60,  pitch = 4,  dist = 0.55, focus = "wheel_rf_dummy" },  -- ruedas
    [13] = { yaw = 165, pitch = 6,  dist = 0.7 },   -- escape
    [14] = { yaw = 0,   pitch = 6,  dist = 0.8 },   -- paragolpes delantero
    [15] = { yaw = 180, pitch = 6,  dist = 0.8 },   -- paragolpes trasero
    [16] = { yaw = 35,  pitch = 14, dist = 1.0 },
}

----------------------------------------------------------------
-- Navegador (uno solo, se oculta y se reutiliza)
----------------------------------------------------------------
local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pending[#pending + 1] = code end
end

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, PANEL_W + 32, H, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/tuning.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pending) do executeBrowserJavascript(source, code) end
        pending = {}
    end)
end

local function showPanel(visible)
    if not isElement(browserGui) then return end
    guiSetVisible(browserGui, visible)
    if visible then guiBringToFront(browserGui) end
end

----------------------------------------------------------------
-- Vista previa local
----------------------------------------------------------------
local function applyLocal(v, st)
    if not isElement(v) or type(st) ~= "table" then return end
    for _, id in ipairs(getVehicleUpgrades(v) or {}) do removeVehicleUpgrade(v, id) end
    for _, id in ipairs(st.u or {}) do addVehicleUpgrade(v, id) end
    if st.c and #st.c >= 6 then setVehicleColor(v, unpack(st.c, 1, 6)) end
    if st.h and #st.h >= 3 then setVehicleHeadLightColor(v, unpack(st.h, 1, 3)) end
    if st.p then setVehiclePaintjob(v, st.p) end
end

local function parseCart(json)
    local cart = type(json) == "string" and fromJSON("[" .. json .. "]")
    return type(cart) == "table" and cart or nil
end

addEventHandler("rp:tune:ui:preview", root, function(json)
    local cart = parseCart(json)
    if not cart or not state or not isElement(vehicle) then return end
    applyLocal(vehicle, {
        c = cart.colors or state.c, h = cart.headlight or state.h, p = cart.paintjob or state.p,
        u = type(cart.full) == "table" and cart.full or state.u,
    })
end)

addEventHandler("rp:tune:ui:buy", root, function(json)
    local cart = parseCart(json)
    if cart and active then triggerServerEvent("rp:tune:buy", resourceRoot, cart) end
end)

----------------------------------------------------------------
-- Camara
----------------------------------------------------------------
local function setView(name)
    local v = VIEWS[name] or VIEWS[tonumber(name)] or VIEWS.colors
    cam.tYaw, cam.tPitch, cam.tDist, cam.focus = v.yaw, v.pitch, v.dist, v.focus
end

addEventHandler("rp:tune:ui:camera", root, function(category)
    if not active then return end
    local slot = type(category) == "string" and category:match("^slot(%d+)$")
    setView(slot and tonumber(slot) or category)
end)

local function angleDelta(a, b)
    return (b - a + 180) % 360 - 180
end

local function localToWorld(m, x, y, z)
    return x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
           x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
           x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
end

local function smoothstep(t) t = math.max(0, math.min(1, t)) return t * t * (3 - 2 * t) end

local function updateCamera()
    if not active or not isElement(vehicle) then return end
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastFrame) / 1000)
    lastFrame = now

    -- Teclado: flechas o A / D giran, W / S cambian la altura
    local turn = (getKeyState("arrow_l") or getKeyState("a")) and -1 or ((getKeyState("arrow_r") or getKeyState("d")) and 1 or 0)
    local tilt = (getKeyState("arrow_u") or getKeyState("w")) and 1 or ((getKeyState("arrow_d") or getKeyState("s")) and -1 or 0)
    if not intro and (turn ~= 0 or tilt ~= 0) then
        cam.tYaw = cam.tYaw + turn * 90 * dt
        cam.tPitch = math.max(2, math.min(75, cam.tPitch + tilt * 45 * dt))
    end

    local yaw, pitch, dist
    if intro then
        -- Toma de entrada: arranca lejos y alto, gira 140 grados y se acerca
        local t = smoothstep((now - intro.start) / intro.duration)
        yaw = cam.tYaw + 140 * (1 - t)
        pitch = cam.tPitch + 30 * (1 - t)
        dist = cam.tDist + 1.6 * (1 - t)
        cam.yaw, cam.pitch, cam.dist = yaw, pitch, dist
        if t >= 1 then
            intro = nil
            showPanel(true)
            callJS("RPT.enter()")
        end
    else
        local k = 1 - math.exp(-dt * 6)
        cam.yaw = cam.yaw + angleDelta(cam.yaw, cam.tYaw) * k
        cam.pitch = cam.pitch + (cam.tPitch - cam.pitch) * k
        cam.dist = cam.dist + (cam.tDist - cam.dist) * k
        yaw, pitch, dist = cam.yaw, cam.pitch, cam.dist
    end

    local m = getElementMatrix(vehicle)
    local base = math.max(3.5, (getElementRadius(vehicle) or 2.5) * 2.1)
    local d = base * dist
    -- Punto que se mira (centro del auto o una pieza)
    local fx, fy, fz = 0, 0, 0.1
    if cam.focus and getVehicleComponentPosition then
        local cx, cy, cz = getVehicleComponentPosition(vehicle, cam.focus)
        if cx then fx, fy, fz = cx, cy, cz end
    end
    local ry, rp = math.rad(yaw), math.rad(pitch)
    local ox = fx + math.sin(ry) * math.cos(rp) * d
    local oy = fy + math.cos(ry) * math.cos(rp) * d
    local oz = fz + math.sin(rp) * d
    -- Corre el auto hacia la derecha de la pantalla para que no lo tape el panel
    local px, py, pz = localToWorld(m, ox, oy, oz)
    local tx, ty, tz = localToWorld(m, fx, fy, fz)
    local sideX, sideY = (ty - py), -(tx - px)
    local len = math.sqrt(sideX * sideX + sideY * sideY)
    if len > 0 then
        local shift = d * 0.18
        px, py = px - sideX / len * shift, py - sideY / len * shift
        tx, ty = tx - sideX / len * shift, ty - sideY / len * shift
    end
    -- Si una pared o un objeto tapa el auto, la camara se pone delante del obstaculo
    local hit, hx, hy, hz = processLineOfSight(tx, ty, tz, px, py, pz, true, false, false, true, false, true, true)
    if hit then
        local vx, vy, vz = tx - hx, ty - hy, tz - hz
        local l = math.sqrt(vx * vx + vy * vy + vz * vz)
        if l > 0.01 then
            local pull = math.min(0.35, l * 0.5)
            px, py, pz = hx + vx / l * pull, hy + vy / l * pull, hz + vz / l * pull
        end
    end
    setCameraMatrix(px, py, pz, tx, ty, tz, 0, 70)
end

----------------------------------------------------------------
-- Entrar y salir
----------------------------------------------------------------
local function zoom(delta)
    if active and not intro then cam.tDist = math.max(0.45, math.min(1.8, cam.tDist + delta)) end
end
local function zoomIn() zoom(-0.08) end
local function zoomOut() zoom(0.08) end

local function onClick(button, buttonState, ax, ay)
    if not active or intro or button ~= "left" then return end
    if buttonState == "down" then
        if ax <= PANEL_W + 32 then return end   -- click dentro del panel
        dragging, lastX, lastY = true, ax, ay
    else
        dragging = false
    end
end

local function onCursorMove(_, _, ax, ay)
    if not dragging then return end
    cam.tYaw = cam.tYaw + (ax - lastX) * 0.4
    cam.tPitch = math.max(2, math.min(75, cam.tPitch + (ay - lastY) * 0.25))
    cam.yaw, cam.pitch = cam.tYaw, cam.tPitch
    lastX, lastY = ax, ay
end

local exitTuning

local function onKey(key, press)
    if not active or not press then return end
    if key == "escape" or key == "backspace" then
        cancelEvent()
        exitTuning(false)
    end
end

local function drawTitle()
    if not intro or not shopName then return end
    local t = (getTickCount() - intro.start) / intro.duration
    local alpha = math.floor(255 * math.max(0, math.min(1, t * 3, (1 - t) * 3)))
    local scale = math.max(1.6, H / 400)
    dxDrawText(shopName:upper(), 2, H * 0.12 + 2, W + 2, H * 0.12 + 2, tocolor(0, 0, 0, alpha), scale, "pricedown", "center", "top")
    dxDrawText(shopName:upper(), 0, H * 0.12, W, H * 0.12, tocolor(255, 255, 255, alpha), scale, "pricedown", "center", "top")
    dxDrawText("Taller de tuning", 0, H * 0.12 + scale * 34, W, H, tocolor(245, 165, 36, alpha), scale * 0.45, "default-bold", "center", "top")
end

local function drawHints()
    if not active or intro then return end
    local text = "Arrastra con el mouse para girar  ·  Rueda: acercar  ·  Flechas / WASD  ·  Esc: salir"
    dxDrawText(text, PANEL_W + 33, H - 39, W + 1, H - 9, tocolor(0, 0, 0, 200), 1, "default-bold", "center", "center")
    dxDrawText(text, PANEL_W + 32, H - 40, W, H - 10, tocolor(255, 255, 255, 220), 1, "default-bold", "center", "center")
end

local function setHidden(hidden)
    setElementData(localPlayer, "rp:hudHidden", hidden and true or false, false)
    showChat(not hidden)
    toggleAllControls(not hidden, true, false)
end

local function enterTuning(v, data)
    active, leaving, vehicle, state, shopName = true, false, v, data.state, data.shop
    near = false
    createBrowser()
    callJS(("RPT.show(%s[0], false)"):format(toJSON(data, true)))
    fadeCamera(false, 0.5)
    setTimer(function()
        if not active then return end
        setHidden(true)
        setView("colors")
        cam.yaw, cam.pitch, cam.dist = cam.tYaw, cam.tPitch, cam.tDist
        intro = { start = getTickCount(), duration = 2600 }
        lastFrame = getTickCount()
        addEventHandler("onClientPreRender", root, updateCamera)
        addEventHandler("onClientRender", root, drawTitle)
        addEventHandler("onClientRender", root, drawHints)
        addEventHandler("onClientClick", root, onClick)
        addEventHandler("onClientCursorMove", root, onCursorMove)
        addEventHandler("onClientKey", root, onKey)
        bindKey("mouse_wheel_up", "down", zoomIn)
        bindKey("mouse_wheel_down", "down", zoomOut)
        showCursor(true)
        fadeCamera(true, 1.0)
    end, 550, 1)
end

exitTuning = function(bought, silent)
    if not active or leaving then return end
    leaving = true
    if not bought and state and isElement(vehicle) then applyLocal(vehicle, state) end
    if not silent then triggerServerEvent("rp:tune:close", resourceRoot) end
    showPanel(false)
    callJS("RPT.hide()")
    dragging, intro = false, nil
    fadeCamera(false, 0.4)
    setTimer(function()
        removeEventHandler("onClientPreRender", root, updateCamera)
        removeEventHandler("onClientRender", root, drawTitle)
        removeEventHandler("onClientRender", root, drawHints)
        removeEventHandler("onClientClick", root, onClick)
        removeEventHandler("onClientCursorMove", root, onCursorMove)
        removeEventHandler("onClientKey", root, onKey)
        unbindKey("mouse_wheel_up", "down", zoomIn)
        unbindKey("mouse_wheel_down", "down", zoomOut)
        setHidden(false)
        showCursor(false)
        setCameraTarget(localPlayer)
        fadeCamera(true, 0.7)
        active, leaving, vehicle, state = false, false, nil, nil
    end, 450, 1)
end

addEventHandler("rp:tune:ui:exit", root, function() exitTuning(false) end)
addEventHandler("rp:tune:ui:repair", root, function() if active then triggerServerEvent("rp:tune:repair", resourceRoot) end end)

addEventHandler("rp:tune:show", resourceRoot, function(v, data)
    if active then
        -- Despues de comprar: estado nuevo, se sigue en el taller
        state = data.state
        callJS(("RPT.show(%s[0], true)"):format(toJSON(data, true)))
        return
    end
    enterTuning(v, data)
end)

-- El servidor saco al jugador (se bajo del auto, etc.)
addEventHandler("rp:tune:done", resourceRoot, function(bought)
    exitTuning(bought, true)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function() exitTuning(false) end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        if state and isElement(vehicle) then applyLocal(vehicle, state) end
        setHidden(false)
        showCursor(false)
        setCameraTarget(localPlayer)
    end
end)

----------------------------------------------------------------
-- Aviso en el marcador y tecla E
----------------------------------------------------------------
addEventHandler("rp:tune:near", resourceRoot, function(name)
    near = name or false
end)

addEventHandler("onClientRender", root, function()
    if not near or active then return end
    local text = ("%s - pulsa E o escribe /tunear"):format(near)
    dxDrawText(text, 1, H * 0.78 + 1, W + 1, H * 0.78 + 1, tocolor(0, 0, 0, 200), 1.4, "default-bold", "center")
    dxDrawText(text, 0, H * 0.78, W, H * 0.78, tocolor(255, 190, 60, 255), 1.4, "default-bold", "center")
end)

local function requestTuning()
    if near and not active then triggerServerEvent("rp:tune:open", resourceRoot) end
end
addCommandHandler("tunear", requestTuning)
bindKey("e", "down", function()
    if near and not active and not isChatBoxInputActive() and not isConsoleActive() and not isCursorShowing() then requestTuning() end
end)
