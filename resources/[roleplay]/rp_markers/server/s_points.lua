--[[
    rp_markers / s_points.lua  (servidor)
    Registro central de los puntos fijos con marcador (puertas, mostradores, Pay 'n' Spray,
    gasolineras...) para que los admins los muevan con el editor de rp_admin (ALT / M + clic derecho).

    El marcador lo sigue creando su recurso (createMarker normal): MTA destruye los elementos con el
    recurso que los crea, y si los creara rp_markers un `restart rp_markers` borraria todos. Lo que
    centraliza rp_markers es la POSICION:

      local x, y, z = exports.rp_markers:placePoint("loc1", cfg.x, cfg.y, cfg.z)
          Posicion efectiva del punto: la de la config o la que movio un admin. Tambien en el cliente
          (mismo export) para que los avisos "Pulsa E" usen el sitio nuevo.
      exports.rp_markers:registerMarker(marker, "loc1", { label = "Ammu-Nation", point = { x, y, z } })
          Lo apunta para la vista ALT y el editor. point = coordenadas del punto (el marcador suele ir
          1 m mas abajo); opciones: ownerSaves = true si el recurso guarda la posicion en su propia BD
          (gasolineras, policia...), level = nivel de admin minimo para moverlo.

    Al mover, se dispara el evento de servidor rp:markers:moved (recurso, clave, x, y, z, admin) con
    el punto nuevo, y en el cliente rp:markers:moved (recurso, clave). El recurso dueno reconstruye
    ese punto (y, si es ownerSaves, lo guarda en su BD como haria su /mover).

    La clave queda en el propio marcador (elementData) para rehidratar si rp_markers se reinicia.
    WORLD_TYPES de rp_admin: tipo "marker" (/nearbymarkers, /gotomarker, /resetmarker <id>).
]]

addEvent("rp:markers:moved")
addEvent("rp:markers:ready")   -- rp_markers arranco: los recursos vuelven a llamar a registerPoint

local POINTS_DATA = "rp:markers:points"   -- en resourceRoot, sincronizado: [clave completa] = { x, y, z, bx, by, bz }
local KEY_DATA = "rp:marker:key"          -- en cada marcador, solo servidor: info del registro
local BASE_TOLERANCE = 0.5

local rows = {}      -- [full] = { id, base = {x,y,z}, x, y, z, label }
local byId = {}      -- [id] = full
local seen = {}      -- [full] = base pedida con placePoint antes de cargar la BD
local markers = {}   -- [marker] = info
local loaded = false

local function db() return exports.rp_database:getConnection() end
local function log(msg, lvl) outputDebugString("[rp_markers] " .. msg, lvl or 3) end
local function dist(a, b) return getDistanceBetweenPoints3D(a[1], a[2], a[3], b[1], b[2], b[3]) end
local function callerName() return sourceResource and getResourceName(sourceResource) or nil end

local function publish()
    local out = {}
    for full, r in pairs(rows) do
        if r.x then out[full] = { r.x, r.y, r.z, r.base[1], r.base[2], r.base[3] } end
    end
    setElementData(resourceRoot, POINTS_DATA, out)
end

local function splitKey(full)
    local owner, key = full:match("^([^:]+):(.+)$")
    return owner, key
end

local function moved(full, x, y, z, admin)
    local owner, key = splitKey(full)
    triggerEvent("rp:markers:moved", root, owner, key, x, y, z, admin)
end

-- Fila en la BD (para el ID estable de /gotomarker): se crea la primera vez que se registra
local function ensureRow(full, label, base)
    if not loaded or rows[full] then return end
    rows[full] = { base = base, label = label }   -- reservado mientras llega el INSERT
    dbQuery(function(qh)
        local _, _, id = dbPoll(qh, 0)
        id = tonumber(id)
        if id and id > 0 then
            rows[full].id = id
            byId[id] = full
        else
            -- ya existia (otra carrera): leer su id
            dbQuery(function(q2)
                local r = (dbPoll(q2, 0) or {})[1]
                if r then rows[full].id = tonumber(r.id) byId[tonumber(r.id)] = full end
            end, db(), "SELECT id FROM marker_points WHERE marker_key = ?", full)
        end
    end, db(), "INSERT IGNORE INTO marker_points (marker_key, label, base_x, base_y, base_z) VALUES (?, ?, ?, ?, ?)",
        full, label, base[1], base[2], base[3])
end

