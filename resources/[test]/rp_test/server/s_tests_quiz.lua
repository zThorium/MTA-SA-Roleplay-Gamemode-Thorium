--[[
    rp_test / s_tests_quiz.lua
    rp_quiz (#111): cuestionario de rol y tutorial. Sin jugadores se prueban los exports,
    las columnas nuevas y que el aprobado se guarda una sola vez en accounts.
]]

test("quiz_recurso_y_exports", function(t)
    local res = getResourceFromName("rp_quiz")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_quiz no esta running") end
    if exports.rp_quiz:hasPassedQuiz(root) ~= false then return t.fail("hasPassedQuiz sin jugador debe ser false") end
    if exports.rp_quiz:openQuiz(root) ~= false then return t.fail("openQuiz sin jugador debe ser false") end
    t.pass()
end)

test("quiz_aprobado_se_guarda_una_vez", function(t, ctx)
    if not ctx.accountId or not ctx.characterId then return t.fail("sin cuenta o personaje de prueba") end
    local SQL = "UPDATE accounts SET quiz_passed_at = NOW() WHERE id = ? AND quiz_passed_at IS NULL"
    query(function()
        query(function(_, first)
            query(function(_, second)
                query(function(rows)
                    local done = rows and rows[1] and tonumber(rows[1].tutorial_done)
                    if first ~= 1 then return t.fail("el primer aprobado no se guardó") end
                    if second ~= 0 then return t.fail("el aprobado se volvió a escribir") end
                    if done ~= 0 and done ~= 1 then return t.fail("falta characters.tutorial_done") end
                    t.pass("aprobado único; tutorial_done = " .. done)
                end, "SELECT tutorial_done FROM characters WHERE id = ?", ctx.characterId)
            end, SQL, ctx.accountId)
        end, SQL, ctx.accountId)
    end, "UPDATE accounts SET quiz_passed_at = NULL WHERE id = ?", ctx.accountId)
end)
