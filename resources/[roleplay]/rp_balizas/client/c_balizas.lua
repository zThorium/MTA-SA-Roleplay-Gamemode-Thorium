--[[
    rp_balizas / c_balizas.lua

    Con la sirena encendida dibuja, por cada vehiculo de emergencia:
      - coronas en la baliza (izquierda/derecha alternadas),
      - una luz dinamica real por lado,
      - destellos de color proyectados sobre paredes y piso: lanza rayos desde cada
        lado de la baliza y pega un parche de luz sobre la superficie que golpea,
        orientado con su normal (como los "shadows" del mod EmergencyLight).
]]

local C = BALIZAS
local glowTex
local cache = {}   -- [veh] = { t = tick, hits = { {x,y,z,nx,ny,nz,dist,side}, ... } }
local lights = {}  -- [veh] = { L = light, R = light }

local function makeGlow()
    local size = 64
    local tex = dxCreateTexture(size, size, "argb", "clamp")
    local px = dxGetTexturePixels(tex)
    local half = size / 2
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local d = math.sqrt((x - half + 0.5) ^ 2 + (y - half + 0.5) ^ 2) / half
            local a = d >= 1 and 0 or (1 - d) ^ 2
            dxSetPixelColor(px, x, y, 255, 255, 255, math.floor(a * 255))
        end
    end
    dxSetTexturePixels(tex, px)
    return tex
end

local function pattern(side, now)
    local p = C.PATTERN[side]
    local slot = math.floor(now / 50) % #p
    if p[slot + 1] ~= 1 then return 0 end
    return 1 - (now % 50) / 50 * 0.35
end

local function offsetPos(veh, ox, oy, oz)
    local m = getElementMatrix(veh)
    return ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1],
           ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2],
           ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
end

local function emitterPos(veh, cfg, side)
    return offsetPos(veh, side == "R" and cfg.x or -cfg.x, cfg.y, cfg.z)
end

