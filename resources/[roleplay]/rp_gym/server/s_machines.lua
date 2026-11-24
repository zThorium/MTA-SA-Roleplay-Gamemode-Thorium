--[[
    rp_gym / s_machines.lua
    Cinta, bicicleta estatica, press de banca y mancuernas. El servidor lleva toda la sesion:
    la barra de potencia, el nivel o peso, las repeticiones, la distancia y las ganancias.
    El cliente solo envia pulsaciones (con separacion minima y alternancia validadas aqui) y dibuja.

    Eventos cliente -> servidor (siempre con `client`):
        rp:gym:start  (machineId, opcion)   subir a la maquina; opcion = indice de peso (banca y mancuernas)
        rp:gym:pulse  (lado)                1 o 2 alternando (cinta y bici); 0 (pesas)
        rp:gym:level  (-1 | 1)              cinta y bici: bajar o subir de nivel
        rp:gym:stop                         bajarse
    Eventos servidor -> cliente:
        rp:gym:near   (tipo, id, etiqueta, extra)   aviso "Pulsa E" (tipo false = ya no hay nada cerca)
        rp:gym:state  (tabla | false)       estado de la sesion para dibujar los medidores
]]

addEvent("rp:gym:start", true)
addEvent("rp:gym:pulse", true)
addEvent("rp:gym:level", true)
addEvent("rp:gym:stop", true)

local machines = {}    -- [id] = { row, cfg, object, col }
local busy = {}        -- [id] = player que la usa
local sessions = {}    -- [player] = sesion
local leaving = {}     -- [player] = true mientras baja de la maquina
nearTarget = {}        -- [player] = { type, id } (lo comparten maquinas y entrenadores)

gymInFight = {}        -- [player] = true durante un combate de entrenamiento (lo rellena s_trainers.lua)

function gymNear(player, kind, id, label, extra)
    nearTarget[player] = kind and { kind, id } or nil
    if isElement(player) then triggerClientEvent(player, "rp:gym:near", resourceRoot, kind, id, label, extra) end
end

local function sameWorld(a, b)
    return getElementDimension(a) == getElementDimension(b) and getElementInterior(a) == getElementInterior(b)
end

----------------------------------------------------------------
-- Elementos del mundo
----------------------------------------------------------------
local endSession   -- se define mas abajo

function gymSpawnMachine(row)
    local cfg = GYM_KINDS[row.kind]
    if not cfg then return false end
    local obj = createObject(cfg.model, row.x, row.y, row.z + cfg.zOffset, 0, 0, row.rotation)
    local col = createColSphere(row.x, row.y, row.z, GYM.TRIGGER_RADIUS)
    for _, el in ipairs({ obj, col }) do
        setElementInterior(el, row.interior)
        setElementDimension(el, row.dimension)
    end
    machines[row.id] = { row = row, cfg = cfg, object = obj, col = col }

    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim or not gymCharacter(el) then return end
        gymNear(el, "machine", row.id, cfg.label, cfg.weights)
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and nearTarget[el] and nearTarget[el][1] == "machine" and nearTarget[el][2] == row.id then
            gymNear(el, false)
        end
    end)
    return true
end

function gymDestroyMachine(id)
    local m = machines[id]
    if not m then return false end
    if busy[id] then endSession(busy[id], "removed") end
    for player, t in pairs(nearTarget) do
        if t[1] == "machine" and t[2] == id then gymNear(player, false) end
    end
    if isElement(m.object) then destroyElement(m.object) end
    if isElement(m.col) then destroyElement(m.col) end
    machines[id] = nil
    return true
end

function gymMachineList() return machines end

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do endSession(player, "stop", true) end
end)

----------------------------------------------------------------
-- Animaciones
----------------------------------------------------------------
local function playAnim(player, anim, loop, freeze)
    if isElement(player) and anim then
        setPedAnimation(player, anim[1], anim[2], -1, loop and true or false, false, false, freeze and true or false)
    end
end

