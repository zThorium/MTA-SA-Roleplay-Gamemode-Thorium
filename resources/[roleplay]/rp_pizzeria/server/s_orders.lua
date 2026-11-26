--[[
    rp_pizzeria / s_orders.lua
    Generacion de pedidos y evaluacion de cada pizza. Todo lo decide el servidor:
    el cliente solo manda lo que armo (posiciones de ingredientes, cobertura de salsa y queso)
    y los cortes; el horno y la freidora se miden con los tiempos del servidor.
]]
Pizzeria = Pizzeria or {}

local C = PIZZERIA
local random = math.random

local function clamp01(v) return math.max(0, math.min(1, v)) end

local function pick(list) return list[random(#list)] end

----------------------------------------------------------------
-- Pedidos
----------------------------------------------------------------
function Pizzeria.difficulty(level)
    return C.DIFFICULTY[math.max(1, math.min(#C.DIFFICULTY, level or 1))]
end

-- Pedido del tutorial: facil y sin prisa (4 pepperoni en toda la pizza, normal, 4 trozos)
local function tutorialOrder(S)
    S.nextId = S.nextId + 1
    local now = getTickCount()
    return {
        id = S.nextId, name = "Rosa", skin = 12, status = "queue", stage = "new",
        spawnedAt = now, arriveAt = now + C.ARRIVE_MS, minArriveAt = now + math.floor(C.ARRIVE_MS * C.MIN_ARRIVE_FRACTION),
        patience = C.TUTORIAL_PATIENCE_MS,
        pizza = { toppings = { { id = "pepperoni", count = 4, zone = "whole" } }, bake = "normal", slices = 4 },
        side = nil, sideState = nil, score = {},
    }
end

function Pizzeria.newOrder(S)
    if S.tutorial then return tutorialOrder(S) end
    local diff = Pizzeria.difficulty(S.level)
    local pool = {}
    for _, t in ipairs(C.TOPPINGS) do
        if t.level <= S.level then pool[#pool + 1] = t.id end
    end
    -- ingredientes distintos, sin repetir
    local nTypes = math.min(#pool, random(diff.types[1], diff.types[2]))
    local toppings = {}
    for _ = 1, nTypes do
        local i = random(#pool)
        local zone = "whole"
        if random() < diff.halfChance then zone = random() < 0.5 and "left" or "right" end
        toppings[#toppings + 1] = { id = pool[i], count = pick(C.COUNTS), zone = zone }
        table.remove(pool, i)
    end

    local bake = "normal"
    if diff.bakeVariants then bake = pick({ "poco", "normal", "normal", "bien" }) end
    local side = nil
    if random() < diff.sideChance then side = random() < 0.5 and "fries" or "garlic" end

    S.nextId = S.nextId + 1
    local patience = C.PATIENCE_MS + nTypes * 20000 + (side and 25000 or 0)
    patience = math.floor(patience * (1 - 0.05 * (S.level - 1)))
    local now = getTickCount()
    return {
        id = S.nextId,
        name = pick(C.NAMES),
        skin = pick(C.SKINS),
        status = "queue",          -- queue -> waiting
        stage = "new",             -- new -> assembled -> baking -> baked -> boxed
        spawnedAt = now,
        arriveAt = now + C.ARRIVE_MS,                                            -- respaldo si el cliente no avisa
        minArriveAt = now + math.floor(C.ARRIVE_MS * C.MIN_ARRIVE_FRACTION),     -- antes de esto no se acepta el aviso
        patience = patience,
        pizza = { toppings = toppings, bake = bake, slices = pick(C.SLICES) },
        side = side,
        sideState = nil,           -- nil -> frying -> done
        score = {},
    }
end

----------------------------------------------------------------
-- Evaluacion
----------------------------------------------------------------
-- placements: { { t = id, x, y } } normalizado al centro de la pizza (radio 1)
-- Devuelve nota 0..1 y la lista saneada para dibujarla luego en el corte.
function Pizzeria.scoreAssembly(order, sauce, cheese, placements)
    local clean, byType = {}, {}
    for _, p in ipairs(placements) do
        local x, y = tonumber(p.x), tonumber(p.y)
        if type(p.t) == "string" and C.TOPPING_BY_ID[p.t] and x and y and x * x + y * y <= 1.05 then
            clean[#clean + 1] = { t = p.t, x = math.floor(x * 1000) / 1000, y = math.floor(y * 1000) / 1000 }
            local b = byType[p.t] or { left = 0, right = 0, total = 0 }
            if x < -0.08 then b.left = b.left + 1 elseif x > 0.08 then b.right = b.right + 1 end
            b.total = b.total + 1
            byType[p.t] = b
        end
    end

    local wanted, sum = {}, 0
    for _, t in ipairs(order.pizza.toppings) do
        wanted[t.id] = true
        local b = byType[t.id] or { left = 0, right = 0, total = 0 }
        local s
        if t.zone == "whole" then
            s = 1 - math.abs(b.total - t.count) / t.count
            -- repartidos en las dos mitades
            local minHalf = math.floor(t.count / 3)
            if b.left < minHalf or b.right < minHalf then s = s - 0.25 end
        else
            local good = t.zone == "left" and b.left or b.right
            local bad = b.total - good
            s = 1 - (math.abs(good - t.count) + bad) / t.count
        end
        sum = sum + clamp01(s)
    end
    local toppingScore = #order.pizza.toppings > 0 and sum / #order.pizza.toppings or 1
    local extra = 0
    for id, b in pairs(byType) do
        if not wanted[id] then extra = extra + 0.1 + 0.02 * b.total end
    end
    local sauceScore = clamp01((tonumber(sauce) or 0) / 0.8)
    local cheeseScore = clamp01((tonumber(cheese) or 0) / 0.8)
    local total = 0.2 * sauceScore + 0.2 * cheeseScore + 0.6 * toppingScore - extra
    return clamp01(total), clean, (tonumber(sauce) or 0) > 0.15, (tonumber(cheese) or 0) > 0.15
end

-- Nota de un tiempo frente a su objetivo: 1 en el punto, 0 a +-window, quemado a burnAt.
function Pizzeria.scoreTiming(elapsed, target, window, burnAt)
    local ratio = elapsed / target
    if ratio >= burnAt then return 0, ratio end
    return clamp01(1 - math.abs(elapsed - target) / (window * target)), ratio
end

-- cuts: { { a = grados, d = distancia al centro 0..1 } }
function Pizzeria.scoreCuts(order, cuts)
    local need = order.pizza.slices / 2
    local angles, offset = {}, 0
    for i, c in ipairs(cuts) do
        if i > 12 then break end
        local a, d = tonumber(c.a), tonumber(c.d)
        if a and d then
            angles[#angles + 1] = a % 180
            offset = offset + clamp01(d)
        end
    end
    if #angles == 0 then return 0 end
    table.sort(angles)
    local ideal, err = 180 / need, 0
    if #angles >= 2 then
        for i = 1, #angles do
            local nextA = angles[i + 1] or (angles[1] + 180)
            err = err + math.abs((nextA - angles[i]) - (180 / #angles))
        end
        err = err / 180
    end
    local countPenalty = math.abs(#angles - need) * 0.3
    -- con un numero de cortes distinto al pedido, los trozos tampoco salen iguales al ideal
    if #angles ~= need then err = err + math.abs(180 / #angles - ideal) / 180 end
    return clamp01(1 - err * 1.4 - (offset / #angles) * 1.5 - countPenalty)
end

function Pizzeria.scoreWait(order, now)
    local elapsed = now - order.spawnedAt
    local half = order.patience * 0.5
    if elapsed <= half then return 1 end
    return clamp01(1 - (elapsed - half) / (order.patience - half))
end

local WEIGHTS = { ing = 0.35, bake = 0.25, cut = 0.15, wait = 0.15, side = 0.10 }
local COMPLAINTS = {
    ing = "¡Esto no es lo que pedí!",
    cut = "¡Qué cortes más feos!",
    wait = "¡Tardaste una eternidad!",
    side = "La guarnición está horrible.",
}

-- Nota final 0..100, desglose y la queja principal (o nil)
function Pizzeria.finalScore(order, now)
    local s = order.score
    s.wait = Pizzeria.scoreWait(order, now)
    local total, weights = 0, 0
    for k, w in pairs(WEIGHTS) do
        if s[k] then total = total + s[k] * w; weights = weights + w end
    end
    local final = math.floor(total / weights * 100 + 0.5)

    local worstK, worstV = nil, 0.5
    for k in pairs(WEIGHTS) do
        if s[k] and s[k] < worstV then worstK, worstV = k, s[k] end
    end
    local complaint
    if worstK == "bake" then
        complaint = (order.bakeRatio or 1) > 1 and "¡Está quemada!" or "¡Está cruda!"
    elseif worstK then
        complaint = COMPLAINTS[worstK]
    end
    return final, complaint
end

-- Pago base y propina (antes del bonus de nivel de rp_jobs)
function Pizzeria.payFor(order, final, streak)
    local base = C.PAY_BASE + C.PAY_PER_TYPE * #order.pizza.toppings + (order.side and C.PAY_SIDE or 0)
    local pay = math.floor(base * (0.4 + 0.6 * final / 100) + 0.5)
    local tip = 0
    if final >= C.TIP_FROM then
        local f = (final - C.TIP_FROM) / (100 - C.TIP_FROM)
        tip = math.floor(base * C.TIP_MAX * f * (1 + C.STREAK_TIP * math.min(streak, 5)) + 0.5)
    end
    return pay, tip
end
