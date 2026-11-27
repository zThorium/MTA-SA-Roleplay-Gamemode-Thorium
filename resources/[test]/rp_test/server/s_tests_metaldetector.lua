-- rp_metaldetector: pruebas de humo (recurso, items del catálogo, botín y mercado de venta)

test("metaldetector_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_metaldetector")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_metaldetector no está running") end
    if exports.rp_metaldetector:isPlayerDetecting(root) ~= false then return t.fail("isPlayerDetecting(root) debería ser false") end
    t.pass()
end)

test("metaldetector_items_existen", function(t)
    if not exports.rp_inventory:getItemDefinition("shovel") then return t.fail("falta el item shovel") end
    for i = 1, 5 do
        local id = "metal_detector_" .. i
        local def = exports.rp_inventory:getItemDefinition(id)
        if not def then return t.fail("falta el item " .. id) end
        if not (def.use and def.use.event) then return t.fail(id .. " debe disparar rp:onItemUse (use.event)") end
    end
    t.pass("5 detectores y la pala")
end)

test("metaldetector_tabla_progreso", function(t, ctx)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        if not ctx.characterId then return t.pass("metal_detecting accesible (sin personaje de prueba)") end
        -- Mismo upsert que el recurso: suma XP, objetos y dinero
        local sql = [[INSERT INTO metal_detecting (character_id, xp, items_found, money_earned) VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE xp = xp + VALUES(xp), items_found = items_found + VALUES(items_found),
            money_earned = money_earned + VALUES(money_earned)]]
        -- Se parte de cero: si el personaje de prueba ya tiene fila (otra prueba, el propio recurso), se borra antes
        query(function(r0)
            local had = r0 and r0[1] and ("%s/%s/%s"):format(r0[1].xp, r0[1].items_found, r0[1].money_earned) or "ninguna"
            query(function()
                query(function(_, _, _, c1, m1)
                    query(function(_, _, _, c2, m2)
                        query(function(r2)
                            local r = r2 and r2[1]
                            dbExec(exports.rp_database:getConnection(), "DELETE FROM metal_detecting WHERE character_id = ?", ctx.characterId)
                            if not r or tonumber(r.xp) ~= 15 or tonumber(r.items_found) ~= 2 or tonumber(r.money_earned) ~= 300 then
                                return t.fail(("valores tras dos upserts: %s (esperado 15/2/300; fila previa %s; errores %s %s)"):format(
                                    r and ("%s/%s/%s"):format(r.xp, r.items_found, r.money_earned) or "sin fila", had,
                                    tostring(m1 or c1 or "-"), tostring(m2 or c2 or "-")))
                            end
                            t.pass("upsert del progreso suma XP, objetos y dinero")
                        end, "SELECT xp, items_found, money_earned FROM metal_detecting WHERE character_id = ?", ctx.characterId)
                    end, sql, ctx.characterId, 5, 1, 300)
                end, sql, ctx.characterId, 10, 1, 0)
            end, "DELETE FROM metal_detecting WHERE character_id = ?", ctx.characterId)
        end, "SELECT xp, items_found, money_earned FROM metal_detecting WHERE character_id = ?", ctx.characterId)
    end, "SELECT COUNT(*) AS n FROM metal_detecting")
end)

test("metaldetector_tabla_coleccion", function(t, ctx)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        if not ctx.characterId then return t.pass("metal_finds accesible (sin personaje de prueba para el upsert)") end
        -- Upsert de un hallazgo dos veces: debe quedar times = 2
        local sql = [[INSERT INTO metal_finds (character_id, item_id, times) VALUES (?, 'rptest_item', 1)
            ON DUPLICATE KEY UPDATE times = times + 1, last_at = CURRENT_TIMESTAMP]]
        query(function()
            query(function()
                query(function(r2)
                    local n = r2 and r2[1] and tonumber(r2[1].times)
                    dbExec(exports.rp_database:getConnection(), "DELETE FROM metal_finds WHERE character_id = ? AND item_id = 'rptest_item'", ctx.characterId)
                    if n ~= 2 then return t.fail("times = " .. tostring(n) .. " (esperado 2)") end
                    t.pass("upsert de la colección suma veces")
                end, "SELECT times FROM metal_finds WHERE character_id = ? AND item_id = 'rptest_item'", ctx.characterId)
            end, sql, ctx.characterId)
        end, sql, ctx.characterId)
    end, "SELECT COUNT(*) AS n FROM metal_finds")
end)

test("metaldetector_botin_valido_y_vendible", function(t)
    local loot = exports.rp_metaldetector:getMetalDetectorLoot()
    if type(loot) ~= "table" or #loot == 0 then return t.fail("tabla de botín vacía") end
    local total = 0
    for _, e in ipairs(loot) do
        if not exports.rp_inventory:getItemDefinition(e.item) then return t.fail("botín con item inexistente: " .. tostring(e.item)) end
        if not (tonumber(e.weight) and e.weight > 0) then return t.fail("peso inválido en " .. e.item) end
        if not (e.amount and e.amount[1] >= 1 and e.amount[2] >= e.amount[1]) then return t.fail("cantidad inválida en " .. e.item) end
        if not exports.rp_jobs:getMarketPrice("beachfinds", e.item) then return t.fail(e.item .. " no se vende en el Puesto del buscador") end
        total = total + e.weight
    end
    t.pass(("%d premios, peso total %d"):format(#loot, total))
end)
