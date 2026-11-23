--[[
    rp_npcrel / c_npcrel.lua

    Parte visual del sistema de vinculos: aviso "[H] Hablar" sobre el peaton cercano,
    menu radial, camara de escena (plano general -> sobre el hombro -> contraplano ->
    primer plano -> orbita en el beso), barras negras, animaciones de ambos,
    corazones/destellos/confeti y la visita de la persona a la que llamas por telefono.
    Todo lo que cuenta (resultado, dinero, etapa) lo decide el servidor.
]]

local screenW, screenH = guiGetScreenSize()
local S = math.max(0.75, screenH / 900)

addEvent("rp:npcrel:open", true)
addEvent("rp:npcrel:result", true)
addEvent("rp:npcrel:numberShared", true)
addEvent("rp:npcrel:summon", true)

local IMG = { heart = "images/heart.png", spark = "images/spark.png" }

local ui = nil          -- conversacion en curso
local visitors = {}     -- [ped] = estado de la persona que viene tras una llamada
local leavers = {}      -- [ped] = { untilT, startT } peds que se van caminando
local parts = {}        -- particulas
local banner = nil      -- cartel grande ("Ahora son amigos")
local target = nil      -- ped al que se puede hablar ahora
local camState = nil    -- camara suavizada

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function rotTo(dx, dy) return math.deg(math.atan2(-dx, dy)) end
local function pick(list) return list[math.random(#list)] end
local function now() return getTickCount() end
local function notify(text, kind) pcall(function() exports.rp_notify:notify(text, kind) end) end

local function headPos(el)
    local x, y, z = getPedBonePosition(el, 8)
    if not x then x, y, z = getElementPosition(el) z = z + 0.7 end
    return x, y, z
end

----------------------------------------------------------------
-- Particulas (sprites 2D proyectados desde el mundo)
----------------------------------------------------------------
local CONFETTI = { { 255, 90, 140 }, { 255, 210, 80 }, { 120, 220, 255 }, { 170, 255, 140 }, { 255, 255, 255 } }

local function addPart(p)
    p.age, p.life = 0, p.life or 1.5
    p.rot, p.spin = p.rot or math.random(-25, 25), p.spin or math.random(-60, 60)
    p.sway, p.phase = p.sway or 0, math.random() * 6.28
    parts[#parts + 1] = p
end

local function hearts(x, y, z, n, big)
    for _ = 1, n do
        local shade = math.random(3)
        local c = shade == 1 and { 255, 90, 140 } or (shade == 2 and { 255, 60, 100 } or { 255, 150, 190 })
        addPart({
            img = "heart", x = x + math.random(-25, 25) / 100, y = y + math.random(-25, 25) / 100, z = z + math.random(0, 25) / 100,
            vx = math.random(-15, 15) / 100, vy = math.random(-15, 15) / 100, vz = math.random(40, 85) / 100,
            size = (big and 0.34 or 0.22) * (0.7 + math.random() * 0.6), life = 1.4 + math.random() * 0.9,
            c = c, sway = 0.25,
        })
    end
end

local function sparks(x, y, z, n, c)
    for _ = 1, n do
        local a = math.random() * 6.28
        local sp = 0.6 + math.random() * 1.1
        addPart({
            img = "spark", x = x, y = y, z = z, vx = math.cos(a) * sp, vy = math.sin(a) * sp, vz = math.random(10, 120) / 100,
            gz = -1.2, size = 0.1 + math.random() * 0.12, life = 0.5 + math.random() * 0.5, c = c or { 255, 240, 160 }, spin = math.random(-300, 300),
        })
    end
end

local function confetti(x, y, z, n)
    for _ = 1, n do
        local a = math.random() * 6.28
        local sp = 0.4 + math.random() * 1.6
        addPart({
            img = "spark", x = x, y = y, z = z + 1.2, vx = math.cos(a) * sp, vy = math.sin(a) * sp, vz = 0.5 + math.random() * 1.4,
            gz = -1.5, size = 0.07 + math.random() * 0.09, life = 1.6 + math.random() * 1.2, c = pick(CONFETTI), spin = math.random(-500, 500), sway = 0.5,
        })
    end
end

local function rejectFx(ped)
    local x, y, z = headPos(ped)
    sparks(x, y, z + 0.2, 7, { 235, 60, 50 })
    pcall(fxAddSparks, x, y, z + 0.1, 0, 0, 1, 1.2, 4, 0, 0, 0, true, 2, 1)
end

local function updateParts(dt)
    for i = #parts, 1, -1 do
        local p = parts[i]
        p.age = p.age + dt
        if p.age >= p.life then
            table.remove(parts, i)
        else
            p.vz = p.vz + (p.gz or 0.0) * dt
            p.x = p.x + (p.vx + math.sin(p.age * 4 + p.phase) * p.sway) * dt
            p.y = p.y + p.vy * dt
            p.z = p.z + p.vz * dt
            p.rot = p.rot + p.spin * dt
        end
    end
end

local function drawParts()
    if #parts == 0 then return end
    local cx, cy, cz = getCameraMatrix()
    for _, p in ipairs(parts) do
        local sx, sy = getScreenFromWorldPosition(p.x, p.y, p.z, 0.2)
        if sx then
            local dist = math.max(0.4, getDistanceBetweenPoints3D(cx, cy, cz, p.x, p.y, p.z))
            local k = p.age / p.life
            local alpha = k < 0.15 and k / 0.15 or (1 - clamp((k - 0.55) / 0.45, 0, 1))
            local px = p.size * screenH * 0.95 / dist * (0.6 + 0.4 * math.min(1, k * 6))
            dxDrawImage(sx - px / 2, sy - px / 2, px, px, IMG[p.img], p.rot, 0, 0,
                tocolor(p.c[1], p.c[2], p.c[3], math.floor(255 * alpha)))
        end
    end
end

----------------------------------------------------------------
-- Camara de escena
----------------------------------------------------------------
local function pose(kind)
    local px, py, pz = headPos(localPlayer)
    local nx, ny, nz = headPos(ui.ped)
    local dx, dy = nx - px, ny - py
    local len = math.max(0.3, math.sqrt(dx * dx + dy * dy))
    dx, dy = dx / len, dy / len
    local rx, ry = dy, -dx   -- derecha del jugador mirando al otro
    local mx, my, mz = (px + nx) / 2, (py + ny) / 2, (pz + nz) / 2
    local push = 1 - 0.018 * (ui.data and ui.data.stage or 1)   -- mas cerca cuanto mas intimidad

    if kind == "wide" then
        return mx + rx * 3.6, my + ry * 3.6, mz + 0.5, mx, my, mz - 0.05, 62
    elseif kind == "over" then
        return px - dx * 1.4 * push + rx * 0.55, py - dy * 1.4 * push + ry * 0.55, pz + 0.18, nx, ny, nz - 0.04, 52
    elseif kind == "reverse" then
        return nx + dx * 1.4 * push - rx * 0.55, ny + dy * 1.4 * push - ry * 0.55, nz + 0.18, px, py, pz - 0.04, 52
    elseif kind == "closeNpc" then
        return nx - dx * 1.05 * push + rx * 0.3, ny - dy * 1.05 * push + ry * 0.3, nz + 0.05, nx, ny, nz - 0.02, 36
    elseif kind == "closePlayer" then
        return px + dx * 1.05 * push - rx * 0.3, py + dy * 1.05 * push - ry * 0.3, pz + 0.05, px, py, pz - 0.02, 36
    elseif kind == "orbit" then
        local t = (now() - ui.orbitT0) / 1000
        local a = ui.orbitA0 + t * 0.55
        local r = ui.orbitR
        return mx + math.cos(a) * r, my + math.sin(a) * r, mz + 0.15 + math.sin(t * 0.8) * 0.12, mx, my, mz - 0.1, 48
    elseif kind == "exit" then
        local fx, fy = getElementPosition(localPlayer)
        local _, _, rz = getElementRotation(localPlayer)
        local r = math.rad(rz)
        return fx + math.sin(r) * 3.6, fy - math.cos(r) * 3.6, pz + 1.0, fx, fy, pz - 0.1, 70
    end
    return mx + rx * 3.6, my + ry * 3.6, mz + 0.5, mx, my, mz, 62
end

-- Si una pared tapa la camara, la acerca al punto de interes
local function clipCamera(cx, cy, cz, lx, ly, lz)
    local hit, hx, hy, hz = processLineOfSight(lx, ly, lz, cx, cy, cz, true, false, false, true, false, false, true, false, ui and ui.ped)
    if hit then
        local dx, dy, dz = cx - lx, cy - ly, cz - lz
        local len = math.max(0.01, math.sqrt(dx * dx + dy * dy + dz * dz))
        return hx - dx / len * 0.25, hy - dy / len * 0.25, hz - dz / len * 0.25
    end
    return cx, cy, cz
end

local lastCamTick = 0
local function updateCamera()
    if not ui or not camState then return end
    local t = now()
    local dt = clamp((t - lastCamTick) / 1000, 0.001, 0.05)
    lastCamTick = t
    if not isElement(ui.ped) then return end

    if ui.shotUntil and t > ui.shotUntil then
        ui.shot, ui.shotUntil = ui.nextShot or ui.shot, nil
        ui.nextShot = nil
    end
    local cx, cy, cz, lx, ly, lz, fov = pose(ui.shot)
    if ui.shot ~= "exit" then cx, cy, cz = clipCamera(cx, cy, cz, lx, ly, lz) end
    local k = 1 - math.exp(-dt * (ui.shot == "exit" and 4 or 5.5))
    local c = camState
    if not c.init then
        c.x, c.y, c.z, c.lx, c.ly, c.lz, c.fov = cx, cy, cz, lx, ly, lz, fov
        c.init = true
    else
        c.x, c.y, c.z = c.x + (cx - c.x) * k, c.y + (cy - c.y) * k, c.z + (cz - c.z) * k
        c.lx, c.ly, c.lz = c.lx + (lx - c.lx) * k, c.ly + (ly - c.ly) * k, c.lz + (lz - c.lz) * k
        c.fov = c.fov + (fov - c.fov) * k
    end
    setCameraMatrix(c.x, c.y, c.z, c.lx, c.ly, c.lz, 0, c.fov)
end

local function shot(name, ms, nextName)
    if not ui then return end
    ui.shot = name
    ui.shotUntil = ms and (now() + ms) or nil
    ui.nextShot = nextName
end

----------------------------------------------------------------
-- Animaciones
----------------------------------------------------------------
local ANIM_MS = { talk = 3600, joke = 3200, compliment = 3000, flirt = 3600, gift = 2800, hug = 3200, kiss = 6000, wave = 2600 }

local function playAnim(el, a, loop)
    if not a or not isElement(el) then return end
    setPedAnimation(el, a[1], a[2], -1, loop ~= false, false, false, false)
end

local function clearAnim(el)
    if isElement(el) then setPedAnimation(el) end
end

local function faceEachOther()
    if not ui or not isElement(ui.ped) then return end
    local px, py = getElementPosition(localPlayer)
    local nx, ny = getElementPosition(ui.ped)
    setPedRotation(localPlayer, rotTo(nx - px, ny - py))
    setElementRotation(ui.ped, 0, 0, rotTo(px - nx, py - ny))
end

-- Acerca a la persona a "dist" metros (abrazo, beso) sin mover al jugador
local function placeNpc(dist)
    local px, py, pz = getElementPosition(localPlayer)
    local nx, ny = getElementPosition(ui.ped)
    local dx, dy = nx - px, ny - py
    local len = math.max(0.2, math.sqrt(dx * dx + dy * dy))
    setElementPosition(ui.ped, px + dx / len * dist, py + dy / len * dist, pz)
    faceEachOther()
end

local function startAnimations(actionId, outcome)
    local set = NPCREL_ANIMS[actionId == "bye" and "wave" or (actionId == "number" and "talk" or (actionId == "askout" and "flirt" or actionId))]
    if not set then return end
    local ms = ANIM_MS[actionId] or 3000
    if actionId == "number" then ms = 2600 elseif actionId == "askout" then ms = 3600 elseif actionId == "bye" then ms = 2600 end
    local bad = outcome == "bad"
    if (actionId == "kiss" or actionId == "hug") and not bad then placeNpc(actionId == "kiss" and 0.72 or 0.9) else faceEachOther() end
    playAnim(localPlayer, pick(set.player), not (actionId == "kiss" or actionId == "hug"))
    playAnim(ui.ped, bad and pick(set.bad) or pick(set.npc), not (actionId == "kiss" or actionId == "hug"))
    local ped = ui.ped
    ui.animUntil = now() + ms
    setTimer(function()
        if not ui or ui.ped ~= ped or not ui.animUntil or now() < ui.animUntil - 50 then return end
        ui.animUntil = nil
        clearAnim(localPlayer)
        if isElement(ped) then playAnim(ped, { "PED", "IDLE_chat" }) end
    end, ms + 80, 1)
end

----------------------------------------------------------------
-- Personas que se van / que vienen
----------------------------------------------------------------
local function sendAway(ped)
    if not isElement(ped) or leavers[ped] then return end
    visitors[ped] = nil
    setElementData(ped, "rp:npcrel", nil, false)
    clearAnim(ped)
    local px, py = getElementPosition(localPlayer)
    local x, y = getElementPosition(ped)
    setElementRotation(ped, 0, 0, rotTo(x - px, y - py) + math.random(-35, 35))
    setPedControlState(ped, "forwards", true)
    setPedControlState(ped, "walk", true)
    leavers[ped] = { startT = now() }
end

local function updateLeavers()
    for ped, l in pairs(leavers) do
        if not isElement(ped) then
            leavers[ped] = nil
        else
            local age = now() - l.startT
            if age > 9000 then
                leavers[ped] = nil
                destroyElement(ped)
            elseif age > 6500 then
                setElementAlpha(ped, math.floor(255 * (1 - (age - 6500) / 2500)))
            end
        end
    end
end

local function groundZ(x, y, z)
    local gz = getGroundPosition(x, y, z + 20)
    return (gz and gz ~= 0) and gz or z
end

local function spawnVisitor(data)
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z, rot
    local ok, sx, sy, sz, sr = pcall(function() return exports.rp_citizens:citizenWalkSpot(32, 55, true) end)
    if ok and sx then x, y, z, rot = sx, sy, sz, sr
    else
        local a = math.random() * 6.28
        x, y = px + math.cos(a) * 38, py + math.sin(a) * 38
        z, rot = groundZ(x, y, pz), 0
    end
    local ped = createPed(data.skin, x, y, z + 1, rot or 0)
    if not ped then return end
    setElementData(ped, "rp:npcrel", data.id, false)
    visitors[ped] = {
        id = data.id, name = data.name, stage = data.stage, dating = data.dating,
        arrived = false, expire = now() + (data.stay or 240000), lastX = x, lastY = y, lastCheck = now(), stuck = 0,
    }
    notify((data.name:match("^(%S+)") or data.name) .. " está llegando.", "info")
end

local function updateVisitors()
    local px, py, pz = getElementPosition(localPlayer)
    for ped, v in pairs(visitors) do
        if not isElement(ped) then
            visitors[ped] = nil
        elseif ui and ui.ped == ped then
            v.expire = math.max(v.expire, now() + 20000)
        elseif now() > v.expire then
            sendAway(ped)
        else
            local x, y, z = getElementPosition(ped)
            local d = getDistanceBetweenPoints2D(px, py, x, y)
            if d > 160 then
                destroyElement(ped) visitors[ped] = nil
            elseif not v.arrived then
                if d > 2.6 then
                    setElementRotation(ped, 0, 0, rotTo(px - x, py - y))
                    setPedControlState(ped, "forwards", true)
                    setPedControlState(ped, "walk", d < 6)
                    setPedControlState(ped, "sprint", false)
                    if now() - v.lastCheck > 4000 then
                        if getDistanceBetweenPoints2D(x, y, v.lastX, v.lastY) < 1.2 then
                            v.stuck = v.stuck + 1
                            if v.stuck >= 2 then   -- atascada: aparece mas cerca, fuera de la vista
                                local ok, sx, sy, sz = pcall(function() return exports.rp_citizens:citizenWalkSpot(9, 16, true) end)
                                if ok and sx then setElementPosition(ped, sx, sy, sz + 1) end
                                v.stuck = 0
                            end
                        else
                            v.stuck = 0
                        end
                        v.lastX, v.lastY, v.lastCheck = x, y, now()
                    end
                else
                    v.arrived = true
                    setPedControlState(ped, "forwards", false)
                    setPedControlState(ped, "walk", false)
                    setElementRotation(ped, 0, 0, rotTo(px - x, py - y))
                    playAnim(ped, { "ON_LOOKERS", "wave_loop" })
                    setTimer(function() if isElement(ped) and not (ui and ui.ped == ped) then clearAnim(ped) end end, 2600, 1)
                    notify((v.name:match("^(%S+)") or v.name) .. " llegó. Pulsa " .. string.upper(NPCREL.KEY) .. " para hablar.", "success")
                end
            end
        end
    end
end

addEventHandler("rp:npcrel:summon", resourceRoot, spawnVisitor)

----------------------------------------------------------------
-- Aviso "[H] Hablar" sobre el peaton cercano
----------------------------------------------------------------
local function talkable(ped)
    if not isElement(ped) or isPedDead(ped) or isPedInVehicle(ped) or leavers[ped] then return false end
    if not (getElementData(ped, "rp:npcrel") or getElementData(ped, "rp:citizen")) then return false end
    if getElementData(ped, "rp:cop") then return false end
    return NPCREL_SKIN_GENDER[getElementModel(ped)] ~= nil
end

local function scanTarget()
    target = nil
    if ui or isPedInVehicle(localPlayer) or isPedDead(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
    if getPedWeapon(localPlayer) >= 22 and getPedControlState(localPlayer, "aim_weapon") then return end
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestD = nil, NPCREL.TALK_DISTANCE
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if talkable(ped) and getElementDimension(ped) == getElementDimension(localPlayer) then
            local x, y, z = getElementPosition(ped)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d < bestD and math.abs(z - pz) < 1.8 then best, bestD = ped, d end
        end
    end
    target = best
end

local function drawPrompt()
    if not target or ui or not isElement(target) then return end
    local x, y, z = headPos(target)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.35)
    if not sx then return end
    local v = visitors[target]
    local text = "[" .. string.upper(NPCREL.KEY) .. "] " .. (v and ("Hablar con " .. (v.name:match("^(%S+)") or v.name)) or "Hablar")
    local w = dxGetTextWidth(text, 1 * S, "default-bold") + 22 * S
    local h = 26 * S
    local pulse = 0.85 + math.sin(now() / 260) * 0.15
    dxDrawRectangle(sx - w / 2, sy - h / 2, w, h, tocolor(20, 20, 26, math.floor(200 * pulse)))
    dxDrawRectangle(sx - w / 2, sy + h / 2 - 3 * S, w, 3 * S, tocolor(255, 90, 140, 230))
    dxDrawText(text, sx - w / 2, sy - h / 2, sx + w / 2, sy + h / 2 - 2 * S, tocolor(255, 255, 255, 255), 1 * S, "default-bold", "center", "center")
end

----------------------------------------------------------------
-- Interaccion
----------------------------------------------------------------
local function blocked()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return true end
    local ok, open = pcall(function() return exports.rp_inventory:isInventoryOpen() end)
    return ok and open == true
end

local function startInteraction(ped)
    if ui or not talkable(ped) then return end
    local adopt = getElementData(ped, "rp:citizen")
    if adopt then
        local ok, res = pcall(function() return exports.rp_citizens:citizenAdopt(ped) end)
        if not ok or not res then return end   -- el recurso de peatones no entrega al ped
    end
    setPedControlState(ped, "forwards", false)
    setPedControlState(ped, "walk", false)
    setPedControlState(ped, "sprint", false)
    ui = {
        ped = ped, pending = true, t0 = now(), npcId = getElementData(ped, "rp:npcrel"),
        shot = "wide", bars = 0, hover = nil, rects = {}, shown = { f = 0, r = 0 },
        subtitle = nil, busy = false, lastSend = 0,
    }
    triggerServerEvent("rp:npcrel:ui:begin", resourceRoot, getElementModel(ped), ui.npcId)
    -- Si el servidor no abre la conversacion, la persona sigue su camino
    setTimer(function()
        if ui and ui.pending and ui.ped == ped then
            local p = ped
            ui = nil
            if isElement(p) then sendAway(p) end
        end
    end, 3500, 1)
end

local function closeInteraction(tellServer)
    if not ui then return end
    local ped = ui.ped
    if tellServer then triggerServerEvent("rp:npcrel:ui:end", resourceRoot) end
    clearAnim(localPlayer)
    showCursor(false)
    toggleAllControls(true, true, false)
    local wasOpen, bars = not ui.pending, ui.bars or 0
    ui = nil
    if wasOpen and camState then
        -- salida suave: la camara vuelve detras del jugador y se entrega al juego
        local fake = { ped = ped, shot = "exit", data = { stage = 1 }, bars = bars, rects = {} }
        ui = fake
        setTimer(function()
            if ui == fake then ui = nil end
            camState = nil
            setCameraTarget(localPlayer)
        end, 750, 1)
    else
        camState = nil
    end
    if isElement(ped) then
        if getElementData(ped, "rp:npcrel") then
            setTimer(function() if isElement(ped) then sendAway(ped) end end, 1500, 1)
        else
            sendAway(ped)
        end
    end
    if banner then banner = nil end
end

addEventHandler("rp:npcrel:open", resourceRoot, function(data)
    if not ui or not ui.pending or not isElement(ui.ped) then
        triggerServerEvent("rp:npcrel:ui:end", resourceRoot)
        return
    end
    ui.pending, ui.data, ui.t0 = false, data, now()
    ui.shown = { f = data.friendship, r = data.romance }
    local px, py, pz = getElementPosition(localPlayer)
    local nx, ny = getElementPosition(ui.ped)
    if getDistanceBetweenPoints2D(px, py, nx, ny) > 1.9 then placeNpc(1.6) end
    faceEachOther()
    playAnim(ui.ped, { "PED", "IDLE_chat" })
    toggleAllControls(false, true, false)
    showCursor(true, false)
    local cx, cy, cz = getCameraMatrix()
    camState = { init = true, x = cx, y = cy, z = cz, lx = px, ly = py, lz = pz, fov = 70 }
    lastCamTick = now()
    shot("wide", 900, "over")
    -- Saludo
    local f = ui.data.stage >= 4 and "Hola, qué sorpresa verte." or (ui.data.stage >= 2 and "¡Hola de nuevo!" or "Hola… ¿nos conocemos?")
    ui.subtitle = { text = f, t0 = now() }
end)

addEventHandler("rp:npcrel:result", resourceRoot, function(res)
    if not ui or ui.pending or not isElement(ui.ped) then return end
    ui.busy = false
    local old = ui.data
    ui.data = res.state
    ui.subtitle = { text = res.text or "", t0 = now() }
    local x, y, z = headPos(ui.ped)
    local gainR = res.gain and res.gain.romance or 0
    local gainF = res.gain and res.gain.friendship or 0

    startAnimations(res.action, res.outcome)

    if res.outcome == "bad" then
        rejectFx(ui.ped)
        shot("closeNpc", 1700, ui.alt and "reverse" or "over")
    else
        if res.action == "kiss" then
            ui.orbitT0, ui.orbitR = now(), 2.1
            local mx, my = getElementPosition(localPlayer)
            local cx, cy = camState and camState.x or mx, camState and camState.y or my
            ui.orbitA0 = math.atan2(cy - my, cx - mx)
            shot("orbit", ANIM_MS.kiss, "over")
            for i = 1, 14 do setTimer(function() if ui then local hx, hy, hz = headPos(ui.ped) hearts(hx, hy, hz + 0.1, 1 + (i % 2), true) end end, i * 380, 1) end
        elseif res.outcome == "great" then
            shot("closeNpc", 1500, ui.alt and "reverse" or "over")
        else
            shot(ui.alt and "reverse" or "over", nil, nil)
            if math.random() < 0.5 then shot("closePlayer", 1100, ui.alt and "reverse" or "over") end
        end
        ui.alt = not ui.alt
        if gainR > 0 or res.celebrate then hearts(x, y, z + 0.15, res.outcome == "great" and 8 or math.min(5, 2 + gainR), res.outcome == "great") end
        if gainF > 0 then sparks(x, y, z + 0.1, res.outcome == "great" and 10 or 5, { 255, 240, 160 }) end
    end
    if res.celebrate then
        confetti(x, y, z, 50)
        setTimer(function() if ui then local cx2, cy2, cz2 = headPos(ui.ped) confetti(cx2, cy2, cz2, 30) end end, 700, 1)
    end
    if res.stageUp and old then
        banner = { text = "¡" .. res.state.stageName:upper() .. "!", sub = res.state.name, t0 = now() }
        sparks(x, y, z + 0.4, 14, { 255, 210, 90 })
    end
    if res.ended then
        ui.ending = true
        setTimer(function() if ui and ui.ending then closeInteraction(false) end end, 2700, 1)
    end
end)

-- Numero guardado: lluvia de corazones sobre quien te lo dio
addEventHandler("rp:npcrel:numberShared", resourceRoot, function(name, auto)
    if not ui or not isElement(ui.ped) then return end
    local x, y, z = headPos(ui.ped)
    hearts(x, y, z + 0.2, auto and 16 or 8, true)
    if auto then confetti(x, y, z, 24) end
end)

local function sendAction(id)
    if not ui or ui.pending or ui.busy or ui.ending then return end
    if now() - ui.lastSend < NPCREL.ACTION_COOLDOWN - 100 then return end
    ui.lastSend, ui.busy = now(), true
    triggerServerEvent("rp:npcrel:ui:act", resourceRoot, id)
    setTimer(function() if ui then ui.busy = false end end, 5000, 1)
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local KIND_COLOR = { friend = { 90, 170, 255 }, romance = { 255, 90, 140 }, special = { 255, 190, 80 } }
-- Se llena al primer uso: los scripts de cliente con cache="false" pueden ejecutarse antes que los compartidos
local KIND_OF = {}
local function kindOf(id)
    if next(KIND_OF) == nil then
        for _, a in ipairs(NPCREL_ACTIONS) do KIND_OF[a.id] = a.kind end
    end
    return KIND_OF[id]
end

local function bar(x, y, w, h, value, shown, r, g, b, label)
    dxDrawText(label, x, y - 17 * S, x + w, y, tocolor(230, 230, 235, 255), 0.85 * S, "default-bold")
    dxDrawText(tostring(math.floor(value)), x, y - 17 * S, x + w, y, tocolor(230, 230, 235, 255), 0.85 * S, "default-bold", "right")
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 30))
    dxDrawRectangle(x, y, w * clamp(shown / 100, 0, 1), h, tocolor(r, g, b, 235))
    dxDrawRectangle(x, y, w * clamp(shown / 100, 0, 1), h / 2, tocolor(255, 255, 255, 40))
end

local function drawCard(alpha)
    local d = ui.data
    local x, y, w = screenW * 0.04, screenH * 0.2, 330 * S
    local h = 232 * S
    dxDrawRectangle(x, y, w, h, tocolor(14, 14, 20, math.floor(205 * alpha)))
    dxDrawRectangle(x, y, 4 * S, h, tocolor(255, 90, 140, math.floor(255 * alpha)))
    local a = math.floor(255 * alpha)
    dxDrawText(d.name, x + 18 * S, y + 10 * S, x + w - 10, y + 40 * S, tocolor(255, 255, 255, a), 1.35 * S, "default-bold")
    -- etapa
    local sc = d.stage >= 5 and { 255, 90, 140 } or (d.stage >= 4 and { 255, 140, 170 } or (d.stage >= 3 and { 120, 200, 255 } or { 190, 190, 200 }))
    local sw = dxGetTextWidth(d.stageName, 0.95 * S, "default-bold") + 18 * S
    dxDrawRectangle(x + 18 * S, y + 44 * S, sw, 22 * S, tocolor(sc[1], sc[2], sc[3], math.floor(60 * alpha)))
    dxDrawText(d.stageName, x + 18 * S, y + 44 * S, x + 18 * S + sw, y + 66 * S, tocolor(sc[1], sc[2], sc[3], a), 0.95 * S, "default-bold", "center", "center")
    bar(x + 18 * S, y + 98 * S, w - 36 * S, 9 * S, d.friendship, ui.shown.f, 90, 170, 255, "Amistad")
    bar(x + 18 * S, y + 134 * S, w - 36 * S, 9 * S, d.romance, ui.shown.r, 255, 90, 140, "Romance")
    -- rasgos y humor
    local line = d.mood and ("Humor: " .. d.mood) or ""
    if #d.traits > 0 then line = table.concat(d.traits, " · ") .. "   |   " .. line end
    dxDrawText(line, x + 18 * S, y + 160 * S, x + w - 10, y + 184 * S, tocolor(200, 200, 210, a), 0.9 * S, "default-bold")
    dxDrawText(("Conversación: %d acciones restantes"):format(d.left or 0), x + 18 * S, y + 192 * S, x + w - 10, y + 216 * S, tocolor(150, 150, 165, a), 0.8 * S, "default-bold")
    -- barritas sobre la cabeza de la persona
    local hx, hy, hz = headPos(ui.ped)
    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.32)
    if sx then
        local bw = 70 * S
        dxDrawRectangle(sx - bw / 2, sy, bw, 5 * S, tocolor(0, 0, 0, 140))
        dxDrawRectangle(sx - bw / 2, sy, bw * clamp(ui.shown.f / 100, 0, 1), 5 * S, tocolor(90, 170, 255, 230))
        dxDrawRectangle(sx - bw / 2, sy + 7 * S, bw, 5 * S, tocolor(0, 0, 0, 140))
        dxDrawRectangle(sx - bw / 2, sy + 7 * S, bw * clamp(ui.shown.r / 100, 0, 1), 5 * S, tocolor(255, 90, 140, 230))
    end
