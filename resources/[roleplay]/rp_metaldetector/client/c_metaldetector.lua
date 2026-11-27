--[[
    rp_metaldetector / c_metaldetector.lua  (cliente)

    Con el detector equipado:
    - cada SURFACE_CHECK_MS mira qué material pisa (processLineOfSight hacia abajo);
    - si no hay punto, busca arena alrededor y propone uno al servidor (él decide qué hay enterrado);
    - la pantalla del detector muestra la lectura del metal (VDI con aguja), la fuerza de la señal
      en barras, la profundidad de cerca y un LED; el audio pita más rápido cuanto más cerca, grave
      para el hierro y agudo para lo demás, y en el punto exacto da un tono continuo;
    - junto al punto, E empieza a cavar: una barra oscila y cada E es una palada (buena en la zona verde);
    - al terminar, el servidor manda el hallazgo: revelación en el mundo (c_fx.lua) y tarjeta con rareza,
      precio estimado, XP y «¡nuevo en tu colección!».
    /hallazgos abre la bitácora con la colección (siluetas de lo que falta).
    Mientras está equipado no se puede disparar ni golpear.
]]

local C = function() return METALDETECTOR end   -- la config se lee dentro de funciones (CLI-04)
local S = MDX.S
local sw, sh = MDX.sw, MDX.sh

local st = {
    equipped = false,
    spot = nil,            -- { x, y, z, vdi, depth, strokes } confirmado por el servidor
    stats = { distinct = 0, total = 0, finds = 12 },
    onSand = false,
    material = nil,
    dist = nil,            -- distancia 2D al punto
    strength = 0,          -- 0-1
    level = nil,           -- fila de BEEPS activa
    lastBeep = 0,
    nextPropose = 0,
    needle = 0,            -- aguja mostrada (suavizada)
    bootAt = 0,            -- animación de encendido
    dig = nil,             -- { progress, need, zone, lastStroke, feedback, fbAt, pending }
    card = nil,            -- datos del último hallazgo + start
    debugSurface = false,
    hint = nil,            -- { text, untilTick }: por qué E aún no cava
    guideStep = nil,
}
local timers = {}
local tone, hum            -- sonidos en bucle

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if exports.rp_injury:isLocalPlayerDowned() then return false end
    if exports.rp_hud:isHudSuppressed() then return false end
    return true
end

local function groundAt(x, y, z, up, down)
    local hit, _, _, hz, _, _, _, _, material = processLineOfSight(x, y, z + (up or 0.5), x, y, z - (down or 2.5),
        true, false, false, true, false, false, false, false, localPlayer)
    if hit then return material, hz end
end

local function isSand(material) return material and C().SAND_MATERIALS[material] == true end

local function onFootOk()
    return not isPedInVehicle(localPlayer) and not isElementInWater(localPlayer)
        and getElementInterior(localPlayer) == 0 and getElementDimension(localPlayer) == 0
end

local function setWeaponLock(on)
    for _, c in ipairs({ "fire", "aim_weapon", "action" }) do toggleControl(c, not on) end
    if on then setPedWeaponSlot(localPlayer, 0) end
end

local function stopLoops()
    if isElement(tone) then destroyElement(tone) end
    if isElement(hum) then destroyElement(hum) end
    tone, hum = nil, nil
end

local function rarityOf(id) return C().RARITIES[id] or C().RARITIES.common end

----------------------------------------------------------------
-- Punto oculto: buscar arena alrededor y proponerlo al servidor
----------------------------------------------------------------
local function proposeSpot()
    local cfg = C()
    local px, py, pz = getElementPosition(localPlayer)
    for _ = 1, cfg.SPOT_TRIES do
        local a = math.random() * math.pi * 2
        local d = cfg.SPOT_MIN_DIST + math.random() * (cfg.SPOT_MAX_DIST - cfg.SPOT_MIN_DIST)
        local x, y = px + math.cos(a) * d, py + math.sin(a) * d
        local material, gz = groundAt(x, y, pz, 15, 25)
        if isSand(material) and cfg.BEACH_ZONES[getZoneName(x, y, gz)] and not testLineAgainstWater(x, y, gz + 3, x, y, gz + 0.2) then
            triggerServerEvent("rp:metaldetector:proposeSpot", resourceRoot, x, y, gz)
            return
        end
    end
