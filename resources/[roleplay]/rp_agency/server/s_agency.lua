--[[
    rp_agency / s_agency.lua

    Agencia de empleo: entrada y salida del edificio, dispensador de turnos,
    cola por orden de llegada, llamada a los mostradores y el tramite en si
    (DNI o trabajo). La emision del DNI esta en s_dni.lua.

    Flujo:
      1. El jugador entra (E en la puerta del Ayuntamiento) y saca un ticket en
         el dispensador eligiendo motivo: DNI (D-xx) o trabajo (T-xx).
      2. La cola se atiende por orden. Cuando un mostrador queda libre llama al
         primero; el jugador tiene AGENCY.CALL_TIMEOUT s para sentarse.
      3. Al llegar al mostrador empieza el tramite (cinematica en el cliente).
         El servidor guarda la sesion y valida cada paso (tiempos minimos,
         que siga sentado en su mostrador, dinero, inventario).
      4. Si sale del edificio, muere o se desconecta con ticket, lo pierde.

    Contrato con rp_jobs (opcional): getJobList, setPlayerJob, getPlayerJob,
    showJobLocation. Sin rp_jobs se usa AGENCY.FALLBACK_JOBS y el trabajo solo
    queda en el element data "rp:job" (no persistente). Ver docs/AGENCIA.md.

    Comandos:
        /agenciacola            (admin) estado de la cola y mostradores
        /agenciareset           (admin) vacia la cola y libera los mostradores
]]

local queue = {}      -- lista ordenada de tickets en espera: { player, number, reason, code, takenAt }
local tickets = {}    -- [player] = ticket (en espera, llamado o atendiendose)
local counters = {}   -- [i] = { state = "free"|"calling"|"busy", ticket, since, col, lastCode }
local lastTicketAt = {}
local nextNumber = 0
local nextCallAt = 0

addEvent("rp:onCharacterLogout", false)
addEvent("rp:agency:door", true)
addEvent("rp:agency:takeTicket", true)
addEvent("rp:agency:jobsRequest", true)
addEvent("rp:agency:jobTake", true)
addEvent("rp:agency:switch", true)
addEvent("rp:agency:leave", true)

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function now() return getTickCount() end

local function isInside(player)
    return isElement(player) and getElementInterior(player) == AGENCY.INTERIOR
        and getElementDimension(player) == AGENCY.DIMENSION
end

local function distanceTo(player, x, y, z)
    local px, py, pz = getElementPosition(player)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z)
end

