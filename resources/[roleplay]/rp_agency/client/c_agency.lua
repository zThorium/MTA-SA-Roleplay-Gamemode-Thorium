--[[
    rp_agency / c_agency.lua
    - Monta la sala: mostradores, sillas, ordenadores, dispensador rojo y las
      trabajadoras (peds locales, para poder animarlas en la cinematica).
    - Avisos "Pulsa E" en la puerta, la salida y el dispensador.
    - HUD de turnos arriba a la derecha (numero que se atiende y el tuyo).
    - Llamada a tu turno: sonido, cartel y flecha sobre el mostrador.
    - Alerta al intentar salir con turno.
    - Vista del dispensador y de la tarjeta del DNI (CEF).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))

local inside = false
local serving, waiting, mine = {}, 0, nil
local callInfo = nil          -- { counter, name, code, seat, at }
local callMarker = nil
local leaveWarnUntil = 0
local dispenserOpen, dispenserTimeout = false, nil
local cardOpen = false
local objects, clerks = {}, {}
local lastE = 0

addEvent("rp:agency:inside", true)
addEvent("rp:agency:state", true)
addEvent("rp:agency:ticket", true)
addEvent("rp:agency:ticketLost", true)
addEvent("rp:agency:called", true)
addEvent("rp:agency:chime", true)
addEvent("rp:agency:confirmLeave", true)
addEvent("rp:agency:showCard", true)
addEvent("rp:agency:ui:ticket", false)
addEvent("rp:agency:ui:close", false)

local COLORS = {
    panel = tocolor(12, 14, 20, 210),
    text = tocolor(242, 244, 248),
    muted = tocolor(154, 163, 178),
    accent = tocolor(245, 165, 36),
    red = tocolor(229, 57, 53),
    green = tocolor(76, 211, 138),
}

function agencyIsInside()
    return getElementInterior(localPlayer) == AGENCY.INTERIOR and getElementDimension(localPlayer) == AGENCY.DIMENSION
end

function agencyClerk(i)
    return clerks[i]
end

local function playSfx(name, volume)
    local snd = playSound("sounds/" .. name .. ".wav")
    if snd and volume then setSoundVolume(snd, volume) end
    return snd
end
agencyPlaySfx = playSfx

----------------------------------------------------------------
-- Sala
----------------------------------------------------------------
local function place(model, x, y, z, rot, noCollision)
    local o = createObject(model, x, y, z, 0, 0, rot or 0)
    if not o then return nil end
    setElementInterior(o, AGENCY.INTERIOR)
    setElementDimension(o, AGENCY.DIMENSION)
    if noCollision then setElementCollisionsEnabled(o, false) end
    objects[#objects + 1] = o
    return o
end

-- Coloca a una trabajadora sentada en su puesto (tambien se usa tras la cinematica)
function agencyResetClerk(i)
    local ped = clerks[i]
    if not isElement(ped) then return end
    local c = agencyCounterPoints(i).clerk
    setElementAlpha(ped, 255)
    setPedControlState(ped, "forwards", false)
    setPedControlState(ped, "walk", false)
    setElementPosition(ped, c.x, c.y, c.z)
    setElementRotation(ped, 0, 0, c.rot, "default", true)
    setPedAnimation(ped, "INT_OFFICE", "OFF_Sit_Type_Loop", -1, true, false, false, false)
end

local function buildRoom()
    local floor = AGENCY.ORIGIN.z - 1
    for i, counter in ipairs(AGENCY.COUNTERS) do
        local p = agencyCounterPoints(i)
        local fx, fy = p.clerk.x - p.seat.x, p.clerk.y - p.seat.y
        local len = math.sqrt(fx * fx + fy * fy)
        fx, fy = fx / len, fy / len
        -- mesa entre los dos, ordenador del lado de la trabajadora, sillas sin colision
        place(2165, p.desk.x, p.desk.y, floor, p.desk.rot)
        place(2190, p.desk.x + fx * 0.25, p.desk.y + fy * 0.25, floor + 0.78, p.clerk.rot)
        place(1714, p.seat.x - fx * 0.15, p.seat.y - fy * 0.15, floor, p.seat.rot + 180, true)
        place(1714, p.clerk.x + fx * 0.15, p.clerk.y + fy * 0.15, floor, p.clerk.rot + 180, true)

        local ped = createPed(counter.clerk.skin or 150, p.clerk.x, p.clerk.y, p.clerk.z, p.clerk.rot)
        if ped then
            setElementInterior(ped, AGENCY.INTERIOR)
            setElementDimension(ped, AGENCY.DIMENSION)
            setElementData(ped, "rp:agency:clerk", true, false)
            clerks[i] = ped
            agencyResetClerk(i)
        end
    end
    -- Dispensador: el extintor rojo de GTA hace de maquina de turnos sobre un poste
    local d = AGENCY.DISPENSER
    local dx, dy = agencyPoint(d.ox, d.oy)
    place(1215, dx, dy, floor, 0)
    place(2690, dx, dy, floor + 1.05, (AGENCY.ORIGIN.rot + d.face) % 360)
end

local function destroyRoom()
    for _, o in ipairs(objects) do if isElement(o) then destroyElement(o) end end
    for _, p in pairs(clerks) do if isElement(p) then destroyElement(p) end end
    objects, clerks = {}, {}
end

addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:agency:clerk") then cancelEvent() end
end)