end

local function drawMenu(alpha)
    local d = ui.data
    local cx, cy = screenW * 0.77, screenH * 0.5
    local rx, ry = 205 * S, screenH * 0.3
    local bw, bh = 172 * S, 44 * S
    local n = #d.actions
    local mx, my = 0, 0
    if isCursorShowing() then
        local rx2, ry2 = getCursorPosition()
        mx, my = rx2 * screenW, ry2 * screenH
    end
    ui.hover = nil
    ui.rects = {}
    for i, a in ipairs(d.actions) do
        local ang = -math.pi / 2 + (i - 1) * 2 * math.pi / n
        local bx, by = cx + math.cos(ang) * rx - bw / 2, cy + math.sin(ang) * ry - bh / 2
        local kc = KIND_COLOR[kindOf(a.id)] or KIND_COLOR.friend
        local over = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
        local usable = a.enabled and not ui.busy and not ui.ending
        if over and a.enabled then ui.hover = a.id end
        ui.rects[#ui.rects + 1] = { id = a.id, x = bx, y = by, w = bw, h = bh, ok = usable }
        local fade = math.floor(255 * alpha)
        -- hilo hasta el centro
        dxDrawLine(cx, cy, bx + bw / 2, by + bh / 2, tocolor(kc[1], kc[2], kc[3], math.floor((a.enabled and 55 or 20) * alpha)), 1)
        local bg = a.enabled and (over and usable and 235 or 190) or 120
        dxDrawRectangle(bx, by, bw, bh, tocolor(14, 14, 20, math.floor(bg * alpha)))
        dxDrawRectangle(bx, by, 5 * S, bh, tocolor(kc[1], kc[2], kc[3], math.floor((a.enabled and 255 or 70) * alpha)))
        if over and usable then dxDrawRectangle(bx, by, bw, bh, tocolor(kc[1], kc[2], kc[3], math.floor(45 * alpha))) end
        local col = a.enabled and tocolor(255, 255, 255, fade) or tocolor(130, 130, 140, fade)
        if a.hint ~= "" then
            dxDrawText(a.label, bx + 16 * S, by + 3 * S, bx + bw - 6, by + bh * 0.62, col, 1 * S, "default-bold", "left", "center")
            dxDrawText(a.hint, bx + 16 * S, by + bh * 0.55, bx + bw - 6, by + bh - 2, tocolor(kc[1], kc[2], kc[3], math.floor((a.enabled and 230 or 150) * alpha)), 0.75 * S, "default-bold", "left", "center")
        else
            dxDrawText(a.label, bx + 16 * S, by, bx + bw - 6, by + bh, col, 1 * S, "default-bold", "left", "center")
        end
    end
    dxDrawText("Backspace: salir", cx - 120 * S, cy - 10 * S, cx + 120 * S, cy + 12 * S, tocolor(190, 190, 200, math.floor(150 * alpha)), 0.8 * S, "default-bold", "center", "center")
end

local function drawSubtitle()
    local s = ui.subtitle
    if not s then return end
    local age = now() - s.t0
    if age > 6500 then ui.subtitle = nil return end
    local shownChars = math.min(#s.text, math.floor(age / 22))
    local text = s.text:sub(1, shownChars)
    -- recortar sin partir un caracter UTF-8 a la mitad
    while #text > 0 and text:byte(#text) >= 0x80 and text:byte(#text) < 0xC0 do text = text:sub(1, #text - 1) end
    local fade = age > 5800 and 1 - (age - 5800) / 700 or 1
    local y = screenH * 0.89 - 66 * S
    dxDrawText(text, screenW * 0.2 + 1, y + 1, screenW * 0.8 + 1, y + 60 * S + 1, tocolor(0, 0, 0, math.floor(230 * fade)), 1.25 * S, "default-bold", "center", "center", false, true)
    dxDrawText(text, screenW * 0.2, y, screenW * 0.8, y + 60 * S, tocolor(255, 255, 255, math.floor(255 * fade)), 1.25 * S, "default-bold", "center", "center", false, true)
end

local function drawBanner()
    if not banner then return end
    local age = now() - banner.t0
    if age > 3200 then banner = nil return end
    local k = clamp(age / 350, 0, 1)
    local pop = 1 + (1 - k) * 0.8
    local fade = age > 2600 and 1 - (age - 2600) / 600 or 1
    local a = math.floor(255 * fade * k)
    local y = screenH * 0.2
    dxDrawText(banner.text, 2, y + 2, screenW + 2, y + 80 * S + 2, tocolor(0, 0, 0, math.floor(a * 0.8)), 3 * S * pop, "default-bold", "center", "center")
    dxDrawText(banner.text, 0, y, screenW, y + 80 * S, tocolor(255, 110, 160, a), 3 * S * pop, "default-bold", "center", "center")
    dxDrawText(banner.sub or "", 0, y + 70 * S, screenW, y + 100 * S, tocolor(255, 255, 255, a), 1.1 * S, "default-bold", "center", "center")
end

local lastRender = 0
addEventHandler("onClientRender", root, function()
    local t = now()
    local dt = clamp((t - lastRender) / 1000, 0, 0.05)
    lastRender = t
    updateParts(dt)
    drawPrompt()
    if ui then
        local goal = (ui.pending or ui.shot == "exit") and 0 or 1
        ui.bars = ui.bars + (goal - ui.bars) * (1 - math.exp(-dt * 5))
        if ui.ped and isElement(ui.ped) then updateCamera() end
        local barH = screenH * 0.11 * (ui.bars or 0)
        dxDrawRectangle(0, 0, screenW, barH, tocolor(0, 0, 0, 255))
        dxDrawRectangle(0, screenH - barH, screenW, barH, tocolor(0, 0, 0, 255))
        if ui.data and not ui.pending and ui.shot ~= "exit" then
            local alpha = clamp((t - ui.t0) / 450, 0, 1)
            local k = 1 - math.exp(-dt * 6)
            ui.shown.f = ui.shown.f + (ui.data.friendship - ui.shown.f) * k
            ui.shown.r = ui.shown.r + (ui.data.romance - ui.shown.r) * k
            drawCard(alpha)
            drawMenu(alpha)
            drawSubtitle()
        end
    end
    drawParts()
    drawBanner()
end)

addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" or not ui or ui.pending or not ui.rects then return end
    for _, r in ipairs(ui.rects) do
        if r.ok and ui.hover == r.id then return sendAction(r.id) end
    end
end)

----------------------------------------------------------------
-- Arranque, teclas y limpieza
----------------------------------------------------------------
local function guard()
    if ui and not ui.pending and ui.shot ~= "exit" then
        local ped = ui.ped
        local px, py, pz = getElementPosition(localPlayer)
        local bad = not isElement(ped) or isPedDead(ped) or isPedDead(localPlayer) or isPedInVehicle(localPlayer)
            or getElementData(localPlayer, "rp:downed")
        if not bad then
            local x, y, z = getElementPosition(ped)
            bad = getDistanceBetweenPoints3D(px, py, pz, x, y, z) > 6
        end
        if bad then closeInteraction(true) end
    end
    scanTarget()
    updateVisitors()
    updateLeavers()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(guard, 200, 0)
    bindKey(NPCREL.KEY, "down", function()
        if ui or blocked() or not target then return end
        startInteraction(target)
    end)
    bindKey("backspace", "down", function()
        if ui and not ui.pending and not ui.ending then closeInteraction(true) end
    end)
end)

local function destroyAll()
    for ped in pairs(visitors) do if isElement(ped) then destroyElement(ped) end end
    for ped in pairs(leavers) do if isElement(ped) then destroyElement(ped) end end
    if ui then
        clearAnim(localPlayer)
        showCursor(false)
        toggleAllControls(true, true, false)
        setCameraTarget(localPlayer)
    end
end
addEventHandler("onClientResourceStop", resourceRoot, destroyAll)
addEventHandler("onClientPlayerWasted", localPlayer, function() if ui then closeInteraction(true) end end)
