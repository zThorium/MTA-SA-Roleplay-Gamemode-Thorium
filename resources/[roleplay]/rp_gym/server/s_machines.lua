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

----------------------------------------------------------------
-- Objetos en las manos (barra del press, mancuernas): pegados al hueso con bone_attach
----------------------------------------------------------------
local propObjects = {}   -- [player] = { [i] = objeto }

local function destroyProps(player)
    for _, obj in pairs(propObjects[player] or {}) do
        if isElement(obj) then
            exports.bone_attach:detachElementFromBone(obj)
            destroyElement(obj)
        end
    end
    propObjects[player] = nil
end

local function createProps(player, cfg)
    destroyProps(player)
    if not cfg.props then return end
    local list = {}
    local x, y, z = getElementPosition(player)
    for i, p in ipairs(cfg.props) do
        local obj = createObject(p.model, x, y, z)
        if obj then
            setElementCollisionsEnabled(obj, false)
            setElementInterior(obj, getElementInterior(player))
            setElementDimension(obj, getElementDimension(player))
            exports.bone_attach:attachElementToBone(obj, player, p.bone, p.off[1], p.off[2], p.off[3], p.off[4], p.off[5], p.off[6])
            list[i] = obj
        end
    end
    propObjects[player] = list
end

-- /ajustarprop: cambia el desplazamiento de un objeto de mano (tambien en las sesiones en curso)
function gymSetProp(kind, index, off)
    local cfg = GYM_KINDS[kind]
    local p = cfg and cfg.props and cfg.props[index]
    if not p then return false end
    p.off = off
    for player, list in pairs(propObjects) do
        local s = gymSessionOf(player)
        if s and s.kind == kind and isElement(list[index]) then
            exports.bone_attach:setElementBonePositionOffset(list[index], off[1], off[2], off[3])
            exports.bone_attach:setElementBoneRotationOffset(list[index], off[4], off[5], off[6])
        end
    end
    return true
end

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
    -- seat = { dx, dy, dz, giro }: desplazamiento de la maquina respecto al personaje (ver GYM_KINDS)
    local s = cfg.seat or { 0, 0, 0, 0 }
    local a = math.rad(row.rotation)
    local ox = s[1] * math.cos(a) - s[2] * math.sin(a)
    local oy = s[1] * math.sin(a) + s[2] * math.cos(a)
    local obj = createObject(cfg.model, row.x + ox, row.y + oy, row.z + cfg.zOffset + s[3], 0, 0, row.rotation + s[4])
    local col = createColSphere(row.x, row.y, row.z, GYM.TRIGGER_RADIUS)
    -- Objetos extra (p. ej. la segunda mancuerna del par), desplazados respecto al principal segun el rumbo
    local extras = {}
    for _, e in ipairs(cfg.extra or {}) do
        local ex = (s[1] + (e.dx or 0)) * math.cos(a) - (s[2] + (e.dy or 0)) * math.sin(a)
        local ey = (s[1] + (e.dx or 0)) * math.sin(a) + (s[2] + (e.dy or 0)) * math.cos(a)
        extras[#extras + 1] = createObject(e.model, row.x + ex, row.y + ey, row.z + cfg.zOffset + s[3] + (e.dz or 0),
            e.rx or 0, e.ry or 0, row.rotation + s[4] + (e.rz or 0))
    end
    for _, el in ipairs({ obj, col, unpack(extras) }) do
        setElementInterior(el, row.interior)
        setElementDimension(el, row.dimension)
    end
    machines[row.id] = { row = row, cfg = cfg, object = obj, col = col, extras = extras }

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

-- Las pesas del suelo desaparecen mientras se entrena (las lleva el personaje en las manos)
function setMachineVisible(id, visible)
    local m = machines[id]
    if not m or not m.cfg.extra then return end
    local alpha = visible and 255 or 0
    if m.cfg.hideMain and isElement(m.object) then setElementAlpha(m.object, alpha) end
    for _, el in ipairs(m.extras or {}) do if isElement(el) then setElementAlpha(el, alpha) end end
end

