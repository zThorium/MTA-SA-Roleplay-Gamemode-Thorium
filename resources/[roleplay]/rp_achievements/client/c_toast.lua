--[[
    rp_achievements / c_toast.lua  (cliente)

    Aviso de medalla con el sistema de UI de la GM (mismo lenguaje que rp_levels y rp_notify):
      - tarjeta oscura con lados en diagonal colgada arriba al centro, debajo de la barra de RP;
      - medalla dibujada con c_dx.lua (disco, aro, estrella) del color de su medalla, con el
        halo y las chispas de las texturas propias (images/fx, las mismas del detector);
      - "LOGRO · ORO" en Kenney Future, nombre en Rubik, "+50 PUNTOS" que sube rodando;
      - sonido según la medalla (paleta: confirmation_002/003, reveal_rare/legendary + sparkle);
      - si se alcanza un hito, anuncio central de rp_notify (tipo "level") y bong_001.
    Varios avisos seguidos se encolan. Con el HUD suprimido (cinemáticas) se pausan.
    /probarlogro enseña las cuatro medallas solo en tu pantalla.
]]

AchUI = AchUI or {}   -- lo comparten c_toast.lua y c_panel.lua

local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.35, screenH / 900))
local function px(v) return v * S end

-- Fuentes de rp_notify (mismo archivo que usa rp_levels, sin copiarlo otra vez)
local function font(path, size, fallback)
    return dxCreateFont(path, math.floor(size * S + 0.5), false, "antialiased") or fallback
end
local F_LABEL = font(":rp_notify/fonts/kenney_future.ttf", 7.5, "default-bold")
local F_POINTS = font(":rp_notify/fonts/kenney_future.ttf", 11, "default-bold")
local F_NAME = font(":rp_notify/fonts/rubik_medium.ttf", 13, "default-bold")
local F_SMALL = font(":rp_notify/fonts/rubik_regular.ttf", 8.5, "default")

local TEX_GLOW = dxCreateTexture("images/fx/glow.png")
local TEX_SPARK = dxCreateTexture("images/fx/sparkle.png")
local TEX_RING = dxCreateTexture("images/fx/ring.png")

local T = { IN = 420, HOLD = 3400, HOLD_QUEUED = 1500, OUT = 350 }
local DARK = { 11, 13, 19 }
local CW, CH = px(400), px(70)
local SK = px(14)
local TOP = px(12) + px(64) + px(14)     -- debajo de la tarjeta de rp_levels
local MR = px(24)                        -- radio de la medalla

local queue, anim, sparks = {}, nil, {}
local lastSound = 0

----------------------------------------------------------------
-- Utilidades (mismas curvas que rp_levels)
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeOutBack(t)
    t = clamp(t, 0, 1)
    local c = 1.70158
    return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function rgba(c, a) return tocolor(c[1], c[2], c[3], clamp(a, 0, 255)) end
local function mix(c1, c2, k) return { c1[1] + (c2[1] - c1[1]) * k, c1[2] + (c2[2] - c1[2]) * k, c1[3] + (c2[3] - c1[3]) * k } end

local function play(file, volume)
    local snd = playSound("sounds/" .. file)
    if snd then setSoundVolume(snd, volume or 0.5) end
end

-- Sonido de la medalla (con enfriamiento: nunca en ráfaga, UX-06)
local MEDAL_SOUNDS = {
    { { "confirmation_002.ogg", 0.5 } },
    { { "confirmation_003.ogg", 0.55 } },
    { { "reveal_rare.wav", 0.6 }, { "sparkle.wav", 0.4 } },
    { { "reveal_legendary.wav", 0.65 }, { "sparkle.wav", 0.45 } },
}
local function medalSound(medal)
    local now = getTickCount()
    if now - lastSound < 600 then return end
    lastSound = now
    for _, s in ipairs(MEDAL_SOUNDS[medal] or MEDAL_SOUNDS[1]) do play(s[1], s[2]) end
end

