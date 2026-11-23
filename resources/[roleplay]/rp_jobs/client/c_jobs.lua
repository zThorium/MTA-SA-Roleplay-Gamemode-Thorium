--[[
    rp_jobs / c_jobs.lua

    - Marcadores y blips de las sedes de trabajo y los puntos de venta (E para abrir).
    - Punto actual del turno (lo manda el servidor): marcador, blip, aviso "Pulsa E" y
      aviso al servidor al llegar. El servidor vuelve a comprobar la posición.
    - HUD del turno (izquierda), objetos que solo ve el trabajador (árboles, rocas, bolsas)
      y el navegador CEF que muestra minijuegos, panel de la sede, punto de venta y resumen.
]]

local screenW, screenH = guiGetScreenSize()
local sc = math.max(0.75, math.min(1.3, screenH / 900))

local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local uiMode = nil            -- "game" | "panel" | "market" | "summary"
local gameToken = nil
local currentHQ, currentMarket = nil, nil

local wp, wpMarker, wpBlip, wpSent, wpSnapped = nil, nil, nil, 0, false
local hud = nil
local props = {}              -- [key] = object
local staticPoints = {}       -- { kind = "hq"|"market", id, x, y, z, marker, name }
local nearPoint = nil
local gps = nil               -- { marker, blip, x, y }

addEvent("rp:jobs:wp", true)
addEvent("rp:jobs:hud", true)
addEvent("rp:jobs:props", true)
addEvent("rp:jobs:propFx", true)
addEvent("rp:jobs:game", true)
addEvent("rp:jobs:closeGame", true)
addEvent("rp:jobs:panel", true)
addEvent("rp:jobs:closePanel", true)
addEvent("rp:jobs:market", true)
addEvent("rp:jobs:summary", true)
addEvent("rp:jobs:sound", true)
addEvent("rp:jobs:gps", true)

addEvent("rp:jobs:ui:result", false)
addEvent("rp:jobs:ui:close", false)
addEvent("rp:jobs:ui:hq", false)
addEvent("rp:jobs:ui:sell", false)

local function isBlocked()
    return isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or getElementData(localPlayer, "rp:downed")
end

----------------------------------------------------------------
-- Navegador CEF
----------------------------------------------------------------
local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function closeUI()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    uiMode, currentHQ, currentMarket = nil, nil, nil
    showCursor(false)
    guiSetInputEnabled(false)
end

local function openUI(mode)
    uiMode = mode
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

local function cancelGame()
    if gameToken then
        triggerServerEvent("rp:jobs:gameResult", resourceRoot, gameToken, { cancel = true })
        gameToken = nil
    end
end

----------------------------------------------------------------
-- Acciones en el mundo (sin CEF): nombres que empiezan por "_"
--   _hold  mantener E hasta llenar la barra (ms)          -> { done = true }
--   _tap   pulsar E `taps` veces (golpes de hacha, pico)  -> { done = true }
--   _bite  esperar la picada y pulsar E a tiempo          -> { caught, reason }
-- Alejarse del sitio, morir o pulsar Retroceso cancela.
----------------------------------------------------------------
local action = nil   -- { name, params, token, progress, x, y, z, started, lastTap, biteAt, state }

local function finishAction(result)
    if not action then return end
    triggerServerEvent("rp:jobs:gameResult", resourceRoot, action.token, result)
    action = nil
end

local function startAction(name, params, token)
    local x, y, z = getElementPosition(localPlayer)
    action = { name = name, params = params or {}, token = token, progress = 0, x = x, y = y, z = z,
        started = getTickCount(), lastTap = 0 }
    if name == "_bite" then
        action.biteAt = getTickCount() + math.random(params.waitMin or 2500, params.waitMax or 6500)
        action.fakes = {}
        for i = 1, (params.fakes or 0) do
            action.fakes[i] = action.started + math.random(800, math.max(900, action.biteAt - action.started - 400))
        end
    end
end

local function actionUse()
    if not action then return false end
    local now = getTickCount()
    if action.name == "_tap" then
        if now - action.lastTap < 260 then return true end
        action.lastTap = now
        action.progress = action.progress + 1 / math.max(1, action.params.taps or 6)
        playSoundFrontEnd(41)
        if action.progress >= 0.999 then finishAction({ done = true }) end
    elseif action.name == "_bite" then
        if now < action.biteAt then finishAction({ caught = false, reason = "early" })
        else finishAction({ caught = true }) end
    end
    return true
