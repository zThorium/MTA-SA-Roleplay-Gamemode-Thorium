--[[
    rp_emergency / s_emergency.lua

    Emergencias 911. /911 abre un menu con Policia, Bomberos y Ambulancia; cada
    servicio es un procedimiento independiente (hoy solo la ambulancia esta
    implementada, los otros disparan el evento "rp:emergency:onCall").

    Ambulancia (maquina de estados por llamada):
      spawning  -> el cliente del jugador elige un punto de la calle fuera de la vista
      enroute   -> ambulancia IA con conductor y 2 paramedicos va al jugador por la red vial
      working   -> paramedicos bajan, buscan abatidos en SEARCH_RADIUS y los reaniman por orden
                   (o cargan a un muerto en la "camilla")
      transport -> lleva al muerto al hospital mas cercano, lo entrega y se recupera
      leaving   -> los paramedicos vuelven a subir, la ambulancia se va y desaparece

    El servidor es dueno de todo el estado. El cliente "syncer" (el que llamo y,
    durante el traslado, el paciente) solo ejecuta la fisica: conducir y caminar
    a los puntos que el servidor ordena. Si no responde, el servidor teletransporta.

    Comandos:
        /911                    abre el menu de emergencias
        /cancelar911 <jugador>  (admin) cancela la llamada activa de un jugador
]]

local calls = {}        -- [id] = call
local byCaller = {}     -- [player] = call
local claimed = {}      -- [paciente] = call que lo atiende
local cooldown = {}     -- [player] = tick hasta el que no puede llamar
local rate = {}         -- [player] = tick del ultimo evento remoto
local nextId = 0
local activeCount = 0

