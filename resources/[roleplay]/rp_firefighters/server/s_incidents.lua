--[[
    rp_firefighters / s_incidents.lua  (servidor)

    Emergencias dinámicas. Cada cierto tiempo aleatorio, si hay bomberos de servicio,
    se elige un sitio (fire_sites, los colocan los admins) y se crea un incidente:
      - Focos de fuego con vida (FIRE.FOCUS_HP). El servidor es dueño de la vida;
        cada cliente dibuja el fuego (createFire es solo de cliente) y avisa a qué
        foco apunta con el extintor o el cañón; aquí se revalida arma, vehículo y distancia.
      - Civiles atrapados (peds) con aire limitado. E para cargarlos a hombros y
        E en la zona segura (ambulancia) para dejarlos a salvo.
      - Éxito: todos los focos apagados y todos los civiles a salvo antes del tiempo.
        Fallo: muere un civil o se acaba el tiempo del edificio.
    Un solo timer de 1 s mueve todo el incidente y manda un resumen compacto a los clientes.
]]

local sites = {}              -- [id] = { id, name, x, y, z, fires = {{x,y,z}}, victims = {{x,y,z,rot}} }
local incident = nil          -- incidente activo (máx. uno a la vez)
local carrying = {}           -- [bombero] = índice de la víctima
local lastSpray = {}          -- [bombero] = tick del último chorro aceptado
local generatorTimer = nil
local lastSiteId = nil

addEvent("rp:firefighters:spray", true)     -- cliente: { [focoIdx] = fracción del intervalo apuntando }
addEvent("rp:firefighters:carry", true)     -- cliente: E junto a un civil o con un civil a hombros
addEvent("rp:firefighters:sync", true)      -- cliente: pide el estado al arrancar

----------------------------------------------------------------
-- Datos para el cliente
----------------------------------------------------------------
local function zoneOf(x, y, z)
    return getZoneName(x, y, z) .. ", " .. getZoneName(x, y, z, true)
end

local function snapshot()
    local I = incident
    if not I then return false end
    local foci, victims = {}, {}
    for i, f in ipairs(I.foci) do foci[i] = { x = f.x, y = f.y, z = f.z, hp = math.floor(f.hp + 0.5) } end
    for i, v in ipairs(I.victims) do victims[i] = { ped = v.ped, state = v.state, life = v.life } end
    return {
        id = I.id, name = I.site.name, zone = I.zone, ended = I.ended or false,
        x = I.site.x, y = I.site.y, z = I.site.z, extractRadius = FIRE.EXTRACT_RADIUS,
        timeLeft = math.max(0, I.timeLeft), timeTotal = FIRE.INCIDENT_TIME_S, lifeTotal = FIRE.VICTIM_LIFE_S,
        foci = foci, victims = victims,
    }
end

local function tickData()
    local I = incident
    local f, v = {}, {}
    for i, x in ipairs(I.foci) do f[i] = math.floor(x.hp + 0.5) end
    for i, x in ipairs(I.victims) do v[i] = { x.state, x.life } end
    return { t = math.max(0, I.timeLeft), f = f, v = v }
end

