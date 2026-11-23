--[[
    rp_events / s_director.lua
    El "director de eventos": decide cuando y donde ocurre algo en la ciudad.

    Como funciona:
      1. Cada EVENTS.TICK segundos recupera "presupuesto de drama" (segun la intensidad
         y los jugadores conectados) y, si alcanza, sortea un evento del catalogo.
      2. El sorteo filtra por hora de juego, clima, cooldowns y jugadores, y pondera por
         peso x modificadores x variedad (lo que salio hace poco pesa menos).
      3. Elige un jugador "ancla" y le pide al CLIENTE un punto fuera de su vista sobre
         la red vial/peatonal de rp_citizens (el servidor no la tiene). El servidor
         valida el punto (distancia, dimension, separacion con otros eventos).
      4. Crea la escena con elementos del servidor (se transmiten solos por proximidad)
         y la mantiene con UN timer global; las etapas (llega la patrulla, la ambulancia...)
         salen por tiempo.
      5. Todo se limpia en finish(): fin de tiempo, sin jugadores cerca, o admin.

    Limites duros: EVENTS.MAX_ACTIVE eventos y EVENTS.MAX_ELEMENTS elementos en total.
    Sin BD: los eventos no sobreviven a un reinicio (y esta bien).

    Exports (servidor):
        startEvent(id, anchorPlayer)   fuerza un evento junto al jugador (admin/misiones)
        endEvent(eventId, reason)      termina un evento activo
        getActiveEvents([categoria])   { { eventId, id, name, category, x, y, z, startedAt, endsAt } }
        registerEvent(def) / unregisterEvent(id)   eventos de otros recursos (ver abajo)
        getIntensity()

    Eventos de otros recursos: registerEvent recibe SOLO datos (id, name, category, kind,
    weight, cooldown, duration, severity, elements, hours, rain, alert). Cuando toca, el
    director dispara en el recurso dueño el evento de servidor
        rp:events:ext:start (eventId, x, y, z, rotacion)   source = resourceRoot del dueño
    y al terminar rp:events:ext:finish (eventId, motivo). El dueño crea y limpia lo suyo.

    Eventos de servidor para quien quiera escuchar:
        rp:events:onStart (eventId, id, x, y, z)   rp:events:onEnd (eventId, id, motivo)
]]

addEvent("rp:events:onStart", false)
addEvent("rp:events:onEnd", false)
addEvent("rp:events:located", true)
addEvent("rp:events:ext:start", false)
addEvent("rp:events:ext:finish", false)
addEvent("rp:onCharacterSpawn", false)

local defs = {}               -- [id] = def (catalogo propio + externos)
local active = {}             -- [eventId] = ev
local nextEventId = 1
local totalElements = 0
local budget = EVENTS.BUDGET_START
local intensity = EVENTS.DEFAULT_INTENSITY
local nextAllowed = {}        -- [id] = tick en el que puede volver a salir
local history = {}            -- ultimos ids lanzados
local pending = {}            -- [token] = { def, anchor, forced, expires }
local pendingCount = 0
local nextToken = 1
local lastAnchor = setmetatable({}, { __mode = "k" })
local notified = setmetatable({}, { __mode = "k" })   -- [ev][player] = true

