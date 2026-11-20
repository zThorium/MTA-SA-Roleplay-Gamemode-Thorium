--[[
    rp_robbery / c_cinematic.lua
    Cinematica mientras se vacia la caja registradora: franjas negras, cuatro
    planos que van cambiando (manos en la caja, contrapicado a la cara, plano
    general desde la esquina y sobre el hombro hacia el cajero), cada uno con
    un acercamiento lento. Abajo el contador del botin sube fardo a fardo.
    Las camaras se acercan si chocan con una pared (processLineOfSight).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))

addEvent("rp:robbery:lootStart", true)
addEvent("rp:robbery:bundle", true)
-- lootEnd y stop los declara c_robbery.lua (se carga antes)

local cine   -- { start, duration, reg = {x,y,z}, clerk, bundles, count, total, pops = {}, shot }

local function lerp(a, b, t) return a + (b - a) * t end
local function ease(t) return t * t * (3 - 2 * t) end

local function formatMoney(n)
    local digits = tostring(math.floor(math.abs(n)))
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return "$" .. digits
end

-- Si hay una pared entre el objetivo y la camara, la camara se pone delante
local function clamp(tx, ty, tz, cx, cy, cz)
    local hit, hx, hy, hz = processLineOfSight(tx, ty, tz, cx, cy, cz, true, false, false, true, false, true, false, false, localPlayer)
    if hit then
        local dx, dy, dz = tx - hx, ty - hy, tz - hz
        local len = math.max(0.001, math.sqrt(dx * dx + dy * dy + dz * dz))
        return hx + dx / len * 0.25, hy + dy / len * 0.25, hz + dz / len * 0.25
    end
    return cx, cy, cz
end

-- Planos: from/to de la camara y del punto al que mira, en funcion del jugador y la caja
local function buildShots()
    local px, py, pz = getElementPosition(localPlayer)
    local rx, ry, rz = cine.reg[1], cine.reg[2], cine.reg[3]
    local dx, dy = rx - px, ry - py
    local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    dx, dy = dx / len, dy / len
    local nx, ny = -dy, dx
    local head = pz + 0.65
    local cx, cy, cz = rx + dx * 0.9, ry + dy * 0.9, pz + 0.6
    if isElement(cine.clerk) and not isPedDead(cine.clerk) then
        cx, cy, cz = getElementPosition(cine.clerk)
        cz = cz + 0.6
    end
    return {
        -- 1. manos en la caja, desde un lado y arriba
        { from = { rx + nx * 1.3 + dx * 0.2, ry + ny * 1.3 + dy * 0.2, rz + 0.9 }, to = { rx + nx * 0.8, ry + ny * 0.8, rz + 0.55 },
          look = { rx, ry, rz + 0.05 }, fov = { 60, 42 }, roll = { -4, 2 } },
        -- 2. contrapicado a la cara del ladron
        { from = { px + dx * 1.0 - nx * 0.7, py + dy * 1.0 - ny * 0.7, pz - 0.45 }, to = { px + dx * 0.7 - nx * 0.45, py + dy * 0.7 - ny * 0.45, pz - 0.35 },
          look = { px, py, head }, fov = { 62, 48 }, roll = { 6, 0 } },
        -- 3. plano general desde la esquina
        { from = { px - dx * 3.4 + nx * 2.6, py - dy * 3.4 + ny * 2.6, pz + 2.3 }, to = { px - dx * 2.6 + nx * 2.0, py - dy * 2.6 + ny * 2.0, pz + 1.9 },
          look = { (px + rx) / 2, (py + ry) / 2, pz + 0.2 }, fov = { 72, 64 }, roll = { 0, 0 } },
        -- 4. sobre el hombro, hacia el cajero
        { from = { px - dx * 1.1 + nx * 0.5, py - dy * 1.1 + ny * 0.5, pz + 0.8 }, to = { px - dx * 0.75 + nx * 0.42, py - dy * 0.75 + ny * 0.42, pz + 0.75 },
          look = { cx, cy, cz }, fov = { 55, 40 }, roll = { 0, -3 } },
    }
end

local function stopCine()
    if not cine then return end
    cine = nil
    RC.cinematic = false
    setCameraTarget(localPlayer)
end

addEventHandler("rp:robbery:lootStart", resourceRoot, function(reg, clerk, duration, bundles)
    cine = { start = getTickCount(), duration = duration, reg = reg, clerk = clerk, bundles = bundles,
        count = 0, total = 0, shown = 0, pops = {} }
    cine.shots = buildShots()
    RC.cinematic = true
    setCameraInterior(getElementInterior(localPlayer))
end)

