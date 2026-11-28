--[[
    rp_admin / s_world.lua
    Gramatica de comandos de OwlGaming para los elementos que colocan los admins.
    Cada tipo de WORLD_TYPES genera solo estos comandos:

        /nearby<plural> [radio]      lista los cercanos con su ID (por defecto 20 m)
        /goto<tipo> <id>             ir hasta uno
        /del<tipo> <id>              borrarlo (fila en BD y mundo)
        /delthis<tipo>               borrar el mas cercano a menos de 5 m
        /delnearby<plural> [radio]   borrar todos los cercanos (super admin, radio max 20 m)
        /nearby [radio]              todos los tipos juntos, mas los vehiculos

    Cada recurso dueno expone dos exports de servidor (los datos siguen siendo suyos):
        adminElements(kind) -> { { id, x, y, z, interior, dimension, label }, ... }
        adminDelete(id, kind) -> true | false, motivo
        adminMove(id, kind, x, y, z, rot, admin, part) -> true | false, motivo   (editor de c_move.lua)
    `kind` solo lo usan los recursos con varios tipos (rp_gym). Si el recurso esta parado,
    sus comandos responden que no esta en marcha.

    Campos opcionales de cada elemento, para la vista con ALT (s_inspect.lua):
        ownerId (characters.id), creator (nombre), createdAt, info (texto extra),
        rot (giro Z), noRot (no guarda giro), element (elemento principal, para la vista previa),
        exit = { x, y, z, interior, dimension } (salida interior de una casa)
    `create` es el comando que crea el tipo: s_inspect.lua lo vigila para guardar que admin lo creo.
]]

WORLD_TYPES = {
    { key = "atm",           many = "atms",           res = "rp_bank",       name = "Cajero", create = "crearatm" },
    { key = "shop",          many = "shops",          res = "rp_shops",      name = "Tienda", create = "crearshop" },
    { key = "house",         many = "houses",         res = "rp_properties", name = "Casa", create = "crearcasa" },
    { key = "clothingstore", many = "clothingstores", res = "rp_clothing",   name = "Tienda de ropa", create = "crearropa" },
    { key = "vending",       many = "vendings",       res = "rp_vending",    name = "Expendedora", create = "crearexpendedora" },
    { key = "dealer",        many = "dealers",        res = "rp_dealers",    name = "Traficante", create = "creartraficante" },
    { key = "robstore",      many = "robstores",      res = "rp_robbery",    name = "Tienda robable", create = "crearrobo" },
    { key = "gymmachine",    many = "gymmachines",    res = "rp_gym",        name = "Maquina de gimnasio", kind = "machine", create = "crearmaquina" },
    { key = "trainer",       many = "trainers",       res = "rp_gym",        name = "Entrenador", kind = "trainer", create = "crearentrenador" },
    { key = "school",        many = "schools",        res = "rp_driving",    name = "Autoescuela", create = "crearautoescuela" },
    { key = "pooltable",     many = "pooltables",     res = "rp_pool",       name = "Mesa de pool", create = "crearmesapool" },
    { key = "crossing",      many = "crossings",      res = "rp_train",      name = "Barrera de tren", create = "crearbarrera" },
    { key = "ticketbooth",   many = "ticketbooths",   res = "rp_train",      name = "Boleteria de tren", kind = "booth", create = "crearboleteria" },
    { key = "trainsign",     many = "trainsigns",     res = "rp_train",      name = "Cartel LED de tren", kind = "sign", create = "crearcartel" },
    { key = "turnstile",     many = "turnstiles",     res = "rp_train",      name = "Torniquete de tren", kind = "gate", create = "creartorniquete" },
    { key = "stationfence",  many = "stationfences",  res = "rp_train",      name = "Reja de estacion", kind = "fence", create = "crearreja" },
    { key = "metropole",     many = "metropoles",     res = "rp_train",      name = "Poste de metro", kind = "pole", create = "crearpostemetro" },
    { key = "flowerclock",   many = "flowerclocks",   res = "rp_relojflores", name = "Reloj de flores", create = "crearrelojflores" },
    { key = "locker",        many = "lockers",        res = "rp_factionduty", name = "Vestuario de faccion", create = "makelocker" },
    { key = "3dtext",        many = "3dtexts",        res = "rp_3dtext",     name = "Texto 3D", create = "create3dtext" },
    { key = "marker",        many = "markers",        res = "rp_markers",    name = "Marcador" },
}

