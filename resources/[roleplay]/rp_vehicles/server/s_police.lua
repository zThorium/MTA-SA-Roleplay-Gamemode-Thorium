--[[
    rp_vehicles / s_police.lua
    Herramientas de policia sobre vehiculos con dueno. Solo para miembros de
    la faccion reservada VEHICLES.POLICE_FACTION_ID (1 = Policia, ver
    rp_factions y rp_database/schema.lua):
        - Cepo (inmoviliza el vehiculo y no deja encender el motor)
        - Multas (las paga el dueno desde el banco con el menu del vehiculo)
        - Historial: multas y registro de acciones policiales

    Acciones (rp:veh:action): police, police_clamp, police_fine,
    fines (dueno), fine_pay (dueno)
]]

local busy = {}

local function logPolice(vehicleId, actor, text)
    dbExec(db(), "INSERT INTO vehicle_police_log (vehicle_id, actor_name, text) VALUES (?, ?, ?)", vehicleId, actor, text)
end

local function ownerPlayer(characterId)
    for _, p in ipairs(getElementsByType("player")) do
        if characterOf(p) == characterId then return p end
    end
end

local function sendPolice(player, vehicle)
    local data = getVehicleData(vehicle)
    dbQuery(function(qh)
        local fines = dbPoll(qh, 0) or {}
        dbQuery(function(qh2)
            local log = dbPoll(qh2, 0) or {}
            dbQuery(function(qh3)
                local owner = (dbPoll(qh3, 0) or {})[1]
                if not isElement(player) or not isElement(vehicle) then return end
                local unpaid = 0
                for _, f in ipairs(fines) do
                    if tonumber(f.paid) == 0 then unpaid = unpaid + tonumber(f.amount) end
                end
                triggerClientEvent(player, "rp:veh:showPolice", resourceRoot, vehicle, {
                    plate = data.plate, name = getVehicleNameFromModel(data.model) or "Vehiculo",
                    owner = owner and owner.name and owner.name:gsub("_", " ") or "?",
                    clamped = data.clamped, locked = data.locked, fines = fines, log = log, unpaid = unpaid,
                    fineMin = VEHICLES.FINE_MIN, fineMax = VEHICLES.FINE_MAX,
                })
            end, db(), "SELECT name FROM characters WHERE id = ?", data.ownerId)
        end, db(), [[SELECT actor_name, text, DATE_FORMAT(created_at, '%d/%m/%Y %H:%i') AS at FROM vehicle_police_log
            WHERE vehicle_id = ? ORDER BY id DESC LIMIT ?]], data.id, VEHICLES.PANEL_ROWS)
    end, db(), [[SELECT id, officer_name, amount, reason, paid, DATE_FORMAT(created_at, '%d/%m/%Y %H:%i') AS at FROM vehicle_fines
        WHERE vehicle_id = ? ORDER BY id DESC LIMIT ?]], data.id, VEHICLES.PANEL_ROWS)
end

local function sendOwnerFines(player, vehicle)
    local data = getVehicleData(vehicle)
    dbQuery(function(qh)
        local fines = dbPoll(qh, 0) or {}
        if not isElement(player) or not isElement(vehicle) then return end
        triggerClientEvent(player, "rp:veh:showFines", resourceRoot, vehicle, {
            plate = data.plate, name = getVehicleNameFromModel(data.model) or "Vehiculo", fines = fines, clamped = data.clamped,
        })
    end, db(), [[SELECT id, officer_name, amount, reason, paid, DATE_FORMAT(created_at, '%d/%m/%Y %H:%i') AS at FROM vehicle_fines
        WHERE vehicle_id = ? ORDER BY paid ASC, id DESC LIMIT ?]], data.id, VEHICLES.PANEL_ROWS)
end

local function toggleClamp(player, vehicle, data)
    data.clamped = not data.clamped
    if data.clamped then
        data.engine = false
        setVehicleEngineState(vehicle, false)
    end
    updateFrozen(vehicle)
    dbExec(db(), "UPDATE vehicles SET clamped = ? WHERE id = ?", data.clamped and 1 or 0, data.id)
    local officer = displayName(player)
    logPolice(data.id, officer, data.clamped and "Puso un cepo" or "Quito el cepo")
    notify(player, data.clamped and "Cepo colocado." or "Cepo retirado.", "success")
    local owner = ownerPlayer(data.ownerId)
    if owner then
        notify(owner, data.clamped and ("La policia puso un cepo a tu vehiculo %s."):format(data.plate)
            or ("La policia retiro el cepo de tu vehiculo %s."):format(data.plate), data.clamped and "warning" or "info")
    end
    sendPolice(player, vehicle)
