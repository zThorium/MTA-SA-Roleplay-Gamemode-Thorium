--[[
    rp_police / s_actions.lua
    Interaccion con sospechosos y vehiculos (tecla K + click derecho):
      esposar (suave: camina lento / fuerte: inmovil), escoltar (attachElements),
      cachear y decomisar, meter / sacar de la patrulla, multar, arrestar
      (calabozo con rp_wanted:jailPlayer), identificar, taser.
    El servidor decide las opciones y vuelve a validar cada accion.
]]

addEvent("rp:pol:menu", true)
addEvent("rp:pol:do", true)
addEvent("rp:pol:tased", true)
addEvent("rp:onCharacterLogout", false)

local cuffed = {}        -- [player] = { mode = 1|2, by = officer }
local escorting = {}     -- [officer] = target
local escortedBy = {}    -- [target] = officer
local tasedUntil = {}    -- [player] = tick
local lastTaser = {}     -- [officer] = tick
local ctx = {}           -- [officer] = { target, kind } (formularios y cacheo)
local throttle = {}

local CUFF_CONTROLS = { "fire", "aim_weapon", "sprint", "jump", "next_weapon", "previous_weapon", "action",
    "vehicle_fire", "vehicle_secondary_fire", "enter_exit", "crouch" }
local HARD_CONTROLS = { "forwards", "backwards", "left", "right", "accelerate", "brake_reverse" }
local restricted = {}

function isCuffed(p) return cuffed[p] ~= nil end

local function applyControls(p)
    if not isElement(p) then return end
    local tased = tasedUntil[p] and tasedUntil[p] > getTickCount()
    local c = cuffed[p]
    if tased then
        toggleAllControls(p, false, true, false)
        restricted[p] = true
    elseif c then
        toggleAllControls(p, true, true, false)
        for _, k in ipairs(CUFF_CONTROLS) do toggleControl(p, k, false) end
        if c.mode == 2 then for _, k in ipairs(HARD_CONTROLS) do toggleControl(p, k, false) end end
        restricted[p] = true
    elseif restricted[p] then
        toggleAllControls(p, true, true, false)
        restricted[p] = nil
    end
end

local function cuffAnim(p)
    local c = cuffed[p]
    if not isElement(p) then return end
    if c and c.mode == 2 and not isPedInVehicle(p) then
        setPedAnimation(p, "ped", "ARRESTgun", -1, false, false, false, true)
    elseif not c then
        setPedAnimation(p)
    end
end

local function stopEscort(officer, target)
    target = target or escorting[officer]
    if target then
        escortedBy[target] = nil
        if isElement(target) then
            detachElements(target)
            setElementCollisionsEnabled(target, true)
        end
    end
    escorting[officer] = nil
end

local function releaseCuffs(target, silent)
    if not cuffed[target] then return end
    local by = escortedBy[target]
    if by then stopEscort(by, target) end
    cuffed[target] = nil
    if isElement(target) then
        setElementData(target, "rp:cuffed", false)
        applyControls(target)
        cuffAnim(target)
        if not silent then notify(target, "Te quitan las esposas.", "info") end
    end
end

function releaseDetainee(target) releaseCuffs(target, true) end

-- Al cruzar la puerta de la comisaria el detenido escoltado cruza con su oficial
function moveEscorted(officer, x, y, z, interior)
    local t = escorting[officer]
    if not t or not isElement(t) then return end
    detachElements(t)
    setElementInterior(t, interior)
    setElementDimension(t, 0)
    setElementPosition(t, x, y, z)
    attachElements(t, officer, 0, 0.85, 0)
end

local function cleanup(p)
    if escorting[p] then stopEscort(p) end
    if escortedBy[p] then stopEscort(escortedBy[p], p) end
    cuffed[p], tasedUntil[p], ctx[p], throttle[p], lastTaser[p] = nil, nil, nil, nil, nil
    restricted[p] = nil
