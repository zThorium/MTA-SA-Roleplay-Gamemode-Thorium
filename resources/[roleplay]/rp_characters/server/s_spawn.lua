--[[
    rp_characters / s_spawn.lua
    Spawn del personaje, guardado periodico y respawn al morir.
]]

local function db()
    return exports.rp_database:getConnection()
end

-- Cuerpo, ropa y cabeza. La cabeza la dibuja rp_heads en cada cliente a partir de "rp:head".
function applyPlayerLook(player, row)
    local head = applyCharacterLook(player, row)
    setElementData(player, "rp:head", head or false)
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

-- Guarda el personaje activo. Si esta muerto o abatido (rp_injury) guarda el hospital:
-- la proxima vez aparece alli con la vida completa.
function saveCharacter(player, toHospital)
    local row = active[player]
    if not row or not isElement(player) then return false end

    if toHospital or isPedDead(player) or getElementHealth(player) <= 0 or getElementData(player, "rp:downed") then
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

-- Vuelve a poner la apariencia guardada (p. ej. al salir del probador sin comprar)
function restoreCharacterLook(player)
    if not active[player] then return false end
    applyPlayerLook(player, active[player])
    return true
end

function getAllowedSkins(gender)
    return SKINS[tonumber(gender)] or {}
end
