--[[
    rp_gym / s_trainers.lua
    Entrenadores de boxeo (Ganton), kung fu (Cobra) y kickboxing (Below the Belt).

    Flujo: E junto al entrenador con 35 % de musculo o mas -> aviso -> E otra vez (en 8 s) para aceptar.
    Combate:
      - Con ring (GYM_FIXED): publico alrededor (unos te apoyan, otros al entrenador, fotografos con flash),
        arbitro, jugador y entrenador a esquinas opuestas, cinematica de presentacion y cuenta 3-2-1
        (GYM_FIGHT.INTRO_MS) y campana. Los efectos (cinematica, sangre, aturdimiento, caidas y cuenta del
        arbitro, publico) los hace el cliente del jugador: client/c_fight.lua.
      - El jugador es el sincronizador del entrenador y su cliente lleva la IA (setPedControlState solo existe
        en el cliente). El servidor mide vidas y distancia al ring y decide el resultado.
      - Durante el combate rp_wanted queda suspendido (pegar al entrenador no da estrellas); con estrellas no se pelea.
      - Victoria: la vida del entrenador baja a TRAINER_WIN_HP. Se aprende el estilo (reemplaza al anterior).
      - Derrota: la vida del jugador baja a PLAYER_LOSE_HP, un golpe lo mataria o no se levanta antes del 10.
        No queda abatido. Gane o pierda, al terminar aparece junto al entrenador, fuera del ring.
      - Rendirse: salir del ring (en Cobra, de la esterilla) hace perder las armas, como en el original.
    Cada estilo se aprende una sola vez: no hay forma de recuperar uno reemplazado, como en el original.

    Eventos cliente -> servidor (con `client`):
        rp:gym:trainer (trainerId)
        rp:gym:down (caido)       el jugador cae (true) o se levanta (false) durante el combate
        rp:gym:lost               el jugador pierde (no se levanto a tiempo o un golpe lo mataria)
    Evento servidor -> cliente:
        rp:gym:fight (ped, activo, resultado | datos)   empieza (datos: publico, arbitro, nombre) o termina
    Element data publico: rp:gymFight = true mientras pelea (rp_injury no lo deja abatido).
]]

addEvent("rp:gym:trainer", true)
addEvent("rp:gym:down", true)
addEvent("rp:gym:lost", true)

local trainers = {}   -- [id] = { row, cfg, ped, col, fight, crowd }
local fights = {}     -- [player] = pelea
local pending = {}    -- [player] = { id, tick }
local stopping = false

local function dbg(fmt, ...)
    if not GYM_FIGHT.DEBUG then return end
    local ok, msg = pcall(string.format, fmt, ...)
    outputDebugString("[rp_gym:pelea] " .. (ok and msg or fmt), 3)
end

-- Al terminar el combate el jugador aparece junto al sitio del entrenador (fuera del ring), a su derecha
local function placeBesideTrainer(player, t)
    local r = math.rad(t.row.rotation)
    local x, y = t.row.x + math.cos(r) * 1.3, t.row.y + math.sin(r) * 1.3
    setPedAnimation(player)
    setElementPosition(player, x, y, t.row.z)
    setElementRotation(player, 0, 0, t.row.rotation)
    setCameraTarget(player, player)
    dbg("%s colocado junto al entrenador (%.2f, %.2f, %.2f)", getPlayerName(player), x, y, t.row.z)
end

local function sameWorld(a, b)
    return getElementDimension(a) == getElementDimension(b) and getElementInterior(a) == getElementInterior(b)
end

local function placeIn(el, row)
    setElementInterior(el, row.interior)
    setElementDimension(el, row.dimension)
end

local function createTrainerPed(t)
    local row, cfg = t.row, t.cfg
    local ped = createPed(cfg.skin, row.x, row.y, row.z, row.rotation)
    placeIn(ped, row)
    setElementFrozen(ped, true)
    setPedFightingStyle(ped, cfg.id)
    t.ped = ped
end

function gymSpawnTrainer(row)
    local cfg = GYM_STYLES[row.style]
    if not cfg then return false end
    local t = { row = row, cfg = cfg }
    createTrainerPed(t)
    t.col = createColSphere(row.x, row.y, row.z, GYM.TRIGGER_RADIUS + 0.8)
    placeIn(t.col, row)
    trainers[row.id] = t

    addEventHandler("onColShapeHit", t.col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim or not gymCharacter(el) then return end
        gymNear(el, "trainer", row.id, cfg.label, cfg.name)
    end)
    addEventHandler("onColShapeLeave", t.col, function(el)
        if getElementType(el) == "player" and nearTarget[el] and nearTarget[el][1] == "trainer" and nearTarget[el][2] == row.id then
            gymNear(el, false)
        end
    end)
    return true
