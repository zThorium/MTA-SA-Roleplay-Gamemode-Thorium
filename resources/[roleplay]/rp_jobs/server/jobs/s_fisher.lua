--[[
    rp_jobs / jobs/s_fisher.lua  -  Pescador

    Modo muelle (a pie) o barco (nivel FISHER.BOAT_LEVEL). Cada punto de pesca tiene unas
    pocas capturas; al agotarse hay que moverse a otro. En cada lanzamiento el servidor elige
    la especie (según muelle/mar y nivel). Se lanza y se espera la picada en el mundo (pulsar E
    a tiempo, sin picar a los amagos). Los peces pequeños salen solos; los grandes (dificultad
    >= FISHER.REEL_DIFFICULTY) pelean y se abre el minijuego "fish" para recogerlos.
    Lo pescado va al inventario y se vende en la lonja.
]]

local F = FISHER

local function pickSpot(player, s)
    local d = s.data
    local list = d.boat and F.SEA_SPOTS or F.PIER_SPOTS
    local options = {}
    for i, p in ipairs(list) do
        if i ~= d.spotIndex then options[#options + 1] = i end
    end
    d.spotIndex = options[math.random(#options)]
    d.spot = list[d.spotIndex]
    d.stock = math.random(F.SPOT_STOCK[1], F.SPOT_STOCK[2])
end

local function askCast(player, s, moved)
    local d, p = s.data, s.data.spot
    Jobs.hud(player, moved and "Ve al punto de pesca marcado" or "Lanza la caña", ("Picadas restantes aquí: %s"):format(d.stock > 2 and "muchas" or "pocas"))
    Jobs.waypoint(player, { kind = "spot", x = p[1], y = p[2], z = p[3], r = d.boat and 14 or 2.5, mode = d.boat and "any" or "foot",
        act = "press", flat = d.boat, text = "Pulsa E para pescar", label = d.boat and "Banco de peces" or "Punto de pesca",
        marker = d.boat and "ring" or "cylinder" })
end

local function pickSpecies(player, s)
    local key = s.data.boat and "sea" or "pier"
    local level = Jobs.level(player, "fisher")
    local list = {}
    for _, sp in ipairs(F.SPECIES) do
        if (sp.minLevel or 1) <= level and (sp[key] or 0) > 0 then
            list[#list + 1] = { sp = sp, weight = sp[key] }
        end
    end
    return Jobs.pickWeighted(list, level).sp
end

Jobs.register("fisher", {
    perks = {
        ("Con nivel %d puedes salir en barco a los bancos de peces."):format(FISHER.BOAT_LEVEL),
        "En el mar hay atunes y, desde nivel 3, peces espada.",
    },

    options = function(player, level)
        return {
            { id = "pier", label = "Pescar en el muelle", enabled = true },
            { id = "boat", label = "Salir en barco", enabled = level >= F.BOAT_LEVEL,
                note = level >= F.BOAT_LEVEL and nil or ("Nivel %d"):format(F.BOAT_LEVEL) },
        }
    end,

    start = function(player, s, option)
        local boat = option == "boat"
        if boat and Jobs.level(player, "fisher") < F.BOAT_LEVEL then
            return false, ("Necesitas nivel %d para salir en barco."):format(F.BOAT_LEVEL)
        end
        s.data = { boat = boat }
        if boat then
            if not Jobs.spawnVehicle(player, JOBS_BY_ID.fisher.boat) then return false, "No hay barcos libres." end
            Jobs.notify(player, "Tu barco está en el agua junto al muelle. Ve a los bancos de peces.", "info", 6000)
        else
            Jobs.notify(player, "Busca el punto de pesca marcado en el muelle.", "info")
        end
        pickSpot(player, s)
        askCast(player, s, true)
    end,

    onReach = function(player, s, wp)
        local d = s.data
        d.species = pickSpecies(player, s)
        Jobs.hold(player, 338, { 0, 0, 0, 0, 0, 0 })
        local level = Jobs.level(player, "fisher")
        Jobs.anim(player, "SWORD", "sword_IDLE", true)
        Jobs.action(player, "_bite", { waitMin = 2500, waitMax = 7000, window = 700 + level * 60, fakes = math.random(0, 2) }, "bite")
    end,

    onGame = function(player, s, name, r, ctx)
        local d = s.data
        Jobs.anim(player, false)
        if name == "_bite" and r.caught and not r.fail and not r.cancel and d.species.difficulty >= F.REEL_DIFFICULTY then
            Jobs.notify(player, "¡Es grande! Recoge sin romper el sedal.", "info")
            return Jobs.game(player, "fish", { difficulty = d.species.difficulty, sea = d.boat, reelOnly = true }, 2500)
        end
        Jobs.hold(player, false)
        if r.cancel then return askCast(player, s, false) end
        if r.caught and not r.fail then
            local sp = d.species
            if Jobs.give(player, sp.item, 1) > 0 then
                Jobs.notify(player, ("¡Pescaste: %s!"):format(sp.name), sp.item == "old_boot" and "info" or "success")
            end
            Jobs.xp(player, 4 + math.floor(sp.difficulty * 10))
        elseif r.reason == "line" then
            Jobs.notify(player, "¡Se rompió el sedal!", "warning")
        elseif r.reason == "early" then
            Jobs.notify(player, "Tiraste antes de tiempo y espantaste al pez.", "warning")
        else
            Jobs.notify(player, "Se escapó.", "warning")
        end
        d.stock = d.stock - 1
        if d.stock <= 0 then
            Jobs.notify(player, "Aquí ya no pican. Prueba en otro punto.", "info")
            pickSpot(player, s)
            return askCast(player, s, true)
        end
        askCast(player, s, false)
    end,
})
