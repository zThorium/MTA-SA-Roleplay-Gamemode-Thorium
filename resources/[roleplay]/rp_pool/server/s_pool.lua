--[[
    rp_pool / server / s_pool.lua

    Pool 8-ball multijugador con apuestas, como el de GTA San Andreas.

    - Mesas: las 3 originales de Ten Green Bottles (interior 11) y las que coloquen los admins.
    - Una partida es 1 contra 1. Quien crea la partida elige la apuesta; el rival acepta
      (o no). Las dos apuestas quedan en custodia (pool_escrow) y el ganador cobra el bote.
    - El servidor simula cada tiro (s_physics.lua) y envia el replay a los clientes.
    - Ranking global en pool_stats: mas victorias y mas dinero ganado en apuestas.

    Comandos:
        /poolranking               abre el ranking global
        /crearmesapool             (admin) coloca una mesa delante de ti
        /borrarmesapool <id>       (admin) borra una mesa
        /mesaspool                 (admin) lista las mesas

    Exports: getPlayerPoolTable(player) -> id de mesa o false
]]

local floor = math.floor

local tables = {}        -- [id] = T
local playerTable = {}   -- [player] = tableId (esperando o jugando)
local nearTable = {}     -- [player] = tableId
local doorCooldown = {}  -- [player] = tick

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:pool:requestSync", true)
addEvent("rp:pool:open", true)
addEvent("rp:pool:create", true)
addEvent("rp:pool:join", true)
addEvent("rp:pool:leave", true)
addEvent("rp:pool:forfeit", true)
addEvent("rp:pool:shoot", true)
addEvent("rp:pool:place", true)
addEvent("rp:pool:aim", true)
addEvent("rp:pool:requestBoard", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= POOL.ADMIN_LEVEL end
local function nameOf(p)
    return exports.rp_characters:getPlayerCharacterName(p) or (getPlayerName(p):gsub("_", " "))
end
local function money(n) return "$" .. tostring(n):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "") end

