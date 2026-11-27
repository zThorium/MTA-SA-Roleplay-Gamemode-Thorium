--[[
    rp_metaldetector / s_metaldetector.lua  (servidor)

    Detector de metales en las playas.
    - Tienda propia (panel CEF): el vendedor junto al muelle de Santa Maria vende 5 detectores y la pala.
      Cada detector exige un nivel de buscador. Cobro en efectivo validado aquí (distancia, nivel, peso).
    - Nivel de buscador (1-5) por personaje en metal_detecting: XP por hallazgo según la rareza,
      objetos encontrados y dinero ganado vendiendo lo encontrado (aviso rp:jobs:onMarketSale de rp_jobs).
    - Usar un detector desde el inventario (rp:onItemUse) lo pone en la mano o lo guarda. El modelo y
      la pose los dibuja cada cliente a partir de elementData rp:heldItem (item del detector en la mano;
      el inventario lo marca y muestra «Guardar»).
    - El cliente comprueba que pisas arena y propone un punto oculto a 15-45 m; el servidor lo valida
      y decide YA lo que hay enterrado según el detector (profundidad máxima, bonus de rareza) y manda
      solo la lectura (VDI con el error de su precisión, profundidad aproximada y paladas).
    - Cavar: E empieza, cada palada es rp:metaldetector:stroke (ritmo mínimo en el servidor), al
      completar se entrega el botín. Backspace cancela.
    - Colección por personaje en metal_finds («¡nuevo!» la primera vez).

    Comandos:
        /detector               panel con tu progreso de buscador y tu colección
        /hallazgos              igual, abierto en la colección
    Admin (catálogo en rp_adminpanel/server/s_catalog.lua):
        /detectorsuelo          muestra el ID de material que pisas (para afinar SAND_MATERIALS)
    Exports (servidor):
        isPlayerDetecting(player) -> true si lleva un detector en la mano
        getMetalDetectorLoot()    -> tabla de botín { { item, weight, amount = { mín, máx } } }
        getPlayerDetectorLevel(player) -> nivel de buscador (1-5) o false si no está cargado
]]

local C = METALDETECTOR
local L = METALDETECTOR_LIMITS

----------------------------------------------------------------
-- Estado (todo local; se limpia al guardar el detector, salir, cambiar de personaje o parar)
----------------------------------------------------------------
local equipped = {}     -- [player] = { tier, shovel, spot, digging, resume, lastPropose }
local lastDig = {}      -- [player] = tick de la última excavación
local lastBuy = {}      -- [player] = tick de la última compra
local findsLog = {}     -- [characterId] = { ticks de hallazgos } (tope por hora)
local collections = {}  -- [characterId] = { [itemId] = veces } (metal_finds)
local progress = {}     -- [characterId] = { xp, items, money } (metal_detecting)
local shop = {}         -- { ped }

addEvent("rp:onItemUse", false)
addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onPlayerDowned", false)
addEvent("rp:jobs:onMarketSale", false)
addEvent("rp:metaldetector:proposeSpot", true)
addEvent("rp:metaldetector:startDig", true)
addEvent("rp:metaldetector:stroke", true)
addEvent("rp:metaldetector:cancelDig", true)
addEvent("rp:metaldetector:openShop", true)
addEvent("rp:metaldetector:buy", true)

----------------------------------------------------------------
-- Atajos
----------------------------------------------------------------
local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function log(msg, level) outputDebugString("[rp_metaldetector] " .. msg, level or 3) end

-- Llamada a un recurso opcional: nil si no está en marcha
local function try(resName, fn, ...)
    local res = getResourceFromName(resName)
    if not res or getResourceState(res) ~= "running" then return nil end
    local ok, value = pcall(call, res, fn, ...)
    return ok and value or nil
end

local function dist2D(x1, y1, x2, y2) return getDistanceBetweenPoints2D(x1, y1, x2, y2) end

