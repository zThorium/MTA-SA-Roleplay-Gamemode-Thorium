--[[
    rp_vehicles / s_perf.lua
    Rendimiento del tuning: piezas con niveles (motor, turbo, frenos, suspension,
    neumaticos, aligeramiento) que modifican el handling de cada vehiculo, con
    tope por clase de vehiculo y desgaste por kilometraje y uso.

    Persistencia (vehicles.perf JSON + vehicles.odometer km):
        { p = { engine = 2, turbo = 1 }, w = { engine = 14.5, turbo = 3.2 } }
    Solo se guardan las piezas y el desgaste; el handling se recalcula siempre
    desde getOriginalHandling, asi nunca se acumulan bonos.

    Configuracion y formulas puras en shared/s_config.lua (PERF, computePerfStats...).
    Panel: categoria "Rendimiento" de html/tuning.js. Efectos visuales: client/c_perf.lua.
]]

addEvent("rp:tune:perf", true)
addEvent("rp:tune:maint", true)

local perf = {}      -- [vehicle] = { parts = {}, wear = {}, odo = km, applied = bool, stats = {}, fx = "" }
local lastPos = {}   -- [vehicle] = { x, y, z }
local lastSpeed = {} -- [vehicle] = km/h en la muestra anterior

local function round(n, d)
    local m = 10 ^ (d or 0)
    return math.floor(n * m + 0.5) / m
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

----------------------------------------------------------------
-- Handling
----------------------------------------------------------------
-- Datos para efectos del cliente (solo cambian cuando cambia un nivel o un tramo de desgaste)
local function publish(vehicle, st)
    local engine, turbo = st.parts.engine or 0, st.parts.turbo or 0
    local worst = math.max(st.wear.engine or 0, st.wear.turbo or 0)
    local key = engine .. ":" .. turbo .. ":" .. math.floor(worst / 10)
    if st.fx == key then return end
    st.fx = key
    if engine == 0 and turbo == 0 then setElementData(vehicle, "rp:perf", nil)
    else setElementData(vehicle, "rp:perf", { e = engine, t = turbo, w = math.floor(worst) }) end
end

function applyPerf(vehicle)
    local st = perf[vehicle]
    if not st or not isElement(vehicle) then return end
    local model = getElementModel(vehicle)
    local classId = getPerfClass(model)
    local hasParts = next(st.parts) ~= nil
    st.stats = computePerfStats(st.parts, st.wear)
    publish(vehicle, st)
    -- Un auto de fabrica no se toca; si tuvo piezas y se quitaron, se vuelve a fijar el valor base
    if not classId or (not hasParts and not st.applied) then return end
    local base = getOriginalHandling(model)
    if type(base) ~= "table" then return end

    local cap = PERF.CLASSES[classId].cap
    local s = {}
    for stat, v in pairs(st.stats) do
        s[stat] = v
        if cap[stat] then s[stat] = math.min(cap[stat], v) end
        s[stat] = math.max(-0.5, s[stat])
    end

    setVehicleHandling(vehicle, "engineAcceleration", base.engineAcceleration * (1 + s.accel))
    setVehicleHandling(vehicle, "maxVelocity", math.min(math.max(PERF.MAX_VELOCITY, base.maxVelocity), base.maxVelocity * (1 + s.speed)))
    setVehicleHandling(vehicle, "brakeDeceleration", base.brakeDeceleration * (1 + s.brake))
    setVehicleHandling(vehicle, "tractionMultiplier", base.tractionMultiplier * (1 + s.grip))
    setVehicleHandling(vehicle, "steeringLock", math.min(math.max(PERF.MAX_STEER, base.steeringLock), base.steeringLock * (1 + s.steer)))
    setVehicleHandling(vehicle, "mass", base.mass * (1 + s.mass))
    setVehicleHandling(vehicle, "turnMass", base.turnMass * (1 + s.mass))
    -- Suspension: cada nivel baja un poco el auto (se ve en el taller)
    local lowered = (st.parts.suspension or 0) * PERF.LOWER_PER_LEVEL
    setVehicleHandling(vehicle, "suspensionLowerLimit", math.min(-0.05, base.suspensionLowerLimit + lowered))
    st.applied = hasParts