----------------------------------------------------------------
-- Serializacion de estado hacia los clientes
----------------------------------------------------------------
local function ballsFlat(T)
    local f = {}
    for b = 0, 15 do
        local ball = T.balls[b]
        f[#f + 1] = floor(ball.u * 1000 + 0.5)
        f[#f + 1] = floor(ball.v * 1000 + 0.5)
        f[#f + 1] = ball.p and 1 or 0
    end
    return f
end

local function tableInfo(T)
    return { id = T.id, x = T.x, y = T.y, z = T.z, rz = T.rz, interior = T.interior,
             dimension = T.dimension, native = T.native }
end

local function stateOf(T)
    local s = { id = T.id, status = T.status, balls = ballsFlat(T) }
    local m = T.match
    if T.status == "waiting" and T.waiting then
        s.bet = T.waiting.bet
        s.names = { T.waiting.name }
    elseif T.status == "playing" and m then
        s.bet = m.bet
        s.names = { m.names[1], m.names[2] }
        s.turn = m.turn
        s.groups = { m.groups[1] or false, m.groups[2] or false }
        s.bih = m.bih
        s.busy = m.busy
        if m.turnStart then
            s.left = math.max(0, POOL.TURN_SECONDS - floor((getTickCount() - m.turnStart) / 1000))
        end
    end
    return s
end

local function broadcastState(T)
    triggerClientEvent(root, "rp:pool:state", resourceRoot, stateOf(T))
end

local function nearbyPlayers(T, range)
    local out, seen = {}, {}
    local m = T.match
    if m then
        for i = 1, 2 do
            local p = m.players[i]
            if isElement(p) then out[#out + 1] = p; seen[p] = true end
        end
    end
    if T.waiting and isElement(T.waiting.player) and not seen[T.waiting.player] then
        out[#out + 1] = T.waiting.player
        seen[T.waiting.player] = true
    end
    for _, p in ipairs(getElementsByType("player")) do
        if not seen[p] and getElementInterior(p) == T.interior and getElementDimension(p) == T.dimension then
            local px, py, pz = getElementPosition(p)
            local dx, dy, dz = px - T.x, py - T.y, pz - T.z
            if dx * dx + dy * dy + dz * dz < range * range then out[#out + 1] = p end
        end
    end
    return out
end

----------------------------------------------------------------
-- Dinero en custodia
----------------------------------------------------------------
local function takeStake(player, amount, tid)
    if amount <= 0 then return true end
    if getPlayerMoney(player) < amount then return false end
    takePlayerMoney(player, amount)
    dbExec(db(), "REPLACE INTO pool_escrow (character_id, amount, table_id) VALUES (?, ?, ?)", characterOf(player), amount, tid)
    exports.rp_characters:saveCharacter(player)
    return true
end

local function clearEscrow(cid)
    if cid then dbExec(db(), "DELETE FROM pool_escrow WHERE character_id = ?", cid) end
end

-- Devuelve dinero a un jugador (online) o directo a la BD (si ya se desconecto)
local function payOut(player, cid, amount)
    if amount > 0 then
        if isElement(player) and characterOf(player) == cid then
            givePlayerMoney(player, amount)
            exports.rp_characters:saveCharacter(player)
        else
            dbExec(db(), "UPDATE characters SET money = money + ? WHERE id = ?", amount, cid)
        end
    end
    clearEscrow(cid)
end

----------------------------------------------------------------
-- Ranking
----------------------------------------------------------------
local function recordResult(wc, wn, lc, ln, bet, reason)
    dbExec(db(), [[INSERT INTO pool_stats (character_id, name, games, wins, losses, money_won, money_lost, best_win)
        VALUES (?, ?, 1, 1, 0, ?, 0, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), games = games + 1, wins = wins + 1,
            money_won = money_won + VALUES(money_won), best_win = GREATEST(best_win, VALUES(best_win))]],
        wc, wn, bet, bet)
    dbExec(db(), [[INSERT INTO pool_stats (character_id, name, games, wins, losses, money_won, money_lost, best_win)
        VALUES (?, ?, 1, 0, 1, 0, ?, 0)
        ON DUPLICATE KEY UPDATE name = VALUES(name), games = games + 1, losses = losses + 1,
            money_lost = money_lost + VALUES(money_lost)]],
        lc, ln, bet)
    dbExec(db(), "INSERT INTO pool_matches (winner_id, loser_id, winner_name, loser_name, bet, reason) VALUES (?, ?, ?, ?, ?, ?)",
        wc, lc, wn, ln, bet, reason)
end

local WINS_SQL = [[SELECT name, wins, losses, games, money_won FROM pool_stats
    ORDER BY wins DESC, games ASC, character_id ASC LIMIT ?]]
local MONEY_SQL = [[SELECT name, wins, games, money_won FROM pool_stats
    ORDER BY money_won DESC, games ASC, character_id ASC LIMIT ?]]
local ME_SQL = [[SELECT s.name, s.wins, s.losses, s.games, s.money_won, s.money_lost, s.best_win,
    (SELECT COUNT(*) FROM pool_stats o WHERE o.wins > s.wins OR (o.wins = s.wins AND o.games < s.games)) + 1 AS rank_wins,
    (SELECT COUNT(*) FROM pool_stats o WHERE o.money_won > s.money_won OR (o.money_won = s.money_won AND o.games < s.games)) + 1 AS rank_money
    FROM pool_stats s WHERE s.character_id = ?]]

local function sendBoard(player)
    local cid = characterOf(player)
    if not cid then return end
    local out = { wins = {}, money = {} }
    dbQuery(function(qh)
        out.wins = dbPoll(qh, 0) or {}
        dbQuery(function(qh2)
            out.money = dbPoll(qh2, 0) or {}
            dbQuery(function(qh3)
                local r = dbPoll(qh3, 0)
                out.me = r and r[1] or nil
                if isElement(player) then triggerClientEvent(player, "rp:pool:board", resourceRoot, out) end
            end, db(), ME_SQL, cid)
        end, db(), MONEY_SQL, POOL.RANK_SIZE)
    end, db(), WINS_SQL, POOL.RANK_SIZE)
end

----------------------------------------------------------------
-- Partida
----------------------------------------------------------------
local beginTurn

local function leftOf(T, group)
    local n = 0
    for b = 1, 15 do
        if not T.balls[b].p and poolGroupOf(b) == group then n = n + 1 end
    end
    return n
end

local function stopTimers(T)
    if isTimer(T.turnTimer) then killTimer(T.turnTimer) end
    if isTimer(T.shotTimer) then killTimer(T.shotTimer) end
    T.turnTimer, T.shotTimer = nil, nil
end

local function resetTable(T)
    stopTimers(T)
    T.status = "idle"
    T.match = nil
    T.waiting = nil
    PoolSim.rack(T.balls)
    broadcastState(T)
end

local function endMatch(T, winnerIdx, reason)
    local m = T.match
    if not m then return end
    local loserIdx = 3 - winnerIdx
    local pot = m.bet * 2
    local wp, lp = m.players[winnerIdx], m.players[loserIdx]
    local wc, lc = m.chars[winnerIdx], m.chars[loserIdx]
    local wn, ln = m.names[winnerIdx], m.names[loserIdx]

    payOut(wp, wc, pot)
    clearEscrow(lc)
    recordResult(wc, wn, lc, ln, m.bet, reason)

    local reasons = {
        eightball = "embocó la 8",
        eightfoul = "%s perdió al embocar la 8 antes de tiempo o con falta",
        forfeit = "%s abandonó la partida",
        timeout = "%s agotó el tiempo de sus turnos",
        quit = "%s se desconectó",
    }
    local why = reasons[reason] or ""
    if reason == "eightball" then why = wn .. " " .. why
    elseif why:find("%%s") then why = why:format(ln) end

    for i = 1, 2 do
        local p = m.players[i]
        if isElement(p) then
            playerTable[p] = nil
            triggerClientEvent(p, "rp:pool:matchEnd", resourceRoot, T.id, winnerIdx, m.bet, why)
            if i == winnerIdx then
                notify(p, ("Ganaste la partida de pool. %s"):format(m.bet > 0 and ("Cobras " .. money(pot) .. ".") or ""), "success")
            else
                notify(p, ("Perdiste la partida de pool. %s"):format(m.bet > 0 and ("Pierdes " .. money(m.bet) .. ".") or ""), "error")
            end
        end
    end
    for _, p in ipairs(nearbyPlayers(T, 12)) do
        if p ~= wp and p ~= lp then
            notify(p, ("%s ganó a %s en el pool%s."):format(wn, ln, m.bet > 0 and (" y se lleva " .. money(pot)) or ""), "info")
        end
    end
    resetTable(T)
end

local function cancelWaiting(T, msg)
    local w = T.waiting
    if not w then return end
    payOut(w.player, w.char, w.bet)
    if isElement(w.player) then
        playerTable[w.player] = nil
        triggerClientEvent(w.player, "rp:pool:matchEnd", resourceRoot, T.id, 0, 0, "")
        if msg then notify(w.player, msg, "warning") end
    end
    resetTable(T)
end

local function startMatch(T, p1, p2)
    local w = T.waiting
    T.waiting = nil
    local players, chars, names = { w.player, p2 }, { w.char, characterOf(p2) }, { w.name, nameOf(p2) }
    -- Quien rompe se decide al azar
    if math.random(2) == 2 then
        players[1], players[2] = players[2], players[1]
        chars[1], chars[2] = chars[2], chars[1]
        names[1], names[2] = names[2], names[1]
    end
    PoolSim.rack(T.balls)
    T.status = "playing"
    T.match = {
        players = players, chars = chars, names = names, bet = w.bet,
        turn = 1, groups = {}, bih = false, breakShot = true, busy = false,
        timeouts = {},
    }
    for i = 1, 2 do
        playerTable[players[i]] = T.id
        setPedWeaponSlot(players[i], 0)   -- sin arma en mano (no se oculta con alpha)
        triggerClientEvent(players[i], "rp:pool:matchStart", resourceRoot, T.id, i, players[3 - i])
    end
    notify(players[1], "Rompes tú. ¡Suerte!", "info")
    notify(players[2], ("Rompe %s."):format(names[1]), "info")
    beginTurn(T)
end

local function onTurnTimeout(tid)
    local T = tables[tid]
    local m = T and T.match
    if not m or m.busy then return end
    local idx = m.turn
    m.timeouts[idx] = (m.timeouts[idx] or 0) + 1
    if m.timeouts[idx] >= POOL.MAX_TIMEOUTS then
        endMatch(T, 3 - idx, "timeout")
        return
    end
    local p = m.players[idx]
    if isElement(p) then notify(p, "Se acabó tu tiempo: falta y pierdes el turno.", "warning") end
    m.turn = 3 - idx
    m.bih = true
    beginTurn(T)
end

beginTurn = function(T)
    local m = T.match
    if not m then return end
    m.busy = false
    if isTimer(T.turnTimer) then killTimer(T.turnTimer) end
    m.turnStart = getTickCount()
    T.turnTimer = setTimer(onTurnTimeout, POOL.TURN_SECONDS * 1000, 1, T.id)
    broadcastState(T)
    for i = 1, 2 do
        local p = m.players[i]
        if isElement(p) then
            triggerClientEvent(p, "rp:pool:turn", resourceRoot, T.id, m.turn, m.bih, POOL.TURN_SECONDS)
        end
    end
    local shooter = m.players[m.turn]
    if isElement(shooter) then
        if m.bih then notify(shooter, "Bola en mano: coloca la blanca donde quieras.", "info") end
    end
end

-- Aplica las reglas tras un tiro (se llama cuando termina la animacion en los clientes)
local function finishShot(tid, res, pre)
    local T = tables[tid]
    local m = T and T.match
    if not m then return end
    local idx = m.turn
    local opp = 3 - idx
    local shooter = m.players[idx]

    local out = PoolRules.evaluate({
        group = m.groups[idx], breakShot = m.breakShot, left = pre.left, res = res,
    })

    if out.eight == "rerack" then
        -- La 8 en el saque: se vuelve a armar y rompe el mismo jugador
        PoolSim.rack(T.balls)
        m.bih = false
        for i = 1, 2 do
            if isElement(m.players[i]) then notify(m.players[i], "Cayó la 8 en el saque: se arma de nuevo.", "warning") end
        end
        beginTurn(T)
        return
    elseif out.eight == "win" then
        return endMatch(T, idx, "eightball")
    elseif out.eight == "loss" then
        return endMatch(T, opp, "eightfoul")
    end

    if out.assign then
        m.groups[idx] = out.assign
        m.groups[opp] = (out.assign == "solid") and "stripe" or "solid"
        if isElement(shooter) then
            notify(shooter, ("Tienes las %s."):format(out.assign == "solid" and "lisas" or "rayadas"), "success")
        end
        local o = m.players[opp]
        if isElement(o) then
            notify(o, ("Tienes las %s."):format(out.assign == "solid" and "rayadas" or "lisas"), "info")
        end
    end

    m.breakShot = false
    m.timeouts[idx] = 0
    if out.foul then
        for i = 1, 2 do
            local p = m.players[i]
            if isElement(p) then
                notify(p, ("Falta de %s: %s. Bola en mano para %s."):format(m.names[idx], out.reason, m.names[opp]), "warning")
            end
        end
        m.turn, m.bih = opp, true
    elseif out.continue then
        m.bih = false
    else
        m.turn, m.bih = opp, false
    end
    beginTurn(T)
end

local function snapshotLeft(T)
    return { left = { solid = leftOf(T, "solid"), stripe = leftOf(T, "stripe") } }
end

----------------------------------------------------------------
-- Eventos del cliente
----------------------------------------------------------------
local function playerCanUse(player, tid)
    if not characterOf(player) then return false end
    if exports.rp_characters:getPlayerCharacterId(player) == nil then return false end
    if getElementData(player, "rp:downed") then return false end
    local T = tables[tid]
    if not T then return false end
    if nearTable[player] ~= tid then return false end
    if getElementInterior(player) ~= T.interior or getElementDimension(player) ~= T.dimension then return false end
    local px, py, pz = getElementPosition(player)
    local dx, dy, dz = px - T.x, py - T.y, pz - T.z
    if dx * dx + dy * dy + dz * dz > (POOL.INTERACT_RADIUS + 1.5) ^ 2 then return false end
    return true
end

addEventHandler("rp:pool:requestSync", root, function()
    local list, states = {}, {}
    for _, T in pairs(tables) do
        list[#list + 1] = tableInfo(T)
        states[#states + 1] = stateOf(T)
    end
    triggerClientEvent(client, "rp:pool:tables", resourceRoot, list, states)
end)

addEventHandler("rp:pool:open", root, function(tid)
    tid = tonumber(tid)
    if not tid or not playerCanUse(client, tid) then return end
    local T = tables[tid]
    local mine = (playerTable[client] == tid) and (T.status == "playing" and "playing" or "waiting") or "none"
    triggerClientEvent(client, "rp:pool:show", resourceRoot, {
        tableId = tid,
        status = T.status,
        mine = mine,
        bet = (T.waiting and T.waiting.bet) or (T.match and T.match.bet) or 0,
        waitingName = T.waiting and T.waiting.name or nil,
        busyWith = playerTable[client] and playerTable[client] ~= tid or false,
        money = getPlayerMoney(client),
        bets = POOL.BETS,
        maxBet = POOL.MAX_BET,
    })
end)

addEventHandler("rp:pool:create", root, function(tid, bet)
    tid, bet = tonumber(tid), tonumber(bet)
    if not tid or not bet or bet < 0 or bet > POOL.MAX_BET or bet ~= floor(bet) then return end
    if not playerCanUse(client, tid) then return end
    local T = tables[tid]
    if T.status ~= "idle" then return notify(client, "Esta mesa ya está ocupada.", "warning") end
    if playerTable[client] then return notify(client, "Ya estás en una partida de pool.", "warning") end
    if not takeStake(client, bet, tid) then
        return notify(client, "No tienes suficiente dinero en mano para esa apuesta.", "error")
    end
    T.status = "waiting"
    T.waiting = { player = client, char = characterOf(client), name = nameOf(client), bet = bet }
    playerTable[client] = tid
    notify(client, bet > 0 and ("Apuesta de %s puesta. Esperando rival..."):format(money(bet)) or "Partida amistosa creada. Esperando rival...", "success")
    broadcastState(T)
    triggerClientEvent(client, "rp:pool:waiting", resourceRoot, tid, bet)
    for _, p in ipairs(nearbyPlayers(T, 15)) do
        if p ~= client then
            notify(p, ("%s busca rival en el pool%s. Pulsa E en la mesa para unirte."):format(T.waiting.name, bet > 0 and (" (apuesta " .. money(bet) .. ")") or ""), "info")
        end
    end
end)

addEventHandler("rp:pool:join", root, function(tid)
    tid = tonumber(tid)
    if not tid or not playerCanUse(client, tid) then return end
    local T = tables[tid]
    if T.status ~= "waiting" or not T.waiting then return notify(client, "Nadie espera rival en esta mesa.", "warning") end
    if T.waiting.player == client then return end
    if playerTable[client] then return notify(client, "Ya estás en una partida de pool.", "warning") end
    if not isElement(T.waiting.player) then return cancelWaiting(T) end
    local bet = T.waiting.bet
    if not takeStake(client, bet, tid) then
        return notify(client, ("Necesitas %s en mano para aceptar la apuesta."):format(money(bet)), "error")
    end
    startMatch(T, T.waiting.player, client)
end)

addEventHandler("rp:pool:leave", root, function()
    local tid = playerTable[client]
    local T = tid and tables[tid]
    if T and T.status == "waiting" and T.waiting and T.waiting.player == client then
        cancelWaiting(T, "Cancelaste la partida. Te devolvimos tu apuesta.")
    end
end)

addEventHandler("rp:pool:forfeit", root, function()
    local tid = playerTable[client]
    local T = tid and tables[tid]
    local m = T and T.match
    if not m or m.busy then return end
    for i = 1, 2 do
        if m.players[i] == client then return endMatch(T, 3 - i, "forfeit") end
    end
end)

addEventHandler("rp:pool:shoot", root, function(angle, power)
    local tid = playerTable[client]
    local T = tid and tables[tid]
    local m = T and T.match
    if not m or m.busy or m.players[m.turn] ~= client or m.bih then return end
    angle, power = tonumber(angle), tonumber(power)
    if not angle or not power or angle ~= angle or power ~= power then return end
    power = math.max(0, math.min(1, power))
    local cue = T.balls[0]
    if cue.p then return end

    m.busy = true
    if isTimer(T.turnTimer) then killTimer(T.turnTimer) end
    local pre = snapshotLeft(T)
    local speed = POOL.MIN_SPEED + (POOL.MAX_SPEED - POOL.MIN_SPEED) * power
    local res = PoolSim.run(T.balls, angle, speed)

    local payload = { tableId = T.id, tracks = res.tracks, events = res.events, frames = res.frames,
                      angle = angle, power = power, shooter = m.turn }
    for _, p in ipairs(nearbyPlayers(T, POOL.STREAM_RANGE)) do
        triggerClientEvent(p, "rp:pool:replay", resourceRoot, payload)
    end
    broadcastState(T)  -- marca busy; los clientes aplican las posiciones al acabar el replay

    local ms = floor(res.frames / POOL.FRAME_RATE * 1000) + 900
    T.shotTimer = setTimer(function() finishShot(T.id, res, pre) end, ms, 1)
end)

addEventHandler("rp:pool:place", root, function(u, v)
    local tid = playerTable[client]
    local T = tid and tables[tid]
    local m = T and T.match
    if not m or m.busy or m.players[m.turn] ~= client or not m.bih then return end
    u, v = tonumber(u), tonumber(v)
    if not u or not v then return end
    local cue = T.balls[0]
    local wasPocketed = cue.p
    cue.p = true   -- no cuenta como obstaculo de si misma
    if not PoolSim.canPlace(T.balls, u, v) then
        cue.p = wasPocketed
        return triggerClientEvent(client, "rp:pool:placeDenied", resourceRoot, tid)
    end
    cue.u, cue.v, cue.p, cue.vx, cue.vy = u, v, false, 0, 0
    m.bih = false
    broadcastState(T)
    triggerClientEvent(client, "rp:pool:turn", resourceRoot, T.id, m.turn, false, POOL.TURN_SECONDS)
end)

-- La direccion/fuerza de apuntado se reenvia a los espectadores para que vean el taco
local lastAim = {}
addEventHandler("rp:pool:aim", root, function(theta, power)
    local tid = playerTable[client]
    local T = tid and tables[tid]
    local m = T and T.match
    if not m or m.busy or m.players[m.turn] ~= client then return end
    theta, power = tonumber(theta), tonumber(power)
    if not theta or not power then return end
    local now = getTickCount()
    if lastAim[client] and now - lastAim[client] < 80 then return end
    lastAim[client] = now
    for _, p in ipairs(nearbyPlayers(T, POOL.STREAM_RANGE)) do
        if p ~= client then triggerClientEvent(p, "rp:pool:aimSync", resourceRoot, tid, theta, math.max(0, math.min(1, power))) end
    end
end)

addEventHandler("rp:pool:requestBoard", root, function() sendBoard(client) end)

addCommandHandler("poolranking", function(player)
    if not characterOf(player) then return end
    triggerClientEvent(player, "rp:pool:openBoard", resourceRoot)
    sendBoard(player)
end)

----------------------------------------------------------------
-- Mesas del mundo
----------------------------------------------------------------
local function spawnTable(row)
    local T = {
        id = tonumber(row.id), x = row.x, y = row.y, z = row.z, rz = row.rotation,
        interior = row.interior, dimension = row.dimension, native = row.native == 1,
        status = "idle", balls = PoolSim.newBalls(),
    }
    if not T.native then
        T.object = createObject(POOL.TABLE_MODEL, T.x, T.y, T.z, 0, 0, T.rz)
        setElementInterior(T.object, T.interior)
        setElementDimension(T.object, T.dimension)
    end
    local cx, cy = poolToWorld(T, 0, 0)
    T.col = createColSphere(cx, cy, T.z + 0.9, POOL.INTERACT_RADIUS)
    setElementInterior(T.col, T.interior)
    setElementDimension(T.col, T.dimension)
    setElementData(T.col, "rp:pool:table", T.id, false)
    tables[T.id] = T

    local function enter(el)
        if characterOf(el) then
            nearTable[el] = T.id
            triggerClientEvent(el, "rp:pool:near", resourceRoot, T.id)
        end
    end
    addEventHandler("onColShapeHit", T.col, function(el, sameDim)
        if getElementType(el) == "player" and sameDim then enter(el) end
    end)
    -- Quien ya esta dentro al crear la mesa (o al arrancar el recurso) no genera "hit"
    for _, p in ipairs(getElementsWithinColShape(T.col, "player")) do
        if getElementInterior(p) == T.interior and getElementDimension(p) == T.dimension then enter(p) end
    end
    addEventHandler("onColShapeLeave", T.col, function(el)
        if getElementType(el) == "player" and nearTable[el] == T.id then
            nearTable[el] = nil
            triggerClientEvent(el, "rp:pool:near", resourceRoot, false)
        end
    end)
    return T
end

local function destroyTable(id)
    local T = tables[id]
    if not T then return end
    stopTimers(T)
    if T.status == "waiting" then cancelWaiting(T) end
    if T.status == "playing" and T.match then
        for i = 1, 2 do
            local p = T.match.players[i]
            payOut(p, T.match.chars[i], T.match.bet)
            if isElement(p) then
                playerTable[p] = nil
                triggerClientEvent(p, "rp:pool:matchEnd", resourceRoot, id, 0, 0, "")
                notify(p, "La mesa se retiró: se te devolvió la apuesta.", "warning")
            end
        end
    end
    for p, tid in pairs(nearTable) do
        if tid == id then nearTable[p] = nil end
    end
    if isElement(T.object) then destroyElement(T.object) end
    if isElement(T.col) then destroyElement(T.col) end
    tables[id] = nil
    triggerClientEvent(root, "rp:pool:tableRemoved", resourceRoot, id)
end

local function loadTables()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do spawnTable(row) end
        outputDebugString(("[rp_pool] %d mesas cargadas"):format(#rows))
        local list, states = {}, {}
        for _, T in pairs(tables) do
            list[#list + 1] = tableInfo(T)
            states[#states + 1] = stateOf(T)
        end
        triggerClientEvent(root, "rp:pool:tables", resourceRoot, list, states)
    end, db(), "SELECT * FROM pool_tables")
end

-- Si no hay mesas, se siembran las de Ten Green Bottles (datos del juego original)
local function seedTables(i)
    local s = POOL.SEED_TABLES[i]
    if not s then return loadTables() end
    dbQuery(function(qh)
        dbPoll(qh, 0)
        seedTables(i + 1)
    end, db(), "INSERT INTO pool_tables (x, y, z, rotation, interior, dimension, native) VALUES (?, ?, ?, ?, ?, ?, ?)",
        s.x, s.y, s.z, s.rz, s.interior, s.dimension, s.native or 0)
end

local function initTables()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if rows and rows[1] and tonumber(rows[1].n) == 0 then
            seedTables(1)
        else
            loadTables()
        end
    end, db(), "SELECT COUNT(*) AS n FROM pool_tables")
end

----------------------------------------------------------------
-- Puertas de Ten Green Bottles
----------------------------------------------------------------
local function teleportPlayer(player, to, interior, dimension)
    local now = getTickCount()
    if doorCooldown[player] and now - doorCooldown[player] < 1500 then return end
    doorCooldown[player] = now
    fadeCamera(player, false, 0.25)
    setTimer(function()
        if not isElement(player) then return end
        setElementInterior(player, interior)
        setElementDimension(player, dimension)
        setCameraInterior(player, interior)
        setElementPosition(player, to.x, to.y, to.z + 1.0)
        setElementRotation(player, 0, 0, to.rot or 0)
        setCameraTarget(player, player)
        fadeCamera(player, true, 0.4)
    end, 280, 1)
end

local function createVenues()
    for _, v in ipairs(POOL.VENUES) do
        local e, i = v.exterior, v.interior
        local m1 = createMarker(e.x, e.y, e.z - 0.1, "cylinder", 1.3, 245, 165, 36, 90)
        setElementInterior(m1, e.interior); setElementDimension(m1, e.dimension)
        local m2 = createMarker(i.x, i.y, i.z - 0.1, "cylinder", 1.1, 245, 165, 36, 90)
        setElementInterior(m2, i.interior); setElementDimension(m2, i.dimension)
        addEventHandler("onMarkerHit", m1, function(el, sameDim)
            if getElementType(el) == "player" and sameDim and not isPedInVehicle(el) and characterOf(el) then
                teleportPlayer(el, v.interiorSpawn, i.interior, i.dimension)
            end
        end)
        addEventHandler("onMarkerHit", m2, function(el, sameDim)
            if getElementType(el) == "player" and sameDim and not isPedInVehicle(el) and characterOf(el) then
                teleportPlayer(el, v.exteriorSpawn, e.interior, e.dimension)
            end
        end)
    end
end

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
addCommandHandler("crearmesapool", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local px, py, pz = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local a = math.rad(rot)
    local x, y, z = px - math.sin(a) * 2.0, py + math.cos(a) * 2.0, pz - 0.98
    local interior, dimension = getElementInterior(player), getElementDimension(player)
    local rz = (floor(rot / 90 + 0.5) * 90) % 360
    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        if not id then return notify(player, "No se pudo crear la mesa.", "error") end
        spawnTable({ id = id, x = x, y = y, z = z, rotation = rz, interior = interior, dimension = dimension, native = 0 })
        local T = tables[tonumber(id)]
        triggerClientEvent(root, "rp:pool:tables", resourceRoot, { tableInfo(T) }, { stateOf(T) })
        notify(player, ("Mesa de pool %d creada."):format(id), "success")
    end, db(), "INSERT INTO pool_tables (x, y, z, rotation, interior, dimension, native) VALUES (?, ?, ?, ?, ?, ?, 0)",
        x, y, z, rz, interior, dimension)
end)

addCommandHandler("borrarmesapool", function(player, _, idStr)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local id = tonumber(idStr)
    if not id or not tables[id] then return notify(player, "Uso: /borrarmesapool <id> (mira /mesaspool)", "warning") end
    destroyTable(id)
    dbExec(db(), "DELETE FROM pool_tables WHERE id = ?", id)
    notify(player, ("Mesa de pool %d borrada."):format(id), "success")
end)

addCommandHandler("mesaspool", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local ids = {}
    for id in pairs(tables) do ids[#ids + 1] = id end
    table.sort(ids)
    outputChatBox("Mesas de pool (" .. #ids .. "):", player, 245, 165, 36)
    for _, id in ipairs(ids) do
        local T = tables[id]
        outputChatBox(("  #%d  %.1f, %.1f, %.1f  int %d dim %d  %s%s"):format(id, T.x, T.y, T.z, T.interior, T.dimension,
            T.status, T.native and "  (mesa del mapa)" or ""), player, 255, 255, 255)
    end
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
local function dropPlayer(player)
    local tid = playerTable[player]
    nearTable[player] = nil
    doorCooldown[player] = nil
    lastAim[player] = nil
    if not tid then return end
    local T = tables[tid]
    if not T then playerTable[player] = nil return end
    if T.status == "waiting" and T.waiting and T.waiting.player == player then
        -- La devolucion se hace antes de que rp_characters guarde al jugador (prioridad alta)
        payOut(player, T.waiting.char, T.waiting.bet)
        T.waiting.bet = 0
        playerTable[player] = nil
        resetTable(T)
    elseif T.status == "playing" and T.match then
        for i = 1, 2 do
            if T.match.players[i] == player then
                playerTable[player] = nil
                endMatch(T, 3 - i, "quit")
                return
            end
        end
    end
    playerTable[player] = nil
end

addEventHandler("onPlayerQuit", root, function() dropPlayer(source) end, true, "high")
addEventHandler("rp:onCharacterLogout", root, function() dropPlayer(source) end, true, "high")

addEventHandler("rp:onCharacterSpawn", root, function()
    local list, states = {}, {}
    for _, T in pairs(tables) do
        list[#list + 1] = tableInfo(T)
        states[#states + 1] = stateOf(T)
    end
    triggerClientEvent(source, "rp:pool:tables", resourceRoot, list, states)
end)

-- Vigilancia: nadie se queda "jugando" si se aleja, cae o se va de la mesa
setTimer(function()
    for _, T in pairs(tables) do
        if T.status == "waiting" and T.waiting then
            local p = T.waiting.player
            if not isElement(p) then
                cancelWaiting(T)
            else
                local px, py, pz = getElementPosition(p)
                local dx, dy, dz = px - T.x, py - T.y, pz - T.z
                if getElementInterior(p) ~= T.interior or getElementDimension(p) ~= T.dimension
                    or dx * dx + dy * dy + dz * dz > 8 * 8 then
                    cancelWaiting(T, "Te alejaste de la mesa: se canceló la partida y se devolvió tu apuesta.")
                end
            end
        elseif T.status == "playing" and T.match and not T.match.busy then
            local m = T.match
            for i = 1, 2 do
                local p = m.players[i]
                if not isElement(p) or not characterOf(p) then
                    return endMatch(T, 3 - i, "quit")
                end
                local px, py, pz = getElementPosition(p)
                local dx, dy, dz = px - T.x, py - T.y, pz - T.z
                if getElementInterior(p) ~= T.interior or getElementDimension(p) ~= T.dimension
                    or dx * dx + dy * dy + dz * dz > 14 * 14 or getElementData(p, "rp:downed") then
                    notify(p, "Abandonaste la mesa: pierdes la partida.", "error")
                    return endMatch(T, 3 - i, "forfeit")
                end
            end
        end
    end
end, 2000, 0)

addEventHandler("rp:onDatabaseReady", root, function()
    -- Apuestas que quedaron en custodia por una caida del servidor: se devuelven (nadie esta
    -- jugando todavia, asi que no hay riesgo de que se sobrescriban con un guardado)
    dbExec(db(), "UPDATE characters c JOIN pool_escrow e ON e.character_id = c.id SET c.money = c.money + e.amount")
    dbExec(db(), "DELETE FROM pool_escrow")
    initTables()
end)

addEventHandler("onResourceStart", resourceRoot, function()
    math.randomseed(getTickCount())
    createVenues()
    if exports.rp_database:isReady() then
        dbExec(db(), "UPDATE characters c JOIN pool_escrow e ON e.character_id = c.id SET c.money = c.money + e.amount")
        dbExec(db(), "DELETE FROM pool_escrow")
        initTables()
    end
end)

-- Al parar el recurso se devuelven las apuestas de las partidas en curso
addEventHandler("onResourceStop", resourceRoot, function()
    for _, T in pairs(tables) do
        if T.status == "waiting" and T.waiting then
            payOut(T.waiting.player, T.waiting.char, T.waiting.bet)
        elseif T.status == "playing" and T.match then
            for i = 1, 2 do payOut(T.match.players[i], T.match.chars[i], T.match.bet) end
        end
    end
end)

function getPlayerPoolTable(player)
    return playerTable[player] or false
end
