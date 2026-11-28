--[[
    rp_factions / s_invoices.lua  (servidor)

    Facturas a clientes (#106). Quien tiene el permiso "bill" (y está de servicio si su tipo
    de facción lo tiene) cobra a un jugador cercano:
        /facturar <id> <monto> <concepto...>      o el export bill(empleado, cliente, monto, concepto)
    El cliente ve una ventana con emisor, monto y concepto y paga en efectivo (1), con el banco (2)
    o rechaza (Retroceso); caduca en INVOICES.EXPIRE_S. Al pagar, el dinero va a los fondos de la
    facción y la comisión del rol del empleado (faction_ranks.commission %) a su banco.
    Todo queda en faction_invoices; F3 › Facturas muestra el aporte de cada miembro.

    Exports (servidor): bill(empleado, cliente, monto, concepto) -> true | false, motivo
    Evento público: rp:faction:onInvoicePaid (source = empleado; invoiceId, cliente, monto, comisión)
]]

local pending = {}     -- [cliente] = { id, employee, factionId, factionName, amount, concept, commission, expires }
local lastBill = {}    -- [empleado] = tick

addEvent("rp:fac:invoiceAnswer", true)          -- cliente: "cash" | "bank" | false
addEvent("rp:faction:onInvoicePaid", false)     -- público

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function charOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p) return (getPlayerName(p):gsub("_", " ")) end

local function cleanText(s)
    return (tostring(s or ""):gsub("#%x%x%x%x%x%x", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function near(a, b)
    if getElementDimension(a) ~= getElementDimension(b) or getElementInterior(a) ~= getElementInterior(b) then return false end
    local x1, y1, z1 = getElementPosition(a)
    local x2, y2, z2 = getElementPosition(b)
    return getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2) <= INVOICES.DISTANCE
end

local function resolve(id, status, method, commission)
    dbExec(db(), "UPDATE faction_invoices SET status = ?, method = ?, commission = ?, resolved_at = NOW() WHERE id = ? AND status = 'pending'",
        status, method, commission or 0, id)
end

local function finish(client, status)
    local inv = pending[client]
    if not inv then return end
    pending[client] = nil
    if isElement(client) then triggerClientEvent(client, "rp:fac:invoiceEnd", resourceRoot) end
    if status then resolve(inv.id, status) end
    return inv
end

----------------------------------------------------------------
-- Emitir
----------------------------------------------------------------
function bill(employee, client, amount, concept)
    if not isElement(employee) or not isElement(client) or getElementType(client) ~= "player" then return false, "Jugador no válido." end
    if employee == client then return false, "No puedes facturarte a ti mismo." end
    local eid, cid = charOf(employee), charOf(client)
    if not eid or not cid then return false, "Ese jugador no tiene un personaje en juego." end
    local f = getPlayerFactionInfo(employee)
    if not f then return false, "No perteneces a ninguna facción." end
    if not hasFactionPermission(employee, "bill") then return false, "Tu rol no puede facturar." end
    local t = FACTION_TYPES[f.type]
    if t and t.duty and not isPlayerOnDuty(employee) then return false, "Debes estar de servicio para facturar." end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < INVOICES.MIN or amount > INVOICES.MAX then
        return false, ("El monto va de $%d a $%d."):format(INVOICES.MIN, INVOICES.MAX)
    end
    concept = cleanText(concept)
    if #concept < INVOICES.CONCEPT_MIN or #concept > INVOICES.CONCEPT_MAX then
        return false, ("El concepto debe tener entre %d y %d letras."):format(INVOICES.CONCEPT_MIN, INVOICES.CONCEPT_MAX)
    end
    if not near(employee, client) then return false, "El cliente debe estar a tu lado." end
    if getElementData(client, "rp:downed") or isPedDead(client) then return false, "El cliente no puede atenderte ahora." end
    local p = pending[client]
    if p and p.expires > getTickCount() then return false, "Ese cliente ya tiene una factura pendiente." end
    local now = getTickCount()
    if lastBill[employee] and now - lastBill[employee] < INVOICES.COOLDOWN_MS then return false, "Espera un momento antes de otra factura." end
    lastBill[employee] = now

    local inv = { employee = employee, employeeId = eid, clientId = cid, factionId = f.id, factionName = f.name,
        tag = f.tag, color = f.color, amount = amount, concept = concept,
        commission = math.max(0, math.min(INVOICES.MAX_COMMISSION, tonumber(f.commission) or 0)),
        expires = now + INVOICES.EXPIRE_S * 1000 }
    pending[client] = inv
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if pending[client] ~= inv then return end
        if not ok or not id then
            pending[client] = nil
            return isElement(employee) and notify(employee, "No se pudo emitir la factura.", "error")
        end
        inv.id = tonumber(id)
        if not isElement(client) then return finish(client, "expired") end
        triggerClientEvent(client, "rp:fac:invoice", resourceRoot, {
            from = nameOf(employee), faction = f.name, tag = f.tag, color = f.color,
            amount = amount, concept = concept, seconds = INVOICES.EXPIRE_S, cash = getPlayerMoney(client),
        })
        if isElement(employee) then notify(employee, ("Factura de $%d enviada a %s. Esperando el pago..."):format(amount, nameOf(client)), "info") end
    end, db(), [[INSERT INTO faction_invoices (faction_id, employee_id, employee_name, client_id, client_name, amount, concept)
                 VALUES (?, ?, ?, ?, ?, ?, ?)]], f.id, eid, getPlayerName(employee), cid, getPlayerName(client), amount, concept)
    return true