-- La config cambio desde que se movio: vale la config y se olvida el movimiento
local function dropIfStale(full, base)
    local r = rows[full]
    if not r or not r.x or dist(r.base, base) <= BASE_TOLERANCE then return false end
    r.x, r.y, r.z, r.base = nil, nil, nil, base
    dbExec(db(), "UPDATE marker_points SET x = NULL, y = NULL, z = NULL, base_x = ?, base_y = ?, base_z = ? WHERE marker_key = ?",
        base[1], base[2], base[3], full)
    log(("%s: la config cambio, se descarta la posicion movida"):format(full), 2)
    publish()
    return true
end

----------------------------------------------------------------
-- Exports para los recursos
----------------------------------------------------------------
function placePoint(key, x, y, z)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    local owner = callerName()
    if not owner or type(key) ~= "string" or not (x and y and z) then return x, y, z end
    local full = owner .. ":" .. key
    local base = { x, y, z }
    seen[full] = base
    if dropIfStale(full, base) then return x, y, z end
    local r = rows[full]
    if r and r.x then return r.x, r.y, r.z end
    return x, y, z
end

function registerMarker(marker, key, opts)
    if not isElement(marker) or getElementType(marker) ~= "marker" or type(key) ~= "string" then return false end
    local owner = callerName()
    if not owner then return false end
    opts = type(opts) == "table" and opts or {}
    local mx, my, mz = getElementPosition(marker)
    local p = type(opts.point) == "table" and opts.point or {}
    local px, py, pz = tonumber(p[1] or p.x) or mx, tonumber(p[2] or p.y) or my, tonumber(p[3] or p.z) or mz
    local full = owner .. ":" .. key
    local info = {
        full = full, label = tostring(opts.label or key):sub(1, 64),
        ownerSaves = opts.ownerSaves == true, level = tonumber(opts.level) or 1,
        off = { mx - px, my - py, mz - pz },
    }
    markers[marker] = info
    setElementData(marker, KEY_DATA, info, false)
    ensureRow(full, info.label, seen[full] or { px, py, pz })
    return true
end

-- Punto fijo cuyo marcador crea el CLIENTE (solo visual: sedes de rp_jobs, agencia, pizzeria).
-- El servidor no tiene el elemento, asi que se apunta el punto: la vista ALT lo dibuja y el editor
-- lo mueve; el cliente del recurso rehace su marcador en rp:markers:moved (cliente).
-- opts: { label, point = { x, y, z }, interior, dimension, ownerSaves, level }.
-- Se pierde si rp_markers se reinicia: el recurso lo vuelve a registrar en rp:markers:ready.
local virtual = {}   -- [full] = info con x, y, z, interior, dimension
function registerPoint(key, opts)
    local owner = callerName()
    if not owner or type(key) ~= "string" or type(opts) ~= "table" or type(opts.point) ~= "table" then return false end
    local p = opts.point
    local x, y, z = tonumber(p[1] or p.x), tonumber(p[2] or p.y), tonumber(p[3] or p.z)
    if not (x and y and z) then return false end
    local full = owner .. ":" .. key
    virtual[full] = {
        full = full, label = tostring(opts.label or key):sub(1, 64),
        ownerSaves = opts.ownerSaves == true, level = tonumber(opts.level) or 1, off = { 0, 0, 0 },
        x = x, y = y, z = z, interior = tonumber(opts.interior) or 0, dimension = tonumber(opts.dimension) or 0,
    }
    ensureRow(full, virtual[full].label, seen[full] or { x, y, z })
    return true
end

----------------------------------------------------------------
-- Gramatica de rp_admin (WORLD_TYPES "marker") y editor
----------------------------------------------------------------
function adminElements()
    local list = {}
    for m, info in pairs(markers) do
        if not isElement(m) then
            markers[m] = nil
        else
            local r = rows[info.full]
            if r and r.id then
                local x, y, z = getElementPosition(m)
                local owner = splitKey(info.full)
                list[#list + 1] = { id = r.id, x = x, y = y, z = z, interior = getElementInterior(m),
                    dimension = getElementDimension(m), label = info.label .. (r.x and " (movido)" or ""),
                    info = ("%s · %s"):format(info.full, info.ownerSaves and ("guarda " .. owner) or "posicion en rp_markers"),
                    creator = "recurso " .. tostring(owner), noRot = true, element = m }
            end
        end
    end
    for full, v in pairs(virtual) do
        local r = rows[full]
        if r and r.id then
            local owner = splitKey(full)
            list[#list + 1] = { id = r.id, x = v.x, y = v.y, z = v.z, interior = v.interior, dimension = v.dimension,
                label = v.label .. (r.x and " (movido)" or ""), info = full .. " · marcador de cliente",
                creator = "recurso " .. tostring(owner), noRot = true }
        end
    end
    return list
