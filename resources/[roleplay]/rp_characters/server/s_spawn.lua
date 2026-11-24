--[[
    rp_characters / s_spawn.lua
    Spawn del personaje, guardado periodico y respawn al morir.
]]

local function db()
    return exports.rp_database:getConnection()
end

-- Cuerpo, complexion, ropa y cabeza. La cabeza la dibuja rp_heads en cada cliente a partir
-- de "rp:head"; la altura y el tono de piel, client/c_body.lua a partir de "rp:body".
function applyPlayerLook(player, row)
    -- Grasa y musculo entrenados (stat_*, escala 0-1000) mandan sobre los del creador (body_*, 0-100)
    local look = setmetatable({}, { __index = row })
    if row.stat_fat then look.body_fat = tonumber(row.stat_fat) / 10 end
    if row.stat_muscle then look.body_muscle = tonumber(row.stat_muscle) / 10 end
    local head = applyCharacterLook(player, look)
    if row.stat_stamina then setPedStat(player, BODY.STAT_STAMINA, tonumber(row.stat_stamina)) end
    setElementData(player, "rp:head", head or false)
    setElementData(player, "rp:body", {
        height = tonumber(row.height) or BODY.HEIGHT_BASE,
        tone = head and tonumber(row.skin_tone) or 0,
    })
end

function spawnCharacter(player, row)
    local d = SPAWN.DEFAULT
    local x, y, z = tonumber(row.pos_x), tonumber(row.pos_y), tonumber(row.pos_z)
    local rot, interior, dimension = tonumber(row.rotation) or d.rot, tonumber(row.interior) or 0, tonumber(row.dimension) or 0

    if not (x and y and z) then
        x, y, z, rot, interior, dimension = d.x, d.y, d.z, d.rot, d.interior, d.dimension
    end

    spawnPlayer(player, x, y, z, rot, tonumber(row.skin) or 26, interior, dimension)
    applyPlayerLook(player, row)
    setElementHealth(player, math.max(1, tonumber(row.health) or 100))
    setPedArmor(player, tonumber(row.armor) or 0)
    setPlayerMoney(player, tonumber(row.money) or 0, true)
    setCameraTarget(player, player)
    fadeCamera(player, true, 1.5)
end

-- Guarda el personaje activo. Si esta muerto (o murio desangrado en rp_injury) guarda el
-- hospital: la proxima vez aparece alli con la vida completa. Un personaje abatido se
-- guarda donde esta, para que al volver siga abatido en el mismo sitio.
function saveCharacter(player, toHospital)
    local row = active[player]
    if not row or not isElement(player) then return false end

    if toHospital or isPedDead(player) or getElementHealth(player) <= 0 or getElementData(player, "rp:downed") == "dying" then
        local h = SPAWN.HOSPITAL
        return dbExec(db(),
            "UPDATE characters SET money = ?, health = 100, armor = 0, pos_x = ?, pos_y = ?, pos_z = ?, rotation = ?, interior = 0, dimension = 0 WHERE id = ?",
            getPlayerMoney(player), h.x, h.y, h.z, h.rot, row.id)
    end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    -- La skin sale de la fila (no del modelo actual) para no guardar una prenda en prueba
    return dbExec(db(),
        "UPDATE characters SET skin = ?, money = ?, health = ?, armor = ?, pos_x = ?, pos_y = ?, pos_z = ?, rotation = ?, interior = ?, dimension = ? WHERE id = ?",
        tonumber(row.skin) or getElementModel(player), getPlayerMoney(player), getElementHealth(player), getPedArmor(player),
        x, y, z, rot, getElementInterior(player), getElementDimension(player), row.id)
end

-- Respawn en el hospital con la vida completa (lo usa rp_injury tras desangrarse)
function respawnAtHospital(player)
    if not isElement(player) or not active[player] then return false end
    local h = SPAWN.HOSPITAL
    spawnPlayer(player, h.x, h.y, h.z, h.rot, getElementModel(player), 0, 0)
    applyPlayerLook(player, active[player])
    setElementHealth(player, 100)
    setCameraTarget(player, player)
    fadeCamera(player, true)
    return true
end

local function injuryRunning()
    local res = getResourceFromName("rp_injury")
    return res and getResourceState(res) == "running"
end

-- Sin rp_injury: respawn directo en el hospital. Con rp_injury, el jugador queda abatido
-- y es ese recurso el que lo manda al hospital.
addEventHandler("onPlayerWasted", root, function()
    local player = source
    if not active[player] or injuryRunning() then return end
    setTimer(function()
        if not isElement(player) or not active[player] then return end
        respawnAtHospital(player)
    end, SPAWN.RESPAWN_DELAY, 1)
end)

