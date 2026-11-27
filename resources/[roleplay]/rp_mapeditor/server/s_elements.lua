--[[
    rp_mapeditor / s_elements.lua
    Operaciones sobre los elementos del borrador. Todo llega del cliente por rp:me:op y se revalida:
    permiso builder, que el jugador esté editando ESE proyecto, límites, modelo y rangos (s_rules.lua),
    y bloqueos (no se toca lo que otro builder tiene seleccionado).

    rp:me:op("create", { { ref, etype, model, x, y, z, rx, ry, rz, props }, ... })
    rp:me:op("update", { { id, model?, x, y, z, rx, ry, rz, props }, ... })
    rp:me:op("delete", { id, ... })
    rp:me:op("select", { id, ... })   -- bloquea para los demás lo seleccionado
    Respuesta a todos los editores: rp:me:rows("add"|"upd"|"del", filas|ids, refs)
]]

addEvent("rp:me:op", true)

local lastOp = {}

local function sessionProject(p)
    local S = ME.sessions[p]
    local P = S and ME.projects[S.pid]
    if not P or not meCanBuild(p) then return nil end
    return P
end

local function lockedByOther(P, id, p)
    local owner = P.locks[id]
    return owner and owner ~= p and isElement(owner) and ME.sessions[owner] and ME.sessions[owner].pid == P.id
end

-- Inserta filas ya validadas. cb(filasCreadas, refs) cuando terminan todas
function meInsertRows(P, list, cb)
    local created, refs, pending = {}, {}, #list
    if pending == 0 then return cb(created, refs) end
    for _, item in ipairs(list) do
        local row, ref = item.row, item.ref
        dbQuery(function(qh)
            local _, _, id = dbPoll(qh, 0)
            if id and ME.projects[P.id] then
                row.id = id
                P.rows[id] = row
                P.count = P.count + 1
                if P.draft then P.draft[id] = meBuild(row, P.interior, meDraftDim(P), P.name, true) end
                created[#created + 1] = row
                if ref then refs[tostring(ref)] = id end
            end
            pending = pending - 1
            if pending == 0 then cb(created, refs) end
        end, meDb(), [[INSERT INTO mapedit_elements (project_id, etype, model, x, y, z, rx, ry, rz, interior, props)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            P.id, row.etype, row.model, row.x, row.y, row.z, row.rx, row.ry, row.rz, P.interior, mePropsToJSON(row.props))
    end
end

-- Borra todas las filas del borrador (cargar una versión, importar reemplazando)
function meClearRows(P)
    dbExec(meDb(), "DELETE FROM mapedit_elements WHERE project_id = ?", P.id)
    local ids = {}
    for id in pairs(P.rows) do ids[#ids + 1] = id end
    P.rows, P.count, P.locks = {}, 0, {}
    if P.draft then
        for _, el in pairs(P.draft) do if isElement(el) then destroyElement(el) end end
        P.draft = {}
    end
    return ids
end

local OPS = {}

OPS.create = function(p, P, list)
    if P.count + #list > MAPEDIT.MAX_ELEMENTS then
        return meNotify(p, ("Límite de %d elementos por proyecto."):format(MAPEDIT.MAX_ELEMENTS), "error")
    end
    local valid, firstErr = {}, nil
    for _, raw in ipairs(list) do
        local row, why = MapEditRules.element(raw, meModelOk)
        if row then valid[#valid + 1] = { row = row, ref = raw.ref } else firstErr = firstErr or why end
    end
    if firstErr then meNotify(p, "No se pudo colocar: " .. firstErr, "error") end
    meInsertRows(P, valid, function(created, refs)
        if #created > 0 then
            meBroadcast(P, "rp:me:rows", "add", created, refs)
            -- lo recién creado queda seleccionado (y bloqueado) por quien lo creó
            if isElement(p) then for _, row in ipairs(created) do P.locks[row.id] = p end end
            meBroadcast(P, "rp:me:locks", meLocksFor(P))
        end
    end)
end

OPS.update = function(p, P, list)
    local changed, firstErr = {}, nil
    for _, raw in ipairs(list) do
        local id = tonumber(type(raw) == "table" and raw.id)
        local cur = id and P.rows[id]
        if cur and not lockedByOther(P, id, p) then
            raw.etype = cur.etype
            if raw.model == nil then raw.model = cur.model end
            local row, why = MapEditRules.element(raw, meModelOk)
            if row then
                row.id = id
                P.rows[id] = row
                dbExec(meDb(), [[UPDATE mapedit_elements SET model = ?, x = ?, y = ?, z = ?, rx = ?, ry = ?, rz = ?, props = ?
                                 WHERE id = ? AND project_id = ?]],
                    row.model, row.x, row.y, row.z, row.rx, row.ry, row.rz, mePropsToJSON(row.props), id, P.id)
                meDraftRebuild(P, id)
                changed[#changed + 1] = row
            else
                firstErr = firstErr or why
            end
        elseif cur then
            firstErr = firstErr or "otro builder lo tiene seleccionado"
        end
    end
    if firstErr then meNotify(p, "No se pudo cambiar: " .. firstErr, "warning") end
    if #changed > 0 then meBroadcast(P, "rp:me:rows", "upd", changed) end
end

OPS.delete = function(p, P, list)
    local ids = {}
    for _, v in ipairs(list) do
        local id = tonumber(v)
        if id and P.rows[id] and not lockedByOther(P, id, p) then ids[#ids + 1] = id end
    end
    if #ids == 0 then return end
    for _, id in ipairs(ids) do
        dbExec(meDb(), "DELETE FROM mapedit_elements WHERE id = ? AND project_id = ?", id, P.id)
        P.rows[id] = nil
        P.count = P.count - 1
        P.locks[id] = nil
        if P.draft then
            if isElement(P.draft[id]) then destroyElement(P.draft[id]) end
            P.draft[id] = nil
        end
    end
    meBroadcast(P, "rp:me:rows", "del", ids)
    meBroadcast(P, "rp:me:locks", meLocksFor(P))
end

OPS.select = function(p, P, list)
    for id, owner in pairs(P.locks) do if owner == p then P.locks[id] = nil end end
    for _, v in ipairs(list) do
        local id = tonumber(v)
        if id and P.rows[id] and not lockedByOther(P, id, p) then P.locks[id] = p end
    end
    meBroadcast(P, "rp:me:locks", meLocksFor(P))
end

addEventHandler("rp:me:op", resourceRoot, function(kind, list)
    local p = client
    local P = sessionProject(p)
    if not P then return end
    local now = getTickCount()
    if lastOp[p] and now - lastOp[p] < MAPEDIT.OP_COOLDOWN_MS then
        if kind ~= "select" then meNotify(p, "Vas muy rápido: espera un momento.", "warning") end
        return
    end
    lastOp[p] = now
    local fn = OPS[tostring(kind)]
    if not fn or type(list) ~= "table" or #list == 0 then return end
    if #list > MAPEDIT.MAX_BATCH then
        return meNotify(p, ("Máximo %d elementos por operación."):format(MAPEDIT.MAX_BATCH), "warning")
    end
    fn(p, P, list)
end)

addEventHandler("onPlayerQuit", root, function() lastOp[source] = nil end)
