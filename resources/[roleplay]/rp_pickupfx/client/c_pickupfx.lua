--[[
    rp_pickupfx / c_pickupfx.lua  (cliente)

    Pickups del juego (casas, flecha, estrellas, camiseta, fajos...) con el mismo trato que el
    icono de rp_3dtext, sin tocar los recursos que los crean:
      - el pickup original del servidor se aparca, SOLO en este cliente, en HIDDEN_DIMENSION.
        La recogida no cambia: la decide el servidor con su posicion y dimension reales.
      - en su lugar se dibuja una copia del modelo (objeto local) algo mas pequena, que gira y
        flota (sube y baja), con el shader fx/pickup.fx aplicado solo a ella
      - columna de luz, halo con nucleo, anillo y onda en el suelo y chispas (fx/glow.fx)
    Los pickups creados por el propio cliente (fajos de rp_citizens) no se pueden aparcar sin romper
    su recogida: esos conservan el modelo nativo y solo llevan los brillos.

    Rendimiento:
      - la lista se revisa cada SCAN_MS, nunca por fotograma; el suelo se calcula una vez
      - copias solo hasta RELEASE_DISTANCE: mas lejos se devuelve el pickup original
      - animacion solo a menos de ANIM_DISTANCE; brillos de los MAX_FX mas cercanos a menos de
        FX_DISTANCE (6 quads cada uno); chispas con tope MAX_SPARKS
      - un shader por modelo, compartido por todas sus copias
    Un pickup con el elementData "rp:pickupUsed" (recogido, esperando reaparecer) se oculta.
]]

local entries = {}    -- [pickup] = { model, style, x, y, z, gz, int, dim, clone, isLocal, phase, acc, dist }
local active = {}     -- los que dibujan brillos este fotograma (reutilizada)
local sparks = {}
local shaders = {}    -- [modelo] = shader | false
local glowDisc, glowRing, glowBeam
local scanTimer, lastTick
local level, Q = 3, nil          -- nivel de calidad actual y su tabla (PICKUPFX.QUALITY)
local fpsFrames, fpsSince = 0, 0

