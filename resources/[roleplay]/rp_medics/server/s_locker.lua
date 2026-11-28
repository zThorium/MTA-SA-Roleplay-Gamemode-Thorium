--[[
    rp_medics / s_locker.lua  (servidor)

    Casillero personal del vestuario: uno por personaje y tipo de facción.
      - Ítems de rp_inventory (faction_locker_items).
      - Una mochila de rp_backpacks con todo su contenido dentro (faction_locker_backpack).
    La memoria (locker[p]) manda; cada cambio se escribe en la BD en el momento.
    Mover = quitar de un lado y poner en el otro; si el segundo paso falla, se deshace el primero.
    Las tablas son genéricas (faction_type) para que el vestuario de F0.2 las reutilice.
]]

local locker = {}             -- [player] = { characterId, loading, items = { [itemId] = n }, pack = { id, contents } | nil }

local function inv() return exports.rp_inventory end
local function itemDef(id) return inv():getItemDefinition(id) end

local function isEquipment(itemId)
    if itemId == MED.DUTY_BACKPACK then return true end
    for _, e in ipairs(MED.EQUIPMENT) do if e.item == itemId then return true end end
    return false
end

-- ¿Se puede guardar este ítem en el casillero? -> true | false, motivo
local function storable(itemId)
    local d = itemDef(itemId)
    if not d then return false, "Ítem desconocido." end
    if isEquipment(itemId) then return false, "El material médico no se guarda en tu casillero: se devuelve al salir de servicio." end
    if d.use and d.use.event == "backpack" then return false, "Las mochilas van en el hueco de mochila." end
    return true
end

-- «Guardar todo» deja el teléfono y los documentos encima
local function keptByDefault(itemId)
    local d = itemDef(itemId)
    return MED.KEEP_ITEMS[itemId] or (d and d.document) or false
end

function MD.lockerReady(p)
    local L = locker[p]
    return L ~= nil and not L.loading
end

function MD.loadLocker(p, characterId)
    local L = { characterId = characterId, loading = true, items = {} }
    locker[p] = L
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(p) or locker[p] ~= L then return end
        for _, r in ipairs(rows) do
            if itemDef(r.item_id) and tonumber(r.amount) > 0 then L.items[r.item_id] = tonumber(r.amount) end
        end
        dbQuery(function(qh2)
            local packs = dbPoll(qh2, 0) or {}
            if not isElement(p) or locker[p] ~= L then return end
            local r = packs[1]
            if r and itemDef(r.backpack_id) then
                L.pack = { id = r.backpack_id, contents = fromJSON(r.contents) or {} }
            end
            L.loading = nil
        end, MD.db(), "SELECT backpack_id, contents FROM faction_locker_backpack WHERE character_id = ? AND faction_type = ?",
            characterId, MED.FACTION_TYPE)
    end, MD.db(), "SELECT item_id, amount FROM faction_locker_items WHERE character_id = ? AND faction_type = ?",
        characterId, MED.FACTION_TYPE)
end

function MD.unloadLocker(p) locker[p] = nil end

function MD.lockerCount(p)
    local L = locker[p]
    if not L then return 0 end
    local n = 0
    for _ in pairs(L.items) do n = n + 1 end
    return n + (L.pack and 1 or 0)
end

----------------------------------------------------------------
-- Escritura en la BD (memoria ya actualizada)
----------------------------------------------------------------
local function saveItem(L, itemId)
    local n = L.items[itemId] or 0
    if n > 0 then
        dbExec(MD.db(), [[
            INSERT INTO faction_locker_items (character_id, faction_type, item_id, amount) VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE amount = VALUES(amount)]], L.characterId, MED.FACTION_TYPE, itemId, n)
    else
        dbExec(MD.db(), "DELETE FROM faction_locker_items WHERE character_id = ? AND faction_type = ? AND item_id = ?",
            L.characterId, MED.FACTION_TYPE, itemId)
    end
end

----------------------------------------------------------------
-- Ítems
----------------------------------------------------------------
-- Guarda `amount` (o todo lo que lleva) de un ítem. -> true | false, motivo
function MD.storeItem(p, itemId, amount)
    local L = locker[p]
    if not L or L.loading then return false, "Tu casillero se está cargando." end
    local ok, why = storable(itemId)
    if not ok then return false, why end
    local have = inv():getItemAmount(p, itemId)
    amount = math.min(tonumber(amount) or have, have)
    if amount < 1 then return false, "No llevas ese ítem." end
    local d = itemDef(itemId)
    if d.weapon then pcall(function()                       -- vuelca las balas gastadas y enfunda el arma
        exports.rp_ammunation:suspendWeapons(p)
        exports.rp_ammunation:resumeWeapons(p, false)
    end) end
    local taken, reason = inv():takeItem(p, itemId, amount)
    if not taken then return false, reason end
    L.items[itemId] = (L.items[itemId] or 0) + amount
    saveItem(L, itemId)
    return true
end

