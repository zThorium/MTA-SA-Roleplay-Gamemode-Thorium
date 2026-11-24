--[[
    rp_hookers / c_hookers.lua
    Prostitutas al estilo GTA SA. Peds locales (como rp_citizens) en barrios conocidos.
      1. Acercate despacio en un auto con un asiento libre y toca la bocina junto a una.
      2. Aparece un modal SI / NO con el precio (lo fija el servidor).
      3. Con SI se sube al asiento del copiloto. Busca un lugar tranquilo (sin gente cerca) y deten el auto.
      4. Se cobra, se apaga el motor, el auto se mece con la animacion BLOWJOBZ y se cura algo de vida.
]]

local SKINS = { 63, 64, 75, 85, 87, 90, 152, 178, 237, 238, 243, 244, 245, 246, 256, 257 }
local ZONES = { ["Ganton"] = true, ["Idlewood"] = true, ["East Beach"] = true, ["Playa del Seville"] = true,
    ["Willowfield"] = true, ["Jefferson"] = true, ["East Los Santos"] = true, ["Glen Park"] = true }

local MAX_HOOKERS = 3
local SPAWN_MIN, SPAWN_MAX, DROP_DIST = 25, 90, 150
local HORN_RANGE = 8
local MAX_SPEED_KMH = 30
local QUIET_RADIUS = 20
local QUIET_HOLD_MS = 2000
local SEEK_TIMEOUT = 5 * 60000
local OFFER_TIMEOUT = 20000
local T_START, T_LOOP, T_END = 3500, 13000, 3500

local hookers = {}      -- [ped] = { cool = tick, busy = bool }
local S = nil           -- sesion: { ped, veh, stage, price, timers = {}, quietSince }
local modal = nil       -- { price }
local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.8, math.min(1.25, screenH / 900))

local function notify(t, k) pcall(function() exports.rp_notify:notify(t, k) end) end
local function say(ped, t, ms) pcall(function() exports.rp_notify:bubble(ped, t, ms or 5000) end) end
local function rotTo(ax, ay, bx, by) return -math.deg(math.atan2(bx - ax, by - ay)) end

