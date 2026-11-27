--[[
    rp_mapeditor / s_core.lua
    Estado compartido del servidor, permisos, utilidades de BD y auditoría.

    ME.projects[id] = {
        id, name, description, interior, dimension, settings, liveVersionId, liveVersion, maxVersion,
        createdName, updatedName,
        rows    = { [eid] = { id, etype, model, x, y, z, rx, ry, rz, props } },   -- borrador
        count   = n,
        draft   = { [eid] = elemento } | nil,   -- solo mientras alguien edita
        editors = { [player] = true },
        locks   = { [eid] = player },
        live    = { snap, elements = {}, removals = {}, markers = { [eid] = marker } } | nil,
    }
    ME.sessions[player] = { pid, saved = { x, y, z, rot, int, dim }, testing }
]]

ME = { projects = {}, byName = {}, sessions = {}, ready = false }

local SUPER_LEVEL = 3

function meDb() return exports.rp_database:getConnection() end
function meNotify(p, t, k) if isElement(p) then exports.rp_notify:notify(p, t, k or "info") end end
function meName(p) return isElement(p) and (getPlayerName(p):gsub("_", " ")) or "?" end

function meCanBuild(p)
    if not isElement(p) or getElementType(p) ~= "player" then return false end
    if not exports.rp_login:isPlayerLoggedIn(p) then return false end
    if (exports.rp_login:getPlayerAdminLevel(p) or 0) >= SUPER_LEVEL then return true end
    local ok, allowed = pcall(function() return exports.rp_adminpanel:hasPermission(p, "world.build") end)
    return ok and allowed == true
end

function meLog(p, project, action, details)
    local acc = isElement(p) and exports.rp_login:getPlayerAccountId(p) or nil
    local actor = isElement(p) and getPlayerName(p) or "consola"
    outputServerLog(("[rp_mapeditor] %s: %s %s %s"):format(actor, action, project and project.name or "-", tostring(details or "")))
    dbExec(meDb(), [[INSERT INTO mapedit_log (project_id, project_name, account_id, actor_name, action, details)
                     VALUES (NULLIF(?, 0), ?, NULLIF(?, 0), ?, ?, ?)]],
        project and project.id or 0, project and project.name or "", acc or 0, actor, tostring(action):sub(1, 24),
        tostring(details or ""):sub(1, 255))
end

-- Modelos válidos (catálogo generado en s_models.lua + vehículos y skins de MTA)
local objectSet, pedSet = {}, {}
for _, m in ipairs(MAPEDIT_MODELS or {}) do objectSet[m[1]] = true end
for _, id in ipairs(getValidPedModels and getValidPedModels() or {}) do pedSet[id] = true end

function meModelOk(etype, model)
    model = tonumber(model)
    if not model then return false end
    if etype == "object" then return objectSet[model] == true end
    if etype == "vehicle" then return model >= 400 and model <= 611 and (getVehicleNameFromModel(model) or "") ~= "" end
    if etype == "ped" then return pedSet[model] == true end
    if etype == "removal" then return model >= 0 and model <= 19999 end
    return true
end

-- props JSON <-> tabla
function mePropsToJSON(t) return toJSON(t or {}, true) end
function mePropsFromJSON(s)
    if type(s) ~= "string" or s == "" then return {} end
    local t = fromJSON(s)
    return type(t) == "table" and t or {}
end

function meRowFromDb(r)
    return {
        id = tonumber(r.id), etype = r.etype, model = tonumber(r.model) or 0,
        x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
        rx = tonumber(r.rx) or 0, ry = tonumber(r.ry) or 0, rz = tonumber(r.rz) or 0,
        props = mePropsFromJSON(r.props),
    }
end

function meCopyRow(row)
    return { id = row.id, etype = row.etype, model = row.model, x = row.x, y = row.y, z = row.z,
             rx = row.rx, ry = row.ry, rz = row.rz, props = fromJSON(toJSON(row.props or {})) or {} }
end

function meDraftDim(P) return MAPEDIT.DIMENSION_BASE + P.id end

-- Resumen de un proyecto para el navegador de proyectos
function meSummary(P)
    local editors = {}
    for p in pairs(P.editors) do if isElement(p) then editors[#editors + 1] = meName(p) end end
    return {
        id = P.id, name = P.name, description = P.description, interior = P.interior, dimension = P.dimension,
        count = P.count, live = P.liveVersion or false, versions = P.maxVersion or 0,
        createdName = P.createdName, updatedName = P.updatedName, editors = editors,
        liveCount = P.live and P.live.snap and #(P.live.snap.rows or {}) or 0,
    }
end

-- Avisa a todos los que editan un proyecto
function meBroadcast(P, event, ...)
    for p in pairs(P.editors) do
        if isElement(p) then triggerClientEvent(p, event, resourceRoot, ...) end
    end
end
