--[[
    rp_vehicles / s_adminspawn.lua
    Creacion de vehiculos por admins.

        /veh <modelo|nombre> [R G B]               (admin 1+) vehiculo TEMPORAL con ID negativo (-1, -2...).
                                                   No se guarda en la BD: desaparece con /delveh o al reiniciar.
        /delveh [id]                               (admin 1+) borra un vehiculo temporal (el tuyo, el que
                                                   ocupas o el mas cercano si no das id).
        /makeveh <modelo|nombre> <jugador> [R G B] vehiculo REAL (tabla vehicles) cuyo dueno es el personaje
                                                   del jugador; recibe la llave. Super admin o permiso
                                                   "vehicles.create" del panel (IAM de rp_adminpanel).

    El vehiculo aparece unos metros delante de donde mira el admin, en su interior y dimension.

    Auditoria: cada temporal guarda quien lo creo (cuenta, personaje, serial, fecha) en
    temps[vehicle] y en el elementData "rp:createdBy" (sin sincronizar con los clientes),
    y todas las creaciones y borrados quedan en admin_log y server.log.

    Exports: getTempVehicleId(vehicle) -> id negativo | false
             getTempVehicleInfo(vehicle) -> { id, model, createdBy = {...}, createdAt } | false
]]

local temps = {}       -- [vehicle] = { id, model, createdBy = {...}, createdAt }
local tempById = {}    -- [id negativo] = vehicle
local lastTempId = 0

local function admLevel(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end

local function noPermission(player)
    notify(player, "No tienes permiso para usar este comando.", "error")
end

-- Registro en admin_log (tabla de rp_admin) y server.log
local function logAdmin(admin, command, target, details)
    outputServerLog(("[rp_vehicles] %s (cuenta #%s) /%s%s | %s"):format(getPlayerName(admin),
        tostring(exports.rp_login:getPlayerAccountId(admin) or "-"), command,
        target and (" -> " .. getPlayerName(target)) or "", details))
    dbExec(db(), [[INSERT INTO admin_log (admin_account_id, admin_name, command, target_account_id,
                   target_character_id, target_name, details)
                   VALUES (NULLIF(?, 0), ?, ?, NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, ''), NULLIF(?, ''))]],
        exports.rp_login:getPlayerAccountId(admin) or 0, getPlayerName(admin), command,
        target and exports.rp_login:getPlayerAccountId(target) or 0,
        target and characterOf(target) or 0,
        target and getPlayerName(target) or "", details:sub(1, 255))
end

----------------------------------------------------------------
-- Argumentos
----------------------------------------------------------------
-- Modelo por ID (400-611) o por nombre: exacto primero, si no el unico que lo contenga
local function parseModel(text)
    if not text or text == "" then return nil end
    local n = tonumber(text)
    if n then return (getVehicleNameFromModel(n) or "") ~= "" and n or nil end
    local exact = getVehicleModelFromName(text)
    if exact then return exact end
    local q, found = text:lower(), nil
    for model = 400, 611 do
        local name = getVehicleNameFromModel(model)
        if name and name ~= "" and name:lower():find(q, 1, true) then
            if found then return nil, "ambiguous" end
            found = model
        end
    end
    return found
end

-- Si los 3 ultimos argumentos son numeros 0-255 (y quedan al menos `minRest` antes), son el color
local function splitColor(args, minRest)
    local n = #args
    if n >= minRest + 3 then
        local r, g, b = tonumber(args[n - 2]), tonumber(args[n - 1]), tonumber(args[n])
        if r and g and b then
            for _, c in ipairs({ r, g, b }) do
                if c < 0 or c > 255 or c ~= math.floor(c) then return nil, "color" end
            end
            return { r, g, b }, n - 3
        end
    end
    return { 245, 245, 245 }, n
end

