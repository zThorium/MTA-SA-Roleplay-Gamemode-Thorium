--[[
    rp_bank / s_bank.lua
    Cuenta bancaria por personaje (characters.bank_money) e historial en
    bank_transactions. Reglas:
      - Depositar: desde un cajero o desde la app Banco del telefono.
      - Retirar: SOLO en un cajero.
      - Transferir: desde cajero o telefono, a cualquier personaje por su nombre.

    Exports (servidor):
        getBalance(player)                       -> saldo (sincrono)
        deposit(player, amount, source)          -> (async) notifica al jugador
        transfer(player, targetName, amount, source)
        sendBankData(player, view)               -> envia saldo + historial al cliente
        isNearATM(player)                        -> bool

    Admin: /crearatm (en tu posicion), /borraratm <id>
]]

local ATM_MODEL = 2942
local ATM_RADIUS = 1.6
local MAX_AMOUNT = 10000000

local atms = {}      -- [id] = { object, col }
local nearAtm = {}   -- [player] = atmId
local busy = {}      -- [player] = true durante una operacion

addEvent("rp:bank:open", true)
addEvent("rp:bank:deposit", true)
addEvent("rp:bank:withdraw", true)
addEvent("rp:bank:transfer", true)
addEvent("rp:onDatabaseReady", false)

local function db() return exports.rp_database:getConnection() end
local function notify(player, text, kind) exports.rp_notify:notify(player, text, kind) end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end

local function validAmount(n)
    return type(n) == "number" and n >= 1 and n <= MAX_AMOUNT and n == math.floor(n)
end

local function logTx(characterId, kind, amount, other)
    dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, ?, ?, ?)",
        characterId, kind, amount, other or "")
end

----------------------------------------------------------------
-- Cajeros
----------------------------------------------------------------
local function spawnATM(row)
    local id = tonumber(row.id)
    local obj = createObject(ATM_MODEL, row.x, row.y, row.z, 0, 0, row.rotation)
    setElementInterior(obj, row.interior)
    setElementDimension(obj, row.dimension)
    setElementData(obj, "rp:atm", id)
    local col = createColSphere(row.x, row.y, row.z + 1, ATM_RADIUS)
    setElementInterior(col, row.interior)
    setElementDimension(col, row.dimension)
    atms[id] = { object = obj, col = col }

    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if getElementType(el) == "player" and sameDim and characterOf(el) then
            nearAtm[el] = id
            triggerClientEvent(el, "rp:bank:nearATM", resourceRoot, true)
        end
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and nearAtm[el] == id then
            nearAtm[el] = nil
            triggerClientEvent(el, "rp:bank:nearATM", resourceRoot, false)
        end
    end)
end

local function createATM(x, y, z, rot, interior, dimension, callback)
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if ok then
            spawnATM({ id = id, x = x, y = y, z = z, rotation = rot, interior = interior, dimension = dimension })
        end
        if callback then callback(ok and id) end
    end, db(), "INSERT INTO atms (x, y, z, rotation, interior, dimension) VALUES (?, ?, ?, ?, ?, ?)", x, y, z, rot, interior, dimension)
end

local function loadATMs()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then
            -- Cajero inicial junto al punto de aparicion (z = pies; el cliente lo ajusta al suelo)
            return createATM(1739.6, -1857.2, 12.6, 180, 0, 0)
        end
        for _, row in ipairs(rows) do spawnATM(row) end
    end, db(), "SELECT * FROM atms")
end

function isNearATM(player)
    local id = nearAtm[player]
    local atm = id and atms[id]
    if not atm or not isElement(atm.object) then return false end
    if getElementDimension(player) ~= getElementDimension(atm.object) then return false end
    local px, py, pz = getElementPosition(player)
    local ax, ay, az = getElementPosition(atm.object)
    return getDistanceBetweenPoints3D(px, py, pz, ax, ay, az) <= ATM_RADIUS + 2
end

