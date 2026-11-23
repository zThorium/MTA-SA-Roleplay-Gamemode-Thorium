--[[
    rp_citizens / c_hangouts.lua
    Vida de barrio: al entrar a un barrio hay gente fuera de las casas, siempre en los
    mismos rincones. Bandas del barrio en las esquinas (Grove, Ballas, Vagos, Aztecas),
    vecinos charlando y riendose junto a la cerca, gente al telefono, fumadores, obreros
    en su descanso en las zonas industriales...

    Como funciona (100% cliente, sin consecuencias de rol):
      - "Puntos de encuentro" deterministas: un hash del indice de cada nodo de acera decide
        si es un punto y su perfil sale del barrio (ghetto/rich/default/industrial). Asi el
        mismo rincon tiene el mismo tipo de gente cada vez que se vuelve.
      - Solo se crea un grupo cuando el jugador esta a 30-90 m de un punto (y no lo ve); se
        destruye a mas de 125 m. Como mucho 3-5 grupos y 12-14 peatones a la vez, que
        cuentan dentro del cupo de c_citizens.lua (siempre quedan 4 peatones caminando).
      - Un solo timer de decision (3 s) y otro de mantenimiento (1 s); sin grupos no hacen nada.
      - Si les disparas, apuntas o los golpeas, huyen y el punto descansa 3 minutos.
      - La intensidad la manda rp_events (elementData root "rp:events"); 0 = sin grupos.
]]

local DECIDE_MS, KEEP_MS = 3000, 1000
local MIN_D, MAX_D, DROP_D = 20, 100, 135
local MAX_PEDS_DAY, MAX_PEDS_NIGHT = 12, 14
local GROUP_CAP = { 3, 4, 5 }                   -- grupos simultaneos segun intensidad
local CELL = 100
-- fraccion de nodos de acera que son punto de encuentro, por perfil del barrio
local DENSITY = { ghetto = 0.12, default = 0.07, rich = 0.05, industrial = 0.04 }

local spots = nil        -- [celda] = { punto, ... }
local groups = {}        -- grupos activos: { spot, peds = {}, anim = tick, born }
local hangPeds = 0

local function intensity()
    local d = getElementData(root, "rp:events")
    -- sin dato del servidor (rp_events no arrancado o aun sin sincronizar): intensidad normal
    return type(d) == "table" and tonumber(d.intensity) or 2
end

function hangoutPeds() return hangPeds end

