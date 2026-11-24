--[[
    rp_races / client / c_races.lua

    Cliente de carreras: UI CEF (menu rapido, sala, resultados y votacion) + HUD dx
    (posicion, vueltas, tiempos, clasificacion, cuenta atras, aviso DNF, barra de reaparicion).

    Teclas: F5 / /carreras = menu | mantener Retroceso = reaparecer en el ultimo checkpoint
            Y / N = aceptar / rechazar una invitacion
]]

local sw, sh = guiGetScreenSize()
local sc = math.max(0.8, math.min(1.4, sh / 900))

for _, ev in ipairs({ "menu", "lobby", "enter", "left", "close", "count", "env", "envReset", "ghost", "boost", "cp",
                      "hud", "dnf", "results", "votes", "invite" }) do
    addEvent("rp:races:" .. ev, true)
end
for _, ev in ipairs({ "create", "join", "random", "leave", "setting", "invite", "start", "vote", "close" }) do
    addEvent("rp:races:ui:" .. ev, false)
end

local browserGui, browser, ready, pendingJS = nil, nil, false, {}
local active = false          -- dentro de una sala/carrera
local racing = false          -- HUD visible
local hud = nil
local countText, countAt = nil, 0
local dnfUntil = nil
local ghostList = {}
local savedEnv = nil
local invite, inviteUntil = nil, 0
local respawnHeld = nil
local lastPos = nil

----------------------------------------------------------------
-- UI (CEF)
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
end

local function openUI()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
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
end

local function push(fn, data)
    openUI()
    callJS(("RACES.%s(%s[0])"):format(fn, toJSON(data or {}, true)))
end

addEventHandler("rp:races:menu", resourceRoot, function(data) if not active then push("menu", data) end end)
addEventHandler("rp:races:lobby", resourceRoot, function(data) racing, hud = false, nil; push("lobby", data) end)
addEventHandler("rp:races:results", resourceRoot, function(data) push("results", data) end)
addEventHandler("rp:races:votes", resourceRoot, function(counts) callJS(("RACES.votes(%s[0])"):format(toJSON(counts or {}, true))) end)
addEventHandler("rp:races:close", resourceRoot, function() closeUI() racing = true end)

addEventHandler("rp:races:ui:create", root, function(i) triggerServerEvent("rp:races:create", resourceRoot, tonumber(i)) end)
addEventHandler("rp:races:ui:join", root, function(id) triggerServerEvent("rp:races:join", resourceRoot, tonumber(id)) end)
addEventHandler("rp:races:ui:random", root, function() triggerServerEvent("rp:races:random", resourceRoot) end)
addEventHandler("rp:races:ui:leave", root, function() closeUI() triggerServerEvent("rp:races:leave", resourceRoot) end)
addEventHandler("rp:races:ui:setting", root, function(k, v) triggerServerEvent("rp:races:setting", resourceRoot, k, v) end)
addEventHandler("rp:races:ui:invite", root, function(n) triggerServerEvent("rp:races:invite", resourceRoot, n) end)
addEventHandler("rp:races:ui:start", root, function() triggerServerEvent("rp:races:start", resourceRoot) end)
addEventHandler("rp:races:ui:vote", root, function(i)
    i = tonumber(i)
    if i == 0 then closeUI() end
    triggerServerEvent("rp:races:vote", resourceRoot, i)
end)
addEventHandler("rp:races:ui:close", root, function() if not active then closeUI() end end)

----------------------------------------------------------------
-- Entorno de carrera
----------------------------------------------------------------
local function applyGhost()
    for i = 1, #ghostList do
        local a = ghostList[i]
        if isElement(a) then
            for j = i + 1, #ghostList do
                if isElement(ghostList[j]) then setElementCollidableWith(a, ghostList[j], false) end
            end
        end
    end
end