end

local function drawAction()
    local now = getTickCount()
    local px, py = getElementPosition(localPlayer)
    if (px - action.x) ^ 2 + (py - action.y) ^ 2 > 3.5 * 3.5 or getKeyState("backspace") then
        return finishAction({ cancel = true })
    end
    local p = action.params
    local text, frac, color = p.text or "", action.progress, tocolor(245, 165, 36)
    if action.name == "_hold" then
        if getKeyState("e") and not isBlocked() then
            action.progress = math.min(1, action.progress + (getTickCount() - (action.lastFrame or now)) / math.max(300, p.ms or 3000))
        end
        action.lastFrame = now
        frac = action.progress
        text = (p.text or "Trabajando") .. "  ·  mantén E"
        if frac >= 1 then return finishAction({ done = true }) end
    elseif action.name == "_tap" then
        text = (p.text or "Trabajando") .. "  ·  pulsa E"
    elseif action.name == "_bite" then
        if now >= action.biteAt + (p.window or 900) then return finishAction({ caught = false, reason = "late" }) end
        local fake = false
        for _, t in ipairs(action.fakes) do if now >= t and now < t + 250 then fake = true end end
        if now >= action.biteAt then
            text, color, frac = "¡PICA!  Pulsa E", tocolor(76, 211, 138), 1 - (now - action.biteAt) / (p.window or 900)
        else
            text, frac = fake and "...¿algo se mueve?" or "Esperando la picada...", 0
            color = fake and tocolor(255, 200, 80) or tocolor(154, 163, 178)
        end
    end
    local w, h = 360 * sc, 46 * sc
    local x, y = (screenW - w) / 2, screenH * 0.70
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 215))
    dxDrawText(text, x, y + 4 * sc, x + w, y + 28 * sc, tocolor(242, 244, 248), 1.1 * sc, "default-bold", "center", "center")
    dxDrawRectangle(x + 12 * sc, y + h - 13 * sc, w - 24 * sc, 6 * sc, tocolor(255, 255, 255, 35))
    dxDrawRectangle(x + 12 * sc, y + h - 13 * sc, (w - 24 * sc) * math.max(0, math.min(1, frac)), 6 * sc, color)
end

addEventHandler("rp:jobs:game", resourceRoot, function(name, params, token)
    if type(name) == "string" and name:sub(1, 1) == "_" then return startAction(name, params, token) end
    gameToken = token
    openUI("game")
    callJS(("RP.game(%s, %s[0])"):format(toJSON(name), toJSON(params or {}, true)))
end)

addEventHandler("rp:jobs:closeGame", resourceRoot, function()
    gameToken, action = nil, nil
    if uiMode == "game" then closeUI() end
end)

addEventHandler("rp:jobs:ui:result", root, function(json)
    if type(json) ~= "string" or #json > 4000 or not gameToken then return end
    local result = fromJSON(json)
    if type(result) ~= "table" then result = { fail = true } end
    triggerServerEvent("rp:jobs:gameResult", resourceRoot, gameToken, result)
    gameToken = nil
    closeUI()
end)

addEventHandler("rp:jobs:ui:close", root, function()
    if uiMode == "game" then cancelGame() end
    closeUI()
end)

addEventHandler("rp:jobs:panel", resourceRoot, function(data)
    if uiMode == "game" then return end
    currentHQ = data and data.job and data.job.id
    openUI("panel")
    callJS(("RP.panel(%s[0])"):format(toJSON(data or {}, true)))
end)

addEventHandler("rp:jobs:closePanel", resourceRoot, function()
    if uiMode == "panel" then closeUI() end
end)

addEventHandler("rp:jobs:ui:hq", root, function(action, option)
    if not currentHQ or type(action) ~= "string" then return end
    triggerServerEvent("rp:jobs:hqAction", resourceRoot, currentHQ, action, type(option) == "string" and option or nil)
end)

addEventHandler("rp:jobs:market", resourceRoot, function(data)
    if uiMode == "game" then return end
    currentMarket = data and data.id
    openUI("market")
    callJS(("RP.market(%s[0])"):format(toJSON(data or {}, true)))
end)

addEventHandler("rp:jobs:ui:sell", root, function(itemId, amount)
    amount = tonumber(amount)
    if currentMarket and type(itemId) == "string" and amount then
        triggerServerEvent("rp:jobs:sell", resourceRoot, currentMarket, itemId, amount)
    end
end)

