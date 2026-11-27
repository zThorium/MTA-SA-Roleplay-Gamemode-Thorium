--[[
    rp_interact / c_interact.lua  (cliente)

    - Con el modo cursor de la tecla M (rp_vehicles) activo, clic derecho sobre una persona:
      pide el menú al servidor y lo muestra en CEF junto al punto del clic. Al pasar el
      cursor por encima de alguien se marca con su nombre y el ratón dibujado.
    - Propuestas que te hacen (dar la mano, un objeto, subir al coche, cachearte): tarjeta dx
      abajo con E aceptar / Retroceso rechazar y cuenta atrás.
    - Primera vez junto a otra persona: consejo con M + clic derecho dibujados (una vez).
    - Primera vez que abres el menú: tutorial de 3 pasos en el CEF.
]]

local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.3, screenH / 900))

addEvent("rp:interact:showMenu", true)
addEvent("rp:interact:frisk", true)
addEvent("rp:interact:request", true)
addEvent("rp:interact:requestEnd", true)
addEvent("rp:interact:sfx", true)
-- Desde el CEF
addEvent("rp:interact:ui:pick", false)
addEvent("rp:interact:ui:close", false)
addEvent("rp:interact:ui:take", false)
addEvent("rp:interact:ui:tutorialDone", false)

local TUTORIAL_FILE = "@tutorial_interact.done"
local TIP_FILE = "@tip_interact.done"
local SOUND = { coins = "sounds/coins.wav", ok = "sounds/confirmation_001.ogg", no = "sounds/error_004.ogg",
                request = "sounds/glass_001.ogg", decline = "sounds/minimize_003.ogg" }

local tex, fonts = {}, {}
local hover = nil          -- persona bajo el cursor (modo M)
local pending = nil        -- { target, x, y, at } menú pedido al servidor
local menu = nil           -- { target, far } menú abierto
local request = nil        -- { from, text, seconds, t0 } propuesta que me hicieron
local tip = nil            -- { t0 } consejo en pantalla
local tipDone, tipNear = false, 0

local function now() return getTickCount() end
-- estandar:dep-opcional rp_help  reporte F1 con la persona elegida (openReport); se comprueba con running()
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end
local function sound(name) if SOUND[name] then playSound(SOUND[name]) end end
local function hasFile(f) return fileExists(f) end
local function markFile(f)
    if fileExists(f) then return end
    local h = fileCreate(f)
    if h then fileWrite(h, "1") fileClose(h) end
end

-- Modo cursor de la tecla M (rp_vehicles). Se pregunta como mucho cada 100 ms (se usa en cada frame).
local modeCache, modeAt = false, 0
local function cursorMode()
    if now() - modeAt < 100 then return modeCache end
    modeAt = now()
    if not running("rp_vehicles") then modeCache = false return false end
    local ok, on = pcall(function() return exports.rp_vehicles:isCursorModeActive() end)
    modeCache = ok and on == true
    return modeCache
end

local function isDowned() return getElementData(localPlayer, "rp:downed") == true end

----------------------------------------------------------------
-- Navegador CEF (uno, precreado y oculto)
----------------------------------------------------------------
local browserGui, browser, browserReady, pendingJS = nil, nil, false, {}

local function callJS(code)
    if isElement(browser) and browserReady then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsData(t)
    return (toJSON(t or {}, true):gsub("<", "\\u003c")) .. "[0]"
end

local function createBrowserUI()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        browserReady = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local hideTimer = nil
local function showBrowser(on)
    if not isElement(browserGui) then return end
    if isTimer(hideTimer) then killTimer(hideTimer) end
    hideTimer = nil
    if on then
        guiSetVisible(browserGui, true)
        guiBringToFront(browserGui)
        focusBrowser(browser)
        showCursor(true)
        guiSetInputEnabled(true)
    else
        guiSetInputEnabled(false)
        focusBrowser(nil)
        showCursor(false)
        -- deja terminar la animacion de salida
        hideTimer = setTimer(function()
            hideTimer = nil
            if not menu and isElement(browserGui) then guiSetVisible(browserGui, false) end
        end, 220, 1)
    end
end

local function closeMenu()
    if not menu then return end
    menu = nil
    callJS("RP.close()")
    showBrowser(false)
end

----------------------------------------------------------------
-- Persona bajo el cursor
----------------------------------------------------------------
local function targetable(p)
    return p ~= localPlayer and isElement(p) and getElementData(p, "rp:characterId") and not isPedDead(p)
        and not getPedOccupiedVehicle(p)
        and getElementDimension(p) == getElementDimension(localPlayer) and getElementInterior(p) == getElementInterior(localPlayer)