addEventHandler("rp:races:ghost", resourceRoot, function(list) ghostList = list or {} applyGhost() end)
setTimer(function() if active and #ghostList > 0 then applyGhost() end end, 2000, 0)

addEventHandler("rp:races:env", resourceRoot, function(hour, weather)
    if not savedEnv then
        local h, m = getTime()
        savedEnv = { h = h, m = m, w = getWeather(), md = getMinuteDuration() }
    end
    if hour and hour >= 0 then setTime(hour, 0) setMinuteDuration(600000) end
    if weather then setWeather(weather) end
end)

local function resetEnv()
    if not savedEnv then return end
    setMinuteDuration(savedEnv.md or 1000)
    setTime(savedEnv.h, savedEnv.m)
    setWeather(savedEnv.w or 0)
    savedEnv = nil
end
addEventHandler("rp:races:envReset", resourceRoot, resetEnv)

addEventHandler("rp:races:enter", resourceRoot, function()
    active, racing, hud, countText, dnfUntil, ghostList = true, false, nil, nil, nil, {}
    setPedCanBeKnockedOffBike(localPlayer, false)
end)

addEventHandler("rp:races:left", resourceRoot, function()
    active, racing, hud, countText, dnfUntil, ghostList = false, false, nil, nil, nil, {}
    closeUI()
    resetEnv()
    setPedCanBeKnockedOffBike(localPlayer, true)
end)

-- Durante la carrera el piloto no recibe dano de personaje (el vehiculo se repara al reaparecer)
addEventHandler("onClientPlayerDamage", localPlayer, function()
    if active then cancelEvent() end
end)

addEventHandler("rp:races:boost", resourceRoot, function(f)
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer or type(f) ~= "number" then return end
    f = math.max(0.98, math.min(1.02, f))
    local vx, vy, vz = getElementVelocity(v)
    setElementVelocity(v, vx * f, vy * f, vz)
end)

addEventHandler("rp:races:hud", resourceRoot, function(d)
    hud = d
    if d.dnf then dnfUntil = getTickCount() + d.dnf * 1000 else dnfUntil = nil end
end)
addEventHandler("rp:races:dnf", resourceRoot, function(s) dnfUntil = getTickCount() + s * 1000 end)
addEventHandler("rp:races:cp", resourceRoot, function(lap) playSoundFrontEnd(lap and 12 or 43) end)
addEventHandler("rp:races:count", resourceRoot, function(n)
    countText, countAt = n == 0 and "GO!" or tostring(n), getTickCount()
    playSoundFrontEnd(n == 0 and 12 or 5)
end)

addEventHandler("rp:races:invite", resourceRoot, function(d)
    invite, inviteUntil = d, getTickCount() + 25000
    playSoundFrontEnd(1)
end)

----------------------------------------------------------------
-- Teclas
----------------------------------------------------------------
local function openMenu()
    if active or isElement(browserGui) then return end
    triggerServerEvent("rp:races:open", resourceRoot)
end
bindKey("F5", "down", openMenu)

bindKey("backspace", "down", function() if racing then respawnHeld = getTickCount() end end)
bindKey("backspace", "up", function() respawnHeld = nil end)

bindKey("y", "down", function()
    if invite and getTickCount() < inviteUntil and not active then
        invite = nil
        triggerServerEvent("rp:races:acceptInvite", resourceRoot)
    end
end)
bindKey("n", "down", function() if invite then invite = nil end end)

----------------------------------------------------------------
-- HUD
----------------------------------------------------------------
local function fmt(ms)
    if not ms then return "--:--.--" end
    local s = ms / 1000
    return ("%02d:%05.2f"):format(math.floor(s / 60), s % 60)
end

local function text(str, x, y, w, h, color, size, align, shadow)
    local sz = size * sc
    if shadow ~= false then dxDrawText(str, x + 1, y + 1, x + w + 1, y + h + 1, tocolor(0, 0, 0, 200), sz, "default-bold", align or "left", "top") end
    dxDrawText(str, x, y, x + w, y + h, color or tocolor(255, 255, 255, 255), sz, "default-bold", align or "left", "top")
end

addEventHandler("onClientRender", root, function()
    local t = getTickCount()

    if invite and not active then
        if t > inviteUntil then invite = nil else
            local w, h = 420 * sc, 64 * sc
            local x, y = (sw - w) / 2, 90 * sc
            dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 220))
            dxDrawRectangle(x, y, 4 * sc, h, tocolor(245, 165, 36, 255))
            text(invite.from .. " te invita a una carrera", x + 16 * sc, y + 8 * sc, w, 20, nil, 1.1)
            text(invite.track .. "   [Y] aceptar   [N] rechazar", x + 16 * sc, y + 34 * sc, w, 20, tocolor(180, 190, 205, 255), 1.0)
        end
    end

    if not racing then return end

    if hud then
        local x = sw - 270 * sc
        local y = sh * 0.30
        dxDrawRectangle(x - 10 * sc, y - 8 * sc, 260 * sc, 300 * sc, tocolor(10, 12, 18, 150))
        text(("%d"):format(hud.pos or 0), x, y, 90 * sc, 60 * sc, tocolor(245, 165, 36, 255), 4.2)
        text("/ " .. (hud.total or 0), x + 78 * sc, y + 36 * sc, 100 * sc, 30 * sc, tocolor(190, 195, 205, 255), 1.6)
        text(("Vuelta %d/%d"):format(hud.lap or 1, hud.laps or 1), x, y + 70 * sc, 240 * sc, 24 * sc, nil, 1.3)
        text(("Checkpoint %d/%d"):format(hud.cp or 1, hud.cps or 1), x, y + 94 * sc, 240 * sc, 20 * sc, tocolor(190, 195, 205, 255), 1.0)
        text("Tiempo  " .. fmt(hud.elapsed), x, y + 120 * sc, 240 * sc, 20 * sc, nil, 1.15)
        text("Vuelta  " .. fmt(hud.lapTime), x, y + 142 * sc, 240 * sc, 20 * sc, tocolor(190, 195, 205, 255), 1.0)
        text("Mejor   " .. fmt(hud.best), x, y + 162 * sc, 240 * sc, 20 * sc, tocolor(120, 220, 150, 255), 1.0)
        for i, row in ipairs(hud.board or {}) do
            local col = i == hud.pos and tocolor(245, 165, 36, 255) or tocolor(230, 232, 238, 255)
            if row.bot then col = tocolor(170, 178, 190, 255) end
            text(("%d. %s%s"):format(i, row.name, row.finished and "  ✔" or ""), x, y + 190 * sc + (i - 1) * 18 * sc, 240 * sc, 18 * sc, col, 0.95)
        end
    end

    if countText then
        local age = t - countAt
        if age > 1300 then countText = nil else
            local a = 255 - math.min(255, math.max(0, (age - 700) / 600 * 255))
            local size = 7 * sc * (1 + (age % 1000) / 4000)
            dxDrawText(countText, 0, sh * 0.2, sw, sh * 0.5, tocolor(245, 165, 36, a), size, "pricedown", "center", "center")
        end
    end

    if dnfUntil then
        local left = math.max(0, math.ceil((dnfUntil - t) / 1000))
        local w = 360 * sc
        dxDrawRectangle((sw - w) / 2, 60 * sc, w, 34 * sc, tocolor(170, 40, 40, 200))
        text(("Tiempo para terminar: %ds"):format(left), (sw - w) / 2, 68 * sc, w, 20, nil, 1.2, "center")
    end

    if hud and hud.finished then
        text("¡Terminaste! Espera los resultados...", 0, sh * 0.12, sw, 30, tocolor(120, 220, 150, 255), 1.6, "center")
    end

    if respawnHeld then
        local p = math.min(1, (t - respawnHeld) / RACE.RESPAWN_HOLD)
        local w, h = 220 * sc, 10 * sc
        local x, y = (sw - w) / 2, sh * 0.82
        text("Reapareciendo...", x, y - 24 * sc, w, 20, nil, 1.1, "center")
        dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 180))
        dxDrawRectangle(x, y, w * p, h, tocolor(245, 165, 36, 255))
        if p >= 1 then
            respawnHeld = nil
            triggerServerEvent("rp:races:respawn", resourceRoot)
        end
    else
        text("Mantén Retroceso: reaparecer en el último checkpoint", 0, sh - 30 * sc, sw, 20, tocolor(190, 195, 205, 200), 0.85, "center")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    resetEnv()
    setPedCanBeKnockedOffBike(localPlayer, true)
end)

----------------------------------------------------------------
-- Control de los pilotos IA: el servidor decide, este cliente (sincronizador del ped) aplica
----------------------------------------------------------------
addEvent("rp:races:aiCtl", true)
addEventHandler("rp:races:aiCtl", resourceRoot, function(list)
    for _, c in ipairs(list or {}) do
        local ped, steer, acc, brake, hand = c[1], c[2], c[3], c[4], c[5]
        if isElement(ped) then
            setPedControlState(ped, "vehicle_left", false)
            setPedControlState(ped, "vehicle_right", false)
            if steer > 0.05 then setPedAnalogControlState(ped, "vehicle_left", steer)
            elseif steer < -0.05 then setPedAnalogControlState(ped, "vehicle_right", -steer) end
            if acc > 0 then setPedAnalogControlState(ped, "accelerate", acc) else setPedControlState(ped, "accelerate", false) end
            setPedControlState(ped, "brake_reverse", brake == 1)
            setPedControlState(ped, "handbrake", hand == 1)
        end
    end
end)
