--[[
    rp_bank / s_cards.lua
    Tarjeta de debito de cada personaje (tabla bank_cards). Se crea sola con un
    numero de 16 digitos y una clave de 4 digitos al entrar al juego, y se entrega
    como item "bcard:<id del personaje>" en el inventario. En el inventario todos
    ven de quien es la tarjeta, pero el numero y la clave solo los ve su dueno.
    Si el personaje la pierde, el cajero le entrega otra al abrirlo.

    Exports (servidor):
        getPlayerCards(player)                            -> { { owner, holder, last4 }, ... }
        payWithCard(player, ownerId, pin, amount, concept) -> true | false, motivo
        chargeAccount(characterId, amount, concept)       -> true | false   (sin tarjeta: cobros forzosos)
]]

local MAX_PIN_ERRORS = 3
local PIN_LOCK_MS = 5 * 60 * 1000

local cards = {}       -- [characterId] = { number, pin, holder }
local pinErrors = {}   -- [player] = { count, until }

local function db() return exports.rp_database:getConnection() end
local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end

local function cardItem(characterId) return "bcard:" .. tostring(characterId) end

local function grouped(number)
    return number:sub(1, 4) .. " " .. number:sub(5, 8) .. " " .. number:sub(9, 12) .. " " .. number:sub(13, 16)
end

-- Numero con digito de control (Luhn), empieza en 4
local function newCardNumber()
    local digits = { 4 }
    for i = 2, 15 do digits[i] = math.random(0, 9) end
    local sum = 0
    for i = 15, 1, -1 do
        local d = digits[i]
        if (15 - i) % 2 == 0 then d = d * 2 if d > 9 then d = d - 9 end end
        sum = sum + d
    end
    digits[16] = (10 - sum % 10) % 10
    return table.concat(digits)
end

local function labelCard(characterId)
    local card = cards[characterId]
    if not card then return end
    local holder = card.holder:gsub("_", " ")
    exports.rp_inventory:setItemLabel(cardItem(characterId), "Tarjeta de debito - " .. holder,
        ("Tarjeta de debito a nombre de %s. Sirve para pagar en los datafonos (p. ej. en la bencinera)."):format(holder),
        ("Numero: %s. Clave: %s (solo tu la ves)."):format(grouped(card.number), card.pin), characterId)
end

-- Pone la tarjeta en el inventario si no la tiene. El inventario se carga de
-- forma asincrona al aparecer, asi que se reintenta unas veces.
local function deliverCard(player, characterId, tries)
    tries = tries or 0
    if not isElement(player) or characterOf(player) ~= characterId or not cards[characterId] then return end
    local item = cardItem(characterId)
    if exports.rp_inventory:hasItem(player, item, 1) then return true end
    local ok = exports.rp_inventory:giveItem(player, item, 1)
    if ok then
        exports.rp_notify:notify(player, "Tienes tu tarjeta de debito en el inventario (I). Ahi puedes ver su numero y su clave.", "info")
        return true
    end
    if tries < 5 then setTimer(deliverCard, 3000, 1, player, characterId, tries + 1) end
    return false
end

local function ensureCard(player, characterId)
    if cards[characterId] then
        labelCard(characterId)
        return setTimer(deliverCard, 2500, 1, player, characterId)
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId then return end
        local row = rows[1]
        if row then
            cards[characterId] = { number = row.number, pin = row.pin, holder = row.holder }
            labelCard(characterId)
            return setTimer(deliverCard, 2500, 1, player, characterId)
        end
        local card = { number = newCardNumber(), pin = ("%04d"):format(math.random(0, 9999)), holder = getPlayerName(player) }
        dbQuery(function(qh2)
            local ok = dbPoll(qh2, 0)
            if not ok or not isElement(player) then return end
            cards[characterId] = card
            labelCard(characterId)
            setTimer(deliverCard, 2500, 1, player, characterId)
        end, db(), "INSERT INTO bank_cards (character_id, number, pin, holder) VALUES (?, ?, ?, ?)",
            characterId, card.number, card.pin, card.holder)
    end, db(), "SELECT number, pin, holder FROM bank_cards WHERE character_id = ?", characterId)
