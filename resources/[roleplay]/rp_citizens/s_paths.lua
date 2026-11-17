--[[
    rp_citizens / s_paths.lua
    Guarda en SQL los cambios del editor de rutas (/nodos) y los reparte en vivo
    a todos los clientes. La red original viene de c_nodes_ls.lua; aqui solo se
    guardan las diferencias (nodos movidos, nuevos, borrados y enlaces).
]]

local BASE = { v = 5687, p = 12537 }   -- nodos de c_nodes_ls.lua
local nextIdx = { v = BASE.v, p = BASE.p }
local cache = { nodes = {}, links = {} } -- copia en memoria para enviar a quien entra

addEvent("rp:onDatabaseReady", false)
addEvent("rp:paths:request", true)
addEvent("rp:paths:toggleEditor", true)
addEvent("rp:paths:move", true)
addEvent("rp:paths:add", true)
addEvent("rp:paths:delete", true)
addEvent("rp:paths:link", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function nodeKey(t, i) return t .. ":" .. i end
local function linkKey(t, a, b) if a > b then a, b = b, a end return t .. ":" .. a .. ":" .. b end

local function validType(t) return t == "v" or t == "p" end
local function validIdx(t, i) return type(i) == "number" and i >= 1 and i <= nextIdx[t] and i == math.floor(i) end
local function validCoord(n) return type(n) == "number" and n == n and math.abs(n) < 4000 end

local function broadcast(op)
    triggerClientEvent(root, "rp:paths:apply", resourceRoot, { op })
end

local function saveNode(t, i, x, y, z, deleted)
    cache.nodes[nodeKey(t, i)] = { t = t, i = i, x = x, y = y, z = z, d = deleted and 1 or 0 }
    dbExec(db(), [[
        INSERT INTO path_nodes (type, idx, x, y, z, deleted) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), deleted = VALUES(deleted)
    ]], t, i, x, y, z, deleted and 1 or 0)
end

local function saveLink(t, a, b, removed)
    if a > b then a, b = b, a end
    cache.links[linkKey(t, a, b)] = { t = t, a = a, b = b, r = removed and 1 or 0 }
    dbExec(db(), "INSERT INTO path_links (type, a, b, removed) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE removed = VALUES(removed)",
        t, a, b, removed and 1 or 0)
end

----------------------------------------------------------------
-- Carga
----------------------------------------------------------------
local function load()
    dbQuery(function(qh)
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            local i = tonumber(r.idx)
            cache.nodes[nodeKey(r.type, i)] = { t = r.type, i = i, x = r.x, y = r.y, z = r.z, d = tonumber(r.deleted) }
            if i > nextIdx[r.type] then nextIdx[r.type] = i end
        end
        dbQuery(function(qh2)
            for _, r in ipairs(dbPoll(qh2, 0) or {}) do
                local a, b = tonumber(r.a), tonumber(r.b)
                cache.links[linkKey(r.type, a, b)] = { t = r.type, a = a, b = b, r = tonumber(r.removed) }
            end
            outputDebugString("[rp_citizens] Cambios de rutas cargados")
        end, db(), "SELECT * FROM path_links")
    end, db(), "SELECT * FROM path_nodes")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

-- El cliente pide los cambios al arrancar
addEventHandler("rp:paths:request", resourceRoot, function()
    local ops = {}
    -- primero los nodos (los nuevos deben existir antes que sus enlaces)
    local nodes = {}
    for _, n in pairs(cache.nodes) do nodes[#nodes + 1] = n end
    table.sort(nodes, function(a, b) return a.i < b.i end)
    for _, n in ipairs(nodes) do
        ops[#ops + 1] = { op = n.d == 1 and "delete" or "node", t = n.t, i = n.i, x = n.x, y = n.y, z = n.z }
    end
    for _, l in pairs(cache.links) do
        ops[#ops + 1] = { op = "link", t = l.t, a = l.a, b = l.b, removed = l.r == 1 }
    end
    triggerLatentClientEvent(client, "rp:paths:apply", 100000, false, resourceRoot, ops)
end)

----------------------------------------------------------------
-- Edicion (solo administradores)
----------------------------------------------------------------
addCommandHandler("nodos", function(player)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    triggerClientEvent(player, "rp:paths:editor", resourceRoot)
end)

addEventHandler("rp:paths:move", resourceRoot, function(t, i, x, y, z)
    if not isAdmin(client) or not validType(t) or not validIdx(t, i) then return end
    if not (validCoord(x) and validCoord(y) and validCoord(z)) then return end
    saveNode(t, i, x, y, z, false)
    broadcast({ op = "node", t = t, i = i, x = x, y = y, z = z })
end)

-- Nuevo nodo en (x,y,z). Si se dan a y b (enlazados), se inserta entre ellos.
addEventHandler("rp:paths:add", resourceRoot, function(t, x, y, z, a, b)
    if not isAdmin(client) or not validType(t) then return end
    if not (validCoord(x) and validCoord(y) and validCoord(z)) then return end
    nextIdx[t] = nextIdx[t] + 1
    local i = nextIdx[t]
    saveNode(t, i, x, y, z, false)
    broadcast({ op = "node", t = t, i = i, x = x, y = y, z = z })
    if validIdx(t, a) and validIdx(t, b) then
        saveLink(t, a, b, true)
        broadcast({ op = "link", t = t, a = a, b = b, removed = true })
    end
    for _, other in ipairs({ a, b }) do
        if validIdx(t, other) and other ~= i then
            saveLink(t, i, other, false)
            broadcast({ op = "link", t = t, a = i, b = other, removed = false })
        end
    end
    notify(client, ("Nodo %s #%d creado."):format(t == "v" and "vial" or "peatonal", i), "success")
end)

addEventHandler("rp:paths:delete", resourceRoot, function(t, i, x, y, z)
    if not isAdmin(client) or not validType(t) or not validIdx(t, i) then return end
    saveNode(t, i, tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0, true)
    broadcast({ op = "delete", t = t, i = i })
end)

addEventHandler("rp:paths:link", resourceRoot, function(t, a, b, removed)
    if not isAdmin(client) or not validType(t) or not validIdx(t, a) or not validIdx(t, b) or a == b then return end
    saveLink(t, a, b, removed and true or false)
    broadcast({ op = "link", t = t, a = a, b = b, removed = removed and true or false })
end)