addEventHandler("rp:jobs:summary", resourceRoot, function(data)
    if uiMode == "game" then closeUI() end
    openUI("summary")
    callJS(("RP.summary(%s[0])"):format(toJSON(data or {}, true)))
end)

local SOUNDS = { trash = 37, wood = 4, timber = 4, rock = 4, blast = 46 }
addEventHandler("rp:jobs:sound", resourceRoot, function(name)
    if SOUNDS[name] then playSoundFrontEnd(SOUNDS[name]) end
end)

----------------------------------------------------------------
-- Suelo: ajusta una Z aproximada a la real cuando la zona está cargada
----------------------------------------------------------------
local function groundZ(x, y, z, above)
    local gz = getGroundPosition(x, y, z + (above or 3))
    if gz and gz ~= 0 and math.abs(gz - z) < 60 then return gz end
    return nil
end

----------------------------------------------------------------
-- Punto del turno
----------------------------------------------------------------
local function clearWaypoint()
    if isElement(wpMarker) then destroyElement(wpMarker) end
    if isElement(wpBlip) then destroyElement(wpBlip) end
    wp, wpMarker, wpBlip, wpSnapped = nil, nil, nil, false
end

local function wpPosition()
    if not wp then return end
    if wp.attach == "vehicle" then
        local v = wp.vehicle
        if not isElement(v) then return end
        local m = getElementMatrix(v)
        local o = wp.offset or {}
        local ox, oy, oz = o[1] or 0, o[2] or 0, o[3] or 0
        local x = ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1]
        local y = ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2]
        local z = ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
        return x, y, z - 0.9
    end
    return wp.x, wp.y, wp.z
end

local MARKER_TYPES = { checkpoint = "checkpoint", cylinder = "cylinder", corona = "corona", ring = "ring" }

addEventHandler("rp:jobs:wp", resourceRoot, function(data)
    clearWaypoint()
    if type(data) ~= "table" then return end
    wp, wpSent = data, 0
    local c = data.color or { 245, 165, 36 }
    local mtype = MARKER_TYPES[data.marker or "cylinder"]
    local x, y, z = wpPosition()
    x, y, z = x or data.x or 0, y or data.y or 0, z or data.z or 0
    if mtype then
        local size = data.small and 0.6 or (mtype == "checkpoint" and 4 or (mtype == "ring" and 6 or 1.4))
        wpMarker = createMarker(x, y, z - (mtype == "cylinder" and 0.95 or 0), mtype, size, c[1], c[2], c[3], mtype == "corona" and 160 or 120)
    end
    if data.blip ~= false and data.x then
        wpBlip = createBlip(data.x, data.y, data.z or 0, 0, 3, c[1], c[2], c[3], 255, 10, 99999)
    end
end)

local function inRange()
    if not wp then return false end
    local x, y, z = wpPosition()
    if not x then return false end
    local px, py, pz = getElementPosition(localPlayer)
    if (px - x) ^ 2 + (py - y) ^ 2 > wp.r * wp.r then return false end
    if not wp.flat and z and math.abs(pz - z) > 8 then return false end
    local veh = getPedOccupiedVehicle(localPlayer)
    if wp.mode == "foot" and veh then return false end
    if wp.mode == "drive" and (not veh or getVehicleController(veh) ~= localPlayer or not getElementData(veh, "rp:jobVehicle")) then return false end
    return true
end

local function sendReach()
    local now = getTickCount()
    if not wp or now - wpSent < 1200 then return end
    wpSent = now
    triggerServerEvent("rp:jobs:reach", resourceRoot, wp.id)
end

-- Comprobación periódica: puntos de llegada, ajuste al suelo y GPS
setTimer(function()
    if wp then
        if wp.act == "enter" and inRange() then sendReach() end
        if not wpSnapped and wp.x and wp.attach ~= "vehicle" then
            local px, py = getElementPosition(localPlayer)
            if (px - wp.x) ^ 2 + (py - wp.y) ^ 2 < 250 * 250 then
                local gz = groundZ(wp.x, wp.y, wp.z or 0, wp.flat and 80 or 4)
                if gz then
                    wp.z, wpSnapped = gz, true
                    if isElement(wpMarker) then
                        local mt = getMarkerType(wpMarker)
                        setElementPosition(wpMarker, wp.x, wp.y, gz + (mt == "corona" and 0.4 or (mt == "cylinder" and 0.05 or 0)))
                    end
                end
            end
        end
    end
    if gps then
        local px, py = getElementPosition(localPlayer)
        if (px - gps.x) ^ 2 + (py - gps.y) ^ 2 < 15 * 15 then
            if isElement(gps.marker) then destroyElement(gps.marker) end
            if isElement(gps.blip) then destroyElement(gps.blip) end
            gps = nil
        end
    end
end, 250, 0)

