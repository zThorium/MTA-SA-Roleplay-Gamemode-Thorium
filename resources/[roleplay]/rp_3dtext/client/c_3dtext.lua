--[[
    rp_3dtext / c_3dtext.lua  (cliente)

    Cada texto 3D es un objeto del icono de info (modelo 1239) con el elementData "rp:text3d".
    Aqui se le da vida:
      - el icono gira y flota, con el shader fx/icon.fx (dorado, siempre brillante, pulso,
        reflejo que lo recorre y borde luminoso)
      - halo, columna de luz, anillo en el suelo y chispas que suben (fx/glow.fx, aditivo)
      - al acercarte aparece una tarjeta con el texto, centrada sobre el icono, con un sonido
    Solo se procesan los iconos cargados (streamed in), que ya estan en tu interior/dimension.
]]

local icons = {}      -- [obj] = { x, y, z, gz, phase, acc, show, near }  (solo los cargados)
local bases = {}      -- [obj] = { x, y, z } posicion real (el cliente la mueve al flotar)
local sparks = {}     -- chispas vivas
local layouts = {}    -- [texto] = { lines = {...}, w, h }  medido a escala 1
local refreshTimer, lastTick
local iconShader, glowDisc, glowRing, glowBeam
local fontText, fontLabel

local LINE_H, PAD_X, PAD_Y, LABEL_H = 0, 14, 10, 0

----------------------------------------------------------------
-- Recursos graficos
----------------------------------------------------------------
local function setupGraphics()
    -- prioridad 1: manda sobre el shader general de rp_pickupfx en las mismas texturas (modelo 1239)
    iconShader = dxCreateShader("fx/icon.fx", 1, 0, false, "object")
    if not iconShader then
        outputDebugString("[rp_3dtext] Sin shader del icono (GPU sin shader model 3): se vera el original.", 2)
    end
    glowDisc = dxCreateShader("fx/glow.fx")
    glowRing = dxCreateShader("fx/glow.fx")
    glowBeam = dxCreateShader("fx/glow.fx")
    if glowRing then dxSetShaderValue(glowRing, "sMode", 1) end
    if glowBeam then dxSetShaderValue(glowBeam, "sMode", 2) end

    fontText = dxCreateFont("fonts/rubik_medium.ttf", 11, false, "cleartype") or "default-bold"
    fontLabel = dxCreateFont("fonts/kenney_future.ttf", 8, false, "cleartype") or "default-bold"
    LINE_H = dxGetFontHeight(1, fontText)
    LABEL_H = dxGetFontHeight(1, fontLabel) + 4
end

----------------------------------------------------------------
-- Lista de iconos cargados
----------------------------------------------------------------
local function refresh()
    local C = TEXT3D
    for _, o in ipairs(getElementsByType("object", root, true)) do
        if not icons[o] and getElementModel(o) == C.ICON_MODEL and getElementData(o, "rp:text3d") then
            if not bases[o] then
                local x, y, z = getElementPosition(o)
                bases[o] = { x = x, y = y, z = z }
            end
            local b = bases[o]
            setElementCollisionsEnabled(o, false)
            if iconShader then engineApplyShaderToWorldTexture(iconShader, "*", o) end
            icons[o] = { x = b.x, y = b.y, z = b.z, gz = b.z - 1.0, phase = math.random() * 6.28,
                acc = 0, show = 0, near = false }
        end
    end
    for o in pairs(icons) do
        if not isElement(o) or not isElementStreamedIn(o) then
            if isElement(o) and iconShader then engineRemoveShaderFromWorldTexture(iconShader, "*", o) end
            icons[o] = nil
        end
    end
    for o in pairs(bases) do
        if not isElement(o) then bases[o] = nil end
    end
end

