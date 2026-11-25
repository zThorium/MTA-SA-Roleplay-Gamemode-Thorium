--[[
    rp_shootingrange / s_session.lua  (servidor)
    Una sesion por jugador, aislada en su dimension. Todo lo decide el servidor:
      - municion: el arma de entrenamiento tiene balas "infinitas" (TRAINING_AMMO, se rellena) que
        NO salen del inventario. Es un arma aparte: se retira siempre al terminar la sesion
        (finishSession) y rp_ammunation no la sincroniza (sus armas estan suspendidas en el campo),
        asi que nunca se convierte en balas reales;
      - impactos: onPlayerWeaponFire + rayo propio contra las esferas de los blancos, con el reloj del servidor;
      - habilidad: solo sube en impactos validos (un impacto por blanco), con tope por sesion y por dia;
      - historial: cada sesion queda en range_sessions y los resultados traen las graficas de progreso.
    shortcut: el punto final del disparo lo reporta el cliente (MTA no lo da de otra forma); "un impacto
    por blanco" y los topes de habilidad acotan el abuso.
]]

rangePlayers = {}   -- [player] = { characterId, inside, dim, prevItem, last, session, dailyGain }

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max

local function db() return exports.rp_database:getConnection() end

local function send(p, ev, ...)
    if isElement(p) then triggerClientEvent(p, ev, resourceRoot, ...) end
end

----------------------------------------------------------------
-- Tope diario de habilidad (ventana de 24 h, todas las armas)
----------------------------------------------------------------
function rangeLoadDailyGain(p, characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local ps = rangePlayers[p]
        if ps and ps.characterId == characterId then ps.dailyGain = tonumber(rows[1] and rows[1].g) or 0 end
    end, db(), [[SELECT COALESCE(SUM(GREATEST(CAST(skill_after AS SIGNED) - CAST(skill_before AS SIGNED), 0)), 0) AS g
                 FROM range_sessions WHERE character_id = ? AND created_at >= NOW() - INTERVAL 1 DAY]], characterId)
end

local function dailyRoom(ps)
    if (RANGE.SKILL_MAX_PER_DAY or 0) <= 0 then return math.huge end
    return max(0, RANGE.SKILL_MAX_PER_DAY - (ps.dailyGain or 0))
end

-- Para el cliente: math.huge no cabe en JSON; -1 = sin tope diario
local function clientRoom(ps)
    local r = dailyRoom(ps)
    return r == math.huge and -1 or r
end

----------------------------------------------------------------
-- Menu y HUD
----------------------------------------------------------------
-- Armas del jugador que se pueden entrenar (solo las que tiene en el inventario)
function rangeWeaponList(p)
    local list = {}
    local ps = rangePlayers[p]
    for itemId, w in pairs(RANGE.WEAPONS) do
        local def = exports.rp_inventory:getItemDefinition(itemId)
        if def and def.weapon and exports.rp_inventory:hasItem(p, itemId, 1) then
            local cat = RANGE.CATEGORIES[w.category]
            list[#list + 1] = {
                item = itemId, name = def.name, category = w.category, categoryName = cat.name,
                skill = skillInfo(getPedStat(p, w.stat) or 0),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.name < b.name
    end)
    return list, ps and dailyRoom(ps) or 0
end

local function hudData(s)
    return {
        shots = s.shots, hits = s.hits, score = s.score, ammo = "∞",
        accuracy = s.shots > 0 and floor(s.hits / s.shots * 100 + 0.5) or 0,
        skill = skillInfo(s.skill), round = s.round,
    }
end

