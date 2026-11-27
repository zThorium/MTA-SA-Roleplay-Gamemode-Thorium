--[[
    rp_jobs / s_jobs.lua

    Núcleo de los trabajos civiles:
      - Trabajo actual por personaje (character_jobs) y experiencia/estadísticas por trabajo (job_stats).
      - API para la agencia de trabajos (exports, ver RECURSOS.md y docs/TRABAJOS.md).
      - Turnos: se empiezan y terminan en la sede (marcador con E). Cada trabajo es un módulo
        (server/jobs/s_<trabajo>.lua) que se registra con Jobs.register y avanza por pasos:
        puntos a los que ir o donde pulsar E, y minijuegos CEF cuyo resultado valida el servidor.
      - Pago en efectivo por tarea con bonus por nivel, objetos al inventario y vehículo de trabajo.

    Comandos:
        /trabajo                         tu trabajo, nivel y GPS a la sede
        /terminarturno                   termina el turno donde estés (sin bonus de ruta)
        /dejartrabajo                    renuncia a tu trabajo
        /setjob <jugador> <id|ninguno>   (admin) asigna o quita un trabajo
        /darxptrabajo <jugador> <xp>     (admin) suma experiencia en su trabajo actual
]]

Jobs = { modules = {} }

local info = {}       -- [player] = { characterId, job, stats = {[jobId] = {xp, tasks, earned, best}}, hiredAt }
local shifts = {}     -- [player] = estado del turno (ver startShift)
local cooldown = {}   -- [player] = tick (anti spam de eventos)
local vehicleOwner = {}   -- [vehicle] = player
local wpCounter = 0

addEvent("rp:onDatabaseReady", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)
addEvent("rp:jobs:onJobChanged", false)     -- para otros recursos: source = jugador, (nuevoId, anteriorId)
addEvent("rp:jobs:onShiftEnd", false)       -- source = jugador, (jobId, ganado, tareas)

addEvent("rp:jobs:reach", true)
addEvent("rp:jobs:gameResult", true)
addEvent("rp:jobs:openHQ", true)
addEvent("rp:jobs:hqAction", true)

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function characterOf(p) return exports.rp_characters:getPlayerCharacterId(p) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end
local function isDowned(p) return getElementData(p, "rp:downed") and true or false end

Jobs.notify = notify

local function throttled(player, ms)
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < (ms or 350) then return true end
    cooldown[player] = now
    return false
end

local function dist2D(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

local function nearPoint(player, p, radius)
    if getElementInterior(player) ~= (p.interior or 0) or getElementDimension(player) ~= (p.dimension or 0) then return false end
    local x, y, z = getElementPosition(player)
    return dist2D(x, y, p.x, p.y) <= radius and math.abs(z - p.z) <= 12
end

----------------------------------------------------------------
-- Experiencia y niveles
----------------------------------------------------------------
local function statsOf(player, jobId)
    local i = info[player]
    if not i then return nil end
    i.stats[jobId] = i.stats[jobId] or { xp = 0, tasks = 0, earned = 0, best = 0 }
    return i.stats[jobId]
end

local function levelFromXP(xp)
    local level = 1
    for l, need in ipairs(JOBS_CONFIG.LEVEL_XP) do
        if xp >= need then level = l end
    end
    return level
end

function Jobs.level(player, jobId)
    local st = statsOf(player, jobId or (info[player] and info[player].job))
    return st and levelFromXP(st.xp) or 1
end

local function saveStats(player, jobId, xp, tasks, earned)
    local i = info[player]
    if not i then return end
    dbExec(db(), [[
        INSERT INTO job_stats (character_id, job_id, xp, tasks, earned) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), tasks = tasks + VALUES(tasks), earned = earned + VALUES(earned)
    ]], i.characterId, jobId, xp, tasks, earned)
end

function Jobs.xp(player, amount)
    local s = shifts[player]
    if not s then return end
    amount = math.max(0, math.floor(amount))
    local st = statsOf(player, s.job)
    local before = levelFromXP(st.xp)
    st.xp = st.xp + amount
    st.tasks = st.tasks + 1
    s.tasks = s.tasks + 1
    saveStats(player, s.job, amount, 1, 0)
    local after = levelFromXP(st.xp)
    triggerEvent("rp:achievements:progress", player, "job_level", after)   -- logros (rp_achievements, modo max)
    if after > before then
        exports.rp_notify:popup(player, "¡Subiste de nivel!", ("Ahora eres nivel %d como %s. Cobras un %d%% más."):format(
            after, JOBS_BY_ID[s.job].name, math.floor((after - 1) * JOBS_CONFIG.LEVEL_PAY_BONUS * 100 + 0.5)), "success", 7000)
    end
    Jobs.refreshHud(player)