end

-- Multiplicador del consumo de bencina (lo usa s_fuel.lua)
function getPerfFuelFactor(vehicle)
    local st = perf[vehicle]
    return 1 + math.max(0, st and st.stats and st.stats.fuel or 0)
end

function getVehicleOdometer(vehicle)
    local st = perf[vehicle]
    return st and st.odo or 0
end

----------------------------------------------------------------
-- Persistencia
----------------------------------------------------------------
function initPerf(vehicle, json, odometer)
    local st = { parts = {}, wear = {}, odo = tonumber(odometer) or 0, applied = false, stats = {}, fx = "" }
    local t = type(json) == "string" and fromJSON(json)
    if type(t) == "table" then
        for id, level in pairs(type(t.p) == "table" and t.p or {}) do
            local def = PERF_PART[id]
            level = tonumber(level)
            if def and level and def.levels[level] then st.parts[id] = level end
        end
        for id, w in pairs(type(t.w) == "table" and t.w or {}) do
            if st.parts[id] and tonumber(w) then st.wear[id] = math.max(0, math.min(100, tonumber(w))) end
        end
    end
    perf[vehicle] = st
    applyPerf(vehicle)
end

function capturePerf(vehicle)
    local st = perf[vehicle]
    if not st or next(st.parts) == nil then return nil end
    local wear = {}
    for id, w in pairs(st.wear) do wear[id] = round(w, 2) end
    return toJSON({ p = st.parts, w = wear }, true)
end

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    perf[source], lastPos[source], lastSpeed[source] = nil, nil, nil
end)

----------------------------------------------------------------
-- Desgaste por kilometraje y uso
----------------------------------------------------------------
-- Angulo (grados) entre hacia donde apunta el auto y hacia donde se mueve
local function slipAngle(vehicle)
    local vx, vy = getElementVelocity(vehicle)
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed < PERF.SLIP_SPEED then return 0 end
    local _, _, rz = getElementRotation(vehicle)
    local fx, fy = -math.sin(math.rad(rz)), math.cos(math.rad(rz))
    local dot = math.min(1, math.abs((vx * fx + vy * fy) / speed))
    return math.deg(math.acos(dot))
end

local function addWear(vehicle, st, id, amount, driver)
    if amount <= 0 or not st.parts[id] then return false end
    local before = st.wear[id] or 0
    local after = math.min(100, before + amount)
    st.wear[id] = after
    if driver and isElement(driver) then
        local name = PERF_PART[id].name
        if after >= 100 and before < 100 then
            notify(driver, ("%s desgastado por completo: ya no mejora el vehiculo y lo empeora. Hazle mantenimiento en un taller."):format(name), "error")
        elseif after >= PERF.WARN_AT and before < PERF.WARN_AT then
            notify(driver, ("%s al %d%% de desgaste: pierde rendimiento. Hazle mantenimiento en un taller."):format(name, PERF.WARN_AT), "warning")
        end
    end
    return math.floor(after) ~= math.floor(before)
end

