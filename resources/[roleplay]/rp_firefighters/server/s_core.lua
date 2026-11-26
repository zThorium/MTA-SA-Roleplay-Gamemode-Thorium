--[[
    rp_firefighters / s_core.lua  (servidor)

    Base de la facción de bomberos (facciones de tipo FIRE.FACTION_TYPE):
      - Vestuario (E): panel para entrar o salir de servicio eligiendo uniforme.
        De servicio: skin, extintor y motosierra de rescate, blip de compañeros,
        alertas de emergencia y sueldo de rol (rp_factions solo lo paga de servicio).
      - Garaje (E): saca o guarda una autobomba de la estación.
      - Experiencia de facción por personaje (firefighter_stats) con rangos de FIRE.RANKS.
    Los incidentes viven en s_incidents.lua; los comandos de admin en s_admin.lua.

    Exports (servidor): isOnDuty(p), isFirefighter(p), getFirefightersOnDuty()
]]

FD = {}                       -- funciones compartidas entre los s_*.lua de este recurso

local duty = {}               -- [player] = { skin = id }
local trucks = {}             -- [player] = vehículo de la estación
local stats = {}              -- [player] = { characterId, xp, fires, rescues, ok, failed }
local cooldown = {}           -- [player] = tick
local points = {}             -- [kind] = { x, y, z, rot, marker, blip }
local dutyBlips = {}          -- [player] = blip del bombero (solo lo ven sus compañeros de servicio)

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:firefighters:use", true)       -- cliente: E en vestuario o garaje
addEvent("rp:firefighters:panel", true)     -- cliente: acción del panel del vestuario
addEvent("rp:firefighters:onDuty", false)   -- interno: (on)

----------------------------------------------------------------
-- Atajos
----------------------------------------------------------------
function FD.db() return exports.rp_database:getConnection() end
function FD.notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
function FD.log(msg, level) outputDebugString("[rp_firefighters] " .. msg, level or 3) end
function FD.charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
function FD.isAdmin(p, level) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= (level or 1) end
function FD.nameOf(p)
    local n = exports.rp_characters:getPlayerCharacterName(p) or getPlayerName(p)
    return (tostring(n):gsub("_", " "))
end

function FD.takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < FIRE.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

function FD.dist(p, x, y, z)
    local px, py, pz = getElementPosition(p)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z)
end

-- Estados de la GM que impiden actuar. Devuelve el motivo o nil.
function FD.blockedReason(p)
    if isPedDead(p) or getElementData(p, "rp:downed") then return "No puedes hacer eso ahora." end
    if getElementData(p, "rp:cuffed") or getElementData(p, "rp:carried") then return "No puedes hacer eso ahora." end
    return nil
end

----------------------------------------------------------------
-- Pertenencia y servicio
----------------------------------------------------------------
function isFirefighter(p)
    if not isElement(p) then return false end
    local ok, id, _, _, _, kind = pcall(function() return exports.rp_factions:getPlayerFaction(p) end)
    return ok and id and kind == FIRE.FACTION_TYPE or false
end

function isOnDuty(p)
    return isElement(p) and duty[p] ~= nil
end

