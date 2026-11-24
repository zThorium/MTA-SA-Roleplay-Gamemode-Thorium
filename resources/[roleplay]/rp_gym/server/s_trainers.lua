--[[
    rp_gym / s_trainers.lua
    Entrenadores de boxeo (Ganton), kung fu (Cobra) y kickboxing (Below the Belt).

    Flujo: E junto al entrenador con 35 % de musculo o mas -> aviso -> E otra vez (en 8 s) para aceptar.
    Combate: el entrenador persigue y golpea al jugador (IA propia sobre setPedControlState).
      - Victoria: la vida del entrenador baja a TRAINER_WIN_HP. Se aprende el estilo (reemplaza al anterior).
      - Derrota: la vida del jugador baja a PLAYER_LOSE_HP. No pasa nada mas.
      - Rendirse: salir del ring (en Cobra, de la esterilla) hace perder las armas, como en el original.
    Cada estilo se aprende una sola vez: no hay forma de recuperar uno reemplazado, como en el original.

    Evento cliente -> servidor (con `client`):
        rp:gym:trainer (trainerId)
]]

addEvent("rp:gym:trainer", true)

local trainers = {}   -- [id] = { row, cfg, ped, col, fight }
local fights = {}     -- [player] = pelea
local pending = {}    -- [player] = { id, tick }

local function sameWorld(a, b)
    return getElementDimension(a) == getElementDimension(b) and getElementInterior(a) == getElementInterior(b)
end

local function createTrainerPed(t)
    local row, cfg = t.row, t.cfg
    local ped = createPed(cfg.skin, row.x, row.y, row.z, row.rotation)
    setElementInterior(ped, row.interior)
    setElementDimension(ped, row.dimension)
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
    setElementInterior(t.col, row.interior)
    setElementDimension(t.col, row.dimension)
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
    setPedControlState(t.ped, "forwards", false)
    setPedControlState(t.ped, "fire", false)
    setElementFrozen(t.ped, true)
    setElementPosition(t.ped, t.row.x, t.row.y, t.row.z)
    setPedRotation(t.ped, t.row.rotation)
    setElementHealth(t.ped, 100)
end

local function endFight(f, result)
    if f.over then return end
    f.over = true
    if isTimer(f.timer) then killTimer(f.timer) end
    local player, t = f.player, f.trainer
    fights[player] = nil
    gymInFight[player] = nil
    t.fight = nil
    resetTrainer(t)
    if not isElement(player) then return end

    local p = profiles[player]
    if result == "win" and p then
        p[t.cfg.column] = 1
        p.style = t.cfg.id
        saveProfile(player)
        setPedFightingStyle(player, t.cfg.id)
        exports.rp_notify:popup(player, "Nuevo estilo de combate", t.cfg.name .. ": has derrotado al entrenador.", "success")
    elseif result == "lose" then
        setElementHealth(player, math.max(getElementHealth(player), 30))
        gymNotify(player, "Has perdido el combate de instruccion. Vuelve cuando estes listo.", "warning")
    elseif result == "forfeit" then
        loseWeapons(player)
        gymNotify(player, "Te rindes y sales del ring: pierdes todas tus armas.", "error")
    end
end

----------------------------------------------------------------
-- Bucle del combate (100 ms)
----------------------------------------------------------------
local function fightTick(f)
    local player, t = f.player, f.trainer
    if not isElement(player) or not isElement(t.ped) then return endFight(f, "abort") end
    if isPedDead(player) or getElementData(player, "rp:downed") or not gymCharacter(player) then return endFight(f, "abort") end

    local row = t.row
    local px, py, pz = getElementPosition(player)
    if not sameWorld(player, t.ped) or getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > t.cfg.ring then
        return endFight(f, "forfeit")
    end
    if getElementHealth(t.ped) <= GYM.TRAINER_WIN_HP then return endFight(f, "win") end
    if getElementHealth(player) <= GYM.PLAYER_LOSE_HP then return endFight(f, "lose") end

    -- IA del entrenador: se gira hacia el jugador, se acerca y pega a intervalos
    local tx, ty = getElementPosition(t.ped)
    local dx, dy = px - tx, py - ty
    local dist = math.sqrt(dx * dx + dy * dy)
    setPedRotation(t.ped, math.deg(math.atan2(-dx, dy)))
    setPedControlState(t.ped, "forwards", dist > 1.4)
    local now = getTickCount()
    if dist <= 1.7 and now >= f.nextHit then
        f.nextHit = now + math.random(GYM.TRAINER_HIT_MS[1], GYM.TRAINER_HIT_MS[2])
        setPedControlState(t.ped, "fire", true)
        setTimer(function()
            if isElement(t.ped) then setPedControlState(t.ped, "fire", false) end
        end, 120, 1)
    end
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

    local now = getTickCount()
    local wait = pending[player]
    if not wait or wait.id ~= trainerId or now - wait.tick > GYM.CONFIRM_MS then
        pending[player] = { id = trainerId, tick = now }
        return gymNotify(player, "Pulsa E otra vez para empezar el combate. Si te rindes (sales del ring) pierdes todas tus armas.", "info")
    end
    pending[player] = nil

    local f = { player = player, trainer = t, nextHit = now + 1500 }
    fights[player], gymInFight[player], t.fight = f, true, f
    setElementHealth(t.ped, 100)
    setPedFightingStyle(t.ped, t.cfg.id)
    setElementFrozen(t.ped, false)
    gymNear(player, false)
    gymNotify(player, "Combate de instruccion: derrota al entrenador.", "info")
    f.timer = setTimer(fightTick, 100, 0, f)
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

addEventHandler("onResourceStop", resourceRoot, function()
    for player, f in pairs(fights) do endFight(f, "abort") end
end)
