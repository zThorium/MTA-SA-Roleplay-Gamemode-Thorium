--[[
    rp_vending / s_vending.lua  (servidor)

    Maquinas expendedoras. Un admin coloca la maquina (objeto del juego) con /crearexpendedora;
    el jugador pulsa E junto a ella, elige un producto en el menu, paga en el datafono (tarjeta
    de rp_bank con clave, o efectivo) y el producto va a su inventario (rp_inventory).

    Flujo y estado (sessions[player].stage):
        rp:vending:open    -> "menu"  (se envia el catalogo de esa maquina)
        rp:vending:choose  -> "pay"   (se envia el datafono con el importe)
        rp:vending:pay     -> "paid"  (cobro; si el item no entra, se devuelve el dinero)
        rp:vending:cancel / alejarse / abatido / salir -> se cierra
    El cliente solo pide: producto, precio y cercania se deciden aqui.

    Admin (catalogo en rp_adminpanel/server/s_catalog.lua):
        /crearexpendedora <bebida|comida>   coloca la maquina delante de ti
        /borrarexpendedora <id>
        /expendedoras                       lista las maquinas
]]

local machines = {}   -- [id] = { row = {...}, col = colshape, obj = object }
local near = {}       -- [player] = machineId
local sessions = {}   -- [player] = { machineId, stage, product }
local cooldown = {}   -- [player] = tick de la ultima accion

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:vending:open", true)
addEvent("rp:vending:choose", true)
addEvent("rp:vending:pay", true)
addEvent("rp:vending:cancel", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function log(msg, level) outputDebugString("[rp_vending] " .. msg, level or 3) end

local PAY_ERRORS = {
    card = "SIN TARJETA", locked = "TARJETA BLOQUEADA", pin = "CLAVE INCORRECTA", funds = "FONDOS INSUFICIENTES",
    cash = "EFECTIVO INSUFICIENTE",
}

local function takeCooldown(p)
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < VENDING.COOLDOWN_MS then return false end
    cooldown[p] = now
    return true
end

local function sameWorld(p, m)
    return getElementDimension(p) == m.row.dimension and getElementInterior(p) == m.row.interior
end

local function isNear(p, m)
    if not m or not sameWorld(p, m) then return false end
    local px, py, pz = getElementPosition(p)
    return getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z + 1) <= VENDING.INTERACT_RADIUS + 0.8
end

local function setNear(p, id)
    near[p] = id
    local m = id and machines[id]
    triggerClientEvent(p, "rp:vending:near", resourceRoot, m and m.row.kind or false)
end

----------------------------------------------------------------
-- Sesion de compra
----------------------------------------------------------------
local function closeSession(p, text, kind)
    local s = sessions[p]
    if not s then return end
    if isTimer(s.timer) then killTimer(s.timer) end
    sessions[p] = nil
    if isElement(p) then
        triggerClientEvent(p, "rp:vending:close", resourceRoot)
        if text then notify(p, text, kind) end
    end
end

-- Motivo por el que el jugador no puede usar la maquina ahora, o nil
local function blockedReason(p)
    if exports.rp_injury:isPlayerDowned(p) then return "No puedes hacer eso ahora." end
    if isPedInVehicle(p) then return "Bájate del vehículo." end
    return nil
end

local function productList(kind)
    local t = VENDING.TYPES[kind]
    return t and t.products or {}
end

addEventHandler("rp:vending:open", resourceRoot, function()
    local p = client
    if not characterOf(p) or sessions[p] or not takeCooldown(p) then return end
    local id = near[p]
    local m = id and machines[id]
    if not isNear(p, m) then return end
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end

    local t = VENDING.TYPES[m.row.kind]
    local list = {}
    for i, prod in ipairs(t.products) do
        local def = exports.rp_inventory:getItemDefinition(prod.item)
        if def then
            local ok, reason = exports.rp_inventory:canCarry(p, prod.item, 1)
            list[#list + 1] = {
                index = i, name = def.name, icon = def.icon, description = def.description or "",
                price = prod.price, canCarry = ok and true or false, reason = reason or "",
            }
        end
    end
    sessions[p] = { machineId = id, stage = "menu" }
    triggerClientEvent(p, "rp:vending:menu", resourceRoot, {
        title = t.name, kind = m.row.kind, products = list,
        cash = getPlayerMoney(p), cards = #(exports.rp_bank:getPlayerCards(p) or {}),
    })
end)

