--[[
    rp_test / s_tests_factions.lua
    API central de rp_factions: la consultan todos los recursos para saber de facciones.
]]

test("fac_api_exports", function(t)
    local names = { "isPlayerInFaction", "isPlayerOnDuty", "getPlayerFactionId", "getPlayerFactionType",
        "isPlayerFactionLeader", "getPlayerFactionInfo", "getFactionInfo", "getFactions", "getFactionPlayers",
        "getCharacterFaction", "getPlayerFaction" }
    for _, n in ipairs(names) do
        local ok = pcall(function() return exports.rp_factions[n](exports.rp_factions, root) end)
        if not ok then return t.fail("export que falla: " .. n) end
    end
    t.pass(#names .. " exports responden")
end)

-- El esquema crea la facción 1 como policía: la API la encuentra por id y por tipo
test("fac_api_policia_por_tipo", function(t)
    local info = exports.rp_factions:getFactionInfo(1)
    if type(info) ~= "table" or info.type ~= "policia" then return t.fail("la facción 1 no es de tipo policia") end
    local list = exports.rp_factions:getFactions("policia")
    for _, f in ipairs(list) do
        if f.id == 1 then return t.pass(("%d facciones de policía"):format(#list)) end
    end
    t.fail("getFactions('policia') no incluye la facción 1")
end)

-- Sin facción no se pertenece a nada (root no es un jugador)
test("fac_api_sin_faccion", function(t)
    local f = exports.rp_factions
    if f:isPlayerInFaction(root) or f:isPlayerInFaction(root, "policia") or f:isPlayerOnDuty(root, "policia")
        or f:getPlayerFactionId(root) or f:getPlayerFactionInfo(root) or f:getCharacterFaction(0) then
        return t.fail("un elemento sin facción aparece como miembro")
    end
    if type(f:getFactionPlayers("policia")) ~= "table" then return t.fail("getFactionPlayers no devuelve lista") end
    t.pass()
end)

-- #102: los tipos que usan los sistemas nuevos existen y son válidos (nombre, color #rrggbb,
-- clave que cabe en factions.type VARCHAR(16) y, si hay servicio, duty + dutyData)
test("fac_tipos_registrados", function(t)
    local types = exports.rp_factions:getFactionTypes()
    if type(types) ~= "table" then return t.fail("getFactionTypes no devuelve una tabla") end
    local needed = { "gobierno", "policia", "medicos", "bomberos", "empresa", "banda", "otra",
        "mecanicos", "noticias", "transporte", "logistica", "seguros", "seguridad", "concesionaria", "mafia" }
    for _, k in ipairs(needed) do
        if not types[k] then return t.fail("falta el tipo " .. k) end
    end
    for k, ty in pairs(types) do
        if #k > 16 then return t.fail(k .. ": clave de más de 16 caracteres") end
        if type(ty.name) ~= "string" or ty.name == "" then return t.fail(k .. ": sin nombre") end
        if type(ty.color) ~= "string" or not ty.color:match("^#%x%x%x%x%x%x$") then return t.fail(k .. ": color no es #rrggbb") end
        if (ty.duty ~= nil) ~= (ty.dutyData ~= nil) then return t.fail(k .. ": duty y dutyData van juntos") end
    end
    t.pass(#needed .. " tipos válidos")
end)

-- #106: facturas. Sin jugadores no se puede emitir; se prueba el export, el permiso y el cobro
-- atómico del banco que usa el pago (con saldo mueve el monto exacto; sin saldo no mueve nada)
test("fac_facturas_export_y_permiso", function(t)
    local ok, why = exports.rp_factions:bill(root, root, 10, "Prueba")
    if ok ~= false or type(why) ~= "string" then return t.fail("bill con datos no válidos debe devolver false, motivo") end
    local types = exports.rp_factions:getFactionTypes()
    if type(types) ~= "table" then return t.fail("sin tipos") end
    t.pass("bill rechaza: " .. why)
end)

test("fac_facturas_cobro_atomico", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    local CHARGE = "UPDATE characters SET bank_money = bank_money - ? WHERE id = ? AND bank_money >= ?"
    query(function(rows)
        local before = tonumber(rows and rows[1] and rows[1].bank_money) or 0
        query(function()
        query(function(_, a1)
            query(function(_, a2)
                query(function(r2)
                    local after = tonumber(r2 and r2[1] and r2[1].bank_money) or -1
                    if a1 ~= 1 then return t.fail("con saldo no cobró") end
                    if a2 ~= 0 then return t.fail("sin saldo cobró igual") end
                    if after ~= before then return t.fail(("saldo %d, esperado %d"):format(after, before)) end
                    t.pass("cobra exacto y sin saldo no mueve nada")
                end, "SELECT bank_money FROM characters WHERE id = ?", ctx.characterId)
            end, CHARGE, before + 1000000, ctx.characterId, before + 1000000)
        end, CHARGE, 25, ctx.characterId, 25)
        end, "UPDATE characters SET bank_money = bank_money + 25 WHERE id = ?", ctx.characterId)
    end, "SELECT bank_money FROM characters WHERE id = ?", ctx.characterId)
end)