end

----------------------------------------------------------------
-- Pagos y objetos
----------------------------------------------------------------
-- Paga en efectivo `base` con el bonus de nivel. Devuelve lo pagado.
function Jobs.pay(player, base, label)
    local s = shifts[player]
    if not s or not isElement(player) then return 0 end
    local level = Jobs.level(player, s.job)
    local amount = math.floor(base * (1 + (level - 1) * JOBS_CONFIG.LEVEL_PAY_BONUS) + 0.5)
    amount = math.max(0, math.min(amount, JOBS_CONFIG.MAX_TASK_PAY))
    if amount <= 0 then return 0 end
    givePlayerMoney(player, amount)
    exports.rp_characters:saveCharacter(player)
    s.earned = s.earned + amount
    local st = statsOf(player, s.job)
    st.earned = st.earned + amount
    saveStats(player, s.job, 0, 0, amount)
    notify(player, ("+$%d  %s"):format(amount, label or "Pago del trabajo"), "success")
    Jobs.refreshHud(player)
    return amount
end

-- Da hasta `amount` unidades de un objeto; si no cabe todo, da lo que quepa. Devuelve lo entregado.
function Jobs.give(player, itemId, amount)
    amount = math.floor(tonumber(amount) or 1)
    local given = 0
    while given < amount do
        local ok, reason = exports.rp_inventory:giveItem(player, itemId, 1)
        if not ok then
            local def = exports.rp_inventory:getItemDefinition(itemId)
            notify(player, ("No te cabe %s: %s"):format(def and def.name or itemId, reason or "inventario lleno"), "warning")
            break
        end
        given = given + 1
    end
    return given
end

function Jobs.itemName(itemId)
    local def = exports.rp_inventory:getItemDefinition(itemId)
    return def and def.name or itemId
end

function Jobs.pickWeighted(list, level)
    local total = 0
    for _, e in ipairs(list) do
        if (e.minLevel or 1) <= (level or 1) then total = total + (e.weight or 1) end
    end
    if total <= 0 then return list[1] end
    local r = math.random() * total
    for _, e in ipairs(list) do
        if (e.minLevel or 1) <= (level or 1) then
            r = r - (e.weight or 1)
            if r <= 0 then return e end
        end
    end
    return list[#list]
end

function Jobs.shuffle(list)
    local t = {}
    for i, v in ipairs(list) do t[i] = v end
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

----------------------------------------------------------------
-- Interfaz en el cliente: HUD, puntos, objetos, minijuegos
----------------------------------------------------------------
function Jobs.hud(player, task, extra)
    local s = shifts[player]
    if not s then return end
    s.hudTask, s.hudExtra = task, extra
    Jobs.refreshHud(player)
end

function Jobs.refreshHud(player)
    local s = shifts[player]
    if not s or JOBS_BY_ID[s.job].external then   -- los trabajos externos dibujan su propio HUD
        return triggerClientEvent(player, "rp:jobs:hud", resourceRoot, false)
    end
    local st = statsOf(player, s.job)
    local level = levelFromXP(st.xp)
    local nextXP = JOBS_CONFIG.LEVEL_XP[level + 1]
    triggerClientEvent(player, "rp:jobs:hud", resourceRoot, {
        job = s.job, task = s.hudTask or "", extra = s.hudExtra or "",
        earned = s.earned, level = level, xp = st.xp,
        levelXP = JOBS_CONFIG.LEVEL_XP[level], nextXP = nextXP or false,
    })
end

-- wp = { x, y, z, r, mode = "drive"|"foot"|"any", act = "enter"|"press", text, label,
--        flat = true (solo distancia 2D), attach = "vehicle" + offset = {x,y,z}, color = {r,g,b}, marker }
function Jobs.waypoint(player, wp)
    local s = shifts[player]
    if not s then return end
    wpCounter = wpCounter + 1
    wp.id = wpCounter
    wp.r = wp.r or 2.5
    wp.mode = wp.mode or "foot"
    wp.act = wp.act or "press"
    wp.color = wp.color or JOBS_BY_ID[s.job].color
    if wp.attach == "vehicle" then wp.vehicle = s.vehicle end
    s.wp = wp
    triggerClientEvent(player, "rp:jobs:wp", resourceRoot, wp)
    return wp.id
end

function Jobs.clearWaypoint(player)
    local s = shifts[player]
    if s then s.wp = nil end
    triggerClientEvent(player, "rp:jobs:wp", resourceRoot, false)
end

-- Objetos que solo ve el trabajador (árboles, rocas, bolsas...). list = { {key, model, x, y, z, rx, ry, rz, snap} }
function Jobs.props(player, list)
    triggerClientEvent(player, "rp:jobs:props", resourceRoot, list or {})
end

-- Efecto sobre un objeto: "fall" (árbol cae hacia arg grados), "remove", "shake"
function Jobs.propFx(player, key, fx, arg)
    triggerClientEvent(player, "rp:jobs:propFx", resourceRoot, key, fx, arg)
end

-- Objeto en la mano derecha que ven todos (bolsa, caña, pala...). model = false para quitarlo
function Jobs.hold(player, model, offset)
    local s = shifts[player]
    if not s then return end
    if isElement(s.held) then destroyElement(s.held) end
    s.held = nil
    if not model then return end
    local x, y, z = getElementPosition(player)
    local obj = createObject(model, x, y, z)
    if not obj then return end
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, getElementInterior(player))
    setElementDimension(obj, getElementDimension(player))
    local o = offset or {}
    exports.bone_attach:attachElementToBone(obj, player, 12, o[1] or 0, o[2] or 0, o[3] or 0, o[4] or 0, o[5] or 0, o[6] or 0)
    s.held = obj
