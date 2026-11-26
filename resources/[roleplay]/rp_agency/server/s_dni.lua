--[[
    rp_agency / s_dni.lua

    Documento Nacional de Identidad. Mismo patron que la licencia de conducir
    (rp_driving): el registro vive en la tabla identity_cards (uno por
    personaje) y el item "id_card" del inventario es solo el "papel". Si lo
    pierdes, la agencia te imprime un duplicado (AGENCY.DNI_DUPLICATE_PRICE).

    Numero: 8 cifras derivadas del id del personaje (unicas) + letra de control
    al estilo espanol (modulo 23).

    Exports (servidor):
        hasPlayerDNI(player)  -> bool (tiene DNI registrado, lo lleve o no)
        getPlayerDNI(player)  -> tabla con los datos del documento | false

    Comandos:
        /mostrardni [id o nombre]   ensena tu DNI a alguien a menos de 3 m (sin argumento, lo miras tu)
        /consultardni <id o nombre> (policia) consulta el registro de un ciudadano
]]

local cache = {}   -- [player] = { characterId, row = fila de identity_cards + datos del personaje | false }

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:onItemUse", false)
addEvent("rp:agency:dniSubmit", true)

local LETTERS = "TRWAGMYFPDXBNJZSQVHLCKE"

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

function dniNumberFor(characterId)
    -- 7919 es primo con 10^8: ids distintos dan numeros distintos
    local digits = (characterId * 7919 + 1234567) % 100000000
    local letter = LETTERS:sub(digits % 23 + 1, digits % 23 + 1)
    return ("%08d%s"):format(digits, letter)
end

local SELECT_CARD = [[
    SELECT ic.number, ic.signature, ic.copies,
           DATE_FORMAT(ic.issued_at, '%d/%m/%Y') AS issued, DATE_FORMAT(ic.issued_at, '%Y') AS issued_year,
           c.id AS character_id, c.name, c.gender, c.age, c.origin, c.height
    FROM identity_cards ic JOIN characters c ON c.id = ic.character_id
    WHERE ic.character_id = ?
]]

local function buildCard(row)
    if not row then return false end
    local id = tonumber(row.character_id) or 0
    local year = (tonumber(row.issued_year) or 2026) - (tonumber(row.age) or 0)
    local issued = tostring(row.issued or "")
    local d, m, y = issued:match("(%d+)/(%d+)/(%d+)")
    return {
        number = row.number, name = (tostring(row.name):gsub("_", " ")),
        gender = tonumber(row.gender) == 1 and "F" or "M",
        birth = ("%02d/%02d/%d"):format(id * 7 % 28 + 1, id % 12 + 1, year),
        origin = row.origin or "", height = tonumber(row.height) or 0,
        issued = issued, expires = (d and ("%s/%s/%d"):format(d, m, tonumber(y) + 10)) or "",
        signature = row.signature or "", copies = tonumber(row.copies) or 1,
    }
end

local function load(player, characterId)
    cache[player] = { characterId = characterId, row = nil, loading = true }
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local c = cache[player]
        if not isElement(player) or not c or c.characterId ~= characterId then return end
        c.row = rows and rows[1] or false
        c.loading = nil
    end, db(), SELECT_CARD, characterId)
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) load(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() cache[source] = nil end)
addEventHandler("onPlayerQuit", root, function() cache[source] = nil end)

local function loadAll()
    for _, p in ipairs(getElementsByType("player")) do
        local id = characterOf(p)
        if id then load(p, id) end
    end
end
addEvent("rp:onDatabaseReady", false)
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadAll() else addEventHandler("rp:onDatabaseReady", root, loadAll) end
end)

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function hasPlayerDNI(player)
    local c = cache[player]
    return c ~= nil and c.row ~= nil and c.row ~= false and c.characterId == characterOf(player)
end

function getPlayerDNI(player)
    if not hasPlayerDNI(player) then return false end
    return buildCard(cache[player].row)
end

-- "none" sin registro, "lost" registrado pero sin el item, "has" lo lleva encima
function getPlayerDNIStatus(player)
    if not hasPlayerDNI(player) then return "none" end
    if exports.rp_inventory:hasItem(player, "id_card", 1) then return "has" end
    return "lost"
end

----------------------------------------------------------------
-- Emision en el mostrador
----------------------------------------------------------------
local function validSignature(sig)
    -- Trazos normalizados a 0-99: "x,y;x,y|x,y;..." (ver html/app.js)
    return type(sig) == "string" and #sig >= 8 and #sig <= 4000 and sig:match("^[%d,;|]+$") ~= nil
end

