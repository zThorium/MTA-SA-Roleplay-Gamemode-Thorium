--[[
    rp_citizens / c_scenes.lua
    Escenas ambientales (100% cliente, sin consecuencias de rol) que dan vida a la
    calle: gente charlando, discusiones, peleas, fumadores, un vendedor ambulante,
    un auto averiado con las balizas... Solo hay UNA escena a la vez, pequena
    (1-4 peatones), cerca del jugador y fuera de su vista; se destruye al alejarse.

    Rendimiento:
      - dos timers baratos (8 s para decidir, 1 s para mantener la escena activa);
      - sin escena activa no se hace nada;
      - los peatones de la escena cuentan dentro del cupo de peatones de
        c_citizens.lua (sceneExtraPeds), no se suman encima;
      - la intensidad la manda el servidor (elementData root "rp:events"):
        0 = sin escenas ni ajustes de poblacion.

    Tambien ajusta la poblacion por hora y clima (eventPopScale).
]]

local TICK_DECIDE = 8000
local TICK_KEEP = 1000
local CHANCE = { 0.28, 0.45, 0.65 }     -- probabilidad por decision segun la intensidad (1-3)
local MIN_GAP = 12000                    -- ms entre el fin de una escena y la siguiente
local SPAWN_MIN, SPAWN_MAX = 45, 85      -- m del jugador
local KEEP_DIST = 135                    -- m: mas lejos se destruye

local active = nil                       -- { kind, peds, objs, veh, x, y, z, born, ttl, onTick, lastWatch }
local lastEnd = 0

local function intensity()
    local d = getElementData(root, "rp:events")
    -- sin dato del servidor (rp_events no arrancado o aun sin sincronizar): intensidad normal
    return type(d) == "table" and tonumber(d.intensity) or 2
end

----------------------------------------------------------------
-- Poblacion por hora y clima (la usa spawnTick de c_citizens.lua)
----------------------------------------------------------------
function eventPopScale()
    if intensity() == 0 then return 1, 1 end
    local h = getTime()
    local pm, cm = 1, 1
    if (h >= 7 and h < 10) or (h >= 17 and h < 20) then cm = 1.25 end   -- hora punta
    if h >= 12 and h < 15 then pm = 1.15 end                             -- mediodia
    if getRainLevel() > 0.15 then pm, cm = pm * 0.55, cm * 0.85 end     -- lluvia: calles vacias
    return pm, cm
end

function sceneExtraPeds()
    local n = hangoutPeds and hangoutPeds() or 0   -- grupos de barrio (c_hangouts.lua)
    if not active then return n end
    for _, p in ipairs(active.peds) do if isElement(p) then n = n + 1 end end
    return n
end

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function headingTo(dx, dy) return -math.deg(math.atan2(dx, dy)) end

-- Punto a "f" metros por delante y "r" a la derecha de (x, y) con rotacion h
local function rel(x, y, h, f, r)
    local rad = math.rad(h)
    return x + (-math.sin(rad)) * f + math.cos(rad) * r, y + math.cos(rad) * f + math.sin(rad) * r
end

local function face(ped, tx, ty)
    local x, y = getElementPosition(ped)
    setElementRotation(ped, 0, 0, headingTo(tx - x, ty - y), "default", true)
end

local function anim(ped, block, name)
    setPedAnimation(ped, block, name, -1, true, false, false, false)
end