end
addEventHandler("onPlayerQuit", root, function() cleanup(source) end)
addEventHandler("rp:onCharacterLogout", root, function()
    local p = source
    local was = cuffed[p]
    cleanup(p)
    if was then setElementData(p, "rp:cuffed", false) end
end)
addEventHandler("onPlayerWasted", root, function()
    if cuffed[source] then releaseCuffs(source, true) end
    if escorting[source] then stopEscort(source) end
end)
addEventHandler("onPlayerSpawn", root, function() if cuffed[source] then applyControls(source) end end)

addEventHandler("rp:pol:onDuty", root, function(on)
    if not on then
        if escorting[source] then stopEscort(source) end
        ctx[source] = nil
    end
end)

-- Un esposado no puede bajarse solo del vehiculo
addEventHandler("onVehicleStartExit", root, function(player)
    if cuffed[player] then cancelEvent() end
end)
addEventHandler("onPlayerVehicleEnter", root, function()
    if escorting[source] then stopEscort(source) end
end)

-- Cada segundo: escoltas rotas, fin del aturdimiento
setTimer(function()
    for officer, target in pairs(escorting) do
        if not isElement(officer) or not isElement(target) or isPedDead(officer) or isPedDead(target)
            or isPedInVehicle(officer) or distPlayers(officer, target) > 6 then
            stopEscort(officer, target)
        end
    end
    local now = getTickCount()
    for p, t in pairs(tasedUntil) do
        if t <= now then
            tasedUntil[p] = nil
            if isElement(p) then
                setElementData(p, "rp:tased", false)
                applyControls(p)
                cuffAnim(p)
                if not cuffed[p] then setPedAnimation(p) end
            end
        end
    end
end, 1000, 0)

----------------------------------------------------------------
-- Validaciones
----------------------------------------------------------------
local function validPlayerTarget(officer, target, maxDist)
    return isElement(target) and getElementType(target) == "player" and target ~= officer and charOf(target)
        and not isPedDead(target) and distPlayers(officer, target) <= (maxDist or POLICE.INTERACT_DISTANCE)
end

local function busy(p)
    local now = getTickCount()
    if throttle[p] and now - throttle[p] < 400 then return true end
    throttle[p] = now
    return false
end