----------------------------------------------------------------
-- Puente con el inventario de la GM
----------------------------------------------------------------
-- Da un item; si no cabe, lo deja en el suelo junto al jugador. Devuelve "inventory" | "ground" | false.
local function givePlayerItem(p, itemId, amount)
    if exports.rp_inventory:canCarry(p, itemId, amount) then
        local ok = exports.rp_inventory:giveItem(p, itemId, amount)
        if ok then return "inventory" end
    end
    local x, y, z = getElementPosition(p)
    local obj = exports.rp_inventory:spawnGroundItem(itemId, amount, x + 0.6, y, z - 0.95, getElementDimension(p), getElementInterior(p))
    return obj and "ground" or false
end

local function hasPlayerItem(p, itemId, amount)
    return exports.rp_inventory:hasItem(p, itemId, amount or 1) == true
end

----------------------------------------------------------------
-- Progreso del buscador (metal_detecting) y colección (metal_finds)
----------------------------------------------------------------
local function loadCharacter(characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return log("no se pudo cargar la colección de #" .. characterId, 2) end
        local col = {}
        for _, r in ipairs(rows) do col[r.item_id] = tonumber(r.times) or 0 end
        collections[characterId] = col
    end, db(), "SELECT item_id, times FROM metal_finds WHERE character_id = ?", characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return log("no se pudo cargar el progreso de #" .. characterId, 2) end
        local r = rows[1] or {}
        progress[characterId] = { xp = tonumber(r.xp) or 0, items = tonumber(r.items_found) or 0, money = tonumber(r.money_earned) or 0 }
    end, db(), "SELECT xp, items_found, money_earned FROM metal_detecting WHERE character_id = ?", characterId)
end

local function unloadCharacter(characterId)
    if not characterId then return end
    collections[characterId] = nil
    progress[characterId] = nil
end

-- Suma un hallazgo a la colección; devuelve veces (tras sumar) y si es la primera vez
local function recordFind(characterId, itemId)
    local col = collections[characterId]
    local before = col and col[itemId] or 0
    if col then col[itemId] = before + 1 end
    dbExec(db(), [[INSERT INTO metal_finds (character_id, item_id, times) VALUES (?, ?, 1)
        ON DUPLICATE KEY UPDATE times = times + 1, last_at = CURRENT_TIMESTAMP]], characterId, itemId)
    return before + 1, col ~= nil and before == 0
end

-- Suma XP, objetos y dinero; devuelve nivel antes y después
local function addProgress(characterId, xp, items, money)
    local pr = progress[characterId]
    local before = pr and metalDetectorLevel(pr.xp) or nil
    if pr then
        pr.xp, pr.items, pr.money = pr.xp + xp, pr.items + items, pr.money + money
    end
    dbExec(db(), [[INSERT INTO metal_detecting (character_id, xp, items_found, money_earned) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), items_found = items_found + VALUES(items_found),
        money_earned = money_earned + VALUES(money_earned)]], characterId, xp, items, money)
    return before, pr and metalDetectorLevel(pr.xp) or nil
end

local function collectionStats(characterId)
    local col = collections[characterId] or {}
    local distinct, total = 0, 0
    for _, f in ipairs(C.FINDS) do
        local n = col[f.item] or 0
        if n > 0 then distinct = distinct + 1 end
        total = total + n
    end
    return distinct, total
end

----------------------------------------------------------------
-- Estado del jugador
----------------------------------------------------------------
local function blockedReason(p)
    if exports.rp_injury:isPlayerDowned(p) then return "No puedes hacer eso ahora." end
    if isPedInVehicle(p) then return "Bájate del vehículo." end
    if try("rp_police", "isCuffed", p) then return "Estás esposado." end
    if try("rp_missions", "getPlayerMission", p) then return "Estás en una misión." end
    return nil
end

local function attachProp(p, def)
    local obj = createObject(def.model, 0, 0, 0)
    if not obj then return nil end
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, getElementInterior(p))
    setElementDimension(obj, getElementDimension(p))
    exports.bone_attach:attachElementToBone(obj, p, C.BONE, def.x, def.y, def.z, def.rx, def.ry, def.rz)
    return obj
