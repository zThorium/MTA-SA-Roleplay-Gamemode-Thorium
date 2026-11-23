--[[
    rp_levels / c_levels.lua

    Barra de RP animada en la parte superior central, al estilo GTA Online
    (dibujada con dx, sin assets externos):
      1. Baja desde el borde superior: circulo con tu nivel, barra de XP y
         circulo con el siguiente nivel.
      2. La barra se llena con el XP ganado (+N XP).
      3. Si subes de nivel: la barra se completa, destella, los circulos pasan
         al nuevo nivel y aparece el aviso grande "NIVEL N".
      4. Se esconde de nuevo. Varios avisos seguidos se encolan.
    El servidor manda rp:levels:update (nivel, xp del nivel, xp necesario, ganado, subio).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.4, screenH / 900))

local T = {                     -- tiempos en ms
    SLIDE = 350, FILL = 900, FLASH = 450, REFILL = 700,
    HOLD = 2400, HOLD_QUEUED = 900, BANNER = 3600,
}
local SOUND_LEVELUP = "sounds/levelup.ogg"   -- Kenney Digital Audio (CC0); alternativa: sounds/levelup_alt.ogg (agregar a meta.xml)
local SOUND_GAIN = nil          -- nil = sin sonido al ganar XP

local COL = {
    blue = { 93, 182, 229 }, dark = { 0, 0, 0 }, white = { 255, 255, 255 }, gold = { 240, 200, 80 },
}
local function col(c, a) return tocolor(c[1], c[2], c[3], math.max(0, math.min(255, a))) end

local W, H = math.floor(460 * s), math.floor(46 * s)
local R = math.floor(27 * s)                -- radio de los circulos
local TOP = math.floor(24 * s)
local BAR_W = W - 2 * R * 2 - math.floor(16 * s)

local known = { level = nil, frac = 0 }     -- ultimo estado conocido (para animar desde ahi)
local queue = {}
local anim = nil                            -- animacion en curso

