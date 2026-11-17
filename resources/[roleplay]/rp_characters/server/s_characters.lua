--[[
    rp_characters / s_characters.lua
    Lista, creacion, eliminacion y seleccion de personajes de una cuenta.
    Todo lo que envia el cliente se valida aqui.
]]

active = {}             -- [player] = fila del personaje en juego (usado por s_spawn.lua)
local clientReady = {}  -- [player] = true cuando el script cliente ya cargo
local pending = {}      -- [player] = true durante una operacion de base de datos

addEvent("rp:onAccountLogin", false)
addEvent("rp:onAccountLogout", false)
addEvent("rp:chars:clientReady", true)
addEvent("rp:chars:create", true)
addEvent("rp:chars:play", true)
addEvent("rp:chars:delete", true)
addEvent("rp:onCharacterSpawn", false)   -- para otros recursos: source = jugador, (characterId, name)
addEvent("rp:onCharacterLogout", false)  -- source = jugador, (characterId)

local function db()
    return exports.rp_database:getConnection()
end

local function accountOf(player)
    return exports.rp_login:getPlayerAccountId(player)
end

local function reply(player, ok, message)
    if isElement(player) then
        triggerClientEvent(player, "rp:chars:result", resourceRoot, ok, message)
    end
end

----------------------------------------------------------------
-- Lista de personajes -> cliente
----------------------------------------------------------------
function sendCharacterList(player)
    local accountId = accountOf(player)
    if not accountId or not clientReady[player] or active[player] then return end

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        triggerClientEvent(player, "rp:chars:show", resourceRoot, rows, CHARS.MAX_SLOTS)
    end, db(), [[
        SELECT id, name, gender, age, skin, race, head, clothes_torso, clothes_legs, clothes_shoes, money, origin,
               DATE_FORMAT(last_played, '%d/%m/%Y') AS last_played
        FROM characters WHERE account_id = ? ORDER BY id LIMIT ?
    ]], accountId, CHARS.MAX_SLOTS)
end

addEventHandler("rp:onAccountLogin", root, function()
    sendCharacterList(source)
end)

addEventHandler("rp:chars:clientReady", resourceRoot, function()
    clientReady[client] = true
    sendCharacterList(client)   -- por si inicio sesion antes de que cargara este script
end)

----------------------------------------------------------------
-- Validacion de los datos del formulario
----------------------------------------------------------------
local function inRange(n, a, b)
    return type(n) == "number" and n == math.floor(n) and n >= a and n <= b
end

local function validNamePart(s)
    return type(s) == "string" and #s >= CHARS.NAME_PART_MIN and #s <= CHARS.NAME_PART_MAX
        and s:match("^%u%l+$") ~= nil
end

local function validText(s, minLen, maxLen, allowNewlines)
    if type(s) ~= "string" or #s < minLen or #s > maxLen then return false end
    local check = allowNewlines and s:gsub("[\r\n\t]", "") or s
    return not check:find("%c")
end

-- Devuelve (datos limpios) o (nil, mensaje de error)
local function validateCharacter(d)
    if type(d) ~= "table" then return nil, "Datos no validos." end

    local first, last = d.firstName, d.lastName
    if not validNamePart(first) or not validNamePart(last) then
        return nil, ("Nombre y apellido: %d-%d letras, empezando por mayuscula (ej. Juan Perez)."):format(CHARS.NAME_PART_MIN, CHARS.NAME_PART_MAX)
    end

    local gender = d.gender
    if gender ~= 0 and gender ~= 1 then return nil, "Selecciona un genero." end
    if not inRange(d.age, CHARS.AGE_MIN, CHARS.AGE_MAX) then
        return nil, ("La edad debe estar entre %d y %d anos."):format(CHARS.AGE_MIN, CHARS.AGE_MAX)
    end
    if not inRange(d.weight, CHARS.WEIGHT_MIN, CHARS.WEIGHT_MAX) then
        return nil, ("El peso debe estar entre %d y %d kg."):format(CHARS.WEIGHT_MIN, CHARS.WEIGHT_MAX)
    end
    if not inRange(d.height, CHARS.HEIGHT_MIN, CHARS.HEIGHT_MAX) then
        return nil, ("La altura debe estar entre %d y %d cm."):format(CHARS.HEIGHT_MIN, CHARS.HEIGHT_MAX)
    end
    if not validText(d.origin, CHARS.ORIGIN_MIN, CHARS.ORIGIN_MAX, false) then
        return nil, "Indica un lugar de origen valido."
    end
    if not validText(d.story, CHARS.STORY_MIN, CHARS.STORY_MAX, true) then
        return nil, ("La historia debe tener entre %d y %d caracteres."):format(CHARS.STORY_MIN, CHARS.STORY_MAX)
    end
    local c = {
        name = first .. "_" .. last, gender = gender, age = d.age, weight = d.weight,
        height = d.height, origin = d.origin, story = d.story,
    }

    if gender == 0 then
        -- Hombre: cuerpo de CJ + cabeza de rp_heads + ropa
        if not inRange(d.race, 1, 4) then return nil, "Selecciona una raza." end
        if not exports.rp_heads:isValidHead(d.head, d.race) then return nil, "Cabeza no valida para esa raza." end
        c.skin, c.race, c.head = CUSTOM_SKIN, d.race, d.head
        for _, slot in ipairs(CLOTHES_SLOTS) do
            local index = d[slot.key]
            if not isValidClothes(slot.type, index) then return nil, "Prenda de ropa no valida." end
            c[slot.column] = index
        end
    else
        if not isSkinAllowed(d.skin, gender) then return nil, "Skin no permitida." end
        c.skin = d.skin
    end

    return c