end

local function pickPlayer(cx, cy)
    local px, py, pz = getElementPosition(localPlayer)
    local camX, camY, camZ = getCameraMatrix()
    local best, bestD = nil, INTERACT.PICK_RADIUS * S
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if targetable(p) then
            local x, y, z = getPedBonePosition(p, 3)
            if not x then x, y, z = getElementPosition(p) end
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= INTERACT.PICK_DISTANCE then
                local sx, sy = getScreenFromWorldPosition(x, y, z)
                if sx then
                    local d = math.sqrt((sx - cx) ^ 2 + (sy - cy) ^ 2)
                    if d < bestD and isLineOfSightClear(camX, camY, camZ, x, y, z, true, false, false, true, false, false, false, localPlayer) then
                        best, bestD = p, d
                    end
                end
            end
        end
    end
    return best
end

addEventHandler("onClientClick", root, function(button, state, ax, ay, _, _, _, clicked)
    if button ~= "right" or state ~= "down" or menu or not cursorMode() then return end
    if isElement(clicked) and getElementType(clicked) == "vehicle" then return end   -- eso es de rp_vehicles
    if isDowned() then return end
    local t = (isElement(clicked) and getElementType(clicked) == "player" and targetable(clicked) and clicked) or pickPlayer(ax, ay)
    if not t then return end
    pending = { target = t, x = ax, y = ay, at = now() }
    triggerServerEvent("rp:interact:menu", resourceRoot, t)
end)

addEventHandler("rp:interact:showMenu", resourceRoot, function(t, data)
    if not pending or pending.target ~= t or now() - pending.at > 3000 or not cursorMode() then return end
    local x, y = pending.x, pending.y
    pending = nil
    if type(data) ~= "table" then return end
    menu = { target = t, far = data.far }
    local tutorial = not hasFile(TUTORIAL_FILE)
    markFile(TIP_FILE)
    tipDone, tip = true, nil
    callJS(("RP.open(%s, %d, %d, %s)"):format(jsData(data), x, y, tutorial and "true" or "false"))
    showBrowser(true)
end)

addEventHandler("rp:interact:frisk", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    menu = menu or { far = false }
    menu.frisk = true
    callJS(("RP.frisk(%s)"):format(jsData(data)))
    showBrowser(true)
end)

-- CEF -> Lua
addEventHandler("rp:interact:ui:pick", root, function(id, json)
    if not menu or type(id) ~= "string" then return end
    local t = menu.target
    if not isElement(t) then return closeMenu() end
    closeMenu()
    if id == "report" then
        if running("rp_help") then
            local ok = pcall(function() return exports.rp_help:openReport(t) end)
            if ok then return end
        end
        return exports.rp_notify:notify("Los reportes no están disponibles ahora. Usa F1.", "warning")
    end
    local data = type(json) == "string" and #json < 400 and fromJSON(json) or {}
    triggerServerEvent("rp:interact:do", resourceRoot, t, id, type(data) == "table" and data or {})
end)
addEventHandler("rp:interact:ui:close", root, closeMenu)
-- Quitar algo en el cacheo (id de objeto o "$cash"); el servidor decide si se puede
addEventHandler("rp:interact:ui:take", root, function(what)
    if menu and menu.frisk and type(what) == "string" and #what <= 64 then
        triggerServerEvent("rp:interact:take", resourceRoot, what)
    end
end)
addEventHandler("rp:interact:ui:tutorialDone", root, function() markFile(TUTORIAL_FILE) end)

----------------------------------------------------------------
-- Propuestas recibidas
----------------------------------------------------------------
addEventHandler("rp:interact:request", resourceRoot, function(d)
    if type(d) ~= "table" then return end
    request = { from = tostring(d.from or "Alguien"), text = tostring(d.text or ""), seconds = tonumber(d.seconds) or 15, t0 = now() }
    sound("request")
end)
addEventHandler("rp:interact:requestEnd", resourceRoot, function() request = nil end)
addEventHandler("rp:interact:sfx", resourceRoot, function(name) sound(name) end)

local function answer(accept)
    if not request then return end
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    request = nil
    sound(accept and "ok" or "decline")
    triggerServerEvent("rp:interact:respond", resourceRoot, accept)
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function px(v) return v * S end

local function drawPill(x, y, w, h, alpha, accent)
    -- postGUI siempre explícito: dxDrawPrimitive (dentro de DX) falla con nil y corta el resto del dibujo
    DX.roundRect(x, y, w, h, px(10), tocolor(16, 14, 22, math.floor(225 * alpha)), false)
    DX.roundRect(x, y + h - px(3), w, px(3), px(1.5), tocolor(accent[1], accent[2], accent[3], math.floor(255 * alpha)), false)