----------------------------------------------------------------
-- Cola
----------------------------------------------------------------
local function startNext()
    local ev = table.remove(queue, 1)
    if not ev then anim = nil; return end
    anim = {
        t0 = getTickCount(), a = ev.a, tier = ev.tier, medal = ev.medal, gained = ev.gained,
        milestone = ev.milestone, hold = (#queue > 0) and T.HOLD_QUEUED or T.HOLD,
        sounded = false, sparked = false, popped = false,
    }
end

local function push(achKey, tier, gained, milestone)
    local a = ACH.BY_KEY[achKey]
    local medal = ACH.medalOf(a, tier)
    if not a or not medal then return end
    queue[#queue + 1] = { a = a, tier = tier, medal = medal, gained = gained or 0, milestone = milestone }
    if not anim then startNext() end
end

addEvent("rp:achievements:unlocked", true)
addEventHandler("rp:achievements:unlocked", resourceRoot, function(achKey, tier, gained, total, milestone)
    tier, gained = tonumber(tier), tonumber(gained)
    if type(achKey) ~= "string" or not tier then return end
    push(achKey, tier, gained, tonumber(milestone) or nil)
    if AchUI.onPoints then AchUI.onPoints(tonumber(total) or 0) end
end)

----------------------------------------------------------------
-- Chispas (textura propia sparkle.png, como el detector)
----------------------------------------------------------------
local function burst(x, y, color, n)
    local now = getTickCount()
    for _ = 1, n do
        local ang = math.rad(math.random(0, 359))
        local v = math.random(60, 200) / 1000 * S
        sparks[#sparks + 1] = { x = x, y = y, vx = math.cos(ang) * v, vy = math.sin(ang) * v - 0.04 * S,
            born = now, life = math.random(500, 950), r = math.random(10, 22) / 10 * S * 4, c = color }
    end
end

local function drawSparks(now, dt)
    for i = #sparks, 1, -1 do
        local p = sparks[i]
        local k = (now - p.born) / p.life
        if k >= 1 then
            table.remove(sparks, i)
        else
            p.vy = p.vy + 0.00025 * S * dt
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            local r = p.r * (1 - k * 0.5)
            if TEX_SPARK then
                dxDrawImage(p.x - r, p.y - r, r * 2, r * 2, TEX_SPARK, k * 180, 0, 0, rgba(p.c, 255 * (1 - k)), false)
            else
                DX.circle(p.x, p.y, r / 4, rgba(p.c, 255 * (1 - k)), false)
            end
        end
    end
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function drawCard(x, y, a, color, shimmer)
    local w, h = CW, CH
    local shadow = tocolor(0, 0, 0, 70 * a)
    DX.poly({ { x, y + px(4), shadow }, { x + w, y + px(4), shadow }, { x + w - SK, y + h + px(4), shadow }, { x + SK, y + h + px(4), shadow } }, false)
    local body = tocolor(DARK[1], DARK[2], DARK[3], 235 * a)
    DX.poly({ { x, y, body }, { x + w, y, body }, { x + w - SK, y + h, body }, { x + SK, y + h, body } }, false)
    -- Halo del color de la medalla, desde la izquierda
    local glow, none = rgba(color, 30 * a), rgba(color, 0)
    local gx = w * 0.55
    dxDrawPrimitive("trianglestrip", false, { x + SK, y, glow }, { x + gx, y, none }, { x + SK * 2, y + h, glow }, { x + gx, y + h, none })
    -- Línea de luz abajo
    local cx, half = x + w / 2, (w / 2 - SK) * 0.9
    local solid, n0 = rgba(color, 210 * a), rgba(color, 0)
    dxDrawPrimitive("trianglestrip", false, { cx - half, y + h - 2, n0 }, { cx, y + h - 2, solid }, { cx - half, y + h, n0 }, { cx, y + h, solid })
    dxDrawPrimitive("trianglestrip", false, { cx, y + h - 2, solid }, { cx + half, y + h - 2, n0 }, { cx, y + h, solid }, { cx + half, y + h, n0 })
    if shimmer then
        local bx = x - px(40) + (w + px(80)) * shimmer
        local bw, sk = px(26), px(22)
        local function cl(v) return clamp(v, x + SK, x + w - SK) end
        local c0, c1 = tocolor(255, 255, 255, 0), tocolor(255, 255, 255, 55 * a)
        dxDrawPrimitive("trianglestrip", false, { cl(bx + sk), y, c0 }, { cl(bx + sk + bw), y, c1 }, { cl(bx), y + h, c0 }, { cl(bx + bw), y + h, c1 })
    end
end

-- Estrella de 5 puntas (cóncava): pentágono central + 5 puntas, todo convexo para DX.poly
local function drawStar(cx, cy, r, color)
    local outer, inner = {}, {}
    for i = 0, 4 do
        local ao = math.rad(-90 + i * 72)
        local ai = math.rad(-90 + 36 + i * 72)
        outer[i + 1] = { cx + math.cos(ao) * r, cy + math.sin(ao) * r }
        inner[i + 1] = { cx + math.cos(ai) * r * 0.42, cy + math.sin(ai) * r * 0.42 }
    end
    local pent = {}
    for i = 1, 5 do pent[i] = { inner[i][1], inner[i][2], color } end
    DX.poly(pent, false)
    for i = 1, 5 do
        local prev = inner[(i - 2) % 5 + 1]
        DX.poly({ { outer[i][1], outer[i][2], color }, { inner[i][1], inner[i][2], color }, { prev[1], prev[2], color } }, false)
    end
end

local function drawMedal(cx, cy, r, color, medal, a, pop)
    r = r * pop
    -- Halo (textura propia glow.png) que crece con la medalla
    if TEX_GLOW then
        local g = r * (2.2 + medal * 0.35)
        dxDrawImage(cx - g, cy - g, g * 2, g * 2, TEX_GLOW, 0, 0, 0, rgba(color, (90 + medal * 25) * a), false)
    end
    -- Cintas
    local ribbon = rgba(mix(color, { 0, 0, 0 }, 0.35), 255 * a)
    DX.poly({ { cx - r * 0.55, cy + r * 0.5, ribbon }, { cx - r * 0.15, cy + r * 0.6, ribbon }, { cx - r * 0.35, cy + r * 1.45, ribbon }, { cx - r * 0.7, cy + r * 1.25, ribbon } }, false)
    DX.poly({ { cx + r * 0.15, cy + r * 0.6, ribbon }, { cx + r * 0.55, cy + r * 0.5, ribbon }, { cx + r * 0.7, cy + r * 1.25, ribbon }, { cx + r * 0.35, cy + r * 1.45, ribbon } }, false)
    -- Disco con aro brillante
    DX.circle(cx, cy, r + px(2), tocolor(DARK[1], DARK[2], DARK[3], 255 * a), false)
    DX.circle(cx, cy, r, rgba(mix(color, { 0, 0, 0 }, 0.25), 255 * a), false)
    DX.circle(cx, cy, r * 0.78, rgba(color, 255 * a), false)
    DX.ring(cx, cy, r, px(2.5), 0, 360, rgba(mix(color, { 255, 255, 255 }, 0.5), 255 * a), false)
    drawStar(cx, cy, r * 0.55, rgba(mix(color, { 255, 255, 255 }, 0.65), 255 * a))
    -- Platino: aro extra (ring.png) girando
    if medal >= 4 and TEX_RING then
        local rr = r * 1.6
        dxDrawImage(cx - rr, cy - rr, rr * 2, rr * 2, TEX_RING, (getTickCount() / 12) % 360, 0, 0, rgba(color, 160 * a), false)
    end
end

local lastFrame = getTickCount()
addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(now - lastFrame, 100)
    lastFrame = now
    if not anim then
        if #sparks > 0 then drawSparks(now, dt) end
        return
    end
    -- Con el HUD suprimido (cinemática, foto) se pausa: su tiempo no corre
    if getElementData(localPlayer, "rp:hudHidden") then anim.t0 = anim.t0 + dt; return end

    local t = now - anim.t0
    local tOut = T.IN + anim.hold
    local tEnd = tOut + T.OUT
    local slide = t < T.IN and easeOutBack(t / T.IN) or (t > tOut and 1 - easeOut((t - tOut) / T.OUT) or 1)
    local a = clamp(t < T.IN and t / 200 or slide, 0, 1)
    local x = screenW / 2 - CW / 2
    local y = TOP - (1 - slide) * (CH + TOP + px(10))

    local m = ACH.MEDALS[anim.medal]
    local color = m.color
    local tPop = T.IN - 120

    if t >= tPop and not anim.sounded then
        anim.sounded = true
        medalSound(anim.medal)
    end

    drawCard(x, y, a, color, (t >= tPop and t < tPop + 900) and easeOut((t - tPop) / 900) or nil)

    -- Medalla: entra con un salto
    local mx, my = x + SK + px(16) + MR, y + CH / 2 - px(4)
    local pop = t < tPop and 0.6 or easeOutBack((t - tPop) / 450)
    drawMedal(mx, my, MR, color, anim.medal, a, math.max(0.01, pop))
    if t >= tPop and t < tPop + 650 then
        local e = easeOut((t - tPop) / 650)
        DX.ring(mx, my, MR * (1 + 1.6 * e), px(3) * (1 - e) + 1, 0, 360, rgba(color, 230 * (1 - e) * a), false)
    end
    if t >= tPop and not anim.sparked then
        anim.sparked = true
        burst(mx, my, mix(color, { 255, 255, 255 }, 0.3), 10 + anim.medal * 6)
    end

    -- Textos
    local tx = mx + MR + px(20)
    local right = x + CW - SK - px(20)
    local ty = y + px(10)
    dxDrawText(("LOGRO · %s"):format(m.label), tx, ty, 0, 0, rgba(color, 255 * a), 1, F_LABEL, "left", "top")
    local shown = anim.gained * easeOut((t - tPop) / 700)
    dxDrawText(("+%d PUNTOS"):format(math.floor(shown + 0.5)), right, ty - px(1), right, 0,
        rgba(mix({ 255, 255, 255 }, color, 0.35), 255 * a), 1, F_POINTS, "right", "top")
    dxDrawText(anim.a.name, tx, ty + px(15), right, 0, tocolor(242, 244, 248, 255 * a), 1, F_NAME, "left", "top", true)
    local goal = anim.a.tiers[anim.tier]
    local desc = anim.a.desc:find("%%s") and anim.a.desc:format(ACH.formatGoal(anim.a, goal)) or anim.a.desc
    dxDrawText(desc, tx, ty + px(36), right, 0, tocolor(150, 158, 174, 235 * a), 1, F_SMALL, "left", "top", true)

    -- Hito alcanzado: anuncio central de rp_notify, un instante después
    if anim.milestone and not anim.popped and t >= tPop + 900 then
        anim.popped = true
        play("bong_001.ogg", 0.55)
        exports.rp_notify:popup("¡Recompensa de logros!",
            ("Llegaste a %s puntos. Escribe /%s y reclámala."):format(ACH.fmt(ACH.MILESTONES[anim.milestone].points), ACH.COMMAND),
            "level", 6000)
    end

    drawSparks(now, dt)
    if t >= tEnd then startNext() end
end)

----------------------------------------------------------------
-- /probarlogro: las cuatro medallas solo en tu pantalla (no da nada)
----------------------------------------------------------------
addCommandHandler("probarlogro", function()
    if anim then return end
    local a = ACH.BY_KEY["pizzero"]
    for tier = 1, 4 do
        queue[#queue + 1] = { a = a, tier = tier, medal = tier, gained = ACH.MEDALS[tier].points, milestone = nil }
    end
    startNext()
end)
