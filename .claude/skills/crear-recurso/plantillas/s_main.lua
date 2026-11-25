--[[
    rp_sistema / s_sistema.lua  (servidor)

    Qué hace el recurso, en 2-4 líneas: qué hace el jugador, qué se guarda y dónde.

    Comandos:
        /comando <arg>          qué hace
    Admin (catálogo en rp_adminpanel/server/s_catalog.lua):
        /comandoadmin <arg>     qué hace
    Exports (servidor):
        isPlayerDoingSistema(player)
]]

----------------------------------------------------------------
-- Estado (todo local; se limpia al salir / cambiar de personaje / parar el recurso)
----------------------------------------------------------------
local state = {}      -- [player] = { characterId = n, ... }   solo jugadores con personaje
local cooldown = {}   -- [player] = tick de la última acción
local points = {}     -- [i] = { marker, blip, colshape, data }

----------------------------------------------------------------
-- Eventos
----------------------------------------------------------------
addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:sistema:use", true)          -- true SOLO en los que dispara el cliente

----------------------------------------------------------------
-- Atajos
----------------------------------------------------------------
local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p, level) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= (level or 1) end
local function log(msg, level) outputDebugString("[rp_sistema] " .. msg, level or 3) end

-- true si puede actuar ahora (y marca el cooldown)
local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < SISTEMA.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

-- Cerca de verdad: misma dimensión, mismo interior y dentro del radio
local function isNear(p, x, y, z, interior, dimension, radius)
    if getElementDimension(p) ~= (dimension or 0) or getElementInterior(p) ~= (interior or 0) then return false end
    local px, py, pz = getElementPosition(p)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= (radius or SISTEMA.INTERACT_RADIUS) + 0.5
end

-- Estados del resto de la GM que impiden usar el sistema. Devuelve el motivo o nil.
local function blockedReason(p)
    if exports.rp_injury:isPlayerDowned(p) then return "No puedes hacer eso ahora." end
    if isPedInVehicle(p) then return "Bájate del vehículo." end
    -- Descomenta lo que aplique (y añade el <include> correspondiente):
    -- if exports.rp_police:isCuffed(p) then return "Estás esposado." end
    -- if exports.rp_missions:getPlayerMission(p) then return "Estás en una misión." end
    -- if exports.rp_races:getPlayerRace(p) then return "Estás en una carrera." end
    return nil
end

----------------------------------------------------------------
-- Dinero (un solo sitio para cobrar). Devuelve true si cobró.
----------------------------------------------------------------
local function charge(p, amount, concept, onDone)
    if amount <= 0 or SISTEMA.PAYMENT == "none" then return onDone(true) end
    local characterId = characterOf(p)
    if not characterId then return onDone(false) end

    if SISTEMA.PAYMENT == "cash" then
        if getPlayerMoney(p) < amount then return onDone(false) end
        takePlayerMoney(p, amount)
        exports.rp_characters:saveCharacter(p)
        return onDone(true)
    end

    -- Banco: cobro atómico, se entrega solo si se afectó la fila
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(p) then return end
        if not affected or affected == 0 then return onDone(false) end
        dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'purchase', ?, ?)",
            characterId, amount, tostring(concept):sub(1, 32))
        onDone(true)
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?",
        amount, characterId, amount)
end

----------------------------------------------------------------
-- Ciclo de vida del jugador
----------------------------------------------------------------
local function loadPlayer(p, characterId)
    state[p] = { characterId = characterId }
    -- Si hay datos por personaje:
    -- dbQuery(function(qh)
    --     local rows = dbPoll(qh, 0) or {}
    --     if not isElement(p) or not state[p] or state[p].characterId ~= characterId then return end  -- cambió de personaje
    --     state[p].data = rows[1]
    -- end, db(), "SELECT * FROM character_sistema WHERE character_id = ?", characterId)
end

local function unloadPlayer(p)
    local s = state[p]
    if not s then return end
    -- guardar lo pendiente, destruir lo que sea del jugador (vehículos temporales, timers, objetos)
    -- if isTimer(s.timer) then killTimer(s.timer) end
    -- if isElement(s.vehicle) then destroyElement(s.vehicle) end
    state[p] = nil
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) loadPlayer(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() unloadPlayer(source) end)
addEventHandler("onPlayerQuit", root, function() unloadPlayer(source); cooldown[source] = nil end)
addEventHandler("rp:onPlayerDowned", root, function()
    -- cortar la actividad en curso si no tiene sentido abatido
end)

----------------------------------------------------------------
-- Mundo
----------------------------------------------------------------
local function spawnPoints()
    for i, pt in ipairs(SISTEMA.POINTS) do
        local m = SISTEMA.MARKER
        local marker = createMarker(pt.x, pt.y, pt.z - 1, m.type, m.size, m.r, m.g, m.b, m.a)
        setElementInterior(marker, pt.interior or 0)
        setElementDimension(marker, pt.dimension or 0)
        local blip
        if SISTEMA.BLIP.enabled and (pt.dimension or 0) == 0 then
            local b = SISTEMA.BLIP
            blip = createBlip(pt.x, pt.y, pt.z, b.icon, b.size, b.r, b.g, b.b, 255, 0, b.visibleDistance)
        end
        points[i] = { marker = marker, blip = blip, data = pt }
    end
end

----------------------------------------------------------------
-- Acción remota (el cliente solo pide; el servidor decide)
----------------------------------------------------------------
addEventHandler("rp:sistema:use", resourceRoot, function(index)
    local p = client                                    -- NUNCA source
    if not state[p] or not takeCooldown(p) then return end

    index = tonumber(index)
    local pt = index and points[index] and points[index].data
    if not pt then return end
    if not isNear(p, pt.x, pt.y, pt.z, pt.interior, pt.dimension) then return end
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end

    charge(p, SISTEMA.PRICE, "Sistema", function(paid)
        if not isElement(p) or not state[p] then return end
        if not paid then return notify(p, "No tienes dinero suficiente.", "error") end
        -- ... efecto real (dar item, iniciar actividad, etc.)
        if SISTEMA.XP_REWARD > 0 then exports.rp_levels:giveXP(p, SISTEMA.XP_REWARD, "Sistema") end
        notify(p, "Hecho.", "success")
    end)
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function isPlayerDoingSistema(p)
    return state[p] ~= nil and state[p].active == true
end

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    spawnPoints()
    -- Rehidratar: si el recurso se reinicia con gente dentro, cargarlos como si acabaran de entrar
    for _, p in ipairs(getElementsByType("player")) do
        local characterId = characterOf(p)
        if characterId then loadPlayer(p, characterId) end
    end
    log(("%d puntos, %d jugadores cargados"):format(#points, #getElementsByType("player")))
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- Los elementos creados por este recurso se destruyen solos. Aquí: guardar lo pendiente y
    -- devolver lo que se cambió en elementos ajenos (congelado, controles, elementData de jugadores).
    for p in pairs(state) do unloadPlayer(p) end
end)