----------------------------------------------------------------
-- Objetos del trabajo (solo los ve este jugador)
----------------------------------------------------------------
local function clearProps()
    for _, o in pairs(props) do if isElement(o) then destroyElement(o) end end
    props = {}
end

addEventHandler("rp:jobs:props", resourceRoot, function(list)
    clearProps()
    for _, p in ipairs(list or {}) do
        local o = createObject(p.model, p.x, p.y, p.z, p.rx or 0, p.ry or 0, p.rz or 0)
        if o then
            props[p.key] = o
            if p.snap then setElementData(o, "rp:snap", p.snapHeight or 3, false) end
        end
    end
end)

addEventHandler("rp:jobs:propFx", resourceRoot, function(key, fx, arg)
    local o = props[key]
    if not isElement(o) then return end
    if fx == "remove" then
        destroyElement(o)
        props[key] = nil
    elseif fx == "fall" then
        local x, y, z = getElementPosition(o)
        setElementRotation(o, 0, 0, -(tonumber(arg) or 0))
        moveObject(o, 1800, x, y, z + 0.3, -85, 0, 0, "OutBounce")
    end
end)

-- Ajuste al suelo de los objetos cuando la zona carga
setTimer(function()
    local px, py = getElementPosition(localPlayer)
    for _, o in pairs(props) do
        local above = isElement(o) and getElementData(o, "rp:snap")
        if above then
            local x, y, z = getElementPosition(o)
            if (px - x) ^ 2 + (py - y) ^ 2 < 200 * 200 then
                local gz = groundZ(x, y, z, above)
                if gz then
                    setElementPosition(o, x, y, gz)
                    setElementData(o, "rp:snap", false, false)
                end
            end
        end
    end
end, 1000, 0)

----------------------------------------------------------------
-- Sedes y puntos de venta
----------------------------------------------------------------
local function createStaticPoints()
    for _, job in ipairs(JOBS) do
        local h, c = job.hq, job.color
        local m = createMarker(h.x, h.y, h.z - 1, "cylinder", 1.3, c[1], c[2], c[3], 110)
        setElementInterior(m, h.interior or 0)
        setElementDimension(m, h.dimension or 0)
        local b = createBlip(h.x, h.y, h.z, 56, 2, c[1], c[2], c[3], 255, 0, 300)
        staticPoints[#staticPoints + 1] = { kind = "hq", id = job.id, x = h.x, y = h.y, z = h.z, marker = m, blip = b,
            name = job.icon .. " " .. job.name, job = job }
    end
    for _, mk in ipairs(MARKETS) do
        local m = createMarker(mk.x, mk.y, mk.z - 1, "cylinder", 1.3, 245, 165, 36, 110)
        local b = createBlip(mk.x, mk.y, mk.z, 52, 2, 245, 165, 36, 255, 0, 300)
        staticPoints[#staticPoints + 1] = { kind = "market", id = mk.id, x = mk.x, y = mk.y, z = mk.z, marker = m, blip = b,
            name = mk.icon .. " " .. mk.name }
    end
end

-- Blip de la sede propia visible desde todo el mapa
local function refreshOwnBlip()
    local mine = getElementData(localPlayer, "rp:job")
    for _, p in ipairs(staticPoints) do
        if p.kind == "hq" and isElement(p.blip) then
            setBlipVisibleDistance(p.blip, p.id == mine and 99999 or 300)
            setBlipSize(p.blip, p.id == mine and 3 or 2)
        end
    end
end

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "rp:job" then refreshOwnBlip() end
end)

setTimer(function()
    nearPoint = nil
    if isElement(browserGui) then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, p in ipairs(staticPoints) do
        if (px - p.x) ^ 2 + (py - p.y) ^ 2 < 2.2 * 2.2 and math.abs(pz - p.z) < 3 and not getPedOccupiedVehicle(localPlayer) then
            nearPoint = p
            return
        end
    end
end, 300, 0)

