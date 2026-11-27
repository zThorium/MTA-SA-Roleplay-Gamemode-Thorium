--[[
    rp_train · estaciones (servidor)

    Boleterías y carteles LED que colocan los admins (tabla train_fixtures). Cada uno se asigna a la
    estación más cercana (a menos de TRAIN.STATION_SNAP) al crearlo.
    - Boletería: empleado (ped) que vende boletos de tren con el menú de rp_shops (addTempShop):
      precio, cobro y peso del inventario los valida rp_shops. El boleto se gasta al subir (s_passengers.lua).
    - Cartel LED: elemento rp_trainsign (data station, name, rot) que dibuja el cliente (c_stations.lua)
      con la llegada estimada que publica s_train.lua en rp:train:eta.

    Admin: /crearboleteria y /crearcartel crean (el cartel se abre en el editor 3D, c_signeditor.lua);
    /editarcartel [id] lo vuelve a colocar; listar, ir y borrar con la gramática Owl de rp_admin
    (/nearbyticketbooths, /gototicketbooth, /delticketbooth <id>, /nearbytrainsigns, /deltrainsign <id>...).
]]

addEvent("rp:onDatabaseReady", false)
addEvent("rp:train:signSave", true)

local fixtures = {} -- [id] = { row, ped, shopId, el }
local KIND_NAME = { booth = "Boletería", sign = "Cartel LED" }

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function greeting()
    return ("Boleto de tren: $%d. Pulsa E para comprarlo; luego súbete con E junto a un vagón cuando el tren esté en el andén.")
        :format(TRAIN.TICKET_PRICE)
end

local function registerShop(f)
    if not isElement(f.ped) then return end
    local name = ("%s · %s"):format(TRAIN.BOOTH_NAME, getStationName(f.row.station) or "Estación")
    local ok, id = pcall(function()
        return exports.rp_shops:addTempShop(f.ped, name, { [TRAIN.TICKET_ITEM] = TRAIN.TICKET_PRICE }, greeting())
    end)
    f.shopId = ok and id or nil
    if not f.shopId then outputDebugString("[rp_train] rp_shops no registró la boletería #" .. f.row.id, 2) end
end

local function spawnFixture(row)
    local f = { row = row }
    if row.kind == "booth" then
        f.ped = createPed(TRAIN.BOOTH_SKIN, row.x, row.y, row.z, row.rot)
        if f.ped then
            setElementFrozen(f.ped, true)
            setElementInterior(f.ped, row.interior)
            setElementDimension(f.ped, row.dimension)
            registerShop(f)
        end
    elseif row.kind == "sign" then
        f.el = createElement("rp_trainsign", "rp_trainsign_" .. row.id)
        setElementPosition(f.el, row.x, row.y, row.z)
        setElementInterior(f.el, row.interior)
        setElementDimension(f.el, row.dimension)
        setElementData(f.el, "station", row.station)
        setElementData(f.el, "name", getStationName(row.station) or "Estación")
        setElementData(f.el, "rot", row.rot)
    else
        return
    end
    fixtures[row.id] = f
end

local function destroyFixture(id)
    local f = fixtures[id]
    if not f then return end
    if f.shopId then pcall(function() exports.rp_shops:removeTempShop(f.shopId) end) end
    for _, e in ipairs({ f.ped, f.el }) do if isElement(e) then destroyElement(e) end end
    fixtures[id] = nil
end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return outputDebugString("[rp_train] no se pudieron leer las boleterías y carteles", 1) end
        for id in pairs(fixtures) do destroyFixture(id) end
        for _, row in ipairs(rows) do spawnFixture(row) end
        outputDebugString(("[rp_train] %d boleterías y carteles cargados"):format(#rows), 3)
    end, db(), "SELECT id, kind, station, x, y, z, rot, interior, dimension FROM train_fixtures")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

-- rp_shops reiniciado: las tiendas temporales se pierden, se vuelven a registrar
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rp_shops" then return end
    for _, f in pairs(fixtures) do if f.ped then registerShop(f) end end
end)

-- Abre el editor 3D del cartel en el cliente del admin
local function editSign(player, id)
    local f = fixtures[id]
    if not f or f.row.kind ~= "sign" or not isElement(f.el) then return false end
    local r = f.row
    triggerClientEvent(player, "rp:train:signEdit", resourceRoot, f.el, id, r.x, r.y, r.z, r.rot)
    return true