local NEARBY_RADIUS, NEARBY_MAX = 20, 500
local DELTHIS_RADIUS = 5
local DELNEARBY_RADIUS, DELNEARBY_MAX = 5, 20
local LIST_MAX = 20

local function running(t)
    local r = getResourceFromName(t.res)
    return r and getResourceState(r) == "running" and r
end

-- Elementos del tipo en el mismo interior y dimension que el admin, ordenados por distancia
local function near(player, t, radius)
    local r = running(t)
    if not r then return nil end
    local ok, list = pcall(call, r, "adminElements", t.kind)
    if not ok or type(list) ~= "table" then return nil end
    local px, py, pz = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)
    local out = {}
    for _, e in ipairs(list) do
        if tonumber(e.interior) == int and tonumber(e.dimension) == dim then
            local d = getDistanceBetweenPoints3D(px, py, pz, e.x, e.y, e.z)
            if d <= radius then e.d = d out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function findById(t, id)
    local r = running(t)
    if not r then return nil end
    local ok, list = pcall(call, r, "adminElements", t.kind)
    if not ok or type(list) ~= "table" then return nil end
    for _, e in ipairs(list) do
        if tonumber(e.id) == id then return e end
    end
end

local function notRunning(player, t)
    notify(player, ("%s no esta en marcha."):format(t.res), "error")
end

local function deleteOne(player, t, id, cmd)
    -- el admin va como 3er argumento para los recursos que auditan quien borra (rp_3dtext)
    local ok, done, why = pcall(call, running(t), "adminDelete", id, t.kind, player)
    if not ok or not done then
        notify(player, ("No se pudo borrar %s #%d%s"):format(t.name:lower(), id, why and (": " .. why) or "."), "error")
        return false
    end
    if forgetCreator then forgetCreator(t.key, id) end
    logAction(player, cmd, nil, ("%s #%d"):format(t.key, id))
    return true
end

local function parseRadius(value, default, max)
    if value == nil then return default end
    local r = tonumber(value)
    if not r or r <= 0 or r > max then return nil end
    return r
end

