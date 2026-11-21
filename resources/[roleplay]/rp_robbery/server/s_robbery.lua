--[[
    rp_robbery / s_robbery.lua
    Maquina de estados del robo (una por jugador, una por tienda):

      threat       apunto al cajero: barra de miedo, H amenaza, E en la caja
      looting      vaciando la caja (cinematica en el cliente), fardo a fardo
      standoff     botin en mano: patrullas esperando afuera
      negotiating  al salir: negociacion por turnos (CEF en el cliente)
      escape       trato cerrado: libre, la cuenta empieza al alejarse
      countdown    cuenta regresiva; en 0 la persecucion de rp_wanted

    Estrellas (rp_wanted, forzadas): 3 / 4 si murio un rehen / 5 si murio el
    cajero. Se ponen cuando llegan las patrullas con la persecucion retenida
    (holdPursuit) y se sueltan al terminar la cuenta. Las condiciones
    negociadas van con setPursuitTerms.

    Exports: isPlayerRobbing, getRobberyState, getStoreCount, simulateNegotiation
]]

ROBS = {}                 -- [player] = R
local playerCooldown = {} -- [characterId] = tick

for _, e in ipairs({ "aim", "aimState", "intimidate", "warningShot", "loot", "choose", "negotiationClosed",
    "hostageOut", "breach" }) do
    addEvent("rp:robbery:" .. e, true)
end
addEvent("rp:onCharacterLogout", false)

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function popup(p, title, t, k) exports.rp_notify:popup(p, title, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function displayName(p)
    local n = exports.rp_characters:getPlayerCharacterName(p) or getPlayerName(p)
    return (tostring(n):gsub("_", " "))
end
local function now() return getTickCount() end

-- rp_wanted es opcional: si no corre, el robo funciona sin estrellas
local function wanted(fn, ...)
    local res = getResourceFromName("rp_wanted")
    if not res or getResourceState(res) ~= "running" then return nil end
    local ok, a, b = pcall(call, res, fn, ...)
    if ok then return a, b end
    outputDebugString("[rp_robbery] rp_wanted:" .. fn .. " fallo: " .. tostring(a), 2)
end

local function hasFirearm(player)
    local w = getPedWeapon(player) or 0
    return w >= ROBBERY.FIREARM_MIN and w <= ROBBERY.FIREARM_MAX
end

local function alive(ped) return isElement(ped) and not isPedDead(ped) end

local function dist(a, b)
    local x1, y1, z1 = getElementPosition(a)
    local x2, y2, z2 = getElementPosition(b)
    return getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)
end

local function anim(ped, block, name, time, loop, freeze)
    if alive(ped) then setPedAnimation(ped, block, name, time or -1, loop or false, false, false, freeze ~= false) end
end