end

----------------------------------------------------------------
-- Timers: suelo (250 ms) y señal/audio (60 ms). Nada pesado en onClientRender.
----------------------------------------------------------------
local function surfaceTick()
    if not st.equipped and not st.debugSurface then return end
    local x, y, z = getElementPosition(localPlayer)
    st.material = groundAt(x, y, z, 0.5, 2.5)
    st.onSand = st.equipped and onFootOk() and isSand(st.material) or false
    if not st.equipped then return end
    if getPedWeaponSlot(localPlayer) ~= 0 then setPedWeaponSlot(localPlayer, 0) end
    if st.dig or st.card then return end

    local now = getTickCount()
    local lost = st.spot and getDistanceBetweenPoints2D(x, y, st.spot[1], st.spot[2]) > C().SPOT_LOST_DIST
    if (not st.spot or lost) and st.onSand and now >= st.nextPropose then
        st.nextPropose = now + 2000
        proposeSpot()
    end
end

local function signalTick()
    local cfg = C()
    local active = st.equipped and st.spot and st.onSand and not st.dig and not st.card
    if not active then
        st.level, st.strength = nil, 0
        st.dist = st.spot and st.equipped and (function()
            local x, y = getElementPosition(localPlayer)
            return getDistanceBetweenPoints2D(x, y, st.spot[1], st.spot[2])
        end)() or nil
        if isElement(tone) then setSoundVolume(tone, 0) end
        if isElement(hum) then setSoundVolume(hum, (st.equipped and not st.dig and not st.card) and cfg.VOLUME.hum or 0) end
        return
    end
    local x, y = getElementPosition(localPlayer)
    st.dist = getDistanceBetweenPoints2D(x, y, st.spot[1], st.spot[2])
    local range = metalDetectorStats(st.stats.tier or 1).range   -- alcance del detector en la mano
    st.strength = MDX.clamp(1 - st.dist / range, 0, 1) ^ 0.8
    st.level = nil
    if st.dist <= range then
        for _, b in ipairs(cfg.BEEPS) do
            if st.dist <= b.maxDist then st.level = b break end
        end
    end
    if isElement(hum) then setSoundVolume(hum, cfg.VOLUME.hum) end

    local vdi = st.spot.vdi or 50
    local low = vdi < cfg.VDI_LOW_TONE
    local now = getTickCount()
    -- Pinpoint: tono continuo (agudo) o gruñido rápido (hierro)
    if st.level and st.level.every == 0 then
        if low then
            if isElement(tone) then setSoundVolume(tone, 0) end
            if now - st.lastBeep >= 240 then st.lastBeep = now; MDX.sound("beep_lo", cfg.VOLUME.beep, 1.05) end
        else
            if not isElement(tone) then tone = MDX.sound("tone_loop", 0, nil, true) end
            if isElement(tone) then
                setSoundVolume(tone, cfg.VOLUME.tone)
                setSoundSpeed(tone, 0.8 + vdi / 99 * 0.6 + 0.012 * math.sin(now / 120))
            end
        end
        return
    end
    if isElement(tone) then setSoundVolume(tone, 0) end
    if st.level and now - st.lastBeep >= st.level.every then
        st.lastBeep = now
        local vol = cfg.VOLUME.beep * (0.45 + 0.55 * st.strength)
        if low then MDX.sound("beep_lo", vol, 0.95 + 0.1 * st.strength)
        else MDX.sound("beep_hi", vol, 0.75 + vdi / 99 * 0.6) end
    end
end