function getFirefightersOnDuty()
    local list = {}
    for p in pairs(duty) do if isElement(p) then list[#list + 1] = p end end
    return list
end

local function refreshDutyBlips()
    local list = getFirefightersOnDuty()
    for p, b in pairs(dutyBlips) do
        if not duty[p] then
            if isElement(b) then destroyElement(b) end
            dutyBlips[p] = nil
        end
    end
    for _, p in ipairs(list) do
        if not isElement(dutyBlips[p]) then
            dutyBlips[p] = createBlipAttachedTo(p, 0, 2, 235, 90, 40, 255, 0, 99999)
            setElementVisibleTo(dutyBlips[p], root, false)
        end
        for _, q in ipairs(list) do
            if q ~= p then setElementVisibleTo(dutyBlips[p], q, true) end
        end
    end
    FD.refreshIncidentBlip()   -- s_incidents: el blip del incidente solo lo ven los de servicio
end

local function applyUniform(p)
    local d = duty[p]
    if not d or not isElement(p) or isPedDead(p) then return end
    setElementModel(p, d.skin)
    setElementData(p, "rp:head", false)        -- la cabeza personalizada no va sobre el uniforme
    for _, e in ipairs(FIRE.EQUIPMENT) do
        if getPedTotalAmmo(p, getSlotFromWeapon(e.weapon)) <= 0 or getPedWeapon(p, getSlotFromWeapon(e.weapon)) ~= e.weapon then
            giveWeapon(p, e.weapon, e.ammo, false)
        end
    end
end

local function destroyTruck(p)
    local v = trucks[p]
    trucks[p] = nil
    if isElement(v) then destroyElement(v) end
end

function FD.setDuty(p, on, skin, silent)
    if on == isOnDuty(p) then return end
    if on then
        duty[p] = { skin = skin }
        applyUniform(p)
    else
        duty[p] = nil
        if isElement(p) then
            for _, e in ipairs(FIRE.EQUIPMENT) do takeWeapon(p, e.weapon) end
            if not isPedDead(p) then exports.rp_characters:restoreCharacterLook(p) end
        end
        destroyTruck(p)
    end
    if isElement(p) then setElementData(p, "rp:fireDuty", on and true or false) end
    triggerEvent("rp:firefighters:onDuty", p, on and true or false)
    refreshDutyBlips()
    if not silent and isElement(p) then
        FD.notify(p, on and "Entras de servicio: tienes extintor y motosierra. Te avisaremos de cada emergencia."
            or "Sales de servicio y devuelves el equipo.", on and "success" or "info")
    end
end

----------------------------------------------------------------
-- Experiencia de facción
----------------------------------------------------------------
local function loadStats(p, characterId)
    stats[p] = { characterId = characterId, xp = 0, fires = 0, rescues = 0, ok = 0, failed = 0 }
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local s = stats[p]
        if not isElement(p) or not s or s.characterId ~= characterId or not rows[1] then return end
        for _, k in ipairs({ "xp", "fires", "rescues", "ok", "failed" }) do s[k] = tonumber(rows[1][k]) or 0 end
    end, FD.db(), "SELECT xp, fires, rescues, ok, failed FROM firefighter_stats WHERE character_id = ?", characterId)
end

-- Suma al registro del personaje (en memoria y en la BD en el momento)
function FD.addStats(p, d)
    local s = stats[p]
    if not s then return end
    for k, v in pairs(d) do s[k] = (s[k] or 0) + v end
    dbExec(FD.db(), [[
        INSERT INTO firefighter_stats (character_id, xp, fires, rescues, ok, failed) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), fires = fires + VALUES(fires), rescues = rescues + VALUES(rescues),
                                ok = ok + VALUES(ok), failed = failed + VALUES(failed)]],
        s.characterId, d.xp or 0, d.fires or 0, d.rescues or 0, d.ok or 0, d.failed or 0)
end

function FD.getStats(p) return stats[p] end

-- Ingreso al banco pagado por el Estado (como rp_payday)
function FD.payBank(p, amount, concept)
    local s = stats[p]
    if not s or amount <= 0 then return end
    dbExec(FD.db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", amount, s.characterId)
    dbExec(FD.db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'bomberos', ?, ?)",
        s.characterId, amount, tostring(concept):sub(1, 32))
end

----------------------------------------------------------------
-- Vestuario y garaje
----------------------------------------------------------------
local function nearPoint(p, kind)
    local pt = points[kind]
    if not pt or getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return false end
    return FD.dist(p, pt.x, pt.y, pt.z) <= FIRE.INTERACT_RADIUS + 1.0
end

