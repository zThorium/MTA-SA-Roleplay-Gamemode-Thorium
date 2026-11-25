--[[
    rp_shootingrange / s_main.lua  (servidor)

    Campo de tiro de Ammu-Nation. El jugador pulsa E en el mostrador de la armeria, elige un arma
    de su inventario y entrena 3 rondas de blancos (estaticos, que avanzan, lateral) con SUS balas.
    Cada jugador entra en su propia dimension. La habilidad nativa del arma (stats 69-79) sube solo
    con impactos validos y se guarda en weapon_skills.

    Exports (servidor):
        isPlayerInRange(player)
    shortcut: si el jugador se desconecta dentro del campo, rp_characters puede guardar su posicion
    antes de que lo devolvamos a la tienda; reaparecera dentro del interior 7 (solucion: moverlo en rp_characters).
]]
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:range:open", true)
addEvent("rp:range:reopen", true)
addEvent("rp:range:train", true)
addEvent("rp:range:abort", true)
addEvent("rp:range:exit", true)

local usedDims = {}

local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end

local function locationById(id)
    for _, l in ipairs(RANGE.LOCATIONS) do if l.id == id then return l end end
end

local function storeDim(loc) return RANGE.STORE_DIM_BASE + loc.id end

-- Ubicacion de cuyo mostrador esta cerca el jugador (interior + dimension + distancia)
local function nearDesk(p)
    if getElementInterior(p) ~= RANGE.STORE_INTERIOR then return nil end
    local px, py, pz = getElementPosition(p)
    local D = RANGE.DESK
    if getDistanceBetweenPoints3D(px, py, pz, D.x, D.y, D.z) > RANGE.INTERACT_RADIUS + 0.5 then return nil end
    for _, l in ipairs(RANGE.LOCATIONS) do
        if getElementDimension(p) == storeDim(l) then return l end
    end
end

local function blockedReason(p)
    if getElementData(p, "rp:downed") or exports.rp_injury:isPlayerDowned(p) then return "No puedes hacer eso ahora." end
    if isPedDead(p) or isPedInVehicle(p) then return "Bajate del vehiculo." end
end

local function takeCooldown(ps)
    local now = getTickCount()
    if ps.last and now - ps.last < RANGE.COOLDOWN_MS then return false end
    ps.last = now
    return true
end

local function sendMenu(p, ps)
    triggerClientEvent(p, "rp:range:menu", resourceRoot, {
        inside = ps.inside, player = exports.rp_characters:getPlayerCharacterName(p) or "", location = ps.loc and ps.loc.name or "", weapons = rangeWeaponList(p),
        categories = RANGE.CATEGORIES, rounds = #RANGE.ROUNDS,
    })
end

local function exitRange(p)
    local ps = rangePlayers[p]
    if not ps or not ps.inside then return end
    finishSession(p, "exit", true)
    ps.inside = false
    if ps.dim then usedDims[ps.dim] = nil end
    ps.dim = nil
    if isElement(p) then
        local D, loc = RANGE.DESK, ps.loc
        setElementInterior(p, RANGE.STORE_INTERIOR, D.x, D.y, D.z)
        setElementDimension(p, storeDim(loc))
        exports.rp_ammunation:resumeWeapons(p, ps.prevItem)
        triggerClientEvent(p, "rp:range:close", resourceRoot)
    end
    ps.prevItem = nil
end

local function enterRange(p, ps, loc)
    local slot
    for i = 1, RANGE.DIM_SLOTS do
        if not usedDims[RANGE.DIM_BASE + i] then slot = RANGE.DIM_BASE + i; break end
    end
    if not slot then return false, "El campo de tiro esta lleno. Vuelve en un rato." end
    usedDims[slot] = true
    ps.dim, ps.loc, ps.inside = slot, loc, true
    ps.prevItem = exports.rp_ammunation:suspendWeapons(p)
    local F = RANGE.FIRE
    setElementInterior(p, RANGE.INTERIOR, F.x, F.y, F.z)
    setElementDimension(p, slot)
    setPedRotation(p, F.rot)
    return true
end

----------------------------------------------------------------
-- Eventos remotos (el cliente solo pide; todo se revalida)
----------------------------------------------------------------
addEventHandler("rp:range:open", resourceRoot, function()
    local p = client
    local ps = rangePlayers[p]
    if not ps or ps.inside or not takeCooldown(ps) then return end
    local loc = nearDesk(p)
    if not loc then return end
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end
    ps.loc = loc
    sendMenu(p, ps)
end)

addEventHandler("rp:range:reopen", resourceRoot, function()
    local p = client
    local ps = rangePlayers[p]
    if not ps or not ps.inside or ps.session or not takeCooldown(ps) then return end
    sendMenu(p, ps)
end)

addEventHandler("rp:range:train", resourceRoot, function(itemId)
    local p = client
    local ps = rangePlayers[p]
    if not ps or type(itemId) ~= "string" or ps.session or not takeCooldown(ps) then return end
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end

    local enteredNow = false
    if not ps.inside then
        local loc = nearDesk(p)
        if not loc then return end
        local ok, err = enterRange(p, ps, loc)
        if not ok then return notify(p, err, "error") end
        enteredNow = true
    end
    local ok, err = startSession(p, itemId)
    if not ok then
        notify(p, err, "warning")
        if enteredNow then exitRange(p) else sendMenu(p, ps) end
    end
end)

addEventHandler("rp:range:abort", resourceRoot, function()
    local ps = rangePlayers[client]
    if ps and ps.session then finishSession(client, "abort") end
end)

addEventHandler("rp:range:exit", resourceRoot, function()
    exitRange(client)
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
local function load(p, characterId) rangePlayers[p] = { characterId = characterId } end

local function unload(p)
    exitRange(p)
    rangePlayers[p] = nil
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) load(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() unload(source) end)
addEventHandler("onPlayerQuit", root, function() unload(source) end)
addEventHandler("rp:onPlayerDowned", root, function() exitRange(source) end)

function isPlayerInRange(p)
    return rangePlayers[p] ~= nil and rangePlayers[p].inside == true
end

addEventHandler("onResourceStart", resourceRoot, function()
    local m = RANGE.MARKER
    for _, loc in ipairs(RANGE.LOCATIONS) do
        local D = RANGE.DESK
        local marker = createMarker(D.x, D.y, D.z - 1, "cylinder", m.size * 1.2, m.r, m.g, m.b, m.a)
        setElementInterior(marker, RANGE.STORE_INTERIOR)
        setElementDimension(marker, storeDim(loc))
    end
    for _, p in ipairs(getElementsByType("player")) do
        local id = exports.rp_characters:getPlayerCharacterId(p)
        if id then load(p, id) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(rangePlayers) do unload(p) end
end)
