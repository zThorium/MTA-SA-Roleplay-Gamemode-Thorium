--[[
    rp_test / s_tests_robbery.lua

    Robo de tiendas (rp_robbery) y su integracion con rp_wanted. Sin jugadores
    no se puede recorrer el robo entero (apuntar, caja, cinematica, CEF): se
    prueban la carga de tiendas desde la BD, la regla de estrellas y la logica
    de la negociacion con tiradas fijas (simulateNegotiation), y que los exports
    nuevos de rp_wanted rechazan lo que no es un jugador.
]]

local function robbery() return exports.rp_robbery end

test("robo_tiendas_cargadas_desde_bd", function(t)
    local tries = 0
    local function check()
        local n = robbery():getStoreCount() or 0
        if n == 0 then
            tries = tries + 1
            if tries > 20 then return t.fail("rp_robbery no cargo ninguna tienda (ni la inicial)") end
            return setTimer(check, 500, 1)
        end
        query(function(rows, _, _, code, msg)
            if not rows then return t.fail(("robbery_stores: [%s] %s"):format(tostring(code), tostring(msg))) end
            local db = tonumber(rows[1].n)
            if db ~= n then return t.fail(("%d tiendas en memoria y %d en la tabla"):format(n, db)) end
            t.pass(n .. " tienda(s) robable(s) en el mundo")
        end, "SELECT COUNT(*) AS n FROM robbery_stores")
    end
    check()
end)

test("robo_estrellas_segun_victimas", function(t)
    local r = robbery()
    local a, b, c, d = r:robberyStarsFor(false, 0), r:robberyStarsFor(false, 2), r:robberyStarsFor(true, 0), r:robberyStarsFor(true, 3)
    if a ~= 3 or b ~= 4 or c ~= 5 or d ~= 5 then
        return t.fail(("sin muertos=%s, rehen=%s, cajero=%s, ambos=%s (esperado 3, 4, 5, 5)"):format(tostring(a), tostring(b), tostring(c), tostring(d)))
    end
    t.pass("3 / 4 si muere un rehen / 5 si muere el cajero")
end)

test("robo_negociacion_canjear_rehenes", function(t)
    local deal = robbery():simulateNegotiation(3, { "seconds", "traps", "tires", "seconds", "deal" })
    if deal.chips ~= 0 or deal.released ~= 3 then return t.fail("rehenes: quedan " .. tostring(deal.chips)) end
    if deal.seconds ~= 15 then return t.fail("ventaja " .. tostring(deal.seconds) .. " s, se esperaban 15 (5 + 10)") end
    if not deal.noTraps or not deal.noTires then return t.fail("faltan condiciones negociadas") end
    if deal.effects[4] ~= "invalid" then return t.fail("se pudo canjear un 4o rehen sin tenerlo: " .. tostring(deal.effects[4])) end
    if deal.result ~= "deal" or not deal.done then return t.fail("no termino en trato: " .. tostring(deal.result)) end
    t.pass("3 rehenes -> 15 s, sin trampas y sin llantas; el 4o canje se rechaza")
end)

test("robo_negociacion_farol", function(t)
    local ok = robbery():simulateNegotiation(0, { "bluff", "deal" }, { 0.1 })
    if ok.effects[1] ~= "bluff_ok_traps" or not ok.noTraps then return t.fail("farol exitoso: " .. tostring(ok.effects[1])) end
    local bad = robbery():simulateNegotiation(2, { "traps", "bluff", "bluff", "bluff", "deal" }, { 0.99, 0.9, 0.9, 0.9 })
    if bad.result ~= "broken" or bad.seconds ~= 0 or bad.noTraps then
        return t.fail(("3 faroles fallidos: resultado %s, %s s, sinTrampas=%s"):format(tostring(bad.result), tostring(bad.seconds), tostring(bad.noTraps)))
    end
    if bad.effects[4] ~= "bluff_broken" or bad.effects[5] ~= "invalid" then
        return t.fail("efectos " .. table.concat(bad.effects, ","))
    end
    t.pass("farol con suerte da 'sin trampas'; 3 fallidos rompen el trato y anulan lo pactado")
end)

test("robo_negociacion_rondas_y_rendicion", function(t)
    local long = robbery():simulateNegotiation(10, { "seconds", "seconds", "seconds", "seconds", "seconds", "seconds", "seconds" })
    if not long.done or long.result ~= "deal" then return t.fail("no se cerro al pasar las rondas maximas") end
    if long.effects[7] ~= "invalid" then return t.fail("se pudo seguir negociando tras el cierre") end
    local give = robbery():simulateNegotiation(1, { "surrender" })
    if give.result ~= "surrender" then return t.fail("rendirse: " .. tostring(give.result)) end
    t.pass(("cierre automatico en la ronda %d con %d s; rendicion"):format(long.round, long.seconds))
end)

test("busqueda_exports_de_persecucion_retenida", function(t)
    local w = exports.rp_wanted
    if w:holdPursuit(root, true) ~= false then return t.fail("holdPursuit acepto algo que no es un jugador") end
    if w:setPursuitTerms(root, true, true) ~= false then return t.fail("setPursuitTerms acepto algo que no es un jugador") end
    if w:isPursuitHeld(root) ~= false then return t.fail("isPursuitHeld no devolvio false") end
    local traps, tires = w:getPursuitTerms(root)
    if traps ~= false or tires ~= false then return t.fail("getPursuitTerms sin datos no devolvio false, false") end
    if w:setWantedLevel(root, 5, true) ~= false then return t.fail("setWantedLevel forzado acepto algo que no es un jugador") end
    t.pass("holdPursuit, setPursuitTerms, isPursuitHeld, getPursuitTerms y setWantedLevel(force) validan el jugador")
end)