----------------------------------------------------------------
-- Calidad: segun los ajustes de MTA del jugador y, si van bajos, segun los FPS reales
----------------------------------------------------------------
local function setLevel(n)
    level = math.max(1, math.min(#PICKUPFX.QUALITY, n))
    Q = PICKUPFX.QUALITY[level]
    -- chispas sobrantes fuera al bajar de nivel
    for i = #sparks, Q.maxSparks + 1, -1 do sparks[i] = nil end
end

local function initialLevel()
    local fx = (dxGetStatus() or {}).SettingFXQuality or 2
    if fx <= 0 then return 1 elseif fx == 1 then return 2 end
    return 3
end

local function watchFps(now)
    fpsFrames = fpsFrames + 1
    local elapsed = now - fpsSince
    if elapsed < PICKUPFX.FPS_WINDOW_MS then return end
    local fps = fpsFrames * 1000 / elapsed
    fpsFrames, fpsSince = 0, now
    -- relativo al tope de FPS del servidor: con fpslimit bajo no se confunde con un PC lento
    local limit = getFPSLimit() or 0
    local minFps = limit > 0 and math.min(PICKUPFX.MIN_FPS, limit * 0.75) or PICKUPFX.MIN_FPS
    if fps < minFps and level > 1 then
        setLevel(level - 1)
        outputDebugString(("[rp_pickupfx] %.0f FPS: calidad de efectos baja a %d"):format(fps, level), 3)
    end
end

----------------------------------------------------------------
-- Shader por modelo (se aplica a cada copia con "*" + elemento)
----------------------------------------------------------------
local function modelShader(model, style)
    if shaders[model] ~= nil then return shaders[model] end
    local sh = dxCreateShader("fx/pickup.fx", 0, 0, false, "object")
    if not sh then
        outputDebugString("[rp_pickupfx] Sin shader de pickups (GPU sin shader model 3): solo brillos.", 2)
        shaders[model] = false
        return false
    end
    local c = style.color
    dxSetShaderValue(sh, "sGlow", c[1] / 255, c[2] / 255, c[3] / 255)
    dxSetShaderValue(sh, "sBoost", style.boost or 1.3)
    dxSetShaderValue(sh, "sTint", style.tint or 0.35)
    shaders[model] = sh
    return sh
end

----------------------------------------------------------------
-- Copia animada
----------------------------------------------------------------
local function groundBelow(x, y, z)
    local hit, _, _, gz = processLineOfSight(x, y, z, x, y, z - 3, true, false, false, true, false, true)
    return hit and gz or (z - 1)
end

-- e.z = altura de la copia (la del pickup + zOffset del estilo); e.gz = suelo, desde la altura real
local function readPickup(e, p)
    local z
    e.x, e.y, z = getElementPosition(p)
    e.gz = groundBelow(e.x, e.y, z) + 0.03
    e.z = z + (e.style.zOffset or 0)
end

local function attachShader(e)
    if not isElement(e.clone) then return end
    local sh = modelShader(e.model, e.style)
    if sh then engineApplyShaderToWorldTexture(sh, "*", e.clone) end
end

local function placeClone(e)
    if not isElement(e.clone) then return end
    setElementPosition(e.clone, e.x, e.y, e.z)
    setElementInterior(e.clone, e.int)
    setElementDimension(e.clone, e.dim)
end

local function createClone(e)
    local C = PICKUPFX
    e.clone = createObject(e.model, e.x, e.y, e.z)
    if not e.clone then return end
    setElementCollisionsEnabled(e.clone, false)
    setObjectScale(e.clone, e.style.scale or C.CLONE_SCALE)
    if e.used then setElementAlpha(e.clone, 0) end
    placeClone(e)
    attachShader(e)
end

-- Devuelve el pickup original a su dimension real y quita la copia
local function release(p, e)
    if isElement(e.clone) then destroyElement(e.clone) end
    if not e.isLocal and isElement(p) and getElementDimension(p) == PICKUPFX.HIDDEN_DIMENSION then
        setElementDimension(p, e.dim)
    end
    entries[p] = nil
end

local function track(p, model, style)
    local e = { model = model, style = style, isLocal = isElementLocal(p),
        int = getElementInterior(p), dim = getElementDimension(p),
        phase = math.random() * 6.28, acc = 0, used = getElementData(p, "rp:pickupUsed", false) and true or false }
    readPickup(e, p)
    if not e.isLocal then
        setElementDimension(p, PICKUPFX.HIDDEN_DIMENSION)
        createClone(e)
    end
    entries[p] = e
end

----------------------------------------------------------------
-- Revision periodica
----------------------------------------------------------------
local function scan()
    local C = PICKUPFX
    local cx, cy, cz = getCameraMatrix()
    for _, p in ipairs(getElementsByType("pickup", root, true)) do
        if not entries[p] then
            local model = getElementModel(p)
            local style = C.STYLES[model]
            if style then
                local x, y, z = getElementPosition(p)
                -- TRACK_DISTANCE < RELEASE_DISTANCE: sin ir y venir entre original y copia en el borde
                if getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) <= C.TRACK_DISTANCE then track(p, model, style) end
            end
        end
    end

    for p, e in pairs(entries) do
        if not isElement(p) then
            release(p, e)
        elseif e.isLocal then
            if not isElementStreamedIn(p) then entries[p] = nil end
        else
            -- El servidor cambio la dimension (se la volvemos a aparcar), el modelo o la posicion
            local dim = getElementDimension(p)
            if dim ~= C.HIDDEN_DIMENSION then
                e.dim = dim
                e.int = getElementInterior(p)
                readPickup(e, p)
                setElementDimension(p, C.HIDDEN_DIMENSION)
                placeClone(e)
            end
            local model = getElementModel(p)
            if model ~= e.model then
                local style = C.STYLES[model]
                if not style then
                    release(p, e)
                else
                    local old = shaders[e.model]
                    if old and isElement(e.clone) then engineRemoveShaderFromWorldTexture(old, "*", e.clone) end
                    e.model, e.style = model, style
                    readPickup(e, p)   -- el nuevo estilo puede tener otro zOffset
                    if isElement(e.clone) then
                        setElementModel(e.clone, model)
                        setObjectScale(e.clone, style.scale or C.CLONE_SCALE)
                        placeClone(e)
                    end
                    attachShader(e)
                end
            end
            if entries[p] and getDistanceBetweenPoints3D(cx, cy, cz, e.x, e.y, e.z) > C.RELEASE_DISTANCE then
                release(p, e)
            end
        end
    end
end

----------------------------------------------------------------
-- Brillos
----------------------------------------------------------------
-- Estrella recogida / reaparecida: se cachea aqui para no leer elementData en cada fotograma
addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if key ~= "rp:pickupUsed" then return end
    local e = entries[source]
    if not e then return end
    e.used = new and true or false
    if isElement(e.clone) then setElementAlpha(e.clone, e.used and 0 or 255) end
end)

