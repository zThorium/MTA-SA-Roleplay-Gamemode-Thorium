--[[
    rp_vending / s_vending.lua  (servidor)

    Maquinas expendedoras de bebidas y comida. Los admins marcan el punto frente a una maquina del
    mapa; el jugador cercano pulsa E, paga en efectivo y sube sed (bebida) o hambre (comida).
    Se guarda solo la posicion de cada maquina (tabla vending_machines).

    Admin (catalogo en rp_adminpanel/server/s_catalog.lua):
        /crearexpendedora <bebida|comida>   marca una maquina en tu posicion
        /borrarexpendedora <id>
        /expendedoras                       lista las maquinas
]]

local machines = {}   -- [id] = { row = {...}, col = colshape }
local near = {}       -- [player] = machineId
local cooldown = {}   -- [player] = tick de la ultima compra

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:vending:buy", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function log(msg, level) outputDebugString("[rp_vending] " .. msg, level or 3) end

local function sameWorld(p, m)
    return getElementDimension(p) == m.row.dimension and getElementInterior(p) == m.row.interior
end

local function setNear(p, id)
    near[p] = id
    local m = id and machines[id]
    triggerClientEvent(p, "rp:vending:near", resourceRoot, m and m.row.kind or false)
end

----------------------------------------------------------------
-- Mundo
----------------------------------------------------------------
local function spawnMachine(row)
    local col = createColSphere(row.x, row.y, row.z, VENDING.INTERACT_RADIUS)
    setElementInterior(col, row.interior)
    setElementDimension(col, row.dimension)
    machines[row.id] = { row = row, col = col }
    setElementData(col, "rp:vendingId", row.id, false)
    -- Rehidratar: quien ya estuviera dentro no dispara onColShapeHit
    for _, p in ipairs(getElementsWithinColShape(col, "player")) do
        if sameWorld(p, machines[row.id]) and exports.rp_characters:getPlayerCharacterId(p) then setNear(p, row.id) end
    end
end

local function destroyMachine(id)
    local m = machines[id]
    if not m then return end
    for p, nid in pairs(near) do if nid == id and isElement(p) then setNear(p, nil) end end
    if isElement(m.col) then destroyElement(m.col) end
    machines[id] = nil
end

addEventHandler("onColShapeHit", resourceRoot, function(el, matchingDim)
    if getElementType(el) ~= "player" or not matchingDim then return end
    local id = getElementData(source, "rp:vendingId")
    local m = id and machines[id]
    if m and sameWorld(el, m) and exports.rp_characters:getPlayerCharacterId(el) then setNear(el, id) end
end)

addEventHandler("onColShapeLeave", resourceRoot, function(el)
    if getElementType(el) ~= "player" then return end
    if near[el] == getElementData(source, "rp:vendingId") then setNear(el, nil) end
end)

addEventHandler("onPlayerQuit", root, function() near[source] = nil; cooldown[source] = nil end)
addEventHandler("rp:onCharacterLogout", root, function() near[source] = nil end)

----------------------------------------------------------------
-- Compra (el cliente solo pide; el servidor decide)
----------------------------------------------------------------
addEventHandler("rp:vending:buy", resourceRoot, function()
    local p = client                                    -- NUNCA source
    if not exports.rp_characters:getPlayerCharacterId(p) then return end
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < VENDING.COOLDOWN_MS then return end
    cooldown[p] = now

    local m = near[p] and machines[near[p]]
    if not m or not sameWorld(p, m) then return end
    local px, py, pz = getElementPosition(p)
    if getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z) > VENDING.INTERACT_RADIUS + 0.5 then return end
    if exports.rp_injury:isPlayerDowned(p) then return end
    if isPedInVehicle(p) then return notify(p, "Bajate del vehiculo.", "error") end

    local t = VENDING.TYPES[m.row.kind]
    if not t then return end
    if (exports.rp_needs:getNeed(p, t.need) or 0) >= 100 then
        return notify(p, t.need == "thirst" and "No tienes sed." or "No tienes hambre.", "info")
    end
    if getPlayerMoney(p) < t.price then return notify(p, ("Necesitas $%d."):format(t.price), "error") end

    takePlayerMoney(p, t.price)                         -- primero cobrar...
    exports.rp_characters:saveCharacter(p)
    exports.rp_needs:addNeed(p, t.need, t.amount)       -- ...despues entregar
    setPedAnimation(p, "VENDING", "VEND_Use", 1600, false, false, false, false)
    notify(p, ("Compraste %s por $%d."):format(t.product, t.price), "success")
end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
local KIND_BY_WORD = { bebida = "drink", bebidas = "drink", comida = "food" }

addCommandHandler("crearexpendedora", function(p, _, word)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    local kind = KIND_BY_WORD[tostring(word):lower()]
    if not kind then return notify(p, "Uso: /crearexpendedora <bebida|comida> (parado frente a la maquina)", "warning") end
    local x, y, z = getElementPosition(p)
    local _, _, rot = getElementRotation(p)
    local interior, dimension = getElementInterior(p), getElementDimension(p)
    dbQuery(function(qh)
        local result, _, insertId = dbPoll(qh, 0)
        if not result or not insertId then return log("Error al insertar maquina", 1) end
        spawnMachine({ id = insertId, kind = kind, x = x, y = y, z = z, rot = rot, interior = interior, dimension = dimension })
        if isElement(p) then notify(p, ("Expendedora de %s #%d creada."):format(VENDING.TYPES[kind].label, insertId), "success") end
    end, db(), "INSERT INTO vending_machines (kind, x, y, z, rot, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?)",
        kind, x, y, z, rot, interior, dimension)
end)

addCommandHandler("borrarexpendedora", function(p, _, id)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not machines[id] then return notify(p, "Uso: /borrarexpendedora <id>", "warning") end
    destroyMachine(id)
    dbExec(db(), "DELETE FROM vending_machines WHERE id = ?", id)
    notify(p, ("Expendedora #%d eliminada."):format(id), "success")
end)

addCommandHandler("expendedoras", function(p)
    if not isAdmin(p) then return notify(p, "No tienes permiso para usar este comando.", "error") end
    local n = 0
    for id, m in pairs(machines) do
        n = n + 1
        outputChatBox(("#%d %s (%.0f, %.0f, %.0f) int %d dim %d"):format(
            id, VENDING.TYPES[m.row.kind].label, m.row.x, m.row.y, m.row.z, m.row.interior, m.row.dimension), p)
    end
    notify(p, n .. " expendedoras (detalle en el chat).", "info")
end)

----------------------------------------------------------------
-- Arranque
----------------------------------------------------------------
local function boot()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do
            if VENDING.TYPES[row.kind] then spawnMachine(row) end
        end
        log(("%d expendedoras cargadas"):format(#rows))
    end, db(), "SELECT id, kind, x, y, z, rot, interior, dimension FROM vending_machines")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then boot() else addEventHandler("rp:onDatabaseReady", root, boot) end
end)
