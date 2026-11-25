--[[
    rp_shootingrange / s_session.lua  (servidor)
    Una sesion por jugador, aislada en su dimension. Todo lo decide el servidor:
      - balas: cada disparo descuenta 1 bala real del inventario (takeItem) en el momento;
      - impactos: onPlayerWeaponFire + rayo propio contra las esferas de los blancos, con el reloj del servidor;
      - habilidad: solo sube en impactos validos (un impacto por blanco), con tope por sesion.
    shortcut: el punto final del disparo lo reporta el cliente (MTA no lo da de otra forma); el tope de
    balas, "un impacto por blanco" y el tope de habilidad por sesion acotan el abuso.
]]

rangePlayers = {}   -- [player] = { characterId, inside, dim, prevItem, last, session }

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max

local function send(p, ev, ...)
    if isElement(p) then triggerClientEvent(p, ev, resourceRoot, ...) end
end

-- Armas del jugador que se pueden entrenar (solo las que tiene en el inventario)
function rangeWeaponList(p)
    local list = {}
    for itemId, w in pairs(RANGE.WEAPONS) do
        local def = exports.rp_inventory:getItemDefinition(itemId)
        if def and def.weapon and exports.rp_inventory:hasItem(p, itemId, 1) then
            local cat = RANGE.CATEGORIES[w.category]
            list[#list + 1] = {
                item = itemId, name = def.name, category = w.category, categoryName = cat.name,
                ammo = exports.rp_inventory:getItemAmount(p, def.ammo), maxAmmo = cat.ammo,
                skill = skillInfo(getPedStat(p, w.stat) or 0),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.name < b.name
    end)
    return list
end

local function hudData(s)
    return {
        shots = s.shots, hits = s.hits, score = s.score, ammo = max(0, s.budget - s.shots),
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

function finishSession(p, reason, silent)
    local ps = rangePlayers[p]
    local s = ps and ps.session
    if not s then return end
    ps.session = nil
    s.finished = true
    if isTimer(s.timer) then killTimer(s.timer) end
    if isTimer(s.endTimer) then killTimer(s.endTimer) end
    if not isElement(p) then return end

    takeWeapon(p, s.weapon)
    local final = floor(s.skill)
    setPedStat(p, s.stat, final)            -- sin los puntos nativos que dan los disparos fallados
    if s.gain > 0 then skillSave(ps.characterId, s.stat, final) end

    if silent then return end
    local before, after = skillInfo(s.skill0), skillInfo(final)
    send(p, "rp:range:results", {
        reason = reason, weapon = s.def.name,
        shots = s.shots, hits = s.hits, misses = s.shots - s.hits,
        accuracy = s.shots > 0 and floor(s.hits / s.shots * 100 + 0.5) or 0,
        score = s.score, before = before, after = after, gained = final - floor(s.skill0),
    })
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
    local cat = RANGE.CATEGORIES[w.category]
    local budget = min(exports.rp_inventory:getItemAmount(p, def.ammo), cat.ammo)
    if budget < 1 then return false, "No tienes municion para esa arma. Comprala en Ammu-Nation." end
    if getPedWeapon(p, getSlotFromWeapon(def.weapon)) ~= 0 then return false, "Guarda el arma que llevas encima antes de entrenar." end

    local stat0 = getPedStat(p, w.stat) or 0
    giveWeapon(p, def.weapon, budget, true)
    local s = {
        itemId = itemId, def = def, weapon = def.weapon, stat = w.stat, category = w.category, budget = budget,
        shots = 0, hits = 0, score = 0, skill0 = stat0, skill = stat0, gain = 0, round = 0, t0 = 0, t1 = 0, targets = {},
    }
    ps.session = s
    send(p, "rp:range:start", { weapon = def.name, budget = budget, rounds = #RANGE.ROUNDS, hud = hudData(s) })
    s.timer = setTimer(tick, 200, 0, p)
    nextRound(p, s)
    return true
end

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
    if not exports.rp_inventory:takeItem(p, s.def.ammo, 1) then
        takeWeapon(p, s.weapon)
        return finishSession(p, "ammo")
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
            local gain = max(0, min(z.gain, RANGE.SKILL_MAX_PER_SESSION - s.gain, RANGE.SKILL_MAX - s.skill))
            s.skill = s.skill + gain
            s.gain = s.gain + gain
            send(p, "rp:range:hit", hit.t.id, z.key, z.name, z.points, hit.t.rearm)
        end
    end
    send(p, "rp:range:hud", hudData(s))

    if s.shots >= s.budget and not isTimer(s.endTimer) then
        s.endTimer = setTimer(finishSession, 1500, 1, p, "ammo")
    end
end)
