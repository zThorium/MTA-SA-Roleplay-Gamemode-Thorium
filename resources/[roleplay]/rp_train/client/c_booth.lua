--[[
    rp_train · empleado de la boletería destacado (cliente)

    Los peds de las boleterías (data rp:train:booth, s_stations.lua) tienen un aura en el piso que
    "respira" (crece y se apaga despacio) para que quien entra a la estación sepa a quién comprarle el
    boleto (UX-02: lo útil destaca). El personaje se ve normal: solo se dibuja el suelo.
    Texturas SVG con degradado (sin imágenes), como el aura de rp_levels. Solo los peds en streaming y a
    menos de BOOTH_AURA_DISTANCE de la cámara.
]]

local booths = {}   -- [ped] = true (en streaming y con la data)
local tex           -- { glow, ring }

local SVG = {
    glow = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><defs>
        <radialGradient id="g" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>
        <stop offset="0.55" stop-color="#ffffff" stop-opacity="0.22"/>
        <stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>
        <circle cx="64" cy="64" r="64" fill="url(#g)"/></svg>]],
    ring = [[<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><defs>
        <radialGradient id="g" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="#ffffff" stop-opacity="0"/>
        <stop offset="0.74" stop-color="#ffffff" stop-opacity="0"/>
        <stop offset="0.87" stop-color="#ffffff" stop-opacity="1"/>
        <stop offset="0.93" stop-color="#ffffff" stop-opacity="0.6"/>
        <stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>
        <circle cx="128" cy="128" r="128" fill="url(#g)"/></svg>]],
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

local function refresh(ped)
    if not isElement(ped) or getElementType(ped) ~= "ped" then return end
    if getElementData(ped, "rp:train:booth") and isElementStreamedIn(ped) then
        booths[ped] = true
        textures()
    else
        booths[ped] = nil
    end
end

addEventHandler("onClientElementStreamIn", root, function() refresh(source) end)
addEventHandler("onClientElementStreamOut", root, function() refresh(source) end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:train:booth" then refresh(source) end
end)
addEventHandler("onClientElementDestroy", root, function() booths[source] = nil end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, ped in ipairs(getElementsByType("ped", root, true)) do refresh(ped) end
end)

local function disc(material, x, y, z, r, color)
    dxDrawMaterialLine3D(x, y - r, z, x, y + r, z, material, r * 2, color, x, y, z + 10)
end

addEventHandler("onClientPreRender", root, function()
    if not next(booths) or not tex then return end
    local cx, cy, cz = getCameraMatrix()
    local c = TRAIN.BOOTH_AURA_COLOR
    -- respiración: 0..1..0 cada BOOTH_AURA_PERIOD ms, suave (seno)
    local t = getTickCount() / TRAIN.BOOTH_AURA_PERIOD
    local breath = 0.5 - 0.5 * math.cos(t * 2 * math.pi)
    local ring = t % 1  -- un anillo que se abre y se desvanece por cada respiración
    for ped in pairs(booths) do
        if isElement(ped) then
            local x, y, z = getElementPosition(ped)
            if getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) < TRAIN.BOOTH_AURA_DISTANCE then
                local base = getElementDistanceFromCentreOfMassToBaseOfModel(ped)
                z = z - ((base and base > 0.2) and base or 1) + 0.04
                local r = TRAIN.BOOTH_AURA_RADIUS
                if tex.glow then
                    disc(tex.glow, x, y, z, r * (0.85 + 0.15 * breath), tocolor(c[1], c[2], c[3], 90 + 120 * breath))
                end
                if tex.ring then
                    disc(tex.ring, x, y, z, r * (0.55 + 0.6 * ring), tocolor(c[1], c[2], c[3], 200 * (1 - ring)))
                end
            end
        end
    end
end)
