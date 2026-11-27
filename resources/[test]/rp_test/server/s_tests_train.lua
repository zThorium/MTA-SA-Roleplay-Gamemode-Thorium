--[[
    rp_test / s_tests_train.lua
    Pruebas de humo de rp_train: tablas, vía cargada, trenes avanzando sin jugadores, boleto y carteles LED.
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

-- El recorrido completo empieza en Unity Station (Los Santos) y pasa por las 6 estaciones en orden de marcha
test("train_recorrido_desde_unity", function(t)
    local r = exports.rp_train:getTrainRoute()
    if type(r) ~= "table" or type(r.stations) ~= "table" then return t.fail("getTrainRoute no devolvió el recorrido") end
    if #r.stations ~= 6 then return t.fail("estaciones en el recorrido: " .. #r.stations) end
    if r.stations[1].name ~= "Unity Station" or r.stations[1].km ~= 0 then return t.fail("el recorrido no empieza en Unity Station") end
    for i = 2, #r.stations do
        if r.stations[i].km <= r.stations[i - 1].km then return t.fail("estaciones fuera de orden en " .. r.stations[i].name) end
    end
    t.pass(("%s > ... > %s (%.1f km)"):format(r.stations[1].name, r.stations[6].name, r.length / 1000))
end)

test("train_tabla_boleterias_y_carteles", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("train_fixtures accesible")
    end, "SELECT id, kind, station, x, y, z, rot, interior, dimension FROM train_fixtures LIMIT 1")
end)

test("train_boleto_en_catalogo", function(t)
    local def = exports.rp_inventory:getItemDefinition("train_ticket")
    if type(def) ~= "table" or not def.name then return t.fail("falta el item train_ticket en rp_inventory") end
    t.pass(def.name)
end)

-- Los carteles LED leen la llegada estimada del tren de pasajeros a cada una de las 6 estaciones
test("train_llegada_estimada", function(t)
    local eta = exports.rp_train:getTrainEta()
    if type(eta) ~= "table" then return t.fail("getTrainEta no devolvió una tabla") end
    local n = 0
    for node, e in pairs(eta) do
        n = n + 1
        if type(node) ~= "string" or not tonumber(e[1]) or e[1] < 0 or (e[2] ~= 0 and e[2] ~= 1) or type(e[3]) ~= "string" then
            return t.fail("entrada inválida para la estación " .. tostring(node))
        end
    end
    if n ~= 6 then return t.fail("estaciones con llegada estimada: " .. n) end
    t.pass("6 estaciones con llegada estimada")
end)