end

function Jobs.anim(player, block, name, loop)
    if block then setPedAnimation(player, block, name, -1, loop and true or false, false, false, loop and true or false)
    else setPedAnimation(player) end
end

function Jobs.sound(player, name)
    triggerClientEvent(player, "rp:jobs:sound", resourceRoot, name)
end

-- Abre un minijuego CEF. El resultado llega a module.onGame(player, s, name, result, ctx).
-- minMs: tiempo mínimo creíble para terminarlo (si llega antes, se trata como fallo).
function Jobs.game(player, name, params, minMs, ctx)
    local s = shifts[player]
    if not s then return end
    local token = ("%d%06d"):format(getTickCount() % 100000, math.random(0, 999999))
    s.game = { token = token, name = name, at = getTickCount(), minMs = minMs or 0, ctx = ctx }
    params = params or {}
    params.jobColor = JOBS_BY_ID[s.job].color
    triggerClientEvent(player, "rp:jobs:game", resourceRoot, name, params, token)
end

-- Acción en el mundo sin CEF (barra en pantalla y animación). kind:
--   "_hold" mantener E params.ms; "_tap" pulsar E params.taps veces; "_bite" picada de pesca.
-- El resultado llega a module.onGame(player, s, kind, result, ctx) como un minijuego más.
function Jobs.action(player, kind, params, ctx)
    params = params or {}
    local minMs = 0
    if kind == "_hold" then minMs = math.floor((params.ms or 3000) * 0.85)
    elseif kind == "_tap" then minMs = (params.taps or 6) * 220
    elseif kind == "_bite" then minMs = math.floor((params.waitMin or 2500) * 0.9) end
    Jobs.game(player, kind, params, minMs, ctx)
end

----------------------------------------------------------------
-- Vehículo del trabajo
----------------------------------------------------------------
function Jobs.spawnVehicle(player, spec)
    local s = shifts[player]
    if not s or not spec then return nil end
    if isElement(s.vehicle) then
        vehicleOwner[s.vehicle] = nil
        destroyElement(s.vehicle)
    end
    local v = createVehicle(spec.model, spec.x, spec.y, spec.z, 0, 0, spec.rz or 0, "TRABAJO")
    if not v then return nil end
    setElementData(v, "rp:jobVehicle", s.job)
    setVehicleColor(v, 255, 255, 255, 255, 255, 255)
    vehicleOwner[v] = player
    s.vehicle, s.leftAt = v, nil
    return v