local function playersInside()
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if isInside(p) then list[#list + 1] = p end
    end
    return list
end

----------------------------------------------------------------
-- Estado para los HUD (todos los que estan dentro)
----------------------------------------------------------------
local function positionInQueue(ticket)
    for i, t in ipairs(queue) do
        if t == ticket then return i end
    end
    return nil
end

local function broadcast()
    local serving = {}
    for i, c in ipairs(counters) do
        serving[i] = { name = AGENCY.COUNTERS[i].name, code = c.lastCode or "--", state = c.state }
    end
    for _, p in ipairs(playersInside()) do
        local t = tickets[p]
        local mine = nil
        if t then
            mine = { code = t.code, reason = t.reason, ahead = (positionInQueue(t) or 1) - 1,
                     counter = t.counter, state = t.state }
        end
        triggerClientEvent(p, "rp:agency:state", resourceRoot, serving, #queue, mine)
    end
end

----------------------------------------------------------------
-- Cola
----------------------------------------------------------------
local function removeFromQueue(ticket)
    for i, t in ipairs(queue) do
        if t == ticket then table.remove(queue, i) return end
    end
end

local releaseCounter -- forward

-- Quita el ticket del jugador (salio, murio, no se presento, termino)
local function dropTicket(player, reason)
    local t = tickets[player]
    if not t then return end
    tickets[player] = nil
    removeFromQueue(t)
    if t.counter and counters[t.counter] and counters[t.counter].ticket == t then
        releaseCounter(t.counter)
    end
    if isElement(player) then
        triggerClientEvent(player, "rp:agency:ticketLost", resourceRoot, reason or "")
    end
    broadcast()
end

local function callNext()
    if now() < nextCallAt then return end
    for i, c in ipairs(counters) do
        if c.state == "free" and #queue > 0 then
            local t = table.remove(queue, 1)
            if isElement(t.player) then
                c.state, c.ticket, c.since, c.lastCode = "calling", t, now(), t.code
                t.state, t.counter, t.calledAt = "called", i, now()
                local pts = agencyCounterPoints(i)
                triggerClientEvent(t.player, "rp:agency:called", resourceRoot, i, AGENCY.COUNTERS[i].name, t.code, pts.seat)
                -- El resto oye el aviso de turno y ve el numero nuevo
                for _, p in ipairs(playersInside()) do
                    if p ~= t.player then triggerClientEvent(p, "rp:agency:chime", resourceRoot, t.code, AGENCY.COUNTERS[i].name) end
                end
                nextCallAt = now() + 1500
            end
        end
    end
    broadcast()
end

function releaseCounter(i)
    local c = counters[i]
    if not c then return end
    c.state, c.ticket, c.since = "free", nil, now()
    nextCallAt = now() + AGENCY.NEXT_DELAY * 1000
end

----------------------------------------------------------------
-- Puertas
----------------------------------------------------------------
local function exitPoint()
    local x, y = agencyPoint(AGENCY.EXIT_OFFSET.ox, AGENCY.EXIT_OFFSET.oy)
    return x, y, AGENCY.ORIGIN.z
end

addEventHandler("rp:agency:door", resourceRoot, function(confirmLeave)
    local player = client
    if not characterOf(player) or getElementData(player, "rp:downed") then return end
    if isPedInVehicle(player) then return end

    if isInside(player) then
        local x, y, z = exitPoint()
        if distanceTo(player, x, y, z) > AGENCY.DOOR_DISTANCE + 0.5 then return end
        if tickets[player] and not confirmLeave then
            return triggerClientEvent(player, "rp:agency:confirmLeave", resourceRoot)
        end
        if tickets[player] then dropTicket(player, "Saliste de la agencia y perdiste tu turno.") end
        local e = AGENCY.EXIT_SPAWN
        fadeCamera(player, false, 0.4)
        setTimer(function()
            if not isElement(player) then return end
            setElementInterior(player, 0)
            setElementDimension(player, 0)
            setElementPosition(player, e.x, e.y, e.z + 0.6)
            triggerClientEvent(player, "rp:agency:groundFix", resourceRoot, e.x, e.y, e.z)
            setElementRotation(player, 0, 0, e.rot)
            setCameraTarget(player, player)
            fadeCamera(player, true, 0.6)
            triggerClientEvent(player, "rp:agency:inside", resourceRoot, false)
        end, 450, 1)
    else
        local en = AGENCY.ENTRANCE
        if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then return end
        if distanceTo(player, en.x, en.y, en.z) > AGENCY.DOOR_DISTANCE + 0.5 then return end
        local s = AGENCY.INSIDE_SPAWN
        fadeCamera(player, false, 0.4)
        setTimer(function()
            if not isElement(player) then return end
            setElementInterior(player, AGENCY.INTERIOR)
            setElementDimension(player, AGENCY.DIMENSION)
            setElementPosition(player, s.x, s.y, s.z)
            setElementRotation(player, 0, 0, s.rot)
            setCameraTarget(player, player)
            fadeCamera(player, true, 0.6)
            triggerClientEvent(player, "rp:agency:inside", resourceRoot, true)
            broadcast()
        end, 450, 1)
    end
end)

----------------------------------------------------------------
-- Dispensador
----------------------------------------------------------------
addEventHandler("rp:agency:takeTicket", resourceRoot, function(reason)
    local player = client
    if type(reason) ~= "string" or not AGENCY.REASONS[reason] then return end
    if not characterOf(player) or getElementData(player, "rp:downed") then return end
    if not isInside(player) then return end
    local d = AGENCY.DISPENSER
    local x, y = agencyPoint(d.ox, d.oy)
    if distanceTo(player, x, y, AGENCY.ORIGIN.z) > AGENCY.USE_DISTANCE + 0.6 then
        return notify(player, "Acercate al dispensador de turnos.", "warning")
    end
    if tickets[player] then
        return notify(player, ("Ya tienes el turno %s."):format(tickets[player].code), "warning")
    end
    local last = lastTicketAt[player]
    if last and now() - last < AGENCY.TICKET_COOLDOWN * 1000 then return end
    lastTicketAt[player] = now()

    nextNumber = nextNumber % AGENCY.TICKET_MAX + 1
    local t = { player = player, number = nextNumber, reason = reason, state = "waiting", takenAt = now() }
    t.code = agencyFormatTicket(reason, nextNumber)
    tickets[player] = t
    queue[#queue + 1] = t

    -- Animacion de sacar el ticket (la ven todos)
    setPedAnimation(player, "VENDING", "VEND_Use", 1600, false, false, false, false)
    triggerClientEvent(player, "rp:agency:ticket", resourceRoot, t.code, reason, #queue - 1)

    -- Si no hay nadie delante, se le llama tras ver el ticket
    nextCallAt = math.max(nextCallAt, now() + AGENCY.CALL_DELAY * 1000)
    broadcast()
end)

----------------------------------------------------------------
-- Mostradores: llegar y sentarse
----------------------------------------------------------------
local function profileOf(player, callback)
    local characterId = characterOf(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local row = rows and rows[1]
        if not row or not isElement(player) or characterOf(player) ~= characterId then return callback(nil) end
        callback({
            name = (tostring(row.name):gsub("_", " ")), gender = tonumber(row.gender) or 0,
            age = tonumber(row.age) or 0, origin = row.origin or "", height = tonumber(row.height) or 0,
            weight = tonumber(row.weight) or 0,
        })
    end, exports.rp_database:getConnection(),
        "SELECT name, gender, age, origin, height, weight FROM characters WHERE id = ?", characterId)
end

local function sitAt(player, i)
    local pts = agencyCounterPoints(i)
    local s = pts.seat
    setElementPosition(player, s.x, s.y, s.z)
    setElementRotation(player, 0, 0, s.rot)
    setPedAnimation(player, "INT_OFFICE", "OFF_Sit_In", -1, false, false, false, true)
    setTimer(function()
        if isElement(player) and tickets[player] and tickets[player].state == "busy" then
            setPedAnimation(player, "INT_OFFICE", "OFF_Sit_Idle_Loop", -1, true, false, false, false)
        end
    end, 1700, 1)
end

local function standUp(player, i)
    if not isElement(player) then return end
    setPedAnimation(player)
    local pts = agencyCounterPoints(i)
    if pts then
        -- un paso atras de la silla, hacia la entrada
        local x, y = agencyPoint(AGENCY.COUNTERS[i].ox, AGENCY.COUNTERS[i].oy - 0.9)
        setElementPosition(player, x, y, pts.seat.z)
    end
end

local function startService(player, i, t)
    local c = counters[i]
    c.state, c.since = "busy", now()
    t.state, t.serviceAt, t.stepAt = "busy", now(), now()
    t.dniDone, t.jobDone = false, false
    toggleAllControls(player, false, true, false)
    sitAt(player, i)
    profileOf(player, function(profile)
        if not isElement(player) or tickets[player] ~= t then return end
        if not profile then
            notify(player, "No se pudieron leer tus datos. Intentalo de nuevo.", "error")
            return endService(player)
        end
        t.profile = profile
        local dni = getPlayerDNIStatus(player)
        triggerClientEvent(player, "rp:agency:serviceStart", resourceRoot, i, AGENCY.COUNTERS[i].clerk.name,
            t.reason, profile, dni, AGENCY.DNI_DUPLICATE_PRICE, AGENCY.REQUIRE_DNI_FOR_JOB)
    end)
    broadcast()
end

function endService(player)
    local t = tickets[player]
    if not t then return end
    local i = t.counter
    tickets[player] = nil
    removeFromQueue(t)
    if isElement(player) then
        toggleAllControls(player, true, true, false)
        if i then standUp(player, i) end
        triggerClientEvent(player, "rp:agency:serviceEnd", resourceRoot)
    end
    if i and counters[i] and counters[i].ticket == t then releaseCounter(i) end
    broadcast()
end

-- Devuelve el ticket si el jugador esta siendo atendido y sigue en su silla
function getServiceTicket(player)
    local t = tickets[player]
    if not t or t.state ~= "busy" or not t.counter then return nil end
    if not isInside(player) then return nil end
    local s = agencyCounterPoints(t.counter).seat
    if distanceTo(player, s.x, s.y, s.z) > 2.5 then return nil end
    return t
end

local function onCounterHit(i, player)
    if getElementType(player) ~= "player" or not isInside(player) then return end
    local t = tickets[player]
    if not t or t.state ~= "called" or t.counter ~= i then return end
    if isPedInVehicle(player) or getElementData(player, "rp:downed") then return end
    startService(player, i, t)
end

----------------------------------------------------------------
-- Tramite: trabajos
----------------------------------------------------------------
local function jobsRunning()
    local r = getResourceFromName("rp_jobs")
    return r and getResourceState(r) == "running"
end

local function sanitizeJob(j)
    if type(j) ~= "table" or type(j.id) ~= "string" then return nil end
    local loc = type(j.location) == "table" and j.location or {}
    local job = {
        id = j.id, name = tostring(j.name or j.id), icon = tostring(j.icon or "💼"),
        description = tostring(j.description or ""), pay = tostring(j.pay or ""),
        howTo = tostring(j.howTo or ""), requirements = j.requirements and tostring(j.requirements) or nil,
        locationName = j.locationName and tostring(j.locationName) or nil,
        location = { x = tonumber(loc.x) or 0, y = tonumber(loc.y) or 0, z = tonumber(loc.z) or 0,
                     interior = tonumber(loc.interior) or 0, dimension = tonumber(loc.dimension) or 0 },
    }
    if type(j.cinematic) == "table" then
        local shots = {}
        for _, s in ipairs(j.cinematic) do
            if type(s) == "table" and type(s.cam) == "table" and type(s.look) == "table" then
                shots[#shots + 1] = {
                    cam = { x = tonumber(s.cam.x) or 0, y = tonumber(s.cam.y) or 0, z = tonumber(s.cam.z) or 0 },
                    look = { x = tonumber(s.look.x) or 0, y = tonumber(s.look.y) or 0, z = tonumber(s.look.z) or 0 },
                    ms = math.max(1000, math.min(15000, tonumber(s.ms) or 4000)), text = s.text and tostring(s.text) or nil,
                }
            end
            if #shots >= 8 then break end
        end
        if #shots > 0 then job.cinematic = shots end
    end
    return job
end

function getAgencyJobs()
    local list
    if jobsRunning() then
        local ok, result = pcall(function() return exports.rp_jobs:getJobList() end)
        if ok and type(result) == "table" and #result > 0 then list = result end
    end
    list = list or AGENCY.FALLBACK_JOBS
    local out = {}
    for _, j in ipairs(list) do
        local job = sanitizeJob(j)
        if job then out[#out + 1] = job end
    end
    return out
end

local function findJob(jobId)
    for _, j in ipairs(getAgencyJobs()) do
        if j.id == jobId then return j end
    end
end

local function currentJob(player)
    if jobsRunning() then
        local ok, id = pcall(function() return exports.rp_jobs:getPlayerJob(player) end)
        if ok then return id end
    end
    return getElementData(player, "rp:job") or nil
end

addEventHandler("rp:agency:jobsRequest", resourceRoot, function()
    local player = client
    local t = getServiceTicket(player)
    if not t or t.reason ~= "job" then return end
    triggerClientEvent(player, "rp:agency:jobs", resourceRoot, getAgencyJobs(), currentJob(player))
end)

addEventHandler("rp:agency:jobTake", resourceRoot, function(jobId)
    local player = client
    local t = getServiceTicket(player)
    if not t or t.reason ~= "job" or type(jobId) ~= "string" then return end
    if now() - t.stepAt < AGENCY.JOB_MIN_SECONDS * 1000 then return end
    if AGENCY.REQUIRE_DNI_FOR_JOB and not hasPlayerDNI(player) then
        return triggerClientEvent(player, "rp:agency:jobResult", resourceRoot, false, "Necesitas tu DNI para que te contraten.")
    end
    local job = findJob(jobId)
    if not job then return end
    if currentJob(player) == job.id then
        return triggerClientEvent(player, "rp:agency:jobResult", resourceRoot, false, "Ya trabajas de " .. job.name .. ".")
    end

    local ok, reason = true, nil
    if jobsRunning() then
        local called, r1, r2 = pcall(function() return exports.rp_jobs:setPlayerJob(player, job.id) end)
        if not called then ok, reason = false, "El sistema de trabajos no responde."
        else ok, reason = r1, r2 end
        if ok then pcall(function() exports.rp_jobs:showJobLocation(player, job.id) end) end
    else
        setElementData(player, "rp:job", job.id)
    end
    if not ok then
        return triggerClientEvent(player, "rp:agency:jobResult", resourceRoot, false, reason or "No se pudo asignar el trabajo.")
    end
    t.jobDone = true
    outputServerLog(("[rp_agency] %s contratado como %s"):format(getPlayerName(player), job.id))
    triggerClientEvent(player, "rp:agency:jobResult", resourceRoot, true, job.id, not jobsRunning())
end)

-- Pasar de un tramite a otro en la misma silla (DNI -> trabajo o al reves)
addEventHandler("rp:agency:switch", resourceRoot, function(reason)
    local player = client
    local t = getServiceTicket(player)
    if not t or type(reason) ~= "string" or not AGENCY.REASONS[reason] then return end
    t.reason, t.stepAt = reason, now()
    triggerClientEvent(player, "rp:agency:switched", resourceRoot, reason, getPlayerDNIStatus(player))
end)

addEventHandler("rp:agency:leave", resourceRoot, function()
    local player = client
    if tickets[player] and tickets[player].state == "busy" then endService(player) end
end)

----------------------------------------------------------------
-- Vigilancia: salidas, tiempo de llamada, gente que se levanta
----------------------------------------------------------------
local function tick()
    for player, t in pairs(tickets) do
        if not isElement(player) then
            tickets[player] = nil
            removeFromQueue(t)
            if t.counter and counters[t.counter] and counters[t.counter].ticket == t then releaseCounter(t.counter) end
        elseif not isInside(player) then
            if t.state == "busy" then endService(player) else dropTicket(player, "Saliste de la agencia y perdiste tu turno.") end
        elseif getElementData(player, "rp:downed") or isPedDead(player) then
            if t.state == "busy" then endService(player) else dropTicket(player, "Perdiste tu turno.") end
        elseif t.state == "called" and now() - t.calledAt > AGENCY.CALL_TIMEOUT * 1000 then
            dropTicket(player, ("No te acercaste a tiempo: el turno %s ha expirado."):format(t.code))
        elseif t.state == "busy" and not getServiceTicket(player) then
            endService(player)
        end
    end
    callNext()
end

----------------------------------------------------------------
-- Arranque
----------------------------------------------------------------
-- Puerta de la calle: blip y punto movible (el marcador lo dibuja el cliente, c_agency.lua).
-- La posicion puede haberla movido un admin con el editor (rp_markers).
local entranceBlip
local function spawnEntrance()
    agencyResolvePoints()
    local en = AGENCY.ENTRANCE
    if isElement(entranceBlip) then destroyElement(entranceBlip) end
    entranceBlip = createBlip(en.x, en.y, en.z, 56, 2, 255, 255, 255, 255, 0, 400)
    pcall(function()
        exports.rp_markers:registerPoint("entrance", { label = "Agencia de empleo · entrada", point = { en.x, en.y, en.z } })
    end)
end

addEvent("rp:markers:moved")
addEvent("rp:markers:ready")
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then spawnEntrance() end
end)
addEventHandler("rp:markers:ready", root, function() spawnEntrance() end)

addEventHandler("onResourceStart", resourceRoot, function()
    for i = 1, #AGENCY.COUNTERS do
        local s = agencyCounterPoints(i).seat
        local col = createColSphere(s.x, s.y, s.z, 1.1)
        setElementInterior(col, AGENCY.INTERIOR)
        setElementDimension(col, AGENCY.DIMENSION)
        counters[i] = { state = "free", col = col }
        addEventHandler("onColShapeHit", col, function(el, sameDim)
            if sameDim then onCounterHit(i, el) end
        end)
    end
    spawnEntrance()
    setTimer(tick, 1000, 0)

    -- Si el recurso se reinicia con gente dentro, que vuelva a ver el HUD
    for _, p in ipairs(playersInside()) do
        triggerClientEvent(p, "rp:agency:inside", resourceRoot, true)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, t in pairs(tickets) do
        if isElement(player) and t.state == "busy" then
            toggleAllControls(player, true, true, false)
            setPedAnimation(player)
        end
    end
end)

local function forget(player)
    if tickets[player] then
        local t = tickets[player]
        if t.state == "busy" then endService(player) else dropTicket(player) end
    end
    lastTicketAt[player] = nil
end
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEventHandler("onPlayerWasted", root, function() forget(source) end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
addCommandHandler("agenciacola", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    outputChatBox(("[Agencia] %d en cola. Ultimo numero: %d"):format(#queue, nextNumber), player, 245, 165, 36)
    for i, c in ipairs(counters) do
        local who = c.ticket and isElement(c.ticket.player) and getPlayerName(c.ticket.player) or "-"
        outputChatBox(("  %s: %s %s (%s)"):format(AGENCY.COUNTERS[i].name, c.state, c.lastCode or "", who), player, 200, 200, 200)
    end
    for i, t in ipairs(queue) do
        outputChatBox(("  %d. %s %s"):format(i, t.code, isElement(t.player) and getPlayerName(t.player) or "?"), player, 200, 200, 200)
    end
end)

addCommandHandler("agenciareset", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local list = {}
    for p in pairs(tickets) do list[#list + 1] = p end
    for _, p in ipairs(list) do
        local t = tickets[p]
        if t and t.state == "busy" then endService(p) else dropTicket(p, "Un administrador reinicio la cola.") end
    end
    queue, nextNumber, nextCallAt = {}, 0, 0
    for i in ipairs(counters) do releaseCounter(i) end
    nextCallAt = 0
    broadcast()
    notify(player, "Cola de la agencia reiniciada.", "success")
end)

-- Para pruebas (rp_test): estado interno de solo lectura
function getAgencyQueueInfo()
    local states = {}
    for i, c in ipairs(counters) do states[i] = c.state end
    return #queue, nextNumber, states
end
