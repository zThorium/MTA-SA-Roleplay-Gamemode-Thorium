--[[
    rp_gym / c_fight.lua
    Combate con el entrenador en el ring, del lado del jugador que pelea.

    - Presentacion (si hay ring): plano del retador, plano del entrenador, plano general con cuenta 3-2-1
      y campana (GYM_FIGHT.INTRO_MS, el servidor espera lo mismo). Narrador: Kenney Voiceover Pack Fighter.
    - IA del entrenador: este cliente es su sincronizador (setPedControlState solo existe en el cliente).
    - Golpes: sonido de impacto (Kenney Impact Sounds) y sangre en los dos; el publico grita y anima a su lado;
      fotografos con flash.
    - Golpe recibido sin cubrirse (clic derecho + salto): aturdido 1-2 s, mareo y vision borrosa, sangre
      alrededor de la pantalla y quejido (audio del propio juego, PAIN_A con playSFX: no se copia nada).
    - Varios golpes seguidos sin cubrirse: puede caer; el arbitro cuenta hasta 10 y hay que pulsar Espacio
      rapido para llenar la barra y levantarse. Si llega a 10, pierde.
    - Al ganar: "K.O." y campana. Vidas, ring y resultado los decide el servidor (s_trainers.lua).
]]

addEvent("rp:gym:fight", true)

local sw, sh = guiGetScreenSize()
local S = math.max(0.8, math.min(1.4, sh / 900))
local F = nil            -- combate en curso
local fx = { blood = 0, dizzy = 0, flashes = {} }   -- efectos que se desvanecen aunque el combate acabe
local koShownAt, KO_MS = nil, 2800
local tex = {}
local screen = nil
local lastFrame = getTickCount()

local PAIN_BANK, PAIN_COUNT = 1, 131   -- PAIN_A, banco 1 (voz de CJ, 12 kHz): quejidos cortos

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function sound(path, volume)
    local s = playSound(path)
    if s and volume then setSoundVolume(s, volume) end
    return s
end
local function voice(name) return sound("sounds/voz/" .. name .. ".ogg", 1) end
local function bell() return sound("sounds/golpe/bell.ogg", 1) end