addEventHandler("rp:robbery:bundle", resourceRoot, function(i, amount, total)
    if not cine then return end
    cine.count, cine.total = i, total
    cine.pops[#cine.pops + 1] = { text = "+" .. formatMoney(amount), at = getTickCount() }
    playSoundFrontEnd(1)
end)

addEventHandler("rp:robbery:lootEnd", resourceRoot, function()
    if not cine then return end
    -- un momento con el total en pantalla y vuelve la camara
    cine.ending = getTickCount()
    setTimer(stopCine, 900, 1)
end)

addEventHandler("rp:robbery:stop", resourceRoot, stopCine)
addEventHandler("onClientPlayerWasted", localPlayer, stopCine)
addEventHandler("onClientResourceStop", resourceRoot, function() if cine then setCameraTarget(localPlayer) end end)

addEventHandler("onClientPreRender", root, function()
    if not cine then return end
    local now = getTickCount()
    local t = math.min(1, (now - cine.start) / cine.duration)
    local n = #cine.shots
    local idx = math.min(n, math.floor(t * n) + 1)
    local local_t = ease((t * n) - (idx - 1))
    local shot = cine.shots[idx]
    cine.shot = idx
    local fx = lerp(shot.from[1], shot.to[1], local_t)
    local fy = lerp(shot.from[2], shot.to[2], local_t)
    local fz = lerp(shot.from[3], shot.to[3], local_t)
    local lx, ly, lz = shot.look[1], shot.look[2], shot.look[3]
    fx, fy, fz = clamp(lx, ly, lz, fx, fy, fz)
    -- temblor leve de camara en mano
    local shake = 0.012
    fx = fx + math.sin(now / 170) * shake
    fz = fz + math.cos(now / 230) * shake
    setCameraMatrix(fx, fy, fz, lx, ly, lz, lerp(shot.roll[1], shot.roll[2], local_t), lerp(shot.fov[1], shot.fov[2], local_t))
end)

addEventHandler("onClientRender", root, function()
    if not cine then return end
    local now = getTickCount()
    local barH = math.min(1, (now - cine.start) / 400) * screenH * 0.11
    dxDrawRectangle(0, 0, screenW, barH, tocolor(0, 0, 0, 255))
    dxDrawRectangle(0, screenH - barH, screenW, barH, tocolor(0, 0, 0, 255))

    -- corte entre planos: destello corto
    local t = (now - cine.start) / cine.duration
    local n = #cine.shots
    local phase = (t * n) % 1
    if t < 1 and t * n > 1 and phase < 0.05 then
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(255, 255, 255, 90 * (1 - phase / 0.05)))
    end

    -- contador del botin (sube suave hacia el total)
    cine.shown = cine.shown + (cine.total - cine.shown) * 0.2
    local text = formatMoney(cine.shown + 0.5)
    local y = screenH - barH + (barH - 60 * s) / 2
    dxDrawText("BOTIN", 0, y - 4 * s, screenW, 0, tocolor(154, 163, 178), 0.9 * s, "default-bold", "center", "top")
    dxDrawText(text, 3, y + 12 * s + 3, screenW + 3, 0, tocolor(0, 0, 0, 220), 2.6 * s, "pricedown", "center", "top")
    dxDrawText(text, 0, y + 12 * s, screenW, 0, tocolor(76, 211, 138), 2.6 * s, "pricedown", "center", "top")

    -- fardos: un rectangulo por fardo, se pintan al cogerlos
    local bw, bh, gap = 22 * s, 12 * s, 6 * s
    local total = cine.bundles * bw + (cine.bundles - 1) * gap
    local bx = screenW - total - 40 * s
    local by = screenH - barH / 2 - bh / 2
    for i = 1, cine.bundles do
        local x = bx + (i - 1) * (bw + gap)
        local got = i <= cine.count
        dxDrawRectangle(x, by, bw, bh, got and tocolor(76, 160, 100) or tocolor(255, 255, 255, 30))
        if got then dxDrawRectangle(x + bw / 2 - 2 * s, by, 4 * s, bh, tocolor(230, 220, 170)) end
    end

    -- "+$320" que suben y se desvanecen
    for i = #cine.pops, 1, -1 do
        local p = cine.pops[i]
        local k = (now - p.at) / 1200
        if k >= 1 then
            table.remove(cine.pops, i)
        else
            local py = screenH * 0.62 - k * 90 * s
            dxDrawText(p.text, 2, py + 2, screenW + 2, 0, tocolor(0, 0, 0, 200 * (1 - k)), 1.8 * s, "pricedown", "center", "top")
            dxDrawText(p.text, 0, py, screenW, 0, tocolor(140, 240, 170, 255 * (1 - k)), 1.8 * s, "pricedown", "center", "top")
        end
    end
end)
