--[[
    rp_medics / s_core.lua  (servidor)

    Base de la facción de médicos (facciones de tipo MED.FACTION_TYPE):
      - Vestuario (E): panel para entrar o salir de servicio eligiendo uniforme, con el
        casillero personal (s_locker.lua) para dejar tus cosas y tu mochila.
        De servicio: uniforme, mochila médica con material, blip de compañeros y sueldo
        de rol (rp_factions solo lo paga de servicio).
      - Garaje (E): saca o guarda una ambulancia del hospital.
    Comandos de admin en s_admin.lua.

    Exports (servidor): isOnDuty(p), isMedic(p), getMedicsOnDuty()
]]

MD = {}                       -- funciones compartidas entre los s_*.lua de este recurso

local duty = {}               -- [player] = { skin = id }
local ambulances = {}         -- [player] = vehículo del hospital
local cooldown = {}           -- [player] = tick
local points = {}             -- [kind] = { x, y, z, rot, marker }
local dutyBlips = {}          -- [player] = blip del médico (solo lo ven sus compañeros de servicio)
local uniformTimers = {}      -- [player] = timer que vuelve a poner el uniforme tras reaparecer

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:medics:use", true)            -- cliente: E en vestuario o garaje
addEvent("rp:medics:panel", true)          -- cliente: acción del panel del vestuario
addEvent("rp:medics:requestPoints", true)
addEvent("rp:medics:onDuty", false)        -- interno: (on)

----------------------------------------------------------------
-- Atajos
----------------------------------------------------------------
function MD.db() return exports.rp_database:getConnection() end
function MD.notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
function MD.log(msg, level) outputDebugString("[rp_medics] " .. msg, level or 3) end
function MD.charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
function MD.isAdmin(p, level) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= (level or 1) end
function MD.nameOf(p)
    local n = exports.rp_characters:getPlayerCharacterName(p) or getPlayerName(p)
    return (tostring(n):gsub("_", " "))
end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < MED.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

local function blocked(p)
    return isPedDead(p) or getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") or getElementData(p, "rp:carried")
end

----------------------------------------------------------------
-- Pertenencia y servicio
----------------------------------------------------------------
function isMedic(p)
    if not isElement(p) then return false end
    local ok, yes = pcall(function() return exports.rp_factions:isPlayerInFaction(p, MED.FACTION_TYPE) end)
    return ok and yes == true
end

function isOnDuty(p)
    return isElement(p) and duty[p] ~= nil
end

