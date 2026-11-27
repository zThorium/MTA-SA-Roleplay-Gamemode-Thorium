--[[
    rp_interact / s_interact.lua  (servidor)

    Menú de interacción con otras personas: con la tecla M (modo cursor de rp_vehicles)
    se hace clic derecho sobre alguien y el servidor arma las opciones según quién eres,
    la distancia y el estado del otro. El cliente solo reenvía: cada acción se valida aquí.

    Sin permisos (todos):  saludar; dar la mano, saludo de pandilla y besar (el otro acepta);
                           mostrar DNI y licencia; dar dinero; dar un objeto (el otro acepta);
                           reanimar con un botiquín; invitar a tu vehículo (acepta);
                           cachear (acepta, o sin permiso si está esposado o herido); reportar.
    Por permiso:           policía de servicio (acciones de rp_police), médicos y bomberos de
                           servicio (reanimar sin botiquín), invitar a tu facción, bloque admin.

    Las propuestas que necesitan permiso del otro le llegan como aviso (E acepta, Retroceso
    rechaza) y caducan a los INTERACT.REQUEST_SECONDS. Nada se guarda en la BD.

    Exports (servidor): getActionIds()  (prueba de humo de rp_test)
]]

----------------------------------------------------------------
-- Estado
----------------------------------------------------------------
local cooldown = {}     -- [player] = tick de la última acción
local moneyCd = {}      -- [player] = tick de la última entrega de dinero
local requests = {}     -- [target] = { from, kind, data, expires }
local cpr = {}          -- [player] = { target, timer, kit }
local frisking = {}     -- [player] = { target } cacheo abierto (para quitar cosas)
local takeCd = {}       -- [player] = tick del último robo en el cacheo

addEvent("rp:onCharacterLogout", false)
addEvent("rp:interact:take", true)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:interact:menu", true)
addEvent("rp:interact:do", true)
addEvent("rp:interact:respond", true)

