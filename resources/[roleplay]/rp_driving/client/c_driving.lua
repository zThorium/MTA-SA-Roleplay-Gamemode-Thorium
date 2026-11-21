--[[
    rp_driving / c_driving.lua

    Lado cliente de la autoescuela:
      - "Pulsa E" junto al instructor y pizarra 3D con los mejores puntajes.
      - Interfaz CEF: menu de pruebas, resultado y tarjeta de la licencia.
      - Durante una prueba: presentacion con camara sobre la pista, cuenta atras,
        HUD (tiempo, par, dano, conos, puntos, giro), zona de parada dibujada en
        el suelo, aviso de conos derribados al servidor y cartel final.
    El servidor valida y puntua todo; aqui solo se dibuja y se reenvia.
]]

local screenW, screenH = guiGetScreenSize()
local S = math.min(1, screenH / 900)
local schools, board = {}, {}
local nearSchool = nil

-- CEF
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

-- Prueba en curso
local run = nil   -- { test, arena, vehicle, cones = {elements}, phase, startTick, cp, total, coneHits, spin, lastYaw, box = {corners} ... }
local banner = nil   -- { title, sub, color, medal, until }
local warnText, warnUntil = nil, 0
local countdown = nil   -- { n, startedAt }
local abortAsked = 0

local MEDAL_COLORS = {
    [0] = { 150, 150, 150 }, [1] = { 205, 127, 50 }, [2] = { 200, 205, 215 }, [3] = { 255, 205, 40 }, [4] = { 150, 235, 255 },
}
local MEDAL_NAMES = { [0] = "Sin medalla", [1] = "Bronce", [2] = "Plata", [3] = "Oro", [4] = "Platino" }

addEvent("rp:driving:schools", true)
addEvent("rp:driving:menu", true)
addEvent("rp:driving:closeMenu", true)
addEvent("rp:driving:begin", true)
addEvent("rp:driving:countdown", true)
addEvent("rp:driving:go", true)
addEvent("rp:driving:checkpoint", true)
addEvent("rp:driving:coneHit", true)
addEvent("rp:driving:warn", true)
addEvent("rp:driving:finish", true)
addEvent("rp:driving:result", true)
addEvent("rp:driving:card", true)
addEvent("rp:driving:ui:close", false)
addEvent("rp:driving:ui:start", false)
addEvent("rp:driving:ui:reprint", false)
addEvent("rp:driving:ui:menu", false)

local function color(c, a) return tocolor(c[1], c[2], c[3], a or 255) end
local ACCENT = DRIVING.COLOR

----------------------------------------------------------------
-- CEF
----------------------------------------------------------------
local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function closeUI()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function openUI()
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

addEventHandler("rp:driving:menu", resourceRoot, function(data)
    if run then return end
    openUI()
    callJS(("RP.menu(%s[0])"):format(toJSON(data or {}, true)))
end)

addEventHandler("rp:driving:result", resourceRoot, function(data)
    banner = nil
    openUI()
    callJS(("RP.result(%s[0])"):format(toJSON(data or {}, true)))
end)

addEventHandler("rp:driving:card", resourceRoot, function(card)
    if run then return end
    openUI()
    callJS(("RP.card(%s[0])"):format(toJSON(card or {}, true)))
end)

addEventHandler("rp:driving:closeMenu", resourceRoot, closeUI)
addEventHandler("rp:driving:ui:close", root, closeUI)

addEventHandler("rp:driving:ui:start", root, function(testId)
    if type(testId) ~= "string" or run then return end
    triggerServerEvent("rp:driving:start", resourceRoot, testId)
end)

addEventHandler("rp:driving:ui:menu", root, function()
    triggerServerEvent("rp:driving:open", resourceRoot)
end)

addEventHandler("rp:driving:ui:reprint", root, function()
    triggerServerEvent("rp:driving:reprint", resourceRoot)
end)

