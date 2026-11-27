--[[
    rp_test / s_tests_wanted.lua

    IA policial de rp_wanted. La persecucion y el combate corren en el cliente
    del buscado (no se pueden probar sin jugador): aqui se prueba lo del servidor
    que los sostiene. Que el arma de cada policia sube con las estrellas (antes,
    de 2 a 4 estrellas seguian con pistola) y que la config de busqueda y combate
    es coherente.
]]

test("busqueda_armas_suben_con_las_estrellas", function(t)
    local w = exports.rp_wanted
    local checks = {
        { "police", 1, 0, 3,  "1 estrella: porra" },
        { "police", 2, 0, 22, "2 estrellas: pistola" },
        { "police", 2, 1, 29, "2 estrellas, acompanante: MP5 por la ventanilla" },
        { "police", 3, 0, 25, "3 estrellas: escopeta" },
        { "police", 4, 0, 29, "4 estrellas: MP5" },
        { "police", 5, 0, 31, "5 estrellas: M4" },
        { "swat",   4, 0, 29, "SWAT a 4 estrellas: MP5" },
        { "fbi",    5, 0, 31, "FBI a 5 estrellas: M4" },
    }
    for _, c in ipairs(checks) do
        local got = w:getCopWeapon(c[1], c[2], c[3])
        if got ~= c[4] then
            return t.fail(("%s -> arma %s, se esperaba %d"):format(c[5], tostring(got), c[4]))
        end
    end
    if w:getCopWeapon("heli", 4, 0) ~= false or w:getCopWeapon("nada", 4, 0) ~= false then
        return t.fail("getCopWeapon acepto una flota sin armas o inexistente")
    end
    t.pass("porra -> pistola -> escopeta -> MP5 -> M4 segun las estrellas")
end)

test("busqueda_config_ia_coherente", function(t)
    local errs = exports.rp_wanted:getPoliceAIConfigErrors()
    if type(errs) ~= "table" then return t.fail("getPoliceAIConfigErrors no devolvio una lista") end
    if #errs > 0 then return t.fail(table.concat(errs, "; ")) end
    t.pass("WANTED_SEARCH y WANTED_COMBAT coherentes")
end)