end

local function destroyProp(obj)
    if isElement(obj) then
        pcall(function() exports.bone_attach:detachElementFromBone(obj) end)
        destroyElement(obj)
    end
end

-- Detector visible en la mano: elementData rp:heldItem = id del item (convención de la GM: el inventario
-- lo marca y su botón pasa a «Guardar»; los clientes de este recurso dibujan el modelo de ese nivel)
local function isDetectorHeld(p) return METALDETECTOR_TIER_BY_ITEM[getElementData(p, "rp:heldItem") or ""] ~= nil end

local function showDetector(p, tier)
    if not isElement(p) then return end
    local t = tier and C.TIERS[tier]
    if t then setElementData(p, "rp:heldItem", t.item)
    elseif isDetectorHeld(p) then removeElementData(p, "rp:heldItem") end   -- no pisar lo que lleve otro recurso
end

-- Lo que el cliente puede saber del punto: posición y lectura del detector (nunca el item)
local function spotForClient(spot)
    if not spot then return false end
    return { spot.x, spot.y, spot.z, vdi = spot.vdi, depth = spot.depth, strokes = spot.strokes }
end

local function sendState(p)
    local s = equipped[p]
    local characterId = characterOf(p)
    local distinct, total = 0, 0
    if characterId then distinct, total = collectionStats(characterId) end
    triggerClientEvent(p, "rp:metaldetector:state", resourceRoot, s ~= nil, s and spotForClient(s.spot) or false,
        { distinct = distinct, total = total, finds = #C.FINDS, tier = s and s.tier or false })
end

-- Termina una excavación a medias (sin premio; el punto sigue ahí)
local function stopDigging(p, reason)
    local s = equipped[p]
    if not s or not s.digging then return end
    if isTimer(s.digging.timeout) then killTimer(s.digging.timeout) end
    s.digging = nil
    destroyProp(s.shovel)
    s.shovel = nil
    if isElement(p) then
        setElementFrozen(p, false)
        setPedAnimation(p)
        showDetector(p, s.tier)
        triggerClientEvent(p, "rp:metaldetector:dig", resourceRoot, "stop")
        if reason then notify(p, reason, "info") end
    end
end

local function unequip(p, reason)
    local s = equipped[p]
    if not s then return end
    stopDigging(p)
    if isTimer(s.resume) then
        -- mirando un hallazgo: aún congelado y con la pala
        killTimer(s.resume)
        destroyProp(s.shovel)
        if isElement(p) then
            setElementFrozen(p, false)
            setPedAnimation(p)
        end
    end
    equipped[p] = nil
    if isElement(p) then
        showDetector(p, nil)
        sendState(p)
        if reason then notify(p, reason, "info") end
    end
end

local function equip(p, tier)
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end
    if getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then
        return notify(p, "El detector solo sirve al aire libre, en la playa.", "warning")
    end
    equipped[p] = { tier = tier.index }
    showDetector(p, tier.index)
    sendState(p)
end

addEventHandler("rp:onItemUse", root, function(itemId)
    local p = source
    local tier = METALDETECTOR_TIER_BY_ITEM[itemId]
    if not tier or not characterOf(p) then return end
    local s = equipped[p]
    if s then
        if s.digging or isTimer(s.resume) then return end
        local same = s.tier == tier.index
        unequip(p, same and "Guardas el detector." or nil)
        if same then return end
    end
    equip(p, tier)
end)

----------------------------------------------------------------
-- Punto oculto: el cliente propone (comprobó arena), el servidor decide qué hay enterrado
----------------------------------------------------------------
local function finite(n) return type(n) == "number" and n == n and n > -1e5 and n < 1e5 end

local function buryLoot(x, y, z, tierIndex)
    local stats = metalDetectorStats(tierIndex)
    local itemId, amount = pickMetalDetectorLoot(tierIndex)
    local find = METALDETECTOR_FIND_BY_ITEM[itemId]
    local rarity = find and C.RARITIES[find.rarity] or C.RARITIES.common
    local vdi = find and find.vdi or 30
    if math.random() < stats.falseChance then
        vdi = C.FINDS[math.random(#C.FINDS)].vdi      -- interferencia: la lectura engaña
    end
    vdi = math.max(1, math.min(99, vdi + math.random(-stats.noise, stats.noise)))
    local depth = math.max(5, (find and find.depth or 15) + math.random(-L.DEPTH_NOISE, L.DEPTH_NOISE))
    return { x = x, y = y, z = z, item = itemId, amount = amount, vdi = vdi, depth = depth, strokes = rarity.strokes }
end

addEventHandler("rp:metaldetector:proposeSpot", resourceRoot, function(x, y, z)
    local p = client
    local s = equipped[p]
    if not s or s.digging or isTimer(s.resume) then return end
    if not (finite(x) and finite(y) and finite(z)) then return end

    local now = getTickCount()
    if s.lastPropose and now - s.lastPropose < L.PROPOSE_COOLDOWN_MS then return end
    s.lastPropose = now

    local px, py, pz = getElementPosition(p)
    -- Con un punto activo solo se acepta otro si el jugador se alejó de él
    if s.spot and dist2D(px, py, s.spot.x, s.spot.y) < C.SPOT_LOST_DIST then return sendState(p) end

    local d = dist2D(px, py, x, y)
    if d < C.SPOT_MIN_DIST - 1 or d > C.SPOT_MAX_DIST + 1 or math.abs(z - pz) > L.MAX_Z_DIFF then return end
    if not C.BEACH_ZONES[getZoneName(x, y, z)] then return end
    if blockedReason(p) or getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return end

    s.spot = buryLoot(x, y, z, s.tier)
    sendState(p)
end)

----------------------------------------------------------------
-- Excavar a paladas
----------------------------------------------------------------
local function underHourlyCap(characterId)
    local now, list, kept = getTickCount(), findsLog[characterId] or {}, {}
    for _, t in ipairs(list) do if now - t < 3600000 then kept[#kept + 1] = t end end
    findsLog[characterId] = kept
    return #kept < L.MAX_FINDS_PER_HOUR
end

-- Los de alrededor ven el destello de los hallazgos buenos
local function broadcastReveal(p, spot, find)
    local list = {}
    for _, other in ipairs(getElementsByType("player")) do
        if other ~= p and getElementDimension(other) == 0 and getElementInterior(other) == 0 then
            local ox, oy = getElementPosition(other)
            if dist2D(ox, oy, spot.x, spot.y) < 120 then list[#list + 1] = other end
        end
    end
    if #list > 0 then
        triggerClientEvent(list, "rp:metaldetector:othersReveal", resourceRoot, spot.x, spot.y, spot.z, find.item, find.rarity)
    end
end

local function finishDig(p)
    local s = equipped[p]
    if not s or not s.digging or not isElement(p) then return end
    if isTimer(s.digging.timeout) then killTimer(s.digging.timeout) end
    s.digging = nil
    local spot = s.spot
    s.spot = nil

    local characterId = characterOf(p)
    if not characterId or not spot then return stopDigging(p) end
    local list = findsLog[characterId] or {}
    list[#list + 1] = getTickCount()
    findsLog[characterId] = list

    local itemId, amount = spot.item, spot.amount
    local where = givePlayerItem(p, itemId, amount)
    if not where then log(("no se pudo entregar %s a %s"):format(itemId, getPlayerName(p)), 2) end
    local find = METALDETECTOR_FIND_BY_ITEM[itemId] or { item = itemId, rarity = "common" }
    local rarity = C.RARITIES[find.rarity] or C.RARITIES.common
    local times, isNew = recordFind(characterId, itemId)
    local levelBefore, levelAfter = addProgress(characterId, rarity.dxp, amount, 0)
    local distinct = collectionStats(characterId)
    local def = exports.rp_inventory:getItemDefinition(itemId)
    local price = try("rp_jobs", "getMarketPrice", C.MARKET_ID, itemId)
    if rarity.xp > 0 then try("rp_levels", "giveXP", p, rarity.xp, "Detector de metales") end
    -- Logros (rp_achievements): hallazgos, colección distinta y legendarios
    triggerEvent("rp:achievements:progress", p, "metal_finds", 1)
    triggerEvent("rp:achievements:progress", p, "metal_distinct", distinct)
    if find.rarity == "legendary" then triggerEvent("rp:achievements:progress", p, "metal_legendary", 1) end

    triggerClientEvent(p, "rp:metaldetector:reveal", resourceRoot, {
        item = itemId, amount = amount, name = def and def.name or itemId, rarity = find.rarity,
        isNew = isNew, times = times, distinct = distinct, finds = #C.FINDS,
        price = price or false, xp = rarity.dxp, ground = where == "ground",
        levelUp = (levelBefore and levelAfter and levelAfter > levelBefore) and levelAfter or false,
        x = spot.x, y = spot.y, z = spot.z,
    })
    if rarity.order >= 3 then broadcastReveal(p, spot, find) end
    if levelBefore and levelAfter and levelAfter > levelBefore then
        local unlocked = C.TIERS[levelAfter]
        exports.rp_notify:popup(p, ("¡Nivel %d de buscador!"):format(levelAfter),
            unlocked and ("Ya puedes comprar el detector %s en el puesto de la playa."):format(unlocked.name) or "Has llegado al nivel máximo.", "success")
    end
    log(("%s encontró %dx %s (%s) con el detector %d"):format(getPlayerName(p), amount, itemId, find.rarity, s.tier))

    -- La pala se queda en la mano mientras el jugador mira el hallazgo; luego vuelve el detector
    s.resume = setTimer(function()
        local st = equipped[p]
        if not st or not isElement(p) then return end
        st.resume = nil
        destroyProp(st.shovel)
        st.shovel = nil
        setElementFrozen(p, false)
        setPedAnimation(p)
        local tier = C.TIERS[st.tier]
        if not tier or not hasPlayerItem(p, tier.item) then return unequip(p, "Ya no llevas el detector.") end
        showDetector(p, st.tier)
        sendState(p)
    end, rarity.closeup and 4200 or 2600, 1)
end

local function armStrokeTimeout(p)
    local s = equipped[p]
    if not s or not s.digging then return end
    if isTimer(s.digging.timeout) then killTimer(s.digging.timeout) end
    s.digging.timeout = setTimer(function()
        stopDigging(p, "Dejas de cavar. El objeto sigue ahí: pulsa E para seguir.")
    end, C.STROKE_TIMEOUT_MS, 1)
end

addEventHandler("rp:metaldetector:startDig", resourceRoot, function()
    local p = client
    local s = equipped[p]
    if not s or s.digging or isTimer(s.resume) or not s.spot then return end

    local now = getTickCount()
    if lastDig[p] and now - lastDig[p] < C.DIG_COOLDOWN_MS then
        return notify(p, "Recupera el aliento un momento antes de volver a cavar.", "info")
    end

    -- Margen de 0,75 m sobre el radio del cliente (posición y latencia)
    local px, py = getElementPosition(p)
    if dist2D(px, py, s.spot.x, s.spot.y) > C.DIG_RADIUS + 0.75 then
        return notify(p, "Estás un poco lejos de la señal: acércate hasta que el tono sea continuo.", "info")
    end
    local why = blockedReason(p)
    if why then return notify(p, why, "error") end
    if not hasPlayerItem(p, C.SHOVEL_ITEM) then
        triggerClientEvent(p, "rp:metaldetector:dig", resourceRoot, "noshovel")
        return notify(p, "Necesitas una pala para desenterrarlo. Se vende en el puesto de la playa.", "error")
    end
    local characterId = characterOf(p)
    if not characterId then return end
    if not underHourlyCap(characterId) then
        return notify(p, "Estás agotado de tanto excavar. Descansa un rato.", "warning")
    end

    lastDig[p] = now
    showDetector(p, nil)
    s.shovel = attachProp(p, C.SHOVEL_PROP)
    setElementFrozen(p, true)
    setPedAnimation(p, C.DIG_ANIM.block, C.DIG_ANIM.name, -1, true, false, false, false)
    s.digging = { progress = 0, need = s.spot.strokes, lastStroke = now }
    armStrokeTimeout(p)
    triggerClientEvent(p, "rp:metaldetector:dig", resourceRoot, "start", 0, s.digging.need)
end)

addEventHandler("rp:metaldetector:stroke", resourceRoot, function(good)
    local p = client
    local s = equipped[p]
    local d = s and s.digging
    if not d then return end
    local now = getTickCount()
    if now - d.lastStroke < C.STROKE_MIN_MS then return end   -- no se puede acelerar
    d.lastStroke = now
    d.progress = d.progress + (good == true and 1 or C.WEAK_STROKE)
    armStrokeTimeout(p)
    if d.progress >= d.need - 0.001 then
        finishDig(p)
    else
        triggerClientEvent(p, "rp:metaldetector:dig", resourceRoot, "progress", d.progress, d.need)
    end
end)

addEventHandler("rp:metaldetector:cancelDig", resourceRoot, function()
    stopDigging(client)
end)

----------------------------------------------------------------
-- Dinero ganado: ventas de lo encontrado en cualquier mercado de rp_jobs
----------------------------------------------------------------
addEventHandler("rp:jobs:onMarketSale", root, function(_, itemId, _, total)
    local characterId = characterOf(source)
    if not characterId or not METALDETECTOR_FIND_BY_ITEM[itemId] then return end
    total = math.floor(tonumber(total) or 0)
    if total > 0 then addProgress(characterId, 0, 0, total) end
end)

----------------------------------------------------------------
-- Panel (CEF): tienda, progreso y colección
----------------------------------------------------------------
local function nearShop(p)
    if not isElement(shop.ped) then return false end
    if getElementDimension(p) ~= getElementDimension(shop.ped) or getElementInterior(p) ~= getElementInterior(shop.ped) then return false end
    local x, y, z = getElementPosition(p)
    local sx, sy, sz = getElementPosition(shop.ped)
    return getDistanceBetweenPoints3D(x, y, z, sx, sy, sz) <= C.SHOP.radius + 1
end

local function panelData(p, tab)
    local characterId = characterOf(p)
    local pr = characterId and progress[characterId]
    local col = characterId and collections[characterId]
    if not pr or not col then return nil end
    local level, levelXp, nextXp = metalDetectorLevel(pr.xp)
    local distinct = collectionStats(characterId)
    local tiers = {}
    for i, t in ipairs(C.TIERS) do
        local st = metalDetectorStats(i)
        tiers[i] = {
            index = i, item = t.item, name = t.name, price = t.price, level = t.level, color = t.color, desc = t.desc,
            radius = t.radius, depth = t.depth, accuracy = t.accuracy,
            range = math.floor(st.range + 0.5), maxDepth = math.floor(st.maxDepth + 0.5),
            owned = hasPlayerItem(p, t.item), locked = level < t.level,
        }
    end
    local collection = {}
    for _, f in ipairs(C.FINDS) do
        local def = exports.rp_inventory:getItemDefinition(f.item)
        local rar = C.RARITIES[f.rarity]
        collection[#collection + 1] = {
            item = f.item, name = def and def.name or f.item, rarity = rar.name, order = rar.order,
            color = ("#%02x%02x%02x"):format(rar.color[1], rar.color[2], rar.color[3]), depth = f.depth,
            times = col[f.item] or 0, price = try("rp_jobs", "getMarketPrice", C.MARKET_ID, f.item) or false,
        }
    end
    return {
        tab = tab, canShop = nearShop(p), money = getPlayerMoney(p),
        level = level, maxLevel = #C.LEVEL_XP, xp = pr.xp, levelXp = levelXp, nextXp = nextXp or false,
        itemsFound = pr.items, moneyEarned = pr.money, distinct = distinct, finds = #C.FINDS,
        tiers = tiers, shovel = { price = C.SHOVEL_PRICE, owned = hasPlayerItem(p, C.SHOVEL_ITEM) },
        collection = collection, equipped = equipped[p] and equipped[p].tier or false,
    }
end

local function openPanel(p, tab)
    local data = panelData(p, tab)
    if not data then return notify(p, "Tu progreso aún se está cargando. Prueba en unos segundos.", "info") end
    triggerClientEvent(p, "rp:metaldetector:panel", resourceRoot, data)
end

addEventHandler("rp:metaldetector:openShop", resourceRoot, function()
    local p = client
    if not characterOf(p) or not nearShop(p) then return end
    openPanel(p, "shop")
end)

-- Compra: kind = "tier" (índice 1..5) o "shovel". Valida cercanía, nivel, peso y dinero; cobra y entrega.
addEventHandler("rp:metaldetector:buy", resourceRoot, function(kind, index)
    local p = client
    local characterId = characterOf(p)
    if not characterId or not progress[characterId] then return end
    local now = getTickCount()
    if lastBuy[p] and now - lastBuy[p] < L.BUY_COOLDOWN_MS then return end
    lastBuy[p] = now
    if not nearShop(p) then return notify(p, "Acércate al vendedor.", "warning") end
    if blockedReason(p) then return end

    local itemId, price, name
    if kind == "shovel" then
        itemId, price, name = C.SHOVEL_ITEM, C.SHOVEL_PRICE, "la pala"
    elseif kind == "tier" then
        local t = C.TIERS[tonumber(index) or 0]
        if not t then return end
        if metalDetectorLevel(progress[characterId].xp) < t.level then
            return notify(p, ("Necesitas nivel %d de buscador para el %s."):format(t.level, t.name), "error")
        end
        itemId, price, name = t.item, t.price, "el detector " .. t.name
    else
        return
    end
    if hasPlayerItem(p, itemId) then return notify(p, "Ya tienes " .. name .. ".", "info") end
    local ok, why = exports.rp_inventory:canCarry(p, itemId, 1)
    if not ok then return notify(p, why or "No te cabe en el inventario.", "error") end
    if getPlayerMoney(p) < price then return notify(p, "No tienes suficiente efectivo.", "error") end

    -- Cobrar primero; si la entrega falla, devolver
    takePlayerMoney(p, price)
    if not exports.rp_inventory:giveItem(p, itemId, 1) then
        givePlayerMoney(p, price)
        exports.rp_characters:saveCharacter(p)
        return notify(p, "No se pudo completar la compra.", "error")
    end
    exports.rp_characters:saveCharacter(p)
    log(("%s compró %s por $%d"):format(getPlayerName(p), itemId, price))
    notify(p, ("Compraste %s por $%d. Úsalo desde el inventario (I)."):format(name, price), "success")
    triggerClientEvent(p, "rp:metaldetector:bought", resourceRoot, kind, tonumber(index) or 0)
    openPanel(p, "shop")
end)

addCommandHandler("detector", function(p) if characterOf(p) then openPanel(p, "progress") end end)
addCommandHandler("hallazgos", function(p) if characterOf(p) then openPanel(p, "collection") end end)

----------------------------------------------------------------
-- Desequipar solo: vehículo, abatido, logout, salida, item perdido
----------------------------------------------------------------
addEventHandler("onPlayerVehicleEnter", root, function()
    if equipped[source] then unequip(source, "Guardas el detector al subir al vehículo.") end
end)
addEventHandler("rp:onPlayerDowned", root, function() unequip(source) end)
addEventHandler("onPlayerWasted", root, function() unequip(source) end)
addEventHandler("rp:onCharacterLogout", root, function(characterId)
    unequip(source)
    unloadCharacter(characterId)
end)
addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    if characterId then loadCharacter(characterId) end
end)
addEventHandler("onPlayerQuit", root, function()
    local characterId = characterOf(source)
    unequip(source)
    lastDig[source], lastBuy[source] = nil, nil
    unloadCharacter(characterId)
end)

-- Si el detector sale del inventario (soltado, vendido, entregado) o cambias de dimensión, se apaga
setTimer(function()
    for p, s in pairs(equipped) do
        if not isElement(p) then
            equipped[p] = nil
        elseif not s.digging and not isTimer(s.resume) then
            local tier = C.TIERS[s.tier]
            if not tier or not hasPlayerItem(p, tier.item) then
                unequip(p, "Ya no llevas el detector.")
            elseif getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then
                unequip(p)
            end
        end
    end
end, 2000, 0)

----------------------------------------------------------------
-- Vendedor. Posición movible con el editor (rp_markers, clave "shop"); el cliente lo encuentra
-- por elementData rp:mdShop y muestra «Pulsa E».
----------------------------------------------------------------
local function spawnShop()
    if isElement(shop.ped) then destroyElement(shop.ped) end
    local sh = C.SHOP
    local x, y, z = sh.x, sh.y, sh.z
    local ok, mx, my, mz = pcall(function() return exports.rp_markers:placePoint("shop", sh.x, sh.y, sh.z) end)
    if ok and mx then x, y, z = mx, my, mz end

    shop.ped = createPed(sh.skin, x, y, z, sh.rot)
    if not shop.ped then return log("no se pudo crear el vendedor", 1) end
    setElementFrozen(shop.ped, true)
    setElementInterior(shop.ped, sh.interior)
    setElementDimension(shop.ped, sh.dimension)
    setElementData(shop.ped, "rp:mdShop", true)
    pcall(function()
        exports.rp_markers:registerPoint("shop", { label = "Detector de metales · " .. sh.name, point = { x, y, z },
            interior = sh.interior, dimension = sh.dimension })
    end)
end

addEvent("rp:markers:moved")
addEvent("rp:markers:ready")
addEventHandler("rp:markers:moved", root, function(owner, key)
    if owner == getResourceName(resource) and key == "shop" then spawnShop() end
end)
addEventHandler("rp:markers:ready", root, spawnShop)

----------------------------------------------------------------
-- Admin: ID de material bajo los pies (lo mide el cliente)
----------------------------------------------------------------
addCommandHandler("detectorsuelo", function(p)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    triggerClientEvent(p, "rp:metaldetector:debugSurface", resourceRoot)
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
-- Tabla de botín (pruebas de rp_test y otros recursos)
function getMetalDetectorLoot() return METALDETECTOR_LOOT end

function isPlayerDetecting(p)
    return equipped[p] ~= nil
end

function getPlayerDetectorLevel(p)
    local characterId = characterOf(p)
    local pr = characterId and progress[characterId]
    return pr and (metalDetectorLevel(pr.xp)) or false
end

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
local function boot()
    for _, p in ipairs(getElementsByType("player")) do
        local characterId = characterOf(p)
        if characterId then loadCharacter(characterId) end
        if isDetectorHeld(p) then removeElementData(p, "rp:heldItem") end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, t in ipairs(C.TIERS) do
        if not exports.rp_inventory:getItemDefinition(t.item) then log("falta el item '" .. t.item .. "' en rp_inventory", 1) end
    end
    if not exports.rp_inventory:getItemDefinition(C.SHOVEL_ITEM) then log("falta el item '" .. C.SHOVEL_ITEM .. "'", 1) end
    for _, e in ipairs(METALDETECTOR_LOOT) do
        if not exports.rp_inventory:getItemDefinition(e.item) then log("falta el item de botín '" .. e.item .. "'", 1) end
        if not METALDETECTOR_FIND_BY_ITEM[e.item] then log("'" .. e.item .. "' no está en METALDETECTOR.FINDS", 1) end
    end
    spawnShop()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- Ped y pala se destruyen solos con el recurso; devolver lo tocado en los jugadores
    for p, s in pairs(equipped) do
        if isElement(p) then
            if isDetectorHeld(p) then removeElementData(p, "rp:heldItem") end
            if s.digging or isTimer(s.resume) then
                setElementFrozen(p, false)
                setPedAnimation(p)
            end
        end
    end
end)
