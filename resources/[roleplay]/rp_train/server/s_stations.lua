--[[
    rp_train · estaciones (servidor)

    Boleterías y carteles LED que colocan los admins (tabla train_fixtures). Cada uno se asigna a la
    estación más cercana (a menos de TRAIN.STATION_SNAP) al crearlo.
    - Boletería: empleado (ped) que vende boletos de tren con el menú de rp_shops (addTempShop):
      precio, cobro y peso del inventario los valida rp_shops. El boleto se gasta al subir (s_passengers.lua).
    - Cartel LED: elemento rp_trainsign (data station, name, rot) que dibuja el cliente (c_stations.lua)
      con la llegada estimada que publica s_train.lua en rp:train:eta.

    - Torniquete: poste + brazo y elemento rp_traingate (data rot, station, name, open). Desde fuera, E
      corta el boleto (lo gasta) y deja un pase de GATE_PASS_MS para esa estación; desde el andén se sale
      libre. En una estación con torniquetes se sube al tren con el pase (s_passengers.lua). La UI del
      boleto y el bloqueo del paso cerrado son del cliente (c_gates.lua, html/).
    - El empleado de la boletería lleva data rp:train:booth: aura en el piso en el cliente (c_booth.lua).

    - Reja: objeto del juego (TRAIN.FENCE_MODELS, columna model) congelado e irrompible para cerrar los lados.

    - Poste de metro: objeto con el modelo de su estación (logo y nombre; data rp:train:pole = nodo), que pone
      cada cliente (c_metropole.lua) con los DFF de tools/build_metro_pole.py.

    Admin: /crearboleteria, /crearcartel, /creartorniquete, /crearreja [tipo] y /crearpostemetro crean (todos menos
    la boletería se abren en el editor 3D, c_signeditor.lua); /editarcartel, /editartorniquete, /editarreja y
    /editarpostemetro [id] los vuelven
    a colocar; listar, ir y borrar con la gramática Owl de rp_admin (/nearbyticketbooths, /delticketbooth <id>,
    /nearbytrainsigns, /nearbyturnstiles, /delturnstile <id>, /nearbystationfences, /delstationfence <id>...).
]]

addEvent("rp:onDatabaseReady", false)
addEvent("rp:train:fixtureSave", true)

local fixtures = {} -- [id] = { row, ped, shopId, el }
local KIND_NAME = { booth = "Boletería", sign = "Cartel LED", gate = "Torniquete", fence = "Reja", pole = "Poste de metro" }
local gateById = {}  -- [elemento rp_traingate] = id
local passes = {}    -- [id de personaje] = { station = nodo, untilTick } (boleto validado en un torniquete)
local gateCooldown = {}

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function greeting()
    return ("Boleto de tren: $%d. Pulsa E para comprarlo; si hay torniquetes, valídalo en ellos y súbete con E junto a un vagón cuando el tren esté en el andén.")
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
            setElementData(f.ped, "rp:train:booth", true) -- aura en el piso en el cliente (c_booth.lua)
            registerShop(f)
        end
    elseif row.kind == "gate" then
        -- row.x/y = centro del paso; row.rot mira hacia el andén. Poste a la izquierda, brazo que cruza el paso
        -- (posiciones en TrainGateLayout, s_config.lua; las usa también el editor 3D del cliente).
        local px, py, postZ, armZ = TrainGateLayout(row.x, row.y, row.z, row.rot)
        f.post = createObject(TRAIN.GATE_POST_MODEL, px, py, postZ, 0, 0, row.rot)
        f.arm = createObject(TRAIN.GATE_ARM_MODEL, px, py, armZ, 0, 90 * TRAIN.GATE_ARM_SIDE, row.rot)
        if f.arm then
            setObjectScale(f.arm, 1, 1, TRAIN.GATE_ARM_LENGTH)
            setElementCollisionsEnabled(f.arm, false) -- el paso lo cierra el cliente (c_gates.lua), no la colisión escalada
        end
        f.el = createElement("rp_traingate", "rp_traingate_" .. row.id)
        setElementPosition(f.el, row.x, row.y, row.z)
        setElementData(f.el, "rot", row.rot)
        setElementData(f.el, "station", row.station)
        setElementData(f.el, "name", getStationName(row.station) or "Estación")
        setElementData(f.el, "open", false)
        for _, e in ipairs({ f.post, f.arm, f.el }) do
            if e then setElementInterior(e, row.interior) setElementDimension(e, row.dimension) end
        end
        gateById[f.el] = row.id
    elseif row.kind == "fence" then
        -- Reja: objeto del juego congelado (el cliente la hace irrompible, c_gates.lua)
        local model = TrainFenceModel(tonumber(row.model)) and tonumber(row.model) or TRAIN.FENCE_MODELS[1].model
        f.obj = createObject(model, row.x, row.y, row.z, 0, 0, row.rot)
        if not f.obj then return end
        f.el = f.obj
        setElementFrozen(f.obj, true)
        setElementInterior(f.obj, row.interior)
        setElementDimension(f.obj, row.dimension)
        setElementData(f.obj, "rp:train:fence", true)
    elseif row.kind == "pole" then
        -- Poste de metro: objeto con modelo provisional; cada cliente le pone el modelo de su estación
        -- (models/metro_pole_<nodo>.dff, c_metropole.lua) según el data rp:train:pole
        f.obj = createObject(TRAIN.POLE_PLACEHOLDER, row.x, row.y, row.z, 0, 0, row.rot)
        if not f.obj then return end
        f.el = f.obj
        setElementFrozen(f.obj, true)
        setElementInterior(f.obj, row.interior)
        setElementDimension(f.obj, row.dimension)
        setElementData(f.obj, "rp:train:pole", row.station)
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
    if isTimer(f.closeTimer) then killTimer(f.closeTimer) end
    if f.el then gateById[f.el] = nil end
    for _, e in ipairs({ f.ped, f.el, f.post, f.arm }) do if isElement(e) then destroyElement(e) end end
    fixtures[id] = nil