end

addCommandHandler("facturar", function(player, _, target, amount, ...)
    if not charOf(player) then return end
    local client = target and exports.rp_ids:findPlayer(target)
    if not target or not amount or #{ ... } == 0 then
        return notify(player, "Uso: /facturar <id> <monto> <concepto>  (el cliente debe estar a tu lado)", "info")
    end
    if not client then return notify(player, "No se encontró ese jugador.", "error") end
    local ok, why = bill(player, client, tonumber(amount), table.concat({ ... }, " "))
    if not ok then notify(player, why, "error") end
end)

----------------------------------------------------------------
-- Pagar o rechazar
----------------------------------------------------------------
local function pay(client, inv, method)
    local employee = inv.employee
    local function done()
        local commission = math.floor(inv.amount * inv.commission / 100)
        local toFaction = inv.amount - commission
        resolve(inv.id, "paid", method, commission)
        if toFaction > 0 then
            addFactionFunds(inv.factionId, toFaction, ("Factura #%d de %s a %s: $%d (%s)"):format(inv.id,
                isElement(employee) and getPlayerName(employee) or "?", getPlayerName(client), inv.amount, inv.concept):sub(1, 255))
        end
        if commission > 0 then
            dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", commission, inv.employeeId)
            dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'commission', ?, ?)",
                inv.employeeId, commission, tostring(inv.factionName):sub(1, 32))
        end
        notify(client, ("Pagaste $%d a %s (%s)."):format(inv.amount, inv.factionName, inv.concept), "success")
        if isElement(employee) then
            notify(employee, ("%s pagó la factura de $%d.%s"):format(nameOf(client), inv.amount,
                commission > 0 and (" Tu comisión: $%d al banco."):format(commission) or ""), "success")
            triggerEvent("rp:faction:onInvoicePaid", employee, inv.id, client, inv.amount, commission)
        end
    end

    if method == "cash" then
        if getPlayerMoney(client) < inv.amount then return notify(client, "No llevas tanto efectivo. Prueba con el banco.", "error") end
        takePlayerMoney(client, inv.amount)
        exports.rp_characters:saveCharacter(client)
        finish(client)
        return done()
    end
    -- Banco: cobro atómico
    finish(client)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not affected or affected == 0 then
            resolve(inv.id, "rejected", "bank")
            if isElement(client) then notify(client, "No tienes saldo suficiente en el banco.", "error") end
            if isElement(employee) then notify(employee, "El cliente no tenía saldo en el banco.", "warning") end
            return
        end
        dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'invoice', ?, ?)",
            inv.clientId, inv.amount, tostring(inv.factionName):sub(1, 32))
        if isElement(client) then done() else resolve(inv.id, "paid", "bank", 0) end
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", inv.amount, inv.clientId, inv.amount)
end