end

function Jobs.vehicle(player)
    local s = shifts[player]
    return s and isElement(s.vehicle) and s.vehicle or nil
end

addEventHandler("onVehicleStartEnter", root, function(player, seat)
    local owner = vehicleOwner[source]
    if owner and seat == 0 and owner ~= player then
        cancelEvent()
        notify(player, "Es un vehículo de trabajo de otra persona.", "error")
    end
end)

addEventHandler("onVehicleExplode", root, function()
    local owner = vehicleOwner[source]
    if owner and shifts[owner] then Jobs.endShift(owner, "Tu vehículo de trabajo quedó destruido.") end
end)

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) == "vehicle" then vehicleOwner[source] = nil end
end)

-- Posición de un punto unido al vehículo (offset relativo, solo rotación Z)
local function attachedPosition(vehicle, offset)
    local x, y, z = getElementPosition(vehicle)
    local _, _, rz = getElementRotation(vehicle)
    local a = math.rad(rz)
    local ox, oy, oz = offset[1] or 0, offset[2] or 0, offset[3] or 0
    return x + ox * math.cos(a) - oy * math.sin(a), y + ox * math.sin(a) + oy * math.cos(a), z + oz
end
Jobs.attachedPosition = attachedPosition

----------------------------------------------------------------
-- Turnos
----------------------------------------------------------------
function Jobs.register(id, module)
    Jobs.modules[id] = module
end

function Jobs.shift(player) return shifts[player] end

function Jobs.endShift(player, reason, quiet)
    local s = shifts[player]
    if not s then return false end
    local module = Jobs.modules[s.job]
    if module and module.stop then pcall(module.stop, player, s) end
    shifts[player] = nil
    if isElement(s.vehicle) then
        vehicleOwner[s.vehicle] = nil
        destroyElement(s.vehicle)
    end
    if isElement(s.held) then destroyElement(s.held) end
    if not isElement(player) then return true end

    if not isDowned(player) then setPedAnimation(player) end
    setElementData(player, "rp:jobShift", false)
    triggerClientEvent(player, "rp:jobs:wp", resourceRoot, false)
    triggerClientEvent(player, "rp:jobs:props", resourceRoot, {})
    triggerClientEvent(player, "rp:jobs:hud", resourceRoot, false)
    triggerClientEvent(player, "rp:jobs:closeGame", resourceRoot)

    local st = statsOf(player, s.job)
    if st and s.earned > st.best then
        st.best = s.earned
        dbExec(db(), "UPDATE job_stats SET best_shift = GREATEST(best_shift, ?) WHERE character_id = ? AND job_id = ?",
            s.earned, s.characterId, s.job)
    end
    triggerEvent("rp:jobs:onShiftEnd", player, s.job, s.earned, s.tasks)
    if not quiet then
        triggerClientEvent(player, "rp:jobs:summary", resourceRoot, {
            job = s.job, earned = s.earned, tasks = s.tasks,
            minutes = math.floor((getTickCount() - s.started) / 60000), reason = reason or "",
        })
    end
    return true
end

local function startShift(player, jobId, option)
    local job, module = JOBS_BY_ID[jobId], Jobs.modules[jobId]
    if not job or not module then return false, "Ese trabajo no está disponible." end
    if shifts[player] then return false, "Ya estás de turno." end
    if isDowned(player) then return false, "No puedes trabajar ahora." end
    local s = {
        job = jobId, player = player, characterId = info[player].characterId,
        earned = 0, tasks = 0, started = getTickCount(), data = {}, option = option,
    }
    shifts[player] = s
    setElementData(player, "rp:jobShift", jobId)
    local ok, reason = module.start(player, s, option)
    if ok == false then
        shifts[player] = nil
        setElementData(player, "rp:jobShift", false)
        if isElement(s.vehicle) then destroyElement(s.vehicle) end
        return false, reason
    end
    Jobs.refreshHud(player)
    return true
end

