-- rp_firefighters: pruebas de humo (recurso, tablas, upsert de experiencia, cascada de sitios y exports)

test("bomberos_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_firefighters")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_firefighters no esta running") end
    t.pass()
end)

test("bomberos_exports_sin_jugador", function(t)
    if exports.rp_firefighters:isOnDuty(root) ~= false then return t.fail("isOnDuty(root) deberia ser false") end
    if exports.rp_firefighters:isFirefighter(root) ~= false then return t.fail("isFirefighter(root) deberia ser false") end
    if type(exports.rp_firefighters:getFirefightersOnDuty()) ~= "table" then return t.fail("getFirefightersOnDuty no devuelve tabla") end
    t.pass()
end)

-- La experiencia se suma con el mismo upsert que usa FD.addStats (cuenta y personaje propios: los de
-- s_tests.lua ya se borraron al llegar aqui)
test("bomberos_stats_upsert_suma", function(t)
    local user = "rptest_fd" .. getRealTime().timestamp
    local function done(ok, msg, accountId)
        if accountId then query(function() end, "DELETE FROM accounts WHERE id = ?", accountId) end
        if ok then t.pass(msg) else t.fail(msg) end
    end
    local sql = [[
        INSERT INTO firefighter_stats (character_id, xp, fires, rescues, ok, failed) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), fires = fires + VALUES(fires), rescues = rescues + VALUES(rescues),
                                ok = ok + VALUES(ok), failed = failed + VALUES(failed)]]
    query(function(_, _, accountId)
        if not accountId then return done(false, "no se creo la cuenta de prueba") end
        query(function(_, _, charId, code, msg)
            if not charId then return done(false, ("INSERT characters: [%s] %s"):format(tostring(code), tostring(msg)), accountId) end
            query(function(r1)
                if not r1 then return done(false, "primer upsert fallo", accountId) end
                query(function(r2)
                    if not r2 then return done(false, "segundo upsert fallo", accountId) end
                    query(function(rows)
                        local r = rows and rows[1]
                        if not r then return done(false, "sin fila", accountId) end
                        if tonumber(r.xp) ~= 65 or tonumber(r.rescues) ~= 3 or tonumber(r.ok) ~= 2 then
                            return done(false, ("suma incorrecta xp=%s rescues=%s ok=%s"):format(tostring(r.xp), tostring(r.rescues), tostring(r.ok)), accountId)
                        end
                        done(true, "xp 65, rescates 3, exitos 2 (y borrado en cascada)", accountId)
                    end, "SELECT xp, rescues, ok FROM firefighter_stats WHERE character_id = ?", charId)
                end, sql, charId, 35, 1, 2, 1, 0)
            end, sql, charId, 30, 2, 1, 1, 0)
        end, "INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin, money) VALUES (?, ?, 0, 30, 75, 175, 'Prueba', 'Prueba', 277, 0)",
            accountId, "Bombero_" .. getRealTime().timestamp)
    end, "INSERT INTO accounts (username, password_hash) VALUES (?, 'x')", user)
end)

-- Borrar un sitio borra sus focos y civiles
test("bomberos_sitio_cascada", function(t)
    query(function(_, _, siteId)
        if not siteId then return t.fail("no se creo el sitio") end
        query(function(ok)
            if not ok then return t.fail("no se creo el punto") end
            query(function()
                query(function(rows)
                    if not rows then return t.fail("SELECT fallo") end
                    if tonumber(rows[1].n) ~= 0 then return t.fail("quedaron puntos huerfanos") end
                    t.pass()
                end, "SELECT COUNT(*) AS n FROM fire_site_points WHERE site_id = ?", siteId)
            end, "DELETE FROM fire_sites WHERE id = ?", siteId)
        end, "INSERT INTO fire_site_points (site_id, kind, x, y, z, rot) VALUES (?, 'fire', 0, 0, 0, 0)", siteId)
    end, "INSERT INTO fire_sites (name, x, y, z) VALUES ('rptest_sitio', 0, 0, 0)")
end)