end

-- Marca sobre la persona bajo el cursor (modo M)
local function drawHover()
    if not cursorMode() or menu or isDowned() then hover = nil return end
    local cx, cy = getCursorPosition()
    if not cx then hover = nil return end
    hover = pickPlayer(cx * screenW, cy * screenH)
    if not hover then return end
    local x, y, z = getPedBonePosition(hover, 8)
    if not x then return end
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.45)
    if not sx then return end
    local name = getPlayerName(hover):gsub("_", " ")
    local label = "Interactuar"
    local icon = px(30)
    local tw = math.max(dxGetTextWidth(name, 1, fonts.name), dxGetTextWidth(label, 1, fonts.small))
    local w, h = icon + px(26) + tw, px(46)
    local x0, y0 = sx - w / 2, sy - h
    drawPill(x0, y0, w, h, 1, { 90, 170, 255 })
    dxDrawImage(x0 + px(8), y0 + (h - icon) / 2 - px(1), icon, icon, tex.mouseRight)
    dxDrawText(name, x0 + icon + px(16), y0 + px(5), x0 + w, y0 + h / 2 + px(2), tocolor(255, 255, 255), 1, fonts.name, "left", "center")
    dxDrawText(label, x0 + icon + px(16), y0 + h / 2, x0 + w, y0 + h - px(6), tocolor(143, 198, 255), 1, fonts.small, "left", "center")
    -- flecha hacia la persona
    DX.poly({ { sx - px(7), y0 + h, tocolor(16, 14, 22, 225) }, { sx + px(7), y0 + h, tocolor(16, 14, 22, 225) }, { sx, y0 + h + px(7), tocolor(16, 14, 22, 225) } }, false)
end

-- Tarjeta de propuesta (abajo, centrada): E acepta, Retroceso rechaza
local function drawRequest()
    if not request then return end
    local total = request.seconds * 1000
    local left = total - (now() - request.t0)
    if left <= 0 then request = nil return end
    local k = math.min(1, (now() - request.t0) / 220)
    local key = px(34)
    local title = request.from
    local text = request.text
    local accept, reject = "Aceptar", "Rechazar"
    local wText = math.max(dxGetTextWidth(title, 1, fonts.name), dxGetTextWidth(text, 1, fonts.body))
    local wKeys = key * 2 + dxGetTextWidth(accept, 1, fonts.body) + dxGetTextWidth(reject, 1, fonts.body) + px(44)
    local w = math.max(wText, wKeys) + px(40)
    local h = px(118)
    local x0 = (screenW - w) / 2
    local y0 = screenH * 0.70 + (1 - k) * px(20)
    drawPill(x0, y0, w, h, k, { 255, 190, 80 })
    local a = math.floor(255 * k)
    dxDrawText(title, x0, y0 + px(10), x0 + w, y0 + px(34), tocolor(255, 212, 138, a), 1, fonts.name, "center", "center")
    dxDrawText(text, x0, y0 + px(34), x0 + w, y0 + px(58), tocolor(244, 241, 246, a), 1, fonts.body, "center", "center")
    -- teclas dibujadas
    local wa = key + px(6) + dxGetTextWidth(accept, 1, fonts.body)
    local wr = key + px(6) + dxGetTextWidth(reject, 1, fonts.body)
    local kx = x0 + (w - (wa + px(28) + wr)) / 2
    local ky = y0 + px(62)
    local pulse = 1 + math.sin(now() / 200) * 0.05
    dxDrawImage(kx - key * (pulse - 1) / 2, ky - key * (pulse - 1) / 2, key * pulse, key * pulse, tex.keyE, 0, 0, 0, tocolor(255, 255, 255, a))
    dxDrawText(accept, kx + key + px(6), ky, kx + wa, ky + key, tocolor(143, 240, 184, a), 1, fonts.body, "left", "center")
    local rx = kx + wa + px(28)
    dxDrawImage(rx, ky, key, key, tex.keyBack, 0, 0, 0, tocolor(255, 255, 255, a))
    dxDrawText(reject, rx + key + px(6), ky, rx + wr, ky + key, tocolor(255, 158, 152, a), 1, fonts.body, "left", "center")
    -- cuenta atrás
    local frac = left / total
    local bx, bw = x0 + px(16), w - px(32)
    dxDrawRectangle(bx, y0 + h - px(12), bw, px(3), tocolor(255, 255, 255, math.floor(30 * k)))
    local col = frac < 0.3 and tocolor(255, 95, 87, a) or tocolor(255, 190, 80, a)
    dxDrawRectangle(bx, y0 + h - px(12), bw * frac, px(3), col)
