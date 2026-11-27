--[[
    rp_mapeditor / s_commands.lua
    /mapeditor (navegador de proyectos) y /mapas, y las acciones de proyecto que pide el panel
    por rp:me:cmd(tipo, a, b, c): crear, abrir, salir, duplicar, borrar, datos, ajustes,
    publicar, despublicar, versiones, exportar e importar .map.
]]

addEvent("rp:me:cmd", true)

local SUPER_LEVEL = 3
local lastCmd = {}

local function isSuper(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= SUPER_LEVEL end

local function sendBrowser(p)
    local list = {}
    for _, P in pairs(ME.projects) do list[#list + 1] = meSummary(P) end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    local S = ME.sessions[p]
    triggerClientEvent(p, "rp:me:browser", resourceRoot, list, { super = isSuper(p), current = S and S.pid or false })
end

local function refreshBrowsers()
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "rp:me:browsing") then sendBrowser(p) end
    end
end

local function editing(p, P) local S = ME.sessions[p] return S and S.pid == P.id end

local function reloadEditors(P)
    local rows = {}
    for _, row in pairs(P.rows) do rows[#rows + 1] = row end
    meBroadcast(P, "rp:me:reload", meSummary(P), P.settings or {}, rows, meLocksFor(P))
end

-- Inserta filas sin validar (importar, cargar versión, duplicar) en tandas
local function insertRaw(p, P, raws, cb)
    local valid, bad = {}, 0
    for _, raw in ipairs(raws) do
        local row = MapEditRules.element(raw, meModelOk)
        if row then valid[#valid + 1] = { row = row } else bad = bad + 1 end
    end
    local room = MAPEDIT.MAX_ELEMENTS - P.count
    if #valid > room then
        bad = bad + (#valid - room)
        for i = #valid, room + 1, -1 do valid[i] = nil end
    end
    meInsertRows(P, valid, function(created) cb(#created, bad) end)
end

local function createProject(p, name, description, interior, dimension, cb)
    local clean, why = MapEditRules.projectName(name)
    if not clean then return meNotify(p, why, "warning") end
    if ME.byName[clean:lower()] then return meNotify(p, "Ya existe un proyecto con ese nombre.", "warning") end
    local n = 0
    for _ in pairs(ME.projects) do n = n + 1 end
    if n >= MAPEDIT.MAX_PROJECTS then return meNotify(p, "Se alcanzó el máximo de proyectos.", "error") end
    description = tostring(description or ""):gsub("[%c<>]", ""):sub(1, 255)
    local acc = exports.rp_login:getPlayerAccountId(p) or 0
    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        if not id then return meNotify(p, "No se pudo crear el proyecto (¿nombre repetido?).", "error") end
        local P = meNewProject({ id = id, name = clean, description = description, interior = interior, dimension = dimension,
                                 created_name = meName(p), updated_name = meName(p) })
        meLog(p, P, "create", "")
        cb(P)
    end, meDb(), [[INSERT INTO mapedit_projects (name, description, interior, dimension, settings, created_by, created_name, updated_name)
                   VALUES (?, ?, ?, ?, '{}', NULLIF(?, 0), ?, ?)]], clean, description, interior, dimension, acc, meName(p), meName(p))
end

local CMD = {}

CMD.list = function(p)
    setElementData(p, "rp:me:browsing", true, false)
    sendBrowser(p)
end

CMD.closebrowser = function(p) removeElementData(p, "rp:me:browsing") end

CMD.create = function(p, name, description)
    createProject(p, name, description, getElementInterior(p), 0, function(P)
        meNotify(p, ("Proyecto «%s» creado."):format(P.name), "success")
        refreshBrowsers()
        if isElement(p) then meEnter(p, P) end
    end)
end

CMD.open = function(p, pid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P then return meNotify(p, "Ese proyecto ya no existe.", "error") end
    meEnter(p, P)
    refreshBrowsers()
end

CMD.leave = function(p)
    meLeave(p)
    refreshBrowsers()
end

CMD.duplicate = function(p, pid, newName)
    local src = ME.projects[tonumber(pid) or -1]
    if not src then return end
    createProject(p, newName, src.description, src.interior, src.dimension, function(P)
        P.settings = src.settings
        dbExec(meDb(), "UPDATE mapedit_projects SET settings = ? WHERE id = ?", toJSON(P.settings or {}, true), P.id)
        local raws = {}
        for _, row in pairs(src.rows) do raws[#raws + 1] = meCopyRow(row) end
        insertRaw(p, P, raws, function(n)
            meNotify(p, ("Proyecto duplicado como «%s» (%d elementos)."):format(P.name, n), "success")
            meLog(p, P, "duplicate", "desde " .. src.name)
            refreshBrowsers()
        end)
    end)
end

CMD.delete = function(p, pid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P then return end
    if P.live then return meNotify(p, "Despublica el mapa antes de borrarlo.", "warning") end
    if next(P.editors) then return meNotify(p, "Alguien está editando ese proyecto.", "warning") end
    if not isSuper(p) and P.createdName ~= meName(p) then
        return meNotify(p, "Solo quien lo creó o un super admin puede borrarlo.", "error")
    end
    dbExec(meDb(), "DELETE FROM mapedit_projects WHERE id = ?", P.id)
    meLog(p, P, "delete", ("%d elementos"):format(P.count))
    meRemoveProject(P)
    meNotify(p, ("Proyecto «%s» borrado."):format(P.name), "success")
    refreshBrowsers()
end

-- Nombre, descripción, interior y dimensión de publicación
CMD.meta = function(p, pid, data)
    local P = ME.projects[tonumber(pid) or -1]
    if not P or type(data) ~= "table" then return end
    local name = P.name
    if data.name and data.name ~= P.name then
        local clean, why = MapEditRules.projectName(data.name)
        if not clean then return meNotify(p, why, "warning") end
        local other = ME.byName[clean:lower()]
        if other and other ~= P then return meNotify(p, "Ya existe un proyecto con ese nombre.", "warning") end
        name = clean
    end
    local interior = math.floor(math.max(0, math.min(255, tonumber(data.interior) or P.interior)))
    local dimension = math.floor(math.max(0, math.min(65535, tonumber(data.dimension) or P.dimension)))
    if dimension >= MAPEDIT.DIMENSION_BASE and dimension < MAPEDIT.DIMENSION_BASE + 1000 then
        return meNotify(p, "Esa dimensión es de borradores; elige otra.", "warning")
    end
    local description = data.description ~= nil and tostring(data.description):gsub("[%c<>]", ""):sub(1, 255) or P.description
    ME.byName[P.name:lower()] = nil
    local intChanged = interior ~= P.interior
    P.name, P.description, P.interior, P.dimension, P.updatedName = name, description, interior, dimension, meName(p)
    ME.byName[P.name:lower()] = P
    dbExec(meDb(), "UPDATE mapedit_projects SET name = ?, description = ?, interior = ?, dimension = ?, updated_name = ? WHERE id = ?",
        P.name, P.description, P.interior, P.dimension, P.updatedName, P.id)
    if intChanged then
        dbExec(meDb(), "UPDATE mapedit_elements SET interior = ? WHERE project_id = ?", interior, P.id)
        if P.draft then meDraftDestroy(P) meDraftSpawn(P) end
        for ed in pairs(P.editors) do if isElement(ed) then setElementInterior(ed, interior) end end
    end
    meLog(p, P, "meta", ("int %d, dim %d"):format(interior, dimension))
    meBroadcast(P, "rp:me:project", meSummary(P))
    meNotify(p, "Datos del proyecto guardados (se aplican al publicar).", "success")
    refreshBrowsers()
end

CMD.settings = function(p, pid, data)
    local P = ME.projects[tonumber(pid) or -1]
    if not P or not editing(p, P) then return end
    P.settings = MapEditRules.settings(data)
    dbExec(meDb(), "UPDATE mapedit_projects SET settings = ?, updated_name = ? WHERE id = ?", toJSON(P.settings, true), meName(p), P.id)
    meBroadcast(P, "rp:me:settings", P.settings)
end

CMD.publish = function(p, pid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P then return end
    if P.count == 0 then return meNotify(p, "El proyecto está vacío.", "warning") end
    mePublish(p, P, function(ok, version)
        if not ok then return end
        meNotify(p, ("«%s» publicado (versión %d). Ya lo ven todos."):format(P.name, version), "success")
        meBroadcast(P, "rp:me:project", meSummary(P))
        refreshBrowsers()
    end)
end

CMD.unpublish = function(p, pid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P or not P.live then return end
    meUnpublish(p, P)
    meNotify(p, ("«%s» ya no está en el mundo."):format(P.name), "success")
    meBroadcast(P, "rp:me:project", meSummary(P))
    refreshBrowsers()
end

CMD.versions = function(p, pid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P then return end
    meListVersions(P, function(list)
        if isElement(p) then triggerClientEvent(p, "rp:me:versions", resourceRoot, P.id, list) end
    end)
end

CMD.pubversion = function(p, pid, vid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P or not tonumber(vid) then return end
    mePublishVersion(p, P, tonumber(vid), function(ok, version)
        if not ok then return meNotify(p, "No se encontró esa versión.", "error") end
        meNotify(p, ("Publicada otra vez la versión %d de «%s»."):format(version, P.name), "success")
        meBroadcast(P, "rp:me:project", meSummary(P))
        CMD.versions(p, pid)
        refreshBrowsers()
    end)
end

-- Reemplaza el borrador por una versión publicada
CMD.loadversion = function(p, pid, vid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P or not editing(p, P) or not tonumber(vid) then return end
    meReadVersion(P, tonumber(vid), function(snap, version)
        if not snap or not ME.projects[P.id] then return meNotify(p, "No se encontró esa versión.", "error") end
        meClearRows(P)
        P.settings = MapEditRules.settings(snap.settings)
        dbExec(meDb(), "UPDATE mapedit_projects SET settings = ? WHERE id = ?", toJSON(P.settings, true), P.id)
        insertRaw(p, P, snap.rows, function(n)
            reloadEditors(P)
            meLog(p, P, "loadversion", ("v%d, %d elementos"):format(version or 0, n))
            meNotify(p, ("Borrador reemplazado por la versión %d."):format(version or 0), "success")
        end)
    end)
end

CMD.export = function(p, pid)
    local P = ME.projects[tonumber(pid) or -1]
    if not P then return end
    local text = meExportMap(P)
    local path = meWriteExport(P, text)
    meLog(p, P, "export", ("%d elementos"):format(P.count))
    triggerClientEvent(p, "rp:me:exported", resourceRoot, P.name, text, path or false)
end

CMD.import = function(p, pid, text, replace)
    local P = ME.projects[tonumber(pid) or -1]
    if not P or not editing(p, P) then return meNotify(p, "Abre el proyecto antes de importar.", "warning") end
    local raws, skipped = meParseMap(text)
    if not raws then return meNotify(p, "No se pudo importar: " .. tostring(skipped), "error") end
    if replace == true or replace == "1" then meClearRows(P) end
    insertRaw(p, P, raws, function(n, bad)
        reloadEditors(P)
        meLog(p, P, "import", ("%d elementos, %d descartados"):format(n, bad + (skipped or 0)))
        local msg = ("Importados %d elementos."):format(n)
        if bad + (skipped or 0) > 0 then msg = msg .. (" %d descartados (modelo o posición no válidos, o límite)."):format(bad + (skipped or 0)) end
        meNotify(p, msg, n > 0 and "success" or "warning")
    end)
end

addEventHandler("rp:me:cmd", resourceRoot, function(kind, a, b, c)
    local p = client
    if not meCanBuild(p) then return meNotify(p, "No tienes permiso para usar el editor de mapas.", "error") end
    if not ME.ready then return meNotify(p, "El editor de mapas aún está cargando.", "warning") end
    local now = getTickCount()
    local heavy = kind == "import" or kind == "export" or kind == "publish" or kind == "duplicate"
    if lastCmd[p] and now - lastCmd[p] < (heavy and 1500 or 200) then return end
    lastCmd[p] = now
    local fn = CMD[tostring(kind)]
    if fn then fn(p, a, b, c) end
end)

----------------------------------------------------------------
-- Comandos de chat
----------------------------------------------------------------
local function openEditor(p)
    if not meCanBuild(p) then return meNotify(p, "No tienes permiso para usar este comando.", "error") end
    if not ME.ready then return meNotify(p, "El editor de mapas aún está cargando.", "warning") end
    triggerClientEvent(p, "rp:me:openBrowser", resourceRoot)
    CMD.list(p)
end
addCommandHandler("mapeditor", openEditor)
addCommandHandler("editormapas", openEditor)

addCommandHandler("mapas", function(p)
    if not meCanBuild(p) then return meNotify(p, "No tienes permiso para usar este comando.", "error") end
    local list = getPublishedMaps()
    outputChatBox(("Mapas publicados (%d):"):format(#list), p, 255, 200, 60)
    for _, m in ipairs(list) do
        outputChatBox(("  %s · v%d · %d elementos · int %d, dim %d"):format(m.name, m.version or 0, m.count, m.interior, m.dimension),
            p, 220, 220, 220)
    end
end)

addEventHandler("onPlayerQuit", root, function() lastCmd[source] = nil end)