-- Comprobación de que el jugador está en el punto actual (con margen)
local function atWaypoint(player, s, wp)
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then return false end
    local veh = getPedOccupiedVehicle(player)
    if wp.mode == "drive" and (veh ~= s.vehicle or getVehicleController(veh) ~= player) then return false end
    if wp.mode == "foot" and veh then return false end
    local tx, ty, tz = wp.x, wp.y, wp.z
    if wp.attach == "vehicle" then
        if not isElement(s.vehicle) then return false end
        tx, ty, tz = attachedPosition(s.vehicle, wp.offset or {})
    end
    local x, y, z = getElementPosition(player)
    if dist2D(x, y, tx, ty) > wp.r + JOBS_CONFIG.REACH_SLACK then return false end
    if not wp.flat and tz and math.abs(z - tz) > 12 then return false end
    return true
end

addEventHandler("rp:jobs:reach", resourceRoot, function(wpId)
    local player = client
    local s = shifts[player]
    if not s or not s.wp or s.game or throttled(player, 250) then return end
    if tonumber(wpId) ~= s.wp.id or isDowned(player) then return end
    if not atWaypoint(player, s, s.wp) then return end
    local wp = s.wp
    s.wp = nil
    triggerClientEvent(player, "rp:jobs:wp", resourceRoot, false)
    local module = Jobs.modules[s.job]
    if module.onReach then module.onReach(player, s, wp) end
end)

addEventHandler("rp:jobs:gameResult", resourceRoot, function(token, result)
    local player = client
    local s = shifts[player]
    if not s or not s.game or s.game.token ~= token then return end
    local g = s.game
    s.game = nil
    if type(result) ~= "table" then result = { cancel = true } end
    if not result.cancel and getTickCount() - g.at < g.minMs then
        outputDebugString(("[rp_jobs] %s terminó %s demasiado rápido (%d ms)"):format(getPlayerName(player), g.name, getTickCount() - g.at), 2)
        result = { fail = true, tooFast = true }
    end
    if isDowned(player) then result = { cancel = true } end
    local module = Jobs.modules[s.job]
    if module.onGame then module.onGame(player, s, g.name, result, g.ctx) end
end)

-- Abandono del vehículo y ciclo de vida
setTimer(function()
    local now = getTickCount()
    for player, s in pairs(shifts) do
        if isElement(s.vehicle) and s.needsVehicle ~= false then
            local occupied = getPedOccupiedVehicle(player) == s.vehicle
            local px, py = getElementPosition(player)
            local vx, vy = getElementPosition(s.vehicle)
            if occupied or dist2D(px, py, vx, vy) < 400 then
                s.leftAt = nil
            else
                s.leftAt = s.leftAt or now
                if now - s.leftAt > JOBS_CONFIG.ABANDON_VEHICLE_MS then
                    Jobs.endShift(player, "Abandonaste el vehículo de trabajo.")
                end
            end
        end
        local module = Jobs.modules[s.job]
        if shifts[player] and module and module.tick then module.tick(player, s, now) end
    end
end, 5000, 0)

----------------------------------------------------------------
-- Trabajo del personaje (persistencia)
----------------------------------------------------------------
local function applyJob(player, jobId)
    info[player].job = jobId
    setElementData(player, "rp:job", jobId or false)
end

local function load(player)
    local characterId = characterOf(player)
    if not characterId then return end
    info[player] = { characterId = characterId, job = nil, stats = {}, loading = true }
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if not isElement(player) or characterOf(player) ~= characterId or not info[player] then return end
        local row = rows[1]
        info[player].hiredAt = row and tonumber(row.hired) or 0
        applyJob(player, row and JOBS_BY_ID[row.job_id] and row.job_id or nil)
        dbQuery(function(qh2)
            local stats = dbPoll(qh2, 0) or {}
            if not info[player] or info[player].characterId ~= characterId then return end
            for _, r in ipairs(stats) do
                info[player].stats[r.job_id] = {
                    xp = tonumber(r.xp) or 0, tasks = tonumber(r.tasks) or 0,
                    earned = tonumber(r.earned) or 0, best = tonumber(r.best_shift) or 0,
                }
            end
            info[player].loading = nil
        end, db(), "SELECT job_id, xp, tasks, earned, best_shift FROM job_stats WHERE character_id = ?", characterId)
    end, db(), "SELECT job_id, UNIX_TIMESTAMP(hired_at) AS hired FROM character_jobs WHERE character_id = ?", characterId)
end

local function unload(player)
    Jobs.endShift(player, nil, true)
    info[player] = nil
    if isElement(player) then setElementData(player, "rp:job", false) end
end