local function addTimer(fn, ms, n)
    local t = setTimer(fn, ms, n or 1)
    S.timers[#S.timers + 1] = t
    return t
end

local function stopTimers()
    if not S then return end
    for _, t in ipairs(S.timers) do if isTimer(t) then killTimer(t) end end
    S.timers = {}
end

----------------------------------------------------------------
-- Ped de la calle
----------------------------------------------------------------
local function idle(ped)
    setPedControlState(ped, "forwards", false)
    setPedAnimation(ped, "PED", "hookertalk", -1, true, false, false, false)
end

local function destroyHooker(ped)
    hookers[ped] = nil
    if isElement(ped) then destroyElement(ped) end
end

-- Se va caminando y desaparece
local function sendAway(ped, fromX, fromY)
    if not isElement(ped) then return end
    local x, y = getElementPosition(ped)
    setPedAnimation(ped)
    setElementRotation(ped, 0, 0, rotTo(fromX, fromY, x, y), "default", true)
    setPedControlState(ped, "forwards", true)
    hookers[ped] = { busy = true }
    setTimer(function() destroyHooker(ped) end, 12000, 1)
end

local function spawnHooker()
    local ok, x, y, z, rot = pcall(function() return exports.rp_citizens:citizenWalkSpot(SPAWN_MIN, SPAWN_MAX, true) end)
    if not ok or not x or not ZONES[getZoneName(x, y, z, false)] then return end
    for ped in pairs(hookers) do
        if isElement(ped) then
            local hx, hy = getElementPosition(ped)
            if getDistanceBetweenPoints2D(x, y, hx, hy) < 30 then return end
        end
    end
    local ped = createPed(SKINS[math.random(#SKINS)], x, y, z + 1, rot or 0)
    if not ped then return end
    hookers[ped] = { cool = 0 }
    idle(ped)
end

local function tick()
    local px, py, pz = getElementPosition(localPlayer)
    local count = 0
    for ped in pairs(hookers) do
        if not isElement(ped) then
            hookers[ped] = nil
        else
            count = count + 1
            local hx, hy = getElementPosition(ped)
            local d = getDistanceBetweenPoints2D(px, py, hx, hy)
            if d > DROP_DIST and not (S and S.ped == ped) then
                destroyHooker(ped)
            elseif not hookers[ped].busy and d < 30 and not (S and S.ped == ped) then
                setElementRotation(ped, 0, 0, rotTo(hx, hy, px, py), "default", true)   -- mira al auto que pasa
            end
        end
    end
    if S or count >= MAX_HOOKERS then return end
    if ZONES[getZoneName(px, py, pz, false)] and math.random() < 0.6 then spawnHooker() end
end

----------------------------------------------------------------
-- Modal SI / NO
----------------------------------------------------------------
local function closeModal()
    if modal then modal = nil showCursor(false) end
end

local function btnRects()
    local w, h = 460 * scale, 190 * scale
    local x, y = (screenW - w) / 2, (screenH - h) / 2
    local bw, bh = 150 * scale, 40 * scale
    local by = y + h - bh - 26 * scale
    return x, y, w, h, { x + w / 2 - bw - 14 * scale, by, bw, bh }, { x + w / 2 + 14 * scale, by, bw, bh }
end

local function inRect(r, cx, cy) return cx >= r[1] and cx <= r[1] + r[3] and cy >= r[2] and cy <= r[2] + r[4] end

local function drawModal()
    if not modal then return end
    local x, y, w, h, yes, no = btnRects()
    local cx, cy = getCursorPosition()
    cx, cy = (cx or 0) * screenW, (cy or 0) * screenH
    dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, 110), true)
    dxDrawRectangle(x, y, w, h, tocolor(14, 16, 22, 242), true)
    dxDrawRectangle(x, y, w, 3 * scale, tocolor(245, 165, 36, 255), true)
    dxDrawText("Trabajadora sexual", x, y + 14 * scale, x + w, y + 44 * scale, tocolor(245, 165, 36), 1.5 * scale, "default-bold", "center", "center", false, false, true)
    dxDrawText(("¿Quieres pasar un buen rato con ella por $%d?"):format(modal.price), x + 20 * scale, y + 54 * scale, x + w - 20 * scale, y + 100 * scale,
        tocolor(242, 244, 248), 1.1 * scale, "default", "center", "top", false, true, true)
    for _, b in ipairs({ { yes, "SI", 76, 211, 138 }, { no, "NO", 255, 107, 107 } }) do
        local r = b[1]
        local hover = inRect(r, cx, cy)
        dxDrawRectangle(r[1], r[2], r[3], r[4], tocolor(b[3], b[4], b[5], hover and 255 or 170), true)
        dxDrawText(b[2], r[1], r[2], r[1] + r[3], r[2] + r[4], tocolor(10, 12, 16), 1.3 * scale, "default-bold", "center", "center", false, false, true)
    end
    dxDrawText("Y / Enter = SI    N / Retroceso = NO", x, y + h - 22 * scale, x + w, y + h - 4 * scale, tocolor(150, 155, 170), 0.9 * scale, "default", "center", "center", false, false, true)
end

----------------------------------------------------------------
-- Sesion
----------------------------------------------------------------
local function releasePed(ped, veh)
    if not isElement(ped) then return end
    if isPedInVehicle(ped) then removePedFromVehicle(ped) end
    if veh and isElement(veh) then
        local vx, vy = getElementPosition(veh)
        sendAway(ped, vx, vy)
    else
        destroyHooker(ped)
    end
end

-- keepHooker: ella se queda (dijiste que no); si no, se marcha
local function endSession(keepHooker, toServer)
    if not S then return end
    local ses = S
    closeModal()
    stopTimers()
    S = nil
    if ses.stage == "service" then
        toggleAllControls(true, true, false)
        if isElement(ses.veh) then setVehicleEngineState(ses.veh, true) end
        setPedAnimation(localPlayer)
        if isElement(ses.ped) then setPedAnimation(ses.ped) end
    end
    if toServer then triggerServerEvent("rp:hooker:cancel", resourceRoot) end
    if keepHooker and isElement(ses.ped) and hookers[ses.ped] then
        hookers[ses.ped].cool = getTickCount() + 8000
        hookers[ses.ped].busy = false
        idle(ses.ped)
    elseif not ses.serverPed then
        releasePed(ses.ped, ses.veh)
    end
end

local function carFree()
    return S and isElement(S.veh) and getPedOccupiedVehicle(localPlayer) == S.veh and getVehicleOccupant(S.veh, 0) == localPlayer
end

local function onHorn()
    if S or isCursorShowing() or isChatBoxInputActive() then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh or getVehicleOccupant(veh, 0) ~= localPlayer or getVehicleType(veh) ~= "Automobile" then return end
    if getVehicleMaxPassengers(veh) < 1 or getVehicleOccupant(veh, 1) then return end
    local vx, vy, vz = getElementVelocity(veh)
    if math.sqrt(vx * vx + vy * vy + vz * vz) * 180 > MAX_SPEED_KMH then return end
    local x, y = getElementPosition(veh)
    local best, bd = nil, HORN_RANGE
    for ped, h in pairs(hookers) do
        if isElement(ped) and not h.busy and getTickCount() > (h.cool or 0) then
            local hx, hy = getElementPosition(ped)
            local d = getDistanceBetweenPoints2D(x, y, hx, hy)
            if d < bd then best, bd = ped, d end
        end
    end
    if not best then return end
    S = { ped = best, veh = veh, stage = "ask", timers = {} }
    hookers[best].busy = true
    local hx, hy = getElementPosition(best)
    setElementRotation(best, 0, 0, rotTo(hx, hy, x, y), "default", true)
    triggerServerEvent("rp:hooker:ask", resourceRoot)
    addTimer(function()    -- el servidor no contesto
        if S and S.stage == "ask" then endSession(true, true) end
    end, OFFER_TIMEOUT)
end
bindKey("horn", "down", onHorn)

addEvent("rp:hooker:offer", true)
addEventHandler("rp:hooker:offer", resourceRoot, function(price)
    if not S or S.stage ~= "ask" then return end
    S.price = tonumber(price) or 0
    modal = { price = S.price }
    showCursor(true)
    say(S.ped, ("Hola guapo, ¿buscas compañía? Son $%d."):format(S.price), 8000)
    stopTimers()
    addTimer(function()
        if S and modal then notify("Te lo pensaste demasiado.", "info") endSession(true, true) end
    end, OFFER_TIMEOUT)
end)

addEvent("rp:hooker:deny", true)
addEventHandler("rp:hooker:deny", resourceRoot, function(text)
    if not S then return end
    if text and isElement(S.ped) then say(S.ped, text, 4000) end
    endSession(true, false)
end)

local function answer(yes)
    if not modal or not S then return end
    closeModal()
    stopTimers()
    if yes then
        S.stage = "wait"
        triggerServerEvent("rp:hooker:accept", resourceRoot)
    else
        say(S.ped, "Tú te lo pierdes...", 3500)
        endSession(true, true)
    end
end

addEventHandler("onClientClick", root, function(button, state, cx, cy)
    if not modal or button ~= "left" or state ~= "down" then return end
    local _, _, _, _, yes, no = btnRects()
    if inRect(yes, cx, cy) then answer(true) elseif inRect(no, cx, cy) then answer(false) end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not modal or not press then return end
    if key == "y" or key == "enter" or key == "num_enter" then answer(true) cancelEvent()
    elseif key == "n" or key == "backspace" then answer(false) cancelEvent() end
end)

addEventHandler("onClientRender", root, function()
    drawModal()
    if S and S.stage == "seek" then
        local msg, r, g, b = "Busca un lugar tranquilo y deten el auto", 245, 165, 36
        if S.quiet then msg, r, g, b = "Lugar tranquilo...", 76, 211, 138
        elseif S.crowd then msg, r, g, b = "Hay gente cerca: busca un lugar mas tranquilo", 255, 107, 107 end
        dxDrawText(msg, 0, screenH - 150 * scale, screenW, screenH - 120 * scale, tocolor(r, g, b), 1.3 * scale, "default-bold", "center", "center", false, false, true)
    end
end)

----------------------------------------------------------------
-- Ella se sube y se busca un lugar tranquilo
----------------------------------------------------------------
local function someoneNear(veh, ped)
    local x, y, z = getElementPosition(veh)
    for _, kind in ipairs({ "ped", "player" }) do
        for _, e in ipairs(getElementsByType(kind, root, true)) do
            if e ~= localPlayer and e ~= ped and not isPedDead(e) and getPedOccupiedVehicle(e) ~= veh then
                local ex, ey, ez = getElementPosition(e)
                if getDistanceBetweenPoints3D(x, y, z, ex, ey, ez) < QUIET_RADIUS then return true end
            end
        end
    end
    return false
end

local function seekTick()
    if not S or S.stage ~= "seek" then return end
    if not carFree() or getVehicleOccupant(S.veh, 1) ~= S.ped then
        notify("Ella se bajo porque dejaste el auto.", "info")
        return endSession(false, true)
    end
    local vx, vy, vz = getElementVelocity(S.veh)
    local stopped = math.sqrt(vx * vx + vy * vy + vz * vz) * 180 < 3
    S.crowd = someoneNear(S.veh, S.ped)
    S.quiet = stopped and not S.crowd
    if S.quiet then
        S.quietSince = S.quietSince or getTickCount()
        if getTickCount() - S.quietSince >= QUIET_HOLD_MS then
            S.stage = "service"
            triggerServerEvent("rp:hooker:start", resourceRoot)
        end
    else
        S.quietSince = nil
    end
end

local function boardCar()
    if not S then return end
    if not carFree() or getVehicleOccupant(S.veh, 1) then return endSession(true, true) end
    setPedControlState(S.ped, "forwards", false)
    stopTimers()
    S.stage = "boarding"
    -- El auto es del servidor: el servidor crea a la prostituta ya sentada y la local se retira
    triggerServerEvent("rp:hooker:board", resourceRoot, getElementModel(S.ped))
    destroyHooker(S.ped)
    S.ped = nil
    local t0 = getTickCount()
    addTimer(function()
        if not S or S.stage ~= "boarding" then return end
        local occ = getVehicleOccupant(S.veh, 1)
        if occ then
            S.ped, S.serverPed, S.stage = occ, true, "seek"
            stopTimers()
            say(occ, "Vamos a un sitio donde no nos vean...", 6000)
            notify("Busca un lugar tranquilo y deten el auto.", "info")
            addTimer(seekTick, 500, 0)
            addTimer(function()
                if S and S.stage == "seek" then
                    notify("Se canso de esperar y se fue.", "warning")
                    endSession(false, true)
                end
            end, SEEK_TIMEOUT)
        elseif getTickCount() - t0 > 5000 then
            notify("No se pudo subir al auto.", "error")
            endSession(false, true)
        end
    end, 150, 0)
end

addEvent("rp:hooker:go", true)
addEventHandler("rp:hooker:go", resourceRoot, function()
    if not S or S.stage ~= "wait" then return end
    stopTimers()
    S.stage = "walk"
    local t0 = getTickCount()
    addTimer(function()
        if not S or S.stage ~= "walk" then return end
        if not carFree() then return endSession(true, true) end
        local m = getElementMatrix(S.veh)
        local dx, dy = m[4][1] + m[1][1] * 1.5, m[4][2] + m[1][2] * 1.5      -- puerta del copiloto
        local x, y = getElementPosition(S.ped)
        if getDistanceBetweenPoints2D(x, y, dx, dy) < 1.3 or getTickCount() - t0 > 5000 then
            return boardCar()
        end
        setElementRotation(S.ped, 0, 0, rotTo(x, y, dx, dy), "default", true)
        setPedControlState(S.ped, "forwards", true)
    end, 100, 0)
end)

----------------------------------------------------------------
-- Servicio: motor apagado, auto meciendose, animaciones BLOWJOBZ
----------------------------------------------------------------
addEvent("rp:hooker:begin", true)
addEventHandler("rp:hooker:begin", resourceRoot, function()
    if not S or S.stage ~= "service" or not carFree() or getVehicleOccupant(S.veh, 1) ~= S.ped then return endSession(false, true) end
    stopTimers()
    local veh, ped = S.veh, S.ped
    toggleAllControls(false, true, false)
    setVehicleEngineState(veh, false)
    setElementVelocity(veh, 0, 0, 0)
    setPedAnimation(localPlayer, "BLOWJOBZ", "BJ_Car_Start_P", -1, false, false, false, true)
    setPedAnimation(ped, "BLOWJOBZ", "BJ_Car_Start_W", -1, false, false, false, true)
    addTimer(function()
        if not S then return end
        setPedAnimation(localPlayer, "BLOWJOBZ", "BJ_Car_Loop_P", -1, true, false, false, true)
        setPedAnimation(ped, "BLOWJOBZ", "BJ_Car_Loop_W", -1, true, false, false, true)
        local dir = 1
        addTimer(function()
            if not S or not isElement(veh) then return end
            dir = -dir
            setElementAngularVelocity(veh, 0.012 * dir, 0, 0)
        end, 260, math.floor(T_LOOP / 260))
    end, T_START)
    addTimer(function()
        if not S then return end
        setPedAnimation(localPlayer, "BLOWJOBZ", "BJ_Car_End_P", -1, false, false, false, false)
        setPedAnimation(ped, "BLOWJOBZ", "BJ_Car_End_W", -1, false, false, false, false)
    end, T_START + T_LOOP)
    addTimer(function()
        if not S then return end
        say(ped, "Fue un placer, cariño. Vuelve cuando quieras.", 5000)
        notify("Te sientes mucho mejor.", "success")
        endSession(false, false)
    end, T_START + T_LOOP + T_END)
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
addEventHandler("onClientPlayerVehicleExit", localPlayer, function()
    if S and S.stage ~= "service" then
        if S.stage == "seek" or S.stage == "walk" then notify("Ella se bajo porque dejaste el auto.", "info") end
        endSession(S.stage == "ask" or S.stage == "wait", true)
    end
end)
addEventHandler("onClientPlayerWasted", localPlayer, function() if S then endSession(false, true) end end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if S and S.stage == "service" then toggleAllControls(true, true, false) setPedAnimation(localPlayer) end
    if modal then showCursor(false) end
end)
addEventHandler("onClientResourceStart", resourceRoot, function() setTimer(tick, 3000, 0) end)
