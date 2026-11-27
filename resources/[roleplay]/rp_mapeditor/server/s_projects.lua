--[[
    rp_mapeditor / s_projects.lua
    Carga de proyectos, borrador (se crea al entrar el primer editor y se destruye al salir el último),
    publicación por versiones, mapa vivo y exports para otros recursos.
]]

----------------------------------------------------------------
-- Borrador
----------------------------------------------------------------
function meDraftSpawn(P)
    if P.draft then return end
    P.draft = {}
    for id, row in pairs(P.rows) do
        P.draft[id] = meBuild(row, P.interior, meDraftDim(P), P.name, true)
    end
end

function meDraftDestroy(P)
    if not P.draft then return end
    for _, el in pairs(P.draft) do if isElement(el) then destroyElement(el) end end
    P.draft = nil
end

function meDraftRebuild(P, id)
    if not P.draft then return end
    local old = P.draft[id]
    if isElement(old) then destroyElement(old) end
    local row = P.rows[id]
    P.draft[id] = row and meBuild(row, P.interior, meDraftDim(P), P.name, true) or nil
end

----------------------------------------------------------------
-- Mapa vivo
----------------------------------------------------------------
local function liveRowsOfType(P, etype)
    local out = {}
    if not (P.live and P.live.snap) then return out end
    for _, row in ipairs(P.live.snap.rows or {}) do
        if row.etype == etype then out[#out + 1] = row end
    end
    return out
end

-- Los quitados se solapan entre mapas: tras restaurar uno se vuelven a aplicar los de los demás
local function reapplyAllRemovals()
    for _, P in pairs(ME.projects) do
        if P.live and P.live.snap then
            for _, row in ipairs(liveRowsOfType(P, "removal")) do meApplyRemoval(row, P.live.snap.interior) end
        end
    end
end

local function markerKey(P, row) return ("mapedit:%d:%d"):format(P.id, row.id or 0) end

function meLiveClear(P)
    if not P.live then return end
    for _, el in pairs(P.live.elements) do if isElement(el) then destroyElement(el) end end
    local snap = P.live.snap
    P.live = nil
    if snap then
        local any = false
        for _, row in ipairs(snap.rows or {}) do
            if row.etype == "removal" then meRestoreRemoval(row, snap.interior) any = true end
        end
        if any then reapplyAllRemovals() end
    end
end

function meLiveBuild(P, snap)
    meLiveClear(P)
    P.live = { snap = snap, elements = {} }
    for _, row in ipairs(snap.rows or {}) do
        if row.etype == "removal" then
            meApplyRemoval(row, snap.interior)
        elseif row.etype ~= "point" then
            local el = meBuild(row, snap.interior, snap.dimension, P.name, false)
            if el then
                P.live.elements[#P.live.elements + 1] = el
                if row.etype == "marker" then
                    pcall(function()
                        exports.rp_markers:registerMarker(el, markerKey(P, row), {
                            label = ("Mapa %s: %s"):format(P.name, row.props.label or "marcador"),
                            point = { row.x, row.y, row.z }, ownerSaves = true,
                        })
                    end)
                end
            end
        end
    end
end

-- Ajustes de los mapas vivos fuera del mundo abierto: el cliente los aplica en esa dimensión
-- También publica la lista de edificios quitados: el cliente de un builder los vuelve a quitar al
-- salir del editor (al salir se restauran los del borrador, que pueden coincidir con estos)
function meSyncLiveSettings()
    local list, rem = {}, {}
    for _, P in pairs(ME.projects) do
        local s = P.live and P.live.snap
        if s and s.dimension ~= 0 and s.settings and next(s.settings) then
            list[#list + 1] = { dim = s.dimension, int = s.interior, settings = s.settings }
        end
        if s then
            for _, row in ipairs(s.rows or {}) do
                if row.etype == "removal" then
                    rem[#rem + 1] = { row.model, row.props.lod or 0, row.props.radius or 1, row.x, row.y, row.z, s.interior }
                end
            end
        end
    end
    setElementData(resourceRoot, "rp:me:live", list)
    setElementData(resourceRoot, "rp:me:liveRem", rem)
end

----------------------------------------------------------------
-- Snapshots y versiones
----------------------------------------------------------------
function meSnapshot(P)
    local rows = {}
    for _, row in pairs(P.rows) do rows[#rows + 1] = meCopyRow(row) end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return { v = 1, name = P.name, interior = P.interior, dimension = P.dimension, settings = P.settings or {}, rows = rows }
end

local function decodeSnap(s)
    local t = type(s) == "string" and fromJSON(s)
    if type(t) ~= "table" or type(t.rows) ~= "table" then return nil end
    t.interior, t.dimension = tonumber(t.interior) or 0, tonumber(t.dimension) or 0
    t.settings = type(t.settings) == "table" and t.settings or {}
    return t
end

function mePublish(player, P, cb)
    local snap = meSnapshot(P)
    local version = (P.maxVersion or 0) + 1
    local json = toJSON(snap, true)
    dbQuery(function(qh)
        local _, _, vid = dbPoll(qh, 0)
        if not vid then
            meNotify(player, "No se pudo guardar la versión (BD).", "error")
            if cb then cb(false) end
            return
        end
        P.maxVersion, P.liveVersionId, P.liveVersion = version, vid, version
        dbExec(meDb(), "UPDATE mapedit_projects SET live_version_id = ?, updated_name = ? WHERE id = ?", vid, meName(player), P.id)
        meLiveBuild(P, snap)
        meSyncLiveSettings()
        meLog(player, P, "publish", ("v%d, %d elementos"):format(version, #snap.rows))
        if cb then cb(true, version) end
    end, meDb(), [[INSERT INTO mapedit_versions (project_id, version, snapshot, element_count, published_by)
                   VALUES (?, ?, ?, ?, ?)]], P.id, version, json, #snap.rows, meName(player))
end

function meUnpublish(player, P)
    meLiveClear(P)
    P.liveVersionId, P.liveVersion = nil, nil
    dbExec(meDb(), "UPDATE mapedit_projects SET live_version_id = NULL, updated_name = ? WHERE id = ?", meName(player), P.id)
    meSyncLiveSettings()
    meLog(player, P, "unpublish", "")
end

-- Publica una versión antigua tal cual (vuelta atrás)
function mePublishVersion(player, P, vid, cb)
    dbQuery(function(qh)
        local r = (dbPoll(qh, 0) or {})[1]
        local snap = r and decodeSnap(r.snapshot)
        if not snap then if cb then cb(false) end return end
        P.liveVersionId, P.liveVersion = tonumber(r.id), tonumber(r.version)
        dbExec(meDb(), "UPDATE mapedit_projects SET live_version_id = ?, updated_name = ? WHERE id = ?", P.liveVersionId, meName(player), P.id)
        meLiveBuild(P, snap)
        meSyncLiveSettings()
        meLog(player, P, "publishver", "v" .. tostring(r.version))
        if cb then cb(true, P.liveVersion) end
    end, meDb(), "SELECT id, version, snapshot FROM mapedit_versions WHERE id = ? AND project_id = ?", vid, P.id)
end

-- Lee el snapshot de una versión (para cargarla en el borrador)
function meReadVersion(P, vid, cb)
    dbQuery(function(qh)
        local r = (dbPoll(qh, 0) or {})[1]
        cb(r and decodeSnap(r.snapshot), r and tonumber(r.version))
    end, meDb(), "SELECT version, snapshot FROM mapedit_versions WHERE id = ? AND project_id = ?", vid, P.id)
end

function meListVersions(P, cb)
    dbQuery(function(qh)
        local out = {}
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            out[#out + 1] = { id = tonumber(r.id), version = tonumber(r.version), count = tonumber(r.element_count),
                              by = r.published_by, at = tostring(r.created_at), live = tonumber(r.id) == P.liveVersionId }
        end
        cb(out)
    end, meDb(), [[SELECT id, version, element_count, published_by, created_at FROM mapedit_versions
                   WHERE project_id = ? ORDER BY version DESC LIMIT ?]], P.id, MAPEDIT.MAX_VERSIONS_LISTED)
end

----------------------------------------------------------------
-- Carga al arrancar
----------------------------------------------------------------
local function addProject(r)
    local P = {
        id = tonumber(r.id), name = r.name, description = r.description or "",
        interior = tonumber(r.interior) or 0, dimension = tonumber(r.dimension) or 0,
        settings = MapEditRules.settings(r.settings and fromJSON(r.settings) or {}),
        liveVersionId = tonumber(r.live_version_id), createdName = r.created_name or "", updatedName = r.updated_name or "",
        rows = {}, count = 0, editors = {}, locks = {}, maxVersion = tonumber(r.max_version) or 0,
    }
    ME.projects[P.id] = P
    ME.byName[P.name:lower()] = P
    return P
end

function meRemoveProject(P)
    meLiveClear(P)
    meDraftDestroy(P)
    ME.projects[P.id] = nil
    ME.byName[P.name:lower()] = nil
    meSyncLiveSettings()
end

function meNewProject(r) return addProject(r) end

local function load()
    local db = meDb()
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do addProject(r) end
        dbQuery(function(qh2)
            for _, r in ipairs(dbPoll(qh2, 0) or {}) do
                local P = ME.projects[tonumber(r.project_id)]
                if P then
                    local row = meRowFromDb(r)
                    P.rows[row.id] = row
                    P.count = P.count + 1
                end
            end
            dbQuery(function(qh3)
                for _, r in ipairs(dbPoll(qh3, 0) or {}) do
                    local P = ME.projects[tonumber(r.project_id)]
                    local snap = P and decodeSnap(r.snapshot)
                    if snap then
                        P.liveVersion = tonumber(r.version)
                        meLiveBuild(P, snap)
                    end
                end
                meSyncLiveSettings()
                ME.ready = true
                local n = 0
                for _ in pairs(ME.projects) do n = n + 1 end
                outputDebugString(("[rp_mapeditor] %d proyectos cargados"):format(n), 3)
            end, db, [[SELECT v.project_id, v.version, v.snapshot FROM mapedit_versions v
                       JOIN mapedit_projects p ON p.live_version_id = v.id]])
        end, db, "SELECT * FROM mapedit_elements ORDER BY id")
    end, db, [[SELECT p.*, (SELECT MAX(version) FROM mapedit_versions v WHERE v.project_id = p.id) AS max_version
               FROM mapedit_projects p]])
end

addEventHandler("onResourceStart", resourceRoot, function()
    setElementData(resourceRoot, "rp:me:live", {})
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- los elementos se destruyen solos con el recurso; los edificios quitados hay que devolverlos
    for _, P in pairs(ME.projects) do
        if P.live and P.live.snap then
            for _, row in ipairs(liveRowsOfType(P, "removal")) do meRestoreRemoval(row, P.live.snap.interior) end
        end
    end
end)

----------------------------------------------------------------
-- Marcadores publicados movidos con el editor de rp_admin (regla 12, ownerSaves)
----------------------------------------------------------------
addEvent("rp:markers:moved", false)
addEventHandler("rp:markers:moved", root, function(resName, key, x, y, z, admin)
    if resName ~= getResourceName(resource) and resName ~= resource then return end
    local pid, rid = tostring(key):match("^mapedit:(%d+):(%d+)$")
    local P = pid and ME.projects[tonumber(pid)]
    if not (P and P.live and P.live.snap) then return end
    rid = tonumber(rid)
    for _, row in ipairs(P.live.snap.rows) do
        if row.id == rid then row.x, row.y, row.z = x, y, z end
    end
    -- el borrador sigue al publicado si la fila existe allí
    local drow = P.rows[rid]
    if drow then
        drow.x, drow.y, drow.z = x, y, z
        dbExec(meDb(), "UPDATE mapedit_elements SET x = ?, y = ?, z = ? WHERE id = ? AND project_id = ?", x, y, z, rid, P.id)
        meDraftRebuild(P, rid)
        meBroadcast(P, "rp:me:rows", "upd", { drow })
    end
    if P.liveVersionId then
        dbExec(meDb(), "UPDATE mapedit_versions SET snapshot = ? WHERE id = ?", toJSON(P.live.snap, true), P.liveVersionId)
    end
    meLiveBuild(P, P.live.snap)
    meLog(admin, P, "markermove", ("#%d -> %.1f, %.1f, %.1f"):format(rid, x, y, z))
end)

----------------------------------------------------------------
-- Exports para otros recursos
----------------------------------------------------------------
function getPublishedMaps()
    local out = {}
    for _, P in pairs(ME.projects) do
        local s = P.live and P.live.snap
        if s then
            out[#out + 1] = { name = P.name, version = P.liveVersion, interior = s.interior, dimension = s.dimension, count = #s.rows }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function isMapPublished(name)
    local P = ME.byName[tostring(name or ""):lower()]
    return P ~= nil and P.live ~= nil
end

-- Puntos con nombre de un mapa publicado: { { name, x, y, z, rot, interior, dimension }, ... }
function getMapPoints(name)
    local P = ME.byName[tostring(name or ""):lower()]
    local out = {}
    if not (P and P.live and P.live.snap) then return out end
    local s = P.live.snap
    for _, row in ipairs(liveRowsOfType(P, "point")) do
        out[#out + 1] = { name = row.props.name, x = row.x, y = row.y, z = row.z, rot = row.rz, interior = s.interior, dimension = s.dimension }
    end
    return out
end
