--[[
    rp_levels / c_levels.lua

    Barra de RP arriba al centro (misma línea visual que rp_notify: tarjeta oscura con
    bordes en diagonal, formas suavizadas con c_dx.lua, Kenney Future + Rubik):
      1. Baja colgada del borde superior con un rebote.
         Izquierda: insignia con tu nivel y un aro que es el progreso al siguiente.
         Derecha: "NIVEL N", contador "+N XP" que sube rodando, barra con la parte
         ganada en blanco y una cabeza brillante, y "actual / necesario XP · faltan N".
      2. Mientras se llena suenan ticks que suben de tono; al terminar, una confirmación.
      3. Si subes de nivel: la barra y el aro se completan en dorado, destello y onda
         desde la insignia, chispas doradas, el número cambia con un salto y suena
         levelup.ogg. Sale el anuncio central de rp_notify ("¡Nivel N!", tipo "level")
         y la barra se rellena con el progreso del nivel nuevo.
      4. Sube y se esconde. Varios avisos seguidos se encolan.
    Con el HUD suprimido (cinemáticas) la animación se pausa.
    El servidor manda rp:levels:update (nivel, xp del nivel, xp necesario, ganado, subio).
]]

local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.35, screenH / 900))
local function px(v) return v * S end

-- Fuentes de rp_notify (mismo archivo, sin copiarlo otra vez)
local function font(path, size, fallback)
    return dxCreateFont(path, math.floor(size * S + 0.5), false, "antialiased") or fallback
end
local F_NUM = font(":rp_notify/fonts/kenney_future.ttf", 15, "default-bold")
local F_LABEL = font(":rp_notify/fonts/kenney_future.ttf", 7.5, "default-bold")
local F_GAIN = font(":rp_notify/fonts/rubik_medium.ttf", 12, "default-bold")
local F_SMALL = font(":rp_notify/fonts/rubik_regular.ttf", 8.5, "default")

local T = {                       -- tiempos en ms
    IN = 420, FILL = 1000, FLASH = 750, REFILL = 800,
    HOLD = 2600, HOLD_QUEUED = 900, OUT = 350,
}
local BLUE = { 86, 168, 255 }
local GOLD = { 255, 196, 64 }
local DARK = { 11, 13, 19 }

local CW, CH = px(390), px(64)      -- tarjeta (borde de arriba; el de abajo es más corto)
local SK = px(14)                    -- inclinación de los lados
local TOP = px(12)
local BR = px(22)                    -- radio de la insignia
local BAR_H = px(7)

local known = { level = nil, frac = 0 }   -- último estado conocido (para animar desde ahí)
local queue, anim, sparks = {}, nil, {}

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeInOut(t) t = clamp(t, 0, 1); return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end
local function easeOutBack(t)
    t = clamp(t, 0, 1)
    local c = 1.70158
    return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function rgba(c, a) return tocolor(c[1], c[2], c[3], clamp(a, 0, 255)) end
local function mix(c1, c2, k) return { c1[1] + (c2[1] - c1[1]) * k, c1[2] + (c2[2] - c1[2]) * k, c1[3] + (c2[3] - c1[3]) * k } end