----------------------------------------------------------------
-- Guía (hasta el primer hallazgo del personaje): una línea, con sonido al cambiar de paso
----------------------------------------------------------------
local function guideText()
    if not onFootOk() then return "Ve a pie por la arena de la playa.", "nosand" end
    if not st.onSand then return "Aquí no hay arena: camina hacia la playa.", "nosand" end
    if st.stats.total > 0 and not st.dig then return nil end
    if not st.spot then return "Calibrando... camina por la arena.", "search" end
    if not st.level then return "Sin señal: recorre la arena en distintas direcciones.", "search" end
    if st.level.every ~= 0 then return "¡Pita! Más rápido = más cerca. El número dice qué metal es.", "follow" end
    return "¡Justo aquí! Pulsa E para cavar con la pala.", "dig"
end

----------------------------------------------------------------
-- Pantalla del detector
----------------------------------------------------------------
local function drawDetector(now)
    local cfg = C()
    local w, h = 360 * S, 212 * S
    local x, y = sw - w - 28 * S, sh * 0.5
    local pin = st.level and st.level.every == 0
    local bg = tocolor(14, 16, 22, 236)
    MDX.panel(x, y, w, h, bg)

    -- Borde superior con el color de la lectura (late en pinpoint)
    local range = st.spot and metalDetectorVdiRange(st.spot.vdi or 0)
    local accent = (st.strength > 0 and range) and range.color or { 90, 96, 110 }
    local pulse = pin and (0.6 + 0.4 * math.sin(now / 70)) or 1
    dxDrawRectangle(x + 10 * S, y, w - 20 * S, 3 * S, MDX.rgba(accent, 255 * pulse))

    -- Cabecera
    local fSmall, fBody = MDX.font("bold", 10), MDX.font("medium", 11)
    local tier = cfg.TIERS[st.stats.tier or 1] or cfg.TIERS[1]
    local th = tier.color:gsub("#", "")
    dxDrawCircle(x + 22 * S, y + 20 * S, 5 * S, 0, 360, tocolor(tonumber(th:sub(1, 2), 16), tonumber(th:sub(3, 4), 16), tonumber(th:sub(5, 6), 16)),
        tocolor(tonumber(th:sub(1, 2), 16), tonumber(th:sub(3, 4), 16), tonumber(th:sub(5, 6), 16)), 12)
    MDX.text(("DETECTOR · %s"):format(tier.name:upper()), x + 34 * S, y + 10 * S, x + w, y + 30 * S, tocolor(150, 156, 170), fSmall, "left", "center", false)
    local led = st.level and st.level.led or { 50, 54, 62 }
    local ledA = 255
    if st.level and st.level.every > 0 then ledA = (now - st.lastBeep) < 110 and 255 or 110 end
    if st.level and pin then ledA = 160 + 95 * math.sin(now / 60) end
    dxDrawCircle(x + w - 24 * S, y + 20 * S, 9 * S, 0, 360, MDX.rgba(led, ledA * 0.35), MDX.rgba(led, ledA * 0.35), 16)
    dxDrawCircle(x + w - 24 * S, y + 20 * S, 5 * S, 0, 360, MDX.rgba(led, ledA), MDX.rgba(led, ledA), 16)

    -- Arco de lectura (0-99) con las zonas de metal
    local cx, cy, rOut, rIn = x + 104 * S, y + 150 * S, 82 * S, 66 * S
    local prev = 0
    for _, r in ipairs(cfg.VDI_RANGES) do
        local a1, a2 = 180 + prev / 99 * 180, 180 + math.min(99, r.max) / 99 * 180
        local lit = range == r and st.strength > 0
        MDX.arc(cx, cy, rOut, rIn, a1 + 1, a2 - 1, MDX.rgba(r.color, lit and 255 or 70), bg)
        prev = r.max + 1
    end
    -- Aguja: arranque (barrido), reposo (temblor) o lectura
    local target = 2 + math.sin(now / 130) * 1.5
    local boot = (now - st.bootAt) / 900
    if boot < 1 then target = 99 * math.sin(boot * math.pi)
    elseif st.strength > 0 and st.spot then target = (st.spot.vdi or 0) + math.sin(now / 55) * 4 * (1 - st.strength) end
    st.needle = st.needle + (target - st.needle) * 0.18
    local ang = math.rad(180 + MDX.clamp(st.needle, 0, 99) / 99 * 180)
    dxDrawLine(cx, cy, cx + math.cos(ang) * (rOut - 4 * S), cy + math.sin(ang) * (rOut - 4 * S), tocolor(255, 255, 255, 235), 3 * S)
    dxDrawCircle(cx, cy, 8 * S, 0, 360, tocolor(235, 238, 244), tocolor(235, 238, 244), 16)
    MDX.text("0", cx - rOut - 4 * S, cy + 2 * S, cx - rOut + 20 * S, cy + 18 * S, tocolor(120, 126, 140), fSmall, "left", "top", false)
    MDX.text("99", cx + rOut - 22 * S, cy + 2 * S, cx + rOut + 6 * S, cy + 18 * S, tocolor(120, 126, 140), fSmall, "right", "top", false)

    -- Lectura numérica, tipo de metal y profundidad
    local rx = x + 208 * S
    local readout = (st.strength > 0 and st.spot) and ("%02d"):format(st.spot.vdi or 0) or "--"
    MDX.text(readout, rx, y + 36 * S, x + w - 16 * S, y + 86 * S, MDX.rgba(st.strength > 0 and accent or { 110, 116, 130 }), MDX.font("bold", 34), "left", "center")
    MDX.text(st.strength > 0 and range and range.name or "Sin objetivo", rx, y + 86 * S, x + w - 10 * S, y + 106 * S,
        st.strength > 0 and MDX.rgba(accent) or tocolor(130, 136, 150), MDX.font("bold", 12), "left", "center")
    local depth = (st.dist and st.dist <= 5 and st.spot) and ("Prof. ≈ %d cm"):format(st.spot.depth or 15) or "Prof. --"
    MDX.text(depth, rx, y + 106 * S, x + w - 10 * S, y + 124 * S, tocolor(170, 176, 190), fBody, "left", "center", false)

    -- Barras de fuerza
    local bars, bw, gap = 10, 11 * S, 4 * S
    local bx, by = rx, y + 168 * S
    local lit = math.floor(st.strength * bars + 0.5)
    for i = 1, bars do
        local bh = (8 + i * 2.6) * S
        local k = (i - 1) / (bars - 1)
        local col = i <= lit and tocolor(80 + 170 * k, 210 - 140 * k, 90 - 40 * k, 255) or tocolor(255, 255, 255, 28)
        dxDrawRectangle(bx + (i - 1) * (bw + gap), by - bh, bw, bh, col)
    end
    MDX.text(pin and "¡AQUÍ!" or "SEÑAL", bx, by + 4 * S, bx + bars * (bw + gap), by + 22 * S,
        pin and MDX.rgba({ 255, 90, 70 }, 255 * pulse) or tocolor(140, 146, 160), fSmall, "left", "center", false)

    -- Guía
    local guide, step = guideText()
    if step ~= st.guideStep then
        if step and st.guideStep and st.stats.total == 0 then MDX.sound("pluck_001", 0.5) end
        st.guideStep = step
    end
    if guide then
        local gh = 44 * S
        MDX.panel(x, y + h + 8 * S, w, gh, tocolor(14, 16, 22, 220))
        MDX.text(guide, x + 14 * S, y + h + 8 * S, x + w - 12 * S, y + h + 8 * S + gh, tocolor(232, 234, 240), fBody, "left", "center", false, true)
    end
