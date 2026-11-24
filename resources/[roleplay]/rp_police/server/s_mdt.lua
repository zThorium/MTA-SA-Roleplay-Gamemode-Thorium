--[[
    rp_police / s_mdt.lua
    MDT (F6, permiso pol_mdt): base de datos de ciudadanos y vehiculos, antecedentes,
    BOLO y ordenes de captura (pol_bolo), despacho y unidades en servicio.
    Todas las consultas son asincronas y parametrizadas.

    Civiles: /multas lista tus multas policiales, /pagarmultas las paga del banco.
]]

addEvent("rp:pol:openMDT", true)

local function likeEscape(s)
    return (s:gsub("[\\%%]", "\\%0"))
end

local function text(s, min, max)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c<>]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s < min or #s > max then return nil end
    return s
end

local function modelName(id) return getVehicleNameFromModel(tonumber(id) or 0) or "Vehiculo" end

-- Datos de un vehiculo con dueno (para el cacheo de matriculas, el MDT y el radar)
function lookupVehicleById(vid, cb)
    dbQuery(function(qh)
        local v = (dbPoll(qh, 0) or {})[1]
        if not v then return cb(nil) end
        local info = { id = tonumber(v.id), plate = v.plate, model = tonumber(v.model), owner = (v.owner or "?"):gsub("_", " "),
            ownerId = tonumber(v.owner_id), clamped = tonumber(v.clamped) == 1, unpaid = 0 }
        dbQuery(function(q2)
            local b = (dbPoll(q2, 0) or {})[1]
            info.bolo = b and b.description or nil
            dbQuery(function(q3)
                local r3 = (dbPoll(q3, 0) or {})[1]
                info.unpaid = tonumber(r3 and r3.s) or 0
                cb(info)
            end, db(), "SELECT COALESCE(SUM(amount), 0) AS s FROM vehicle_fines WHERE vehicle_id = ? AND paid = 0", info.id)
        end, db(), "SELECT description FROM police_bolos WHERE active = 1 AND kind = 'vehicle' AND plate = ? LIMIT 1", info.plate)
    end, db(), [[SELECT v.id, v.plate, v.model, v.clamped, v.owner_id, c.name AS owner FROM vehicles v
        LEFT JOIN characters c ON c.id = v.owner_id WHERE v.id = ?]], vid)
end

local function lookupPlate(plate, cb)
    dbQuery(function(qh)
        local v = (dbPoll(qh, 0) or {})[1]
        if not v then return cb(nil) end
        lookupVehicleById(tonumber(v.id), cb)
    end, db(), "SELECT id FROM vehicles WHERE plate = ? LIMIT 1", plate)
end

----------------------------------------------------------------
-- Apertura
----------------------------------------------------------------
addEventHandler("rp:pol:openMDT", resourceRoot, function()
    local p = client
    if not charOf(p) or isPedDead(p) then return end
    if currentUI(p) then return end
    if not can(p, "pol_mdt") then
        return notify(p, isOnDuty(p) and "Tu rol no tiene acceso al MDT." or "Debes estar de servicio para usar el MDT.", "warning")
    end
    local _, _, rankName = exports.rp_factions:getPlayerFaction(p)
    showUI(p, "mdt", {
        me = { name = dname(p), rank = rankName },
        perms = { bolo = can(p, "pol_bolo"), fine = can(p, "pol_fine"), evidence = can(p, "pol_evidence") },
        alerts = getAlertList(),
    })
end)

----------------------------------------------------------------
-- Ciudadanos
----------------------------------------------------------------
UI_ACTIONS.mdt_search = function(p, d)
    if not can(p, "pol_mdt") then return end
    local q = text(d.q, 2, 32)
    if not q then return end
    q = likeEscape(q:gsub(" ", "_"))
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = { id = tonumber(r.id), name = r.name:gsub("_", " "), age = tonumber(r.age), gender = tonumber(r.gender) }
        end
        updateUI(p, "citizens", { list = out })
    end, db(), "SELECT id, name, age, gender FROM characters WHERE name LIKE ? ORDER BY name LIMIT 15", "%" .. q .. "%")
end

