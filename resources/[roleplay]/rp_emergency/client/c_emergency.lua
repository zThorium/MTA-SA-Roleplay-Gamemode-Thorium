--[[
    rp_emergency / c_emergency.lua
    Menu CEF del 911, punto de aparicion de la ambulancia y movimiento de los
    paramedicos. El servidor decide todo; aqui solo se ejecuta lo que ordena.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

addEvent("rp:emergency:show", true)
addEvent("rp:emergency:spawnRequest", true)
addEvent("rp:emergency:drive", true)
addEvent("rp:emergency:walk", true)
addEvent("rp:emergency:stop", true)
addEvent("rp:emergency:ui:call", false)
addEvent("rp:emergency:ui:close", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function close()
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

addEventHandler("rp:emergency:show", resourceRoot, function(services, busy)
    if type(services) ~= "table" then return end
    open()
    callJS(("RP.show(%s[0], %s)"):format(toJSON(services, true), tostring(busy == true)))
end)

addEventHandler("rp:emergency:ui:call", root, function(id)
    if type(id) ~= "string" then return end
    triggerServerEvent("rp:emergency:call", resourceRoot, id)
    close()
end)

addEventHandler("rp:emergency:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)   -- abatido (rp_injury)
addEventHandler("onClientResourceStop", resourceRoot, close)

----------------------------------------------------------------
-- Ambulancia
----------------------------------------------------------------
addEventHandler("rp:emergency:spawnRequest", resourceRoot, function(callId)
    local x, y, z, rot = pickSpawnPoint()
    triggerServerEvent("rp:emergency:spawn", resourceRoot, callId, x, y, z, rot)
end)

addEventHandler("rp:emergency:drive", resourceRoot, function(callId, vehicle, ped, mode, tx, ty)
    if not isElement(vehicle) or not isElement(ped) then return end
    startAIDriver(callId, vehicle, ped, mode, tonumber(tx), tonumber(ty))
end)

-- Los paramedicos no mueren ni se les puede herir
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:emergency") then cancelEvent() end
end)

----------------------------------------------------------------
-- Caminar de los paramedicos (el servidor corrige si no llegan)
----------------------------------------------------------------
local walking = nil   -- { callId, token, list, started, timer }

local function stopWalking(report)
    if not walking then return end
    local w = walking
    walking = nil
    if isTimer(w.timer) then killTimer(w.timer) end
    for _, o in ipairs(w.list) do
        if isElement(o[1]) then
            for _, k in ipairs({ "forward", "sprint", "walk" }) do setPedControlState(o[1], k, false) end
        end
    end
    if report then triggerServerEvent("rp:emergency:walked", resourceRoot, w.callId, w.token) end
end

-- Corren si estan lejos, caminan al acercarse y rodean lo que les tapa el paso
local function walkTick()
    if not walking then return end
    local now = getTickCount()
    local pending = 0
    for _, o in ipairs(walking.list) do
        local ped, tx, ty = o[1], o[2], o[3]
        if isElement(ped) and isElementStreamedIn(ped) then
            local x, y, z = getElementPosition(ped)
            local d = getDistanceBetweenPoints2D(x, y, tx, ty)
            if d > EMERGENCY.WALK_ARRIVE_DIST then
                pending = pending + 1
                local rot = -math.deg(math.atan2(tx - x, ty - y))
                -- atascado (no avanza): rodea durante un momento hacia un lado
                o.lastX, o.lastY, o.checkAt = o.lastX or x, o.lastY or y, o.checkAt or now + 1200
                if now >= o.checkAt then
                    if getDistanceBetweenPoints2D(x, y, o.lastX, o.lastY) < 0.4 then
                        o.side = (o.side == 60) and -60 or 60
                        o.sideUntil = now + 900
                    end
                    o.lastX, o.lastY, o.checkAt = x, y, now + 1200
                end
                -- algo justo delante (auto, poste, muro): se aparta antes de chocar
                local r = math.rad(rot)
                local fx, fy = -math.sin(r), math.cos(r)
                if d > 2 and not isLineOfSightClear(x, y, z, x + fx * 1.3, y + fy * 1.3, z, true, true, false, true, false, true, false, ped) then
                    o.side = o.side or 60
                    o.sideUntil = now + 600
                end
                if o.sideUntil and now < o.sideUntil then rot = rot + o.side end
                setElementRotation(ped, 0, 0, rot, "default", true)
                setPedControlState(ped, "forward", true)
                local animated = getPedAnimation(ped)
                setPedControlState(ped, "sprint", d > 7 and not animated)
                setPedControlState(ped, "walk", d < 2.5 or (animated and true or false))
            else
                setPedControlState(ped, "forward", false)
                setPedControlState(ped, "sprint", false)
                setPedControlState(ped, "walk", false)
            end
        end
    end
    if pending == 0 or now - walking.started > EMERGENCY.WALK_TIMEOUT * 1000 then stopWalking(true) end
end

addEventHandler("rp:emergency:walk", resourceRoot, function(callId, token, list)
    if type(list) ~= "table" then return end
    stopWalking(false)
    walking = { callId = callId, token = token, list = list, started = getTickCount() }
    walking.timer = setTimer(walkTick, 100, 0)
end)

addEventHandler("rp:emergency:stop", resourceRoot, function(callId)
    if isAIDriving(callId) then stopAIDriver() end
    if walking and walking.callId == callId then stopWalking(false) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopAIDriver()
    stopWalking(false)
end)