addEventHandler("rp:jobs:gps", resourceRoot, function(jobId)
    local job = JOBS_BY_ID[jobId]
    if not job then return end
    if gps then
        if isElement(gps.marker) then destroyElement(gps.marker) end
        if isElement(gps.blip) then destroyElement(gps.blip) end
    end
    local c = job.color
    gps = { x = job.hq.x, y = job.hq.y,
        marker = createMarker(job.hq.x, job.hq.y, job.hq.z + 1.5, "arrow", 1.2, c[1], c[2], c[3], 200),
        blip = createBlip(job.hq.x, job.hq.y, job.hq.z, 41, 2, c[1], c[2], c[3], 255, 20, 99999) }
end)

----------------------------------------------------------------
-- Tecla E
----------------------------------------------------------------
local function onUse()
    if isElement(browserGui) or isBlocked() then return end
    if actionUse() then return end
    if wp and wp.act == "press" and inRange() then return sendReach() end
    if nearPoint then
        if nearPoint.kind == "hq" then triggerServerEvent("rp:jobs:openHQ", resourceRoot, nearPoint.id)
        else triggerServerEvent("rp:jobs:openMarket", resourceRoot, nearPoint.id) end
    end
end

----------------------------------------------------------------
-- Dibujo: avisos y HUD del turno
----------------------------------------------------------------
local function prompt(text)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end

local function drawHud()
    local job = JOBS_BY_ID[hud.job]
    if not job then return end
    local c = job.color
    local w, x, y = 300 * sc, 20 * sc, screenH * 0.30
    local h = 104 * sc
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 205))
    dxDrawRectangle(x, y, 4 * sc, h, tocolor(c[1], c[2], c[3], 255))
    local tx = x + 14 * sc
    dxDrawText(job.icon .. "  " .. job.name:upper(), tx, y + 8 * sc, x + w - 10 * sc, 0, tocolor(c[1], c[2], c[3]), 1.0 * sc, "default-bold")
    dxDrawText(("Nv %d"):format(hud.level), tx, y + 8 * sc, x + w - 12 * sc, 0, tocolor(154, 163, 178), 1.0 * sc, "default-bold", "right")
    dxDrawText(hud.task or "", tx, y + 28 * sc, x + w - 10 * sc, y + 62 * sc, tocolor(242, 244, 248), 1.05 * sc, "default-bold", "left", "top", true, true)
    dxDrawText(hud.extra or "", tx, y + 64 * sc, x + w - 10 * sc, 0, tocolor(154, 163, 178), 0.95 * sc, "default")
    dxDrawText(("$%d en este turno"):format(hud.earned or 0), tx, y + 64 * sc, x + w - 12 * sc, 0, tocolor(76, 211, 138), 0.95 * sc, "default-bold", "right")
    -- barra de experiencia
    local barY = y + h - 12 * sc
    local p = 1
    if hud.nextXP then p = (hud.xp - hud.levelXP) / math.max(1, hud.nextXP - hud.levelXP) end
    dxDrawRectangle(tx, barY, w - 28 * sc, 4 * sc, tocolor(255, 255, 255, 30))
    dxDrawRectangle(tx, barY, (w - 28 * sc) * math.max(0, math.min(1, p)), 4 * sc, tocolor(c[1], c[2], c[3], 230))
end

addEventHandler("onClientRender", root, function()
    if hud and not isElement(browserGui) then drawHud() end
    if isElement(browserGui) or getElementData(localPlayer, "rp:downed") then return end
    if action then return drawAction() end
    -- marcador unido al vehículo (atrás del camión)
    if wp and wp.attach == "vehicle" and isElement(wpMarker) then
        local x, y, z = wpPosition()
        if x then setElementPosition(wpMarker, x, y, z) end
    end
    if wp and wp.act == "press" and inRange() then
        return prompt(wp.text or "Pulsa E")
    end
    if nearPoint then
        prompt(nearPoint.kind == "hq" and ("Pulsa E: %s"):format(nearPoint.name) or ("Pulsa E para vender en %s"):format(nearPoint.name))
    end
end)

addEventHandler("rp:jobs:hud", resourceRoot, function(data)
    hud = type(data) == "table" and data or nil
    if not hud then clearWaypoint() end
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    createStaticPoints()
    refreshOwnBlip()
    bindKey("e", "down", onUse)
end)

local function onDown()
    if uiMode == "game" then cancelGame() end
    if action then finishAction({ cancel = true }) end
    closeUI()
end
addEventHandler("onClientPlayerWasted", localPlayer, onDown)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, onDown)
addEventHandler("onClientResourceStop", resourceRoot, function()
    closeUI()
    clearProps()
end)
