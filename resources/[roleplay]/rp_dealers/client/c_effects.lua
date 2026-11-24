--[[
    rp_dealers / c_effects.lua
    Efectos visuales de las drogas (solo en el cliente del que las toma).

      weed    : relajado. Tinte verdoso, imagen borrosa, el mundo va un poco mas lento.
      cocaine : acelerado. Todo va mas rapido, destellos blancos, resistencia infinita al correr.
      lsd     : alucinaciones. Imagen que ondula por franjas, fantasma que pulsa, colores y cielo que cambian.

    Los efectos se pueden combinar. Cada uno entra y sale con una rampa de unos segundos.
    El servidor manda rp:drugs:start (tipo, ms), rp:drugs:stop y rp:drugs:overdose.
]]

addEvent("rp:drugs:start", true)
addEvent("rp:drugs:stop", true)
addEvent("rp:drugs:overdose", true)

local screenW, screenH = guiGetScreenSize()
local RAMP_IN, RAMP_OUT = 4000, 8000

local active = {}          -- [kind] = { start = tick, finish = tick }
local saved = nil          -- { blur, stamina } para restaurar
local source_ = nil        -- dxCreateScreenSource (solo LSD)
local STAMINA_STAT = 22

local function ramp(e, now)
    if now >= e.finish then return 0 end
    local i = math.min(1, (now - e.start) / RAMP_IN, (e.finish - now) / RAMP_OUT)
    return math.max(0, i)
end

local function hsv(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    local r, g, b
    if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
    return r * 255, g * 255, b * 255
end

local function restore()
    setGameSpeed(1)
    if saved then
        setBlurLevel(saved.blur)
        setPedStat(localPlayer, STAMINA_STAT, saved.stamina)
        saved = nil
    end
    resetSkyGradient()
    if isElement(source_) then destroyElement(source_) source_ = nil end
end

local function stopAll()
    active = {}
    restore()
end

local function onRender()
    local now = getTickCount()
    local any = false
    local speed, blur = 1, saved and saved.blur or 36

    for kind, e in pairs(active) do
        if now >= e.finish then
            active[kind] = nil
        else
            any = true
            local i = ramp(e, now)
            local t = now / 1000

            if kind == "weed" then
                speed = speed * (1 - 0.15 * i)
                blur = math.max(blur, 36) + 40 * i
                dxDrawRectangle(0, 0, screenW, screenH, tocolor(60, 170, 70, 45 * i), true)
                -- parpados pesados: viñeta oscura arriba y abajo que respira
                local lid = (0.06 + 0.03 * math.sin(t * 1.3)) * screenH * i
                dxDrawRectangle(0, 0, screenW, lid, tocolor(0, 0, 0, 150 * i), true)
                dxDrawRectangle(0, screenH - lid, screenW, lid, tocolor(0, 0, 0, 150 * i), true)

            elseif kind == "cocaine" then
                speed = speed * (1 + 0.2 * i)
                setPedStat(localPlayer, STAMINA_STAT, 1000)
                local pulse = (0.5 + 0.5 * math.sin(t * 9)) * i
                dxDrawRectangle(0, 0, screenW, screenH, tocolor(255, 255, 255, 28 * pulse), true)
                -- vision de tunel
                local edge = 0.12 * screenW * i
                dxDrawRectangle(0, 0, edge, screenH, tocolor(0, 0, 0, 120 * i), true)
                dxDrawRectangle(screenW - edge, 0, edge, screenH, tocolor(0, 0, 0, 120 * i), true)

            elseif kind == "lsd" then
                blur = blur + 20 * i
                if not isElement(source_) then source_ = dxCreateScreenSource(screenW, screenH) end
                if isElement(source_) then
                    dxUpdateScreenSource(source_)
                    -- imagen por franjas que ondula
                    local step, amp = 18, 26 * i
                    for y = 0, screenH - 1, step do
                        local dx = math.sin(t * 2.2 + y * 0.018) * amp
                        dxDrawImageSection(dx, y, screenW, step, source_, 0, y, screenW, step, 0, 0, 0, tocolor(255, 255, 255, 255), true)
                    end
                    -- fantasma que pulsa (zoom)
                    local z = 1 + 0.05 * math.sin(t * 1.7) * i
                    local w, h = screenW * z, screenH * z
                    dxDrawImage((screenW - w) / 2, (screenH - h) / 2, w, h, source_, 0, 0, 0, tocolor(255, 255, 255, 70 * i), true)
                end
                -- color que recorre todo el espectro
                local r, g, b = hsv((t * 0.12) % 1, 0.9, 1)
                dxDrawRectangle(0, 0, screenW, screenH, tocolor(r, g, b, 60 * i), true)
                local r2, g2, b2 = hsv((t * 0.12 + 0.5) % 1, 0.9, 1)
                setSkyGradient(r, g, b, r2, g2, b2)
            end
        end
    end

    if not any then
        if saved then restore() end
        removeEventHandler("onClientRender", root, onRender)
        return
    end
    setGameSpeed(speed)
    setBlurLevel(math.min(255, blur))
end

local function start(kind, ms)
    ms = tonumber(ms)
    if not ms or ms <= 0 or ms > 600000 then return end
    local now = getTickCount()
    local wasEmpty = next(active) == nil
    -- una dosis nueva de la misma droga alarga el efecto
    local cur = active[kind]
    local from = (cur and now < cur.finish) and cur.finish or now
    active[kind] = { start = cur and cur.start or now, finish = from + ms }
    if wasEmpty then
        saved = { blur = getBlurLevel(), stamina = getPedStat(localPlayer, STAMINA_STAT) }
        addEventHandler("onClientRender", root, onRender)
    end
end

addEventHandler("rp:drugs:start", resourceRoot, start)
addEventHandler("rp:drugs:stop", resourceRoot, function()
    local was = next(active) ~= nil
    stopAll()
    if was then removeEventHandler("onClientRender", root, onRender) end
end)

-- Sobredosis: se va la luz unos segundos
addEventHandler("rp:drugs:overdose", resourceRoot, function()
    local was = next(active) ~= nil
    stopAll()
    if was then removeEventHandler("onClientRender", root, onRender) end
    fadeCamera(false, 0.6)
    setTimer(fadeCamera, 3500, 1, true, 2)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    local was = next(active) ~= nil
    stopAll()
    if was then removeEventHandler("onClientRender", root, onRender) end
end)
addEventHandler("onClientResourceStop", resourceRoot, function() stopAll() end)