end

----------------------------------------------------------------
-- Aviso para cavar (junto al punto)
----------------------------------------------------------------
local function drawDigPrompt(now)
    local font = MDX.font("bold", 15)
    local label = "Cavar aquí"
    local w = dxGetTextWidth(label, 1, font) + 90 * S
    local x, y = (sw - w) / 2, sh - 210 * S
    local pulse = 0.75 + 0.25 * math.sin(now / 160)
    MDX.panel(x, y, w, 52 * S)
    dxDrawRectangle(x + 10 * S, y + 52 * S - 3 * S, w - 20 * S, 3 * S, tocolor(255, 196, 50, 255 * pulse))
    local key = MDX.tex("images/keys/keyboard_e.png")
    if key then dxDrawImage(x + 12 * S, y + 6 * S, 40 * S, 40 * S, key, 0, 0, 0, tocolor(255, 255, 255, 255 * pulse)) end
    MDX.text(label, x + 60 * S, y, x + w - 12 * S, y + 52 * S, tocolor(245, 246, 250), font, "left", "center")
end

-- Por qué E todavía no cava (lejos, fuera de la arena)
local function drawHint(now)
    local h = st.hint
    if not h or now > h.untilTick then st.hint = nil return end
    local a = math.min(1, (h.untilTick - now) / 400)
    local font = MDX.font("bold", 13)
    local w = dxGetTextWidth(h.text, 1, font) + 40 * S
    local x, y = (sw - w) / 2, sh - 210 * S
    MDX.panel(x, y, w, 44 * S, tocolor(14, 16, 22, 230 * a))
    dxDrawRectangle(x + 10 * S, y + 41 * S, w - 20 * S, 3 * S, tocolor(245, 165, 36, 255 * a))
    MDX.text(h.text, x, y, x + w, y + 44 * S, tocolor(245, 246, 250, 255 * a), font, "center", "center")
