--[[
    rp_robbery / c_robbery.lua
    Lado cliente del robo:
      - Puerta y salida de la tienda (E), aviso "Pulsa E".
      - Detecta que apuntas con un arma de fuego a un NPC de la tienda y lo
        avisa al servidor (que valida e inicia el robo).
      - Barra de MIEDO (arriba a la derecha, bajo las estrellas), H amenaza,
        disparo de advertencia, E en la caja registradora.
      - IA de los NPC que mueve este cliente (es su syncer): cajero armado,
        rehen que huye o liberado, policias del cerco apuntando.
      - Condiciones negociadas, cuenta regresiva y aviso de persecucion.
    La cinematica de la caja esta en c_cinematic.lua y la negociacion en
    c_negotiation.lua. Estado compartido: RC (tabla global).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))
local MARGIN = math.floor(22 * s)

RC = {
    near = nil,          -- { kind = "door"|"exit", id, name }
    robbing = false,
    state = nil,         -- threat | looting | standoff | negotiating | escape | countdown
    fear = 100, shownFear = 100, fearVisible = false, fearBump = 0,
    clerk = nil, register = nil, hostages = {},
    fleeing = {}, released = {},
    cops = {}, negotiator = nil, copsHostile = false, copsLowered = false,
    escape = nil, countdownEnd = nil, countdownTotal = 0,
    flash = nil,         -- { text, color, until }
}

for _, e in ipairs({ "near", "start", "fear", "hostile", "flee", "lootEnd", "standoff", "released", "escape",
    "countdown", "pursuit", "stop" }) do
    addEvent("rp:robbery:" .. e, true)
end

local function isFirearm(w) return w and w >= ROBBERY.FIREARM_MIN and w <= ROBBERY.FIREARM_MAX end
local function busy() return isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() end
local function alive(ped) return isElement(ped) and not isPedDead(ped) end

local function flash(text, r, g, b, ms)
    RC.flash = { text = text, color = { r, g, b }, at = getTickCount(), ms = ms or 2500 }
end

----------------------------------------------------------------
-- Puerta y salida
----------------------------------------------------------------
addEventHandler("rp:robbery:near", resourceRoot, function(kind, id, name)
    if id then
        RC.near = { kind = kind, id = id, name = name }
    elseif RC.near and RC.near.kind == kind then
        RC.near = nil
    end
end)

local function nearRegister()
    if not RC.robbing or RC.state ~= "threat" or not RC.register then return false end
    local x, y, z = getElementPosition(localPlayer)
    local r = RC.register
    return getDistanceBetweenPoints3D(x, y, z, r[1], r[2], r[3]) <= ROBBERY.LOOT.RADIUS
end

local function onUse()
    if busy() or isPedInVehicle(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
    if nearRegister() then
        return triggerServerEvent("rp:robbery:loot", resourceRoot)
    end
    if RC.near then
        if RC.near.kind == "door" then
            triggerServerEvent("rp:robbery:door", resourceRoot, RC.near.id)
        else
            triggerServerEvent("rp:robbery:exit", resourceRoot)
        end
        RC.near = nil
    end
end

local function onIntimidate()
    if busy() or not RC.robbing or RC.state ~= "threat" then return end
    triggerServerEvent("rp:robbery:intimidate", resourceRoot)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", onUse)
    bindKey("h", "down", onIntimidate)
end)

----------------------------------------------------------------
-- Apuntar a un NPC de la tienda
----------------------------------------------------------------
local lastAimReport, aimingClerk = 0, false

local function aimingAt()
    if not getPedControlState(localPlayer, "aim_weapon") or not isFirearm(getPedWeapon(localPlayer)) then return nil end
    return getPedTarget(localPlayer)
end

addEventHandler("onClientPlayerTarget", localPlayer, function(target)
    if RC.robbing or not target or getElementType(target) ~= "ped" then return end
    local role = getElementData(target, "rp:robberyPed")
    if role ~= "clerk" and role ~= "customer" then return end
    if not getElementData(localPlayer, "rp:characterId") or not aimingAt() then return end
    local now = getTickCount()
    if now - lastAimReport < 1000 then return end
    lastAimReport = now
    triggerServerEvent("rp:robbery:aim", resourceRoot, target)
end)

