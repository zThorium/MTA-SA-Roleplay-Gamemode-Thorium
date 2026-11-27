--[[
    rp_driving / s_license.lua

    Licencia de conducir. Los datos viven en driving_licenses (por personaje);
    el item "driver_license" del inventario es solo el papel: se puede perder
    o reimprimir en la autoescuela. Mismo patron que el DNI de la agencia.

    Se obtiene al aprobar todas las pruebas. La distincion (bronce ... platino)
    es la peor medalla entre las pruebas, asi que mejora al repetirlas.
    Si la policia la retira, se recupera aprobando otra vez el examen final.

    Comandos:
        /mostrarlicencia [id]            ensena tu licencia a un jugador a menos de 3 m (sin id: la miras tu)
        /consultarlicencia <id>          (policia) consulta en el registro la licencia de un jugador
        /retirarlicencia <id> <motivo>   (policia, a menos de 5 m) retira la licencia
        /darlicencia <id>                (admin) entrega o rehabilita la licencia sin pruebas

    Exports (servidor):
        getDriverLicense(player)  -> { number, status ("valid" | "revoked"), issued, reason } | false
        hasDriverLicense(player)  -> true si tiene una licencia vigente
]]

pendingDelivery = {}      -- [characterId] = true: la licencia se emitio pero no cupo en el inventario
local licenses = {}       -- [characterId] = fila (cache para los exports)
local cooldown = {}

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onItemUse", false)
addEvent("rp:driving:reprint", true)

local function isPolice(player)
    local ok, yes = pcall(function() return exports.rp_factions:isPlayerInFaction(player, DRIVING.POLICE_FACTION_TYPE) end)
    return ok and yes == true
end

local function sameSpot(a, b, maxDist)
    if getElementInterior(a) ~= getElementInterior(b) or getElementDimension(a) ~= getElementDimension(b) then return false end
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz) <= maxDist
end

----------------------------------------------------------------
-- Lectura
----------------------------------------------------------------
local LICENSE_SQL = [[
    SELECT number, status, revoked_reason, revoked_by,
           DATE_FORMAT(issued_at, '%d/%m/%Y') AS issued, DATE_FORMAT(revoked_at, '%d/%m/%Y') AS revoked
    FROM driving_licenses WHERE character_id = ?
]]

function getLicenseRow(characterId, callback)
    dbQuery(function(qh)
        local row = (dbPoll(qh, 0) or {})[1]
        licenses[characterId] = row or nil
        callback(row or false)
    end, db(), LICENSE_SQL, characterId)
end

-- Datos de la tarjeta: licencia + personaje + distincion
local function buildCard(characterId, callback)
    dbQuery(function(qh)
        local c = (dbPoll(qh, 0) or {})[1]
        if not c then return callback(false) end
        getLicenseRow(characterId, function(lic)
            dbQuery(function(qh2)
                local s = (dbPoll(qh2, 0) or {})[1] or {}
                local passed = tonumber(s.passed) or 0
                callback({
                    name = displayName(c.name), age = tonumber(c.age), gender = tonumber(c.gender) == 1 and "F" or "M",
                    height = tonumber(c.height), origin = c.origin,
                    number = lic and lic.number, status = lic and lic.status or "none",
                    issued = lic and lic.issued, revoked = lic and lic.revoked,
                    reason = lic and lic.revoked_reason, by = lic and lic.revoked_by and displayName(lic.revoked_by),
                    medal = passed >= #DRIVING_TESTS and (tonumber(s.min_medal) or 0) or 0,
                    score = tonumber(s.total) or 0, maxScore = #DRIVING_TESTS * 100,
                })
            end, db(), "SELECT COUNT(*) AS passed, MIN(medal) AS min_medal, SUM(best_score) AS total FROM driving_scores WHERE character_id = ? AND medal > 0", characterId)
        end)
    end, db(), "SELECT name, age, gender, height, origin FROM characters WHERE id = ?", characterId)
end

-- mode: "own" (la miras tu), "shown" (te la ensenan), "check" (consulta policial)
local function showCard(viewer, characterId, mode, fromName)
    buildCard(characterId, function(card)
        if not card or not isElement(viewer) then return end
        card.mode, card.from = mode, fromName
        triggerClientEvent(viewer, "rp:driving:card", resourceRoot, card)
    end)
end

