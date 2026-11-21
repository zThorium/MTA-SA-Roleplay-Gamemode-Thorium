--[[
    rp_agency / c_service.lua
    Tramite en el mostrador: cinematica de sentarse, camara centrada en la
    trabajadora, dialogo (CEF), la trabajadora que se levanta a imprimir el DNI
    y vuelve a entregarlo, y la cinematica de "Mas informacion" de un trabajo.

    El dialogo lo lleva html/app.js; este archivo mueve camara, ped y sonidos
    cuando el JS pide una "cue", y reenvia al servidor lo que el jugador elige.
    El servidor revalida todo (tiempos minimos, que siga sentado, inventario).
]]

local service = nil      -- { counter, clerkName, reason, startedAt, timers = {} }
local cam = nil          -- animacion de camara en curso
local typingSound = nil
local jobBlip, jobMarker = nil, nil

addEvent("rp:agency:serviceStart", true)
addEvent("rp:agency:serviceEnd", true)
addEvent("rp:agency:dniResult", true)
addEvent("rp:agency:jobs", true)
addEvent("rp:agency:jobResult", true)
addEvent("rp:agency:switched", true)
addEvent("rp:agency:ui:cue", false)
addEvent("rp:agency:ui:dni", false)
addEvent("rp:agency:ui:jobs", false)
addEvent("rp:agency:ui:jobInfo", false)
addEvent("rp:agency:ui:jobTake", false)
addEvent("rp:agency:ui:switch", false)
addEvent("rp:agency:ui:leave", false)

function agencyInService()
    return service ~= nil
end

local function later(ms, fn)
    if not service then return end
    local t = setTimer(function() if service then fn() end end, ms, 1)
    service.timers[#service.timers + 1] = t
    return t
end

----------------------------------------------------------------
-- Camara
----------------------------------------------------------------
local function smooth(t) return t * t * (3 - 2 * t) end

-- from/to = { cx, cy, cz, lx, ly, lz }
local function camMove(from, to, ms, done)
    cam = { from = from, to = to, start = getTickCount(), ms = math.max(1, ms), done = done }
end

local function camStop()
    cam = nil
end

addEventHandler("onClientPreRender", root, function()
    if not cam then return end
    local t = math.min(1, (getTickCount() - cam.start) / cam.ms)
    local k = smooth(t)
    local f, d = cam.from, cam.to
    setCameraMatrix(f[1] + (d[1] - f[1]) * k, f[2] + (d[2] - f[2]) * k, f[3] + (d[3] - f[3]) * k,
                    f[4] + (d[4] - f[4]) * k, f[5] + (d[5] - f[5]) * k, f[6] + (d[6] - f[6]) * k)
    if t >= 1 then
        local done = cam.done
        cam.done = nil
        if done then done() end
    end
end)

-- Vectores del mostrador: f = de la silla hacia la trabajadora, r = derecha
local function counterFrame(i)
    local p = agencyCounterPoints(i)
    local fx, fy = p.clerk.x - p.seat.x, p.clerk.y - p.seat.y
    local len = math.sqrt(fx * fx + fy * fy)
    fx, fy = fx / len, fy / len
    return p, fx, fy, fy, -fx
end

-- Plano central: por encima del hombro del jugador, mirando a la trabajadora
local function centralShot(i)
    local p, fx, fy, rx, ry = counterFrame(i)
    return { p.seat.x - fx * 0.55 + rx * 0.18, p.seat.y - fy * 0.55 + ry * 0.18, p.seat.z + 0.62,
             p.clerk.x, p.clerk.y, p.clerk.z + 0.28 }
end

-- Plano lateral: se ve al jugador sentandose
local function sideShot(i)
    local p, fx, fy, rx, ry = counterFrame(i)
    return { p.desk.x + rx * 2.6 - fx * 0.6, p.desk.y + ry * 2.6 - fy * 0.6, p.desk.z + 0.7,
             p.seat.x, p.seat.y, p.seat.z }
end

----------------------------------------------------------------
-- Inicio y fin
----------------------------------------------------------------
local function stopTyping()
    if isElement(typingSound) then destroyElement(typingSound) end
    typingSound = nil
end

local function finish()
    if not service then return end
    for _, t in ipairs(service.timers) do if isTimer(t) then killTimer(t) end end
    local i = service.counter
    service = nil
    camStop()
    stopTyping()
    uiClose()
    setCameraInterior(AGENCY.INTERIOR)
    setCameraTarget(localPlayer)
    showChat(true)
    setElementData(localPlayer, "rp:hudHidden", false, false)
    if i then agencyResetClerk(i) end
end

addEventHandler("rp:agency:serviceStart", resourceRoot, function(i, clerkName, reason, profile, dniStatus, price, requireDni)
    if service then finish() end
    agencyClearCall()
    service = { counter = i, clerkName = clerkName, reason = reason, startedAt = getTickCount(), timers = {} }
    showChat(false)
    setElementData(localPlayer, "rp:hudHidden", true, false)
    agencyResetClerk(i)
    local ped = agencyClerk(i)
    if ped then setPedAnimation(ped, "INT_OFFICE", "OFF_Sit_Idle_Loop", -1, true, false, false, false) end

    -- 1) plano lateral mientras se sienta  2) paso al plano central
    local side = sideShot(i)
    setCameraMatrix(unpack(side))
    fadeCamera(true, 0.5)
    later(2600, function()
        camMove(side, centralShot(i), 1800, function()
            uiOpen(true)
            uiCall(("RP.service(%s)"):format(jsJSON({
                clerk = clerkName, reason = reason, profile = profile, dni = dniStatus,
                price = price, requireDni = requireDni, counter = i,
            })))
        end)
    end)
