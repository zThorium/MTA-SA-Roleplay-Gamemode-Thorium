--[[
    rp_relojflores · servidor

    Reloj de Flores de Viña del Mar: monumento que colocan los admins (tabla flower_clocks). El servidor crea un ancla
    invisible (objeto congelado, sin colisión, data rp:flowerclock) y cada cliente (c_relojflores.lua) monta encima
    los modelos de tools/build_flower_clock.py como edificios y mueve las agujas con la hora.

    Admin: /crearrelojflores (alias /makeflowerclock) lo pone delante del admin mirándolo. Moverlo con el
    editor de rp_admin (ALT o M + clic derecho) y listar, ir y borrar con la gramática Owl:
    /nearbyflowerclocks, /gotoflowerclock <id>, /delflowerclock <id>, /delthisflowerclock.
]]

addEvent("rp:onDatabaseReady", false)

local clocks = {} -- [id] = { row, obj }

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function spawnClock(row)
    local obj = createObject(FLOWERCLOCK.PLACEHOLDER, row.x, row.y, row.z, 0, 0, row.rot)
    if not obj then return end
    setElementFrozen(obj, true)
    -- ancla invisible: el cliente monta el reloj con createBuilding (pasto con la colisión, flores, LOD)
    setElementAlpha(obj, 0)
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, row.interior)
    setElementDimension(obj, row.dimension)
    setElementData(obj, "rp:flowerclock", row.id)
    clocks[row.id] = { row = row, obj = obj }
end

local function destroyClock(id)
    local c = clocks[id]
    if c and isElement(c.obj) then destroyElement(c.obj) end
    clocks[id] = nil
end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return outputDebugString("[rp_relojflores] no se pudieron leer los relojes", 1) end
        for id in pairs(clocks) do destroyClock(id) end
        for _, r in ipairs(rows) do
            spawnClock({ id = tonumber(r.id), x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z),
                rot = tonumber(r.rot) or 0, interior = tonumber(r.interior) or 0, dimension = tonumber(r.dimension) or 0 })
        end
        outputDebugString(("[rp_relojflores] %d relojes de flores cargados"):format(#rows), 3)
    end, db(), "SELECT id, x, y, z, rot, interior, dimension FROM flower_clocks")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

-- /crearrelojflores: delante del admin, con la esfera mirándolo
local function create(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    if isPedInVehicle(player) then return notify(player, "Bájate del vehículo para colocarlo.", "warning") end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local d = FLOWERCLOCK.FORWARD
    local fx, fy, fz = x - math.sin(math.rad(rot)) * d, y + math.cos(math.rad(rot)) * d, z - FLOWERCLOCK.DROP
    -- el frente del modelo mira a -Y: con el mismo giro que el admin, la esfera lo mira a él
    local frot = rot % 360
    local int, dim = getElementInterior(player), getElementDimension(player)
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId then return isElement(player) and notify(player, "No se pudo guardar el reloj.", "error") end
        spawnClock({ id = insertId, x = fx, y = fy, z = fz, rot = frot, interior = int, dimension = dim })
        if isElement(player) then
            notify(player, ("Reloj de flores #%d colocado. Ajústalo con ALT + clic derecho (editor); bórralo con /delflowerclock %d.")
                :format(insertId, insertId), "success")
        end
    end, db(), "INSERT INTO flower_clocks (x, y, z, rot, interior, dimension) VALUES (?, ?, ?, ?, ?, ?)",
        fx, fy, fz, frot, int, dim)
end
addCommandHandler("crearrelojflores", create)
addCommandHandler("makeflowerclock", create)

----------------------------------------------------------------
-- Gramática Owl de rp_admin (WORLD_TYPES "flowerclock") y editor de la vista ALT
----------------------------------------------------------------
function adminElements()
    local list = {}
    for id, c in pairs(clocks) do
        local r = c.row
        list[#list + 1] = { id = id, x = r.x, y = r.y, z = r.z, interior = r.interior, dimension = r.dimension,
            label = "Reloj de flores", rot = r.rot, element = c.obj }
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    if not id or not clocks[id] then return false, "no existe" end
    dbExec(db(), "DELETE FROM flower_clocks WHERE id = ?", id)
    destroyClock(id)
    return true
end

function adminMove(id, _, x, y, z, rot)
    id = tonumber(id)
    local c = id and clocks[id]
    if not c then return false, "no existe" end
    local r = c.row
    r.x, r.y, r.z, r.rot = x, y, z, (tonumber(rot) or r.rot) % 360
    dbExec(db(), "UPDATE flower_clocks SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", r.x, r.y, r.z, r.rot, id)
    destroyClock(id)
    spawnClock(r)
    return true
end
