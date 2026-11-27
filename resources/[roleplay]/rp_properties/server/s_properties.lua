--[[
    rp_properties / s_properties.lua
    Propiedades comprables (tabla properties). En la puerta hay un pickup:
      - casa verde: en venta -> al tocarlo se abre un modal Comprar / Previsualizar
      - flecha blanca: con dueno -> E para entrar (si esta abierta o eres el dueno)
    Dentro hay un punto de salida (E). La compra se paga con la cuenta bancaria.

    Comandos:
        /cerrarcasa              abre o cierra con llave la propiedad en la que estas (dueno)
        /vendercasa              vende la propiedad en la que estas (reembolso 50%)
        /crearcasa <tipo> <precio> <nombre...>   (admin) crea una propiedad en tu posicion
        /borrarcasa <id>                         (admin)
        /tiposcasa                               lista los tipos de interior
]]

local props = {}       -- [id] = { row, pickup, col, exitCol }
local previews = {}    -- [player] = { id, timer }
local near = {}        -- [player] = { id, inside = bool }

addEvent("rp:prop:buy", true)
addEvent("rp:prop:preview", true)
addEvent("rp:prop:enter", true)
addEvent("rp:prop:exit", true)
addEvent("rp:onDatabaseReady", false)
-- Eventos para otros recursos (rp_furniture): entrar/salir (source = jugador), vender y borrar (source = root)
addEvent("rp:prop:entered", false)
addEvent("rp:prop:left", false)
addEvent("rp:prop:sold", false)
addEvent("rp:prop:deleted", false)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end

local function dimensionOf(id) return PROPERTY.DIMENSION_BASE + id end

-- Propiedades iniciales (puertas de Grove Street e Idlewood)
local SEED = {
    { "Casa Grove Street 1", "grove",  45000, 2495.33, -1691.14, 14.77 },
    { "Casa Grove Street 2", "small",  30000, 2513.77, -1650.90, 14.36 },
    { "Casa Grove Street 3", "ryder",  35000, 2486.47, -1645.00, 14.08 },
    { "Casa Grove Street 4", "small",  30000, 2469.53, -1646.41, 13.78 },
    { "Casa Grove Street 5", "medium", 55000, 2451.84, -1641.40, 14.07 },
    { "Casa Ganton",         "family", 80000, 2524.52, -1658.62, 15.82 },
    { "Casa Idlewood",       "modern", 95000, 2065.18, -1703.48, 14.15 },
    { "Villa Idlewood",      "villa",  250000, 2018.10, -1703.20, 14.23 },
}

----------------------------------------------------------------
-- Elementos del mundo
----------------------------------------------------------------
-- Interior de una propiedad: el suyo propio (casas originales de GTA) o el del tipo
local function interiorOf(row)
    if tonumber(row.int_id) and tonumber(row.ix) then
        return { interior = tonumber(row.int_id), x = tonumber(row.ix), y = tonumber(row.iy), z = tonumber(row.iz) + 1,
                 rot = tonumber(row.irot) or 0, name = (INTERIOR_TYPES[row.type] or {}).name or "Casa original" }
    end
    return INTERIOR_TYPES[row.type]
end

local function ownerName(row)
    return row.owner_name and (tostring(row.owner_name):gsub("_", " ")) or nil
end

local function publicInfo(row)
    local t = interiorOf(row)
    return {
        id = tonumber(row.id), name = row.name, price = tonumber(row.price), typeName = t and t.name or row.type,
        owner = ownerName(row), locked = tonumber(row.locked) == 1,
    }
end

local function destroyProperty(id)
    local p = props[id]
    if not p then return end
    for _, el in ipairs({ p.pickup, p.col, p.exitCol, p.exitMarker }) do if isElement(el) then destroyElement(el) end end
    props[id] = nil
end

