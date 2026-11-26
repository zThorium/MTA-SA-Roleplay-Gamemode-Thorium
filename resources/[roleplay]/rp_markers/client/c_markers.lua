--[[
    rp_markers / c_markers.lua  (cliente)

    Sustituye el cilindro nativo de GTA por un marcador moderno dibujado en 3D:
      - aro de suelo que respira y aro segmentado que gira
      - dos ondas de pulso que se expanden (más rápidas si estás dentro)
      - haz de luz vertical que se apaga cuando la cámara está encima
      - partículas que suben en espiral
      - insignia flotante con icono (aparece al acercarte con un "pop") y texto debajo

    El marcador original sigue existiendo (colisión, onMarkerHit...); solo se le pone
    alfa 0 en ESTE cliente. Al parar el recurso se le devuelve su color.
]]

local screenW, screenH = guiGetScreenSize()

local tex = {}              -- texturas base
local iconTex = {}          -- [nombre] = textura (carga perezosa)
local tracked = {}          -- [marker] = { r, g, b, a, size, style, seed, inside, iconA, x, y, z }
local visible = {}          -- marcadores a dibujar (se recalcula en cada escaneo)
local hidden = false        -- cinemática: no se dibuja nada
local demoMarkers = nil
local scanTimer = nil
local lastFrame = getTickCount()
local labelFont = "default-bold"

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

local function getIconTexture(name)
    if not name then return nil end
    if iconTex[name] == nil then
        iconTex[name] = dxCreateTexture("images/icons/" .. name .. ".png", "argb", true, "clamp") or false
    end
    return iconTex[name] or nil
end

local function styleOf(marker)
    return getElementData(marker, MARKERS.ELEMENT_DATA)
end

local function isHudSuppressed()
    local res = getResourceFromName("rp_hud")
    if res and getResourceState(res) == "running" then
        return exports.rp_hud:isHudSuppressed() and true or false
    end
    return false
end

local function restore(marker, data)
    if isElement(marker) then setMarkerColor(marker, data.r, data.g, data.b, data.a) end
end

