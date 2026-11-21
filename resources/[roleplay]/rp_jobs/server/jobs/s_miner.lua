--[[
    rp_jobs / jobs/s_miner.lua  -  Minero

    En cada turno hay MINER.VEINS_PER_SHIFT vetas repartidas por la cantera (rocas que solo
    ve el minero). En cada una:
      - Se pica en el mundo con la pala/pico (pulsar E varias veces).
      - Las vetas ricas (plata, oro o MINER.RICH_CHANCE de las demás) abren el minijuego "vein":
        golpear las grietas que brillan; los golpes en roca sana cansan. Desde nivel 2 se puede
        poner dinamita (más mineral y más gemas, pero el doble de riesgo de derrumbe).
      - Posible derrumbe: minijuego "cavein" (pulsar las teclas que salen a tiempo) o daño.
    El mineral va al inventario y se vende en la fundición. Al acabar las vetas salen otras.
]]

local M = MINER

local function newVeins(player, s)
    local veins = Jobs.shuffle(M.VEINS)
    local level = Jobs.level(player, "miner")
    s.data = { veins = {}, idx = 0 }
    local props = {}
    for i = 1, M.VEINS_PER_SHIFT do
        local v = veins[i]
        local ore = Jobs.pickWeighted(M.ORES, level)
        s.data.veins[i] = { pos = v, ore = ore }
        props[i] = { key = "rock" .. i, model = M.ROCK_MODELS[math.random(#M.ROCK_MODELS)], x = v[1], y = v[2], z = v[3],
            rz = math.random(0, 359), snap = true, snapHeight = 30 }
    end
    Jobs.props(player, props)
end

local function nextVein(player, s)
    local d = s.data
    d.idx = d.idx + 1
    if d.idx > #d.veins then
        Jobs.notify(player, "Agotaste estas vetas. Hay otras nuevas marcadas. Vende el mineral en la fundición.", "info", 6000)
        newVeins(player, s)
        return nextVein(player, s)
    end
    local v = d.veins[d.idx].pos
    Jobs.hud(player, "Ve a la veta marcada", ("Veta %d/%d"):format(d.idx, #d.veins))
    Jobs.waypoint(player, { kind = "vein", x = v[1], y = v[2], z = v[3], r = 3.5, mode = "foot", act = "press", flat = true,
        text = "Pulsa E para picar la veta", label = ("Veta %d"):format(d.idx), marker = "cylinder" })
end

local ORE_COLORS = { ore_coal = "#3a3a3a", ore_iron = "#b5651d", ore_copper = "#d9822b", ore_silver = "#d8dde6", ore_gold = "#f5c542" }

local function giveOre(player, s)
    local d = s.data
    local vein = d.veins[d.idx]
    local res = d.result
    local y = vein.ore.yield
    local amount = math.floor(y[1] + (y[2] - y[1]) * res.score + 0.5) + (res.dynamiteGood and 1 or 0)
    local got = {}
    local given = Jobs.give(player, vein.ore.item, math.max(1, amount))
    if given > 0 then got[#got + 1] = ("%dx %s"):format(given, Jobs.itemName(vein.ore.item):lower()) end
    local gemChance = M.GEM_CHANCE * (res.dynamiteGood and 2 or 1) * (0.5 + res.score)
    if math.random() < gemChance and Jobs.give(player, "gem_raw", 1) > 0 then
        got[#got + 1] = "¡una gema en bruto!"
    end
    if #got > 0 then Jobs.notify(player, "Sacaste " .. table.concat(got, " y ") .. ".", "success", 6000) end
    Jobs.xp(player, 8 + math.floor(res.score * 8))
    Jobs.propFx(player, "rock" .. d.idx, "remove")
    nextVein(player, s)
end

Jobs.register("miner", {
    perks = {
        "Desde nivel 2 puedes usar dinamita; con nivel 2 y 3 aparecen plata y oro.",
        "Hay derrumbes: si ves teclas en pantalla, ¡púlsalas rápido!",
    },

    start = function(player, s)
        Jobs.notify(player, "Las vetas están marcadas en la cantera. Ponte el casco.", "info")
        newVeins(player, s)
        nextVein(player, s)
    end,

    onReach = function(player, s, wp)
        local d = s.data
        local vein = d.veins[d.idx]
        Jobs.hold(player, 337, { 0, 0, 0, 0, 0, 0 })
        Jobs.anim(player, "BASEBALL", "Bat_4", true)
        local rich = vein.ore.item == "ore_silver" or vein.ore.item == "ore_gold" or math.random() < M.RICH_CHANCE
        if not rich then
            return Jobs.action(player, "_tap", { text = "Picando la veta", taps = 10 }, "dig")
        end
        Jobs.notify(player, "¡Veta rica! Busca las grietas.", "info")
        Jobs.game(player, "vein", {
            ore = vein.ore.item, color = ORE_COLORS[vein.ore.item] or "#999",
            cracks = 8 + math.random(0, 4), dynamite = Jobs.level(player, "miner") >= 2, time = 22,
        }, 5000)
    end,

    onGame = function(player, s, name, r, ctx)
        local d = s.data
        Jobs.anim(player, false)
        if name == "_tap" and ctx == "dig" then
            -- Picado normal: mismo resultado que una veta mediocre del minijuego
            name = "vein"
            r = (r.cancel or r.fail) and r or { hits = 6, total = 10, misses = 0 }
        end
        if name == "vein" then
            Jobs.hold(player, false)
            if r.cancel then
                local v = d.veins[d.idx].pos
                return Jobs.waypoint(player, { kind = "vein", x = v[1], y = v[2], z = v[3], r = 3.5, mode = "foot", act = "press",
                    flat = true, text = "Pulsa E para picar la veta", label = ("Veta %d"):format(d.idx), marker = "cylinder" })
            end
            local hits = math.max(0, math.min(tonumber(r.hits) or 0, 20))
            local misses = math.max(0, math.min(tonumber(r.misses) or 0, 60))
            local total = math.max(1, tonumber(r.total) or hits)
            local score = r.fail and 0 or math.max(0, math.min(1, hits / math.max(total, 1) - misses * 0.03))
            local dynamite = r.dynamite and Jobs.level(player, "miner") >= 2
            d.result = { score = score, dynamiteGood = dynamite and r.dynamiteGood and true or false }
            Jobs.sound(player, dynamite and "blast" or "rock")
            if math.random() < M.CAVEIN_CHANCE * (dynamite and 2 or 1) then
                Jobs.notify(player, "¡DERRUMBE!", "error")
                local keys, pool = {}, { "W", "A", "S", "D", "Q", "E" }
                for i = 1, 5 + math.random(0, 2) do keys[i] = pool[math.random(#pool)] end
                return Jobs.game(player, "cavein", { keys = keys, time = 4200 }, 800)
            end
            return giveOre(player, s)

        elseif name == "cavein" then
            if not r.ok or r.fail or r.cancel then
                setElementHealth(player, math.max(5, getElementHealth(player) - M.CAVEIN_DAMAGE))
                Jobs.notify(player, "Te cayeron piedras encima. Pierdes parte del mineral.", "error")
                d.result.score = d.result.score * 0.5
            else
                Jobs.notify(player, "¡Saliste a tiempo!", "success")
                Jobs.xp(player, 5)
            end
            giveOre(player, s)
        end
    end,
})