end

function adminDelete(id)
    return false, ("los marcadores son de su recurso; /resetmarker %s lo devuelve a su sitio"):format(tostring(id))
end

local function infoOf(full)
    for m, info in pairs(markers) do
        if info.full == full and isElement(m) then return info end
    end
    return virtual[full]
end

-- x, y, z = posicion nueva del MARCADOR que movio el admin
function adminMove(id, _, x, y, z, _, admin)
    local full = byId[tonumber(id)]
    local info = full and infoOf(full)
    if not info then return false, "no existe" end
    if isElement(admin) and (exports.rp_login:getPlayerAdminLevel(admin) or 0) < info.level then
        return false, ("hace falta admin nivel %d"):format(info.level)
    end
    local px, py, pz = x - info.off[1], y - info.off[2], z - info.off[3]
    local r = rows[full]
    if not info.ownerSaves then
        r.x, r.y, r.z = px, py, pz
        if seen[full] then r.base = seen[full] end
        dbExec(db(), [[UPDATE marker_points SET x = ?, y = ?, z = ?, base_x = ?, base_y = ?, base_z = ?,
                       moved_by = ?, moved_at = NOW() WHERE marker_key = ?]],
            px, py, pz, r.base[1], r.base[2], r.base[3], isElement(admin) and getPlayerName(admin) or "sistema", full)
        publish()
    end
    -- Respuesta inmediata aunque el dueno tarde en reconstruir
    for m, i in pairs(markers) do
        if i.full == full and isElement(m) then setElementPosition(m, px + i.off[1], py + i.off[2], pz + i.off[3]) end
    end
    if virtual[full] then virtual[full].x, virtual[full].y, virtual[full].z = px, py, pz end
    moved(full, px, py, pz, admin)
    return true
end

addCommandHandler("resetmarker", function(player, _, id)
    if (exports.rp_login:getPlayerAdminLevel(player) or 0) < 1 then
        return exports.rp_notify:notify(player, "No tienes permiso para usar este comando.", "error")
    end
    local full = byId[tonumber(id) or -1]
    local r = full and rows[full]
    if not r then return exports.rp_notify:notify(player, "Uso: /resetmarker <id> (mira /nearbymarkers)", "warning") end
    if not r.x then return exports.rp_notify:notify(player, "Ese marcador ya esta en su sitio original.", "info") end
    r.x, r.y, r.z = nil, nil, nil
    dbExec(db(), "UPDATE marker_points SET x = NULL, y = NULL, z = NULL, moved_by = ?, moved_at = NOW() WHERE marker_key = ?",
        getPlayerName(player), full)
    publish()
    moved(full, r.base[1], r.base[2], r.base[3], player)
    exports.rp_notify:notify(player, ("Marcador #%d devuelto a su sitio."):format(r.id), "success")
end)

----------------------------------------------------------------
-- Arranque
----------------------------------------------------------------
local function load()
    dbQuery(function(qh)
        local list = dbPoll(qh, 0)
        if not list then return log("no se pudieron cargar los puntos movidos", 1) end
        loaded = true
        for _, r in ipairs(list) do
            local full = r.marker_key
            rows[full] = { id = tonumber(r.id), label = r.label, base = { tonumber(r.base_x), tonumber(r.base_y), tonumber(r.base_z) },
                x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) }
            if not rows[full].x then rows[full].y, rows[full].z = nil, nil end
            byId[tonumber(r.id)] = full
        end
        -- Lo que los recursos pidieron antes de cargar: comprobar config cambiada, crear filas y avisar
        for full, base in pairs(seen) do dropIfStale(full, base) end
        for m, info in pairs(markers) do
            if isElement(m) then ensureRow(info.full, info.label, seen[info.full] or { getElementPosition(m) }) end
        end
        for full, v in pairs(virtual) do ensureRow(full, v.label, seen[full] or { v.x, v.y, v.z }) end
        publish()
        for full, r in pairs(rows) do
            if r.x and seen[full] then moved(full, r.x, r.y, r.z) end
        end
    end, db(), "SELECT id, marker_key, label, base_x, base_y, base_z, x, y, z FROM marker_points")
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Rehidratar los marcadores ya registrados (rp_markers reiniciado en caliente)
    for _, m in ipairs(getElementsByType("marker")) do
        local info = getElementData(m, KEY_DATA)
        if type(info) == "table" and info.full then markers[m] = info end
    end
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
    -- Los puntos de marcadores de cliente (registerPoint) viven solo en memoria: que los registren otra vez
    triggerEvent("rp:markers:ready", root)
end)