----------------------------------------------------------------
-- Puntos de interaccion
----------------------------------------------------------------
local function nearPoint(x, y, z, dist)
    local px, py, pz = getElementPosition(localPlayer)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= dist
end

local function exitPoint()
    local x, y = agencyPoint(AGENCY.EXIT_OFFSET.ox, AGENCY.EXIT_OFFSET.oy)
    return x, y, AGENCY.ORIGIN.z
end

local function dispenserPoint()
    local x, y = agencyPoint(AGENCY.DISPENSER.ox, AGENCY.DISPENSER.oy)
    return x, y, AGENCY.ORIGIN.z
end

local function currentSpot()
    if isPedInVehicle(localPlayer) then return nil end
    if agencyIsInside() then
        local ex, ey, ez = exitPoint()
        if nearPoint(ex, ey, ez, AGENCY.DOOR_DISTANCE) then return "exit", ex, ey, ez end
        local dx, dy, dz = dispenserPoint()
        if nearPoint(dx, dy, dz, AGENCY.USE_DISTANCE) then return "dispenser", dx, dy, dz end
    elseif getElementInterior(localPlayer) == 0 and getElementDimension(localPlayer) == 0 then
        local e = AGENCY.ENTRANCE
        if nearPoint(e.x, e.y, e.z, AGENCY.DOOR_DISTANCE) then return "entrance", e.x, e.y, e.z end
    end
    return nil
end

local function blocked()
    return isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
        or getElementData(localPlayer, "rp:downed") or agencyInService()
end

local function openDispenser()
    if dispenserOpen or uiIsOpen() then return end
    dispenserOpen = true
    uiOpen(true)
    uiCall(("RP.dispenser(%s, %s)"):format(jsString(AGENCY.NAME), mine and jsString(mine.code) or "null"))
end

local function closeDispenser()
    if not dispenserOpen then return end
    dispenserOpen = false
    if isTimer(dispenserTimeout) then killTimer(dispenserTimeout) end
    uiClose()
end

local function onE()
    if blocked() then return end
    if getTickCount() - lastE < 600 then return end
    lastE = getTickCount()
    local spot = currentSpot()
    if spot == "entrance" then
        triggerServerEvent("rp:agency:door", resourceRoot, false)
    elseif spot == "exit" then
        local confirm = mine ~= nil and getTickCount() < leaveWarnUntil
        triggerServerEvent("rp:agency:door", resourceRoot, confirm)
    elseif spot == "dispenser" then
        if mine then
            return exports.rp_notify:notify(("Ya tienes el turno %s. Espera a que te llamen."):format(mine.code), "info")
        end
        openDispenser()
    end
end

addEventHandler("rp:agency:ui:ticket", root, function(reason)
    if not dispenserOpen or type(reason) ~= "string" or not AGENCY.REASONS[reason] then return end
    triggerServerEvent("rp:agency:takeTicket", resourceRoot, reason)
    -- si el servidor lo rechaza (aviso por rp_notify) no llega el ticket: cerrar igual
    dispenserTimeout = setTimer(closeDispenser, 2500, 1)
end)

addEventHandler("rp:agency:ui:close", root, function()
    if dispenserOpen then closeDispenser() end
    if cardOpen then cardOpen = false uiClose() end
end)

addEventHandler("rp:agency:ticket", resourceRoot, function(code, reason, ahead)
    if isTimer(dispenserTimeout) then killTimer(dispenserTimeout) end
    playSfx("ticket")
    if dispenserOpen then
        uiCall(("RP.ticketOut(%s, %s, %d)"):format(jsString(code), jsString(AGENCY.REASONS[reason].label), tonumber(ahead) or 0))
        dispenserTimeout = setTimer(closeDispenser, 3600, 1)
    end
    mine = { code = code, reason = reason, ahead = ahead }
end)

----------------------------------------------------------------
-- Turnos
----------------------------------------------------------------
local function clearCall()
    callInfo = nil
    if isElement(callMarker) then destroyElement(callMarker) end
    callMarker = nil