----------------------------------------------------------------
-- Datos para la interfaz
----------------------------------------------------------------
-- Sincrona: las funciones (callbacks) no se pueden pasar por exports
function getBalance(player)
    local characterId = characterOf(player)
    if not characterId then return false end
    local rows = dbPoll(dbQuery(db(), "SELECT bank_money FROM characters WHERE id = ?", characterId), -1)
    return rows and rows[1] and tonumber(rows[1].bank_money) or 0
end

-- view: "atm" (cajero) o "phone" (app del telefono)
function sendBankData(player, view)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        local balance = tonumber(rows[1] and rows[1].bank_money) or 0
        dbQuery(function(qh2)
            local history = dbPoll(qh2, 0) or {}
            if not isElement(player) then return end
            triggerClientEvent(player, "rp:bank:data", root, view, {
                name = (getPlayerName(player):gsub("_", " ")),
                balance = balance, cash = getPlayerMoney(player), history = history,
                canWithdraw = view == "atm" and isNearATM(player),
            })
        end, db(), [[
            SELECT type, amount, other_name, DATE_FORMAT(created_at, '%d/%m %H:%i') AS date
            FROM bank_transactions WHERE character_id = ? ORDER BY id DESC LIMIT 12
        ]], characterId)
    end, db(), "SELECT bank_money FROM characters WHERE id = ?", characterId)
end

----------------------------------------------------------------
-- Operaciones
----------------------------------------------------------------
local function finish(player, view, ok, message)
    busy[player] = nil
    if not isElement(player) then return end
    notify(player, message, ok and "success" or "error")
    exports.rp_characters:saveCharacter(player)
    sendBankData(player, view)
end

function deposit(player, amount, view)
    local characterId = characterOf(player)
    if not characterId or busy[player] then return end
    if not validAmount(amount) then return notify(player, "Cantidad no valida.", "error") end
    if getPlayerMoney(player) < amount then return notify(player, "No llevas tanto dinero en efectivo.", "error") end

    busy[player] = true
    takePlayerMoney(player, amount)
    dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", amount, characterId)
    logTx(characterId, "deposit", amount)
    finish(player, view, true, ("Depositaste $%d en tu cuenta."):format(amount))
end

local function withdraw(player, amount)
    local characterId = characterOf(player)
    if not characterId or busy[player] then return end
    if not isNearATM(player) then return notify(player, "Solo puedes retirar dinero en un cajero.", "error") end
    if not validAmount(amount) then return notify(player, "Cantidad no valida.", "error") end

    busy[player] = true
    -- Descuento atomico: solo afecta la fila si hay saldo suficiente
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(player) then return end
        if affected and affected > 0 then
            givePlayerMoney(player, amount)
            logTx(characterId, "withdraw", amount)
            finish(player, "atm", true, ("Retiraste $%d."):format(amount))
        else
            finish(player, "atm", false, "Saldo insuficiente.")
        end
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, characterId, amount)
end

function transfer(player, targetName, amount, view)
    local characterId = characterOf(player)
    if not characterId or busy[player] then return end
    if not validAmount(amount) then return notify(player, "Cantidad no valida.", "error") end
    if type(targetName) ~= "string" or #targetName < 3 or #targetName > 32 then
        return notify(player, "Escribe el nombre del destinatario (Nombre Apellido).", "error")
    end
    targetName = targetName:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "_")

    busy[player] = true
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        local target = rows[1]
        if not target then return finish(player, view, false, "No existe ningun personaje con ese nombre.") end
        if tonumber(target.id) == characterId then return finish(player, view, false, "No puedes transferirte a ti mismo.") end

        dbQuery(function(qh2)
            local _, affected = dbPoll(qh2, 0)
            if not isElement(player) then return end
            if not affected or affected == 0 then return finish(player, view, false, "Saldo insuficiente.") end

            dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", amount, target.id)
            local myName = getPlayerName(player)
            logTx(characterId, "transfer_out", amount, target.name)
            logTx(target.id, "transfer_in", amount, myName)
            finish(player, view, true, ("Transferiste $%d a %s."):format(amount, (target.name:gsub("_", " "))))

            -- Aviso al destinatario si esta conectado
            for _, p in ipairs(getElementsByType("player")) do
                if characterOf(p) == tonumber(target.id) then
                    exports.rp_notify:notify(p, ("Recibiste una transferencia de $%d de %s."):format(amount, (myName:gsub("_", " "))), "success")
                end
            end
        end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, characterId, amount)
    end, db(), "SELECT id, name FROM characters WHERE name = ? LIMIT 1", targetName)