local function spawnProperty(row)
    local id = tonumber(row.id)
    destroyProperty(id)
    local t = interiorOf(row)
    if not t then return outputDebugString("[rp_properties] Tipo desconocido en propiedad #" .. id, 2) end

    local owned = row.owner_id ~= nil and row.owner_id ~= false
    local pickup = createPickup(row.x, row.y, row.z, 3, owned and PROPERTY.PICKUP_OWNED or PROPERTY.PICKUP_FOR_SALE, 0)
    setElementData(pickup, "rp:property", publicInfo(row))

    -- Zona de la puerta (tubo vertical: tolera pequenos errores de altura)
    local col = createColTube(row.x, row.y, row.z - 2, 1.4, 4)
    -- Zona de salida dentro del interior
    local exitCol = createColSphere(t.x, t.y, t.z, 2.0)
    setElementInterior(exitCol, t.interior)
    setElementDimension(exitCol, dimensionOf(id))
    -- Marcador visible de salida (mismo interior y dimension que la propiedad)
    local exitMarker = createMarker(t.x, t.y, t.z - 1, "cylinder", 1.4, 245, 165, 36, 150)
    setElementInterior(exitMarker, t.interior)
    setElementDimension(exitMarker, dimensionOf(id))
    exports.rp_markers:setMarkerStyle(exitMarker, { icon = "exit", label = "Salir" })

    props[id] = { row = row, pickup = pickup, col = col, exitCol = exitCol, exitMarker = exitMarker, exit = t }

    addEventHandler("onColShapeHit", col, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim or not characterOf(el) or isPedInVehicle(el) then return end
        near[el] = { id = id, inside = false }
        triggerClientEvent(el, "rp:prop:near", resourceRoot, publicInfo(props[id].row), false, tonumber(props[id].row.owner_id) == characterOf(el))
    end)
    addEventHandler("onColShapeLeave", col, function(el)
        if getElementType(el) == "player" and near[el] and near[el].id == id and not near[el].inside then
            near[el] = nil
            triggerClientEvent(el, "rp:prop:near", resourceRoot, false)
        end
    end)
    addEventHandler("onColShapeHit", exitCol, function(el, sameDim)
        if getElementType(el) ~= "player" or not sameDim then return end
        near[el] = { id = id, inside = true }
        triggerClientEvent(el, "rp:prop:near", resourceRoot, publicInfo(props[id].row), true, false)
    end)
    addEventHandler("onColShapeLeave", exitCol, function(el)
        if getElementType(el) == "player" and near[el] and near[el].id == id and near[el].inside then
            near[el] = nil
            triggerClientEvent(el, "rp:prop:near", resourceRoot, false)
        end
    end)
end

local function refresh(id)
    local p = props[id]
    if not p then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if rows[1] then spawnProperty(rows[1]) else destroyProperty(id) end
    end, db(), "SELECT p.*, c.name AS owner_name FROM properties p LEFT JOIN characters c ON c.id = p.owner_id WHERE p.id = ?", id)
end

local function insertProperty(name, kind, price, x, y, z, callback)
    dbQuery(function(qh)
        local ok, _, id = dbPoll(qh, 0)
        if ok then
            spawnProperty({ id = id, name = name, type = kind, price = price, x = x, y = y, z = z, locked = 1 })
        end
        if callback then callback(ok and id) end
    end, db(), "INSERT INTO properties (name, type, price, x, y, z) VALUES (?, ?, ?, ?, ?, ?)", name, kind, price, x, y, z)
end

-- Siembra atomica: no inserta si ya hay una propiedad con ese nombre en esa puerta. loadProperties
-- puede correr dos veces seguidas (arranque + rp:onDatabaseReady de un reinicio de rp_database) y
-- ambas veian la tabla vacia: asi nacieron las casas 139-146, copias de la 1-8.
local function seedProperty(name, kind, price, x, y, z)
    dbQuery(function(qh)
        local ok, affected, id = dbPoll(qh, 0)
        if ok and (tonumber(affected) or 0) > 0 then
            spawnProperty({ id = id, name = name, type = kind, price = price, x = x, y = y, z = z, locked = 1 })
        end
    end, db(), [[
        INSERT INTO properties (name, type, price, x, y, z)
        SELECT ?, ?, ?, ?, ?, ? FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM properties WHERE name = ? AND ABS(x - ?) < 0.5 AND ABS(y - ?) < 0.5)
    ]], name, kind, price, x, y, z, name, x, y)
end

-- Borra las copias que dejo esa carrera: misma puerta y nombre que otra, sin dueno y sin nada
-- asociado (muebles, miembros, estilo). Si las dos estan libres se queda la de id menor; nunca
-- se borra una con dueno.
local DEDUPE_SQL = [[
    DELETE b FROM properties b
    JOIN properties a ON a.id <> b.id AND a.name = b.name
        AND ABS(a.x - b.x) < 0.5 AND ABS(a.y - b.y) < 0.5 AND ABS(a.z - b.z) < 1
        AND (a.owner_id IS NOT NULL OR a.id < b.id)
    WHERE b.owner_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM property_furniture f WHERE f.property_id = b.id)
        AND NOT EXISTS (SELECT 1 FROM property_members m WHERE m.property_id = b.id)
        AND NOT EXISTS (SELECT 1 FROM property_style s WHERE s.property_id = b.id)
        AND NOT EXISTS (SELECT 1 FROM furniture_log l WHERE l.property_id = b.id)
]]