----------------------------------------------------------------
-- Emision
----------------------------------------------------------------
local function giveLicenseItem(player, characterId)
    if exports.rp_inventory:hasItem(player, "driver_license", 1) then return true end
    local ok, reason = exports.rp_inventory:giveItem(player, "driver_license", 1)
    if ok then
        pendingDelivery[characterId] = nil
        return true
    end
    pendingDelivery[characterId] = true
    notify(player, (reason or "No tienes espacio.") .. " Recoge tu licencia en la autoescuela cuando tengas espacio (gratis).", "warning", 9000)
    return false
end

local function newNumber()
    return ("%s-%06d"):format(DRIVING.LICENSE_PREFIX, math.random(0, 999999))
end

function issueLicense(player, characterId, tries)
    tries = tries or 0
    local number = newNumber()
    dbQuery(function(qh)
        local ok, _, _, code = dbPoll(qh, 0)
        if not ok then
            if tries < 5 then return issueLicense(player, characterId, tries + 1) end   -- numero repetido
            return outputDebugString("[rp_driving] No se pudo emitir la licencia del personaje " .. characterId .. " (" .. tostring(code) .. ")", 1)
        end
        getLicenseRow(characterId, function()
            if not isElement(player) or characterOf(player) ~= characterId then return end
            giveLicenseItem(player, characterId)
            triggerEvent("rp:achievements:progress", player, "driving_license", 1)   -- logros (rp_achievements)
            exports.rp_notify:popup(player, "¡Licencia de conducir!",
                "Aprobaste todas las pruebas. Tu licencia esta en el inventario (I): la policia puede pedirtela. Sigue mejorando tus medallas para subir su distincion.", "success", 12000)
            showCard(player, characterId, "own")
        end)
    end, db(), "INSERT INTO driving_licenses (character_id, number) VALUES (?, ?)", characterId, number)
end

local function reinstateLicense(player, characterId)
    dbExec(db(), "UPDATE driving_licenses SET status = 'valid', revoked_reason = NULL, revoked_by = NULL, revoked_at = NULL WHERE character_id = ?", characterId)
    getLicenseRow(characterId, function()
        if not isElement(player) then return end
        giveLicenseItem(player, characterId)
        exports.rp_notify:popup(player, "Licencia rehabilitada", "Aprobaste el examen final: tu licencia vuelve a estar vigente.", "success", 9000)
    end)
end

-- Lo llama s_runs.lua al aprobar una prueba (scores ya incluye el resultado nuevo)
function afterTestPassed(player, characterId, test, scores)
    getLicenseRow(characterId, function(lic)
        if not isElement(player) or characterOf(player) ~= characterId then return end
        if not lic then
            if allTestsPassed(scores) then issueLicense(player, characterId) end
        elseif lic.status ~= "valid" and test.index == #DRIVING_TESTS then
            reinstateLicense(player, characterId)
        end
    end)
end

----------------------------------------------------------------
-- Reimpresion en la autoescuela
----------------------------------------------------------------
addEventHandler("rp:driving:reprint", resourceRoot, function()
    local player = client
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 1500 then return end
    cooldown[player] = now
    local characterId = characterOf(player)
    if not characterId or not getNearSchool(player) or isPlayerInTest(player) then return end
    getLicenseRow(characterId, function(lic)
        if not isElement(player) or characterOf(player) ~= characterId then return end
        if not lic then return notify(player, "Aun no tienes licencia: aprueba todas las pruebas.", "warning") end
        if lic.status ~= "valid" then return notify(player, "Tu licencia esta retirada. Aprueba de nuevo el examen final.", "error") end
        if exports.rp_inventory:hasItem(player, "driver_license", 1) then return notify(player, "Ya llevas tu licencia encima.", "info") end
        local free = pendingDelivery[characterId]
        local ok, reason = exports.rp_inventory:canCarry(player, "driver_license", 1)
        if not ok then return notify(player, reason, "error") end
        if not free then
            if getPlayerMoney(player) < DRIVING.REPRINT_PRICE then
                return notify(player, ("El duplicado cuesta $%d en efectivo."):format(DRIVING.REPRINT_PRICE), "error")
            end
            takePlayerMoney(player, DRIVING.REPRINT_PRICE)
            exports.rp_characters:saveCharacter(player)
        end
        giveLicenseItem(player, characterId)
        notify(player, free and "Recogiste tu licencia de conducir." or ("Duplicado de la licencia: -$%d."):format(DRIVING.REPRINT_PRICE), "success")
        sendMenu(player, "license")
    end)
end)

----------------------------------------------------------------
-- Usar el item y comandos
----------------------------------------------------------------
addEventHandler("rp:onItemUse", root, function(itemId)
    if itemId ~= "driver_license" then return end
    local characterId = characterOf(source)
    if characterId then showCard(source, characterId, "own") end
end)