local function sendRound(p, s)
    s.targets = rangeBuildRound(s.round, s.category)
    local round = RANGE.ROUNDS[s.round]
    local now = getTickCount()
    s.t0 = now + RANGE.ROUND_DELAY_MS
    s.t1 = s.t0 + round.time * 1000
    send(p, "rp:range:round", s.round, #RANGE.ROUNDS, round.kind, s.targets, RANGE.ROUND_DELAY_MS, round.time * 1000)
end

----------------------------------------------------------------
-- Historial: guardar la sesion y leer el progreso para las graficas
----------------------------------------------------------------
local function loadHistory(characterId, stat, cb)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        dbQuery(function(qh2)
            local agg = (dbPoll(qh2, 0) or {})[1] or {}
            -- Las filas vienen de la mas nueva a la mas vieja; las graficas van de izquierda (vieja) a derecha
            local history = {}
            for i = #rows, 1, -1 do
                local r = rows[i]
                history[#history + 1] = {
                    accuracy = tonumber(r.accuracy) or 0, score = tonumber(r.score) or 0,
                    skill = tonumber(r.skill_after) or 0, shots = tonumber(r.shots) or 0,
                    hits = tonumber(r.hits) or 0, date = tostring(r.d or ""),
                }
            end
            local shots, hits = tonumber(agg.shots) or 0, tonumber(agg.hits) or 0
            cb(history, {
                sessions = tonumber(agg.n) or 0, shots = shots, hits = hits,
                accuracy = shots > 0 and floor(hits / shots * 100 + 0.5) or 0,
                bestScore = tonumber(agg.best_score) or 0, bestAccuracy = tonumber(agg.best_acc) or 0,
            })
        end, db(), [[SELECT COUNT(*) AS n, COALESCE(SUM(shots), 0) AS shots, COALESCE(SUM(hits), 0) AS hits,
                            COALESCE(MAX(score), 0) AS best_score, COALESCE(MAX(accuracy), 0) AS best_acc
                     FROM range_sessions WHERE character_id = ? AND stat_id = ?]], characterId, stat)
    end, db(), [[SELECT shots, hits, score, accuracy, skill_after, DATE_FORMAT(created_at, '%d/%m %H:%i') AS d
                 FROM range_sessions WHERE character_id = ? AND stat_id = ? ORDER BY id DESC LIMIT ?]],
        characterId, stat, RANGE.HISTORY_SESSIONS or 15)
end

