--[[
    rp_jobs / jobs/s_lumber.lua  -  Leñador

    Carga de LUMBER.TREES_PER_LOAD árboles del bosque de Shady Creeks:
      1. En cada árbol, minijuego "fell": eliges hacia dónde cae (hay obstáculos alrededor que
         decide el servidor) y lo talas golpeando en el momento justo.
      2. El árbol cae hacia el lado elegido; llevas el tronco al camión (se ve cargado en la caja).
      3. Con la carga completa vas al aserradero y cortas los troncos en tablas (minijuego "saw").
    Pago por tronco entre PAY_PER_LOG y PAY_PER_LOG_MAX según el corte y las tablas.
]]

local L = LUMBER
local OBSTACLES = { "road", "cabin", "tree", "powerline", "rocks", "creek" }

local function clearLogs(s)
    for _, o in ipairs(s.data.logObjs or {}) do
        if isElement(o) then destroyElement(o) end
    end
    s.data.logObjs = {}
end

local function newLoad(player, s)
    if s.data then clearLogs(s) end
    local trees = Jobs.shuffle(L.TREES)
    s.data = { trees = {}, idx = 0, quality = {}, logObjs = {} }
    local props = {}
    for i = 1, L.TREES_PER_LOAD do
        local t = trees[i]
        s.data.trees[i] = t
        props[i] = { key = "tree" .. i, model = L.TREE_MODELS[math.random(#L.TREE_MODELS)], x = t[1], y = t[2], z = t[3],
            rz = math.random(0, 359), snap = true, snapHeight = 40 }
    end
    Jobs.props(player, props)
end

local function nextTree(player, s)
    local d = s.data
    d.idx = d.idx + 1
    if d.idx > #d.trees then
        local p = L.SAWMILL
        Jobs.hud(player, "Camión cargado: llévalo al aserradero", ("Troncos %d/%d"):format(#d.quality, #d.trees))
        return Jobs.waypoint(player, { kind = "sawmill", x = p[1], y = p[2], z = p[3], r = 9, mode = "drive", act = "enter",
            label = "Aserradero", marker = "checkpoint" })
    end
    local t = d.trees[d.idx]
    Jobs.hud(player, "Ve al árbol marcado y tálalo", ("Árbol %d/%d"):format(d.idx, #d.trees))
    Jobs.waypoint(player, { kind = "tree", x = t[1], y = t[2], z = t[3], r = 3.5, mode = "foot", act = "press", flat = true,
        text = "Pulsa E para talar el árbol", label = ("Árbol %d"):format(d.idx), marker = "cylinder" })
end

-- 8 direcciones (0 = norte, 45 = noreste...). 3-5 tienen obstáculo; el resto son seguras.
local function rollObstacles()
    local dirs, blocked = {}, {}
    local n = math.random(3, 5)
    local order = Jobs.shuffle({ 0, 1, 2, 3, 4, 5, 6, 7 })
    for i = 1, n do blocked[order[i]] = OBSTACLES[math.random(#OBSTACLES)] end
    for i = 0, 7 do dirs[#dirs + 1] = { dir = i, obstacle = blocked[i] or false } end
    return dirs
end

Jobs.register("lumber", {
    perks = {
        "Elegir bien hacia dónde cae el árbol evita dañar la madera.",
        "Las tablas bien cortadas en el aserradero se pagan casi al doble.",
    },

    start = function(player, s)
        if not Jobs.spawnVehicle(player, JOBS_BY_ID.lumber.vehicle) then return false, "No hay camión disponible." end
        Jobs.notify(player, "Sube al camión y ve al bosque. Los árboles a talar están marcados.", "info", 6000)
        newLoad(player, s)
        nextTree(player, s)
    end,

    onReach = function(player, s, wp)
        local d = s.data
        if wp.kind == "tree" then
            d.dirs = rollObstacles()
            Jobs.hold(player, 341, { 0, 0, 0, 0, 0, 0 })
            Jobs.anim(player, "CHAINSAW", "WEAPON_csaw", true)
            Jobs.game(player, "fell", { dirs = d.dirs, hits = 5 + math.floor(Jobs.level(player) / 2), speed = 1 + d.idx * 0.08 }, 5000)

        elseif wp.kind == "log" then
            Jobs.sound(player, "wood")
            local v = Jobs.vehicle(player)
            if v then
                local n = #d.logObjs
                local x, y, z = getElementPosition(v)
                local o = createObject(L.LOG_MODEL, x, y, z)
                if o then
                    setElementCollisionsEnabled(o, false)
                    attachElements(o, v, (n % 2 == 0) and -0.45 or 0.45, -1.6 - math.floor(n / 2) * 1.3, 0.55 + math.floor(n / 4) * 0.5, 0, 0, 90)
                    d.logObjs[#d.logObjs + 1] = o
                end
            end
            Jobs.propFx(player, "tree" .. d.idx, "remove")
            nextTree(player, s)

        elseif wp.kind == "sawmill" then
            local p = L.SAWMILL
            Jobs.hud(player, "Bájate y corta los troncos en la sierra", ("Troncos %d"):format(#d.quality))
            Jobs.waypoint(player, { kind = "saw", x = p[1] + 4, y = p[2], z = p[3], r = 3, mode = "foot", act = "press",
                text = "Pulsa E para usar la sierra", label = "Sierra", marker = "cylinder" })

        elseif wp.kind == "saw" then
            Jobs.game(player, "saw", { logs = #d.quality, speed = 1 + Jobs.level(player) * 0.05 }, 4000 * #d.quality)
        end
    end,

    onGame = function(player, s, name, r, ctx)
        local d = s.data
        Jobs.anim(player, false)
        if name == "fell" then
            Jobs.hold(player, false)
            local q = 0.3
            local dir = tonumber(r.dir)
            local entry = dir and d.dirs[dir + 1]
            if not r.cancel and not r.fail and entry then
                local hits = math.max(0, math.min(tonumber(r.hits) or 0, 20))
                local misses = math.max(0, math.min(tonumber(r.misses) or 0, 50))
                q = hits / math.max(1, hits + misses)
                if entry.obstacle then
                    q = q * 0.4
                    Jobs.notify(player, "El árbol cayó sobre un obstáculo: la madera se dañó.", "warning")
                end
            elseif r.cancel then
                -- Se puede volver a intentar
                local t = d.trees[d.idx]
                return Jobs.waypoint(player, { kind = "tree", x = t[1], y = t[2], z = t[3], r = 3.5, mode = "foot", act = "press",
                    flat = true, text = "Pulsa E para talar el árbol", label = ("Árbol %d"):format(d.idx), marker = "cylinder" })
            end
            d.quality[#d.quality + 1] = math.max(0.1, math.min(1, q))
            Jobs.xp(player, 6 + math.floor(q * 6))
            Jobs.propFx(player, "tree" .. d.idx, "fall", ((dir or math.random(0, 7)) * 45))
            Jobs.sound(player, "timber")
            Jobs.hud(player, "Lleva el tronco al camión", ("Árbol %d/%d"):format(d.idx, #d.trees))
            Jobs.waypoint(player, { kind = "log", attach = "vehicle", offset = { 0, -4.5, 0 }, r = 2.5, mode = "foot", act = "press",
                text = "Pulsa E para cargar el tronco", label = "Camión", marker = "cylinder", blip = false })

        elseif name == "saw" then
            local acc = {}
            if type(r.cuts) == "table" and not r.fail then
                for i = 1, #d.quality do acc[i] = math.max(0, math.min(1, tonumber(r.cuts[i]) or 0)) end
            end
            local total = 0
            for i, q in ipairs(d.quality) do
                local cut = acc[i] or (r.cancel and 0.3 or 0)
                total = total + L.PAY_PER_LOG + (L.PAY_PER_LOG_MAX - L.PAY_PER_LOG) * (q * 0.5 + cut * 0.5)
            end
            Jobs.pay(player, total, ("%d troncos al aserradero"):format(#d.quality))
            Jobs.xp(player, 20)
            Jobs.notify(player, "Nueva carga: vuelve al bosque.", "info")
            newLoad(player, s)
            nextTree(player, s)
        end
    end,

    stop = function(player, s)
        if s.data then clearLogs(s) end
    end,
})
