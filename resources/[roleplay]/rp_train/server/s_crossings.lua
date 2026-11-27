--[[
    rp_train · cruces a nivel (servidor)

    Cada fila de rail_crossings es una barrera (poste + brazo) que pone un admin junto a la vía.
    Cuando un tren ocupa el tramo del cruce: el brazo baja y el elemento rp_railcrossing pasa a
    closed = true (campanas en el cliente; rp_citizens detiene el tráfico IA). Cuando la cola del
    tren lo deja atrás, el brazo sube y closed = false.
]]

addEvent("rp:onDatabaseReady", false)

local crossings = {} -- [id] = { row, d, base, arm, el, closed }

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function armRotY(c, closed) return closed and 90 * c.row.side or 0 end

local function spawnCrossing(row)
    local c = { row = row, closed = false }
    c.d = TrainTrack.project(row.x, row.y)
    c.base = createObject(TRAIN.BARRIER_BASE_MODEL, row.x, row.y, row.z - 1, 0, 0, row.rot)
    c.arm = createObject(TRAIN.BARRIER_MODEL, row.x, row.y, row.z - 0.3, 0, armRotY(c, false), row.rot)
    c.el = createElement("rp_railcrossing", "rp_railcrossing_" .. row.id)
    setElementPosition(c.el, row.x, row.y, row.z)
    setElementData(c.el, "closed", false)
    for _, e in ipairs({ c.base, c.arm, c.el }) do
        if e then setElementInterior(e, row.interior) setElementDimension(e, row.dimension) end
    end
    crossings[row.id] = c
end

local function destroyCrossing(id)
    local c = crossings[id]
    if not c then return end
    for _, e in ipairs({ c.base, c.arm, c.el }) do if isElement(e) then destroyElement(e) end end
    crossings[id] = nil
end

local function setClosed(c, closed)
    if c.closed == closed then return end
    c.closed = closed
    setElementData(c.el, "closed", closed)
    if not isElement(c.arm) then return end
    stopObject(c.arm)
    local _, ry = getElementRotation(c.arm)
    local delta = (armRotY(c, closed) - ry + 180) % 360 - 180
    local x, y, z = getElementPosition(c.arm)
    moveObject(c.arm, TRAIN.BARRIER_MOVE_MS, x, y, z, 0, delta, 0, "InOutQuad")
end

-- La llama el paso de simulación de s_train.lua
function updateCrossings()
    for _, c in pairs(crossings) do
        setClosed(c, isTrackOccupied(c.d, TRAIN.CROSSING_APPROACH, TRAIN.CROSSING_CLEAR))
    end
end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return outputDebugString("[rp_train] no se pudieron leer los cruces", 1) end
        for id in pairs(crossings) do destroyCrossing(id) end
        for _, row in ipairs(rows) do spawnCrossing(row) end
        outputDebugString(("[rp_train] %d barreras de cruce cargadas"):format(#rows), 3)
    end, db(), "SELECT id, x, y, z, rot, side, interior, dimension FROM rail_crossings")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

-- /crearbarrera [inv]: barrera en tu posición, el brazo apunta hacia donde miras. "inv" baja hacia el otro lado.
addCommandHandler("crearbarrera", function(player, _, flag)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local _, dist = TrainTrack.project(x, y)
    if dist > TRAIN.CROSSING_SNAP then
        return notify(player, ("Estás a %d m de la vía: ponte junto al cruce."):format(dist), "warning")
    end
    local side = flag == "inv" and -1 or 1
    local int, dim = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId then return notify(player, "No se pudo guardar la barrera.", "error") end
        spawnCrossing({ id = insertId, x = x, y = y, z = z, rot = rot, side = side, interior = int, dimension = dim })
        setElementPosition(player, x, y, z + 1.5)
        notify(player, ("Barrera #%d creada (a %.1f m de la vía)."):format(insertId, dist), "success")
    end, db(), "INSERT INTO rail_crossings (x, y, z, rot, side, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?)",
        x, y, z, rot, side, int, dim)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbycrossings, /gotocrossing, /delcrossing...).
-- kind = "booth" | "sign": boleterías y carteles LED (s_stations.lua); sin kind, barreras.
function adminElements(kind)
    if kind then return stationAdminElements(kind) end
    local list = {}
    for id, e in pairs(crossings) do
        local row = e.row
        if row then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = row.interior, dimension = row.dimension, label = e.closed and "Barrera (cerrada)" or "Barrera (abierta)",
                rot = tonumber(row.rot) or 0, element = e.base }
        end
    end
    return list
end

function adminDelete(id, kind)
    if kind then return stationAdminDelete(id, kind) end
    id = tonumber(id)
    if not id or not crossings[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM rail_crossings WHERE id = ?", id)
    destroyCrossing(id)
    return true
end

-- Mover desde el editor de rp_admin (vista ALT). Con `kind` es una pieza de estacion (s_stations.lua)
function adminMove(id, kind, x, y, z, rot)
    if kind then return stationAdminMove(id, kind, x, y, z, rot) end
    id = tonumber(id)
    local c = id and crossings[id]
    if not c then return false, "no existe" end
    local row = c.row
    row.x, row.y, row.z, row.rot = x, y, z, rot
    dbExec(db(), "UPDATE rail_crossings SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", x, y, z, rot, id)
    destroyCrossing(id)
    spawnCrossing(row)
    return true
end

addCommandHandler("borrarbarrera", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrarbarrera <id> (mira /barreras)", "warning") end
    notify(player, ("Barrera #%d eliminada."):format(id), "success")
end)

addCommandHandler("barreras", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local px, py = getElementPosition(player)
    local n = 0
    for id, c in pairs(crossings) do
        n = n + 1
        outputChatBox(("#%d  %s  a %d m"):format(id, c.closed and "cerrada" or "abierta",
            getDistanceBetweenPoints2D(px, py, c.row.x, c.row.y)), player, 200, 200, 200)
    end
    if n == 0 then notify(player, "No hay barreras. Crea una con /crearbarrera junto a un cruce.", "info") end
end)
