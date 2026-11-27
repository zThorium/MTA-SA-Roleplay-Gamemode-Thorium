--[[
    rp_robbery / s_admin.lua
    Comandos de administracion (admin_level >= 1):
        /crearrobo <tipo> <nombre>   crea una tienda robable: parate en la puerta, de espaldas a ella (mirando a la calle)
        /borrarrobo <id>             la elimina
        /robos                       lista de tiendas y su estado
        /tiposrobo                   tipos de interior 24/7
        /robopunto <id> <punto>      corrige un punto parado en el sitio correcto:
                                     puerta (fuera, mirando a la calle), salida, cajero (mirando a los clientes),
                                     caja, cliente (anade un sitio de cliente, max 4), clientes (borra los sitios)
        /resetrobo <id>              termina el robo en curso, quita la espera y repone cajero y clientes
]]

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function db() return exports.rp_database:getConnection() end

local function denied(player)
    notify(player, "No tienes permiso para usar este comando.", "error")
end

local function rotOf(player)
    local _, _, rz = getElementRotation(player)
    return math.floor(rz * 10 + 0.5) / 10
end

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

addCommandHandler("crearrobo", function(player, _, kind, ...)
    if not isAdmin(player) then return denied(player) end
    local name = table.concat({ ... }, " ")
    if not kind or not ROBBERY_TYPES[kind] or #name < 3 or #name > 48 then
        return notify(player, "Uso: /crearrobo <tipo> <nombre> (tipos: /tiposrobo). Parate en la puerta mirando a la calle.", "warning")
    end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        return notify(player, "La puerta tiene que estar en el mundo exterior.", "warning")
    end
    local x, y, z = getElementPosition(player)
    insertStore(name, kind, round(x), round(y), round(z), rotOf(player), function(id)
        if not id then return notify(player, "No se pudo crear la tienda.", "error") end
        notify(player, ("Tienda robable #%d creada (%s). Entra y ajusta cajero y caja con /robopunto."):format(id, name), "success")
        local r = math.rad(rotOf(player))
        setElementPosition(player, x - math.sin(r) * 2.5, y + math.cos(r) * 2.5, z)
    end)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbyrobstores, /gotorobstore, /delrobstore...)
function adminElements()
    local list = {}
    for id, e in pairs(STORES) do
        local row = e.row
        if row then
            list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                interior = 0, dimension = 0, label = row.name,
                rot = tonumber(row.rot) or 0, element = e.pickup }
        end
    end
    return list
end

function adminDelete(id)
    id = tonumber(id)
    local store = id and STORES[id]
    if not store then return false, "no existe" end
    if store.robbery then endRobbery(store.robbery, "admin") end
    dbExec(db(), "DELETE FROM robbery_stores WHERE id = ?", id)
    destroyStore(id)
    return true
end

-- Mover la entrada desde el editor de rp_admin (vista ALT); no durante un robo
function adminMove(id, _, x, y, z, rot)
    id = tonumber(id)
    local store = id and STORES[id]
    if not store then return false, "no existe" end
    if store.robbery then return false, "hay un robo en curso" end
    local row = store.row
    row.x, row.y, row.z, row.rot = x, y, z, rot
    row.points = toJSON(store.points or {}, true)   -- conservar los puntos editados desde la carga
    dbExec(db(), "UPDATE robbery_stores SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", x, y, z, rot, id)
    spawnStore(row)
    return true
end

addCommandHandler("borrarrobo", function(player, _, id)
    if not isAdmin(player) then return denied(player) end
    id = tonumber(id)
    if not id or not adminDelete(id) then return notify(player, "Uso: /borrarrobo <id> (mira /robos)", "warning") end
    notify(player, ("Tienda robable #%d borrada."):format(id), "success")
end)