end

----------------------------------------------------------------
-- Minijuego de paladas
----------------------------------------------------------------
local function strokeMarker(now)
    local cfg = C()
    local t = (now / 1000) * cfg.STROKE_SPEED
    return 0.5 - 0.5 * math.cos(t * math.pi * 2)   -- 0..1 de ida y vuelta
end

local function newZone()
    local cfg = C()
    return 0.12 + math.random() * (1 - 0.24 - cfg.STROKE_ZONE)
end

local function drawDig(now)
    local cfg, d = C(), st.dig
    local w, h = 520 * S, 168 * S
    local x, y = (sw - w) / 2, sh - 250 * S
    MDX.panel(x, y, w, h)
    local depthCm = st.spot and st.spot.depth or 20
    local frac = MDX.clamp(d.progress / d.need, 0, 1)
    MDX.text("Cavando", x + 20 * S, y + 12 * S, x + w, y + 40 * S, tocolor(245, 246, 250), MDX.font("bold", 16), "left", "center")
    MDX.text(("%d / %d cm"):format(math.floor(depthCm * frac + 0.5), depthCm), x, y + 12 * S, x + w - 20 * S, y + 40 * S,
        tocolor(210, 186, 130), MDX.font("bold", 14), "right", "center")

    -- Profundidad
    local px, py, pw = x + 20 * S, y + 48 * S, w - 40 * S
    dxDrawRectangle(px, py, pw, 8 * S, tocolor(255, 255, 255, 25))
    dxDrawRectangle(px, py, pw * frac, 8 * S, tocolor(210, 170, 100, 255))

    -- Barra de palada: zona buena y marcador que va y viene
    local bx, by, bw, bh = x + 20 * S, y + 72 * S, w - 40 * S, 30 * S
    dxDrawRectangle(bx, by, bw, bh, tocolor(255, 255, 255, 18))
    local zx = bx + bw * d.zone
    local zw = bw * cfg.STROKE_ZONE
    dxDrawRectangle(zx, by, zw, bh, tocolor(80, 210, 110, 170))
    dxDrawRectangle(zx + zw * 0.35, by, zw * 0.3, bh, tocolor(120, 245, 150, 220))
    local locked = now - d.lastStroke < cfg.STROKE_MIN_MS
    local m = strokeMarker(now)
    dxDrawRectangle(bx + bw * m - 3 * S, by - 6 * S, 6 * S, bh + 12 * S, locked and tocolor(255, 255, 255, 90) or tocolor(255, 255, 255, 255))

    -- Respuesta de la última palada
    if d.feedback and now - d.fbAt < 700 then
        local k = (now - d.fbAt) / 700
        local col = d.feedback == "good" and { 120, 240, 140 } or { 245, 170, 70 }
        MDX.text(d.feedback == "good" and "¡Buena palada!" or "Palada floja", x, y - 40 * S - 20 * S * k, x + w, y - 6 * S,
            MDX.rgba(col, 255 * (1 - k)), MDX.font("bold", 18), "center", "center")
    end

    -- Teclas
    local fk = MDX.font("medium", 12)
    local used = MDX.keyHint(MDX.tex("images/keys/keyboard_e.png"), "Palada (en la zona verde)", x + 20 * S, y + h - 48 * S, 32 * S, fk)
    MDX.keyHint(MDX.tex("images/keys/keyboard_backspace.png"), "Dejar de cavar", x + 40 * S + used, y + h - 48 * S, 32 * S, fk)