----------------------------------------------------------------
-- Tarjeta de texto: lineas partidas a mano para centrarlas de verdad
----------------------------------------------------------------
local function layout(text)
    local cached = layouts[text]
    if cached then return cached end
    local maxW = TEXT3D.WRAP_WIDTH
    local lines, w = {}, 0
    local src = tostring(text):gsub("\\n", "\n")
    for para in (src .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if line ~= "" and dxGetTextWidth(try, 1, fontText) > maxW then
                lines[#lines + 1] = line
                line = word
            else
                line = try
            end
        end
        lines[#lines + 1] = line
    end
    for _, l in ipairs(lines) do w = math.max(w, dxGetTextWidth(l, 1, fontText)) end
    w = math.max(w, dxGetTextWidth("INFO", 1, fontLabel) + 22)
    cached = { lines = lines, w = w, h = #lines * LINE_H }
    layouts[text] = cached
    return cached
end

-- Rectangulo con esquinas recortadas (aspecto redondeado)
local function card(x, y, w, h, color)
    local r = 3
    dxDrawRectangle(x + r, y, w - r * 2, h, color)
    dxDrawRectangle(x, y + r, r, h - r * 2, color)
    dxDrawRectangle(x + w - r, y + r, r, h - r * 2, color)
end

local function drawCard(text, sx, sy, scale, alpha, rise)
    local L = layout(text)
    local w = (L.w + PAD_X * 2) * scale
    local h = (L.h + LABEL_H + PAD_Y * 2) * scale
    local x = sx - w / 2
    local y = sy - h - rise
    local g = TEXT3D.GOLD

    card(x, y, w, h, tocolor(10, 12, 18, 205 * alpha))
    dxDrawRectangle(x + 3, y, w - 6, 2 * scale, tocolor(g[1], g[2], g[3], 255 * alpha))
    -- etiqueta INFO con un punto dorado
    local ly = y + PAD_Y * scale
    local labelW = dxGetTextWidth("INFO", scale, fontLabel)
    local dot = 6 * scale
    local lx = sx - (labelW + dot + 6 * scale) / 2
    dxDrawRectangle(lx, ly + (LABEL_H * scale - 4 * scale) / 2 - dot / 2, dot, dot, tocolor(g[1], g[2], g[3], 255 * alpha))
    dxDrawText("INFO", lx + dot + 6 * scale, ly, 0, 0, tocolor(g[1], g[2], g[3], 255 * alpha), scale, fontLabel)
    -- lineas centradas
    local ty = ly + LABEL_H * scale
    for i, line in ipairs(L.lines) do
        local yy = ty + (i - 1) * LINE_H * scale
        dxDrawText(line, x + 1, yy + 1, x + w + 1, yy + LINE_H * scale + 1, tocolor(0, 0, 0, 160 * alpha), scale,
            fontText, "center", "top")
        dxDrawText(line, x, yy, x + w, yy + LINE_H * scale, tocolor(255, 255, 255, 255 * alpha), scale,
            fontText, "center", "top")
    end
end

----------------------------------------------------------------
-- Efectos
----------------------------------------------------------------
local function spawnSpark(ic)
    if #sparks >= TEXT3D.MAX_SPARKS then return end
    local life = 1.1 + math.random() * 0.9
    sparks[#sparks + 1] = {
        cx = ic.x, cy = ic.y, z = ic.gz + 0.05 + math.random() * 0.2,
        ang = math.random() * 6.28, rad = 0.2 + math.random() * 0.35,
        spin = (math.random() < 0.5 and -1 or 1) * (1 + math.random()),
        vz = 0.45 + math.random() * 0.5, age = 0, life = life,
        size = 0.05 + math.random() * 0.06,
    }
end

local function drawSparks(dt)
    local i = 1
    while i <= #sparks do
        local s = sparks[i]
        s.age = s.age + dt
        if s.age >= s.life then
            sparks[i] = sparks[#sparks]
            sparks[#sparks] = nil
        else
            s.ang = s.ang + s.spin * dt
            s.z = s.z + s.vz * dt
            s.rad = s.rad * (1 - 0.25 * dt)
            local x, y = s.cx + math.cos(s.ang) * s.rad, s.cy + math.sin(s.ang) * s.rad
            local a = math.sin(math.pi * s.age / s.life)
            if glowDisc then
                dxDrawMaterialLine3D(x, y, s.z + s.size, x, y, s.z - s.size, glowDisc, s.size * 2,
                    tocolor(255, 235, 170, 255 * a))
            end
            i = i + 1
        end
    end
end

local function drawIconFx(ic, iz, t, k)
    local g = TEXT3D.GOLD
    -- columna de luz del suelo al icono
    if glowBeam then
        dxDrawMaterialLine3D(ic.x, ic.y, ic.gz, ic.x, ic.y, iz + 0.45, glowBeam, 0.6, tocolor(g[1], g[2], g[3], 70 * k))
    end
    -- halo que respira
    if glowDisc then
        local s = 1.15 + 0.15 * math.sin(t * 3 + ic.phase)
        dxDrawMaterialLine3D(ic.x, ic.y, iz + s / 2, ic.x, ic.y, iz - s / 2, glowDisc, s, tocolor(g[1], g[2], g[3], 110 * k))
    end
    -- dos anillos en el suelo: uno fijo y una onda que se expande y se apaga
    if glowRing then
        local z = ic.gz + 0.03
        local r = 0.6
        dxDrawMaterialLine3D(ic.x - r, ic.y, z, ic.x + r, ic.y, z, glowRing, r * 2,
            tocolor(g[1], g[2], g[3], 150 * k), ic.x, ic.y, z + 1)
        local p = (t * 0.6 + ic.phase) % 1
        local rw = 0.4 + p * 0.9
        dxDrawMaterialLine3D(ic.x - rw, ic.y, z, ic.x + rw, ic.y, z, glowRing, rw * 2,
            tocolor(g[1], g[2], g[3], 140 * k * (1 - p)), ic.x, ic.y, z + 1)
    end
end

----------------------------------------------------------------
-- Fotograma
----------------------------------------------------------------
local function render()
    local C = TEXT3D
    local now = getTickCount()
    local dt = math.min((now - (lastTick or now)) / 1000, 0.1)
    lastTick = now
    local t = now / 1000
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)

    for o, ic in pairs(icons) do
        if isElement(o) then
            -- animacion del icono
            local iz = ic.z + math.sin(t * C.BOB_SPEED + ic.phase) * C.BOB_HEIGHT
            setElementPosition(o, ic.x, ic.y, iz, false)
            setElementRotation(o, 0, 0, (t * C.SPIN_DEG_S + ic.phase * 57) % 360)

            local camDist = getDistanceBetweenPoints3D(cx, cy, cz, ic.x, ic.y, ic.z)
            if camDist <= C.FX_DISTANCE then
                local k = math.min(1, (C.FX_DISTANCE - camDist) / 8)
                drawIconFx(ic, iz, t, k)
                ic.acc = ic.acc + dt * C.SPARKS_PER_S * k
                while ic.acc >= 1 do
                    ic.acc = ic.acc - 1
                    spawnSpark(ic)
                end
            end

            -- tarjeta de texto
            local dist = getDistanceBetweenPoints3D(px, py, pz, ic.x, ic.y, ic.z)
            local tz = ic.z + C.BOB_HEIGHT + C.TEXT_OFFSET_Z
            local want = dist <= C.DRAW_DISTANCE
                and isLineOfSightClear(cx, cy, cz, ic.x, ic.y, tz, true, false, false, true, false, false, false)
            if want and not ic.near then
                local snd = playSound3D("sounds/glass_001.ogg", ic.x, ic.y, ic.z)
                if snd then
                    setSoundVolume(snd, C.SOUND_VOLUME)
                    setSoundMaxDistance(snd, 15)
                    setElementInterior(snd, getElementInterior(localPlayer))
                    setElementDimension(snd, getElementDimension(localPlayer))
                end
            end
            ic.near = want and true or (ic.near and dist <= C.DRAW_DISTANCE + 1.5)
            ic.show = math.max(0, math.min(1, ic.show + (want and 4 or -4) * dt))

            if ic.show > 0 then
                local sx, sy = getScreenFromWorldPosition(ic.x, ic.y, tz, 0.05)
                if sx then
                    local fade = dist <= C.FADE_DISTANCE and 1
                        or math.max(0, 1 - (dist - C.FADE_DISTANCE) / (C.DRAW_DISTANCE - C.FADE_DISTANCE))
                    local ease = 1 - (1 - ic.show) ^ 3
                    local scale = math.max(0.8, math.min(1.15, 1.3 - dist * 0.07))
                    drawCard(getElementData(o, "rp:text3d"), sx, sy, scale, ease * fade, (1 - ease) * -12)
                end
            end
        end
    end

    drawSparks(dt)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setupGraphics()
    refresh()
    refreshTimer = setTimer(refresh, 1000, 0)
    addEventHandler("onClientRender", root, render)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(refreshTimer) then killTimer(refreshTimer) end
end)