-- Solo a los clientes que ya cargaron el recurso (avisan con rp:firefighters:sync al arrancar)
local readyClients = {}       -- [jugador] = true
local function sendAll(name, ...)
    local list = {}
    for p in pairs(readyClients) do if isElement(p) then list[#list + 1] = p end end
    if #list > 0 then triggerClientEvent(list, name, resourceRoot, ...) end
end

-- Los que deben ver el blip y el HUD: bomberos de servicio
local function dutyList() return getFirefightersOnDuty() end

function FD.refreshIncidentBlip()
    if not incident or not isElement(incident.blip) then return end
    setElementVisibleTo(incident.blip, root, false)
    for _, p in ipairs(dutyList()) do setElementVisibleTo(incident.blip, p, true) end
end

----------------------------------------------------------------
-- Cargar civiles
----------------------------------------------------------------
local function victimFree(v)
    return v.state == "trapped"
end

local function dropVictim(p, rescued)
    local idx = carrying[p]
    carrying[p] = nil
    local I = incident
    local v = I and I.victims[idx]
    if not v or not isElement(v.ped) then return end
    v.carrier = nil
    detachElements(v.ped)
    setElementCollisionsEnabled(v.ped, true)
    if rescued then
        -- Junto a la ambulancia, sentado y a salvo
        local s = I.site
        local a = math.rad(idx * 50)
        setElementPosition(v.ped, s.x + math.cos(a) * 2.2, s.y + math.sin(a) * 2.2, s.z)
        setElementRotation(v.ped, 0, 0, math.deg(a) + 90, "default", true)
        setPedAnimation(v.ped, "BEACH", "ParkSit_M_loop", -1, true, false, false, true)
        v.state = "safe"
        I.contrib[p] = I.contrib[p] or { hits = 0, rescues = 0, foci = 0 }
        I.contrib[p].rescues = I.contrib[p].rescues + 1
        exports.rp_notify:bubble(root, v.ped, "¡Gracias! Pensé que no salía de ahí...", 5000)
        triggerClientEvent(p, "rp:firefighters:fx", resourceRoot, "rescued")
    else
        if isElement(p) then
            local x, y, z = getElementPosition(p)
            local _, _, rz = getElementRotation(p)
            local a = math.rad(rz)
            setElementPosition(v.ped, x + math.sin(a) * 0.9, y - math.cos(a) * 0.9, z)
        end
        setPedAnimation(v.ped, "ped", "cower", -1, true, false, false, true)
        v.state = "trapped"
    end
end

local function pickVictim(p, idx)
    local v = incident.victims[idx]
    setElementFrozen(v.ped, false)
    setElementCollisionsEnabled(v.ped, false)
    local C = FIRE.CARRY
    attachElements(v.ped, p, C.X, C.Y, C.Z, C.RX, C.RY, C.RZ)
    setPedAnimation(v.ped, "SWEET", "Sweet_injuredloop", -1, true, false, false, true)
    v.state, v.carrier = "carried", p
    carrying[p] = idx
    triggerClientEvent(p, "rp:firefighters:fx", resourceRoot, "pickup")
end

function FD.dropCarried(p)
    if carrying[p] then dropVictim(p, false) end
end

addEventHandler("rp:firefighters:carry", resourceRoot, function(idx)
    local p = client
    local I = incident
    if not I or I.ended or not isOnDuty(p) or not FD.takeCooldown(p) then return end
    if FD.blockedReason(p) then return end
    if getElementDimension(p) ~= 0 or getElementInterior(p) ~= 0 then return end
    -- Con un civil a hombros: dejarlo (a salvo si está en la zona segura)
    if carrying[p] then
        local inZone = FD.dist(p, I.site.x, I.site.y, I.site.z) <= FIRE.EXTRACT_RADIUS + 1
        dropVictim(p, inZone)
        if inZone then FD.notify(p, "Civil a salvo con los paramédicos.", "success")
        else FD.notify(p, "Lo dejas en el suelo. Llévalo a la zona segura (ambulancia).", "warning") end
        return
    end
    if isPedInVehicle(p) then return end
    idx = tonumber(idx)
    local v = idx and I.victims[idx]
    if not v or not victimFree(v) or not isElement(v.ped) then return end
    local x, y, z = getElementPosition(v.ped)
    if FD.dist(p, x, y, z) > FIRE.INTERACT_RADIUS + 1.0 then return end
    pickVictim(p, idx)
    FD.notify(p, "Lo cargas a hombros. Llévalo a la ambulancia y pulsa E.", "info")
end)

-- No se sube a un vehículo con un civil a hombros (el attach hace levitar el auto)
addEventHandler("onVehicleStartEnter", root, function(p)
    if carrying[p] then
        cancelEvent()
        FD.notify(p, "Deja primero al civil en la zona segura (E).", "warning")
    end
end)

----------------------------------------------------------------
-- Chorro de agua
----------------------------------------------------------------
-- Herramienta con la que apaga ahora: "cannon", "ext" o nil
local function toolOf(p)
    local veh = getPedOccupiedVehicle(p)
    if veh then
        if FIRE.CANNON.models[getElementModel(veh)] and getVehicleController(veh) == p then return "cannon", FIRE.CANNON end
        return nil
    end
    if getPedWeapon(p) == 42 and getPedTotalAmmo(p) > 0 then return "ext", FIRE.EXTINGUISHER end
    return nil
end

addEventHandler("rp:firefighters:spray", resourceRoot, function(hits)
    local p = client
    local I = incident
    if not I or I.ended or not isOnDuty(p) or type(hits) ~= "table" then return end
    local now = getTickCount()
    local dt = math.min((now - (lastSpray[p] or 0)) / 1000, 0.6)    -- el cliente manda cada ~0,5 s
    if dt < 0.25 then return end
    lastSpray[p] = now
    local tool, cfg = toolOf(p)
    if not tool or FD.blockedReason(p) then return end
    local px, py, pz = getElementPosition(p)
    local count = 0
    for idx, frac in pairs(hits) do
        idx, frac = tonumber(idx), tonumber(frac)
        local f = idx and I.foci[idx]
        count = count + 1
        if count > 3 then break end                                  -- un chorro no toca más de 3 focos
        if f and f.hp > 0 and frac and frac > 0 then
            if getDistanceBetweenPoints3D(px, py, pz, f.x, f.y, f.z) <= cfg.range + 3 then
                local dmg = cfg.dps * dt * math.min(frac, 1)
                f.hp = math.max(0, f.hp - dmg)
                f.lastHit = now
                local c = I.contrib[p] or { hits = 0, rescues = 0, foci = 0 }
                c.hits = c.hits + dmg
                I.contrib[p] = c
                if f.hp <= 0 then
                    c.foci = c.foci + 1
                    sendAll("rp:firefighters:focusOut", I.id, idx)
                end
            end
        end
    end
end)

----------------------------------------------------------------
-- Fin del incidente
----------------------------------------------------------------
local function cleanup()
    local I = incident
    if not I then return end
    if isTimer(I.timer) then killTimer(I.timer) end
    for p, idx in pairs(carrying) do if I.victims[idx] then dropVictim(p, false) end end
    for _, v in ipairs(I.victims) do if isElement(v.ped) then destroyElement(v.ped) end end
    for _, e in ipairs({ I.blip, I.marker, I.ambulance, I.zoneBlip }) do if isElement(e) then destroyElement(e) end end
    incident = nil
    sendAll("rp:firefighters:incident", false)
end

local function finish(success, reason)
    local I = incident
    if not I or I.ended then return end
    I.ended = true
    if isTimer(I.timer) then killTimer(I.timer) end
    for p in pairs(carrying) do dropVictim(p, false) end

    local R = FIRE.REWARD
    local rescuedTotal = 0
    for _, v in ipairs(I.victims) do if v.state == "safe" then rescuedTotal = rescuedTotal + 1 end end

    for _, p in ipairs(dutyList()) do
        local c = I.contrib[p]
        local took = c and (c.rescues > 0 or c.hits >= R.MIN_HITS)
        local result = { success = success, reason = reason, name = I.site.name, participated = took and true or false,
            rescued = rescuedTotal, victims = #I.victims, money = 0, xp = 0 }
        if took then
            if success then
                local money = R.BASE + R.PER_RESCUE * c.rescues + R.PER_FOCUS * c.foci
                local xp = R.XP_BASE + R.XP_RESCUE * c.rescues + R.XP_FOCUS * c.foci
                FD.payBank(p, money, "Bomberos: " .. I.site.name)
                FD.addStats(p, { xp = xp, fires = c.foci, rescues = c.rescues, ok = 1 })
                pcall(function() exports.rp_levels:giveXP(p, R.LEVEL_XP, "Emergencia de bomberos") end)
                result.money, result.xp = money, xp
            else
                FD.addStats(p, { fires = c.foci, rescues = c.rescues, failed = 1 })
            end
            result.myRescues, result.myFoci = c.rescues, c.foci
        end
        local s = FD.getStats(p)
        if s then result.totalXp = s.xp; local _, rank = fireRankOf(s.xp); result.rank = rank end
        triggerClientEvent(p, "rp:firefighters:result", resourceRoot, result)
    end

    -- Fallo por civil: queda tendido; fallo por tiempo: el fuego "consume" el edificio
    sendAll("rp:firefighters:ended", I.id, success)
    FD.log(("incidente %d en %s: %s (%s)"):format(I.id, I.site.name, success and "resuelto" or "fallido", reason or ""))
    local id = I.id
    setTimer(function() if incident and incident.id == id then cleanup() end end, FIRE.CLEANUP_S * 1000, 1)
    FD.scheduleNext()
end

local function tick()
    local I = incident
    if not I or I.ended then return end
    I.timeLeft = I.timeLeft - 1
    local now = getTickCount()
    local fociAlive = 0
    for _, f in ipairs(I.foci) do
        if f.hp > 0 then
            fociAlive = fociAlive + 1
            if f.hp < FIRE.FOCUS_HP and now - f.lastHit > FIRE.REGEN_IDLE_S * 1000 then
                f.hp = math.min(FIRE.FOCUS_HP, f.hp + FIRE.REGEN_PER_S)
            end
        end
    end
    local allSafe = true
    for _, v in ipairs(I.victims) do
        if v.state == "trapped" or v.state == "carried" then
            allSafe = false
            v.life = v.life - 1
            if v.life <= 0 then
                v.life = 0
                if v.carrier then dropVictim(v.carrier, false) end
                v.state = "dead"
                if isElement(v.ped) then killPed(v.ped) end
                sendAll("rp:firefighters:tick", tickData())
                return finish(false, "Un civil no aguantó el humo.")
            end
        end
    end
    sendAll("rp:firefighters:tick", tickData())
    if fociAlive == 0 and allSafe then return finish(true, "Fuego extinguido y civiles a salvo.") end
    if I.timeLeft <= 0 then return finish(false, "El fuego consumió el edificio.") end
end

----------------------------------------------------------------
-- Inicio del incidente
----------------------------------------------------------------
local nextIncidentId = 0

local function shuffle(t)
    for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

-- Devuelve true o false, motivo
function FD.startIncident(siteId)
    if incident then return false, "Ya hay una emergencia activa." end
    local site = sites[siteId]
    if not site then return false, "Ese sitio no existe." end
    if #site.fires == 0 or #site.victims == 0 then return false, "El sitio necesita al menos un foco y un civil." end

    nextIncidentId = nextIncidentId + 1
    local I = { id = nextIncidentId, site = site, zone = zoneOf(site.x, site.y, site.z), timeLeft = FIRE.INCIDENT_TIME_S,
        foci = {}, victims = {}, contrib = {} }

    local fires = shuffle({ unpack(site.fires) })
    for i = 1, math.min(#fires, FIRE.MAX_FOCI) do
        local f = fires[i]
        I.foci[i] = { x = f.x, y = f.y, z = f.z, hp = FIRE.FOCUS_HP, lastHit = 0 }
    end
    local spots = shuffle({ unpack(site.victims) })
    local n = math.min(#spots, math.random(FIRE.MIN_VICTIMS, FIRE.MAX_VICTIMS))
    for i = 1, n do
        local s = spots[i]
        local ped = createPed(FIRE.VICTIM_SKINS[math.random(#FIRE.VICTIM_SKINS)], s.x, s.y, s.z, s.rot or 0)
        if ped then
            setElementData(ped, "rp:fireVictim", i)
            setElementFrozen(ped, true)
            setPedAnimation(ped, "ped", "cower", -1, true, false, false, true)
            I.victims[#I.victims + 1] = { ped = ped, state = "trapped", life = FIRE.VICTIM_LIFE_S }
        end
    end

    -- Zona segura con ambulancia (decorado: cerrada, intocable y con luces)
    I.marker = createMarker(site.x, site.y, site.z - 1, "cylinder", FIRE.EXTRACT_RADIUS * 0.5, 255, 95, 120, 90)
    pcall(function() exports.rp_markers:setMarkerStyle(I.marker, { icon = "medical", label = "Zona segura", color = { 255, 95, 120 } }) end)
    I.ambulance = createVehicle(416, site.x + 3.5, site.y + 3.5, site.z + 0.3, 0, 0, math.random(0, 359))
    if I.ambulance then
        setVehicleLocked(I.ambulance, true)
        setVehicleDamageProof(I.ambulance, true)
        setElementFrozen(I.ambulance, true)
        setVehicleSirensOn(I.ambulance, true)
        setVehicleEngineState(I.ambulance, false)
    end
    -- Blip del fuego: solo los bomberos de servicio, siempre visible en el borde del radar
    I.blip = createBlip(site.x, site.y, site.z, 0, 3, 235, 70, 40, 255, 10, 99999)
    setElementData(I.blip, "rp:radarEdge", true)

    incident = I
    FD.refreshIncidentBlip()
    I.timer = setTimer(tick, 1000, 0)
    lastSiteId = site.id

    sendAll("rp:firefighters:incident", snapshot())
    for _, p in ipairs(dutyList()) do
        triggerClientEvent(p, "rp:firefighters:alert", resourceRoot, {
            name = site.name, zone = I.zone, x = site.x, y = site.y, z = site.z,
            foci = #I.foci, victims = #I.victims, time = FIRE.INCIDENT_TIME_S, life = FIRE.VICTIM_LIFE_S,
            novice = (function() local st = FD.getStats(p) return not st or (st.ok + st.failed) < 2 end)(),
        })
        outputChatBox(("[CENTRAL SFFD] Incendio estructural en %s (%s). Coordenadas %.1f, %.1f, %.1f. %d civiles atrapados."):format(
            site.name, I.zone, site.x, site.y, site.z, #I.victims), p, 235, 110, 60)
    end
    FD.log(("incidente %d en %s (%d focos, %d civiles)"):format(I.id, site.name, #I.foci, #I.victims))
    return true
end

function FD.cancelIncident()
    if not incident then return false end
    if not incident.ended then
        incident.ended = true
        sendAll("rp:firefighters:ended", incident.id, false)
        for _, p in ipairs(dutyList()) do FD.notify(p, "La central cancela la emergencia en curso.", "info") end
    end
    cleanup()
    FD.scheduleNext()
    return true
end

function FD.getIncident() return incident end

----------------------------------------------------------------
-- Generador
----------------------------------------------------------------
local function eligibleSites()
    local list = {}
    for id, s in pairs(sites) do
        if #s.fires > 0 and #s.victims > 0 and (id ~= lastSiteId or next(sites, next(sites)) == nil) then list[#list + 1] = id end
    end
    return list
end

local function tryGenerate()
    generatorTimer = nil
    if incident then return FD.scheduleNext() end
    if #dutyList() < FIRE.MIN_ON_DUTY then return FD.scheduleNext() end
    local list = eligibleSites()
    if #list == 0 then
        FD.log("no hay sitios de incendio completos (/fdsitio crear, foco, civil)", 2)
        return FD.scheduleNext()
    end
    local ok, why = FD.startIncident(list[math.random(#list)])
    if not ok then FD.log("no se pudo generar: " .. tostring(why), 2); FD.scheduleNext() end
end

function FD.scheduleNext(seconds)
    if isTimer(generatorTimer) then killTimer(generatorTimer) end
    seconds = seconds or math.random(FIRE.ALERT_MIN_S, FIRE.ALERT_MAX_S)
    generatorTimer = setTimer(tryGenerate, seconds * 1000, 1)
end

----------------------------------------------------------------
-- Sitios (fire_sites + fire_site_points)
----------------------------------------------------------------
function FD.getSites() return sites end

function FD.loadSites(onDone)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local fresh = {}
        for _, r in ipairs(rows) do
            fresh[tonumber(r.id)] = { id = tonumber(r.id), name = r.name, x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), fires = {}, victims = {} }
        end
        dbQuery(function(qh2)
            for _, r in ipairs(dbPoll(qh2, 0) or {}) do
                local s = fresh[tonumber(r.site_id)]
                if s then
                    local list = r.kind == "fire" and s.fires or s.victims
                    list[#list + 1] = { id = tonumber(r.id), x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), rot = tonumber(r.rot) }
                end
            end
            sites = fresh
            if onDone then onDone() end
        end, FD.db(), "SELECT id, site_id, kind, x, y, z, rot FROM fire_site_points ORDER BY id")
    end, FD.db(), "SELECT id, name, x, y, z FROM fire_sites")
end

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("rp:firefighters:sync", resourceRoot, function()
    readyClients[client] = true
    if incident and not incident.ended then triggerClientEvent(client, "rp:firefighters:incident", resourceRoot, snapshot()) end
end)

addEventHandler("rp:firefighters:onDuty", root, function(on)
    if not on then FD.dropCarried(source) end
    if on and incident and not incident.ended then
        triggerClientEvent(source, "rp:firefighters:incident", resourceRoot, snapshot())
    end
end)

local function forget(p)
    FD.dropCarried(p)
    lastSpray[p] = nil
end
addEventHandler("onPlayerQuit", root, function() forget(source); readyClients[source] = nil end)
addEventHandler("onPlayerWasted", root, function() forget(source) end)
addEventHandler("rp:onPlayerDowned", root, function() forget(source) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)

-- attachElements no sincroniza interior/dimensión: si el bombero cambia, suelta al civil
setTimer(function()
    for p, idx in pairs(carrying) do
        if not isElement(p) or getElementDimension(p) ~= 0 or getElementInterior(p) ~= 0 then forget(p) end
    end
end, 1000, 0)

function FD.bootIncidents()
    FD.loadSites(function() FD.log(("%d sitios de incendio cargados"):format((function() local n = 0 for _ in pairs(sites) do n = n + 1 end return n end)())) end)
    FD.scheduleNext(FIRE.ALERT_FIRST_S)
end

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(carrying) do carrying[p] = nil end
end)