addCommandHandler("tiposrobo", function(player)
    if not isAdmin(player) then return denied(player) end
    outputChatBox("Tipos de tienda robable:", player, 245, 165, 36)
    local keys = {}
    for k in pairs(ROBBERY_TYPES) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local t = ROBBERY_TYPES[k]
        outputChatBox(("  %s - %s (interior %d, x%.1f botin)"):format(k, t.name, t.interior, t.multiplier), player, 220, 220, 220)
    end
end)

addCommandHandler("robos", function(player)
    if not isAdmin(player) then return denied(player) end
    local ids = {}
    for id in pairs(STORES) do ids[#ids + 1] = id end
    table.sort(ids)
    outputChatBox(("Tiendas robables (%d):"):format(#ids), player, 245, 165, 36)
    local now = getTickCount()
    for _, id in ipairs(ids) do
        local s = STORES[id]
        local status = "disponible"
        if s.robbery then
            status = ("ROBO EN CURSO (%s, %s)"):format(getPlayerName(s.robbery.player), s.robbery.state)
        elseif s.cooldownUntil and now < s.cooldownUntil then
            status = ("vacia, %d min"):format(math.ceil((s.cooldownUntil - now) / 60000))
        end
        outputChatBox(("  #%d %s [%s] - %s"):format(id, s.row.name, s.row.type, status), player, 220, 220, 220)
    end
end)

local POINTS = { puerta = true, salida = "exit", cajero = "clerk", caja = "register", cliente = "customers", clientes = "customers" }

addCommandHandler("robopunto", function(player, _, id, which)
    if not isAdmin(player) then return denied(player) end
    id = tonumber(id)
    local store = id and STORES[id]
    if not store or not which or not POINTS[which] then
        return notify(player, "Uso: /robopunto <id> puerta|salida|cajero|caja|cliente|clientes", "warning")
    end
    if store.robbery then return notify(player, "Hay un robo en curso en esa tienda.", "warning") end
    local x, y, z = getElementPosition(player)
    local p = { x = round(x), y = round(y), z = round(z), rot = rotOf(player) }

    if which == "puerta" then
        if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
            return notify(player, "La puerta se marca desde fuera.", "warning")
        end
        dbExec(db(), "UPDATE robbery_stores SET x = ?, y = ?, z = ?, rot = ? WHERE id = ?", p.x, p.y, p.z, p.rot, id)
        store.row.x, store.row.y, store.row.z, store.row.rot = p.x, p.y, p.z, p.rot
    else
        if getPlayerStore(player) ~= store then
            return notify(player, "Tienes que estar dentro de esa tienda.", "warning")
        end
        local key = POINTS[which]
        if which == "clientes" then
            store.points.customers = {}
        elseif which == "cliente" then
            local list = store.points.customers or {}
            if #list >= 4 then return notify(player, "Maximo 4 sitios de cliente. Borralos con /robopunto <id> clientes.", "warning") end
            list[#list + 1] = p
            store.points.customers = list
        else
            store.points[key] = p
        end
        saveStorePoints(store)
    end
    -- Rehace la tienda con los puntos nuevos (vuelve a crear pickup, salida y NPCs)
    local row = store.row
    row.points = toJSON(store.points, true)
    local cooldown = store.cooldownUntil
    local fresh = spawnStore(row)
    if fresh then fresh.cooldownUntil = cooldown end
    if which ~= "puerta" and which ~= "salida" then
        local r = math.rad(p.rot)
        setElementPosition(player, x - math.sin(r) * 1.2, y + math.cos(r) * 1.2, z)
    end
    notify(player, ("Punto '%s' de la tienda #%d guardado."):format(which, id), "success")
end)

addCommandHandler("resetrobo", function(player, _, id)
    if not isAdmin(player) then return denied(player) end
    id = tonumber(id)
    local store = id and STORES[id]
    if not store then return notify(player, "Uso: /resetrobo <id>", "warning") end
    resetStore(store)
    notify(player, ("Tienda #%d reiniciada."):format(id), "success")
end)