----------------------------------------------------------------
-- Escaneo (unas veces por segundo, no cada frame)
----------------------------------------------------------------
local function scan()
    hidden = isHudSuppressed()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local maxDist = MARKERS.DRAW_DIST
    local list = {}

    for _, m in ipairs(getElementsByType("marker", root, true)) do
        local data = tracked[m]
        local style = styleOf(m)
        local native = type(style) == "table" and style.native

        if native or not MARKERS.TYPES[getMarkerType(m)] then
            if data then restore(m, data); tracked[m] = nil end
        else
            local r, g, b, a = getMarkerColor(m)
            if not data then
                -- alfa 0 de origen = zona invisible a propósito: no se dibuja
                if a > 0 then
                    data = { seed = math.random() * 10, inside = false, iconA = 0 }
                    tracked[m] = data
                end
            end
            if data then
                if a > 0 then
                    -- nuevo, o el servidor le cambió el color: guardar y volver a ocultar
                    data.r, data.g, data.b, data.a = r, g, b, a
                    setMarkerColor(m, r, g, b, 0)
                end
                data.size = getMarkerSize(m)
                data.style = type(style) == "table" and style or nil

                if getElementDimension(m) == dim and getElementInterior(m) == int then
                    local x, y, z = getElementPosition(m)
                    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= maxDist then
                        data.inside = isElementWithinMarker(localPlayer, m)
                        list[#list + 1] = m
                    end
                end
            end
        end
    end
    visible = list
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
-- Quad horizontal (mirando hacia arriba) centrado en x,y,z y girado rotDeg
local function drawFlat(texture, x, y, z, radius, rotDeg, color)
    local a = math.rad(rotDeg)
    local dx, dy = math.sin(a) * radius, math.cos(a) * radius
    dxDrawMaterialLine3D(x - dx, y - dy, z, x + dx, y + dy, z, texture, radius * 2, color, x, y, z + 10)
end

-- Billboard (mira a la cámara) centrado en x,y,z
local function drawBillboard(texture, x, y, z, size, color)
    local h = size / 2
    dxDrawMaterialLine3D(x, y, z + h, x, y, z - h, texture, size, color)
end

local function drawMarker(m, data, t, dt, cx, cy, cz, px, py, pz)
    local x, y, z = getElementPosition(m)
    local style = data.style
    local r, g, b = data.r, data.g, data.b
    local fixed = style and (style.color or MARKERS.PALETTE[MARKERS.ICON_CATEGORY[style.icon or ""] or ""])
    if fixed then r, g, b = fixed[1], fixed[2], fixed[3] end

    local camDist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
    local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
    local fade = clamp01((MARKERS.DRAW_DIST - camDist) / 15)
    if fade <= 0 then return end

    local R = data.size * MARKERS.RADIUS_SCALE
    local seed = data.seed
    local inside = data.inside
    local boost = inside and 1.25 or 1
    local gz = z + 0.03

    -- Suelo: aro que respira + aro segmentado girando
    drawFlat(tex.ring, x, y, gz, R * (1 + 0.03 * math.sin(t * 2.2 + seed)), 0,
        tocolor(r, g, b, math.min(255, 215 * fade * boost)))
    drawFlat(tex.dash, x, y, gz + 0.01, R, (t * (inside and 90 or 35) + seed * 57) % 360,
        tocolor(r, g, b, 200 * fade))

    -- Ondas de pulso
    local speed = inside and 1.1 or 0.55
    for k = 0, 1 do
        local p = (t * speed + k * 0.5 + seed) % 1
        drawFlat(tex.ring, x, y, gz + 0.005, R * (0.95 + p * 0.6), 0,
            tocolor(r, g, b, (1 - p) * (1 - p) * 170 * fade))
    end

    -- Haz de luz (se apaga si la cámara está casi encima, para no tapar la vista)
    local H = MARKERS.BEAM_HEIGHT
    if not (style and style.beam == false) then
        local beamA = (75 + 20 * math.sin(t * 3 + seed)) * fade * clamp01((camDist - 1.5) / 4) * boost
        if beamA > 1 then
            dxDrawMaterialLine3D(x, y, z + H, x, y, z, tex.beam, R * 1.7, tocolor(r, g, b, beamA))
        end
    end

    -- Partículas en espiral
    if camDist <= MARKERS.PARTICLE_DIST then
        local n = MARKERS.PARTICLES
        local pFade = fade * clamp01((MARKERS.PARTICLE_DIST - camDist) / 8)
        for i = 1, n do
            local ph = (t * 0.32 + i / n + seed) % 1
            local ang = i * 2.39996 + t * 0.9
            local rr = R * 0.75 * (0.35 + 0.65 * ((i * 0.618) % 1))
            local s = 0.075 * (1 - ph * 0.5)
            drawBillboard(tex.glow, x + math.cos(ang) * rr, y + math.sin(ang) * rr, z + 0.1 + ph * H * 0.9, s * 2,
                tocolor(r, g, b, math.sin(ph * math.pi) * 230 * pFade))
        end
    end

    -- Insignia con icono: aparece con un "pop" al acercarse
    local icon = style and getIconTexture(style.icon)
    local target = (icon and dist <= MARKERS.ICON_DIST) and 1 or 0
    data.iconA = data.iconA + (target - data.iconA) * math.min(1, dt * 6)
    if icon and data.iconA > 0.01 then
        local a = data.iconA
        local pop = 1 + 0.25 * math.sin(a * math.pi)              -- se pasa un poco y vuelve
        local s = MARKERS.ICON_SIZE * (0.55 + 0.45 * a) * pop
        local ix, iy = x, y
        local iz = z + MARKERS.ICON_HEIGHT + 0.08 * math.sin(t * 1.6 + seed)
        -- Capas separadas 1 cm hacia la cámara para que no parpadeen entre sí
        local vx, vy, vz = cx - ix, cy - iy, cz - iz
        local len = math.sqrt(vx * vx + vy * vy + vz * vz)
        if len > 0.01 then vx, vy, vz = vx / len * 0.012, vy / len * 0.012, vz / len * 0.012 end
        local alpha = 255 * a * fade

        drawBillboard(tex.glow, ix - vx, iy - vy, iz - vz, s * 2.1,
            tocolor(r, g, b, alpha * (0.35 + 0.15 * math.sin(t * 2.5)) * boost))
        drawBillboard(tex.badge_bg, ix, iy, iz, s, tocolor(255, 255, 255, alpha))
        drawBillboard(tex.badge_ring, ix + vx, iy + vy, iz + vz, s, tocolor(r, g, b, alpha))
        drawBillboard(icon, ix + vx * 2, iy + vy * 2, iz + vz * 2, s * 0.56, tocolor(255, 255, 255, alpha))

        -- Texto bajo la insignia
        local label = style.label
        if label and dist <= MARKERS.LABEL_DIST then
            local la = alpha * clamp01((MARKERS.LABEL_DIST - dist) / 2)
            local sx, sy = getScreenFromWorldPosition(ix, iy, iz - s * 0.62, 0.05)
            if sx and la > 4 then
                local scale = 1.05
                local w = dxGetTextWidth(label, scale, labelFont) + 18
                local h = dxGetFontHeight(scale, labelFont) + 6
                local bx, by = sx - w / 2, sy
                dxDrawRectangle(bx, by, w, h, tocolor(12, 14, 20, la * 0.78))
                dxDrawRectangle(bx, by + h - 2, w, 2, tocolor(r, g, b, la))
                dxDrawText(label, bx, by, bx + w, by + h - 2, tocolor(255, 255, 255, la), scale, labelFont,
                    "center", "center")
            end
        end
    end
end

local function render()
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastFrame) / 1000)
    lastFrame = now
    if hidden or #visible == 0 then return end

    local t = now / 1000
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    for _, m in ipairs(visible) do
        local data = tracked[m]
        if data and isElement(m) then
            drawMarker(m, data, t, dt, cx, cy, cz, px, py, pz)
        end
    end
