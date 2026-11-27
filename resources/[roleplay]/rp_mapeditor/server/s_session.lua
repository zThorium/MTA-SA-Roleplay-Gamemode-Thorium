--[[
    rp_mapeditor / s_session.lua
    Entrar y salir del editor. Al entrar, el personaje queda congelado e invisible en la dimensión
    de borrador del proyecto (27000 + id) y su posición real se guarda en "rp:savePos" para que
    rp_characters no guarde la de la cámara. Al salir se devuelve todo.
]]

addEvent("rp:me:test", true)

local function running(res)
    return res and getResourceState(res) == "running"
end

local function blockedReason(p)
    if getElementData(p, "rp:downed") then return "No puedes editar estando abatido." end
    -- rp_police y rp_missions arrancan después: dependencias opcionales
    if running(getResourceFromName("rp_police")) then
        local okC, cuffed = pcall(function() return exports.rp_police:isCuffed(p) end)
        if okC and cuffed then return "No puedes editar esposado." end
    end
    if running(getResourceFromName("rp_missions")) then
        local okM, mission = pcall(function() return exports.rp_missions:getPlayerMission(p) end)
        if okM and mission then return "Sal de la misión antes de editar." end
    end
    if not exports.rp_characters:getPlayerCharacterId(p) then return "Entra con un personaje primero." end
    return nil
end

function meEnter(p, P)
    local why = blockedReason(p)
    if why then return meNotify(p, why, "error") end
    local S = ME.sessions[p]
    if S and S.pid == P.id then return end
    if S then meLeave(p, true) end

    if isPedInVehicle(p) then removePedFromVehicle(p) end
    local x, y, z = getElementPosition(p)
    local _, _, rot = getElementRotation(p)
    local saved = { x, y, z, rot, getElementInterior(p), getElementDimension(p) }
    ME.sessions[p] = { pid = P.id, saved = saved, testing = false }
    setElementData(p, "rp:savePos", saved, false)
    setElementData(p, "rp:me:editing", true)

    P.editors[p] = true
    meDraftSpawn(P)
    setElementInterior(p, P.interior)
    setElementDimension(p, meDraftDim(P))
    setElementFrozen(p, true)
    setElementAlpha(p, 0)

    local rows = {}
    for _, row in pairs(P.rows) do rows[#rows + 1] = row end
    triggerClientEvent(p, "rp:me:enter", resourceRoot, meSummary(P), P.settings or {}, rows, meLocksFor(P))
    meBroadcast(P, "rp:me:editors", meSummary(P).editors)
    meLog(p, P, "enter", "")
end

function meLeave(p, switching)
    local S = ME.sessions[p]
    if not S then return end
    ME.sessions[p] = nil
    local P = ME.projects[S.pid]
    if P then
        P.editors[p] = nil
        local released = false
        for id, owner in pairs(P.locks) do
            if owner == p then P.locks[id] = nil released = true end
        end
        if not next(P.editors) then meDraftDestroy(P)
        else
            if released then meBroadcast(P, "rp:me:locks", meLocksFor(P)) end
            meBroadcast(P, "rp:me:editors", meSummary(P).editors)
        end
    end
    if isElement(p) then
        removeElementData(p, "rp:savePos")
        removeElementData(p, "rp:me:editing")
        if not switching then
            local s = S.saved
            if isPedInVehicle(p) then removePedFromVehicle(p) end
            setElementInterior(p, s[5])
            setElementDimension(p, s[6])
            setElementPosition(p, s[1], s[2], s[3])
            setElementRotation(p, 0, 0, s[4] or 0)
            setElementFrozen(p, false)
            setElementAlpha(p, 255)
            triggerClientEvent(p, "rp:me:leave", resourceRoot)
        end
    end
end

-- Bloqueos: [id] = nombre de quien lo tiene seleccionado
function meLocksFor(P)
    local out = {}
    for id, owner in pairs(P.locks) do
        if isElement(owner) then out[tostring(id)] = meName(owner) else P.locks[id] = nil end
    end
    return out
end

-- Modo prueba: el personaje se ve y se mueve dentro del borrador
addEventHandler("rp:me:test", resourceRoot, function(on)
    local S = ME.sessions[client]
    if not S then return end
    S.testing = on == true
    setElementFrozen(client, not S.testing)
    setElementAlpha(client, S.testing and 255 or 0)
end)

-- Limpieza
addEventHandler("onPlayerQuit", root, function()
    -- rp_characters ya guardó la posición real (rp:savePos) en su propio onPlayerQuit
    if ME.sessions[source] then meLeave(source, true) end
end)

addEventHandler("rp:onCharacterLogout", root, function()
    if ME.sessions[source] then meLeave(source) end
end)

addEventHandler("onPlayerWasted", root, function()
    if ME.sessions[source] then meLeave(source) end
end)

-- Un super admin quitó el rol builder desde el IAM: fuera del editor al momento
addEvent("rp:adminpanel:permsChanged", false)
addEventHandler("rp:adminpanel:permsChanged", root, function(accountId)
    setTimer(function()
        for p in pairs(ME.sessions) do
            if isElement(p) and exports.rp_login:getPlayerAccountId(p) == accountId and not meCanBuild(p) then
                meLeave(p)
                meNotify(p, "Ya no tienes el rol builder: saliste del editor de mapas.", "warning")
            end
        end
    end, 50, 1)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(ME.sessions) do
        if isElement(p) then
            local s = ME.sessions[p].saved
            removeElementData(p, "rp:savePos")
            removeElementData(p, "rp:me:editing")
            setElementInterior(p, s[5])
            setElementDimension(p, s[6])
            setElementPosition(p, s[1], s[2], s[3])
            setElementFrozen(p, false)
            setElementAlpha(p, 255)
        end
    end
end)
