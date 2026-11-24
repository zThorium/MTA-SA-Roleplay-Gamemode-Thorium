--[[
    rp_furniture / s_furniture.lua

    Modo construccion de interiores (estilo Los Sims). Cada mueble es un objeto del servidor
    en la dimension de la propiedad (10000 + id); la base guarda clave de catalogo, posicion,
    giro, escala, color y material (tabla property_furniture).

    - Carga perezosa: los objetos de una casa se crean cuando entra el primer jugador y se
      destruyen FURN.UNLOAD_DELAY ms despues de que sale el ultimo.
    - Solo construye el dueno o un residente (property_members), y solo uno a la vez por casa.
    - El cliente solo propone; aqui se valida clave, zona, limites, dinero y permisos.
    - Cada cambio se guarda al instante. "Cancelar" revierte la sesion al estado inicial.

    Comandos:
        /decorar                   entra o sale del modo construccion (tambien F4)
        /bodega                    muestra los muebles guardados en tu bodega
        /residente <id>            (dueno) permite construir a un jugador
        /quitarresidente <id>      (dueno) le quita el permiso
        /muebleinfo                (admin) datos de la casa en la que estas
        /limpiarmuebles <idCasa>   (admin) devuelve todos los muebles de una casa a la bodega del dueno
]]

RPF = {}   -- API interna compartida con s_interact.lua (mismo recurso, mismo entorno)

local houses = {}      -- [pid] = { id, interior, loaded, loading, waiters, objs, rows, lights, members, removed, weight, unloadTimer }
local inside = {}      -- [player] = pid
local sessions = {}    -- [pid] = { player, cid, snap, placed, money, stock, startedAt, isOwner }
local actTick = {}     -- [player] = { tick, count }

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:prop:entered", false)
addEvent("rp:prop:left", false)
addEvent("rp:prop:sold", false)
addEvent("rp:prop:deleted", false)

addEvent("rp:furn:startBuild", true)
addEvent("rp:furn:endBuild", true)
addEvent("rp:furn:place", true)
addEvent("rp:furn:update", true)
addEvent("rp:furn:remove", true)
addEvent("rp:furn:hideProps", true)
addEvent("rp:furn:restoreProp", true)
addEvent("rp:furn:clearAll", true)
addEvent("rp:furn:bpList", true)
addEvent("rp:furn:bpSave", true)
addEvent("rp:furn:bpApply", true)
addEvent("rp:furn:bpDelete", true)
addEvent("rp:furn:memberAdd", true)
addEvent("rp:furn:memberRemove", true)
addEvent("rp:furn:requestStock", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function cidOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p, lvl) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= (lvl or 1) end

local function dimOf(pid) return FURN.DIMENSION_BASE + pid end
local function pidOfDim(dim) if dim and dim > FURN.DIMENSION_BASE then return dim - FURN.DIMENSION_BASE end end

local function num(v)
    v = tonumber(v)
    if v and v == v and v > -100000 and v < 100000 then return v end
end

local function round3(v) return math.floor(v * 1000 + (v >= 0 and 0.5 or -0.5)) / 1000 end

local function propInfo(pid)
    local ok, res = pcall(function() return exports.rp_properties:getPropertyInfo(pid) end)
    if ok and res then return res end
end

local function logf(pid, cid, action, key, amount)
    dbExec(db(), "INSERT INTO furniture_log (property_id, character_id, action, item_key, amount) VALUES (?, ?, ?, ?, ?)",
        pid, cid, action, key, amount or 0)
end

local function encodeState(t)
    if not t or next(t) == nil then return nil end
    local ok, s = pcall(toJSON, t, true)
    if ok and s and #s <= 250 then return s end
end

local function decodeState(s)
    if not s or s == "" then return {} end
    local ok, t = pcall(fromJSON, s)
    if ok and type(t) == "table" then return t end
    return {}
end

----------------------------------------------------------------
-- Objetos del mundo
----------------------------------------------------------------
local function publicData(row, state)
    return { id = row.id, key = row.item_key, color = row.color, mat = row.material, on = state.on, st = state.st }
end

local function updateLight(h, fid)
    local old = h.lights[fid]
    if isElement(old) then destroyElement(old) end
    h.lights[fid] = nil
    local row, obj = h.rows[fid], h.objs[fid]
    if not row or not isElement(obj) then return end
    local def = FURN_ITEMS[row.item_key]
    if not def or def.act ~= "light" or not row.stateT.on then return end
    local c = def.color or { 255, 235, 190 }
    if row.color then
        c = { math.floor(row.color / 65536) % 256, math.floor(row.color / 256) % 256, row.color % 256 }
    end
    local m = createMarker(row.x, row.y, row.z + 0.1, "corona", 1.6, c[1], c[2], c[3], 210)
    setElementInterior(m, h.interior)
    setElementDimension(m, dimOf(h.id))
    h.lights[fid] = m
end

local function spawnObject(h, row)
    local def = FURN_ITEMS[row.item_key]
    if not def then
        outputDebugString(("[rp_furniture] Mueble #%d con clave desconocida '%s' (no se crea)"):format(row.id, tostring(row.item_key)), 2)
        return
    end
    local old = h.objs[row.id]
    if isElement(old) then destroyElement(old) end
    local obj = createObject(def.model, row.x, row.y, row.z, row.rx, row.ry, row.rz)
    if not obj then return end
    setElementInterior(obj, h.interior)
    setElementDimension(obj, dimOf(h.id))
    setObjectScale(obj, row.sx, row.sy, row.sz)
    setObjectBreakable(obj, false)
    setElementFrozen(obj, true)
    row.stateT = row.stateT or decodeState(row.state)
    setElementData(obj, "rp:furn", publicData(row, row.stateT))
    h.objs[row.id] = obj
    updateLight(h, row.id)
    return obj
end

local function destroyObject(h, fid)
    if isElement(h.objs[fid]) then destroyElement(h.objs[fid]) end
    if isElement(h.lights[fid]) then destroyElement(h.lights[fid]) end
    h.objs[fid], h.lights[fid] = nil, nil
end

local function recalcWeight(h)
    local w = 0
    for _, row in pairs(h.rows) do
        local def = FURN_ITEMS[row.item_key]
        w = w + (def and def.w or 1)
    end
    h.weight = w
end

local function normalizeRow(r)
    return {
        id = tonumber(r.id), property_id = tonumber(r.property_id), item_key = r.item_key,
        x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
        rx = tonumber(r.rx) or 0, ry = tonumber(r.ry) or 0, rz = tonumber(r.rz) or 0,
        sx = tonumber(r.sx) or 1, sy = tonumber(r.sy) or 1, sz = tonumber(r.sz) or 1,
        color = tonumber(r.color), material = (r.material and r.material ~= "") and r.material or nil,
        state = r.state, placed_by = tonumber(r.placed_by),
    }
end

local function limitOf(h)
    local info = propInfo(h.id)
    return (info and FURN.LIMIT_BY_TYPE[info.type]) or FURN.LIMIT_DEFAULT
end

----------------------------------------------------------------
-- Carga y descarga de una casa
----------------------------------------------------------------
local function houseOf(pid)
    local h = houses[pid]
    if not h then
        h = { id = pid, loaded = false, loading = false, waiters = {}, objs = {}, rows = {}, lights = {},
              members = {}, removed = {}, weight = 0, interior = 0 }
        houses[pid] = h
    end
    return h
end

