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

-- Guarda el personaje activo. Si esta muerto no guarda la posicion (volvera al spawn).
function saveCharacter(player)
    local row = active[player]
    if not row or not isElement(player) then return false end

    if isPedDead(player) or getElementHealth(player) <= 0 then
        return dbExec(db(), "UPDATE characters SET money = ?, health = 100, armor = 0, pos_x = NULL, pos_y = NULL, pos_z = NULL WHERE id = ?",
            getPlayerMoney(player), row.id)
    end

    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    return dbExec(db(),
        "UPDATE characters SET skin = ?, money = ?, health = ?, armor = ?, pos_x = ?, pos_y = ?, pos_z = ?, rotation = ?, interior = ?, dimension = ? WHERE id = ?",
        getElementModel(player), getPlayerMoney(player), getElementHealth(player), getPedArmor(player),
        x, y, z, rot, getElementInterior(player), getElementDimension(player), row.id)
end

addEventHandler("onPlayerWasted", root, function()
    local player = source
    if not active[player] then return end
    setTimer(function()
        if not isElement(player) or not active[player] then return end
        local h = SPAWN.HOSPITAL
        spawnPlayer(player, h.x, h.y, h.z, h.rot, getElementModel(player), 0, 0)
        applyPlayerLook(player, active[player])
        setCameraTarget(player, player)
        fadeCamera(player, true)
    end, SPAWN.RESPAWN_DELAY, 1)
end)

setTimer(function()
    for player in pairs(active) do
        saveCharacter(player)
    end
end, SPAWN.AUTOSAVE_INTERVAL, 0)