local function joinArgs(args, from, to)
    local out = {}
    for i = from, to do out[#out + 1] = args[i] end
    return table.concat(out, " ")
end

-- Punto unos metros delante de donde mira el admin (o su vehiculo)
local function spawnPointFor(player, model)
    local veh = getPedOccupiedVehicle(player)
    local ref = veh or player
    local x, y, z = getElementPosition(ref)
    local _, _, rz = getElementRotation(ref)
    local a = math.rad(rz)
    local ahead = veh and 7 or 5
    local vtype = getVehicleType(model)
    if vtype == "Plane" or vtype == "Helicopter" then ahead = ahead + 6 end
    return x - math.sin(a) * ahead, y + math.cos(a) * ahead, z + 0.6, (rz + 90) % 360,
        getElementInterior(player), getElementDimension(player)
end

local function modelLabel(model) return ("%s (%d)"):format(getVehicleNameFromModel(model) or "?", model) end

----------------------------------------------------------------
-- Temporales
----------------------------------------------------------------
function getTempVehicleById(id) return tempById[tonumber(id)] end
function getTempVehicleId(vehicle) return temps[vehicle] and temps[vehicle].id or false end
function getTempVehicleInfo(vehicle) return temps[vehicle] or false end

local function countTempsBy(accountId)
    local n = 0
    for _, t in pairs(temps) do
        if t.createdBy.accountId == accountId then n = n + 1 end
    end
    return n
end

addCommandHandler("veh", function(player, cmd, ...)
    if admLevel(player) < 1 then return noPermission(player) end
    local usage = "Uso: /veh <modelo o nombre> [R G B] (ej: /veh 411 255 0 0, /veh infernus)"
    local args = { ... }
    local color, rest = splitColor(args, 1)
    if not color then return notify(player, "Los colores R G B van de 0 a 255.", "warning") end
    if rest < 1 then return notify(player, usage, "warning") end
    local model, why = parseModel(joinArgs(args, 1, rest))
    if not model then
        return notify(player, why == "ambiguous" and "Varios modelos coinciden: escribe el nombre completo o el ID (400-611)."
            or usage, "warning")
    end

    local accountId = exports.rp_login:getPlayerAccountId(player) or 0
    if countTempsBy(accountId) >= VEHICLES.TEMP_MAX_PER_ADMIN then
        return notify(player, ("Ya tienes %d vehiculos temporales. Borra alguno con /delveh <id>."):format(VEHICLES.TEMP_MAX_PER_ADMIN), "warning")
    end

    local x, y, z, rz, int, dim = spawnPointFor(player, model)
    local v = createVehicle(model, x, y, z, 0, 0, rz, "ADMIN")
    if not v then return notify(player, "No se pudo crear el vehiculo.", "error") end
    setElementInterior(v, int)
    setElementDimension(v, dim)
    setVehicleColor(v, color[1], color[2], color[3], color[1], color[2], color[3])

    lastTempId = lastTempId - 1
    local info = {
        id = lastTempId, model = model,
        createdAt = os.date("%Y-%m-%d %H:%M:%S"),
        createdBy = {
            accountId = accountId,
            account = exports.rp_login:getPlayerAccountName(player) or "-",
            player = getPlayerName(player),
            characterId = characterOf(player) or false,
            serial = getPlayerSerial(player),
            adminLevel = admLevel(player),
        },
    }
    temps[v] = info
    tempById[info.id] = v
    setElementData(v, "rp:tempVehicleId", info.id)            -- sincronizado: solo el numero
    setElementData(v, "rp:createdBy", info.createdBy, false)  -- solo servidor: auditoria

    logAdmin(player, "veh", nil, ("temporal #%d %s rgb %d,%d,%d en %.1f,%.1f,%.1f int %d dim %d"):format(
        info.id, modelLabel(model), color[1], color[2], color[3], x, y, z, int, dim))
    notify(player, ("Vehiculo temporal #%d creado: %s. Borralo con /delveh %d."):format(info.id, modelLabel(model), info.id), "success")
end)

-- /delveh [id]: solo temporales (los reales no se borran con esto)
addCommandHandler("delveh", function(player, cmd, id)
    if admLevel(player) < 1 then return noPermission(player) end
    local v
    if id then
        v = tonumber(id) and tempById[tonumber(id)]
        if not v then return notify(player, "Uso: /delveh <id negativo> (solo vehiculos temporales de /veh)", "warning") end
    else
        local occupied = getPedOccupiedVehicle(player)
        v = occupied and temps[occupied] and occupied
        if not v then
            local bestDist = 10
            for tv in pairs(temps) do
                local d = distanceTo(player, tv)
                if d < bestDist then v, bestDist = tv, d end
            end
        end
        if not v then return notify(player, "No hay vehiculos temporales a menos de 10 m. Uso: /delveh <id>", "warning") end
    end
    local info = temps[v]
    logAdmin(player, "delveh", nil, ("temporal #%d %s creado por %s (cuenta #%d) el %s"):format(
        info.id, modelLabel(info.model), info.createdBy.account, info.createdBy.accountId, info.createdAt))
    destroyElement(v)
    notify(player, ("Vehiculo temporal #%d borrado."):format(info.id), "success")
end)

addEventHandler("onElementDestroy", root, function()
    local info = temps[source]
    if info then
        tempById[info.id] = nil
        temps[source] = nil
    end
end)

----------------------------------------------------------------
-- Vehiculos reales
----------------------------------------------------------------
local SUPER_LEVEL = 3

-- Super admin, o permiso "vehicles.create" dado desde el panel (rp_adminpanel puede no estar en marcha)
local function canMakeVehicle(player)
    if admLevel(player) >= SUPER_LEVEL then return true end
    local ok, allowed = pcall(function() return exports.rp_adminpanel:hasPermission(player, "vehicles.create") end)
    return ok and allowed == true
end

addCommandHandler("makeveh", function(player, cmd, ...)
    if not canMakeVehicle(player) then return noPermission(player) end
    local usage = "Uso: /makeveh <modelo o nombre> <id o nombre del dueno> [R G B]"
    local args = { ... }
    local color, rest = splitColor(args, 2)
    if not color then return notify(player, "Los colores R G B van de 0 a 255.", "warning") end
    if rest < 2 then return notify(player, usage, "warning") end
    local model, why = parseModel(joinArgs(args, 1, rest - 1))
    if not model then
        return notify(player, why == "ambiguous" and "Varios modelos coinciden: escribe el nombre completo o el ID (400-611)."
            or usage, "warning")
    end
    local target = exports.rp_ids:findPlayer(args[rest])
    if not target then return notify(player, "No se encontro a ese jugador. " .. usage, "warning") end
    local characterId = characterOf(target)
    if not characterId then return notify(player, displayName(target) .. " no tiene un personaje en juego.", "warning") end

    local x, y, z, rz, int, dim = spawnPointFor(player, model)
    insertOwnedVehicle(target, characterId, model, color, x, y, z, rz, int, dim, function(vehicle, id)
        if not isElement(player) then return end
        if not vehicle then return notify(player, "No se pudo crear el vehiculo (error de base de datos).", "error") end
        logAdmin(player, "makeveh", isElement(target) and target or nil,
            ("vehiculo #%d %s dueno personaje #%d rgb %d,%d,%d en %.1f,%.1f,%.1f int %d dim %d"):format(
            id, modelLabel(model), characterId, color[1], color[2], color[3], x, y, z, int, dim))
        notify(player, ("Vehiculo #%d (%s) creado para %s."):format(id, modelLabel(model),
            isElement(target) and displayName(target) or ("personaje #" .. characterId)), "success")
        if isElement(target) then
            notify(target, ("Un administrador te dio un %s. La llave esta en tu inventario (si no cabe, usa /copiallave)."):format(
                getVehicleNameFromModel(model) or "vehiculo"), "info")
        end
    end)
end)