end

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return outputDebugString("[rp_train] no se pudieron leer las boleterías y carteles", 1) end
        for id in pairs(fixtures) do destroyFixture(id) end
        for _, row in ipairs(rows) do spawnFixture(row) end
        outputDebugString(("[rp_train] %d boleterías, carteles, torniquetes y rejas cargados"):format(#rows), 3)
    end, db(), "SELECT id, kind, station, x, y, z, rot, interior, dimension, model FROM train_fixtures")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

-- rp_shops reiniciado: las tiendas temporales se pierden, se vuelven a registrar
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rp_shops" then return end
    for _, f in pairs(fixtures) do if f.ped then registerShop(f) end end
end)

-- Abre el editor 3D (c_signeditor.lua) de un cartel o un torniquete en el cliente del admin
local EDITABLE = { sign = true, gate = true, fence = true, pole = true }
local function editFixture(player, id)
    local f = fixtures[id]
    if not f or not EDITABLE[f.row.kind] or not isElement(f.el) then return false end
    local r = f.row
    triggerClientEvent(player, "rp:train:fixtureEdit", resourceRoot, r.kind, f.el, id, r.x, r.y, r.z, r.rot,
        f.post or false, f.arm or false)
    return true
end

-- Coloca poste, brazo (cerrado) y elemento de un torniquete en su fila
local function placeGate(f)
    local r = f.row
    if isTimer(f.closeTimer) then killTimer(f.closeTimer) end
    f.closeTimer = nil
    local px, py, postZ, armZ = TrainGateLayout(r.x, r.y, r.z, r.rot)
    if isElement(f.post) then
        setElementPosition(f.post, px, py, postZ)
        setElementRotation(f.post, 0, 0, r.rot)
    end
    if isElement(f.arm) then
        stopObject(f.arm)
        setElementPosition(f.arm, px, py, armZ)
        setElementRotation(f.arm, 0, 90 * TRAIN.GATE_ARM_SIDE, r.rot)
    end
    setElementPosition(f.el, r.x, r.y, r.z)
    setElementData(f.el, "rot", r.rot)
    setElementData(f.el, "open", false)
end

-- El fixture del tipo más cercano al admin a menos de SIGN_EDIT_NEAR
local function nearestFixture(player, kind)
    local px, py, pz = getElementPosition(player)
    local id, best
    for fid, f in pairs(fixtures) do
        if f.row.kind == kind then
            local d = getDistanceBetweenPoints3D(px, py, pz, f.row.x, f.row.y, f.row.z)
            if d <= TRAIN.SIGN_EDIT_NEAR and (not best or d < best) then id, best = fid, d end
        end
    end
    return id
end

