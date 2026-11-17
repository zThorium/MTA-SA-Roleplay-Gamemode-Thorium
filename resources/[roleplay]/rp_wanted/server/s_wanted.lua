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
    clearWanted, reportCrime, isWantedPolice
    Evento: rp:onWantedLevelChange (source = jugador; nuevo, anterior)

    Admin: /busqueda <jugador> [0-6]
]]

addEvent("rp:onWantedLevelChange", false)
addEvent("rp:wanted:crime", true)
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

local function applyChaos(player, chaos)
    local s = state(player)
    s.chaos = math.max(0, math.min(WANTED.MAX_CHAOS, math.floor(chaos)))
    local old = s.level
    local level = wantedLevelFromChaos(s.chaos)
    if level == old then return end
    s.level = level
    setElementData(player, "rp:wanted", level)
    if level == 0 then setLost(player, s, false) end
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

-- Delito: se aplica medio segundo despues (cola de GTA) y no se repite con la
-- misma victima en QUEUE_TIME
function reportCrime(player, crimeKey, victimKey, dontCare)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local crime = WANTED_CRIMES[crimeKey]
    if not crime then return false end
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
        local points = crime.points
        if dontCare then points = points / WANTED.DONT_CARE_DIVISOR end
        local chaos = s.chaos + math.floor(points)
        outputServerLog(("[rp_wanted] %s: %s +%d (caos %d -> %d)"):format(getPlayerName(player), crimeKey, math.floor(points), s.chaos, chaos))
        -- libertad condicional: un delito poco despues de un arresto devuelve el nivel anterior
        if s.parole and getTickCount() - s.parole.at < WANTED.PAROLE_TIME then
            chaos = math.max(chaos, s.parole.chaos)
        end
        applyChaos(player, chaos)
    end, WANTED.REPORT_DELAY, 1)
    return true
end

function getWantedLevel(player) return W[player] and W[player].level or 0 end
function getWantedChaos(player) return W[player] and W[player].chaos or 0 end

function setWantedLevel(player, level)
    level = math.max(0, math.min(WANTED.MAX_LEVEL, math.floor(tonumber(level) or 0)))
    if not isElement(player) then return false end
    local s = state(player)
    s.parole = nil
    applyChaos(player, level == 0 and 0 or WANTED.SET_LEVEL_CHAOS[level])
    return true
end

function clearWanted(player)
    return setWantedLevel(player, 0)
end

----------------------------------------------------------------
-- Delitos detectados en el cliente (peatones y trafico son del cliente)
----------------------------------------------------------------
addEventHandler("rp:wanted:crime", resourceRoot, function(crimeKey, victimKey, dontCare)
    local player = client
    if type(crimeKey) ~= "string" or not WANTED_CRIMES[crimeKey] then return end
    local s = state(player)
    -- limite: 12 avisos por segundo
    local now = getTickCount()
    if now - s.reportWindow > 1000 then s.reportWindow, s.reports = now, 0 end
    s.reports = s.reports + 1
    if s.reports > 12 then return end
    reportCrime(player, crimeKey, type(victimKey) == "string" and victimKey:sub(1, 40) or "", dontCare == true)
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
    if crime then reportCrime(attacker, crime, getPlayerSerial(source)) end
end)

----------------------------------------------------------------
-- Decaimiento: cada segundo sin policia a menos de 18 m
----------------------------------------------------------------
local CITIES = { ["Los Santos"] = true, ["San Fierro"] = true, ["Las Venturas"] = true }

local function policeNear(player, radius)
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
            if s.chaos > 0 and not s.busted then
                local x, y, z = getElementPosition(player)
                local elusive = getElementInterior(player) ~= 0 or not CITIES[getZoneName(x, y, z, true)]
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

-- La faccion de un jugador puede cambiar: se refrescan los puntos de la policia
setTimer(function()
    for player in pairs(blips) do
        if isElement(player) then refreshPoliceBlip(player) else blips[player] = nil end
    end
end, 15000, 0)

----------------------------------------------------------------
-- Arresto (lo pide s_units.lua cuando un policia te alcanza)
----------------------------------------------------------------
-- Te sacaron del vehiculo o te redujeron en el piso: manos arriba, pantalla
-- negra y a la celda (server/s_jail.lua). Se borra la busqueda.
function bustPlayer(player, cop)
    local s = W[player]
    if not s or s.level <= 0 or s.busted then return false end
    local level, chaos = s.level, s.chaos
    s.busted = true
    applyChaos(player, 0)
    outputServerLog(("[rp_wanted] %s arrestado con %d estrellas"):format(getPlayerName(player), level))

    if isPedInVehicle(player) then removePedFromVehicle(player) end
    toggleAllControls(player, false, true, false)
    setPedAnimation(player, "ped", "handsup", -1, false, false, false, true)
    popup(player, "Arrestado", ("Te arresto la policia (%d estrella%s)."):format(level, level == 1 and "" or "s"), "error")
    setTimer(function() if isElement(player) then fadeCamera(player, false, 1.0) end end, 1800, 1)

    setTimer(function()
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
    end
end

addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local player = source
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