local function loopAnimFor(s)
    local cfg = s.cfg
    if cfg.levels then
        if s.tired then return { cfg.tired[1], cfg.tired[2] } end
        for _, entry in ipairs(cfg.loops) do
            if s.level <= entry[1] then return { "GYMNASIUM", entry[2] } end
        end
        return { "GYMNASIUM", cfg.loops[#cfg.loops][2] }
    end
    return cfg.rest
end

local function sendState(s)
    if not isElement(s.player) then return end
    triggerClientEvent(s.player, "rp:gym:state", resourceRoot, {
        kind = s.kind, label = s.cfg.label, level = s.level, levels = s.cfg.levels, gauge = math.floor(s.gauge * 10) / 10,
        reps = s.reps, dist = math.floor(s.dist), secs = math.floor(s.secs), lb = s.lb, ready = s.ready,
        tired = s.tired,
    })
end

----------------------------------------------------------------
-- Fin de sesion
----------------------------------------------------------------
local REASONS = {
    limit = { "Has llegado al limite de entrenamiento de hoy. Descansa 12 horas antes de volver.", "warning" },
    fall = { "Te quedas sin fuerzas y te caes de la maquina.", "warning" },
    idle = { "Sueltas el peso: no tienes fuerzas para continuar.", "warning" },
    removed = { "La maquina ya no esta disponible.", "info" },
}

function endSession(player, reason, silent)
    local s = sessions[player]
    if not s then return end
    sessions[player] = nil
    busy[s.id] = nil
    if isTimer(s.timer) then killTimer(s.timer) end
    local alive = isElement(player)

    if not silent and alive then
        if s.cfg.levels and s.acc > 0.5 and reason ~= "limit" then
            local f = (s.level / s.cfg.levels) * s.acc / GYM.RATE_SECONDS
            gymApplyDelta(player, GYM.RATE_STAMINA * f, GYM.RATE_MUSCLE * f, GYM.RATE_FAT * f, false)
        end
        -- Records y visitas (stats de GTA)
        gymBumpStat(player, 198, 1)
        if s.cfg.levels then
            gymBumpStat(player, s.cfg.distStat, s.dist)
            gymBumpStat(player, s.cfg.timeStat, s.secs, true)
        elseif s.reps > 0 then
            gymBumpStat(player, s.cfg.recordStat, s.lb, true)
        end
        exports.rp_characters:setBodyStats(player, nil, nil, nil, true)   -- redibuja el cuerpo con lo ganado
        saveProfile(player)
        if REASONS[reason] then gymNotify(player, REASONS[reason][1], REASONS[reason][2]) end
    end
    if not alive then return end

    triggerClientEvent(player, "rp:gym:state", resourceRoot, false)
    if silent then
        setElementFrozen(player, false)
        setPedAnimation(player)
        return
    end
    leaving[player] = true
    playAnim(player, (reason == "fall") and s.cfg.fall or s.cfg.getoff, false, false)
    setTimer(function()
        leaving[player] = nil
        if isElement(player) then
            setElementFrozen(player, false)
            setPedAnimation(player)
        end
    end, GYM.GETOFF_MS, 1)
end
function gymEndSession(player, reason, silent) endSession(player, reason, silent) end

for _, event in ipairs({ "onPlayerQuit", "onPlayerWasted", "rp:onCharacterLogout" }) do
    addEventHandler(event, root, function() endSession(source, "quit", true) end)
end
addEventHandler("onPlayerQuit", root, function()
    leaving[source], nearTarget[source] = nil, nil
end)

----------------------------------------------------------------
-- Bucle de la sesion
----------------------------------------------------------------
local function tick(s)
    local player = s.player
    if sessions[player] ~= s then return end
    local now = getTickCount()
    local dt = math.min((now - s.last) / 1000, 1)
    s.last = now

    if not s.ready then
        if now >= s.readyAt then
            s.ready, s.idleSince = true, now
            playAnim(player, loopAnimFor(s), s.cfg.levels ~= nil or s.kind == "dumbbells", s.cfg.levels == nil)
        end
        return sendState(s)
    end

    local cfg = s.cfg
    if cfg.levels then
        s.gauge = s.gauge - (cfg.drainBase + cfg.drainStep * s.level) * dt
        s.secs = s.secs + dt
        s.dist = s.dist + (cfg.speedBase + cfg.speedStep * s.level) / 3.6 * dt
        s.acc = s.acc + dt
        if s.acc >= GYM.APPLY_EVERY then
            local f = (s.level / cfg.levels) * s.acc / GYM.RATE_SECONDS
            s.acc = 0
            if gymApplyDelta(player, GYM.RATE_STAMINA * f, GYM.RATE_MUSCLE * f, GYM.RATE_FAT * f, false) then
                return endSession(player, "limit")
            end
        end
        if s.gauge <= 0 and now - s.readyAt > GYM_GRACE_MS then return endSession(player, "fall") end
        s.gauge = math.max(0, s.gauge)
        local tired = s.gauge < 25
        if tired ~= s.tired then
            s.tired = tired
            playAnim(player, loopAnimFor(s), true, false)
        end
    elseif now >= s.lockUntil then
        local w = (s.lb - s.minLb) / (s.maxLb - s.minLb)
        s.gauge = math.max(0, s.gauge - (cfg.decayBase + cfg.decayHeavy * w) * dt)
        if s.gauge > 0 then
            s.idleSince = now
        elseif now - s.idleSince > GYM_IDLE_FAIL_MS then
            return endSession(player, "idle")
        end
    end
    sendState(s)
end

local function completeRep(s, now)
    local player = s.player
    s.gauge, s.reps = 0, s.reps + 1
    s.lockUntil = now + GYM_REP_LOCK_MS
    s.idleSince = s.lockUntil
    s.flip = not s.flip
    playAnim(player, (s.flip and s.cfg.up2) or s.cfg.up, false, true)
    setTimer(function()
        if sessions[player] == s then playAnim(player, s.cfg.rest, s.kind == "dumbbells", true) end
    end, math.floor(GYM_REP_LOCK_MS * 0.6), 1)
    -- Ganancia de musculo: mas peso = mas; cuanto mas fuerte ya es el personaje, menos (0,1 % a 0,9 %)
    local stats = exports.rp_characters:getBodyStats(player)
    local weight = (s.lb - s.minLb) / (s.maxLb - s.minLb)
    local strength = 1 - (stats and stats.muscle or 0) / 1000
    local gain = GYM.REP_MUSCLE_MIN + (GYM.REP_MUSCLE_MAX - GYM.REP_MUSCLE_MIN) * weight * strength
    gain = math.max(GYM.REP_MUSCLE_MIN, gain * s.cfg.muscleFactor)
    if gymApplyDelta(player, 0, gain, GYM.REP_FAT, false) then endSession(player, "limit") end
end

----------------------------------------------------------------
-- Eventos del cliente
----------------------------------------------------------------
addEventHandler("rp:gym:start", resourceRoot, function(machineId, option)
    local player = client
    machineId = tonumber(machineId)
    local m = machineId and machines[machineId]
    if not m or not gymCharacter(player) or sessions[player] or leaving[player] or gymInFight[player] then return end
    if getElementData(player, "rp:downed") or isPedDead(player) or isPedInVehicle(player) then return end
    local p = profiles[player]
    if not p or p.loading then return end

    local px, py, pz = getElementPosition(player)
    if not sameWorld(player, m.col) or getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z) > GYM.USE_RANGE then
        return gymNotify(player, "Estas demasiado lejos de la maquina.", "warning")
    end
    if busy[machineId] then return gymNotify(player, "Esa maquina esta ocupada.", "warning") end
    local lock = gymLockRemaining(player)
    if lock > 0 then
        return gymNotify(player, "Estas agotado de tanto entrenar. Vuelve en " .. gymLockText(lock) .. ".", "warning")
    end

    local cfg = m.cfg
    local lb
    if cfg.weights then
        option = tonumber(option)
        if not option or option ~= math.floor(option) or not cfg.weights[option] then return end
        lb = cfg.weights[option]
    end

    local now = getTickCount()
    local s = {
        player = player, id = machineId, kind = m.row.kind, cfg = cfg, level = 1, gauge = cfg.levels and GYM_GAUGE_START or 0,
        reps = 0, dist = 0, secs = 0, acc = 0, lb = lb, minLb = cfg.weights and cfg.weights[1], maxLb = cfg.weights and cfg.weights[#cfg.weights],
        last = now, readyAt = now + GYM.GETON_MS, lockUntil = 0, idleSince = now, lastPulse = 0, lastSide = 0,
        lastLevel = 0, ready = false, tired = false, flip = false,
    }
    sessions[player] = s
    busy[machineId] = player
    gymNear(player, false)

    setElementPosition(player, m.row.x, m.row.y, m.row.z)
    setElementRotation(player, 0, 0, m.row.rotation)
    setElementFrozen(player, true)
    playAnim(player, cfg.geton, false, true)
    s.timer = setTimer(tick, GYM.TICK_MS, 0, s)
    sendState(s)
end)

addEventHandler("rp:gym:pulse", resourceRoot, function(side)
    local s = sessions[client]
    if not s or not s.ready or type(side) ~= "number" then return end
    local now = getTickCount()
    if now - s.lastPulse < GYM.PULSE_MIN_MS then return end

    if s.cfg.levels then
        if (side ~= 1 and side ~= 2) or side == s.lastSide then return end   -- hay que alternar, como al correr
        s.lastSide = side
        s.lastPulse = now
        s.gauge = math.min(100, s.gauge + s.cfg.pulseGain)
    else
        if side ~= 0 or now < s.lockUntil then return end
        s.lastPulse = now
        local w = (s.lb - s.minLb) / (s.maxLb - s.minLb)
        s.gauge = s.gauge + (s.cfg.gainBase - s.cfg.gainHeavy * w)
        if s.gauge >= 100 then completeRep(s, now) end
    end
end)

addEventHandler("rp:gym:level", resourceRoot, function(dir)
    local s = sessions[client]
    if not s or not s.ready or not s.cfg.levels or (dir ~= 1 and dir ~= -1) then return end
    local now = getTickCount()
    if now - s.lastLevel < 250 then return end
    s.lastLevel = now
    local level = math.max(1, math.min(s.cfg.levels, s.level + dir))
    if level == s.level then return end
    if s.level > 0 then   -- cada nivel pendiente de entrenar se paga con la fraccion acumulada al nivel anterior
        local f = (s.level / s.cfg.levels) * s.acc / GYM.RATE_SECONDS
        s.acc = 0
        if f > 0 and gymApplyDelta(client, GYM.RATE_STAMINA * f, GYM.RATE_MUSCLE * f, GYM.RATE_FAT * f, false) then
            return endSession(client, "limit")
        end
    end
    s.level = level
    playAnim(client, loopAnimFor(s), true, false)
end)

addEventHandler("rp:gym:stop", resourceRoot, function()
    if sessions[client] and sessions[client].ready then endSession(client, "stop") end
end)
