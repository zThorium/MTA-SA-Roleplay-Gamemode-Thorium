--[[
    rp_test / s_tests_logs.lua

    Pruebas de rp_logs (registro de economía): la tabla existe, log() escribe la fila con lo que se
    le pasa (personaje por id, objetivo desconectado como { id, name }, recurso que llama), rechaza
    tipos desconocidos y el flush en lote escribe varias filas a la vez.
    Las filas de prueba llevan detalle "rptest_logs_*" y se borran al final.
]]

local MARK = "rptest_logs_" .. getTickCount()

test("logs_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_logs")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_logs no está running") end
    t.pass()
end)

test("logs_tabla_existe", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("economy_log accesible")
    end, "SELECT COUNT(*) AS n FROM economy_log")
end)

test("logs_tipo_desconocido_rechazado", function(t)
    local ok, why = exports.rp_logs:log("no_existe", nil, nil, 1, MARK)
    if ok then return t.fail("aceptó un tipo desconocido") end
    t.pass(tostring(why))
end)

test("logs_escribe_fila", function(t, ctx)
    local actor = ctx.characterId or 1
    if not exports.rp_logs:log("bank_transfer", actor, { id = 424242, name = "Prueba_Destino" }, 1234, MARK .. "_a") then
        return t.fail("log() devolvió false")
    end
    exports.rp_logs:flush()
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        local r = rows[1]
        if not r then return t.fail("no se escribió la fila") end
        if tonumber(r.actor_char_id) ~= actor then return t.fail("actor_char_id " .. tostring(r.actor_char_id)) end
        if tonumber(r.target_char_id) ~= 424242 or r.target_name ~= "Prueba Destino" then
            return t.fail(("objetivo %s / %s"):format(tostring(r.target_char_id), tostring(r.target_name)))
        end
        if tonumber(r.amount) ~= 1234 or r.type ~= "bank_transfer" then return t.fail("cantidad o tipo mal guardados") end
        if r.resource ~= "rp_test" then return t.fail("recurso guardado: " .. tostring(r.resource)) end
        t.pass("fila completa")
    end, "SELECT * FROM economy_log WHERE details = ? ORDER BY id DESC LIMIT 1", MARK .. "_a")
end)

test("logs_lote_varias_filas", function(t)
    for i = 1, 3 do exports.rp_logs:log("item_drop", nil, nil, i, MARK .. "_lote") end
    exports.rp_logs:flush()
    query(function(rows)
        if not rows then return t.fail("SELECT falló") end
        local n = tonumber(rows[1] and rows[1].n) or 0
        if n ~= 3 then return t.fail(("se esperaban 3 filas, hay %d"):format(n)) end
        t.pass("3 filas en un INSERT")
    end, "SELECT COUNT(*) AS n FROM economy_log WHERE details = ?", MARK .. "_lote")
end)

test("logs_limpieza", function(t)
    query(function(rows, affected)
        if not rows then return t.fail("DELETE falló") end
        t.pass(("%d filas de prueba borradas"):format(affected or 0))
    end, "DELETE FROM economy_log WHERE details LIKE ?", MARK .. "%")
end)
