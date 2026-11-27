--[[
    rp_npcrel / c_npcrel.lua

    Parte visual del sistema de vinculos: aviso con la tecla H dibujada sobre el peaton
    cercano, camara de escena (plano general -> sobre el hombro -> contraplano ->
    primer plano -> orbita en el beso), barras negras, animaciones de ambos,
    corazones/destellos/confeti, globo de emocion sobre la cabeza y la visita de la
    persona a la que llamas por telefono.
    La ficha, las acciones, el dialogo, el tutorial y el panel /vinculos son CEF (html/).
    Todo lo que cuenta (resultado, dinero, etapa, frases) lo decide el servidor.
]]

local screenW, screenH = guiGetScreenSize()
local S = math.max(0.75, screenH / 900)

addEvent("rp:npcrel:open", true)
addEvent("rp:npcrel:result", true)
addEvent("rp:npcrel:numberShared", true)
addEvent("rp:npcrel:summon", true)
addEvent("rp:npcrel:list", true)
-- Desde el CEF
addEvent("rp:npcrel:ui:pick", false)
addEvent("rp:npcrel:ui:leave", false)
addEvent("rp:npcrel:ui:closeList", false)
addEvent("rp:npcrel:ui:tutorialDone", false)

local IMG = { heart = "images/heart.png", spark = "images/spark.png" }
local TUTORIAL_FILE = "@tutorial_vinculos.done"