-- /ajustarextra: cambia un objeto extra de todas las maquinas de ese tipo y las redibuja
function gymSetExtra(kind, index, e)
    local cfg = GYM_KINDS[kind]
    if not (cfg and cfg.extra and cfg.extra[index]) then return false end
    for k, v in pairs(e) do cfg.extra[index][k] = v end
    local rows = {}
    for _, m in pairs(machines) do
        if m.row.kind == kind then rows[#rows + 1] = m.row end
    end
    for _, row in ipairs(rows) do
        gymDestroyMachine(row.id)
        gymSpawnMachine(row)
    end
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
    for _, el in ipairs(m.extras or {}) do if isElement(el) then destroyElement(el) end end
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
            if s.level <= entry[1] then return { entry[3] or "GYMNASIUM", entry[2] } end
        end
        local last = cfg.loops[#cfg.loops]
        return { last[3] or "GYMNASIUM", last[2] }
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
    destroyProps(player)
    setMachineVisible(s.id, true)
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

    -- Con el recurso parandose el cliente ya no tiene el evento registrado (el cliente se limpia solo)
    if reason ~= "stop" then triggerClientEvent(player, "rp:gym:state", resourceRoot, false) end
    if silent then
        setElementFrozen(player, false)
        setPedAnimation(player)
        removeElementData(player, "rp:gym")
        return
    end
    leaving[player] = true
    playAnim(player, (reason == "fall") and s.cfg.fall or s.cfg.getoff, false, false)
    setTimer(function()
        leaving[player] = nil
        if isElement(player) then
            setElementFrozen(player, false)
            setPedAnimation(player)
            removeElementData(player, "rp:gym")
            -- Sigue dentro de la zona: el aviso "Pulsa E" no volveria a salir hasta salir y entrar
            local m = machines[s.id]
            if m and isElement(m.col) and isElementWithinColShape(player, m.col) then
                gymNear(player, "machine", s.id, m.cfg.label, m.cfg.weights)
            end
        end
    end, s.cfg.getoffMs or GYM.GETOFF_MS, 1)
end
function gymEndSession(player, reason, silent) endSession(player, reason, silent) end
function gymSessionOf(player) return sessions[player] end

for _, event in ipairs({ "onPlayerQuit", "onPlayerWasted", "rp:onCharacterLogout" }) do
    addEventHandler(event, root, function() endSession(source, "quit", true) end)
end
addEventHandler("onPlayerQuit", root, function()
    leaving[source], nearTarget[source] = nil, nil
end)

----------------------------------------------------------------
-- Bucle de la sesion
----------------------------------------------------------------
local tickInner

-- Los errores de script no llegan a ningun log (scriptdebugloglevel 0): se capturan y van a server.log
-- OJO: MTA copia las tablas que se pasan a un temporizador, asi que se pasa el jugador y se busca la sesion real
local function tick(player)
    local s = sessions[player]
    if not s then return end
    local ok, err = pcall(tickInner, s)
    if not ok then outputServerLog("[rp_gym] ERROR en tick: " .. tostring(err)) end
end

function tickInner(s)
    local player = s.player
    local now = getTickCount()
    local dt = math.min((now - s.last) / 1000, 1)
    s.last = now

    -- Con los controles libres, A/D podrian girar o desplazar al personaje: se reancla a la maquina
    local ok, err = pcall(function()
        local px, py, pz = getElementPosition(player)
        local m = machines[s.id]
        if m and getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z) > 0.6 then
            setElementPosition(player, m.row.x, m.row.y, m.row.z)
        end
        if m then setElementRotation(player, 0, 0, m.row.rotation) end
    end)
    if not ok then outputServerLog("[rp_gym] error al reanclar: " .. tostring(err)) end

    if not s.ready then
        if now >= s.readyAt then
            s.ready, s.idleSince = true, now
            local anim = loopAnimFor(s)
            outputServerLog(("[rp_gym] sesion lista: %s %s/%s"):format(getPlayerName(player), tostring(anim[1]), tostring(anim[2])))
            playAnim(player, anim, s.cfg.levels ~= nil or s.kind == "dumbbells", s.cfg.levels == nil)
            createProps(player, s.cfg)
            setMachineVisible(s.id, false)
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
    if not m or not gymCharacter(player) then return end
    -- Antes se ignoraba en silencio; ahora se avisa de por que no empieza
    if sessions[player] then return gymNotify(player, "Ya estas entrenando: pulsa Retroceso para bajarte primero.", "warning") end
    if leaving[player] then return gymNotify(player, "Espera a terminar de bajarte de la maquina.", "warning") end
    if gymInFight[player] then return end
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
        last = now, readyAt = now + (cfg.getonMs or GYM.GETON_MS), lockUntil = 0, idleSince = now, lastPulse = 0, lastSide = 0,
        lastLevel = 0, ready = false, tired = false, flip = false,
    }
    sessions[player] = s
    busy[machineId] = player
    -- rp_heads usa un metodo de cabeza mas robusto en poses agachadas o tumbadas (evita que gire 180 grados)
    setElementData(player, "rp:gym", true)
    outputServerLog(("[rp_gym] sesion iniciada: %s en %s (%d)"):format(getPlayerName(player), m.row.kind, machineId))
    gymNear(player, false)

    setElementPosition(player, m.row.x, m.row.y, m.row.z)
    setElementRotation(player, 0, 0, m.row.rotation)
    -- No congelar: un jugador congelado no reproduce animaciones (el cliente bloquea los controles)
    playAnim(player, cfg.geton, false, true)
    s.timer = setTimer(tick, GYM.TICK_MS, 0, player)
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

-- El cliente avisa de que no esta reproduciendo la animacion de la sesion: se repite la que toca
addEvent("rp:gym:resync", true)
addEventHandler("rp:gym:resync", resourceRoot, function()
    local s = sessions[client]
    if not s then return end
    local now = getTickCount()
    if now - (s.lastResync or 0) < 1000 then return end
    s.lastResync = now
    if not s.ready then
        playAnim(client, s.cfg.geton, false, true)
    elseif s.cfg.levels then
        playAnim(client, loopAnimFor(s), true, false)
    else
        playAnim(client, loopAnimFor(s), s.kind == "dumbbells", true)
    end
end)

addEventHandler("rp:gym:stop", resourceRoot, function()
    if sessions[client] then endSession(client, "stop_user") end   -- tambien antes de estar "ready": nunca se queda atrapado
end)
