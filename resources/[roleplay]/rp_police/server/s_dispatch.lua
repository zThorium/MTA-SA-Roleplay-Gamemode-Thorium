--[[
    rp_police / s_dispatch.lua
    Despacho: alertas automaticas a los policias de servicio con codigo, zona,
    blip temporal y descripcion generada (genero y vehiculo del sospechoso).
    Origenes: disparos (cliente), busqueda subiendo a 2+ estrellas (rp_wanted),
    /policia <mensaje> (ciudadanos), /panico (policias) y el export dispatchAlert
    para otros recursos (p. ej. robos).

    Export: dispatchAlert(clave, x, y, z, texto, jugador)   claves: POLICE_CODES
    Comandos: /policia <mensaje>, /panico, /responder [n]
]]

addEvent("rp:pol:shot", true)
addEvent("rp:onWantedLevelChange", false)
addEvent("rp:onCharacterSpawn", false)

local alerts = {}        -- lista, la mas nueva al final
local nextId = 1
local gender = {}        -- [characterId] = 0|1
local lastShot, lastWanted, lastCall = {}, {}, {}

addEventHandler("rp:onCharacterSpawn", root, function(characterId)
    local id = characterId or charOf(source)
    if not id or gender[id] ~= nil then return end
    dbQuery(function(qh)
        local r = (dbPoll(qh, 0) or {})[1]
        if r then gender[id] = tonumber(r.gender) end
    end, db(), "SELECT gender FROM characters WHERE id = ?", id)
end)