function getMedicsOnDuty()
    local list = {}
    for p in pairs(duty) do if isElement(p) then list[#list + 1] = p end end
    return list
end

local function refreshDutyBlips()
    local list = getMedicsOnDuty()
    for p, b in pairs(dutyBlips) do
        if not duty[p] then
            if isElement(b) then destroyElement(b) end
            dutyBlips[p] = nil
        end
    end
    for _, p in ipairs(list) do
        if not isElement(dutyBlips[p]) then
            dutyBlips[p] = createBlipAttachedTo(p, 0, 2, 229, 72, 77, 255, 0, 99999)
            setElementVisibleTo(dutyBlips[p], root, false)
        end
        for _, q in ipairs(list) do
            if q ~= p then setElementVisibleTo(dutyBlips[p], q, true) end
        end
    end
end

local function applyUniform(p)
    local d = duty[p]
    if not d or not isElement(p) or isPedDead(p) then return end
    setElementModel(p, d.skin)
    setElementData(p, "rp:head", false)        -- la cabeza personalizada no va sobre el uniforme
end

local function destroyAmbulance(p)
    local v = ambulances[p]
    ambulances[p] = nil
    if isElement(v) then destroyElement(v) end
end

-- Mochila médica con el material: se pone al entrar de servicio
local function giveKit(p)
    local contents = {}
    for _, e in ipairs(MED.EQUIPMENT) do contents[e.item] = e.amount end
    local ok, why = exports.rp_backpacks:equipFromGround(p, MED.DUTY_BACKPACK, contents)
    if not ok then MD.log(("no se pudo dar la mochila medica a %s: %s"):format(getPlayerName(p), tostring(why)), 2) end
    return ok
end

-- Se retira la mochila médica y el material que se sacó de ella al inventario.
-- shortcut: quita hasta lo entregado aunque el médico ya tuviera botiquines propios encima; si se separan, contar por origen.
local function takeKit(p)
    if exports.rp_backpacks:getBackpack(p) == MED.DUTY_BACKPACK then exports.rp_backpacks:stowBackpack(p) end
    for _, e in ipairs(MED.EQUIPMENT) do
        local n = math.min(e.amount, exports.rp_inventory:getItemAmount(p, e.item))
        if n > 0 then exports.rp_inventory:takeItem(p, e.item, n) end
    end
end

function MD.setDuty(p, on, skin, silent)
    if on == isOnDuty(p) then return end
    if on then
        duty[p] = { skin = skin }
        applyUniform(p)
        giveKit(p)
    else
        duty[p] = nil
        if isElement(p) then
            pcall(takeKit, p)
            if not isPedDead(p) then exports.rp_characters:restoreCharacterLook(p) end
        end
        destroyAmbulance(p)
    end
    if isElement(p) then setElementData(p, "rp:medDuty", on and true or false) end
    triggerEvent("rp:medics:onDuty", p, on and true or false)
    refreshDutyBlips()
    if not silent and isElement(p) then
        MD.notify(p, on and "Entras de servicio: llevas la mochila médica con el material."
            or "Sales de servicio y devuelves la mochila médica.", on and "success" or "info")
    end
end

----------------------------------------------------------------
-- Vestuario y garaje
----------------------------------------------------------------
local function dist(p, x, y, z)
    local px, py, pz = getElementPosition(p)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z)
end

local function nearPoint(p, kind)
    local pt = points[kind]
    if not pt or getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return false end
    return dist(p, pt.x, pt.y, pt.z) <= MED.INTERACT_RADIUS + 1.0
end

local function lockerData(p)
    local skins = {}
    for i, sk in ipairs(MED.SKINS) do skins[i] = { id = sk.id, name = sk.name } end
    local data = MD.lockerData(p)
    data.onDuty = isOnDuty(p)
    data.skin = duty[p] and duty[p].skin or MED.SKINS[1].id
    data.skins = skins
    data.name = MD.nameOf(p)
    data.colleagues = #getMedicsOnDuty()
    data.requireUnarmed = MED.REQUIRE_UNARMED
    return data
end

local function sendPanel(p)
    triggerClientEvent(p, "rp:medics:lockerOpen", resourceRoot, lockerData(p))
end

local function toggleAmbulance(p)
    if isElement(ambulances[p]) then
        local g = points.garage
        local vx, vy, vz = getElementPosition(ambulances[p])
        if getDistanceBetweenPoints3D(vx, vy, vz, g.x, g.y, g.z) > 40 then
            return MD.notify(p, "Trae la ambulancia al hospital para guardarla.", "warning")
        end
        destroyAmbulance(p)
        return MD.notify(p, "Guardas la ambulancia.", "success")
    end
    local a = points.ambulance
    for _, v in ipairs(getElementsByType("vehicle")) do
        local x, y, z = getElementPosition(v)
        if getDistanceBetweenPoints3D(x, y, z, a.x, a.y, a.z) < 4 then
            return MD.notify(p, "La salida del garaje está ocupada. Espera un momento.", "warning")
        end
    end
    local plate = ("LSMD%03d"):format(exports.rp_ids:getPlayerId(p) or 0)
    local v = createVehicle(MED.AMBULANCES[1], a.x, a.y, a.z, 0, 0, a.rot or 0, plate)
    if not v then return end
    setElementData(v, "rp:ambulance", MD.charOf(p))
    setVehicleEngineState(v, true)
    ambulances[p] = v
    warpPedIntoVehicle(p, v)
    MD.notify(p, "Sacas la ambulancia. Guárdala aquí mismo al terminar.", "success")