end

-- Crea una boletería o un cartel delante del admin, mirándolo, en la estación más cercana
local function create(player, kind)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    if getElementDimension(player) ~= 0 or getElementInterior(player) ~= 0 then
        return notify(player, "Las estaciones están en el mundo abierto (interior y dimensión 0).", "warning")
    end
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    local node, name, dist = getNearestStation(x, y, TRAIN.STATION_SNAP)
    if not node then
        return notify(player, ("No hay ninguna estación a menos de %d m."):format(TRAIN.STATION_SNAP), "warning")
    end
    local d = kind == "sign" and TRAIN.SIGN_FORWARD or 1.2
    local fx, fy = x - math.sin(math.rad(rot)) * d, y + math.cos(math.rad(rot)) * d
    local fz = kind == "sign" and z + TRAIN.SIGN_LIFT or z
    local frot = (rot + 180) % 360
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId then return notify(player, "No se pudo guardar.", "error") end
        spawnFixture({ id = insertId, kind = kind, station = node, x = fx, y = fy, z = fz, rot = frot, interior = 0, dimension = 0 })
        if isElement(player) then
            notify(player, ("%s #%d creada en %s (a %d m de la estación)."):format(KIND_NAME[kind], insertId, name, dist), "success")
            if kind == "sign" then editSign(player, insertId) end
        end
    end, db(), "INSERT INTO train_fixtures (kind, station, x, y, z, rot, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, 0, 0)",
        kind, node, fx, fy, fz, frot)
end

addCommandHandler("crearboleteria", function(player) create(player, "booth") end)
addCommandHandler("crearcartel", function(player) create(player, "sign") end)

-- /editarcartel [id]: sin id, el más cercano a menos de SIGN_EDIT_NEAR
addCommandHandler("editarcartel", function(player, _, id)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    id = tonumber(id)
    if not id then
        local px, py, pz = getElementPosition(player)
        local best
        for fid, f in pairs(fixtures) do
            if f.row.kind == "sign" then
                local d = getDistanceBetweenPoints3D(px, py, pz, f.row.x, f.row.y, f.row.z)
                if d <= TRAIN.SIGN_EDIT_NEAR and (not best or d < best) then id, best = fid, d end
            end
        end
    end
    if not id or not editSign(player, id) then
        notify(player, ("Uso: /editarcartel [id] (sin id, el más cercano a menos de %d m; mira /nearbytrainsigns)"):format(TRAIN.SIGN_EDIT_NEAR), "warning")
    end
end)

-- Guardar la posición del editor: el servidor comprueba admin, números y que no se aleje demasiado
addEventHandler("rp:train:signSave", resourceRoot, function(id, x, y, z, rot)
    local p = client
    if not isAdmin(p) then return end
    local f = fixtures[tonumber(id)]
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot)
    if not f or f.row.kind ~= "sign" or not (x and y and z and rot) then return end
    local r = f.row
    if getDistanceBetweenPoints3D(x, y, z, r.x, r.y, r.z) > TRAIN.SIGN_EDIT_RANGE then
        return notify(p, ("El cartel no puede moverse más de %d m. Usa /crearcartel allí."):format(TRAIN.SIGN_EDIT_RANGE), "warning")
    end
    rot = rot % 360
    dbExec(db(), "UPDATE train_fixtures SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", x, y, z, rot, r.id)
    r.x, r.y, r.z, r.rot = x, y, z, rot
    setElementPosition(f.el, x, y, z)
    setElementData(f.el, "rot", rot)
    notify(p, ("Cartel #%d guardado."):format(r.id), "success")
end)

-- Para adminElements/adminDelete (s_crossings.lua) con kind = "booth" | "sign"
function stationAdminElements(kind)
    local list = {}
    for id, f in pairs(fixtures) do
        local row = f.row
        if row.kind == kind then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = row.interior, dimension = row.dimension,
                label = ("%s (%s)"):format(KIND_NAME[kind], getStationName(row.station) or "?") }
        end
    end
    return list
end

function stationAdminDelete(id, kind)
    id = tonumber(id)
    local f = id and fixtures[id]
    if not f or f.row.kind ~= kind then return false, "no existe" end
    dbExec(db(), "DELETE FROM train_fixtures WHERE id = ?", id)
    destroyFixture(id)
    return true
end
