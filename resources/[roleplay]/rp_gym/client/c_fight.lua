--[[
    rp_gym / c_fight.lua
    Combate con el entrenador en el ring, del lado del jugador que pelea.

    - Presentacion (si hay ring): plano del retador, plano del entrenador, plano general con cuenta 3-2-1
      y campana (GYM_FIGHT.INTRO_MS, el servidor espera lo mismo). Narrador: Kenney Voiceover Pack Fighter.
    - IA del entrenador: este cliente es su sincronizador (setPedControlState solo existe en el cliente).
      Tras conectar un golpe se aparta un momento (no encadena golpes sin pausa).
    - Golpes: sonido de impacto y sangre en los dos; el publico grita y anima a su lado; fotografos con flash.
    - Golpe recibido sin cubrirse (clic derecho + salto): aturdido 1-2 s, mareo y vision borrosa y sangre
      alrededor de la pantalla. Tras un aturdimiento hay GYM_FIGHT.STUN_IMMUNE_MS sin poder volver a quedar
      aturdido, para que el jugador recupere el control y pueda cubrirse o pegar.
    - Varios golpes seguidos sin cubrirse: puede caer; el arbitro cuenta hasta 10 y hay que pulsar Espacio
      rapido para llenar la barra y levantarse. Si llega a 10, pierde. Mientras, el entrenador se va a
      su esquina y celebra con su publico; al levantarse dejan de celebrar y tiene 3 s antes del siguiente golpe.
    - Vigilante: si en pleno combate los controles quedan desactivados sin estar aturdido ni en el suelo,
      se reactivan y se registra en el debug.
    - Logs: con GYM_FIGHT.DEBUG, cada cambio de fase, golpe, aturdimiento y cambio de controles sale en
      /debugscript 3 con el prefijo [rp_gym:pelea].
    - Al ganar: "K.O." y campana. Vidas, ring y resultado los decide el servidor (s_trainers.lua).
    Interfaz con GymUI (client/c_ui.lua).
]]

addEvent("rp:gym:fight", true)

local sw, sh = guiGetScreenSize()
local F = nil            -- combate en curso
local fx = { blood = 0, dizzy = 0, flashes = {} }   -- efectos que se desvanecen aunque el combate acabe
local koShownAt, KO_MS = nil, 2800
local endShown = nil     -- { result, at } tarjeta de resultado
local tex = {}
local screen = nil
local lastFrame = getTickCount()

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function dbg(fmt, ...)
    if not GYM_FIGHT.DEBUG then return end
    local ok, msg = pcall(string.format, fmt, ...)
    outputDebugString("[rp_gym:pelea] " .. (ok and msg or fmt), 3)
end

local function sound(path, volume)
    local s = playSound(path)
    if s and volume then setSoundVolume(s, volume) end
    return s
end
local function voice(name) return sound("sounds/voz/" .. name .. ".ogg", 1) end
local function bell() return sound("sounds/golpe/bell.ogg", 1) end
-- Campana de inicio (Pixabay): el archivo dura ~15 s, se corta a los 4 s
local function startBell()
    local s = sound("sounds/golpe/bell_start.mp3", 1)
    if s then setTimer(function() if isElement(s) then destroyElement(s) end end, 4000, 1) end
end