local function headingTo(dx, dy) return -math.deg(math.atan2(dx, dy)) end
local function pick(list) return list[math.random(#list)] end

----------------------------------------------------------------
-- Puntos de encuentro (se generan una vez, de forma determinista)
----------------------------------------------------------------
local function buildSpots()
    spots = {}
    local n = #PED_NODES / 3
    for i = 1, n do
        local links = PED_LINKS[i]
        if links and #links > 0 then
            local r = ((i * 2654435761) % 4294967296) / 4294967296
            if r < 0.12 then   -- tope: ningun perfil supera esta fraccion
                local x, y, z = PED_NODES[i * 3 - 2], PED_NODES[i * 3 - 1], PED_NODES[i * 3]
                local profile, zone, gang = citizenZoneInfo(x, y, z)
                if r < (DENSITY[profile] or 0.07) then
                    local t = links[1]
                    local rot = headingTo(PED_NODES[t * 3 - 2] - x, PED_NODES[t * 3 - 1] - y)
                    local key = math.floor(x / CELL) * 1000 + math.floor(y / CELL)
                    local cell = spots[key]
                    if not cell then cell = {} spots[key] = cell end
                    cell[#cell + 1] = { x = x, y = y, z = z, rot = rot, profile = profile, zone = zone, gang = gang, rest = 0, seed = r }
                end
            end
        end
    end
end

----------------------------------------------------------------
-- Tipos de grupo
----------------------------------------------------------------
local TALK = {
    { "ped", "IDLE_chat" }, { "GANGS", "prtial_gngtlkA" }, { "GANGS", "prtial_gngtlkB" },
    { "GANGS", "prtial_gngtlkC" }, { "GANGS", "prtial_gngtlkE" }, { "RAPPING", "Laugh_01" },
}
local GANG_TALK = {
    { "GANGS", "prtial_gngtlkA" }, { "GANGS", "prtial_gngtlkB" }, { "GANGS", "prtial_gngtlkD" },
    { "GANGS", "prtial_gngtlkF" }, { "GANGS", "prtial_gngtlkH" }, { "GANGS", "smkcig_prtl" }, { "RAPPING", "Laugh_01" },
}
local SMOKE = { { "SMOKING", "M_smkstnd_loop" }, { "GANGS", "smkcig_prtl" } }

local function setAnim(ped, a)
    setPedAnimation(ped, a[1], a[2], -1, true, false, false, false)
end

local function newPed(g, skin, x, y, z, rot)
    local ped = createPed(skin, x, y, z + 1, rot or 0)
    if ped then
        g.peds[#g.peds + 1] = ped
        hangPeds = hangPeds + 1
    end
    return ped
end

-- n peds en circulo mirando al centro
local function ring(g, spot, n, radius, skinFn, anims)
    for i = 1, n do
        local a = (i / n) * math.pi * 2 + math.random() * 0.5
        local px, py = spot.x + math.cos(a) * radius, spot.y + math.sin(a) * radius
        local ped = newPed(g, skinFn(), px, py, spot.z)
        if ped then
            setElementRotation(ped, 0, 0, headingTo(spot.x - px, spot.y - py), "default", true)
            setAnim(ped, pick(anims))
        end
    end
    g.anims = anims
end

local function civilSkin(spot) return citizenPickSkin(spot.x, spot.y, spot.z) end
local function gangSkin(spot)
    if spot.gang then return pick(spot.gang) end
    return citizenProfileSkin("ghetto")
end

local TYPES = {}

TYPES.gang = function(g, s)
    ring(g, s, math.random(3, 5), 1.2, function() return gangSkin(s) end, GANG_TALK)
end

TYPES.neighbors = function(g, s)
    ring(g, s, math.random(2, 3), 0.95, function() return civilSkin(s) end, TALK)
end

-- Vecinos junto a la cerca: uno en la acera y otro hacia las casas
TYPES.fence = function(g, s)
    local ax, ay = citizenAwayFromRoad(s.x, s.y)
    if not ax then return TYPES.neighbors(g, s) end
    local a = newPed(g, civilSkin(s), s.x, s.y, s.z)
    local b = newPed(g, civilSkin(s), s.x + ax * 1.6, s.y + ay * 1.6, s.z)
    if a and b then
        setElementRotation(a, 0, 0, headingTo(ax, ay), "default", true)
        setElementRotation(b, 0, 0, headingTo(-ax, -ay), "default", true)
        setAnim(a, pick(TALK)) setAnim(b, pick(TALK))
    end
    g.anims = TALK
end

-- Alguien en su puerta/jardin mirando a la calle o al telefono
TYPES.porch = function(g, s)
    local ax, ay = citizenAwayFromRoad(s.x, s.y)
    if not ax then return TYPES.phone(g, s) end
    local p = newPed(g, civilSkin(s), s.x + ax * 2.0, s.y + ay * 2.0, s.z)
    if p then
        setElementRotation(p, 0, 0, headingTo(-ax, -ay), "default", true)
        setAnim(p, pick({ { "ped", "phone_talk" }, SMOKE[1], { "ped", "IDLE_chat" } }))
    end
    g.anims = { { "ped", "phone_talk" }, SMOKE[1] }
end

TYPES.phone = function(g, s)
    local p = newPed(g, civilSkin(s), s.x, s.y, s.z, s.rot)
    if p then setAnim(p, { "ped", "phone_talk" }) end
    g.anims = { { "ped", "phone_talk" }, { "ped", "IDLE_chat" } }
end

TYPES.smoker = function(g, s)
    local p = newPed(g, civilSkin(s), s.x, s.y, s.z, s.rot)
    if p then setAnim(p, pick(SMOKE)) end
    g.anims = SMOKE
end

-- Descanso de obreros (zonas industriales)
TYPES.workers = function(g, s)
    ring(g, s, math.random(2, 3), 1.0, function() return citizenProfileSkin("industrial") end,
        { SMOKE[1], { "ped", "IDLE_chat" }, { "RAPPING", "Laugh_01" } })
end

-- Tipo segun barrio y hora: { {tipo, peso}, ... }
local function weightsFor(profile, h)
    local night = h >= 20 or h < 5
    if profile == "ghetto" then
        if night then return { { "gang", 55 }, { "neighbors", 15 }, { "smoker", 15 }, { "fence", 10 }, { "phone", 5 } } end
        return { { "gang", 30 }, { "neighbors", 25 }, { "fence", 20 }, { "porch", 15 }, { "smoker", 10 } }
    elseif profile == "rich" then
        if night then return { { "phone", 40 }, { "smoker", 30 }, { "neighbors", 30 } } end
        return { { "neighbors", 35 }, { "fence", 25 }, { "porch", 20 }, { "phone", 20 } }
    elseif profile == "industrial" then
        if night then return nil end
        return { { "workers", 60 }, { "smoker", 25 }, { "phone", 15 } }
    end
    if night then return { { "neighbors", 30 }, { "smoker", 30 }, { "phone", 20 }, { "fence", 20 } } end
    return { { "neighbors", 30 }, { "fence", 30 }, { "porch", 20 }, { "phone", 10 }, { "smoker", 10 } }
end

local function pickType(profile, h)
    local list = weightsFor(profile, h)
    if not list then return nil end
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return list[1][1]
end

----------------------------------------------------------------
-- Ciclo de vida de los grupos
----------------------------------------------------------------
local function destroyGroup(g, restMs)
    for _, p in ipairs(g.peds) do
        if isElement(p) then destroyElement(p) end
        hangPeds = hangPeds - 1
    end
    g.peds = {}
    g.spot.rest = getTickCount() + (restMs or 20000)
    g.spot.group = nil
    for i = #groups, 1, -1 do if groups[i] == g then table.remove(groups, i) end end
end

-- Huyen del origen del susto y desaparecen a los 6 s; el punto descansa 3 min
local function panicGroup(g, fromX, fromY)
    if g.endAt then return end
    g.endAt = getTickCount() + 6000
    g.spot.rest = getTickCount() + 180000
    for _, p in ipairs(g.peds) do
        if isElement(p) and not isPedDead(p) then
            setPedAnimation(p)
            local x, y = getElementPosition(p)
            setElementRotation(p, 0, 0, headingTo(x - fromX, y - fromY) + math.random(-25, 25), "default", true)
            setPedControlState(p, "forwards", true)
            setPedControlState(p, "sprint", true)
        end
    end
end

local function playerOk()
    if not getElementData(localPlayer, "rp:characterId") then return false end
    if getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0 then return false end
    local v = getPedOccupiedVehicle(localPlayer)
    if v then
        local vx, vy = getElementVelocity(v)
        if math.sqrt(vx * vx + vy * vy) * 180 > 70 then return false end
    end
    return true
end

local function decide()
    local lv = intensity()
    if lv < 1 or not citizensEnabled() or not playerOk() then return end
    if not spots then buildSpots() end

    local h = getTime()
    local cap = GROUP_CAP[math.min(lv, 3)]
    if getRainLevel() > 0.15 then cap = math.min(cap, 1) end          -- con lluvia casi nadie esta fuera
    if h >= 1 and h < 5 then cap = math.min(cap, 2) end               -- madrugada
    local maxPeds = (h >= 20 or h < 5) and MAX_PEDS_NIGHT or MAX_PEDS_DAY
    if #groups >= cap or hangPeds >= maxPeds - 2 then return end

    local px, py = getElementPosition(localPlayer)
    local now = getTickCount()
    local cx, cy = math.floor(px / CELL), math.floor(py / CELL)
    local best, bestScore
    for ox = -1, 1 do
        for oy = -1, 1 do
            local cell = spots[(cx + ox) * 1000 + (cy + oy)]
            if cell then
                for _, s in ipairs(cell) do
                    if not s.group and now > s.rest then
                        local d = getDistanceBetweenPoints2D(px, py, s.x, s.y)
                        if d >= MIN_D and d <= MAX_D then
                            -- prefiere los puntos mas cercanos (se nota mas la vida al llegar)
                            local score = d + math.random() * 25
                            if not bestScore or score < bestScore then
                                -- no aparece a la vista salvo lejos
                                if d > 55 or not citizenIsVisible(s.x, s.y, s.z) then best, bestScore = s, score end
                            end
                        end
                    end
                end
            end
        end
    end
    if not best then return end

    local t = pickType(best.profile, h)
    if not t then best.rest = now + 60000 return end
    local g = { spot = best, peds = {}, anim = now + math.random(12000, 22000), born = now }
    best.group = g
    g.gang = (t == "gang")   -- c_gangs.lua: personalidad y enojo en vez de panico
    groups[#groups + 1] = g
    TYPES[t](g, best)
    if #g.peds == 0 then destroyGroup(g, 60000) end
end

local function keep()
    if #groups == 0 then return end
    local px, py = getElementPosition(localPlayer)
    local now = getTickCount()
    local off = not playerOk() and (getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0)
    local aimed = getPedTarget(localPlayer)
    local armed = getPedWeapon(localPlayer) >= 22
    for i = #groups, 1, -1 do
        local g = groups[i]
        if g then
            local dist = getDistanceBetweenPoints2D(px, py, g.spot.x, g.spot.y)
            if off or dist > DROP_D or intensity() < 1 or not citizensEnabled() then
                destroyGroup(g, 20000)
            elseif g.endAt and now > g.endAt then
                destroyGroup(g, 180000)
            elseif g.gang and #g.peds == 0 then
                destroyGroup(g, 180000)   -- todos pasaron a c_gangs.lua
            elseif not g.endAt then
                local scared = false
                for _, p in ipairs(g.peds) do
                    if isElement(p) and not g.gang then
                        if isPedDead(p) or (armed and aimed == p) then scared = true end
                    end
                end
                if scared then
                    panicGroup(g, px, py)
                elseif now > g.anim and g.anims then
                    -- cambian de gesto de vez en cuando (hablan, rien, fuman)
                    g.anim = now + math.random(12000, 24000)
                    for _, p in ipairs(g.peds) do
                        if isElement(p) and math.random() < 0.6 then setAnim(p, pick(g.anims)) end
                    end
                end
            end
        end
    end
end

local function groupOf(ped)
    for _, g in ipairs(groups) do
        for _, p in ipairs(g.peds) do if p == ped then return g end end
    end
end

-- c_gangs.lua: ver si un peaton es de un grupo y sacarlo de el (queda libre, sin animacion)
function hangoutHas(ped) return groupOf(ped) ~= nil end

function hangoutRelease(ped)
    local g = groupOf(ped)
    if not g then return false end
    for i = #g.peds, 1, -1 do if g.peds[i] == ped then table.remove(g.peds, i) end end
    hangPeds = hangPeds - 1
    setPedAnimation(ped)
    return true
end

addEventHandler("onClientPedDamage", root, function(attacker)
    if #groups == 0 then return end
    local g = groupOf(source)
    if g and g.gang then return end   -- las bandas las gobierna c_gangs.lua
    if g then
        local x, y = getElementPosition(isElement(attacker) and attacker or localPlayer)
        panicGroup(g, x, y)
    end
end)

-- Disparos cerca: los grupos a menos de 40 m huyen
addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon)
    if weapon < 22 or #groups == 0 then return end
    local x, y = getElementPosition(localPlayer)
    for _, g in ipairs(groups) do
        if not g.gang and getDistanceBetweenPoints2D(x, y, g.spot.x, g.spot.y) < 40 then panicGroup(g, x, y) end
    end
end)

-- Explosiones: igual
addEventHandler("onClientExplosion", root, function(x, y)
    for _, g in ipairs(groups) do
        if getDistanceBetweenPoints2D(x, y, g.spot.x, g.spot.y) < 50 then panicGroup(g, x, y) end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(decide, DECIDE_MS, 0)
    setTimer(keep, KEEP_MS, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for i = #groups, 1, -1 do destroyGroup(groups[i], 0) end
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    for i = #groups, 1, -1 do destroyGroup(groups[i], 20000) end
end)

-- Diagnostico: /barrioinfo
addCommandHandler("barrioinfo", function()
    local total = 0
    if spots then for _, c in pairs(spots) do total = total + #c end end
    local px, py, pz = getElementPosition(localPlayer)
    local profile, zone = citizenZoneInfo(px, py, pz)
    local near, nearest = 0, nil
    if spots then
        local cx, cy = math.floor(px / CELL), math.floor(py / CELL)
        for ox = -1, 1 do
            for oy = -1, 1 do
                for _, s in ipairs(spots[(cx + ox) * 1000 + (cy + oy)] or {}) do
                    local d = getDistanceBetweenPoints2D(px, py, s.x, s.y)
                    if d <= MAX_D then near = near + 1 end
                    if not nearest or d < nearest then nearest = d end
                end
            end
        end
    end
    outputChatBox(("[Barrio] %s (%s) | intensidad %d | puntos %d (a <%d m: %d, el mas cercano %s m) | grupos %d, peds %d | poblacion %s | listo %s"):format(
        zone, profile, intensity(), total, MAX_D, near, nearest and math.floor(nearest) or "-", #groups, hangPeds,
        tostring(citizensEnabled()), tostring(playerOk())), 255, 220, 120)
end)

-- Primera pasada poco despues de cargar, sin esperar al primer tick
setTimer(function() if spots == nil and playerOk() then buildSpots() end end, 4000, 1)
