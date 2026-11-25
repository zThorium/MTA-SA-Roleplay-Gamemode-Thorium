--[[
    rp_wanted / s_wanted.lua
    Nivel de busqueda (estrellas) al estilo de GTA San Andreas, ver shared/s_config.lua.

      - Puntos de caos por delito, cola anti repeticion de 10 s por victima.
      - Decaimiento cada segundo si no hay policia a menos de 18 m.
      - Arresto ("Busted"), muerte, libertad condicional y Pay 'n' Spray.
      - La policia jugadora (faccion 1) recibe el aviso de la central y ve un
        punto rojo sobre los buscados en el mapa.

    elementData publico del jugador:
      rp:wanted       estrellas (0-6)
      rp:wantedLost   true mientras ningun policia esta cerca (las estrellas parpadean)

    Exports (servidor): getWantedLevel, getWantedChaos, setWantedLevel,
    clearWanted, reportCrime, isWantedPolice, holdPursuit, isPursuitHeld,
    setPursuitTerms, getPursuitTerms
      setWantedLevel(player, nivel, force): force = true ignora el tope por
        antiguedad del personaje (lo usa rp_robbery: 5 estrellas al matar al cajero).
      holdPursuit(player, true/false): las estrellas se ven pero la policia IA no
        sale ni baja la busqueda (cuenta regresiva de un robo negociado).
      setPursuitTerms(player, sinTrampas, sinLlantas): condiciones negociadas.
        Sin trampas = sin pinchos ni controles de carretera; sin llantas = la
        policia no revienta neumaticos. Se borran al quedar en 0 estrellas.
    Evento: rp:onWantedLevelChange (source = jugador; nuevo, anterior)

    Admin: /busqueda <jugador> [0-6]
]]

addEvent("rp:onWantedLevelChange", false)
addEvent("rp:wanted:crime", true)
addEvent("rp:wanted:seen", true)
addEvent("rp:onCharacterSpawn", false)    -- de rp_characters
addEvent("rp:onCharacterLogout", false)

local W = {}             -- [player] = { chaos, level, queue = {[clave] = vence}, parole, lost, busted, reports }
local remembered = {}    -- [characterId] = { chaos, at }

local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind) end
local function popup(p, title, text, kind) exports.rp_notify:popup(p, title, text, kind) end
local function characterOf(p) return getElementData(p, "rp:characterId") end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function displayName(player)
    local name = exports.rp_characters:getPlayerCharacterName(player) or getPlayerName(player)
    return (tostring(name):gsub("_", " "))
end

-- Miembro de la policia (faccion reservada). Sin rp_factions nadie es policia.
function isWantedPolice(player)
    local ok, id = pcall(function() return exports.rp_factions:getPlayerFaction(player) end)
    return ok and tonumber(id) == WANTED.POLICE_FACTION_ID
end

-- Policia de servicio: miembro de la faccion y con uniforme (skin de policia) o
-- en un vehiculo policial. Un policia de civil comete delitos como cualquiera.
local function isPoliceOnDuty(player)
    if not isWantedPolice(player) then return false end
    -- Marcado de servicio de rp_police (vestuario)
    local ok, duty = pcall(function() return exports.rp_police:isOnDuty(player) end)
    if ok and duty then return true end
    if WANTED_POLICE_SKINS[getElementModel(player)] then return true end
    local v = getPedOccupiedVehicle(player)
    return v and WANTED_POLICE_MODELS[getElementModel(v)] or false
end

local dutyNotice = {}

local function state(player)
    local s = W[player]
    if not s then
        s = { chaos = 0, level = 0, queue = {}, reports = 0, reportWindow = 0 }
        W[player] = s
    end
    return s
end

----------------------------------------------------------------
-- Tope de estrellas por antiguedad del personaje (como el progreso de la
-- historia en GTA SA). Se lee de characters.created_at al aparecer.
----------------------------------------------------------------
local maxLevels = {}   -- [player] = tope

local function maxLevelOf(player)
    return maxLevels[player] or WANTED.MAX_LEVEL
end