addEventHandler("rp:fac:invoiceAnswer", resourceRoot, function(method)
    local client = client
    local inv = pending[client]
    if not inv or not inv.id then return end
    if inv.expires < getTickCount() then
        finish(client, "expired")
        return notify(client, "La factura caducó.", "warning")
    end
    if method ~= "cash" and method ~= "bank" then
        finish(client, "rejected")
        notify(client, "Rechazaste la factura.", "info")
        if isElement(inv.employee) then notify(inv.employee, ("%s rechazó la factura."):format(nameOf(client)), "info") end
        return
    end
    if not isElement(inv.employee) or not near(inv.employee, client) then
        finish(client, "expired")
        return notify(client, "Quien te facturó ya no está a tu lado.", "warning")
    end
    pay(client, inv, method)
end)

-- Caducidad y limpieza
local expireTimer = setTimer(function()
    local now = getTickCount()
    for client, inv in pairs(pending) do
        if inv.id and (inv.expires <= now or not isElement(client)) then
            finish(client, "expired")
            if isElement(inv.employee) then notify(inv.employee, "La factura caducó sin respuesta.", "info") end
        end
    end
end, 2000, 0)

addEventHandler("onPlayerQuit", root, function()
    lastBill[source] = nil
    if pending[source] then finish(source, "expired") end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if isTimer(expireTimer) then killTimer(expireTimer) end
    for client in pairs(pending) do finish(client, "expired") end
end)

----------------------------------------------------------------
-- F3 › Facturas: aporte por miembro y últimas facturas
----------------------------------------------------------------
function sendInvoiceStats(player, f, full)
    if not f then return end
    local cid = charOf(player)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        dbQuery(function(qh2)
            local recent = dbPoll(qh2, 0) or {}
            if not isElement(player) then return end
            local members, list = {}, {}
            for _, r in ipairs(rows) do
                members[#members + 1] = { name = tostring(r.employee_name):gsub("_", " "), total = tonumber(r.total) or 0,
                    count = tonumber(r.n) or 0, commission = tonumber(r.commission) or 0, last = r.last }
            end
            for _, r in ipairs(recent) do
                list[#list + 1] = { id = tonumber(r.id), employee = tostring(r.employee_name):gsub("_", " "),
                    client = tostring(r.client_name):gsub("_", " "), amount = tonumber(r.amount), concept = r.concept,
                    status = r.status, method = r.method or "", date = r.created_at }
            end
            triggerClientEvent(player, "rp:fac:invoices", resourceRoot, { members = members, recent = list, full = full, days = INVOICES.STATS_DAYS })
        end, db(), [[SELECT id, employee_name, client_name, amount, concept, status, method, DATE_FORMAT(created_at, '%d/%m %H:%i') AS created_at
                     FROM faction_invoices WHERE faction_id = ? AND (? = 1 OR employee_id = ?) ORDER BY id DESC LIMIT 25]],
            f.id, full and 1 or 0, cid)
    end, db(), [[SELECT employee_name, SUM(amount) AS total, COUNT(*) AS n, SUM(commission) AS commission,
                        DATE_FORMAT(MAX(resolved_at), '%d/%m %H:%i') AS last
                 FROM faction_invoices
                 WHERE faction_id = ? AND status = 'paid' AND created_at >= NOW() - INTERVAL ? DAY AND (? = 1 OR employee_id = ?)
                 GROUP BY employee_id, employee_name ORDER BY total DESC LIMIT 40]],
        f.id, INVOICES.STATS_DAYS, full and 1 or 0, cid)
end