local function vehicleOccupants(v)
    local list = {}
    for _, p in pairs(getVehicleOccupants(v) or {}) do list[#list + 1] = p end
    return list
end

----------------------------------------------------------------
-- Acciones sobre personas
----------------------------------------------------------------
local ACT = {}

local function doCuff(officer, target, mode)
    if not can(officer, "pol_detain") then return notify(officer, "No tienes permiso para detener.", "error") end
    if not exports.rp_inventory:hasItem(officer, "pol_cuffs", 1) then return notify(officer, "Necesitas esposas (armeria).", "warning") end
    if cuffed[target] then return end
    if isPedInVehicle(target) then return notify(officer, "Sacalo del vehiculo primero.", "warning") end
    if isPedInVehicle(officer) then return end
    cuffed[target] = { mode = mode, by = officer }
    setElementData(target, "rp:cuffed", mode)
    takeAllWeapons(target)
    applyControls(target)
    cuffAnim(target)
    notify(target, mode == 2 and "Te esposan con las manos a la espalda. No puedes moverte." or "Te esposan.", "warning")
    notify(officer, ("Esposas a %s."):format(dname(target)), "success")
    factionLog(("%s esposo a %s."):format(dname(officer), dname(target)))
end
ACT.cuff = function(o, t) doCuff(o, t, 1) end
ACT.hardcuff = function(o, t) doCuff(o, t, 2) end

ACT.uncuff = function(officer, target)
    if not can(officer, "pol_detain") or not cuffed[target] then return end
    releaseCuffs(target)
    notify(officer, ("Quitas las esposas a %s."):format(dname(target)), "success")
end

ACT.escort = function(officer, target)
    if not can(officer, "pol_detain") or not cuffed[target] or isPedInVehicle(officer) then return end
    if escorting[officer] == target then
        stopEscort(officer, target)
        return notify(officer, "Sueltas al detenido.", "info")
    end
    if escorting[officer] then stopEscort(officer) end
    if escortedBy[target] then stopEscort(escortedBy[target], target) end
    escorting[officer], escortedBy[target] = target, officer
    attachElements(target, officer, 0, 0.85, 0)
    setElementCollisionsEnabled(target, false)
    notify(officer, ("Escoltas a %s. Usa el mismo menu para soltarlo."):format(dname(target)), "success")
end

ACT.search = function(officer, target)
    if not can(officer, "pol_detain") then return end
    if not cuffed[target] and getElementData(target, "rp:downed") ~= true then
        return notify(officer, "Solo puedes cachear a alguien esposado o abatido.", "warning")
    end
    local inv = exports.rp_inventory:getInventory(target) or {}
    local items = {}
    for id, amount in pairs(inv) do
        local def = exports.rp_inventory:getItemDefinition(id)
        if def and amount > 0 then
            items[#items + 1] = { id = id, name = def.name, icon = def.icon, amount = amount, police = def.police and true or false }
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    ctx[officer] = { target = target, kind = "search" }
    showUI(officer, "search", { name = dname(target), cash = getPlayerMoney(target), items = items })
    notify(target, "Un oficial te esta cacheando.", "info")
end

UI_ACTIONS.seize = function(officer, d)
    local c = ctx[officer]
    if not c or c.kind ~= "search" or not can(officer, "pol_detain") then return end
    local target, itemId, amount = c.target, d.item, math.floor(tonumber(d.amount) or 0)
    if type(itemId) ~= "string" or amount < 1 then return end
    if not validPlayerTarget(officer, target, 4) or (not cuffed[target] and getElementData(target, "rp:downed") ~= true) then
        return notify(officer, "El sospechoso ya no esta a tu alcance.", "warning")
    end
    local have = exports.rp_inventory:getItemAmount(target, itemId)
    if have < amount then amount = have end
    if amount < 1 then return end
    local ok = exports.rp_inventory:takeItem(target, itemId, amount)
    if not ok then return end
    local def = exports.rp_inventory:getItemDefinition(itemId)
    dbExec(db(), "INSERT INTO police_seized (character_id, item, amount, officer_name) VALUES (?, ?, ?, ?)",
        charOf(target), itemId:sub(1, 48), amount, dname(officer))
    factionLog(("%s decomiso %dx %s a %s."):format(dname(officer), amount, def and def.name or itemId, dname(target)))
    notify(officer, ("Decomisas %dx %s."):format(amount, def and def.name or itemId), "success")
    notify(target, ("Te decomisan %dx %s."):format(amount, def and def.name or itemId), "warning")
    ACT.search(officer, target)
end

ACT.identify = function(officer, target)
    if not can(officer, "pol_detain") then return end
    local id = charOf(target)
    dbQuery(function(qh)
        local row = (dbPoll(qh, 0) or {})[1]
        if not isElement(officer) or not row then return end
        local lic = row.lic and (row.lic == "valid" and "vigente" or ("estado: " .. row.lic)) or "sin licencia de conducir"
        local wanted = tonumber(row.warrants) > 0
        popup(officer, "Identificacion", ("%s, %d anos. Licencia: %s.%s"):format(
            row.name:gsub("_", " "), row.age, lic, wanted and " ORDEN DE CAPTURA ACTIVA." or ""), wanted and "warning" or "info")
    end, db(), [[SELECT c.name, c.age, (SELECT status FROM driving_licenses WHERE character_id = c.id) AS lic,
        (SELECT COUNT(*) FROM police_bolos WHERE active = 1 AND kind = 'person' AND character_id = c.id) AS warrants
        FROM characters c WHERE c.id = ?]], id)
end

ACT.fine = function(officer, target)
    if not can(officer, "pol_fine") then return notify(officer, "No tienes permiso para multar.", "error") end
    ctx[officer] = { target = target, kind = "fine" }
    showUI(officer, "form", { kind = "fine", name = dname(target), max = POLICE.MAX_FINE })
end

ACT.arrest = function(officer, target)
    if not can(officer, "pol_fine") then return notify(officer, "No tienes permiso para arrestar.", "error") end
    if not cuffed[target] then return notify(officer, "El detenido debe ir esposado.", "warning") end
    if not nearPoint(officer, "booking", POLICE.BOOKING_RADIUS) then
        return notify(officer, "Llevalo a los calabozos de la comisaria para procesarlo.", "warning")
    end
    ctx[officer] = { target = target, kind = "arrest" }
    showUI(officer, "form", { kind = "arrest", name = dname(target), maxMin = POLICE.MAX_JAIL_MIN, max = POLICE.MAX_FINE })
end

local function cleanText(s, min, max)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c<>]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s < min or #s > max then return nil end
    return s
end

local function chargeFine(targetId, amount, reason, officerName, target, cb)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        local paid = affected and affected > 0
        if paid then
            dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'purchase', ?, 'Multa LSPD')", targetId, amount)
        end
        dbExec(db(), "INSERT INTO police_records (character_id, kind, text, amount, paid, officer_name) VALUES (?, 'fine', ?, ?, ?, ?)",
            targetId, reason, amount, paid and 1 or 0, officerName)
        if cb then cb(paid) end
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, targetId, amount)
end