addEvent("rp:onCharacterLogout", false)
addEvent("rp:emergency:onCall", false)              -- hook: policia/bomberos (source = jugador)
addEvent("rp:emergency:onPatientDelivered", false)  -- hook: paciente entregado en el hospital
addEvent("rp:emergency:revive", false)              -- hook: el sistema de abatidos debe reanimar a source
addEvent("rp:emergency:open", true)
addEvent("rp:emergency:call", true)
addEvent("rp:emergency:spawn", true)
addEvent("rp:emergency:arrived", true)
addEvent("rp:emergency:walked", true)

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function popup(p, t, m, k) exports.rp_notify:popup(p, t, m, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function ok(el) return isElement(el) end

local function limited(player, ms)
    local now = getTickCount()
    if rate[player] and now - rate[player] < (ms or 300) then return true end
    rate[player] = now
    return false
end

-- Posicion relativa al elemento (ox = derecha, oy = delante)
local function offset(el, ox, oy)
    local x, y, z = getElementPosition(el)
    local _, _, rz = getElementRotation(el)
    local r = math.rad(rz)
    return x + ox * math.cos(r) - oy * math.sin(r), y + ox * math.sin(r) + oy * math.cos(r), z
end

local function heading(dx, dy) return -math.deg(math.atan2(dx, dy)) end

local function face(ped, tx, ty)
    local x, y = getElementPosition(ped)
    setElementRotation(ped, 0, 0, heading(tx - x, ty - y))
end

local function dist3(a, b)
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
end

----------------------------------------------------------------
-- Estado de los pacientes (contrato con el sistema de abatidos)
----------------------------------------------------------------
local function isDead(p)
    return isPedDead(p) or getElementData(p, EMERGENCY.DEAD_KEY) == true
end

function isPlayerDowned(p)
    return ok(p) and not isDead(p) and getElementData(p, EMERGENCY.DOWNED_KEY) == true
end

-- Reanima a un jugador. Primero avisa al sistema de abatidos (evento) y despues
-- garantiza un estado coherente aunque ese sistema no exista todavia.
function revivePlayer(p, reason)
    if not ok(p) then return false end
    triggerEvent("rp:emergency:revive", p, reason or "paramedics")
    setElementData(p, EMERGENCY.DOWNED_KEY, false)
    setElementData(p, EMERGENCY.DEAD_KEY, false)
    if isPedDead(p) then
        local x, y, z = getElementPosition(p)
        local _, _, rz = getElementRotation(p)
        spawnPlayer(p, x, y, z, rz, getElementModel(p), getElementInterior(p), getElementDimension(p))
        setCameraTarget(p, p)
    end
    detachElements(p)
    setElementFrozen(p, false)
    toggleAllControls(p, true, true, true)
    setPedAnimation(p)
    if getElementHealth(p) < EMERGENCY.REVIVE_HEALTH then setElementHealth(p, EMERGENCY.REVIVE_HEALTH) end
    return true
end

local function playerValid(p)
    return ok(p) and getElementType(p) == "player" and characterOf(p)
end

----------------------------------------------------------------
-- Ciclo de vida de la llamada
----------------------------------------------------------------
local function killTimers(c)
    for _, k in ipairs({ "stepTimer", "workTimer", "deadline", "hardTimer", "leaveTimer", "spawnTimer" }) do
        if isTimer(c[k]) then killTimer(c[k]) end
        c[k] = nil
    end
end

local function toController(c, event, ...)
    if playerValid(c.syncer) then triggerClientEvent(c.syncer, event, resourceRoot, ...) end
end

local function setController(c, player)
    if not playerValid(player) then return end
    if c.syncer ~= player then toController(c, "rp:emergency:stop", c.id) end
    c.syncer = player
    for _, el in ipairs({ c.vehicle, c.driver, c.medics[1], c.medics[2] }) do
        if ok(el) then setElementSyncer(el, player) end
    end
end

local function releasePatients(c)
    for p, owner in pairs(claimed) do
        if owner == c then
            claimed[p] = nil
            if ok(p) then
                detachElements(p)
                setElementFrozen(p, false)
                toggleAllControls(p, true, true, true)
            end
        end
    end
end

local function destroyCall(c)
    for _, el in ipairs({ c.blip, c.medics[1], c.medics[2], c.driver, c.vehicle }) do
        if ok(el) then destroyElement(el) end
    end
end

-- fade = la ambulancia se desvanece (lo ven todos) en lugar de desaparecer de golpe
local function endCall(c, fade, message)
    if c.ended then return end
    c.ended = true
    killTimers(c)
    releasePatients(c)
    toController(c, "rp:emergency:stop", c.id)
    calls[c.id] = nil
    if byCaller[c.caller] == c then byCaller[c.caller] = nil end
    cooldown[c.caller] = getTickCount() + EMERGENCY.CALL_COOLDOWN * 1000
    activeCount = math.max(0, activeCount - 1)
    if ok(c.caller) and message then popup(c.caller, "911", message, "info") end

    if not fade then return destroyCall(c) end
    local alpha = 255
    setTimer(function()
        alpha = alpha - 25
        if alpha <= 0 then return destroyCall(c) end
        for _, el in ipairs({ c.vehicle, c.driver, c.medics[1], c.medics[2] }) do
            if ok(el) then setElementAlpha(el, alpha) end
        end
    end, 120, 11)
end

----------------------------------------------------------------
-- Movimiento de los paramedicos (el syncer camina, el servidor corrige)
----------------------------------------------------------------
local function finishWalk(c, token)
    if c.ended or c.walkToken ~= token or not c.walkDone then return end
    if isTimer(c.stepTimer) then killTimer(c.stepTimer) end
    local cb = c.walkDone
    c.walkDone = nil
    for _, o in ipairs(c.walkOrders or {}) do
        if ok(o.ped) then
            local x, y, z = getElementPosition(o.ped)
            if getDistanceBetweenPoints3D(x, y, z, o.x, o.y, o.z) > 3.5 then
                setElementPosition(o.ped, o.x, o.y, o.z)      -- teletransporte controlado
            end
            if o.face then face(o.ped, o.face[1], o.face[2]) end
        end
    end
    cb()
end

-- orders = { { ped, x, y, z, face = {x, y} }, ... }; onDone se llama cuando todos llegaron
local function walk(c, orders, onDone)
    c.walkToken = (c.walkToken or 0) + 1
    local token = c.walkToken
    c.walkOrders, c.walkDone = orders, onDone
    local list = {}
    for _, o in ipairs(orders) do
        if not o.keep then setPedAnimation(o.ped) end      -- keep = conserva la animacion (cargando camilla)
        list[#list + 1] = { o.ped, o.x, o.y, o.z }
    end
    toController(c, "rp:emergency:walk", c.id, token, list)
    if isTimer(c.stepTimer) then killTimer(c.stepTimer) end
    c.stepTimer = setTimer(finishWalk, (EMERGENCY.WALK_TIMEOUT + 4) * 1000, 1, c, token)
end

addEventHandler("rp:emergency:walked", resourceRoot, function(callId, token)
    local c = calls[tonumber(callId)]
    if not c or client ~= c.syncer then return end
    finishWalk(c, tonumber(token))
end)

----------------------------------------------------------------
-- Pasos de la ambulancia
----------------------------------------------------------------
local leave, processNext, boardAndLeave

local function sideSpot(c, i)
    -- Costado derecho (lado de la acera), uno delante y otro detras
    return offset(c.vehicle, 2.4, i == 1 and 1.0 or -1.0)
end

local function exitMedics(c)
    for i, m in ipairs(c.medics) do
        if ok(m) then
            removePedFromVehicle(m)
            local x, y, z = sideSpot(c, i)
            setElementPosition(m, x, y, z + 0.2)
        end
    end
end

-- Los paramedicos vuelven al vehiculo, suben y la ambulancia se va
boardAndLeave = function(c)
    if c.ended then return end
    c.state = "boarding"
    setVehicleDoorOpenRatio(c.vehicle, 4, 0, 400)
    setVehicleDoorOpenRatio(c.vehicle, 5, 0, 400)
    local orders = {}
    for i, m in ipairs(c.medics) do
        if ok(m) then
            local x, y, z = sideSpot(c, i)
            orders[#orders + 1] = { ped = m, x = x, y = y, z = z }
        end
    end
    walk(c, orders, function()
        if c.ended then return end
        -- Esperan a que TODOS esten dentro antes de arrancar
        for i, m in ipairs(c.medics) do
            if ok(m) then
                setPedAnimation(m)
                warpPedIntoVehicle(m, c.vehicle, i)
            end
        end
        leave(c)
    end)
end

leave = function(c)
    if c.ended then return end
    c.state = "leaving"
    local patient = c.patient
    if ok(c.vehicle) then setVehicleDoorOpenRatio(c.vehicle, 4, 0, 400) end
    if patient and playerValid(c.caller) and patient ~= c.syncer then setController(c, c.caller) end
    toController(c, "rp:emergency:drive", c.id, c.vehicle, c.driver, "leave")
    c.leaveTimer = setTimer(endCall, EMERGENCY.LEAVE_TIME * 1000, 1, c, true)
end

local function lookAround(c, onDone)
    -- No hay abatidos: miran alrededor un momento y regresan
    local cx, cy = getElementPosition(c.caller)
    for _, m in ipairs(c.medics) do
        if ok(m) then
            face(m, cx, cy)
            setPedAnimation(m, "COP_AMBIENT", "Coplook_loop", EMERGENCY.LOOK_TIME * 1000, false, false, false, false)
        end
    end
    c.workTimer = setTimer(function() if not c.ended then onDone() end end, EMERGENCY.LOOK_TIME * 1000, 1)
end

local function scanPatients(c)
    local vx, vy, vz = getElementPosition(c.vehicle)
    local downed, dead = {}, nil
    for _, p in ipairs(getElementsByType("player")) do
        if playerValid(p) and not claimed[p] and getElementDimension(p) == 0 and getElementInterior(p) == 0 then
            local d = getDistanceBetweenPoints3D(vx, vy, vz, getElementPosition(p))
            if d <= EMERGENCY.SEARCH_RADIUS then
                if isDead(p) then
                    if not dead or d < dead.d then dead = { p = p, d = d } end
                elseif isPlayerDowned(p) then
                    downed[#downed + 1] = { p = p, d = d }
                end
            end
        end
    end
    table.sort(downed, function(a, b) return a.d < b.d end)
    local queue = {}
    for _, e in ipairs(downed) do
        if #queue < EMERGENCY.MAX_PATIENTS then queue[#queue + 1] = e.p end
    end
    if dead and #queue < EMERGENCY.MAX_PATIENTS then queue[#queue + 1] = dead.p end   -- el muerto va el ultimo
    for _, p in ipairs(queue) do claimed[p] = c end
    return queue
end

-- Posiciones de los dos paramedicos junto a un paciente
local function aroundPatient(c, patient)
    local px, py, pz = getElementPosition(patient)
    local orders = {}
    for i, m in ipairs(c.medics) do
        if ok(m) then
            local side = i == 1 and 1 or -1
            orders[#orders + 1] = { ped = m, x = px + side * 0.9, y = py + 0.2, z = pz, face = { px, py } }
        end
    end
    return orders
end

local function startRevive(c, patient)
    local m1, m2 = c.medics[1], c.medics[2]
    if ok(m1) then setPedAnimation(m1, "MEDIC", "CPR", -1, true, false, false, false) end
    if ok(m2) then setPedAnimation(m2, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false) end
    popup(patient, "911", "Los paramedicos te estan atendiendo.", "info")
    c.workTimer = setTimer(function()
        if c.ended then return end
        for _, m in ipairs(c.medics) do if ok(m) then setPedAnimation(m) end end
        if playerValid(patient) and claimed[patient] == c then
            local near = ok(m1) and dist3(m1, patient) < 6
            if near and not isDead(patient) then
                revivePlayer(patient, "paramedics")
                popup(patient, "911", "Te han reanimado los paramedicos.", "success")
            elseif near and isDead(patient) then
                table.insert(c.queue, 1, patient)            -- murio durante la atencion: se traslada
                return processNext(c)
            end
        end
        claimed[patient] = nil
        processNext(c)
    end, EMERGENCY.REVIVE_TIME * 1000, 1)
end

-- Hospital mas cercano a un punto
local function nearestHospital(x, y)
    local best, bestD = nil, math.huge
    for _, h in ipairs(EMERGENCY.HOSPITALS) do
        local d = getDistanceBetweenPoints2D(x, y, h.road[1], h.road[2])
        if d < bestD then best, bestD = h, d end
    end
    return best
end

local function finishDelivery(c, patient, hospital)
    if c.ended then return end
    if playerValid(patient) then
        detachElements(patient)
        triggerEvent("rp:emergency:onPatientDelivered", patient, hospital.name)
        local bed = hospital.bed
        if isPedDead(patient) then
            spawnPlayer(patient, bed[1], bed[2], bed[3], bed[4], getElementModel(patient), bed[5], bed[6])
        else
            setElementPosition(patient, bed[1], bed[2], bed[3])
            setElementRotation(patient, 0, 0, bed[4])
            setElementInterior(patient, bed[5])
            setElementDimension(patient, bed[6])
        end
        revivePlayer(patient, "hospital")
        setElementHealth(patient, EMERGENCY.TREAT_HEALTH)
        setCameraTarget(patient, patient)
        fadeCamera(patient, true, 1.5)
        popup(patient, hospital.name, "Has sido atendido por el personal medico.", "success")
        claimed[patient] = nil
    end
    c.patient = nil
    -- Los paramedicos vuelven a la ambulancia (que sigue en la puerta del hospital)
    boardAndLeave(c)
end

local function arriveAtHospital(c)
    local hospital = c.hospital
    c.state = "working"
    local patient = c.patient
    exitMedics(c)
    if not playerValid(patient) then c.patient = nil return boardAndLeave(c) end
    removePedFromVehicle(patient)
    local m1 = c.medics[1]
    setPedAnimation(m1, "CARRY", "crry_prtial", -1, true, true, false, false)
    local ox, oy, oz, rx, ry, rz = unpack(EMERGENCY.CARRY_OFFSET)
    attachElements(patient, m1, ox, oy, oz, rx, ry, rz)
    setPedAnimation(patient, "CRACK", "crckdeth2", -1, true, false, false, true)
    local d = hospital.door
    walk(c, {
        { ped = m1, x = d[1], y = d[2], z = d[3], keep = true },
        { ped = c.medics[2], x = d[1] + 1, y = d[2], z = d[3] },
    }, function()
        if c.ended then return end
        detachElements(patient)
        setPedAnimation(m1)
        if playerValid(patient) then fadeCamera(patient, false, 1.5) end
        c.workTimer = setTimer(finishDelivery, EMERGENCY.TREAT_TIME * 1000, 1, c, patient, hospital)
    end)
end

-- Carga al muerto: camilla simulada (el paciente va pegado al paramedico) y sube a la ambulancia
local function loadAndTransport(c, patient)
    local m1, m2 = c.medics[1], c.medics[2]
    c.patient = patient
    -- Un muerto de MTA no tiene cuerpo: se le da uno en el sitio para poder llevarlo
    if isPedDead(patient) then
        local x, y, z = getElementPosition(patient)
        local _, _, rz = getElementRotation(patient)
        spawnPlayer(patient, x, y, z, rz, getElementModel(patient), getElementInterior(patient), getElementDimension(patient))
        setCameraTarget(patient, patient)
    end
    toggleAllControls(patient, false, true, false)
    setElementHealth(patient, math.max(1, getElementHealth(patient)))
    setPedAnimation(patient, "CRACK", "crckdeth2", -1, true, false, false, true)
    setPedAnimation(m1, "CARRY", "liftup", EMERGENCY.LOAD_TIME * 1000, false, false, false, false)
    setPedAnimation(m2, "CARRY", "liftup", EMERGENCY.LOAD_TIME * 1000, false, false, false, false)
    popup(patient, "911", "Los paramedicos te colocan en la camilla.", "info")
    setVehicleDoorOpenRatio(c.vehicle, 4, 1, 800)
    setVehicleDoorOpenRatio(c.vehicle, 5, 1, 800)

    c.workTimer = setTimer(function()
        if c.ended then return end
        if not playerValid(patient) then c.patient = nil return processNext(c) end
        local ox, oy, oz, rx, ry, rz = unpack(EMERGENCY.CARRY_OFFSET)
        attachElements(patient, m1, ox, oy, oz, rx, ry, rz)
        setPedAnimation(m1, "CARRY", "crry_prtial", -1, true, true, false, false)
        setPedAnimation(m2, "CARRY", "crry_prtial", -1, true, true, false, false)
        local bx, by, bz = offset(c.vehicle, 0, -3.6)
        local sx, sy = offset(c.vehicle, 1.1, -3.6)
        walk(c, {
            { ped = m1, x = bx, y = by, z = bz, keep = true },
            { ped = m2, x = sx, y = sy, z = bz, keep = true },
        }, function()
            if c.ended then return end
            detachElements(patient)
            setPedAnimation(m1) setPedAnimation(m2)
            if not playerValid(patient) then c.patient = nil return boardAndLeave(c) end
            -- El paciente va dentro; mientras dure el traslado el es el syncer (la ambulancia se aleja del que llamo)
            warpPedIntoVehicle(patient, c.vehicle, EMERGENCY.PATIENT_SEAT)
            setPedAnimation(patient)
            warpPedIntoVehicle(m1, c.vehicle, 1)
            warpPedIntoVehicle(m2, c.vehicle, 2)
            setVehicleDoorOpenRatio(c.vehicle, 4, 0, 600)
            setVehicleDoorOpenRatio(c.vehicle, 5, 0, 600)
            c.state = "transport"
            local vx, vy = getElementPosition(c.vehicle)
            c.hospital = nearestHospital(vx, vy)
            setController(c, patient)
            popup(patient, "911", "Te trasladan al hospital " .. c.hospital.name .. ".", "info")
            toController(c, "rp:emergency:drive", c.id, c.vehicle, c.driver, "hospital", c.hospital.road[1], c.hospital.road[2])
            c.deadline = setTimer(endCall, EMERGENCY.ENROUTE_TIMEOUT * 1000, 1, c, true, "La ambulancia no pudo llegar al hospital.")
        end)
    end, EMERGENCY.LOAD_TIME * 1000, 1)
end

processNext = function(c)
    if c.ended then return end
    local patient = table.remove(c.queue, 1)
    if not patient then return boardAndLeave(c) end
    if not playerValid(patient) or claimed[patient] ~= c or getElementDimension(patient) ~= 0 then
        claimed[patient or false] = nil
        return processNext(c)
    end
    local dead = isDead(patient)
    walk(c, aroundPatient(c, patient), function()
        if c.ended then return end
        if not playerValid(patient) then return processNext(c) end
        if dead or isDead(patient) then
            loadAndTransport(c, patient)
        else
            startRevive(c, patient)
        end
    end)
end

-- La ambulancia llego a donde esta el jugador
local function onArrivedAtScene(c)
    c.state = "working"
    if isTimer(c.deadline) then killTimer(c.deadline) end
    c.deadline = nil
    popup(c.caller, "911", "La ambulancia ha llegado.", "success")
    exitMedics(c)
    c.queue = scanPatients(c)
    if #c.queue > 0 then return processNext(c) end
    -- Sin abatidos cerca: miran, vuelven a escanear una vez y se van
    local cx, cy, cz = getElementPosition(c.caller)
    local orders = {}
    for i, m in ipairs(c.medics) do
        local x, y, z = getElementPosition(m)
        orders[#orders + 1] = { ped = m, x = x + (cx - x) * 0.25, y = y + (cy - y) * 0.25, z = z, face = { cx, cy } }
    end
    walk(c, orders, function()
        lookAround(c, function()
            c.queue = scanPatients(c)
            if #c.queue > 0 then return processNext(c) end
            popup(c.caller, "911", "Los paramedicos no encontraron a nadie que atender.", "info")
            boardAndLeave(c)
        end)
    end)
end

addEventHandler("rp:emergency:arrived", resourceRoot, function(callId, mode)
    local c = calls[tonumber(callId)]
    if not c or client ~= c.syncer or c.ended then return end
    if mode == "target" and c.state == "enroute" then
        if not ok(c.caller) or dist3(c.vehicle, c.caller) > EMERGENCY.ARRIVE_MAX_DIST then return end
        onArrivedAtScene(c)
    elseif mode == "hospital" and c.state == "transport" and c.hospital then
        local h = c.hospital.road
        local vx, vy = getElementPosition(c.vehicle)
        if getDistanceBetweenPoints2D(vx, vy, h[1], h[2]) > 80 then return end
        if isTimer(c.deadline) then killTimer(c.deadline) end
        c.deadline = nil
        arriveAtHospital(c)
    end
end)

----------------------------------------------------------------
-- Despacho
----------------------------------------------------------------
local function dispatchAmbulance(player)
    if byCaller[player] then return notify(player, "Ya tienes una ambulancia en camino.", "warning") end
    if cooldown[player] and getTickCount() < cooldown[player] then
        return notify(player, "Espera un momento antes de volver a llamar al 911.", "warning")
    end
    if activeCount >= EMERGENCY.MAX_ACTIVE_CALLS then
        return notify(player, "Todas las unidades estan ocupadas. Intentalo en unos minutos.", "warning")
    end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        return notify(player, "La ambulancia no puede entrar: sal al exterior para llamarla.", "warning")
    end
    if isPedInVehicle(player) then
        return notify(player, "Detente fuera del vehiculo para llamar a la ambulancia.", "warning")
    end

    nextId = nextId + 1
    local c = { id = nextId, caller = player, syncer = player, state = "spawning", medics = {}, queue = {} }
    c.x, c.y, c.z = getElementPosition(player)
    c.interior, c.dimension = getElementInterior(player), getElementDimension(player)
    calls[c.id], byCaller[player] = c, c
    activeCount = activeCount + 1
    c.hardTimer = setTimer(endCall, 20 * 60000, 1, c, true)
    c.spawnTimer = setTimer(function()
        if not c.ended and c.state == "spawning" then endCall(c, false, "No hay ambulancias disponibles ahora.") end
    end, EMERGENCY.SPAWN_REQUEST_TIMEOUT * 1000, 1)

    triggerClientEvent(player, "rp:emergency:spawnRequest", resourceRoot, c.id)
    popup(player, "911", "Tu llamada fue recibida. Buscando una ambulancia...", "info")
end

addEventHandler("rp:emergency:spawn", resourceRoot, function(callId, x, y, z, rot)
    local player = client
    local c = calls[tonumber(callId)]
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot) or 0
    if not c or c.caller ~= player or c.state ~= "spawning" or not (x and y and z) then return end
    local d = getDistanceBetweenPoints2D(c.x, c.y, x, y)
    if d < 40 or d > EMERGENCY.SPAWN_MAX + 150 then return end
    if isTimer(c.spawnTimer) then killTimer(c.spawnTimer) end

    local vehicle = createVehicle(EMERGENCY.AMBULANCE_MODEL, x, y, z + 0.6, 0, 0, rot, "LSMD")
    if not vehicle then return endCall(c, false, "No se pudo enviar la ambulancia.") end
    c.vehicle = vehicle
    setVehicleDamageProof(vehicle, true)
    setVehicleEngineState(vehicle, true)
    setVehicleLocked(vehicle, true)
    setVehicleSirensOn(vehicle, true)
    setElementData(vehicle, "rp:emergency", c.id)

    local skins = EMERGENCY.PARAMEDIC_SKINS
    local function newPed(seat)
        local ped = createPed(skins[math.random(#skins)], x, y, z + 1)
        warpPedIntoVehicle(ped, vehicle, seat)
        setElementData(ped, "rp:emergency", c.id)
        return ped
    end
    c.driver = newPed(0)
    c.medics = { newPed(1), newPed(2) }
    setController(c, player)

    c.blip = createBlipAttachedTo(vehicle, 22, 2, 255, 255, 255, 255, 0, 99999, player)
    c.state = "enroute"
    c.deadline = setTimer(endCall, EMERGENCY.ENROUTE_TIMEOUT * 1000, 1, c, true,
        "La ambulancia no pudo llegar hasta ti. Vuelve a llamar.")
    triggerClientEvent(player, "rp:emergency:drive", resourceRoot, c.id, vehicle, c.driver, "target", c.x, c.y)
    popup(player, "911", "Una ambulancia va en camino. Esperala fuera, en la calle.", "success")
end)

-- Nadie roba ni sube a la ambulancia fuera de la secuencia
addEventHandler("onVehicleStartEnter", root, function(player)
    if getElementData(source, "rp:emergency") then cancelEvent() end
end)
addEventHandler("onVehicleStartExit", root, function(player)
    if getElementData(source, "rp:emergency") then cancelEvent() end
end)

----------------------------------------------------------------
-- Menu y llamadas
----------------------------------------------------------------
local VALID_SERVICE = {}
for _, s in ipairs(EMERGENCY.SERVICES) do VALID_SERVICE[s.id] = s end

local function openMenu(player)
    if not characterOf(player) then return end
    if isPedDead(player) or getElementData(player, "rp:downed") then return end   -- abatido (rp_injury)
    triggerClientEvent(player, "rp:emergency:show", resourceRoot, EMERGENCY.SERVICES, byCaller[player] ~= nil)
end

addCommandHandler(EMERGENCY.COMMAND, openMenu)
addEventHandler("rp:emergency:open", resourceRoot, function() if not limited(client, 500) then openMenu(client) end end)

local procedures = {
    ambulance = dispatchAmbulance,
    police = function(player) end,
    fire = function(player) end,
}
-- Policia y bomberos: aun sin unidades; se avisa por evento para que los implementen las facciones
for _, id in ipairs({ "police", "fire" }) do
    procedures[id] = function(player)
        local x, y, z = getElementPosition(player)
        triggerEvent("rp:emergency:onCall", player, id, x, y, z, getElementInterior(player), getElementDimension(player))
        notify(player, ("Tu llamada a %s quedo registrada, pero no hay unidades disponibles todavia."):format(VALID_SERVICE[id].name), "info")
    end
end

addEventHandler("rp:emergency:call", resourceRoot, function(service)
    local player = client
    if limited(player, 800) or type(service) ~= "string" then return end
    if not characterOf(player) or isPedDead(player) or getElementData(player, "rp:downed") then return end
    local s = VALID_SERVICE[service]
    if not s then return end
    procedures[service](player)
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
local function playerGone(player)
    rate[player], cooldown[player] = nil, nil
    claimed[player] = nil
    local mine = byCaller[player]
    if mine then endCall(mine, false) end
    for _, c in pairs(calls) do
        if c.syncer == player and not c.ended then
            if c.patient == player then
                endCall(c, true)
            elseif playerValid(c.caller) and c.caller ~= player then
                setController(c, c.caller)
            else
                endCall(c, true)
            end
        end
        if c.patient == player then c.patient = nil end
    end
end

addEventHandler("onPlayerQuit", root, function() playerGone(source) end)
addEventHandler("rp:onCharacterLogout", root, function() playerGone(source) end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, c in pairs(calls) do endCall(c, false) end
end)

addCommandHandler("cancelar911", function(player, _, query)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    if not target then return notify(player, "Uso: /cancelar911 <id o nombre>", "warning") end
    local c = byCaller[target]
    if not c then return notify(player, "Ese jugador no tiene una llamada activa.", "warning") end
    endCall(c, true, "Un administrador cancelo la ambulancia.")
    notify(player, ("Llamada de %s cancelada."):format((getPlayerName(target):gsub("_", " "))), "success")
end)

function getActiveCall(player)
    local c = byCaller[player]
    return c and c.state or false
end