end

addEventHandler("rp:medics:use", resourceRoot, function(kind)
    local p = client
    if not MD.charOf(p) or not takeCooldown(p) then return end
    if kind ~= "locker" and kind ~= "garage" then return end
    if not isMedic(p) then return MD.notify(p, "Solo el personal médico puede usar esto.", "error") end
    if not nearPoint(p, kind) then return end
    if blocked(p) then return MD.notify(p, "No puedes hacer eso ahora.", "error") end
    if kind == "locker" then
        if isPedInVehicle(p) then return MD.notify(p, "Bájate del vehículo.", "warning") end
        sendPanel(p)
    else
        if not isOnDuty(p) then return MD.notify(p, "Entra de servicio en el vestuario antes de sacar una ambulancia.", "warning") end
        toggleAmbulance(p)
    end
end)

local function validSkin(id)
    for _, sk in ipairs(MED.SKINS) do if sk.id == tonumber(id) then return sk.id end end
end

local ACTIONS = {}

ACTIONS.duty_on = function(p, skinArg, storeAll)
    local skin = validSkin(skinArg)
    if not skin then return end
    if isOnDuty(p) then
        duty[p].skin = skin
        applyUniform(p)
        return MD.notify(p, "Te cambias de uniforme.", "success")
    end
    if storeAll == true then MD.storeAll(p) end
    local worn = exports.rp_backpacks:getBackpack(p)
    if worn and worn ~= MED.DUTY_BACKPACK then
        return MD.notify(p, "Deja tu mochila en el casillero: de servicio llevas la mochila médica.", "warning")
    end
    if MED.REQUIRE_UNARMED and MD.carriesWeapons(p) then
        return MD.notify(p, "Guarda tus armas en el casillero antes de entrar de servicio.", "warning")
    end
    MD.setDuty(p, true, skin)
end

ACTIONS.duty_off = function(p, takeAll)
    if not isOnDuty(p) then return end
    MD.setDuty(p, false)
    if takeAll == true then
        local left = MD.takeAll(p)
        if left > 0 then
            MD.notify(p, ("Te quedan %d cosas en el casillero: no te caben."):format(left), "warning")
        end
    end
end

ACTIONS.store = function(p, itemId)
    if type(itemId) ~= "string" then return end
    local ok, why = MD.storeItem(p, itemId)
    if not ok then MD.notify(p, why, "warning") end
end

ACTIONS.take = function(p, itemId)
    if type(itemId) ~= "string" then return end
    local n, why = MD.takeItem(p, itemId)
    if n < 1 then MD.notify(p, why, "warning") end
end

ACTIONS.store_pack = function(p)
    local ok, why = MD.storePack(p)
    if not ok then MD.notify(p, why, "warning") end
end

ACTIONS.take_pack = function(p)
    local ok, why = MD.takePack(p)
    if not ok then MD.notify(p, why, "warning") end
end

addEventHandler("rp:medics:panel", resourceRoot, function(action, a, b)
    local p = client
    local fn = type(action) == "string" and ACTIONS[action]
    if not fn or not MD.charOf(p) or not takeCooldown(p) then return end
    if not isMedic(p) or not nearPoint(p, "locker") or isPedInVehicle(p) or blocked(p) then return end
    if not MD.lockerReady(p) then return MD.notify(p, "Tu casillero se está cargando.", "info") end
    fn(p, a, b)
    sendPanel(p)
end)

----------------------------------------------------------------
-- Puntos del hospital (config + medic_points)
----------------------------------------------------------------
local POINT_STYLE = {
    locker = { icon = "clothes", label = "Vestuario médico" },
    garage = { icon = "car", label = "Garaje de ambulancias" },
}

