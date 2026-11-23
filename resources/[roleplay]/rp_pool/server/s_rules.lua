--[[
    rp_pool / server / s_rules.lua

    Reglas de 8-ball como funcion pura (sin jugadores ni timers), para poder probarlas.

    PoolRules.evaluate(ctx) recibe:
        group       grupo del tirador ("solid" | "stripe" | nil si la mesa esta abierta)
        breakShot   true si es el saque
        left        { solid = n, stripe = n } bolas que le quedaban a cada grupo ANTES del tiro
        res         resultado de PoolSim.run: pocketed (orden), firstHit, railAfter, cuePocketed

    y devuelve una tabla con:
        foul, reason      falta y motivo (texto para el jugador)
        eight             nil | "win" | "loss" | "rerack"   (la 8 cayo en este tiro)
        assign            grupo que se le reparte al tirador (primera embocada legal), o nil
        continue          true si sigue tirando el mismo jugador
        objs              bolas objeto embocadas (sin la blanca), en orden
]]

PoolRules = {}

function PoolRules.evaluate(ctx)
    local res = ctx.res
    local g = ctx.group
    local out = { foul = false, objs = {} }

    local cueIn = res.cuePocketed
    for _, b in ipairs(res.pocketed) do
        if b ~= 0 then out.objs[#out.objs + 1] = b else cueIn = true end
    end

    -- Faltas
    if cueIn then
        out.foul, out.reason = true, "La blanca cayó en una tronera"
    elseif not res.firstHit then
        out.foul, out.reason = true, "La blanca no tocó ninguna bola"
    else
        local fg = poolGroupOf(res.firstHit)
        if g then
            local needed = (ctx.left[g] == 0) and "eight" or g
            if fg ~= needed then
                out.foul = true
                out.reason = (needed == "eight") and "Debías tocar primero la 8" or "Tocaste primero una bola que no es tuya"
            end
        elseif fg == "eight" then
            out.foul, out.reason = true, "Tocaste la 8 primero con la mesa abierta"
        end
    end
    if not out.foul and not ctx.breakShot and not res.railAfter and #out.objs == 0 then
        out.foul, out.reason = true, "Ninguna bola tocó banda"
    end

    -- La 8
    local eightIn = false
    for _, b in ipairs(out.objs) do if b == 8 then eightIn = true end end
    if eightIn then
        if ctx.breakShot then
            out.eight = "rerack"
        elseif (not out.foul) and g ~= nil and ctx.left[g] == 0 then
            out.eight = "win"
        else
            out.eight = "loss"
        end
        return out
    end

    -- Reparto de grupos: primera embocada legal tras el saque
    local assigned = g
    if not g and not out.foul and not ctx.breakShot then
        for _, b in ipairs(out.objs) do
            local grp = poolGroupOf(b)
            if grp == "solid" or grp == "stripe" then
                out.assign = grp
                assigned = grp
                break
            end
        end
    end

    -- Sigue tirando si no hubo falta y embocó una bola suya (o cualquiera si la mesa seguia abierta)
    out.continue = false
    if not out.foul then
        for _, b in ipairs(out.objs) do
            if assigned then
                if poolGroupOf(b) == assigned then out.continue = true end
            elseif b ~= 8 then
                out.continue = true
            end
        end
    end
    return out
end