-- Disparo de advertencia: disparar sin darle a ningun NPC de la tienda
addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon, _, _, _, _, _, hitElement)
    if not RC.robbing or RC.state ~= "threat" or not isFirearm(weapon) then return end
    if hitElement and isElement(hitElement) and getElementData(hitElement, "rp:robberyPed") then return end
    triggerServerEvent("rp:robbery:warningShot", resourceRoot)
end)

-- Disparar a la policia del cerco rompe el trato
local breached = false
addEventHandler("onClientPedDamage", root, function(attacker)
    if attacker ~= localPlayer or breached or not RC.robbing then return end
    local role = getElementData(source, "rp:robberyPed")
    if (role == "cop" or role == "negotiator") and getElementData(source, "rp:robberyOwner") == localPlayer then
        breached = true
        triggerServerEvent("rp:robbery:breach", resourceRoot, source)
    end
end)

----------------------------------------------------------------
-- Eventos del servidor
----------------------------------------------------------------
addEventHandler("rp:robbery:start", resourceRoot, function(data)
    RC.robbing, RC.state = true, "threat"
    RC.fear, RC.shownFear, RC.fearVisible = data.fear or 100, data.fear or 100, true
    RC.clerk, RC.register, RC.hostages = data.clerk, data.register, data.hostages or {}
    RC.fleeing, RC.released, RC.cops, RC.negotiator = {}, {}, {}, nil
    RC.copsHostile, RC.copsLowered, RC.escape, RC.countdownEnd = false, false, nil, nil
    breached = false
    flash("¡ROBO!", 229, 72, 77, 1800)
end)

addEventHandler("rp:robbery:fear", resourceRoot, function(value, bumped)
    if value < 0 then RC.fearVisible = false return end
    RC.fear = value
    if bumped then RC.fearBump = getTickCount() end
end)

addEventHandler("rp:robbery:hostile", resourceRoot, function(clerk)
    RC.fearVisible = false
    RC.hostileClerk = clerk
end)

addEventHandler("rp:robbery:flee", resourceRoot, function(ped, x, y, z)
    RC.fleeing[ped] = { x, y, z }
end)

addEventHandler("rp:robbery:lootEnd", resourceRoot, function()
    RC.state = "standoff"
    RC.fearVisible = false
end)

addEventHandler("rp:robbery:standoff", resourceRoot, function(cops, negotiator)
    RC.cops, RC.negotiator = cops or {}, negotiator
end)

addEventHandler("rp:robbery:released", resourceRoot, function(ped)
    RC.released[ped] = getTickCount()
end)

addEventHandler("rp:robbery:escape", resourceRoot, function(data)
    RC.state = "escape"
    RC.escape = data
    RC.copsLowered = not data.broken
end)

addEventHandler("rp:robbery:countdown", resourceRoot, function(seconds)
    RC.state = "countdown"
    RC.countdownTotal = seconds
    RC.countdownEnd = getTickCount() + seconds * 1000
    flash("¡CORRE!", 245, 165, 36, 1500)
end)

addEventHandler("rp:robbery:pursuit", resourceRoot, function(breach)
    RC.countdownEnd = nil
    RC.copsHostile = breach
    flash(breach and "¡TRATO ROTO!" or "¡PERSECUCION!", 229, 72, 77, 2600)
end)

local function resetPeds()
    for _, ped in ipairs(RC.cops or {}) do
        if isElement(ped) then
            setPedControlState(ped, "aim_weapon", false)
            setPedControlState(ped, "fire", false)
        end
    end
    if isElement(RC.hostileClerk) then
        setPedControlState(RC.hostileClerk, "aim_weapon", false)
        setPedControlState(RC.hostileClerk, "fire", false)
    end
end