-- Crea una boletería, cartel, torniquete o reja delante del admin, en la estación más cercana.
-- model: solo rejas (modelo de TRAIN.FENCE_MODELS). Cartel, torniquete y reja se abren en el editor 3D.
local function create(player, kind, model)
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
    local FORWARD = { sign = TRAIN.SIGN_FORWARD, gate = TRAIN.GATE_FORWARD, fence = TRAIN.FENCE_FORWARD, pole = TRAIN.POLE_FORWARD }
    local d = FORWARD[kind] or 1.2
    local fx, fy = x - math.sin(math.rad(rot)) * d, y + math.cos(math.rad(rot)) * d
    local fz = kind == "sign" and z + TRAIN.SIGN_LIFT or kind == "fence" and z - TRAIN.FENCE_DROP
        or kind == "pole" and z - TRAIN.POLE_DROP or z
    -- boletería y cartel miran al admin; torniquete y reja miran hacia donde mira el admin
    local frot = (kind == "gate" or kind == "fence") and rot % 360 or (rot + 180) % 360
    model = model or 0
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId then return notify(player, "No se pudo guardar.", "error") end
        spawnFixture({ id = insertId, kind = kind, station = node, x = fx, y = fy, z = fz, rot = frot,
            interior = 0, dimension = 0, model = model })
        if isElement(player) then
            notify(player, ("%s #%d guardado: %s, a %d m de la estación."):format(KIND_NAME[kind], insertId, name, dist), "success")
            if kind == "gate" then
                notify(player, "Recuerda: el torniquete se pone desde fuera, mirando hacia el andén. Desde ese lado se valida el boleto.", "info")
            end
            editFixture(player, insertId)
        end
    end, db(), "INSERT INTO train_fixtures (kind, station, x, y, z, rot, interior, dimension, model) VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?)",
        kind, node, fx, fy, fz, frot, model)
end

addCommandHandler("crearboleteria", function(player) create(player, "booth") end)
addCommandHandler("crearcartel", function(player) create(player, "sign") end)
addCommandHandler("creartorniquete", function(player) create(player, "gate") end)
-- Poste de metro con el nombre de la estación más cercana (modelo de tools/build_metro_pole.py)
addCommandHandler("crearpostemetro", function(player) create(player, "pole") end)