addEventHandler("rp:vending:choose", resourceRoot, function(index)
    local p = client
    local s = sessions[p]
    if not s or s.stage ~= "menu" then return end
    local m = machines[s.machineId]
    if not isNear(p, m) then return closeSession(p) end

    index = tonumber(index)
    local prod = index and productList(m.row.kind)[index]
    local def = prod and exports.rp_inventory:getItemDefinition(prod.item)
    if not def then return end
    local ok, reason = exports.rp_inventory:canCarry(p, prod.item, 1)
    if not ok then return notify(p, reason or "No te cabe en el inventario.", "error") end

    s.stage, s.product = "pay", { item = prod.item, price = prod.price, name = def.name }
    triggerClientEvent(p, "rp:vending:pos", resourceRoot, {
        station = VENDING.TYPES[m.row.kind].name, product = def.name, amount = prod.price,
        cards = exports.rp_bank:getPlayerCards(p) or {}, cash = getPlayerMoney(p),
    })
end)

-- Devuelve lo cobrado si la entrega falla (efectivo a la mano, tarjeta a la cuenta del titular)
local function refund(p, method, ownerId, amount)
    if method == "cash" then
        givePlayerMoney(p, amount)
        exports.rp_characters:saveCharacter(p)
    else
        dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", amount, ownerId)
        dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'refund', ?, ?)",
            ownerId, amount, "Expendedora")
    end
    log(("reembolso de $%d a %s (%s)"):format(amount, getPlayerName(p), method), 2)
end

addEventHandler("rp:vending:pay", resourceRoot, function(method, ownerId, pin)
    local p = client
    local s = sessions[p]
    if not s or s.stage ~= "pay" or s.paying then return end
    local m = machines[s.machineId]
    if not isNear(p, m) or blockedReason(p) then return closeSession(p) end
    method = method == "cash" and "cash" or "card"
    local prod = s.product
    if not exports.rp_inventory:canCarry(p, prod.item, 1) then
        return closeSession(p, "No te cabe en el inventario.", "error")
    end

    -- 1) Cobrar
    s.paying = true
    local ok, reason
    if method == "cash" then
        if getPlayerMoney(p) >= prod.price then
            takePlayerMoney(p, prod.price)
            exports.rp_characters:saveCharacter(p)
            ok = true
        else
            reason = "cash"
        end
    else
        ownerId = tonumber(ownerId)
        if type(pin) ~= "string" or not pin:match("^%d%d%d%d$") or not ownerId then
            ok, reason = false, "pin"
        else
            ok, reason = exports.rp_bank:payWithCard(p, ownerId, pin, prod.price, VENDING.TYPES[m.row.kind].name)
        end
    end
    s.paying = nil
    triggerClientEvent(p, "rp:vending:payResult", resourceRoot, ok and true or false,
        ok and "APROBADO" or (PAY_ERRORS[reason] or "RECHAZADO"), method == "cash")
    if not ok then return end

    -- 2) Entregar (si falla, se devuelve el dinero)
    local given, why = exports.rp_inventory:giveItem(p, prod.item, 1)
    if not given then
        refund(p, method, ownerId, prod.price)
        return closeSession(p, (why or "No se pudo entregar el producto.") .. " Se te devolvio el dinero.", "error")
    end
    s.stage = "paid"
    -- El producto ya está en el inventario; el timer solo deja ver la boleta antes de cerrar
    s.timer = setTimer(function()
        s.timer = nil
        if not isElement(p) or sessions[p] ~= s then return end
        closeSession(p, ("Compraste %s por $%d. Está en tu inventario."):format(prod.name, prod.price), "success")
        if not isPedInVehicle(p) then setPedAnimation(p, "VENDING", "VEND_Use", 1600, false, false, false, false) end
    end, VENDING.CLOSE_AFTER_PAY_MS, 1)
end)

addEventHandler("rp:vending:cancel", resourceRoot, function()
    local p = client
    local s = sessions[p]
    if s and s.stage ~= "paid" and not s.paying then closeSession(p) end
end)

----------------------------------------------------------------
-- Mundo
----------------------------------------------------------------
local function spawnMachine(row)
    local t = VENDING.TYPES[row.kind]
    local obj = createObject(t.model, row.x, row.y, row.z + t.zOffset, 0, 0, row.rot)
    setElementInterior(obj, row.interior)
    setElementDimension(obj, row.dimension)
    setElementFrozen(obj, true)
    local col = createColSphere(row.x, row.y, row.z + 1, VENDING.INTERACT_RADIUS + 0.6)
    setElementInterior(col, row.interior)
    setElementDimension(col, row.dimension)
    machines[row.id] = { row = row, col = col, obj = obj }
    setElementData(col, "rp:vendingId", row.id, false)
    -- Rehidratar: quien ya estuviera dentro no dispara onColShapeHit (CIC-03)
    for _, p in ipairs(getElementsWithinColShape(col, "player")) do
        if sameWorld(p, machines[row.id]) and characterOf(p) then setNear(p, row.id) end
    end
