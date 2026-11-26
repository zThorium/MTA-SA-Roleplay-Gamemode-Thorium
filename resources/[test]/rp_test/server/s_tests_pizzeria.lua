-- rp_pizzeria: pruebas de humo (recurso en marcha, integracion con rp_jobs y exports)

test("pizzeria_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_pizzeria")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_pizzeria no esta running") end
    t.pass()
end)

-- El pizzero esta registrado en rp_jobs como trabajo externo y la agencia lo ve
test("pizzeria_trabajo_en_rp_jobs", function(t)
    local info = exports.rp_jobs:getJobInfo("pizza")
    if not info then return t.fail("rp_jobs no tiene el trabajo 'pizza'") end
    if info.location.x == 0 then return t.fail("sin ubicacion para la agencia") end
    t.pass(info.name)
end)

-- Los exports de trabajos externos no pagan ni dan XP fuera de turno
test("pizzeria_exports_externos_sin_turno", function(t)
    if exports.rp_jobs:payExternalJob(root, 100, "prueba") ~= 0 then return t.fail("payExternalJob pago sin turno") end
    if exports.rp_jobs:giveExternalJobXP(root, 10) ~= false then return t.fail("giveExternalJobXP dio XP sin turno") end
    if exports.rp_pizzeria:isPlayerOnPizzaShift(root) ~= false then return t.fail("isPlayerOnPizzaShift(root) deberia ser false") end
    t.pass()
end)
