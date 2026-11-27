-- rp_achievements: pruebas de humo (recurso, catálogo, tablas, upsert de estadísticas y reclamo atómico de hitos)

test("achievements_recurso_y_catalogo", function(t)
    local res = getResourceFromName("rp_achievements")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_achievements no está running") end
    local s = exports.rp_achievements:getAchievementStats()
    if type(s) ~= "table" then return t.fail("getAchievementStats no devolvió tabla") end
    if #s.problems > 0 then return t.fail("catálogo: " .. table.concat(s.problems, "; ")) end
    if s.achievements < 30 or s.milestones < 1 then return t.fail("catálogo demasiado corto") end
    if exports.rp_achievements:hasAchievement(root, "points:0") ~= false then return t.fail("hasAchievement(root) debería ser false") end
    if exports.rp_achievements:progress(root, "pizza_delivered", 1) ~= false then return t.fail("progress(root) debería ser false") end
    t.pass(("%d logros, %d estadísticas, %d hitos, %d puntos posibles"):format(s.achievements, s.stats, s.milestones, s.maxPoints))
end)

test("achievements_tabla_estadisticas", function(t, ctx)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        if not ctx.characterId then return t.pass("tabla accesible (sin personaje de prueba)") end
        local sql = [[INSERT INTO character_achievement_stats (character_id, stat_key, value) VALUES (?, 'rptest_stat', ?)
            ON DUPLICATE KEY UPDATE value = VALUES(value)]]
        query(function()
            query(function()
                query(function(r2)
                    local v = r2 and r2[1] and tonumber(r2[1].value)
                    dbExec(exports.rp_database:getConnection(), "DELETE FROM character_achievement_stats WHERE character_id = ? AND stat_key = 'rptest_stat'", ctx.characterId)
                    if v ~= 42 then return t.fail("value = " .. tostring(v) .. " (esperado 42)") end
                    t.pass("el upsert guarda el último valor")
                end, "SELECT value FROM character_achievement_stats WHERE character_id = ? AND stat_key = 'rptest_stat'", ctx.characterId)
            end, sql, ctx.characterId, 42)
        end, sql, ctx.characterId, 7)
    end, "SELECT COUNT(*) AS n FROM character_achievement_stats")
end)

test("achievements_tabla_medallas", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("character_achievements accesible")
    end, "SELECT COUNT(*) AS n FROM character_achievements")
end)

-- Mismo INSERT IGNORE que s_rewards.lua: el segundo reclamo del mismo hito no afecta filas
test("achievements_hito_no_se_cobra_dos_veces", function(t, ctx)
    if not ctx.characterId then
        return query(function(rows, _, _, code, msg)
            if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
            t.pass("tabla de hitos accesible (sin personaje de prueba)")
        end, "SELECT COUNT(*) AS n FROM character_achievement_milestones")
    end
    local db = exports.rp_database:getConnection()
    local sql = "INSERT IGNORE INTO character_achievement_milestones (character_id, milestone) VALUES (?, 250)"
    dbExec(db, "DELETE FROM character_achievement_milestones WHERE character_id = ? AND milestone = 250", ctx.characterId)
    dbQuery(function(qh)
        local _, first = dbPoll(qh, 0)
        dbQuery(function(qh2)
            local _, second = dbPoll(qh2, 0)
            dbExec(db, "DELETE FROM character_achievement_milestones WHERE character_id = ? AND milestone = 250", ctx.characterId)
            if first ~= 1 or second ~= 0 then
                return t.fail(("filas afectadas %s y %s (esperado 1 y 0)"):format(tostring(first), tostring(second)))
            end
            t.pass("el primer reclamo inserta y el segundo no")
        end, db, sql, ctx.characterId)
    end, db, sql, ctx.characterId)
end)
