--[[
    rp_resmanager / s_resmanager.lua
    Panel para iniciar / reiniciar / detener / refrescar recursos desde el juego.
    Solo super admin (accounts.admin_level >= SUPER_ADMIN_LEVEL). Cada accion se
    revalida en el servidor; el cliente nunca decide permisos.

    Requiere el grupo ACL "RPResourceManager" de acl.xml (resource.rp_resmanager
    con permisos para start/stop/restart/refresh de recursos).
]]

SUPER_ADMIN_LEVEL = 3

-- Recursos que este panel no puede detener ni reiniciar (romperia el panel o el login)
local LOCKED = { rp_resmanager = true, rp_database = true, rp_login = true }

addEvent("rp:resmgr:tryOpen", true)
addEvent("rp:resmgr:request", true)
addEvent("rp:resmgr:action", true)
addEvent("rp:resmgr:open", true)
addEvent("rp:resmgr:list", true)
addEvent("rp:resmgr:toggle", true)

local STATE_ORDER = { running = 1, starting = 2, failed_to_load = 3, loaded = 4, stopping = 5 }

local function isSuper(player)
    return isElement(player) and (exports.rp_login:getPlayerAdminLevel(player) or 0) >= SUPER_ADMIN_LEVEL
end

local function buildList()
    local list = {}
    for _, res in ipairs(getResources()) do
        local name = getResourceName(res)
        list[#list + 1] = {
            name = name,
            state = getResourceState(res),
            author = getResourceInfo(res, "author") or "",
            locked = LOCKED[name] == true,
            err = getResourceLoadFailureReason(res) or "",
        }
    end
    table.sort(list, function(a, b)
        local ra, rb = STATE_ORDER[a.state] or 9, STATE_ORDER[b.state] or 9
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

local function sendList(player)
    triggerClientEvent(player, "rp:resmgr:list", resourceRoot, buildList())
end

local function logAction(player, text)
    outputServerLog(("[rp_resmanager] %s: %s"):format(getPlayerName(player), text))
end

local function deny(player)
    exports.rp_notify:notify(player, "Solo los super admin pueden usar el panel de recursos.", "error")
end

addEventHandler("rp:resmgr:tryOpen", resourceRoot, function()
    if not isSuper(client) then return deny(client) end
    triggerClientEvent(client, "rp:resmgr:toggle", resourceRoot)
end)

addCommandHandler("recursos", function(player)
    if not isSuper(player) then return deny(player) end
    triggerClientEvent(player, "rp:resmgr:toggle", resourceRoot)
end)

addEventHandler("rp:resmgr:request", resourceRoot, function()
    if not isSuper(client) then return end
    sendList(client)
end)

addEventHandler("rp:resmgr:open", resourceRoot, function(isOpen)
    if not isSuper(client) then return end
    setElementData(client, "rp:resmgr:open", isOpen and true or nil, false)
end)

addEventHandler("rp:resmgr:action", resourceRoot, function(action, name)
    local player = client
    if not isSuper(player) then return end
    if type(action) ~= "string" or type(name) ~= "string" then return end

    if action == "refresh" then
        refreshResources(false)
        logAction(player, "refresh")
        exports.rp_notify:notify(player, "Lista de recursos actualizada desde el disco.", "success")
        return sendList(player)
    end

    local res = getResourceFromName(name)
    if not res then
        exports.rp_notify:notify(player, "El recurso '" .. name .. "' no existe.", "error")
        return sendList(player)
    end

    local state = getResourceState(res)
    if (action == "stop" or action == "restart") and LOCKED[name] then
        exports.rp_notify:notify(player, "'" .. name .. "' esta protegido; hazlo desde la consola del servidor.", "warning")
        return sendList(player)
    end

    local ok
    if action == "start" then
        if state == "running" then
            exports.rp_notify:notify(player, name .. " ya esta iniciado.", "info")
            return sendList(player)
        end
        ok = startResource(res, false)
    elseif action == "stop" then
        if state ~= "running" then
            exports.rp_notify:notify(player, name .. " no esta iniciado.", "info")
            return sendList(player)
        end
        ok = stopResource(res)
    elseif action == "restart" then
        if state == "running" then ok = restartResource(res) else ok = startResource(res, false) end
    else
        return
    end

    logAction(player, action .. " " .. name .. " -> " .. tostring(ok))
    if ok then
        local verb = action == "start" and "iniciado" or action == "stop" and "detenido" or "reiniciado"
        exports.rp_notify:notify(player, name .. ": " .. verb .. ".", "success")
    else
        exports.rp_notify:notify(player, ("No se pudo hacer '%s' en %s (revisa la consola y el ACL)."):format(action, name), "error")
    end
    sendList(player)
end)

-- Mantener fresca la lista de quien tiene el panel abierto (el estado cambia de forma asincrona)
local function refreshViewers()
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "rp:resmgr:open") and isSuper(p) then sendList(p) end
    end
end
addEventHandler("onResourceStart", root, function() setTimer(refreshViewers, 500, 1) end)
addEventHandler("onResourceStop", root, function() setTimer(refreshViewers, 500, 1) end)