end

function gymTrainerList() return trainers end

----------------------------------------------------------------
-- Publico y arbitro (solo entrenadores con ring)
----------------------------------------------------------------
local function destroyCrowd(t)
    for _, c in ipairs(t.crowd or {}) do
        if isElement(c.ped) then destroyElement(c.ped) end
    end
    t.crowd, t.crowdToken = nil, nil
end

local function spawnCrowd(t)
    destroyCrowd(t)
    local ring, row = t.row.ring, t.row
    local list = {}
    local function add(skin, x, y, z, rot, side)
        local ped = createPed(skin, x, y, z, rot)
        if not ped then return end
        placeIn(ped, row)
        setElementFrozen(ped, true)
        setElementData(ped, "rp:gymCrowd", side)
        list[#list + 1] = { ped = ped, side = side }
        return ped
    end
    for _, c in ipairs(ring.crowd or {}) do
        local photo = c.side == "photo"
        local pool = photo and GYM_FIGHT.PHOTO_SKINS or GYM_FIGHT.CROWD_SKINS
        local ped = add(pool[math.random(#pool)], c.x, c.y, ring.crowdZ, c.rot, c.side)
        if ped and photo then
            giveWeapon(ped, 43, 50, true)   -- camara en la mano
            setPedAnimation(ped, "CAMERA", "camstnd_idleloop", -1, true, false, false, false)
        elseif ped then
            setPedAnimation(ped, "RIOT", "RIOT_CHANT", -1, true, false, false, false)
        end
    end
    local r = ring.referee
    if r then add(GYM_FIGHT.REFEREE_SKIN, r.x, r.y, r.z, r.rot, "referee") end
    t.crowd = list
end

-- El publico se queda unos segundos tras el combate (celebracion) y se va
local function dismissCrowd(t, ms)
    local token = {}
    t.crowdToken = token
    setTimer(function() if t.crowdToken == token and not t.fight then destroyCrowd(t) end end, ms, 1)
end

----------------------------------------------------------------
-- Fin del combate
----------------------------------------------------------------
-- Rendirse: se pierden las armas que se llevan (nativas y las del inventario)
local function loseWeapons(player)
    takeAllWeapons(player)
    for itemId, amount in pairs(exports.rp_inventory:getInventory(player) or {}) do
        if itemId:find("^wpn_") then exports.rp_inventory:takeItem(player, itemId, amount) end
    end
end

local function resetTrainer(t)
    if not isElement(t.ped) then return end
    setElementSyncer(t.ped, true)   -- vuelve a la sincronizacion automatica
    setPedAnimation(t.ped)
    setElementFrozen(t.ped, true)
    setElementPosition(t.ped, t.row.x, t.row.y, t.row.z)
    setElementRotation(t.ped, 0, 0, t.row.rotation)
    setElementHealth(t.ped, 100)
end

local function endFight(f, result)
    if f.over then return end
    f.over = true
    if isTimer(f.timer) then killTimer(f.timer) end
    if isTimer(f.liveTimer) then killTimer(f.liveTimer) end
    local player, t = f.player, f.trainer
    fights[player] = nil
    gymInFight[player] = nil
    t.fight = nil
    dbg("fin del combate de %s: %s", isElement(player) and getPlayerName(player) or "?", tostring(result))
    if result == "win" and isElement(t.ped) and not stopping then
        -- K.O.: queda tendido unos segundos y vuelve a su sitio (si nadie empezo otro combate)
        setElementSyncer(t.ped, true)
        setPedAnimation(t.ped, "PED", "KO_skid_front", -1, false, true, false, true)
        setTimer(function() if not t.fight then resetTrainer(t) end end, 3500, 1)
    else
        resetTrainer(t)
    end
    if t.crowd then dismissCrowd(t, 6000) end
    if not isElement(player) then return end
    removeElementData(player, "rp:gymFight")
    if f.suspendedWanted then exports.rp_wanted:setWantedSuspended(player, false) end
    -- Con el recurso parandose el cliente ya no tiene el evento (se limpia solo)
    if not stopping then triggerClientEvent(player, "rp:gym:fight", resourceRoot, t.ped, false, result) end

    local p = profiles[player]
    if result == "win" or result == "lose" then
        -- Gane o pierda, tras la campana sale del ring y aparece junto al entrenador (no queda atrapado ni abatido)
        setTimer(function()
            if isElement(player) and not fights[player] then placeBesideTrainer(player, t) end
        end, result == "win" and 3000 or 2500, 1)
    end
    if result == "win" and p then
        p[t.cfg.column] = 1
        p.style = t.cfg.id
        saveProfile(player)
        setPedFightingStyle(player, t.cfg.id)
        -- Logros (rp_achievements, modo max): estilos aprendidos
        local learned = 0
        for _, col in ipairs({ "boxing", "kungfu", "kickboxing" }) do if tonumber(p[col]) == 1 then learned = learned + 1 end end
        triggerEvent("rp:achievements:progress", player, "gym_styles", learned)
        exports.rp_notify:popup(player, "Nuevo estilo de combate", t.cfg.name .. ": has derrotado al entrenador.", "success")
    elseif result == "lose" then
        setElementHealth(player, math.max(getElementHealth(player), 30))
        gymNotify(player, "Has perdido el combate de instruccion. Vuelve cuando estes listo.", "warning")
    elseif result == "forfeit" then
        if f.down then setPedAnimation(player) end
        loseWeapons(player)
        gymNotify(player, "Te rindes y sales del ring: pierdes todas tus armas.", "error")
    elseif f.down then
        setPedAnimation(player)
    end
end

----------------------------------------------------------------
-- Bucle del combate (100 ms)
----------------------------------------------------------------
local function fightTick(f)
    local player, t = f.player, f.trainer
    if not isElement(player) or not isElement(t.ped) then return endFight(f, "abort") end
    if isPedDead(player) or getElementData(player, "rp:downed") or not gymCharacter(player) then return endFight(f, "abort") end
    if not f.live then return end   -- cinematica de presentacion

    -- Con ring: salir de el (distancia al centro) es rendirse. Sin ring: alejarse del sitio del entrenador.
    local row, ring = t.row, t.row.ring
    local px, py = getElementPosition(player)
    local cx, cy, limit = row.x, row.y, t.cfg.ring
    if ring then cx, cy, limit = ring.x, ring.y, ring.radius end
    if not sameWorld(player, t.ped) or (not f.down and getDistanceBetweenPoints2D(px, py, cx, cy) > limit) then
        return endFight(f, "forfeit")
    end
    if getElementHealth(t.ped) <= GYM.TRAINER_WIN_HP then return endFight(f, "win") end
    if getElementHealth(player) <= GYM.PLAYER_LOSE_HP then return endFight(f, "lose") end
end

function gymEndFightFor(player, result)
    if fights[player] then endFight(fights[player], result or "abort") end
end

----------------------------------------------------------------
-- Interaccion
----------------------------------------------------------------
addEventHandler("rp:gym:trainer", resourceRoot, function(trainerId)
    local player = client
    trainerId = tonumber(trainerId)
    local t = trainerId and trainers[trainerId]
    local p = profiles[player]
    if not t or not p or p.loading or not gymCharacter(player) then return end
    if fights[player] or gymInFight[player] or getElementData(player, "rp:downed") or isPedDead(player) or isPedInVehicle(player) then return end

    local px, py, pz = getElementPosition(player)
    if not sameWorld(player, t.ped) or getDistanceBetweenPoints3D(px, py, pz, t.row.x, t.row.y, t.row.z) > GYM.USE_RANGE then
        return gymNotify(player, "Estas demasiado lejos del entrenador.", "warning")
    end
    if p[t.cfg.column] == 1 then
        return gymNotify(player, "Ya aprendiste " .. t.cfg.name .. ": el entrenador no tiene nada mas que ensenarte.", "info")
    end
    local stats = exports.rp_characters:getBodyStats(player)
    if not stats or stats.muscle < GYM.MIN_MUSCLE then
        return gymNotify(player, ("Necesitas al menos %d %% de musculo para entrenar con el. Tienes %.1f %%."):format(
            GYM.MIN_MUSCLE / 10, stats and stats.muscle / 10 or 0), "warning")
    end
    if t.fight then return gymNotify(player, "El entrenador esta ocupado con otra persona.", "warning") end
    if getElementHealth(player) <= GYM.PLAYER_LOSE_HP + 10 then
        return gymNotify(player, "Estas demasiado herido para pelear.", "warning")
    end
    -- Suspender rp_wanted pone las estrellas a 0: con estrellas no se pelea (si no, seria una forma de borrarlas)
    if (exports.rp_wanted:getWantedLevel(player) or 0) > 0 then
        return gymNotify(player, "No puedes pelear con el entrenador mientras te busca la policia.", "warning")
    end

    local now = getTickCount()
    local wait = pending[player]
    if not wait or wait.id ~= trainerId or now - wait.tick > GYM.CONFIRM_MS then
        pending[player] = { id = trainerId, tick = now }
        return gymNotify(player, "Pulsa E otra vez para empezar el combate. Si te rindes (sales del ring) pierdes todas tus armas.", "info")
    end
    pending[player] = nil

    local f = { player = player, trainer = t }
    fights[player], gymInFight[player], t.fight = f, true, f
    setElementData(player, "rp:gymFight", true)
    -- Pegar al entrenador no es delito (no pisa una suspension ajena, p. ej. de una mision)
    if not exports.rp_wanted:isWantedSuspended(player) then
        exports.rp_wanted:setWantedSuspended(player, true)
        f.suspendedWanted = true
    end
    setPedAnimation(t.ped)   -- por si sigue tendido del K.O. anterior
    setElementHealth(t.ped, 100)
    setPedFightingStyle(t.ped, t.cfg.id)
    gymNear(player, false)

    local ring, intro = t.row.ring, 0
    if ring then   -- cada uno a su esquina, con publico y arbitro; el combate empieza tras la presentacion
        setElementPosition(player, ring.player.x, ring.player.y, ring.player.z)
        setElementRotation(player, 0, 0, ring.player.rot)
        setElementPosition(t.ped, ring.trainer.x, ring.trainer.y, ring.trainer.z)
        setElementRotation(t.ped, 0, 0, ring.trainer.rot)
        setCameraTarget(player, player)
        spawnCrowd(t)
        intro = GYM_FIGHT.INTRO_MS
    end
    setElementSyncer(t.ped, player)   -- la IA corre en su cliente
    triggerClientEvent(player, "rp:gym:fight", resourceRoot, t.ped, true, {
        crowd = t.crowd, intro = intro, style = t.cfg.name, label = t.cfg.label, ring = ring,
    })
    dbg("%s empieza combate con %s (ring %s, presentacion %d ms)", getPlayerName(player), t.cfg.label, tostring(ring ~= nil), intro)
    local function goLive()
        if fights[player] ~= f then return end
        f.live = true
        dbg("combate de %s en vivo", getPlayerName(player))
        if isElement(t.ped) then
            setPedAnimation(t.ped)
            setElementFrozen(t.ped, false)
            setElementSyncer(t.ped, player)
        end
    end
    if intro > 0 then f.liveTimer = setTimer(goLive, intro, 1) else goLive() end
    -- MTA copia las tablas pasadas a un temporizador: se pasa el jugador y se busca el combate real
    f.timer = setTimer(function(pl) if fights[pl] then fightTick(fights[pl]) end end, 100, 0, player)
end)

-- Caida y levantarse (lo decide el cliente: solo cambia la animacion; no da ventaja)
addEventHandler("rp:gym:down", resourceRoot, function(down)
    local f = fights[client]
    if not f or not f.live or type(down) ~= "boolean" or f.down == down then return end
    f.down = down
    dbg("%s %s", getPlayerName(client), down and "cae al suelo" or "se levanta")
    if down then
        setPedAnimation(client, "PED", "KO_skid_back", -1, false, true, false, true)
    else
        setPedAnimation(client, "PED", "getup_front", -1, false, true, false, false)
        setTimer(function(p) if isElement(p) and fights[p] and not fights[p].down then setPedAnimation(p) end end, 1300, 1, client)
    end
end)

-- El jugador pierde por cuenta o por un golpe que lo mataria (solo puede perder: no hay nada que validar)
addEventHandler("rp:gym:lost", resourceRoot, function()
    local f = fights[client]
    if f and f.live then endFight(f, "lose") end
end)

----------------------------------------------------------------
-- Mantenimiento
----------------------------------------------------------------
-- Fuera de un combate el entrenador es indestructible: recupera la vida y reaparece si muere
setTimer(function()
    for _, t in pairs(trainers) do
        if not t.fight then
            if not isElement(t.ped) or isPedDead(t.ped) then
                if isElement(t.ped) then destroyElement(t.ped) end
                createTrainerPed(t)
            elseif getElementHealth(t.ped) < 100 then
                setElementHealth(t.ped, 100)
            end
        end
    end
end, 1000, 0)

function gymDestroyTrainer(id)
    local t = trainers[id]
    if not t then return false end
    if t.fight then endFight(t.fight, "abort") end
    destroyCrowd(t)
    for player, near in pairs(nearTarget) do
        if near[1] == "trainer" and near[2] == id then gymNear(player, false) end
    end
    if isElement(t.ped) then destroyElement(t.ped) end
    if isElement(t.col) then destroyElement(t.col) end
    trainers[id] = nil
    return true
end

for _, event in ipairs({ "onPlayerQuit", "onPlayerWasted", "rp:onCharacterLogout" }) do
    addEventHandler(event, root, function() gymEndFightFor(source, "abort"); pending[source] = nil end)
end

-- El publico y el arbitro no reciben dano
addEventHandler("onPedWasted", resourceRoot, function()
    if getElementData(source, "rp:gymCrowd") then destroyElement(source) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    stopping = true
    for player, f in pairs(fights) do endFight(f, "abort") end
end)
