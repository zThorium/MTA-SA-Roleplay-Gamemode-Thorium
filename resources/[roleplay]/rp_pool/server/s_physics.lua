--[[
    rp_pool / server / s_physics.lua

    Simulacion de un tiro completo, solo en el servidor (autoritativa). Devuelve el
    "replay" que los clientes reproducen: trayectorias por bola a 60 fps, eventos de
    sonido y el resultado (bolas embocadas en orden, primera bola tocada, etc.).

    Bolas: tabla indexada 0..15 con { u, v, p (embocada), vx, vy } en coordenadas de mesa.
    Las troneras no son circulos: la banda se interrumpe en las bocas y cualquier bola
    que cruza la linea de banda dentro de una boca cae (determinista y robusto).
]]

PoolSim = {}

local R = POOL.BALL_R
local BX = POOL.HALF_L - R      -- limite del centro de la bola contra la banda larga
local BY = POOL.HALF_W - R      -- limite contra la banda corta
local MC = POOL.MOUTH_CORNER
local MS = POOL.MOUTH_SIDE
local sqrt, abs, floor = math.sqrt, math.abs, math.floor

PoolSim.BX, PoolSim.BY = BX, BY

----------------------------------------------------------------
-- Colocacion inicial (triangulo de 8-ball)
----------------------------------------------------------------
function PoolSim.newBalls()
    local balls = {}
    for b = 0, 15 do balls[b] = { u = 0, v = 0, p = false, vx = 0, vy = 0 } end
    PoolSim.rack(balls)
    return balls
end