end

----------------------------------------------------------------
-- API de cliente (marcadores creados en el cliente)
----------------------------------------------------------------
--- Igual que el export de servidor pero sin sincronizar: para marcadores creados en el cliente.
--- Se guarda en el propio marcador, así sobrevive a un reinicio de rp_markers.
function setMarkerStyle(marker, style)
    if not isElement(marker) or getElementType(marker) ~= "marker" then return false end
    local clean = MARKERS.sanitizeStyle(style)
    if clean then
        setElementData(marker, MARKERS.ELEMENT_DATA, clean, false)
    else
        removeElementData(marker, MARKERS.ELEMENT_DATA)
    end
    return true
end

function getMarkerIcons()
    return MARKERS.ICONS
end

----------------------------------------------------------------
-- /markerdemo (lo autoriza el servidor): todos los iconos en círculo alrededor
----------------------------------------------------------------
local DEMO_COLORS = {
    { 255, 170, 40 }, { 60, 200, 255 }, { 120, 230, 120 }, { 255, 80, 90 }, { 190, 120, 255 }, { 255, 255, 255 },
}

addEvent("rp:markers:demo", true)
addEventHandler("rp:markers:demo", resourceRoot, function()
    if demoMarkers then
        for _, m in ipairs(demoMarkers) do if isElement(m) then destroyElement(m) end end
        demoMarkers = nil
        outputChatBox("[rp_markers] Demo retirada.", 200, 200, 200)
        return
    end
    demoMarkers = {}
    local px, py, pz = getElementPosition(localPlayer)
    local icons = MARKERS.ICONS
    for i, name in ipairs(icons) do
        local ang = (i - 1) / #icons * math.pi * 2
        local ring = (i % 2 == 0) and 9 or 6
        local c = DEMO_COLORS[(i - 1) % #DEMO_COLORS + 1]
        local m = createMarker(px + math.cos(ang) * ring, py + math.sin(ang) * ring, pz - 1, "cylinder", 1.5,
            c[1], c[2], c[3], 150)
        if m then
            setElementDimension(m, getElementDimension(localPlayer))
            setElementInterior(m, getElementInterior(localPlayer))
            setMarkerStyle(m, { icon = name, label = name })
            demoMarkers[#demoMarkers + 1] = m
        end
    end
    outputChatBox("[rp_markers] Demo: " .. #icons .. " iconos alrededor. /markerdemo otra vez para quitarla.", 200, 200, 200)
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, name in ipairs({ "ring", "dash", "beam", "glow", "badge_bg", "badge_ring" }) do
        tex[name] = dxCreateTexture("images/" .. name .. ".png", "argb", true, "clamp")
    end
    scan()
    scanTimer = setTimer(scan, MARKERS.SCAN_MS, 0)
    addEventHandler("onClientRender", root, render)
end)

addEventHandler("onClientElementDestroy", root, function()
    if tracked[source] then tracked[source] = nil end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(scanTimer) then killTimer(scanTimer) end
    -- Devolver el cilindro nativo a todos los marcadores que se ocultaron
    for m, data in pairs(tracked) do restore(m, data) end
    tracked, visible = {}, {}
end)