----------------------------------------------------------------
-- Autoescuelas en el mundo
----------------------------------------------------------------
addEventHandler("rp:driving:schools", resourceRoot, function(list, top)
    schools, board = list or {}, top or {}
end)

addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:drivingSchool") then cancelEvent() end
end)

local function updateNear()
    nearSchool = nil
    if run or isPedInVehicle(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
    local px, py, pz = getElementPosition(localPlayer)
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for _, s in ipairs(schools) do
        if s.interior == int and s.dimension == dim and getDistanceBetweenPoints3D(px, py, pz, s.x, s.y, s.z) <= DRIVING.INTERACT_RADIUS then
            nearSchool = s.id
            return
        end
    end
end

local function drawPrompt(text)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, color(ACCENT))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end

-- Pizarra flotante con el top del ranking general
local function drawBoard(s, px, py, pz)
    local dist = getDistanceBetweenPoints3D(px, py, pz, s.x, s.y, s.z)
    if dist > DRIVING.BOARD_DISTANCE then return end
    local sx, sy = getScreenFromWorldPosition(s.x, s.y, s.z + 2.3, 0.1)
    if not sx then return end
    local scale = math.max(0.55, math.min(1, 12 / math.max(dist, 1)))
    local rows = math.min(#board, DRIVING.BOARD_ROWS)
    local w, lh = 300 * scale, 20 * scale
    local h = (54 + math.max(rows, 1) * 20) * scale
    local x, y = sx - w / 2, sy - h
    local alpha = dist > DRIVING.BOARD_DISTANCE - 6 and math.floor(255 * (DRIVING.BOARD_DISTANCE - dist) / 6) or 255
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, math.floor(alpha * 0.85)))
    dxDrawRectangle(x, y, w, 3 * scale, color(ACCENT, alpha))
    dxDrawText("AUTOESCUELA", x, y + 6 * scale, x + w, y + 24 * scale, color(ACCENT, alpha), 1.15 * scale, "default-bold", "center")
    dxDrawText("Mejores puntajes", x, y + 24 * scale, x + w, y + 40 * scale, tocolor(154, 163, 178, alpha), 0.9 * scale, "default", "center")
    if rows == 0 then
        dxDrawText("Nadie aun. ¡Se el primero!", x, y + 44 * scale, x + w, y + 44 * scale + lh, tocolor(242, 244, 248, alpha), scale, "default", "center")
    end
    for i = 1, rows do
        local r = board[i]
        local ry = y + (44 + (i - 1) * 20) * scale
        dxDrawText(i .. ". " .. r.name, x + 12 * scale, ry, x + w * 0.62, ry + lh, tocolor(242, 244, 248, alpha), scale, "default-bold", "left", "center", true)
        dxDrawRectangle(x + w * 0.64, ry + lh / 2 - 4 * scale, 8 * scale, 8 * scale, color(MEDAL_COLORS[r.medal] or MEDAL_COLORS[0], alpha))
        dxDrawText(("%d pts"):format(r.total), x, ry, x + w - 12 * scale, ry + lh, color(ACCENT, alpha), scale, "default-bold", "right", "center")
    end
end

----------------------------------------------------------------
-- Prueba: utilidades
----------------------------------------------------------------
local function toWorld(f, r)
    return drivingToWorld(run.arena, f, r)
end

local function groundZ(x, y)
    local z = run.arena.z
    local gz = getGroundPosition(x, y, z + 4)
    if gz and gz ~= 0 and math.abs(gz - z) < 6 then return gz end
    return z
end