local function saveSession(characterId, s, final, reason, cb)
    local accuracy = s.shots > 0 and floor(s.hits / s.shots * 100 + 0.5) or 0
    if s.shots < 1 then return cb() end   -- sesiones sin disparos no ensucian el historial
    dbQuery(function(qh)
        dbPoll(qh, 0)
        cb()
    end, db(), [[INSERT INTO range_sessions (character_id, stat_id, item_id, shots, hits, score, accuracy, skill_before, skill_after, reason)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        characterId, s.stat, s.itemId, min(s.shots, 65535), min(s.hits, 65535), s.score, accuracy,
        floor(s.skill0), final, reason)
end

----------------------------------------------------------------
-- Fin de la sesion (siempre retira el arma de entrenamiento)
----------------------------------------------------------------
function finishSession(p, reason, silent)
    local ps = rangePlayers[p]
    local s = ps and ps.session
    if not s then return end
    ps.session = nil
    s.finished = true
    if isTimer(s.timer) then killTimer(s.timer) end
    if not isElement(p) then return end

    takeWeapon(p, s.weapon)                 -- el arma de entrenamiento nunca sale del campo
    local final = floor(s.skill)
    setPedStat(p, s.stat, final)            -- sin los puntos nativos que dan los disparos fallados
    if s.gain > 0 then
        skillSave(ps.characterId, s.stat, final)
        ps.dailyGain = (ps.dailyGain or 0) + s.gain
    end

    local characterId = ps.characterId
    saveSession(characterId, s, final, reason, function()
        if silent or not isElement(p) then return end
        loadHistory(characterId, s.stat, function(history, totals)
            if not isElement(p) or (rangePlayers[p] and rangePlayers[p].session) then return end
            local before, after = skillInfo(s.skill0), skillInfo(final)
            send(p, "rp:range:results", {
                reason = reason, weapon = s.def.name,
                shots = s.shots, hits = s.hits, misses = s.shots - s.hits,
                accuracy = s.shots > 0 and floor(s.hits / s.shots * 100 + 0.5) or 0,
                score = s.score, before = before, after = after, gained = final - floor(s.skill0),
                capped = s.capped == true, dailyRoom = clientRoom(rangePlayers[p] or {}),
                history = history, totals = totals, levels = RANGE.LEVELS, skillMax = RANGE.SKILL_MAX,
            })
        end)
    end)
end

local function nextRound(p, s)
    s.round = s.round + 1
    if s.round > #RANGE.ROUNDS then return finishSession(p, "done") end
    sendRound(p, s)
end

local function allResolved(s, now)
    if now < s.t0 then return false end
    local el = now - s.t0
    for _, t in ipairs(s.targets) do
        if t.kind == "lateral" then return false end
        if not t.dead and el <= t.at + t.life then return false end
    end
    return true
end

local function tick(p)
    local ps = rangePlayers[p]
    local s = ps and ps.session
    if not s then return end
    if not isElement(p) or exports.rp_injury:isPlayerDowned(p) then return finishSession(p, "abort", true) end
    local now = getTickCount()
    if now >= s.t1 or allResolved(s, now) then nextRound(p, s) end
end

function startSession(p, itemId)
    local ps = rangePlayers[p]
    local w = RANGE.WEAPONS[itemId]
    local def = w and exports.rp_inventory:getItemDefinition(itemId)
    if not ps or not ps.inside or ps.session or not def or not def.weapon then return false, "No puedes entrenar ahora." end
    if not exports.rp_inventory:hasItem(p, itemId, 1) then return false, "No tienes esa arma." end
    if getPedWeapon(p, getSlotFromWeapon(def.weapon)) ~= 0 then return false, "Guarda el arma que llevas encima antes de entrenar." end

    local stat0 = getPedStat(p, w.stat) or 0
    giveWeapon(p, def.weapon, RANGE.TRAINING_AMMO, true)
    local s = {
        itemId = itemId, def = def, weapon = def.weapon, stat = w.stat, category = w.category,
        shots = 0, hits = 0, score = 0, skill0 = stat0, skill = stat0, gain = 0, round = 0, t0 = 0, t1 = 0, targets = {},
    }
    ps.session = s
    send(p, "rp:range:start", { weapon = def.name, rounds = #RANGE.ROUNDS, hud = hudData(s), dailyRoom = clientRoom(ps) })
    s.timer = setTimer(tick, 200, 0, p)
    nextRound(p, s)
    return true
end

----------------------------------------------------------------
-- Disparos
----------------------------------------------------------------
-- Rayo del disparo contra las esferas de zona de cada blanco vivo. Devuelve el mas cercano.
local function findHit(s, sx, sy, sz, ex, ey, ez, now)
    local dx, dy, dz = ex - sx, ey - sy, ez - sz
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1 then return end
    local ux, uy, uz = dx / len, dy / len, dz / len
    local el = now - s.t0
    local best
    for _, t in ipairs(s.targets) do
        if not t.dead and now >= (t.blocked or 0) then
            local active, d, l = rangeTargetState(t, el)
            if active then
                local speed = 0
                if t.kind == "advance" then speed = abs(t.d1 - t.d0) / (t.life / 1000)
                elseif t.kind == "lateral" then speed = t.amp * 2 * math.pi / t.period end
                local pad = speed * RANGE.LAG_S
                local bx, by, bz = rangeWorldPos(d, l)
                for zi, z in ipairs(RANGE.ZONES) do
                    local px, py, pz = bx - sx, by - sy, (bz + z.z) - sz
                    local proj = px * ux + py * uy + pz * uz
                    if proj > 0 and len >= proj - 1.5 then
                        local qx, qy, qz = px - ux * proj, py - uy * proj, pz - uz * proj
                        if sqrt(qx * qx + qy * qy + qz * qz) <= z.r + pad then
                            if not best or proj < best.proj then best = { t = t, zone = zi, proj = proj } end
                            break
                        end
                    end
                end
            end
        end
    end
    return best
end

addEventHandler("onPlayerWeaponFire", root, function(weapon, ex, ey, ez, _, sx, sy, sz)
    local p = source
    local ps = rangePlayers[p]
    local s = ps and ps.session
    if not s or s.finished or weapon ~= s.weapon then return end

    s.shots = s.shots + 1
    -- Municion de entrenamiento: se rellena, nunca se toca el inventario
    if (getPedTotalAmmo(p, getSlotFromWeapon(s.weapon)) or 0) < RANGE.REFILL_BELOW then
        setWeaponAmmo(p, s.weapon, RANGE.TRAINING_AMMO)
    end
    setPedStat(p, s.stat, floor(s.skill))   -- los fallos no dan habilidad nativa

    local now = getTickCount()
    local px, py, pz = getElementPosition(p)
    if now >= s.t0 and now <= s.t1 and getDistanceBetweenPoints3D(px, py, pz, sx, sy, sz) <= RANGE.SHOT_MAX_FROM_PLAYER then
        local hit = findHit(s, sx, sy, sz, ex, ey, ez, now)
        if hit then
            local z = RANGE.ZONES[hit.zone]
            if hit.t.rearm > 0 then hit.t.blocked = now + hit.t.rearm else hit.t.dead = true end
            s.hits = s.hits + 1
            s.score = s.score + z.points
            local room = min(RANGE.SKILL_MAX_PER_SESSION - s.gain, RANGE.SKILL_MAX - s.skill, dailyRoom(ps) - s.gain)
            local gain = max(0, min(z.gain, room))
            if gain < z.gain then s.capped = true end
            s.skill = s.skill + gain
            s.gain = s.gain + gain
            send(p, "rp:range:hit", hit.t.id, z.key, z.name, z.points, hit.t.rearm)
        end
    end
    send(p, "rp:range:hud", hudData(s))
end)
