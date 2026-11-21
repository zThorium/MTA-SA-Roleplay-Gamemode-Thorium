--[[
    rp_jobs / jobs/s_garbage.lua  -  Recolector de basura

    Ruta de GARBAGE.STOPS_PER_ROUTE paradas al azar (ordenadas por cercanía).
    En cada parada: bajas del camión, llevas las bolsas una a una a la parte de atrás
    y, al cargar la última, se abre el minijuego del compactador (vista del interior del
    camión): arrastrar bolsas al compactador, reciclables a su contenedor, no tocar las
    jeringas y quedarte con lo de valor. El servidor decide antes qué hallazgos hay.
    Al volver a la planta con la ruta completa se cobra el bono y empieza otra ruta.
]]

local G = GARBAGE

local function routeFrom(x, y)
    local pool = Jobs.shuffle(G.POINTS)
    local picked = {}
    for i = 1, math.min(G.STOPS_PER_ROUTE, #pool) do picked[i] = pool[i] end
    -- vecino más cercano desde la planta
    local ordered, cx, cy = {}, x, y
    while #picked > 0 do
        local best, bestD = 1, math.huge
        for i, p in ipairs(picked) do
            local d = (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2
            if d < bestD then best, bestD = i, d end
        end
        local p = table.remove(picked, best)
        ordered[#ordered + 1] = p
        cx, cy = p[1], p[2]
    end
    return ordered
end

local function rollFinds(level)
    local finds = {}
    local chance = G.FIND_CHANCE + (level - 1) * G.FIND_CHANCE_PER_LEVEL
    local count = (math.random() < chance) and ((math.random() < chance * 0.5) and 2 or 1) or 0
    for i = 1, count do
        local f = Jobs.pickWeighted(G.FINDS, level)
        if f.cash then
            finds[i] = { cash = math.random(f.cash[1], f.cash[2]), icon = "💵", name = "Fajo de billetes" }
        else
            local def = exports.rp_inventory:getItemDefinition(f.item)
            finds[i] = { item = f.item, icon = def and def.icon or "❔", name = def and def.name or f.item }
        end
    end
    return finds
end

local function nextStop(player, s)
    local d = s.data
    d.idx = d.idx + 1
    if d.idx > #d.stops then
        local hq = JOBS_BY_ID.garbage.hq
        Jobs.hud(player, "Ruta completa: vuelve a la planta con el camión", ("Paradas %d/%d"):format(#d.stops, #d.stops))
        Jobs.waypoint(player, { kind = "depot", x = hq.x, y = hq.y, z = hq.z, r = 9, mode = "drive", act = "enter",
            label = "Planta de residuos", marker = "checkpoint" })
        return
    end
    local p = d.stops[d.idx]
    Jobs.hud(player, "Conduce hasta la siguiente parada", ("Parada %d/%d"):format(d.idx, #d.stops))
    Jobs.waypoint(player, { kind = "stop", x = p[1], y = p[2], z = p[3], r = 9, mode = "drive", act = "enter",
        label = ("Parada %d"):format(d.idx), marker = "checkpoint" })
end

local function askBag(player, s)
    local d, p = s.data, s.data.stops[s.data.idx]
    Jobs.hud(player, "Recoge las bolsas y llévalas al camión", ("Bolsas %d/%d · Parada %d/%d"):format(d.loaded, d.bags, d.idx, #d.stops))
    Jobs.waypoint(player, { kind = "bag", x = p[1], y = p[2], z = p[3], r = 3, mode = "foot", act = "press",
        text = "Pulsa E para coger una bolsa", label = "Bolsas de basura", marker = "cylinder", blip = false })
end

Jobs.register("garbage", {
    perks = {
        "Más probabilidad de encontrar objetos de valor con cada nivel.",
        "Bono de ruta completa al volver a la planta.",
    },

    start = function(player, s)
        local job = JOBS_BY_ID.garbage
        if not Jobs.spawnVehicle(player, job.vehicle) then return false, "No hay camión disponible." end
        s.data = { stops = routeFrom(job.hq.x, job.hq.y), idx = 0, route = 1 }
        Jobs.notify(player, "Sube al camión de basura y empieza la ruta.", "info", 6000)
        nextStop(player, s)
    end,

    onReach = function(player, s, wp)
        local d = s.data
        if wp.kind == "stop" then
            local p = d.stops[d.idx]
            d.bags, d.loaded = math.random(G.BAGS_MIN, G.BAGS_MAX), 0
            local props = {}
            for i = 1, d.bags do
                local a = math.rad(i * 360 / d.bags + math.random(-20, 20))
                props[i] = { key = "bag" .. i, model = (i % 2 == 0) and 1265 or 1264,
                    x = p[1] + math.cos(a) * 1.2, y = p[2] + math.sin(a) * 1.2, z = p[3], rz = math.random(0, 359), snap = true }
            end
            Jobs.props(player, props)
            Jobs.notify(player, ("Hay %d bolsas. Bájate y cárgalas atrás del camión."):format(d.bags), "info")
            askBag(player, s)

        elseif wp.kind == "bag" then
            Jobs.hold(player, 1264, { 0.05, 0.02, -0.25, 0, 0, 0 })
            Jobs.propFx(player, "bag" .. (d.loaded + 1), "remove")
            Jobs.hud(player, "Lleva la bolsa a la parte de atrás del camión", ("Bolsas %d/%d"):format(d.loaded, d.bags))
            Jobs.waypoint(player, { kind = "load", attach = "vehicle", offset = G.TRUCK_REAR, r = 2.2, mode = "foot", act = "press",
                text = "Pulsa E para tirar la bolsa al camión", label = "Camión", marker = "cylinder", blip = false })

        elseif wp.kind == "load" then
            Jobs.hold(player, false)
            Jobs.anim(player, "GRENADE", "WEAPON_throwu", false)
            Jobs.sound(player, "trash")
            d.loaded = d.loaded + 1
            if d.loaded < d.bags then return askBag(player, s) end
            -- Todas cargadas: compactador
            d.finds = rollFinds(Jobs.level(player, "garbage"))
            local params = {
                bags = d.bags + math.random(1, 3),                 -- también hay basura suelta de antes
                recyclables = math.random(2, 5),
                hazards = math.random(0, 2) + (d.idx >= 4 and 1 or 0),
                finds = d.finds, time = 30,
            }
            d.gameParams = params
            Jobs.hud(player, "Ordena la basura dentro del camión", "")
            Jobs.game(player, "compactor", params, 5000)

        elseif wp.kind == "depot" then
            Jobs.pay(player, G.ROUTE_BONUS, ("Bono de ruta %d"):format(d.route))
            Jobs.xp(player, 30)
            d.route = d.route + 1
            d.stops, d.idx = routeFrom(wp.x, wp.y), 0
            Jobs.notify(player, "Nueva ruta asignada. Termina el turno en la oficina cuando quieras.", "info", 6000)
            nextStop(player, s)
        end
    end,

    onGame = function(player, s, name, r, ctx)
        local d, p = s.data, s.data.gameParams or {}
        Jobs.anim(player, false)
        if name ~= "compactor" then return end
        local score = 0
        if not r.cancel and not r.fail then
            local compacted = math.max(0, math.min(tonumber(r.compacted) or 0, p.bags))
            local recycled = math.max(0, math.min(tonumber(r.recycled) or 0, p.recyclables))
            local touched = math.max(0, math.min(tonumber(r.hazards) or 0, p.hazards))
            score = compacted / math.max(1, p.bags) * 0.6 + recycled / math.max(1, p.recyclables) * 0.3 + 0.1 - touched * 0.15
            score = math.max(0, math.min(1, score))
            if touched > 0 then
                setElementHealth(player, math.max(5, getElementHealth(player) - 5 * touched))
                Jobs.notify(player, "Te pinchaste con una jeringa. Ten más cuidado.", "warning")
            end
            -- Hallazgos: solo los que el servidor generó para esta parada
            local seen = {}
            for _, idx in ipairs(type(r.found) == "table" and r.found or {}) do
                idx = tonumber(idx)
                local f = idx and d.finds and d.finds[idx]
                if f and not seen[idx] then
                    seen[idx] = true
                    if f.cash then
                        givePlayerMoney(player, f.cash)
                        exports.rp_characters:saveCharacter(player)
                        Jobs.notify(player, ("¡Encontraste un fajo con $%d!"):format(f.cash), "success")
                    elseif Jobs.give(player, f.item, 1) > 0 then
                        Jobs.notify(player, ("¡Encontraste %s! Véndelo en la compraventa."):format(f.name), "success")
                    end
                end
            end
        end
        d.finds = nil
        Jobs.pay(player, G.PAY_PER_STOP + (G.PAY_PER_STOP_MAX - G.PAY_PER_STOP) * score,
            ("Parada %d (%d%%)"):format(d.idx, math.floor(score * 100)))
        Jobs.xp(player, 10 + math.floor(score * 8))
        Jobs.props(player, {})
        nextStop(player, s)
    end,

    stop = function(player, s)
        if isElement(player) then Jobs.hold(player, false) end
    end,
})