UI_ACTIONS.form_fine = function(officer, d)
    local c = ctx[officer]
    if not c or c.kind ~= "fine" or not can(officer, "pol_fine") then return end
    local target = c.target
    local amount, reason = math.floor(tonumber(d.amount) or 0), cleanText(d.reason, 3, 120)
    if amount < 1 or amount > POLICE.MAX_FINE then return notify(officer, ("La multa debe ser de $1 a $%d."):format(POLICE.MAX_FINE), "warning") end
    if not reason then return notify(officer, "Escribe el motivo (3 a 120 caracteres).", "warning") end
    if not validPlayerTarget(officer, target, 6) then return notify(officer, "El sospechoso ya no esta cerca.", "warning") end
    ctx[officer] = nil
    triggerClientEvent(officer, "rp:pol:ui:close", resourceRoot)
    local oname = dname(officer)
    chargeFine(charOf(target), amount, reason, oname, target, function(paid)
        if isElement(officer) then
            notify(officer, paid and ("Multa de $%d cobrada a %s."):format(amount, dname(target))
                or ("Multa de $%d registrada: %s no tiene saldo, queda pendiente."):format(amount, dname(target)), paid and "success" or "info")
        end
        if isElement(target) then
            popup(target, "Multa policial", ("$%d: %s.%s"):format(amount, reason, paid and " Cobrada de tu cuenta." or " Queda pendiente de pago."), "warning")
        end
    end)
    factionLog(("%s multo a %s con $%d: %s"):format(oname, dname(target), amount, reason))
end

UI_ACTIONS.form_arrest = function(officer, d)
    local c = ctx[officer]
    if not c or c.kind ~= "arrest" or not can(officer, "pol_fine") then return end
    local target = c.target
    local minutes = math.floor(tonumber(d.minutes) or 0)
    local reason = cleanText(d.reason, 3, 200)
    local fine = math.floor(tonumber(d.fine) or 0)
    if minutes < 1 or minutes > POLICE.MAX_JAIL_MIN then
        return notify(officer, ("La condena debe ser de 1 a %d minutos."):format(POLICE.MAX_JAIL_MIN), "warning")
    end
    if fine < 0 or fine > POLICE.MAX_FINE then return notify(officer, "Multa no valida.", "warning") end
    if not reason then return notify(officer, "Escribe los cargos (3 a 200 caracteres).", "warning") end
    if not validPlayerTarget(officer, target, 8) or not cuffed[target] then
        return notify(officer, "El detenido ya no esta a tu alcance.", "warning")
    end
    if not nearPoint(officer, "booking", POLICE.BOOKING_RADIUS) then return notify(officer, "Debes estar en los calabozos.", "warning") end
    ctx[officer] = nil
    triggerClientEvent(officer, "rp:pol:ui:close", resourceRoot)

    local targetId, oname = charOf(target), dname(officer)
    if isPedInVehicle(target) then removePedFromVehicle(target) end
    releaseCuffs(target, true)
    pcall(function() exports.rp_wanted:clearWanted(target) end)
    exports.rp_wanted:jailPlayer(target, minutes * 60, minutes * POLICE.BAIL_PER_MIN, 0)
    dbExec(db(), "INSERT INTO police_records (character_id, kind, text, minutes, officer_name) VALUES (?, 'arrest', ?, ?, ?)",
        targetId, reason, minutes, oname)
    dbExec(db(), "UPDATE police_bolos SET active = 0, closed_by = ? WHERE active = 1 AND kind = 'person' AND character_id = ?", oname, targetId)
    if fine > 0 then chargeFine(targetId, fine, "Multa del arresto: " .. reason, oname, target) end
    notify(officer, ("%s queda encarcelado %d min."):format(dname(target), minutes), "success")
    factionLog(("%s arresto a %s (%d min): %s"):format(oname, dname(target), minutes, reason))
