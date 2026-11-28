--[[
    rp_test / s_tests_factionduty.lua
    Servicio genérico de facción (#104): exports, tipos que lo usan, tablas y el libro del equipo
    entregado (entrar y salir de servicio no duplica ítems).
]]

test("fduty_exports", function(t)
    local d = exports.rp_factionduty
    if d:isOnDuty(root) ~= false then return t.fail("isOnDuty(root) debería ser false") end
    if d:hasDuty(0) ~= false then return t.fail("hasDuty(0) debería ser false") end
    if type(d:adminElements()) ~= "table" then return t.fail("adminElements no devuelve lista") end
    -- Sin vestuario una facción genérica no tiene servicio: el sueldo se cobra como siempre
    if exports.rp_factions:isPlayerOnDuty(root) then return t.fail("root aparece de servicio") end
    t.pass()
end)

test("fduty_tipos_genericos", function(t)
    local types = exports.rp_factions:getFactionTypes()
    local count = 0
    for k, ty in pairs(types) do
        if ty.duty == "rp_factionduty" then
            if not ty.dutyOptional or ty.dutyData ~= "rp:factionDuty" then return t.fail(k .. ": servicio genérico mal declarado") end
            count = count + 1
        end
    end
    for _, k in ipairs({ "policia", "bomberos", "medicos", "banda", "mafia" }) do
        if types[k] and types[k].duty == "rp_factionduty" then return t.fail(k .. " no debe usar el servicio genérico") end
    end
    if count == 0 then return t.fail("ningún tipo usa rp_factionduty") end
    t.pass(count .. " tipos con servicio genérico")
end)

-- Entrar dos veces de servicio suma lo entregado en una sola fila y salir la borra (no quedan restos)
test("fduty_libro_no_duplica", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    local ADD = [[
        INSERT INTO faction_duty_items (character_id, item_id, amount) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
    ]]
    local cid = ctx.characterId
    query(function(ok, _, _, code, msg)
        if not ok then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        query(function()
            query(function(rows)
                if not rows or #rows ~= 1 or tonumber(rows[1].amount) ~= 2 then
                    return t.fail("el libro no acumula en una fila: " .. tostring(rows and #rows))
                end
                query(function()
                    query(function(left)
                        if left and #left > 0 then return t.fail("quedan filas tras devolver") end
                        t.pass("una fila por objeto y se borra al devolver")
                    end, "SELECT 1 FROM faction_duty_items WHERE character_id = ?", cid)
                end, "DELETE FROM faction_duty_items WHERE character_id = ? AND item_id = ?", cid, "vest")
            end, "SELECT amount FROM faction_duty_items WHERE character_id = ? AND item_id = ?", cid, "vest")
        end, ADD, cid, "vest", 1)
    end, ADD, cid, "vest", 1)
end)

-- Los equipos guardan los objetos en JSON (toJSON del servidor) y se leen igual al cargar
test("fduty_equipos_json", function(t)
    query(function(rows, _, id, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        query(function(r)
            local items = r and r[1] and fromJSON(r[1].items)
            query(function() end, "DELETE FROM faction_loadouts WHERE id = ?", id)
            if type(items) ~= "table" or not items[1] or items[1].id ~= "vest" then return t.fail("el JSON de objetos no se lee") end
            t.pass()
        end, "SELECT items FROM faction_loadouts WHERE id = ?", id)
    end, "INSERT INTO faction_loadouts (faction_id, name, min_level, skin, items) VALUES (1, 'rptest_equipo', 1, 280, ?)",
        toJSON({ { id = "vest", amount = 1 } }, true))
end)
