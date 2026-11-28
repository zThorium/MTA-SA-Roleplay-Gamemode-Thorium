--[[
    rp_test / s_tests_properties.lua
    Regresion de #150: /vendercasa liberaba la casa sin comprobar el dueno en SQL y pagaba el
    reembolso dos veces si se mandaba seguido. Se reproduce la misma sentencia atomica que usa
    rp_properties (UPDATE ... AND owner_id = ?): solo la primera venta afecta una fila.
]]

test("properties_vender_es_atomico", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    local SELL = "UPDATE properties SET owner_id = NULL, locked = 1 WHERE id = ? AND owner_id = ?"
    query(function(rows, _, propId, code, msg)
        if not rows or not propId or propId == 0 then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        local function finish(ok, why)
            query(function() if ok then t.pass(why) else t.fail(why) end end, "DELETE FROM properties WHERE id = ?", propId)
        end
        query(function(_, first)
            if first ~= 1 then return finish(false, "la primera venta no libero la casa (" .. tostring(first) .. ")") end
            query(function(_, second)
                if second ~= 0 then return finish(false, "la segunda venta tambien afecto filas: doble reembolso") end
                finish(true, "solo la primera venta paga")
            end, SELL, propId, ctx.characterId)
        end, SELL, propId, ctx.characterId)
    end, "INSERT INTO properties (name, type, price, x, y, z, owner_id) VALUES ('rptest_casa', 'house', 1000, 0, 0, -50, ?)", ctx.characterId)
end)