local function colorName(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    if mx < 60 then return "negro" end
    if mn > 190 then return "blanco" end
    if mx - mn < 35 then return mx > 120 and "gris" or "gris oscuro" end
    if r >= g and r >= b then return (g > r * 0.6) and "naranja" or "rojo" end
    if g >= r and g >= b then return "verde" end
    return "azul"
end

-- Descripcion generada a partir de lo que se ve del sospechoso
local function describe(player)
    if not isElement(player) then return "" end
    local g = gender[charOf(player)]
    local parts = { g == 1 and "Sujeto femenino" or "Sujeto masculino" }
    local v = getPedOccupiedVehicle(player)
    if v then
        local r, gr, b = getVehicleColor(v, true)
        parts[#parts + 1] = ("en %s %s"):format(getVehicleNameFromModel(getElementModel(v)) or "vehiculo", colorName(r, gr, b))
    else
        parts[#parts + 1] = "a pie"
    end
    return table.concat(parts, ", ")
end

function getAlertList()
    local out = {}
    for i = #alerts, math.max(1, #alerts - 24), -1 do
        local a = alerts[i]
        out[#out + 1] = { id = a.id, code = a.code, title = a.title, zone = a.zone, desc = a.desc, at = a.at, color = a.color,
            x = a.x, y = a.y, z = a.z, responders = a.responders }
    end
    return out
end

function dispatchAlert(key, x, y, z, extra, source)
    local def = POLICE_CODES[key]
    if not def then return false end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return false end
    local desc = {}
    if source then desc[#desc + 1] = describe(source) end
    if type(extra) == "string" and extra ~= "" then desc[#desc + 1] = extra:sub(1, 160) end
    local a = {
        id = nextId, code = def.code, title = def.title, color = def.color, x = x, y = y, z = z,
        zone = getZoneName(x, y, z), desc = table.concat(desc, ". "), at = getRealTime().timestamp, responders = 0,
    }
    nextId = nextId + 1
    alerts[#alerts + 1] = a
    if #alerts > POLICE.ALERTS_KEEP then table.remove(alerts, 1) end

    local officers = officersOnDuty()
    if #officers == 0 then return true end
    local blip = createBlip(x, y, z, 0, 3, def.color[1], def.color[2], def.color[3], 255, 0, 99999)
    setElementVisibleTo(blip, root, false)
    for _, o in ipairs(officers) do
        setElementVisibleTo(blip, o, true)
        triggerClientEvent(o, "rp:pol:alert", resourceRoot, { id = a.id, code = a.code, title = a.title, zone = a.zone, desc = a.desc,
            x = x, y = y, z = z, color = def.color })
    end
    a.blip = blip
    setTimer(function() if isElement(blip) then destroyElement(blip) end end, POLICE.ALERT_BLIP_MS, 1)
    return true
end

function respondAlert(officer, id)
    if not isOnDuty(officer) then return end
    local a
    if id and id > 0 then
        for _, x in ipairs(alerts) do if x.id == id then a = x break end end
    else
        a = alerts[#alerts]
    end
    if not a then return notify(officer, "No hay un aviso con ese numero.", "warning") end
    a.responders = a.responders + 1
    triggerClientEvent(officer, "rp:pol:setWaypoint", resourceRoot, a.x, a.y)
    for _, o in ipairs(officersOnDuty()) do
        if o ~= officer then notify(o, ("%s responde al aviso #%d (%s)."):format(dname(officer), a.id, a.code), "info") end
    end
    notify(officer, ("Respondes al aviso #%d en %s. Punto marcado en el mapa."):format(a.id, a.zone), "success")
end
addEvent("rp:pol:setWaypoint", true)

addCommandHandler("responder", function(p, _, id) respondAlert(p, tonumber(id)) end)

----------------------------------------------------------------
-- Origenes
----------------------------------------------------------------
addEventHandler("rp:pol:shot", resourceRoot, function(weapon)
    local p = client
    weapon = tonumber(weapon)
    if not weapon or weapon < 22 or weapon > 38 or weapon == 23 or not charOf(p) then return end
    if getPedWeapon(p) ~= weapon or isOnDuty(p) then return end
    local x, y, z = getElementPosition(p)
    addCasing(p, weapon, x, y, z)
    local now = getTickCount()
    if lastShot[p] and now - lastShot[p] < POLICE.SHOT_ALERT_COOLDOWN then return end
    lastShot[p] = now
    dispatchAlert("shots", x, y, z, nil, p)
end)

addEventHandler("rp:onWantedLevelChange", root, function(level, old)
    local p = source
    if not isElement(p) or (level or 0) < 2 or (old or 0) >= 2 or isOnDuty(p) then return end
    local now = getTickCount()
    if lastWanted[p] and now - lastWanted[p] < POLICE.WANTED_ALERT_COOLDOWN then return end
    lastWanted[p] = now
    local x, y, z = getElementPosition(p)
    dispatchAlert("wanted", x, y, z, ("Busqueda de %d estrellas"):format(level), p)
end)

addCommandHandler("policia", function(p, _, ...)
    if not charOf(p) then return end
    local msg = table.concat({ ... }, " "):gsub("[%c<>]", ""):sub(1, 140)
    if #msg < 3 then return notify(p, "Uso: /policia <que ocurre>", "info") end
    local now = getTickCount()
    if lastCall[p] and now - lastCall[p] < 20000 then return notify(p, "Espera unos segundos entre llamadas.", "warning") end
    lastCall[p] = now
    local x, y, z = getElementPosition(p)
    dispatchAlert("call", x, y, z, ("%s: \"%s\""):format(dname(p), msg), nil)
    notify(p, "La central recibio tu aviso. Mantente a salvo.", "success")
end)

addCommandHandler("panico", function(p)
    if not isOnDuty(p) then return end
    local now = getTickCount()
    if lastCall[p] and now - lastCall[p] < 15000 then return end
    lastCall[p] = now
    local x, y, z = getElementPosition(p)
    dispatchAlert("panic", x, y, z, dname(p) .. " solicita apoyo inmediato", nil)
    notify(p, "Boton de panico enviado a todas las unidades.", "success")
end)

addEventHandler("onPlayerQuit", root, function()
    lastShot[source], lastWanted[source], lastCall[source] = nil, nil, nil
end)