end)

addEventHandler("rp:agency:serviceEnd", resourceRoot, finish)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if service then
        setCameraTarget(localPlayer)
        showChat(true)
        setElementData(localPlayer, "rp:hudHidden", false, false)
    end
end)

----------------------------------------------------------------
-- Cues del dialogo
----------------------------------------------------------------
local function clerkAnim(block, anim, loop)
    local ped = service and agencyClerk(service.counter)
    if ped then setPedAnimation(ped, block, anim, -1, loop ~= false, false, false, false) end
end

-- La trabajadora se levanta, sale de plano a imprimir y vuelve con el DNI
local function printSequence()
    local i = service.counter
    local ped = agencyClerk(i)
    local c = agencyCounterPoints(i).clerk
    stopTyping()
    if not ped then
        later(6000, function() uiCall("RP.cueDone('print')") end)
        return
    end
    setPedAnimation(ped, "INT_OFFICE", "OFF_Sit_2Idle_180", -1, false, false, false, true)
    later(1500, function()
        setPedAnimation(ped)
        setElementRotation(ped, 0, 0, (c.rot + 180) % 360, "default", true)
        setPedControlState(ped, "walk", true)
        setPedControlState(ped, "forwards", true)
    end)
    later(4300, function()
        setPedControlState(ped, "forwards", false)
        setElementAlpha(ped, 0)
        agencyPlaySfx("printer")
    end)
    later(6200, function() agencyPlaySfx("typing", 0.5) end)
    later(8200, function() agencyPlaySfx("stamp") end)
    later(9000, function()
        setElementAlpha(ped, 255)
        setElementRotation(ped, 0, 0, c.rot, "default", true)
        setPedControlState(ped, "walk", true)
        setPedControlState(ped, "forwards", true)
    end)
    later(11800, function()
        setPedControlState(ped, "forwards", false)
        setPedControlState(ped, "walk", false)
        setElementPosition(ped, c.x, c.y, c.z)
        setElementRotation(ped, 0, 0, c.rot, "default", true)
        uiCall("RP.cueDone('print')")
    end)
end