end

-- Consejo de la primera vez junto a otra persona
local function drawTip()
    if not tip then return end
    local age = now() - tip.t0
    if age > 9000 or cursorMode() or menu then tip = nil return end
    local alpha = math.min(1, age / 300, (9000 - age) / 400)
    local key = px(36)
    local t1, t2 = "Pulsa", "y haz clic derecho sobre una persona para interactuar"
    local w1, w2 = dxGetTextWidth(t1, 1, fonts.body), dxGetTextWidth(t2, 1, fonts.body)
    local w = w1 + key * 2 + w2 + px(60)
    local h = px(52)
    local x0, y0 = (screenW - w) / 2, screenH * 0.78
    drawPill(x0, y0, w, h, alpha, { 90, 170, 255 })
    local a = math.floor(255 * alpha)
    local x = x0 + px(16)
    local cy = y0 + (h - key) / 2 - px(1)
    dxDrawText(t1, x, y0, x + w1, y0 + h, tocolor(255, 255, 255, a), 1, fonts.body, "left", "center")
    x = x + w1 + px(8)
    dxDrawImage(x, cy, key, key, tex.keyM, 0, 0, 0, tocolor(255, 255, 255, a))
    x = x + key + px(4)
    dxDrawImage(x, cy, key, key, tex.mouseRight, 0, 0, 0, tocolor(255, 255, 255, a))
    x = x + key + px(8)
    dxDrawText(t2, x, y0, x + w2, y0 + h, tocolor(255, 255, 255, a), 1, fonts.body, "left", "center")
end

addEventHandler("onClientRender", root, function()
    drawHover()
    drawTip()
    drawRequest()
end)

----------------------------------------------------------------
-- Vigilancia: cerrar el menú si ya no tiene sentido; consejo de la primera vez
----------------------------------------------------------------
local function guard()
    if menu and not menu.frisk then
        local t = menu.target
        local bad = not isElement(t) or isPedDead(localPlayer) or isDowned() or not getElementData(localPlayer, "rp:characterId")
        if not bad and not menu.far then
            local ax, ay, az = getElementPosition(localPlayer)
            local bx, by, bz = getElementPosition(t)
            bad = getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz) > INTERACT.DISTANCE + 3
        end
        if bad then closeMenu() end
    end
    -- Consejo: una sola vez, tras unos segundos junto a alguien y sin nada abierto
    if not tipDone and not tip and getElementData(localPlayer, "rp:characterId") and not isCursorShowing() and not isDowned() then
        local x, y, z = getElementPosition(localPlayer)
        local close = false
        for _, p in ipairs(getElementsByType("player", root, true)) do
            if targetable(p) then
                local px2, py2, pz2 = getElementPosition(p)
                if getDistanceBetweenPoints3D(x, y, z, px2, py2, pz2) <= INTERACT.TIP_DISTANCE then close = true break end
            end
        end
        tipNear = close and tipNear + 0.25 or 0
        if tipNear >= INTERACT.TIP_SECONDS then
            tip, tipDone = { t0 = now() }, true   -- una vez por sesión hasta que abra el menú
            sound("request")
        end
    end
end

----------------------------------------------------------------
-- Arranque y limpieza
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.mouseRight = dxCreateTexture("images/mouse_right.png", "argb", true, "clamp")
    tex.keyM = dxCreateTexture("images/keyboard_m.png", "argb", true, "clamp")
    tex.keyE = dxCreateTexture("images/keyboard_e.png", "argb", true, "clamp")
    tex.keyBack = dxCreateTexture("images/keyboard_backspace.png", "argb", true, "clamp")
    fonts.name = dxCreateFont("html/fonts/rubik_semibold.ttf", math.floor(12 * S + 0.5), false, "antialiased") or "default-bold"
    fonts.body = dxCreateFont("html/fonts/rubik_medium.ttf", math.floor(11 * S + 0.5), false, "antialiased") or "default"
    fonts.small = dxCreateFont("html/fonts/rubik_medium.ttf", math.floor(9.5 * S + 0.5), false, "antialiased") or "default"
    tipDone = hasFile(TIP_FILE)
    createBrowserUI()
    setTimer(guard, 250, 0)
    bindKey("e", "down", function() if request then answer(true) end end)
    bindKey("backspace", "down", function() if request then answer(false) end end)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    closeMenu()
    request = nil
end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then closeMenu() request, tip = nil, nil end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if menu then
        guiSetInputEnabled(false)
        showCursor(false)
    end
end)