end

local function doStroke()
    local cfg, d = C(), st.dig
    local now = getTickCount()
    if now - d.lastStroke < cfg.STROKE_MIN_MS + 30 or d.pending then return end
    local m = strokeMarker(now)
    local good = m >= d.zone and m <= d.zone + cfg.STROKE_ZONE
    d.lastStroke, d.feedback, d.fbAt = now, good and "good" or "weak", now
    d.progress = math.min(d.need, d.progress + (good and 1 or cfg.WEAK_STROKE))
    d.zone = newZone()
    if d.progress >= d.need - 0.001 then d.pending = true end   -- el servidor manda el hallazgo
    triggerServerEvent("rp:metaldetector:stroke", resourceRoot, good)

    local sx, sy, sz = st.spot[1], st.spot[2], st.spot[3]
    MDX.fx.stroke(sx, sy, sz, good)
    MDX.fx.digHole(sx, sy, sz, d.progress / d.need)
    MDX.sound("footstep_snow_00" .. math.random(0, 2), 0.9, 0.9 + math.random() * 0.2)
    MDX.sound(good and "impactSoft_heavy_001" or "impactSoft_medium_000", good and 0.6 or 0.4)
    if d.pending then MDX.sound("impactMetal_light_00" .. (math.random(0, 1) * 2), 0.9) end   -- ¡la pala toca metal!
end

----------------------------------------------------------------
-- Tarjeta del hallazgo
----------------------------------------------------------------
local function drawCard(now)
    local c = st.card
    local t = now - c.start - 500
    if t < 0 then return end
    local life = c.closeup and 7600 or 4200   -- con plano cercano la tarjeta sale al volver la cámara
    if t > life then st.card = nil return end
    local rar = rarityOf(c.rarity)
    local inK = MDX.easeOutBack(MDX.clamp(t / 450, 0, 1))
    local outK = MDX.clamp((t - life + 400) / 400, 0, 1)
    local a = 1 - outK

    local w, h = 500 * S, 190 * S
    local x = (sw - w) / 2
    local y = sh - 300 * S + (1 - inK) * 60 * S + outK * 30 * S
    MDX.panel(x, y, w, h, tocolor(14, 16, 22, 240 * a))
    dxDrawRectangle(x + 12 * S, y, w - 24 * S, 4 * S, MDX.rgba(rar.color, 255 * a))

    -- Imagen con brillo de la rareza
    local glow = MDX.tex("images/fx/glow.png")
    local isz = 150 * S
    local ix, iy = x + 20 * S, y + (h - isz) / 2
    if glow then
        local g = isz * (1.25 + 0.06 * math.sin(now / 160))
        dxDrawImage(ix + isz / 2 - g / 2, iy + isz / 2 - g / 2, g, g, glow, 0, 0, 0, MDX.rgba(rar.color, 150 * a))
    end
    local tex = MDX.itemTex(c.item)
    if tex then dxDrawImage(ix, iy, isz, isz, tex, math.sin(now / 400) * 4, 0, 0, tocolor(255, 255, 255, 255 * a)) end

    -- Textos
    local tx, tw = ix + isz + 20 * S, x + w - 18 * S
    local ty = y + 18 * S
    MDX.text(rar.name:upper(), tx, ty, tw, ty + 20 * S, MDX.rgba(rar.color, 255 * a), MDX.font("bold", 12), "left", "center")
    local name = c.amount > 1 and ("%s  x%d"):format(c.name, c.amount) or c.name
    MDX.text(name, tx, ty + 20 * S, tw, ty + 56 * S, tocolor(250, 250, 252, 255 * a), MDX.font("bold", 22), "left", "center", true, true)
    local line = c.price and ("≈ $%d en el Puesto del buscador"):format(c.price * c.amount) or "Se vende en el Puesto del buscador"
    MDX.text(line, tx, ty + 60 * S, tw, ty + 80 * S, tocolor(140, 225, 150, 255 * a), MDX.font("medium", 12), "left", "center")
    MDX.text(c.levelUp and ("+%d XP de buscador · ¡NIVEL %d!"):format(c.xp or 0, c.levelUp) or ("+%d XP de buscador"):format(c.xp or 0), tx, ty + 82 * S, tw, ty + 102 * S, tocolor(150, 190, 255, 255 * a), MDX.font("medium", 12), "left", "center")
    if c.ground then
        MDX.text("No te cabía: lo dejaste en la arena.", tx, ty + 104 * S, tw, ty + 124 * S, tocolor(245, 180, 80, 255 * a), MDX.font("medium", 11), "left", "center")
    end

    -- Insignia de colección
    local badgeY = y + h - 42 * S
    if c.isNew then
        local p = 0.8 + 0.2 * math.sin(now / 110)
        local bt = ("¡NUEVO EN TU COLECCIÓN!  %d/%d"):format(c.distinct, c.finds)
        local bw = dxGetTextWidth(bt, 1, MDX.font("bold", 12)) + 24 * S
        MDX.panel(tx, badgeY, bw, 28 * S, MDX.rgba({ 255, 196, 50 }, 235 * a * p), 8 * S)
        MDX.text(bt, tx, badgeY, tx + bw, badgeY + 28 * S, tocolor(30, 24, 10, 255 * a), MDX.font("bold", 12), "center", "center", false)
    else
        MDX.text(("Encontrado %d veces · Colección %d/%d · /detector"):format(c.times, c.distinct, c.finds), tx, badgeY, tw, badgeY + 28 * S,
            tocolor(160, 166, 180, 255 * a), MDX.font("medium", 11), "left", "center")
    end
