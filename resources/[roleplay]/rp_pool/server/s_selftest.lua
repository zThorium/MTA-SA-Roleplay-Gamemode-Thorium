--[[
    rp_pool / server / s_selftest.lua

    Autoprueba de la fisica y las reglas (sin jugadores ni BD). Se llama desde rp_test
    con exports.rp_pool:runSelfTest() y devuelve { passes, fails, failures = { ... }, info }.
    Tambien se puede lanzar a mano desde la consola del servidor con: poolselftest
]]

local function runAll()
    local report = { passes = 0, fails = 0, failures = {}, info = "" }
    local function check(name, cond, info)
        if cond then
            report.passes = report.passes + 1
        else
            report.fails = report.fails + 1
            report.failures[#report.failures + 1] = name .. " " .. tostring(info or "")
        end
    end

    local R = POOL.BALL_R
    local function emptyTable()
        local balls = PoolSim.newBalls()
        for b = 1, 15 do balls[b].p = true end
        return balls
    end

    math.randomseed(12345)

    -- 1. Triangulo
    local balls = PoolSim.newBalls()
    local minGap = 9
    for i = 0, 14 do
        for j = i + 1, 15 do
            local dx, dy = balls[i].u - balls[j].u, balls[i].v - balls[j].v
            local d = math.sqrt(dx * dx + dy * dy)
            if d < minGap then minGap = d end
        end
    end
    check("rack sin solapes", minGap >= 2 * R - 1e-6, minGap)
    local row3u = 0.48 + 2 * (2 * R * 0.8660254 + 0.0006)
    check("la 8 en el centro de la 3a fila", math.abs(balls[8].v) < 1e-6 and math.abs(balls[8].u - row3u) < 1e-6)

    -- 2. Rozamiento: recorrido = v^2 / (2 a)
    local bs = emptyTable()
    bs[0].u, bs[0].v = -0.48, 0
    local res = PoolSim.run(bs, 0, 1.2)
    local travelled = bs[0].u + 0.48
    local expected = 1.2 ^ 2 / (2 * POOL.DECEL)
    check("rozamiento (recorrido)", math.abs(travelled - expected) / expected < 0.04, ("%.3f vs %.3f"):format(travelled, expected))
    check("sin choque: firstHit nil", res.firstHit == nil)

    -- 3. Tronera de esquina
    bs = emptyTable()
    bs[0].u, bs[0].v = 0.75, 0.33
    res = PoolSim.run(bs, math.atan2(0.525 - 0.33, 0.96 - 0.75), 1.5)
    check("tronera de esquina", bs[0].p and res.cuePocketed and res.pocketed[1] == 0)
    local pk
    for _, e in ipairs(res.events) do if e[2] == 3 then pk = e end end
    check("evento de tronera", pk ~= nil and pk[5] == 0)

    -- 4. Tronera lateral
    bs = emptyTable()
    bs[0].u, bs[0].v = 0.0, 0.2
    res = PoolSim.run(bs, math.pi / 2, 1.5)
    check("tronera lateral", bs[0].p)

    -- 5. Rebote en banda
    bs = emptyTable()
    bs[0].u, bs[0].v = 0.5, 0
    res = PoolSim.run(bs, 0, 3)
    local cush = 0
    for _, e in ipairs(res.events) do if e[2] == 2 then cush = cush + 1 end end
    check("rebote en banda", cush >= 1 and not bs[0].p and bs[0].u < 0.9, ("cush=%d u=%.3f"):format(cush, bs[0].u))

    -- 6. Choque frontal
    bs = emptyTable()
    bs[0].u, bs[0].v = -0.3, 0
    bs[1].p, bs[1].u, bs[1].v = false, 0.0, 0
    res = PoolSim.run(bs, 0, 1.0)
    check("primera bola tocada", res.firstHit == 1)
    check("transferencia de momento", bs[1].u > 0.15 and math.abs(bs[0].u + 0.3) < 0.35, ("b1.u=%.3f cue.u=%.3f"):format(bs[1].u, bs[0].u))

    -- 7. Colocacion de la blanca
    bs = PoolSim.newBalls()
    check("canPlace libre", PoolSim.canPlace(bs, -0.5, 0.3))
    check("canPlace sobre bola", not PoolSim.canPlace(bs, 0.48, 0))
    check("canPlace fuera", not PoolSim.canPlace(bs, 2, 0))
    check("canPlace boca de tronera", not PoolSim.canPlace(bs, 0.9, 0.5))
    check("canPlace NaN", not PoolSim.canPlace(bs, 0 / 0, 0))

    -- 8. Tiros aleatorios desde el saque: invariantes y coste
    local maxFrames, totalMs, shots, maxTrack, pocketedTotal = 0, 0, 120, 0, 0
    local nan, outside = false, false
    for _ = 1, shots do
        local b = PoolSim.newBalls()
        local t0 = getTickCount()
        local r = PoolSim.run(b, math.random() * 2 * math.pi, POOL.MIN_SPEED + math.random() * (POOL.MAX_SPEED - POOL.MIN_SPEED))
        totalMs = totalMs + (getTickCount() - t0)
        maxFrames = math.max(maxFrames, r.frames)
        local n = 0
        for _, t in ipairs(r.tracks) do n = n + #t end
        maxTrack = math.max(maxTrack, n)
        pocketedTotal = pocketedTotal + #r.pocketed
        for i = 0, 15 do
            local ball = b[i]
            if ball.u ~= ball.u or ball.v ~= ball.v then nan = true end
            if not ball.p and (math.abs(ball.u) > PoolSim.BX + 1e-3 or math.abs(ball.v) > PoolSim.BY + 1e-3) then outside = true end
        end
    end
    check("sin NaN", not nan)
    check("ninguna bola fuera de la mesa", not outside)
    check("duracion maxima < 30 s", maxFrames / 60 < 30, maxFrames / 60)
    report.info = ("%d tiros: %.1f ms/tiro, maximo %.1f s, replay maximo %d numeros"):format(shots, totalMs / shots, maxFrames / 60, maxTrack)

    -- 9. Reglas de 8-ball
    local ev = PoolRules.evaluate
    local function r(t) t.pocketed = t.pocketed or {}; return t end
    local o
    o = ev({ group = nil, breakShot = true, left = { solid = 7, stripe = 7 }, res = r({ firstHit = 3, railAfter = true, pocketed = { 5 } }) })
    check("saque embocando: sigue y mesa abierta", not o.foul and o.continue and o.assign == nil)
    o = ev({ group = nil, breakShot = false, left = { solid = 7, stripe = 7 }, res = r({ firstHit = 3, railAfter = true, pocketed = { 11 } }) })
    check("mesa abierta: la primera embocada reparte", o.assign == "stripe" and o.continue)
    o = ev({ group = "solid", breakShot = false, left = { solid = 5, stripe = 7 }, res = r({ firstHit = 10, railAfter = true, pocketed = {} }) })
    check("falta: bola equivocada", o.foul)
    o = ev({ group = "solid", breakShot = false, left = { solid = 5, stripe = 7 }, res = r({ firstHit = 2, railAfter = true, pocketed = { 12 } }) })
    check("embocar ajena sin falta: pasa el turno", not o.foul and not o.continue)
    o = ev({ group = "solid", breakShot = false, left = { solid = 5, stripe = 7 }, res = r({ firstHit = 2, railAfter = true, pocketed = { 0, 2 } }) })
    check("blanca embocada: falta", o.foul and not o.continue)
    o = ev({ group = "solid", breakShot = false, left = { solid = 5, stripe = 7 }, res = r({ firstHit = nil, railAfter = false, pocketed = {} }) })
    check("sin contacto: falta", o.foul)
    o = ev({ group = "solid", breakShot = false, left = { solid = 5, stripe = 7 }, res = r({ firstHit = 2, railAfter = false, pocketed = {} }) })
    check("sin banda: falta", o.foul)
    o = ev({ group = "solid", breakShot = false, left = { solid = 0, stripe = 7 }, res = r({ firstHit = 8, railAfter = true, pocketed = { 8 } }) })
    check("8 legal: gana", o.eight == "win")
    o = ev({ group = "solid", breakShot = false, left = { solid = 2, stripe = 7 }, res = r({ firstHit = 3, railAfter = true, pocketed = { 8 } }) })
    check("8 antes de tiempo: pierde", o.eight == "loss")
    o = ev({ group = "solid", breakShot = false, left = { solid = 0, stripe = 7 }, res = r({ firstHit = 8, railAfter = true, pocketed = { 0, 8 } }) })
    check("8 con blanca: pierde", o.eight == "loss")
    o = ev({ group = nil, breakShot = true, left = { solid = 7, stripe = 7 }, res = r({ firstHit = 1, railAfter = true, pocketed = { 8 } }) })
    check("8 en el saque: se arma de nuevo", o.eight == "rerack")
    o = ev({ group = "stripe", breakShot = false, left = { solid = 7, stripe = 0 }, res = r({ firstHit = 8, railAfter = true, pocketed = {} }) })
    check("tocar la 8 cuando es la ultima: sin falta", not o.foul)

    return report
end

function runSelfTest()
    local ok, report = pcall(runAll)
    math.randomseed(getTickCount())   -- la autoprueba fija la semilla: se restaura el azar
    if not ok then return { passes = 0, fails = 1, failures = { tostring(report) }, info = "" } end
    return report
end

addCommandHandler("poolselftest", function(player)
    if player then return end   -- solo desde la consola del servidor
    local r = runSelfTest()
    outputServerLog(("[rp_pool] autoprueba: %d bien, %d fallos %s | %s"):format(r.passes, r.fails, table.concat(r.failures, "; "), r.info))
end)
