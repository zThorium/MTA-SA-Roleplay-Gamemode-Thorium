--[[
    rp_chat / s_descriptions.lua
    Descripciones de rol: lo que se ve a simple vista (tatuajes, heridas, olor, estado del auto o de la casa).

        /yo [texto | borrar]        tu personaje
        /descveh [texto | borrar]   tu vehículo (dentro o a 5 m)
        /desccasa [texto | borrar]  tu casa (dentro o en la puerta)
        /examinar [id]              con id: esa persona (5 m); sin id: el vehículo más cercano o la casa donde estás
    Sin texto muestran la descripción actual. Se guardan en la tabla descriptions.
    Export: examinePlayer(viewer, target) para la opción «Examinar» del menú M (rp_interact).
]]

local DESC_LEN, RANGE = 200, 5
local COLOR = "#80DEA8"   -- mismo verde que /do

local function db() return exports.rp_database:getConnection() end
local function charId(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function nameOf(p) return (getPlayerName(p):gsub("#%x%x%x%x%x%x", ""):gsub("_", " ")) end
local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end

local function clean(text)
    text = tostring(text or ""):gsub("#%x%x%x%x%x%x", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, DESC_LEN)
end

local function near(a, b)
    if getElementDimension(a) ~= getElementDimension(b) or getElementInterior(a) ~= getElementInterior(b) then return false end
    local x, y, z = getElementPosition(a)
    local x2, y2, z2 = getElementPosition(b)
    return getDistanceBetweenPoints3D(x, y, z, x2, y2, z2) <= RANGE
end

-- Lee la descripción y se la muestra solo a quien mira
local function show(viewer, kind, refId, title)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(viewer) then return end
        local text = rows and rows[1] and rows[1].text
        outputChatBox(("%s* %s: #ECEFF5%s"):format(COLOR, title, text or "nada que destaque a simple vista."), viewer, 255, 255, 255, true)
    end, db(), "SELECT text FROM descriptions WHERE kind = ? AND ref_id = ?", kind, refId)
end

-- Guarda, borra o muestra (sin texto) la descripción propia
local function edit(player, kind, refId, raw, what, usage)
    local text = clean(raw)
    if text == "" then
        notify(player, usage, "info")
        return show(player, kind, refId, "Tu descripción de " .. what)
    end
    if text:lower() == "borrar" then
        dbExec(db(), "DELETE FROM descriptions WHERE kind = ? AND ref_id = ?", kind, refId)
        return notify(player, "Descripción de " .. what .. " borrada.", "success")
    end
    dbExec(db(), "INSERT INTO descriptions (kind, ref_id, text) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE text = VALUES(text)",
        kind, refId, text)
    notify(player, "Descripción de " .. what .. " guardada. Los demás la ven con /examinar.", "success")
end

-- Vehículo con dueño en BD: el que conduces o el más cercano a 5 m
local function nearestVehicle(player)
    local v = getPedOccupiedVehicle(player)
    if v and exports.rp_vehicles:getVehicleDatabaseId(v) then return v end
    local best, bestD
    local x, y, z = getElementPosition(player)
    for _, veh in ipairs(getElementsWithinRange(x, y, z, RANGE, "vehicle")) do
        if near(player, veh) and exports.rp_vehicles:getVehicleDatabaseId(veh) then
            local vx, vy, vz = getElementPosition(veh)
            local d = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            if not bestD or d < bestD then best, bestD = veh, d end
        end
    end
    return best
end

addCommandHandler("yo", function(p, _, ...)
    local id = charId(p)
    if not id then return end
    edit(p, "character", id, table.concat({ ... }, " "), "tu personaje",
        "Uso: /yo <descripción>  (ej: /yo Tatuaje de un águila en el cuello, huele a tabaco)  ·  /yo borrar")
end)

addCommandHandler("descveh", function(p, _, ...)
    if not charId(p) then return end
    local v = nearestVehicle(p)
    if not v then return notify(p, "Súbete a tu vehículo o acércate a él.", "warning") end
    if exports.rp_vehicles:getVehicleOwner(v) ~= charId(p) then return notify(p, "Ese vehículo no es tuyo.", "error") end
    edit(p, "vehicle", exports.rp_vehicles:getVehicleDatabaseId(v), table.concat({ ... }, " "), "tu vehículo",
        "Uso: /descveh <descripción>  (ej: /descveh Rayón en la puerta del conductor)  ·  /descveh borrar")
end)

addCommandHandler("desccasa", function(p, _, ...)
    if not charId(p) then return end
    local id = exports.rp_properties:getPlayerProperty(p)
    local info = id and exports.rp_properties:getPropertyInfo(id)
    if not info then return notify(p, "Entra en tu casa o ponte en la puerta.", "warning") end
    if info.owner_id ~= charId(p) then return notify(p, "Esta propiedad no es tuya.", "error") end
    edit(p, "property", id, table.concat({ ... }, " "), "tu casa",
        "Uso: /desccasa <descripción>  (ej: /desccasa Huele a pintura fresca)  ·  /desccasa borrar")
end)

function examinePlayer(viewer, target)
    if not isElement(viewer) or not isElement(target) or not charId(target) then return false end
    if not near(viewer, target) then return false end
    show(viewer, "character", charId(target), nameOf(target))
    return true
end

addCommandHandler("examinar", function(p, _, query)
    if not charId(p) then return end
    if query then
        local t = exports.rp_ids:findPlayer(query)
        if not t or t == p or not charId(t) then return notify(p, "No se encontró ese jugador.", "error") end
        if not examinePlayer(p, t) then return notify(p, "Está demasiado lejos para fijarte en los detalles.", "warning") end
        return
    end
    local v = nearestVehicle(p)
    if v then return show(p, "vehicle", exports.rp_vehicles:getVehicleDatabaseId(v), getVehicleName(v)) end
    local id = exports.rp_properties:getPlayerProperty(p)
    local info = id and exports.rp_properties:getPropertyInfo(id)
    if info then return show(p, "property", id, info.name or "La casa") end
    notify(p, "Uso: /examinar <id>  (una persona a 5 m)  ·  sin id: el vehículo más cercano o la casa donde estás", "info")
end)