local function spawnSpark(e)
    if #sparks >= Q.maxSparks then return end
    local c = e.style.color
    sparks[#sparks + 1] = {
        cx = e.x, cy = e.y, z = e.gz + math.random() * 0.25,
        ang = math.random() * 6.28, rad = 0.2 + math.random() * 0.3,
        spin = (math.random() < 0.5 and -1 or 1) * (1 + math.random()),
        vz = 0.4 + math.random() * 0.45, age = 0, life = 1 + math.random() * 0.8,
        size = 0.04 + math.random() * 0.05,
        r = math.min(255, c[1] + 60), g = math.min(255, c[2] + 60), b = math.min(255, c[3] + 60),
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
            local x, y = s.cx + math.cos(s.ang) * s.rad, s.cy + math.sin(s.ang) * s.rad
            local a = math.sin(math.pi * s.age / s.life)
            dxDrawMaterialLine3D(x, y, s.z + s.size, x, y, s.z - s.size, glowDisc, s.size * 2,
                tocolor(s.r, s.g, s.b, 255 * a))
            i = i + 1
        end
    end
end

local function drawGlow(e, iz, t, k)
    local c = e.style.color
    local f = e.style.fxScale or 1   -- tamano de los brillos de este estilo (la estrella, mas grandes)
    -- columna de luz del suelo al pickup
    if Q.beam then
        dxDrawMaterialLine3D(e.x, e.y, e.gz, e.x, e.y, iz + 0.55 * f, glowBeam, 0.65 * f, tocolor(c[1], c[2], c[3], 75 * k))
    end
    -- halo que respira (en calidad baja, mas pequeno: menos pixeles que rellenar)
    local s = ((Q.core and 1.2 or 0.9) + 0.15 * math.sin(t * 3 + e.phase)) * f
    dxDrawMaterialLine3D(e.x, e.y, iz + s / 2, e.x, e.y, iz - s / 2, glowDisc, s, tocolor(c[1], c[2], c[3], 120 * k))
    if Q.core then
        dxDrawMaterialLine3D(e.x, e.y, iz + 0.26 * f, e.x, e.y, iz - 0.26 * f, glowDisc, 0.52 * f,
            tocolor(math.min(255, c[1] + 80), math.min(255, c[2] + 80), math.min(255, c[3] + 80), 100 * k))
    end
    -- anillo fijo y onda que se expande en el suelo
    local r = 0.55 * f
    dxDrawMaterialLine3D(e.x - r, e.y, e.gz, e.x + r, e.y, e.gz, glowRing, r * 2,
        tocolor(c[1], c[2], c[3], 130 * k), e.x, e.y, e.gz + 1)
    if not Q.wave then return end
    local p = (t * 0.6 + e.phase) % 1
    local rw = (0.35 + p * 0.8) * f
    dxDrawMaterialLine3D(e.x - rw, e.y, e.gz, e.x + rw, e.y, e.gz, glowRing, rw * 2,
        tocolor(c[1], c[2], c[3], 120 * k * (1 - p)), e.x, e.y, e.gz + 1)
end

----------------------------------------------------------------
-- Fotograma
----------------------------------------------------------------
local function byDistance(a, b) return a.dist < b.dist end

local function render()
    local C = PICKUPFX
    local now = getTickCount()
    local dt = math.min((now - (lastTick or now)) / 1000, 0.1)
    lastTick = now
    watchFps(now)
    local t = now / 1000
    local cx, cy, cz = getCameraMatrix()
    local myInt, myDim = getElementInterior(localPlayer), getElementDimension(localPlayer)

    local n = 0
    for _, e in pairs(entries) do
        if e.int == myInt and e.dim == myDim then
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, e.x, e.y, e.z)
            local used = e.used
            local iz = e.z
            if isElement(e.clone) then
                if not used and dist <= Q.animDistance then
                    -- mismo movimiento que el icono de rp_3dtext: gira y flota
                    iz = e.z + math.sin(t * C.BOB_SPEED + e.phase) * C.BOB_HEIGHT
                    setElementPosition(e.clone, e.x, e.y, iz, false)
                    setElementRotation(e.clone, 0, 0, (t * C.SPIN_DEG_S + e.phase * 57) % 360)
                end
            end
            if not used and dist <= (e.style.fxDistance or C.FX_DISTANCE) then
                e.dist, e.iz = dist, iz
                n = n + 1
                active[n] = e
            end
        end
    end
    for i = n + 1, #active do active[i] = nil end
    if n > Q.maxFx then table.sort(active, byDistance) end

    for i = 1, math.min(n, Q.maxFx) do
        local e = active[i]
        local k = math.min(1, ((e.style.fxDistance or C.FX_DISTANCE) - e.dist) / 6)
        drawGlow(e, e.iz, t, k)
        if Q.sparkRate > 0 and e.dist <= C.SPARK_DISTANCE and (e.style.sparks or 0) > 0 then
            e.acc = e.acc + dt * e.style.sparks * Q.sparkRate
            while e.acc >= 1 do
                e.acc = e.acc - 1
                spawnSpark(e)
            end
        end
    end

    drawSparks(dt)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    glowDisc = dxCreateShader("fx/glow.fx")
    glowRing = dxCreateShader("fx/glow.fx")
    glowBeam = dxCreateShader("fx/glow.fx")
    if not glowDisc or not glowRing or not glowBeam then
        return outputDebugString("[rp_pickupfx] No se pudo crear fx/glow.fx; sin efectos de pickups.", 2)
    end
    dxSetShaderValue(glowRing, "sMode", 1)
    dxSetShaderValue(glowBeam, "sMode", 2)
    setLevel(initialLevel())
    fpsSince = getTickCount()
    scan()
    scanTimer = setTimer(scan, PICKUPFX.SCAN_MS, 0)
    addEventHandler("onClientRender", root, render)
end)

-- Al parar: devolver todos los pickups originales a su dimension (las copias se destruyen solas)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(scanTimer) then killTimer(scanTimer) end
    for p, e in pairs(entries) do release(p, e) end
end)
