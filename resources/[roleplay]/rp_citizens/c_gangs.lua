--[[
    rp_citizens / c_gangs.lua
    Pandilleros con caracter. Los peatones con skin de banda (Grove, Ballas, Vagos, Aztecas,
    Rifa) ya no huyen todos igual: cada uno tiene una personalidad y un nivel de enojo.

    Personalidades (se sortean una vez por peaton):
      hothead   se enciende rapido (miradas, pitidos, apuntarle) y va directo a pegar
      leader    avisa con insultos antes de pasar a mayores y llama a su banda
      follower  no empieza nada, pero se une si sus companeros atacan
      coward    se asusta y huye

    Enojo (0-100): sube si les pegas o disparas, les apuntas, les pitas, te quedas mirandolos
    de cerca o casi los atropellas. Con poco enojo solo te miran mal (insulto, quietos);
    con mucho, atacan: la banda del mismo barrio a menos de 45 m se une y te acorralan
    (cada uno toma un hueco alrededor, el primero se pone delante si vas en auto) y despues
    pegan; los conductores de banda se bajan del auto. Si te quedas parado en el auto con
    ellos junto a la puerta, el servidor te saca del vehiculo (rp:citizens:pullOut).
    Si matas a uno, la banda del mismo barrio cercana se lanza a por ti.

    Todo es local de cliente (los peatones solo existen en este cliente). Se apoya en
    citizenInternals() de c_citizens.lua y en hangoutHas/hangoutRelease de c_hangouts.lua.
]]

local TICK = 200
local DT = TICK / 1000
local REACH = 40            -- m: solo se evalua a los pandilleros a menos de esto
local RALLY = 45            -- m: la banda que se une
local GIVE_UP = 45          -- m: dejan de perseguir si te alejas tanto durante GIVE_UP_MS
local GIVE_UP_MS = 5000
local MAX_HUNT_MS = 60000   -- como mucho persiguen un minuto

local FAMILIES = {
    ballas = { 102, 103, 104 }, grove = { 105, 106, 107 }, vagos = { 108, 109, 110 },
    aztecas = { 114, 115, 116 }, rifa = { 173, 174, 175 },
}
local FAMILY_OF = {}
for name, list in pairs(FAMILIES) do for _, id in ipairs(list) do FAMILY_OF[id] = name end end

-- Umbrales de enojo por personalidad; mul = lo rapido que se enojan
local TH = {
    hothead  = { warn = 20, hunt = 60,  mul = 1.5 },
    leader   = { warn = 35, hunt = 100, mul = 1.0 },
    follower = { warn = 55, hunt = 100, mul = 0.8 },
    coward   = { flee = 60, mul = 1.0 },
}

local I                      -- c_citizens: peds, cars y utilidades (ver citizenInternals)
local anger = {}             -- [ped] = enojo
local hostile = setmetatable({}, { __mode = "k" })   -- [ped] = { phase = "WARN" | "HUNT", ... }
local pers = setmetatable({}, { __mode = "k" })
local nextPull = 0

local function internals()
    if not I and citizenInternals then I = citizenInternals() end
    return I