local function buildBox()
    local box = run.test.box
    if not box then return end
    local a = math.rad(box.a)
    local hl, hw = box.l / 2, box.w / 2
    local corners = {}
    for _, c in ipairs({ { hl, -hw }, { hl, hw }, { -hl, hw }, { -hl, -hw } }) do
        -- (along, across) -> (f, r) de la pista
        local f = box.f + c[1] * math.cos(a) + c[2] * math.sin(a)
        local r = box.r - c[1] * math.sin(a) + c[2] * math.cos(a)
        local x, y = toWorld(f, r)
        corners[#corners + 1] = { x, y, groundZ(x, y) + 0.06 }
    end
    -- Flecha de la direccion en la que hay que quedar
    local tipF, tipR = box.f + hl * 0.8 * math.cos(a), box.r - hl * 0.8 * math.sin(a)
    local tx, ty = toWorld(tipF, tipR)
    local cx, cy = toWorld(box.f, box.r)
    run.box = { corners = corners, arrow = { cx, cy, groundZ(cx, cy) + 0.06, tx, ty } }
end

local function farthestPoint(test)
    local best = { 0, 0 }
    local function consider(f, r) if math.abs(f) > math.abs(best[1]) then best = { f, r } end end
    for _, c in ipairs(test.checkpoints) do consider(c[1], c[2]) end
    for _, c in ipairs(test.cones) do consider(c[1], c[2]) end
    if test.box then consider(test.box.f, test.box.r) end
    return best
end

local function fmtTime(s)
    s = math.max(0, s or 0)
    return ("%d:%05.2f"):format(math.floor(s / 60), s % 60)
end

local function endIntro()
    if not run or run.phase ~= "intro" then return end
    run.phase = "waiting"
    setCameraTarget(localPlayer)
    triggerServerEvent("rp:driving:ready", resourceRoot)
end

----------------------------------------------------------------
-- Prueba: eventos del servidor
----------------------------------------------------------------
addEventHandler("rp:driving:begin", resourceRoot, function(testId, arena, vehicle, cones)
    local test = DRIVING_TEST_INDEX[testId]
    if not test then return end
    closeUI()
    pcall(function() exports.rp_inventory:closeInventory() end)
    run = {
        test = test, arena = arena, vehicle = vehicle, phase = "intro", introStart = getTickCount(),
        cp = 0, total = #test.checkpoints * (test.laps or 1), coneHits = 0, spin = 0, cones = {},
    }
    banner, countdown, warnText = nil, nil, nil
    -- Conos: se guarda su posicion inicial para detectar cuando se mueven
    for i = 1, cones or 0 do
        local c = test.cones[i]
        local x, y = toWorld(c[1], c[2])
        run.cones[i] = { x = x, y = y }
    end
    buildBox()
    local far = farthestPoint(test)
    run.introFrom = { 0, 0 }
    run.introTo = far
end)

addEventHandler("rp:driving:countdown", resourceRoot, function(n)
    if not run then return end
    if run.phase == "intro" then endIntro() end
    run.phase = "countdown"
    countdown = { n = n, startedAt = getTickCount(), last = -1 }
end)

addEventHandler("rp:driving:go", resourceRoot, function()
    if not run then return end
    run.phase = "running"
    run.startTick = getTickCount()
    countdown = { n = 0, startedAt = getTickCount() - 1, go = true }
    local _, _, rz = getElementRotation(run.vehicle)
    run.lastYaw, run.spin = rz, 0
    playSoundFrontEnd(45)
end)

addEventHandler("rp:driving:checkpoint", resourceRoot, function(i, total)
    if not run then return end
    run.cp, run.total = i, total
    playSoundFrontEnd(43)
end)

addEventHandler("rp:driving:coneHit", resourceRoot, function(n)
    if not run then return end
    run.coneHits = n
    warnText, warnUntil = "Cono derribado", getTickCount() + 1500
    playSoundFrontEnd(4)
end)

addEventHandler("rp:driving:warn", resourceRoot, function(text)
    warnText, warnUntil = tostring(text), getTickCount() + 2500
    playSoundFrontEnd(4)
end)

addEventHandler("rp:driving:finish", resourceRoot, function(passed, score, medal, reason)
    if not run then return end
    run.phase = "ending"
    run.endTime = run.startTick and (getTickCount() - run.startTick) / 1000 or 0
    if passed then
        banner = { title = "PRUEBA SUPERADA", sub = ("%d%%  -  %s"):format(score, MEDAL_NAMES[medal] or ""), color = MEDAL_COLORS[medal], medal = medal }
        playSoundFrontEnd(medal >= 3 and 7 or 8)
    else
        banner = { title = "SUSPENDIDO", sub = reason or "", color = { 229, 72, 77 } }
        playSoundFrontEnd(5)
    end
    banner.untilTick = getTickCount() + 3300
    -- El cartel se queda mientras el servidor devuelve al jugador a la autoescuela
    local finished = run
    setTimer(function() if run == finished then run = nil end end, 3200, 1)
end)

----------------------------------------------------------------
-- Prueba: deteccion de conos derribados (se mueven o se caen)
----------------------------------------------------------------
setTimer(function()
    if not run or run.phase ~= "running" then return end
    for i, c in ipairs(run.cones) do
        if not c.reported then
            local obj = c.object
            if not isElement(obj) then
                -- Busca el objeto del servidor por cercania (los crea el servidor en la dimension privada)
                for _, o in ipairs(getElementsByType("object", root, true)) do
                    if getElementModel(o) == 1238 and getElementDimension(o) == getElementDimension(localPlayer) then
                        local ox, oy = getElementPosition(o)
                        if getDistanceBetweenPoints2D(ox, oy, c.x, c.y) < 0.3 then c.object = o break end
                    end
                end
                obj = c.object
            end
            if isElement(obj) then
                local ox, oy = getElementPosition(obj)
                local rx, ry = getElementRotation(obj)
                local tilted = math.abs(drivingWrap(rx)) > 30 or math.abs(drivingWrap(ry)) > 30
                if getDistanceBetweenPoints2D(ox, oy, c.x, c.y) > 0.45 or tilted then
                    c.reported = true
                    triggerServerEvent("rp:driving:cone", resourceRoot, i)
                end
            end
        end
    end
end, 150, 0)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function drawShadowText(text, x1, y1, x2, y2, col, scale, font, alignX, alignY)
    dxDrawText(text, x1 + 2, y1 + 2, x2 + 2, y2 + 2, tocolor(0, 0, 0, 200), scale, font, alignX, alignY)
    dxDrawText(text, x1, y1, x2, y2, col, scale, font, alignX, alignY)
end

local function drawBox()
    if not run.box then return end
    local col = tocolor(245, 205, 40, 230)
    local done = run.cp >= run.total and (not run.test.spin or math.abs(run.spin) >= run.test.spin)
    if not done then col = tocolor(245, 205, 40, 90) end
    local c = run.box.corners
    for i = 1, 4 do
        local a, b = c[i], c[i % 4 + 1]
        dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], col, 6)
    end
    local ar = run.box.arrow
    dxDrawLine3D(ar[1], ar[2], ar[3], ar[4], ar[5], ar[3], col, 4)