function MD.placePoint(kind, x, y, z, rot, silent)
    local pt = points[kind] or {}
    if isElement(pt.marker) then destroyElement(pt.marker) end
    pt.x, pt.y, pt.z, pt.rot, pt.marker = x, y, z, rot or 0, nil
    local style = POINT_STYLE[kind]
    if style then
        pt.marker = createMarker(x, y, z - 1, "cylinder", 1.2, 229, 72, 77, 140)
        pcall(function()
            exports.rp_markers:setMarkerStyle(pt.marker, { icon = style.icon, label = style.label, color = { 229, 72, 77 } })
            -- Movible con el editor de rp_admin; se guarda en medic_points (rp:markers:moved, abajo)
            exports.rp_markers:registerMarker(pt.marker, kind, { label = style.label, point = { x, y, z }, ownerSaves = true })
        end)
    end
    points[kind] = pt
    if silent then return end          -- al arrancar, los clientes los piden con requestPoints
    triggerClientEvent(root, "rp:medics:points", resourceRoot, MD.pointsForClient())
end

addEvent("rp:markers:moved")
addEventHandler("rp:markers:moved", root, function(owner, kind, x, y, z, admin)
    if owner ~= getResourceName(resource) or not POINT_STYLE[kind] or not x then return end
    local rot = points[kind] and points[kind].rot or 0
    dbExec(MD.db(), "REPLACE INTO medic_points (kind, x, y, z, rot) VALUES (?, ?, ?, ?, ?)", kind, x, y, z, rot)
    MD.placePoint(kind, x, y, z, rot)
    MD.log(("%s movio el punto %s con el editor"):format(isElement(admin) and getPlayerName(admin) or "?", kind))
end)

function MD.pointsForClient()
    local out = {}
    for kind, pt in pairs(points) do
        if POINT_STYLE[kind] then out[kind] = { x = pt.x, y = pt.y, z = pt.z } end
    end
    return out
end

local function loadPoints()
    for kind, pt in pairs(MED.POINTS) do MD.placePoint(kind, pt.x, pt.y, pt.z, pt.rot, true) end
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            if MED.POINTS[r.kind] then MD.placePoint(r.kind, tonumber(r.x), tonumber(r.y), tonumber(r.z), tonumber(r.rot)) end
        end
    end, MD.db(), "SELECT kind, x, y, z, rot FROM medic_points")
end

addEventHandler("rp:medics:requestPoints", resourceRoot, function()
    triggerClientEvent(client, "rp:medics:points", resourceRoot, MD.pointsForClient())
end)

----------------------------------------------------------------
-- Ciclo de vida del jugador
----------------------------------------------------------------
local function forget(p)
    if duty[p] then MD.setDuty(p, false, nil, true) end
    destroyAmbulance(p)
    MD.unloadLocker(p)
    if isTimer(uniformTimers[p]) then killTimer(uniformTimers[p]) end
    uniformTimers[p], cooldown[p] = nil, nil
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) MD.loadLocker(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() forget(source) end)
addEventHandler("onPlayerQuit", root, function() forget(source) end)

-- Revivido o reaparecido en el hospital: se le devuelve su ropa; se vuelve a uniformar
addEventHandler("onPlayerSpawn", root, function()
    local p = source
    if not duty[p] then return end
    if isTimer(uniformTimers[p]) then killTimer(uniformTimers[p]) end
    uniformTimers[p] = setTimer(function() uniformTimers[p] = nil applyUniform(p) end, 600, 1)
end)

-- Si lo echan de la facción, sale de servicio (sus cosas siguen en el casillero)
setTimer(function()
    for p in pairs(duty) do
        if not isElement(p) then duty[p] = nil elseif not isMedic(p) then MD.setDuty(p, false) end
    end
end, 5000, 0)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    loadPoints()
    for _, p in ipairs(getElementsByType("player")) do
        local characterId = MD.charOf(p)
        if characterId then MD.loadLocker(p, characterId) end
        setElementData(p, "rp:medDuty", false)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(duty) do
        if isElement(p) then
            pcall(takeKit, p)
            if not isPedDead(p) then exports.rp_characters:restoreCharacterLook(p) end
            setElementData(p, "rp:medDuty", false)
        end
    end
end)
