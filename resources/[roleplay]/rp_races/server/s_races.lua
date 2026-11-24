--[[
    rp_races / server / s_races.lua

    Carreras estilo GTA Online (RF-01..RF-19).

    Flujo: marker/menu -> sala (lobby) -> cuenta atras -> carrera -> resultados + votacion -> sala/salida.
    Cada carrera vive en su propia dimension (RACE.DIM_BASE + n) con vehiculos, IA, markers y props propios.

    Comandos:  /carreras  (tambien F5)  menu rapido: crear sala, unirse a una, o a una aleatoria
               /salircarrera            abandonar la carrera/sala
    Eventos cliente->servidor: rp:races:open|create|join|random|leave|setting|invite|start|respawn|vote
    Exports: getPlayerRace(player) -> id o false
]]

local floor, sqrt, abs, rad, deg, atan2 = math.floor, math.sqrt, math.abs, math.rad, math.deg, math.atan2

local races = {}          -- [id] = race
local playerRace = {}     -- [player] = race
local usedDims = {}
local nextId = 1
local invites = {}        -- [player] = { race = id, expires = tick }

for _, ev in ipairs({ "open", "create", "join", "random", "leave", "setting", "invite", "start", "respawn", "vote" }) do
    addEvent("rp:races:" .. ev, true)
end
addEvent("rp:onCharacterLogout", false)

local function notify(p, t, k, d) pcall(function() exports.rp_notify:notify(p, t, k, d) end) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p)
    return exports.rp_characters:getPlayerCharacterName(p) or (getPlayerName(p):gsub("_", " "))
end
local function money(n) return "$" .. tostring(n):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "") end
local function now() return getTickCount() end

