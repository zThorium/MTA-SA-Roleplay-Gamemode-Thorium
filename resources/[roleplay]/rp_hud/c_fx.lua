--[[
    rp_hud / c_fx.lua
    Estado compartido del HUD y efectos (se carga antes que c_hud, c_wanted y c_tutorial,
    que comparten estas variables globales porque son el mismo recurso):
      - Hud: preferencias, rectangulos de cada parte en pantalla (para el tutorial),
        valores de demostracion y estado de la estamina.
      - Sonidos del HUD (Kenney CC0 + propios), con enfriamiento para no sonar en rafaga.
      - Textos flotantes ("+25", "+$500") que suben y se desvanecen.
      - Vineta de pantalla: roja con la vida baja (con latido) o al recibir dano,
        ambar cuando el hambre o la sed estan a 0.
]]

local screenW, screenH = guiGetScreenSize()

Hud = {
    -- /hud necesidades | mapa | velocimetro | sonidos (se guardan en @hud_prefs.xml)
    prefs = { needs = true, map = true, speedo = true, sounds = true },
    rects = {},            -- [nombre] = { x, y, w, h } de lo que se dibujo en el ultimo frame
    demo = nil,            -- { key = "hunger", t0 = tick }: el tutorial anima esa necesidad
    showAll = false,       -- el tutorial obliga a ver estamina y cordura aunque esten llenas
    staminaLocked = false, -- sin aliento (c_hud)
    starsY = nil,          -- donde van las estrellas de busqueda (c_wanted)
    topRightBottom = nil,  -- fin del bloque de arriba a la derecha (export getTopRightBottom)
}

function Hud.setRect(name, x, y, w, h)
    local r = Hud.rects[name]
    if not r then r = {}; Hud.rects[name] = r end
    r[1], r[2], r[3], r[4], r.t = x, y, w, h, getTickCount()
end

-- Rectangulo dibujado hace poco (si esa parte dejo de dibujarse, no cuenta)
function Hud.getRect(name)
    local r = Hud.rects[name]
    if r and getTickCount() - r.t < 500 then return r end
    return nil
end

----------------------------------------------------------------
-- Sonidos
----------------------------------------------------------------
local SOUNDS = {
    step = { "pluck_001.ogg", 0.55 },          -- paso nuevo del tutorial
    done = { "confirmation_003.ogg", 0.6 },    -- tutorial terminado
    recover = { "confirmation_002.ogg", 0.45 },-- una necesidad sube (comer, beber, dormir)
    critical = { "error_004.ogg", 0.5 },       -- una necesidad entra en rojo
    tip = { "glass_001.ogg", 0.55 },           -- consejo de primera vez
    spend = { "drop_002.ogg", 0.45 },          -- pagas
    earn = { "coins.wav", 0.5 },               -- cobras
    heartbeat = { "heartbeat.wav", 0.7 },      -- vida baja
}
local lastPlayed = {}

-- cooldown en ms: el mismo sonido no se repite antes de ese tiempo
function Hud.sound(name, cooldown)
    if not Hud.prefs.sounds then return end
    local def = SOUNDS[name]
    if not def then return end
    local now = getTickCount()
    if lastPlayed[name] and now - lastPlayed[name] < (cooldown or 250) then return end
    lastPlayed[name] = now
    local snd = playSound("sounds/" .. def[1])
    if snd then setSoundVolume(snd, def[2]) end
end

----------------------------------------------------------------
-- Textos flotantes
----------------------------------------------------------------
local floats = {}

function Hud.float(text, x, y, r, g, b, scale, font)
    floats[#floats + 1] = { text = text, x = x, y = y, r = r, g = g, b = b, t0 = getTickCount(),
        scale = scale or 1, font = font or "default-bold" }
    if #floats > 12 then table.remove(floats, 1) end
end