addEventHandler("rp:agency:ui:cue", root, function(name)
    if not service or type(name) ~= "string" then return end
    if name == "type" then
        clerkAnim("INT_OFFICE", "OFF_Sit_Type_Loop")
        if not isElement(typingSound) then
            typingSound = playSound("sounds/typing.wav", true)
            if typingSound then setSoundVolume(typingSound, 0.55) end
        end
    elseif name == "idle" then
        stopTyping()
        clerkAnim("INT_OFFICE", "OFF_Sit_Idle_Loop")
    elseif name == "photo" then
        agencyPlaySfx("shutter")
        clerkAnim("INT_OFFICE", "OFF_Sit_Watch")
    elseif name == "print" then
        printSequence()
    elseif name == "hand" then
        local ped = agencyClerk(service.counter)
        if ped then
            setPedAnimation(ped, "DEALER", "DEALER_DEAL", -1, false, false, false, false)
            later(1700, function() agencyResetClerk(service.counter) clerkAnim("INT_OFFICE", "OFF_Sit_Idle_Loop") end)
        end
        agencyPlaySfx("paper")
    elseif name == "bye" then
        stopTyping()
        local ped = agencyClerk(service.counter)
        if ped then setPedAnimation(ped, "GANGS", "hndshkfa_swt", -1, false, false, false, false) end
    end
end)

----------------------------------------------------------------
-- DNI
----------------------------------------------------------------
addEventHandler("rp:agency:ui:dni", root, function(signature)
    if not service or type(signature) ~= "string" or #signature > 4000 then return end
    -- El servidor exige un tiempo minimo de tramite; si el jugador fue muy rapido, esperamos
    local wait = AGENCY.DNI_MIN_SECONDS * 1000 + 500 - (getTickCount() - service.startedAt)
    if wait > 0 then
        later(wait, function() triggerServerEvent("rp:agency:dniSubmit", resourceRoot, signature) end)
    else
        triggerServerEvent("rp:agency:dniSubmit", resourceRoot, signature)
    end
end)

addEventHandler("rp:agency:dniResult", resourceRoot, function(ok, data, price)
    if not service then return end
    if ok then
        uiCall(("RP.dniResult(true, %s, %d)"):format(jsJSON(data), tonumber(price) or 0))
    else
        uiCall(("RP.dniResult(false, %s, 0)"):format(jsString(data)))
    end
end)

----------------------------------------------------------------
-- Trabajos
----------------------------------------------------------------
local jobsById = {}

addEventHandler("rp:agency:ui:jobs", root, function()
    if service then triggerServerEvent("rp:agency:jobsRequest", resourceRoot) end
end)

addEventHandler("rp:agency:jobs", resourceRoot, function(list, current)
    if not service then return end
    jobsById = {}
    for _, j in ipairs(list or {}) do
        local x, y, z = j.location.x, j.location.y, j.location.z
        j.zone = getZoneName(x, y, z) .. ", " .. getZoneName(x, y, z, true)
        local e = AGENCY.ENTRANCE
        j.distance = math.floor(getDistanceBetweenPoints2D(e.x, e.y, x, y) / 100 + 0.5) / 10
        jobsById[j.id] = j
    end
    uiCall(("RP.jobs(%s, %s)"):format(jsJSON(list or {}), current and jsString(current) or "null"))
end)

-- Planos por defecto si el trabajo no trae los suyos
local function defaultShots(job)
    local l = job.location
    return {
        { cam = { x = l.x + 70, y = l.y - 70, z = l.z + 55 }, look = { x = l.x, y = l.y, z = l.z }, ms = 5000,
          text = ("%s · %s"):format(job.name, job.zone or "") },
        { cam = { x = l.x - 25, y = l.y + 18, z = l.z + 10 }, look = { x = l.x, y = l.y, z = l.z + 1 }, ms = 5500,
          text = job.description },
        { cam = { x = l.x + 8, y = l.y + 30, z = l.z + 22 }, look = { x = l.x, y = l.y, z = l.z }, ms = 5500,
          text = job.howTo },
    }