addCommandHandler("mostrarlicencia", function(player, _, query)
    local characterId = characterOf(player)
    if not characterId then return end
    if not exports.rp_inventory:hasItem(player, "driver_license", 1) then
        return notify(player, "No llevas tu licencia de conducir encima.", "error")
    end
    if not query then return showCard(player, characterId, "own") end
    local target = exports.rp_ids:findPlayer(query)
    if not target or target == player or not characterOf(target) then
        return notify(player, "Uso: /mostrarlicencia [id o nombre] (sin id la miras tu)", "warning")
    end
    if not sameSpot(player, target, DRIVING.SHOW_DISTANCE) then
        return notify(player, "Acercate a esa persona para ensenarle la licencia.", "warning")
    end
    local name = displayName(getPlayerName(player))
    showCard(target, characterId, "shown", name)
    notify(player, ("Le ensenas tu licencia a %s."):format(displayName(getPlayerName(target))), "info")
end)

addCommandHandler("consultarlicencia", function(player, _, query)
    if not characterOf(player) then return end
    if not isPolice(player) and not isAdmin(player) then
        return notify(player, "Solo la policia puede consultar el registro de licencias.", "error")
    end
    local target = query and exports.rp_ids:findPlayer(query)
    local characterId = target and characterOf(target)
    if not characterId then return notify(player, "Uso: /consultarlicencia <id o nombre>", "warning") end
    showCard(player, characterId, "check")
end)

addCommandHandler("retirarlicencia", function(player, _, query, ...)
    if not characterOf(player) then return end
    local admin = isAdmin(player)
    if not isPolice(player) and not admin then return notify(player, "Solo la policia puede retirar licencias.", "error") end
    local reason = table.concat({ ... }, " "):gsub("^%s+", ""):gsub("%s+$", "")
    local target = query and exports.rp_ids:findPlayer(query)
    local characterId = target and characterOf(target)
    if not characterId or #reason < 3 then return notify(player, "Uso: /retirarlicencia <id o nombre> <motivo>", "warning") end
    if #reason > DRIVING.REASON_MAX then reason = reason:sub(1, DRIVING.REASON_MAX) end
    if not admin and not sameSpot(player, target, DRIVING.REVOKE_DISTANCE) then
        return notify(player, "Tienes que estar junto al conductor.", "warning")
    end
    local officer = getPlayerName(player)
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        if not isElement(player) then return end
        if not (affected and affected > 0) then return notify(player, "Esa persona no tiene una licencia vigente.", "warning") end
        licenses[characterId] = nil
        if isElement(target) then
            getLicenseRow(characterId, function() end)
            exports.rp_inventory:takeItem(target, "driver_license", 1)
            exports.rp_notify:popup(target, "Licencia retirada",
                ("%s te ha retirado la licencia de conducir: %s. Para recuperarla, aprueba otra vez el examen final de la autoescuela."):format(displayName(officer), reason), "error", 12000)
        end
        notify(player, ("Licencia de %s retirada."):format(displayName(getPlayerName(target))), "success")
    end, db(), [[UPDATE driving_licenses SET status = 'revoked', revoked_reason = ?, revoked_by = ?, revoked_at = NOW()
        WHERE character_id = ? AND status = 'valid']], reason, officer, characterId)
end)

addCommandHandler("darlicencia", function(player, _, query)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    local characterId = target and characterOf(target)
    if not characterId then return notify(player, "Uso: /darlicencia <id o nombre>", "warning") end
    getLicenseRow(characterId, function(lic)
        if not isElement(target) then return end
        if not lic then issueLicense(target, characterId)
        elseif lic.status ~= "valid" then reinstateLicense(target, characterId)
        else giveLicenseItem(target, characterId) end
        if isElement(player) then notify(player, ("Licencia entregada a %s."):format(displayName(getPlayerName(target))), "success") end
    end)
end)

----------------------------------------------------------------
-- Cache para los exports
----------------------------------------------------------------
addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    getLicenseRow(characterId, function() end)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    local function loadOnline()
        for _, p in ipairs(getElementsByType("player")) do
            local id = characterOf(p)
            if id then getLicenseRow(id, function() end) end
        end
    end
    if exports.rp_database:isReady() then loadOnline() end
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)

function getDriverLicense(player)
    local characterId = isElement(player) and characterOf(player)
    local row = characterId and licenses[characterId]
    if not row then return false end
    return { number = row.number, status = row.status, issued = row.issued, reason = row.revoked_reason }
end

function hasDriverLicense(player)
    local lic = getDriverLicense(player)
    return lic and lic.status == "valid" or false
end