-- 12345 -> "12.345"
local function fmt(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    return (out:gsub("^%.", ""))
end

local function play(file, volume, speed)
    local snd = playSound("sounds/" .. file)
    if snd then
        setSoundVolume(snd, volume or 0.5)
        if speed then setSoundSpeed(snd, speed) end
    end
end

local function needOf(level) return xpForLevel(level + 1) - xpForLevel(level) end

----------------------------------------------------------------
-- Cola de animaciones
----------------------------------------------------------------
local function startNext()
    -- Si la anterior era la prueba de /probarnivel, vuelve al estado real
    if anim and anim.restore then known.level, known.frac = anim.restore.level, anim.restore.frac end
    local ev = table.remove(queue, 1)
    if not ev then anim = nil; return end
    local fromLevel = known.level or ev.level
    local fromFrac = known.frac
    local levelUp = ev.levelUp and ev.level > fromLevel
    local fromNeed = needOf(fromLevel)
    anim = {
        t0 = getTickCount(), gained = ev.gained, levelUp = levelUp,
        fromLevel = fromLevel, toLevel = ev.level, fromFrac = fromFrac,
        toFrac = ev.need > 0 and ev.cur / ev.need or 1,
        fromNeed = fromNeed, cur = ev.cur, need = ev.need,
        hold = (#queue > 0) and T.HOLD_QUEUED or T.HOLD, restore = ev.restore,
        lastTick = 0, filled = false, flashed = false, popped = false,
    }
    known.level, known.frac = ev.level, anim.toFrac
    play("maximize_003.ogg", 0.25)
end

addEvent("rp:levels:update", true)
addEventHandler("rp:levels:update", resourceRoot, function(level, cur, need, gained, levelUp)
    level, cur, need, gained = tonumber(level), tonumber(cur), tonumber(need), tonumber(gained) or 0
    if not level or not cur or not need then return end
    if gained <= 0 then                       -- sincronización silenciosa (al entrar al juego)
        known.level, known.frac = level, need > 0 and cur / need or 1
        return
    end
    queue[#queue + 1] = { level = level, cur = cur, need = need, gained = gained, levelUp = levelUp }
    if not anim then startNext() end
end)

----------------------------------------------------------------
-- Chispas doradas
----------------------------------------------------------------
local function burst(x, y)
    local now = getTickCount()
    for _ = 1, 22 do
        local a = math.rad(math.random(0, 359))
        local v = math.random(80, 220) / 1000 * S
        sparks[#sparks + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - 0.05 * S,
            born = now, life = math.random(500, 900), r = math.random(15, 30) / 10 * S }
    end
end

local function drawSparks(now, dt)
    for i = #sparks, 1, -1 do
        local p = sparks[i]
        local k = (now - p.born) / p.life
        if k >= 1 then
            table.remove(sparks, i)
        else
            p.vy = p.vy + 0.0003 * S * dt
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            DX.circle(p.x, p.y, p.r * (1 - k * 0.5), rgba(GOLD, 255 * (1 - k)), false)
        end
    end
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function drawCard(x, y, a, shimmer)
    -- Trapecio colgado del borde superior: arriba más ancho que abajo
    local w, h = CW, CH
    local shadow = tocolor(0, 0, 0, 70 * a)
    DX.poly({ { x, y + px(4), shadow }, { x + w, y + px(4), shadow }, { x + w - SK, y + h + px(4), shadow }, { x + SK, y + h + px(4), shadow } }, false)
    local body = tocolor(DARK[1], DARK[2], DARK[3], 235 * a)
    DX.poly({ { x, y, body }, { x + w, y, body }, { x + w - SK, y + h, body }, { x + SK, y + h, body } }, false)
    -- Halo azul suave en el centro (por dentro, no necesita suavizado)
    local cx = x + w / 2
    local glow, none0 = rgba(BLUE, 22 * a), rgba(BLUE, 0)
    local gx = w / 2 - SK
    dxDrawPrimitive("trianglestrip", false, { cx - gx, y, none0 }, { cx, y, glow }, { cx - gx, y + h, none0 }, { cx, y + h, glow })
    dxDrawPrimitive("trianglestrip", false, { cx, y, glow }, { cx + gx, y, none0 }, { cx, y + h, glow }, { cx + gx, y + h, none0 })
    -- Línea de luz en el borde de abajo
    local half = (w / 2 - SK) * 0.9
    local solid, none = rgba(BLUE, 200 * a), rgba(BLUE, 0)
    dxDrawPrimitive("trianglestrip", false, { cx - half, y + h - 2, none }, { cx, y + h - 2, solid }, { cx - half, y + h, none }, { cx, y + h, solid })
    dxDrawPrimitive("trianglestrip", false, { cx, y + h - 2, solid }, { cx + half, y + h - 2, none }, { cx, y + h, solid }, { cx + half, y + h, none })
    -- Brillo que cruza la tarjeta (al subir de nivel)
    if shimmer then
        local bx = x - px(40) + (w + px(80)) * shimmer
        local bw, sk = px(26), px(22)
        local function cl(v) return clamp(v, x + SK, x + w - SK) end
        local c0, c1 = tocolor(255, 255, 255, 0), tocolor(255, 230, 170, 60 * a)
        dxDrawPrimitive("trianglestrip", false, { cl(bx + sk), y, c0 }, { cl(bx + sk + bw), y, c1 }, { cl(bx), y + h, c0 }, { cl(bx + bw), y + h, c1 })
    end
end

local function drawBar(x, y, w, frac, gainFrom, color, a, whiteK)
    DX.roundRect(x, y, w, BAR_H, BAR_H / 2, tocolor(255, 255, 255, 22 * a), false)
    frac = clamp(frac, 0, 1)
    if frac <= 0 then return end
    -- Parte de antes (color) y parte ganada (blanca que se tiñe al terminar)
    local base = clamp(math.min(gainFrom, frac), 0, 1)
    DX.roundRect(x, y, w * frac, BAR_H, BAR_H / 2, rgba(mix(color, { 255, 255, 255 }, whiteK), 245 * a), false)
    if base > 0 then DX.roundRect(x, y, w * base, BAR_H, BAR_H / 2, rgba(color, 245 * a), false) end
    -- Cabeza brillante en el borde del relleno
    local hx = x + w * frac
    DX.circle(hx - BAR_H / 2, y + BAR_H / 2, BAR_H * 0.95, rgba({ 255, 255, 255 }, 60 * a * whiteK), false)
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
    -- Con el HUD suprimido la animación se pausa (su tiempo no corre)
    if getElementData(localPlayer, "rp:hudHidden") then anim.t0 = anim.t0 + dt; return end

    local t = now - anim.t0
    local up = anim.levelUp
    local tFill = T.IN - 100
    local tFlash = tFill + T.FILL
    local tRefill = tFlash + (up and T.FLASH or 0)
    local tHold = tRefill + (up and T.REFILL or 0)
    local tOut = tHold + anim.hold
    local tEnd = tOut + T.OUT

    -- Entrada (con rebote) y salida
    local slide = t < T.IN and easeOutBack(t / T.IN) or (t > tOut and 1 - easeOut((t - tOut) / T.OUT) or 1)
    local a = clamp(t < T.IN and t / 200 or slide, 0, 1)
    local x = screenW / 2 - CW / 2
    local y = TOP - (1 - slide) * (CH + TOP + px(10))

    -- Fase: progreso mostrado, nivel mostrado, color y números
    local fillK = easeInOut((t - tFill) / T.FILL)
    local level, frac, gainFrom, color, cur, need = anim.fromLevel, 0, anim.fromFrac, BLUE, 0, anim.fromNeed
    local whiteK = 1 - easeOut((t - tFlash) / 500)        -- lo ganado se ve blanco y luego se tiñe
    local gold = 0
    if not up then
        level, need = anim.toLevel, anim.need
        frac = anim.fromFrac + (anim.toFrac - anim.fromFrac) * fillK
        cur = frac * need
    elseif t < tFlash then
        frac = anim.fromFrac + (1 - anim.fromFrac) * fillK
        cur = frac * need
    elseif t < tRefill then
        frac, gainFrom, cur = 1, 1, need
        gold = 1
    else
        local rk = easeOut((t - tRefill) / T.REFILL)
        level, need = anim.toLevel, anim.need
        frac, gainFrom = anim.toFrac * rk, 0
        cur = frac * need
        gold = 1 - easeOut((t - tRefill) / 600)
        whiteK = 0
    end
    color = mix(BLUE, GOLD, gold)

    -- Sonidos: ticks que suben de tono mientras se llena, y el cierre
    if t >= tFill and t < tFlash and now - anim.lastTick > 70 then
        anim.lastTick = now
        play("tick_001.ogg", 0.22, 0.9 + 0.7 * fillK)
    end
    if t >= tFlash and not anim.filled then
        anim.filled = true
        if up then
            play("levelup.ogg", 0.75)
        else
            play("confirmation_001.ogg", 0.35)
        end
    end

    drawCard(x, y, a, (up and t >= tFlash and t < tFlash + 900) and easeOut((t - tFlash) / 900) or nil)

    -- Insignia: fondo, aro de progreso, número (con salto al cambiar)
    local bx, by = x + SK + px(14) + BR, y + CH / 2
    DX.circle(bx, by, BR + px(2), tocolor(DARK[1], DARK[2], DARK[3], 255 * a), false)
    DX.circle(bx, by, BR - px(3), rgba(color, (40 + 90 * gold) * a), false)
    DX.ring(bx, by, BR, px(3), 0, 360, tocolor(255, 255, 255, 28 * a), false)
    DX.ring(bx, by, BR, px(3), -90, -90 + 360 * clamp(frac, 0, 1), rgba(color, 255 * a), false)
    local numScale, numA = 1, 1
    if up and t >= tFlash and t < tRefill then
        local k = (t - tFlash) / T.FLASH
        if k < 0.35 then numScale, numA = 1 - 0.6 * easeOut(k / 0.35), 1 - k / 0.35   -- el viejo se encoge
        else level = anim.toLevel; numScale = easeOutBack((k - 0.35) / 0.4) end         -- el nuevo salta
    end
    dxDrawText(tostring(level), bx, by, bx, by, rgba({ 255, 255, 255 }, 255 * a * numA), numScale, F_NUM, "center", "center")

    -- Destello y onda desde la insignia al subir de nivel
    if up and t >= tFlash and t < tFlash + 700 then
        local e = easeOut((t - tFlash) / 700)
        DX.ring(bx, by, BR * (1 + 1.8 * e), px(3) * (1 - e) + 1, 0, 360, rgba(GOLD, 230 * (1 - e) * a), false)
        DX.circle(bx, by, BR * (1 + 0.3 * e), tocolor(255, 255, 255, 120 * (1 - e) * a), false)
        if not anim.sparked then anim.sparked = true; burst(bx, by) end
    end

    -- Texto y barra
    local tx = bx + BR + px(16)
    local right = x + CW - SK - px(22)
    local bw = right - tx
    local ty = y + px(9)
    local labelCol = up and t >= tFlash and rgba(GOLD, 255 * a) or tocolor(160, 168, 184, 255 * a)
    dxDrawText(up and t >= tFlash and "¡SUBES DE NIVEL!" or ("NIVEL " .. level), tx, ty, 0, 0, labelCol, 1, F_LABEL, "left", "top")
    local shown = anim.gained * easeOut((t - tFill) / T.FILL)
    local gainPop = 1 + 0.18 * (1 - easeOut((t - tFlash) / 300)) * (t >= tFlash and 1 or 0)
    dxDrawText(("+%s XP"):format(fmt(shown)), right, ty - px(3), right, ty - px(3), rgba(mix({ 255, 255, 255 }, color, 0.35), 255 * a),
        gainPop, F_GAIN, "right", "top")
    local barY = y + px(30)
    drawBar(tx, barY, bw, frac, gainFrom, color, a, whiteK)
    local info
    if need <= 0 then info = "Nivel máximo"
    else info = ("%s / %s XP"):format(fmt(cur), fmt(need)) end
    dxDrawText(info, tx, barY + BAR_H + px(5), 0, 0, tocolor(150, 158, 174, 235 * a), 1, F_SMALL, "left", "top")
    if need > 0 then
        dxDrawText(("faltan %s para el %d"):format(fmt(need - cur), level + 1), right, barY + BAR_H + px(5), right, 0,
            tocolor(120, 128, 144, 235 * a), 1, F_SMALL, "right", "top")
    end

    -- Anuncio central de rp_notify, un instante después del destello
    if up and not anim.popped and t >= tFlash + 250 then
        anim.popped = true
        local sub
        if anim.need <= 0 then
            sub = "Alcanzaste el nivel máximo. ¡Enhorabuena!"
        else
            sub = ("Subiste de nivel. Te faltan %s XP para el nivel %d."):format(fmt(anim.need - anim.cur), anim.toLevel + 1)
        end
        exports.rp_notify:popup(("¡Nivel %d!"):format(anim.toLevel), sub, "level", 5000)
    end

    drawSparks(now, dt)
    if t >= tEnd then startNext() end
end)

----------------------------------------------------------------
-- /probarnivel: simula una subida de nivel solo en tu pantalla (no da XP)
----------------------------------------------------------------
addCommandHandler("probarnivel", function()
    if anim then return end
    local saved = { level = known.level, frac = known.frac }
    local lv = (known.level or 1)
    known.level, known.frac = lv, 0.7
    local need = needOf(lv + 1)
    queue[#queue + 1] = { level = lv + 1, cur = math.floor(need * 0.15), need = need, gained = math.floor(needOf(lv) * 0.45),
        levelUp = true, restore = saved }
    startNext()
end)