end

addEventHandler("rp:agency:state", resourceRoot, function(srv, count, my)
    serving, waiting, mine = srv or {}, tonumber(count) or 0, my
    if not mine or mine.state ~= "called" then clearCall() end
end)

addEventHandler("rp:agency:ticketLost", resourceRoot, function(reason)
    mine = nil
    clearCall()
    if dispenserOpen then closeDispenser() end
    if reason and reason ~= "" then exports.rp_notify:notify(reason, "warning", 6000) end
end)

addEventHandler("rp:agency:called", resourceRoot, function(i, name, code, seat)
    clearCall()
    callInfo = { counter = i, name = name, code = code, seat = seat, at = getTickCount() }
    callMarker = createMarker(seat.x, seat.y, seat.z + 1.4, "arrow", 0.6, 245, 165, 36, 200)
    if callMarker then
        setElementInterior(callMarker, AGENCY.INTERIOR)
        setElementDimension(callMarker, AGENCY.DIMENSION)
    end
    playSfx("call")
end)

addEventHandler("rp:agency:chime", resourceRoot, function()
    playSfx("call", 0.45)
end)

addEventHandler("rp:agency:confirmLeave", resourceRoot, function()
    leaveWarnUntil = getTickCount() + 6000
    playSfx("warn", 0.8)
end)

addEventHandler("rp:agency:inside", resourceRoot, function(state)
    inside = state
    if not state then
        serving, waiting, mine = {}, 0, nil
        clearCall()
        closeDispenser()
    end
end)

function agencyClearCall() clearCall() end

----------------------------------------------------------------
-- Tarjeta del DNI
----------------------------------------------------------------
addEventHandler("rp:agency:showCard", resourceRoot, function(card, ownerName)
    if agencyInService() or dispenserOpen then return end
    cardOpen = true
    uiOpen(true)
    uiCall(("RP.card(%s, %s)"):format(jsJSON(card), ownerName and jsString(ownerName) or "null"))
end)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function shadowText(text, x1, y1, x2, y2, color, scale, font, ax, ay)
    dxDrawText(text, x1 + 1, y1 + 1, x2 + 1, y2 + 1, tocolor(0, 0, 0, 170), scale, font, ax, ay)
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, ax, ay)
end

local function prompt3D(x, y, z, text)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.35)
    if not sx then return end
    local w = dxGetTextWidth(text, 1.0 * s, "default-bold") + 24 * s
    local h = 28 * s
    dxDrawRectangle(sx - w / 2, sy - h / 2, w, h, COLORS.panel)
    dxDrawRectangle(sx - w / 2, sy + h / 2 - 2, w, 2, COLORS.accent)
    dxDrawText(text, sx - w / 2, sy - h / 2, sx + w / 2, sy + h / 2, COLORS.text, 1.0 * s, "default-bold", "center", "center")
end

local function drawTurnHUD()
    local w = 250 * s
    local x = screenW - w - 22 * s
    local y = 118 * s
    local rowH = 22 * s
    local rows = #serving + (mine and 2 or 0) + 1
    local h = 34 * s + rows * rowH
    dxDrawRectangle(x, y, w, h, COLORS.panel)
    dxDrawRectangle(x, y, 3 * s, h, COLORS.red)
    shadowText("TURNOS", x + 14 * s, y + 8 * s, x + w, y + 30 * s, COLORS.muted, 0.95 * s, "default-bold", "left", "top")
    shadowText(("%d en espera"):format(waiting), x, y + 8 * s, x + w - 12 * s, y + 30 * s, COLORS.muted, 0.9 * s, "default", "right", "top")
    local ry = y + 30 * s
    for _, c in ipairs(serving) do
        local busy = c.state ~= "free"
        shadowText(c.name, x + 14 * s, ry, x + w, ry + rowH, COLORS.text, 1.0 * s, "default", "left", "center")
        shadowText(c.code, x, ry, x + w - 12 * s, ry + rowH, busy and COLORS.accent or COLORS.muted, 1.35 * s, "default-bold", "right", "center")
        ry = ry + rowH
    end
    if mine then
        ry = ry + rowH * 0.3
        dxDrawRectangle(x + 12 * s, ry, w - 24 * s, 1, tocolor(255, 255, 255, 30))
        shadowText("Tu turno", x + 14 * s, ry, x + w, ry + rowH, COLORS.text, 1.0 * s, "default-bold", "left", "center")
        shadowText(mine.code, x, ry, x + w - 12 * s, ry + rowH, COLORS.green, 1.5 * s, "default-bold", "right", "center")
        ry = ry + rowH
        local info
        if mine.state == "called" then info = "Te toca: ve al mostrador"
        elseif mine.state == "busy" then info = "Te estan atendiendo"
        elseif (mine.ahead or 0) == 0 then info = "Eres el siguiente"
        else info = ("%d persona%s delante"):format(mine.ahead, mine.ahead == 1 and "" or "s") end
        shadowText(info, x + 14 * s, ry, x + w, ry + rowH, COLORS.muted, 0.95 * s, "default", "left", "center")
    end
