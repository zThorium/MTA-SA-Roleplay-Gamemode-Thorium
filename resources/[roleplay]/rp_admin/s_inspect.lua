--[[
    rp_admin / s_inspect.lua
    Vista de admin con ALT: mientras un admin (nivel 1+) mantiene ALT, el cliente pide aqui
    lo que hay alrededor y lo dibuja encima de cada cosa con su ID, dueno, creador y comandos.

    Que se muestra (mismo interior y dimension que el admin):
      - Todo tipo registrado en WORLD_TYPES (s_world.lua): cajeros, tiendas, casas (y su
        salida interior), expendedoras, maquinas y entrenadores del gym, barreras,
        boleterias, carteles, torniquetes, rejas, mesas de pool, textos 3D...
      - Vehiculos: ID de BD, matricula, dueno y fecha; los temporales con el recurso que los creo.
      - Objetos, pickups, marcadores y peds sueltos de cualquier recurso (los que no son de
        un tipo registrado), con su recurso, modelo y ID de elemento.

    Creador: la tabla admin_world_creators guarda que admin creo cada elemento. Se rellena
    vigilando el comando `create` de cada tipo: al usarlo, se compara la lista de IDs antes y
    despues y los nuevos se apuntan a ese admin. Los creados antes de esto salen sin creador
    (salvo los textos 3D, que lo guardan ellos mismos).
]]

local RADIUS = 70            -- tipos registrados, casas y vehiculos con dueno
local LOOSE_RADIUS = 30      -- objetos, pickups, marcadores, peds y vehiculos temporales
local LOOSE_MAX = 60
local DEDUPE_DIST = 1.5      -- un objeto suelto tan cerca de un registrado es el mismo
local COOLDOWN_MS = 800
local WATCH_STEP_MS, WATCH_TIMES = 1000, 10   -- busca el ID nuevo hasta 10 s tras el comando
local ROOTS_TTL_MS = 5000

-- Recursos cuyos elementos sueltos no se muestran (miles de peatones/trafico o adjuntos)
local SKIP_LOOSE = { rp_citizens = true, bone_attach = true, rp_heads = true }
local LOOSE_TYPES = { "object", "pickup", "marker", "ped" }

local creators = {}          -- [type_key][id] = { name, at }
local lastRequest = {}

local function isAdmin(p) return levelOf(p) >= LEVEL_ADMIN end
local function log(msg, lvl) outputDebugString("[rp_admin] " .. msg, lvl or 3) end
local function nowText() local t = getRealTime() return ("%04d-%02d-%02d %02d:%02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute, t.second) end

----------------------------------------------------------------
-- Creadores
----------------------------------------------------------------
local function loadCreators()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return log("no se pudieron cargar los creadores de elementos", 1) end
        for _, r in ipairs(rows) do
            creators[r.type_key] = creators[r.type_key] or {}
            creators[r.type_key][tonumber(r.element_id)] = { name = r.admin_name, at = tostring(r.created_at) }
        end
    end, db(), "SELECT type_key, element_id, admin_name, created_at FROM admin_world_creators")
end

local function rememberCreator(key, id, accountId, name)
    creators[key] = creators[key] or {}
    creators[key][id] = { name = name, at = nowText() }
    dbExec(db(), [[INSERT INTO admin_world_creators (type_key, element_id, account_id, admin_name)
                   VALUES (?, ?, NULLIF(?, 0), ?)
                   ON DUPLICATE KEY UPDATE account_id = VALUES(account_id), admin_name = VALUES(admin_name), created_at = NOW()]],
        key, id, accountId or 0, name)
    log(("%s creo %s #%d"):format(name, key, id))
end

-- Global: s_world.lua lo llama al borrar con /del<tipo>
function forgetCreator(key, id)
    if creators[key] then creators[key][id] = nil end
    dbExec(db(), "DELETE FROM admin_world_creators WHERE type_key = ? AND element_id = ?", key, id)
end

local function runningRes(t)
    local r = getResourceFromName(t.res)
    return r and getResourceState(r) == "running" and r
end

local function listOf(t)
    local r = runningRes(t)
    if not r then return nil end
    local ok, list = pcall(call, r, "adminElements", t.kind)
    return ok and type(list) == "table" and list or nil
end

local function idSet(t)
    local list = listOf(t)
    if not list then return nil end
    local set = {}
    for _, e in ipairs(list) do
        local id = tonumber(e.id)
        if id then set[id] = true end
    end
    return set
end

local typesByCommand = {}
for _, t in ipairs(WORLD_TYPES) do
    if t.create then
        typesByCommand[t.create] = typesByCommand[t.create] or {}
        table.insert(typesByCommand[t.create], t)
    end
end