local function printList(player, title, list, withType)
    outputChatBox(title, player, 255, 126, 0)
    if #list == 0 then return outputChatBox("   Ninguno.", player, 255, 126, 0) end
    for i, e in ipairs(list) do
        if i > LIST_MAX then
            return outputChatBox(("   ... y %d mas. Reduce el radio."):format(#list - LIST_MAX), player, 180, 180, 180)
        end
        outputChatBox(("   %sID %d: %s - %.0f m"):format(withType and (e.typeName .. " ") or "", e.id,
            e.label or "", e.d), player, 255, 255, 255)
    end
end

for _, t in ipairs(WORLD_TYPES) do
    addCommandHandler("nearby" .. t.many, function(player, cmd, radius)
        if not guard(player) then return end
        radius = parseRadius(radius, NEARBY_RADIUS, NEARBY_MAX)
        if not radius then return notify(player, ("Uso: /%s [radio 1-%d]"):format(cmd, NEARBY_MAX), "warning") end
        local list = near(player, t, radius)
        if not list then return notRunning(player, t) end
        printList(player, ("%s a menos de %d m:"):format(t.name, radius), list)
    end)

    addCommandHandler("goto" .. t.key, function(player, cmd, id)
        if not guard(player) then return end
        id = tonumber(id)
        if not id then return notify(player, ("Uso: /%s <id> (mira /nearby%s)"):format(cmd, t.many), "warning") end
        if not running(t) then return notRunning(player, t) end
        local e = findById(t, id)
        if not e then return notify(player, ("No existe %s #%d."):format(t.name:lower(), id), "warning") end
        moveTo(player, e.x + 1, e.y, e.z + 0.5, tonumber(e.interior) or 0, tonumber(e.dimension) or 0)
        notify(player, ("Fuiste hasta %s #%d."):format(t.name:lower(), id), "success")
        logAction(player, cmd, nil, ("%s #%d"):format(t.key, id))
    end)

    addCommandHandler("del" .. t.key, function(player, cmd, id)
        if not guard(player) then return end
        id = tonumber(id)
        if not id then return notify(player, ("Uso: /%s <id> (mira /nearby%s)"):format(cmd, t.many), "warning") end
        if not running(t) then return notRunning(player, t) end
        if deleteOne(player, t, id, cmd) then
            notify(player, ("%s #%d eliminado."):format(t.name, id), "success")
        end
    end)

    addCommandHandler("delthis" .. t.key, function(player, cmd)
        if not guard(player) then return end
        local list = near(player, t, DELTHIS_RADIUS)
        if not list then return notRunning(player, t) end
        local e = list[1]
        if not e then return notify(player, ("No hay ningun %s a menos de %d m."):format(t.name:lower(), DELTHIS_RADIUS), "warning") end
        if deleteOne(player, t, tonumber(e.id), cmd) then
            notify(player, ("%s #%d eliminado."):format(t.name, e.id), "success")
        end
    end)

    addCommandHandler("delnearby" .. t.many, function(player, cmd, radius)
        if not guard(player, LEVEL_SUPER) then return end
        radius = parseRadius(radius, DELNEARBY_RADIUS, DELNEARBY_MAX)
        if not radius then return notify(player, ("Uso: /%s [radio 1-%d]"):format(cmd, DELNEARBY_MAX), "warning") end
        local list = near(player, t, radius)
        if not list then return notRunning(player, t) end
        local n = 0
        for _, e in ipairs(list) do
            if deleteOne(player, t, tonumber(e.id), cmd) then n = n + 1 end
        end
        notify(player, ("%d %s eliminados a menos de %d m."):format(n, t.name:lower(), radius), n > 0 and "success" or "info")
    end)
end

-- /nearby [radio]: todos los tipos y los vehiculos, en una sola lista
addCommandHandler("nearby", function(player, cmd, radius)
    if not guard(player) then return end
    radius = parseRadius(radius, NEARBY_RADIUS, NEARBY_MAX)
    if not radius then return notify(player, ("Uso: /%s [radio 1-%d]"):format(cmd, NEARBY_MAX), "warning") end
    local all = {}
    for _, t in ipairs(WORLD_TYPES) do
        for _, e in ipairs(near(player, t, radius) or {}) do
            e.typeName = t.name
            all[#all + 1] = e
        end
    end
    local veh = getResourceFromName("rp_vehicles")
    if veh and getResourceState(veh) == "running" then
        local px, py, pz = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        for _, v in ipairs(getElementsByType("vehicle")) do
            if getElementInterior(v) == int and getElementDimension(v) == dim then
                local x, y, z = getElementPosition(v)
                local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                local id = d <= radius and exports.rp_vehicles:getVehicleDatabaseId(v)
                if id then
                    all[#all + 1] = { id = id, d = d, typeName = "Vehiculo", label = getVehicleName(v) }
                elseif d <= radius then
                    local tempId = exports.rp_vehicles:getTempVehicleId(v)
                    if tempId then
                        all[#all + 1] = { id = tempId, d = d, typeName = "Vehiculo temporal", label = getVehicleName(v) }
                    end
                end
            end
        end
    end
    table.sort(all, function(a, b) return a.d < b.d end)
    printList(player, ("Elementos a menos de %d m (vehiculos: /gotoveh, /getveh):"):format(radius), all, true)
end)

-- Para el menu de admin del cursor (s_move.lua): borra por clave de tipo con el mismo registro que /del<tipo>
function worldTypeByKey(key)
    for _, t in ipairs(WORLD_TYPES) do
        if t.key == key then return t end
    end
end

function worldDelete(player, key, id)
    local t = worldTypeByKey(key)
    if not t or not running(t) then return false end
    return deleteOne(player, t, id, "del" .. t.key)
end