local ui = nil          -- conversacion en curso
local visitors = {}     -- [ped] = estado de la persona que viene tras una llamada
local leavers = {}      -- [ped] = { startT } peds que se van caminando
local parts = {}        -- particulas
local target = nil      -- ped al que se puede hablar ahora
local camState = nil    -- camara suavizada
local emote = nil       -- globo de emocion sobre la persona { tex, t0 }
local tex = {}          -- texturas dx (se crean una vez)
local timers = {}       -- timers con nombre, para poder cancelarlos

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function rotTo(dx, dy) return math.deg(math.atan2(-dx, dy)) end
local function pick(list) return list[math.random(#list)] end
local function now() return getTickCount() end
local function notify(text, kind) pcall(function() exports.rp_notify:notify(text, kind) end) end
local function firstName(name) return (tostring(name or ""):match("^(%S+)")) or tostring(name or "") end
-- estandar:dep-opcional rp_citizens  peatones (citizenAdopt, citizenWalkSpot); se comprueba con running()
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

-- Timer con nombre: si ya habia uno con ese nombre lo cancela
local function after(name, ms, fn)
    if timers[name] and isTimer(timers[name]) then killTimer(timers[name]) end
    timers[name] = setTimer(function() timers[name] = nil fn() end, math.max(50, ms), 1)
end
local function cancel(name)
    if timers[name] and isTimer(timers[name]) then killTimer(timers[name]) end
    timers[name] = nil
end

local function headPos(el)
    local x, y, z = getPedBonePosition(el, 8)
    if not x then x, y, z = getElementPosition(el) z = z + 0.7 end
    return x, y, z
end

----------------------------------------------------------------
-- Navegador CEF (uno, precreado y oculto)
----------------------------------------------------------------
local browserGui, browser, browserReady, pendingJS = nil, nil, false, {}
local listOpen = false

local function callJS(code)
    if isElement(browser) and browserReady then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function jsData(t)
    local json = toJSON(t or {}, true)
    return (json:gsub("<", "\\u003c")) .. "[0]"
end

local function createBrowserUI()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    browserReady, pendingJS = false, {}
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        browserReady = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local function showBrowser(on)
    if not isElement(browserGui) then return end
    cancel("hideBrowser")
    if on then
        guiSetVisible(browserGui, true)
        guiBringToFront(browserGui)
        focusBrowser(browser)
        showCursor(true, false)
        guiSetInputEnabled(true)
    else
        guiSetInputEnabled(false)
        showCursor(false)
        -- deja terminar la animacion de salida del panel
        after("hideBrowser", 420, function()
            if not ui and not listOpen and isElement(browserGui) then guiSetVisible(browserGui, false) end
        end)
    end
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
-- Globo de emocion sobre la cabeza (Kenney Emotes, CC0)
----------------------------------------------------------------
local EMOTES = { "hearts", "heart", "faceHappy", "laugh", "faceSad", "anger", "heartBroken", "question", "dots3", "stars", "exclamation" }

local function showEmote(name)
    if tex[name] then emote = { tex = tex[name], t0 = now() } end
end

local function emoteFor(res)
    if res.stageUp then return "stars" end
    if res.reject == "romance" then return "heartBroken" end
    if res.bored then return "dots3" end
    if res.outcome == "bad" then return res.action == "flirt" and "anger" or (res.action == "number" and "question" or "faceSad") end
    if res.action == "bye" then return nil end
    if res.action == "joke" then return "laugh" end
    if res.action == "number" then return "exclamation" end
    local kind
    for _, a in ipairs(NPCREL_ACTIONS) do if a.id == res.action then kind = a.kind end end
    if kind == "romance" or res.action == "askout" then return res.outcome == "great" and "hearts" or "heart" end
    return res.outcome == "great" and "stars" or "faceHappy"
end

local function drawEmote()
    if not emote or not ui or not isElement(ui.ped) then return end
    local age = now() - emote.t0
    if age > 2600 then emote = nil return end
    local x, y, z = headPos(ui.ped)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.42)
    if not sx then return end
    local k = clamp(age / 220, 0, 1)
    local pop = 1 + math.sin(k * math.pi) * 0.25
    local fade = age > 2200 and 1 - (age - 2200) / 400 or 1
    local w = 46 * S * pop * (0.4 + 0.6 * k)
    local h = w * 38 / 32
    local bob = math.sin(age / 180) * 3 * S
    dxDrawImage(sx - w / 2, sy - h + bob, w, h, emote.tex, 0, 0, 0, tocolor(255, 255, 255, math.floor(255 * fade)))
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
    after("anim", ms + 80, function()
        clearAnim(localPlayer)
        if ui and ui.ped == ped and isElement(ped) then playAnim(ped, { "PED", "IDLE_chat" }) end
    end)
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

-- Punto de aparicion en una acera (rp_citizens es opcional)
local function walkSpot(minD, maxD)
    if not running("rp_citizens") then return nil end
    local ok, sx, sy, sz, sr = pcall(function() return exports.rp_citizens:citizenWalkSpot(minD, maxD, true) end)
    if ok and sx then return sx, sy, sz, sr end
    return nil
end

local function spawnVisitor(data)
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z, rot = walkSpot(32, 55)
    if not x then
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
    notify(firstName(data.name) .. " está llegando.", "info")
end

local function updateVisitors()
    local px, py = getElementPosition(localPlayer)
    for ped, v in pairs(visitors) do
        if not isElement(ped) then
            visitors[ped] = nil
        elseif ui and ui.ped == ped then
            v.expire = math.max(v.expire, now() + 20000)
        elseif now() > v.expire then
            sendAway(ped)
        else
            local x, y = getElementPosition(ped)
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
                                local sx, sy, sz = walkSpot(9, 16)
                                if sx then setElementPosition(ped, sx, sy, sz + 1) end
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
                    notify(firstName(v.name) .. " llegó. Pulsa " .. string.upper(NPCREL.KEY) .. " para hablar.", "success")
                end
            end
        end
    end
end

addEventHandler("rp:npcrel:summon", resourceRoot, spawnVisitor)

----------------------------------------------------------------
-- Aviso con la tecla dibujada sobre el peaton cercano
----------------------------------------------------------------
local function talkable(ped)
    if not isElement(ped) or isPedDead(ped) or isPedInVehicle(ped) or leavers[ped] then return false end
    if not (getElementData(ped, "rp:npcrel") or getElementData(ped, "rp:citizen")) then return false end
    if getElementData(ped, "rp:cop") then return false end
    return NPCREL_SKIN_GENDER[getElementModel(ped)] ~= nil
end

local function scanTarget()
    target = nil
    if ui or listOpen or isPedInVehicle(localPlayer) or isPedDead(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
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
    if best ~= target then target = best end
end

local promptT0, promptPed = 0, nil
local function drawPrompt()
    if not target or ui or not isElement(target) then promptPed = nil return end
    if promptPed ~= target then promptPed, promptT0 = target, now() end
    local x, y, z = headPos(target)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.38)
    if not sx then return end
    local v = visitors[target]
    local label = v and ("Hablar con " .. firstName(v.name)) or "Hablar"
    local k = clamp((now() - promptT0) / 200, 0, 1)
    local a = math.floor(255 * k)
    local key = 34 * S * (1 + math.sin(now() / 230) * 0.05)
    local tw = dxGetTextWidth(label, 1.05 * S, "default-bold")
    local w = key + 10 * S + tw + 18 * S
    local h = 40 * S
    local x0 = sx - w / 2
    local y0 = sy - h / 2 - (1 - k) * 8 * S
    dxDrawRectangle(x0, y0, w, h, tocolor(16, 14, 22, math.floor(215 * k)))
    dxDrawRectangle(x0, y0 + h - 3 * S, w, 3 * S, v and tocolor(255, 90, 140, a) or tocolor(90, 170, 255, a))
    dxDrawImage(x0 + 6 * S, y0 + (h - key) / 2, key, key, tex.keyH, 0, 0, 0, tocolor(255, 255, 255, a))
    if v then dxDrawImage(x0 + w - 4 * S, y0 - 12 * S, 22 * S, 22 * S, IMG.heart, 0, 0, 0, tocolor(255, 90, 140, a)) end
    dxDrawText(label, x0 + key + 14 * S, y0, x0 + w, y0 + h - 2 * S, tocolor(255, 255, 255, a), 1.05 * S, "default-bold", "left", "center")
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
    if ui or listOpen or not talkable(ped) then return end
    if getElementData(ped, "rp:citizen") then
        if not running("rp_citizens") then return end
        local ok, res = pcall(function() return exports.rp_citizens:citizenAdopt(ped) end)
        if not ok or not res then return end   -- el recurso de peatones no entrega al ped
    end
    setPedControlState(ped, "forwards", false)
    setPedControlState(ped, "walk", false)
    setPedControlState(ped, "sprint", false)
    ui = { ped = ped, pending = true, t0 = now(), npcId = getElementData(ped, "rp:npcrel"), shot = "wide", bars = 0, busy = false, lastSend = 0 }
    triggerServerEvent("rp:npcrel:ui:begin", resourceRoot, getElementModel(ped), ui.npcId)
    -- Si el servidor no abre la conversacion, la persona sigue su camino
    after("pending", 3500, function()
        if ui and ui.pending and ui.ped == ped then
            ui = nil
            if isElement(ped) then sendAway(ped) end
        end
    end)
end

local function closeInteraction(tellServer)
    if not ui then return end
    local ped = ui.ped
    if tellServer then triggerServerEvent("rp:npcrel:ui:end", resourceRoot) end
    cancel("busy") cancel("ending") cancel("anim") cancel("pending")
    clearAnim(localPlayer)
    callJS("RP.close()")
    showBrowser(false)
    toggleAllControls(true, true, false)
    emote = nil
    local wasOpen, bars = not ui.pending, ui.bars or 0
    ui = nil
    if wasOpen and camState then
        -- salida suave: la camara vuelve detras del jugador y se entrega al juego
        local fake = { ped = ped, shot = "exit", data = { stage = 1 }, bars = bars, exiting = true }
        ui = fake
        after("exit", 750, function()
            if ui == fake then ui = nil end
            camState = nil
            setCameraTarget(localPlayer)
        end)
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
end

addEventHandler("rp:npcrel:open", resourceRoot, function(data)
    if not ui or not ui.pending or not isElement(ui.ped) then
        triggerServerEvent("rp:npcrel:ui:end", resourceRoot)
        return
    end
    cancel("pending")
    ui.pending, ui.data, ui.t0 = false, data, now()
    local px, py, pz = getElementPosition(localPlayer)
    local nx, ny = getElementPosition(ui.ped)
    if getDistanceBetweenPoints2D(px, py, nx, ny) > 1.9 then placeNpc(1.6) end
    faceEachOther()
    playAnim(ui.ped, { "PED", "IDLE_chat" })
    playAnim(localPlayer, { "GANGS", "prtial_gngtlkA" })
    after("anim", 1800, function() clearAnim(localPlayer) end)
    toggleAllControls(false, true, false)
    local cx, cy, cz = getCameraMatrix()
    camState = { init = true, x = cx, y = cy, z = cz, lx = px, ly = py, lz = pz, fov = 70 }
    lastCamTick = now()
    shot("wide", 900, "over")
    showEmote(data.stage >= 4 and "heart" or (data.stage >= 2 and "faceHappy" or "question"))
    callJS(("RP.open(%s, %s)"):format(jsData(data), tostring(not fileExists(TUTORIAL_FILE))))
    showBrowser(true)
end)

addEventHandler("rp:npcrel:result", resourceRoot, function(res)
    if not ui or ui.pending or not isElement(ui.ped) then return end
    ui.busy = false
    cancel("busy")
    ui.data = res.state
    callJS(("RP.result(%s)"):format(jsData(res)))
    local x, y, z = headPos(ui.ped)
    local gainR = res.gain and res.gain.romance or 0
    local gainF = res.gain and res.gain.friendship or 0

    startAnimations(res.action, res.outcome)
    local em = emoteFor(res)
    if em then after("emote", 500, function() showEmote(em) end) end

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
            for i = 1, 14 do setTimer(function() if ui and isElement(ui.ped) then local hx, hy, hz = headPos(ui.ped) hearts(hx, hy, hz + 0.1, 1 + (i % 2), true) end end, i * 380, 1) end
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
        setTimer(function() if ui and isElement(ui.ped) then local cx2, cy2, cz2 = headPos(ui.ped) confetti(cx2, cy2, cz2, 30) end end, 700, 1)
    end
    if res.stageUp then sparks(x, y, z + 0.4, 14, { 255, 210, 90 }) end
    if res.ended then
        -- deja leer las frases (accion + etapa + cansancio) antes de cerrar
        local chars = #(res.text or "") + #(res.stageText or "") + #(res.tiredText or "") + #(res.playerText or "")
        ui.ending = true
        after("ending", 2600 + chars * 28, function() if ui and ui.ending then closeInteraction(false) end end)
    end
end)

-- Numero guardado: lluvia de corazones sobre quien te lo dio
addEventHandler("rp:npcrel:numberShared", resourceRoot, function(name, auto)
    if not ui or not isElement(ui.ped) then return end
    local x, y, z = headPos(ui.ped)
    hearts(x, y, z + 0.2, auto and 16 or 8, true)
    if auto then confetti(x, y, z, 24) end
    callJS(("RP.toast(%s, true)"):format(jsString("📱 " .. firstName(name) .. " te dio su número")))
end)

local function sendAction(id)
    if not ui or ui.pending or ui.busy or ui.ending or ui.exiting then return end
    if now() - ui.lastSend < NPCREL.ACTION_COOLDOWN - 100 then return callJS("RP.unbusy()") end
    ui.lastSend, ui.busy = now(), true
    triggerServerEvent("rp:npcrel:ui:act", resourceRoot, id)
    -- si el servidor no contesta (sin dinero, accion invalida), se vuelve a poder elegir
    after("busy", 3000, function() if ui then ui.busy = false callJS("RP.unbusy()") end end)
end

addEventHandler("rp:npcrel:ui:pick", root, function(id)
    if type(id) == "string" then sendAction(id) end
end)
addEventHandler("rp:npcrel:ui:leave", root, function()
    if ui and not ui.pending and not ui.ending and not ui.exiting then closeInteraction(true) end
end)
addEventHandler("rp:npcrel:ui:tutorialDone", root, function()
    if fileExists(TUTORIAL_FILE) then return end
    local f = fileCreate(TUTORIAL_FILE)
    if f then fileWrite(f, "1") fileClose(f) end
end)

----------------------------------------------------------------
-- Panel /vinculos
----------------------------------------------------------------
local function closeList()
    if not listOpen then return end
    listOpen = false
    callJS("RP.closeList()")
    showBrowser(false)
end

addEventHandler("rp:npcrel:list", resourceRoot, function(list, max, days)
    if ui then return end
    listOpen = true
    callJS(("RP.list(%s, %d, %d)"):format(jsData(list), tonumber(max) or 40, tonumber(days) or 3))
    showBrowser(true)
end)
addEventHandler("rp:npcrel:ui:closeList", root, closeList)

----------------------------------------------------------------
-- Dibujo dx (barras de cine, aviso, globo, particulas)
----------------------------------------------------------------
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
        drawEmote()
    end
    drawParts()
end)

