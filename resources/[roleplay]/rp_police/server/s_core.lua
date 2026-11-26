--[[
    rp_police / s_core.lua
    Base del sistema policial de la faccion 1:
      - Funciones globales compartidas por los demas s_*.lua (permisos, duty, UI)
      - Servicio (vestuario): sin servicio no hay permisos, ni sueldo de rol, ni radar
      - Puntos fisicos (vestuario, armeria, garaje, laboratorio, calabozos)
      - Roles por defecto de la faccion 1 (Cadete ... Comisario)
      - Blips de unidades en servicio (solo los ven los policias de servicio)

    Admin: /pmover <vestuario|armeria|garaje|lab|calabozos|patrulla>  (nivel 3)
]]

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:pol:use", true)
addEvent("rp:pol:ui", true)
addEvent("rp:pol:uiClosed", true)
addEvent("rp:pol:requestPoints", true)

UI_ACTIONS = {}           -- [accion] = function(player, data)
local duty = {}           -- [player] = true
local blips = {}          -- [player] = blip
local openUI = {}         -- [player] = modo
local lastUI = {}         -- [player] = tick
POINTS = {}               -- [tipo] = { x, y, z, rot, marker }

function db() return exports.rp_database:getConnection() end
function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
function popup(p, title, text, kind) exports.rp_notify:popup(p, title, text, kind) end
function charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
function dname(p)
    local n = exports.rp_characters:getPlayerCharacterName(p) or getPlayerName(p)
    return (tostring(n):gsub("_", " "))