local function addPed(sc, x, y, z, rot)
    local ped = createPed(citizenPickSkin(x, y, z), x, y, z + 1, rot or 0)
    if ped then sc.peds[#sc.peds + 1] = ped end
    return ped
end

local function destroyScene()
    if not active then return end
    for _, p in ipairs(active.peds) do if isElement(p) then destroyElement(p) end end
    for _, o in ipairs(active.objs) do if isElement(o) then destroyElement(o) end end
    if active.veh and isElement(active.veh) then destroyElement(active.veh) end
    active = nil
    lastEnd = getTickCount()
end

----------------------------------------------------------------
-- Catalogo de escenas
-- test(h, rain) -> peso (0 = no aplica). road = true usa un punto de calzada.
----------------------------------------------------------------
local function day(h) return h >= 7 and h < 21 end
local function night(h) return h >= 21 or h < 5 end

local SCENES = {}

SCENES.chat = {
    test = function(h, rain) return (day(h) and not rain) and 10 or (rain and 0 or 3) end,
    ttl = { 50000, 100000 },
    build = function(sc, x, y, z, h)
        local n = math.random(2, 3)
        for i = 1, n do
            local a = (i / n) * math.pi * 2
            local px, py = x + math.cos(a) * 0.9, y + math.sin(a) * 0.9
            local ped = addPed(sc, px, py, z, 0)
            if ped then
                face(ped, x, y)
                if i % 2 == 0 then anim(ped, "ped", "IDLE_chat") else anim(ped, "GANGS", "prtial_gngtlkA") end
            end
        end
    end,
}

SCENES.argue = {
    test = function(h, rain) return rain and 3 or 6 end,
    ttl = { 40000, 70000 },
    build = function(sc, x, y, z, h)
        local a = addPed(sc, x, y, z, h)
        local bx, by = rel(x, y, h, 1.4, 0)
        local b = addPed(sc, bx, by, z, h + 180)
        if a and b then
            face(a, bx, by) face(b, x, y)
            anim(a, "RIOT", "RIOT_ANGRY")
            anim(b, "GANGS", "prtial_gngtlkD")
        end
        sc.watch = 22
    end,
}

SCENES.phone = {
    test = function(h, rain) return 7 end,
    ttl = { 40000, 80000 },
    build = function(sc, x, y, z, h)
        local p = addPed(sc, x, y, z, h)
        if p then anim(p, "ped", "phone_talk") end
    end,
}

SCENES.smoker = {
    test = function(h, rain) return rain and 0 or (night(h) and 9 or 4) end,
    ttl = { 50000, 90000 },
    build = function(sc, x, y, z, h)
        local p = addPed(sc, x, y, z, h)
        if p then anim(p, "SMOKING", "M_smkstnd_loop") end
    end,
}

SCENES.vendor = {
    test = function(h, rain) return (day(h) and h >= 9 and h < 20 and not rain) and 6 or 0 end,
    ttl = { 70000, 120000 },
    build = function(sc, x, y, z, h)
        local cx, cy = rel(x, y, h, 1.1, 0)
        local cart = createObject(1340, cx, cy, z + 0.1, 0, 0, h)
        if cart then sc.objs[#sc.objs + 1] = cart end
        local vendor = addPed(sc, x, y, z, h)
        if vendor then anim(vendor, "DEALER", "DEALER_IDLE") end
        local fx, fy = rel(x, y, h, 2.6, 0.2)
        local buyer = addPed(sc, fx, fy, z, h + 180)
        if buyer then face(buyer, cx, cy) anim(buyer, "ped", "IDLE_chat") end
    end,
}

SCENES.drunk = {
    test = function(h, rain) return (night(h) and not rain) and 4 or 0 end,
    ttl = { 60000, 100000 },
    build = function(sc, x, y, z, h)
        local p = addPed(sc, x, y, z, h)
        if p then anim(p, "CRACK", "crckidle2") end
    end,
}

-- Pelea: dos peatones se pegan unos 20 s; al final salen corriendo
SCENES.fight = {
    test = function(h, rain) return (not rain) and (night(h) and 5 or 2) or 0 end,
    ttl = { 30000, 30000 },
    build = function(sc, x, y, z, h)
        local a = addPed(sc, x, y, z, h)
        local bx, by = rel(x, y, h, 1.2, 0)
        local b = addPed(sc, bx, by, z, h + 180)
        if a and b then
            face(a, bx, by) face(b, x, y)
            sc.fighters = { a, b }
        end
        sc.watch = 26
    end,
    onTick = function(sc, now)
        if not sc.fighters then return end
        local a, b = sc.fighters[1], sc.fighters[2]
        if not (isElement(a) and isElement(b)) then sc.fighters = nil return end
        local elapsed = now - sc.born
        if elapsed < 21000 then
            -- golpes intermitentes y se miran de frente
            local ax, ay = getElementPosition(a)
            local bx, by = getElementPosition(b)
            face(a, bx, by) face(b, ax, ay)
            local on = (math.floor(elapsed / 700) % 2) == 0
            setPedControlState(a, "fire", on)
            setPedControlState(b, "fire", not on)
        else
            -- terminan: cada uno se va en direccion contraria
            for i, p in ipairs(sc.fighters) do
                setPedControlState(p, "fire", false)
                local px, py = getElementPosition(p)
                local ox, oy = getElementPosition(sc.fighters[3 - i])
                setElementRotation(p, 0, 0, headingTo(px - ox, py - oy), "default", true)
                setPedControlState(p, "forwards", true)
                setPedControlState(p, "sprint", true)
            end
        end
    end,
}

-- Auto averiado en la calzada con el capo abierto y las balizas
SCENES.breakdown = {
    road = true,
    test = function(h, rain) return rain and 8 or 5 end,
    ttl = { 90000, 150000 },
    build = function(sc, x, y, z, h)
        local bx, by = rel(x, y, h, 0, 1.3)   -- algo hacia la orilla
        local veh = createVehicle(citizenPickCar(bx, by, z), bx, by, z + 1, 0, 0, h)
        if not veh then return end
        sc.veh = veh
        setVehicleEngineState(veh, false)
        setVehicleDoorOpenRatio(veh, 0, 1)
        setElementFrozen(veh, true)
        local px, py = rel(bx, by, h, 3.1, 1.6)
        local ped = addPed(sc, px, py, z, h + 90)
        if ped then face(ped, bx, by) anim(ped, "ped", "phone_talk") end
        sc.blink = 0
    end,
    onTick = function(sc, now)
        if sc.veh and isElement(sc.veh) then
            sc.blink = 1 - sc.blink
            setVehicleOverrideLights(sc.veh, sc.blink == 1 and 2 or 1)
        end
    end,
}

local function pickScene(h, rain)
    local total, list = 0, {}
    for name, def in pairs(SCENES) do
        local w = def.test(h, rain)
        if w > 0 then total = total + w list[#list + 1] = { name, w } end
    end
    if total <= 0 then return nil end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return list[#list][1]
end

----------------------------------------------------------------
-- Decidir y mantener
----------------------------------------------------------------
local function playerReady()
    if not getElementData(localPlayer, "rp:characterId") then return false end
    if getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0 then return false end
    if getElementData(localPlayer, "rp:downed") then return false end
    local v = getPedOccupiedVehicle(localPlayer)
    if v then
        local vx, vy = getElementVelocity(v)
        if math.sqrt(vx * vx + vy * vy) * 180 > 60 then return false end   -- a toda velocidad no se aprecia
    end
    return true
end

local function decide()
    if active then return end
    local lv = intensity()
    if lv < 1 or not citizensEnabled() or not playerReady() then return end
    if getTickCount() - lastEnd < MIN_GAP then return end
    if math.random() > CHANCE[math.min(lv, 3)] then return end

    local h = getTime()
    local rain = getRainLevel() > 0.15
    local kind = pickScene(h, rain)
    local def = kind and SCENES[kind]
    if not def then return end
    -- respeta el cupo de peatones: si la calle ya esta llena no se anade la escena
    local peds = citizenCounts()
    if peds > 12 then return end

    local x, y, z, rot
    if def.road then x, y, z, rot = citizenRoadSpot(SPAWN_MIN, SPAWN_MAX, true)
    else x, y, z, rot = citizenWalkSpot(SPAWN_MIN, SPAWN_MAX, true) end
    if not x then return end

    local sc = { kind = kind, peds = {}, objs = {}, x = x, y = y, z = z, born = getTickCount(), onTick = def.onTick, lastWatch = 0 }
    sc.ttl = math.random(def.ttl[1], def.ttl[2])
    active = sc
    def.build(sc, x, y, z, rot)
    if #sc.peds == 0 and not sc.veh then destroyScene() end
end

local function keep()
    if not active then return end
    local sc = active
    local px, py = getElementPosition(localPlayer)
    local now = getTickCount()
    local dist = getDistanceBetweenPoints2D(px, py, sc.x, sc.y)

    -- el jugador se fue, entro a un interior, o se desactivo la poblacion o las escenas
    if dist > KEEP_DIST or not playerReady() and (getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0)
        or not citizensEnabled() or intensity() < 1 then
        return destroyScene()
    end
    if sc.endAt and now > sc.endAt then return destroyScene() end
    -- fin de vida: se retira cuando nadie la mira (o a los 60 s de gracia)
    if now - sc.born > sc.ttl then
        local seen = false
        for _, p in ipairs(sc.peds) do
            if isElement(p) and isElementOnScreen(p) then seen = true break end
        end
        if sc.veh and isElement(sc.veh) and isElementOnScreen(sc.veh) then seen = true end
        if not seen or now - sc.born > sc.ttl + 60000 then return destroyScene() end
    end
    -- alguna victima fue herida/asustada: la escena se acaba (ya reaccionan los demas por su cuenta)
    for _, p in ipairs(sc.peds) do
        if isElement(p) and isPedDead(p) then return destroyScene() end
    end
    -- los que miran (peleas, discusiones)
    if sc.watch and now - sc.lastWatch > 6000 and dist < 80 then
        sc.lastWatch = now
        citizenWatch(sc.x, sc.y, sc.watch, 7000)
    end
    if sc.onTick then sc.onTick(sc, now) end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(decide, TICK_DECIDE, 0)
    setTimer(keep, TICK_KEEP, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, destroyScene)
addEventHandler("onClientPlayerWasted", localPlayer, destroyScene)

----------------------------------------------------------------
-- Si los atacan o se dispara cerca, la escena entra en panico: huyen y desaparecen
----------------------------------------------------------------
local function panic(fromX, fromY)
    local sc = active
    if not sc or sc.endAt then return end
    sc.endAt = getTickCount() + 6000
    sc.fighters = nil
    for _, p in ipairs(sc.peds) do
        if isElement(p) and not isPedDead(p) then
            setPedAnimation(p)
            setPedControlState(p, "fire", false)
            local x, y = getElementPosition(p)
            setElementRotation(p, 0, 0, headingTo(x - fromX, y - fromY), "default", true)
            setPedControlState(p, "forwards", true)
            setPedControlState(p, "sprint", true)
        end
    end
end

addEventHandler("onClientPedDamage", root, function(attacker)
    if not active then return end
    for _, p in ipairs(active.peds) do
        if p == source then
            local ax, ay = getElementPosition(isElement(attacker) and attacker or localPlayer)
            return panic(ax, ay)
        end
    end
end)

addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon)
    if not active or weapon < 22 then return end
    local x, y = getElementPosition(localPlayer)
    if getDistanceBetweenPoints2D(x, y, active.x, active.y) < 35 then panic(x, y) end
end)