local function loadMaxLevel(player, characterId)
    local ok, conn = pcall(function() return exports.rp_database:getConnection() end)
    if not ok or not conn or not characterId then return end
    dbQuery(function(q)
        local rows = dbPoll(q, 0)
        local days = rows and rows[1] and tonumber(rows[1].days) or 0
        local cap = WANTED.MAX_LEVEL
        for _, t in ipairs(WANTED.MAX_LEVEL_BY_AGE) do
            if days >= t.days then cap = t.max end
        end
        if isElement(player) and characterOf(player) == characterId then maxLevels[player] = cap end
    end, conn, "SELECT DATEDIFF(NOW(), created_at) AS days FROM characters WHERE id = ?", characterId)
end

----------------------------------------------------------------
-- Policia jugadora: aviso de la central y punto en el mapa
----------------------------------------------------------------
local blips = {}   -- [buscado] = blip

local function policePlayers()
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if characterOf(p) and isWantedPolice(p) then list[#list + 1] = p end
    end
    return list
end

local function refreshPoliceBlip(player)
    local level = W[player] and W[player].level or 0
    if level <= 0 then
        if isElement(blips[player]) then destroyElement(blips[player]) end
        blips[player] = nil
        return
    end
    local blip = blips[player]
    if not isElement(blip) then
        blip = createBlipAttachedTo(player, 0, 2, 229, 72, 77, 255, 1, 99999)
        blips[player] = blip
    end
    setBlipSize(blip, math.min(4, 1 + math.ceil(level / 2)))
    setElementVisibleTo(blip, root, false)
    for _, cop in ipairs(policePlayers()) do
        if cop ~= player then setElementVisibleTo(blip, cop, true) end
    end
end

local function radioPolice(player, level)
    local x, y, z = getElementPosition(player)
    local zone = getElementInterior(player) ~= 0 and "un interior" or getZoneName(x, y, z)
    local stars = ("%d estrella%s"):format(level, level == 1 and "" or "s")
    for _, cop in ipairs(policePlayers()) do
        if cop ~= player then
            outputChatBox(("[Central] Se busca a %s (%s) en %s."):format(displayName(player), stars, zone), cop, 90, 140, 255)
        end
    end
end

----------------------------------------------------------------
-- Caos y nivel
----------------------------------------------------------------
local function setLost(player, s, lost)
    lost = lost and s.level > 0 or false
    if s.lost == lost then return end
    s.lost = lost
    setElementData(player, "rp:wantedLost", lost)
end

-- Suspension (rp_missions): mientras dura no se acumulan estrellas ni caos
local suspended = {}

local function applyChaos(player, chaos)
    if suspended[player] then chaos = 0 end
    local s = state(player)
    s.chaos = math.max(0, math.min(WANTED.MAX_CHAOS, math.floor(chaos)))
    local cap = maxLevelOf(player)
    if (s.forcedCap or 0) > cap then cap = s.forcedCap end
    if cap < WANTED.MAX_LEVEL then s.chaos = math.min(s.chaos, WANTED.THRESHOLDS[cap + 1] - 1) end
    local old = s.level
    local level = wantedLevelFromChaos(s.chaos)
    if level == old then return end
    s.level = level
    if level > old then
        -- margen sobre el umbral (como SetWantedLevel de GTA) y unos segundos sin
        -- decaimiento: la estrella recien ganada no se pierde al instante
        s.chaos = math.max(s.chaos, WANTED.SET_LEVEL_CHAOS[level] or s.chaos)
        s.graceUntil = getTickCount() + WANTED.DECAY_GRACE
    end
    setElementData(player, "rp:wanted", level)
    if level == 0 then
        setLost(player, s, false)
        clearPursuitExtras(player, s)
    end
    triggerEvent("rp:onWantedLevelChange", player, level, old)
    refreshPoliceBlip(player)
    if level > old then
        if old == 0 then
            popup(player, "Policia", "La policia te esta buscando.", "warning")
        end
        radioPolice(player, level)
    elseif level == 0 and not s.busted then
        notify(player, "Perdiste a la policia.", "success")
    end
end

local policeNear

-- Delito: se aplica medio segundo despues (cola de GTA) y no se repite con la
-- misma victima en QUEUE_TIME. Si lo ve un policia (witnessed, o una unidad o
-- policia jugador cerca) vale el doble y da estrella al momento.
-- witnessed: "police" (lo vio la policia), "civil" (un testigo llamo a la policia)
-- o nil/true desde otros recursos (cuenta como civil). Sin testigos el cliente ni lo avisa.
function reportCrime(player, crimeKey, victimKey, dontCare, witnessed)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local crime = WANTED_CRIMES[crimeKey]
    if not crime then return false end
    if suspended[player] then return false end
    if isPlayerJailed and isPlayerJailed(player) then return false end
    if not characterOf(player) then
        outputServerLog(("[rp_wanted] %s: %s ignorado (sin personaje activo)"):format(getPlayerName(player), crimeKey))
        return false
    end
    if isPoliceOnDuty(player) then
        local now = getTickCount()
        outputServerLog(("[rp_wanted] %s: %s ignorado (policia de servicio)"):format(getPlayerName(player), crimeKey))
        if not dutyNotice[player] or now - dutyNotice[player] > 60000 then
            dutyNotice[player] = now
            notify(player, "Estas de servicio como policia: no acumulas busqueda.", "info")
        end
        return false
    end
    local s = state(player)
    if s.busted then return false end
    local now = getTickCount()
    local key = crimeKey .. ":" .. tostring(victimKey or "")
    if s.queue[key] and s.queue[key] > now then return false end
    s.queue[key] = now + WANTED.QUEUE_TIME
    setTimer(function()
        if not isElement(player) or W[player] ~= s or s.busted then return end
        local points = crime.points * (WANTED.CRIME_SCALE or 1)
        if dontCare then points = points / WANTED.DONT_CARE_DIVISOR end
        local seen = witnessed == "police" or policeNear(player, WANTED.WITNESS_RADIUS)
        if seen then points = points * WANTED.WITNESS_MULTIPLIER end
        local chaos = s.chaos + math.floor(points)
        -- estrella inmediata: delito grave o visto por la policia
        local minLevel = math.min(crime.instant or 0, maxLevelOf(player))
        if seen and points > 0 then minLevel = math.max(minLevel, 1) end
        if minLevel > 0 and wantedLevelFromChaos(chaos) < minLevel then
            chaos = WANTED.SET_LEVEL_CHAOS[minLevel]
        end
        s.graceUntil = math.max(s.graceUntil or 0, getTickCount() + WANTED.DECAY_GRACE)
        setLost(player, s, false)
        outputServerLog(("[rp_wanted] %s: %s +%d%s (caos %d -> %d)"):format(getPlayerName(player), crimeKey,
            math.floor(points), seen and " [testigo]" or "", s.chaos, chaos))
        -- libertad condicional: un delito poco despues de un arresto devuelve el nivel anterior
        if s.parole and getTickCount() - s.parole.at < WANTED.PAROLE_TIME then
            chaos = math.max(chaos, s.parole.chaos)
        end
        applyChaos(player, chaos)
    end, (witnessed == "police" or policeNear(player, WANTED.WITNESS_RADIUS)) and WANTED.REPORT_DELAY
        or WANTED.CIVIL_REPORT_DELAY, 1)
    return true
end

function getWantedLevel(player) return W[player] and W[player].level or 0 end
function getWantedChaos(player) return W[player] and W[player].chaos or 0 end

function setWantedLevel(player, level, force)
    level = math.max(0, math.min(WANTED.MAX_LEVEL, math.floor(tonumber(level) or 0)))
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local s = state(player)
    s.parole = nil
    if force and level > 0 then s.forcedCap = math.max(s.forcedCap or 0, level) end
    applyChaos(player, level == 0 and 0 or WANTED.SET_LEVEL_CHAOS[level])
    return true
end

function clearWanted(player)
    return setWantedLevel(player, 0)
end

----------------------------------------------------------------
-- Persecucion retenida y condiciones negociadas (rp_robbery)
----------------------------------------------------------------
function clearPursuitExtras(player, s)
    s.forcedCap, s.held, s.terms = nil, nil, nil
    if isElement(player) then
        setElementData(player, "rp:wantedHeld", false)
        setElementData(player, "rp:wantedNoTires", false)
    end
end

function holdPursuit(player, held)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local s = state(player)
    s.held = held and true or nil
    setElementData(player, "rp:wantedHeld", s.held or false)
    -- al soltarla, la estrella no empieza a bajar al instante
    if not held then s.graceUntil = getTickCount() + WANTED.DECAY_GRACE end
    return true
end

function isPursuitHeld(player)
    return W[player] and W[player].held or false
end

function setPursuitTerms(player, noTraps, noTires)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local s = state(player)
    s.terms = { noTraps = noTraps and true or false, noTires = noTires and true or false }
    setElementData(player, "rp:wantedNoTires", s.terms.noTires)
    return true
end

function getPursuitTerms(player)
    local t = W[player] and W[player].terms
    if not t then return false, false end
    return t.noTraps, t.noTires
end

----------------------------------------------------------------
-- Delitos detectados en el cliente (peatones y trafico son del cliente)
----------------------------------------------------------------
addEventHandler("rp:wanted:crime", resourceRoot, function(crimeKey, victimKey, dontCare, witnessed)
    local player = client
    if type(crimeKey) ~= "string" or not WANTED_CRIMES[crimeKey] then return end
    local s = state(player)
    -- limite: 12 avisos por segundo
    local now = getTickCount()
    if now - s.reportWindow > 1000 then s.reportWindow, s.reports = now, 0 end
    s.reports = s.reports + 1
    if s.reports > 12 then return end
    -- sin testigo valido no cuenta (lo filtra el cliente; aqui se exige igual)
    if witnessed ~= "police" and witnessed ~= "civil" then return end
    reportCrime(player, crimeKey, type(victimKey) == "string" and victimKey:sub(1, 40) or "", dontCare == true, witnessed)
end)

-- Delitos contra otros jugadores (golpes, disparos, atropellos)
addEventHandler("onPlayerDamage", root, function(attacker, weapon)
    if not WANTED.PLAYER_CRIMES or not attacker or not isElement(attacker) then return end
    local byVehicle = false
    if getElementType(attacker) == "vehicle" then
        attacker, byVehicle = getVehicleController(attacker), true
    end
    if not attacker or attacker == source or getElementType(attacker) ~= "player" then return end
    local crime = wantedCrimeForPedDamage(weapon, isPoliceOnDuty(source), byVehicle)
    -- la victima (un jugador) es testigo
    if crime then reportCrime(attacker, crime, getPlayerSerial(source), false, "civil") end
end)

----------------------------------------------------------------
-- Decaimiento: cada segundo sin policia a menos de 18 m
----------------------------------------------------------------
local CITIES = { ["Los Santos"] = true, ["San Fierro"] = true, ["Las Venturas"] = true }

-- Unidades IA o policias jugadores cerca (la linea de vision solo se puede
-- medir en el cliente: c_crimes.lua la manda como "witnessed")
function policeNear(player, radius)
    local x, y, z = getElementPosition(player)
    if wantedUnitsNear and wantedUnitsNear(x, y, z, radius) then return true end
    for _, el in ipairs(getElementsWithinRange(x, y, z, radius, "player")) do
        if el ~= player and characterOf(el) and isWantedPolice(el) and not isPedDead(el) then return true end
    end
    for _, v in ipairs(getElementsWithinRange(x, y, z, radius, "vehicle")) do
        local driver = getVehicleController(v)
        if WANTED_POLICE_MODELS[getElementModel(v)] and driver and driver ~= player
            and getElementType(driver) == "player" and isWantedPolice(driver) then
            return true
        end
    end
    return false
end

setTimer(function()
    local now = getTickCount()
    for player, s in pairs(W) do
        if not isElement(player) then
            W[player] = nil
        else
            if s.parole and now - s.parole.at > WANTED.PAROLE_TIME then s.parole = nil end
            local x, y, z = getElementPosition(player)
            local inCity = getElementInterior(player) == 0 and CITIES[getZoneName(x, y, z, true)] ~= nil
            -- GTA: salir de la ciudad al campo con 2+ estrellas quita una
            if s.inCity and not inCity and getElementInterior(player) == 0 and s.level >= 2 and not s.busted
                and now - (s.cityDropAt or 0) > WANTED.CITY_EXIT_COOLDOWN then
                s.cityDropAt = now
                applyChaos(player, WANTED.SET_LEVEL_CHAOS[s.level - 1])
                notify(player, "Saliste de la ciudad: la policia te busca con menos intensidad.", "info")
            end
            s.inCity = inCity
            local unseen = now - (s.seenAt or 0) > WANTED.EVADE_TIME
            if s.held then
                -- persecucion retenida (robo negociado): no baja hasta que se suelte
                setLost(player, s, false)
            elseif s.chaos > 0 and not s.busted and now < (s.graceUntil or 0) then
                setLost(player, s, false)
            elseif s.chaos > 0 and not s.busted and not unseen then
                -- algun policia te ve (lo informa tu cliente): no baja
                setLost(player, s, false)
            elseif s.chaos > 0 and not s.busted then
                local elusive = not inCity
                -- GTA: con 2+ estrellas en una zona apartada y dentro de un vehiculo policial no baja
                local v = getPedOccupiedVehicle(player)
                local hiding = s.level > 1 and elusive and v and WANTED_POLICE_MODELS[getElementModel(v)]
                if hiding then
                    setLost(player, s, false)
                elseif policeNear(player, WANTED.DECAY_RADIUS) then
                    setLost(player, s, false)
                else
                    setLost(player, s, true)
                    applyChaos(player, s.chaos - (elusive and WANTED.DECAY_ELUSIVE or WANTED.DECAY_CITY))
                end
            end
        end
    end
end, 1000, 0)

-- El cliente informa si algun policia (unidad, patrulla del trafico, helicoptero
-- o policia jugador) tiene linea de vision: la busqueda solo baja tras EVADE_TIME
-- sin que te vean (GTA: temporizador de evasion; cualquier avistamiento lo reinicia)
addEventHandler("rp:wanted:seen", resourceRoot, function()
    local s = W[client]
    if s then s.seenAt = getTickCount() end
end)

-- La faccion de un jugador puede cambiar: se refrescan los puntos de la policia
setTimer(function()
    for player in pairs(blips) do
        if isElement(player) then refreshPoliceBlip(player) else blips[player] = nil end
    end
end, 15000, 0)

----------------------------------------------------------------
-- Arresto (lo pide s_units.lua cuando un policia te alcanza)
----------------------------------------------------------------
-- GTA (CTaskComplexArrestPed): si vas en un vehiculo el policia abre la puerta
-- del conductor y te saca; a pie te reduce en el piso. Recien ahi es "Busted":
-- pantalla negra y a la celda (server/s_jail.lua). Se borra la busqueda.
-- inVeh lo manda el cliente: el auto puede ser del trafico (solo existe en su
-- cliente) y el servidor no lo ve.
local function playAnim(ped, block, anim, time, loop, freeze)
    if isElement(ped) and not isPedDead(ped) then
        setPedAnimation(ped, block, anim, time or -1, loop or false, false, false, freeze ~= false)
    end
end

function bustPlayer(player, cop, inVeh)
    local s = W[player]
    if not s or s.level <= 0 or s.busted then return false end
    local level, chaos = s.level, s.chaos
    s.busted = true
    applyChaos(player, 0)
    outputServerLog(("[rp_wanted] %s arrestado con %d estrellas%s"):format(getPlayerName(player), level,
        inVeh and " (sacado del vehiculo)" or ""))

    local veh = getPedOccupiedVehicle(player)
    inVeh = inVeh or veh ~= nil
    toggleAllControls(player, false, true, false)
    if cop and isElement(cop) then
        local x, y = getElementPosition(cop)
        local px, py = getElementPosition(player)
        setElementRotation(cop, 0, 0, (360 - math.deg(math.atan2(px - x, py - y))) % 360, "default", true)
    end
    -- el cliente del arrestado abre la puerta y lo saca de un auto del trafico
    triggerClientEvent(player, "rp:wanted:bustSequence", resourceRoot, cop, inVeh)

    if inVeh then
        if veh then
            setElementVelocity(veh, 0, 0, 0)
            setVehicleDoorOpenRatio(veh, 2, 1, 500)
        end
        playAnim(cop, "ped", "CAR_open_LHS", 700)
        setTimer(function()
            if not isElement(player) then return end
            playAnim(cop, "ped", "CAR_pullout_LHS", 1200)
            local v = getPedOccupiedVehicle(player)
            if v then
                local m = getElementMatrix(v)
                local x, y, z = getElementPosition(v)
                removePedFromVehicle(player)
                setElementPosition(player, x - m[1][1] * 1.7, y - m[1][2] * 1.7, z + 0.2)
            end
        end, 700, 1)
        setTimer(function() playAnim(player, "ped", "FLOOR_hit_f", -1, false, true) end, 1000, 1)
        setTimer(function() playAnim(cop, "ped", "ARRESTgun", 2600, true) end, 1900, 1)
    else
        playAnim(cop, "ped", "ARRESTgun", 4000, true)
        playAnim(player, "ped", "handsup", -1, false, true)
    end
    setTimer(function()
        if isElement(player) then
            popup(player, "Arrestado", ("Te arresto la policia (%d estrella%s)."):format(level, level == 1 and "" or "s"), "error")
        end
    end, inVeh and 1400 or 300, 1)
    setTimer(function() if isElement(player) then fadeCamera(player, false, 1.0) end end, WANTED.BUST_FREEZE - 1300, 1)

    setTimer(function()
        if isElement(veh) then setVehicleDoorOpenRatio(veh, 2, 0, 400) end
        if not isElement(player) then return end
        s.busted = nil
        setPedAnimation(player)
        if WANTED.BUST_TAKE_WEAPONS then takeAllWeapons(player) end
        toggleAllControls(player, true, true, false)
        jailPlayer(player, level * WANTED.JAIL_SECONDS_PER_STAR, level * WANTED.JAIL_BAIL_PER_STAR, chaos)
    end, WANTED.BUST_FREEZE, 1)
    return true
end

-- Libertad condicional al salir de la carcel: un delito en los 20 s siguientes
-- devuelve el caos que tenias al ser arrestado (GTA: ClearWantedLevelAndGoOnParole)
function setWantedParole(player, chaos)
    if not isElement(player) or not chaos or chaos <= 0 then return end
    state(player).parole = { chaos = chaos, at = getTickCount() }
end

function isPlayerBusted(player)
    return W[player] and W[player].busted or false
end

-- Morir borra la busqueda (sin libertad condicional)
addEventHandler("onPlayerWasted", root, function()
    local s = W[source]
    if s and s.chaos > 0 then
        s.parole = nil
        applyChaos(source, 0)
    end
end)

----------------------------------------------------------------
-- Persistencia corta (reconectar no borra las estrellas)
----------------------------------------------------------------
local function remember(player)
    local s, id = W[player], characterOf(player)
    if s and id and s.chaos > 0 and not s.busted then
        remembered[id] = { chaos = s.chaos, at = getTickCount() }
    end
end

local function forget(player)
    remember(player)
    if isElement(blips[player]) then destroyElement(blips[player]) end
    blips[player] = nil
    local s = W[player]
    if s and s.level > 0 then
        local old = s.level
        s.level = 0
        triggerEvent("rp:onWantedLevelChange", player, 0, old)
    end
    W[player] = nil
    if isElement(player) then
        setElementData(player, "rp:wanted", 0)
        setElementData(player, "rp:wantedLost", false)
        setElementData(player, "rp:wantedHeld", false)
        setElementData(player, "rp:wantedNoTires", false)
    end
end

addEventHandler("onPlayerQuit", root, function() forget(source) maxLevels[source] = nil end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local player = source
    maxLevels[player] = nil
    loadMaxLevel(player, characterId)
    local saved = remembered[characterId]
    remembered[characterId] = nil
    W[player] = nil
    setElementData(player, "rp:wanted", 0)
    setElementData(player, "rp:wantedLost", false)
    if saved and getTickCount() - saved.at < WANTED.REMEMBER_MINUTES * 60000 then
        setTimer(function()
            if isElement(player) and characterOf(player) == characterId then applyChaos(player, saved.chaos) end
        end, 3000, 1)
    end
end)

----------------------------------------------------------------
-- Pay 'n' Spray: borra la busqueda si ningun policia te ve entrar
----------------------------------------------------------------
local sprayCooldown = {}

addEventHandler("onResourceStart", resourceRoot, function()
    outputServerLog("[rp_wanted] Busqueda policial iniciada (/busquedainfo, /delitosdebug)")
    for _, p in ipairs(getElementsByType("player")) do
        if characterOf(p) then loadMaxLevel(p, characterOf(p)) end
    end
    for _, spot in ipairs(WANTED.SPRAYS) do
        local marker = createMarker(spot.x, spot.y, spot.z - 1, "cylinder", 4, 245, 165, 36, 60)
        setElementData(marker, "rp:spray", spot.name, false)
        createBlip(spot.x, spot.y, spot.z, 63, 2, 255, 255, 255, 255, 0, 400)
        addEventHandler("onMarkerHit", marker, function(player, sameDim)
            if not sameDim or getElementType(player) ~= "player" then return end
            local vehicle = getPedOccupiedVehicle(player)
            if not vehicle or getVehicleController(vehicle) ~= player then return end
            local now = getTickCount()
            if sprayCooldown[player] and now - sprayCooldown[player] < 15000 then return end
            sprayCooldown[player] = now
            local s = W[player]
            local wanted = s and s.level > 0
            if wanted and policeNear(player, WANTED.SPRAY_COP_RADIUS) then
                return notify(player, "La policia te vio entrar: el Pay 'n' Spray no te sirve ahora.", "error")
            end
            if getPlayerMoney(player) < WANTED.SPRAY_PRICE then
                return notify(player, ("Necesitas $%d en efectivo."):format(WANTED.SPRAY_PRICE), "error")
            end
            takePlayerMoney(player, WANTED.SPRAY_PRICE)
            fixVehicle(vehicle)
            if wanted then
                s.parole = nil
                applyChaos(player, 0)
                popup(player, spot.name, ("Reparado por $%d. La policia ya no te reconoce."):format(WANTED.SPRAY_PRICE), "success")
            else
                notify(player, ("Vehiculo reparado por $%d."):format(WANTED.SPRAY_PRICE), "success")
            end
        end)
    end
end)

addEventHandler("onPlayerQuit", root, function() sprayCooldown[source] = nil dutyNotice[source] = nil end)

-- Portones de los garajes Pay 'n' Spray: getGarageBoundingBox solo existe en el
-- cliente, que nos dice que garajes contienen los puntos; aqui se abren.
addEvent("rp:wanted:garages", true)
addEventHandler("rp:wanted:garages", resourceRoot, function(ids)
    if type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        id = tonumber(id)
        if id and id >= 0 and id <= 49 and id == math.floor(id) and not isGarageOpen(id) then setGarageOpen(id, true) end
    end
end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
addCommandHandler("busqueda", function(admin, _, query, level)
    if not isAdmin(admin) then return end
    local target = query and exports.rp_ids:findPlayer(query)
    if not target then return notify(admin, "Uso: /busqueda <jugador> [0-6]", "info") end
    if not level then
        return outputChatBox(("%s: %d estrellas, %d puntos de caos."):format(displayName(target), getWantedLevel(target), getWantedChaos(target)), admin, 245, 165, 36)
    end
    if not characterOf(target) then return notify(admin, "Ese jugador no tiene un personaje activo.", "error") end
    level = tonumber(level)
    if not level or level < 0 or level > WANTED.MAX_LEVEL then return notify(admin, "Nivel de 0 a 6.", "error") end
    setWantedLevel(target, level)
    notify(admin, ("%s ahora tiene %d estrellas."):format(displayName(target), level), "success")
end)

-- Diagnostico para cualquier jugador: estrellas, caos y si cuenta como policia de servicio
addCommandHandler("busquedainfo", function(player)
    local s = W[player]
    outputChatBox(("Busqueda: %d estrellas, %d puntos de caos (siguiente estrella: %s)."):format(
        s and s.level or 0, s and s.chaos or 0,
        tostring(WANTED.THRESHOLDS[(s and s.level or 0) + 1] or "-")), player, 245, 165, 36)
    outputChatBox(("Tope de estrellas de tu personaje: %d (sube con la antiguedad del personaje)."):format(maxLevelOf(player)),
        player, 245, 165, 36)
    if isWantedPolice(player) then
        outputChatBox(isPoliceOnDuty(player)
            and "Eres policia de servicio (uniforme o vehiculo policial): tus delitos no suman."
            or "Eres policia, pero de civil: tus delitos suman como los de cualquiera.", player, 245, 165, 36)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, "rp:wanted", 0)
        setElementData(p, "rp:wantedLost", false)
    end
end)

----------------------------------------------------------------
-- Suspension de la busqueda (misiones, instancias aisladas)
--   exports.rp_wanted:setWantedSuspended(player, true)  -> pone las estrellas en 0 y bloquea nuevos delitos
--   exports.rp_wanted:setWantedSuspended(player, false) -> vuelve a la normalidad (empieza sin estrellas)
----------------------------------------------------------------
function setWantedSuspended(player, on)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    suspended[player] = on and true or nil
    if on then setWantedLevel(player, 0) end
    return true
end

function isWantedSuspended(player) return suspended[player] == true end

addEventHandler("onPlayerQuit", root, function() suspended[source] = nil end)
