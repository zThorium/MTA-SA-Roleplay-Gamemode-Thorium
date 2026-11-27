--[[
    rp_pizzeria / s_pizzeria.lua
    Contratacion, turno (instancia por dimension), estaciones de la cocina, clientes y pagos.
    El cliente solo dice "estoy en tal estacion" y manda lo que armo o corto; el servidor
    comprueba distancia, dimension, estado del pedido, stock y tiempos minimos, y calcula
    nota y pago. El puesto, la XP y el dinero pasan por rp_jobs (trabajo externo "pizza").

    Export: isPlayerOnPizzaShift(player) -> bool
]]
Pizzeria = Pizzeria or {}

local C = PIZZERIA
local shifts = {}        -- [player] = S (estado del turno)
local slots = {}         -- [slot] = player
local lastAction = {}    -- [player] = tick
local stopping = false     -- parando el recurso: el cliente ya no escucha eventos

for _, name in ipairs({ "hireOpen", "hireAction", "station", "assemble", "cut", "fry", "restock", "discard", "leave", "closePanel", "arrived" }) do
    addEvent("rp:pizzeria:" .. name, true)
end
addEvent("rp:jobs:onShiftEnd", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:onCharacterLogout", false)

local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function jobs() local r = getResourceFromName("rp_jobs") return r and getResourceState(r) == "running" end

local function throttled(p, ms)
    local now = getTickCount()
    if lastAction[p] and now - lastAction[p] < (ms or 300) then return true end
    lastAction[p] = now
    return false
end

local function blocked(p)
    return not isElement(p) or isPedDead(p) or isPedInVehicle(p) or getElementData(p, "rp:downed")
        or getElementData(p, "rp:cuffed") or getElementData(p, "rp:carried")
end

local function near(p, x, y, z, r, interior, dim)
    if getElementInterior(p) ~= interior or getElementDimension(p) ~= dim then return false end
    local px, py, pz = getElementPosition(p)
    return math.abs(pz - z) < 2.5 and getDistanceBetweenPoints2D(px, py, x, y) <= r
end

----------------------------------------------------------------
-- Estado hacia el cliente
----------------------------------------------------------------
local function snapshot(S)
    local now = getTickCount()
    local orders = {}
    for _, o in pairs(S.orders) do
        orders[#orders + 1] = {
            id = o.id, name = o.name, skin = o.skin, status = o.status, stage = o.stage,
            ago = now - o.spawnedAt, patience = o.patience, arriveIn = math.max(0, o.arriveAt - now),
            pizza = o.pizza, side = o.side or false, sideState = o.sideState or false,
        }
    end
    table.sort(orders, function(a, b) return a.id < b.id end)
    local queue = {}
    for i, id in ipairs(S.queue) do queue[i] = id end
    local function slot(v, target)
        if not v then return false end
        return { order = v.order, ago = now - v.at, target = target or v.target }
    end
    return {
        orders = orders, queue = queue,
        hand = S.hand and { order = S.hand.order, kind = S.hand.kind } or false,
        ovens = { slot(S.ovens[1]), slot(S.ovens[2]) },
        fryer = { slot(S.fryer[1], C.FRY_MS), slot(S.fryer[2], C.FRY_MS) },
        stock = S.stock, earned = S.earned, served = S.served, streak = S.streak, level = S.level, tutorial = S.tutorial,
    }
end

local function push(S)
    if isElement(S.player) then triggerClientEvent(S.player, "rp:pizzeria:state", resourceRoot, snapshot(S)) end
end

local function fx(S, kind, data)
    if isElement(S.player) then triggerClientEvent(S.player, "rp:pizzeria:fx", resourceRoot, kind, data or {}) end
end

local function anim(p, block, name, ms, loop)
    if blocked(p) then return end
    setPedAnimation(p, block, name, ms or -1, loop or false, false, false, false)
end

----------------------------------------------------------------
-- Lo que lleva en la mano
----------------------------------------------------------------
local HAND_MODEL = { raw = 2683, baked = 2683, boxed = 1582 }

local function setHand(S, orderId, kind)
    if isElement(S.handObj) then destroyElement(S.handObj) end
    S.handObj = nil
    S.hand = orderId and { order = orderId, kind = kind } or nil
    if not orderId then return end
    local p = S.player
    local obj = createObject(HAND_MODEL[kind], 0, 0, -50)
    setElementInterior(obj, C.INTERIOR)
    setElementDimension(obj, S.dim)
    setElementCollisionsEnabled(obj, false)
    if kind == "boxed" then
        exports.bone_attach:attachElementToBone(obj, p, 12, 0.05, 0.15, 0.1, 0, -90, 0)
    else
        exports.bone_attach:attachElementToBone(obj, p, 12, 0.05, 0.1, 0.06, 0, 0, 0)
    end
    S.handObj = obj
end

-- Quita cualquier rastro de un pedido de la mano, hornos y freidora
local function forgetOrder(S, id)
    if S.hand and S.hand.order == id then setHand(S, nil) end
    for i = 1, 2 do
        if S.ovens[i] and S.ovens[i].order == id then S.ovens[i] = nil end
        if S.fryer[i] and S.fryer[i].order == id then S.fryer[i] = nil end
    end
    for i, q in ipairs(S.queue) do
        if q == id then table.remove(S.queue, i) break end
    end
    S.orders[id] = nil
end

----------------------------------------------------------------
-- Turno
----------------------------------------------------------------
local function freeSlot()
    for i = 1, C.DIM_COUNT do
        if not slots[i] or not isElement(slots[i]) then return i end
    end
end

local function levelOf(p)
    if not jobs() then return 1 end
    return exports.rp_jobs:getPlayerJobLevel(p, C.JOB_ID) or 1
end

-- Limpia la instancia. La llama rp:jobs:onShiftEnd (fin desde rp_jobs) o el propio recurso.
local function cleanup(p, moveOut)
    local S = shifts[p]
    if not S then return end
    shifts[p] = nil
    slots[S.slot] = nil
    if isTimer(S.timer) then killTimer(S.timer) end
    if isElement(S.handObj) then destroyElement(S.handObj) end
    if not isElement(p) then return end
    if not stopping then triggerClientEvent(p, "rp:pizzeria:shift", resourceRoot, false) end
    if moveOut and getElementDimension(p) == S.dim then
        local h = C.HIRE
        setElementDimension(p, h.dimension)
        setElementPosition(p, h.x, h.y, h.z)
        if not getElementData(p, "rp:downed") then setPedAnimation(p) end
    end
end

local function endShift(p, reason)
    if not shifts[p] then return end
    if jobs() then exports.rp_jobs:endExternalShift(p, reason) end
    cleanup(p, true)   -- por si rp_jobs no esta o ya habia cerrado el turno
end

local function tick(S)
    local p = S.player
    if not isElement(p) then return cleanup(p) end
    local now = getTickCount()

    -- clientes que se cansan de esperar
    for id, o in pairs(S.orders) do
        if now - o.spawnedAt > o.patience then
            forgetOrder(S, id)
            S.streak = 0
            S.lost = S.lost + 1
            fx(S, "left", { id = id })
            notify(p, ("%s se fue enojado: tardaste demasiado."):format(o.name), "warning")
            push(S)
        end
    end

    -- cliente nuevo
    local active = 0
    for _ in pairs(S.orders) do active = active + 1 end
    local diff = Pizzeria.difficulty(S.level)
    local maxActive = S.tutorial and 1 or diff.maxActive   -- en el tutorial, un solo cliente
    if now >= S.nextSpawn and active < maxActive then
        local o = Pizzeria.newOrder(S)
        S.orders[o.id] = o
        S.queue[#S.queue + 1] = o.id
        -- el que no es el primero de la cola llega cuando avance
        if #S.queue > 1 then o.arriveAt = now + C.ARRIVE_MS + 2000 * (#S.queue - 1) end
        local spawn = math.random(C.SPAWN_MS[1], C.SPAWN_MS[2]) * (1 - 0.06 * (S.level - 1))
        if S.streak >= 3 then spawn = spawn * 0.85 end
        S.nextSpawn = now + math.floor(spawn)
        fx(S, "bell", { id = o.id })
        push(S)
    end
end

local function startShift(p, tutorial)
    if shifts[p] then return end
    local slot = freeSlot()
    if not slot then return notify(p, "La pizzería está llena, prueba en un rato.", "error") end
    local ok, reason = exports.rp_jobs:startExternalShift(p, C.JOB_ID)
    if not ok then return notify(p, reason or "No puedes empezar el turno ahora.", "error") end

    local S = {
        player = p, slot = slot, dim = C.DIM_BASE + slot, level = levelOf(p),
        orders = {}, queue = {}, nextId = 0, ovens = {}, fryer = {},
        stock = {}, earned = 0, served = 0, lost = 0, streak = 0,
        nextSpawn = getTickCount() + C.FIRST_CUSTOMER_MS, panel = nil, tutorial = tutorial and true or false,
    }
    -- La despensa empieza a medias: hay que reponer pronto
    for id, b in pairs(C.BASE) do S.stock[id] = math.ceil(b.stock / 2) end
    for _, t in ipairs(C.TOPPINGS) do S.stock[t.id] = math.ceil(t.stock / 2) end
    shifts[p] = S
    slots[slot] = p

    local st = C.START
    setElementDimension(p, S.dim)
    setElementInterior(p, C.INTERIOR, st.x, st.y, st.z)
    setElementRotation(p, 0, 0, st.rot)
    -- Cierre, no argumento: setTimer copia las tablas que recibe y tick trabajaria sobre una copia nueva cada vez
    S.timer = setTimer(function() tick(S) end, 1000, 0)
    triggerClientEvent(p, "rp:pizzeria:shift", resourceRoot, true, S.dim)
    push(S)
    if S.tutorial then
        exports.rp_notify:popup(p, "Tutorial de pizzero",
            "Te guiaremos con una flecha por cada estación. Llegará un solo cliente con un pedido fácil y sin prisa. Sigue los pasos de la tarjeta de la izquierda.", "info", 9000)
    else
        exports.rp_notify:popup(p, "¡A trabajar!",
            "Toma pedidos en la caja, arma la pizza, hornéala, córtala y entrégala en Entregas. Todo con E en cada estación. Para terminar, sal por el comedor o usa /terminarturno.", "info", 9000)
    end
end

addEventHandler("rp:jobs:onShiftEnd", root, function(jobId)
    if jobId == C.JOB_ID then cleanup(source, true) end
end)
addEventHandler("onPlayerQuit", root, function()
    cleanup(source)
    lastAction[source] = nil
end)
addEventHandler("rp:onCharacterLogout", root, function() endShift(source, "Tu turno terminó.") end)
addEventHandler("rp:onPlayerDowned", root, function() endShift(source, "Tu turno terminó.") end)
addEventHandler("onPlayerWasted", root, function() endShift(source, "Tu turno terminó.") end)
addEventHandler("onResourceStop", resourceRoot, function()
    stopping = true
    for p in pairs(shifts) do
        if jobs() then exports.rp_jobs:endExternalShift(p, "La pizzería cerró un momento.", true) end
        cleanup(p, true)
    end
end)

----------------------------------------------------------------
-- Contratacion (marcador del comedor)
----------------------------------------------------------------
local function hireData(p)
    local current = exports.rp_jobs:getPlayerJob(p)
    local info = exports.rp_jobs:getJobInfo(C.JOB_ID) or {}
    local stats = exports.rp_jobs:getPlayerJobStats(p, C.JOB_ID) or {}
    local otherName = false
    if current and current ~= C.JOB_ID then
        local other = exports.rp_jobs:getJobInfo(current)
        otherName = other and other.name or current
    end
    return {
        hired = current == C.JOB_ID, other = otherName,
        description = info.description or "", pay = info.pay or "",
        level = stats.level or 1, xp = stats.xp or 0, tasks = stats.tasks or 0,
        earned = stats.earned or 0, best = stats.bestShift or 0,
    }
end

addEventHandler("rp:pizzeria:hireOpen", resourceRoot, function()
    local p = client
    if throttled(p, 800) or blocked(p) or shifts[p] or not jobs() then return end
    if not exports.rp_characters:getPlayerCharacterId(p) then return end
    local h = C.HIRE
    if not near(p, h.x, h.y, h.z, h.radius + 1.5, C.INTERIOR, h.dimension) then return end
    triggerClientEvent(p, "rp:pizzeria:panel", resourceRoot, "hire", hireData(p))
end)

addEventHandler("rp:pizzeria:hireAction", resourceRoot, function(action)
    local p = client
    if throttled(p, 600) or blocked(p) or not jobs() then return end
    local h = C.HIRE
    if not near(p, h.x, h.y, h.z, h.radius + 2, C.INTERIOR, h.dimension) then return end
    if action == "hire" then
        local ok, reason = exports.rp_jobs:setPlayerJob(p, C.JOB_ID)
        if not ok then return notify(p, reason or "No puedes tomar el trabajo ahora.", "error") end
        notify(p, "¡Bienvenido a Well Stacked Pizza! Ya eres pizzero.", "success")
        triggerClientEvent(p, "rp:pizzeria:panel", resourceRoot, "hire", hireData(p))
    elseif action == "start" or action == "tutorial" then
        if exports.rp_jobs:getPlayerJob(p) ~= C.JOB_ID then return end
        triggerClientEvent(p, "rp:pizzeria:closePanel", resourceRoot)
        -- la primera vez (ninguna pizza entregada) el turno empieza siempre con el tutorial
        local stats = exports.rp_jobs:getPlayerJobStats(p, C.JOB_ID) or {}
        startShift(p, action == "tutorial" or (stats.tasks or 0) == 0)
    elseif action == "quit" then
        local ok = exports.rp_jobs:quitPlayerJob(p)
        if ok then notify(p, "Dejaste el trabajo de pizzero.", "info") end
        triggerClientEvent(p, "rp:pizzeria:closePanel", resourceRoot)
    end
end)

addEventHandler("rp:pizzeria:leave", resourceRoot, function()
    local p = client
    local S = shifts[p]
    if not S then return end
    local l = C.LEAVE
    if not near(p, l.x, l.y, l.z, l.radius + 1.5, C.INTERIOR, S.dim) then return end
    endShift(p, "Terminaste tu turno.")
end)

----------------------------------------------------------------
-- Estaciones
----------------------------------------------------------------
-- Mostrador: zona rectangular del lado del personal (con margen)
local function atCounter(p, dim)
    if getElementInterior(p) ~= C.INTERIOR or getElementDimension(p) ~= dim then return false end
    local x, y = getElementPosition(p)
    local z, m = C.COUNTER, C.STATION_SLACK
    return x >= z.x1 - m and x <= z.x2 + m and y >= z.y1 - m and y <= z.y2 + m
end

local function atStation(S, id)
    local st = C.STATION_BY_ID[id]
    if not st then return nil end
    if st.kind == "pickup" then return atCounter(S.player, S.dim) and st or nil end
    if not near(S.player, st.x, st.y, st.z, C.STATION_RADIUS + C.STATION_SLACK, C.INTERIOR, S.dim) then return nil end
    return st
end

local function openPanel(S, kind, data)
    S.panel = { kind = kind, at = getTickCount() }
    triggerClientEvent(S.player, "rp:pizzeria:panel", resourceRoot, kind, data)
    if kind ~= "fryer" then anim(S.player, "BD_FIRE", "wash_up", -1, true) end
end

local function closePanel(S)
    S.panel = nil
    if isElement(S.player) and not blocked(S.player) then setPedAnimation(S.player) end
end

local function stockMax()
    local m = {}
    for id, b in pairs(C.BASE) do m[id] = b.stock end
    for _, t in ipairs(C.TOPPINGS) do m[t.id] = t.stock end
    return m
end

local function fryerData(S)
    local now, pending, baskets = getTickCount(), {}, {}
    for _, o in pairs(S.orders) do
        if o.side and o.status == "waiting" and not o.sideState then
            pending[#pending + 1] = { id = o.id, name = o.name, side = o.side }
        end
    end
    table.sort(pending, function(a, b) return a.id < b.id end)
    for i = 1, 2 do
        local f = S.fryer[i]
        baskets[i] = f and { order = f.order, side = S.orders[f.order] and S.orders[f.order].side, ago = now - f.at, target = C.FRY_MS } or false
    end
    return { pending = pending, baskets = baskets }
end

local handlers = {}

function handlers.order(S)
    local p = S.player
    local id = S.queue[1]
    local o = id and S.orders[id]
    if not o then return notify(p, "No hay nadie esperando en la caja.", "info") end
    local now = getTickCount()
    if now < o.arriveAt then return notify(p, ("%s todavía viene llegando."):format(o.name), "info") end
    table.remove(S.queue, 1)
    o.status, o.takenAt = "waiting", now
    -- el siguiente de la cola tarda un poco en avanzar
    if S.queue[1] and S.orders[S.queue[1]] then
        local n = S.orders[S.queue[1]]
        n.arriveAt = math.max(n.arriveAt, now + 2500)
        n.minArriveAt = now + 800   -- avanzar un puesto en la fila
    end
    anim(p, "INT_SHOP", "shop_cashier", 2500)
    fx(S, "ordered", { id = o.id })
    push(S)
end

function handlers.assembly(S)
    if S.hand then return notify(S.player, "Tienes las manos ocupadas.", "error") end
    local tickets = {}
    for _, o in pairs(S.orders) do
        if o.status == "waiting" and o.stage == "new" then
            tickets[#tickets + 1] = { id = o.id, name = o.name, pizza = o.pizza }
        end
    end
    if #tickets == 0 then return notify(S.player, "No hay pedidos por armar. Toma pedidos en la caja.", "info") end
    table.sort(tickets, function(a, b) return a.id < b.id end)
    openPanel(S, "assembly", { tickets = tickets, stock = S.stock, max = stockMax(),
        coach = S.tutorial or S.level <= C.GUIDES_UP_TO_LEVEL })
end

function handlers.oven(S, st)
    local p, slot, now = S.player, st.slot, getTickCount()
    local ov = S.ovens[slot]
    if ov then
        if S.hand then return notify(p, "Suelta lo que llevas para sacar la pizza.", "error") end
        local o = S.orders[ov.order]
        S.ovens[slot] = nil
        if not o then return push(S) end
        local score, ratio = Pizzeria.scoreTiming(now - ov.at, ov.target, 0.35, C.BURN_AT)
        o.score.bake, o.bakeRatio, o.stage = score, ratio, "baked"
        setHand(S, o.id, "baked")
        anim(p, "BAR", "Barserve_give", 1500)
        fx(S, "oven_out", { ratio = ratio })
        return push(S)
    end
    if not S.hand or S.hand.kind ~= "raw" then return notify(p, "Necesitas una pizza armada para hornear.", "info") end
    local o = S.orders[S.hand.order]
    if not o then setHand(S, nil) return push(S) end
    S.ovens[slot] = { order = o.id, at = now, target = math.floor(C.BAKE_MS * (C.BAKE[o.pizza.bake] or 1)) }
    o.stage = "baking"
    setHand(S, nil)
    anim(p, "BAR", "Barserve_give", 1500)
    fx(S, "oven_in", { slot = slot })
    push(S)
end

function handlers.cut(S)
    local p = S.player
    if not S.hand or S.hand.kind ~= "baked" then return notify(p, "Trae una pizza recién horneada para cortarla.", "info") end
    local o = S.orders[S.hand.order]
    if not o then setHand(S, nil) return push(S) end
    -- guias de corte (y ajuste automatico) en el tutorial y en los niveles bajos
    local guides = S.tutorial or S.level <= C.GUIDES_UP_TO_LEVEL
    openPanel(S, "cut", { id = o.id, name = o.name, slices = o.pizza.slices, built = o.built or {}, ratio = o.bakeRatio or 1, guides = guides })
end

function handlers.fryer(S)
    openPanel(S, "fryer", fryerData(S))
end

function handlers.pantry(S)
    openPanel(S, "pantry", { stock = S.stock, max = stockMax() })
end

function handlers.pickup(S)
    local p = S.player
    if not S.hand or S.hand.kind ~= "boxed" then return notify(p, "Trae una pizza ya empacada para entregarla.", "info") end
    local o = S.orders[S.hand.order]
    if not o then setHand(S, nil) return push(S) end
    if o.side and o.sideState ~= "done" then
        return notify(p, ("Falta la guarnición de %s (%s)."):format(o.name, C.SIDES[o.side].name), "warning")
    end

    local now = getTickCount()
    local final, complaint = Pizzeria.finalScore(o, now)
    local pay, tip = Pizzeria.payFor(o, final, S.streak)
    if final >= C.STREAK_GOOD then S.streak = S.streak + 1 else S.streak = 0 end
    local paid = exports.rp_jobs:payExternalJob(p, pay + tip, ("Pizza de %s"):format(o.name)) or 0
    exports.rp_jobs:giveExternalJobXP(p, 8 + math.floor(final / 10))
    S.earned, S.served = S.earned + paid, S.served + 1
    S.level = levelOf(p)
    triggerEvent("rp:achievements:progress", p, "pizza_delivered", 1)            -- logros (rp_achievements)
    if final >= 95 then triggerEvent("rp:achievements:progress", p, "pizza_perfect", 1) end

    local reaction = final >= 85 and "love" or final >= 70 and "happy" or final >= 50 and "neutral" or "complain"
    local sc = o.score
    fx(S, "served", {
        id = o.id, name = o.name, final = final, reaction = reaction, complaint = complaint or false,
        paid = paid, tip = tip, streak = S.streak,
        x = math.max(C.COUNTER.x1 + 0.3, math.min(C.COUNTER.x2 - 0.3, (getElementPosition(p)))),
        parts = {
            ing = math.floor((sc.ing or 0) * 100), bake = math.floor((sc.bake or 0) * 100),
            cut = math.floor((sc.cut or 0) * 100), wait = math.floor((sc.wait or 0) * 100),
            side = sc.side and math.floor(sc.side * 100) or false,
        },
    })
    S.orders[o.id] = nil
    setHand(S, nil)
    anim(p, "BAR", "Barserve_give", 1500)
    if S.tutorial then
        -- fin del tutorial: el cliente muestra la despensa y la freidora y luego empieza el turno normal
        S.tutorial = false
        S.nextSpawn = now + C.AFTER_TUTORIAL_MS
        fx(S, "tutorial_done", {})
    end
    push(S)
end

addEventHandler("rp:pizzeria:station", resourceRoot, function(id)
    local p = client
    local S = shifts[p]
    if not S or throttled(p, 350) or blocked(p) then return end
    local st = atStation(S, id)
    if not st then return end
    S.panel = nil   -- con un panel abierto el cliente no puede pulsar E: si quedo uno colgado, se descarta
    handlers[st.kind](S, st)
end)

-- El ped del cliente llego a la caja (lo ve el trabajador). Solo vale para el primero de la fila y
-- desde un tiempo minimo plausible; si nunca llega el aviso, arriveAt (calculado) sirve de respaldo.
addEventHandler("rp:pizzeria:arrived", resourceRoot, function(orderId)
    local S = shifts[client]
    if not S or throttled(client, 200) then return end
    local id = tonumber(orderId)
    local o = id and S.orders[id]
    if not o or o.status ~= "queue" or S.queue[1] ~= id then return end
    local now = getTickCount()
    if now < (o.minArriveAt or 0) or now >= o.arriveAt then return end
    o.arriveAt = now
    push(S)
end)

addEventHandler("rp:pizzeria:closePanel", resourceRoot, function()
    local S = shifts[client]
    if S and S.panel then closePanel(S) end
end)

addEventHandler("rp:pizzeria:discard", resourceRoot, function()
    local S = shifts[client]
    if not S or not S.hand or throttled(client, 500) then return end
    local o = S.orders[S.hand.order]
    if o then o.stage, o.built, o.score.ing, o.score.bake, o.score.cut = "new", nil, nil, nil, nil end
    setHand(S, nil)
    notify(client, "Tiraste la pizza. Ese pedido vuelve a la mesa de armado.", "info")
    push(S)
end)

----------------------------------------------------------------
-- Resultados de los paneles
----------------------------------------------------------------
local function panelOpen(S, kind, stationId)
    return S.panel and S.panel.kind == kind and atStation(S, stationId)
end

addEventHandler("rp:pizzeria:assemble", resourceRoot, function(orderId, sauce, cheese, placements)
    local p = client
    local S = shifts[p]
    if not S or not panelOpen(S, "assembly", "assembly") or S.hand then return end
    local o = S.orders[tonumber(orderId) or -1]
    if not o or o.status ~= "waiting" or o.stage ~= "new" or type(placements) ~= "table" then return end
    if #placements > C.MAX_PIECES then return notify(p, "Eso no es una pizza, es una montaña.", "error") end

    local now = getTickCount()
    if now - S.panel.at < C.MIN_ASSEMBLY_MS + #placements * C.MIN_PER_PIECE_MS then return end

    local score, clean, usedSauce, usedCheese = Pizzeria.scoreAssembly(o, sauce, cheese, placements)
    -- stock: masa siempre, salsa y queso si los puso, una pieza por ingrediente colocado
    local need = { dough = 1, sauce = usedSauce and 1 or 0, cheese = usedCheese and 1 or 0 }
    for _, c in ipairs(clean) do need[c.t] = (need[c.t] or 0) + 1 end
    for id, n in pairs(need) do
        if (S.stock[id] or 0) < n then
            local name = C.BASE[id] and C.BASE[id].name or (C.TOPPING_BY_ID[id] and C.TOPPING_BY_ID[id].name) or id
            return notify(p, ("No queda suficiente %s: repón en la despensa."):format(name:lower()), "error")
        end
    end
    for id, n in pairs(need) do S.stock[id] = S.stock[id] - n end

    o.score.ing, o.built, o.stage = score, { items = clean, sauce = usedSauce, cheese = usedCheese }, "assembled"
    setHand(S, o.id, "raw")
    closePanel(S)
    triggerClientEvent(p, "rp:pizzeria:closePanel", resourceRoot)
    notify(p, ("Pizza de %s armada. ¡Al horno!"):format(o.name), "success")
    push(S)
end)

addEventHandler("rp:pizzeria:cut", resourceRoot, function(cuts)
    local p = client
    local S = shifts[p]
    if not S or not panelOpen(S, "cut", "cut") or type(cuts) ~= "table" then return end
    if not S.hand or S.hand.kind ~= "baked" then return end
    if getTickCount() - S.panel.at < C.MIN_CUT_MS then return end
    local o = S.orders[S.hand.order]
    if not o then return end
    o.score.cut, o.stage = Pizzeria.scoreCuts(o, cuts), "boxed"
    setHand(S, o.id, "boxed")
    closePanel(S)
    triggerClientEvent(p, "rp:pizzeria:closePanel", resourceRoot)
    fx(S, "boxed", {})
    push(S)
end)

addEventHandler("rp:pizzeria:fry", resourceRoot, function(action, arg)
    local p = client
    local S = shifts[p]
    if not S or not panelOpen(S, "fryer", "fryer") or throttled(p, 300) then return end
    local now = getTickCount()
    if action == "fry" then
        local o = S.orders[tonumber(arg) or -1]
        if not o or not o.side or o.sideState or o.status ~= "waiting" then return end
        local free = not S.fryer[1] and 1 or not S.fryer[2] and 2
        if not free then return notify(p, "Las dos canastas están ocupadas.", "error") end
        S.fryer[free] = { order = o.id, at = now }
        o.sideState = "frying"
        fx(S, "fry_in", {})
    elseif action == "take" then
        local i = tonumber(arg)
        local f = i and S.fryer[i]
        if not f then return end
        S.fryer[i] = nil
        local o = S.orders[f.order]
        if o then
            local score = Pizzeria.scoreTiming(now - f.at, C.FRY_MS, 0.4, C.FRY_BURN_AT)
            o.score.side, o.sideState = score, "done"
            notify(p, ("%s de %s listas en la bandeja."):format(C.SIDES[o.side].name, o.name), "success")
        end
    else
        return
    end
    triggerClientEvent(p, "rp:pizzeria:panel", resourceRoot, "fryer", fryerData(S))
    push(S)
end)

addEventHandler("rp:pizzeria:restock", resourceRoot, function(id)
    local p = client
    local S = shifts[p]
    if not S or not panelOpen(S, "pantry", "pantry") then return end
    local now = getTickCount()
    if S.lastRestock and now - S.lastRestock < C.RESTOCK_COOLDOWN_MS then return end
    local def = C.BASE[id] or C.TOPPING_BY_ID[id]
    if not def then return end
    if S.stock[id] >= def.stock then return notify(p, ("Ya está lleno de %s."):format(def.name:lower()), "info") end
    S.lastRestock = now
    S.stock[id] = math.min(def.stock, S.stock[id] + def.restock)
    triggerClientEvent(p, "rp:pizzeria:panel", resourceRoot, "pantry", { stock = S.stock, max = stockMax() })
    push(S)
end)

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function isPlayerOnPizzaShift(player)
    return shifts[player] ~= nil
end

----------------------------------------------------------------
-- Marcador de contratacion movible por los admins (rp_markers; el marcador lo dibuja el cliente)
----------------------------------------------------------------
local function registerHire()
    pizzeriaResolveHire()
    local h = PIZZERIA.HIRE
    pcall(function()
        exports.rp_markers:registerPoint("hire", { label = "Pizzería · contratación", point = { h.x, h.y, h.z },
            interior = PIZZERIA.INTERIOR, dimension = h.dimension })
    end)
end
addEvent("rp:markers:moved")
addEvent("rp:markers:ready")
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then registerHire() end
end)
addEventHandler("rp:markers:ready", root, registerHire)
addEventHandler("onResourceStart", resourceRoot, registerHire)
