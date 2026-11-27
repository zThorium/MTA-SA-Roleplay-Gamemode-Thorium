--[[
    rp_vehicles / s_admin.lua
    Comandos de administracion de vehiculos (nivel de admin 1 o mas).
    <id> es el ID del vehiculo en la base de datos (el que muestra /nearbyvehs).
    Si no se da, se usa el vehiculo en el que estas o el mas cercano.

        /nearbyvehs [radio]     vehiculos cercanos con ID, modelo, matricula y dueno
        /fixveh [id]            repara
        /blowveh [id]           explota
        /getveh <id>            trae el vehiculo a tu lado
        /gotoveh <id>           te lleva junto al vehiculo
        /vehinfo [id]           datos del vehiculo
        /nearbytalleres [radio] talleres de tuning cercanos con su numero
        /movertaller <numero>   mueve un taller a donde esta tu auto (ver s_tuning.lua)
]]

local function chat(player, text, r, g, b)
    outputChatBox(text, player, r or 245, g or 165, b or 36)
end

local function guard(player)
    if isAdmin(player) then return true end
    notify(player, "No tienes permiso para usar este comando.", "error")
    return false
end

-- Vehiculo por ID, o el ocupado, o el mas cercano (10 m)
local function resolveVehicle(player, id)
    id = tonumber(id)
    if id then return getVehicleById(id) end
    local occupied = getPedOccupiedVehicle(player)
    if occupied then return occupied end
    local best, bestDist = nil, 10
    for _, v in ipairs(getElementsByType("vehicle")) do
        local d = distanceTo(player, v)
        if d < bestDist then best, bestDist = v, d end
    end
    return best
end

local function label(v)
    local data = getVehicleData(v)
    local id = data and data.id or (getTempVehicleId and getTempVehicleId(v)) or "-"
    return ("#%s %s (%s)"):format(id, getVehicleName(v) or "?", getVehiclePlateText(v) or "")
end

addCommandHandler("nearbyvehs", function(player, _, radius)
    if not guard(player) then return end
    radius = math.min(500, tonumber(radius) or 30)
    local found = {}
    for _, v in ipairs(getElementsByType("vehicle")) do
        local d = distanceTo(player, v)
        if d <= radius then found[#found + 1] = { v = v, d = d } end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    if #found == 0 then return chat(player, ("No hay vehiculos a menos de %d m."):format(radius)) end
    chat(player, ("Vehiculos a menos de %d m (%d):"):format(radius, #found))
    for i = 1, math.min(#found, 15) do
        local v = found[i].v
        local data = getVehicleData(v)
        chat(player, ("  %s - %.0f m%s%s"):format(label(v), found[i].d,
            data and (" - dueno #" .. data.ownerId)
                or (getTempVehicleInfo(v) and (" - temporal de " .. getTempVehicleInfo(v).createdBy.account) or " - sin dueno"),
            data and (data.locked and " - cerrado" or " - abierto") or ""), 255, 255, 255)
    end
end)

addCommandHandler("fixveh", function(player, _, id)
    if not guard(player) then return end
    local v = resolveVehicle(player, id)
    if not v then return notify(player, "No se encontro el vehiculo.", "warning") end
    fixVehicle(v)
    saveVehicle(v)
    notify(player, "Vehiculo " .. label(v) .. " reparado.", "success")
end)

addCommandHandler("blowveh", function(player, _, id)
    if not guard(player) then return end
    local v = resolveVehicle(player, id)
    if not v then return notify(player, "No se encontro el vehiculo.", "warning") end
    blowVehicle(v)
    notify(player, "Vehiculo " .. label(v) .. " explotado.", "success")
end)

addCommandHandler("getveh", function(player, _, id)
    if not guard(player) then return end
    local v = tonumber(id) and getVehicleById(id)
    if not v then return notify(player, "Uso: /getveh <id> (ver /nearbyvehs o /vehinfo)", "warning") end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local a = math.rad(rz)
    setElementInterior(v, getElementInterior(player))
    setElementDimension(v, getElementDimension(player))
    setElementPosition(v, x - math.sin(a) * 4, y + math.cos(a) * 4, z + 0.5)
    setElementRotation(v, 0, 0, rz)
    setElementVelocity(v, 0, 0, 0)
    saveVehicle(v)
    notify(player, "Trajiste el vehiculo " .. label(v) .. ".", "success")
end)

addCommandHandler("gotoveh", function(player, _, id)
    if not guard(player) then return end
    local v = tonumber(id) and getVehicleById(id)
    if not v then return notify(player, "Uso: /gotoveh <id>", "warning") end
    local x, y, z = getElementPosition(v)
    removePedFromVehicle(player)
    setElementInterior(player, getElementInterior(v))
    setElementDimension(player, getElementDimension(v))
    setElementPosition(player, x + 2.5, y, z + 1)
    notify(player, "Fuiste al vehiculo " .. label(v) .. ".", "success")
end)

addCommandHandler("vehinfo", function(player, _, id)
    if not guard(player) then return end
    local v = resolveVehicle(player, id)
    if not v then return notify(player, "No se encontro el vehiculo.", "warning") end
    local data = getVehicleData(v)
    chat(player, "Vehiculo " .. label(v))
    chat(player, ("  Vida %d%% - motor %s - %s%s%s"):format(math.floor(getElementHealth(v) / 10),
        getVehicleEngineState(v) and "encendido" or "apagado", isVehicleLocked(v) and "cerrado" or "abierto",
        data and data.handbrake and " - freno de mano" or "", data and data.clamped and " - CEPO" or ""), 255, 255, 255)
    if data then
        chat(player, ("  Dueno: personaje #%d - ultimo piloto: %s"):format(data.ownerId,
            data.lastDriver and (tostring(data.lastDriver.name):gsub("_", " ") .. " (" .. tostring(data.lastDriver.at) .. ")") or "-"), 255, 255, 255)
    end
end)

addCommandHandler("nearbytalleres", function(player, _, radius)
    if not guard(player) then return end
    radius = tonumber(radius) or 300
    local px, py, pz = getElementPosition(player)
    local any = false
    for i, shop in ipairs(getTuningShops()) do
        local d = getDistanceBetweenPoints3D(px, py, pz, shop.x, shop.y, shop.z)
        if d <= radius then
            any = true
            chat(player, ("Taller %d: %s - %.0f m. Usa /movertaller %d estando en tu auto para moverlo."):format(i, shop.name, d, i))
        end
    end
    if not any then chat(player, ("No hay talleres a menos de %d m. Prueba /nearbytalleres 3000."):format(radius)) end
end)