-- Sedes y puntos de venta: sus marcadores los dibuja el cliente; aqui se apuntan en rp_markers para
-- que los admins los muevan con el editor (ALT / M + clic derecho) y se usa la posicion movida
local function registerJobPoints()
    jobsResolvePoints()
    pcall(function()
        for _, job in ipairs(JOBS) do
            local h = job.hq
            if not job.external and h then
                exports.rp_markers:registerPoint("hq_" .. job.id, { label = "Sede · " .. job.name, point = { h.x, h.y, h.z },
                    interior = h.interior or 0, dimension = h.dimension or 0 })
            end
        end
        for _, mk in ipairs(MARKETS) do
            exports.rp_markers:registerPoint("market_" .. mk.id, { label = "Venta · " .. mk.name, point = { mk.x, mk.y, mk.z } })
        end
    end)
end

addEvent("rp:markers:moved")
addEvent("rp:markers:ready")
addEventHandler("rp:markers:moved", root, function(owner)
    if owner == getResourceName(resource) then registerJobPoints() end
end)
addEventHandler("rp:markers:ready", root, registerJobPoints)

addEventHandler("onResourceStart", resourceRoot, function()
    registerJobPoints()
    local function loadAll()
        for _, p in ipairs(getElementsByType("player")) do
            if characterOf(p) then load(p) end
        end
    end
    if exports.rp_database:isReady() then loadAll() else addEventHandler("rp:onDatabaseReady", root, loadAll) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(shifts) do Jobs.endShift(p, nil, true) end
    for _, p in ipairs(getElementsByType("player")) do
        removeElementData(p, "rp:jobShift")
    end
end)

addEventHandler("rp:onCharacterSpawn", root, function() load(source) end)
addEventHandler("rp:onCharacterLogout", root, function() unload(source) end)
addEventHandler("onPlayerQuit", root, function()
    unload(source)
    cooldown[source] = nil
end)
addEventHandler("onPlayerWasted", root, function()
    if shifts[source] then Jobs.endShift(source, "Tu turno terminó.") end
end)

----------------------------------------------------------------
-- API pública (exports, ver docs/TRABAJOS.md)
----------------------------------------------------------------
local function publicJob(job)
    return {
        id = job.id, name = job.name, icon = job.icon, description = job.description,
        pay = job.pay, howTo = job.howTo, requirements = job.requirements,
        locationName = job.locationName,
        location = { x = job.hq.x, y = job.hq.y, z = job.hq.z, interior = job.hq.interior or 0, dimension = job.hq.dimension or 0 },
        color = job.color, cinematic = job.cinematic,
    }
end