addEventHandler("rp:robbery:stop", resourceRoot, function(reason)
    resetPeds()
    RC.robbing, RC.state, RC.fearVisible = false, nil, false
    RC.clerk, RC.register, RC.hostileClerk = nil, nil, nil
    RC.fleeing, RC.released = {}, {}
    -- tras empezar la persecucion las patrullas del cerco siguen un rato (las mueve este cliente)
    if reason ~= "pursuit" then RC.cops, RC.negotiator = {}, nil end
    RC.escape, RC.countdownEnd = nil, nil
end)

----------------------------------------------------------------
-- IA de los NPC (este cliente es su syncer)
----------------------------------------------------------------
local function face(ped, x, y)
    local px, py = getElementPosition(ped)
    setElementRotation(ped, 0, 0, (360 - math.deg(math.atan2(x - px, y - py))) % 360, "default", true)
end

local function shootAt(ped, now, period, burst, maxDist)
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z = getElementPosition(ped)
    face(ped, px, py)
    setPedAimTarget(ped, px, py, pz + 0.3)
    setPedControlState(ped, "aim_weapon", true)
    local clear = getDistanceBetweenPoints3D(x, y, z, px, py, pz) < maxDist
        and isLineOfSightClear(x, y, z + 0.6, px, py, pz + 0.5, true, false, false, true, false, true, false)
    setPedControlState(ped, "fire", clear and (now % period) < burst)
end

setTimer(function()
    local now = getTickCount()
    local px, py, pz = getElementPosition(localPlayer)

    -- cajero con la escopeta
    local clerk = RC.hostileClerk
    if alive(clerk) and isElementSyncer(clerk) and not isPedDead(localPlayer) then
        shootAt(clerk, now, 1500, 180, 25)
    end

    -- rehen que corre hacia la salida
    for ped, target in pairs(RC.fleeing) do
        if not alive(ped) then
            RC.fleeing[ped] = nil
        else
            local x, y, z = getElementPosition(ped)
            face(ped, target[1], target[2])
            setPedControlState(ped, "forwards", true)
            setPedControlState(ped, "sprint", true)
            if getDistanceBetweenPoints3D(x, y, z, target[1], target[2], target[3]) < 1.4 then
                RC.fleeing[ped] = nil
                triggerServerEvent("rp:robbery:hostageOut", resourceRoot, ped)
            end
        end
    end

    -- rehen liberado: camina hacia la policia
    for ped, at in pairs(RC.released) do
        if not alive(ped) or now - at > 6500 then
            RC.released[ped] = nil
        elseif isElement(RC.negotiator) then
            local nx, ny = getElementPosition(RC.negotiator)
            face(ped, nx, ny)
            setPedControlState(ped, "forwards", true)
            setPedControlState(ped, "walk", true)
        end
    end

    -- policias del cerco
    for _, cop in ipairs(RC.cops or {}) do
        if alive(cop) and isElementSyncer(cop) then
            if RC.copsHostile then
                shootAt(cop, now + getElementModel(cop) * 37, 1300, 250, 50)
            elseif RC.copsLowered then
                setPedControlState(cop, "aim_weapon", false)
                setPedControlState(cop, "fire", false)
            elseif getElementDimension(localPlayer) == 0 then
                local x, y = getElementPosition(cop)
                face(cop, px, py)
                setPedAimTarget(cop, px, py, pz + 0.4)
                setPedControlState(cop, "aim_weapon", true)
            end
        end
    end

    -- miedo: apunto al cajero o no
    if RC.robbing and RC.state == "threat" then
        local on = aimingAt() == RC.clerk and RC.clerk ~= nil
        if on ~= aimingClerk then
            aimingClerk = on
            triggerServerEvent("rp:robbery:aimState", resourceRoot, on)
        end
    end
end, 100, 0)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function hudVisible()
    return getElementData(localPlayer, "rp:characterId") and not isPlayerMapVisible()
        and not getElementData(localPlayer, "rp:hudHidden")
end

local function shadowText(text, x1, y1, x2, y2, color, scale, font, ax, ay)
    dxDrawText(text, x1 + 2, y1 + 2, x2 + 2, y2 + 2, tocolor(0, 0, 0, 200), scale, font, ax, ay)
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, ax, ay)
end