-- /crearreja [tipo]: sin tipo, lista los tipos
addCommandHandler("crearreja", function(player, _, n)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local def = TRAIN.FENCE_MODELS[tonumber(n) or 0]
    if not def then
        local list = {}
        for i, f in ipairs(TRAIN.FENCE_MODELS) do list[#list + 1] = ("%d = %s"):format(i, f.name) end
        return notify(player, "Uso: /crearreja <tipo> · " .. table.concat(list, " · "), "info")
    end
    create(player, "fence", def.model)
end)

-- /editartorniquete [id], /editarreja [id]: sin id, el más cercano a menos de SIGN_EDIT_NEAR
local function editCommand(kind, cmd, list)
    addCommandHandler(cmd, function(player, _, id)
        if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
        id = tonumber(id) or nearestFixture(player, kind)
        local f = id and fixtures[id]
        if not f or f.row.kind ~= kind or not editFixture(player, id) then
            notify(player, ("Uso: /%s [id] (sin id, el más cercano a menos de %d m; mira /%s)"):format(cmd, TRAIN.SIGN_EDIT_NEAR, list), "warning")
        end
    end)
end
editCommand("sign", "editarcartel", "nearbytrainsigns")
editCommand("gate", "editartorniquete", "nearbyturnstiles")
editCommand("fence", "editarreja", "nearbystationfences")
editCommand("pole", "editarpostemetro", "nearbymetropoles")

----------------------------------------------------------------
-- Torniquetes: validar el boleto (desde fuera) y salir (desde el andén)
----------------------------------------------------------------
addEvent("rp:train:gatePunch", true)
addEvent("rp:train:gateExit", true)

local function charId(p)
    local ok, id = pcall(function() return exports.rp_characters:getPlayerCharacterId(p) end)
    return ok and id or nil
end

-- Posición del jugador respecto al paso: a lo largo (negativo = fuera, positivo = andén) y de lado
local function gateFrame(f, x, y)
    local r = math.rad(f.row.rot)
    local dx, dy = x - f.row.x, y - f.row.y
    return dx * -math.sin(r) + dy * math.cos(r), dx * math.cos(r) + dy * math.sin(r)
end

-- Gate pedido por el cliente: existe, está cerca y en el mismo mundo. Devuelve el fixture y "along".
local function nearGate(p, el)
    local id = isElement(el) and gateById[el]
    local f = id and fixtures[id]
    if not f or not isElement(f.arm) then return end
    if getElementDimension(p) ~= f.row.dimension or getElementInterior(p) ~= f.row.interior then return end
    if isPedInVehicle(p) or isPedDead(p) or getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") then return end
    local x, y, z = getElementPosition(p)
    local along, side = gateFrame(f, x, y)
    if math.abs(along) > TRAIN.GATE_USE + 1 or math.abs(side) > TRAIN.GATE_HALF_WIDTH + 1.5 or math.abs(z - f.row.z) > 3 then return end
    return f, along
end

local function setGateOpen(f, open)
    if not isElement(f.arm) then return end
    setElementData(f.el, "open", open)
    stopObject(f.arm)
    local _, ry = getElementRotation(f.arm)
    local target = open and 0 or 90 * TRAIN.GATE_ARM_SIDE
    local x, y, z = getElementPosition(f.arm)
    moveObject(f.arm, TRAIN.GATE_MOVE_MS, x, y, z, 0, (target - ry + 180) % 360 - 180, 0, "OutQuad")
end

local function openGate(f)
    if isTimer(f.closeTimer) then killTimer(f.closeTimer) end
    if not getElementData(f.el, "open") then setGateOpen(f, true) end
    f.closeTimer = setTimer(function() f.closeTimer = nil setGateOpen(f, false) end, TRAIN.GATE_OPEN_MS, 1)
end

local function takeGateCooldown(p)
    local now = getTickCount()
    if gateCooldown[p] and now - gateCooldown[p] < 800 then return false end
    gateCooldown[p] = now
    return true
end

local function validPass(cid, station)
    local ps = cid and passes[cid]
    if ps and ps.station == station and getTickCount() < ps.untilTick then return ps end
    if ps and getTickCount() >= ps.untilTick then passes[cid] = nil end
end

-- E desde fuera: se corta el boleto (se gasta) y queda un pase para subir al tren en esta estación
addEventHandler("rp:train:gatePunch", resourceRoot, function(el)
    local p = client
    if not takeGateCooldown(p) then return end
    local cid = charId(p)
    local f, along = nearGate(p, el)
    if not cid or not f or along > 0.3 then return end
    local station = f.row.station
    if validPass(cid, station) then
        openGate(f)
        return triggerClientEvent(p, "rp:train:gateResult", resourceRoot, "validated")
    end
    if not exports.rp_inventory:hasItem(p, TRAIN.TICKET_ITEM, 1) then
        return triggerClientEvent(p, "rp:train:gateResult", resourceRoot, "noticket", TRAIN.TICKET_PRICE)
    end
    local ok, why = exports.rp_inventory:takeItem(p, TRAIN.TICKET_ITEM, 1)
    if not ok then
        notify(p, why or "No se pudo usar el boleto.", "error")
        return triggerClientEvent(p, "rp:train:gateResult", resourceRoot, "error")
    end
    passes[cid] = { station = station, untilTick = getTickCount() + TRAIN.GATE_PASS_MS }
    triggerClientEvent(p, "rp:train:gateResult", resourceRoot, "punched", getStationName(station) or "",
        math.floor(TRAIN.GATE_PASS_MS / 60000))
    -- el brazo sube cuando termina la animación del corte en la UI
    setTimer(function() if fixtures[f.row.id] == f then openGate(f) end end, 900, 1)
end)

-- Desde el andén se sale libre (el cliente lo pide al acercarse)
addEventHandler("rp:train:gateExit", resourceRoot, function(el)
    local p = client
    if not takeGateCooldown(p) then return end
    local f, along = nearGate(p, el)
    if f and along > -0.3 then openGate(f) end
end)

addEventHandler("onPlayerQuit", root, function() gateCooldown[source] = nil end)

-- Para s_passengers.lua: ¿la estación tiene torniquetes? Entonces se sube con el pase, no con el boleto.
function stationHasGates(node)
    for _, f in pairs(fixtures) do
        if f.row.kind == "gate" and f.row.station == node then return true end
    end
    return false
end

-- Gasta el pase del personaje para esa estación. true si lo tenía.
function useStationPass(player, node)
    local cid = charId(player)
    if not validPass(cid, node) then return false end
    passes[cid] = nil
    return true
end

-- Guardar la posición del editor 3D (cartel, torniquete o reja): el servidor comprueba admin, números
-- y que no se aleje demasiado de donde estaba
-- Copias en fila de un cartel, torniquete o reja: la i-ésima queda en (x, y, z) + i * paso y gira i * drot
local function duplicate(p, f, dup)
    local r = f.row
    local made, pending = 0, dup.n
    for i = 1, dup.n do
        local row = { kind = r.kind, station = r.station, x = r.x + dup.dx * i, y = r.y + dup.dy * i, z = r.z + dup.dz * i,
            rot = (r.rot + dup.drot * i) % 360, interior = r.interior, dimension = r.dimension, model = tonumber(r.model) or 0 }
        dbQuery(function(qh)
            local _, _, insertId = dbPoll(qh, 0)
            pending = pending - 1
            if insertId then
                row.id = insertId
                spawnFixture(row)
                made = made + 1
            end
            if pending == 0 and isElement(p) then
                notify(p, ("%d copias de %s #%d creadas (cada una a %.2f, %.2f, %.2f m y %.1f° de la anterior)."):format(
                    made, KIND_NAME[r.kind]:lower(), r.id, dup.dx, dup.dy, dup.dz, dup.drot), made == dup.n and "success" or "warning")
            end
        end, db(), "INSERT INTO train_fixtures (kind, station, x, y, z, rot, interior, dimension, model) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            row.kind, row.station, row.x, row.y, row.z, row.rot, row.interior, row.dimension, row.model)
    end
end

-- dup (opcional, /duplicar en el editor): { n, dx, dy, dz, drot } = cantidad de copias y paso entre cada una
local function readDup(dup)
    if type(dup) ~= "table" then return nil end
    local n = math.floor(tonumber(dup.n) or 0)
    local dx, dy, dz, drot = tonumber(dup.dx), tonumber(dup.dy), tonumber(dup.dz), tonumber(dup.drot) or 0
    if n < 1 or n > TRAIN.DUP_MAX or not (dx and dy and dz) then return nil end
    if math.sqrt(dx * dx + dy * dy + dz * dz) > TRAIN.DUP_STEP_MAX or math.abs(drot) > 360 then return nil end
    return { n = n, dx = dx, dy = dy, dz = dz, drot = drot }
end

addEventHandler("rp:train:fixtureSave", resourceRoot, function(id, x, y, z, rot, dupIn)
    local p = client
    if not isAdmin(p) then return end
    local f = fixtures[tonumber(id)]
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot)
    if not f or not EDITABLE[f.row.kind] or not (x and y and z and rot) then return end
    local dup = readDup(dupIn)
    if dupIn and not dup then
        notify(p, ("Duplicado no válido: hasta %d copias y %d m entre cada una."):format(TRAIN.DUP_MAX, TRAIN.DUP_STEP_MAX), "warning")
    end
    local r = f.row
    if getDistanceBetweenPoints3D(x, y, z, r.x, r.y, r.z) > TRAIN.SIGN_EDIT_RANGE then
        if isElement(p) then triggerClientEvent(p, "rp:train:fixtureEditFailed", resourceRoot) end
        return notify(p, ("No puede moverse más de %d m de donde estaba: créalo de nuevo allí."):format(TRAIN.SIGN_EDIT_RANGE), "warning")
    end
    rot = rot % 360
    dbExec(db(), "UPDATE train_fixtures SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", x, y, z, rot, r.id)
    r.x, r.y, r.z, r.rot = x, y, z, rot
    if r.kind == "gate" then
        placeGate(f)
    elseif r.kind == "fence" or r.kind == "pole" then
        setElementPosition(f.obj, x, y, z)
        setElementRotation(f.obj, 0, 0, rot)
    else
        setElementPosition(f.el, x, y, z)
        setElementData(f.el, "rot", rot)
    end
    notify(p, ("%s #%d guardado."):format(KIND_NAME[r.kind], r.id), "success")
    if dup then duplicate(p, f, dup) end
end)

-- Para adminElements/adminDelete (s_crossings.lua) con kind = "booth" | "sign" | "gate" | "fence"
function stationAdminElements(kind)
    local list = {}
    for id, f in pairs(fixtures) do
        local row = f.row
        if row.kind == kind then
            local fence = kind == "fence" and TrainFenceModel(tonumber(row.model))
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = row.interior, dimension = row.dimension,
                label = ("%s (%s)"):format(fence and fence.name or KIND_NAME[kind], getStationName(row.station) or "?"),
                rot = tonumber(row.rot) or 0, element = f.obj or f.post or f.ped or f.el }
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

-- La llama adminMove (s_crossings.lua) desde el editor de rp_admin (vista ALT)
function stationAdminMove(id, kind, x, y, z, rot)
    id = tonumber(id)
    local f = id and fixtures[id]
    if not f or f.row.kind ~= kind then return false, "no existe" end
    local row = f.row
    rot = rot % 360
    dbExec(db(), "UPDATE train_fixtures SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", x, y, z, rot, id)
    destroyFixture(id)
    row.x, row.y, row.z, row.rot = x, y, z, rot
    spawnFixture(row)
    return true
end
