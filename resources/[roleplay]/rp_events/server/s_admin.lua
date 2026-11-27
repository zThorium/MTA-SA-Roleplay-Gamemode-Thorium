--[[
    rp_events / s_admin.lua
    Comandos de administracion del mundo vivo (nivel 1):
        /evento [id]                crea un evento junto a ti (sin id: lista los disponibles)
        /eventos                    eventos activos con distancia
        /eventoslista               catalogo con peso, horario y cooldown
        /terminarevento <n|todos>   termina un evento (o todos)
        /eventosintensidad [0-3]    0 apagado, 1 tranquilo, 2 normal, 3 movido
        /eventosinfo                presupuesto y elementos en uso
        /clima [nombre]             vista previa del clima (solo para ti); Enter lo pone para todos
        /hora <h> [m]               cambia la hora de juego
]]

local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function say(p, text) outputChatBox("[Eventos] " .. text, p, 120, 200, 255) end

local function admin(name, fn)
    addCommandHandler(name, function(player, cmd, ...)
        if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
        fn(player, ...)
    end)
end

admin("evento", function(player, id)
    local defs = getEventDefs()
    if not id then
        local ids = {}
        for k in pairs(defs) do ids[#ids + 1] = k end
        table.sort(ids)
        return say(player, "Uso: /evento <id>. Disponibles: " .. table.concat(ids, ", "))
    end
    if not defs[id] then return notify(player, "Evento desconocido. /evento para ver la lista.", "error") end
    if not startEvent(id, player) then
        return notify(player, "No se puede crear ahora (ya hay una peticion en curso o estas en un interior).", "error")
    end
end)

admin("eventos", function(player)
    local list = getActiveEvents()
    if #list == 0 then return say(player, "No hay eventos activos.") end
    local px, py = getElementPosition(player)
    for _, e in ipairs(list) do
        local d = math.floor(math.sqrt((px - e.x) ^ 2 + (py - e.y) ^ 2))
        local left = math.max(0, math.floor((e.endsAt - getTickCount()) / 1000))
        say(player, ("#%d %s (%s) a %d m, quedan %d s - %s"):format(e.eventId, e.name, e.id, d, left, getZoneName(e.x, e.y, e.z)))
    end
end)

admin("eventoslista", function(player)
    local rows = {}
    for id, d in pairs(getEventDefs()) do
        local hours = d.hours and (d.hours[1] .. "-" .. d.hours[2] .. " h") or "todo el dia"
        rows[#rows + 1] = ("%s: peso %s, %s, cooldown %d s, coste %d%s%s"):format(
            id, tostring(d.weight), hours, d.cooldown or 0, d.severity or 1,
            d.rain == "no" and ", sin lluvia" or d.rain == "only" and ", solo lluvia" or "",
            d.external and (", de " .. d.external) or "")
    end
    table.sort(rows)
    for _, r in ipairs(rows) do say(player, r) end
end)

admin("terminarevento", function(player, which)
    if which == "todos" then
        return say(player, ("%d eventos terminados."):format(clearAllEvents()))
    end
    local n = tonumber(which)
    if not n then return say(player, "Uso: /terminarevento <numero|todos>") end
    if endEvent(n, "admin") then say(player, "Evento #" .. n .. " terminado.") else say(player, "No existe ese evento.") end
end)

admin("eventosintensidad", function(player, level)
    if not level then return say(player, ("Intensidad actual: %d (0 apagado, 1 tranquilo, 2 normal, 3 movido)."):format(getIntensity())) end
    if setIntensity(level) then say(player, "Intensidad: " .. getIntensity()) else say(player, "Uso: /eventosintensidad <0-3>") end
end)

admin("eventosinfo", function(player)
    say(player, ("Presupuesto %.1f/%d, elementos %d/%d, intensidad %d"):format(
        getBudget(), EVENTS.BUDGET_MAX, getElementTotal(), EVENTS.MAX_ELEMENTS, getIntensity()))
end)

-- /clima abre la vista previa en el cliente del admin (solo la ve el); con Enter confirma
addEvent("rp:events:weatherConfirm", true)

admin("clima", function(player, name)
    if name and not WORLD.WEATHER[name] then
        local names = {}
        for k, d in pairs(WORLD.WEATHER) do names[#names + 1] = k .. " (" .. d.label .. ")" end
        table.sort(names)
        return say(player, "Clima desconocido. Disponibles: " .. table.concat(names, ", "))
    end
    local w = getWorldState()
    triggerClientEvent(player, "rp:events:weatherPreview", resourceRoot, name or w.weather, w.id)
end)

addEventHandler("rp:events:weatherConfirm", resourceRoot, function(name, id)
    local player = client
    if not player or not isAdmin(player) then return end
    if type(name) ~= "string" or type(id) ~= "number" then return end
    if setWeatherState(name, true, id) then
        local def = WORLD.WEATHER[name]
        notify(player, ("Clima cambiado a %s."):format(def.label), "success")
        outputServerLog(("[rp_events] %s puso el clima %s (id %d)"):format(getPlayerName(player), name, id))
    else
        notify(player, "Clima no valido.", "error")
    end
end)

admin("hora", function(player, h, m)
    h, m = tonumber(h), tonumber(m) or 0
    if not h or h < 0 or h > 23 or m < 0 or m > 59 then return say(player, "Uso: /hora <0-23> [minutos]") end
    setGameTime(math.floor(h), math.floor(m))
    say(player, ("Hora de juego: %02d:%02d"):format(h, m))
end)

-- Calibrar los puestos del mercadillo en juego: /mercadoajuste <dz> <rotacion>
admin("mercadoajuste", function(player, dz, rot)
    if not dz then
        return say(player, ("Puestos: subida %.2f m, rotacion extra %d. Uso: /mercadoajuste <dz> <0|90|180|270>, luego /evento market."):format(MARKET.CART_DZ, MARKET.CART_ROT))
    end
    dz, rot = tonumber(dz), tonumber(rot) or MARKET.CART_ROT
    if not dz or dz < -2 or dz > 3 then return say(player, "dz debe estar entre -2 y 3 metros.") end
    MARKET.CART_DZ, MARKET.CART_ROT = dz, rot % 360
    say(player, ("Puestos: subida %.2f m, rotacion extra %d. Crea otro con /evento market (/terminarevento todos antes)."):format(MARKET.CART_DZ, MARKET.CART_ROT))
end)
