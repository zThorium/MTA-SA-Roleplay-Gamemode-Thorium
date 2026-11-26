--[[
    rp_levels / c_aura.lua
    Aura dorada al subir de nivel, como en los MMORPG. SOLO la ve el propio jugador:
    todo se dibuja en su cliente y no se sincroniza (los demás no ven nada, por rol).

        LevelAura.start()   -- lo llama c_levels.lua en el destello de subida de nivel

    Capas (unos 3,4 s en total, entra rápido y se desvanece):
      - El cuerpo brilla en dorado con borde luminoso: fx/aura.fx, shader EN CAPA que suma
        luz sin pisar el de rp_characters (altura y tono). También a lo pegado con
        bone_attach (cabeza de rp_heads, toys).
      - Columna de luz suave que sube desde los pies y halo detrás del cuerpo.
      - Dos anillos de luz que se abren por el suelo.
      - Destellos que suben girando alrededor del cuerpo.
      - Una luz dorada real que ilumina un poco alrededor.
    Las texturas de luz son SVG con degradados (sin imágenes).
]]

LevelAura = {}

local DURATION = 3400
local GOLD = { 255, 200, 90 }

local active = nil      -- efecto en curso
local tex = nil         -- texturas SVG (se crean la primera vez)
local shaders = nil     -- { ped = shader, object = shader } o false si la tarjeta no puede

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeIn(t) t = clamp(t, 0, 1); return t * t end

----------------------------------------------------------------
-- Texturas de luz (SVG: degradados ya suavizados)
----------------------------------------------------------------
local SVG = {
    glow = [[<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><defs>
        <radialGradient id="g" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="#ffffff" stop-opacity="1"/>
        <stop offset="0.3" stop-color="#fff0b8" stop-opacity="0.85"/>
        <stop offset="1" stop-color="#ffc040" stop-opacity="0"/></radialGradient></defs>
        <circle cx="32" cy="32" r="32" fill="url(#g)"/></svg>]],
    ring = [[<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><defs>
        <radialGradient id="g" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="#ffc040" stop-opacity="0"/>
        <stop offset="0.68" stop-color="#ffc040" stop-opacity="0"/>
        <stop offset="0.86" stop-color="#ffd36a" stop-opacity="1"/>
        <stop offset="0.92" stop-color="#fff3c4" stop-opacity="0.9"/>
        <stop offset="1" stop-color="#ffc040" stop-opacity="0"/></radialGradient></defs>
        <circle cx="128" cy="128" r="128" fill="url(#g)"/></svg>]],
    pillar = [[<svg xmlns="http://www.w3.org/2000/svg" width="64" height="256"><defs>
        <radialGradient id="g" cx="50%" cy="88%" r="50%">
        <stop offset="0" stop-color="#fff6d0" stop-opacity="0.9"/>
        <stop offset="0.45" stop-color="#ffcf5a" stop-opacity="0.5"/>
        <stop offset="1" stop-color="#ffb030" stop-opacity="0"/></radialGradient></defs>
        <rect width="64" height="256" fill="url(#g)"/></svg>]],
}

local function textures()
    if tex then return tex end
    tex = {}
    for name, data in pairs(SVG) do
        local w, h = data:match('width="(%d+)" height="(%d+)"')
        tex[name] = svgCreate(tonumber(w), tonumber(h), data) or nil
    end
    return tex
end

local function getShaders()
    if shaders ~= nil then return shaders end
    local ped = dxCreateShader("fx/aura.fx", 1, 0, true, "ped")
    local obj = dxCreateShader("fx/aura.fx", 1, 0, true, "object")
    if not ped then
        outputDebugString("[rp_levels] La tarjeta no admite el shader del aura: se verá sin el brillo del cuerpo", 3)
        shaders = false
        return false
    end
    shaders = { ped = ped, object = obj }
    return shaders
end

----------------------------------------------------------------
-- Posición de los pies (igual que rp_characters/c_body.lua)
----------------------------------------------------------------
local function feet()
    local x, y, z = getElementPosition(localPlayer)
    if not getPedOccupiedVehicle(localPlayer) then
        local base = getElementDistanceFromCentreOfMassToBaseOfModel(localPlayer)
        z = z - ((base and base > 0.2) and base or 1)
    else
        z = z - 0.5
    end
    return x, y, z
end

local function bodyScale()
    local res = getResourceFromName("rp_characters")
    if res and getResourceState(res) == "running" then
        local ok, s = pcall(function() return exports.rp_characters:getPedBodyScale(localPlayer) end)
        if ok and tonumber(s) then return tonumber(s) end
    end
    return 1
end