end

local function drawIntro()
    local now = getTickCount()
    local DURATION = 7000
    local t = math.min(1, (now - run.introStart) / DURATION)
    local e = t * t * (3 - 2 * t)
    local a, b = run.introFrom, run.introTo
    local f = a[1] + (b[1] - a[1]) * e
    local r = a[2] + (b[2] - a[2]) * e
    local camF, camR = f - 30 + 20 * e, r + 28
    local cx, cy = toWorld(camF, camR)
    local lx, ly = toWorld(f + 10, r)
    setCameraMatrix(cx, cy, run.arena.z + 22 - 6 * e, lx, ly, run.arena.z)

    -- Panel de instrucciones
    local w, h = math.min(760, screenW - 40), 170 * S + 20
    local x, y = (screenW - w) / 2, screenH - h - 60 * S
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 225))
    dxDrawRectangle(x, y, 4, h, color(ACCENT))
    dxDrawText(("PRUEBA %d / %d"):format(run.test.index, #DRIVING_TESTS), x + 24, y + 14, x + w, y + 34, color(ACCENT), 1, "default-bold")
    dxDrawText(run.test.name, x + 24, y + 32, x + w, y + 70, tocolor(242, 244, 248), 2 * S + 0.4, "default-bold")
    dxDrawText(run.test.howto, x + 24, y + 74 * S + 10, x + w - 24, y + h - 34, tocolor(200, 205, 215), 1.05, "default", "left", "top", true, true)
    local info = ("Par %.1f s   ·   Platino %.1f s   ·   Limite %d s"):format(run.test.par, run.test.platinum or 0, run.test.limit)
    dxDrawText(info, x + 24, y + h - 30, x + w, y + h - 8, tocolor(154, 163, 178), 1, "default")
    dxDrawText("ESPACIO para empezar", x, y + h - 30, x + w - 24, y + h - 8, color(ACCENT), 1, "default-bold", "right")

    if t >= 1 and now - run.introStart > DURATION + 1500 then endIntro() end
end

local function drawCountdown()
    if not countdown then return end
    local elapsed = getTickCount() - countdown.startedAt
    local text, col
    if countdown.go then
        if elapsed > 900 then countdown = nil return end
        text, col = "¡YA!", { 76, 211, 138 }
    else
        local remaining = countdown.n - math.floor(elapsed / 1000)
        if remaining <= 0 then return end
        if remaining ~= countdown.last then
            countdown.last = remaining
            playSoundFrontEnd(44)
        end
        text, col = tostring(remaining), ACCENT
    end
    local pulse = 1 + 0.25 * (1 - (elapsed % 1000) / 1000)
    drawShadowText(text, 0, 0, screenW, screenH * 0.8, color(col), 4 * pulse * S, "pricedown", "center", "center")
end

local function drawHud()
    local test = run.test
    local now = getTickCount()
    local elapsed = run.endTime or (run.startTick and (now - run.startTick) / 1000 or 0)
    local x2 = screenW - 30
    local y = 200 * S

    -- Tiempo (rojo al pasar del par)
    local overPar = elapsed > test.par
    drawShadowText(fmtTime(elapsed), 0, y, x2, y + 50, overPar and tocolor(229, 72, 77) or tocolor(242, 244, 248), 1.6 * S + 0.6, "pricedown", "right", "top")
    y = y + 56 * S + 8
    dxDrawText(("Par %.1f s · Platino %.1f s"):format(test.par, test.platinum or 0), 0, y, x2, y + 20, tocolor(200, 205, 215), 1, "default-bold", "right")
    y = y + 26

    -- Dano del auto
    local health = isElement(run.vehicle) and getElementHealth(run.vehicle) or 0
    local pct = math.max(0, math.min(1, (health - 300) / 700))
    local bw = 180
    dxDrawText("Auto", 0, y, x2 - bw - 10, y + 14, tocolor(200, 205, 215), 1, "default-bold", "right")
    dxDrawRectangle(x2 - bw, y + 2, bw, 10, tocolor(0, 0, 0, 160))
    dxDrawRectangle(x2 - bw, y + 2, bw * pct, 10, pct > 0.6 and tocolor(76, 211, 138) or (pct > 0.3 and color(ACCENT) or tocolor(229, 72, 77)))
    y = y + 24

    local lines = {}
    if #test.cones > 0 then lines[#lines + 1] = ("Conos derribados: %d"):format(run.coneHits) end
    if run.total > 0 then
        local lap = test.laps and test.laps > 1 and math.min(test.laps, math.floor(run.cp / #test.checkpoints) + 1)
        lines[#lines + 1] = ("Puntos: %d / %d"):format(run.cp, run.total) .. (lap and ("   Vuelta %d / %d"):format(lap, test.laps) or "")
    end
    if test.spin then
        lines[#lines + 1] = ("Giro: %d° / %d°"):format(math.min(test.spin, math.floor(math.abs(run.spin))), test.spin)
    end
    if test.box and run.cp >= run.total and (not test.spin or math.abs(run.spin) >= test.spin) then
        lines[#lines + 1] = "Detente dentro de la zona amarilla"
    end
    for _, l in ipairs(lines) do
        drawShadowText(l, 0, y, x2, y + 18, tocolor(242, 244, 248), 1.05, "default-bold", "right", "top")
        y = y + 22
    end

    -- Nombre de la prueba y ayuda
    drawShadowText(test.name, 0, 24 * S + 40, screenW, 0, color(ACCENT), 1.5 * S + 0.5, "default-bold", "center", "top")
    if run.phase == "running" then
        local hint = now - abortAsked < 3000 and "Pulsa F otra vez para abandonar" or "F: abandonar"
        dxDrawText(hint, 0, screenH - 40, screenW - 30, screenH - 20, tocolor(154, 163, 178), 1, "default", "right")
    end

    if warnText and now < warnUntil then
        drawShadowText(warnText, 0, screenH * 0.28, screenW, 0, tocolor(229, 72, 77), 1.6 * S + 0.4, "default-bold", "center", "top")
    end
end

local function drawBanner()
    if not banner then return end
    if getTickCount() > banner.untilTick then banner = nil return end
    local h = 150 * S
    local y = screenH * 0.34
    dxDrawRectangle(0, y, screenW, h, tocolor(0, 0, 0, 170))
    drawShadowText(banner.title, 0, y + 10 * S, screenW, y + h * 0.65, color(banner.color), 3 * S, "pricedown", "center", "center")
    drawShadowText(banner.sub, 0, y + h * 0.62, screenW, y + h - 8, tocolor(242, 244, 248), 1.5 * S + 0.3, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    if run then
        -- Giro acumulado (solo para mostrarlo; el que cuenta es el del servidor)
        if run.phase == "running" and isElement(run.vehicle) then
            local _, _, rz = getElementRotation(run.vehicle)
            if run.lastYaw then run.spin = run.spin + drivingWrap(rz - run.lastYaw) end
            run.lastYaw = rz
        end
        if run.phase == "intro" then
            drawIntro()
        else
            drawBox()
            drawHud()
            drawCountdown()
        end
        drawBanner()
        return
    end
    drawBanner()
    updateNear()
    if isElement(browserGui) then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, s in ipairs(schools) do
        if s.interior == getElementInterior(localPlayer) and s.dimension == getElementDimension(localPlayer) then
            drawBoard(s, px, py, pz)
        end
    end
    if nearSchool then drawPrompt("Pulsa E para hablar con el instructor de la autoescuela") end
end)

----------------------------------------------------------------
-- Teclas
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rp:driving:requestSchools", resourceRoot)

    bindKey(DRIVING.KEY, "down", function()
        if run or not nearSchool or isElement(browserGui) or getElementData(localPlayer, "rp:downed") then return end
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:driving:open", resourceRoot)
    end)

    local function skipIntro()
        if run and run.phase == "intro" and not isChatBoxInputActive() and not isConsoleActive() then endIntro() end
    end
    bindKey("space", "down", skipIntro)
    bindKey("enter", "down", skipIntro)

    bindKey("f", "down", function()
        if not run or run.phase ~= "running" or isChatBoxInputActive() or isConsoleActive() then return end
        local now = getTickCount()
        if now - abortAsked < 3000 then
            abortAsked = 0
            triggerServerEvent("rp:driving:abort", resourceRoot)
        else
            abortAsked = now
        end
    end)
end)

addEventHandler("onClientPlayerWasted", localPlayer, closeUI)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, closeUI)
addEventHandler("onClientResourceStop", resourceRoot, function()
    closeUI()
    if run then setCameraTarget(localPlayer) end
end)
