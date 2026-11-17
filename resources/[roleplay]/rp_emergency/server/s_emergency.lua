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

    Tambien se llama desde la app Telefono de rp_phone (export callService).

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

local function pick(list) return list[math.random(#list)] end

-- Registro de cada llamada en server.log (para diagnosticar ambulancias que no llegan)
local function log(c, text)
    outputServerLog(("[rp_emergency] llamada #%d (%s): %s"):format(c.id,
        ok(c.caller) and getPlayerName(c.caller) or "?", text))
end

-- Globo de texto de rol sobre un paramedico (kind: "say", "me" o "radio")
local function say(c, ped, text, kind, ms)
    if not ok(ped) then return end
    local x, y, z = getElementPosition(ped)
    local name = c.names and c.names[ped] or "Paramedico"
    for _, p in ipairs(getElementsWithinRange(x, y, z, 60, "player")) do
        triggerClientEvent(p, "rp:emergency:say", resourceRoot, ped, text, kind or "say", ms or 4000, name)
    end
end

local function anim(ped, block, name, loop)
    if not ok(ped) then return end
    if block then setPedAnimation(ped, block, name, -1, loop ~= false, false, false, loop == false)
    else setPedAnimation(ped) end
end

-- Guion de rol: steps = { { ms, fn }, ... }. Ejecuta fn y espera ms antes del siguiente.
-- Si check() deja de cumplirse se corta y llama a onAbort.
local function runScript(c, steps, check, onAbort, onDone)
    local i = 0
    local function nextStep()
        if c.ended then return end
        if check and not check() then return onAbort and onAbort() end
        i = i + 1
        local step = steps[i]
        if not step then return onDone and onDone() end
        if step[2] then step[2]() end
        c.workTimer = setTimer(nextStep, step[1], 1)
    end
    nextStep()
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
    -- persist = true: sin el, MTA quita el control en cuanto el jugador esta a mas de
    -- 100 m de un ped (la ambulancia aparece a 120-200 m) y la ambulancia no se movia nunca.
    for _, el in ipairs({ c.vehicle, c.driver, c.medics[1], c.medics[2] }) do
        if ok(el) then setElementSyncer(el, player, true) end
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
    log(c, "termina en estado " .. tostring(c.state) .. (message and (" (" .. message .. ")") or ""))
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
local leave, processNext, boardAndLeave, searchScene

-- Puerta de cada paramedico: 1 = copiloto (puerta delantera derecha), 2 = puertas traseras
local function sideSpot(c, i)
    if i == 1 then return offset(c.vehicle, 1.9, 0.9) end
    return offset(c.vehicle, 0.5, -4.4)
end

local function openDoors(c, open)
    if not ok(c.vehicle) then return end
    local r = open and 1 or 0
    setVehicleDoorOpenRatio(c.vehicle, 3, r, 500)
    setVehicleDoorOpenRatio(c.vehicle, 4, r, 700)
    setVehicleDoorOpenRatio(c.vehicle, 5, r, 700)
end

-- Bajan con la animacion de salir del vehiculo (uno por la puerta, otro por atras)
local function exitMedics(c)
    local _, _, rz = getElementRotation(c.vehicle)
    for i, m in ipairs(c.medics) do
        if ok(m) then
            removePedFromVehicle(m)
            local x, y, z = sideSpot(c, i)
            setElementPosition(m, x, y, z + 0.2)
            setElementRotation(m, 0, 0, i == 1 and rz - 90 or rz + 180)
            setPedAnimation(m, "PED", "CAR_getout_RHS", 1100, false, false, false, false)
        end
    end
end

-- Los paramedicos vuelven al vehiculo, suben y la ambulancia se va
boardAndLeave = function(c)
    if c.ended then return end
    c.state = "boarding"
    say(c, c.medics[2], "recoge el equipo y lo guarda en la ambulancia.", "me")
    local orders = {}
    for i, m in ipairs(c.medics) do
        if ok(m) then
            local x, y, z = sideSpot(c, i)
            orders[#orders + 1] = { ped = m, x = x, y = y, z = z }
        end
    end
    walk(c, orders, function()
        if c.ended then return end
        openDoors(c, true)
        for _, m in ipairs(c.medics) do
            if ok(m) then
                face(m, getElementPosition(c.vehicle))
                setPedAnimation(m, "PED", "CAR_getin_RHS", 1000, false, false, false, false)
            end
        end
        -- Esperan a que TODOS esten dentro antes de arrancar
        c.workTimer = setTimer(function()
            if c.ended then return end
            for i, m in ipairs(c.medics) do
                if ok(m) then
                    setPedAnimation(m)
                    warpPedIntoVehicle(m, c.vehicle, i)
                end
            end
            openDoors(c, false)
            say(c, c.driver, pick({ "Central, unidad " .. c.unit .. " libre, regresamos a base.",
                "Central, aqui " .. c.unit .. ", servicio terminado. Volvemos." }), "radio")
            c.workTimer = setTimer(leave, 1500, 1, c)
        end, 1000, 1)
    end)
end

leave = function(c)
    if c.ended then return end
    c.state = "leaving"
    -- Quien llamo ya puede pedir otra ambulancia mientras esta se va
    if byCaller[c.caller] == c then byCaller[c.caller] = nil end
    cooldown[c.caller] = getTickCount() + EMERGENCY.CALL_COOLDOWN * 1000
    local patient = c.patient
    if ok(c.vehicle) then
        openDoors(c, false)
        setVehicleSirensOn(c.vehicle, false)
    end
    if patient and playerValid(c.caller) and patient ~= c.syncer then setController(c, c.caller) end
    toController(c, "rp:emergency:drive", c.id, c.vehicle, c.driver, "leave")
    c.leaveTimer = setTimer(endCall, EMERGENCY.LEAVE_TIME * 1000, 1, c, true)
end

local function lookAround(c, onDone)
    -- No hay abatidos: miran alrededor un momento y regresan
    local cx, cy = getElementPosition(c.caller)
    say(c, c.medics[1], pick(EMERGENCY.LINES.callout))
    say(c, c.medics[2], "mira a su alrededor buscando heridos.", "me")
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
    popup(patient, "911", "Los paramedicos te estan atendiendo.", "info")
    local function check()
        return playerValid(patient) and claimed[patient] == c and not isDead(patient) and ok(m1) and dist3(m1, patient) < 6
    end
    local function abort()
        anim(m1) anim(m2)
        if playerValid(patient) and claimed[patient] == c and isDead(patient) then
            table.insert(c.queue, 1, patient)            -- murio durante la atencion: se traslada
        else
            claimed[patient] = nil
        end
        processNext(c)
    end
    runScript(c, {
        { 2800, function()
            anim(m1, "BOMBER", "BOM_Plant_Loop")
            anim(m2, "BOMBER", "BOM_Plant_Loop")
            say(c, m1, pick(EMERGENCY.LINES.assess))
            say(c, m2, "abre el maletin de trauma y saca el desfibrilador.", "me")
        end },
        { 2600, function() say(c, m1, "se arrodilla y le busca el pulso en el cuello.", "me") end },
        { 2600, function()
            say(c, m1, pick(EMERGENCY.LINES.noPulse))
            anim(m1, "MEDIC", "CPR")
        end },
        { 3200, function()
            say(c, m1, "Uno, dos, tres, cuatro, cinco, seis...", "say", 3000)
            say(c, m2, "le abre la camisa y coloca los parches del desfibrilador en el pecho.", "me")
        end },
        { 2800, function()
            say(c, m1, "...veintiocho, veintinueve, treinta.", "say", 2600)
            say(c, m2, "Analizando ritmo... descarga indicada. Cargando.")
        end },
        { 1600, function()
            anim(m1, "BOMBER", "BOM_Plant_Loop")
            say(c, m2, "¡Despejen!", "say", 2000)
        end },
        { 1600, function()
            say(c, m2, "presiona el boton de descarga.", "me")
            triggerClientEvent(patient, "rp:emergency:shock", resourceRoot)
        end },
        { 2400, function()
            say(c, m1, "le vuelve a tomar el pulso.", "me")
        end },
        { 2000, function()
            say(c, m2, pick(EMERGENCY.LINES.pulse))
            revivePlayer(patient, "paramedics")
            popup(patient, "911", "Te han reanimado los paramedicos.", "success")
            anim(m1) anim(m2)
            say(c, m1, "ayuda al paciente a incorporarse lentamente.", "me")
        end },
        { 3500, function() say(c, m1, pick(EMERGENCY.LINES.advice), "say", 5000) end },
    }, check, abort, function()
        claimed[patient] = nil
        processNext(c)
    end)
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
    say(c, c.medics[2], "¡Paciente critico, abran paso! Directo a urgencias.")
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
    say(c, m1, pick(EMERGENCY.LINES.dead))
    say(c, m2, "despliega la camilla y lo sujeta con las correas.", "me")
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
            setVehicleSirensOn(c.vehicle, true)
            say(c, c.driver, "Central, unidad " .. c.unit .. " en traslado a " .. c.hospital.name .. ", paciente critico.", "radio")
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
    say(c, c.medics[1], pick(EMERGENCY.LINES.running), "say", 2500)
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
    say(c, c.driver, "Central, unidad " .. c.unit .. " en el lugar.", "radio")
    log(c, "llego al lugar")
    openDoors(c, true)
    -- Ya saben a quien atender antes de bajar: abren, bajan y salen corriendo
    c.queue = scanPatients(c)
    c.workTimer = setTimer(function()
        if c.ended then return end
        exitMedics(c)
        setController(c, c.syncer)       -- reafirma el control de los peds al bajar del vehiculo
        say(c, c.medics[2], "baja por las puertas traseras con el maletin y el desfibrilador.", "me")
        c.workTimer = setTimer(function()
            if c.ended then return end
            if #c.queue == 0 then c.queue = scanPatients(c) end
            if #c.queue > 0 then return processNext(c) end
            searchScene(c)
        end, 800, 1)
    end, 400, 1)
end

-- Sin abatidos a la vista: se acercan a quien llamo, preguntan, miran y se van
searchScene = function(c)
    if not ok(c.caller) then return boardAndLeave(c) end
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
            say(c, c.medics[1], pick(EMERGENCY.LINES.noone))
            popup(c.caller, "911", "Los paramedicos no encontraron a nadie que atender.", "info")
            boardAndLeave(c)
        end)
    end)
end

addEventHandler("rp:emergency:arrived", resourceRoot, function(callId, mode)
    local c = calls[tonumber(callId)]
    if not c or client ~= c.syncer or c.ended then return end
    if mode == "target" and c.state == "enroute" then
        if not ok(c.caller) or dist3(c.vehicle, c.caller) > EMERGENCY.ARRIVE_MAX_DIST then
            log(c, "aviso de llegada rechazado: la ambulancia esta lejos de quien llamo; sigue hacia el")
            if ok(c.caller) then
                local cx, cy = getElementPosition(c.caller)
                toController(c, "rp:emergency:drive", c.id, c.vehicle, c.driver, "target", cx, cy)
            end
            return
        end
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
-- Devuelve true si se envio la ambulancia (false = rechazada, ya se aviso al jugador)
local function dispatchAmbulance(player)
    if byCaller[player] then notify(player, "Ya hay una ambulancia atendiendo tu llamada.", "warning") return false end
    if cooldown[player] and getTickCount() < cooldown[player] then
        notify(player, "Espera un momento antes de volver a llamar al 911.", "warning") return false
    end
    if activeCount >= EMERGENCY.MAX_ACTIVE_CALLS then
        notify(player, "Todas las unidades estan ocupadas. Intentalo en unos minutos.", "warning") return false
    end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        notify(player, "La ambulancia no puede entrar: sal al exterior para llamarla.", "warning") return false
    end
    if isPedInVehicle(player) then
        notify(player, "Detente fuera del vehiculo para llamar a la ambulancia.", "warning") return false
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

    log(c, "despacho solicitado")
    triggerClientEvent(player, "rp:emergency:spawnRequest", resourceRoot, c.id)
    popup(player, "911", "Tu llamada fue recibida. Buscando una ambulancia...", "info")
    return true
end

addEventHandler("rp:emergency:spawn", resourceRoot, function(callId, x, y, z, rot)
    local player = client
    local c = calls[tonumber(callId)]
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot) or 0
    if not c or c.caller ~= player or c.state ~= "spawning" or not (x and y and z) then return end
    local d = getDistanceBetweenPoints2D(c.x, c.y, x, y)
    if d < 40 or d > EMERGENCY.SPAWN_MAX + 150 then
        return log(c, ("punto de aparicion rechazado a %.0f m"):format(d))
    end
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
    c.unit = tostring(math.random(10, 49))
    local pool = {}
    for _, n in ipairs(EMERGENCY.PARAMEDIC_NAMES) do pool[#pool + 1] = n end
    c.names = {}
    for _, ped in ipairs({ c.driver, c.medics[1], c.medics[2] }) do
        c.names[ped] = "Paramedico " .. table.remove(pool, math.random(#pool))
    end
    setController(c, player)

    c.blip = createBlipAttachedTo(vehicle, 22, 2, 255, 255, 255, 255, 0, 99999, player)
    c.state = "enroute"
    c.deadline = setTimer(endCall, EMERGENCY.ENROUTE_TIMEOUT * 1000, 1, c, true,
        "La ambulancia no pudo llegar hasta ti. Vuelve a llamar.")
    -- Va directo al abatido mas cercano a quien llamo (si hay), si no a quien llamo
    local tx, ty = c.x, c.y
    local best = EMERGENCY.SEARCH_RADIUS
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= player and isPlayerDowned(p) and getElementDimension(p) == 0 then
            local px, py = getElementPosition(p)
            local pd = getDistanceBetweenPoints2D(c.x, c.y, px, py)
            if pd < best then tx, ty, best = px, py, pd end
        end
    end
    log(c, ("ambulancia %s creada a %.0f m, en camino"):format(c.unit, d))
    triggerClientEvent(player, "rp:emergency:drive", resourceRoot, c.id, vehicle, c.driver, "target", tx, ty)
    popup(player, "911", "Central: la ambulancia " .. c.unit .. " va en camino con sirena. Esperala fuera, junto a la calle.", "success")
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
        return true
    end
end

-- Punto unico de entrada de una llamada (menu /911 y app Telefono de rp_phone).
-- Devuelve true si la central acepto la llamada; si la rechaza (cooldown, en un
-- vehiculo, interior...) devuelve false y el aviso al jugador ya lo dio el procedimiento.
function callService(player, service)
    if not playerValid(player) or type(service) ~= "string" or not VALID_SERVICE[service] then return false end
    if isPedDead(player) or getElementData(player, "rp:downed") then return false end   -- abatido (rp_injury)
    return procedures[service](player) == true
end

addEventHandler("rp:emergency:call", resourceRoot, function(service)
    local player = client
    if limited(player, 800) or type(service) ~= "string" then return end
    callService(player, service)
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
