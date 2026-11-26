--[[
    rp_pizzeria / c_customers.lua
    Clientes de la pizzeria: peds de cliente (solo los ve el trabajador, en su dimension).
    Estados: entrando -> fila -> esperando -> recoger -> sentarse a comer -> irse
             (o irse enojado si se acaba la paciencia). El servidor decide los pedidos;
    aqui solo se animan los peds y se dibuja el emoji de animo sobre su cabeza.
]]
local peds = {}          -- [orderId] = c
local seatsTaken = {}    -- [seatIndex] = orderId
local emojiTex = {}
-- Globos de Kenney (emotes, CC0): animo segun la paciencia y reacciones
local EMOJIS = { "happy", "neutral", "annoyed", "angry", "love", "complain", "ready", "tip" }

local function cfg() return PIZZERIA end

----------------------------------------------------------------
-- Movimiento
----------------------------------------------------------------
-- Caminar de verdad: el ped anda con su propio motor de GTA (controles "forwards" + "walk"), con sus
-- transiciones y su fisica; el script solo lo orienta hacia el siguiente punto del camino (giro suave).
-- Si apenas avanza en ATASCO_MS (una silla, otro cuerpo), se le da un empujon de medio metro hacia el
-- punto, nunca un salto al destino.
local TURN_SPEED = 360        -- grados por segundo
local ARRIVE_DIST = 0.35      -- metros para dar por alcanzado un punto
local STUCK_MS = 3000

local function headingTo(x1, y1, x2, y2) return (-math.deg(math.atan2(x2 - x1, y2 - y1))) % 360 end

local function turnTowards(current, target, maxStep)
    local diff = (target - current + 540) % 360 - 180
    if math.abs(diff) <= maxStep then return target end
    return (current + (diff > 0 and maxStep or -maxStep)) % 360
end

-- Ancla: solo para quien esta sentado (congelado en la silla)
local function setAnchor(c, x, y)
    c.anchor = { x = x, y = y }
end

local function controls(c, on)
    if not isElement(c.ped) then return end
    setPedControlState(c.ped, "forwards", on)   -- el control se llama "forwards" (como en rp_citizens)
    setPedControlState(c.ped, "walk", on)
end

local function stopWalking(c)
    c.walking = false
    controls(c, false)
end

-- path = { {x, y}, ... }; onArrive se llama al llegar al ultimo punto; face = rotacion final
local function walk(c, path, face, onArrive)
    c.path, c.wp, c.face, c.onArrive, c.anchor = path, 1, face, onArrive, nil
    if not isElement(c.ped) then return end
    setElementFrozen(c.ped, false)
    setPedAnimation(c.ped)
    local _, _, rz = getElementRotation(c.ped)
    c.heading, c.walking = rz, true
    local x, y = getElementPosition(c.ped)
    c.progress = { x = x, y = y, t = getTickCount() }
end

local function updateWalk(c, dt)
    if not isElement(c.ped) then return end
    if not c.path then
        local a = c.anchor
        if a then
            local x, y = getElementPosition(c.ped)
            if getDistanceBetweenPoints2D(x, y, a.x, a.y) > 0.2 then setElementPosition(c.ped, a.x, a.y, cfg().SEAT_Z, false) end
        end
        return
    end
    local x, y = getElementPosition(c.ped)
    local target = c.path[c.wp]
    -- el ultimo punto pide mas precision que los de paso
    local reach = c.path[c.wp + 1] and ARRIVE_DIST * 1.6 or ARRIVE_DIST
    if getDistanceBetweenPoints2D(x, y, target.x, target.y) <= reach then
        c.wp = c.wp + 1
        target = c.path[c.wp]
        if not target then
            c.path = nil
            stopWalking(c)
            if c.face then setElementRotation(c.ped, 0, 0, c.face, "default", true) end
            local cb = c.onArrive
            c.onArrive = nil
            if cb then cb(c) end
            return
        end
    end
    c.heading = turnTowards(c.heading or 0, headingTo(x, y, target.x, target.y), TURN_SPEED * dt / 1000)
    setElementRotation(c.ped, 0, 0, c.heading, "default", true)
    controls(c, true)
    -- atasco: empujon corto hacia el punto (sin cortar el paso)
    local now, p = getTickCount(), c.progress
    if getDistanceBetweenPoints2D(x, y, p.x, p.y) > 0.3 then
        p.x, p.y, p.t = x, y, now
    elseif now - p.t > STUCK_MS then
        local d = getDistanceBetweenPoints2D(x, y, target.x, target.y)
        local k = math.min(0.5, d) / math.max(d, 0.01)
        setElementPosition(c.ped, x + (target.x - x) * k, y + (target.y - y) * k, cfg().SEAT_Z, false)
        p.x, p.y, p.t = x, y, now
    end