function getPlayerRace(p) local r = playerRace[p]; return r and r.id or false end

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function humans(race)
    local list = {}
    for _, E in ipairs(race.entities) do if E.kind == "player" then list[#list + 1] = E end end
    return list
end

local function sendHumans(race, event, ...)
    for _, E in ipairs(race.entities) do
        if E.kind == "player" and isElement(E.player) then triggerClientEvent(E.player, event, resourceRoot, ...) end
    end
end

local function headingTo(x1, y1, x2, y2) return deg(atan2(-(x2 - x1), y2 - y1)) end

local function gridPos(track, i)
    local s = track.start
    local row, side = floor((i - 1) / 2), (i % 2 == 1) and -1 or 1
    local r = rad(s[4])
    local fx, fy = -math.sin(r), math.cos(r)
    local rx, ry = math.cos(r), math.sin(r)
    local back = row * RACE.GRID_ROW_GAP + 2
    return s[1] - fx * back + rx * side * RACE.GRID_SIDE, s[2] - fy * back + ry * side * RACE.GRID_SIDE, s[3] + 1, s[4]
end

----------------------------------------------------------------
-- Estado del jugador (RF-19)
----------------------------------------------------------------
local function saveState(p)
    local x, y, z = getElementPosition(p)
    local _, _, rz = getElementRotation(p)
    return { x = x, y = y, z = z, rz = rz, int = getElementInterior(p), dim = getElementDimension(p),
             hp = getElementHealth(p), armor = getPedArmor(p), skin = getElementModel(p) }
end

local function restoreState(p, st)
    if not isElement(p) then return end
    if isPedInVehicle(p) then removePedFromVehicle(p) end
    setElementFrozen(p, false)
    toggleAllControls(p, true, true, false)
    if not st then setElementDimension(p, 0) setElementInterior(p, 0) return end
    setElementInterior(p, st.int)
    setElementDimension(p, st.dim)
    if isPedDead(p) then return end   -- el hospital (rp_characters/rp_injury) se encarga
    setElementPosition(p, st.x, st.y, st.z)
    setElementRotation(p, 0, 0, st.rz)
    setElementHealth(p, st.hp)
    setPedArmor(p, st.armor)
end

----------------------------------------------------------------
-- Mapa de la pista (RF-06): props solo en la dimension de la carrera
----------------------------------------------------------------
local function buildProps(race)
    for _, o in ipairs(race.objects) do if isElement(o) then destroyElement(o) end end
    race.objects = {}
    local t = race.track
    local function add(model, x, y, z, rz)
        local o = createObject(model, x, y, z, 0, 0, rz or 0)
        if o then setElementDimension(o, race.dim) setElementInterior(o, 0) race.objects[#race.objects + 1] = o end
    end
    -- conos que marcan la linea de salida/meta
    local r = rad(t.start[4])
    local fx, fy, rx, ry = -math.sin(r), math.cos(r), math.cos(r), math.sin(r)
    for _, side in ipairs({ -1, 1 }) do
        for k = 0, 3 do
            add(1238, t.start[1] + rx * side * 6.5 - fx * k * 3, t.start[2] + ry * side * 6.5 - fy * k * 3, t.start[3] - 0.3)
        end
    end
    for _, o in ipairs(t.objects or {}) do add(o[1], o[2], o[3], o[4], o[7]) end
end

local function clearEntityEnv(E)
    for _, k in ipairs({ "marker", "blip", "ped", "veh" }) do
        if isElement(E[k]) then destroyElement(E[k]) end
        E[k] = nil
    end
end

----------------------------------------------------------------
-- Sala (lobby)
----------------------------------------------------------------
local function trackNames() local n = {} for i, t in ipairs(RACE_TRACKS) do n[i] = t.name end return n end

local function lobbyPayload(race, forPlayer)
    local E = race.byPlayer[forPlayer]
    local names = {}
    for _, h in ipairs(humans(race)) do names[#names + 1] = h.name end
    local t = race.track
    local data = {
        id = race.id, state = race.state, track = race.trackIdx, trackName = t.name, trackLength = t.length, trackNames = trackNames(),
        isHost = (race.host == forPlayer), hostName = race.host and nameOf(race.host) or "-",
        settings = race.s, players = names, max = RACE.MAX_PLAYERS,
        secLeft = race.deadline and math.max(0, floor((race.deadline - now()) / 1000)) or 0,
    }
    if data.isHost then
        local inv = {}
        for _, p in ipairs(getElementsByType("player")) do
            if not playerRace[p] and characterOf(p) and #inv < 40 then inv[#inv + 1] = getPlayerName(p) end
        end
        data.invitable = inv
    end
    return data
end

local function sendLobby(race)
    for _, E in ipairs(race.entities) do
        if E.kind == "player" then triggerClientEvent(E.player, "rp:races:lobby", resourceRoot, lobbyPayload(race, E.player)) end
    end
end

local function placeInLobby(race, E)
    local p = E.player
    local x, y, z, rz = gridPos(race.track, 1)
    local idx = (#humans(race))
    local r = rad(rz)
    local bx = x - (-math.sin(r)) * (14 + idx * 1.5) + math.cos(r) * ((idx % 2 == 0) and -1 or 1) * 2
    local by = y - math.cos(r) * (14 + idx * 1.5) + math.sin(r) * ((idx % 2 == 0) and -1 or 1) * 2
    setElementInterior(p, 0)
    setElementDimension(p, race.dim)
    setElementPosition(p, bx, by, z + 0.5)
    setElementRotation(p, 0, 0, rz)
    setElementFrozen(p, true)
end

local function newEntityForPlayer(race, p)
    local E = { kind = "player", player = p, name = nameOf(p), cp = 1, lap = 1, times = {}, skin = getElementModel(p) }
    return E
end

local function allocDim()
    for i = 0, 300 do
        local d = RACE.DIM_BASE + i
        if not usedDims[d] then usedDims[d] = true return d end
    end
end

local function createRace(host, trackIdx)
    local dim = allocDim()
    if not dim then return nil end
    local race = {
        id = nextId, dim = dim, trackIdx = trackIdx, track = RACE_TRACKS[trackIdx], host = host,
        state = "lobby", entities = {}, byPlayer = {}, objects = {}, saved = {}, votes = {},
        s = { class = RACE.DEFAULTS.class, laps = RACE.DEFAULTS.laps, hour = RACE.DEFAULTS.hour, weather = RACE.DEFAULTS.weather,
              ghost = RACE.DEFAULTS.ghost, ai = RACE.DEFAULTS.ai, difficulty = RACE.DEFAULTS.difficulty, catchup = RACE.DEFAULTS.catchup },
        deadline = now() + RACE.LOBBY_TIME * 1000, finishedCount = 0, timers = {},
    }
    nextId = nextId + 1
    races[race.id] = race
    buildProps(race)
    return race
end

local function joinRace(race, p)
    if playerRace[p] then return false end
    local E = newEntityForPlayer(race, p)
    race.saved[p] = saveState(p)
    race.entities[#race.entities + 1] = E
    race.byPlayer[p] = E
    playerRace[p] = race
    setElementData(p, "rp:race", race.id, false)
    placeInLobby(race, E)
    toggleAllControls(p, false, true, false)
    triggerClientEvent(p, "rp:races:enter", resourceRoot, race.id)
    sendLobby(race)
    return true
end

----------------------------------------------------------------
-- Progreso, ranking (RF-09) y objetivo visible solo para el piloto (RF-08)
----------------------------------------------------------------
local function progressOf(race, E) return (E.lap - 1) * #race.track.cps + (E.cp - 1) end

local function computeRanks(race)
    local list = {}
    for _, E in ipairs(race.entities) do
        if isElement(E.veh) then
            local cp = race.track.cps[E.cp]
            local x, y = getElementPosition(E.veh)
            E.dNext = sqrt((cp[1] - x) ^ 2 + (cp[2] - y) ^ 2)
        else
            E.dNext = E.dNext or 1e9
        end
        list[#list + 1] = E
    end
    table.sort(list, function(a, b)
        if a.finished ~= b.finished then return a.finished == true end
        if a.finished and b.finished then return a.place < b.place end
        if a.dnf ~= b.dnf then return not a.dnf end
        local pa, pb = progressOf(race, a), progressOf(race, b)
        if pa ~= pb then return pa > pb end
        return a.dNext < b.dNext
    end)
    for i, E in ipairs(list) do E.rank = i end
    race.ranked = list
    return list
end

local function updateTarget(race, E)
    if E.kind ~= "player" or not isElement(E.marker) then return end
    local cps = race.track.cps
    local cp = cps[E.cp]
    local lastOne = (E.cp == #cps)
    setElementPosition(E.marker, cp[1], cp[2], cp[3] + 0.5)
    local nxt = lastOne and (E.lap < race.s.laps and cps[1] or nil) or cps[E.cp + 1]
    if lastOne and not nxt then
        setMarkerType(E.marker, "ring")
        setMarkerColor(E.marker, 255, 255, 255, 190)
    else
        setMarkerType(E.marker, "checkpoint")
        setMarkerColor(E.marker, 255, 190, 30, 170)
        if nxt then setMarkerTarget(E.marker, nxt[1], nxt[2], nxt[3] + 0.5) end
    end
    if isElement(E.blip) then setElementPosition(E.blip, cp[1], cp[2], cp[3]) end
end

local function makeTarget(race, E)
    local cp = race.track.cps[1]
    E.marker = createMarker(cp[1], cp[2], cp[3], "checkpoint", 9, 255, 190, 30, 170)
    setElementDimension(E.marker, race.dim)
    setElementVisibleTo(E.marker, root, false)
    setElementVisibleTo(E.marker, E.player, true)
    E.blip = createBlip(cp[1], cp[2], cp[3], 0, 2, 255, 190, 30, 255, 0, 99999, E.player)
    setElementDimension(E.blip, race.dim)
    updateTarget(race, E)
end

----------------------------------------------------------------
-- Respawn (RF-10)
----------------------------------------------------------------
local function respawnEntity(race, E, t)
    if not isElement(E.veh) then return end
    local track = race.track
    local cps = track.cps
    local px, py, pz
    if E.cp > 1 then local c = cps[E.cp - 1]; px, py, pz = c[1], c[2], c[3]
    else local s = track.start; px, py, pz = s[1], s[2], s[3] end
    local nx = cps[E.cp]
    local rz = headingTo(px, py, nx[1], nx[2])
    local veh = E.veh
    fixVehicle(veh)
    setElementFrozen(veh, false)
    setElementPosition(veh, px, py, pz + 1)
    setElementRotation(veh, 0, 0, rz)
    setElementVelocity(veh, 0, 0, 0)
    setElementAngularVelocity(veh, 0, 0, 0)
    E.lastRespawn, E.flipSince, E.stillSince, E.kinematic = t, nil, nil, false
    if E.kind == "bot" then E.ni = aiNearestAhead(track, px, py, rz) end
end

----------------------------------------------------------------
-- Fin de carrera, recompensas (RF-16..RF-18)
----------------------------------------------------------------
local function cleanupRaceEntities(race)
    for _, E in ipairs(race.entities) do
        if E.kind == "bot" then clearEntityEnv(E) else
            if isElement(E.player) and isPedInVehicle(E.player) then removePedFromVehicle(E.player) end
            clearEntityEnv(E)
        end
    end
    for i = #race.entities, 1, -1 do if race.entities[i].kind == "bot" then table.remove(race.entities, i) end end
end

local function killTimers(race)
    for _, t in pairs(race.timers) do if isTimer(t) then killTimer(t) end end
    race.timers = {}
end

local function leavePlayer(race, p, silent)
    local E = race.byPlayer[p]
    if not E then return end
    race.byPlayer[p] = nil
    for i, e in ipairs(race.entities) do if e == E then table.remove(race.entities, i) break end end
    if isElement(p) and isPedInVehicle(p) then removePedFromVehicle(p) end
    clearEntityEnv(E)
    local st = race.saved[p]
    race.saved[p] = nil
    playerRace[p] = nil
    invites[p] = nil
    if isElement(p) then
        restoreState(p, st)
        setElementData(p, "rp:race", false, false)
        triggerClientEvent(p, "rp:races:left", resourceRoot)
        pcall(function() exports.rp_characters:saveCharacter(p) end)
        if not silent then notify(p, "Saliste de la carrera.", "info") end
    end
end

local function destroyRace(race)
    killTimers(race)
    for _, E in ipairs({ unpack(race.entities) }) do
        if E.kind == "player" then leavePlayer(race, E.player, true) end
    end
    for _, E in ipairs(race.entities) do clearEntityEnv(E) end
    for _, o in ipairs(race.objects) do if isElement(o) then destroyElement(o) end end
    usedDims[race.dim] = nil
    races[race.id] = nil
end

local function afterLeave(race)
    local hs = humans(race)
    if #hs == 0 then return destroyRace(race) end
    if not race.byPlayer[race.host] then
        race.host = hs[1].player
        notify(race.host, "Ahora eres el anfitrion de la sala.", "info")
    end
end

local function dropPlayer(p)
    local race = playerRace[p]
    if not race then return end
    local E = race.byPlayer[p]
    if race.state == "running" and E and not E.finished then E.dnf = true end
    leavePlayer(race, p, true)
    if races[race.id] then
        afterLeave(race)
        if races[race.id] and race.state == "lobby" then sendLobby(race) end
    end
end

local endRace -- adelante

local function checkEnd(race)
    if race.state ~= "running" then return end
    local pending = 0
    for _, E in ipairs(race.entities) do
        if E.kind == "player" and not E.finished and not E.dnf then pending = pending + 1 end
    end
    if race.botOnly then
        for _, E in ipairs(race.entities) do if not E.finished then pending = pending + 1 end end
    end
    if pending == 0 then endRace(race) end
end

local function rewardFor(race, E, rank, total, duration)
    local posF = math.max(0.1, 1 - (rank - 1) * 0.16)
    local durF = raceClamp(duration / 180, 0.5, 1.5)
    local bots = 0
    for _, e in ipairs(race.entities) do if e.kind == "bot" then bots = bots + 1 end end
    local eff = total - bots * 0.5          -- las IA cuentan la mitad (anti-farmeo)
    if eff < 2 then eff = 1.2 end
    local m = floor((RACE.REWARD_BASE + RACE.REWARD_PER_RACER * eff) * posF * durF)
    local xp = floor((RACE.XP_BASE + RACE.XP_PER_RACER * eff) * posF * durF)
    if E.dnf then m, xp = floor(m * 0.15), floor(xp * 0.2) end
    return m, xp
end

endRace = function(race)
    if race.state ~= "running" then return end
    race.state = "results"
    killTimers(race)
    local t = now()
    local duration = (t - race.t0) / 1000
    for _, E in ipairs(race.entities) do
        if E.kind == "bot" then aiStop(E) end
        if isElement(E.veh) then setElementFrozen(E.veh, true) end
        if not E.finished and E.kind == "player" then E.dnf = true end
        if isElement(E.marker) then destroyElement(E.marker) E.marker = nil end
        if isElement(E.blip) then destroyElement(E.blip) E.blip = nil end
    end
    aiFlush(race)
    local ranked = computeRanks(race)
    local total = #ranked
    local rows = {}
    for i, E in ipairs(ranked) do
        local mny, xp = 0, 0
        if E.kind == "player" then
            mny, xp = rewardFor(race, E, i, total, duration)
            E.reward = { money = mny, xp = xp }
            if isElement(E.player) then
                givePlayerMoney(E.player, mny)
                pcall(function() exports.rp_characters:saveCharacter(E.player) end)
                pcall(function() exports.rp_levels:giveXP(E.player, xp, "carrera") end)
            end
        end
        local lapsDone = (E.lap - 1)
        rows[#rows + 1] = { pos = i, name = E.name, bot = E.kind == "bot", time = E.finished and E.finishTime or nil,
                            best = E.best, dnf = (not E.finished), money = mny, xp = xp, laps = lapsDone }
    end
    race.voteEnd = t + RACE.VOTE_TIME * 1000
    race.votes = {}
    local tracks = {}
    for i, tr in ipairs(RACE_TRACKS) do tracks[i] = tr.name end
    sendHumans(race, "rp:races:results", { rows = rows, tracks = tracks, voteSecs = RACE.VOTE_TIME, trackIdx = race.trackIdx,
                                           duration = floor(duration) })
    race.timers.vote = setTimer(function() race.resolveVote() end, RACE.VOTE_TIME * 1000, 1)
end

local function toLobby(race, trackIdx)
    killTimers(race)
    cleanupRaceEntities(race)
    race.trackIdx, race.track = trackIdx, RACE_TRACKS[trackIdx]
    race.state = "lobby"
    race.finishedCount, race.dnfEnd, race.votes = 0, nil, {}
    for _, E in ipairs(race.entities) do
        E.cp, E.lap, E.times, E.best, E.finished, E.dnf, E.place, E.finishTime, E.reward = 1, 1, {}, nil, nil, nil, nil, nil, nil
        E.lastRespawn = nil
    end
    buildProps(race)
    for _, E in ipairs(race.entities) do
        placeInLobby(race, E)
        toggleAllControls(E.player, false, true, false)
    end
    race.deadline = now() + RACE.REGROUP_TIME * 1000
    sendHumans(race, "rp:races:envReset")
    sendLobby(race)
end

-- se define en startRace
local startRace

----------------------------------------------------------------
-- Inicio (RF-07)
----------------------------------------------------------------
local ghostList

local function broadcastGhost(race)
    if not race.s.ghost then return end
    local list = {}
    for _, E in ipairs(race.entities) do if isElement(E.veh) then list[#list + 1] = E.veh end end
    sendHumans(race, "rp:races:ghost", list)
end

startRace = function(race)
    if race.state ~= "lobby" then return end
    local hs = humans(race)
    if #hs == 0 and not race.botOnly then return destroyRace(race) end
    race.state = "countdown"
    race.deadline = nil
    local cls = RACE.CLASSES[race.s.class] or RACE.CLASSES[1]

    -- relleno con IA (RF-12)
    if race.s.ai then
        local free = RACE.MAX_PLAYERS - #race.entities
        for i = 1, free do
            race.entities[#race.entities + 1] = { kind = "bot", name = raceBotName(i), cp = 1, lap = 1, times = {}, botIdx = i }
        end
    end
    -- orden de parrilla aleatorio
    for i = #race.entities, 2, -1 do
        local j = math.random(i)
        race.entities[i], race.entities[j] = race.entities[j], race.entities[i]
    end

    local colors = { { 220, 40, 40 }, { 40, 90, 220 }, { 240, 200, 30 }, { 40, 180, 80 }, { 240, 120, 20 }, { 160, 60, 200 }, { 240, 240, 240 }, { 30, 30, 30 } }
    for i, E in ipairs(race.entities) do
        local x, y, z, rz = gridPos(race.track, i)
        local model = cls.models[math.random(#cls.models)]
        local veh = createVehicle(model, x, y, z, 0, 0, rz, "CARRERA")
        setElementDimension(veh, race.dim)
        setElementInterior(veh, 0)
        local c = colors[((i - 1) % #colors) + 1]
        setVehicleColor(veh, c[1], c[2], c[3], 20, 20, 20)
        setVehicleEngineState(veh, true)
        setVehicleLocked(veh, true)
        setElementFrozen(veh, true)
        setElementData(veh, "rp:race", race.id, false)
        E.veh, E.grid, E.cp, E.lap = veh, i, 1, 1
        if E.kind == "player" then
            local p = E.player
            setElementFrozen(p, false)
            setElementDimension(p, race.dim)
            warpPedIntoVehicle(p, veh)
            toggleAllControls(p, true, true, false)
            makeTarget(race, E)
            triggerClientEvent(p, "rp:races:env", resourceRoot, race.s.hour, RACE.WEATHERS[race.s.weather] and RACE.WEATHERS[race.s.weather].id or 0)
        else
            E.race = race
            local ped = createPed(raceBotSkin(E.botIdx), x, y, z)
            setElementDimension(ped, race.dim)
            warpPedIntoVehicle(ped, veh)
            E.ped = ped
            E.ni = aiNearestAhead(race.track, x, y, rz)
            aiStop(E)
        end
    end
    broadcastGhost(race)
    sendHumans(race, "rp:races:close")   -- cierra la sala; arranca el HUD

    -- cuenta atras 3,2,1,GO
    for k = 0, RACE.COUNTDOWN do
        local n = RACE.COUNTDOWN - k
        race.timers["c" .. k] = setTimer(function()
            if not races[race.id] then return end
            sendHumans(race, "rp:races:count", n)
            if n == 0 then
                race.state, race.t0 = "running", now()
                for _, E in ipairs(race.entities) do
                    E.lapStart = race.t0
                    if isElement(E.veh) then setElementFrozen(E.veh, false) end
                    if E.kind == "bot" then aiStart(E) end
                end
            end
        end, 800 + k * 1000, 1)
    end
end

----------------------------------------------------------------
-- Tick principal
----------------------------------------------------------------
local function onCheckpoint(race, E, t)
    local cps = race.track.cps
    if E.cp == #cps then
        local lapTime = t - E.lapStart
        E.times[#E.times + 1] = lapTime
        if not E.best or lapTime < E.best then E.best = lapTime end
        E.lastLap = lapTime
        E.lapStart = t
        if E.lap >= race.s.laps then
            E.finished = true
            race.finishedCount = race.finishedCount + 1
            E.place = race.finishedCount
            E.finishTime = t - race.t0
            if E.kind == "player" then
                notify(E.player, ("Terminaste en la posicion %d."):format(E.place), "success")
                if isElement(E.marker) then destroyElement(E.marker) E.marker = nil end
                if isElement(E.blip) then destroyElement(E.blip) E.blip = nil end
                if not race.dnfEnd then
                    race.dnfEnd = t + RACE.DNF_TIME * 1000
                    sendHumans(race, "rp:races:dnf", RACE.DNF_TIME)
                end
            else
                aiStop(E)
            end
            return
        end
        E.lap = E.lap + 1
        E.cp = 1
    else
        E.cp = E.cp + 1
    end
    if E.kind == "player" then
        updateTarget(race, E)
        triggerClientEvent(E.player, "rp:races:cp", resourceRoot, E.cp == 1 and E.lap > 1)
    end
end

local hudTick = 0
local fuelTick = 0

local function raceTick(race, t)
    if race.state ~= "running" then return end
    local cps = race.track.cps

    race.humanPos = {}
    for _, E in ipairs(race.entities) do
        if E.kind == "player" and isElement(E.veh) then
            local x, y = getElementPosition(E.veh)
            race.humanPos[#race.humanPos + 1] = { x, y }
        end
    end

    for _, E in ipairs(race.entities) do
        local veh = E.veh
        if isElement(veh) and not E.finished then
            if E.kind == "bot" then aiThink(race, E, t) end
            local x, y, z = getElementPosition(veh)
            local cp = cps[E.cp]
            local dx, dy = cp[1] - x, cp[2] - y
            if dx * dx + dy * dy < RACE.CP_RADIUS ^ 2 and abs(z - cp[3]) < 12 then
                onCheckpoint(race, E, t)
            end
            if not E.finished then
                -- respawn por vehiculo destruido / caida / volcado / atasco (RF-10, RF-14)
                local need = false
                local ok = not E.lastRespawn or t - E.lastRespawn > RACE.RESPAWN_CD
                if getElementHealth(veh) < 280 or isVehicleBlown(veh) then need = true end
                local ref = E.cp > 1 and cps[E.cp - 1] or race.track.start
                if z < ref[3] - 30 then need = true end
                local m = getElementMatrix(veh)
                if m and m[3][3] < 0.25 then
                    E.flipSince = E.flipSince or t
                    if t - E.flipSince > RACE.FLIP_TIME then need = true end
                else E.flipSince = nil end
                if E.kind == "bot" and not E.kinematic then
                    if (E.kmh or 0) < 4 then
                        E.stillSince = E.stillSince or t
                        if t - E.stillSince > RACE.STUCK_TIME then need = true end
                    else E.stillSince = nil end
                end
                if need and ok then respawnEntity(race, E, t) end
            end
        end
    end

    aiFlush(race)
    local ranked = computeRanks(race)

    -- rebufo y catchup (RF-11): el cliente aplica el impulso al humano; el servidor al bot
    if RACE.SLIPSTREAM then
        for i = 2, #ranked do
            local E, A = ranked[i], ranked[i - 1]
            if not E.finished and isElement(E.veh) and isElement(A.veh) then
                local x, y = getElementPosition(E.veh)
                local ax, ay = getElementPosition(A.veh)
                local dx, dy = ax - x, ay - y
                local d = sqrt(dx * dx + dy * dy)
                local vx, vy = getElementVelocity(E.veh)
                local sp = sqrt(vx * vx + vy * vy)
                if d < RACE.SLIP_DIST and d > 3 and sp > 0.5 and sp < 1.25 then
                    local dot = (vx * dx + vy * dy) / (sp * d)
                    if dot > 0.93 then
                        if E.kind == "player" then triggerClientEvent(E.player, "rp:races:boost", resourceRoot, 1.012)
                        else local _, _, vz = getElementVelocity(E.veh); setElementVelocity(E.veh, vx * 1.012, vy * 1.012, vz) end
                    end
                end
            end
        end
        if race.s.catchup and #ranked >= 2 then
            local L, S = ranked[1], ranked[2]
            if not L.finished and isElement(L.veh) and (progressOf(race, L) - progressOf(race, S)) >= 3 then
                if L.kind == "player" then triggerClientEvent(L.player, "rp:races:boost", resourceRoot, 0.994)
                elseif isElement(L.veh) then
                    local vx, vy, vz = getElementVelocity(L.veh); setElementVelocity(L.veh, vx * 0.994, vy * 0.994, vz)
                end
            end
        end
    end

    -- HUD
    hudTick = hudTick + 1
    if hudTick % 5 == 0 then
        local board = {}
        for i = 1, math.min(6, #ranked) do
            local E = ranked[i]
            board[#board + 1] = { name = E.name, bot = E.kind == "bot", finished = E.finished or false }
        end
        local dnfLeft = race.dnfEnd and math.max(0, floor((race.dnfEnd - t) / 1000)) or nil
        for _, E in ipairs(race.entities) do
            if E.kind == "player" then
                triggerClientEvent(E.player, "rp:races:hud", resourceRoot, {
                    pos = E.rank, total = #ranked, lap = math.min(E.lap, race.s.laps), laps = race.s.laps,
                    cp = E.cp, cps = #cps, elapsed = t - race.t0, lapTime = t - (E.lapStart or t), best = E.best, last = E.lastLap,
                    board = board, dnf = dnfLeft, finished = E.finished or false,
                })
            end
        end
    end

    -- combustible infinito para los coches de carrera
    fuelTick = fuelTick + 1
    if fuelTick % 50 == 0 then
        for _, E in ipairs(race.entities) do
            if isElement(E.veh) then pcall(function() exports.rp_vehicles:setVehicleFuel(E.veh, 200) end) end
        end
    end

    -- cierre por tiempo (RF-16)
    if race.dnfEnd and t >= race.dnfEnd then
        for _, E in ipairs(race.entities) do
            if E.kind == "player" and not E.finished then E.dnf = true end
        end
        endRace(race)
    else
        checkEnd(race)
    end
end

setTimer(function()
    local t = now()
    for _, race in pairs(races) do raceTick(race, t) end
end, 100, 0)

-- Sala: arranque automatico al agotar el tiempo (RF-04) y fin de invitaciones
setTimer(function()
    local t = now()
    for _, race in pairs(races) do
        if race.state == "lobby" and race.deadline and t >= race.deadline then startRace(race) end
    end
    for p, inv in pairs(invites) do
        if t > inv.expires then invites[p] = nil end
    end
end, 1000, 0)

----------------------------------------------------------------
-- Votacion (RF-18)
----------------------------------------------------------------
local function resolveVoteFor(race)
    if race.state ~= "results" then return end
    local tally, best, bestN = {}, nil, 0
    for _, v in pairs(race.votes) do
        if v > 0 then tally[v] = (tally[v] or 0) + 1 end
    end
    local ties = {}
    for idx, n in pairs(tally) do
        if n > bestN then bestN, ties = n, { idx } elseif n == bestN then ties[#ties + 1] = idx end
    end
    if bestN == 0 then return destroyRace(race) end
    best = ties[math.random(#ties)]
    -- quienes votaron salir (0) o no votaron y quieren irse ya se fueron; el resto sigue
    for _, E in ipairs({ unpack(race.entities) }) do
        if E.kind == "player" and race.votes[E.player] == 0 then leavePlayer(race, E.player, true) end
    end
    if #humans(race) == 0 then return destroyRace(race) end
    afterLeave(race)
    if races[race.id] then toLobby(race, best) end
end

local function wireResolve(race) race.resolveVote = function() resolveVoteFor(race) end end

----------------------------------------------------------------
-- Eventos del cliente
----------------------------------------------------------------
local function canJoin(p)
    if not isElement(p) or not characterOf(p) then return false, "Necesitas un personaje en juego." end
    if playerRace[p] then return false, "Ya estas en una carrera." end
    if isPedDead(p) or getElementHealth(p) <= 0 then return false, "No puedes correr ahora." end
    if isPedInVehicle(p) then return false, "Bajate de tu vehiculo para entrar a una carrera." end
    if getElementDimension(p) ~= 0 then return false, "Solo puedes entrar a una carrera desde el mundo abierto." end
    local ok, tbl = pcall(function() return exports.rp_pool:getPlayerPoolTable(p) end)
    if ok and tbl then return false, "Estas jugando al pool." end
    return true
end

local function menuData(p, trackIdx)
    local lobbies = {}
    for _, race in pairs(races) do
        if race.state == "lobby" and #humans(race) < RACE.MAX_PLAYERS then
            lobbies[#lobbies + 1] = { id = race.id, track = race.track.name, host = race.host and nameOf(race.host) or "-",
                players = #humans(race), max = RACE.MAX_PLAYERS, class = RACE.CLASSES[race.s.class].name, laps = race.s.laps,
                secLeft = race.deadline and math.max(0, floor((race.deadline - now()) / 1000)) or 0 }
        end
    end
    table.sort(lobbies, function(a, b) return a.id < b.id end)
    local tracks = {}
    for i, t in ipairs(RACE_TRACKS) do tracks[i] = { idx = i, name = t.name, length = t.length } end
    return { lobbies = lobbies, tracks = tracks, track = trackIdx or 1 }
end

local function openMenu(p, trackIdx)
    local ok, why = canJoin(p)
    if not ok then return notify(p, why, "warning") end
    triggerClientEvent(p, "rp:races:menu", resourceRoot, menuData(p, trackIdx))
end

addEventHandler("rp:races:open", root, function() openMenu(client) end)
addCommandHandler("carreras", function(p) openMenu(p) end)
addCommandHandler("salircarrera", function(p) dropPlayer(p) end)

addEventHandler("rp:races:create", root, function(trackIdx)
    local p = client
    trackIdx = tonumber(trackIdx)
    if not trackIdx or not RACE_TRACKS[trackIdx] then return end
    local ok, why = canJoin(p)
    if not ok then return notify(p, why, "warning") end
    local race = createRace(p, trackIdx)
    if not race then return notify(p, "No hay espacio para mas carreras.", "error") end
    wireResolve(race)
    joinRace(race, p)
end)

local function tryJoin(p, race)
    local ok, why = canJoin(p)
    if not ok then return notify(p, why, "warning") end
    if not race or race.state ~= "lobby" then return notify(p, "Esa sala ya no esta disponible.", "warning") end
    if #humans(race) >= RACE.MAX_PLAYERS then return notify(p, "La sala esta llena.", "warning") end
    joinRace(race, p)
end

addEventHandler("rp:races:join", root, function(id)
    id = tonumber(id)
    tryJoin(client, id and races[id])
end)

addEventHandler("rp:races:random", root, function()
    local p = client
    local pool = {}
    for _, race in pairs(races) do
        if race.state == "lobby" and #humans(race) < RACE.MAX_PLAYERS then pool[#pool + 1] = race end
    end
    if #pool > 0 then return tryJoin(p, pool[math.random(#pool)]) end
    -- nadie esperando: crear una en una pista aleatoria
    local ok, why = canJoin(p)
    if not ok then return notify(p, why, "warning") end
    local race = createRace(p, math.random(#RACE_TRACKS))
    if not race then return notify(p, "No hay espacio para mas carreras.", "error") end
    wireResolve(race)
    joinRace(race, p)
    notify(p, "No habia salas: creaste una en una pista aleatoria.", "info")
end)

addEventHandler("rp:races:leave", root, function() dropPlayer(client) end)

local SETTERS = {
    track = function(race, v)
        v = floor(tonumber(v) or 0)
        if not RACE_TRACKS[v] then return false end
        race.trackIdx, race.track = v, RACE_TRACKS[v]
        buildProps(race)
        for _, E in ipairs(race.entities) do placeInLobby(race, E) end
        return true
    end,
    class = function(race, v) v = floor(tonumber(v) or 0) if not RACE.CLASSES[v] then return false end race.s.class = v return true end,
    laps = function(race, v) v = floor(tonumber(v) or 0) if v < 1 or v > RACE.MAX_LAPS then return false end race.s.laps = v return true end,
    hour = function(race, v) v = floor(tonumber(v) or -2) if v < -1 or v > 23 then return false end race.s.hour = v return true end,
    weather = function(race, v) v = floor(tonumber(v) or 0) if not RACE.WEATHERS[v] then return false end race.s.weather = v return true end,
    difficulty = function(race, v) v = floor(tonumber(v) or 0) if not RACE.DIFFICULTY[v] then return false end race.s.difficulty = v return true end,
    ghost = function(race, v) race.s.ghost = (v == true or v == 1) return true end,
    ai = function(race, v) race.s.ai = (v == true or v == 1) return true end,
    catchup = function(race, v) race.s.catchup = (v == true or v == 1) return true end,
}

addEventHandler("rp:races:setting", root, function(key, value)
    local race = playerRace[client]
    if not race or race.state ~= "lobby" or race.host ~= client then return end
    if type(key) ~= "string" or not SETTERS[key] then return end
    if type(value) == "string" then
        if value == "true" then value = true elseif value == "false" then value = false end
    end
    if SETTERS[key](race, value) then sendLobby(race) end
end)

addEventHandler("rp:races:invite", root, function(name)
    local race = playerRace[client]
    if not race or race.state ~= "lobby" or race.host ~= client or type(name) ~= "string" then return end
    local target = getPlayerFromName(name)
    if not target or target == client then return end
    if not canJoin(target) then return notify(client, "Ese jugador no puede unirse ahora.", "warning") end
    invites[target] = { race = race.id, expires = now() + 30000 }
    triggerClientEvent(target, "rp:races:invite", resourceRoot, { race = race.id, from = nameOf(client), track = race.track.name })
    notify(client, "Invitacion enviada a " .. getPlayerName(target):gsub("_", " ") .. ".", "success")
end)

addEventHandler("rp:races:start", root, function()
    local race = playerRace[client]
    if not race or race.state ~= "lobby" or race.host ~= client then return end
    startRace(race)
end)

addEventHandler("rp:races:respawn", root, function()
    local race = playerRace[client]
    if not race or race.state ~= "running" then return end
    local E = race.byPlayer[client]
    if not E or E.finished then return end
    local t = now()
    if E.lastRespawn and t - E.lastRespawn < RACE.RESPAWN_CD then return end
    respawnEntity(race, E, t)
end)

addEventHandler("rp:races:vote", root, function(idx)
    local race = playerRace[client]
    if not race or race.state ~= "results" then return end
    idx = floor(tonumber(idx) or -1)
    if idx ~= 0 and not RACE_TRACKS[idx] then return end
    if idx == 0 then
        -- salir ya
        dropPlayer(client)
        return
    end
    race.votes[client] = idx
    local counts = {}
    for _, v in pairs(race.votes) do counts[v] = (counts[v] or 0) + 1 end
    sendHumans(race, "rp:races:votes", counts)
end)

----------------------------------------------------------------
-- Entrada de aceptacion de invitaciones y markers del mundo (RF-01)
----------------------------------------------------------------
addEvent("rp:races:acceptInvite", true)
addEventHandler("rp:races:acceptInvite", root, function()
    local inv = invites[client]
    if not inv then return end
    invites[client] = nil
    tryJoin(client, races[inv.race])
end)

local function createWorldMarkers()
    for i, t in ipairs(RACE_TRACKS) do
        local s = t.start
        local m = createMarker(s[1], s[2], s[3] - 1, "cylinder", RACE.MARKER_SIZE, 255, 190, 30, 140)
        setElementDimension(m, 0)
        local b = createBlip(s[1], s[2], s[3], 53, 2, 255, 255, 255, 255, 0, 700)
        setElementData(m, "rp:raceTrack", i, false)
        addEventHandler("onMarkerHit", m, function(hit, matching)
            if not matching or getElementType(hit) ~= "player" or isPedInVehicle(hit) then return end
            openMenu(hit, i)
        end)
    end
end
createWorldMarkers()

----------------------------------------------------------------
-- Bloqueos y limpieza
----------------------------------------------------------------
addEventHandler("onVehicleStartExit", root, function(p)
    if getElementData(source, "rp:race") and playerRace[p] then
        local E = playerRace[p].byPlayer[p]
        if E and not E.finished and playerRace[p].state ~= "results" then cancelEvent() end
    end
end)

addEventHandler("onPlayerWasted", root, function() if playerRace[source] then dropPlayer(source) end end)
addEventHandler("onPlayerQuit", root, function() dropPlayer(source) invites[source] = nil end, true, "high")
addEventHandler("rp:onCharacterLogout", root, function() dropPlayer(source) end, true, "high")

addEventHandler("onResourceStop", resourceRoot, function()
    for _, race in pairs({ unpack((function() local l = {} for _, r in pairs(races) do l[#l + 1] = r end return l end)()) }) do
        destroyRace(race)
    end
end)

----------------------------------------------------------------
-- Prueba automatica sin jugadores (solo IA): usada por rp_test / revision manual
----------------------------------------------------------------
local botTest = nil
function runBotTest(trackIdx, laps)
    if botTest and races[botTest.id] then return false end
    local race = createRace(nil, tonumber(trackIdx) or 1)
    if not race then return false end
    race.botOnly = true
    race.s.laps = tonumber(laps) or 1
    wireResolve(race)
    botTest = race
    startRace(race)
    -- sin humanos nadie vota: cerrar al terminar
    return true
end

function getBotTestStatus()
    local r = botTest
    if not r then return { state = "none" } end
    local out = { state = r.state, entities = {}, alive = races[r.id] ~= nil }
    for _, E in ipairs(r.entities) do
        out.entities[#out.entities + 1] = { name = E.name, lap = E.lap, cp = E.cp, finished = E.finished or false, place = E.place or 0,
                                            time = E.finishTime or 0, kinematic = E.kinematic or false }
    end
    return out
end