----------------------------------------------------------------
-- Arranque, teclas y limpieza
----------------------------------------------------------------
local function guard()
    if ui and not ui.pending and not ui.exiting then
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
    if listOpen and (isPedDead(localPlayer) or getElementData(localPlayer, "rp:downed")) then closeList() end
    scanTarget()
    updateVisitors()
    updateLeavers()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.keyH = dxCreateTexture("images/keys/keyboard_h.png", "argb", true, "clamp")
    for _, name in ipairs(EMOTES) do tex[name] = dxCreateTexture("images/emotes/emote_" .. name .. ".png", "argb", true, "clamp") end
    createBrowserUI()
    timers.guard = setTimer(guard, 200, 0)
    bindKey(NPCREL.KEY, "down", function()
        if ui or listOpen or blocked() or not target then return end
        startInteraction(target)
    end)
    -- Respaldo por si el navegador pierde el foco (el CEF ya escucha Backspace/Esc)
    bindKey("backspace", "down", function()
        if listOpen then return closeList() end
        if ui and not ui.pending and not ui.ending and not ui.exiting then closeInteraction(true) end
    end)
end)

-- /npcdebug: que ve el sistema en los peatones cercanos (para diagnosticar "no sale Hablar")
addCommandHandler("npcdebug", function()
    local px, py, pz = getElementPosition(localPlayer)
    local list = getElementsByType("ped", root, true)
    outputChatBox(("[npcrel] peds cargados: %d | objetivo: %s | ui: %s | en vehiculo: %s"):format(
        #list, tostring(target), tostring(ui ~= nil), tostring(isPedInVehicle(localPlayer))), 255, 200, 120)
    local near = {}
    for _, ped in ipairs(list) do
        if ped ~= localPlayer then
            local x, y, z = getElementPosition(ped)
            near[#near + 1] = { ped = ped, d = getDistanceBetweenPoints3D(px, py, pz, x, y, z) }
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    for i = 1, math.min(6, #near) do
        local ped = near[i].ped
        outputChatBox(("  %.1f m | skin %d | citizen=%s | genero=%s | talkable=%s | vehiculo=%s | muerto=%s"):format(
            near[i].d, getElementModel(ped), tostring(getElementData(ped, "rp:citizen")),
            tostring(NPCREL_SKIN_GENDER and NPCREL_SKIN_GENDER[getElementModel(ped)]), tostring(talkable(ped)),
            tostring(isPedInVehicle(ped)), tostring(isPedDead(ped))), 255, 255, 255)
    end
    if #near == 0 then outputChatBox("  No hay peds cargados cerca: rp_citizens no esta generando peatones (revisa /traficostats).", 255, 120, 120) end
end)

local function destroyAll()
    for _, t in pairs(timers) do if isTimer(t) then killTimer(t) end end
    timers = {}
    for ped in pairs(visitors) do if isElement(ped) then destroyElement(ped) end end
    for ped in pairs(leavers) do if isElement(ped) then destroyElement(ped) end end
    if ui or listOpen then
        clearAnim(localPlayer)
        guiSetInputEnabled(false)
        showCursor(false)
        toggleAllControls(true, true, false)
        setCameraTarget(localPlayer)
    end
    if isElement(browserGui) then destroyElement(browserGui) end
end
addEventHandler("onClientResourceStop", resourceRoot, destroyAll)
addEventHandler("onClientPlayerWasted", localPlayer, function()
    if ui then closeInteraction(true) end
    closeList()
end)