local function lockerData(p)
    local s = stats[p] or {}
    local idx, rank, nextXp, curXp = fireRankOf(s.xp)
    local skins = {}
    for i, sk in ipairs(FIRE.SKINS) do skins[i] = { id = sk.id, name = sk.name } end
    local equip = {}
    for i, e in ipairs(FIRE.EQUIPMENT) do equip[i] = e.name end
    return {
        onDuty = isOnDuty(p), skin = duty[p] and duty[p].skin or FIRE.SKINS[1].id,
        name = FD.nameOf(p), skins = skins, equipment = equip,
        stats = { xp = s.xp or 0, fires = s.fires or 0, rescues = s.rescues or 0, ok = s.ok or 0, failed = s.failed or 0 },
        rank = rank, rankIndex = idx, rankCount = #FIRE.RANKS, rankXp = curXp, nextXp = nextXp or false,
        colleagues = #getFirefightersOnDuty(),
    }
end

local function toggleTruck(p)
    if trucks[p] and isElement(trucks[p]) then
        local v = trucks[p]
        local g = points.garage
        local vx, vy, vz = getElementPosition(v)
        if getDistanceBetweenPoints3D(vx, vy, vz, g.x, g.y, g.z) > 40 then
            return FD.notify(p, "Trae la autobomba a la estación para guardarla.", "warning")
        end
        destroyTruck(p)
        return FD.notify(p, "Guardas la autobomba.", "success")
    end
    local t = points.truck
    for _, v in ipairs(getElementsByType("vehicle")) do
        local x, y, z = getElementPosition(v)
        if getDistanceBetweenPoints3D(x, y, z, t.x, t.y, t.z) < 4 then
            return FD.notify(p, "La salida del garaje está ocupada. Espera un momento.", "warning")
        end
    end
    -- Alterna modelo: si ya hay muchas autobombas fuera, sale la escala
    local out = 0
    for _, v in pairs(trucks) do if isElement(v) and getElementModel(v) == FIRE.TRUCKS[1] then out = out + 1 end end
    local model = FIRE.TRUCKS[(out >= 2 and #FIRE.TRUCKS > 1) and 2 or 1]
    local v = createVehicle(model, t.x, t.y, t.z, 0, 0, t.rot or 0, ("SFFD%03d"):format(exports.rp_ids:getPlayerId(p) or 0))
    if not v then return end
    setElementData(v, "rp:fireTruck", FD.charOf(p))
    setVehicleEngineState(v, true)
    trucks[p] = v
    warpPedIntoVehicle(p, v)
    FD.notify(p, "Sacas la autobomba. Su cañón de agua apaga el fuego desde lejos.", "success")
end

addEventHandler("rp:firefighters:use", resourceRoot, function(kind)
    local p = client
    if not FD.charOf(p) or not FD.takeCooldown(p) then return end
    if kind ~= "locker" and kind ~= "garage" then return end
    if not isFirefighter(p) then return FD.notify(p, "Solo el personal de bomberos puede usar esto.", "error") end
    if not nearPoint(p, kind) then return end
    local why = FD.blockedReason(p)
    if why then return FD.notify(p, why, "error") end
    if kind == "locker" then
        if isPedInVehicle(p) then return FD.notify(p, "Bájate del vehículo.", "warning") end
        triggerClientEvent(p, "rp:firefighters:lockerOpen", resourceRoot, lockerData(p))
    else
        if not isOnDuty(p) then return FD.notify(p, "Entra de servicio en el vestuario antes de sacar un vehículo.", "warning") end
        toggleTruck(p)
    end
end)

addEventHandler("rp:firefighters:panel", resourceRoot, function(action, arg)
    local p = client
    if type(action) ~= "string" or not FD.charOf(p) or not FD.takeCooldown(p) then return end
    if not isFirefighter(p) or not nearPoint(p, "locker") or isPedInVehicle(p) or FD.blockedReason(p) then return end
    if action == "duty_on" then
        local skin
        for _, sk in ipairs(FIRE.SKINS) do if sk.id == tonumber(arg) then skin = sk.id end end
        if not skin then return end
        if isOnDuty(p) then
            duty[p].skin = skin
            applyUniform(p)
            FD.notify(p, "Te cambias de uniforme.", "success")
        else
            FD.setDuty(p, true, skin)
        end
    elseif action == "duty_off" then
        FD.setDuty(p, false)
    else
        return
    end
    triggerClientEvent(p, "rp:firefighters:lockerOpen", resourceRoot, lockerData(p))
end)

----------------------------------------------------------------
-- Puntos de la estación (config + fire_points)
----------------------------------------------------------------
local POINT_STYLE = {
    locker = { icon = "clothes", label = "Vestuario de bomberos" },
    garage = { icon = "car", label = "Garaje de bomberos" },
}

function FD.placePoint(kind, x, y, z, rot, silent)
    local pt = points[kind] or {}
    if isElement(pt.marker) then destroyElement(pt.marker) end
    if isElement(pt.blip) then destroyElement(pt.blip) end
    pt.x, pt.y, pt.z, pt.rot = x, y, z, rot or 0
    pt.marker, pt.blip = nil, nil
    local style = POINT_STYLE[kind]
    if style then
        pt.marker = createMarker(x, y, z - 1, "cylinder", 1.2, 235, 90, 40, 140)
        pcall(function() exports.rp_markers:setMarkerStyle(pt.marker, { icon = style.icon, label = style.label, color = { 235, 90, 40 } }) end)
    end
    if kind == "locker" then
        local b = FIRE.STATION_BLIP
        pt.blip = createBlip(x, y, z, b.icon, 2, 255, 255, 255, 255, 0, b.visibleDistance)
    end
    points[kind] = pt
    if silent then return end          -- al arrancar, los clientes los piden con requestPoints
    triggerClientEvent(root, "rp:firefighters:points", resourceRoot, FD.pointsForClient())
end

function FD.pointsForClient()
    local out = {}
    for kind, pt in pairs(points) do
        if POINT_STYLE[kind] then out[kind] = { x = pt.x, y = pt.y, z = pt.z } end
    end
    return out
end

local function loadPoints()
    for kind, pt in pairs(FIRE.POINTS) do FD.placePoint(kind, pt.x, pt.y, pt.z, pt.rot, true) end
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            if FIRE.POINTS[r.kind] then FD.placePoint(r.kind, tonumber(r.x), tonumber(r.y), tonumber(r.z), tonumber(r.rot)) end
        end
    end, FD.db(), "SELECT kind, x, y, z, rot FROM fire_points")
end

addEvent("rp:firefighters:requestPoints", true)
addEventHandler("rp:firefighters:requestPoints", resourceRoot, function()
    triggerClientEvent(client, "rp:firefighters:points", resourceRoot, FD.pointsForClient())
end)

----------------------------------------------------------------
-- Ciclo de vida del jugador
----------------------------------------------------------------
local function forget(p)
    if duty[p] then FD.setDuty(p, false, nil, true) end
    destroyTruck(p)
    stats[p], cooldown[p] = nil, nil
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) loadStats(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)

-- Revivido o reaparecido en el hospital: rp_injury/rp_characters le devuelven su ropa; se vuelve a uniformar
addEventHandler("onPlayerSpawn", root, function()
    local p = source
    if duty[p] then setTimer(applyUniform, 600, 1, p) end
end)

-- Si lo echan de la facción, sale de servicio
setTimer(function()
    for p in pairs(duty) do
        if not isElement(p) then duty[p] = nil elseif not isFirefighter(p) then FD.setDuty(p, false) end
    end
end, 5000, 0)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    loadPoints()
    for _, p in ipairs(getElementsByType("player")) do
        local characterId = FD.charOf(p)
        if characterId then loadStats(p, characterId) end
        setElementData(p, "rp:fireDuty", false)
    end
    FD.bootIncidents()
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(duty) do
        if isElement(p) then
            for _, e in ipairs(FIRE.EQUIPMENT) do takeWeapon(p, e.weapon) end
            if not isPedDead(p) then exports.rp_characters:restoreCharacterLook(p) end
            setElementData(p, "rp:fireDuty", false)
        end
    end
end)
