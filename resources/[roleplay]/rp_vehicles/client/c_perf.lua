--[[
    rp_vehicles / c_perf.lua
    Efectos visibles del rendimiento del tuning (solo vehiculos cercanos):
      - Turbo o motor Stage 3: llamaradas por el escape al soltar el acelerador.
      - Motor o turbo muy desgastado (70%+): humo del motor.
    Sonidos: silbido del turbo mientras se acelera, soplido (BOV) al soltar,
    estallido junto a las llamaradas y ruido de herramientas al instalar piezas.
    Los niveles llegan en el element data "rp:perf" = { e = motor, t = turbo, w = desgaste % }.
]]

local state = {}   -- [vehicle] = { throttle = bool, last = tick }

-- Posicion del escape en el mundo y direccion hacia atras
local function exhaust(vehicle)
    local model = getElementModel(vehicle)
    local ok, x, y, z = pcall(getVehicleModelDummyPosition, model, "exhaust")
    if not ok or not x then
        local _, minY, minZ = getElementBoundingBox(vehicle)
        x, y, z = 0, minY or -2, (minZ or -0.5) + 0.25
    end
    local m = getElementMatrix(vehicle)
    local wx = x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1]
    local wy = x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2]
    local wz = x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
    return wx, wy, wz, -m[2][1], -m[2][2], -m[2][3]
end

local function play3D(file, vehicle, volume, speed)
    local x, y, z = getElementPosition(vehicle)
    local snd = playSound3D("sounds/" .. file .. ".wav", x, y, z, false)
    if not snd then return end
    setSoundMaxDistance(snd, 45)
    setSoundVolume(snd, volume)
    if speed then setSoundSpeed(snd, speed) end
    attachElements(snd, vehicle)
end

-- Silbido del turbo: un sonido en bucle por vehiculo, solo mientras se acelera
local function whistle(vehicle, s, on, level, speed)
    level = math.max(1, math.min(3, level or 1))
    -- Cada nivel de turbo tiene su propio sonido; si cambia la pieza se recrea
    if isElement(s.whistle) and (not on or s.whistleLevel ~= level) then
        destroyElement(s.whistle)
        s.whistle = nil
    end
    if on and not isElement(s.whistle) then
        local x, y, z = getElementPosition(vehicle)
        s.whistleLevel = level
        s.whistle = playSound3D("sounds/tune_turbo_" .. level .. ".wav", x, y, z, true)
        if s.whistle then
            setSoundMaxDistance(s.whistle, 35)
            attachElements(s.whistle, vehicle)
        end
    end
    if on and isElement(s.whistle) then
        setSoundVolume(s.whistle, math.min(1, 0.2 + 0.15 * level))
        setSoundSpeed(s.whistle, math.min(1.6, 0.7 + speed / 160))
    end
end

local function flames(vehicle, power)
    local x, y, z, dx, dy, dz = exhaust(vehicle)
    play3D("tune_backfire", vehicle, 0.6 + 0.2 * power)
    for i = 1, power do
        fxAddTankFire(x, y, z, dx * 0.6, dy * 0.6, dz * 0.6 + 0.05)
    end
    fxAddSparks(x, y, z, dx, dy, dz, 0.8, 3 * power, 0, 0, 0.1, false, 0.5, 1)
end

local function smoke(vehicle)
    local x, y, z = getElementPosition(vehicle)
    local m = getElementMatrix(vehicle)
    -- Capo: un poco por delante del centro del auto
    local fx, fy, fz = m[2][1] * 1.4, m[2][2] * 1.4, m[2][3] * 1.4
    local fxEffect = createEffect("smoke50lit", x + fx, y + fy, z + fz + 0.5, 0, 0, 0, 80)
    if fxEffect then setTimer(function() if isElement(fxEffect) then destroyElement(fxEffect) end end, 1200, 1) end
end

setTimer(function()
    local now = getTickCount()
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local p = getElementData(v, "rp:perf")
        local driver = type(p) == "table" and getVehicleController(v)
        if driver and getVehicleEngineState(v) then
            local s = state[v] or {}
            state[v] = s
            local vx, vy, vz = getElementVelocity(v)
            local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
            local throttle = getPedControlState(driver, "accelerate")

            -- Llamarada al soltar el acelerador a velocidad
            local power = math.max(p.t or 0, (p.e or 0) >= 3 and 2 or 0)
            if s.throttle and not throttle and speed > 45 and power >= 1 and now - (s.last or 0) > 900 then
                s.last = now
                flames(v, power)
            end
            local turbo = p.t or 0
            if turbo > 0 and throttle and speed > 20 then
                if not s.throttle then s.pressed = now end
                whistle(v, s, true, turbo, speed)
            else
                whistle(v, s, false)
                -- Soplido al soltar el acelerador despues de unos instantes con turbo cargado
                if turbo > 0 and s.throttle and speed > 25 and now - (s.pressed or now) > 700 then
                    play3D("tune_bov", v, 0.5 + 0.15 * turbo)
                end
            end
            s.throttle = throttle

            -- Humo si el motor o el turbo estan muy gastados
            if (p.w or 0) >= 70 and now - (s.smoke or 0) > 700 then
                s.smoke = now
                smoke(v)
            end
        elseif state[v] and isElement(state[v].whistle) then
            destroyElement(state[v].whistle)
            state[v].whistle = nil
        end
    end
end, 120, 0)

local function dropState(v)
    local s = state[v]
    if s and isElement(s.whistle) then destroyElement(s.whistle) end
    state[v] = nil
end

addEventHandler("onClientElementDestroy", root, function()
    if getElementType(source) == "vehicle" then dropState(source) end
end)
addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "vehicle" then dropState(source) end
end)

-- Pieza instalada o mantenimiento hecho en el taller
addEvent("rp:tune:sound", true)
addEventHandler("rp:tune:sound", resourceRoot, function(kind)
    if kind ~= "install" then return end
    local snd = playSound("sounds/tune_install.wav")
    if snd then setSoundVolume(snd, 0.8) end
end)