-- Objetos pegados al jugador con bone_attach (cabeza, toys) para que también brillen
local function attachedObjects()
    local list = {}
    local res = getResourceFromName("bone_attach")
    if not res or getResourceState(res) ~= "running" then return list end
    for _, obj in ipairs(getElementsByType("object", root, true)) do
        local ok, owner = pcall(function() return exports.bone_attach:getElementBoneAttachmentDetails(obj) end)
        if ok and owner == localPlayer then list[#list + 1] = obj end
    end
    return list
end

----------------------------------------------------------------
-- Inicio y fin
----------------------------------------------------------------
local function stop()
    if not active then return end
    local sh = active.shaders
    if sh then
        engineRemoveShaderFromWorldTexture(sh.ped, "*", localPlayer)
        if sh.object then
            for _, obj in ipairs(active.objects) do
                if isElement(obj) then engineRemoveShaderFromWorldTexture(sh.object, "*", obj) end
            end
        end
        dxSetShaderValue(sh.ped, "sStrength", 0)
    end
    if isElement(active.light) then destroyElement(active.light) end
    active = nil
end

function LevelAura.start()
    stop()
    textures()
    local x, y, z = feet()
    active = {
        t0 = getTickCount(), sparks = {}, lastSpawn = 0, objects = {},
        shaders = getShaders() or nil,
        light = createLight(0, x, y, z + 1, 6, GOLD[1], GOLD[2], GOLD[3]),
    }
    local sh = active.shaders
    if sh then
        local scale = bodyScale()
        for _, s in pairs(sh) do
            if s then dxSetShaderValue(s, "sScale", scale); dxSetShaderValue(s, "sPivot", x, y, z) end
        end
        engineApplyShaderToWorldTexture(sh.ped, "*", localPlayer)
        if sh.object then
            active.objects = attachedObjects()
            for _, obj in ipairs(active.objects) do engineApplyShaderToWorldTexture(sh.object, "*", obj) end
        end
    end
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function billboard(material, x, y, z, size, color)
    dxDrawMaterialLine3D(x, y, z - size / 2, x, y, z + size / 2, material, size, color)
end

addEventHandler("onClientPreRender", root, function(dtRaw)
    if not active then return end
    local now = getTickCount()
    local t = now - active.t0
    if t > DURATION or not isElement(localPlayer) then stop(); return end
    local dt = math.min(tonumber(dtRaw) or 16, 100)

    -- Envolvente: entra en 300 ms, late, y se apaga el último segundo
    local env = easeOut(t / 300) * (1 - easeIn((t - (DURATION - 1100)) / 1100))
    local pulse = 0.82 + 0.18 * math.sin(t / 85)
    local x, y, z = feet()

    -- Cuerpo dorado (shader en capa)
    local sh = active.shaders
    if sh then
        for _, s in pairs(sh) do
            if s then
                dxSetShaderValue(s, "sStrength", env * pulse)
                dxSetShaderValue(s, "sPivot", x, y, z)
            end
        end
    end

    -- Luz real que ilumina alrededor
    if isElement(active.light) then
        setElementPosition(active.light, x, y, z + 1.1)
        local k = env * pulse
        setLightColor(active.light, GOLD[1] * k, GOLD[2] * k, GOLD[3] * k)
    end

    local T = tex or {}
    -- Columna de luz y halo detrás del cuerpo
    if T.pillar then
        local h = 2.7 * (0.6 + 0.4 * easeOut(t / 500))
        dxDrawMaterialLine3D(x, y, z - 0.15, x, y, z + h, T.pillar, 1.7, tocolor(255, 255, 255, 200 * env * pulse))
    end
    if T.glow then
        billboard(T.glow, x, y, z + 1.0, 1.9, tocolor(255, 220, 140, 90 * env))
    end

    -- Anillos que se abren por el suelo
    if T.ring then
        for _, delay in ipairs({ 0, 280 }) do
            local e = (t - delay) / 1300
            if e > 0 and e < 1 then
                local r = 0.35 + 1.9 * easeOut(e)
                dxDrawMaterialLine3D(x, y - r, z + 0.04, x, y + r, z + 0.04, T.ring, r * 2,
                    tocolor(255, 255, 255, 255 * (1 - e)), x, y, z + 10)
            end
        end
    end

    -- Destellos que suben girando alrededor del cuerpo
    if T.glow then
        if t < DURATION - 1200 and now - active.lastSpawn > 35 and #active.sparks < 70 then
            active.lastSpawn = now
            active.sparks[#active.sparks + 1] = {
                born = now, life = math.random(900, 1500),
                ang = math.rad(math.random(0, 359)), r = math.random(30, 65) / 100,
                z0 = math.random(0, 120) / 100, up = math.random(60, 120) / 100,
                spin = (math.random(0, 1) * 2 - 1) * math.random(15, 35) / 10,
                size = math.random(5, 11) / 100, tw = math.random(0, 628) / 100,
            }
        end
        for i = #active.sparks, 1, -1 do
            local p = active.sparks[i]
            local k = (now - p.born) / p.life
            if k >= 1 then
                table.remove(active.sparks, i)
            else
                local age = (now - p.born) / 1000
                local a = p.ang + p.spin * age
                local rr = p.r * (1 - 0.35 * k)
                local twinkle = 0.6 + 0.4 * math.sin(p.tw + age * 18)
                local alpha = 255 * math.min(1, k * 6) * (1 - k) * twinkle * math.max(env, 0.3)
                billboard(T.glow, x + math.cos(a) * rr, y + math.sin(a) * rr, z + p.z0 + p.up * age, p.size, tocolor(255, 236, 170, alpha))
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, stop)