end

local function drawCall()
    if not callInfo then return end
    local t = (getTickCount() - callInfo.at) / 1000
    local pulse = 0.75 + 0.25 * math.abs(math.sin(t * 3))
    local w, h = 520 * s, 92 * s
    local x, y = (screenW - w) / 2, 70 * s
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 225))
    dxDrawRectangle(x, y, w, 4 * s, tocolor(245, 165, 36, 255 * pulse))
    shadowText(("¡Es tu turno! %s"):format(callInfo.code), x, y + 10 * s, x + w, y + 50 * s, tocolor(245, 165, 36, 255 * pulse), 2.0 * s, "default-bold", "center", "center")
    local left = math.max(0, AGENCY.CALL_TIMEOUT - math.floor(t))
    shadowText(("Acercate al %s y sientate  ·  %ds"):format(callInfo.name, left), x, y + 50 * s, x + w, y + h - 8 * s, COLORS.text, 1.15 * s, "default", "center", "center")
end

local function drawLeaveWarning()
    if getTickCount() > leaveWarnUntil or not mine then return end
    local w, h = 460 * s, 96 * s
    local x, y = (screenW - w) / 2, screenH * 0.62
    dxDrawRectangle(x, y, w, h, tocolor(40, 12, 12, 230))
    dxDrawRectangle(x, y, w, 4 * s, COLORS.red)
    shadowText(("Si sales perderas tu turno %s"):format(mine.code), x, y + 10 * s, x + w, y + 50 * s, COLORS.text, 1.4 * s, "default-bold", "center", "center")
    shadowText("Pulsa E otra vez para salir, o alejate de la puerta para seguir esperando.", x + 10 * s, y + 50 * s, x + w - 10 * s, y + h - 8 * s, COLORS.muted, 1.0 * s, "default", "center", "center")
end

-- Pantalla de turnos sobre cada mostrador
local function drawCounterSigns()
    for i, c in ipairs(serving) do
        local p = agencyCounterPoints(i)
        if p then
            local sx, sy = getScreenFromWorldPosition(p.desk.x, p.desk.y, p.desk.z + 1.6)
            if sx and nearPoint(p.desk.x, p.desk.y, p.desk.z, 18) then
                local w, h = 120 * s, 46 * s
                dxDrawRectangle(sx - w / 2, sy - h / 2, w, h, tocolor(10, 10, 10, 220))
                dxDrawText(c.name, sx - w / 2, sy - h / 2 + 3 * s, sx + w / 2, sy, COLORS.muted, 0.85 * s, "default", "center", "top")
                dxDrawText(c.code, sx - w / 2, sy - 4 * s, sx + w / 2, sy + h / 2, COLORS.red, 1.5 * s, "default-bold", "center", "center")
            end
        end
    end
end

addEventHandler("onClientRender", root, function()
    if agencyInService() then return end
    local spot, x, y, z = currentSpot()
    if spot and not uiIsOpen() then
        local text = spot == "entrance" and "Pulsa E para entrar a la Agencia de Empleo"
            or spot == "exit" and "Pulsa E para salir"
            or "Pulsa E para sacar tu numero"
        prompt3D(x, y, z, text)
    end
    if agencyIsInside() then
        local dx, dy, dz = dispenserPoint()
        local sx, sy = getScreenFromWorldPosition(dx, dy, dz + 0.9)
        if sx and nearPoint(dx, dy, dz, 15) then
            shadowText("TOME SU NUMERO", sx - 100, sy - 12, sx + 100, sy + 12, COLORS.red, 1.2 * s, "default-bold", "center", "center")
        end
        drawCounterSigns()
        drawTurnHUD()
        drawCall()
        drawLeaveWarning()
    end
end)

----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    buildRoom()
    bindKey("e", "down", onE)
    -- Texto sobre la puerta exterior
    local e = AGENCY.ENTRANCE
    local m = createMarker(e.x, e.y, e.z - 1, "cylinder", 1.2, 245, 165, 36, 90)
    if m then objects[#objects + 1] = m end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    destroyRoom()
    clearCall()
end)

-- Si se aleja de la puerta, la alerta se quita
setTimer(function()
    if leaveWarnUntil > 0 and currentSpot() ~= "exit" then leaveWarnUntil = 0 end
end, 500, 0)
