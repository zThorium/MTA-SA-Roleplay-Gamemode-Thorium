--[[
    rp_jobs / jobs/s_farmer.lua  -  Granjero

    Cada temporada (un cultivo al azar):
      1. Arar: recorrer las filas del campo con el tractor (puntos en zigzag). Cuenta el tiempo.
      2. Sembrar a mano: minijuego "sow" (sembrar en el momento justo a lo largo del surco).
      3. Cuidar: 1 o 2 eventos al azar entre plaga ("pests"), sequía ("water") y malas hierbas ("weeds").
      4. Cosechar con la cosechadora (mismos surcos) y llevar el grano al silo.
    Pago entre FARMER.PAY_MIN y PAY_MAX según la calidad media de todos los pasos.
]]

local F = FARMER

local CARE_TEXT = {
    pests = { "¡Plaga en el cultivo! Pulsa E para espantar los bichos", "Plaga" },
    water = { "La tierra está seca. Pulsa E para regar", "Sequía" },
    weeds = { "Salieron malas hierbas. Pulsa E para arrancarlas", "Malas hierbas" },
}

local function fieldPoints(n)
    local f, pts = F.FIELD, {}
    local perRow = math.max(2, math.floor(n / f.rows))
    for row = 0, f.rows - 1 do
        local y = f.y - (f.rows - 1) * f.rowGap / 2 + row * f.rowGap
        for k = 0, perRow - 1 do
            local t = perRow == 1 and 0.5 or k / (perRow - 1)
            if row % 2 == 1 then t = 1 - t end
            pts[#pts + 1] = { f.x - f.width / 2 + t * f.width, y, f.z }
        end
    end
    return pts
end

local function randomFieldSpot()
    local f = F.FIELD
    return { f.x + math.random(-f.width / 2 + 5, f.width / 2 - 5), f.y + math.random(-15, 15), f.z }
end

local function driveNext(player, s, phase)
    local d = s.data
    d.pi = d.pi + 1
    local p = d.points[d.pi]
    Jobs.hud(player, phase == "plow" and ("Ara el campo de %s con el tractor"):format(d.crop.name)
        or "Cosecha con la cosechadora", ("Surco %d/%d"):format(d.pi, #d.points))
    Jobs.waypoint(player, { kind = phase, x = p[1], y = p[2], z = p[3], r = 6, mode = "drive", act = "enter",
        label = phase == "plow" and "Arar" or "Cosechar", marker = "checkpoint", flat = true })
end

local function nextCare(player, s)
    local d = s.data
    d.ci = d.ci + 1
    local ev = d.care[d.ci]
    if not ev then
        -- Cosecha: cambia el tractor por la cosechadora
        local v = Jobs.vehicle(player)
        local spec = { model = F.HARVEST_MODEL, x = JOBS_BY_ID.farmer.vehicle.x, y = JOBS_BY_ID.farmer.vehicle.y,
            z = JOBS_BY_ID.farmer.vehicle.z + 0.5, rz = JOBS_BY_ID.farmer.vehicle.rz }
        if v then spec.x, spec.y, spec.z = getElementPosition(v); spec.z = spec.z + 0.6 end
        Jobs.spawnVehicle(player, spec)
        Jobs.notify(player, ("El %s está listo. Sube a la cosechadora."):format(d.crop.name:lower()), "info", 6000)
        d.points, d.pi = fieldPoints(F.PLOW_POINTS), 0
        return driveNext(player, s, "harvest")
    end
    local spot = randomFieldSpot()
    Jobs.hud(player, CARE_TEXT[ev][2] .. ": ve al punto marcado del campo", ("Cuidados %d/%d"):format(d.ci, #d.care))
    Jobs.waypoint(player, { kind = "care", event = ev, x = spot[1], y = spot[2], z = spot[3], r = 3, mode = "foot",
        act = "press", text = CARE_TEXT[ev][1], label = CARE_TEXT[ev][2], flat = true, marker = "cylinder" })
end

local function newSeason(player, s)
    local crop = F.CROPS[math.random(#F.CROPS)]
    local care = Jobs.shuffle(F.CARE_EVENTS)
    local count = math.random() < 0.45 and 2 or 1
    s.data = { crop = crop, points = fieldPoints(F.PLOW_POINTS), pi = 0, scores = {}, care = {}, ci = 0, plowStart = nil }
    for i = 1, count do s.data.care[i] = care[i] end
    Jobs.notify(player, ("Nueva temporada: toca sembrar %s %s."):format(crop.icon, crop.name:lower()), "info", 6000)
    driveNext(player, s, "plow")
end

local function average(t)
    local sum = 0
    for _, v in ipairs(t) do sum = sum + v end
    return #t > 0 and sum / #t or 0
end

Jobs.register("farmer", {
    perks = {
        "Cada temporada cambia el cultivo y lo que hay que cuidar.",
        "Arar rápido y sembrar con precisión sube la calidad de la cosecha.",
    },

    start = function(player, s)
        if not Jobs.spawnVehicle(player, JOBS_BY_ID.farmer.vehicle) then return false, "No hay tractor disponible." end
        Jobs.notify(player, "Sube al tractor y ara el campo siguiendo los puntos.", "info", 6000)
        newSeason(player, s)
    end,

    onReach = function(player, s, wp)
        local d = s.data
        if wp.kind == "plow" then
            d.plowStart = d.plowStart or getTickCount()
            if d.pi < #d.points then return driveNext(player, s, "plow") end
            local expected = #d.points * 12000
            local took = getTickCount() - d.plowStart
            d.scores[#d.scores + 1] = math.max(0.3, math.min(1, 1 - (took - expected) / expected))
            Jobs.xp(player, 8)
            local p = F.SOW_SPOT
            Jobs.hud(player, "Bájate del tractor y siembra a mano", d.crop.icon .. " " .. d.crop.name)
            Jobs.waypoint(player, { kind = "sow", x = p[1], y = p[2], z = p[3], r = 3, mode = "foot", act = "press",
                text = "Pulsa E para sembrar", label = "Sembrar", marker = "cylinder" })

        elseif wp.kind == "sow" then
            Jobs.anim(player, "BOMBER", "BOM_Plant_Loop", true)
            Jobs.game(player, "sow", { crop = d.crop.icon, rows = 3, seeds = 6, speed = 1 + Jobs.level(player) * 0.08 }, 6000)

        elseif wp.kind == "care" then
            Jobs.anim(player, "BOMBER", "BOM_Plant_Loop", true)
            local params = { crop = d.crop.icon, time = 20 }
            if wp.event == "pests" then params.bugs = 14 + Jobs.level(player) * 2
            elseif wp.event == "water" then params.cells = 24
            else params.weeds = 10 end
            Jobs.game(player, wp.event, params, 5000, wp.event)

        elseif wp.kind == "harvest" then
            if d.pi < #d.points then return driveNext(player, s, "harvest") end
            Jobs.xp(player, 8)
            Jobs.hud(player, "Lleva la cosecha al silo", d.crop.icon .. " " .. d.crop.name)
            Jobs.waypoint(player, { kind = "silo", x = F.SILO[1], y = F.SILO[2], z = F.SILO[3], r = 8, mode = "drive",
                act = "enter", label = "Silo", marker = "checkpoint" })

        elseif wp.kind == "silo" then
            local q = average(d.scores)
            Jobs.pay(player, F.PAY_MIN + (F.PAY_MAX - F.PAY_MIN) * q, ("Cosecha de %s (calidad %d%%)"):format(d.crop.name:lower(), math.floor(q * 100)))
            Jobs.xp(player, 30)
            Jobs.spawnVehicle(player, JOBS_BY_ID.farmer.vehicle)
            Jobs.notify(player, "El tractor te espera en la granja para la próxima temporada.", "info", 6000)
            newSeason(player, s)
        end
    end,

    onGame = function(player, s, name, r, ctx)
        local d = s.data
        Jobs.anim(player, false)
        local score = 0
        if not r.cancel and not r.fail then score = math.max(0, math.min(1, tonumber(r.score) or 0)) end
        d.scores[#d.scores + 1] = score
        Jobs.xp(player, 5 + math.floor(score * 6))
        if name == "sow" then
            Jobs.notify(player, ("Siembra al %d%%. Ahora a esperar que crezca..."):format(math.floor(score * 100)), score >= 0.6 and "success" or "warning")
            setTimer(function()
                if Jobs.shift(player) == s then nextCare(player, s) end
            end, 3000, 1)
        else
            Jobs.notify(player, ("Cuidado del cultivo: %d%%"):format(math.floor(score * 100)), score >= 0.6 and "success" or "warning")
            nextCare(player, s)
        end
    end,
})