local function wearVehicle(vehicle, st, driver, km)
    st.odo = st.odo + km
    if next(st.parts) == nil then return end

    local speed = vehicleSpeedKmh(vehicle)
    local vmax = tonumber(getVehicleHandling(vehicle).maxVelocity) or 150
    local ratio = math.min(1.3, speed / math.max(vmax, 50))
    -- El servidor no lee las teclas: frenazo = bajada fuerte de velocidad entre muestras
    local previous = lastSpeed[vehicle] or speed
    lastSpeed[vehicle] = speed
    local braking = previous > PERF.BRAKE_MIN_SPEED and previous - speed >= PERF.BRAKE_DROP
    local slipping = slipAngle(vehicle) > PERF.SLIP_ANGLE
    local turbo = st.parts.turbo or 0
    local changed = false

    for _, def in ipairs(PERF.PARTS) do
        local level = st.parts[def.id]
        if level and def.wear then
            local w = def.wear
            local levelMult = 1 + w.level * (level - 1)
            local amount = km * w.km * levelMult * (0.7 + w.speed * ratio)
            if def.id == "engine" then amount = amount * (1 + PERF.TURBO_ENGINE_WEAR * turbo) end
            if w.use == "brake" and braking then amount = amount + PERF.BRAKE_USE * math.max(0.3, ratio) * levelMult end
            if w.use == "slip" and slipping then amount = amount + PERF.SLIP_USE * levelMult end
            if addWear(vehicle, st, def.id, amount, driver) then changed = true end
        end
    end
    if changed then applyPerf(vehicle) end
end

setTimer(function()
    for v, st in pairs(perf) do
        if isElement(v) then
            local driver = getVehicleController(v)
            if driver and getVehicleEngineState(v) then
                local x, y, z = getElementPosition(v)
                local last = lastPos[v]
                lastPos[v] = { x, y, z }
                local dist = last and getDistanceBetweenPoints3D(x, y, z, last[1], last[2], last[3]) or 0
                if dist > 400 then dist = 0 end   -- teletransporte
                if dist > 1 then wearVehicle(v, st, driver, dist / 1000) end
            else
                lastPos[v], lastSpeed[v] = nil, nil
            end
        end
    end
end, PERF.TICK, 0)

-- Los choques fuertes desgastan la suspension
addEventHandler("onVehicleDamage", root, function(loss)
    local st = perf[source]
    if not st or not st.parts.suspension or (loss or 0) < PERF.IMPACT_MIN then return end
    if addWear(source, st, "suspension", loss * PERF.IMPACT_WEAR, getVehicleController(source)) then applyPerf(source) end
end)

----------------------------------------------------------------
-- Panel del taller
----------------------------------------------------------------
local function percentList(stats)
    local out = {}
    for i, stat in ipairs(PERF.STAT_ORDER) do out[i] = round((stats[stat] or 0) * 100, 1) end
    return out
end

