--[[
    rp_admin / s_move.lua
    Guardar lo que un admin mueve con el editor (c_move.lua) y borrar desde el menu del cursor.

    Eventos cliente -> servidor (con `client`, solo admin nivel 1+):
        rp:admin:move:save (key, id, part, x, y, z, rot)
            key = clave de WORLD_TYPES, part = "exit" para la salida interior de una casa.
            Revalida: mismo interior y dimension, que exista, que no salte mas de MOVE_MAX metros
            y que el admin este cerca del destino. Lo guarda el recurso dueno con su export
            adminMove(id, kind, x, y, z, rot, admin, part) -> true | false, motivo.
        rp:admin:world:delete (key, id)   igual que /del<tipo> <id>
    Respuesta: rp:admin:move:result (ok, motivo) al cliente que movio.
]]

local MOVE_MAX = 60        -- metros desde donde estaba (para mas, /del y crear de nuevo)
local ADMIN_RANGE = 120    -- el admin tiene que estar cerca de donde lo deja
local COOLDOWN_MS = 500

local lastAction = {}

local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

local function cooled(player)
    local now = getTickCount()
    if lastAction[player] and now - lastAction[player] < COOLDOWN_MS then return false end
    lastAction[player] = now
    return true
end

-- Posicion actual del elemento (o de su salida) segun el recurso dueno. Un mismo ID puede estar
-- en varias dimensiones (salida compartida de un interior, rp_markers): se prefiere la del admin.
local function current(t, id, part, player)
    local r = getResourceFromName(t.res)
    if not r or getResourceState(r) ~= "running" then return nil, nil, "no esta en marcha " .. t.res end
    local ok, list = pcall(call, r, "adminElements", t.kind)
    if not ok or type(list) ~= "table" then return nil, nil, "no responde " .. t.res end
    local found
    for _, e in ipairs(list) do
        if tonumber(e.id) == id then
            local cur = e
            if part == "exit" then cur = type(e.exit) == "table" and e.exit or nil end
            if cur then
                if not isElement(player) or (tonumber(cur.interior) == getElementInterior(player)
                    and tonumber(cur.dimension) == getElementDimension(player)) then
                    return cur, r
                end
                found = found or cur
            end
        end
    end
    if found then return found, r end
    return nil, r, "no existe"
end

addEvent("rp:admin:move:save", true)
addEventHandler("rp:admin:move:save", resourceRoot, function(key, id, part, x, y, z, rot)
    local player = client
    if not player or levelOf(player) < LEVEL_ADMIN then return end
    local function fail(why)
        triggerClientEvent(player, "rp:admin:move:result", resourceRoot, false, why)
    end
    if not cooled(player) then return fail("Espera un momento.") end

    local t = type(key) == "string" and worldTypeByKey(key)
    id, x, y, z, rot = tonumber(id), tonumber(x), tonumber(y), tonumber(z), tonumber(rot)
    part = part == "exit" and "exit" or nil
    if not t or not id or not (finite(x) and finite(y) and finite(z) and finite(rot))
        or math.abs(x) >= 30000 or math.abs(y) >= 30000 or z < -100 or z > 5000 then
        return fail("Datos de posicion no validos.")
    end

    local cur, res, why = current(t, id, part, player)
    if not cur then return fail(why or "No existe.") end
    if tonumber(cur.interior) ~= getElementInterior(player) or tonumber(cur.dimension) ~= getElementDimension(player) then
        return fail("Tienes que estar en el mismo interior y dimension.")
    end
    if getDistanceBetweenPoints3D(x, y, z, tonumber(cur.x), tonumber(cur.y), tonumber(cur.z)) > MOVE_MAX then
        return fail(("No se puede mover mas de %d m de una vez."):format(MOVE_MAX))
    end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > ADMIN_RANGE then
        return fail("Estas demasiado lejos de donde lo dejas.")
    end

    rot = rot % 360
    local ok, done, reason = pcall(call, res, "adminMove", id, t.kind, x, y, z, rot, player, part)
    if not ok then return fail(t.res .. " no permite mover (falta adminMove).") end
    if not done then return fail(reason and ("No se pudo: " .. reason .. ".") or "No se pudo mover.") end

    -- NPC recien creado: fijar su giro de forma explicita (conformPedRotation), porque el cliente
    -- que lo sincroniza puede traer otro giro (p. ej. el de la vista previa del editor)
    local now = current(t, id, part, player)
    if now and isElement(now.element) and getElementType(now.element) == "ped" then
        setElementRotation(now.element, 0, 0, rot, "default", true)
    end

    logAction(player, "mover", nil, ("%s #%d%s -> %.2f %.2f %.2f rot %.0f"):format(t.key, id,
        part and " (salida)" or "", x, y, z, rot))
    triggerClientEvent(player, "rp:admin:move:result", resourceRoot, true)
    notify(player, ("%s #%d movido."):format(t.name, id), "success")
end)

addEvent("rp:admin:world:delete", true)
addEventHandler("rp:admin:world:delete", resourceRoot, function(key, id)
    local player = client
    if not player or levelOf(player) < LEVEL_ADMIN or not cooled(player) then return end
    local t = type(key) == "string" and worldTypeByKey(key)
    id = tonumber(id)
    if not t or not id then return end
    local cur = current(t, id, nil, player)
    if not cur then return notify(player, "Ya no existe.", "warning") end
    if tonumber(cur.interior) ~= getElementInterior(player) or tonumber(cur.dimension) ~= getElementDimension(player) then
        return notify(player, "Tienes que estar en el mismo interior y dimension.", "warning")
    end
    if worldDelete(player, key, id) then
        notify(player, ("%s #%d eliminado."):format(t.name, id), "success")
    end
end)

addEventHandler("onPlayerQuit", root, function() lastAction[source] = nil end)