local FLOAT_MS = 1400
function Hud.drawFloats()
    local now = getTickCount()
    for i = #floats, 1, -1 do
        local f = floats[i]
        local k = (now - f.t0) / FLOAT_MS
        if k >= 1 then
            table.remove(floats, i)
        else
            local rise = (1 - (1 - k) ^ 3) * 34
            local a = k < 0.15 and k / 0.15 or (1 - (k - 0.15) / 0.85)
            local pop = k < 0.12 and (1 + 0.35 * (1 - k / 0.12)) or 1
            local y = f.y - rise
            local sc = f.scale * pop
            dxDrawText(f.text, f.x - 200 + 1, y + 1, f.x + 200 + 1, y + 1, tocolor(0, 0, 0, 220 * a), sc, f.font, "center", "center")
            dxDrawText(f.text, f.x - 200, y, f.x + 200, y, tocolor(f.r, f.g, f.b, 255 * a), sc, f.font, "center", "center")
        end
    end
end

----------------------------------------------------------------
-- Vineta (bordes de la pantalla teñidos)
----------------------------------------------------------------
local vignetteTex
local function getVignette()
    if vignetteTex then return vignetteTex end
    local N = 128
    local tex = dxCreateTexture(N, N, "argb", "clamp")
    if not tex then return nil end
    local px = dxGetTexturePixels(tex)
    for y = 0, N - 1 do
        for x = 0, N - 1 do
            local dx, dy = (x + 0.5) / N * 2 - 1, (y + 0.5) / N * 2 - 1
            local d = math.sqrt(dx * dx * 0.85 + dy * dy * 1.0)
            local k = math.max(0, math.min(1, (d - 0.55) / 0.6))
            k = k * k * (3 - 2 * k)
            dxSetPixelColor(px, x, y, 255, 255, 255, math.floor(255 * k))
        end
    end
    dxSetTexturePixels(tex, px)
    vignetteTex = tex
    return tex
end

local hitFlash = 0          -- 0..1, sube al recibir dano y se apaga sola
local healFlash = 0
local lastBeat = 0

function Hud.onDamage(amount)
    hitFlash = math.min(1, hitFlash + 0.35 + math.min(0.5, (amount or 0) / 40))
end
function Hud.onHeal() healFlash = 1 end

local function drawTint(r, g, b, a)
    if a <= 1 then return end
    local tex = getVignette()
    if tex then dxDrawImage(0, 0, screenW, screenH, tex, 0, 0, 0, tocolor(r, g, b, math.min(255, a))) end
end

-- Se llama desde el render de c_hud (solo con el HUD activo)
function Hud.drawVignette(health, starving)
    local now = getTickCount()
    local downed = getElementData(localPlayer, "rp:downed")
    -- vida baja: el borde late con el corazon (mas rapido cuanto menos vida)
    if health > 0 and health <= 25 and not downed and not isPedDead(localPlayer) then
        local period = 650 + health * 22
        local ph = ((now - lastBeat) % period) / period
        if now - lastBeat >= period then
            lastBeat = now
            Hud.sound("heartbeat", 400)
        end
        local beat = math.max(0, 1 - ph * 3.2) + 0.6 * math.max(0, 1 - math.abs(ph - 0.37) * 6)
        drawTint(190, 20, 25, 90 + 110 * math.min(1, beat))
    elseif starving then
        drawTint(230, 130, 30, 55 + 35 * (math.sin(now / 420) * 0.5 + 0.5))
    end
    if hitFlash > 0.01 then
        drawTint(220, 25, 30, 230 * hitFlash)
        hitFlash = hitFlash * 0.92
    end
    if healFlash > 0.01 then
        drawTint(80, 230, 120, 120 * healFlash)
        healFlash = healFlash * 0.93
    end
end

addEventHandler("onClientPlayerDamage", localPlayer, function(_, _, _, loss)
    Hud.onDamage(loss)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    getVignette()   -- se crea al arrancar, nunca en mitad de un frame
end)
