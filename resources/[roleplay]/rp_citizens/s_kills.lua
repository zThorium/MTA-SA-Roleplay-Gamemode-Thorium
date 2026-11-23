--[[
    rp_citizens / s_kills.lua
    Matar a un peaton (existe solo en el cliente) cuesta cordura y puede soltar dinero.
    El cliente solo avisa de la muerte; aqui se limita el ritmo, se decide el botin y se
    comprueba la distancia al recogerlo.
]]

local CFG = {
    MAX_KILL_DIST = 150,          -- m entre el jugador y la muerte (francotirador incluido)
    MIN_INTERVAL = 700,           -- ms entre avisos de muerte
    LOOT_WINDOW = 60000,          -- ventana para limitar botines
    LOOT_MAX = 5,                 -- botines por ventana (evita farmear)
    LOOT_TTL = 90000,             -- ms que dura el dinero en el suelo
    COLLECT_DIST = 6,
    SANITY_KILL = 6,              -- cordura que cuesta cada muerte
    SANITY_SPREE = 4,             -- extra si ya mato a 3+ en LOOT_WINDOW
    CASH = { 5, 45 },             -- cartera normal
    RICH_CHANCE = 0.08,
    RICH_CASH = { 100, 250 },
}

addEvent("rp:citizens:killed", true)
addEvent("rp:citizens:collect", true)
addEvent("rp:citizens:drop", true)
addEvent("rp:onCharacterLogout", false)

local state = {}      -- [player] = { last = ms, kills = { ms... }, drops = { [id] = {amount,x,y,z,exp} }, nextId = n }

local function get(player)
    local st = state[player]
    if not st then st = { last = 0, kills = {}, drops = {}, nextId = 1 } state[player] = st end
    return st
end

addEventHandler("onPlayerQuit", root, function() state[source] = nil end)
addEventHandler("rp:onCharacterLogout", root, function() state[source] = nil end)

addEventHandler("rp:citizens:killed", resourceRoot, function(x, y, z)
    local player = client
    if not isElement(player) or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return end
    if not exports.rp_characters:getPlayerCharacterId(player) or isPedDead(player) then return end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > CFG.MAX_KILL_DIST then return end

    local now = getTickCount()
    local st = get(player)
    if now - st.last < CFG.MIN_INTERVAL then return end
    st.last = now

    -- Muertes recientes (para la racha y el limite de botines)
    local recent = {}
    for _, t in ipairs(st.kills) do if now - t < CFG.LOOT_WINDOW then recent[#recent + 1] = t end end
    local spree = #recent >= 3
    local canLoot = #recent < CFG.LOOT_MAX
    recent[#recent + 1] = now
    st.kills = recent

    exports.rp_needs:addSanity(player, -(CFG.SANITY_KILL + (spree and CFG.SANITY_SPREE or 0)), true)

    if not canLoot then return end
    local range = math.random() < CFG.RICH_CHANCE and CFG.RICH_CASH or CFG.CASH
    local id = st.nextId
    st.nextId = id + 1
    st.drops[id] = { amount = math.random(range[1], range[2]), x = x, y = y, z = z, exp = now + CFG.LOOT_TTL }
    triggerClientEvent(player, "rp:citizens:drop", resourceRoot, id, x, y, z)
end)

addEventHandler("rp:citizens:collect", resourceRoot, function(id)
    local player = client
    local st = isElement(player) and state[player]
    local drop = st and st.drops[id]
    if not drop then return end
    st.drops[id] = nil
    if getTickCount() > drop.exp then return end
    local px, py, pz = getElementPosition(player)
    if isPedDead(player) or getDistanceBetweenPoints3D(px, py, pz, drop.x, drop.y, drop.z) > CFG.COLLECT_DIST then return end
    givePlayerMoney(player, drop.amount)
    exports.rp_notify:notify(player, ("Recoges $%d de la cartera."):format(drop.amount), "success")
end)

----------------------------------------------------------------
-- Pandilleros que te sacan del auto (c_gangs.lua)
-- El cliente lo pide cuando varios te rodean con el auto casi parado. Solo afecta al propio
-- jugador, asi que se valida lo basico (en un auto, casi parado, con espera entre peticiones).
----------------------------------------------------------------
addEvent("rp:citizens:pullOut", true)
local lastPull = {}

addEventHandler("rp:citizens:pullOut", resourceRoot, function()
    local player = client
    if not isElement(player) or not exports.rp_characters:getPlayerCharacterId(player) or isPedDead(player) then return end
    local vehicle = getPedOccupiedVehicle(player)
    if not vehicle then return end
    local vx, vy = getElementVelocity(vehicle)
    if math.sqrt(vx * vx + vy * vy) * 180 > 20 then return end
    local now = getTickCount()
    if lastPull[player] and now - lastPull[player] < 8000 then return end
    lastPull[player] = now

    removePedFromVehicle(player)
    setPedAnimation(player, "ped", "FLOOR_hit_f", -1, false, false, false, false)
    setTimer(function() if isElement(player) and not isPedDead(player) then setPedAnimation(player) end end, 1800, 1)
    exports.rp_notify:notify(player, "Te sacaron del auto a la fuerza.", "error")
end)

addEventHandler("onPlayerQuit", root, function() lastPull[source] = nil end)