local function prompt(text)
    local w = dxGetTextWidth(text, 1.1 * s, "default-bold") + 40 * s
    local x, y = (screenW - w) / 2, screenH - 150 * s
    dxDrawRectangle(x, y, w, 36 * s, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3 * s, 36 * s, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36 * s, tocolor(242, 244, 248), 1.1 * s, "default-bold", "center", "center")
end

-- Debajo del dinero, el arma y las estrellas: rp_hud dice donde termina su bloque
-- (se pregunta 4 veces por segundo, no en cada frame). Si rp_hud no esta, medidas aproximadas.
local hudBottom, hudBottomAt = nil, 0
local function fearTop()
    local now = getTickCount()
    if now - hudBottomAt > 250 then
        hudBottomAt = now
        local ok, y = pcall(function() return exports.rp_hud:getTopRightBottom() end)
        hudBottom = ok and tonumber(y) or nil
    end
    if hudBottom then return hudBottom + 6 * s end
    local y = MARGIN + dxGetFontHeight(2.2 * s, "default-bold") + 2 * s + dxGetFontHeight(1.5 * s, "default-bold") + 4 * s
    local weapon = getPedWeapon(localPlayer)
    if weapon and weapon ~= 0 then y = y + dxGetFontHeight(1.0 * s, "default-bold") + 4 * s end
    y = y + 6 * s
    if (tonumber(getElementData(localPlayer, "rp:wanted")) or 0) > 0 then y = y + 34 * s end
    return y + 6 * s
end

local function drawFear(now)
    RC.shownFear = RC.shownFear + (RC.fear - RC.shownFear) * 0.15
    local v = math.max(0, math.min(100, RC.shownFear)) / 100
    local w, h = 230 * s, 46 * s
    local x, y = screenW - MARGIN - w, fearTop()
    local low = RC.fear <= ROBBERY.FEAR.LOW
    local bump = math.max(0, 1 - (now - RC.fearBump) / 400)
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 200))
    dxDrawRectangle(x, y, 3 * s, h, low and tocolor(229, 72, 77, 255) or tocolor(245, 165, 36, 255))
    dxDrawText("MIEDO DEL CAJERO", x + 12 * s, y + 4 * s, x + w, y + 20 * s, tocolor(154, 163, 178), 0.85 * s, "default-bold", "left", "center")
    dxDrawText(("%d%%"):format(math.floor(RC.fear + 0.5)), x, y + 4 * s, x + w - 10 * s, y + 20 * s,
        tocolor(242, 244, 248), 0.85 * s, "default-bold", "right", "center")
    local bx, by, bw, bh = x + 12 * s, y + 24 * s, w - 22 * s, 12 * s
    dxDrawRectangle(bx, by, bw, bh, tocolor(255, 255, 255, 25))
    -- de amarillo (lleno) a rojo (vacio)
    local r, g, b = 229 + (255 - 229) * v, 72 + (214 - 72) * v, 77 + (110 - 77) * v
    local alpha = low and (150 + math.sin(now / 120) * 105) or 255
    dxDrawRectangle(bx, by, bw * v, bh, tocolor(r, g, b, alpha))
    if bump > 0 then dxDrawRectangle(bx, by - 2 * s, bw * v, bh + 4 * s, tocolor(255, 255, 255, 120 * bump)) end
    if low then
        shadowText("¡Pierde el miedo! Pulsa H para amenazarlo", 0, y + h + 4 * s, x + w, 0,
            tocolor(229, 72, 77, 150 + math.sin(now / 120) * 105), 0.95 * s, "default-bold", "right", "top")
    else
        dxDrawText("H amenazar  ·  apuntarle lo calma menos", 0, y + h + 4 * s, x + w, 0, tocolor(154, 163, 178, 200),
            0.8 * s, "default", "right", "top")
    end
end