setTimer(function()
    for player in pairs(active) do
        saveCharacter(player)
    end
end, SPAWN.AUTOSAVE_INTERVAL, 0)

----------------------------------------------------------------
-- Apariencia (usado por rp_clothing)
----------------------------------------------------------------
local LOOK_COLUMNS = { skin = true, clothes_torso = true, clothes_legs = true, clothes_shoes = true }

-- Apariencia guardada del personaje activo
function getCharacterLook(player)
    local row = active[player]
    if not row then return false end
    return {
        gender = tonumber(row.gender), skin = tonumber(row.skin), race = tonumber(row.race), head = tonumber(row.head),
        height = tonumber(row.height), body_fat = tonumber(row.body_fat), body_muscle = tonumber(row.body_muscle),
        skin_tone = tonumber(row.skin_tone),
        clothes_torso = tonumber(row.clothes_torso), clothes_legs = tonumber(row.clothes_legs), clothes_shoes = tonumber(row.clothes_shoes),
    }
end

-- Guarda cambios de apariencia (solo columnas permitidas) y los aplica
function setCharacterLook(player, changes)
    local row = active[player]
    if not row or type(changes) ~= "table" then return false end
    local sets, params = {}, {}
    for column, value in pairs(changes) do
        if LOOK_COLUMNS[column] and type(value) == "number" and value == math.floor(value) and value >= 0 then
            row[column] = value
            sets[#sets + 1] = column .. " = ?"
            params[#params + 1] = value
        end
    end
    if #sets == 0 then return false end
    params[#params + 1] = row.id
    dbExec(db(), "UPDATE characters SET " .. table.concat(sets, ", ") .. " WHERE id = ?", unpack(params))
    applyPlayerLook(player, row)
    return true
end

----------------------------------------------------------------
-- Cuerpo entrenado (usado por rp_gym): unico lugar que escribe grasa, musculo y resistencia
----------------------------------------------------------------
local function clampStat(v)
    return math.max(0, math.min(BODY.STAT_MAX, tonumber(v) or 0))
end

-- Stats actuales del personaje activo, escala 0-1000: { fat, muscle, stamina }
function getBodyStats(player)
    local row = active[player]
    if not row then return false end
    return {
        fat = tonumber(row.stat_fat) or (tonumber(row.body_fat) or 0) * 10,
        muscle = tonumber(row.stat_muscle) or (tonumber(row.body_muscle) or 0) * 10,
        stamina = tonumber(row.stat_stamina) or BODY.STAMINA_DEFAULT,
    }
end

-- Guarda y aplica stats (escala 0-1000; nil = sin cambios). rebuild = true vuelve a vestir el cuerpo
-- de CJ para que se vea el cambio (es caro: hacerlo al terminar el entrenamiento, no en cada paso).
function setBodyStats(player, fat, muscle, stamina, rebuild)
    local row = active[player]
    if not row then return false end
    local current = getBodyStats(player)
    fat = clampStat(fat == nil and current.fat or fat)
    muscle = clampStat(muscle == nil and current.muscle or muscle)
    stamina = clampStat(stamina == nil and current.stamina or stamina)

    row.stat_fat, row.stat_muscle, row.stat_stamina = fat, muscle, stamina
    row.body_fat = math.floor(fat / 10 + 0.5)       -- se mantiene el valor 0-100 que usa el creador y el peso
    row.body_muscle = math.floor(muscle / 10 + 0.5)
    dbExec(db(), "UPDATE characters SET stat_fat = ?, stat_muscle = ?, stat_stamina = ?, body_fat = ?, body_muscle = ? WHERE id = ?",
        fat, muscle, stamina, row.body_fat, row.body_muscle, row.id)

    setPedStat(player, BODY.STAT_STAMINA, stamina)
    setPedStat(player, BODY.STAT_FAT, fat)         -- solo tienen efecto en el cuerpo de CJ
    setPedStat(player, BODY.STAT_MUSCLE, muscle)
    if rebuild then applyPlayerLook(player, row) end
    return true
end

-- Vuelve a poner la apariencia guardada (p. ej. al salir del probador sin comprar)
function restoreCharacterLook(player)
    if not active[player] then return false end
    applyPlayerLook(player, active[player])
    return true
end

function getAllowedSkins(gender)
    return SKINS[tonumber(gender)] or {}
end