end

local function destroyMachine(id)
    local m = machines[id]
    if not m then return end
    for p, nid in pairs(near) do if nid == id and isElement(p) then setNear(p, nil) end end
    for p, s in pairs(sessions) do if s.machineId == id then closeSession(p) end end
    if isElement(m.col) then destroyElement(m.col) end
    if isElement(m.obj) then destroyElement(m.obj) end
    machines[id] = nil
end

addEventHandler("onColShapeHit", resourceRoot, function(el, matchingDim)
    if getElementType(el) ~= "player" or not matchingDim then return end
    local id = getElementData(source, "rp:vendingId")
    local m = id and machines[id]
    if m and sameWorld(el, m) and characterOf(el) then setNear(el, id) end
end)

addEventHandler("onColShapeLeave", resourceRoot, function(el)
    if getElementType(el) ~= "player" then return end
    local id = getElementData(source, "rp:vendingId")
    if near[el] == id then setNear(el, nil) end
    local s = sessions[el]
    if s and s.machineId == id and s.stage ~= "paid" and not s.paying then closeSession(el) end
end)

local function clearPlayer(p)
    closeSession(p)
    near[p] = nil
end

addEventHandler("onPlayerQuit", root, function() sessions[source] = nil; near[source] = nil; cooldown[source] = nil end)
addEventHandler("rp:onCharacterLogout", root, function() clearPlayer(source) end)
addEventHandler("rp:onPlayerDowned", root, function() closeSession(source) end)
addEventHandler("onPlayerWasted", root, function() closeSession(source) end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
local KIND_BY_WORD = { bebida = "drink", bebidas = "drink", comida = "food", snacks = "food" }

addCommandHandler("crearexpendedora", function(p, _, word)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    local kind = KIND_BY_WORD[tostring(word):lower()]
    if not kind then return notify(p, "Uso: /crearexpendedora <bebida|comida> (la maquina aparece delante de ti)", "warning") end
    local x, y, z = getElementPosition(p)
    local _, _, rot = getElementRotation(p)
    -- Delante del admin, en el suelo y mirandolo (como /crearatm)
    local d = VENDING.PLACE_DISTANCE
    local mx, my, mz = x - math.sin(math.rad(rot)) * d, y + math.cos(math.rad(rot)) * d, z - 1
    local mrot = (rot + 180) % 360
    local interior, dimension = getElementInterior(p), getElementDimension(p)
    dbQuery(function(qh)
        local result, _, insertId = dbPoll(qh, 0)
        if not result or not insertId then return log("Error al insertar maquina", 1) end
        spawnMachine({ id = insertId, kind = kind, x = mx, y = my, z = mz, rot = mrot, interior = interior, dimension = dimension })
        if isElement(p) then notify(p, ("%s #%d creada."):format(VENDING.TYPES[kind].name, insertId), "success") end
    end, db(), "INSERT INTO vending_machines (kind, x, y, z, rot, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?)",
        kind, mx, my, mz, mrot, interior, dimension)
end)

addCommandHandler("borrarexpendedora", function(p, _, id)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not machines[id] then return notify(p, "Uso: /borrarexpendedora <id>", "warning") end
    destroyMachine(id)
    dbExec(db(), "DELETE FROM vending_machines WHERE id = ?", id)
    notify(p, ("Expendedora #%d eliminada."):format(id), "success")
end)

addCommandHandler("expendedoras", function(p)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    local n = 0
    for id, m in pairs(machines) do
        n = n + 1
        outputChatBox(("#%d %s (%.0f, %.0f, %.0f) int %d dim %d"):format(
            id, VENDING.TYPES[m.row.kind].name, m.row.x, m.row.y, m.row.z, m.row.interior, m.row.dimension), p)
    end
    notify(p, n .. " expendedoras (detalle en el chat).", "info")
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local n = 0
        for _, row in ipairs(rows) do
            if VENDING.TYPES[row.kind] then spawnMachine(row); n = n + 1 end
        end
        log(("%d expendedoras cargadas"):format(n))
    end, db(), "SELECT id, kind, x, y, z, rot, interior, dimension FROM vending_machines")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(sessions) do if isElement(p) then triggerClientEvent(p, "rp:vending:close", resourceRoot) end end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
-- Copia de los tipos de maquina y sus productos (la usa rp_test para validar el catalogo)
function getVendingTypes()
    local out = {}
    for kind, t in pairs(VENDING.TYPES) do
        local products = {}
        for i, p in ipairs(t.products) do products[i] = { item = p.item, price = p.price } end
        out[kind] = { name = t.name, model = t.model, products = products }
    end
    return out
end