UI_ACTIONS.mdt_profile = function(p, d)
    if not can(p, "pol_mdt") then return end
    local id = math.floor(tonumber(d.id) or 0)
    if id < 1 then return end
    local out, left = {}, 7
    local function part(key, rows)
        out[key] = rows
        left = left - 1
        if left > 0 then return end
        local c = out.char and out.char[1]
        if not c then return end
        local profile = {
            id = tonumber(c.id), name = c.name:gsub("_", " "), age = tonumber(c.age), gender = tonumber(c.gender),
            origin = c.origin, since = c.since,
            license = out.lic[1] and { number = out.lic[1].number, status = out.lic[1].status } or false,
            vehicles = {}, properties = {}, records = {}, warrants = {}, unpaid = tonumber(out.fines[1] and out.fines[1].s) or 0,
        }
        for _, v in ipairs(out.veh) do profile.vehicles[#profile.vehicles + 1] = { plate = v.plate, name = modelName(v.model) } end
        for _, h in ipairs(out.prop) do profile.properties[#profile.properties + 1] = { name = h.name, type = h.type } end
        for _, r in ipairs(out.rec) do
            profile.records[#profile.records + 1] = { kind = r.kind, text = r.text, amount = tonumber(r.amount), minutes = tonumber(r.minutes),
                paid = tonumber(r.paid) == 1, officer = r.officer_name, at = r.at }
        end
        for _, w in ipairs(out.bolo) do profile.warrants[#profile.warrants + 1] = { id = tonumber(w.id), description = w.description, reward = tonumber(w.reward) } end
        updateUI(p, "profile", profile)
    end
    local function q(key, sql, ...)
        dbQuery(function(qh) part(key, dbPoll(qh, 0) or {}) end, db(), sql, ...)
    end
    q("char", "SELECT id, name, age, gender, origin, DATE_FORMAT(created_at, '%d/%m/%Y') AS since FROM characters WHERE id = ?", id)
    q("lic", "SELECT number, status FROM driving_licenses WHERE character_id = ?", id)
    q("veh", "SELECT plate, model FROM vehicles WHERE owner_id = ? LIMIT 15", id)
    q("prop", "SELECT name, type FROM properties WHERE owner_id = ? LIMIT 15", id)
    q("rec", "SELECT kind, text, amount, minutes, paid, officer_name, DATE_FORMAT(created_at, '%d/%m/%Y %H:%i') AS at FROM police_records WHERE character_id = ? ORDER BY id DESC LIMIT 25", id)
    q("bolo", "SELECT id, description, reward FROM police_bolos WHERE active = 1 AND kind = 'person' AND character_id = ?", id)
    q("fines", "SELECT COALESCE(SUM(amount), 0) AS s FROM police_records WHERE character_id = ? AND kind = 'fine' AND paid = 0", id)
end

UI_ACTIONS.record_add = function(p, d)
    if not can(p, "pol_fine") then return end
    local id, note = math.floor(tonumber(d.id) or 0), text(d.text, 3, 200)
    if id < 1 or not note then return notify(p, "Escribe la nota (3 a 200 caracteres).", "warning") end
    dbExec(db(), "INSERT INTO police_records (character_id, kind, text, officer_name) VALUES (?, 'note', ?, ?)", id, note, dname(p))
    factionLog(("%s agrego una nota al historial #%d."):format(dname(p), id))
    notify(p, "Nota agregada al historial.", "success")
    UI_ACTIONS.mdt_profile(p, { id = id })
end

----------------------------------------------------------------
-- Vehiculos
----------------------------------------------------------------
UI_ACTIONS.mdt_vehicle = function(p, d)
    if not can(p, "pol_mdt") then return end
    local plate = text(d.plate, 2, 8)
    if not plate then return end
    lookupPlate(plate:upper(), function(info)
        if not isElement(p) then return end
        if not info then return updateUI(p, "vehicle", { plate = plate:upper(), found = false }) end
        updateUI(p, "vehicle", { found = true, plate = info.plate, name = modelName(info.model), owner = info.owner, ownerId = info.ownerId,
            bolo = info.bolo or false, unpaid = info.unpaid, clamped = info.clamped })
    end)
end

----------------------------------------------------------------
-- BOLO y ordenes de captura
----------------------------------------------------------------
local function sendBolos(p)
    dbQuery(function(qh)
        local out = {}
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            out[#out + 1] = { id = tonumber(r.id), kind = r.kind, subject = r.subject:gsub("_", " "), plate = r.plate,
                description = r.description, reward = tonumber(r.reward), officer = r.officer_name, at = r.at, warrant = r.character_id ~= nil }
        end
        updateUI(p, "bolos", { list = out })
    end, db(), [[SELECT id, kind, subject, character_id, plate, description, reward, officer_name,
        DATE_FORMAT(created_at, '%d/%m %H:%i') AS at FROM police_bolos WHERE active = 1 ORDER BY id DESC LIMIT 40]])
end
UI_ACTIONS.mdt_bolos = function(p) if can(p, "pol_mdt") then sendBolos(p) end end

local function announceBolo(p, kind, subject, description)
    for _, o in ipairs(officersOnDuty()) do
        if o ~= p then
            popup(o, kind == "person" and "Orden de captura" or "BOLO", ("%s: %s"):format(subject, description), "warning")
        end
    end
end

UI_ACTIONS.bolo_add = function(p, d)
    if not can(p, "pol_bolo") then return notify(p, "Tu rol no puede emitir BOLO.", "error") end
    local kind = d.kind == "vehicle" and "vehicle" or "person"
    local subject, desc = text(d.subject, 2, 40), text(d.description, 5, 200)
    local reward = math.floor(tonumber(d.reward) or 0)
    if not subject or not desc then return notify(p, "Completa el sujeto y la descripcion.", "warning") end
    if reward < 0 or reward > POLICE.MAX_BOLO_REWARD then return notify(p, ("Recompensa maxima: $%d."):format(POLICE.MAX_BOLO_REWARD), "warning") end
    local oname = dname(p)
    if kind == "vehicle" then
        local plate = subject:upper():gsub("%s", "")
        if #plate > 8 then return notify(p, "Matricula no valida.", "warning") end
        dbExec(db(), "INSERT INTO police_bolos (kind, subject, plate, description, reward, officer_name) VALUES ('vehicle', ?, ?, ?, ?, ?)",
            plate, plate, desc, reward, oname)
        announceBolo(p, kind, plate, desc)
        notify(p, "BOLO de vehiculo emitido.", "success")
        factionLog(("%s emitio un BOLO de vehiculo: %s."):format(oname, plate))
        return setTimer(function() if isElement(p) then sendBolos(p) end end, 300, 1)
    end
    dbQuery(function(qh)
        local c = (dbPoll(qh, 0) or {})[1]
        if not isElement(p) then return end
        if not c then return notify(p, "No existe ningun ciudadano con ese nombre (Nombre Apellido).", "warning") end
        dbExec(db(), "INSERT INTO police_bolos (kind, subject, character_id, description, reward, officer_name) VALUES ('person', ?, ?, ?, ?, ?)",
            c.name, c.id, desc, reward, oname)
        announceBolo(p, kind, c.name:gsub("_", " "), desc)
        notify(p, "Orden de captura emitida.", "success")
        factionLog(("%s emitio una orden de captura contra %s."):format(oname, c.name:gsub("_", " ")))
        setTimer(function() if isElement(p) then sendBolos(p) end end, 300, 1)
    end, db(), "SELECT id, name FROM characters WHERE name = ? LIMIT 1", (subject:gsub("%s+", "_")))
end

UI_ACTIONS.bolo_close = function(p, d)
    if not can(p, "pol_bolo") then return end
    local id = math.floor(tonumber(d.id) or 0)
    if id < 1 then return end
    dbExec(db(), "UPDATE police_bolos SET active = 0, closed_by = ? WHERE id = ? AND active = 1", dname(p), id)
    factionLog(("%s cancelo el BOLO #%d."):format(dname(p), id))
    notify(p, "BOLO cancelado.", "success")
    setTimer(function() if isElement(p) then sendBolos(p) end end, 300, 1)
end

----------------------------------------------------------------
-- Unidades y despacho
----------------------------------------------------------------
UI_ACTIONS.mdt_units = function(p)
    if not can(p, "pol_mdt") then return end
    local out = {}
    for _, o in ipairs(officersOnDuty()) do
        local _, _, rank = exports.rp_factions:getPlayerFaction(o)
        local x, y, z = getElementPosition(o)
        out[#out + 1] = { id = exports.rp_ids:getPlayerId(o), name = dname(o), rank = rank, zone = getZoneName(x, y, z),
            vehicle = getPedOccupiedVehicle(o) and (getVehicleNameFromModel(getElementModel(getPedOccupiedVehicle(o))) or "") or "A pie" }
    end
    updateUI(p, "units", { list = out })
end

UI_ACTIONS.mdt_dispatch = function(p)
    if can(p, "pol_mdt") then updateUI(p, "dispatch", { list = getAlertList() }) end
end

UI_ACTIONS.alert_respond = function(p, d)
    if can(p, "pol_mdt") then respondAlert(p, math.floor(tonumber(d.id) or 0)) end
end

----------------------------------------------------------------
-- Multas personales (civil)
----------------------------------------------------------------
addCommandHandler("multas", function(p)
    local id = charOf(p)
    if not id then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) then return end
        if #rows == 0 then return notify(p, "No tienes multas policiales pendientes.", "success") end
        local total = 0
        for _, r in ipairs(rows) do total = total + tonumber(r.amount) end
        popup(p, "Multas pendientes", ("%d multa(s), total $%d. Usa /pagarmultas para pagarlas desde tu banco."):format(#rows, total), "warning")
    end, db(), "SELECT amount FROM police_records WHERE character_id = ? AND kind = 'fine' AND paid = 0", id)
end)

addCommandHandler("pagarmultas", function(p)
    local id = charOf(p)
    if not id then return end
    dbQuery(function(qh)
        local r1 = (dbPoll(qh, 0) or {})[1]
        local total = tonumber(r1 and r1.s) or 0
        if not isElement(p) then return end
        if total <= 0 then return notify(p, "No tienes multas pendientes.", "info") end
        dbQuery(function(q2)
            local _, affected = dbPoll(q2, 0)
            if not isElement(p) then return end
            if not affected or affected == 0 then return notify(p, ("Necesitas $%d en tu cuenta bancaria."):format(total), "error") end
            dbExec(db(), "UPDATE police_records SET paid = 1 WHERE character_id = ? AND kind = 'fine' AND paid = 0", id)
            dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'purchase', ?, 'Multas LSPD')", id, total)
            notify(p, ("Pagaste $%d en multas."):format(total), "success")
        end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", total, id, total)
    end, db(), "SELECT COALESCE(SUM(amount), 0) AS s FROM police_records WHERE character_id = ? AND kind = 'fine' AND paid = 0", id)
end)

-- Radar / ALPR: el cliente manda hasta 6 vehiculos delante de la patrulla
addEvent("rp:pol:alpr", true)
local alprCache, lastAlpr = {}, {}
addEventHandler("rp:pol:alpr", resourceRoot, function(list)
    local p = client
    if type(list) ~= "table" or not isOnDuty(p) then return end
    local now = getTickCount()
    if lastAlpr[p] and now - lastAlpr[p] < 1500 then return end
    lastAlpr[p] = now
    local px, py, pz = getElementPosition(p)
    for i = 1, math.min(#list, 6) do
        local v = list[i]
        if isElement(v) and getElementType(v) == "vehicle" then
            local x, y, z = getElementPosition(v)
            local vid = getDistanceBetweenPoints3D(px, py, pz, x, y, z) < 60 and exports.rp_vehicles:getVehicleDatabaseId(v)
            if vid then
                local cached = alprCache[vid]
                if cached and now - cached.at < 60000 then
                    triggerClientEvent(p, "rp:pol:alprResult", resourceRoot, v, cached.data)
                else
                    lookupVehicleById(vid, function(info)
                        if not info then return end
                        local data = { plate = info.plate, owner = info.owner, bolo = info.bolo or false, unpaid = info.unpaid, name = modelName(info.model) }
                        alprCache[vid] = { at = getTickCount(), data = data }
                        if isElement(p) and isElement(v) then triggerClientEvent(p, "rp:pol:alprResult", resourceRoot, v, data) end
                    end)
                end
            end
        end
    end
end)
addEvent("rp:pol:alprResult", true)
addEventHandler("onPlayerQuit", root, function() lastAlpr[source] = nil end)