end

----------------------------------------------------------------
-- Eventos de la interfaz
----------------------------------------------------------------
addEventHandler("rp:bank:open", root, function(view)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    view = view == "phone" and "phone" or "atm"
    if view == "atm" and not isNearATM(client) then return end
    sendBankData(client, view)
end)

addEventHandler("rp:bank:deposit", root, function(amount, view)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    view = view == "phone" and "phone" or "atm"
    if view == "phone" and not exports.rp_inventory:hasItem(client, "phone", 1) then return end
    if view == "atm" and not isNearATM(client) then return end
    deposit(client, tonumber(amount), view)
end)

addEventHandler("rp:bank:withdraw", root, function(amount)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    withdraw(client, tonumber(amount))
end)

addEventHandler("rp:bank:transfer", root, function(targetName, amount, view)
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    view = view == "phone" and "phone" or "atm"
    if view == "phone" and not exports.rp_inventory:hasItem(client, "phone", 1) then return end
    if view == "atm" and not isNearATM(client) then return end
    transfer(client, targetName, tonumber(amount), view)
end)

addEventHandler("onPlayerQuit", root, function()
    nearAtm[source], busy[source] = nil, nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadATMs() else addEventHandler("rp:onDatabaseReady", root, loadATMs) end
end)

----------------------------------------------------------------
-- Administracion
----------------------------------------------------------------
local function isAdmin(player)
    return (exports.rp_login:getPlayerAdminLevel(player) or 0) >= 1
end

addCommandHandler("crearatm", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    -- El cajero se coloca 1 m delante del jugador, mirando hacia el
    local fx, fy = x - math.sin(math.rad(rot)), y + math.cos(math.rad(rot))
    createATM(fx, fy, z - 1, rot + 180, getElementInterior(player), getElementDimension(player), function(id)
        if id then notify(player, ("Cajero #%d creado."):format(id), "success") end
    end)
end)

addCommandHandler("borraratm", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    local atm = id and atms[id]
    if not atm then return notify(player, "Uso: /borraratm <id>", "warning") end
    for _, el in pairs(atm) do if isElement(el) then destroyElement(el) end end
    atms[id] = nil
    dbExec(db(), "DELETE FROM atms WHERE id = ?", id)
    notify(player, ("Cajero #%d eliminado."):format(id), "success")
end)

-- /dardinero <id o nombre> <cantidad>  (admin) ingresa dinero en la cuenta bancaria
addCommandHandler("dardinero", function(player, _, query, amount)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    amount = tonumber(amount)
    local target = query and exports.rp_ids:findPlayer(query)
    local characterId = target and characterOf(target)
    if not characterId or not amount or amount == 0 or amount ~= math.floor(amount) then
        return notify(player, "Uso: /dardinero <id o nombre> <cantidad>", "warning")
    end
    dbExec(db(), "UPDATE characters SET bank_money = GREATEST(0, bank_money + ?) WHERE id = ?", amount, characterId)
    logTx(characterId, amount > 0 and "deposit" or "withdraw", math.abs(amount), "Administracion")
    notify(player, ("Ingresaste $%d en la cuenta de %s."):format(amount, (getPlayerName(target):gsub("_", " "))), "success")
    notify(target, ("Un administrador ingreso $%d en tu cuenta bancaria."):format(amount), "info")
end)