function PoolSim.rack(balls)
    local footU = 0.48
    local rowStep = 2 * R * 0.8660254 + 0.0006
    local colStep = 2 * R + 0.0008

    -- Huecos del triangulo: fila 1..5 con k bolas
    local slots = {}
    for row = 1, 5 do
        for j = 0, row - 1 do
            slots[#slots + 1] = { u = footU + (row - 1) * rowStep, v = (j - (row - 1) / 2) * colStep, row = row, j = j }
        end
    end

    -- La 8 va en el centro de la fila 3; una lisa y una rayada en las esquinas de la ultima fila
    local solids, stripes = {}, {}
    for b = 1, 7 do solids[#solids + 1] = b end
    for b = 9, 15 do stripes[#stripes + 1] = b end
    local function pick(list) return table.remove(list, math.random(#list)) end

    local assign = {}
    for i, s in ipairs(slots) do
        if s.row == 3 and s.j == 1 then assign[i] = 8 end
    end
    local cornerA, cornerB = {}, {}
    for i, s in ipairs(slots) do
        if s.row == 5 and s.j == 0 then cornerA = i end
        if s.row == 5 and s.j == 4 then cornerB = i end
    end
    if math.random(2) == 1 then
        assign[cornerA], assign[cornerB] = pick(solids), pick(stripes)
    else
        assign[cornerA], assign[cornerB] = pick(stripes), pick(solids)
    end
    local rest = {}
    for _, b in ipairs(solids) do rest[#rest + 1] = b end
    for _, b in ipairs(stripes) do rest[#rest + 1] = b end
    for i = 1, #slots do
        if not assign[i] then assign[i] = table.remove(rest, math.random(#rest)) end
    end

    for i, s in ipairs(slots) do
        local ball = balls[assign[i]]
        ball.u, ball.v, ball.p, ball.vx, ball.vy = s.u, s.v, false, 0, 0
    end
    local cue = balls[0]
    cue.u, cue.v, cue.p, cue.vx, cue.vy = -0.48, 0, false, 0, 0
end

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
-- Posicion (u, v) de cada tronera (0..5) para sonidos y efectos
function PoolSim.pocketPos(idx)
    local x = (idx == 5 or idx == 6) and 0 or (((idx - 1) >= 2) and POOL.HALF_L or -POOL.HALF_L)
    local y
    if idx == 5 then y = -POOL.HALF_W elseif idx == 6 then y = POOL.HALF_W
    else y = (((idx - 1) % 2) == 1) and POOL.HALF_W or -POOL.HALF_W end
    return x, y
end

-- Es valida la posicion (u, v) para colocar la blanca? (dentro de las bandas, sin tocar otras bolas)
function PoolSim.canPlace(balls, u, v)
    if type(u) ~= "number" or type(v) ~= "number" then return false end
    if u ~= u or v ~= v then return false end
    if abs(u) > BX - 0.012 or abs(v) > BY - 0.012 then return false end
    -- fuera de las bocas de las troneras
    if abs(u) > BX - MC - 0.02 and abs(v) > BY - MC - 0.02 then return false end
    if abs(v) > BY - 0.03 and abs(u) < MS + 0.03 then return false end
    for b = 1, 15 do
        local ball = balls[b]
        if not ball.p then
            local dx, dy = ball.u - u, ball.v - v
            if dx * dx + dy * dy < (2 * R + 0.003) ^ 2 then return false end
        end
    end
    return true
end

----------------------------------------------------------------
-- Simulacion de un tiro
-- angle: radianes en el marco de la mesa. speed: m/s.
-- Modifica `balls` (posiciones finales, embocadas) y devuelve el resultado.
----------------------------------------------------------------
function PoolSim.run(balls, angle, speed)
    local dt = POOL.SIM_DT
    local per = POOL.STEPS_PER_FRAME
    local maxSteps = floor(POOL.MAX_SIM_TIME / dt)
    local decel, stopSpeed = POOL.DECEL, POOL.STOP_SPEED
    local cushionE, cushionT, ballE = POOL.CUSHION_E, POOL.CUSHION_T, POOL.BALL_E
    local diam2 = (2 * R) ^ 2

    balls[0].vx, balls[0].vy = math.cos(angle) * speed, math.sin(angle) * speed

    -- Registro de claves por bola (lista plana f,u,v) con "hold" para no interpolar reposos
    local rec = {}
    for b = 0, 15 do
        rec[b] = { list = {}, lf = 0, lu = balls[b].u, lv = balls[b].v }
    end
    local events = {}
    local pocketed = {}
    local firstHit, railAfter = nil, false
    local shotRails = 0

    local function mm(x) return floor(x * 1000 + 0.5) end

    local function snapshot(f)
        for b = 0, 15 do
            local ball = balls[b]
            local k = rec[b]
            if (not ball.p) or ball.justPocketed then
                if abs(ball.u - k.lu) + abs(ball.v - k.lv) > 1e-6 then
                    local l = k.list
                    if k.lf < f - 1 then
                        l[#l + 1] = f - 1; l[#l + 1] = mm(k.lu); l[#l + 1] = mm(k.lv)
                    end
                    l[#l + 1] = f; l[#l + 1] = mm(ball.u); l[#l + 1] = mm(ball.v)
                    k.lf, k.lu, k.lv = f, ball.u, ball.v
                end
            end
            ball.justPocketed = nil
        end
    end

    local function pocket(b, ball, idx, f)
        ball.p = true
        ball.justPocketed = true
        ball.vx, ball.vy = 0, 0
        pocketed[#pocketed + 1] = b
        if firstHit then railAfter = true end
        local px, py = PoolSim.pocketPos(idx)
        events[#events + 1] = { f, 3, mm(px), mm(py), b }
    end

    local frame = 0
    local step = 0
    while step < maxSteps do
        step = step + 1
        frame = step / per
        local moving = false

        -- Integracion + rozamiento
        for b = 0, 15 do
            local ball = balls[b]
            if not ball.p then
                local vx, vy = ball.vx, ball.vy
                if vx ~= 0 or vy ~= 0 then
                    local sp = sqrt(vx * vx + vy * vy)
                    local ns = sp - decel * dt
                    if ns < stopSpeed then
                        ball.vx, ball.vy = 0, 0
                    else
                        local k = ns / sp
                        vx, vy = vx * k, vy * k
                        ball.vx, ball.vy = vx, vy
                        ball.u = ball.u + vx * dt
                        ball.v = ball.v + vy * dt
                        moving = true
                    end
                end
            end
        end

        if not moving then break end

        -- Choques bola-bola
        for i = 0, 14 do
            local a = balls[i]
            if not a.p then
                for j = i + 1, 15 do
                    local c = balls[j]
                    if not c.p and (a.vx ~= 0 or a.vy ~= 0 or c.vx ~= 0 or c.vy ~= 0) then
                        local dx, dy = c.u - a.u, c.v - a.v
                        local d2 = dx * dx + dy * dy
                        if d2 < diam2 and d2 > 1e-12 then
                            local d = sqrt(d2)
                            local nx, ny = dx / d, dy / d
                            local ov = (2 * R - d) * 0.5
                            a.u, a.v = a.u - nx * ov, a.v - ny * ov
                            c.u, c.v = c.u + nx * ov, c.v + ny * ov
                            local vn = (a.vx - c.vx) * nx + (a.vy - c.vy) * ny
                            if vn > 0 then
                                local imp = (1 + ballE) * 0.5 * vn
                                a.vx, a.vy = a.vx - imp * nx, a.vy - imp * ny
                                c.vx, c.vy = c.vx + imp * nx, c.vy + imp * ny
                                if i == 0 and not firstHit then firstHit = j end
                                events[#events + 1] = { frame, 1, mm((a.u + c.u) / 2), mm((a.v + c.v) / 2), floor(vn * 100) }
                            end
                        end
                    end
                end
            end
        end

        -- Bandas y troneras
        for b = 0, 15 do
            local ball = balls[b]
            if not ball.p then
                local u, v = ball.u, ball.v
                local au, av = abs(u), abs(v)
                if (au > BX and av > BY - MC) or (av > BY and au > BX - MC) then
                    local idx = ((u > 0) and 2 or 0) + ((v > 0) and 1 or 0) + 1
                    pocket(b, ball, idx, frame)
                elseif av > BY and au < MS then
                    pocket(b, ball, v > 0 and 6 or 5, frame)
                else
                    local hit = 0
                    if au > BX then
                        local vn = abs(ball.vx)
                        ball.u = u > 0 and BX or -BX
                        if (u > 0 and ball.vx > 0) or (u < 0 and ball.vx < 0) then
                            ball.vx = -ball.vx * cushionE
                            ball.vy = ball.vy * cushionT
                            hit = vn
                        end
                    end
                    if av > BY then
                        local vn = abs(ball.vy)
                        ball.v = v > 0 and BY or -BY
                        if (v > 0 and ball.vy > 0) or (v < 0 and ball.vy < 0) then
                            ball.vy = -ball.vy * cushionE
                            ball.vx = ball.vx * cushionT
                            hit = math.max(hit, vn)
                        end
                    end
                    if hit > 0 then
                        shotRails = shotRails + 1
                        if firstHit then railAfter = true end
                        events[#events + 1] = { frame, 2, mm(ball.u), mm(ball.v), floor(hit * 100) }
                    end
                end
            end
        end

        if step % per == 0 then snapshot(step / per) end
    end

    -- Todo en reposo: fotograma final y limpieza de velocidades
    local lastFrame = floor(step / per) + 1
    for b = 0, 15 do balls[b].vx, balls[b].vy = 0, 0 end
    snapshot(lastFrame)

    local tracks = {}
    for b = 0, 15 do
        local l = rec[b].list
        if #l > 0 then
            local t = { b }
            for i = 1, #l do t[#t + 1] = l[i] end
            tracks[#tracks + 1] = t
        end
    end

    -- Eventos con el fotograma redondeado a 0.1 para ahorrar bytes
    for _, e in ipairs(events) do e[1] = floor(e[1] * 10 + 0.5) / 10 end

    return {
        tracks = tracks,
        events = events,
        frames = lastFrame,
        pocketed = pocketed,
        firstHit = firstHit,
        railAfter = railAfter,
        cuePocketed = balls[0].p,
    }
end