end


----------------------------------------------------------------
-- Crear / destruir
----------------------------------------------------------------
local function destroyCustomer(id)
    local c = peds[id]
    if not c then return end
    if isElement(c.ped) then destroyElement(c.ped) end
    if isElement(c.box) then destroyElement(c.box) end
    if isElement(c.plate) then destroyElement(c.plate) end
    if c.seat then seatsTaken[c.seat] = nil end
    if isTimer(c.eatTimer) then killTimer(c.eatTimer) end
    if isTimer(c.leaveTimer) then killTimer(c.leaveTimer) end
    peds[id] = nil
end

local function clearAll()
    for id in pairs(peds) do destroyCustomer(id) end
    seatsTaken = {}
end

local function spawnCustomer(o)
    local C, d = cfg(), cfg().DOOR
    local ped = createPed(o.skin, d.x, d.y, d.z, 0)
    if not ped then return end
    setElementInterior(ped, C.INTERIOR)
    setElementDimension(ped, Pz.dim)
    for _, other in pairs(peds) do
        if isElement(other.ped) then setElementCollidableWith(ped, other.ped, false) end
    end
    local c = { id = o.id, ped = ped, order = o, mode = "enter" }
    peds[o.id] = c
    return c
end

local function place(c, x, y, rot)
    setElementPosition(c.ped, x, y, cfg().SEAT_Z)
    setElementRotation(c.ped, 0, 0, rot, "default", true)
end