end

local function endInfo()
    if not service then return end
    camStop()
    setCameraInterior(AGENCY.INTERIOR)
    fadeCamera(false, 0.3)
    later(350, function()
        setCameraMatrix(unpack(centralShot(service.counter)))
        fadeCamera(true, 0.5)
        uiCall("RP.infoDone()")
    end)
end

addEventHandler("rp:agency:ui:jobInfo", root, function(jobId)
    local job = service and jobsById[jobId]
    if not job then return end
    local shots = job.cinematic or defaultShots(job)
    fadeCamera(false, 0.4)
    local function play(n)
        local shot = shots[n]
        if not shot or not service then return endInfo() end
        local c, l = shot.cam, shot.look
        -- cada plano hace un travelling suave hacia el punto que mira
        local from = { c.x, c.y, c.z, l.x, l.y, l.z }
        local to = { c.x + (l.x - c.x) * 0.25, c.y + (l.y - c.y) * 0.25, c.z + (l.z - c.z) * 0.18, l.x, l.y, l.z }
        uiCall(("RP.infoShot(%d, %d, %s)"):format(n, #shots, jsString(shot.text or "")))
        camMove(from, to, shot.ms, function() play(n + 1) end)
    end
    later(420, function()
        setCameraInterior(job.location.interior or 0)
        fadeCamera(true, 0.6)
        play(1)
    end)
end)

addEventHandler("rp:agency:ui:jobTake", root, function(jobId)
    if service and type(jobId) == "string" then triggerServerEvent("rp:agency:jobTake", resourceRoot, jobId) end
end)

local function clearJobRoute()
    if isElement(jobBlip) then destroyElement(jobBlip) end
    if isElement(jobMarker) then destroyElement(jobMarker) end
    jobBlip, jobMarker = nil, nil
end

-- Sin rp_jobs, la agencia marca la ubicacion ella misma hasta que llegues
local function markJob(job)
    clearJobRoute()
    local l = job.location
    jobBlip = createBlip(l.x, l.y, l.z, 41, 2, 245, 165, 36, 255, 0, 99999)
    jobMarker = createMarker(l.x, l.y, l.z - 1, "checkpoint", 3, 245, 165, 36, 160)
    if jobMarker then
        addEventHandler("onClientMarkerHit", jobMarker, function(el, dim)
            if el == localPlayer and dim then
                exports.rp_notify:notify(("Llegaste a %s."):format(job.name), "success")
                clearJobRoute()
            end
        end)
    end
end

addEventHandler("rp:agency:jobResult", resourceRoot, function(ok, data, fallback)
    if not service then return end
    if ok then
        local job = jobsById[data]
        if job and fallback then markJob(job) end
        uiCall(("RP.jobResult(true, %s)"):format(jsString(data)))
    else
        uiCall(("RP.jobResult(false, %s)"):format(jsString(data)))
    end
end)

----------------------------------------------------------------
-- Cambiar de tramite y marcharse
----------------------------------------------------------------
addEventHandler("rp:agency:ui:switch", root, function(reason)
    if service and AGENCY.REASONS[reason] then triggerServerEvent("rp:agency:switch", resourceRoot, reason) end
end)

addEventHandler("rp:agency:switched", resourceRoot, function(reason, dniStatus)
    if not service then return end
    service.reason = reason
    if reason == "dni" then service.startedAt = getTickCount() end
    uiCall(("RP.switched(%s, %s)"):format(jsString(reason), jsString(dniStatus)))
end)

addEventHandler("rp:agency:ui:leave", root, function()
    if not service then return end
    uiClose()
    fadeCamera(false, 0.6)
    later(700, function()
        triggerServerEvent("rp:agency:leave", resourceRoot)
        fadeCamera(true, 0.8)
    end)
    -- por si el servidor no responde
    later(4000, finish)
end)