-- onPlayerCommand llega antes que el comando: foto de los IDs y luego se buscan los nuevos
addEventHandler("onPlayerCommand", root, function(cmd)
    local types = typesByCommand[tostring(cmd):lower()]
    if not types or not isAdmin(source) then return end
    local accountId = exports.rp_login:getPlayerAccountId(source)
    local name = (getPlayerName(source):gsub("_", " "))
    for _, t in ipairs(types) do
        local before = idSet(t)
        if before then
            local timer
            timer = setTimer(function()
                local now = idSet(t)
                local found = false
                for id in pairs(now or {}) do
                    if not before[id] then
                        found = true
                        rememberCreator(t.key, id, accountId, name)
                    end
                end
                if (found or not now) and isTimer(timer) then killTimer(timer) end
            end, WATCH_STEP_MS, WATCH_TIMES)
        end
    end
end)

----------------------------------------------------------------
-- Recurso dueno de un elemento
----------------------------------------------------------------
local roots, rootsAt = {}, 0

local function resourceRoots()
    if getTickCount() - rootsAt < ROOTS_TTL_MS then return roots end
    roots, rootsAt = {}, getTickCount()
    for _, r in ipairs(getResources()) do
        if getResourceState(r) == "running" then
            local name = getResourceName(r)
            local dyn, rr = getResourceDynamicElementRoot(r), getResourceRootElement(r)
            if dyn then roots[dyn] = name end
            if rr then roots[rr] = name end
        end
    end
    return roots
end

local function ownerResource(el)
    local map = resourceRoots()
    local p, n = getElementParent(el), 0
    while p and n < 8 do
        if map[p] then return map[p] end
        p, n = getElementParent(p), n + 1
    end
    return nil
end