end
local function adminLevel(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end

function isOfficer(p)
    local ok, id = pcall(function() return exports.rp_factions:getPlayerFaction(p) end)
    return ok and tonumber(id) == POLICE.FACTION_ID
end

function isOnDuty(p)
    return isElement(p) and duty[p] == true and isOfficer(p)
end

-- Servicio + permiso del rol (el lider los tiene todos)
function can(p, perm)
    if not isOnDuty(p) then return false end
    return exports.rp_factions:hasFactionPermission(p, perm)
end

function rankLevel(p)
    local ok, lv = pcall(function() return exports.rp_factions:getPlayerRankLevel(p) end)
    return ok and lv or 0
end

function officersOnDuty()
    local list = {}
    for p in pairs(duty) do
        if isElement(p) and isOfficer(p) then list[#list + 1] = p end
    end
    return list
end

function factionLog(text)
    dbExec(db(), "INSERT INTO faction_log (faction_id, text) VALUES (?, ?)", POLICE.FACTION_ID, tostring(text):sub(1, 255))
end

function distPlayers(a, b)
    if not isElement(a) or not isElement(b) then return 9999 end
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
end

function nearPoint(player, kind, radius)
    local pt = POINTS[kind]
    if not pt or not isElement(player) then return false end
    if getElementInterior(player) ~= (POLICE_POINTS[kind].interior or 0) or getElementDimension(player) ~= 0 then return false end
    local x, y, z = getElementPosition(player)
    return getDistanceBetweenPoints3D(x, y, z, pt.x, pt.y, pt.z) <= (radius or POLICE.POINT_RADIUS + 1.2)
end

----------------------------------------------------------------
-- UI (un solo panel CEF para MDT, cacheo, armeria, garaje, laboratorio y formularios)
----------------------------------------------------------------
function showUI(player, mode, data)
    if not isElement(player) then return end
    openUI[player] = mode
    triggerClientEvent(player, "rp:pol:ui:open", resourceRoot, mode, data or {})
end

function updateUI(player, kind, data)
    if isElement(player) and openUI[player] then
        triggerClientEvent(player, "rp:pol:ui:update", resourceRoot, kind, data or {})
    end
end

function currentUI(player) return openUI[player] end

addEventHandler("rp:pol:uiClosed", resourceRoot, function() openUI[client] = nil end)

addEventHandler("rp:pol:ui", resourceRoot, function(action, data)
    local player = client
    if type(action) ~= "string" or type(data) ~= "table" then return end
    local now = getTickCount()
    if lastUI[player] and now - lastUI[player] < 120 then return end
    lastUI[player] = now
    if not charOf(player) or not openUI[player] then return end
    local handler = UI_ACTIONS[action]
    if handler then handler(player, data) end
end)

----------------------------------------------------------------
-- Servicio
----------------------------------------------------------------
local function refreshBlips()
    local list = officersOnDuty()
    for p, b in pairs(blips) do
        if not duty[p] or not isElement(p) then
            if isElement(b) then destroyElement(b) end
            blips[p] = nil
        end
    end
    for _, p in ipairs(list) do
        if not isElement(blips[p]) then
            blips[p] = createBlipAttachedTo(p, 0, 2, 59, 111, 224, 255, 0, 99999)
        end
        setElementVisibleTo(blips[p], root, false)
        for _, q in ipairs(list) do setElementVisibleTo(blips[p], q, true) end
    end
end

function setDuty(player, on, silent)
    if on == (duty[player] == true) then return end
    duty[player] = on or nil
    setElementData(player, "rp:policeDuty", on and true or false)
    if not on then
        -- Devolver el equipo reglamentario
        for _, a in ipairs(POLICE_ARMORY) do
            if a.issued then
                local have = exports.rp_inventory:getItemAmount(player, a.item)
                if have > 0 then exports.rp_inventory:takeItem(player, a.item, have) end
            end
        end
        takeWeapon(player, 23)
        takeWeapon(player, 3)
    end
    refreshBlips()
    triggerEvent("rp:pol:onDuty", player, on and true or false)
    if not silent then
        notify(player, on and "Entras de servicio. Ya tienes tus permisos, el sueldo y el radar activos."
            or "Sales de servicio. Devuelves el equipo reglamentario.", on and "success" or "info")
        factionLog(("%s %s de servicio."):format(dname(player), on and "entro" or "salio"))
    end
end
addEvent("rp:pol:onDuty", false)

function toggleDuty(player)
    if not isOfficer(player) then return end
    if isPedInVehicle(player) then return notify(player, "Bajate del vehiculo.", "warning") end
    setDuty(player, not isOnDuty(player))
end

local function forget(player)
    if duty[player] then
        duty[player] = nil
        refreshBlips()
        triggerEvent("rp:pol:onDuty", player, false)
    end
    openUI[player], lastUI[player] = nil, nil
    if isElement(player) then setElementData(player, "rp:policeDuty", false) end
end
addEventHandler("onPlayerQuit", root, function() forget(source) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerWasted", root, function()
    if duty[source] then openUI[source] = nil end
end)

-- Si lo echan de la faccion, sale de servicio
setTimer(function()
    for p in pairs(duty) do
        if not isElement(p) or not isOfficer(p) then forget(p) end
    end
end, 5000, 0)

----------------------------------------------------------------
-- Puntos fisicos
----------------------------------------------------------------
-- Icono de rp_markers de cada punto fisico
local POINT_ICONS = {
    entrance = "police", exit = "exit", locker = "clothes", armory = "gun",
    lab = "info", booking = "key", garage = "car",
}

local function placePoint(kind, x, y, z, rot)
    local def = POLICE_POINTS[kind]
    local pt = POINTS[kind] or {}
    pt.x, pt.y, pt.z, pt.rot = x, y, z, rot or 0
    if not def.hidden then
        if isElement(pt.marker) then destroyElement(pt.marker) end
        local c = def.color
        pt.marker = createMarker(x, y, z - 0.95, "cylinder", 1.6, c[1], c[2], c[3], 110)
        setElementInterior(pt.marker, def.interior or 0)
        exports.rp_markers:setMarkerStyle(pt.marker, { icon = POINT_ICONS[kind] or "police", label = def.label,
            color = kind ~= "exit" and { 59, 111, 224 } or nil })  -- azul policía salvo la salida (verde)
        if isElement(pt.blip) then destroyElement(pt.blip) end
    end
    POINTS[kind] = pt
end

local function pointList()
    local out = {}
    for kind, def in pairs(POLICE_POINTS) do
        local pt = POINTS[kind]
        if pt and not def.hidden then out[#out + 1] = { kind = kind, label = def.label, x = pt.x, y = pt.y, z = pt.z, interior = def.interior or 0 } end
    end
    return out
end

local function loadPoints()
    for kind, def in pairs(POLICE_POINTS) do placePoint(kind, def.x, def.y, def.z, def.rot) end
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            if POLICE_POINTS[r.kind] then placePoint(r.kind, r.x, r.y, r.z, r.rot) end
        end
        triggerClientEvent("rp:pol:points", resourceRoot, pointList())
    end, db(), "SELECT kind, x, y, z, rot FROM police_points")
end

addEventHandler("rp:pol:requestPoints", resourceRoot, function()
    triggerClientEvent(client, "rp:pol:points", resourceRoot, pointList())
end)

local pointAliases = {
    entrada = "entrance", salida = "exit", vestuario = "locker", armeria = "armory", garaje = "garage",
    lab = "lab", calabozos = "booking", patrulla = "garage_spawn",
}
local pointUsage = "entrada|salida|vestuario|armeria|garaje|lab|calabozos|patrulla"

local function resolveKind(name)
    name = name and name:lower()
    return name and (pointAliases[name] or (POLICE_POINTS[name] and name)) or nil
end

-- /pmover <punto>: mueve el marcador a tu posicion (estando en el interior correcto)
addCommandHandler("pmover", function(admin, _, name)
    if adminLevel(admin) < 3 then return notify(admin, "Necesitas nivel de admin 3 para mover los puntos de la policia.", "error") end
    local kind = resolveKind(name)
    if not kind then return notify(admin, "Uso: /pmover <" .. pointUsage .. ">", "info") end
    local def = POLICE_POINTS[kind]
    if getElementInterior(admin) ~= (def.interior or 0) then
        return notify(admin, ("Ese punto va en el interior %d y estas en el %d."):format(def.interior or 0, getElementInterior(admin)), "warning")
    end
    local el = getPedOccupiedVehicle(admin) or admin
    local x, y, z = getElementPosition(el)
    local rot = select(3, getElementRotation(el))
    placePoint(kind, x, y, z, rot)
    dbExec(db(), "REPLACE INTO police_points (kind, x, y, z, rot) VALUES (?, ?, ?, ?, ?)", kind, x, y, z, rot)
    triggerClientEvent("rp:pol:points", resourceRoot, pointList())
    notify(admin, ("Punto '%s' movido a %.1f, %.1f, %.1f (mira a %d)."):format(kind, x, y, z, rot), "success")
end)

-- /pir <punto>: te lleva al punto (para encontrarlo o comprobarlo)
addCommandHandler("pir", function(admin, _, name)
    if adminLevel(admin) < 3 then return end
    local kind = resolveKind(name)
    local pt = kind and POINTS[kind]
    if not pt then return notify(admin, "Uso: /pir <" .. pointUsage .. ">", "info") end
    if getPedOccupiedVehicle(admin) then removePedFromVehicle(admin) end
    setElementInterior(admin, POLICE_POINTS[kind].interior or 0)
    setElementDimension(admin, 0)
    setElementPosition(admin, pt.x, pt.y, pt.z + 0.3)
    notify(admin, "Teletransportado a '" .. kind .. "'.", "info")
end)

-- /plista: todos los puntos con su posicion actual
addCommandHandler("plista", function(admin)
    if adminLevel(admin) < 3 then return end
    for kind, def in pairs(POLICE_POINTS) do
        local pt = POINTS[kind]
        outputChatBox(("[Policia] %s (int %d): %.1f, %.1f, %.1f"):format(kind, def.interior or 0, pt.x, pt.y, pt.z), admin, 120, 170, 255)
    end
end)

-- Entrada y salida de la comisaria (publicas)
local lastDoor = {}
local function useDoor(player, kind)
    local now = getTickCount()
    if lastDoor[player] and now - lastDoor[player] < 1500 then return end
    if isPedInVehicle(player) then return notify(player, "Bajate del vehiculo.", "warning") end
    lastDoor[player] = now
    local to = kind == "entrance" and "exit" or "entrance"
    local def, pt = POLICE_POINTS[to], POINTS[to]
    local r = math.rad(pt.rot or 0)
    local x, y, z = pt.x - math.sin(r) * 2, pt.y + math.cos(r) * 2, pt.z
    fadeCamera(player, false, 0.25)
    setTimer(function()
        if not isElement(player) then return end
        setElementInterior(player, def.interior or 0)
        setElementDimension(player, 0)
        setElementPosition(player, x, y, z)
        setElementRotation(player, 0, 0, pt.rot or 0)
        setCameraTarget(player, player)
        moveEscorted(player, x, y, z, def.interior or 0)
        fadeCamera(player, true, 0.4)
    end, 300, 1)
end
addEventHandler("onPlayerQuit", root, function() lastDoor[source] = nil end)

addEventHandler("rp:pol:use", resourceRoot, function(kind)
    local player = client
    if type(kind) ~= "string" or not charOf(player) or isPedDead(player) then return end
    if kind == "evidence" then return collectEvidence(player) end
    if not POLICE_POINTS[kind] or POLICE_POINTS[kind].hidden then return end
    if not nearPoint(player, kind) then return end
    if kind == "entrance" or kind == "exit" then return useDoor(player, kind) end
    if not isOfficer(player) then return notify(player, "Solo el personal de la policia puede usar esto.", "warning") end
    if kind == "locker" then return toggleDuty(player) end
    if not isOnDuty(player) then return notify(player, "Debes estar de servicio (vestuario).", "warning") end
    if kind == "armory" then return openArmory(player) end
    if kind == "garage" then return openGarage(player) end
    if kind == "lab" then return openLab(player) end
    if kind == "booking" then
        return notify(player, "Calabozos: lleva a un detenido esposado y usa K > Arrestar cerca de este punto.", "info")
    end
end)

----------------------------------------------------------------
-- Roles de la faccion 1
----------------------------------------------------------------
local function seedRanks()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local f1 = rows[1]
        if not f1 or tonumber(f1.n) == nil then return end
        local n = tonumber(f1.n)
        if n > 2 then return end   -- ya configurados por un lider/admin
        local pending = 0
        local function done()
            pending = pending - 1
            if pending == 0 then
                pcall(function() exports.rp_factions:reloadFactions() end)
                outputServerLog("[rp_police] roles de la faccion 1 sembrados")
            end
        end
        local function run(sql, ...)
            pending = pending + 1
            dbQuery(function(q) dbPoll(q, 0) done() end, db(), sql, ...)
        end
        run("UPDATE IGNORE faction_ranks SET name = 'Oficial I', level = 2, salary = 800, permissions = ? WHERE faction_id = ? AND name = 'Oficial' AND permissions = 1",
            policePermMask(POLICE_RANKS[2].perms), POLICE.FACTION_ID)
        run("UPDATE faction_ranks SET permissions = ? WHERE faction_id = ? AND name = 'Comisario' AND permissions = 1023",
            policePermMask("all"), POLICE.FACTION_ID)
        for _, r in ipairs(POLICE_RANKS) do
            run("INSERT IGNORE INTO faction_ranks (faction_id, name, level, salary, permissions) SELECT id, ?, ?, ?, ? FROM factions WHERE id = ? AND type = 'policia'",
                r.name, r.level, r.salary, policePermMask(r.perms), POLICE.FACTION_ID)
        end
    end, db(), "SELECT COUNT(*) AS n FROM faction_ranks WHERE faction_id = ? AND EXISTS (SELECT 1 FROM factions WHERE id = ? AND type = 'policia')",
        POLICE.FACTION_ID, POLICE.FACTION_ID)
end

local function start()
    loadPoints()
    seedRanks()
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then start() else addEventHandler("rp:onDatabaseReady", root, start) end
    for _, p in ipairs(getElementsByType("player")) do setElementData(p, "rp:policeDuty", false) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(duty) do
        if isElement(p) then setElementData(p, "rp:policeDuty", false) end
    end
end)