end

addEvent("rp:onCharacterSpawn", false)
addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    ensureCard(source, tonumber(characterId))
end)

-- Al abrir un cajero: si perdiste la tarjeta, te dan otra (misma cuenta y clave)
addEventHandler("rp:bank:open", root, function(view)
    local characterId = characterOf(client)
    if characterId and view ~= "phone" and cards[characterId] then deliverCard(client, characterId, 5) end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    math.randomseed(getRealTime().timestamp)
    for _, player in ipairs(getElementsByType("player")) do
        local characterId = characterOf(player)
        if characterId then ensureCard(player, characterId) end
    end
end)

-- Si rp_inventory se reinicia pierde los textos de las tarjetas
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rp_inventory" then return end
    for characterId in pairs(cards) do labelCard(characterId) end
end)

addEventHandler("onPlayerQuit", root, function() pinErrors[source] = nil end)

----------------------------------------------------------------
-- Pagos
----------------------------------------------------------------
local function cardRow(characterId)
    characterId = tonumber(characterId)
    if not characterId then return nil end
    if cards[characterId] then return cards[characterId] end
    local rows = dbPoll(dbQuery(db(), "SELECT number, pin, holder FROM bank_cards WHERE character_id = ?", characterId), -1)
    local row = rows and rows[1]
    if row then cards[characterId] = { number = row.number, pin = row.pin, holder = row.holder } end
    return cards[characterId]
end

-- Tarjetas que el jugador lleva en el inventario (la suya y las de otros)
function getPlayerCards(player)
    local out = {}
    local inv = exports.rp_inventory:getInventory(player) or {}
    for itemId in pairs(inv) do
        local owner = tonumber(itemId:match("^bcard:(%d+)$"))
        local card = owner and cardRow(owner)
        if card then
            out[#out + 1] = { owner = owner, holder = (card.holder:gsub("_", " ")), last4 = card.number:sub(-4) }
        end
    end
    table.sort(out, function(a, b) return a.owner < b.owner end)
    return out
end

-- Sincrona (dbPoll con espera): las funciones no se pueden pasar por exports
function chargeAccount(characterId, amount, concept)
    characterId, amount = tonumber(characterId), tonumber(amount)
    if not characterId or not amount or amount < 1 then return false end
    amount = math.floor(amount)
    local _, affected = dbPoll(dbQuery(db(),
        "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, characterId, amount), -1)
    if not affected or affected == 0 then return false end
    dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'purchase', ?, ?)",
        characterId, amount, tostring(concept or "Compra"):sub(1, 32))
    return true
end

-- motivo: "card" (no la lleva), "locked" (demasiados errores), "pin", "funds"
function payWithCard(player, ownerId, pin, amount, concept)
    ownerId = tonumber(ownerId)
    if not ownerId or not exports.rp_inventory:hasItem(player, cardItem(ownerId), 1) then return false, "card" end
    local card = cardRow(ownerId)
    if not card then return false, "card" end
    local errors = pinErrors[player]
    if errors and errors.untilTick and getTickCount() < errors.untilTick then return false, "locked" end
    if tostring(pin) ~= card.pin then
        errors = errors or { count = 0 }
        errors.count = errors.count + 1
        if errors.count >= MAX_PIN_ERRORS then errors.count, errors.untilTick = 0, getTickCount() + PIN_LOCK_MS end
        pinErrors[player] = errors
        return false, errors.untilTick and getTickCount() < errors.untilTick and "locked" or "pin"
    end
    pinErrors[player] = nil
    if not chargeAccount(ownerId, amount, concept) then return false, "funds" end
    -- Aviso al titular si es otra persona y esta conectada
    if ownerId ~= characterOf(player) then
        for _, p in ipairs(getElementsByType("player")) do
            if characterOf(p) == ownerId then
                exports.rp_notify:notify(p, ("Se pago $%d con tu tarjeta en %s."):format(amount, tostring(concept)), "warning")
            end
        end
    end
    return true
end