local function loadHouse(pid, cb)
    local h = houseOf(pid)
    if isTimer(h.unloadTimer) then killTimer(h.unloadTimer) end
    h.unloadTimer = nil
    if h.loaded then if cb then cb(h) end return end
    if cb then h.waiters[#h.waiters + 1] = cb end
    if h.loading then return end
    local info = propInfo(pid)
    if not info then h.waiters = {} return end
    h.loading, h.interior = true, info.interior

    local function fail(what)
        outputDebugString("[rp_furniture] Error al cargar " .. what .. " de la propiedad #" .. pid, 1)
        h.loading, h.waiters = false, {}
    end

    dbQuery(function(q1)
        local rows = dbPoll(q1, 0)
        if rows == false or rows == nil then return fail("muebles") end
        dbQuery(function(q2)
            local style = dbPoll(q2, 0)
            if style == false or style == nil then return fail("estilo") end
            dbQuery(function(q3)
                local members = dbPoll(q3, 0)
                if members == false or members == nil then return fail("residentes") end
                h.rows, h.members, h.removed = {}, {}, {}
                for _, r in ipairs(rows) do
                    local row = normalizeRow(r)
                    h.rows[row.id] = row
                    spawnObject(h, row)
                end
                for _, m in ipairs(members) do h.members[tonumber(m.character_id)] = m.role end
                if style[1] and style[1].removed_props and style[1].removed_props ~= "" then
                    local ok, list = pcall(fromJSON, style[1].removed_props)
                    if ok and type(list) == "table" then h.removed = list end
                end
                recalcWeight(h)
                h.loaded, h.loading = true, false
                local waiters = h.waiters
                h.waiters = {}
                for _, w in ipairs(waiters) do w(h) end
            end, db(), "SELECT character_id, role FROM property_members WHERE property_id = ?", pid)
        end, db(), "SELECT removed_props FROM property_style WHERE property_id = ?", pid)
    end, db(), "SELECT * FROM property_furniture WHERE property_id = ? ORDER BY id", pid)
end

local function unloadHouse(pid)
    local h = houses[pid]
    if not h then return end
    for fid in pairs(h.objs) do destroyObject(h, fid) end
    houses[pid] = nil
end

local function playersInside(pid)
    local list = {}
    for p, id in pairs(inside) do if id == pid and isElement(p) then list[#list + 1] = p end end
    return list
end

local function scheduleUnload(pid)
    local h = houses[pid]
    if not h or #playersInside(pid) > 0 or sessions[pid] then return end
    if isTimer(h.unloadTimer) then killTimer(h.unloadTimer) end
    h.unloadTimer = setTimer(function()
        if #playersInside(pid) == 0 and not sessions[pid] then unloadHouse(pid) end
    end, FURN.UNLOAD_DELAY, 1)
end

----------------------------------------------------------------
-- Permisos y zona
----------------------------------------------------------------
local function isOwnerOf(player, pid)
    local info = propInfo(pid)
    return info ~= nil and info.owner_id ~= nil and info.owner_id == cidOf(player)
end

local function canBuild(player, pid)
    local cid = cidOf(player)
    if not cid then return false end
    local info = propInfo(pid)
    if not info or not info.owner_id then return false end
    if info.owner_id == cid then return true, true end
    local h = houses[pid]
    return h ~= nil and h.members[cid] ~= nil, false
end

-- Zona de construccion: cilindro alrededor de la salida; la zona de la puerta queda libre
local function boundsOf(info)
    local r = FURN.RADIUS_BY_INTERIOR[info.interior] or FURN.RADIUS_DEFAULT
    return { x = info.x, y = info.y, z = info.z, r = r, zmin = info.z - FURN.Z_BELOW, zmax = info.z + FURN.Z_ABOVE, door = FURN.DOOR_CLEAR }
end

local function inBounds(info, t)
    local b = boundsOf(info)
    local dx, dy = t.x - b.x, t.y - b.y
    local d2 = dx * dx + dy * dy
    if d2 > b.r * b.r then return false, "Esta fuera de la zona de construccion." end
    if t.z < b.zmin or t.z > b.zmax then return false, "Esta fuera de la zona de construccion." end
    if d2 < b.door * b.door and math.abs(t.z - b.z) < 2.5 then return false, "No puedes bloquear la puerta de salida." end
    return true
end
RPF.inBounds = inBounds

local function parseTransform(d, def, base)
    local t = {}
    for _, k in ipairs({ "x", "y", "z" }) do
        t[k] = num(d[k])
        if t[k] == nil then
            if base then t[k] = base[k] else return nil end
        end
        t[k] = round3(t[k])
    end
    for _, k in ipairs({ "rx", "ry", "rz" }) do
        local v = num(d[k])
        if v == nil then v = base and base[k] or 0 end
        t[k] = round3(v % 360)
    end
    local smax = def.struct and FURN.SCALE_STRUCT_MAX or FURN.SCALE_MAX
    for _, k in ipairs({ "sx", "sy", "sz" }) do
        local v = num(d[k])
        if v == nil then v = base and base[k] or def[k] or 1 end
        t[k] = round3(math.max(FURN.SCALE_MIN, math.min(smax, v)))
    end
    return t
end

local function parseColor(v)
    if v == nil then return nil, false end
    v = num(v)
    if not v then return nil, false end
    if v < 0 then return nil, true end                        -- quitar tinte
    return math.floor(v) % 0x1000000, true
end

local function parseMaterial(v)
    if v == nil then return nil, false end
    if v == "" then return nil, true end
    if type(v) == "string" and FURN_MATERIAL_BY_ID[v] then return v, true end
    return nil, false
end

local function rateOk(player)
    local now = getTickCount()
    local a = actTick[player]
    if not a or now - a.tick > 1000 then a = { tick = now, count = 0 } actTick[player] = a end
    a.count = a.count + 1
    return a.count <= FURN.MAX_ACTIONS_PER_SEC
end

----------------------------------------------------------------
-- Dinero y bodega
----------------------------------------------------------------
local function charge(cid, amount, cb)
    if amount <= 0 then return cb(true) end
    dbQuery(function(q)
        local _, affected = dbPoll(q, 0)
        cb(affected ~= nil and affected > 0)
    end, db(), "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?", amount, cid, amount)
end

local function credit(cid, amount)
    if amount > 0 then dbExec(db(), "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", amount, cid) end
end

local function stockAdd(cid, key, n)
    dbExec(db(), "INSERT INTO character_furniture_stock (character_id, item_key, qty) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + ?",
        cid, key, n, n)
end

local function stockTake(cid, key, n, cb)
    dbQuery(function(q)
        local _, affected = dbPoll(q, 0)
        cb(affected ~= nil and affected > 0)
    end, db(), "UPDATE character_furniture_stock SET qty = qty - ? WHERE character_id = ? AND item_key = ? AND qty >= ?", n, cid, key, n)
end

local function loadStock(cid, cb)
    dbQuery(function(q)
        local rows = dbPoll(q, 0) or {}
        local stock = {}
        for _, r in ipairs(rows) do if tonumber(r.qty) > 0 then stock[r.item_key] = tonumber(r.qty) end end
        cb(stock)
    end, db(), "SELECT item_key, qty FROM character_furniture_stock WHERE character_id = ?", cid)
end

local function loadMoney(cid, cb)
    dbQuery(function(q)
        local r = (dbPoll(q, 0) or {})[1]
        cb(r and tonumber(r.bank_money) or 0)
    end, db(), "SELECT bank_money FROM characters WHERE id = ?", cid)
end

----------------------------------------------------------------
-- Estado enviado al cliente
----------------------------------------------------------------
local function memberList(h, cb)
    local ids = {}
    for cid in pairs(h.members) do ids[#ids + 1] = cid end
    if #ids == 0 then return cb({}) end
    local marks = string.rep("?,", #ids):sub(1, -2)
    dbQuery(function(q)
        local rows = dbPoll(q, 0) or {}
        local out = {}
        for _, r in ipairs(rows) do out[#out + 1] = { id = tonumber(r.id), name = (tostring(r.name):gsub("_", " ")) } end
        cb(out)
    end, db(), "SELECT id, name FROM characters WHERE id IN (" .. marks .. ")", unpack(ids))
end

local function pushSync(player, pid)
    local h, s = houses[pid], sessions[pid]
    if not h or not s or not isElement(player) then return end
    triggerClientEvent(player, "rp:furn:sync", resourceRoot, {
        weight = h.weight, limit = limitOf(h), money = s.money, stock = s.stock, count = (function() local n = 0 for _ in pairs(h.rows) do n = n + 1 end return n end)(),
    })
end

local function pushMembers(player, pid)
    local h = houses[pid]
    if not h then return end
    memberList(h, function(list)
        if isElement(player) then triggerClientEvent(player, "rp:furn:members", resourceRoot, list) end
    end)
end

----------------------------------------------------------------
-- Entrar y salir de una casa
----------------------------------------------------------------
local function endSession(pid, commit, silent)
    local s = sessions[pid]
    if not s then return end
    local h = houses[pid]
    local player = s.player
    sessions[pid] = nil

    local function finish()
        if isElement(player) then
            setElementFrozen(player, false)
            if not silent then triggerClientEvent(player, "rp:furn:buildOff", resourceRoot, commit) end
        end
        scheduleUnload(pid)
    end

    if commit or not h then return finish() end
    -- Cancelar: vuelve al estado inicial de la sesion
    local cid, snap, placed = s.cid, s.snap, s.placed

    -- 1) lo colocado en la sesion se retira (devuelve dinero o bodega)
    local toRemove = {}
    for fid in pairs(h.rows) do if not snap[fid] then toRemove[#toRemove + 1] = fid end end
    for _, fid in ipairs(toRemove) do
        local row = h.rows[fid]
        local info = placed[fid]
        if info then
            if info.stock then stockAdd(cid, row.item_key, 1) else credit(cid, info.paid) end
        end
        h.rows[fid] = nil
        destroyObject(h, fid)
        dbExec(db(), "DELETE FROM property_furniture WHERE id = ?", fid)
    end
    -- 2) lo guardado en la bodega durante la sesion se restaura si sigue disponible
    local pending = {}
    for fid, row in pairs(snap) do if not h.rows[fid] then pending[#pending + 1] = row end end
    local function restoreNext(i)
        local row = pending[i]
        if not row then
            -- 3) lo movido o pintado vuelve a su sitio
            for fid, old in pairs(snap) do
                local cur = h.rows[fid]
                if cur and (cur.x ~= old.x or cur.y ~= old.y or cur.z ~= old.z or cur.rx ~= old.rx or cur.ry ~= old.ry or cur.rz ~= old.rz
                    or cur.sx ~= old.sx or cur.sy ~= old.sy or cur.sz ~= old.sz or cur.color ~= old.color or cur.material ~= old.material) then
                    for k, v in pairs(old) do cur[k] = v end
                    if isElement(h.objs[fid]) then
                        setElementPosition(h.objs[fid], cur.x, cur.y, cur.z)
                        setElementRotation(h.objs[fid], cur.rx, cur.ry, cur.rz)
                        setObjectScale(h.objs[fid], cur.sx, cur.sy, cur.sz)
                        setElementData(h.objs[fid], "rp:furn", publicData(cur, cur.stateT or {}))
                    end
                    updateLight(h, fid)
                    dbExec(db(), "UPDATE property_furniture SET x=?, y=?, z=?, rx=?, ry=?, rz=?, sx=?, sy=?, sz=?, color=?, material=? WHERE id=?",
                        cur.x, cur.y, cur.z, cur.rx, cur.ry, cur.rz, cur.sx, cur.sy, cur.sz, cur.color, cur.material, fid)
                end
            end
            recalcWeight(h)
            return finish()
        end
        stockTake(cid, row.item_key, 1, function(ok)
            if ok then
                local copy = {}
                for k, v in pairs(row) do copy[k] = v end
                copy.stateT = decodeState(copy.state)
                dbQuery(function(q)
                    local res = dbPoll(q, 0)
                    if res ~= false and res ~= nil then
                        h.rows[copy.id] = copy
                        spawnObject(h, copy)
                    else
                        stockAdd(cid, row.item_key, 1)
                    end
                    restoreNext(i + 1)
                end, db(), "INSERT INTO property_furniture (id, property_id, item_key, x, y, z, rx, ry, rz, sx, sy, sz, color, material, state, placed_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    copy.id, pid, copy.item_key, copy.x, copy.y, copy.z, copy.rx, copy.ry, copy.rz, copy.sx, copy.sy, copy.sz, copy.color, copy.material, copy.state, copy.placed_by)
            else
                restoreNext(i + 1)
            end
        end)
    end
    restoreNext(1)
end
RPF.endSession = endSession

local function onEnter(player, pid)
    if inside[player] == pid then return end
    if not propInfo(pid) then return end
    inside[player] = pid
    loadHouse(pid, function(h)
        if not isElement(player) or inside[player] ~= pid then return end
        local can = canBuild(player, pid)
        triggerClientEvent(player, "rp:furn:enter", resourceRoot, pid, can and true or false, h.removed)
    end)
end

local function onLeave(player)
    local pid = inside[player]
    if not pid then return end
    local s = sessions[pid]
    if s and s.player == player then endSession(pid, true, true) end
    inside[player] = nil
    if isElement(player) then triggerClientEvent(player, "rp:furn:leave", resourceRoot) end
    scheduleUnload(pid)
end

addEventHandler("rp:prop:entered", root, function(id) onEnter(source, id) end)
addEventHandler("rp:prop:left", root, function() onLeave(source) end)

-- Respaldo: personajes que aparecen dentro de una casa al iniciar sesion, teletransportes de admin...
setTimer(function()
    for _, p in ipairs(getElementsByType("player")) do
        local cid = cidOf(p)
        local pid = cid and getElementInterior(p) ~= 0 and pidOfDim(getElementDimension(p)) or nil
        if pid ~= inside[p] then
            if inside[p] then onLeave(p) end
            if pid then onEnter(p, pid) end
        end
        -- red de seguridad: si el suelo desaparece y el jugador cae al vacio, vuelve a la salida
        if pid and inside[p] == pid then
            local info = propInfo(pid)
            local _, _, pz = getElementPosition(p)
            if info and pz < info.z - 20 then
                setElementPosition(p, info.x, info.y, info.z + 0.5)
                setElementVelocity(p, 0, 0, 0)
                notify(p, "Te devolvimos a la entrada. Si falta el suelo, usa /restaurarcasa.", "warning")
            end
        end
    end
end, 2000, 0)

addEventHandler("rp:onCharacterLogout", root, function() onLeave(source) end)
addEventHandler("onPlayerQuit", root, function()
    local pid = inside[source]
    if pid then
        local s = sessions[pid]
        if s and s.player == source then endSession(pid, true, true) end
        inside[source] = nil
        scheduleUnload(pid)
    end
    actTick[source] = nil
end)

----------------------------------------------------------------
-- Venta o borrado de la propiedad
----------------------------------------------------------------
addEventHandler("rp:prop:sold", root, function(pid, ownerCid)
    local function process(h)
        if sessions[pid] then endSession(pid, true) end
        -- todos los muebles vuelven a la bodega del vendedor
        local counts = {}
        for fid, row in pairs(h.rows) do counts[row.item_key] = (counts[row.item_key] or 0) + 1 end
        for key, n in pairs(counts) do
            if ownerCid then stockAdd(ownerCid, key, n) end
        end
        for fid in pairs(h.objs) do destroyObject(h, fid) end
        h.rows, h.members, h.removed, h.weight = {}, {}, {}, 0
        dbExec(db(), "DELETE FROM property_furniture WHERE property_id = ?", pid)
        dbExec(db(), "DELETE FROM property_members WHERE property_id = ?", pid)
        dbExec(db(), "DELETE FROM property_style WHERE property_id = ?", pid)
        logf(pid, ownerCid, "sold", nil, 0)
        for _, p in ipairs(playersInside(pid)) do triggerClientEvent(p, "rp:furn:props", resourceRoot, {}) end
        scheduleUnload(pid)
    end
    loadHouse(pid, process)
end)

addEventHandler("rp:prop:deleted", root, function(pid)
    if sessions[pid] then endSession(pid, true) end
    unloadHouse(pid)
end)

----------------------------------------------------------------
-- Sesion de construccion
----------------------------------------------------------------
local function activeSession(player)
    local pid = inside[player]
    local s = pid and sessions[pid]
    if not s or s.player ~= player then return end
    local h = houses[pid]
    if not h or not h.loaded then return end
    return s, pid, h
end

local function startBuild(player)
    local pid = inside[player]
    if not pid then return notify(player, "Debes estar dentro de tu propiedad para decorar.", "warning") end
    if getElementData(player, "rp:downed") or isPedDead(player) or isPedInVehicle(player) then return end
    local can, isOwner = canBuild(player, pid)
    if not can then return notify(player, "Solo el dueno o un residente puede decorar esta propiedad.", "error") end
    local cur = sessions[pid]
    if cur and cur.player ~= player and isElement(cur.player) then
        return notify(player, "Otra persona esta decorando ahora mismo.", "warning")
    end
    local info = propInfo(pid)
    if not info then return end
    local cid = cidOf(player)

    loadHouse(pid, function(h)
        if not isElement(player) or inside[player] ~= pid then return end
        if sessions[pid] and sessions[pid].player ~= player and isElement(sessions[pid].player) then return end
        loadStock(cid, function(stock)
            loadMoney(cid, function(money)
                if not isElement(player) or inside[player] ~= pid then return end
                local snap = {}
                for fid, row in pairs(h.rows) do
                    local c = {}
                    for k, v in pairs(row) do if k ~= "stateT" then c[k] = v end end
                    snap[fid] = c
                end
                sessions[pid] = { player = player, cid = cid, snap = snap, placed = {}, money = money, stock = stock,
                                  startedAt = getTickCount(), isOwner = isOwner and true or false }
                setElementFrozen(player, true)
                dbQuery(function(q)
                    local bps = {}
                    for _, r in ipairs(dbPoll(q, 0) or {}) do bps[#bps + 1] = { id = tonumber(r.id), name = r.name, interior = tonumber(r.interior) } end
                    memberList(h, function(members)
                        if not isElement(player) then return end
                        triggerClientEvent(player, "rp:furn:buildOn", resourceRoot, {
                            pid = pid, name = info.name, isOwner = isOwner and true or false,
                            bounds = boundsOf(info), weight = h.weight, limit = limitOf(h),
                            money = money, stock = stock, removed = h.removed, members = members, blueprints = bps,
                            interior = info.interior, stations = FURN_STATIONS,
                        })
                    end)
                end, db(), "SELECT id, name, interior FROM property_blueprints WHERE character_id = ? ORDER BY id", cid)
            end)
        end)
    end)
end

addEventHandler("rp:furn:startBuild", resourceRoot, function()
    if client then startBuild(client) end
end)

addEventHandler("rp:furn:endBuild", resourceRoot, function(commit)
    local player = client
    local s, pid = activeSession(player)
    if not s then return end
    endSession(pid, commit ~= false)
end)

addCommandHandler("decorar", function(player)
    if not cidOf(player) then return end
    triggerClientEvent(player, "rp:furn:toggle", resourceRoot)
end)

----------------------------------------------------------------
-- Colocar
----------------------------------------------------------------
local function ack(player, ref, ok, data)
    if isElement(player) then triggerClientEvent(player, "rp:furn:ack", resourceRoot, ref, ok, data) end
end

addEventHandler("rp:furn:place", resourceRoot, function(data)
    local player = client
    local s, pid, h = activeSession(player)
    if not s or type(data) ~= "table" then return end
    local ref = num(data.ref)
    if not rateOk(player) then return ack(player, ref, false, "Vas muy rapido.") end

    local def = FURN_ITEMS[tostring(data.key or "")]
    if not def then return ack(player, ref, false, "Mueble desconocido.") end
    local t = parseTransform(data, def)
    if not t then return ack(player, ref, false, "Posicion no valida.") end
    local info = propInfo(pid)
    if not info then return end
    local okb, why = inBounds(info, t)
    if not okb then return ack(player, ref, false, why) end

    local color = parseColor(data.color)
    local material = parseMaterial(data.mat)
    local fromStock = data.src == "stock"
    local cost = fromStock and 0 or def.price

    local w = def.w or 1
    if h.weight + w > limitOf(h) + 1e-6 then
        return ack(player, ref, false, "Alcanzaste el limite de objetos de esta propiedad.")
    end
    h.weight = h.weight + w   -- reserva mientras se cobra

    local function rollback(msg)
        h.weight = h.weight - w
        ack(player, ref, false, msg)
    end

    local function insert()
        dbQuery(function(q)
            local res, _, id = dbPoll(q, 0)
            if res == false or res == nil or not id then
                if fromStock then stockAdd(s.cid, def.key, 1) else credit(s.cid, cost) end
                return rollback("No se pudo guardar el mueble.")
            end
            if not houses[pid] then return end
            local row = { id = id, property_id = pid, item_key = def.key, x = t.x, y = t.y, z = t.z, rx = t.rx, ry = t.ry, rz = t.rz,
                          sx = t.sx, sy = t.sy, sz = t.sz, color = color, material = material, state = nil, stateT = {}, placed_by = s.cid }
            h.rows[id] = row
            spawnObject(h, row)
            s.placed[id] = { paid = cost, stock = fromStock }
            if fromStock then s.stock[def.key] = math.max(0, (s.stock[def.key] or 1) - 1) if s.stock[def.key] == 0 then s.stock[def.key] = nil end
            else s.money = s.money - cost end
            logf(pid, s.cid, fromStock and "place_stock" or "buy", def.key, cost)
            ack(player, ref, true, { id = id })
            pushSync(player, pid)
        end, db(), "INSERT INTO property_furniture (property_id, item_key, x, y, z, rx, ry, rz, sx, sy, sz, color, material, placed_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            pid, def.key, t.x, t.y, t.z, t.rx, t.ry, t.rz, t.sx, t.sy, t.sz, color, material, s.cid)
    end

    if fromStock then
        stockTake(s.cid, def.key, 1, function(ok)
            if not ok then return rollback("No tienes ese mueble en la bodega.") end
            insert()
        end)
    else
        charge(s.cid, cost, function(ok)
            if not ok then return rollback(("Necesitas $%d en tu cuenta bancaria."):format(cost)) end
            insert()
        end)
    end
end)

----------------------------------------------------------------
-- Mover, girar, escalar y pintar
----------------------------------------------------------------
local function canTouch(s, row)
    return s.isOwner or row.placed_by == s.cid
end

addEventHandler("rp:furn:update", resourceRoot, function(list)
    local player = client
    local s, pid, h = activeSession(player)
    if not s or type(list) ~= "table" or not rateOk(player) then return end
    local info = propInfo(pid)
    if not info then return end
    local count, applied, failed = 0, {}, nil

    for _, d in ipairs(list) do
        count = count + 1
        if count > FURN.MAX_BATCH then break end
        local fid = type(d) == "table" and num(d.id)
        local row = fid and h.rows[fid]
        local def = row and FURN_ITEMS[row.item_key]
        if row and def and canTouch(s, row) then
            local t = parseTransform(d, def, row)
            local okb, why = inBounds(info, t)
            if okb then
                for k, v in pairs(t) do row[k] = v end
                local c, hasC = parseColor(d.color)
                if hasC then row.color = c end
                local m, hasM = parseMaterial(d.mat)
                if hasM then row.material = m end
                local obj = h.objs[fid]
                if isElement(obj) then
                    setElementPosition(obj, row.x, row.y, row.z)
                    setElementRotation(obj, row.rx, row.ry, row.rz)
                    setObjectScale(obj, row.sx, row.sy, row.sz)
                    setElementData(obj, "rp:furn", publicData(row, row.stateT or {}))
                end
                updateLight(h, fid)
                dbExec(db(), "UPDATE property_furniture SET x=?, y=?, z=?, rx=?, ry=?, rz=?, sx=?, sy=?, sz=?, color=?, material=? WHERE id=?",
                    row.x, row.y, row.z, row.rx, row.ry, row.rz, row.sx, row.sy, row.sz, row.color, row.material, fid)
                applied[#applied + 1] = fid
            else
                failed = why
            end
        end
    end
    if failed then notify(player, failed, "warning") end
    triggerClientEvent(player, "rp:furn:updated", resourceRoot, applied)
end)

----------------------------------------------------------------
-- Retirar: bodega, vender o deshacer
----------------------------------------------------------------
local function nonEmptyContainers(ids, cb)
    if #ids == 0 then return cb({}) end
    local marks = string.rep("?,", #ids):sub(1, -2)
    dbQuery(function(q)
        local set = {}
        for _, r in ipairs(dbPoll(q, 0) or {}) do set[tonumber(r.furniture_id)] = true end
        cb(set)
    end, db(), "SELECT DISTINCT furniture_id FROM furniture_storage WHERE amount > 0 AND furniture_id IN (" .. marks .. ")", unpack(ids))
end

addEventHandler("rp:furn:remove", resourceRoot, function(list, mode)
    local player = client
    local s, pid, h = activeSession(player)
    if not s or type(list) ~= "table" or not rateOk(player) then return end
    if mode ~= "stock" and mode ~= "sell" and mode ~= "refund" then return end

    local ids = {}
    for _, v in ipairs(list) do
        local fid = num(v)
        if fid and h.rows[fid] and canTouch(s, h.rows[fid]) and #ids < FURN.MAX_BATCH then ids[#ids + 1] = fid end
    end
    nonEmptyContainers(ids, function(busy)
        if not isElement(player) or sessions[pid] ~= s then return end
        local removed, skippedBusy = {}, false
        for _, fid in ipairs(ids) do
            local row = h.rows[fid]
            local def = row and FURN_ITEMS[row.item_key]
            if row and def then
                if busy[fid] then
                    skippedBusy = true
                elseif mode == "refund" and not s.placed[fid] then
                    -- solo se deshace lo colocado en esta sesion
                elseif mode == "stock" or mode == "sell" or mode == "refund" then
                    local gain = 0
                    if mode == "stock" then
                        stockAdd(s.cid, row.item_key, 1)
                        s.stock[row.item_key] = (s.stock[row.item_key] or 0) + 1
                    elseif mode == "sell" then
                        gain = math.floor(def.price * (s.placed[fid] and FURN.SESSION_REFUND or FURN.SELL_REFUND))
                        credit(s.cid, gain)
                        s.money = s.money + gain
                    else
                        local info = s.placed[fid]
                        if info.stock then
                            stockAdd(s.cid, row.item_key, 1)
                            s.stock[row.item_key] = (s.stock[row.item_key] or 0) + 1
                        else
                            credit(s.cid, info.paid)
                            s.money = s.money + info.paid
                            gain = info.paid
                        end
                    end
                    -- vendido: ya no forma parte del estado inicial de la sesion
                    if mode == "sell" then s.snap[fid] = nil end
                    s.placed[fid] = nil
                    h.rows[fid] = nil
                    destroyObject(h, fid)
                    dbExec(db(), "DELETE FROM property_furniture WHERE id = ?", fid)
                    logf(pid, s.cid, mode, row.item_key, gain)
                    removed[#removed + 1] = fid
                end
            end
        end
        recalcWeight(h)
        if skippedBusy then notify(player, "Vacia el mueble antes de retirarlo.", "warning") end
        triggerClientEvent(player, "rp:furn:removed", resourceRoot, removed)
        pushSync(player, pid)
    end)
end)

addEventHandler("rp:furn:clearAll", resourceRoot, function()
    local player = client
    local s, pid, h = activeSession(player)
    if not s or not s.isOwner or not rateOk(player) then return end
    local ids = {}
    for fid in pairs(h.rows) do ids[#ids + 1] = fid end
    -- se procesa por tandas
    local function batch(from)
        local chunk = {}
        for i = from, math.min(from + FURN.MAX_BATCH - 1, #ids) do chunk[#chunk + 1] = ids[i] end
        if #chunk == 0 then return end
        nonEmptyContainers(chunk, function(busy)
            if sessions[pid] ~= s then return end
            for _, fid in ipairs(chunk) do
                local row = h.rows[fid]
                if row and not busy[fid] then
                    stockAdd(s.cid, row.item_key, 1)
                    s.stock[row.item_key] = (s.stock[row.item_key] or 0) + 1
                    s.placed[fid] = nil
                    h.rows[fid] = nil
                    destroyObject(h, fid)
                    dbExec(db(), "DELETE FROM property_furniture WHERE id = ?", fid)
                end
            end
            recalcWeight(h)
            batch(from + FURN.MAX_BATCH)
            if from + FURN.MAX_BATCH > #ids then
                logf(pid, s.cid, "clear", nil, #ids)
                triggerClientEvent(player, "rp:furn:reload", resourceRoot)
                pushSync(player, pid)
            end
        end)
    end
    batch(1)
end)

----------------------------------------------------------------
-- Ocultar objetos originales del interior
----------------------------------------------------------------
local function saveStyle(h)
    local json = toJSON(h.removed, true)
    dbExec(db(), "INSERT INTO property_style (property_id, removed_props) VALUES (?, ?) ON DUPLICATE KEY UPDATE removed_props = ?", h.id, json, json)
    for _, p in ipairs(playersInside(h.id)) do triggerClientEvent(p, "rp:furn:props", resourceRoot, h.removed) end
end

addEventHandler("rp:furn:hideProps", resourceRoot, function(list)
    local player = client
    local s, pid, h = activeSession(player)
    if not s or not s.isOwner or type(list) ~= "table" or not rateOk(player) then return end
    local info = propInfo(pid)
    if not info then return end
    local added, refused = 0, false
    for _, d in ipairs(list) do
        if type(d) == "table" and added < FURN.MAX_BATCH then
            local m, x, y, z = num(d.m), num(d.x), num(d.y), num(d.z)
            -- r > 0.5: oculta ese modelo en todo el radio (boton "Vaciar interior"); si no, solo el objeto de esa posicion
            local rad = num(d.r)
            rad = rad and math.max(0.3, math.min(60, rad)) or 0.4
            -- m = -1: comodin "todos los muebles originales" (boton Vaciar interior, solo con radio)
            -- Solo se pueden ocultar modelos de mobiliario: nunca paredes ni suelos (el personaje caeria al vacio)
            local wild = m == -1 and rad > 0.5
            if m and m >= 0 and not FURN_DEFAULT_PROP_IDS[math.floor(m)] then refused = true end
            if m and x and y and z and (wild or (m >= 0 and m <= 20000 and FURN_DEFAULT_PROP_IDS[math.floor(m)])) and #h.removed < FURN.MAX_HIDDEN_PROPS then
                local b = boundsOf(info)
                local dx, dy = x - b.x, y - b.y
                if dx * dx + dy * dy <= (b.r + 6) ^ 2 and z > b.zmin - 4 and z < b.zmax + 4 then
                    local dup = false
                    for _, e in ipairs(h.removed) do
                        if e.m == math.floor(m) then
                            -- un modelo ya oculto en todo el radio cubre cualquier objeto suelto de ese modelo
                            if (e.r or 0) > 0.5 and math.abs(e.x - x) < 8 and math.abs(e.y - y) < 8 then dup = true break end
                            if rad <= 0.5 and (e.r or 0) <= 0.5 and math.abs(e.x - x) < 0.3 and math.abs(e.y - y) < 0.3 and math.abs(e.z - z) < 0.3 then dup = true break end
                        end
                    end
                    if not dup then
                        local entry = { m = math.floor(m), x = round3(x), y = round3(y), z = round3(z) }
                        if rad > 0.5 then entry.r = round3(rad) end
                        h.removed[#h.removed + 1] = entry
                        added = added + 1
                    end
                end
            end
        end
    end
    if added > 0 then
        saveStyle(h)
        logf(pid, s.cid, "hide_props", nil, added)
    elseif refused then
        notify(player, "Eso es parte de la estructura de la casa (pared, suelo, puerta) y no se puede ocultar.", "warning")
    else
        notify(player, "No se pudo ocultar ese objeto.", "warning")
    end
end)

-- index: 0 = todo, un numero = esa entrada, o una lista de numeros (se quitan de mayor a menor)
addEventHandler("rp:furn:restoreProp", resourceRoot, function(index)
    local player = client
    local s, pid, h = activeSession(player)
    if not s or not s.isOwner or not rateOk(player) then return end
    if type(index) == "table" then
        local list = {}
        for _, v in ipairs(index) do
            local i = num(v)
            if i and h.removed[i] then list[#list + 1] = i end
        end
        table.sort(list, function(a, b) return a > b end)
        local last
        for _, i in ipairs(list) do
            if i ~= last then table.remove(h.removed, i) end
            last = i
        end
        if #list == 0 then return end
    else
        index = num(index)
        if not index then return end
        if index == 0 then
            h.removed = {}
        elseif h.removed[index] then
            table.remove(h.removed, index)
        else
            return
        end
    end
    saveStyle(h)
    logf(pid, s.cid, "restore_props", nil, type(index) == "table" and #index or index)
end)

-- Rescate: si algo oculto deja la casa sin suelo, el dueno (o un admin) lo restaura todo
addCommandHandler("restaurarcasa", function(player)
    local pid = inside[player] or pidOfDim(getElementDimension(player))
    if not pid then return notify(player, "Debes estar dentro de una propiedad.", "warning") end
    local info = propInfo(pid)
    if not info or not (isOwnerOf(player, pid) or isAdmin(player, 1)) then
        return notify(player, "Solo el dueno de la propiedad puede usar este comando.", "error")
    end
    loadHouse(pid, function(h)
        h.removed = {}
        saveStyle(h)
        for _, p in ipairs(playersInside(pid)) do triggerClientEvent(p, "rp:furn:props", resourceRoot, {}) end
        -- si cayo al vacio, vuelve a la salida
        local _, _, z = getElementPosition(player)
        if z < info.z - 10 then setElementPosition(player, info.x, info.y, info.z + 0.5) end
        logf(pid, cidOf(player), "restore_all_cmd", nil, 0)
        notify(player, "Se restauraron todos los objetos originales de la casa.", "success")
    end)
end)

----------------------------------------------------------------
-- Planos
----------------------------------------------------------------
local function sendBlueprints(player, cid)
    dbQuery(function(q)
        local bps = {}
        for _, r in ipairs(dbPoll(q, 0) or {}) do bps[#bps + 1] = { id = tonumber(r.id), name = r.name, interior = tonumber(r.interior) } end
        if isElement(player) then triggerClientEvent(player, "rp:furn:blueprints", resourceRoot, bps) end
    end, db(), "SELECT id, name, interior FROM property_blueprints WHERE character_id = ? ORDER BY id", cid)
end

addEventHandler("rp:furn:bpList", resourceRoot, function()
    local player = client
    local s = activeSession(player)
    if s then sendBlueprints(player, s.cid) end
end)

addEventHandler("rp:furn:bpSave", resourceRoot, function(name)
    local player = client
    local s, pid, h = activeSession(player)
    if not s or type(name) ~= "string" or not rateOk(player) then return end
    name = name:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #name < 2 or #name > 40 then return notify(player, "El nombre del plano debe tener entre 2 y 40 letras.", "warning") end
    local info = propInfo(pid)
    if not info then return end
    local entries = {}
    for _, row in pairs(h.rows) do
        entries[#entries + 1] = {
            k = row.item_key, x = round3(row.x - info.x), y = round3(row.y - info.y), z = round3(row.z - info.z),
            rx = row.rx, ry = row.ry, rz = row.rz, sx = row.sx, sy = row.sy, sz = row.sz, c = row.color, m = row.material,
        }
    end
    if #entries == 0 then return notify(player, "No hay muebles que guardar.", "warning") end
    dbQuery(function(q)
        local r = (dbPoll(q, 0) or {})[1]
        if r and tonumber(r.total) >= FURN.MAX_BLUEPRINTS then
            return notify(player, ("Solo puedes guardar %d planos. Borra alguno."):format(FURN.MAX_BLUEPRINTS), "warning")
        end
        dbQuery(function(q2)
            local res = dbPoll(q2, 0)
            if res == false or res == nil then return notify(player, "No se pudo guardar el plano.", "error") end
            notify(player, ("Plano '%s' guardado (%d muebles)."):format(name, #entries), "success")
            sendBlueprints(player, s.cid)
        end, db(), "INSERT INTO property_blueprints (character_id, name, interior, data) VALUES (?, ?, ?, ?)",
            s.cid, name, info.interior, toJSON(entries, true))
    end, db(), "SELECT COUNT(*) AS total FROM property_blueprints WHERE character_id = ?", s.cid)
end)

addEventHandler("rp:furn:bpDelete", resourceRoot, function(id)
    local player = client
    local s = activeSession(player)
    id = num(id)
    if not s or not id or not rateOk(player) then return end
    dbExec(db(), "DELETE FROM property_blueprints WHERE id = ? AND character_id = ?", id, s.cid)
    sendBlueprints(player, s.cid)
end)

addEventHandler("rp:furn:bpApply", resourceRoot, function(id, replace)
    local player = client
    local s, pid, h = activeSession(player)
    id = num(id)
    if not s or not id or not s.isOwner or not rateOk(player) then return end
    local info = propInfo(pid)
    if not info then return end

    dbQuery(function(q)
        local r = (dbPoll(q, 0) or {})[1]
        if not r then return notify(player, "Plano no encontrado.", "error") end
        if tonumber(r.interior) ~= info.interior then
            return notify(player, "Ese plano es de otro tipo de interior y no encaja aqui.", "warning")
        end
        local ok, entries = pcall(fromJSON, r.data)
        if not ok or type(entries) ~= "table" then return notify(player, "El plano esta danado.", "error") end

        local function run()
            -- valida cada entrada
            local plan, weight, cost = {}, h.weight, 0
            local stockLeft = {}
            for k, v in pairs(s.stock) do stockLeft[k] = v end
            for _, e in ipairs(entries) do
                local def = type(e) == "table" and FURN_ITEMS[tostring(e.k)]
                if def then
                    local t = parseTransform({ x = (num(e.x) or 0) + info.x, y = (num(e.y) or 0) + info.y, z = (num(e.z) or 0) + info.z,
                                               rx = e.rx, ry = e.ry, rz = e.rz, sx = e.sx, sy = e.sy, sz = e.sz }, def)
                    if t and inBounds(info, t) and weight + (def.w or 1) <= limitOf(h) then
                        weight = weight + (def.w or 1)
                        local fromStock = (stockLeft[def.key] or 0) > 0
                        if fromStock then stockLeft[def.key] = stockLeft[def.key] - 1 else cost = cost + def.price end
                        local c = parseColor(e.c)
                        local m = parseMaterial(e.m)
                        plan[#plan + 1] = { def = def, t = t, color = c, mat = m, stock = fromStock }
                    end
                end
            end
            if #plan == 0 then return notify(player, "Nada del plano cabe en esta casa.", "warning") end

            charge(s.cid, cost, function(paid)
                if not paid then return notify(player, ("Necesitas $%d para aplicar este plano."):format(cost), "error") end
                s.money = s.money - cost
                local placedN = 0
                local function nextItem(i)
                    local it = plan[i]
                    if not it then
                        recalcWeight(h)
                        logf(pid, s.cid, "blueprint", nil, cost)
                        notify(player, ("Plano aplicado: %d muebles."):format(placedN), "success")
                        triggerClientEvent(player, "rp:furn:reload", resourceRoot)
                        return pushSync(player, pid)
                    end
                    local function insert()
                        dbQuery(function(q3)
                            local res, _, newId = dbPoll(q3, 0)
                            if res ~= false and res ~= nil and newId and houses[pid] then
                                local t = it.t
                                local row = { id = newId, property_id = pid, item_key = it.def.key, x = t.x, y = t.y, z = t.z, rx = t.rx, ry = t.ry, rz = t.rz,
                                              sx = t.sx, sy = t.sy, sz = t.sz, color = it.color, material = it.mat, stateT = {}, placed_by = s.cid }
                                h.rows[newId] = row
                                spawnObject(h, row)
                                s.placed[newId] = { paid = it.stock and 0 or it.def.price, stock = it.stock }
                                placedN = placedN + 1
                            else
                                if it.stock then stockAdd(s.cid, it.def.key, 1) else credit(s.cid, it.def.price) s.money = s.money + it.def.price end
                            end
                            nextItem(i + 1)
                        end, db(), "INSERT INTO property_furniture (property_id, item_key, x, y, z, rx, ry, rz, sx, sy, sz, color, material, placed_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                            pid, it.def.key, it.t.x, it.t.y, it.t.z, it.t.rx, it.t.ry, it.t.rz, it.t.sx, it.t.sy, it.t.sz, it.color, it.mat, s.cid)
                    end
                    if it.stock then
                        stockTake(s.cid, it.def.key, 1, function(ok2)
                            if ok2 then
                                s.stock[it.def.key] = math.max(0, (s.stock[it.def.key] or 1) - 1)
                                if s.stock[it.def.key] == 0 then s.stock[it.def.key] = nil end
                                insert()
                            else
                                -- la bodega cambio: se compra
                                it.stock = false
                                charge(s.cid, it.def.price, function(ok3) if ok3 then s.money = s.money - it.def.price insert() else nextItem(i + 1) end end)
                            end
                        end)
                    else
                        insert()
                    end
                end
                nextItem(1)
            end)
        end

        if replace then
            -- lo que hay ahora pasa a la bodega y el plano lo usa primero
            local ids = {}
            for fid in pairs(h.rows) do ids[#ids + 1] = fid end
            nonEmptyContainers(ids, function(busy)
                for _, fid in ipairs(ids) do
                    local row = h.rows[fid]
                    if row and not busy[fid] then
                        stockAdd(s.cid, row.item_key, 1)
                        s.stock[row.item_key] = (s.stock[row.item_key] or 0) + 1
                        s.placed[fid] = nil
                        h.rows[fid] = nil
                        destroyObject(h, fid)
                        dbExec(db(), "DELETE FROM property_furniture WHERE id = ?", fid)
                    end
                end
                recalcWeight(h)
                -- da tiempo a que las escrituras de la bodega lleguen antes de leerla
                setTimer(function()
                    if sessions[pid] ~= s then return end
                    loadStock(s.cid, function(stock)
                        s.stock = stock
                        run()
                    end)
                end, 250, 1)
            end)
        else
            run()
        end
    end, db(), "SELECT interior, data FROM property_blueprints WHERE id = ? AND character_id = ?", id, s.cid)
end)

----------------------------------------------------------------
-- Residentes
----------------------------------------------------------------
addEventHandler("rp:furn:memberAdd", resourceRoot, function(targetId)
    local player = client
    local s, pid, h = activeSession(player)
    targetId = num(targetId)
    if not s or not s.isOwner or not targetId or not rateOk(player) then return end
    local target = exports.rp_ids:getPlayerFromId(targetId)
    local tcid = target and cidOf(target)
    if not tcid then return notify(player, "No hay ningun jugador con ese ID.", "error") end
    if tcid == s.cid then return notify(player, "Ya eres el dueno.", "warning") end
    local n = 0
    for _ in pairs(h.members) do n = n + 1 end
    if n >= FURN.MAX_MEMBERS and not h.members[tcid] then
        return notify(player, ("Maximo %d residentes."):format(FURN.MAX_MEMBERS), "warning")
    end
    dbExec(db(), "INSERT IGNORE INTO property_members (property_id, character_id, role) VALUES (?, ?, 'builder')", pid, tcid)
    h.members[tcid] = "builder"
    logf(pid, s.cid, "member_add", nil, tcid)
    notify(player, (getPlayerName(target):gsub("_", " ")) .. " ahora puede decorar tu propiedad.", "success")
    notify(target, "Ahora puedes decorar la propiedad de " .. (getPlayerName(player):gsub("_", " ")) .. ".", "info")
    if inside[target] == pid then triggerClientEvent(target, "rp:furn:enter", resourceRoot, pid, true, h.removed) end
    pushMembers(player, pid)
end)

addEventHandler("rp:furn:memberRemove", resourceRoot, function(cid)
    local player = client
    local s, pid, h = activeSession(player)
    cid = num(cid)
    if not s or not s.isOwner or not cid or not rateOk(player) then return end
    if not h.members[cid] then return end
    h.members[cid] = nil
    dbExec(db(), "DELETE FROM property_members WHERE property_id = ? AND character_id = ?", pid, cid)
    logf(pid, s.cid, "member_remove", nil, cid)
    -- si estaba construyendo, se cierra su sesion
    for _, p in ipairs(playersInside(pid)) do
        if cidOf(p) == cid then
            local ms = sessions[pid]
            if ms and ms.player == p then endSession(pid, true) end
            triggerClientEvent(p, "rp:furn:enter", resourceRoot, pid, false, h.removed)
        end
    end
    pushMembers(player, pid)
end)

addCommandHandler("residente", function(player, _, id)
    local pid = inside[player]
    if not pid or not isOwnerOf(player, pid) then return notify(player, "Debes estar dentro de tu propiedad.", "warning") end
    id = tonumber(id)
    local target = id and exports.rp_ids:getPlayerFromId(id)
    local tcid = target and cidOf(target)
    if not tcid then return notify(player, "Uso: /residente <id del jugador>", "warning") end
    loadHouse(pid, function(h)
        if tcid == cidOf(player) then return end
        local n = 0
        for _ in pairs(h.members) do n = n + 1 end
        if n >= FURN.MAX_MEMBERS and not h.members[tcid] then return notify(player, ("Maximo %d residentes."):format(FURN.MAX_MEMBERS), "warning") end
        dbExec(db(), "INSERT IGNORE INTO property_members (property_id, character_id, role) VALUES (?, ?, 'builder')", pid, tcid)
        h.members[tcid] = "builder"
        notify(player, (getPlayerName(target):gsub("_", " ")) .. " ahora puede decorar tu propiedad.", "success")
        notify(target, "Ahora puedes decorar la propiedad de " .. (getPlayerName(player):gsub("_", " ")) .. ".", "info")
        if inside[target] == pid then triggerClientEvent(target, "rp:furn:enter", resourceRoot, pid, true, h.removed) end
    end)
end)

addCommandHandler("quitarresidente", function(player, _, id)
    local pid = inside[player]
    if not pid or not isOwnerOf(player, pid) then return notify(player, "Debes estar dentro de tu propiedad.", "warning") end
    id = tonumber(id)
    local target = id and exports.rp_ids:getPlayerFromId(id)
    local tcid = target and cidOf(target)
    if not tcid then return notify(player, "Uso: /quitarresidente <id del jugador>", "warning") end
    loadHouse(pid, function(h)
        h.members[tcid] = nil
        dbExec(db(), "DELETE FROM property_members WHERE property_id = ? AND character_id = ?", pid, tcid)
        local ms = sessions[pid]
        if ms and ms.player == target then endSession(pid, true) end
        if inside[target] == pid then triggerClientEvent(target, "rp:furn:enter", resourceRoot, pid, false, h.removed) end
        notify(player, "Residente retirado.", "success")
    end)
end)

----------------------------------------------------------------
-- Bodega
----------------------------------------------------------------
addCommandHandler("bodega", function(player)
    local cid = cidOf(player)
    if not cid then return end
    loadStock(cid, function(stock)
        if not isElement(player) then return end
        local parts, total = {}, 0
        for key, qty in pairs(stock) do
            local def = FURN_ITEMS[key]
            parts[#parts + 1] = ("%dx %s"):format(qty, def and def.name or key)
            total = total + qty
        end
        table.sort(parts)
        if total == 0 then return notify(player, "Tu bodega de muebles esta vacia.", "info") end
        notify(player, ("Bodega (%d): %s"):format(total, table.concat(parts, ", "):sub(1, 220)), "info")
    end)
end)

addEventHandler("rp:furn:requestStock", resourceRoot, function()
    local player = client
    local s, pid = activeSession(player)
    if not s then return end
    loadStock(s.cid, function(stock)
        s.stock = stock
        pushSync(player, pid)
    end)
end)

----------------------------------------------------------------
-- Admin
----------------------------------------------------------------
addCommandHandler("muebleinfo", function(player)
    if not isAdmin(player, 1) then return end
    local pid = inside[player]
    local h = pid and houses[pid]
    if not h then return notify(player, "No estas dentro de una propiedad cargada.", "warning") end
    local n = 0
    for _ in pairs(h.rows) do n = n + 1 end
    local ms = 0
    for _ in pairs(h.members) do ms = ms + 1 end
    notify(player, ("Casa #%d: %d muebles, peso %.1f/%d, %d residentes, %d objetos ocultos, sesion: %s"):format(
        pid, n, h.weight, limitOf(h), ms, #h.removed, sessions[pid] and getPlayerName(sessions[pid].player) or "ninguna"), "info")
end)

addCommandHandler("limpiarmuebles", function(player, _, id)
    if not isAdmin(player, 3) then return end
    id = tonumber(id)
    local info = id and propInfo(id)
    if not info then return notify(player, "Uso: /limpiarmuebles <idCasa>", "warning") end
    loadHouse(id, function(h)
        if sessions[id] then endSession(id, true) end
        local owner = info.owner_id
        local n = 0
        for fid, row in pairs(h.rows) do
            if owner then stockAdd(owner, row.item_key, 1) end
            n = n + 1
        end
        for fid in pairs(h.objs) do destroyObject(h, fid) end
        h.rows, h.weight = {}, 0
        dbExec(db(), "DELETE FROM property_furniture WHERE property_id = ?", id)
        logf(id, nil, "admin_clear", nil, n)
        notify(player, ("Casa #%d: %d muebles devueltos a la bodega del dueno."):format(id, n), "success")
        scheduleUnload(id)
    end)
end)

----------------------------------------------------------------
-- API interna (s_interact.lua)
----------------------------------------------------------------
RPF.houses, RPF.inside, RPF.sessions = houses, inside, sessions
RPF.db, RPF.notify, RPF.cidOf, RPF.num = db, notify, cidOf, num
RPF.dimOf, RPF.propInfo, RPF.canBuild = dimOf, propInfo, canBuild
RPF.updateLight, RPF.publicData, RPF.encodeState = updateLight, publicData, encodeState
RPF.loadHouse, RPF.isOwnerOf = loadHouse, isOwnerOf
RPF.stockAdd, RPF.logf = stockAdd, logf

-- Cierra sesiones y descarga todo al parar el recurso
addEventHandler("onResourceStop", resourceRoot, function()
    for pid, s in pairs(sessions) do
        if isElement(s.player) then setElementFrozen(s.player, false) end
    end
end)

-- Si el recurso se reinicia con jugadores dentro, se vuelven a registrar
addEventHandler("onResourceStart", resourceRoot, function()
    local function init()
        for _, p in ipairs(getElementsByType("player")) do
            local cid = cidOf(p)
            local pid = cid and getElementInterior(p) ~= 0 and pidOfDim(getElementDimension(p)) or nil
            if pid then onEnter(p, pid) end
        end
    end
    if exports.rp_database:isReady() then setTimer(init, 500, 1) else addEventHandler("rp:onDatabaseReady", root, function() setTimer(init, 500, 1) end) end
end)