addEventHandler("rp:agency:dniSubmit", resourceRoot, function(signature)
    local player = client
    local t = getServiceTicket(player)
    if not t or t.reason ~= "dni" or t.dniDone or t.dniPending then return end
    local function fail(msg)
        triggerClientEvent(player, "rp:agency:dniResult", resourceRoot, false, msg)
    end
    if getTickCount() - t.stepAt < AGENCY.DNI_MIN_SECONDS * 1000 then return fail("Aun no he terminado de tomar tus datos.") end
    if not validSignature(signature) then return fail("Necesito tu firma para emitir el documento.") end
    local characterId = characterOf(player)
    local c = cache[player]
    if not characterId or not c or c.loading then return fail("Tus datos aun se estan cargando. Intentalo de nuevo.") end

    local status = getPlayerDNIStatus(player)
    if status == "has" then return fail("Ya tienes un DNI vigente.") end
    local ok, reason = exports.rp_inventory:canCarry(player, "id_card", 1)
    if not ok then return fail(reason or "No tienes espacio en el inventario.") end

    local price = status == "lost" and AGENCY.DNI_DUPLICATE_PRICE or 0
    if price > 0 then
        if getPlayerMoney(player) < price then
            return fail(("El duplicado cuesta $%d en efectivo y no te alcanza."):format(price))
        end
        takePlayerMoney(player, price)
        exports.rp_characters:saveCharacter(player)
    end

    t.dniPending = true
    local number = dniNumberFor(characterId)
    dbQuery(function(qh)
        local result = dbPoll(qh, 0)
        if not isElement(player) then return end
        local function refund()
            if price > 0 then givePlayerMoney(player, price) exports.rp_characters:saveCharacter(player) end
        end
        if not result or characterOf(player) ~= characterId then
            t.dniPending = nil
            refund()
            return fail("El sistema esta caido. Vuelve a intentarlo en un momento.")
        end
        -- Recarga la fila con los datos del personaje y entrega el papel
        dbQuery(function(qh2)
            local rows = dbPoll(qh2, 0)
            t.dniPending = nil
            if not isElement(player) or characterOf(player) ~= characterId then return end
            local row = rows and rows[1]
            if not row then refund() return fail("No se pudo imprimir el documento.") end
            cache[player] = { characterId = characterId, row = row }
            local given, why = exports.rp_inventory:giveItem(player, "id_card", 1)
            if not given then refund() return fail(why or "No tienes espacio en el inventario.") end
            t.dniDone = true
            outputServerLog(("[rp_agency] DNI %s emitido a %s (%s)"):format(row.number, getPlayerName(player), price > 0 and "duplicado" or "nuevo"))
            triggerClientEvent(player, "rp:agency:dniResult", resourceRoot, true, buildCard(row), price)
        end, db(), SELECT_CARD, characterId)
    end, db(), [[
        INSERT INTO identity_cards (character_id, number, signature) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE signature = VALUES(signature), issued_at = CURRENT_TIMESTAMP, copies = copies + 1
    ]], characterId, number, signature)
end)

----------------------------------------------------------------
-- Ver y ensenar el documento
----------------------------------------------------------------
local function showCard(viewer, card, ownerName)
    triggerClientEvent(viewer, "rp:agency:showCard", resourceRoot, card, ownerName)
end

addEventHandler("rp:onItemUse", root, function(itemId)
    if itemId ~= "id_card" then return end
    local card = getPlayerDNI(source)
    if not card then return notify(source, "Este DNI no esta registrado a tu nombre.", "error") end
    showCard(source, card, nil)
end)

addCommandHandler("mostrardni", function(player, _, query)
    if not characterOf(player) or getElementData(player, "rp:downed") then return end
    if not exports.rp_inventory:hasItem(player, "id_card", 1) then
        return notify(player, "No llevas tu DNI encima. Puedes pedir un duplicado en la agencia de empleo.", "warning")
    end
    local card = getPlayerDNI(player)
    if not card then return notify(player, "No tienes DNI registrado.", "error") end
    if not query then return showCard(player, card, nil) end

    local target = exports.rp_ids:findPlayer(query)
    if not target or target == player then return notify(player, "Uso: /mostrardni [id o nombre]", "warning") end
    local x, y, z = getElementPosition(player)
    local tx, ty, tz = getElementPosition(target)
    if getElementDimension(player) ~= getElementDimension(target) or getElementInterior(player) ~= getElementInterior(target)
        or getDistanceBetweenPoints3D(x, y, z, tx, ty, tz) > AGENCY.SHOW_DISTANCE then
        return notify(player, "Esa persona esta demasiado lejos.", "warning")
    end
    local name = (getPlayerName(player):gsub("_", " "))
    showCard(target, card, name)
    setPedAnimation(player, "DEALER", "DEALER_DEAL", 1500, false, false, false, false)
    notify(player, ("Le muestras tu DNI a %s."):format((getPlayerName(target):gsub("_", " "))), "info")
end)

local function isPolice(player)
    local ok, yes = pcall(function() return exports.rp_factions:isPlayerInFaction(player, "policia") end)
    return ok and yes == true
end

addCommandHandler("consultardni", function(player, _, query)
    if not characterOf(player) then return end
    if not isPolice(player) then return notify(player, "Solo la policia puede consultar el registro de identidad.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    if not target then return notify(player, "Uso: /consultardni <id o nombre>", "warning") end
    local card = getPlayerDNI(target)
    local name = (getPlayerName(target):gsub("_", " "))
    if not card then return notify(player, ("%s no tiene DNI registrado."):format(name), "warning") end
    showCard(player, card, name .. " (registro)")
end)