----------------------------------------------------------------
-- Recogida
----------------------------------------------------------------
local function keysOf(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    return out
end

local function gather(player, forPick)
    local px, py, pz = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    local out, ownerIds, vehicleIds = {}, {}, {}

    local function near(x, y, z, i, d, radius)
        return tonumber(i) == int and tonumber(d) == dim
            and getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= radius
    end

    -- 1. Tipos registrados
    for _, t in ipairs(WORLD_TYPES) do
        for _, e in ipairs(listOf(t) or {}) do
            local id, x, y, z = tonumber(e.id), tonumber(e.x), tonumber(e.y), tonumber(e.z)
            if id and x and y and z then
                local c = creators[t.key] and creators[t.key][id]
                -- rot/noRot/element/part los usa el editor para mover (c_move.lua)
                local function entry(src, ex, ey, ez, suffix, part)
                    return { kind = t.key == "house" and "house" or "type", key = t.key, typeName = t.name .. (suffix or ""),
                        id = id, label = e.label, info = e.info, ownerId = tonumber(e.ownerId), res = t.res,
                        creator = e.creator or (c and c.name), createdAt = e.createdAt and tostring(e.createdAt) or (c and c.at),
                        x = ex, y = ey, z = ez, interior = int, dimension = dim,
                        rot = tonumber(src.rot) or 0, noRot = (part ~= "exit" and e.noRot) or nil,
                        element = isElement(src.element) and src.element or nil, part = part }
                end
                if near(x, y, z, e.interior, e.dimension, RADIUS) then
                    out[#out + 1] = entry(e, x, y, z)
                end
                local ex = type(e.exit) == "table" and e.exit
                if ex and tonumber(ex.x) and near(ex.x, ex.y, ex.z, ex.interior, ex.dimension, RADIUS) then
                    out[#out + 1] = entry(ex, tonumber(ex.x), tonumber(ex.y), tonumber(ex.z), " (salida)", "exit")
                end
                if e.ownerId then ownerIds[tonumber(e.ownerId)] = true end
            end
        end
    end
    local registered = #out

    -- 2. Vehiculos
    local vehRes = getResourceFromName("rp_vehicles")
    local vehRunning = vehRes and getResourceState(vehRes) == "running"
    for _, v in ipairs(getElementsWithinRange(px, py, pz, RADIUS, "vehicle", int, dim)) do
        local dbId = vehRunning and exports.rp_vehicles:getVehicleDatabaseId(v) or nil
        local temp = not dbId and vehRunning and exports.rp_vehicles:getTempVehicleInfo(v) or nil
        if temp then
            -- Temporal de /veh: ID negativo y quien lo creo (auditoria)
            local by = temp.createdBy or {}
            out[#out + 1] = { kind = "vehicle", elem = v, id = temp.id, temp = true, label = getVehicleName(v),
                info = ("modelo %d, temporal (no se guarda)"):format(getElementModel(v)), res = "rp_vehicles",
                creator = ("%s (cuenta %s #%s)"):format(tostring(by.player), tostring(by.account), tostring(by.accountId)),
                createdAt = temp.createdAt, elementId = getElementID(v) }
        end
        local x, y, z = getElementPosition(v)
        if not temp and (dbId or getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= LOOSE_RADIUS) then
            local res = ownerResource(v)
            if dbId or not SKIP_LOOSE[res or ""] then
                local ownerId = dbId and tonumber(exports.rp_vehicles:getVehicleOwner(v)) or nil
                out[#out + 1] = { kind = "vehicle", elem = v, id = dbId, label = getVehicleName(v),
                    info = ("matricula %s, modelo %d"):format(getVehiclePlateText(v) or "-", getElementModel(v)),
                    ownerId = ownerId, res = res, elementId = getElementID(v) }
                if dbId then vehicleIds[dbId] = true end
                if ownerId then ownerIds[ownerId] = true end
            end
        end
    end

    -- 3. Elementos sueltos de cualquier recurso
    local loose = {}
    for _, etype in ipairs(LOOSE_TYPES) do
        for _, el in ipairs(getElementsWithinRange(px, py, pz, LOOSE_RADIUS, etype, int, dim)) do
            if not isElementAttached(el) then
                local res = ownerResource(el)
                if res and not SKIP_LOOSE[res] then
                    local x, y, z = getElementPosition(el)
                    local dup = false
                    for i = 1, registered do
                        local r = out[i]
                        if getDistanceBetweenPoints3D(x, y, z, r.x, r.y, r.z) <= DEDUPE_DIST then dup = true break end
                    end
                    if not dup then
                        local info
                        if etype == "pickup" then info = ("pickup tipo %d"):format(getPickupType(el))
                        elseif etype == "marker" then info = ("marcador %s"):format(getMarkerType(el) or "?")
                        else info = ("%s modelo %d"):format(etype == "ped" and "ped" or "objeto", getElementModel(el)) end
                        loose[#loose + 1] = { kind = "loose", elem = el, etype = etype, res = res, info = info,
                            elementId = getElementID(el), d = getDistanceBetweenPoints3D(px, py, pz, x, y, z) }
                    end
                end
            end
        end
    end
    table.sort(loose, function(a, b) return a.d < b.d end)
    for i = 1, math.min(#loose, LOOSE_MAX) do
        loose[i].d = nil
        out[#out + 1] = loose[i]
    end

    -- 4. Nombres de duenos y fecha de los vehiculos (BD, asincrono)
    local function send(names, vehDates)
        if not isElement(player) then return end
        for _, e in ipairs(out) do
            if e.ownerId then e.owner = names[e.ownerId] or ("personaje #" .. e.ownerId) end
            if e.kind == "vehicle" and e.id and not e.temp then e.createdAt = vehDates[e.id] end
        end
        triggerClientEvent(player, "rp:admin:inspect:data", resourceRoot, out, int, dim, forPick)
    end

    local vids = keysOf(vehicleIds)
    local function step2(vehDates)
        local cids = keysOf(ownerIds)
        if #cids == 0 then return send({}, vehDates) end
        dbQuery(function(qh)
            local rows = dbPoll(qh, 0) or {}
            local names = {}
            for _, r in ipairs(rows) do names[tonumber(r.id)] = r.name end
            send(names, vehDates)
        end, db(), "SELECT id, name FROM characters WHERE FIND_IN_SET(id, ?)", table.concat(cids, ","))
    end
    if #vids == 0 then return step2({}) end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        local dates = {}
        for _, r in ipairs(rows) do dates[tonumber(r.id)] = tostring(r.created_at) end
        step2(dates)
    end, db(), "SELECT id, created_at FROM vehicles WHERE FIND_IN_SET(id, ?)", table.concat(vids, ","))
end

----------------------------------------------------------------
-- Eventos
----------------------------------------------------------------
local function sendEnabled(player)
    triggerClientEvent(player, "rp:admin:inspect:enable", resourceRoot, isAdmin(player))
end

addEvent("rp:admin:inspect:request", true)
-- forPick: la pide el menu del cursor (M + clic derecho); lleva su propio cooldown para no
-- chocar con el refresco de la vista ALT
local lastPick = {}
addEventHandler("rp:admin:inspect:request", resourceRoot, function(forPick)
    local player = client
    if not player then return end
    if not isAdmin(player) then return sendEnabled(player) end
    local stamps = forPick == true and lastPick or lastRequest
    local now = getTickCount()
    if stamps[player] and now - stamps[player] < COOLDOWN_MS then return end
    stamps[player] = now
    gather(player, forPick == true)
end)

-- El cliente esta listo (al entrar o al reiniciar rp_admin) y al cambiar de cuenta
addEventHandler("onPlayerResourceStart", root, function(res)
    if res == resource then sendEnabled(source) end
end)
addEvent("rp:onAccountLogin")
addEventHandler("rp:onAccountLogin", root, function() sendEnabled(source) end)
addEvent("rp:onAccountLogout")
addEventHandler("rp:onAccountLogout", root, function()
    triggerClientEvent(source, "rp:admin:inspect:enable", resourceRoot, false)
end)

addEventHandler("onPlayerQuit", root, function() lastRequest[source] = nil lastPick[source] = nil end)

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadCreators() else addEventHandler("rp:onDatabaseReady", root, loadCreators) end
end)