end

local function addFine(player, vehicle, data, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    reason = type(reason) == "string" and reason:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if amount < VEHICLES.FINE_MIN or amount > VEHICLES.FINE_MAX then
        return notify(player, ("La multa debe ser entre $%d y $%d."):format(VEHICLES.FINE_MIN, VEHICLES.FINE_MAX), "warning")
    end
    if #reason < 3 or #reason > VEHICLES.FINE_REASON_MAX then
        return notify(player, "Escribe el motivo de la multa (3 a 128 caracteres).", "warning")
    end
    local officer = displayName(player)
    dbExec(db(), "INSERT INTO vehicle_fines (vehicle_id, officer_id, officer_name, amount, reason) VALUES (?, ?, ?, ?, ?)",
        data.id, characterOf(player), officer, amount, reason)
    logPolice(data.id, officer, ("Multa de $%d: %s"):format(amount, reason))
    notify(player, ("Multa de $%d registrada a %s."):format(amount, data.plate), "success")
    local owner = ownerPlayer(data.ownerId)
    if owner then
        exports.rp_notify:popup(owner, "Multa de transito",
            ("Tu vehiculo %s recibio una multa de $%d: %s. Pagala desde el menu del vehiculo (M + click derecho)."):format(data.plate, amount, reason), "warning")
    end
    setTimer(function() if isElement(player) and isElement(vehicle) then sendPolice(player, vehicle) end end, 300, 1)
end

local function payFine(player, vehicle, data, fineId)
    fineId = tonumber(fineId)
    local characterId = characterOf(player)
    if not fineId or busy[player] or data.ownerId ~= characterId then return end
    busy[player] = true
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local fine = rows[1]
        if not fine or not isElement(player) then busy[player] = nil return end
        local amount = tonumber(fine.amount)
        -- Primero se marca como pagada (solo una vez) y luego se cobra
        dbQuery(function(qh2)
            local _, affected = dbPoll(qh2, 0)
            if not affected or affected == 0 then busy[player] = nil return end
            dbQuery(function(qh3)
                local _, charged = dbPoll(qh3, 0)
                busy[player] = nil
                if not charged or charged == 0 then
                    dbExec(db(), "UPDATE vehicle_fines SET paid = 0, paid_at = NULL WHERE id = ?", fineId)
                    if isElement(player) then notify(player, ("Necesitas $%d en tu cuenta bancaria."):format(amount), "error") end
                    return
                end
                dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'fine', ?, ?)",
                    characterId, amount, "Multa " .. data.plate)
                logPolice(data.id, getPlayerName(player):gsub("_", " "), ("Pago la multa #%d ($%d)"):format(fineId, amount))
                if isElement(player) then
                    notify(player, ("Pagaste la multa de $%d."):format(amount), "success")
                    if isElement(vehicle) then sendOwnerFines(player, vehicle) end
                end
            end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, characterId, amount)
        end, db(), "UPDATE vehicle_fines SET paid = 1, paid_at = NOW() WHERE id = ? AND paid = 0", fineId)
    end, db(), "SELECT amount FROM vehicle_fines WHERE id = ? AND vehicle_id = ? AND paid = 0", fineId, data.id)
end

-- Llamado desde s_interaction.lua
function onPoliceAction(player, vehicle, data, action, a, b)
    if action == "fines" then
        if data.ownerId == characterOf(player) then sendOwnerFines(player, vehicle) end
        return
    elseif action == "fine_pay" then
        return payFine(player, vehicle, data, a)
    end
    if not isPolice(player) then return notify(player, "Solo la policia puede hacer eso.", "error") end
    if action == "police" then sendPolice(player, vehicle)
    elseif action == "police_clamp" then toggleClamp(player, vehicle, data)
    elseif action == "police_fine" then addFine(player, vehicle, data, a, b)
    end
end

-- Aviso de multas pendientes al entrar
addEvent("rp:onCharacterSpawn", false)
addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local player = source
    dbQuery(function(qh)
        local row = (dbPoll(qh, 0) or {})[1]
        local total, count = tonumber(row and row.total) or 0, tonumber(row and row.n) or 0
        if count > 0 and isElement(player) then
            notify(player, ("Tienes %d multa(s) de transito sin pagar ($%d)."):format(count, total), "warning")
        end
    end, db(), [[SELECT COUNT(*) AS n, COALESCE(SUM(f.amount), 0) AS total FROM vehicle_fines f
        JOIN vehicles v ON v.id = f.vehicle_id WHERE v.owner_id = ? AND f.paid = 0]], characterId)
end)

addEventHandler("onPlayerQuit", root, function() busy[source] = nil end)