----------------------------------------------------------------
-- Atajos
----------------------------------------------------------------
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function adminLevel(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end
local function idOf(p) return exports.rp_ids:getPlayerId(p) end
local function dname(p) return (getPlayerName(p):gsub("_", " ")) end
local function log(msg, level) outputDebugString("[rp_interact] " .. msg, level or 3) end
local function sfx(p, name) if isElement(p) then triggerClientEvent(p, "rp:interact:sfx", resourceRoot, name) end end

-- Recursos opcionales: si no están en marcha, la llamada devuelve nil
-- estandar:dep-opcional rp_police rp_factions rp_agency rp_driving rp_wanted rp_levels rp_nametags
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running" and r or nil
end
local function try(res, fn, ...)
    local r = running(res)
    if not r then return nil end
    local ok, a, b = pcall(call, r, fn, ...)
    if ok then return a, b end
    log(("%s:%s fallo: %s"):format(res, fn, tostring(a)), 2)
end

local function ame(p, text) try("rp_nametags", "setAme", p, text, 4000) end

local function dist(a, b)
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
end

-- Ejecuta un comando de otro recurso en nombre del jugador (cada comando lo valida por su cuenta).
-- Necesita el derecho function.executeCommandHandler: grupo RPCommandRelay de acl.xml.
local function runCommand(p, cmd, t)
    if not hasObjectPermissionTo(resource, "function.executeCommandHandler", false) then
        log("falta el permiso function.executeCommandHandler (grupo RPCommandRelay de acl.xml; en consola: reloadacl)", 1)
        return notify(p, "Esta opción no está disponible ahora. Avisa a un administrador.", "error")
    end
    return executeCommandHandler(cmd, p, tostring(idOf(t)))
end

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < INTERACT.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

local function isDowned(p) return try("rp_injury", "isPlayerDowned", p) == true end
local function isCuffed(p) return try("rp_police", "isCuffed", p) == true end
local function isSubdued(p) return isDowned(p) or isCuffed(p) or getElementData(p, "rp:tased") == true end

-- Motivo por el que este jugador no puede actuar ("" = sin aviso), o nil si puede
local function blockReason(p)
    if not characterOf(p) or isPedDead(p) then return "" end
    if isDowned(p) then return "No puedes hacerlo estando herido." end
    if isCuffed(p) then return "Estás esposado." end
    if try("rp_wanted", "isPlayerJailed", p) then return "Estás en el calabozo." end
    if cpr[p] then return "Estás reanimando a alguien." end
end

local function validTarget(p, t)
    return isElement(t) and getElementType(t) == "player" and t ~= p and characterOf(t) and not isPedDead(t)
        and getElementDimension(t) == getElementDimension(p) and getElementInterior(t) == getElementInterior(p)
end

-- Gira al ped para que mire hacia (x, y)
local function face(ped, x, y)
    local px, py = getElementPosition(ped)
    setElementRotation(ped, 0, 0, math.deg(math.atan2(y - py, x - px)) - 90, "default", true)
end

local function isMedic(p)
    return try("rp_factions", "isPlayerInFaction", p, "medicos") == true
        or try("rp_factions", "isPlayerOnDuty", p, "bomberos") == true
end

local function freeSeat(vehicle)
    for s = 1, getVehicleMaxPassengers(vehicle) or 0 do
        if not getVehicleOccupant(vehicle, s) then return s end
    end
end

-- Objetos que se pueden dar (el equipo policial no)
local function tradableItems(p)
    local list = {}
    for id, amount in pairs(exports.rp_inventory:getInventory(p) or {}) do
        local def = exports.rp_inventory:getItemDefinition(id)
        if def and not def.police and (tonumber(amount) or 0) > 0 then
            list[#list + 1] = { id = id, name = def.name, icon = def.icon or "📦", amount = amount }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

----------------------------------------------------------------
-- Propuestas (el otro acepta con E o rechaza con Retroceso)
----------------------------------------------------------------
local ACCEPT = {}

local function endRequest(t)
    requests[t] = nil
    if isElement(t) then triggerClientEvent(t, "rp:interact:requestEnd", resourceRoot) end
end

local function propose(p, t, kind, data, text, icon)
    local r = requests[t]
    if r and isElement(r.from) and r.expires > getTickCount() then
        return notify(p, ("%s está respondiendo a otra propuesta. Espera un momento."):format(dname(t)), "warning")
    end
    requests[t] = { from = p, kind = kind, data = data, expires = getTickCount() + INTERACT.REQUEST_SECONDS * 1000 }
    triggerClientEvent(t, "rp:interact:request", resourceRoot,
        { from = dname(p), text = text, icon = icon or "🤝", seconds = INTERACT.REQUEST_SECONDS })
    notify(p, ("Esperando a que %s acepte..."):format(dname(t)), "info")
end

addEventHandler("rp:interact:respond", resourceRoot, function(accept)
    local t = client
    local r = requests[t]
    if not r then return end
    endRequest(t)
    local p = r.from
    if not isElement(p) or r.expires < getTickCount() then return end
    if accept ~= true then
        notify(p, ("%s rechazó tu propuesta."):format(dname(t)), "info")
        return sfx(p, "no")
    end
    local why = blockReason(p) or blockReason(t)
    local range = r.kind == "car" and INTERACT.VEHICLE_INVITE_DISTANCE or INTERACT.DISTANCE + 1
    if why or not validTarget(p, t) or dist(p, t) > range then
        notify(t, "Ya no se puede hacer.", "warning")
        return notify(p, ("No se pudo: %s ya no está a tu lado."):format(dname(t)), "warning")
    end
    ACCEPT[r.kind](p, t, r.data)
end)

-- Caducidad
setTimer(function()
    local now = getTickCount()
    for t, r in pairs(requests) do
        if r.expires <= now or not isElement(r.from) then
            endRequest(t)
            if isElement(r.from) and isElement(t) then notify(r.from, ("%s no respondió."):format(dname(t)), "info") end
        end
    end
end, 1000, 0)

----------------------------------------------------------------
-- Acciones
----------------------------------------------------------------
local ACT = {}
local RANGE = { invite_car = INTERACT.VEHICLE_INVITE_DISTANCE }

ACT.greet = function(p, t)
    if isPedInVehicle(p) then return end
    local x, y = getElementPosition(t)
    face(p, x, y)
    setPedAnimation(p, "ON_LOOKERS", "wave_loop", 2500, true, false, true, false)
    ame(p, ("saluda a %s"):format(dname(t)))
end

-- Gestos de dos (config INTERACT_GESTURES)
local function gestureBlocked(p, t)
    if isPedInVehicle(p) then return "Bájate del vehículo primero." end
    if isPedInVehicle(t) then return "Esa persona está en un vehículo." end
    if isSubdued(t) then return "Esa persona no puede ahora." end
end

for key, g in pairs(INTERACT_GESTURES) do
    ACT[key] = function(p, t)
        local why = gestureBlocked(p, t)
        if why then return notify(p, why, "warning") end
        propose(p, t, "gesture", { g = key }, ("quiere: %s"):format(g.label:lower()), g.icon)
    end
end

ACCEPT.gesture = function(p, t, d)
    local g = INTERACT_GESTURES[d.g]
    if not g or gestureBlocked(p, t) then return end
    -- El invitado se coloca frente a ti a la distancia del gesto
    local px, py, pz = getElementPosition(p)
    local tx, ty, tz = getElementPosition(t)
    local dx, dy = tx - px, ty - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then dx, dy, len = 0, 1, 1 end
    setElementPosition(t, px + dx / len * g.gap, py + dy / len * g.gap, tz, false)
    face(p, px + dx, py + dy)
    face(t, px, py)
    setPedAnimation(p, g.me[1], g.me[2], g.ms, false, false, false, false)
    setPedAnimation(t, g.them[1], g.them[2], g.ms, false, false, false, false)
    ame(p, g.ame:format(dname(t)))
    sfx(p, "ok") sfx(t, "ok")
end

-- Documentos: los muestran rp_agency y rp_driving con sus propias tarjetas
ACT.show_dni = function(p, t)
    if not running("rp_agency") then return notify(p, "Los DNI no están disponibles ahora.", "warning") end
    runCommand(p, "mostrardni", t)
end
ACT.show_license = function(p, t)
    if not running("rp_driving") then return notify(p, "Las licencias no están disponibles ahora.", "warning") end
    runCommand(p, "mostrarlicencia", t)
end

-- Dinero en mano (sin permiso del otro: nadie rechaza un regalo; tope y cooldown)
ACT.give_money = function(p, t, d)
    local amount = math.floor(tonumber(d.amount) or 0)
    if amount < 1 or amount > INTERACT.MONEY_MAX then
        return notify(p, ("Puedes dar de $1 a $%d de una vez."):format(INTERACT.MONEY_MAX), "warning")
    end
    local now = getTickCount()
    if moneyCd[p] and now - moneyCd[p] < INTERACT.MONEY_COOLDOWN_MS then
        return notify(p, "Espera un momento antes de dar más dinero.", "warning")
    end
    if getPlayerMoney(p) < amount then return notify(p, "No llevas tanto efectivo.", "error") end
    moneyCd[p] = now
    takePlayerMoney(p, amount)
    givePlayerMoney(t, amount)
    exports.rp_characters:saveCharacter(p)
    exports.rp_characters:saveCharacter(t)
    if not isPedInVehicle(p) then
        local x, y = getElementPosition(t)
        face(p, x, y)
        setPedAnimation(p, "DEALER", "DEALER_DEAL", 1500, false, false, false, false)
    end
    ame(p, ("le da dinero a %s"):format(dname(t)))
    notify(p, ("Le diste $%d a %s."):format(amount, dname(t)), "success")
    notify(t, ("%s te dio $%d."):format(dname(p), amount), "success")
    sfx(p, "coins") sfx(t, "coins")
    if amount >= INTERACT.MONEY_LOG_FROM then
        outputServerLog(("[rp_interact] %s (pj %s) dio $%d en mano a %s (pj %s)"):format(
            getPlayerName(p), tostring(characterOf(p)), amount, getPlayerName(t), tostring(characterOf(t))))
    end
end

-- Objetos: el otro acepta y se revalida todo al aceptar
local function checkItem(p, t, itemId, amount)
    local def = type(itemId) == "string" and exports.rp_inventory:getItemDefinition(itemId)
    if not def or def.police then return nil, "Ese objeto no se puede dar." end
    if amount < 1 or amount > 999 then return nil, "Cantidad no válida." end
    if not exports.rp_inventory:hasItem(p, itemId, amount) then return nil, "No tienes tantos." end
    local ok, why = exports.rp_inventory:canCarry(t, itemId, amount)
    if not ok then return nil, ("%s no puede cargarlo: %s"):format(dname(t), tostring(why or "sin espacio")) end
    return def
end

ACT.give_item = function(p, t, d)
    local amount = math.floor(tonumber(d.amount) or 0)
    local def, why = checkItem(p, t, d.item, amount)
    if not def then return notify(p, why, "warning") end
    propose(p, t, "item", { item = d.item, amount = amount }, ("te ofrece %d × %s"):format(amount, def.name), def.icon or "🎁")
end

ACCEPT.item = function(p, t, d)
    local def, why = checkItem(p, t, d.item, d.amount)
    if not def then
        notify(t, "La entrega ya no es posible.", "warning")
        return notify(p, why, "warning")
    end
    if not exports.rp_inventory:takeItem(p, d.item, d.amount) then return end
    if not exports.rp_inventory:giveItem(t, d.item, d.amount) then
        exports.rp_inventory:giveItem(p, d.item, d.amount)   -- reembolso
        return notify(p, "No se pudo entregar.", "error")
    end
    if not isPedInVehicle(p) then setPedAnimation(p, "DEALER", "DEALER_DEAL", 1500, false, false, false, false) end
    ame(p, ("le entrega %s a %s"):format(def.name:lower(), dname(t)))
    notify(p, ("Entregaste %d × %s a %s."):format(d.amount, def.name, dname(t)), "success")
    notify(t, ("%s te entregó %d × %s."):format(dname(p), d.amount, def.name), "success")
    sfx(p, "ok") sfx(t, "ok")
end

-- Reanimar (RCP): civiles con botiquín, médicos y bomberos de servicio sin él
local function stopCPR(p, silent)
    local c = cpr[p]
    if not c then return end
    cpr[p] = nil
    if isTimer(c.timer) then killTimer(c.timer) end
    if isElement(p) then
        setElementFrozen(p, false)
        setPedAnimation(p)
        if not silent then notify(p, "Dejaste de reanimar.", "info") end
    end
end

local function finishCPR(p)
    local c = cpr[p]
    if not c then return end
    stopCPR(p, true)
    local t = c.target
    if not isElement(p) or not validTarget(p, t) or dist(p, t) > INTERACT.DISTANCE or not isDowned(t) or isDowned(p) then
        if isElement(p) then notify(p, "No pudiste terminar la reanimación.", "warning") end
        return
    end
    if c.kit and not exports.rp_inventory:takeItem(p, INTERACT.MEDKIT_ITEM, 1) then
        return notify(p, "Te quedaste sin botiquín.", "error")
    end
    if not try("rp_injury", "revivePlayer", t) then return notify(p, "No se pudo reanimar.", "error") end
    notify(p, ("Reanimaste a %s."):format(dname(t)), "success")
    notify(t, ("%s te reanimó."):format(dname(p)), "success")
    sfx(p, "ok") sfx(t, "ok")
    try("rp_levels", "giveXP", p, 10, "Ayudar a un herido")
end

local function startCPR(p, t, seconds, kit)
    if isPedInVehicle(p) then return notify(p, "Bájate del vehículo primero.", "warning") end
    if not isDowned(t) then return notify(p, "Esa persona no está herida.", "info") end
    local x, y = getElementPosition(t)
    face(p, x, y)
    setElementFrozen(p, true)
    setPedAnimation(p, "MEDIC", "CPR", -1, true, false, false, false)
    cpr[p] = { target = t, kit = kit, timer = setTimer(finishCPR, seconds * 1000, 1, p) }
    ame(p, ("le hace RCP a %s"):format(dname(t)))
    notify(p, ("Reanimando a %s... (%d s, no te alejes)"):format(dname(t), seconds), "info")
    notify(t, ("%s te está reanimando."):format(dname(p)), "info")
end

ACT.help_up = function(p, t)
    if not exports.rp_inventory:hasItem(p, INTERACT.MEDKIT_ITEM, 1) then
        return notify(p, "Necesitas un botiquín. O llama al 911 desde el teléfono (P).", "warning")
    end
    startCPR(p, t, INTERACT.CPR_SECONDS, true)
end

ACT.med_revive = function(p, t)
    if not isMedic(p) then return end
    startCPR(p, t, INTERACT.MED_CPR_SECONDS, false)
end

-- Invitar a tu vehículo (eres el conductor y hay asiento libre)
local function carFor(p, t)
    local v = getPedOccupiedVehicle(p)
    if not v or getVehicleController(v) ~= p then return nil, "Tienes que ir conduciendo." end
    if isPedInVehicle(t) then return nil, "Esa persona ya va en un vehículo." end
    if isSubdued(t) then return nil, "Esa persona no puede subir sola." end
    if not freeSeat(v) then return nil, "No quedan asientos libres." end
    return v
end

ACT.invite_car = function(p, t)
    local v, why = carFor(p, t)
    if not v then return notify(p, why, "warning") end
    propose(p, t, "car", { v = v }, ("te invita a subir a su %s"):format(getVehicleName(v) or "vehículo"), "🚗")
end

ACCEPT.car = function(p, t, d)
    local v, why = carFor(p, t)
    if not v or v ~= d.v then return notify(t, why or "Ya no se puede subir.", "warning") end
    warpPedIntoVehicle(t, v, freeSeat(v))
    notify(p, ("%s subió a tu vehículo."):format(dname(t)), "success")
    sfx(p, "ok")
end

-- Cachear: con permiso del otro, o directo si está esposado, herido o aturdido.
-- Quitarle cosas solo si está reducido (eso es un robo: rp_wanted "person_rob").
local function showFrisk(p, t, refresh)
    local canTake = isSubdued(t)
    local items = {}
    for id, amount in pairs(exports.rp_inventory:getInventory(t) or {}) do
        local def = exports.rp_inventory:getItemDefinition(id)
        if def and (tonumber(amount) or 0) > 0 then
            items[#items + 1] = { id = id, name = def.name, icon = def.icon or "📦", amount = amount,
                                  takeable = canTake and not def.police or nil }
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    local cash = getPlayerMoney(t)
    frisking[p] = { target = t }
    triggerClientEvent(p, "rp:interact:frisk", resourceRoot, {
        name = dname(t), cash = cash, items = items, canTake = canTake,
        cashTake = canTake and math.min(cash, INTERACT.ROB_CASH_MAX) or 0,
    })
    if not refresh then
        ame(p, ("cachea a %s"):format(dname(t)))
        notify(t, ("%s te está cacheando."):format(dname(p)), "info")
    end
end

local function reportRob(p, t)
    try("rp_wanted", "reportCrime", p, "person_rob", characterOf(t))
end

addEventHandler("rp:interact:take", resourceRoot, function(what)
    local p = client
    local f = frisking[p]
    if not f or type(what) ~= "string" or #what > 64 then return end
    local now = getTickCount()
    if takeCd[p] and now - takeCd[p] < INTERACT.TAKE_COOLDOWN_MS then return end
    takeCd[p] = now
    local t = f.target
    local why = blockReason(p)
    if why then if why ~= "" then notify(p, why, "warning") end return end
    if not validTarget(p, t) or dist(p, t) > INTERACT.DISTANCE + 0.5 then
        frisking[p] = nil
        return notify(p, "Esa persona ya no está a tu lado.", "warning")
    end
    if not isSubdued(t) then
        showFrisk(p, t, true)
        return notify(p, "Solo puedes quitarle cosas si está esposado, herido o aturdido.", "warning")
    end

    if what == "$cash" then
        local amount = math.min(getPlayerMoney(t), INTERACT.ROB_CASH_MAX)
        if amount < 1 then return showFrisk(p, t, true) end
        takePlayerMoney(t, amount)
        givePlayerMoney(p, amount)
        exports.rp_characters:saveCharacter(p)
        exports.rp_characters:saveCharacter(t)
        ame(p, ("le quita dinero a %s"):format(dname(t)))
        notify(p, ("Le quitaste $%d a %s."):format(amount, dname(t)), "success")
        notify(t, ("%s te quitó $%d."):format(dname(p), amount), "error")
        outputServerLog(("[rp_interact] ROBO %s (pj %s) quito $%d a %s (pj %s)"):format(
            getPlayerName(p), tostring(characterOf(p)), amount, getPlayerName(t), tostring(characterOf(t))))
        sfx(p, "coins")
    else
        local def = exports.rp_inventory:getItemDefinition(what)
        if not def or def.police then return notify(p, "Eso no se puede quitar.", "warning") end
        local amount = tonumber(exports.rp_inventory:getItemAmount(t, what)) or 0
        if amount < 1 then return showFrisk(p, t, true) end
        local ok, reason = exports.rp_inventory:canCarry(p, what, amount)
        if not ok then return notify(p, "No te cabe: " .. tostring(reason or "sin espacio"), "warning") end
        if not exports.rp_inventory:takeItem(t, what, amount) then return showFrisk(p, t, true) end
        if not exports.rp_inventory:giveItem(p, what, amount) then
            exports.rp_inventory:giveItem(t, what, amount)   -- reembolso
            return notify(p, "No se pudo quitar.", "error")
        end
        ame(p, ("le quita %s a %s"):format(def.name:lower(), dname(t)))
        notify(p, ("Le quitaste %d × %s a %s."):format(amount, def.name, dname(t)), "success")
        notify(t, ("%s te quitó %d × %s."):format(dname(p), amount, def.name), "error")
        outputServerLog(("[rp_interact] ROBO %s (pj %s) quito %dx %s a %s (pj %s)"):format(
            getPlayerName(p), tostring(characterOf(p)), amount, what, getPlayerName(t), tostring(characterOf(t))))
        sfx(p, "ok")
    end
    reportRob(p, t)
    showFrisk(p, t, true)
end)

ACT.frisk = function(p, t)
    if isSubdued(t) then return showFrisk(p, t) end
    propose(p, t, "frisk", {}, "quiere cachearte", "🔎")
end
ACCEPT.frisk = function(p, t) showFrisk(p, t) end

-- Facción
ACT.fac_invite = function(p, t)
    if try("rp_factions", "hasFactionPermission", p, "invite") ~= true then return notify(p, "Tu rol no puede invitar.", "error") end
    runCommand(p, "finvitar", t)
end

----------------------------------------------------------------
-- Menú (el servidor decide qué se ve y por qué algo está bloqueado)
----------------------------------------------------------------
local function buildMenu(p, t)
    local d = dist(p, t)
    local near = d <= INTERACT.DISTANCE + 0.5
    local admin = adminLevel(p) >= 1
    if not near and not (admin and d <= INTERACT.ADMIN_DISTANCE) then return nil, "Acércate más a esa persona." end

    local groups = {}
    local function group(title, tone)
        local g = { title = title, tone = tone, items = {} }
        groups[#groups + 1] = g
        return g
    end
    local function add(g, id, label, icon, desc, extra)
        local item = { id = id, label = label, icon = icon, desc = desc }
        for k, v in pairs(extra or {}) do item[k] = v end
        g.items[#g.items + 1] = item
    end

    local inCar = isPedInVehicle(p)
    local tDowned, subdued = isDowned(t), isSubdued(t)
    local cash = getPlayerMoney(p)
    local items = {}

    if near then
        -- Social
        local g = group("Social", "friend")
        local gestureWhy = (inCar and "Bájate del vehículo") or (subdued and "Ahora no puede") or nil
        add(g, "greet", "Saludar", "👋", "Un gesto con la mano", { locked = inCar and "Bájate del vehículo" or nil })
        for _, key in ipairs({ "handshake", "gang", "kiss" }) do
            local ge = INTERACT_GESTURES[key]
            add(g, key, ge.label, ge.icon, "Tiene que aceptar", { locked = gestureWhy, ask = true })
        end

        -- Documentos
        g = group("Documentos", "info")
        local dniWhy
        if not running("rp_agency") then dniWhy = "No disponible"
        elseif not try("rp_agency", "hasPlayerDNI", p) then dniWhy = "No tienes DNI: sácalo en la agencia"
        elseif not exports.rp_inventory:hasItem(p, "id_card", 1) then dniWhy = "No llevas el DNI encima" end
        add(g, "show_dni", "Mostrar DNI", "🪪", "Le enseñas tu documento", { locked = dniWhy })
        local lic = try("rp_driving", "getDriverLicense", p)
        add(g, "show_license", "Mostrar licencia", "🚘", "Tu licencia de conducir",
            { locked = (not lic) and "No tienes licencia de conducir" or nil })

        -- Dar
        g = group("Dar", "money")
        items = tradableItems(p)
        add(g, "give_money", "Dar dinero", "💵", ("Llevas $%d en efectivo"):format(cash),
            { locked = cash < 1 and "No llevas efectivo" or nil, form = "money" })
        add(g, "give_item", "Dar un objeto", "🎁", "Tiene que aceptar",
            { locked = #items == 0 and "No llevas nada que dar" or nil, form = "item", ask = true })

        -- Ayuda
        g = group("Ayuda", "help")
        if tDowned then
            local medics = #(try("rp_factions", "getFactionPlayers", "medicos") or {})
            local hasKit = exports.rp_inventory:hasItem(p, INTERACT.MEDKIT_ITEM, 1)
            add(g, "help_up", "Reanimar con botiquín", "🩹",
                medics > 0 and "Hay médicos conectados: también sirve el 911" or ("Gasta 1 botiquín · %d s"):format(INTERACT.CPR_SECONDS),
                { locked = (not hasKit) and "Necesitas un botiquín" or nil })
        end
        if inCar then
            local _, why = carFor(p, t)
            add(g, "invite_car", "Invitar a tu vehículo", "🚗", "Tiene que aceptar", { locked = why, ask = true })
        end
        add(g, "frisk", "Cachear", "🔎", subdued and "Está reducido: no hace falta permiso" or "Tiene que aceptar",
            { ask = not subdued or nil })
    end

    -- Policía de servicio (acciones de rp_police)
    local pol = near and try("rp_police", "getPlayerActions", p, t)
    if type(pol) == "table" and #pol > 0 then
        local g = group("Policía", "police")
        for _, o in ipairs(pol) do
            add(g, "pol:" .. tostring(o.id), tostring(o.label), o.icon or "🚓", nil,
                { locked = o.disabled and (o.hint or "No disponible") or nil })
        end
    end

    -- Servicios y facción
    if near then
        local g
        if tDowned and isMedic(p) then
            g = group("Servicio", "help")
            add(g, "med_revive", "Reanimar (servicio)", "🚑", ("Sin botiquín · %d s"):format(INTERACT.MED_CPR_SECONDS))
        end
        if try("rp_factions", "hasFactionPermission", p, "invite") == true
            and try("rp_factions", "isPlayerInFaction", t) ~= true then
            local info = try("rp_factions", "getPlayerFactionInfo", p)
            g = group("Facción", "faction")
            add(g, "fac_invite", "Invitar a " .. (info and info.tag or "tu facción"), "🏳️", "Le llega la invitación")
        end
    end

    -- Otros
    local g = group("Otros", "muted")
    add(g, "report", "Reportar", "🚩", "Abre el reporte F1 con esta persona", { client = true })

    if admin then
        g = group("Administración", "admin")
        for _, a in ipairs(INTERACT_ADMIN) do add(g, a.id, a.label, a.icon) end
    end

    -- Ficha de la persona: lo que se ve a simple vista
    local states = {}
    if tDowned then states[#states + 1] = "Herido" end
    if isCuffed(t) then states[#states + 1] = "Esposado" end
    local info = { name = dname(t), id = idOf(t), level = try("rp_levels", "getPlayerLevel", t), states = states }
    if try("rp_factions", "isPlayerOnDuty", t) == true then
        local f = try("rp_factions", "getPlayerFactionInfo", t)
        if f then info.faction = { name = f.name, rank = f.rank, color = f.color } end
    end
    if admin then info.admin = { character = characterOf(t), account = exports.rp_login:getPlayerAccountName(t) } end

    return { target = info, groups = groups, cash = cash, moneyMax = INTERACT.MONEY_MAX, items = items, far = not near }
end

addEventHandler("rp:interact:menu", resourceRoot, function(t)
    local p = client
    if not takeCooldown(p) then return end
    local why = blockReason(p)
    if why then if why ~= "" then notify(p, why, "warning") end return end
    if not validTarget(p, t) then return end
    local data, err = buildMenu(p, t)
    if not data then return notify(p, err, "warning") end
    triggerClientEvent(p, "rp:interact:showMenu", resourceRoot, t, data)
end)

local ADMIN_CMD = {}
for _, a in ipairs(INTERACT_ADMIN) do ADMIN_CMD[a.id] = a.cmd end

addEventHandler("rp:interact:do", resourceRoot, function(t, id, data)
    local p = client
    if type(id) ~= "string" or #id > 40 or not takeCooldown(p) then return end
    if not validTarget(p, t) then return notify(p, "Esa persona ya no está aquí.", "warning") end

    -- Admin: el comando de rp_admin valida nivel, IAM y deja la auditoría
    if ADMIN_CMD[id] then
        if adminLevel(p) < 1 or dist(p, t) > INTERACT.ADMIN_DISTANCE then return end
        return runCommand(p, ADMIN_CMD[id], t)
    end

    local why = blockReason(p)
    if why then if why ~= "" then notify(p, why, "warning") end return end
    if dist(p, t) > (RANGE[id] or INTERACT.DISTANCE) + 0.5 then return notify(p, "Acércate más a esa persona.", "warning") end

    if id:sub(1, 4) == "pol:" then
        try("rp_police", "doPlayerAction", p, t, id:sub(5))
        return
    end
    local fn = ACT[id]
    if fn then fn(p, t, type(data) == "table" and data or {}) end
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
local function cleanup(p)
    stopCPR(p, true)
    for t, r in pairs(requests) do
        if t == p or r.from == p then endRequest(t) end
    end
    -- Si alguien le estaba reanimando, se corta
    for helper, c in pairs(cpr) do if c.target == p then stopCPR(helper) end end
    for who, f in pairs(frisking) do if who == p or f.target == p then frisking[who] = nil end end
    cooldown[p], moneyCd[p], takeCd[p] = nil, nil, nil
end
addEventHandler("onPlayerQuit", root, function() cleanup(source) end)
addEventHandler("rp:onCharacterLogout", root, function() cleanup(source) end)
addEventHandler("onPlayerWasted", root, function() stopCPR(source, true) end)
addEventHandler("rp:onPlayerDowned", root, function()
    stopCPR(source, true)
    if requests[source] then endRequest(source) end
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(cpr) do stopCPR(p, true) end
end)

----------------------------------------------------------------
-- Export para rp_test: cada acción del menú tiene quien la ejecute
----------------------------------------------------------------
function getActionIds()
    local list = {}
    for id in pairs(ACT) do list[#list + 1] = id end
    for id in pairs(ADMIN_CMD) do list[#list + 1] = id end
    local kinds = {}
    for k in pairs(ACCEPT) do kinds[#kinds + 1] = k end
    table.sort(list)
    table.sort(kinds)
    return { actions = list, accepts = kinds, gestures = INTERACT_GESTURES }
end