function getJobList()
    local list = {}
    for _, job in ipairs(JOBS) do list[#list + 1] = publicJob(job) end
    return list
end

function getJobInfo(jobId)
    local job = JOBS_BY_ID[jobId]
    return job and publicJob(job) or false
end

function getPlayerJob(player)
    return info[player] and info[player].job or nil
end

function isPlayerOnShift(player)
    return shifts[player] and true or false
end

function getPlayerJobLevel(player, jobId)
    if not info[player] then return 1 end
    return Jobs.level(player, jobId)
end

function getPlayerJobStats(player, jobId)
    local i = info[player]
    jobId = jobId or (i and i.job)
    if not i or not jobId then return false end
    local st = statsOf(player, jobId)
    return { xp = st.xp, level = levelFromXP(st.xp), tasks = st.tasks, earned = st.earned, bestShift = st.best }
end

-- force = true salta la espera entre cambios (admins o recursos de confianza)
function setPlayerJob(player, jobId, force)
    local i = info[player]
    if not isElement(player) or not i or i.loading then return false, "Tu personaje todavía no está cargado." end
    if not JOBS_BY_ID[jobId] then return false, "Ese trabajo no existe." end
    if i.job == jobId then return false, "Ya tienes ese trabajo." end
    local wait = (i.hiredAt or 0) + JOBS_CONFIG.CHANGE_COOLDOWN_MIN * 60 - os.time()
    if i.job and not force and wait > 0 then
        return false, ("Acabas de cambiar de trabajo. Espera %d min."):format(math.ceil(wait / 60))
    end
    local old = i.job
    if shifts[player] then Jobs.endShift(player, "Cambiaste de trabajo.") end
    dbExec(db(), [[
        INSERT INTO character_jobs (character_id, job_id, hired_at) VALUES (?, ?, NOW())
        ON DUPLICATE KEY UPDATE job_id = VALUES(job_id), hired_at = NOW()
    ]], i.characterId, jobId)
    i.hiredAt = os.time()
    applyJob(player, jobId)
    triggerEvent("rp:jobs:onJobChanged", player, jobId, old)
    return true
end

function quitPlayerJob(player)
    local i = info[player]
    if not i or not i.job then return false, "No tienes trabajo." end
    local old = i.job
    if shifts[player] then Jobs.endShift(player, "Dejaste el trabajo.") end
    dbExec(db(), "DELETE FROM character_jobs WHERE character_id = ?", i.characterId)
    applyJob(player, nil)
    triggerEvent("rp:jobs:onJobChanged", player, false, old)
    return true
end

----------------------------------------------------------------
-- Trabajos externos (job.external = "rp_x"): otro recurso juega el turno y rp_jobs
-- lleva el puesto, el turno (rp:jobShift, fin al morir o con /terminarturno), la XP y los pagos.
-- El recurso externo escucha rp:jobs:onShiftEnd para limpiar su parte.
----------------------------------------------------------------
for _, job in ipairs(JOBS) do
    if job.external then Jobs.register(job.id, { start = function() return true end }) end
end

local function externalShift(player)
    local s = shifts[player]
    return s and JOBS_BY_ID[s.job].external and s or nil
end

function startExternalShift(player, jobId)
    local job, i = JOBS_BY_ID[jobId], info[player]
    if not job or not job.external then return false, "Ese trabajo no es externo." end
    if not i or i.job ~= jobId then return false, "Este no es tu trabajo." end
    return startShift(player, jobId)
end

function endExternalShift(player, reason, quiet)
    if not externalShift(player) then return false end
    return Jobs.endShift(player, reason, quiet)
end

-- Paga `base` con el bonus de nivel y el tope de MAX_TASK_PAY. Devuelve lo pagado.
function payExternalJob(player, base, label)
    if not externalShift(player) or type(base) ~= "number" then return 0 end
    return Jobs.pay(player, base, label)
end

function giveExternalJobXP(player, amount)
    if not externalShift(player) or type(amount) ~= "number" then return false end
    Jobs.xp(player, amount)
    return true
end

function showJobLocation(player, jobId)
    local job = JOBS_BY_ID[jobId]
    if not job or not isElement(player) then return false end
    triggerClientEvent(player, "rp:jobs:gps", resourceRoot, job.id)
    return true
end

----------------------------------------------------------------
-- Sede del trabajo (panel)
----------------------------------------------------------------
local function hqPanelData(player, jobId)
    local job, i = JOBS_BY_ID[jobId], info[player]
    local st = statsOf(player, jobId)
    local level = levelFromXP(st.xp)
    local module = Jobs.modules[jobId]
    return {
        job = publicJob(job), myJob = i.job or false, onShift = shifts[player] and shifts[player].job or false,
        canHire = JOBS_CONFIG.HIRE_AT_HQ and i.job ~= jobId,
        level = level, xp = st.xp, levelXP = JOBS_CONFIG.LEVEL_XP[level], nextXP = JOBS_CONFIG.LEVEL_XP[level + 1] or false,
        tasks = st.tasks, earned = st.earned, best = st.best,
        bonus = math.floor((level - 1) * JOBS_CONFIG.LEVEL_PAY_BONUS * 100 + 0.5),
        options = module and module.options and module.options(player, level) or {},
        perks = module and module.perks or {},
    }
end

addEventHandler("rp:jobs:openHQ", resourceRoot, function(jobId)
    local player = client
    local job = JOBS_BY_ID[jobId]
    if not job or not info[player] or throttled(player) or isDowned(player) then return end
    if not nearPoint(player, job.hq, 4) then return end
    triggerClientEvent(player, "rp:jobs:panel", resourceRoot, hqPanelData(player, jobId))
end)

addEventHandler("rp:jobs:hqAction", resourceRoot, function(jobId, action, option)
    local player = client
    local job = JOBS_BY_ID[jobId]
    if not job or not info[player] or throttled(player, 600) or isDowned(player) then return end
    if not nearPoint(player, job.hq, 5) then return notify(player, "Acércate a la sede.", "warning") end
    if type(option) ~= "string" then option = nil end

    local ok, reason = true, nil
    if action == "hire" then
        if not JOBS_CONFIG.HIRE_AT_HQ then return notify(player, "Pide el puesto en la agencia de trabajos.", "warning") end
        ok, reason = setPlayerJob(player, jobId)
        if ok then notify(player, ("Ahora trabajas de %s. Empieza tu turno aquí mismo."):format(job.name), "success") end
    elseif action == "start" then
        if info[player].job ~= jobId then return notify(player, "Este no es tu trabajo.", "error") end
        ok, reason = startShift(player, jobId, option)
        if ok then triggerClientEvent(player, "rp:jobs:closePanel", resourceRoot) return end
    elseif action == "stop" then
        if not shifts[player] then return end
        local module = Jobs.modules[shifts[player].job]
        if module and module.finishAtHQ then module.finishAtHQ(player, shifts[player]) end
        Jobs.endShift(player, "Terminaste tu turno.")
        triggerClientEvent(player, "rp:jobs:closePanel", resourceRoot)
        return
    elseif action == "quit" then
        ok, reason = quitPlayerJob(player)
        if ok then notify(player, "Dejaste tu trabajo.", "info") end
    else
        return
    end
    if not ok and reason then notify(player, reason, "error") end
    triggerClientEvent(player, "rp:jobs:panel", resourceRoot, hqPanelData(player, jobId))
end)

----------------------------------------------------------------
-- Comandos
----------------------------------------------------------------
addCommandHandler("trabajo", function(player)
    local i = info[player]
    if not i then return end
    if not i.job then
        return notify(player, "No tienes trabajo. Ve a la agencia de trabajos para conseguir uno.", "info")
    end
    local job, st = JOBS_BY_ID[i.job], statsOf(player, i.job)
    notify(player, ("%s %s · nivel %d (%d XP) · ganado en total $%d. Marqué la sede en tu mapa."):format(
        job.icon, job.name, levelFromXP(st.xp), st.xp, st.earned), "info", 7000)
    showJobLocation(player, i.job)
end)

addCommandHandler("terminarturno", function(player)
    if not shifts[player] then return notify(player, "No estás de turno.", "warning") end
    Jobs.endShift(player, "Terminaste tu turno.")
end)

addCommandHandler("dejartrabajo", function(player)
    local ok, reason = quitPlayerJob(player)
    notify(player, ok and "Dejaste tu trabajo." or reason, ok and "info" or "warning")
end)

addCommandHandler("setjob", function(player, _, query, jobId)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    if not target or not jobId then
        local ids = {}
        for _, j in ipairs(JOBS) do ids[#ids + 1] = j.id end
        return notify(player, "Uso: /setjob <id o nombre> <" .. table.concat(ids, "|") .. "|ninguno>", "warning", 8000)
    end
    local ok, reason
    if jobId == "ninguno" then ok, reason = quitPlayerJob(target)
    else ok, reason = setPlayerJob(target, jobId, true) end
    if not ok then return notify(player, reason or "No se pudo.", "error") end
    local name = getPlayerName(target):gsub("_", " ")
    notify(player, ("Trabajo de %s: %s."):format(name, jobId), "success")
    notify(target, jobId == "ninguno" and "Un administrador te quitó el trabajo." or
        ("Un administrador te asignó el trabajo de %s."):format(JOBS_BY_ID[jobId].name), "info")
end)

addCommandHandler("darxptrabajo", function(player, _, query, amount)
    if not isAdmin(player) then return notify(player, "No tienes permiso para usar este comando.", "error") end
    local target = query and exports.rp_ids:findPlayer(query)
    amount = tonumber(amount)
    local i = target and info[target]
    if not i or not i.job or not amount or amount ~= math.floor(amount) or amount < 1 then
        return notify(player, "Uso: /darxptrabajo <id o nombre> <xp> (el jugador debe tener trabajo)", "warning")
    end
    local st = statsOf(target, i.job)
    st.xp = st.xp + amount
    saveStats(target, i.job, amount, 0, 0)
    notify(player, ("+%d XP de %s para %s (nivel %d)."):format(amount, i.job, getPlayerName(target):gsub("_", " "), levelFromXP(st.xp)), "success")
    Jobs.refreshHud(target)
end)