----------------------------------------------------------------
-- Casas de Los Santos a partir de los datos de GTA (s_seed_ls.lua)
----------------------------------------------------------------
local function classify(model, x, y)
    model = model:lower()
    if model:find("hill") or model:find("mulhouse") or model:find("santahouse") or model:find("tce") then
        local kinds = { "large", "villa", "modern" }
        return kinds[math.random(#kinds)], math.random(14, 35) * 10000
    elseif model:find("apart") then
        return "small", math.random(30, 55) * 1000
    elseif model:find("lawn") or model:find("compfuk") or model:find("sanped") then
        local kinds = { "medium", "modern", "family" }
        return kinds[math.random(#kinds)], math.random(55, 90) * 1000
    end
    local kinds = { "small", "ryder", "grove" }
    return kinds[math.random(#kinds)], math.random(25, 45) * 1000
end

-- Inserta (bloqueante, solo la primera vez) evitando duplicar puertas cercanas
function seedLosSantos(existing)
    local taken = {}
    for _, r in ipairs(existing) do taken[#taken + 1] = { tonumber(r.x), tonumber(r.y) } end
    local function free(x, y)
        for _, t in ipairs(taken) do
            if getDistanceBetweenPoints2D(x, y, t[1], t[2]) < 9 then return false end
        end
        taken[#taken + 1] = { x, y }
        return true
    end
    local count, counter = 0, {}
    local function zoneName(x, y, z)
        local zone = getZoneName(x, y, z)
        counter[zone] = (counter[zone] or 0) + 1
        return ("Casa %s %d"):format(zone, counter[zone])
    end

    for _, h in ipairs(ENEX_HOUSES) do
        local name, x, y, z, int, ix, iy, iz, irot = unpack(h)
        if free(x, y) then
            local price = name == "MADDOGS" and 900000 or math.random(60, 120) * 1000
            dbPoll(dbQuery(db(), "INSERT INTO properties (name, type, price, x, y, z, int_id, ix, iy, iz, irot, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                name == "MADDOGS" and "Mansion de Mulholland" or zoneName(x, y, z), "medium", price, x, y, z, int, ix, iy, iz, irot, "enex"), -1)
            count = count + 1
        end
    end
    for _, h in ipairs(MAP_HOUSES) do
        local model, x, y, z = unpack(h)
        if free(x, y) then
            local kind, price = classify(model, x, y)
            dbPoll(dbQuery(db(), "INSERT INTO properties (name, type, price, x, y, z, source) VALUES (?, ?, ?, ?, ?, ?, ?)",
                zoneName(x, y, z), kind, price, x, y, z, "map"), -1)
            count = count + 1
        end
    end
    return count
end

local selectAndSpawn   -- se define abajo

function loadProperties()
    dbQuery(function(qh)
        local _, removed = dbPoll(qh, 0)
        if (tonumber(removed) or 0) > 0 then
            outputDebugString(("[rp_properties] %d propiedades duplicadas (sin dueno) eliminadas"):format(removed), 2)
        end
        selectAndSpawn()
    end, db(), DEDUPE_SQL)
end

selectAndSpawn = function()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if #rows == 0 then
            for _, s in ipairs(SEED) do seedProperty(s[1], s[2], s[3], s[4], s[5], s[6]) end
            return
        end
        -- Primera vez con los datos de GTA: agrega las casas de todo Los Santos
        local hasMap = false
        for _, row in ipairs(rows) do if row.source == "map" or row.source == "enex" then hasMap = true break end end
        if not hasMap then
            local added = seedLosSantos(rows)
            outputDebugString(("[rp_properties] %d casas de Los Santos agregadas desde los datos del juego"):format(added))
            return loadProperties()
        end
        for _, row in ipairs(rows) do spawnProperty(row) end
        outputDebugString(("[rp_properties] %d propiedades cargadas"):format(#rows))
    end, db(), "SELECT p.*, c.name AS owner_name FROM properties p LEFT JOIN characters c ON c.id = p.owner_id")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadProperties() else addEventHandler("rp:onDatabaseReady", root, loadProperties) end
end)

----------------------------------------------------------------
-- Entrar / salir
----------------------------------------------------------------
-- Coloca al jugador congelado (espera a que cargue el mapa) para no caer a traves del suelo
local function placePlayer(player, interior, dimension, x, y, z, rot)
    setElementFrozen(player, true)
    setElementInterior(player, interior)
    setElementDimension(player, dimension)
    setElementPosition(player, x, y, z)
    if rot then setElementRotation(player, 0, 0, rot) end
    setCameraTarget(player, player)
    setTimer(function()
        if isElement(player) then setElementFrozen(player, false) end
    end, 1500, 1)
end

local entryPos = {}   -- [player] = { id, x, y, z }: donde estaba al entrar, para volver exacto ahi

local function teleportInside(player, id)
    if getElementInterior(player) == 0 and getElementDimension(player) == 0 then
        local ex, ey, ez = getElementPosition(player)
        entryPos[player] = { id = id, x = ex, y = ey, z = ez }
    end
    local row = props[id].row
    local t = interiorOf(row)
    fadeCamera(player, false, 0.5)
    setTimer(function()
        if not isElement(player) then return end
        placePlayer(player, t.interior, dimensionOf(id), t.x, t.y, t.z, t.rot)
        fadeCamera(player, true, 0.8)
        triggerEvent("rp:prop:entered", player, id)
    end, 600, 1)
end

local function teleportOutside(player, id)
    local row = props[id] and props[id].row
    fadeCamera(player, false, 0.5)
    setTimer(function()
        if not isElement(player) then return end
        -- Sale exactamente en la puerta (el pickup siempre esta en el exterior)
        local ep = entryPos[player]
        if ep and ep.id == id then row = { x = ep.x, y = ep.y, z = ep.z } end
        if row then
            placePlayer(player, 0, 0, tonumber(row.x), tonumber(row.y), tonumber(row.z) + 0.6)
            triggerClientEvent(player, "rp:prop:groundFix", resourceRoot, tonumber(row.x), tonumber(row.y), tonumber(row.z))
        else
            setElementInterior(player, 0)
            setElementDimension(player, 0)
        end
        fadeCamera(player, true, 0.8)
        triggerEvent("rp:prop:left", player, id)
    end, 600, 1)
end

local function endPreview(player, silent)
    local pv = previews[player]
    if not pv then return end
    if isTimer(pv.timer) then killTimer(pv.timer) end
    previews[player] = nil
    if isElement(player) then
        triggerClientEvent(player, "rp:prop:previewTimer", resourceRoot, false)
        if not silent then
            teleportOutside(player, pv.id)
            notify(player, "Termino la visita a la propiedad.", "info")
        end
    end
end

addEventHandler("rp:prop:enter", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local n = near[player]
    if not n or n.inside or not props[n.id] then return end
    local row = props[n.id].row
    if not row.owner_id then return end   -- en venta: se usa el modal
    if tonumber(row.locked) == 1 and tonumber(row.owner_id) ~= characterOf(player) then
        return notify(player, "La puerta esta cerrada con llave.", "warning")
    end
    teleportInside(player, n.id)
end)

addEventHandler("rp:prop:exit", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local n = near[player]
    if not n or not n.inside then
        -- Respaldo: si el jugador esta en la dimension de una propiedad y cerca de la salida, sale igual
        local dim = getElementDimension(player)
        local id = dim > PROPERTY.DIMENSION_BASE and dim - PROPERTY.DIMENSION_BASE
        local p = id and props[id]
        if not p then return end
        local px, py, pz = getElementPosition(player)
        if getElementInterior(player) ~= p.exit.interior or getDistanceBetweenPoints3D(px, py, pz, p.exit.x, p.exit.y, p.exit.z) > 8 then return end
        n = { id = id, inside = true }
    end
    if previews[player] then return endPreview(player) end
    teleportOutside(player, n.id)
end)

addEventHandler("rp:prop:preview", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local n = near[player]
    if not n or n.inside or not props[n.id] or props[n.id].row.owner_id then return end
    if previews[player] then return end
    local id = n.id
    previews[player] = { id = id, timer = setTimer(function() endPreview(player) end, PROPERTY.PREVIEW_TIME, 1) }
    teleportInside(player, id)
    triggerClientEvent(player, "rp:prop:previewTimer", resourceRoot, PROPERTY.PREVIEW_TIME)
    notify(player, "Tienes 1 minuto para ver la propiedad. Pulsa E en la salida para terminar antes.", "info")
end)

----------------------------------------------------------------
-- Comprar
----------------------------------------------------------------
addEventHandler("rp:prop:buy", resourceRoot, function()
    if client and getElementData(client, "rp:downed") then return end   -- abatido (rp_injury)
    local player = client
    local n = near[player]
    local characterId = characterOf(player)
    if not n or n.inside or not characterId or not props[n.id] then return end
    local id = n.id
    local row = props[id].row
    if row.owner_id then return notify(player, "Esta propiedad ya tiene dueno.", "error") end
    local price = tonumber(row.price)

    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) then return end
        if (tonumber(rows[1] and rows[1].total) or 0) >= PROPERTY.MAX_PER_CHARACTER then
            return notify(player, ("Solo puedes tener %d propiedades."):format(PROPERTY.MAX_PER_CHARACTER), "error")
        end
        -- Cobro atomico desde la cuenta bancaria
        dbQuery(function(qh2)
            local _, affected = dbPoll(qh2, 0)
            if not isElement(player) then return end
            if not affected or affected == 0 then
                return notify(player, ("Necesitas $%d en tu cuenta bancaria."):format(price), "error")
            end
            -- Asignar dueno solo si sigue libre (evita dobles compras)
            dbQuery(function(qh3)
                local _, assigned = dbPoll(qh3, 0)
                if not assigned or assigned == 0 then
                    dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", price, characterId)
                    return notify(player, "Alguien compro esta propiedad antes que tu.", "error")
                end
                dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'purchase', ?, ?)", characterId, price, row.name)
                if isElement(player) then triggerEvent("rp:achievements:progress", player, "property_bought", 1) end   -- logros
                exports.rp_notify:popup(player, "Propiedad comprada", row.name .. " ya es tuya. Usa /cerrarcasa para abrir o cerrar.", "success")
                refresh(id)
                triggerClientEvent(player, "rp:prop:near", resourceRoot, false)
                near[player] = nil
            end, db(), "UPDATE properties SET owner_id = ?, locked = 1 WHERE id = ? AND owner_id IS NULL", characterId, id)
        end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", price, characterId, price)
    end, db(), "SELECT COUNT(*) AS total FROM properties WHERE owner_id = ?", characterId)
end)

----------------------------------------------------------------
-- Comandos
----------------------------------------------------------------
local function currentProperty(player)
    local dim = getElementDimension(player)
    if dim > PROPERTY.DIMENSION_BASE then return dim - PROPERTY.DIMENSION_BASE end
    return near[player] and near[player].id
end

addCommandHandler("cerrarcasa", function(player)
    local id = currentProperty(player)
    local p = id and props[id]
    if not p or tonumber(p.row.owner_id) ~= characterOf(player) then
        return notify(player, "Debes estar en la puerta o dentro de una propiedad tuya.", "warning")
    end
    local locked = tonumber(p.row.locked) == 1 and 0 or 1
    dbExec(db(), "UPDATE properties SET locked = ? WHERE id = ?", locked, id)
    p.row.locked = locked
    setElementData(p.pickup, "rp:property", publicInfo(p.row))
    notify(player, locked == 1 and "Cerraste la puerta con llave." or "Abriste la puerta.", "success")
end)

addCommandHandler("vendercasa", function(player)
    local id = currentProperty(player)
    local p = id and props[id]
    local characterId = characterOf(player)
    if not p or tonumber(p.row.owner_id) ~= characterId then
        return notify(player, "Debes estar en la puerta o dentro de una propiedad tuya.", "warning")
    end
    local refund = math.floor(tonumber(p.row.price) * PROPERTY.SELL_REFUND)
    dbExec(db(), "UPDATE properties SET owner_id = NULL, locked = 1 WHERE id = ?", id)
    dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", refund, characterId)
    dbExec(db(), "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'sale', ?, ?)", characterId, refund, p.row.name)
    notify(player, ("Vendiste %s. Recibiste $%d en tu cuenta."):format(p.row.name, refund), "success")
    -- Saca a quien este dentro
    for _, pl in ipairs(getElementsByType("player")) do
        if getElementDimension(pl) == dimensionOf(id) then teleportOutside(pl, id) end
    end
    triggerEvent("rp:prop:sold", root, id, characterId)   -- rp_furniture guarda los muebles en la bodega del vendedor
    refresh(id)
end)

local function isAdmin(player) return (exports.rp_login:getPlayerAdminLevel(player) or 0) >= 1 end

addCommandHandler("tiposcasa", function(player)
    local list = {}
    for key, t in pairs(INTERIOR_TYPES) do list[#list + 1] = key .. " (" .. t.name .. ")" end
    table.sort(list)
    notify(player, "Tipos: " .. table.concat(list, ", "), "info")
end)

addCommandHandler("crearcasa", function(player, _, kind, price, ...)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    price = tonumber(price)
    local name = table.concat({ ... }, " ")
    if not INTERIOR_TYPES[kind] or not price or price < 1 or #name < 3 or #name > 48 then
        return notify(player, "Uso: /crearcasa <tipo> <precio> <nombre>  (ver /tiposcasa)", "warning")
    end
    if getElementInterior(player) ~= 0 then return notify(player, "Crea la propiedad en el exterior, frente a la puerta.", "warning") end
    local x, y, z = getElementPosition(player)
    insertProperty(name, kind, math.floor(price), x, y, z, function(id)
        if id then notify(player, ("Propiedad #%d '%s' creada."):format(id, name), "success") end
    end)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbyhouses, /gotohouse, /delhouse...)
function adminElements()
    local list = {}
    for id, e in pairs(props) do
        local row = e.row
        if row then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = 0, dimension = 0, label = row.name .. (row.owner_id and (" (con dueno #" .. tostring(row.owner_id) .. ")") or " (en venta)"),
                ownerId = tonumber(row.owner_id), createdAt = row.created_at,
                info = ("tipo %s, $%s%s"):format(tostring(row.type), tostring(row.price),
                    row.source == "enex" and ", entrada del mapa original" or ""),
                noRot = true, element = e.pickup,
                exit = e.exit and { x = e.exit.x, y = e.exit.y, z = e.exit.z, interior = e.exit.interior, dimension = dimensionOf(id),
                    rot = tonumber(e.exit.rot) or 0, element = e.exitMarker } }
        end
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not props[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM properties WHERE id = ?", id)
    triggerEvent("rp:prop:deleted", root, id)
    destroyProperty(id)
    return true
end

-- Mover desde el editor de rp_admin (vista ALT). part = "exit" mueve la salida dentro del interior
-- (se guarda como interior propio: int_id/ix/iy/iz/irot); si no, la puerta de la calle (sin giro).
function adminMove(id, _, x, y, z, rot, _, part)
    id = tonumber(id)
    local p = id and props[id]
    if not p then return false, "no existe" end
    local row = p.row
    if part == "exit" then
        local t = interiorOf(row)
        if not t then return false, "tipo de interior desconocido" end
        row.int_id, row.ix, row.iy, row.iz, row.irot = t.interior, x, y, z - 1, rot   -- interiorOf suma 1 a iz
        dbExec(db(), "UPDATE properties SET int_id = ?, ix = ?, iy = ?, iz = ?, irot = ? WHERE id = ?",
            row.int_id, row.ix, row.iy, row.iz, row.irot, id)
    else
        row.x, row.y, row.z = x, y, z
        dbExec(db(), "UPDATE properties SET x = ?, y = ?, z = ? WHERE id = ?", x, y, z, id)
    end
    spawnProperty(row)
    return true
end

addCommandHandler("borrarcasa", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrarcasa <id>", "warning") end
    notify(player, ("Propiedad #%d eliminada."):format(id), "success")
end)

addEventHandler("onPlayerQuit", root, function()
    -- Si sale durante una visita, que no aparezca dentro de una casa ajena
    if previews[source] then
        local pv = previews[source]
        endPreview(source, true)
        local row = props[pv.id] and props[pv.id].row
        local ep = entryPos[player]
        if ep and ep.id == id then row = { x = ep.x, y = ep.y, z = ep.z } end
        if row then
            setElementInterior(source, 0)
            setElementDimension(source, 0)
            setElementPosition(source, tonumber(row.x), tonumber(row.y), tonumber(row.z) + 0.6)
        end
    end
    near[source] = nil
end)

----------------------------------------------------------------
-- API para otros recursos (rp_furniture)
----------------------------------------------------------------
-- -> { id, name, type, owner_id, locked, price, interior, x, y, z, rot } | false
-- (x, y, z = punto de salida dentro del interior)
function getPropertyInfo(id)
    local p = props[tonumber(id)]
    if not p then return false end
    local t = p.exit
    return {
        id = tonumber(p.row.id), name = p.row.name, type = p.row.type,
        owner_id = tonumber(p.row.owner_id), locked = tonumber(p.row.locked) == 1, price = tonumber(p.row.price),
        interior = t.interior, x = t.x, y = t.y, z = t.z, rot = t.rot,
    }
end
