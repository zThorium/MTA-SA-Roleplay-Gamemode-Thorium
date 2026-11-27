--[[
    rp_test / s_tests_3dtext.lua
    Pruebas de humo de rp_3dtext: tablas, borrado logico auditable y exports de la gramatica Owl.
]]

test("3dtext_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_3dtext")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_3dtext no esta running") end
    t.pass()
end)

test("3dtext_crear_fila_y_log", function(t, ctx)
    query(function(rows, _, insertId, code, msg)
        if not rows or not insertId or insertId == 0 then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        ctx.text3dId = insertId
        query(function(r2, _, _, c2, m2)
            if not r2 then return t.fail(("log: [%s] %s"):format(tostring(c2), tostring(m2))) end
            t.pass("texto #" .. insertId)
        end, "INSERT INTO text3d_log (text3d_id, action, text, admin_account_id, admin_account, admin_name) VALUES (?, 'create', ?, NULL, 'rptest', 'rptest')",
            insertId, "Prueba")
    end, "INSERT INTO text3d (text, x, y, z, interior, dimension, created_by_account_id, created_by_account, created_by_name) VALUES (?, 0, 0, 3, 0, 0, NULL, 'rptest', 'rptest')",
        "Prueba")
end)

test("3dtext_borrado_logico_conserva_autor", function(t, ctx)
    if not ctx.text3dId then return t.fail("no hay texto de prueba") end
    query(function(_, affected)
        if affected ~= 1 then return t.fail("no marco deleted_at") end
        query(function(rows)
            local r = rows and rows[1]
            if not r or r.created_by_name ~= "rptest" or not r.deleted_at or r.n ~= 1 then
                return t.fail("la fila borrada no conserva autor/hora/historial")
            end
            query(function() t.pass("autor, hora de borrado e historial conservados") end,
                "DELETE FROM text3d WHERE id = ?", ctx.text3dId)
        end, [[SELECT t.created_by_name, t.deleted_at, (SELECT COUNT(*) FROM text3d_log WHERE text3d_id = t.id) AS n
               FROM text3d t WHERE t.id = ?]], ctx.text3dId)
    end, "UPDATE text3d SET deleted_at = NOW(), deleted_by_name = 'rptest' WHERE id = ? AND deleted_at IS NULL", ctx.text3dId)
end)

test("3dtext_exports_owl", function(t)
    local list = exports.rp_3dtext:adminElements()
    if type(list) ~= "table" then return t.fail("adminElements no devuelve tabla") end
    local ok = exports.rp_3dtext:adminDelete(-1)
    if ok then return t.fail("adminDelete borro un id inexistente") end
    t.pass(#list .. " textos en el mundo")
end)