local function later(ms, fn)
    local t = setTimer(fn, ms, 1)
    if F then F.timers[#F.timers + 1] = t end
    return t
end

local function setPhase(phase)
    if F and F.phase ~= phase then
        dbg("fase %s -> %s", tostring(F.phase), phase)
        F.phase = phase
    end
end

local function setControls(on, why)
    toggleAllControls(on, true, false)
    dbg("controles %s (%s)", on and "ACTIVADOS" or "desactivados", why or "?")
end

local function textures()
    if tex.blood then return end
    tex.blood = dxCreateTexture("images/blood.png", "argb", true, "clamp")
    tex.glow = dxCreateTexture("images/glow.png", "argb", true, "clamp")
    screen = dxCreateScreenSource(math.floor(sw / 3), math.floor(sh / 3))   -- a baja resolucion: ya sale borroso
end

local function freeTextures()
    for k, t in pairs(tex) do if isElement(t) then destroyElement(t) end tex[k] = nil end
    if isElement(screen) then destroyElement(screen) end
    screen = nil
end

local function crowdBy(side)
    local list = {}
    for _, c in ipairs(F and F.crowd or {}) do
        if c.side == side and isElement(c.ped) then list[#list + 1] = c.ped end
    end
    return list
end

----------------------------------------------------------------
-- Publico y fotografos
----------------------------------------------------------------
-- silent = sin subir el ruido del publico (cuando el golpe lo recibe el jugador)
local function crowdReact(side, silent)
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
    if not silent then F.roar = 1 end   -- el bucle del publico sube y vuelve a bajar (onClientRender)
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
    local s = sound("sounds/golpe/punch.mp3", 1)
    if s then setSoundSpeed(s, 0.88 + math.random() * 0.24) end   -- tono distinto en cada golpe
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

local function lose(why)
    if not F or F.phase == "over" then return end
    dbg("pierde: %s", why or "?")
    setPhase("over")
    triggerServerEvent("rp:gym:lost", resourceRoot)
end

----------------------------------------------------------------
-- Caida y cuenta del arbitro
----------------------------------------------------------------
-- El publico del entrenador celebra mientras el jugador esta en el suelo (y deja de hacerlo al levantarse)
local function crowdCelebrate(on)
    for _, ped in ipairs(crowdBy("trainer")) do
        if on then
            setPedAnimation(ped, "ON_LOOKERS", "shout_01", -1, true, false, false, false)
        else
            setPedAnimation(ped, "RIOT", "RIOT_CHANT", -1, true, false, false, false)
        end
    end
end

local function stopCelebrating()
    if F.celebrating and isElement(F.ped) then setPedAnimation(F.ped) end
    F.celebrating = false
    crowdCelebrate(false)
end

local function endStun(why)
    if not F or (F.stunUntil or 0) == 0 then return end
    F.stunUntil = 0
    F.stunImmuneUntil = getTickCount() + GYM_FIGHT.STUN_IMMUNE_MS
    if setCameraShakeLevel then setCameraShakeLevel(0) end
    if F.phase == "live" then setControls(true, "fin del aturdimiento: " .. why) end
end

local function getUp()
    if not F or F.phase ~= "down" then return end
    setPhase("rising")
    if isTimer(F.countTimer) then killTimer(F.countTimer) end
    triggerServerEvent("rp:gym:down", resourceRoot, false)
    voice("ready")
    stopCelebrating()
    crowdReact("player")
    later(1300, function()
        if not F or F.phase ~= "rising" then return end
        setPhase("live")
        F.streak, F.stunUntil = 0, 0
        F.stunImmuneUntil = getTickCount() + 3000 + GYM_FIGHT.STUN_IMMUNE_MS
        F.nextHit = getTickCount() + 3000   -- 3 s de respiro antes de que el entrenador vuelva a pegar
        setControls(true, "se levanta")
    end)
end

local function startDown()
    setPhase("down")
    F.mash, F.count, F.pressedAt, F.stunUntil = 0, 0, 0, 0
    setControls(false, "cae al suelo")
    if setCameraShakeLevel then setCameraShakeLevel(0) end
    triggerServerEvent("rp:gym:down", resourceRoot, true)
    crowdReact("trainer")
    crowdCelebrate(true)
    F.countTimer = setTimer(function()
        if not F or F.phase ~= "down" then return end
        F.count = F.count + 1
        F.countAt = getTickCount()
        dbg("cuenta %d (barra %d %%)", F.count, math.floor(F.mash))
        voice(tostring(F.count))
        F.roar = 1
        if isElement(F.referee) then
            setPedAnimation(F.referee, "RIOT", "RIOT_shout", -1, false, false, false, false)
        end
        if F.count >= 10 then
            later(900, function() if F and F.phase == "down" then lose("cuenta de 10") end end)
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
        return lose("golpe mortal")
    end
    if attacker ~= F.ped then return end
    local now = getTickCount()
    -- El entrenador se aparta un momento tras conectar: no encadena golpes
    F.nextHit = math.max(F.nextHit, now + GYM_FIGHT.TRAINER_RECOVER_MS)
    local covered = isCovered()
    hitFx(localPlayer, covered)
    crowdReact("trainer", true)
    if covered then
        F.streak = 0
        dbg("golpe bloqueado (vida %.0f)", getElementHealth(localPlayer))
        return
    end

    if now - (F.lastHitAt or 0) > GYM_FIGHT.STREAK_WINDOW_MS then F.streak = 0 end
    F.streak, F.lastHitAt = F.streak + 1, now
    fx.blood, fx.dizzy = math.min(1, fx.blood + 0.55), math.max(fx.dizzy, 0.7)
    local canStun = (F.stunUntil or 0) == 0 and now >= (F.stunImmuneUntil or 0)
    dbg("golpe recibido: -%.1f vida (%.0f), racha %d, aturdible %s", loss, getElementHealth(localPlayer), F.streak, tostring(canStun))
    if F.streak >= GYM_FIGHT.DOWN_STREAK and math.random() < GYM_FIGHT.DOWN_CHANCE then return startDown() end
    if canStun then
        local stun = math.min(GYM_FIGHT.STUN_MS[2], GYM_FIGHT.STUN_MS[1] + (F.streak - 1) * 500)
        F.stunUntil = now + stun
        fx.dizzy = 1
        setControls(false, ("aturdido %d ms"):format(stun))
        if setCameraShakeLevel then setCameraShakeLevel(120) end
    end
end)

addEventHandler("onClientPedDamage", root, function(attacker, weapon, bodypart, loss)
    if not F then return end
    if getElementData(source, "rp:gymCrowd") then return cancelEvent() end   -- publico y arbitro
    if source ~= F.ped then return end
    if F.phase ~= "live" then return cancelEvent() end
    if attacker ~= localPlayer then return end
    hitFx(F.ped, false)
    crowdReact("player")
    dbg("golpe al entrenador: -%.1f (%.0f)", loss or 0, getElementHealth(F.ped))
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
-- IA del entrenador y vigilante (100 ms)
----------------------------------------------------------------
local function think()
    local ped = F and F.ped
    local now = getTickCount()
    -- Vigilante: en pleno combate, sin aturdimiento, los controles tienen que estar activos
    if F and F.phase == "live" then
        if (F.stunUntil or 0) > 0 and now >= F.stunUntil + 250 then endStun("vigilante") end
        if (F.stunUntil or 0) == 0 and not isControlEnabled("fire") then
            dbg("VIGILANTE: controles desactivados sin aturdimiento (fase live): se reactivan")
            setControls(true, "vigilante")
        end
    end
    if not isElement(ped) or isPedDead(ped) then return end
    local px, py = getElementPosition(localPlayer)
    local tx, ty = getElementPosition(ped)
    local dx, dy = px - tx, py - ty
    local dist = math.sqrt(dx * dx + dy * dy)
    local fighting = F.phase == "live"
    local corner = F.ring and F.ring.trainer
    if (F.phase == "down" or F.phase == "rising") and corner then
        -- Con el jugador en el suelo el entrenador se va a su esquina (como manda el arbitro) y celebra con el publico
        local cx, cy = corner.x - tx, corner.y - ty
        local away = math.sqrt(cx * cx + cy * cy) > 0.6 and F.phase == "down"
        if away then
            setElementRotation(ped, 0, 0, math.deg(math.atan2(-cx, cy)))
        elseif F.phase == "down" and not F.celebrating then
            F.celebrating = true
            setElementRotation(ped, 0, 0, math.deg(math.atan2(-dx, dy)))
            setPedAnimation(ped, "CASINO", "manwinb", -1, true, false, false, false)
        end
        setPedControlState(ped, "forwards", away)
        setPedControlState(ped, "fire", false)
        return
    end
    if F.phase ~= "intro" then setElementRotation(ped, 0, 0, math.deg(math.atan2(-dx, dy))) end
    -- Mientras espera para volver a pegar guarda distancia; luego entra
    local waiting = now < F.nextHit - 400
    setPedControlState(ped, "forwards", fighting and dist > (waiting and 2.2 or 1.4))
    setPedControlState(ped, "backwards", fighting and waiting and dist < 1.6)
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
    setPhase("live")
    F.nextHit = getTickCount() + 900
    F.liveAt = getTickCount()
    setCameraTarget(localPlayer)
    setPedAnimation(localPlayer)
    if isElement(F.ped) then setPedAnimation(F.ped) end
    setControls(true, "empieza el combate")
    exports.rp_hud:setHudSuppressed("rp_gym", false)
    voice("fight")
    startBell()
    F.loop = playSound("sounds/crowd.mp3", true)   -- publico (Pixabay); sube con cada golpe (F.roar)
    if F.loop then setSoundVolume(F.loop, 0.35) end
end

local function cleanup()
    if not F then return end
    for _, t in ipairs(F.timers) do if isTimer(t) then killTimer(t) end end
    if isElement(F.loop) then destroyElement(F.loop) end
    if isElement(F.ped) then
        for _, c in ipairs({ "forwards", "backwards", "fire" }) do setPedControlState(F.ped, c, false) end
    end
    if F.phase == "intro" then setCameraTarget(localPlayer) end
    setControls(true, "fin del combate")
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
              style = info.style or "", name = (getPlayerName(localPlayer):gsub("_", " ")) }
        for _, c in ipairs(F.crowd) do if c.side == "referee" then F.referee = c.ped end end
        dbg("combate empieza: %s, presentacion %d ms, publico %d", F.label, F.intro, #F.crowd)
        F.timers[#F.timers + 1] = setTimer(think, 100, 0)
        endShown = nil
        if F.intro <= 0 then return goLive() end

        setControls(false, "presentacion")
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
        dbg("combate termina: %s", tostring(result))
        cleanup()
        if not wasLive then return end
        if result == "win" or result == "lose" then
            bell(); setTimer(bell, 350, 1); setTimer(bell, 700, 1)
            setTimer(voice, 1300, 1, result == "win" and "you_win" or "you_lose")
            if result == "win" then koShownAt = getTickCount() end
            endShown = { result = result, at = getTickCount() + (result == "win" and KO_MS or 600) }
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
        local bx, by = ax, ay
        if isElement(F.ped) then bx, by = getElementPosition(F.ped) end
        local cx, cy = (ax + bx) / 2, (ay + by) / 2
        local k = math.min(1, (t - 7000) / 4000)
        local a = math.rad(200 + 40 * k)
        setCameraMatrix(cx + math.cos(a) * 6.5, cy + math.sin(a) * 6.5, az + 2.6 - k, cx, cy, az)
    end
end)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
-- Texto grande animado: una sola fuente de 96 px escalada (crear una por tamano llenaria la memoria)
local function bigText(str, y, size, color, a)
    GymUI.shadowText(str, 0, y, sw, 0, color, GymUI.font("title", 96), "center", "top", a, size / 96)
end

-- Ficha de un peleador: nombre, etiqueta y vida (alineada a la izquierda o a la derecha)
local function fighterCard(x, y, w, name, tag, frac, right)
    local S = GymUI.S
    local h = 74 * S
    GymUI.panel(x, y, w, h, 1, right and GymUI.C.bad or GymUI.C.good)
    local px, pw = x + 20 * S, w - 38 * S
    local ax = right and "right" or "left"
    GymUI.text(tag, px, y + 10 * S, pw, 16 * S, GymUI.col(GymUI.C.muted), GymUI.font("title", 11), ax, "center")
    GymUI.text(name, px, y + 26 * S, pw, 24 * S, GymUI.col(GymUI.C.text), GymUI.font("bold", 19), ax, "center", true)
    frac = math.max(0, math.min(1, frac))
    local bw, bh, by = pw, 10 * S, y + 54 * S
    dxDrawRectangle(px, by, bw, bh, GymUI.col(GymUI.C.track, 30))
    local c = frac > 0.5 and GymUI.C.good or (frac > 0.25 and GymUI.C.accent or GymUI.C.bad)
    local fw = bw * frac
    dxDrawRectangle(right and (px + bw - fw) or px, by, fw, bh, GymUI.col(c))
end

local function drawHud(now)
    local S = GymUI.S
    local w, gap, y = 360 * S, 70 * S, 28 * S
    local hp = (getElementHealth(localPlayer) - GYM.PLAYER_LOSE_HP) / (100 - GYM.PLAYER_LOSE_HP)
    local thp = isElement(F.ped) and (getElementHealth(F.ped) - GYM.TRAINER_WIN_HP) / (100 - GYM.TRAINER_WIN_HP) or 0
    fighterCard(sw / 2 - gap / 2 - w, y, w, F.name, "RETADOR", hp, false)
    fighterCard(sw / 2 + gap / 2, y, w, F.label, F.style:upper(), thp, true)
    GymUI.shadowText("VS", sw / 2 - gap / 2, y, gap, 74 * S, GymUI.col(GymUI.C.accent), GymUI.font("title", 24), "center", "center")

    -- Estado: aturdido / racha de golpes
    if (F.stunUntil or 0) > now then
        GymUI.shadowText("¡ATURDIDO!", 0, y + 90 * S, sw, 0, GymUI.col(GymUI.C.bad), GymUI.font("title", 22), "center", "top")
    elseif (F.streak or 0) >= 2 and now - (F.lastHitAt or 0) < GYM_FIGHT.STREAK_WINDOW_MS then
        GymUI.shadowText("¡Cúbrete o caerás!", 0, y + 90 * S, sw, 0, GymUI.col(GymUI.C.accent), GymUI.font("bold", 20), "center", "top")
    end

    -- Controles dibujados
    local hs, cy = 34 * S, sh - 64 * S
    local wTotal = 520 * S
    local x = (sw - wTotal) / 2
    GymUI.panel(x - 16 * S, cy - 12 * S, wTotal + 32 * S, hs + 24 * S, 0.85, false)
    local used = GymUI.hint({ "mouse_left" }, "Golpear", x, cy, hs)
    used = used + 36 * S
    used = used + GymUI.hint({ "mouse_right", "+", "keyboard_shift" }, "Cubrirte", x + used, cy, hs)
    GymUI.hint({}, "No salgas del ring", x + used + 36 * S, cy, hs)
end

local function drawIntroTexts(t)
    local S = GymUI.S
    local function lowerThird(name, sub, k)
        local a = math.min(1, k * 4, (1 - k) * 4)
        local slide = (1 - math.min(1, k * 4)) * 80 * S
        local x, y, w, h = 60 * S - slide, sh * 0.70, 560 * S, 112 * S
        GymUI.panel(x, y, w, h, a)
        GymUI.text(sub, x + 28 * S, y + 16 * S, w, 22 * S, GymUI.col(GymUI.C.accent, 255 * a), GymUI.font("title", 16), "left", "center")
        GymUI.text(name, x + 28 * S, y + 42 * S, w - 40 * S, 52 * S, GymUI.col(GymUI.C.text, 255 * a), GymUI.font("title", 36), "left", "center", true)
    end
    if t < 3500 then
        lowerThird(F.name, "EL RETADOR", t / 3500)
    elseif t < 7000 then
        lowerThird(F.label, F.style:upper(), (t - 3500) / 3500)
    elseif t >= 8000 then
        local n = 3 - math.floor((t - 8000) / 1000)
        if n >= 1 then
            local k = ((t - 8000) % 1000) / 1000
            bigText(tostring(n), sh * 0.30, 140 - 40 * k, GymUI.col(GymUI.C.text, 255 * (1 - k * 0.6)), 1 - k * 0.6)
        end
    end
end

local function drawDown(now)
    local S = GymUI.S
    if F.count > 0 then
        local k = math.min(1, (now - (F.countAt or now)) / 200)
        bigText(tostring(F.count), sh * 0.14, 150 - 30 * k, GymUI.col(GymUI.C.text))
        GymUI.shadowText("CUENTA DEL ÁRBITRO", 0, sh * 0.14 - 34 * S, sw, 0, GymUI.col(GymUI.C.accent), GymUI.font("title", 16), "center", "top")
    end
    local w, h = 460 * S, 250 * S
    local x, y = (sw - w) / 2, sh * 0.55
    GymUI.panel(x, y, w, h, 1, GymUI.C.good)
    GymUI.text("¡LEVÁNTATE!", x, y + 14 * S, w, 30 * S, GymUI.col(GymUI.C.text), GymUI.font("title", 24), "center", "center")
    GymUI.text("Pulsa Espacio rápido para llenar la barra", x, y + 46 * S, w, 22 * S, GymUI.col(GymUI.C.muted), GymUI.font("body", 16), "center", "center")
    -- Tecla Espacio animada: se "hunde" al pulsarla y parpadea sola para que se entienda que hay que machacarla
    local pressed = now - (F.pressedAt or 0) < 110 or (now % 360) < 140
    local ks = 110 * S
    local scale = pressed and 0.88 or 1
    local img = GymUI.key(pressed and "keyboard_space_outline" or "keyboard_space")
    if img then dxDrawImage(x + (w - ks * scale) / 2, y + 74 * S + (ks - ks * scale) / 2, ks * scale, ks * scale, img) end
    local bw = w - 60 * S
    GymUI.bar(x + 30 * S, y + h - 40 * S, bw, 16 * S, F.mash / 100, GymUI.col(GymUI.C.good))
end

local function drawEnd(now)
    local S = GymUI.S
    local age = now - endShown.at
    if age < 0 then return end
    if age > 4000 then endShown = nil return end
    local a = math.min(1, age / 200, (4000 - age) / 400)
    local win = endShown.result == "win"
    local w, h = 460 * S, 110 * S
    local x, y = (sw - w) / 2, sh * 0.62
    GymUI.panel(x, y, w, h, a, win and GymUI.C.good or GymUI.C.bad)
    GymUI.text(win and "¡VICTORIA!" or "DERROTA", x, y + 18 * S, w, 34 * S,
        GymUI.col(win and GymUI.C.good or GymUI.C.bad, 255 * a), GymUI.font("title", 28), "center", "center")
    GymUI.text(win and ("Has aprendido " .. "un nuevo estilo de pelea") or "Vuelve cuando estés listo",
        x, y + 62 * S, w, 24 * S, GymUI.col(GymUI.C.text, 255 * a), GymUI.font("body", 17), "center", "center")
end

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastFrame) / 1000)
    lastFrame = now

    -- Mareo y vision borrosa: la pantalla a baja resolucion encima, desplazada y oscilando
    if fx.dizzy > 0.02 and isElement(screen) then
        dxUpdateScreenSource(screen, true)
        local a, wob = fx.dizzy, math.sin(now * 0.007)
        local off = 14 * GymUI.S * a
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
            dxDrawMaterialLine3D(f.x, f.y, f.z + 0.35, f.x, f.y, f.z - 0.35, tex.glow, 0.7, tocolor(255, 255, 255, 255 * (1 - age / 140)))
        end
    end

    if F then
        if isElement(F.loop) then
            F.roar = math.max(0, (F.roar or 0) - dt / 1.5)
            setSoundVolume(F.loop, 0.35 + 0.5 * F.roar)
        end
        if F.phase == "intro" then
            drawIntroTexts(now - F.startedAt)
        else
            if F.phase == "live" and (F.stunUntil or 0) > 0 and now >= F.stunUntil then endStun("tiempo cumplido") end
            if F.phase == "down" then
                F.mash = math.max(0, F.mash - GYM_FIGHT.MASH_DECAY * dt)
                drawDown(now)
            elseif F.phase == "live" then
                drawHud(now)
            end
            if F.liveAt and now - F.liveAt < 1200 then
                local k = (now - F.liveAt) / 1200
                bigText("¡PELEA!", sh * 0.30, 110 - 20 * k, GymUI.col(GymUI.C.bad, 255 * (1 - k * k)), 1 - k * k)
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
            local a = math.min(1, (KO_MS - t) / 500)
            bigText("K.O.", sh * 0.28, 200 - 80 * pop, GymUI.col(GymUI.C.bad, 255 * a), a)
        end
    end
    if endShown then drawEnd(now) end
    if not F and not koShownAt and not endShown and fx.blood <= 0.01 and fx.dizzy <= 0.02 and #fx.flashes == 0 and tex.blood then
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