local function ease(t) t = math.max(0, math.min(1, t)); return 1 - (1 - t) ^ 3 end
local function easeBack(t)
    t = math.max(0, math.min(1, t))
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function startNext()
    local ev = table.remove(queue, 1)
    if not ev then anim = nil; return end
    local fromLevel = known.level or ev.level
    local fromFrac = known.frac
    local toFrac = ev.need > 0 and ev.cur / ev.need or 1
    anim = {
        t0 = getTickCount(), gained = ev.gained, levelUp = ev.levelUp and ev.level > fromLevel,
        fromLevel = fromLevel, toLevel = ev.level, fromFrac = fromFrac, toFrac = toFrac,
        hold = (#queue > 0) and T.HOLD_QUEUED or T.HOLD,
    }
    if anim.levelUp then local snd = playSound(SOUND_LEVELUP); if snd then setSoundVolume(snd, 0.8) end elseif SOUND_GAIN then playSoundFrontEnd(SOUND_GAIN) end
    known.level, known.frac = ev.level, toFrac
end

addEvent("rp:levels:update", true)
addEventHandler("rp:levels:update", resourceRoot, function(level, cur, need, gained, levelUp)
    level, cur, need, gained = tonumber(level), tonumber(cur), tonumber(need), tonumber(gained) or 0
    if not level or not cur or not need then return end
    if gained <= 0 then                       -- sincronizacion silenciosa (al entrar al juego)
        known.level, known.frac = level, need > 0 and cur / need or 1
        return
    end
    queue[#queue + 1] = { level = level, cur = cur, need = need, gained = gained, levelUp = levelUp }
    if not anim then startNext() end
end)

local function drawCircle(cx, cy, r, c, a, number, scale)
    dxDrawCircle(cx, cy, r + 2 * s, 0, 360, col(c, a * 0.9), col(c, a * 0.9), 48)
    dxDrawCircle(cx, cy, r, 0, 360, col(COL.dark, a * 0.75), col(COL.dark, a * 0.75), 48)
    dxDrawText(tostring(number), cx - r, cy - r, cx + r, cy + r, col(COL.white, a), scale, "default-bold", "center", "center")
end

local function drawBar(x, y, frac, a, flash)
    dxDrawRectangle(x, y, BAR_W, H * 0.34, col(COL.dark, a * 0.7))
    local w = math.max(0, math.min(1, frac)) * BAR_W
    -- segmentos de 10 (como la barra del juego): se dibuja la barra y se marcan los cortes
    dxDrawRectangle(x, y, w, H * 0.34, col(COL.blue, a))
    for i = 1, 9 do dxDrawRectangle(x + BAR_W * i / 10 - 1, y, 2, H * 0.34, col(COL.dark, a * 0.55)) end
    if flash > 0 then dxDrawRectangle(x, y, BAR_W, H * 0.34, col(COL.white, a * flash)) end
end

addEventHandler("onClientRender", root, function()
    if not anim then return end
    local t = getTickCount() - anim.t0

    local tFill = T.SLIDE
    local tFlash = tFill + T.FILL
    local tRefill = tFlash + (anim.levelUp and T.FLASH or 0)
    local tHold = tRefill + (anim.levelUp and T.REFILL or 0)
    local tOut = tHold + anim.hold
    local tEnd = tOut + T.SLIDE

    -- posicion vertical (entra / sale) y opacidad
    local slide = 1
    if t < T.SLIDE then slide = ease(t / T.SLIDE) elseif t > tOut then slide = 1 - ease((t - tOut) / T.SLIDE) end
    local a = 255 * slide
    local cy = TOP + R - (1 - slide) * (R * 2 + TOP)
    local cx0 = screenW / 2 - W / 2
    local leftCx, rightCx = cx0 + R, cx0 + W - R
    local barX, barY = cx0 + 2 * R + math.floor(8 * s), cy - H * 0.17

    -- fraccion y niveles mostrados segun la fase
    local lvlL, frac, flash = anim.fromLevel, anim.fromFrac, 0
    if not anim.levelUp then
        frac = anim.fromFrac + (anim.toFrac - anim.fromFrac) * ease((t - tFill) / T.FILL)
        lvlL = anim.toLevel
    else
        if t < tFlash then
            frac = anim.fromFrac + (1 - anim.fromFrac) * ease((t - tFill) / T.FILL)
        elseif t < tRefill then
            frac, flash = 1, 1 - ((t - tFlash) / T.FLASH)
        else
            lvlL = anim.toLevel
            frac = anim.toFrac * ease((t - tRefill) / T.REFILL)
        end
    end

    dxDrawRectangle(barX - 6 * s, cy - H * 0.5, BAR_W + 12 * s, H, col(COL.dark, a * 0.35))
    drawBar(barX, barY, frac, a, flash)
    local numScale = 1.25 * s
    local pulse = (anim.levelUp and t >= tFlash and t < tRefill) and (1 + 0.25 * flash) or 1
    drawCircle(leftCx, cy, R, COL.blue, a, lvlL, numScale * pulse)
    drawCircle(rightCx, cy, R, COL.white, a * 0.85, math.min(lvlL + 1, 9999), numScale * 0.9)

    -- "+N XP" sobre la barra
    if t < tHold + anim.hold then
        dxDrawText(("+%d XP"):format(anim.gained), barX, cy - H * 0.95, barX + BAR_W, cy - H * 0.2,
            col(COL.white, a), 0.9 * s, "default-bold", "center", "bottom")
    end

    -- Aviso grande de subida de nivel
    if anim.levelUp and t >= tRefill then
        local bt = t - tRefill
        local scale = easeBack(bt / 450)
        local ba = 255
        if bt > T.BANNER - 400 then ba = 255 * (1 - (bt - (T.BANNER - 400)) / 400) end
        if bt < T.BANNER then
            local cyB = TOP + H + 70 * s
            local sc = scale * s
            dxDrawText("SUBES DE NIVEL", 0, cyB - 40 * s, screenW, cyB, col(COL.gold, ba), 1.0 * sc, "default-bold", "center", "bottom")
            dxDrawText(tostring(anim.toLevel), 0, cyB, screenW, cyB + 90 * s, col(COL.white, ba), 4.2 * sc, "default-bold", "center", "top")
        end
    end

    local bannerEnd = anim.levelUp and (tRefill + T.BANNER) or 0
    if t >= math.max(tEnd, bannerEnd) then startNext() end
end)