end

----------------------------------------------------------------
-- Render (solo dibuja lo que calcularon los timers)
----------------------------------------------------------------
addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    if st.debugSurface then
        MDX.text(("Material bajo los pies: %s  (%s)"):format(tostring(st.material), isSand(st.material) and "arena" or "no arena"),
            0, sh * 0.3, sw, sh * 0.3 + 30, tocolor(255, 230, 120), MDX.font("bold", 16), "center", "center")
    end
    if MDX.fx.closeupActive() then return end
    if st.card then drawCard(now) end
    if not st.equipped or exports.rp_hud:isHudSuppressed() then return end
    if st.dig then
        drawDig(now)
    elseif not st.card then
        drawDetector(now)
        if st.spot and st.dist and st.onSand and st.dist <= C().DIG_RADIUS and canInteract() then drawDigPrompt(now)
        elseif st.hint then drawHint(now) end
    end
end)

----------------------------------------------------------------
-- Eventos del servidor
----------------------------------------------------------------
addEvent("rp:metaldetector:state", true)
addEventHandler("rp:metaldetector:state", resourceRoot, function(on, spot, stats)
    local was = st.equipped
    st.equipped = on == true
    st.spot = type(spot) == "table" and spot or nil
    if type(stats) == "table" then st.stats = stats end
    if st.equipped ~= was then
        setWeaponLock(st.equipped)
        if st.equipped then
            st.bootAt, st.needle = getTickCount(), 0
            MDX.sound("power_on", 0.6)
            if not isElement(hum) then hum = MDX.sound("hum_loop", 0, nil, true) end
        else
            stopLoops()
        end
    end
    if not st.equipped then st.dig, st.level, st.dist, st.strength = nil, nil, nil, 0 end
    if st.equipped and not st.spot then st.nextPropose = math.max(st.nextPropose, getTickCount()) end
end)