end

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end
local function angleDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end
local function dist2(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function personality(ped)
    local p = pers[ped]
    if p then return p end
    local r = math.random()
    p = r < 0.35 and "hothead" or r < 0.55 and "leader" or r < 0.85 and "follower" or "coward"
    pers[ped] = p
    return p
end

local function controllable(ped)
    if not isElement(ped) or isPedDead(ped) then return false end
    if hostile[ped] then return true end
    local i = internals()
    if not i then return false end
    local s = i.peds[ped]
    if s then return s.state ~= "DEAD" end
    return hangoutHas ~= nil and hangoutHas(ped)
end

-- c_citizens / c_hangouts le dejan a este modulo las reacciones de estos peatones
function gangHandles(ped)
    return isElement(ped) and FAMILY_OF[getElementModel(ped)] ~= nil and controllable(ped)
end

----------------------------------------------------------------
-- Control del peaton
----------------------------------------------------------------
local function takeOver(ped)
    local i = internals()
    local s = i.peds[ped]
    if s then
        s.state = "GANG"
        setPedAnimation(ped)
        return true
    end
    return hangoutRelease ~= nil and hangoutRelease(ped) == true
end

local function stopMoving(ped)
    setPedControlState(ped, "forwards", false)
    setPedControlState(ped, "sprint", false)
    setPedControlState(ped, "walk", false)
    setPedControlState(ped, "fire", false)
end

-- Termina el conflicto: vuelve a caminar (o huye)
local function release(ped, flee)
    hostile[ped] = nil
    anger[ped] = 0
    if not isElement(ped) then return end
    local i = internals()
    stopMoving(ped)
    setPedAnimation(ped)
    if takeAllWeapons then takeAllWeapons(ped) else setPedWeaponSlot(ped, 0) end   -- takeAllWeapons puede no existir en cliente
    if isPedDead(ped) then return end
    local s = i.peds[ped]
    if not s and adoptMirrorPed and adoptMirrorPed(ped) then s = i.peds[ped] end
    if not s then return destroyElement(ped) end
    i.resumeWalk(ped, s)
    if flee then i.startFlee(ped, localPlayer, math.random(8000, 12000), 0) end
end

local function flee(ped)
    local i = internals()
    local h = hostile[ped]
    if not h and not takeOver(ped) then return end
    release(ped, true)
end

local function startWarn(ped)
    if hostile[ped] or not takeOver(ped) then return end
    hostile[ped] = { phase = "WARN", born = getTickCount(), nextInsult = 0 }
end

local function startHunt(ped, delay)
    local h = hostile[ped]
    if h and h.phase == "HUNT" then return end
    if not h then
        if not takeOver(ped) then return end
        h = { born = getTickCount() }
        hostile[ped] = h
    end
    local now = getTickCount()
    h.phase, h.huntAt, h.startAt = "HUNT", now, now + (delay or 0)
    h.posUntil = now + 3500
    h.inPos, h.far, h.doorSince = false, nil, nil
    setPedAnimation(ped)
    -- armas de mano de vez en cuando
    local p = personality(ped)
    local r = math.random()
    if (p == "hothead" or p == "leader") and r < 0.35 then givePedWeapon(ped, 5, 1, true)    -- bate
    elseif r < 0.55 then givePedWeapon(ped, 1, 1, true) end                                   -- punos americanos
    anger[ped] = math.max(anger[ped] or 0, 100)
end

-- La banda cercana se une; los cobardes huyen
local function rally(ped)
    local model = FAMILY_OF[getElementModel(ped)]
    local x, y = getElementPosition(ped)
    for _, other in ipairs(getElementsByType("ped", root, true)) do
        if other ~= ped and FAMILY_OF[getElementModel(other)] == model and controllable(other) then
            local ox, oy = getElementPosition(other)
            local h = hostile[other]
            if dist2(x, y, ox, oy) <= RALLY and not (h and h.phase == "HUNT") then
                if personality(other) == "coward" then
                    flee(other)
                else
                    startHunt(other, math.random(150, 1200))
                end
            end
        end
    end
end

-- Sube el enojo; devuelve true si ya pasa a atacar
local function provoke(ped, amount)
    if not controllable(ped) then return end
    local p = personality(ped)
    anger[ped] = math.min(150, (anger[ped] or 0) + amount * (TH[p].mul or 1))
end

----------------------------------------------------------------
-- Ganchos para c_citizens: conductores de banda
----------------------------------------------------------------
function gangEngage(ped)
    if controllable(ped) then
        startHunt(ped)
        rally(ped)
    end
end

-- Un auto de la poblacion con conductor de banda fue chocado/disparado/pitado. true = el conductor
-- se baja a pelear (los cobardes siguen su reaccion normal de huida).
function gangCarProvoked(vehicle, s, amount)
    local i = internals()
    local driver = s.driver
    if not i or not isElement(driver) or not FAMILY_OF[getElementModel(driver)] then return false end
    local p = personality(driver)
    if p == "coward" then return false end
    s.gangAnger = (s.gangAnger or 0) + amount * TH[p].mul
    if s.gangAnger >= (TH[p].hunt or 100) then
        s.gangAnger = 0
        i.abandonCar(vehicle, s, true)
        return true
    end
    return false
end

----------------------------------------------------------------
-- Bucle de decision
----------------------------------------------------------------
local function playerBusy()
    return isPedDead(localPlayer) or getElementData(localPlayer, "rp:downed") or not getElementData(localPlayer, "rp:characterId")
        or getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0
end

local function updateWarn(ped, h, now, ctx, x, y)
    stopMoving(ped)
    setElementRotation(ped, 0, 0, heading(ctx.px - x, ctx.py - y), "default", true)
    if now > h.nextInsult then
        h.nextInsult = now + math.random(2500, 4000)
        setPedAnimation(ped, "ped", "fucku", -1, false, false, false, false)
    end
end

local function updateHunt(ped, h, now, ctx, x, y, z, hunters)
    if now < h.startAt then
        setElementRotation(ped, 0, 0, heading(ctx.px - x, ctx.py - y), "default", true)
        return
    end
    local i = internals()
    local dP = dist2(x, y, ctx.px, ctx.py)

    -- Se rinde: demasiado lejos, mucho rato, o herido sin ser cabeza caliente
    if dP > GIVE_UP then h.far = h.far or now else h.far = nil end
    if (h.far and now - h.far > GIVE_UP_MS) or now - h.huntAt > MAX_HUNT_MS then return release(ped) end
    if getElementHealth(ped) < 30 and personality(ped) ~= "hothead" then return release(ped, true) end

    local tx, ty = ctx.px, ctx.py
    if ctx.veh then tx, ty = getElementPosition(ctx.veh) end

    -- 1) Acorralar: cada uno toma su hueco alrededor del objetivo antes de atacar (solo si son 2 o mas)
    if not h.inPos and #hunters > 1 and now < h.posUntil and not ctx.allInPos then
        local R = ctx.veh and 3.6 or 2.3
        local sx, sy = tx + math.cos(h.slot or 0) * R, ty + math.sin(h.slot or 0) * R
        if dist2(x, y, sx, sy) < 1.0 then
            h.inPos = true
            stopMoving(ped)
            setElementRotation(ped, 0, 0, heading(tx - x, ty - y), "default", true)
        else
            local rot = heading(sx - x, sy - y)
            if not i.pedClear(x, y, z, rot, 1.6) then rot = rot + (h.side or 55) end
            setElementRotation(ped, 0, 0, rot, "default", true)
            i.setWalking(ped, true, dist2(x, y, sx, sy) > 4)
            setPedControlState(ped, "fire", false)
        end
        return
    end
    h.inPos = true

    -- 2) Atacar
    local ax, ay = tx, ty
    if ctx.veh then
        -- a la puerta del conductor (izquierda del auto)
        local m = getElementMatrix(ctx.veh)
        ax, ay = tx - m[1][1] * 1.7 + m[2][1] * 0.2, ty - m[1][2] * 1.7 + m[2][2] * 0.2
    end
    local d = dist2(x, y, ax, ay)
    local reach = ctx.veh and 1.2 or 1.4
    if d > reach then
        local rot = heading(ax - x, ay - y)
        if not i.pedClear(x, y, z, rot, 1.6) then rot = rot + (h.side or -55) end
        setElementRotation(ped, 0, 0, rot, "default", true)
        i.setWalking(ped, true, d > 4)
        setPedControlState(ped, "fire", false)
        h.doorSince = nil
    else
        stopMoving(ped)
        setElementRotation(ped, 0, 0, heading(tx - x, ty - y), "default", true)
        setPedControlState(ped, "fire", not getPedControlState(ped, "fire"))   -- golpes intermitentes
        if ctx.veh then h.doorSince = h.doorSince or now end
    end
