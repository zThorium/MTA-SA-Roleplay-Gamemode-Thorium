--[[
    rp_test / s_tests_walk.lua
    Pruebas de humo del estilo de caminar de rp_anims (characters.walk_style).
]]

test("walk_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_anims")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_anims no esta running") end
    t.pass()
end)

test("walk_estilo_se_guarda_por_personaje", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    query(function(_, affected)
        if affected ~= 1 then return t.fail("no actualizo walk_style") end
        query(function(rows)
            if not rows or not rows[1] or tonumber(rows[1].walk_style) ~= 126 then return t.fail("walk_style no quedo en 126") end
            query(function() t.pass("walk_style guardado y leido") end,
                "UPDATE characters SET walk_style = 0 WHERE id = ?", ctx.characterId)
        end, "SELECT walk_style FROM characters WHERE id = ?", ctx.characterId)
    end, "UPDATE characters SET walk_style = ? WHERE id = ?", 126, ctx.characterId)
end)
