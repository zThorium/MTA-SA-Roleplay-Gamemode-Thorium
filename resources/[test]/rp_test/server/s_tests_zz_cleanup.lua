-- rp_test: limpieza final. Va en el ultimo <script> del meta.xml: borra la cuenta y el personaje de prueba
-- cuando ya corrieron todas las pruebas que los usan (antes estaba en s_tests.lua y las de despues
-- recibian un characterId ya borrado: fallaban por la clave foranea).

local PREFIX = "rptest_"

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
test("borrar_cuenta_en_cascada", function(t, ctx)
    if not ctx.accountId then return t.fail("sin cuenta de prueba") end
    query(function(rows, affected)
        if not rows or affected ~= 1 then return t.fail("no se borro la cuenta de prueba") end
        ctx.cleanup = nil
        -- login_log usa ON DELETE SET NULL: sus filas se quedarian; se borran aparte
        query(function() end, "DELETE FROM login_log WHERE username LIKE ?", PREFIX .. "%")
        query(function(r)
            local left = r and r[1] and tonumber(r[1].n)
            if left ~= 0 then return t.fail(tostring(left) .. " filas huerfanas (personajes/items) tras borrar la cuenta") end
            t.pass("cuenta, personaje, items y movimientos borrados")
        end, [[
            SELECT (SELECT COUNT(*) FROM characters WHERE id = ?)
                 + (SELECT COUNT(*) FROM character_items WHERE character_id = ?)
                 + (SELECT COUNT(*) FROM bank_transactions WHERE character_id = ?) AS n
        ]], ctx.characterId or 0, ctx.characterId or 0, ctx.characterId or 0)
    end, "DELETE FROM accounts WHERE id = ?", ctx.accountId)
end)