end

local function tick()
    local i = internals()
    if not i then return end
    local now = getTickCount()

    if playerBusy() then
        -- el jugador cayo o salio del mundo: los que peleaban se calman
        for ped, h in pairs(hostile) do
            if not h.calmAt then h.calmAt = now + 2500 end
            if now > h.calmAt then release(ped) end
        end
        return
    end

    local px, py, pz = getElementPosition(localPlayer)
    local veh = getPedOccupiedVehicle(localPlayer)
    local speed = 0
    if veh then
        local vx, vy = getElementVelocity(veh)
        speed = math.sqrt(vx * vx + vy * vy) * 180
    end
    local rz = select(3, getElementRotation(localPlayer))
    local weapon = getPedWeapon(localPlayer)
    local ctx = {
        px = px, py = py, pz = pz, veh = veh, speed = speed,
        horn = veh and getControlState("horn"),
        aiming = (not veh) and weapon >= 22 and getControlState("aim_weapon"),
        aimT = getPedTarget(localPlayer),
        standing = (not veh) and getPedMoveState(localPlayer) == "stand",
    }
    local vfx, vfy
    if veh then local m = getElementMatrix(veh) vfx, vfy = m[2][1], m[2][2] end

    -- Peatones de banda a la vista
    local hunters = {}
    local peds = getElementsByType("ped", root, true)
    for _, ped in ipairs(peds) do
        if FAMILY_OF[getElementModel(ped)] and controllable(ped) and not isPedInVehicle(ped) then
            local x, y, z = getElementPosition(ped)
            local d = dist2(x, y, px, py)
            local h = hostile[ped]
            if d <= REACH or h then
                local p = personality(ped)
                local t = TH[p]
                -- que sube el enojo
                local gain = 0
                local facing = math.abs(angleDiff(heading(x - px, y - py), rz))
                if ctx.aiming and (ctx.aimT == ped or (d < 18 and facing < 25)) then gain = gain + 55 end
                if ctx.horn and d < 22 and ((x - px) * vfx + (y - py) * vfy) > 0 then gain = gain + 45 end
                if ctx.standing and d < 2.5 and facing < 50 then gain = gain + 14 end   -- mirarlos fijo y de cerca
                if veh and speed > 25 and d < 1.8 then gain = gain + 160 end            -- casi los atropellas
                local a = (anger[ped] or 0) + (gain * (t.mul or 1) - 6) * DT
                anger[ped] = math.max(0, math.min(150, a))
                a = anger[ped]

                if not h then
                    if p == "coward" then
                        if a >= t.flee then flee(ped) end
                    elseif a >= t.hunt then
                        startHunt(ped)
                        rally(ped)
                    elseif a >= t.warn then
                        startWarn(ped)
                    end
                elseif h.phase == "WARN" then
                    if a >= (t.hunt or 100) then
                        startHunt(ped)
                        rally(ped)
                    elseif a < 8 then
                        release(ped)
                    else
                        updateWarn(ped, h, now, ctx, x, y)
                    end
                end
                h = hostile[ped]
                if h and h.phase == "HUNT" then hunters[#hunters + 1] = ped end
            end
        end
    end

    -- Huecos alrededor del objetivo (el primero, delante del auto si vas en vehiculo)
    local n = #hunters
    if n > 0 then
        local tx, ty = px, py
        if veh then tx, ty = getElementPosition(veh) end
        local base
        if veh then
            base = math.atan2(vfy, vfx)          -- el primero se pone delante del auto
        else
            local hx, hy = getElementPosition(hunters[1])
            base = math.atan2(hy - ty, hx - tx)  -- el primero conserva su lado
        end
        local allIn = true
        for k, ped in ipairs(hunters) do
            local h = hostile[ped]
            h.slot = base + (k - 1) * (2 * math.pi / n)
            h.side = h.side or (math.random() < 0.5 and 55 or -55)
            if not h.inPos then allIn = false end
        end
        ctx.allInPos = allIn
        for _, ped in ipairs(hunters) do
            local h = hostile[ped]
            local x, y, z = getElementPosition(ped)
            updateHunt(ped, h, now, ctx, x, y, z, hunters)
        end
        -- Acorralado en el auto, parado y con alguien en la puerta: te sacan del vehiculo
        if veh and speed < 12 and now > nextPull then
            for _, ped in ipairs(hunters) do
                local h = hostile[ped]
                if h and h.doorSince and now - h.doorSince > 2500 then
                    nextPull = now + 10000
                    triggerServerEvent("rp:citizens:pullOut", resourceRoot)
                    break
                end
            end
        end
    end

    -- Conductores de banda: se enojan si pitas, apuntas o los cierras; se bajan a pelear
    for vehicle, s in pairs(i.cars) do
        local driver = s.driver
        if s.state ~= "ABANDONED" and isElement(driver) and isElement(vehicle) and FAMILY_OF[getElementModel(driver)] then
            local x, y = getElementPosition(vehicle)
            local d = dist2(x, y, px, py)
            if d < 30 and vehicle ~= veh then
                local gain = 0
                if ctx.horn and d < 25 then gain = gain + 35 end
                if ctx.aiming and (ctx.aimT == driver or ctx.aimT == vehicle) then gain = gain + 55 end
                if gain > 0 then gangCarProvoked(vehicle, s, gain * DT) end
            end
            if s.gangAnger and s.gangAnger > 0 then s.gangAnger = math.max(0, s.gangAnger - 6 * DT) end
        end
    end
end

----------------------------------------------------------------
-- Eventos
----------------------------------------------------------------
local function fromPlayer(attacker)
    if not isElement(attacker) then return false end
    if getElementType(attacker) == "vehicle" then return getVehicleController(attacker) == localPlayer end
    return attacker == localPlayer
end

-- Golpes y disparos a un pandillero: se enciende y avisa a su banda
addEventHandler("onClientPedDamage", root, function(attacker)
    if not FAMILY_OF[getElementModel(source)] or not controllable(source) or not fromPlayer(attacker) then return end
    local ped = source
    local p = personality(ped)
    if p == "coward" then
        provoke(ped, 100)
        return flee(ped)
    end
    provoke(ped, 100)
    startHunt(ped)
    rally(ped)
end)

addEventHandler("onClientPedWasted", root, function(killer)
    if not FAMILY_OF[getElementModel(source)] then return end
    hostile[source] = nil
    if isElement(killer) and getElementType(killer) == "vehicle" then killer = getVehicleController(killer) end
    if killer ~= localPlayer then return end
    -- la banda cercana lo ve o lo oye: se lanza
    local model = FAMILY_OF[getElementModel(source)]
    local x, y = getElementPosition(source)
    for _, other in ipairs(getElementsByType("ped", root, true)) do
        if other ~= source and FAMILY_OF[getElementModel(other)] == model and controllable(other) then
            local ox, oy = getElementPosition(other)
            if dist2(x, y, ox, oy) <= 60 then
                if personality(other) == "coward" then flee(other) else startHunt(other, math.random(200, 1500)) end
            end
        end
    end
end)

-- Disparos cerca: se ponen tensos (los cabeza caliente saltan enseguida)
addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon)
    if weapon < 22 then return end
    local px, py = getElementPosition(localPlayer)
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if FAMILY_OF[getElementModel(ped)] and controllable(ped) and not hostile[ped] then
            local x, y = getElementPosition(ped)
            if dist2(x, y, px, py) < 30 then provoke(ped, 45) end
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(tick, TICK, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for ped in pairs(hostile) do
        if isElement(ped) then stopMoving(ped) end
    end
end)

-- Diagnostico: /pandilleros
addCommandHandler("pandilleros", function()
    local lines, n = {}, 0
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if FAMILY_OF[getElementModel(ped)] then
            n = n + 1
            local h = hostile[ped]
            lines[#lines + 1] = ("%s/%s enojo %d%s"):format(FAMILY_OF[getElementModel(ped)], personality(ped),
                math.floor(anger[ped] or 0), h and (" [" .. h.phase .. "]") or "")
        end
    end
    outputChatBox(("[Pandillas] %d a la vista: %s"):format(n, table.concat(lines, " | ")), 255, 220, 120)
end)