-- Rayos desde cada lado de la baliza; guarda los impactos para dibujarlos cada frame.
local function castRays(veh, cfg)
    local hits = {}
    local _, _, rz = getElementRotation(veh)
    for _, side in ipairs({ "L", "R" }) do
        local ox, oy, oz = emitterPos(veh, cfg, side)
        for i = 0, C.YAWS - 1 do
            local yaw = math.rad(rz + i * 360 / C.YAWS)
            for _, pitch in ipairs(C.PITCHES) do
                local p = math.rad(pitch)
                local dx, dy, dz = math.cos(p) * math.sin(yaw), math.cos(p) * math.cos(yaw), math.sin(p)
                local ex, ey, ez = ox + dx * C.RAY_RANGE, oy + dy * C.RAY_RANGE, oz + dz * C.RAY_RANGE
                local hit, hx, hy, hz, _, nx, ny, nz = processLineOfSight(ox, oy, oz, ex, ey, ez,
                    true, true, false, true, false, false, false, false, veh)
                if hit then
                    local d = getDistanceBetweenPoints3D(ox, oy, oz, hx, hy, hz)
                    hits[#hits + 1] = { hx, hy, hz, nx, ny, nz, d, side }
                end
            end
        end
    end
    return hits
end

local function cross(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function norm(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return 0, 0, 1 end
    return x / l, y / l, z / l
end

-- Parche de luz pegado a la superficie (quad orientado por la normal); crece con la distancia.
local function drawPatch(h, color)
    local nx, ny, nz = h[4], h[5], h[6]
    local ax, ay, az = 0, 0, 1
    if math.abs(nz) > 0.9 then ax, ay, az = 1, 0, 0 end
    local t1x, t1y, t1z = norm(cross(nx, ny, nz, ax, ay, az))
    local t2x, t2y, t2z = cross(nx, ny, nz, t1x, t1y, t1z)
    local s = 0.9 + h[7] * 0.38
    local px, py, pz = h[1] + nx * 0.04, h[2] + ny * 0.04, h[3] + nz * 0.04
    dxDrawMaterialPrimitive3D("trianglestrip", glowTex, false,
        { px - t1x * s - t2x * s, py - t1y * s - t2y * s, pz - t1z * s - t2z * s, color, 0, 0 },
        { px + t1x * s - t2x * s, py + t1y * s - t2y * s, pz + t1z * s - t2z * s, color, 1, 0 },
        { px - t1x * s + t2x * s, py - t1y * s + t2y * s, pz - t1z * s + t2z * s, color, 0, 1 },
        { px + t1x * s + t2x * s, py + t1y * s + t2y * s, pz + t1z * s + t2z * s, color, 1, 1 })
end

local function destroyLights(veh)
    local l = lights[veh]
    if not l then return end
    for _, light in pairs(l) do if isElement(light) then destroyElement(light) end end
    lights[veh] = nil
end

local function isActive(veh)
    return C.MODELS[getElementModel(veh)] and getVehicleSirensOn(veh) and getElementHealth(veh) > 250
end

addEventHandler("onClientPreRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    local now = getTickCount()
    local near = {}
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        if isActive(veh) then
            local vx, vy, vz = getElementPosition(veh)
            local d = getDistanceBetweenPoints3D(cx, cy, cz, vx, vy, vz)
            if d <= C.MAX_DIST then near[#near + 1] = { veh = veh, d = d } end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)

    local seen = {}
    for idx, e in ipairs(near) do
        local veh, cfg = e.veh, C.MODELS[getElementModel(e.veh)]
        seen[veh] = true
        local fl = { L = pattern("L", now), R = pattern("R", now) }
        local cols = { L = cfg.cL, R = cfg.cR }

        -- coronas (3 sprites por lado, como corona.number del mod)
        for _, side in ipairs({ "L", "R" }) do
            if fl[side] > 0 then
                local c = cols[side]
                local size = C.CORONA_SIZE * (1 + e.d / 120)
                local sx0 = side == "R" and cfg.x or -cfg.x
                for _, off in ipairs({ -0.2, 0, 0.2 }) do
                    local sx, sy, sz = offsetPos(veh, sx0 + off, cfg.y, cfg.z)
                    dxDrawMaterialLine3D(sx, sy, sz + size / 2, sx, sy, sz - size / 2, glowTex, size,
                        tocolor(c[1], c[2], c[3], math.floor(255 * fl[side])), cx, cy, cz)
                end
            end
        end

        -- luz dinamica real
        if idx <= C.MAX_LIGHTS then
            lights[veh] = lights[veh] or {}
            for _, side in ipairs({ "L", "R" }) do
                local ox, oy, oz = emitterPos(veh, cfg, side)
                local c, f = cols[side], fl[side]
                local l = lights[veh][side]
                if not isElement(l) then
                    l = createLight(0, ox, oy, oz, C.LIGHT_RADIUS, 0, 0, 0)
                    lights[veh][side] = l
                end
                if l then
                    setElementPosition(l, ox, oy, oz + 0.3)
                    setLightColor(l, c[1] * f, c[2] * f, c[3] * f)
                end
            end
        else
            destroyLights(veh)
        end

        -- reflejo en paredes y piso
        if idx <= C.MAX_SURFACE and e.d <= C.SURFACE_DIST then
            local ch = cache[veh]
            if not ch or now - ch.t >= C.RAY_REFRESH then
                ch = { t = now, hits = castRays(veh, cfg) }
                cache[veh] = ch
            end
            local fade = 1 - e.d / C.SURFACE_DIST
            for _, h in ipairs(ch.hits) do
                local f = fl[h[8]]
                if f > 0 then
                    local k = (1 - h[7] / C.RAY_RANGE) ^ 1.5
                    local a = math.floor(C.SURFACE_ALPHA * f * k * fade)
                    if a > 4 then
                        local c = cols[h[8]]
                        drawPatch(h, tocolor(c[1], c[2], c[3], a))
                    end
                end
            end
        else
            cache[veh] = nil
        end
    end

    for veh in pairs(lights) do if not seen[veh] then destroyLights(veh) end end
    for veh in pairs(cache) do if not seen[veh] then cache[veh] = nil end end
end)

addEventHandler("onClientElementDestroy", root, function()
    if getElementType(source) == "vehicle" then destroyLights(source) cache[source] = nil end
end)

addEventHandler("onClientResourceStart", resourceRoot, function() glowTex = makeGlow() end)
