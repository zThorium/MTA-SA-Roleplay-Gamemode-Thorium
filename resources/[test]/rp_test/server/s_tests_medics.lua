-- rp_medics: pruebas de humo (recurso, exports, registro del servicio, mochila de servicio y casillero en BD)

test("medicos_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_medics")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_medics no esta running") end
    t.pass()
end)

test("medicos_exports_sin_jugador", function(t)
    if exports.rp_medics:isOnDuty(root) ~= false then return t.fail("isOnDuty(root) deberia ser false") end
    if exports.rp_medics:isMedic(root) ~= false then return t.fail("isMedic(root) deberia ser false") end
    if type(exports.rp_medics:getMedicsOnDuty()) ~= "table" then return t.fail("getMedicsOnDuty no devuelve tabla") end
    t.pass()
end)

-- La mochila de servicio existe como item y rp_backpacks expone stowBackpack (sin jugador devuelve false)
test("medicos_mochila_de_servicio", function(t)
    if not exports.rp_inventory:getItemDefinition("bp_medic") then return t.fail("falta el item bp_medic") end
    if exports.rp_backpacks:stowBackpack(root) ~= false then return t.fail("stowBackpack(root) deberia ser false") end
    t.pass()
end)

-- Casillero: guardar ítems (upsert), guardar la mochila con contenido JSON, leerla igual y borrado en cascada
test("medicos_casillero_bd", function(t)
    local user = "rptest_md" .. getRealTime().timestamp
    local function done(ok, msg, accountId)
        if accountId then query(function() end, "DELETE FROM accounts WHERE id = ?", accountId) end
        if ok then t.pass(msg) else t.fail(msg) end
    end
    local upsert = [[
        INSERT INTO faction_locker_items (character_id, faction_type, item_id, amount) VALUES (?, 'medicos', ?, ?)
        ON DUPLICATE KEY UPDATE amount = VALUES(amount)]]
    query(function(_, _, accountId)
        if not accountId then return done(false, "no se creo la cuenta de prueba") end
        query(function(_, _, charId, code, msg)
            if not charId then return done(false, ("INSERT characters: [%s] %s"):format(tostring(code), tostring(msg)), accountId) end
            query(function(r1)
                if not r1 then return done(false, "primer upsert fallo", accountId) end
                query(function(r2)
                    if not r2 then return done(false, "segundo upsert fallo", accountId) end
                    query(function(r3)
                        if not r3 then return done(false, "REPLACE de la mochila fallo", accountId) end
                        query(function(rows)
                            local r = rows and rows[1]
                            if not r or tonumber(r.amount) ~= 5 then return done(false, "cantidad guardada incorrecta", accountId) end
                            query(function(packs)
                                local p = packs and packs[1]
                                local c = p and fromJSON(p.contents)
                                if not c or c.water ~= 2 or p.backpack_id ~= "bp_hiking" then
                                    return done(false, "contenido de la mochila no coincide", accountId)
                                end
                                query(function()
                                    query(function(left)
                                        if not left or tonumber(left[1].n) ~= 0 then return done(false, "quedaron filas tras borrar el personaje", accountId) end
                                        done(true, "items 5, mochila con 2 aguas, cascada ok", accountId)
                                    end, "SELECT (SELECT COUNT(*) FROM faction_locker_items WHERE character_id = ?) + (SELECT COUNT(*) FROM faction_locker_backpack WHERE character_id = ?) AS n", charId, charId)
                                end, "DELETE FROM characters WHERE id = ?", charId)
                            end, "SELECT backpack_id, contents FROM faction_locker_backpack WHERE character_id = ? AND faction_type = 'medicos'", charId)
                        end, "SELECT amount FROM faction_locker_items WHERE character_id = ? AND item_id = 'burger'", charId)
                    end, "REPLACE INTO faction_locker_backpack (character_id, faction_type, backpack_id, contents) VALUES (?, 'medicos', 'bp_hiking', ?)",
                        charId, toJSON({ water = 2 }, true))
                end, upsert, charId, "burger", 5)
            end, upsert, charId, "burger", 2)
        end, "INSERT INTO characters (account_id, name, gender, age, weight, height, origin, story, skin, money) VALUES (?, ?, 0, 30, 75, 175, 'Prueba', 'Prueba', 274, 0)",
            accountId, "Medico_" .. getRealTime().timestamp)
    end, "INSERT INTO accounts (username, password_hash) VALUES (?, 'x')", user)
end)