addEvent("rp:metaldetector:dig", true)
addEventHandler("rp:metaldetector:dig", resourceRoot, function(kind, progress, need)
    if kind == "start" then
        st.dig = { progress = 0, need = need or 3, zone = newZone(), lastStroke = getTickCount() - 400 }
        if isElement(tone) then setSoundVolume(tone, 0) end
        MDX.sound("drop_002", 0.7)
        if st.spot then MDX.fx.digHole(st.spot[1], st.spot[2], st.spot[3], 0) end
    elseif kind == "progress" and st.dig then
        st.dig.progress, st.dig.need = progress or st.dig.progress, need or st.dig.need   -- el servidor manda
    elseif kind == "stop" then
        st.dig = nil
    elseif kind == "noshovel" then
        MDX.sound("error_004", 0.6)
    end
end)

addEvent("rp:metaldetector:reveal", true)
addEventHandler("rp:metaldetector:reveal", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    st.dig, st.spot, st.level, st.dist, st.strength = nil, nil, nil, nil, 0
    if isElement(tone) then setSoundVolume(tone, 0) end
    st.stats.total = (st.stats.total or 0) + 1
    st.stats.distinct = data.distinct or st.stats.distinct
    local rar = rarityOf(data.rarity)
    data.start, data.closeup = getTickCount(), rar.closeup
    st.card = data
    st.nextPropose = getTickCount() + C().NEXT_SPOT_MS
    MDX.fx.reveal(data, true)

    setTimer(function() MDX.sound(rar.sound, 0.85) end, 250, 1)
    if rar.order >= 3 then setTimer(function() MDX.sound("sparkle", 0.6) end, 600, 1) end
    if data.item == "old_coin" or data.item == "doubloon" then setTimer(function() MDX.sound("coins", 0.6) end, 900, 1) end
    if data.isNew then setTimer(function() MDX.sound("new_entry", 0.8) end, 1100, 1) end
    if data.levelUp then setTimer(function() MDX.sound("reveal_rare", 0.7) end, 1800, 1) end
end)

addEvent("rp:metaldetector:othersReveal", true)
addEventHandler("rp:metaldetector:othersReveal", resourceRoot, function(x, y, z, item, rarity)
    MDX.fx.othersReveal(x, y, z, item, rarity)
end)

addEvent("rp:metaldetector:debugSurface", true)
addEventHandler("rp:metaldetector:debugSurface", resourceRoot, function()
    st.debugSurface = not st.debugSurface
    exports.rp_notify:notify("Medidor de material " .. (st.debugSurface and "activado" or "desactivado") .. ".", "info")
end)

----------------------------------------------------------------
-- Teclas: E solo actúa junto a tu punto o cavando (la usan muchos recursos)
----------------------------------------------------------------
-- Aviso breve junto a la pantalla del detector cuando E no puede hacer nada todavía (UX-08: nunca en silencio)
local function hint(text)
    if st.hint and st.hint.text == text and getTickCount() < st.hint.untilTick - 1500 then return end
    st.hint = { text = text, untilTick = getTickCount() + 2200 }
    MDX.sound("error_004", 0.35)
end

local function onE()
    if not st.equipped or not canInteract() then return end
    if st.dig then return doStroke() end
    if st.card then return end
    -- Solo explica por qué no cuando hay una señal cerca (E la usan muchos recursos)
    if not st.spot or not st.dist or st.dist > metalDetectorStats(st.stats.tier or 1).range then return end
    if not st.onSand then return hint("Tienes que estar sobre la arena para cavar.") end
    if st.dist > C().DIG_RADIUS then return hint("Aún no: acércate hasta que el tono sea continuo («¡AQUÍ!»).") end
    triggerServerEvent("rp:metaldetector:startDig", resourceRoot)
end

local function onBackspace()
    if st.dig and not st.dig.pending and canInteract() then
        triggerServerEvent("rp:metaldetector:cancelDig", resourceRoot)
    end
end

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", onE)
    bindKey("backspace", "down", onBackspace)
    timers[1] = setTimer(surfaceTick, METALDETECTOR.SURFACE_CHECK_MS, 0)
    timers[2] = setTimer(signalTick, METALDETECTOR.BEEP_TICK_MS, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if st.equipped then setWeaponLock(false) end
    stopLoops()
    unbindKey("e", "down", onE)
    unbindKey("backspace", "down", onBackspace)
    for _, t in ipairs(timers) do if isTimer(t) then killTimer(t) end end
end)
