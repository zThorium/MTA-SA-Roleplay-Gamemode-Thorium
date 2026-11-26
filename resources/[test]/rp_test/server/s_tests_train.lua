--[[
    rp_test / s_tests_train.lua
    Pruebas de humo de rp_train: tabla de barreras, vía cargada y trenes avanzando sin jugadores.
]]

test("train_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_train")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_train no está running") end
    t.pass()
end)

test("train_tabla_existe", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("rail_crossings accesible")
    end, "SELECT COUNT(*) AS n FROM rail_crossings")
end)

test("train_via_y_trenes", function(t)
    local len = exports.rp_train:getTrackLength()
    if not len or len < 18000 or len > 18300 then return t.fail("largo de vía inesperado: " .. tostring(len)) end
    local state = exports.rp_train:getTrainState()
    if type(state) ~= "table" or #state < 1 then return t.fail("no hay trenes") end
    t.pass(("%d trenes, vía de %.0f m"):format(#state, len))
end)

-- Sin jugadores nadie sincroniza: el servidor debe avanzar los trenes por su cuenta
test("train_avanza_sin_jugadores", function(t)
    local before = exports.rp_train:getTrainState()
    setTimer(function()
        local after = exports.rp_train:getTrainState()
        for i, s in ipairs(after) do
            if s.d ~= before[i].d or s.stopped then return t.pass(("tren %d: %.1f -> %.1f m"):format(i, before[i].d, s.d)) end
        end
        t.fail("ningún tren se movió en 3 s")
    end, 3000, 1)
end)
