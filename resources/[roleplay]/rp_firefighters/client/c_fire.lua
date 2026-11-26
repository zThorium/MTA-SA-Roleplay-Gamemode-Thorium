--[[
    rp_firefighters / c_fire.lua  (cliente)

    Fuego de los incidentes, para todos los jugadores cercanos:
      - Efecto de llamas por foco (grande/mediano/pequeño según su vida) y columna de humo.
      - createFire nativo (quema, suena y reacciona al agua) renovado cada pocos segundos
        mientras el servidor diga que el foco sigue vivo: createFire es solo de cliente.
      - Al apagarse: vapor, se extingue y desaparece.
    Detección del chorro (solo bomberos de servicio): a qué focos apunta el extintor o el
    cañón de la autobomba; se manda al servidor cada 0,5 s y allí se revalida.
]]

local fx = {}                 -- [idx] = { tier, flame, smoke, nextFire }
local sprayHits, spraySamples = {}, 0
local FX_DIST = 160           -- metros: dibujar llamas y humo
local NATIVE_FIRE_DIST = 90   -- metros: fuego nativo (quema y suena)
local NATIVE_FIRE_EVERY = 7000

local TIERS = {               -- vida mínima del foco -> efecto de llamas y tamaño del fuego nativo
    { hp = 60, flame = "fire_large", size = 2.6 },
    { hp = 25, flame = "fire_med",   size = 1.8 },
    { hp = 0,  flame = "fire",       size = 1.0 },
}

local function tierOf(hp)
    for i, t in ipairs(TIERS) do if hp > t.hp or i == #TIERS then return i end end
end

local function clearFocus(idx, withSteam)
    local e = fx[idx]
    fx[idx] = nil
    if not e then return end
    if isElement(e.flame) then destroyElement(e.flame) end
    if isElement(e.smoke) then destroyElement(e.smoke) end
    local f = FDC.incident and FDC.incident.foci[idx]
    if f then
        extinguishFire(f.x, f.y, f.z, 4)
        if withSteam then
            local steam = createEffect("smoke30m", f.x, f.y, f.z - 0.6, -90, 0, 0, FX_DIST)
            if steam then setTimer(function() if isElement(steam) then destroyElement(steam) end end, 6000, 1) end
        end
    end
end

local function clearAll(withSteam)
    for idx in pairs(fx) do clearFocus(idx, withSteam) end
    fx = {}
end

-- Mantener los efectos de cada foco según distancia y vida
local function updateFx()
    local I = FDC.incident
    -- Tras un fallo el fuego sigue hasta que el servidor limpia la escena
    if not I or getElementDimension(localPlayer) ~= 0 or getElementInterior(localPlayer) ~= 0 then
        if next(fx) then clearAll(false) end
        return
    end
    local px, py, pz = getElementPosition(localPlayer)
    local now = getTickCount()
    for idx, f in ipairs(I.foci) do
        local d = getDistanceBetweenPoints3D(px, py, pz, f.x, f.y, f.z)
        local e = fx[idx]
        if f.hp <= 0 or d > FX_DIST then
            if e then clearFocus(idx, false) end
        else
            local tier = tierOf(f.hp)
            if not e or e.tier ~= tier then
                if e then
                    if isElement(e.flame) then destroyElement(e.flame) end
                else
                    e = { nextFire = 0 }
                    e.smoke = createEffect("smoke50lit", f.x, f.y, f.z + 0.5, -90, 0, 0, FX_DIST)
                end
                e.tier = tier
                e.flame = createEffect(TIERS[tier].flame, f.x, f.y, f.z - 0.9, -90, 0, 0, FX_DIST)
                fx[idx] = e
            end
            if d <= NATIVE_FIRE_DIST and now >= e.nextFire then
                createFire(f.x, f.y, f.z - 0.9, TIERS[tier].size)
                e.nextFire = now + NATIVE_FIRE_EVERY
            end
        end
    end
end
setTimer(updateFx, 300, 0)

FDC.onFire = function(incident)
    if not incident then clearAll(false) end
    updateFx()
end

FDC.onEnded = function(_, success)
    if success then clearAll(true) end
end

addEventHandler("rp:firefighters:focusOut", resourceRoot, function(id, idx)
    local I = FDC.incident
    if not I or I.id ~= id or not I.foci[idx] then return end
    I.foci[idx].hp = 0
    clearFocus(idx, true)
    if FDC.onDuty then FDC.hudJS("FD.sound(\"focusOut\")") end
end)

----------------------------------------------------------------
-- Chorro de agua (solo bomberos de servicio)
----------------------------------------------------------------
local function activeTool()
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh then
        if FIRE.CANNON.models[getElementModel(veh)] and getVehicleController(veh) == localPlayer
            and getPedControlState(localPlayer, "vehicle_fire") then
            return FIRE.CANNON, veh
        end
        return nil
    end
    if getPedWeapon(localPlayer) == 42 and getPedControlState(localPlayer, "fire") then return FIRE.EXTINGUISHER end
    return nil
end

-- shortcut: cono desde la cámara sin línea de visión; si atraviesan paredes, añadir processLineOfSight
local function sample()
    local I = FDC.incident
    if not FDC.onDuty or not I or I.ended then return end
    spraySamples = spraySamples + 1
    local cfg, veh = activeTool()
    if not cfg then return end
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    local dx, dy, dz = tx - cx, ty - cy, tz - cz
    local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dl == 0 then return end
    local ox, oy, oz = getElementPosition(veh or localPlayer)
    local cosMax = math.cos(math.rad(cfg.angle))
    for idx, f in ipairs(I.foci) do
        if f.hp > 0 then
            local vx, vy, vz = f.x - ox, f.y - oy, f.z - oz
            local d = math.sqrt(vx * vx + vy * vy + vz * vz)
            if d <= cfg.range then
                -- Muy cerca cuenta siempre; si no, el foco debe estar dentro del cono de la mirada
                local cosA = d < 1.5 and 1 or (vx * dx + vy * dy + vz * dz) / (d * dl)
                if cosA >= cosMax then sprayHits[idx] = (sprayHits[idx] or 0) + 1 end
            end
        end
    end
end
setTimer(sample, 100, 0)

setTimer(function()
    if spraySamples == 0 then return end
    if next(sprayHits) then
        local out = {}
        for idx, n in pairs(sprayHits) do out[idx] = n / spraySamples end
        triggerServerEvent("rp:firefighters:spray", resourceRoot, out)
    end
    sprayHits, spraySamples = {}, 0
end, 500, 0)

----------------------------------------------------------------
-- Los civiles no mueren por el fuego del cliente: su vida la lleva el servidor
----------------------------------------------------------------
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:fireVictim") then cancelEvent() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function() clearAll(false) end)