end

----------------------------------------------------------------
-- Acciones sobre vehiculos
----------------------------------------------------------------
local function detaineeFor(officer, vehicle)
    local t = escorting[officer]
    if t and isElement(t) then return t end
    local best, bd = nil, 5
    for p in pairs(cuffed) do
        if isElement(p) and not isPedInVehicle(p) then
            local d = distPlayers(officer, p)
            if d < bd then best, bd = p, d end
        end
    end
    return best
end

local function plateInfo(officer, vehicle)
    local vid = exports.rp_vehicles:getVehicleDatabaseId(vehicle)
    local model = getVehicleNameFromModel(getElementModel(vehicle)) or "Vehiculo"
    if not vid then
        return popup(officer, "Matricula " .. getVehiclePlateText(vehicle), model .. ": sin registro de propietario.", "info")
    end
    lookupVehicleById(vid, function(info)
        if not isElement(officer) or not info then return end
        local flags = {}
        if info.bolo then flags[#flags + 1] = "BOLO ACTIVO: " .. info.bolo end
        if info.unpaid > 0 then flags[#flags + 1] = ("multas pendientes $%d"):format(info.unpaid) end
        if info.clamped then flags[#flags + 1] = "con cepo" end
        popup(officer, "Matricula " .. info.plate, ("%s de %s.%s"):format(model, info.owner,
            #flags > 0 and (" " .. table.concat(flags, "; ") .. ".") or " Sin novedades."), info.bolo and "warning" or "info")
    end)
end

ACT.v_plate = function(officer, vehicle)
    if not can(officer, "pol_mdt") then return notify(officer, "No tienes acceso al MDT.", "error") end
    plateInfo(officer, vehicle)
end

ACT.v_putin = function(officer, vehicle)
    if not can(officer, "pol_detain") then return end
    local target = detaineeFor(officer, vehicle)
    if not target or not cuffed[target] then return notify(officer, "No hay un detenido esposado cerca.", "warning") end
    local seats = getVehicleMaxPassengers(vehicle) or 0
    local seat
    for s = seats, 1, -1 do   -- primero los asientos traseros
        if not getVehicleOccupant(vehicle, s) then seat = s break end
    end
    if not seat then return notify(officer, "No queda asiento libre.", "warning") end
    stopEscort(officer, target)
    setElementCollisionsEnabled(target, true)
    setPedAnimation(target)
    warpPedIntoVehicle(target, vehicle, seat)
    notify(officer, ("Metes a %s en el vehiculo."):format(dname(target)), "success")
end

ACT.v_takeout = function(officer, vehicle)
    if not can(officer, "pol_detain") then return end
    local n = 0
    for _, p in ipairs(vehicleOccupants(vehicle)) do
        if cuffed[p] then
            removePedFromVehicle(p)
            cuffAnim(p)
            n = n + 1
        end
    end
    notify(officer, n > 0 and ("Sacas a %d detenido(s)."):format(n) or "No hay detenidos esposados dentro.", n > 0 and "success" or "info")
end

----------------------------------------------------------------
-- Menu contextual
----------------------------------------------------------------
addEventHandler("rp:pol:menu", resourceRoot, function(target)
    local officer = client
    if busy(officer) or not isOnDuty(officer) or isPedDead(officer) or not isElement(target) then return end
    local options = {}
    local function opt(id, label, icon, disabled, hint)
        options[#options + 1] = { id = id, label = label, icon = icon, disabled = disabled or nil, hint = hint }
    end
    local title
    if getElementType(target) == "player" then
        if not validPlayerTarget(officer, target) then return end
        title = dname(target)
        local detain, fine = can(officer, "pol_detain"), can(officer, "pol_fine")
        if not cuffed[target] then
            if detain then
                opt("cuff", "Esposar", "🔗")
                opt("hardcuff", "Esposar (inmovilizar)", "⛓️")
                opt("identify", "Pedir identificacion", "🪪")
            end
        else
            if detain then
                opt("uncuff", "Quitar esposas", "🔓")
                opt("escort", escorting[officer] == target and "Soltar escolta" or "Escoltar", "🚶")
                opt("search", "Cachear", "🔎")
                opt("identify", "Identificar", "🪪")
            end
            if fine then
                opt("fine", "Multar", "💵")
                local near = nearPoint(officer, "booking", POLICE.BOOKING_RADIUS)
                opt("arrest", "Arrestar", "🚔", not near, not near and "Solo en los calabozos" or nil)
            end
        end
    elseif getElementType(target) == "vehicle" then
        if distPlayers(officer, target) > POLICE.INTERACT_DISTANCE + 2 then return end
        title = getVehicleNameFromModel(getElementModel(target)) or "Vehiculo"
        if can(officer, "pol_mdt") then opt("v_plate", "Consultar matricula", "🔖") end
        if can(officer, "pol_detain") then
            opt("v_putin", "Meter al detenido", "🚓")
            opt("v_takeout", "Sacar detenidos", "🚪")
        end
    else
        return
    end
    if #options == 0 then return notify(officer, "No tienes acciones disponibles sobre esto.", "info") end
    triggerClientEvent(officer, "rp:pol:menuOptions", resourceRoot, target, title, options)
end)

addEventHandler("rp:pol:do", resourceRoot, function(target, id)
    local officer = client
    if busy(officer) or type(id) ~= "string" or not isOnDuty(officer) or isPedDead(officer) or not isElement(target) then return end
    local handler = ACT[id]
    if not handler then return end
    if id:sub(1, 2) == "v_" then
        if getElementType(target) ~= "vehicle" or distPlayers(officer, target) > POLICE.INTERACT_DISTANCE + 2 then return end
    else
        if not validPlayerTarget(officer, target) then return end
    end
    handler(officer, target)
end)
addEvent("rp:pol:menuOptions", true)

----------------------------------------------------------------
-- Taser
----------------------------------------------------------------
addEventHandler("rp:pol:tased", resourceRoot, function(attacker)
    local victim = client
    if not isElement(attacker) or getElementType(attacker) ~= "player" or attacker == victim then return end
    if not isOnDuty(attacker) or POLICE_EQUIPPED[attacker] ~= "pol_taser" then return end
    if distPlayers(attacker, victim) > POLICE.TASER_RANGE + 4 then return end
    local now = getTickCount()
    if lastTaser[attacker] and now - lastTaser[attacker] < POLICE.TASER_COOLDOWN then return end
    lastTaser[attacker] = now
    tasedUntil[victim] = now + POLICE.TASER_SECONDS * 1000
    setElementData(victim, "rp:tased", true)
    if isPedInVehicle(victim) then removePedFromVehicle(victim) end
    applyControls(victim)
    setPedAnimation(victim, "crack", "crckdeth2", -1, false, false, false, true)
    notify(victim, "Un taser te deja inmovil unos segundos.", "warning")
    notify(attacker, ("Taser a %s."):format(dname(victim)), "success")
    factionLog(("%s uso el taser contra %s."):format(dname(attacker), dname(victim)))
end)