local function later(R, ms, fn)
    local t = setTimer(function()
        if ROBS[R.player] == R or R.lingering then fn() end
    end, ms, 1)
    R.timers[#R.timers + 1] = t
    return t
end

----------------------------------------------------------------
-- Rehenes
----------------------------------------------------------------
-- Rehenes que aun cuentan para negociar: vivos, dentro y sin escaparse.
-- Un cajero armado no se deja canjear.
local function hostageList(R)
    local list = {}
    for _, ped in ipairs(R.hostages) do
        if alive(ped) and not R.gone[ped] and not (ped == R.store.clerk and R.hostile) then list[#list + 1] = ped end
    end
    return list
end

local function setStars(R)
    local stars = robberyStarsFor(R.clerkKilled, R.hostagesKilled)
    local current = wanted("getWantedLevel", R.player) or 0
    if stars > current then wanted("setWantedLevel", R.player, stars, true) end
    R.stars = math.max(stars, current)
end

----------------------------------------------------------------
-- Fin del robo (cualquier motivo)
----------------------------------------------------------------
local function destroyStage(R)
    if not R.stage then return end
    for _, el in ipairs(R.stage.elements) do
        if isElement(el) then destroyElement(el) end
    end
    R.stage = nil
end

function endRobbery(R, reason)
    if ROBS[R.player] ~= R then return end
    ROBS[R.player] = nil
    local player, store = R.player, R.store
    if store.robbery == R then store.robbery = nil end
    store.cooldownUntil = now() + ROBBERY.STORE_COOLDOWN
    if R.characterId then playerCooldown[R.characterId] = now() end
    for _, t in ipairs(R.timers) do if isTimer(t) then killTimer(t) end end
    R.timers = {}
    outputServerLog(("[rp_robbery] %s: robo de %s termina (%s), botin $%d"):format(
        isElement(player) and getPlayerName(player) or "?", store.row.name, reason, R.loot))

    if isElement(player) then
        if reason ~= "pursuit" then wanted("holdPursuit", player, false) end
        toggleAllControls(player, true, true, false)
        setElementFrozen(player, false)
        if R.state == "looting" or R.state == "negotiating" then setPedAnimation(player) end
        triggerClientEvent(player, "rp:robbery:stop", resourceRoot, reason)
    end

    -- Las patrullas del cerco se van un rato despues (o al instante si ya no hay jugador)
    if R.stage then
        if isElement(player) and reason == "pursuit" then
            setTimer(destroyStage, ROBBERY.POLICE.LEAVE_AFTER, 1, R)
        else
            destroyStage(R)
        end
    end
    -- Rehenes que siguen con animacion: quietos de nuevo; vuelven a su sitio mas tarde
    setTimer(function()
        if not STORES[store.row.id] or store.robbery then return end
        spawnStorePeds(store)
    end, ROBBERY.PEDS_RESPAWN, 1)
end

----------------------------------------------------------------
-- Inicio: apuntar a un NPC de la tienda
----------------------------------------------------------------
local refusedAt = {}

local function refuse(player, text)
    local t = now()
    if refusedAt[player] and t - refusedAt[player] < 8000 then return end
    refusedAt[player] = t
    notify(player, text, "warning")
end

local function startRobbery(player, store, target)
    local cid = characterOf(player)
    local R = {
        player = player, store = store, characterId = cid, state = "threat",
        fear = ROBBERY.FEAR.START, aiming = true, lastIntimidate = 0, lastWarning = 0,
        loot = 0, clerkKilled = false, hostagesKilled = 0, hostile = false,
        hostages = {}, gone = {}, timers = {}, startedAt = now(),
    }
    ROBS[player] = R
    store.robbery = R

    if alive(store.clerk) then R.hostages[#R.hostages + 1] = store.clerk end
    for _, ped in ipairs(store.customers) do
        if alive(ped) then R.hostages[#R.hostages + 1] = ped end
    end
    -- El cliente del ladron mueve a los NPC (cajero armado, rehen que huye)
    for _, ped in ipairs(R.hostages) do
        setElementSyncer(ped, player)
        if ped == store.clerk then
            anim(ped, "SHOP", "SHP_Rob_HandsUp", -1, false)
        else
            anim(ped, "ped", "cower", -1, true)
        end
    end

    local reg = getStorePoint(store, "register")
    triggerClientEvent(player, "rp:robbery:start", resourceRoot, {
        store = store.row.id, name = store.row.name, clerk = store.clerk, hostages = R.hostages,
        register = { reg.x, reg.y, reg.z }, fear = R.fear,
    })
    exports.rp_notify:bubble(player, store.clerk, "¡No dispares! ¡Llevate lo que quieras!", 3500)
    outputServerLog(("[rp_robbery] %s inicia un robo en %s (%d rehenes)"):format(getPlayerName(player), store.row.name, #R.hostages))
    return R
end

addEventHandler("rp:robbery:aim", resourceRoot, function(ped)
    local player = client
    if ROBS[player] or not isElement(ped) or getElementType(ped) ~= "ped" then return end
    local role = getElementData(ped, "rp:robberyPed")
    if role ~= "clerk" and role ~= "customer" then return end
    local store = getPlayerStore(player)
    if not store or tonumber(getElementData(ped, "rp:robberyStore")) ~= store.row.id then return end
    if not characterOf(player) or getElementData(player, "rp:downed") or isPedDead(player) then return end
    if not hasFirearm(player) or dist(player, ped) > ROBBERY.AIM_DISTANCE then return end
    if store.robbery then return refuse(player, "Ya estan robando esta tienda.") end
    if not alive(store.clerk) then return refuse(player, "No hay nadie atendiendo la caja.") end
    if store.cooldownUntil and now() < store.cooldownUntil then
        return refuse(player, "La caja esta vacia: robaron esta tienda hace poco.")
    end
    local last = playerCooldown[characterOf(player)]
    if last and now() - last < ROBBERY.PLAYER_COOLDOWN then
        return refuse(player, "Espera un poco antes de otro robo: la policia esta atenta.")
    end
    startRobbery(player, store, ped)
end)

-- El cliente avisa si esta apuntando al cajero (el miedo baja mas lento)
addEventHandler("rp:robbery:aimState", resourceRoot, function(on)
    local R = ROBS[client]
    if R then R.aiming = on == true end
end)

----------------------------------------------------------------
-- Miedo
----------------------------------------------------------------
local THREATS = {
    "¡Las manos donde pueda verlas!", "¡Ni se te ocurra tocar ese telefono!", "¡Rapido o esto se pone feo!",
    "¡Quieto! ¡Nadie se hace el heroe!", "¡Mirame! ¡Yo mando aqui!",
}

local function addFear(R, amount)
    R.fear = math.min(100, R.fear + amount)
    triggerClientEvent(R.player, "rp:robbery:fear", resourceRoot, R.fear, true)
end

addEventHandler("rp:robbery:intimidate", resourceRoot, function()
    local R = ROBS[client]
    if not R or R.state ~= "threat" or R.hostile or not alive(R.store.clerk) then return end
    local t = now()
    if t - R.lastIntimidate < ROBBERY.FEAR.INTIMIDATE_COOLDOWN then return end
    if not hasFirearm(client) or dist(client, R.store.clerk) > ROBBERY.AIM_DISTANCE then return end
    R.lastIntimidate = t
    addFear(R, ROBBERY.FEAR.INTIMIDATE)
    anim(R.store.clerk, "SHOP", "SHP_Rob_React", 1200, false)
    later(R, 1250, function() if R.state == "threat" and not R.hostile then anim(R.store.clerk, "SHOP", "SHP_HandsUp_Scr", -1, true) end end)
    exports.rp_notify:bubble(client, client, THREATS[math.random(#THREATS)], 2200)
end)

addEventHandler("rp:robbery:warningShot", resourceRoot, function()
    local R = ROBS[client]
    if not R or R.state ~= "threat" or R.hostile or not alive(R.store.clerk) then return end
    local t = now()
    if t - R.lastWarning < ROBBERY.FEAR.WARNING_COOLDOWN or not hasFirearm(client) then return end
    R.lastWarning = t
    addFear(R, ROBBERY.FEAR.WARNING_SHOT)
    for _, ped in ipairs(R.hostages) do
        if alive(ped) and ped ~= R.store.clerk then anim(ped, "SHOP", "SHP_Duck", -1, false) end
    end
end)

-- Miedo en 0: el cajero saca la escopeta y un cliente intenta huir
local function clerkFightsBack(R)
    local clerk = R.store.clerk
    R.hostile = true
    if alive(clerk) then
        setPedAnimation(clerk)
        setElementFrozen(clerk, false)
        giveWeapon(clerk, ROBBERY.CLERK_WEAPON, 99, true)
        setElementData(clerk, "rp:robberyHostile", true)
        anim(clerk, "SHOP", "SHP_Gun_Grab", 900, false, false)
        exports.rp_notify:bubble(R.player, clerk, "¡Se acabo! ¡Fuera de mi tienda!", 3000)
    end
    local runner
    for _, ped in ipairs(hostageList(R)) do
        if ped ~= clerk then runner = ped break end
    end
    if runner then
        setPedAnimation(runner)
        setElementFrozen(runner, false)
        R.gone[runner] = "fleeing"
        local e = getStorePoint(R.store, "exit")
        triggerClientEvent(R.player, "rp:robbery:flee", resourceRoot, runner, e.x, e.y, e.z)
        later(R, 9000, function() if isElement(runner) and R.gone[runner] == "fleeing" then destroyElement(runner) end end)
    end
    triggerClientEvent(R.player, "rp:robbery:hostile", resourceRoot, clerk, runner)
    popup(R.player, "¡Perdiste el control!", "El cajero saco una escopeta de debajo del mostrador.", "error")
end

-- El rehen que huia llego a la puerta: desaparece (se fue a la calle)
addEventHandler("rp:robbery:hostageOut", resourceRoot, function(ped)
    local R = ROBS[client]
    if not R or not isElement(ped) or R.gone[ped] ~= "fleeing" then return end
    R.gone[ped] = "escaped"
    destroyElement(ped)
end)

setTimer(function()
    for _, R in pairs(ROBS) do
        if R.state == "threat" and not R.hostile and alive(R.store.clerk) then
            local rate = R.aiming and ROBBERY.FEAR.DECAY_AIMING or ROBBERY.FEAR.DECAY
            R.fear = math.max(0, R.fear - rate * 0.25)
            triggerClientEvent(R.player, "rp:robbery:fear", resourceRoot, R.fear, false)
            if R.fear <= 0 then clerkFightsBack(R) end
        end
    end
end, 250, 0)

----------------------------------------------------------------
-- Caja registradora
----------------------------------------------------------------
local stagePolice

local function finishLoot(R)
    local player = R.player
    setPedAnimation(player)
    toggleAllControls(player, true, true, false)
    exports.rp_characters:saveCharacter(player)
    for _, ped in ipairs(hostageList(R)) do
        if ped == R.store.clerk then anim(ped, "SHOP", "SHP_HandsUp_Scr", -1, true) else anim(ped, "ped", "cower", -1, true) end
    end
    triggerClientEvent(player, "rp:robbery:lootEnd", resourceRoot, R.loot)
    stagePolice(R)
end

addEventHandler("rp:robbery:loot", resourceRoot, function()
    local player = client
    local R = ROBS[player]
    if not R or R.state ~= "threat" or isPedInVehicle(player) then return end
    local store = R.store
    if getPlayerStore(player) ~= store then return end
    local reg = getStorePoint(store, "register")
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, reg.x, reg.y, reg.z) > ROBBERY.LOOT.RADIUS + 0.6 then return end
    if R.hostile and alive(store.clerk) then
        return notify(player, "¡El cajero te esta apuntando! Encargate de el primero.", "error")
    end

    R.state = "looting"
    toggleAllControls(player, false, true, false)
    setElementRotation(player, 0, 0, (360 - math.deg(math.atan2(reg.x - px, reg.y - py))) % 360, "default", true)
    anim(player, "ROB_BANK", "CAT_Safe_Rob", -1, true, false)
    if alive(store.clerk) then anim(store.clerk, "SHOP", "SHP_Rob_GiveCash", -1, true) end

    local L = ROBBERY.LOOT
    local mult = ROBBERY_TYPES[store.row.type].multiplier or 1
    triggerClientEvent(player, "rp:robbery:lootStart", resourceRoot, { reg.x, reg.y, reg.z }, store.clerk,
        L.BUNDLES * L.BUNDLE_MS, L.BUNDLES)
    for i = 1, L.BUNDLES do
        later(R, i * L.BUNDLE_MS, function()
            if R.state ~= "looting" or not isElement(player) then return end
            local amount = math.floor(math.random(L.BUNDLE_MIN, L.BUNDLE_MAX) * mult)
            R.loot = R.loot + amount
            givePlayerMoney(player, amount)
            triggerClientEvent(player, "rp:robbery:bundle", resourceRoot, i, amount, R.loot)
            if i == L.BUNDLES then later(R, 500, function() finishLoot(R) end) end
        end)
    end
end)

----------------------------------------------------------------
-- Cerco policial afuera
----------------------------------------------------------------
local function cityPolice(x, y, z)
    local city = getZoneName(x, y, z, true)
    return ROBBERY.POLICE.CITY[city] or ROBBERY.POLICE.CITY.rural
end

stagePolice = function(R)
    local store, P = R.store, ROBBERY.POLICE
    local d = store.row
    local r = math.rad(d.rot)
    local fx, fy = -math.sin(r), math.cos(r)       -- hacia la calle
    local lx, ly = math.cos(r), math.sin(r)        -- a lo largo de la fachada
    local fleet = cityPolice(d.x, d.y, d.z)
    local stage = { elements = {}, cops = {}, cars = {} }
    R.stage = stage
    local function keep(el, role)
        if not el then return end
        stage.elements[#stage.elements + 1] = el
        if role then
            setElementData(el, "rp:robberyPed", role)
            setElementData(el, "rp:robberyOwner", R.player)
        end
        return el
    end

    local half = (P.CARS - 1) / 2
    for i = 0, P.CARS - 1 do
        local off = (i - half) * P.SPACING
        local cx, cy = d.x + fx * P.DISTANCE + lx * off, d.y + fy * P.DISTANCE + ly * off
        local car = keep(createVehicle(fleet.model, cx, cy, d.z - 0.3, 0, 0, d.rot + (i % 2 == 0 and 80 or 100)))
        if car then
            stage.cars[#stage.cars + 1] = car
            setVehicleSirensOn(car, true)
            setVehicleLocked(car, true)
            setVehicleDamageProof(car, true)
            setElementFrozen(car, true)
            setElementData(car, "rp:copCar", true)
        end
        for k = 1, P.COPS_PER_CAR do
            local side = (k == 1) and -1.6 or 1.6
            local ped = keep(createPed(fleet.skin, cx + fx * 2.4 + lx * side, cy + fy * 2.4 + ly * side, d.z,
                (d.rot + 180) % 360), "cop")
            if ped then
                giveWeapon(ped, P.WEAPON, 200, true)
                setElementData(ped, "rp:cop", true)
                stage.cops[#stage.cops + 1] = ped
            end
        end
    end
    stage.negotiator = keep(createPed(P.NEGOTIATOR_SKIN, d.x + fx * (P.DISTANCE - 4), d.y + fy * (P.DISTANCE - 4), d.z,
        (d.rot + 180) % 360), "negotiator")
    if stage.negotiator then setElementFrozen(stage.negotiator, true) end

    R.state = "standoff"
    R.standoffAt = now()
    wanted("holdPursuit", R.player, true)
    setStars(R)
    popup(R.player, "¡Alarma silenciosa!", "La policia rodeo la tienda. Al salir tendras que negociar.", "warning")
    triggerClientEvent(R.player, "rp:robbery:standoff", resourceRoot, stage.cops, stage.negotiator)

    -- Si se queda dentro demasiado, la policia deja de negociar
    later(R, P.INSIDE_PATIENCE, function()
        if R.state ~= "standoff" then return end
        popup(R.player, "Sin negociacion", "La policia se canso de esperar. Saldran a por ti en cuanto pongas un pie fuera.", "error")
        endRobbery(R, "nodeal")
    end)
end

----------------------------------------------------------------
-- Negociacion
----------------------------------------------------------------
local function dealStatus(R)
    local d = R.deal
    return { chips = d.chips, seconds = d.seconds, noTraps = d.noTraps, noTires = d.noTires,
        patience = d.patience, round = d.round, maxRounds = ROBBERY.NEGOTIATION.MAX_ROUNDS }
end

local function sendTurn(R, lines)
    local opts = {}
    for _, o in ipairs(robberyOptionsFor(R.deal)) do opts[#opts + 1] = { id = o.id, label = o.label } end
    triggerClientEvent(R.player, "rp:robbery:turn", resourceRoot, {
        lines = lines, options = opts, status = dealStatus(R), done = R.deal.done,
        result = R.deal.result,
    })
end

local finishNegotiation

local function startNegotiation(R)
    local player = R.player
    R.state = "negotiating"
    R.deal = robberyNewDeal(#hostageList(R))
    toggleAllControls(player, false, true, false)
    setElementFrozen(player, true)
    if R.stage then
        for _, el in ipairs(R.stage.elements) do
            if getElementType(el) == "ped" then setElementSyncer(el, player) end
        end
    end
    local name = displayName(player)
    triggerClientEvent(player, "rp:robbery:negotiation", resourceRoot, {
        negotiator = R.stage and R.stage.negotiator, cops = R.stage and R.stage.cops or {},
        cars = R.stage and R.stage.cars or {}, name = name, copName = ROBBERY.NEGOTIATION.NEGOTIATOR,
    })
    local intro = R.deal.chips > 0 and "intro" or "intro_nochips"
    sendTurn(R, {
        { speaker = "cop", text = robberyLine(intro, name), mood = "intro", burst = ROBBERY_BURSTS.intro },
        { speaker = "cop", text = robberyLine("ask", name) },
    })
end

-- Un rehen canjeado sale por la puerta con las manos en alto hacia la policia
local function releaseHostage(R)
    local list = hostageList(R)
    local ped
    for _, p in ipairs(list) do if p ~= R.store.clerk then ped = p break end end
    ped = ped or list[1]
    if not ped then return end
    R.gone[ped] = "released"
    local d = R.store.row
    local r = math.rad(d.rot)
    setPedAnimation(ped)
    setElementInterior(ped, 0)
    setElementDimension(ped, 0)
    setElementPosition(ped, d.x - math.sin(r) * 1.5 + math.cos(r) * 1.2, d.y + math.cos(r) * 1.5 + math.sin(r) * 1.2, d.z)
    setElementRotation(ped, 0, 0, d.rot, "default", true)
    setElementFrozen(ped, false)
    setElementSyncer(ped, R.player)
    triggerClientEvent(R.player, "rp:robbery:released", resourceRoot, ped)
    setTimer(function() if isElement(ped) then destroyElement(ped) end end, 7000, 1)
end

addEventHandler("rp:robbery:choose", resourceRoot, function(id)
    local R = ROBS[client]
    if not R or R.state ~= "negotiating" or R.deal.done or type(id) ~= "string" then return end
    local t = now()
    if R.lastChoice and t - R.lastChoice < 600 then return end
    R.lastChoice = t
    local option
    for _, o in ipairs(robberyOptionsFor(R.deal)) do if o.id == id then option = o end end
    if not option then return end
    local ok, effect = robberyApplyOption(R.deal, id)
    if not ok then return end
    if effect:find("^release_") then releaseHostage(R) end

    local name = displayName(R.player)
    local lines = { { speaker = "player", text = option.say } }
    local base = effect:gsub("%+timeout$", "")
    lines[#lines + 1] = { speaker = "cop", text = robberyLine(base, name), mood = base, burst = ROBBERY_BURSTS[base] }
    if effect:find("%+timeout$") then
        lines[#lines + 1] = { speaker = "cop", text = robberyLine("timeout", name), mood = "timeout" }
    elseif not R.deal.done then
        lines[#lines + 1] = { speaker = "cop", text = robberyLine("ask", name) }
    end
    sendTurn(R, lines)
    if R.deal.done then
        -- el cliente avisa al cerrar la ultima frase; por si no llega, se cierra solo
        later(R, 25000, function() if R.state == "negotiating" then finishNegotiation(R) end end)
    end
end)

addEventHandler("rp:robbery:negotiationClosed", resourceRoot, function()
    local R = ROBS[client]
    if R and R.state == "negotiating" and R.deal.done then finishNegotiation(R) end
end)

local function startPursuit(R, breach)
    if R.state == "pursuit" then return end
    R.state = "pursuit"
    if breach then
        wanted("setPursuitTerms", R.player, false, false)
        local current = wanted("getWantedLevel", R.player) or R.stars or 3
        wanted("setWantedLevel", R.player, math.min(6, current + 1), true)
    end
    wanted("holdPursuit", R.player, false)
    triggerClientEvent(R.player, "rp:robbery:pursuit", resourceRoot, breach and true or false)
    endRobbery(R, "pursuit")
end

local function startCountdown(R)
    R.state = "countdown"
    local secs = R.deal and R.deal.seconds or 0
    if secs <= 0 then return startPursuit(R) end
    R.countdownEnd = now() + secs * 1000
    triggerClientEvent(R.player, "rp:robbery:countdown", resourceRoot, secs)
    later(R, secs * 1000, function() if R.state == "countdown" then startPursuit(R) end end)
end

finishNegotiation = function(R)
    local player, d = R.player, R.deal
    setElementFrozen(player, false)
    toggleAllControls(player, true, true, false)
    if d.result == "surrender" then
        -- Devuelve el botin (lo que le quede en mano) y va a la carcel
        local back = math.min(R.loot, getPlayerMoney(player))
        if back > 0 then takePlayerMoney(player, back) end
        exports.rp_characters:saveCharacter(player)
        wanted("clearWanted", player)
        wanted("jailPlayer", player, ROBBERY.SURRENDER.JAIL_SECONDS, ROBBERY.SURRENDER.BAIL, 0)
        return endRobbery(R, "surrender")
    end
    -- trato (o sin trato si se le acabo la paciencia al negociador)
    wanted("setPursuitTerms", player, d.noTraps, d.noTires)
    R.state = "escape"
    R.escapeAt = now()
    local door = R.store.row
    triggerClientEvent(player, "rp:robbery:escape", resourceRoot, {
        seconds = d.seconds, noTraps = d.noTraps, noTires = d.noTires, broken = d.result == "broken",
        door = { door.x, door.y, door.z }, radius = ROBBERY.ESCAPE.RADIUS,
    })
    if d.result == "broken" then
        notify(player, "¡Sin trato! La policia sale a por ti ya.", "error")
        return startPursuit(R)
    end
end

-- Alejarse de la puerta inicia la cuenta (o pasado MAX_WAIT aunque no se mueva)
setTimer(function()
    for player, R in pairs(ROBS) do
        if R.state == "escape" then
            local d = R.store.row
            local x, y, z = getElementPosition(player)
            local far = getElementDimension(player) == 0 and getElementInterior(player) == 0
                and getDistanceBetweenPoints3D(x, y, z, d.x, d.y, d.z) > ROBBERY.ESCAPE.RADIUS
            if far or now() - R.escapeAt > ROBBERY.ESCAPE.MAX_WAIT then startCountdown(R) end
        end
    end
end, 250, 0)

-- Disparar a la policia del cerco rompe el trato (lo informa el cliente del ladron)
addEventHandler("rp:robbery:breach", resourceRoot, function(ped)
    local R = ROBS[client]
    if not R or not R.stage or not isElement(ped) then return end
    if getElementData(ped, "rp:robberyOwner") ~= client then return end
    if R.state ~= "escape" and R.state ~= "countdown" and R.state ~= "negotiating" and R.state ~= "standoff" then return end
    popup(client, "¡Rompiste el trato!", "Disparaste a la policia: sin condiciones y una estrella mas.", "error")
    if R.stage then
        for _, cop in ipairs(R.stage.cops) do if isElement(cop) then setElementData(cop, "rp:robberyHostile", true) end end
    end
    if R.state == "negotiating" then
        setElementFrozen(client, false)
        toggleAllControls(client, true, true, false)
    end
    startPursuit(R, true)
end)

----------------------------------------------------------------
-- Entrar / salir de la tienda (llamados desde s_stores.lua)
----------------------------------------------------------------
function canEnterStore(player, store)
    local R = ROBS[player]
    if R and R.state ~= "threat" and R.state ~= "looting" and R.state ~= "standoff" then
        notify(player, "No puedes volver a entrar ahora.", "warning")
        return false
    end
    return true
end

function onPlayerLeftStore(player, store)
    local R = ROBS[player]
    if not R or R.store ~= store then return end
    if R.state == "threat" then
        -- Se fue sin vaciar la caja: el cajero llama a la policia
        local stars = math.max(ROBBERY.ESCAPE.ABORT_STARS, (R.clerkKilled or R.hostagesKilled > 0)
            and robberyStarsFor(R.clerkKilled, R.hostagesKilled) or 0)
        wanted("setWantedLevel", player, math.max(stars, wanted("getWantedLevel", player) or 0), true)
        notify(player, "Huiste sin el botin. El cajero ya llamo a la policia.", "warning")
        endRobbery(R, "abort")
    elseif R.state == "standoff" then
        startNegotiation(R)
    end
end

----------------------------------------------------------------
-- Muertes, abatidos y desconexiones
----------------------------------------------------------------
addEventHandler("onPedWasted", root, function(_, killer)
    local role = getElementData(source, "rp:robberyPed")
    if not role then return end
    local killerPlayer = killer and isElement(killer) and getElementType(killer) == "vehicle" and getVehicleController(killer) or killer
    if not (killerPlayer and isElement(killerPlayer) and getElementType(killerPlayer) == "player") then killerPlayer = nil end

    if role == "cop" or role == "negotiator" then
        local owner = getElementData(source, "rp:robberyOwner")
        local R = owner and ROBS[owner]
        if R and killerPlayer == owner then startPursuit(R, true) end
        return
    end
    local storeId = tonumber(getElementData(source, "rp:robberyStore"))
    local store = storeId and STORES[storeId]
    local R = store and store.robbery
    if R and killerPlayer == R.player then
        if role == "clerk" then R.clerkKilled = true else R.hostagesKilled = R.hostagesKilled + 1 end
        if R.state == "threat" and role == "clerk" then
            triggerClientEvent(R.player, "rp:robbery:fear", resourceRoot, -1, false)   -- oculta la barra
        end
        if R.stars then setStars(R) end
        outputServerLog(("[rp_robbery] %s mato a un %s en %s"):format(getPlayerName(R.player),
            role == "clerk" and "cajero" or "rehen", store.row.name))
    elseif killerPlayer and not R then
        -- Matar a un NPC de la tienda sin robo: delito normal
        wanted("reportCrime", killerPlayer, "ped_shoot", "robbery:" .. tostring(storeId), false, "civil")
        if store then
            setTimer(function() if STORES[storeId] and not store.robbery then spawnStorePeds(store) end end,
                ROBBERY.PEDS_RESPAWN, 1)
        end
    end
end)

local function stopFor(player, reason)
    local R = ROBS[player]
    if R then endRobbery(R, reason) end
end

addEventHandler("onPlayerWasted", root, function() stopFor(source, "dead") end)
addEventHandler("onPlayerQuit", root, function()
    stopFor(source, "quit")
    refusedAt[source] = nil
end)
addEventHandler("rp:onCharacterLogout", root, function() stopFor(source, "logout") end)
addEventHandler("onElementDataChange", root, function(key, _, new)
    if key == "rp:downed" and new and getElementType(source) == "player" then stopFor(source, "downed") end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, R in pairs(ROBS) do endRobbery(R, "stop") end
end)

----------------------------------------------------------------
-- Exports
----------------------------------------------------------------
function isPlayerRobbing(player)
    return ROBS[player] ~= nil
end

function getRobberyState(player)
    local R = ROBS[player]
    return R and R.state or false
end

function getStoreCount()
    local n = 0
    for _ in pairs(STORES) do n = n + 1 end
    return n
end

-- Para rp_test: aplica una lista de opciones con tiradas fijas y devuelve el trato final
function simulateNegotiation(chips, choices, rolls)
    local deal = robberyNewDeal(chips)
    local effects = {}
    for i, id in ipairs(choices or {}) do
        local ok, effect = robberyApplyOption(deal, id, rolls and rolls[i])
        effects[#effects + 1] = ok and effect or "invalid"
    end
    deal.effects = effects
    return deal
end

-- Admin: estado de una tienda y abortar/reiniciar (s_admin.lua)
function resetStore(store)
    if store.robbery then endRobbery(store.robbery, "admin") end
    store.cooldownUntil = nil
    spawnStorePeds(store)
end