----------------------------------------------------------------
-- Comportamiento segun el estado del servidor
----------------------------------------------------------------
local function goToSpot(c, spot, entering)
    local C = cfg()
    local path = {}
    if entering then
        for _, p in ipairs(C.ENTRY_PATH) do path[#path + 1] = p end
    end
    path[#path + 1] = spot
    c.spot = spot
    walk(c, path, 0, function()
        -- si su punto final es la caja y sigue en la fila, avisa al servidor de que ya llego
        if c.spot == cfg().QUEUE[1] and c.order and c.order.status == "queue" then
            triggerServerEvent("rp:pizzeria:arrived", resourceRoot, c.id)
        end
    end)
end

local function syncCustomers(state)
    local C = cfg()
    local seen = {}
    local queuePos = {}
    for i, id in ipairs(state.queue) do queuePos[id] = i end
    local waitIdx = 0
    for _, o in ipairs(state.orders) do
        seen[o.id] = true
        local c = peds[o.id] or spawnCustomer(o)
        if c then
            c.order = o
            c.orderTick = getTickCount()
            local spot
            if o.status == "queue" then
                local i = queuePos[o.id] or #C.QUEUE
                spot = C.QUEUE[math.min(i, #C.QUEUE)]
            else
                waitIdx = waitIdx + 1
                spot = C.WAIT[(waitIdx - 1) % #C.WAIT + 1]
            end
            if c.mode == "enter" then
                c.mode = "line"
                goToSpot(c, spot, true)
            elseif c.mode == "line" and c.spot ~= spot then
                -- en la fila: avanza; si ya estaba entrando, solo cambia el destino final
                if c.path and c.wp < #c.path then
                    c.path[#c.path], c.spot = spot, spot
                else
                    goToSpot(c, spot, false)
                end
            end
        end
    end
    -- pedidos que desaparecieron sin "served" ni "left" (no deberia pasar): fuera
    for id, c in pairs(peds) do
        if not seen[id] and c.mode == "line" then destroyCustomer(id) end
    end
end

local function freeSeat()
    local C = cfg()
    local free = {}
    for i = 1, #C.SEATS do if not seatsTaken[i] then free[#free + 1] = i end end
    if #free == 0 then return nil end
    return free[math.random(#free)]
end

local function leave(c, angry)
    local C = cfg()
    c.mode = angry and "angry" or "leaving"
    local x, y = getElementPosition(c.ped)
    local path = {}
    if c.seat then
        local s = C.SEATS[c.seat]
        path[#path + 1] = { x = s.ax, y = s.y }
        path[#path + 1] = { x = s.ax, y = -131.8 }
    elseif x > 375.5 then
        path[#path + 1] = { x = 376.9, y = math.min(y, -120.5) }
        path[#path + 1] = { x = 376.9, y = -131.5 }
    else
        path[#path + 1] = { x = 371.6, y = -119.8 }
        path[#path + 1] = { x = 371.6, y = -131.8 }
    end
    path[#path + 1] = { x = C.DOOR.x, y = C.DOOR.y }
    setPedAnimation(c.ped)
    walk(c, path, nil, function() destroyCustomer(c.id) end)
end

local function sitAndEat(c)
    local C = cfg()
    local s = C.SEATS[c.seat]
    if isElement(c.box) then destroyElement(c.box) end
    c.box = nil
    place(c, s.x, s.y, s.rot)
    setAnchor(c, s.x, s.y)
    setElementFrozen(c.ped, true)
    c.mode = "eating"
    setPedAnimation(c.ped, "FOOD", "FF_Sit_In", -1, false, false, false, true)
    -- pizza en la mesa, delante de su silla
    local px = C.TABLE_X + (s.side == "w" and -0.32 or 0.32)
    c.plate = createObject(2683, px, s.y, C.PLATE_Z, 0, 0, math.random(0, 359))
    setElementInterior(c.plate, C.INTERIOR)
    setElementDimension(c.plate, Pz.dim)
    setElementCollisionsEnabled(c.plate, false)
    local anims = { "FF_Sit_Eat1", "FF_Sit_Eat2", "FF_Sit_Eat3", "FF_Sit_Look", "FF_Sit_Eat1" }
    local i = 0
    c.eatTimer = setTimer(function()
        if not isElement(c.ped) then return end
        i = i + 1
        setPedAnimation(c.ped, "FOOD", anims[(i - 1) % #anims + 1], -1, true, false, false, true)
    end, 4000, 0)
    c.leaveTimer = setTimer(function()
        if isTimer(c.eatTimer) then killTimer(c.eatTimer) end
        if not isElement(c.ped) then return end
        setElementFrozen(c.ped, false)
        setPedAnimation(c.ped, "FOOD", "FF_Sit_Out_180", -1, false, false, false, false)
        if isElement(c.plate) then destroyElement(c.plate) end
        setTimer(function() if isElement(c.ped) then leave(c, false) end end, 1600, 1)
    end, math.random(C.EAT_MS[1], C.EAT_MS[2]), 1)
end

local function served(data)
    local c = peds[data.id]
    if not c or not isElement(c.ped) then return end
    local C = cfg()
    c.mode, c.reaction, c.reactionText, c.reactionUntil = "pickup", data.reaction, data.complaint, getTickCount() + 6000
    if not c.reactionText then
        c.reactionText = data.reaction == "love" and "¡Deliciosa! Quédate el cambio." or data.reaction == "happy" and "¡Gracias!" or "Mmm... bueno."
    end
    if data.tip and data.tip > 0 then c.tipText = ("+$%d de propina"):format(data.tip) end
    -- viene al mostrador justo enfrente de donde le entregaste la pizza
    local px = tonumber(data.x) or C.PICKUP.x
    walk(c, { { x = px, y = C.PICKUP.y - 0.8 }, { x = px, y = C.PICKUP.y } }, 0, function()
        c.box = createObject(1582, 0, 0, -50)
        setElementInterior(c.box, C.INTERIOR)
        setElementDimension(c.box, Pz.dim)
        setElementCollisionsEnabled(c.box, false)
        exports.bone_attach:attachElementToBone(c.box, c.ped, 12, 0.05, 0.15, 0.1, 0, -90, 0)
        setPedAnimation(c.ped, "FOOD", data.reaction == "complain" and "EAT_Vomit_SK" or "SHP_Thank", 2200, false, false, false, false)
        setTimer(function()
            if not isElement(c.ped) then return end
            setPedAnimation(c.ped)
            c.seat = freeSeat()
            if not c.seat or data.reaction == "complain" then return leave(c, false) end
            seatsTaken[c.seat] = c.id
            local s = C.SEATS[c.seat]
            walk(c, { { x = s.ax, y = -119.8 }, { x = s.ax, y = s.y }, { x = s.x + (s.side == "w" and -0.15 or 0.15), y = s.y } },
                s.rot, sitAndEat)
        end, 2300, 1)
    end)
end

----------------------------------------------------------------
-- Enganche con c_pizzeria.lua
----------------------------------------------------------------
Pz.onState = function(state) syncCustomers(state) end

-- Ped de un cliente (para que el tutorial lo senale)
Pz.customerPed = function(id) return peds[id] and isElement(peds[id].ped) and peds[id].ped or nil end

Pz.onFx = function(kind, data)
    if kind == "served" then
        served(data)
    elseif kind == "left" then
        local c = peds[data.id]
        if c and isElement(c.ped) then
            c.reaction, c.reactionText, c.reactionUntil = "angry", "¡Me voy, esto es un desastre!", getTickCount() + 5000
            leave(c, true)
        end
    end
end

Pz.onShiftChanged = function(on)
    clearAll()
    for _, name in ipairs(EMOJIS) do
        if on and not emojiTex[name] then emojiTex[name] = dxCreateTexture("images/" .. name .. ".png", "argb", true, "clamp") end
    end
end

addEventHandler("onClientResourceStop", resourceRoot, clearAll)

addEventHandler("onClientPedDamage", resourceRoot, function() cancelEvent() end)

----------------------------------------------------------------
-- Cada frame: caminar y emojis
----------------------------------------------------------------
local function moodOf(c)
    local o = c.order
    if not o or not o.patience then return "happy" end
    local elapsed = o.ago + (getTickCount() - (c.orderTick or getTickCount()))
    local left = 1 - elapsed / o.patience
    if left > 0.6 then return "happy" elseif left > 0.35 then return "neutral" elseif left > 0.15 then return "annoyed" end
    return "angry"
end

local lastFrame = getTickCount()
addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(100, now - lastFrame)   -- tope: tras una pausa larga no "saltan"
    lastFrame = now
    if not Pz.onShift then return end
    local cx, cy, cz = getCameraMatrix()
    for _, c in pairs(peds) do
        updateWalk(c, dt)
        if isElement(c.ped) and isElementOnScreen(c.ped) then
            local emoji, text
            if c.reactionUntil and now < c.reactionUntil then
                emoji, text = c.reaction, c.reactionText
                -- con propina: primero su reaccion y luego el globo de dinero
                if c.tipText and c.reactionUntil - now < 3500 then emoji = "tip" end
            elseif c.mode == "line" then
                emoji = moodOf(c)
                -- ya en la caja esperando que lo atiendan: "!" que late (si no esta enojado)
                if c.order and c.order.status == "queue" and not c.path and c.spot == cfg().QUEUE[1] and (emoji == "happy" or emoji == "neutral") then
                    emoji = "ready"
                end
            end
            if emoji and emojiTex[emoji] then
                local hx, hy, hz = getPedBonePosition(c.ped, 8)
                local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
                if dist < 25 then
                    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.45)
                    if sx then
                        local size = math.max(26, 64 - dist * 2.2)
                        if emoji == "angry" or emoji == "ready" then size = size * (1 + 0.08 * math.sin(now / 90)) end
                        local h = size * 1.19   -- los globos de Kenney miden 32x38
                        dxDrawImage(sx - size / 2, sy - h, size, h, emojiTex[emoji])
                        if text then
                            local w = dxGetTextWidth(text, 1, "default-bold") + 16
                            dxDrawRectangle(sx - w / 2, sy - h - 28, w, 22, tocolor(255, 255, 255, 230))
                            dxDrawText(text, sx - w / 2, sy - h - 28, sx + w / 2, sy - h - 6, tocolor(20, 20, 24), 1, "default-bold", "center", "center")
                            if c.tipText then
                                dxDrawText(c.tipText, sx - 100, sy - h - 50, sx + 100, sy - h - 30, tocolor(76, 211, 138), 1.1, "default-bold", "center", "center")
                            end
                        end
                    end
                end
            end
        end
    end
end)
