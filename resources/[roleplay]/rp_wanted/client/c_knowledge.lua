--[[
    rp_wanted / c_knowledge.lua
    Lo que la policia sabe del jugador local (como GTA V): no su posicion real,
    sino donde lo vio por ultima vez. Lo usa client/c_police.lua para decidir a
    donde van las patrullas, los policias a pie, el helicoptero y las lanchas.

      live     algun policia te ve (o te vio hace menos de GRACE): posicion real
      predict  te perdieron: van a tu ultima posicion proyectada con tu velocidad
      search   barren calles alrededor de la ultima posicion, cada vez mas lejos

    Te "ven" las unidades de la persecucion, las patrullas del trafico, el
    helicoptero (hasta 140 m) y los policias jugadores con uniforme, siempre con
    linea de vision. Un delito denunciado (el servidor manda rp:wanted:reveal) o
    disparar con un policia cerca les dice donde estas.

    Globales: knowledgeSeen, knowledgeMode, knowledgeTarget, knowledgeSearchRadius,
              knowledgeSearchPoint, knowledgeLastSeenOnFoot
]]

local S = WANTED_SEARCH
local K = { seenAt = 0, seq = 0 }   -- lkp = {x, y, z}, vel = {vx, vy}, onFoot
local wantedLevel = 0

-- Un policia ve al jugador ahora mismo (o el jugador se delato)
function knowledgeSeen(now)
    local x, y, z = getElementPosition(localPlayer)
    local veh = getPedOccupiedVehicle(localPlayer)
    local vx, vy = getElementVelocity(veh or localPlayer)
    K.lkp, K.vel, K.onFoot = { x, y, z }, { vx, vy }, not veh
    K.seenAt = now or getTickCount()
    K.seq = K.seq + 1
end

function knowledgeMode(now)
    if not K.lkp then return "live" end
    local age = now - K.seenAt
    if age < S.GRACE then return "live" end
    if age < S.GRACE + S.PREDICT_MS then return "predict" end
    return "search"
end

-- Punto al que va la policia: x, y, z, modo
function knowledgeTarget(now)
    local mode = knowledgeMode(now)
    if mode == "live" then
        local x, y, z = getElementPosition(localPlayer)
        return x, y, z, mode
    end
    -- velocidad de MTA: unidades por 1/50 s
    local t = math.min(now - K.seenAt, S.GRACE + S.PREDICT_MS) / 1000 * 50
    local p, v = K.lkp, K.vel
    return p[1] + v[1] * t, p[2] + v[2] * t, p[3], mode
end

function knowledgeLastSeenOnFoot() return K.onFoot == true end

-- Radio de busqueda: crece con el tiempo sin verte
function knowledgeSearchRadius(now)
    local lost = math.max(0, now - K.seenAt - S.GRACE - S.PREDICT_MS)
    return S.RADIUS_MIN + (S.RADIUS_MAX - S.RADIUS_MIN) * math.min(1, lost / S.GROW_MS)
end

-- Punto de busqueda de una unidad o policia (st guarda su estado). El primero
-- es la ultima posicion proyectada; despues, puntos al azar cada vez mas lejos:
-- nodos de calle para los vehiculos, alrededor de la ultima posicion a pie.
function knowledgeSearchPoint(st, now, x, y, onFoot)
    local sp = st.sp
    local reached = sp and getDistanceBetweenPoints2D(x, y, sp[1], sp[2]) < (onFoot and 3 or S.POINT_REACHED)
    if sp and st.spSeq == K.seq and not reached and now - st.spAt < S.POINT_TIMEOUT then return sp end
    local cx, cy, cz = knowledgeTarget(now)
    if st.spSeq ~= K.seq then
        sp = { cx, cy, cz }
    elseif onFoot then
        local a, r = math.random() * math.pi * 2, 6 + math.random() * (S.FOOT_RADIUS - 6)
        sp = { cx + math.cos(a) * r, cy + math.sin(a) * r, cz }
    else
        local R = knowledgeSearchRadius(now)
        local n = loadRoadGraph() and roadNodeAround(cx, cy, R * 0.25, R)
        sp = n and { nodePosition(n) } or { cx + (math.random() - 0.5) * R, cy + (math.random() - 0.5) * R, cz }
    end
    st.sp, st.spAt, st.spSeq = sp, now, K.seq
    return sp
end

----------------------------------------------------------------
-- Vision: algun policia con linea de vision
----------------------------------------------------------------
local function copSees(el, px, py, pz, range)
    local x, y, z = getElementPosition(el)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > range then return false end
    return isLineOfSightClear(x, y, z + 0.8, px, py, pz + 0.6, true, false, false, true, false, true, false)
end

function policeSeesMe()
    local px, py, pz = getElementPosition(localPlayer)
    for _, ped in ipairs(getElementsWithinRange(px, py, pz, 70, "ped")) do
        if getElementData(ped, "rp:cop") and not isPedDead(ped) and copSees(ped, px, py, pz, 70) then return true end
    end
    for _, v in ipairs(getElementsWithinRange(px, py, pz, 140, "vehicle")) do
        if getElementData(v, "rp:copCar") and getVehicleController(v) and getVehicleController(v) ~= localPlayer then
            -- el helicoptero ve desde mas lejos
            local range = getVehicleType(v) == "Helicopter" and 140 or 70
            if copSees(v, px, py, pz, range) then return true end
        end
    end
    for _, pl in ipairs(getElementsWithinRange(px, py, pz, 70, "player")) do
        if pl ~= localPlayer and WANTED_POLICE_SKINS[getElementModel(pl)] and copSees(pl, px, py, pz, 70) then return true end
    end
    return false
end

-- Cada SIGHT_TICK se mira; al servidor se le avisa como mucho una vez por segundo
-- (el decaimiento solo empieza tras WANTED.EVADE_TIME sin avistamientos)
local seenSentAt = 0
setTimer(function()
    if wantedLevel <= 0 then return end
    local now = getTickCount()
    if policeSeesMe() then
        knowledgeSeen(now)
        if now - seenSentAt >= 1000 then
            seenSentAt = now
            triggerServerEvent("rp:wanted:seen", resourceRoot)
        end
    end
end, S.SIGHT_TICK, 0)

-- Disparar con un policia cerca delata la posicion
addEventHandler("onClientPlayerWeaponFire", localPlayer, function()
    if wantedLevel <= 0 then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, ped in ipairs(getElementsWithinRange(px, py, pz, S.SHOT_REVEAL_RADIUS, "ped")) do
        if getElementData(ped, "rp:cop") and not isPedDead(ped) then return knowledgeSeen() end
    end
end)

-- Un delito denunciado: la central da la posicion
addEvent("rp:wanted:reveal", true)
addEventHandler("rp:wanted:reveal", resourceRoot, function() knowledgeSeen() end)

addEvent("rp:wanted:level", true)
addEventHandler("rp:wanted:level", resourceRoot, function(lv)
    local old = wantedLevel
    wantedLevel = tonumber(lv) or 0
    -- la busqueda empieza por un delito: saben donde estas
    if old <= 0 and wantedLevel > 0 then knowledgeSeen() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    wantedLevel = tonumber(getElementData(localPlayer, "rp:wanted")) or 0
    if wantedLevel > 0 then knowledgeSeen() end
end)