local function now() return getTickCount() end
local function pick(list) return list[math.random(#list)] end

local function notify(p, text, kind)
    pcall(function() exports.rp_notify:notify(p, text, kind or "info") end)
end

----------------------------------------------------------------
-- Jugadores
----------------------------------------------------------------
local function isEligible(p)
    if not isElement(p) or getElementType(p) ~= "player" then return false end
    if not getElementData(p, "rp:characterId") then return false end
    if getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return false end
    if isPedDead(p) or getElementData(p, "rp:downed") or getElementData(p, "rp:jail") then return false end
    return true
end

local function eligiblePlayers()
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if isEligible(p) then list[#list + 1] = p end
    end
    return list
end

local function distSq(x1, y1, x2, y2) return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 end

local function playersNear(x, y, radius, onlyEligible)
    local r2, list = radius * radius, {}
    for _, p in ipairs(getElementsByType("player")) do
        if (not onlyEligible or isEligible(p)) and getElementData(p, "rp:characterId") then
            local px, py = getElementPosition(p)
            if distSq(px, py, x, y) <= r2 then list[#list + 1] = p end
        end
    end
    return list
end

----------------------------------------------------------------
-- Sincronizacion con los clientes (lista pequena, solo cuando cambia)
----------------------------------------------------------------
local stopping = false

local function syncList(target)
    -- al parar el recurso los clientes ya no tienen el evento registrado (daria error)
    if stopping then return end
    local list = {}
    for id, ev in pairs(active) do
        list[#list + 1] = { id = id, key = ev.def.id, name = ev.def.name, x = ev.x, y = ev.y, z = ev.z, endsAt = ev.endsAt }
    end
    if target then
        triggerClientEvent(target, "rp:events:list", resourceRoot, list)
        return
    end
    -- solo a quien ya tiene personaje (su cliente ya cargo el recurso)
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "rp:characterId") then triggerClientEvent(p, "rp:events:list", resourceRoot, list) end
    end
end

addEventHandler("rp:onCharacterSpawn", root, function()
    if next(active) then syncList(source) end
end)

local function publishState()
    setElementData(root, "rp:events", { intensity = intensity })
end

----------------------------------------------------------------
-- Ayudantes de construccion (H) para las funciones build() del catalogo
----------------------------------------------------------------
local function trackElement(ev, el)
    if el then
        ev.els[#ev.els + 1] = el
        totalElements = totalElements + 1
    end
    return el
end

local function makeHelpers(ev)
    local H = { ev = ev }
    local hr = math.rad(ev.h)
    local fx, fy = -math.sin(hr), math.cos(hr)      -- delante
    local rx, ry = math.cos(hr), math.sin(hr)       -- derecha

    function H.pos(f, r) return ev.x + fx * f + rx * r, ev.y + fy * f + ry * r end

    -- Lado de la acera donde estan las casas: +1 = a la derecha del rumbo, -1 = a la izquierda
    -- (por el vector "alejarse de la calzada" que mando el cliente). La calle queda al otro lado.
    if ev.ax then H.side = ((ev.ax * rx + ev.ay * ry) >= 0) and 1 or -1 else H.side = 1 end

    -- Convierte un NPC del evento en vendedor (rp_shops, tienda temporal sin SQL)
    function H.shop(ped, name, catalog)
        if not isElement(ped) then return end
        setElementFrozen(ped, true)
        local ok, id = pcall(function() return exports.rp_shops:addTempShop(ped, name, catalog) end)
        if ok and id then ev.shops[#ev.shops + 1] = id end
        return ok and id or false
    end

    -- Vehiculo inmovil de escenografia: cerrado, apagado y congelado
    function H.veh(model, f, r, dh, opts)
        opts = opts or {}
        local x, y = H.pos(f, r)
        local v = createVehicle(model, x, y, ev.z + 0.9, 0, 0, (ev.h + (dh or 0)) % 360)
        if not v then return end
        setVehicleLocked(v, true)
        setVehicleEngineState(v, false)
        setElementFrozen(v, true)
        if opts.health then setElementHealth(v, math.max(300, opts.health)) end   -- >250: no explota
        if opts.sirens then setVehicleSirensOn(v, true) end
        if opts.hood then setVehicleDoorOpenRatio(v, 0, 1) end
        if opts.smoke then setElementData(v, "rp:fx", "smoke") end
        if opts.fire then setElementData(v, "rp:fx", "fire") end
        setElementData(v, "rp:eventProp", true)
        return trackElement(ev, v)
    end

    function H.panels(v)
        if not isElement(v) then return end
        for panel = 0, 6 do
            if math.random() < 0.6 then setVehiclePanelState(v, panel, math.random(1, 3)) end
        end
        setVehicleDoorState(v, 2, 2)
    end

    function H.ped(skin, f, r)
        local x, y = H.pos(f, r)
        local p = createPed(skin, x, y, ev.z + 1.0, ev.h)
        if not p then return end
        setElementData(p, "rp:eventProp", true)
        return trackElement(ev, p)
    end

    function H.obj(model, f, r, dh, dz)
        local x, y = H.pos(f, r)
        local o = createObject(model, x, y, ev.z + (dz or 0), 0, 0, ev.h + (dh or 0))
        return trackElement(ev, o)
    end

    function H.anim(ped, block, name)
        if isElement(ped) then setPedAnimation(ped, block, name, -1, true, false, false, false) end
    end

    function H.faceTo(ped, f, r)
        if not isElement(ped) then return end
        local tx, ty = H.pos(f, r)
        local x, y = getElementPosition(ped)
        setElementRotation(ped, 0, 0, -math.deg(math.atan2(tx - x, ty - y)))
    end

    function H.faceEachOther(a, b)
        if not (isElement(a) and isElement(b)) then return end
        local ax, ay = getElementPosition(a)
        local bx, by = getElementPosition(b)
        setElementRotation(a, 0, 0, -math.deg(math.atan2(bx - ax, by - ay)))
        setElementRotation(b, 0, 0, -math.deg(math.atan2(ax - bx, ay - by)))
    end

    function H.stage(seconds, fn)
        ev.stages[#ev.stages + 1] = { t = seconds * 1000, fn = fn, done = false }
    end

    -- Aviso a los jugadores que estan cerca del evento
    function H.say(text)
        for _, p in ipairs(playersNear(ev.x, ev.y, EVENTS.NOTIFY_RADIUS, true)) do notify(p, text, "info") end
    end

    return H
end

----------------------------------------------------------------
-- Ciclo de vida de un evento
----------------------------------------------------------------
local function finishEvent(eventId, reason)
    local ev = active[eventId]
    if not ev then return false end
    active[eventId] = nil
    notified[ev] = nil
    if ev.def.external then
        local res = getResourceFromName(ev.def.external)
        local rootEl = res and getResourceRootElement(res)
        if rootEl then triggerEvent("rp:events:ext:finish", rootEl, eventId, reason) end
    end
    for _, sid in ipairs(ev.shops or {}) do
        pcall(function() exports.rp_shops:removeTempShop(sid) end)
    end
    for _, el in ipairs(ev.els) do
        if isElement(el) then destroyElement(el) end
        totalElements = totalElements - 1
    end
    ev.els = {}
    triggerEvent("rp:events:onEnd", resourceRoot, eventId, ev.def.id, reason)
    outputServerLog(("[rp_events] fin #%d %s (%s, %d s)"):format(eventId, ev.def.id, reason, math.floor((now() - ev.born) / 1000)))
    syncList()
    return true
end

local function startEventAt(def, x, y, z, h, forced, ax, ay)
    -- limites duros
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    if n >= EVENTS.MAX_ACTIVE and not forced then return false end
    if totalElements + (def.elements or 0) > EVENTS.MAX_ELEMENTS + (forced and 12 or 0) then return false end

    local id = nextEventId
    nextEventId = nextEventId + 1
    local secs = math.random(def.duration[1], def.duration[2])
    local ev = {
        eventId = id, def = def, x = x, y = y, z = z, h = h, els = {}, stages = {}, shops = {}, ax = ax, ay = ay,
        born = now(), endsAt = now() + secs * 1000, lastNear = now(),
    }
    active[id] = ev

    local ok, err
    if def.external then
        local res = getResourceFromName(def.external)
        local rootEl = res and getResourceRootElement(res)
        ok = rootEl and true or false
        err = "recurso no disponible"
        if ok then triggerEvent("rp:events:ext:start", rootEl, id, x, y, z, h) end
    else
        ok, err = pcall(def.build, makeHelpers(ev))
    end
    if not ok then
        outputServerLog(("[rp_events] ERROR creando %s: %s"):format(def.id, tostring(err)))
        finishEvent(id, "error")
        return false
    end

    nextAllowed[def.id] = now() + (def.cooldown or 300) * 1000
    history[#history + 1] = def.id
    while #history > EVENTS.HISTORY do table.remove(history, 1) end
    triggerEvent("rp:events:onStart", resourceRoot, id, def.id, x, y, z)
    outputServerLog(("[rp_events] inicio #%d %s en %.0f, %.0f (%d s)"):format(id, def.id, x, y, secs))
    syncList()
    return true
end

----------------------------------------------------------------
-- Pedir el punto al cliente ancla y validarlo
----------------------------------------------------------------
local function requestSpawn(def, anchor, forced)
    local token = nextToken
    nextToken = nextToken + 1
    pending[token] = { def = def, anchor = anchor, forced = forced, expires = now() + EVENTS.LOCATE_TIMEOUT * 1000 }
    pendingCount = pendingCount + 1
    lastAnchor[anchor] = now()
    triggerClientEvent(anchor, "rp:events:locate", resourceRoot, token, def.kind, forced and true or false)
    setTimer(function()
        local p = pending[token]
        if p then
            -- el cliente no encontro un punto valido: se devuelve el presupuesto
            pending[token] = nil
            pendingCount = pendingCount - 1
            if not p.forced then budget = math.min(EVENTS.BUDGET_MAX, budget + (def.severity or 1)) end
            if p.forced and isElement(p.anchor) then notify(p.anchor, "No se encontro un punto valido cerca para el evento.", "error") end
        end
    end, EVENTS.LOCATE_TIMEOUT * 1000 + 500, 1)
end

addEventHandler("rp:events:located", resourceRoot, function(token, x, y, z, h, ax, ay)
    local p = pending[token]
    if not p or p.anchor ~= client then return end
    pending[token] = nil
    pendingCount = pendingCount - 1
    x, y, z, h = tonumber(x), tonumber(y), tonumber(z), tonumber(h)
    if not (x and y and z and h) or x ~= x or y ~= y or z ~= z or h ~= h then return end
    if math.abs(x) > 3000 or math.abs(y) > 3000 or z < -20 or z > 120 then return end
    if not isEligible(client) then return end

    local cx, cy = getElementPosition(client)
    local d = math.sqrt(distSq(cx, cy, x, y))
    local minD = p.forced and 0 or EVENTS.MIN_SPAWN_DIST
    if d < minD or d > EVENTS.MAX_SPAWN_DIST then return end
    -- separacion con otros eventos
    for _, ev in pairs(active) do
        if distSq(ev.x, ev.y, x, y) < EVENTS.EVENT_SPACING ^ 2 and not p.forced then return end
    end
    ax, ay = tonumber(ax), tonumber(ay)
    if not (ax and ay) or ax ~= ax or ay ~= ay then ax, ay = nil, nil end
    startEventAt(p.def, x, y, z, h % 360, p.forced, ax, ay)
    if p.forced and isElement(client) then
        notify(client, ("Evento '%s' creado."):format(p.def.name), "success")
    end
end)

----------------------------------------------------------------
-- Sorteo
----------------------------------------------------------------
local function inHours(hours, h)
    if not hours then return true end
    local a, b = hours[1], hours[2]
    if a <= b then return h >= a and h < b end
    return h >= a or h < b      -- cruza la medianoche
end

local function weightOf(def, world, nPlayers)
    if intensity == 0 then return 0 end
    if not inHours(def.hours, world.hour) then return 0 end
    if def.rain == "no" and world.raining then return 0 end
    if def.rain == "only" and not world.raining then return 0 end
    if nextAllowed[def.id] and now() < nextAllowed[def.id] then return 0 end
    if budget < (def.severity or 1) then return 0 end
    if (def.minPlayers or 1) > nPlayers then return 0 end
    local w = def.weight or 1
    if def.mult then
        local ok, m = pcall(def.mult, world)
        if ok and tonumber(m) then w = w * m end
    end
    for _, hid in ipairs(history) do
        if hid == def.id then w = w * EVENTS.HISTORY_MULT end
    end
    return w
end

local function pickAnchor(players)
    -- de 3 candidatos al azar, el que lleva mas tiempo sin ser ancla (reparte la variedad)
    local best, bestT
    for _ = 1, math.min(3, #players) do
        local p = pick(players)
        local t = lastAnchor[p] or 0
        if not best or t < bestT then best, bestT = p, t end
    end
    return best
end

local function directorTick()
    if intensity == 0 then return end
    local players = eligiblePlayers()
    if #players == 0 then return end

    -- recupera presupuesto: menos con pocos jugadores
    local perMin = EVENTS.BUDGET_REGEN[intensity + 1] or 0
    local scale = math.min(1, 0.5 + 0.25 * #players)
    budget = math.min(EVENTS.BUDGET_MAX, budget + perMin * scale * (EVENTS.TICK / 60))

    local n = 0
    for _ in pairs(active) do n = n + 1 end
    if n >= EVENTS.MAX_ACTIVE or pendingCount > 0 or totalElements >= EVENTS.MAX_ELEMENTS - 6 then return end

    local world = getWorldState and getWorldState() or { hour = getTime(), raining = false, night = false }
    local total, list = 0, {}
    for _, def in pairs(defs) do
        local w = weightOf(def, world, #players)
        if w > 0 then list[#list + 1] = { def, w } total = total + w end
    end
    if total <= 0 then return end
    local r = math.random() * total
    local chosen
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then chosen = e[1] break end
    end
    chosen = chosen or list[#list][1]

    budget = budget - (chosen.severity or 1)
    requestSpawn(chosen, pickAnchor(players), false)
end

----------------------------------------------------------------
-- Mantenimiento de los eventos activos (un solo timer)
----------------------------------------------------------------
local function maintain()
    if not next(active) then return end
    local t = now()
    local ended = {}
    for id, ev in pairs(active) do
        local elapsed = t - ev.born
        if t >= ev.endsAt then
            ended[#ended + 1] = { id, "timeout" }
        else
            for _, st in ipairs(ev.stages) do
                if not st.done and elapsed >= st.t then
                    st.done = true
                    local ok, err = pcall(st.fn)
                    if not ok then outputServerLog("[rp_events] ERROR en etapa de " .. ev.def.id .. ": " .. tostring(err)) end
                end
            end
            -- jugadores cerca: avisos y control de abandono
            local near = playersNear(ev.x, ev.y, EVENTS.NEAR_RADIUS, true)
            if #near > 0 then ev.lastNear = t
            elseif t - ev.lastNear > EVENTS.ABANDON_AFTER * 1000 then ended[#ended + 1] = { id, "abandoned" } end
            if ev.def.alert then
                local seen = notified[ev]
                if not seen then seen = setmetatable({}, { __mode = "k" }) notified[ev] = seen end
                for _, p in ipairs(near) do
                    if not seen[p] then
                        local px, py = getElementPosition(p)
                        if distSq(px, py, ev.x, ev.y) <= EVENTS.NOTIFY_RADIUS ^ 2 then
                            seen[p] = true
                            notify(p, ev.def.alert, "info")
                        end
                    end
                end
            end
        end
    end
    for _, e in ipairs(ended) do finishEvent(e[1], e[2]) end
end

----------------------------------------------------------------
-- Registro (catalogo propio + otros recursos)
----------------------------------------------------------------
for _, def in ipairs(CATALOG) do defs[def.id] = def end

function registerEvent(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or type(def.name) ~= "string" then return false end
    if type(def.duration) ~= "table" or not tonumber(def.duration[1]) or not tonumber(def.duration[2]) then return false end
    if defs[def.id] and not defs[def.id].external then return false end        -- no pisa los propios
    if not sourceResource then return false end
    local clean = {
        id = def.id, name = def.name, category = tostring(def.category or "other"),
        kind = def.kind == "walk" and "walk" or "road",
        weight = math.max(0, tonumber(def.weight) or 1), cooldown = tonumber(def.cooldown) or 300,
        duration = { tonumber(def.duration[1]), tonumber(def.duration[2]) },
        severity = math.max(1, math.min(3, math.floor(tonumber(def.severity) or 1))),
        elements = math.max(0, math.min(30, math.floor(tonumber(def.elements) or 5))),
        hours = type(def.hours) == "table" and { tonumber(def.hours[1]) or 0, tonumber(def.hours[2]) or 24 } or nil,
        rain = (def.rain == "no" or def.rain == "only") and def.rain or nil,
        alert = type(def.alert) == "string" and def.alert or nil,
        external = getResourceName(sourceResource),
    }
    defs[clean.id] = clean
    return true
end

function unregisterEvent(id)
    local def = defs[id]
    if not def or not def.external then return false end
    defs[id] = nil
    return true
end

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    for id, def in pairs(defs) do
        if def.external == name then
            defs[id] = nil
            for eid, ev in pairs(active) do
                if ev.def.id == id then finishEvent(eid, "resource_stop") end
            end
        end
    end
end)

----------------------------------------------------------------
-- Exports / admin
----------------------------------------------------------------
function startEvent(id, anchor)
    local def = defs[id]
    if not def or not isEligible(anchor) then return false end
    if pendingCount > 0 then return false end
    requestSpawn(def, anchor, true)
    return true
end

function endEvent(eventId, reason)
    return finishEvent(tonumber(eventId), tostring(reason or "cancel"))
end

function getActiveEvents(category)
    local out = {}
    for id, ev in pairs(active) do
        if not category or ev.def.category == category then
            out[#out + 1] = { eventId = id, id = ev.def.id, name = ev.def.name, category = ev.def.category,
                x = ev.x, y = ev.y, z = ev.z, startedAt = ev.born, endsAt = ev.endsAt }
        end
    end
    return out
end

function getIntensity() return intensity end

function setIntensity(level)
    level = math.floor(tonumber(level) or -1)
    if level < 0 or level > 3 then return false end
    intensity = level
    publishState()
    if level == 0 then
        for id in pairs(active) do finishEvent(id, "disabled") end
    end
    return true
end

function getEventDefs() return defs end
function getBudget() return budget end
function getElementTotal() return totalElements end

function clearAllEvents()
    local n = 0
    for id in pairs(active) do finishEvent(id, "cleared") n = n + 1 end
    return n
end

addEventHandler("onResourceStart", resourceRoot, function()
    publishState()
    setTimer(directorTick, EVENTS.TICK * 1000, 0)
    setTimer(maintain, EVENTS.MAINTAIN_TICK * 1000, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    stopping = true
    for id in pairs(active) do finishEvent(id, "resource_stop") end
end)

-- El cliente avisa cuando ya cargo el recurso (p. ej. tras /restart): se le envia la lista actual
addEvent("rp:events:ready", true)
addEventHandler("rp:events:ready", resourceRoot, function()
    if isElement(client) and next(active) then syncList(client) end
end)
