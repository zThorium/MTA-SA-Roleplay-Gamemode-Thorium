--[[
    rp_test / s_tests_sistema.lua   (copiar a resources/[test]/rp_test/server/)

    Pruebas de humo de rp_sistema sin jugadores: se reproducen las consultas del
    recurso contra la BD real y se llaman sus exports. Registrar en rp_test/meta.xml:
        <include resource="rp_sistema" />
        <script src="server/s_tests_sistema.lua" type="server" />

    Helpers del runner (s_runner.lua):
        test(nombre, function(t, ctx) ... t.pass(detalle) / t.fail(motivo) end)
        query(function(rows, affected, insertId, errCode, errMsg) ... end, sql, ...)
    Las pruebas corren en orden; ctx se comparte entre ellas. Cuentas de prueba con
    prefijo "rptest_" (se borran solas; todo cuelga de ON DELETE CASCADE).
]]

test("sistema_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_sistema")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_sistema no está running") end
    t.pass()
end)

test("sistema_tabla_existe", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("character_sistema accesible")
    end, "SELECT COUNT(*) AS n FROM character_sistema")
end)

-- Ejemplo de cobro atómico: necesita un personaje de prueba en ctx (lo crean las pruebas de s_tests.lua)
test("sistema_cobro_sin_saldo_no_entrega", function(t, ctx)
    if not ctx.characterId then return t.fail("no hay personaje de prueba en ctx") end
    query(function(rows, affected)
        if not rows then return t.fail("UPDATE falló") end
        if affected ~= 0 then return t.fail("cobró sin saldo suficiente") end
        t.pass("0 filas afectadas con saldo insuficiente")
    end, "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?",
        999999999, ctx.characterId, 999999999)
end)

test("sistema_export_responde", function(t)
    local ok = exports.rp_sistema:isPlayerDoingSistema(root) == false
    if not ok then return t.fail("isPlayerDoingSistema debería devolver false sin jugador") end
    t.pass()
end)