-- Saca todo lo que quepa de un ítem. -> cantidad sacada (0 si no cabe nada), motivo
function MD.takeItem(p, itemId)
    local L = locker[p]
    if not L or L.loading then return 0, "Tu casillero se está cargando." end
    local have = L.items[itemId] or 0
    if have < 1 then return 0, "No está en tu casillero." end
    local n = have
    while n > 0 and not inv():canCarry(p, itemId, n) do n = n - 1 end
    if n < 1 then
        local _, why = inv():canCarry(p, itemId, 1)
        return 0, why or "No te cabe."
    end
    -- Primero sale del casillero; si la entrega falla, vuelve
    L.items[itemId] = have - n
    if L.items[itemId] < 1 then L.items[itemId] = nil end
    local ok, why = inv():giveItem(p, itemId, n)
    if not ok then
        L.items[itemId] = have
        return 0, why
    end
    saveItem(L, itemId)
    return n
end

----------------------------------------------------------------
-- Mochila
----------------------------------------------------------------
-- Guarda la mochila personal puesta (con su contenido). -> true | false, motivo
function MD.storePack(p)
    local L = locker[p]
    if not L or L.loading then return false, "Tu casillero se está cargando." end
    local worn = exports.rp_backpacks:getBackpack(p)
    if not worn then return false, "No llevas ninguna mochila puesta." end
    if worn == MED.DUTY_BACKPACK then return false, "La mochila médica se devuelve al salir de servicio." end
    if L.pack then return false, "Ya tienes una mochila en el casillero." end
    local id, contents = exports.rp_backpacks:stowBackpack(p)
    if not id then return false, "No puedes quitarte la mochila ahora." end
    L.pack = { id = id, contents = contents or {} }
    dbExec(MD.db(), "REPLACE INTO faction_locker_backpack (character_id, faction_type, backpack_id, contents) VALUES (?, ?, ?, ?)",
        L.characterId, MED.FACTION_TYPE, id, toJSON(L.pack.contents, true))
    return true
end

-- Se pone la mochila del casillero. -> true | false, motivo
function MD.takePack(p)
    local L = locker[p]
    if not L or L.loading then return false, "Tu casillero se está cargando." end
    if not L.pack then return false, "No tienes ninguna mochila en el casillero." end
    if exports.rp_backpacks:getBackpack(p) then return false, "Ya llevas una mochila puesta." end
    local pack = L.pack
    L.pack = nil
    local ok, why = exports.rp_backpacks:equipFromGround(p, pack.id, pack.contents)
    if not ok then
        L.pack = pack
        return false, why
    end
    dbExec(MD.db(), "DELETE FROM faction_locker_backpack WHERE character_id = ? AND faction_type = ?", L.characterId, MED.FACTION_TYPE)
    return true
end

----------------------------------------------------------------
-- Todo de una vez
----------------------------------------------------------------
-- Guarda la mochila (si hay hueco) y todo lo que lleva encima menos teléfono, documentos y material.
-- -> número de lotes guardados
function MD.storeAll(p)
    local stored = 0
    local worn = exports.rp_backpacks:getBackpack(p)
    if worn and worn ~= MED.DUTY_BACKPACK and MD.storePack(p) then stored = stored + 1 end
    for itemId in pairs(inv():getInventory(p) or {}) do
        if not keptByDefault(itemId) and storable(itemId) and MD.storeItem(p, itemId) then stored = stored + 1 end
    end
    return stored
end

-- Se pone la mochila y saca todo lo que quepa. -> lotes que se quedan dentro
function MD.takeAll(p)
    local L = locker[p]
    if not L or L.loading then return 0 end
    if L.pack and not exports.rp_backpacks:getBackpack(p) then MD.takePack(p) end
    local left = 0
    local ids = {}
    for itemId in pairs(L.items) do ids[#ids + 1] = itemId end
    for _, itemId in ipairs(ids) do
        MD.takeItem(p, itemId)
        if L.items[itemId] then left = left + 1 end
    end
    return left + (L.pack and 1 or 0)
end

-- ¿Lleva armas encima (inventario o mochila)?
function MD.carriesWeapons(p)
    for itemId in pairs(inv():getInventory(p) or {}) do
        local d = itemDef(itemId)
        if d and d.weapon then return true end
    end
    return false
end

----------------------------------------------------------------
-- Datos para el panel
----------------------------------------------------------------
local function entry(itemId, n, extra)
    local d = itemDef(itemId) or {}
    local e = { id = itemId, name = d.name or itemId, icon = d.icon or "📦", amount = n }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

local function sortByName(list) table.sort(list, function(a, b) return a.name < b.name end) end

function MD.lockerData(p)
    local L = locker[p] or { items = {} }
    local carried, stored = {}, {}
    for itemId, n in pairs(inv():getInventory(p) or {}) do
        local ok = storable(itemId)
        carried[#carried + 1] = entry(itemId, n, { locked = not ok, kept = keptByDefault(itemId) and true or false })
    end
    for itemId, n in pairs(L.items) do stored[#stored + 1] = entry(itemId, n) end
    sortByName(carried); sortByName(stored)

    local function packInfo(id, contents)
        local d = itemDef(id) or {}
        local count = 0
        for _, n in pairs(contents or {}) do count = count + n end
        return { id = id, name = d.name or "Mochila", count = count, duty = id == MED.DUTY_BACKPACK }
    end
    local worn = exports.rp_backpacks:getBackpack(p)
    local wornInfo = worn and exports.rp_backpacks:getBackpackInfo(p)
    return {
        loading = L.loading or false,
        carried = carried, stored = stored,
        wornPack = worn and packInfo(worn, wornInfo and wornInfo.items) or false,
        lockerPack = L.pack and packInfo(L.pack.id, L.pack.contents) or false,
    }
end