local function later(ms, fn)
    local t = setTimer(fn, ms, 1)
    if F then F.timers[#F.timers + 1] = t end
    return t
end

local function textures()
    if tex.blood then return end
    tex.blood = dxCreateTexture("images/blood.png", "argb", true, "clamp")
    tex.glow = dxCreateTexture("images/glow.png", "argb", true, "clamp")
    for _, k in ipairs({ "keyboard_space", "keyboard_space_outline", "mouse_right", "keyboard_shift" }) do
        tex[k] = dxCreateTexture("images/keys/" .. k .. ".png", "argb", true, "clamp")
    end
    screen = dxCreateScreenSource(math.floor(sw / 3), math.floor(sh / 3))   -- a baja resolucion: ya sale borroso
end

local function freeTextures()
    for k, t in pairs(tex) do if isElement(t) then destroyElement(t) end tex[k] = nil end
    if isElement(screen) then destroyElement(screen) end
    screen = nil
end

local function outlined(text, x, y, w, size, font, color, alpha, align)
    local black = tocolor(0, 0, 0, alpha)
    for ox = -2, 2, 2 do
        for oy = -2, 2, 2 do
            if ox ~= 0 or oy ~= 0 then dxDrawText(text, x + ox, y + oy, x + w + ox, y + oy, black, size, font, align or "center", "top") end
        end
    end
    dxDrawText(text, x, y, x + w, y, color, size, font, align or "center", "top")
end

local function crowdBy(side)
    local list = {}
    for _, c in ipairs(F and F.crowd or {}) do
        if c.side == side and isElement(c.ped) then list[#list + 1] = c.ped end
    end
    return list
end

local function setControls(on) toggleAllControls(on, true, false) end

----------------------------------------------------------------
-- Publico y fotografos
----------------------------------------------------------------
local function crowdReact(side)
    local now = getTickCount()
    if now - (F.lastCheer or 0) < 700 then return end
    F.lastCheer = now
    local peds = crowdBy(side)
    local texts = side == "player" and GYM_FIGHT.CHEER_PLAYER or GYM_FIGHT.CHEER_TRAINER
    for i = 1, math.min(#peds, math.random(1, 3)) do
        local ped = peds[math.random(#peds)]
        setPedAnimation(ped, "ON_LOOKERS", math.random() < 0.5 and "shout_01" or "shout_02", -1, false, false, false, false)
        setTimer(function()
            if isElement(ped) then setPedAnimation(ped, "RIOT", "RIOT_CHANT", -1, true, false, false, false) end
        end, 1500, 1)
        if i == 1 then exports.rp_notify:bubble(ped, texts[math.random(#texts)], 1600) end
    end
    if now - (F.lastRoar or 0) > 1200 then
        F.lastRoar = now
        sound("sounds/crowd_cheer.wav", 0.55)
    end
    F.nextFlash = math.min(F.nextFlash or 0, now + 200)   -- los fotografos disparan tras un buen golpe
end

local function flash(ped)
    local x, y, z = getPedBonePosition(ped, 25)   -- mano derecha
    if not x then return end
    local light = createLight(0, x, y, z + 0.2, 6, 255, 255, 255)
    if light then
        setElementInterior(light, getElementInterior(ped))
        setElementDimension(light, getElementDimension(ped))
        setTimer(function() if isElement(light) then destroyElement(light) end end, 90, 1)
    end
    fx.flashes[#fx.flashes + 1] = { x = x, y = y, z = z + 0.15, at = getTickCount() }
    local s = playSound3D("sounds/shutter.wav", x, y, z)
    if s then
        setElementInterior(s, getElementInterior(ped))
        setElementDimension(s, getElementDimension(ped))
        setSoundMaxDistance(s, 30)
    end
    setPedAnimation(ped, "CAMERA", "picstnd_take", -1, false, false, false, false)
    setTimer(function()
        if isElement(ped) then setPedAnimation(ped, "CAMERA", "camstnd_idleloop", -1, true, false, false, false) end
    end, 900, 1)
end

----------------------------------------------------------------
-- Golpes
----------------------------------------------------------------
local function hitFx(target, covered)
    if covered then
        sound("sounds/golpe/block_" .. math.random(0, 2) .. ".ogg", 0.8)
        return
    end
    local kind = math.random() < 0.4 and "heavy" or "medium"
    sound(("sounds/golpe/punch_%s_%d.ogg"):format(kind, math.random(0, 4)), 1)
    local x, y, z = getPedBonePosition(target, 8)   -- cabeza
    if x then
        fxAddBlood(x, y, z, 0, 0, 0.3, 6, 1)
        fxAddBlood(x, y, z - 0.25, 0, 0, -0.2, 4, 1)
    end
end

-- Cubrirse = mantener apuntar (clic derecho) y salto, o estar ya en la animacion de bloqueo del estilo
local function isCovered()
    local _, anim = getPedAnimation(localPlayer)
    if anim and tostring(anim):lower():find("block") then return true end
    return getPedControlState(localPlayer, "aim_weapon") and getPedControlState(localPlayer, "jump")
end

local function lose()
    if not F or F.phase == "over" then return end
    F.phase = "over"
    triggerServerEvent("rp:gym:lost", resourceRoot)
end

----------------------------------------------------------------
-- Caida y cuenta del arbitro
----------------------------------------------------------------
local function getUp()
    if not F or F.phase ~= "down" then return end
    F.phase = "rising"
    if isTimer(F.countTimer) then killTimer(F.countTimer) end
    triggerServerEvent("rp:gym:down", resourceRoot, false)
    voice("ready")
    crowdReact("player")
    later(1300, function()
        if not F or F.phase ~= "rising" then return end
        F.phase, F.streak, F.stunUntil = "live", 0, 0
        setControls(true)
    end)
end

local function startDown()
    F.phase, F.mash, F.count, F.pressedAt = "down", 0, 0, 0
    setControls(false)
    triggerServerEvent("rp:gym:down", resourceRoot, true)
    crowdReact("trainer")
    F.countTimer = setTimer(function()
        if not F or F.phase ~= "down" then return end
        F.count = F.count + 1
        voice(tostring(F.count))
        if isElement(F.referee) then
            setPedAnimation(F.referee, "RIOT", "RIOT_shout", -1, false, false, false, false)
        end
        if F.count >= 10 then
            later(900, function() if F and F.phase == "down" then lose() end end)
        end
    end, GYM_FIGHT.COUNT_MS, 10)
    F.timers[#F.timers + 1] = F.countTimer
end

addEventHandler("onClientPlayerDamage", localPlayer, function(attacker, weapon, bodypart, loss)
    if not F then return end
    if F.phase ~= "live" then   -- presentacion, en el suelo o levantandose: el entrenador no hace dano
        if attacker == F.ped then cancelEvent() end
        return
    end
    if loss >= getElementHealth(localPlayer) then   -- este golpe lo mataria: pierde (rp_injury no lo deja abatido)
        cancelEvent()
        return lose()
    end
    if attacker ~= F.ped then return end
    local covered = isCovered()
    hitFx(localPlayer, covered)
    crowdReact("trainer")
    if covered then F.streak = 0 return end

    local now = getTickCount()
    if now - (F.lastHitAt or 0) > GYM_FIGHT.STREAK_WINDOW_MS then F.streak = 0 end
    F.streak, F.lastHitAt = F.streak + 1, now
    local stun = math.min(GYM_FIGHT.STUN_MS[2], GYM_FIGHT.STUN_MS[1] + (F.streak - 1) * 500)
    F.stunUntil = now + stun
    setControls(false)
    if setCameraShakeLevel then setCameraShakeLevel(120) end
    fx.blood, fx.dizzy = math.min(1, fx.blood + 0.55), 1
    local pain = playSFX("pain_a", PAIN_BANK, math.random(0, PAIN_COUNT - 1), false)
    if pain then setSoundVolume(pain, 1) end
    if F.streak >= GYM_FIGHT.DOWN_STREAK and math.random() < GYM_FIGHT.DOWN_CHANCE then startDown() end
end)

addEventHandler("onClientPedDamage", root, function(attacker)
    if not F then return end
    if getElementData(source, "rp:gymCrowd") then return cancelEvent() end   -- publico y arbitro
    if source ~= F.ped then return end
    if F.phase ~= "live" then return cancelEvent() end
    if attacker ~= localPlayer then return end
    hitFx(F.ped, false)
    crowdReact("player")
    local now = getTickCount()
    F.combo = F.combo or {}
    F.combo[#F.combo + 1] = now
    while F.combo[1] and now - F.combo[1] > 2500 do table.remove(F.combo, 1) end
    if #F.combo >= 3 and now - (F.lastCombo or 0) > 6000 then
        F.lastCombo = now
        voice("combo")
    end
end)

----------------------------------------------------------------
-- IA del entrenador (100 ms)
----------------------------------------------------------------
local function think()
    local ped = F and F.ped
    if not isElement(ped) or isPedDead(ped) then return end
    local px, py = getElementPosition(localPlayer)
    local tx, ty = getElementPosition(ped)
    local dx, dy = px - tx, py - ty
    local dist = math.sqrt(dx * dx + dy * dy)
    local fighting = F.phase == "live"
    if F.phase ~= "intro" then setElementRotation(ped, 0, 0, math.deg(math.atan2(-dx, dy))) end
    setPedControlState(ped, "forwards", fighting and dist > 1.4)
    local now = getTickCount()
    if fighting and dist <= 1.7 and now >= F.nextHit then
        F.nextHit = now + math.random(GYM.TRAINER_HIT_MS[1], GYM.TRAINER_HIT_MS[2])
        setPedControlState(ped, "fire", true)   -- se suelta en el siguiente tick (golpe de ~100 ms)
    else
        setPedControlState(ped, "fire", false)
    end
    -- Fotografos
    if (fighting or F.phase == "down") and now >= (F.nextFlash or 0) then
        F.nextFlash = now + math.random(700, 2200)
        local photos = crowdBy("photo")
        if #photos > 0 then flash(photos[math.random(#photos)]) end
    end
end

----------------------------------------------------------------
-- Presentacion
----------------------------------------------------------------
local function goLive()
    if not F or F.phase ~= "intro" then return end
    F.phase = "live"
    F.nextHit = getTickCount() + 900
    setCameraTarget(localPlayer)
    setPedAnimation(localPlayer)
    if isElement(F.ped) then setPedAnimation(F.ped) end
    setControls(true)
    exports.rp_hud:setHudSuppressed("rp_gym", false)
    voice("fight")
    bell()
    F.loop = playSound("sounds/crowd_loop.wav", true)
    if F.loop then setSoundVolume(F.loop, 0.35) end
end

local function cleanup()
    if not F then return end
    for _, t in ipairs(F.timers) do if isTimer(t) then killTimer(t) end end
    if isElement(F.loop) then destroyElement(F.loop) end
    if isElement(F.ped) then
        setPedControlState(F.ped, "forwards", false)
        setPedControlState(F.ped, "fire", false)
    end
    if F.phase == "intro" then setCameraTarget(localPlayer) end
    setControls(true)
    if setCameraShakeLevel then setCameraShakeLevel(0) end
    exports.rp_hud:setHudSuppressed("rp_gym", false)
    F = nil
end

addEventHandler("rp:gym:fight", resourceRoot, function(ped, active, info)
    if active then
        cleanup()
        if not isElement(ped) then return end
        textures()
        info = type(info) == "table" and info or {}
        F = { ped = ped, crowd = info.crowd or {}, ring = info.ring, phase = "intro", timers = {}, streak = 0, nextHit = 0, nextFlash = 0,
              intro = tonumber(info.intro) or 0, startedAt = getTickCount(), label = info.label or "Entrenador",
              style = info.style or "", name = getPlayerName(localPlayer):gsub("_", " ") }
        for _, c in ipairs(F.crowd) do if c.side == "referee" then F.referee = c.ped end end
        F.timers[#F.timers + 1] = setTimer(think, 100, 0)
        if F.intro <= 0 then return goLive() end

        setControls(false)
        exports.rp_hud:setHudSuppressed("rp_gym", true)
        setPedAnimation(localPlayer, "GYMNASIUM", "gym_shadowbox", -1, true, false, false, false)
        setPedAnimation(ped, "RIOT", "RIOT_ANGRY_B", -1, true, false, false, false)
        later(300, function() voice("player_1") end)
        later(3800, function() voice("player_2") end)
        later(7000, function() voice("prepare_yourself") end)
        later(8000, function() voice("3") end)
        later(9000, function() voice("2") end)
        later(10000, function() voice("1") end)
        later(F.intro, goLive)
    else
        local result = info
        local wasLive = F and F.phase ~= "intro"
        cleanup()
        if not wasLive then return end
        if result == "win" or result == "lose" then
            bell(); setTimer(bell, 350, 1); setTimer(bell, 700, 1)
            setTimer(voice, 1300, 1, result == "win" and "you_win" or "you_lose")
            if result == "win" then koShownAt = getTickCount() end
        end
    end
end)

----------------------------------------------------------------
-- Paredes invisibles del ring: ni el jugador ni el entrenador pasan de `half` m del centro (X e Y)
----------------------------------------------------------------
local function keepInside(el, r)
    if not isElement(el) then return end
    local x, y, z = getElementPosition(el)
    local nx = math.max(r.x - r.half, math.min(r.x + r.half, x))
    local ny = math.max(r.y - r.half, math.min(r.y + r.half, y))
    if nx ~= x or ny ~= y then
        setElementPosition(el, nx, ny, z, false)   -- sin warp: no corta la animacion
        local vx, vy, vz = getElementVelocity(el)
        setElementVelocity(el, nx ~= x and 0 or vx, ny ~= y and 0 or vy, vz)
    end
end

addEventHandler("onClientPreRender", root, function()
    local r = F and F.ring
    if not r or not r.half or F.phase == "over" then return end
    keepInside(localPlayer, r)
    keepInside(F.ped, r)   -- este cliente es su sincronizador
end)

----------------------------------------------------------------
-- Camara de la presentacion
----------------------------------------------------------------
local function headOf(el)
    local x, y, z = getPedBonePosition(el, 8)
    if not x then x, y, z = getElementPosition(el) z = z + 0.6 end
    return x, y, z
end

local function portrait(el, k)
    local x, y, z = headOf(el)
    local _, _, rot = getElementRotation(el)
    local a = math.rad(rot + 90 + (k - 0.5) * 50)   -- orbita lenta por delante del personaje
    local d = 2.4 - 0.5 * k
    setCameraMatrix(x + math.cos(a) * d, y + math.sin(a) * d, z + 0.1 - 0.25 * k, x, y, z - 0.05)
end

addEventHandler("onClientPreRender", root, function()
    if not F or F.phase ~= "intro" then return end
    local t = getTickCount() - F.startedAt
    if t < 3500 then
        portrait(localPlayer, t / 3500)
    elseif t < 7000 and isElement(F.ped) then
        portrait(F.ped, (t - 3500) / 3500)
    else
        local ax, ay, az = getElementPosition(localPlayer)
        local bx, by = 0, 0
        if isElement(F.ped) then bx, by = getElementPosition(F.ped) else bx, by = ax, ay end
        local cx, cy = (ax + bx) / 2, (ay + by) / 2
        local k = math.min(1, (t - 7000) / 4000)
        local a = math.rad(200 + 40 * k)
        setCameraMatrix(cx + math.cos(a) * 6.5, cy + math.sin(a) * 6.5, az + 2.6 - k, cx, cy, az)
    end
end)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function healthBar(x, y, w, frac, label, alignRight)
    frac = math.max(0, math.min(1, frac))
    dxDrawRectangle(x - 2, y - 2, w + 4, 18 * S + 4, tocolor(0, 0, 0, 200))
    dxDrawRectangle(x, y, w, 18 * S, tocolor(50, 50, 50, 220))
    local fw = w * frac
    dxDrawRectangle(alignRight and (x + w - fw) or x, y, fw, 18 * S, tocolor(229, 52, 48, 255))
    outlined(label, x, y - 24 * S, w, 1.1 * S, "default-bold", tocolor(255, 255, 255), 255, alignRight and "right" or "left")
end

local function drawIntroTexts(t)
    local function lowerThird(name, sub, k)
        local a = math.floor(255 * math.min(1, k * 4, (1 - k) * 4))
        outlined(name, 60 * S, sh * 0.72, sw, 2.2 * S, "bankgothic", tocolor(255, 255, 255, a), a, "left")
        outlined(sub, 64 * S, sh * 0.72 + 56 * S, sw, 1.2 * S, "default-bold", tocolor(245, 165, 36, a), a, "left")
    end
    if t < 3500 then
        lowerThird(F.name, "EL RETADOR", t / 3500)
    elseif t < 7000 then
        lowerThird(F.label, F.style:upper(), (t - 3500) / 3500)
    elseif t >= 8000 then
        local n = 3 - math.floor((t - 8000) / 1000)
        if n >= 1 then
            local k = ((t - 8000) % 1000) / 1000
            local a = math.floor(255 * (1 - k * 0.6))
            outlined(tostring(n), 0, sh * 0.3, sw, (6 - 2.5 * k) * S, "bankgothic", tocolor(255, 255, 255, a), a)
        end
    end
end

local function drawDown(now)
    local cx = sw / 2
    if F.count > 0 then
        outlined(tostring(F.count), 0, sh * 0.16, sw, 5 * S, "bankgothic", tocolor(255, 255, 255), 255)
    end
    outlined("¡Pulsa ESPACIO rápido para levantarte!", 0, sh * 0.58, sw, 1.4 * S, "default-bold", tocolor(245, 165, 36), 255)
    -- Tecla Espacio animada: se "hunde" al pulsarla y parpadea sola para que se entienda que hay que machacarla
    local pressed = now - (F.pressedAt or 0) < 110 or (now % 360) < 140
    local iw, ih = 120 * S, 120 * S
    local scale = pressed and 0.9 or 1
    local img = pressed and tex.keyboard_space_outline or tex.keyboard_space
    if img then
        dxDrawImage(cx - iw * scale / 2, sh * 0.64 + (ih - ih * scale) / 2, iw * scale, ih * scale, img)
    end
    local bw, by = 360 * S, sh * 0.64 + ih + 14 * S
    dxDrawRectangle(cx - bw / 2 - 2, by - 2, bw + 4, 20 * S + 4, tocolor(0, 0, 0, 220))
    dxDrawRectangle(cx - bw / 2, by, bw, 20 * S, tocolor(50, 50, 50, 220))
    dxDrawRectangle(cx - bw / 2, by, bw * math.min(1, F.mash / 100), 20 * S, tocolor(76, 211, 138, 255))
end

local function drawHud()
    local w = 320 * S
    local hp = (getElementHealth(localPlayer) - GYM.PLAYER_LOSE_HP) / (100 - GYM.PLAYER_LOSE_HP)
    local thp = isElement(F.ped) and (getElementHealth(F.ped) - GYM.TRAINER_WIN_HP) / (100 - GYM.TRAINER_WIN_HP) or 0
    healthBar(sw / 2 - w - 40 * S, 60 * S, w, hp, F.name, false)
    healthBar(sw / 2 + 40 * S, 60 * S, w, thp, F.label, true)
    outlined("VS", 0, 54 * S, sw, 1.4 * S, "bankgothic", tocolor(245, 165, 36), 255)
    -- Como cubrirse, con las teclas dibujadas
    local ix, iy, is = sw / 2 - 120 * S, sh - 90 * S, 44 * S
    if tex.mouse_right then dxDrawImage(ix, iy, is, is, tex.mouse_right) end
    outlined("+", ix + is, iy + 8 * S, 24 * S, 1.3 * S, "default-bold", tocolor(255, 255, 255), 255)
    if tex.keyboard_shift then dxDrawImage(ix + is + 24 * S, iy, is, is, tex.keyboard_shift) end
    outlined("Cubrirte", ix + is * 2 + 34 * S, iy + 10 * S, 200 * S, 1.2 * S, "default-bold", tocolor(255, 255, 255), 255, "left")
end

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastFrame) / 1000)
    lastFrame = now

    -- Mareo y vision borrosa: la pantalla a baja resolucion encima, desplazada y oscilando
    if fx.dizzy > 0.02 and isElement(screen) then
        dxUpdateScreenSource(screen, true)
        local a, wob = fx.dizzy, math.sin(now * 0.007)
        local off = 14 * S * a
        dxDrawImage(off * wob, off * 0.4 * math.cos(now * 0.005), sw, sh, screen, wob * 1.5 * a, 0, 0, tocolor(255, 255, 255, 150 * a))
        dxDrawImage(-off * wob, 0, sw, sh, screen, 0, 0, 0, tocolor(255, 230, 230, 90 * a))
        fx.dizzy = math.max(0, fx.dizzy - dt / 1.8)
    end
    if fx.blood > 0.01 and tex.blood then
        dxDrawImage(0, 0, sw, sh, tex.blood, 0, 0, 0, tocolor(255, 255, 255, 255 * fx.blood))
        fx.blood = math.max(0, fx.blood - dt / 3)
    end
    -- Destellos de los flashes
    for i = #fx.flashes, 1, -1 do
        local f = fx.flashes[i]
        local age = now - f.at
        if age > 140 or not tex.glow then
            table.remove(fx.flashes, i)
        else
            local a = math.floor(255 * (1 - age / 140))
            dxDrawMaterialLine3D(f.x, f.y, f.z + 0.35, f.x, f.y, f.z - 0.35, tex.glow, 0.7, tocolor(255, 255, 255, a))
        end
    end

    if F then
        if F.phase == "intro" then
            drawIntroTexts(now - F.startedAt)
        else
            if F.phase == "live" and F.stunUntil and F.stunUntil > 0 and now >= F.stunUntil then
                F.stunUntil = 0
                setControls(true)
                if setCameraShakeLevel then setCameraShakeLevel(0) end
            end
            if F.phase == "down" then
                F.mash = math.max(0, F.mash - GYM_FIGHT.MASH_DECAY * dt)
                drawDown(now)
            elseif F.phase == "live" then
                drawHud()
            end
            if now - F.startedAt - F.intro < 1200 then
                outlined("¡PELEA!", 0, sh * 0.3, sw, 4 * S, "bankgothic", tocolor(229, 52, 48), 255)
            end
        end
    end

    -- "K.O." grande en el centro: entra desde grande, se queda y se desvanece
    if koShownAt then
        local t = now - koShownAt
        if t > KO_MS then
            koShownAt = nil
        else
            local pop = math.min(1, t / 220)
            local a = math.floor(255 * math.min(1, (KO_MS - t) / 500))
            outlined("K.O.", 0, sh * 0.32, sw, (sh / 900) * (5.5 - 2.5 * pop), "bankgothic", tocolor(229, 52, 48, a), a)
        end
    end
    if not F and not koShownAt and fx.blood <= 0.01 and fx.dizzy <= 0.02 and #fx.flashes == 0 and tex.blood then
        freeTextures()
    end
end)

-- Espacio repetido para levantarse
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("space", "down", function()
        if not F or F.phase ~= "down" or gymBusy() then return end
        F.pressedAt = getTickCount()
        F.mash = F.mash + GYM_FIGHT.MASH_GAIN
        if F.mash >= 100 then getUp() end
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, cleanup)
