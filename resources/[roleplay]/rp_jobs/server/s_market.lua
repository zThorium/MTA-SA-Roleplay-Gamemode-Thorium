--[[
    rp_jobs / s_market.lua

    Puntos de venta de productos (lonja, peletería, fundición, compraventa) con precios
    dinámicos: cada MARKET.TICK_MIN minutos el precio de cada producto sube o baja al azar,
    y cada unidad vendida lo baja un poco (si todos venden atún, el atún vale menos).
    Con el tiempo vuelve hacia el precio base. Los factores viven en memoria.

    Se vende con E en el marcador del punto de venta (cualquiera puede vender, tenga o no
    el trabajo: así se puede rolear la reventa).
]]

local factors = {}   -- [marketId][itemId] = factor
local trends = {}    -- [marketId][itemId] = -1 | 0 | 1 (último cambio)
local cooldown = {}

addEvent("rp:jobs:openMarket", true)
addEvent("rp:jobs:sell", true)
-- Aviso para otros recursos tras una venta (source = jugador): (marketId, itemId, cantidad, total cobrado).
-- Lo usa rp_metaldetector para el dinero ganado del buscador.
addEvent("rp:jobs:onMarketSale", false)

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end

local function clampFactor(f) return math.max(MARKET.MIN_FACTOR, math.min(MARKET.MAX_FACTOR, f)) end

local function init()
    for _, m in ipairs(MARKETS) do
        factors[m.id], trends[m.id] = {}, {}
        for itemId in pairs(m.items) do
            factors[m.id][itemId] = clampFactor(0.9 + math.random() * 0.2)
            trends[m.id][itemId] = 0
        end
    end
end

local function tick()
    for _, m in ipairs(MARKETS) do
        for itemId in pairs(m.items) do
            local f = factors[m.id][itemId]
            local before = f
            f = f + (1 - f) * MARKET.RECOVERY                       -- vuelve hacia el precio base
            f = f + (math.random() * 2 - 1) * MARKET.DRIFT          -- y se mueve al azar
            f = clampFactor(f)
            factors[m.id][itemId] = f
            trends[m.id][itemId] = (f > before + 0.005) and 1 or ((f < before - 0.005) and -1 or 0)
        end
    end
end

function getMarketPrice(marketId, itemId)
    local m = MARKETS_BY_ID[marketId]
    local base = m and m.items[itemId]
    if not base then return false end
    return math.max(1, math.floor(base * factors[marketId][itemId] + 0.5))
end

local function marketData(player, m)
    local rows = {}
    for itemId, base in pairs(m.items) do
        local def = exports.rp_inventory:getItemDefinition(itemId)
        rows[#rows + 1] = {
            id = itemId, name = def and def.name or itemId, icon = def and def.icon or "📦",
            price = getMarketPrice(m.id, itemId), base = base, trend = trends[m.id][itemId],
            have = exports.rp_inventory:getItemAmount(player, itemId) or 0,
        }
    end
    table.sort(rows, function(a, b)
        if (a.have > 0) ~= (b.have > 0) then return a.have > 0 end
        return a.base < b.base
    end)
    return { id = m.id, name = m.name, icon = m.icon, items = rows, money = getPlayerMoney(player) }
end

local function nearMarket(player, m, radius)
    if getElementInterior(player) ~= (m.interior or 0) or getElementDimension(player) ~= (m.dimension or 0) then return false end
    local x, y, z = getElementPosition(player)
    return ((x - m.x) ^ 2 + (y - m.y) ^ 2) <= radius * radius and math.abs(z - m.z) <= 12
end

addEventHandler("rp:jobs:openMarket", resourceRoot, function(marketId)
    local player = client
    local m = MARKETS_BY_ID[marketId]
    if not m or not exports.rp_characters:getPlayerCharacterId(player) or getElementData(player, "rp:downed") then return end
    if not nearMarket(player, m, 4) then return end
    triggerClientEvent(player, "rp:jobs:market", resourceRoot, marketData(player, m))
end)

addEventHandler("rp:jobs:sell", resourceRoot, function(marketId, itemId, amount)
    local player = client
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 400 then return end
    cooldown[player] = now

    local m = MARKETS_BY_ID[marketId]
    amount = tonumber(amount)
    if not m or type(itemId) ~= "string" or not m.items[itemId] then return end
    if not amount or amount < 1 or amount > 100 or amount ~= math.floor(amount) then return end
    if not exports.rp_characters:getPlayerCharacterId(player) or getElementData(player, "rp:downed") then return end
    if not nearMarket(player, m, 5) then return notify(player, "Acércate al mostrador.", "warning") end

    local have = exports.rp_inventory:getItemAmount(player, itemId) or 0
    amount = math.min(amount, have)
    if amount < 1 then return notify(player, "No tienes eso.", "error") end

    -- Se cobra unidad a unidad: cada una baja un poco el precio de la siguiente
    local total = 0
    for _ = 1, amount do
        total = total + getMarketPrice(m.id, itemId)
        factors[m.id][itemId] = clampFactor(factors[m.id][itemId] - MARKET.SATURATION)
    end
    trends[m.id][itemId] = -1
    local ok = exports.rp_inventory:takeItem(player, itemId, amount)
    if not ok then return notify(player, "No se pudo completar la venta.", "error") end
    givePlayerMoney(player, total)
    exports.rp_characters:saveCharacter(player)
    triggerEvent("rp:jobs:onMarketSale", player, m.id, itemId, amount, total)
    exports.rp_notify:notify(player, ("Vendiste %dx %s por $%d."):format(amount, Jobs.itemName(itemId), total), "success")
    triggerClientEvent(player, "rp:jobs:market", resourceRoot, marketData(player, m))
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)

addEventHandler("onResourceStart", resourceRoot, function()
    init()
    setTimer(tick, MARKET.TICK_MIN * 60 * 1000, 0)
end)
