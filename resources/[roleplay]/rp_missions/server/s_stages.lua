--[[
    rp_missions / server / s_stages.lua

    Motor de etapas (RF-02). Una etapa se completa cuando todos sus componentes estan hechos:
    goto, getin, enemies/waves, interact (mantener E), deliver (escolta de vehiculo), wait, cutscene.
    Los enemigos se escalan con Base + (Jugadores-1)*Factor y se vigilan con onPedWasted.
]]

local floor, max, min, sqrt, rad, cos, sin = math.floor, math.max, math.min, math.sqrt, math.rad, math.cos, math.sin

addEvent("rp:missions:hold", true)

local function dist(x1, y1, z1, x2, y2, z2) return getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2) end
local function now() return getTickCount() end

----------------------------------------------------------------
-- Entidades: marcadores y blips visibles solo para el grupo
----------------------------------------------------------------
local function showOnlyTo(inst, el)
    setElementVisibleTo(el, root, false)
    for _, m in ipairs(inst.members) do if isElement(m) then setElementVisibleTo(el, m, true) end end
end

local function track(inst, kind, el)
    inst.rt.owned = inst.rt.owned or {}
    local list = inst.entities[kind]
    list[#list + 1] = el
    return el
end

local function addTarget(inst, x, y, z, r, color, key)
    local mk = createMarker(x, y, z - 0.9, "cylinder", max(1.4, r * 2), color[1], color[2], color[3], 110)
    setElementDimension(mk, inst.dim)
    setElementInterior(mk, inst.def.interior or 0)
    showOnlyTo(inst, mk)
    local bl = createBlip(x, y, z, 0, 2, color[1], color[2], color[3], 255, 0, 9999)
    setElementDimension(bl, inst.dim)
    setElementData(bl, "rp:radarEdge", true)   -- el minimapa de rp_hud lo dibuja siempre, clavado al borde si esta lejos
    showOnlyTo(inst, bl)
    inst.rt.targets = inst.rt.targets or {}
    inst.rt.targets[key or (#inst.rt.targets + 1)] = { mk, bl }
    return mk, bl
end

local function removeTarget(inst, key)
    local t = inst.rt and inst.rt.targets and inst.rt.targets[key]
    if t then
        for _, e in ipairs(t) do if isElement(e) then destroyElement(e) end end
        inst.rt.targets[key] = nil
    end
end

local function clearTargets(inst)
    if not inst.rt or not inst.rt.targets then return end
    for k in pairs(inst.rt.targets) do removeTarget(inst, k) end
end

function M.cleanupEntities(inst)
    for _, list in pairs(inst.entities) do
        for _, e in pairs(list) do if isElement(e) then destroyElement(e) end end
    end
    inst.entities = { vehicles = {}, peds = {}, markers = {}, blips = {}, objects = {} }
    if inst.rt then clearTargets(inst) end
    inst.vehicleByKey, inst.objectByKey = nil, nil
end

local ACCENT = { 245, 165, 36 }
local DANGER = { 229, 72, 77 }

----------------------------------------------------------------
-- Enemigos
----------------------------------------------------------------
local function groupCount(inst, g) return min(MISSIONS.MAX_ENEMIES_ALIVE, scaledEnemyCount(g.count, g.per, #inst.members, inst.difficulty)) end

-- Los enemigos NO aparecen en puntos al azar: un punto aleatorio puede caer dentro de una casa o bajo un tejado (y no se les
-- puede disparar). El servidor no tiene colisiones, asi que propone candidatos y el cliente del miembro mas cercano los valida
-- con rayos (hay suelo a la altura esperada, sin techo encima, y linea de vision libre hasta el punto del grupo).
addEvent("rp:missions:validated", true)
local pendingSpawns = {}   -- [token] = { inst, rt, g, count, counted, validator, cands, done }
local nextSpawnToken = 1

local function createEnemy(inst, g, x, y, z)
    local D = inst.diff
    local skin = g.skins[math.random(#g.skins)]
    local ped = createPed(skin, x, y, z, math.random(0, 359))
    if not ped then return end
    setElementDimension(ped, inst.dim)
    setElementInterior(ped, inst.def.interior or 0)
    setPedStat(ped, 24, 1000)
    setElementHealth(ped, min(200, floor(100 * D.hp)))
    setPedArmor(ped, D.armor)
    giveWeapon(ped, g.weapon, g.ammo or 250, true)
    for stat = 69, 79 do setPedStat(ped, stat, floor(300 + D.acc * 699)) end
    setElementData(ped, "rp:mEnemy", inst.id)
    setElementData(ped, "rp:mAcc", D.acc)
    inst.entities.peds[#inst.entities.peds + 1] = ped
    return ped
end

local function finishSpawn(token, valid)
    local sp = pendingSpawns[token]
    if not sp or sp.done then return end
    sp.done = true
    pendingSpawns[token] = nil
    local inst, rt, g = sp.inst, sp.rt, sp.g
    if inst.destroyed or inst.rt ~= rt then return end
    local created = 0
    -- posiciones validadas primero
    for _, v in ipairs(valid or {}) do
        if created >= sp.count then break end
        if createEnemy(inst, g, v[1], v[2], v[3] + 0.8) then created = created + 1 end
    end
    -- si faltan, junto al punto central del grupo (que es un lugar abierto elegido en el diseno)
    while created < sp.count do
        local a, r = math.random() * math.pi * 2, math.random() * 2.5
        if createEnemy(inst, g, g.x + cos(a) * r, g.y + sin(a) * r, g.z + 0.8) then created = created + 1 else break end
    end
    rt.aliveEnemies = max(0, (rt.aliveEnemies or 0) - (sp.count - created))   -- ajusta la reserva
    if not sp.counted then rt.enemyTotal = (rt.enemyTotal or 0) + created end
    M.syncHud(inst)
end

addEventHandler("rp:missions:validated", resourceRoot, function(token, list)
    local sp = pendingSpawns[token]
    if not sp or client ~= sp.validator or type(list) ~= "table" then return end
    local valid = {}
    for _, v in ipairs(list) do
        if type(v) == "table" and #valid < sp.count * 4 then
            local x, y, z = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
            -- el servidor no confia en el cliente: debe estar cerca del punto del grupo
            if x and y and z and dist(x, y, z, sp.g.x, sp.g.y, sp.g.z) <= (sp.g.radius or 8) + 6 then valid[#valid + 1] = { x, y, z } end
        end
    end
    finishSpawn(token, valid)
end)

local function spawnEnemies(inst, g, count)
    local rt = inst.rt
    if count <= 0 then return end
    -- reserva: la etapa no se da por limpia mientras llegan
    rt.aliveEnemies = (rt.aliveEnemies or 0) + count
    -- validador: el miembro vivo mas cercano al grupo (su cliente tiene cargado el mapa alli)
    local validator, bd
    for _, m in ipairs(M.alive(inst)) do
        local px, py, pz = getElementPosition(m)
        local d = dist(px, py, pz, g.x, g.y, g.z)
        if not bd or d < bd then validator, bd = m, d end
    end
    local token = nextSpawnToken
    nextSpawnToken = nextSpawnToken + 1
    local sp = { inst = inst, rt = rt, g = g, count = count, counted = rt.countedGroup, validator = validator }
    pendingSpawns[token] = sp
    if not validator then return finishSpawn(token, nil) end
    -- candidatos: mas que enemigos, por si algunos caen en interiores o bajo techo
    local cands = {}
    for i = 1, count * 4 + 4 do
        local a, r = math.random() * math.pi * 2, math.random() * (g.radius or 8)
        cands[i] = { g.x + cos(a) * r, g.y + sin(a) * r }
    end
    triggerClientEvent(validator, "rp:missions:validate", resourceRoot, token, g.x, g.y, g.z, cands)
    setTimer(function() finishSpawn(token, nil) end, 2500, 1)   -- si el cliente no responde, se usa el punto central
end
local function anyoneNear(inst, x, y, z, range)
    for _, m in ipairs(M.alive(inst)) do
        local px, py, pz = getElementPosition(m)
        if dist(px, py, pz, x, y, z) <= range then return true end
    end
    return false
end

addEventHandler("onPedWasted", root, function(_, killer)
    local id = getElementData(source, "rp:mEnemy")
    local inst = id and M.instances[id]
    if not inst or not inst.rt then return end
    removeElementData(source, "rp:mEnemy")
    inst.rt.aliveEnemies = max(0, (inst.rt.aliveEnemies or 1) - 1)
    inst.rt.enemyKilled = (inst.rt.enemyKilled or 0) + 1
    if isElement(killer) and getElementType(killer) == "vehicle" then killer = getVehicleController(killer) end
    if isElement(killer) and getElementType(killer) == "player" and inst.stats[killer] then
        inst.stats[killer].kills = inst.stats[killer].kills + 1
    end
    local ped = source
    setTimer(function() if isElement(ped) then destroyElement(ped) end end, 8000, 1)
    M.syncHud(inst)
end)


----------------------------------------------------------------
-- NPC de historia (Sweet, Ryder, Cesar): aparecen en cinematicas y, si ally=true, acompanan y disparan
----------------------------------------------------------------
local function upsertNpc(inst, n, place)
    local x, y, z, rot
    if n.rel and place then
        local r = rad(place[4])
        x, y, z, rot = place[1] - sin(r) * n.rel, place[2] + cos(r) * n.rel, place[3], place[4] + 180
    else
        x, y, z, rot = n.x, n.y, n.z, n.rot or 0
    end
    local ped = inst.npcs[n.key]
    if isElement(ped) then
        removePedFromVehicle(ped)
        setElementPosition(ped, x, y, z + 0.1)
        setElementRotation(ped, 0, 0, rot)
    else
        ped = createPed(n.skin, x, y, z + 0.1, rot)
        if not ped then return end
        setElementDimension(ped, inst.dim)
        setElementInterior(ped, inst.def.interior or 0)
        inst.npcs[n.key] = ped
        inst.entities.peds[#inst.entities.peds + 1] = ped
        setElementData(ped, "rp:mNpc", n.contact or n.key)
        if n.ally then
            setElementData(ped, "rp:mAlly", true)
            if n.weapon then giveWeapon(ped, n.weapon[1], n.weapon[2], true) end
            for stat = 69, 79 do setPedStat(ped, stat, 800) end
        end
    end
    if n.anim then setPedAnimation(ped, n.anim[1], n.anim[2], -1, n.anim[3] ~= false, false, false, false) else setPedAnimation(ped) end
    if not n.keep and not n.ally then inst.rt.npcTemp = inst.rt.npcTemp or {}; inst.rt.npcTemp[#inst.rt.npcTemp + 1] = n.key end
    return ped
end

local function boardNpc(inst, key, vehKey)
    local ped, veh = inst.npcs[key], inst.vehicleByKey and inst.vehicleByKey[vehKey]
    if not isElement(ped) or not isElement(veh) then return end
    removePedFromVehicle(ped)
    setPedAnimation(ped)
    for _, seat in ipairs({ 3, 2, 1 }) do
        if not getVehicleOccupant(veh, seat) and seat <= getVehicleMaxPassengers(veh) then
            warpPedIntoVehicle(ped, veh, seat)
            return
        end
    end
end

-- Los aliados no mueren (son los contactos del jugador)
addEventHandler("onPedDamage", root, function()
    if getElementData(source, "rp:mAlly") then setElementHealth(source, 100) end
end)

-- Si un aliado se queda lejos de todo el grupo, se teletransporta junto al jugador mas cercano
setTimer(function()
    for _, inst in pairs(M.instances) do
        if inst.state == "IN_PROGRESS" and inst.npcs then
            for _, ped in pairs(inst.npcs) do
                if isElement(ped) and getElementData(ped, "rp:mAlly") and not isPedInVehicle(ped) then
                    local x, y, z = getElementPosition(ped)
                    local near, nd
                    for _, m in ipairs(M.alive(inst)) do
                        local px, py, pz = getElementPosition(m)
                        local d = dist(px, py, pz, x, y, z)
                        if not nd or d < nd then near, nd = m, d end
                    end
                    if near and nd > 70 then
                        local px, py, pz = getElementPosition(near)
                        local veh = getPedOccupiedVehicle(near)
                        if veh then
                            for _, seat in ipairs({ 3, 2, 1 }) do
                                if seat <= getVehicleMaxPassengers(veh) and not getVehicleOccupant(veh, seat) then warpPedIntoVehicle(ped, veh, seat) break end
                            end
                        else
                            setElementPosition(ped, px + 1.5, py + 1.5, pz + 0.3)
                        end
                    end
                end
            end
        end
    end
end, 2000, 0)

----------------------------------------------------------------
-- Headshot a enemigos (el cliente avisa, el servidor valida)
----------------------------------------------------------------
addEvent("rp:missions:headshot", true)
addEventHandler("rp:missions:headshot", resourceRoot, function(ped, weapon)
    local p = client
    local inst = M.playerInst[p]
    if not inst or inst.state ~= "IN_PROGRESS" or not isElement(ped) or getElementType(ped) ~= "ped" then return end
    if getElementData(ped, "rp:mEnemy") ~= inst.id or isPedDead(ped) then return end
    weapon = tonumber(weapon) or 0
    if not ((weapon >= 22 and weapon <= 34) or weapon == 38) then return end
    local x, y, z = getElementPosition(p)
    local px, py, pz = getElementPosition(ped)
    if dist(x, y, z, px, py, pz) > 120 then return end
    killPed(ped, p, weapon, 9)
    if inst.stats[p] then inst.stats[p].heads = (inst.stats[p].heads or 0) + 1 end
    triggerClientEvent(p, "rp:missions:flash", resourceRoot, "HEADSHOT", "ok")
end)

----------------------------------------------------------------
-- Coreografia de actores en cinematicas (bloqueo de escena, estandar: docs/CINEMATICAS.md)
--   cutscene.actors = { {t=ms, npc="sweet", anim={block,name,loop}, rot=grados, walk={x,y,z,ms}, after={block,name,loop}}, ... }
----------------------------------------------------------------
local function runActor(inst, rt, a)
    if inst.destroyed or inst.rt ~= rt then return end
    local ped = inst.npcs and inst.npcs[a.npc]
    if not isElement(ped) then return end
    if a.rot then setElementRotation(ped, 0, 0, a.rot) end
    if a.anim then setPedAnimation(ped, a.anim[1], a.anim[2], -1, a.anim[3] ~= false, false, false, false) end
    if a.clear then setPedAnimation(ped) end
    local w = a.walk
    if w then
        local x0, y0, z0 = getElementPosition(ped)
        local steps = math.max(1, math.floor((w.ms or 2000) / 120))
        local ang = -math.deg(math.atan2(w.x - x0, w.y - y0))
        setElementRotation(ped, 0, 0, ang)
        setPedAnimation(ped, "PED", w.run and "run_player" or "WALK_player", -1, true, true, false, false)
        local n = 0
        local timer
        timer = setTimer(function()
            n = n + 1
            if not isElement(ped) or inst.destroyed then return end
            local f = n / steps
            setElementPosition(ped, x0 + (w.x - x0) * f, y0 + (w.y - y0) * f, z0 + ((w.z or z0) - z0) * f)
            if n >= steps then
                local after = a.after
                if after then setPedAnimation(ped, after[1], after[2], -1, after[3] ~= false, false, false, false)
                else setPedAnimation(ped) end
            end
        end, 120, steps)
        rt.actorTimers = rt.actorTimers or {}
        rt.actorTimers[#rt.actorTimers + 1] = timer
    end
end

local function scheduleActors(inst, rt, actors)
    rt.actorTimers = rt.actorTimers or {}
    for i = 1, #actors do
        local a = actors[i]
        rt.actorTimers[#rt.actorTimers + 1] = setTimer(function() runActor(inst, rt, a) end, math.max(1, a.t or 1), 1)
    end
end

----------------------------------------------------------------
-- Gestos y miradas ligados al dialogo (como el juego original: CTaskComplexGangLeader)
-- En GTA SA los gestos de conversacion (prtial_gngtlkA..H) son animaciones PARCIALES de un solo disparo:
-- se mezclan sobre la postura base y se eliminan solas; el juego lanza uno al azar cada pocos segundos
-- mientras el personaje habla. Nunca son un bucle sobre un personaje congelado.
--   cutscene.talk = false  desactiva el programador (por defecto activo)
--   line.gesture = {block, name}  fuerza un gesto concreto en esa linea
----------------------------------------------------------------
local GESTURES = {
    "prtial_gngtlkA", "prtial_gngtlkB", "prtial_gngtlkC", "prtial_gngtlkD",
    "prtial_gngtlkE", "prtial_gngtlkF", "prtial_gngtlkG", "prtial_gngtlkH",
}

local function speakerElement(inst, who)
    if who == "me" then return M.alive(inst)[1] end
    local ped = inst.npcs and inst.npcs[who]
    if isElement(ped) then return ped end
end

local function doGesture(inst, rt, speaker, forced, last)
    if inst.destroyed or inst.rt ~= rt or not isElement(speaker) then return end
    local block, name = "GANGS", nil
    if forced then
        block, name = forced[1], forced[2]
    else
        -- uno al azar, distinto del anterior
        local idx = math.random(#GESTURES)
        if idx == last.idx then idx = idx % #GESTURES + 1 end
        last.idx = idx
        name = GESTURES[idx]
    end
    -- un solo disparo, mezcla suave, sin quedarse congelado en el ultimo cuadro
    setPedAnimation(speaker, block, name, -1, false, false, false, false, 300)
end
-- ===== Mocap real (rp_mocap) =====
-- Si rp_mocap esta activo y tiene al personaje, los gestos son clips de mocap de las cinematicas del juego
-- (gesto de un disparo de ~3 s + idle en bucle entre medias); si no, se usan los gestos genericos de GANGS.
local WHO_CHAR = { sweet = "sweet", ryder = "ryder", cesar = "cesar", smoke = "smoke", me = "cj" }

local function mocapOn()
    local res = getResourceFromName("rp_mocap")
    return res and getResourceState(res) == "running"
end

local function mocapChar(who)
    local c = WHO_CHAR[who]
    if c and mocapOn() then
        local ok, has = pcall(function() return exports.rp_mocap:hasCharacter(c) end)
        if ok and has then return c end
    end
end

local function mocapPlay(inst, ped, char, kind, idx)
    pcall(function() exports.rp_mocap:play(inst.members, ped, char, kind, idx, kind == "idle") end)
end

local function mocapIdle(inst, ped, char)
    local ok, n = pcall(function() return exports.rp_mocap:getClipCount(char, "idle") end)
    if ok and n and n > 0 then mocapPlay(inst, ped, char, "idle", math.random(n)) end
end

-- Para todos los actores de la cinematica (NPC y jugadores)
function M.mocapStopCast(inst)
    if not mocapOn() then return end
    for _, ped in pairs(inst.npcs or {}) do if isElement(ped) then pcall(function() exports.rp_mocap:stop(inst.members, ped) end) end end
    for _, p in ipairs(inst.members) do if isElement(p) then pcall(function() exports.rp_mocap:stop(inst.members, p) end) end end
end

local function scheduleTalk(inst, rt, cutscene)
    if cutscene.talk == false then return end
    rt.talkTimers = rt.talkTimers or {}
    local sched = cutsceneSchedule(cutscene)
    local function later(ms, fn) rt.talkTimers[#rt.talkTimers + 1] = setTimer(fn, math.max(1, ms), 1) end

    -- Postura base: idle de mocap para cada actor mientras no gesticula
    local actorsChar = {}   -- [ped] = personaje
    for key, ped in pairs(inst.npcs or {}) do
        local c = mocapChar(key)
        if c and isElement(ped) then actorsChar[ped] = c end
    end
    for _, p in ipairs(M.alive(inst)) do
        local c = mocapChar("me")
        if c then actorsChar[p] = c end
    end
    do
        local n = 0
        for _ in pairs(actorsChar) do n = n + 1 end
        outputServerLog(("[rp_missions] cinematica etapa %d: rp_mocap=%s actores con mocap=%d"):format(inst.stage or 0, tostring(mocapOn() and true or false), n))
    end
    later(150, function()
        if inst.destroyed or inst.rt ~= rt then return end
        for ped, c in pairs(actorsChar) do if isElement(ped) then mocapIdle(inst, ped, c) end end
    end)

    for i, line in ipairs(cutscene.lines or {}) do
        local speaker = speakerElement(inst, line.who)
        if speaker then
            local s, e = sched[i].s, sched[i].e
            local last = {}
            local char = actorsChar[speaker]
            -- los demas miran a quien habla (la cabeza gira; rp_heads/bone_attach la siguen)
            later(s, function()
                if inst.destroyed or inst.rt ~= rt or not isElement(speaker) then return end
                local sx, sy, sz = getElementPosition(speaker)
                local listeners = {}
                for _, ped in pairs(inst.npcs or {}) do if ped ~= speaker and isElement(ped) then listeners[#listeners + 1] = ped end end
                for _, p in ipairs(M.alive(inst)) do if p ~= speaker then listeners[#listeners + 1] = p end end
                for _, l in ipairs(listeners) do pcall(setPedLookAt, l, sx, sy, sz + 0.6, e - s + 200, 400, speaker) end
            end)
            if char then
                -- Gestos de mocap: uno al empezar y otro cada ~3.4-4.4 s (dura 3 s); al terminar vuelve el idle
                local t = s + 300
                while t < e - 1200 do
                    later(t, function()
                        if inst.destroyed or inst.rt ~= rt or not isElement(speaker) then return end
                        local ok, idx = pcall(function() return exports.rp_mocap:pickClip(char, "gesture", last.idx) end)
                        if ok and idx then last.idx = idx mocapPlay(inst, speaker, char, "gesture", idx) end
                    end)
                    later(t + 3050, function()
                        if inst.destroyed or inst.rt ~= rt or not isElement(speaker) then return end
                        mocapIdle(inst, speaker, char)
                    end)
                    t = t + 3400 + math.random(0, 1000)
                end
            else
                -- sin mocap: gestos parciales genericos de GANGS, un disparo cada 1.5-2.6 s
                local t = s + 350
                local first = true
                while t < e - 700 do
                    local forced = first and line.gesture or nil
                    later(t, function() doGesture(inst, rt, speaker, forced, last) end)
                    first = false
                    t = t + 1500 + math.random(0, 1100)
                end
            end
        end
    end
end
----------------------------------------------------------------
-- HUD / sincronizacion
----------------------------------------------------------------
function M.hudData(inst)
    local rt, st = inst.rt, inst.rt and inst.rt.st
    local counters = {}
    if rt and st then
        if (rt.enemyTotal or 0) > 0 then counters[#counters + 1] = { label = "Enemigos", a = rt.enemyKilled or 0, b = rt.enemyTotalExpected or rt.enemyTotal } end
        if st.interact then
            local total = #st.interact.points
            counters[#counters + 1] = { label = st.interact.label or "Objetivos", a = rt.pointsDone or 0, b = total }
        end
        if st.waves and rt.waveIdx then counters[#counters + 1] = { label = "Oleada", a = min(rt.waveIdx, #st.waves), b = #st.waves } end
        if st.deliver and rt.vehicle and isElement(rt.vehicle) then
            counters[#counters + 1] = { label = "Vehiculo", a = max(0, floor(getElementHealth(rt.vehicle) / 10)), b = 100, pct = true }
        end
    end
    local members = {}
    for _, m in ipairs(inst.members) do
        members[#members + 1] = { p = m, name = M.nameOf(m), spec = inst.spec[m] and true or false, role = inst.roles[m] }
    end
    local points
    if rt and rt.points then
        points = {}
        for i, pt in ipairs(rt.points) do points[i] = { pt[1], pt[2], pt[3], rt.pointDone[i] and true or false } end
    end
    return {
        stage = inst.stage, total = #inst.def.stages, text = st and st.text, counters = counters, lives = inst.lives,
        diffLabel = inst.diff and inst.diff.label, elapsed = inst.startedAt and (now() - inst.startedAt) or 0,
        members = members, points = points, holdTime = st and st.interact and st.interact.time,
        holdText = st and st.interact and st.interact.text, cutscene = rt and rt.cutscene and true or false,
    }
end

function M.syncHud(inst)
    if inst.state ~= "IN_PROGRESS" then return end
    M.sendAll(inst, "rp:missions:hud", M.hudData(inst))
end

----------------------------------------------------------------
-- Inicio de etapa
----------------------------------------------------------------
local function freezeCast(inst, on, anim)
    for _, m in ipairs(M.alive(inst)) do
        if on then
            removePedFromVehicle(m)
            setElementFrozen(m, true)
            setElementData(m, "rp:noNeckFix", true)
            -- anim[3] = true: bucle; false: una vez y se queda en el ultimo cuadro
            if anim then setPedAnimation(m, anim[1], anim[2], -1, anim[3] ~= false, false, false, anim[3] == false) end
        else
            setElementFrozen(m, false)
            setElementData(m, "rp:noNeckFix", nil)
            setPedAnimation(m)
        end
    end
end

function M.startStage(inst, idx)
    if inst.destroyed or inst.state ~= "IN_PROGRESS" then return end
    local st = inst.def.stages[idx]
    if not st then return M.finish(inst, true) end
    clearTargets(inst)
    inst.stage = idx
    local rt = {
        idx = idx, st = st, startedAt = now(), holders = {}, pointDone = {}, pointProg = {}, pointsDone = 0,
        enemyKilled = 0, aliveEnemies = 0, comp = {}, groups = {}, targets = {},
    }
    inst.rt = rt
    if st.snap then inst.snapPoint = st.snap end
    inst.vehicleByKey = inst.vehicleByKey or {}
    inst.objectByKey = inst.objectByKey or {}

    -- Vehiculos y props de la etapa
    for _, v in ipairs(st.vehicles or {}) do
        local veh = createVehicle(v.model, v.x, v.y, v.z, 0, 0, v.rot or 0)
        if veh then
            setElementDimension(veh, inst.dim)
            setElementInterior(veh, inst.def.interior or 0)
            if v.color then setVehicleColor(veh, v.color[1], v.color[2], v.color[1], v.color[2]) end
            setVehicleEngineState(veh, true)
            setElementData(veh, "rp:mission", inst.id)
            inst.entities.vehicles[#inst.entities.vehicles + 1] = veh
            inst.vehicleByKey[v.key] = veh
            local bl = createBlipAttachedTo(veh, 0, 2, ACCENT[1], ACCENT[2], ACCENT[3], 255, 0, 9999)
            setElementDimension(bl, inst.dim)
            setElementData(bl, "rp:radarEdge", true)
            showOnlyTo(inst, bl)
            rt.targets["veh_" .. v.key] = { bl }
        end
    end
    for _, o in ipairs(st.objects or {}) do
        local obj = createObject(o.model, o.x, o.y, o.z)
        if obj then
            setElementDimension(obj, inst.dim)
            setElementInterior(obj, inst.def.interior or 0)
            inst.entities.objects[#inst.entities.objects + 1] = obj
            inst.objectByKey[o.key] = obj
        end
    end

    -- NPC de historia
    inst.npcs = inst.npcs or {}
    for _, n in ipairs(st.npcs or (st.cutscene and st.cutscene.npcs) or {}) do upsertNpc(inst, n, st.cutscene and st.cutscene.place) end
    if st.boardNpc then boardNpc(inst, st.boardNpc[1], st.boardNpc[2]) end

    -- Cinematica: baja a todos de los vehiculos, aparta los vehiculos del escenario, coloca al grupo, lo congela y avisa a los clientes
    if st.cutscene then
        rt.cutscene = true
        local c = st.cutscene

        -- 1) Nadie puede empezar la cinematica dentro de un auto (al llegar en el Greenwood el jugador sigue sentado y la animacion
        --    chocaria con el vehiculo): se les baja y se espera un instante antes de colocarlos
        local inCar = false
        for _, m in ipairs(M.alive(inst)) do
            if isPedInVehicle(m) then inCar = true removePedFromVehicle(m) end
        end
        for _, ped in pairs(inst.npcs or {}) do
            if isElement(ped) and isPedInVehicle(ped) then inCar = true removePedFromVehicle(ped) end
        end

        -- 2) Los vehiculos de la mision que quedaron en el escenario se apartan (si no, los actores se colocan dentro del auto)
        if c.place then
            local p = c.place
            local r = rad(p[4])
            local fx, fy = -sin(r), cos(r)             -- hacia donde mira el grupo
            rt.parkedVehicles = {}
            for _, veh in ipairs(inst.entities.vehicles) do
                if isElement(veh) then
                    local vx, vy, vz = getElementPosition(veh)
                    if dist(vx, vy, vz, p[1], p[2], p[3]) < 10 then
                        setElementVelocity(veh, 0, 0, 0)
                        setElementPosition(veh, p[1] - fx * 11 + cos(r) * 5, p[2] - fy * 11 + sin(r) * 5, vz + 0.2)
                        setElementRotation(veh, 0, 0, p[4] + 90)
                        setElementFrozen(veh, true)
                        rt.parkedVehicles[#rt.parkedVehicles + 1] = veh
                    end
                end
            end
        end

        local function beginCutscene()
            if inst.destroyed or inst.rt ~= rt or rt.completing then return end
            if c.place then
                local p = c.place
                local members = M.alive(inst)
                for i, m in ipairs(members) do
                    local off = (i - (#members + 1) / 2) * (p.spread or 1.4)
                    local a = rad(p[4])   -- perpendicular a la mirada: lado a lado, no en fila
                    setElementPosition(m, p[1] + cos(a) * off, p[2] + sin(a) * off, p[3])
                    setElementRotation(m, 0, 0, p[4])
                end
            end
            freezeCast(inst, true, c.anim)
            if c.actors then scheduleActors(inst, rt, c.actors) end
            scheduleTalk(inst, rt, c)
            M.sendAll(inst, "rp:missions:cutscene", idx)
            rt.cutsceneTimer = setTimer(function() if inst.rt == rt then M.completeStage(inst, false) end end, totalCutsceneTime(st), 1)
        end
        if inCar then setTimer(beginCutscene, 700, 1) else beginCutscene() end
        M.syncHud(inst)
        return
    end
    -- Objetivos de la etapa
    local gt = st.goto
    if gt then addTarget(inst, gt[1], gt[2], gt[3], gt[4] or 6, ACCENT, "goto") end
    if st.getin and inst.vehicleByKey[st.getin] then rt.vehicle = inst.vehicleByKey[st.getin] end
    if st.deliver then
        local d = st.deliver
        rt.vehicle = inst.vehicleByKey[d.vehicle]
        addTarget(inst, d.x, d.y, d.z, d.r or 8, ACCENT, "deliver")
        rt.ambushDone = {}
    end
    if st.interact then
        rt.points = st.interact.points
        for i, pt in ipairs(st.interact.points) do addTarget(inst, pt[1], pt[2], pt[3], 1.3, ACCENT, "pt" .. i) end
    end
    if st.enemies then
        rt.enemyTotalExpected = 0
        for gi, g in ipairs(st.enemies) do rt.enemyTotalExpected = rt.enemyTotalExpected + groupCount(inst, g) end
        rt.enemyTotal = rt.enemyTotalExpected
        rt.countedGroup = true
        if not st.goto then
            local g = st.enemies[1]
            addTarget(inst, g.x, g.y, g.z, 8, DANGER, "foes")
        end
    end
    if st.waves then
        rt.waveIdx = 0
        rt.waveCooldown = now() + 1500
        rt.enemyTotalExpected = 0
        for _, g in ipairs(st.waves) do rt.enemyTotalExpected = rt.enemyTotalExpected + groupCount(inst, g) end
        rt.enemyTotal = rt.enemyTotalExpected
        rt.countedGroup = true
    end

    if st.radio then
        setTimer(function() if inst.rt == rt and not inst.destroyed then M.sendAll(inst, "rp:missions:radio", idx, st.radio) end end, 700, 1)
    end
    M.sendAll(inst, "rp:missions:stage", inst.stage, #inst.def.stages, st.text)
    M.syncHud(inst)
end

----------------------------------------------------------------
-- Interaccion (mantener E)
----------------------------------------------------------------
function M.releaseHold(inst, p)
    local rt = inst.rt
    if not rt or not rt.holders[p] then return end
    rt.holders[p] = nil
    if isElement(p) then
        setElementFrozen(p, false)
        setPedAnimation(p)
        triggerClientEvent(p, "rp:missions:progress", resourceRoot, nil)
    end
end

addEventHandler("rp:missions:hold", resourceRoot, function(point)
    local p = client
    local inst = M.playerInst[p]
    if not inst or inst.state ~= "IN_PROGRESS" or not inst.rt or not inst.rt.st.interact then return end
    local rt = inst.rt
    if point == false or point == nil then return M.releaseHold(inst, p) end
    point = floor(tonumber(point) or 0)
    local pt = rt.points[point]
    if not pt or rt.pointDone[point] or inst.spec[p] or isPedDead(p) or isPedInVehicle(p) or rt.holders[p] then return end
    local x, y, z = getElementPosition(p)
    if dist(x, y, z, pt[1], pt[2], pt[3]) > MISSIONS.HOLD_RANGE + 1.2 then return end
    rt.holders[p] = point
    setElementFrozen(p, true)
    local a = rt.st.interact.anim
    if a then setPedAnimation(p, a[1], a[2], -1, true, false, false, false) end
    -- mira hacia el punto
    local ang = -math.deg(math.atan2(pt[1] - x, pt[2] - y))
    setElementRotation(p, 0, 0, ang)
end)

local function tickInteract(inst, rt)
    local it = rt.st.interact
    for p, point in pairs(rt.holders) do
        if not isElement(p) or isPedDead(p) or inst.spec[p] then
            rt.holders[p] = nil
        elseif rt.pointDone[point] then
            M.releaseHold(inst, p)
        else
            rt.pointProg[point] = (rt.pointProg[point] or 0) + MISSIONS.TICK
            local pct = min(1, rt.pointProg[point] / it.time)
            triggerClientEvent(p, "rp:missions:progress", resourceRoot, pct, it.text)
            if pct >= 1 then
                rt.pointDone[point] = true
                rt.pointsDone = rt.pointsDone + 1
                removeTarget(inst, "pt" .. point)
                local key = rt.points[point][4]
                local obj = key and inst.objectByKey[key]
                if isElement(obj) then destroyElement(obj) end
                for q, pi in pairs(rt.holders) do
                    if pi == point then
                        if inst.stats[q] then inst.stats[q].objs = inst.stats[q].objs + 1 end
                        M.releaseHold(inst, q)
                    end
                end
                M.sendAll(inst, "rp:missions:flash", ("%s %d/%d"):format(it.text or "Objetivo", rt.pointsDone, #rt.points), "ok")
                M.syncHud(inst)
            end
        end
    end
    return rt.pointsDone >= #rt.points
end

----------------------------------------------------------------
-- Bucle
----------------------------------------------------------------
local function allAliveIn(inst, test)
    local list = M.alive(inst)
    if #list == 0 then return false end
    for _, m in ipairs(list) do if not test(m) then return false end end
    return true
end

local function tickEnemies(inst, rt, st)
    local done = true
    if st.enemies then
        for gi, g in ipairs(st.enemies) do
            if not rt.groups[gi] then
                if anyoneNear(inst, g.x, g.y, g.z, MISSIONS.SPAWN_RANGE) then
                    rt.groups[gi] = true
                    spawnEnemies(inst, g, groupCount(inst, g))
                    M.syncHud(inst)
                end
                done = false
            end
        end
        if rt.aliveEnemies > 0 then done = false end
    end
    if st.waves then
        local wave = st.waves[rt.waveIdx or 0]
        if (rt.waveIdx or 0) == 0 or (rt.aliveEnemies == 0 and rt.waveIdx < #st.waves and now() > (rt.waveCooldown or 0)) then
            local nxt = st.waves[(rt.waveIdx or 0) + 1]
            if nxt and anyoneNear(inst, nxt.x, nxt.y, nxt.z, MISSIONS.SPAWN_RANGE) and now() > (rt.waveCooldown or 0) then
                rt.waveIdx = (rt.waveIdx or 0) + 1
                rt.waveCooldown = now() + 4000
                spawnEnemies(inst, nxt, groupCount(inst, nxt))
                M.sendAll(inst, "rp:missions:flash", ("Oleada %d/%d: %s"):format(rt.waveIdx, #st.waves, nxt.label or "enemigos"), "warn")
                M.syncHud(inst)
            end
        end
        if rt.waveIdx < #st.waves or rt.aliveEnemies > 0 or rt.waveIdx == 0 then done = false end
    end
    return done
end

local function tickDeliver(inst, rt, st)
    local d = st.deliver
    local veh = rt.vehicle
    if not isElement(veh) or isVehicleBlown(veh) or getElementHealth(veh) < (d.minHealth or 1) then
        M.finish(inst, false, "El vehiculo de la mision fue destruido.")
        return false
    end
    local vx, vy, vz = getElementPosition(veh)
    for i, a in ipairs(d.ambush or {}) do
        if not rt.ambushDone[i] and dist(vx, vy, vz, a.at[1], a.at[2], a.at[3]) < 140 then
            rt.ambushDone[i] = true
            inst.rt.countedGroup = false
            spawnEnemies(inst, a.group, groupCount(inst, a.group))
            inst.rt.countedGroup = true
            M.sendAll(inst, "rp:missions:flash", "¡Emboscada!", "warn")
            M.syncHud(inst)
        end
    end
    if dist(vx, vy, vz, d.x, d.y, d.z) <= (d.r or 8) then
        local seated
        for _, m in ipairs(M.alive(inst)) do if getPedOccupiedVehicle(m) == veh then seated = true end end
        if seated then return true end
    end
    return false
end

function M.tick(inst)
    if inst.destroyed or inst.state ~= "IN_PROGRESS" then return end
    local rt = inst.rt
    if not rt or rt.completing or rt.cutscene then return end
    local st = rt.st

    if rt.lastHud == nil or now() - rt.lastHud > 1500 then rt.lastHud = now(); M.syncHud(inst) end

    local ok = true
    if st.goto then
        if not rt.comp.goto then
            local g = st.goto
            rt.comp.goto = allAliveIn(inst, function(m)
                local x, y, z = getElementPosition(m)
                if dist(x, y, z, g[1], g[2], g[3]) > (g[4] or 6) then return false end
                if g.vehicle and not isPedInVehicle(m) then return false end
                return true
            end)
            if rt.comp.goto then removeTarget(inst, "goto") end
        end
        ok = ok and rt.comp.goto
    end
    if st.getin then
        local veh = inst.vehicleByKey[st.getin]
        if not rt.comp.getin then
            rt.comp.getin = isElement(veh) and allAliveIn(inst, function(m) return getPedOccupiedVehicle(m) == veh end)
            if rt.comp.getin then removeTarget(inst, "veh_" .. st.getin) end
        end
        if not isElement(veh) then M.finish(inst, false, "El vehiculo de la mision se perdio.") return end
        ok = ok and rt.comp.getin
    end
    if st.enemies or st.waves then
        local d = tickEnemies(inst, rt, st)
        if d and not rt.comp.foes then removeTarget(inst, "foes") end
        rt.comp.foes = d
        ok = ok and d
    end
    if st.interact then
        local d = tickInteract(inst, rt)
        rt.comp.interact = d
        ok = ok and d
    end
    if st.deliver then
        if inst.state ~= "IN_PROGRESS" then return end
        local d = tickDeliver(inst, rt, st)
        if inst.state ~= "IN_PROGRESS" then return end
        rt.comp.deliver = d
        if d then
            for _, m in ipairs(M.alive(inst)) do
                if getPedOccupiedVehicle(m) == rt.vehicle and inst.stats[m] then inst.stats[m].objs = inst.stats[m].objs + 1 end
            end
        end
        ok = ok and d
    end
    if st.wait then ok = ok and (now() - rt.startedAt >= st.wait) end

    if ok then M.completeStage(inst, false) end
end

function M.completeStage(inst, forced)
    local rt = inst.rt
    if not rt or rt.completing or inst.state ~= "IN_PROGRESS" then return end
    rt.completing = true
    if isTimer(rt.cutsceneTimer) then killTimer(rt.cutsceneTimer) end
    for _, t in ipairs(rt.actorTimers or {}) do if isTimer(t) then killTimer(t) end end
    for _, t in ipairs(rt.talkTimers or {}) do if isTimer(t) then killTimer(t) end end
    for p in pairs(rt.holders) do M.releaseHold(inst, p) end
    if rt.cutscene then
        freezeCast(inst, false)
        for _, key in ipairs(rt.npcTemp or {}) do
            local ped = inst.npcs[key]
            if isElement(ped) then destroyElement(ped) end
            inst.npcs[key] = nil
        end
        M.mocapStopCast(inst)
        for _, veh in ipairs(rt.parkedVehicles or {}) do if isElement(veh) then setElementFrozen(veh, false) end end
        for key, ped in pairs(inst.npcs or {}) do if isElement(ped) then setPedAnimation(ped) end end
        M.sendAll(inst, "rp:missions:cutsceneEnd")
    else
        M.sendAll(inst, "rp:missions:stageDone", inst.stage)
    end
    clearTargets(inst)
    if forced then
        for _, ped in ipairs(inst.entities.peds) do if isElement(ped) then destroyElement(ped) end end
        for k, o in pairs(inst.objectByKey or {}) do if isElement(o) then destroyElement(o) end end
    end
    -- Los enemigos que queden se retiran al cambiar de etapa; vehiculos y props se arrastran por clave
    local nextIdx = inst.stage + 1
    rt.nextTimer = setTimer(function()
        if inst.destroyed or inst.state ~= "IN_PROGRESS" then return end
        for _, ped in ipairs(inst.entities.peds) do
            if isElement(ped) and getElementData(ped, "rp:mEnemy") then destroyElement(ped) end
        end
        M.startStage(inst, nextIdx)
    end, rt.cutscene and 700 or 1600, 1)
end