-- Datos de la categoria "Rendimiento" (nil si el vehiculo no se puede mejorar)
function getPerfPanel(vehicle)
    local st, data = perf[vehicle], getVehicleData(vehicle)
    local classId = data and getPerfClass(data.model)
    if not st or not classId then return nil end
    local class = PERF.CLASSES[classId]
    local current = computePerfStats(st.parts, st.wear)

    local defs = {}
    for i, stat in ipairs(PERF.STAT_ORDER) do
        defs[i] = { name = PERF.STAT_NAMES[stat], cost = PERF.COST_STATS[stat] == true,
            cap = round((class.cap[stat] or PERF.COST_DISPLAY_CAP) * 100, 1) }
    end

    local parts = {}
    for _, def in ipairs(PERF.PARTS) do
        local level = st.parts[def.id] or 0
        local wear = st.wear[def.id] or 0
        local part = {
            id = def.id, name = def.name, desc = def.desc, level = level, wear = round(wear, 1), wears = def.wear ~= nil,
            levelName = level > 0 and def.levels[level].name or nil,
            maint = perfMaintenancePrice(classId, def.id, level, wear), levels = {},
        }
        for i, lv in ipairs(def.levels) do
            local trialParts = copy(st.parts)
            trialParts[def.id] = i
            local trialWear = copy(st.wear)
            trialWear[def.id] = nil
            local fresh = computePerfStats(trialParts, nil)
            local ok, bad = perfWithinCap(classId, fresh)
            part.levels[i] = {
                level = i, name = lv.name, price = perfLevelPrice(classId, lv), installed = level == i,
                ok = ok, why = bad and ("Supera el tope de " .. PERF.STAT_NAMES[bad]:lower() .. " de la clase") or nil,
                stats = percentList(computePerfStats(trialParts, trialWear)),
            }
        end
        parts[#parts + 1] = part
    end

    local maintTotal = 0
    for _, p in ipairs(parts) do maintTotal = maintTotal + p.maint end
    return {
        class = class.name, odo = round(st.odo, 1), defs = defs, stats = percentList(current),
        parts = parts, maintTotal = maintTotal, remove = TUNING.PRICE_REMOVE,
    }
end

-- Comprueba que el jugador esta tuneando su vehiculo en un taller. Devuelve v, st, classId.
local function tuningContext(player)
    local v = getTuningVehicle(player)
    if not v or not isElement(v) or getPedOccupiedVehicle(player) ~= v or not isVehicleInTuningShop(v) then return end
    local data = getVehicleData(v)
    if not data or data.ownerId ~= characterOf(player) then return end
    local classId = getPerfClass(data.model)
    if not classId or not perf[v] then
        notify(player, "Este vehiculo no admite mejoras de rendimiento.", "warning")
        return
    end
    return v, perf[v], classId
end

local function finish(player, v, message)
    applyPerf(v)
    saveVehicle(v)
    exports.rp_characters:saveCharacter(player)
    notify(player, message, "success")
    sendTuning(player, v, getVehicleTuningShop(v) or { name = "Taller" })
end

addEventHandler("rp:tune:perf", resourceRoot, function(partId, level)
    local player = client
    local v, st, classId = tuningContext(player)
    if not v then return end
    local def = type(partId) == "string" and PERF_PART[partId]
    level = tonumber(level)
    if not def or not level or level ~= math.floor(level) or level < 0 or level > #def.levels then return end
    if (st.parts[def.id] or 0) == level then return notify(player, "Esa pieza ya esta instalada.", "warning") end

    local price = TUNING.PRICE_REMOVE
    if level > 0 then
        price = perfLevelPrice(classId, def.levels[level])
        local trial = copy(st.parts)
        trial[def.id] = level
        local ok, bad = perfWithinCap(classId, computePerfStats(trial, nil))
        if not ok then
            return notify(player, ("Esa pieza supera el tope de %s de la clase %s. Prueba con una de menor nivel."):format(
                PERF.STAT_NAMES[bad]:lower(), PERF.CLASSES[classId].name:lower()), "error")
        end
    end
    if getPlayerMoney(player) < price then return notify(player, ("Necesitas $%d en efectivo."):format(price), "error") end
    takePlayerMoney(player, price)
    st.parts[def.id] = level > 0 and level or nil
    st.wear[def.id] = nil   -- pieza nueva (o quitada): sin desgaste
    if level > 0 then
        finish(player, v, ("%s instalado por $%d."):format(def.levels[level].name, price))
    else
        finish(player, v, ("%s retirado por $%d."):format(def.name, price))
    end
end)

addEventHandler("rp:tune:maint", resourceRoot, function(partId)
    local player = client
    local v, st, classId = tuningContext(player)
    if not v then return end
    local ids = {}
    if partId == "all" then
        for id in pairs(st.parts) do ids[#ids + 1] = id end
    elseif type(partId) == "string" and PERF_PART[partId] then
        ids[1] = partId
    else
        return
    end
    local total, fixed = 0, {}
    for _, id in ipairs(ids) do
        local price = perfMaintenancePrice(classId, id, st.parts[id] or 0, st.wear[id] or 0)
        if price > 0 then total = total + price fixed[#fixed + 1] = id end
    end
    if total <= 0 then return notify(player, "No hay piezas que necesiten mantenimiento.", "warning") end
    if getPlayerMoney(player) < total then return notify(player, ("Necesitas $%d en efectivo."):format(total), "error") end
    takePlayerMoney(player, total)
    for _, id in ipairs(fixed) do st.wear[id] = nil end
    finish(player, v, ("Mantenimiento hecho por $%d."):format(total))
end)