end

----------------------------------------------------------------
-- Crear
----------------------------------------------------------------
addEventHandler("rp:chars:create", resourceRoot, function(data)
    local player = client
    local accountId = accountOf(player)
    if not accountId or active[player] or pending[player] then return end

    local c, err = validateCharacter(data)
    if not c then return reply(player, false, err) end

    pending[player] = true
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        local count = rows and rows[1] and tonumber(rows[1].total) or CHARS.MAX_SLOTS
        if count >= CHARS.MAX_SLOTS then
            pending[player] = nil
            return reply(player, false, "No te quedan espacios libres para personajes.")
        end

        -- Las columnas de apariencia solo aplican a hombres; para mujeres quedan en NULL
        local sql, params
        if c.head then
            sql = [[
                INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin,
                                        race, head, clothes_torso, clothes_legs, clothes_shoes, money)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]]
            params = { accountId, c.name, c.gender, c.age, c.weight, c.height, c.origin, c.story, c.skin,
                c.race, c.head, c.clothes_torso, c.clothes_legs, c.clothes_shoes, CHARS.START_MONEY }
        else
            sql = [[
                INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin, money)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]]
            params = { accountId, c.name, c.gender, c.age, c.weight, c.height, c.origin, c.story, c.skin, CHARS.START_MONEY }
        end

        dbQuery(function(insertQh)
            local result, code = dbPoll(insertQh, 0)
            if not isElement(player) then return end
            pending[player] = nil

            if not result then
                if code == 1062 then
                    return reply(player, false, "Ya existe un personaje con ese nombre.")
                end
                outputDebugString("[rp_characters] Error al crear personaje: " .. tostring(code), 1)
                return reply(player, false, "Error al crear el personaje. Avisa a un administrador.")
            end

            outputServerLog(("[rp_characters] Cuenta #%d creo el personaje %s"):format(accountId, c.name))
            reply(player, true, "Personaje " .. c.name:gsub("_", " ") .. " creado.")
            sendCharacterList(player)
        end, db(), sql, unpack(params))
    end, db(), "SELECT COUNT(*) AS total FROM characters WHERE account_id = ?", accountId)
end)

----------------------------------------------------------------
-- Eliminar (el cliente pide confirmar escribiendo el nombre)
----------------------------------------------------------------
addEventHandler("rp:chars:delete", resourceRoot, function(characterId)
    local player = client
    local accountId = accountOf(player)
    if not accountId or active[player] or pending[player] or type(characterId) ~= "number" then return end

    pending[player] = true
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(player) then return end
        pending[player] = nil
        if affected and affected > 0 then
            outputServerLog(("[rp_characters] Cuenta #%d elimino el personaje #%d"):format(accountId, characterId))
            reply(player, true, "Personaje eliminado.")
        else
            reply(player, false, "No se pudo eliminar el personaje.")
        end
        sendCharacterList(player)
    end, db(), "DELETE FROM characters WHERE id = ? AND account_id = ?", characterId, accountId)
end)

----------------------------------------------------------------
-- Jugar
----------------------------------------------------------------
addEventHandler("rp:chars:play", resourceRoot, function(characterId)
    local player = client
    local accountId = accountOf(player)
    if not accountId or active[player] or pending[player] or type(characterId) ~= "number" then return end

    pending[player] = true
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(player) then return end
        pending[player] = nil

        local row = rows and rows[1]
        if not row then return reply(player, false, "Personaje no encontrado.") end

        active[player] = row
        dbExec(db(), "UPDATE characters SET last_played = NOW() WHERE id = ?", row.id)
        setElementData(player, "rp:characterId", row.id)   -- publico: lo usan nametags y scoreboard
        setPlayerName(player, row.name)

        triggerClientEvent(player, "rp:chars:spawned", resourceRoot)
        spawnCharacter(player, row)
        exports.rp_notify:popup(player, "Bienvenido a Los Santos", (row.name:gsub("_", " ")) .. ", disfruta del rol.", "success")
        exports.rp_notify:notify(player, "Pulsa I para abrir tu inventario y Tab para ver los jugadores.", "info", 8000)
        outputServerLog(("[rp_characters] %s entro al juego (personaje #%d)"):format(row.name, row.id))
        triggerEvent("rp:onCharacterSpawn", player, row.id, row.name)
    end, db(), "SELECT * FROM characters WHERE id = ? AND account_id = ? LIMIT 1", characterId, accountId)
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
local function closeCharacter(player)
    if active[player] then
        -- rp_injury: abatido -> guarda el tiempo pendiente (sigue abatido al volver);
        -- ya desangrado -> se cobra el hospital y aparece alli
        local downed = isElement(player) and getElementData(player, "rp:downed")
        if downed then triggerEvent("rp:onDownedLogout", player) end
        saveCharacter(player, downed == "dying")
        triggerEvent("rp:onCharacterLogout", player, active[player].id)
        active[player] = nil
        if isElement(player) then
            setElementData(player, "rp:head", false)
            setElementData(player, "rp:characterId", false)
        end
    end
end

addEventHandler("onPlayerQuit", root, function()
    closeCharacter(source)
    clientReady[source], pending[source] = nil, nil
end)

addEventHandler("rp:onAccountLogout", root, function()
    closeCharacter(source)
end)

-- Sin personaje en juego no se puede usar el chat
addEventHandler("onPlayerChat", root, function()
    if not active[source] then cancelEvent() end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(active) do
        saveCharacter(player)
    end
end)

-- Exports
function getPlayerCharacterId(player)
    return active[player] and active[player].id or false
end

function getPlayerCharacterName(player)
    return active[player] and active[player].name or false
end