local function drawEscape(now)
    local e = RC.escape
    if not e then return end
    local cx = screenW / 2
    local y = 70 * s
    if RC.state == "countdown" and RC.countdownEnd then
        local left = math.max(0, (RC.countdownEnd - now) / 1000)
        local secs = math.ceil(left)
        if secs ~= RC.lastTick then
            RC.lastTick = secs
            if secs > 0 and secs <= 5 then playSoundFrontEnd(5) end
        end
        local urgent = left <= 5
        local scale = 3.2 * s * (1 + (1 - (left % 1)) * 0.12)
        shadowText("LA POLICIA SALE EN", 0, y, screenW, 0, tocolor(242, 244, 248), 1.2 * s, "default-bold", "center", "top")
        shadowText(tostring(secs), 0, y + 22 * s, screenW, 0, urgent and tocolor(229, 72, 77) or tocolor(245, 165, 36),
            scale, "default-bold", "center", "top")
        local bw = 260 * s
        dxDrawRectangle(cx - bw / 2, y + 90 * s, bw, 6 * s, tocolor(255, 255, 255, 30))
        dxDrawRectangle(cx - bw / 2, y + 90 * s, bw * (left / math.max(1, RC.countdownTotal)), 6 * s,
            urgent and tocolor(229, 72, 77) or tocolor(245, 165, 36))
        y = y + 104 * s
    elseif RC.state == "escape" then
        local x, yy, z = getElementPosition(localPlayer)
        local d = getDistanceBetweenPoints3D(x, yy, z, e.door[1], e.door[2], e.door[3])
        local left = math.max(0, math.ceil(e.radius - d))
        shadowText(("Alejate %d m: la cuenta de %d s empieza al salir de la zona"):format(left, e.seconds),
            0, y, screenW, 0, tocolor(242, 244, 248), 1.15 * s, "default-bold", "center", "top")
        y = y + 26 * s
    else
        return
    end
    local terms = {
        { e.noTraps, "Sin pinchos ni barricadas" },
        { e.noTires, "Sin disparos a las llantas" },
    }
    for _, t in ipairs(terms) do
        local color = t[1] and tocolor(76, 211, 138) or tocolor(154, 163, 178, 160)
        shadowText((t[1] and "SI  ·  " or "NO  ·  ") .. t[2], 0, y, screenW, 0, color, 1.0 * s, "default-bold", "center", "top")
        y = y + 20 * s
    end
end

local function drawFlash(now)
    local f = RC.flash
    if not f then return end
    local t = (now - f.at) / f.ms
    if t >= 1 then RC.flash = nil return end
    local pop = t < 0.12 and (t / 0.12) or 1
    local alpha = t > 0.75 and (1 - (t - 0.75) / 0.25) * 255 or 255
    local scale = (2.0 + (1 - pop) * 3) * s * 2
    local c = f.color
    dxDrawText(f.text, 4, screenH * 0.28 + 4, screenW + 4, 0, tocolor(0, 0, 0, alpha * 0.8), scale, "default-bold", "center", "top")
    dxDrawText(f.text, 0, screenH * 0.28, screenW, 0, tocolor(c[1], c[2], c[3], alpha), scale, "default-bold", "center", "top")
end

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    if not hudVisible() then return end
    if RC.cinematic or RC.negotiating then return drawFlash(now) end
    if RC.fearVisible and RC.robbing and RC.state == "threat" then drawFear(now) end
    if nearRegister() then
        prompt("Pulsa E para vaciar la caja")
    elseif RC.near and not RC.robbing and not isPedInVehicle(localPlayer) then
        prompt(RC.near.kind == "door" and ("Pulsa E para entrar a " .. tostring(RC.near.name)) or "Pulsa E para salir")
    elseif RC.near and RC.robbing and RC.near.kind == "exit" and RC.state ~= "looting" then
        prompt(RC.state == "standoff" and "Pulsa E para salir... (la policia te espera)" or "Pulsa E para salir sin el botin")
    end
    drawEscape(now)
    drawFlash(now)
end)

addEventHandler("onClientResourceStop", resourceRoot, resetPeds)
