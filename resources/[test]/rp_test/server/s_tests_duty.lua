--[[
    rp_test / s_tests_duty.lua
    rp_duty (#104): vestuario genérico de facción. Sin jugadores no se puede entrar de servicio,
    así que se prueban los exports, los tipos que lo usan y el registro del equipo entregado
    (faction_duty_items), que es lo que evita duplicar ítems tras una caída del servidor.
]]

test("duty_recurso_y_exports", function(t)
    local res = getResourceFromName("rp_duty")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_duty no esta running") end
    if exports.rp_duty:isOnDuty(root) ~= false then return t.fail("isOnDuty sin jugador debe ser false") end
    if exports.rp_duty:getDutyLoadout(root) ~= false then return t.fail("getDutyLoadout sin jugador debe ser false") end
    if type(exports.rp_duty:adminElements()) ~= "table" then return t.fail("adminElements no devuelve tabla") end
    t.pass()
end)

-- Todo tipo con duty apunta a un recurso que existe; los genéricos usan rp_duty y su element data
test("duty_tipos_con_servicio", function(t)
    local types = exports.rp_factions:getFactionTypes()
    local generic = 0
    for k, ty in pairs(types) do
        if ty.duty then
            if not getResourceFromName(ty.duty) then return t.fail(k .. ": el recurso de servicio " .. ty.duty .. " no existe") end
            if ty.duty == "rp_duty" then
                generic = generic + 1
                if ty.dutyData ~= "rp:factionDuty" then return t.fail(k .. ": dutyData debe ser rp:factionDuty") end
            end
        end
    end
    for _, k in ipairs({ "medicos", "gobierno", "mecanicos", "noticias", "transporte" }) do
        if not types[k] or types[k].duty ~= "rp_duty" then return t.fail(k .. " debe usar rp_duty") end
    end
    for _, k in ipairs({ "policia", "bomberos", "banda", "mafia" }) do
        if types[k] and types[k].duty == "rp_duty" then return t.fail(k .. " no debe usar rp_duty") end
    end
    t.pass(generic .. " tipos con vestuario generico")
end)

-- Un registro por personaje: REPLACE no duplica y el borrado lo deja limpio
test("duty_registro_de_equipo", function(t, ctx)
    if not ctx.characterId then return t.fail("sin personaje de prueba") end
    local SQL = "REPLACE INTO faction_duty_items (character_id, faction_id, items) VALUES (?, NULL, ?)"
    query(function(r1, _, _, code, msg)
        if not r1 then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        query(function()
            query(function(rows)
                local n = rows and rows[1] and tonumber(rows[1].n)
                local items = rows and rows[1] and rows[1].items
                query(function(_, deleted)
                    if n ~= 1 then return t.fail("hay " .. tostring(n) .. " registros (debe haber 1)") end
                    if items ~= "medkit:3" then return t.fail("el segundo registro no reemplazo al primero: " .. tostring(items)) end
                    if deleted ~= 1 then return t.fail("no se borro el registro") end
                    t.pass("un registro por personaje")
                end, "DELETE FROM faction_duty_items WHERE character_id = ?", ctx.characterId)
            end, "SELECT COUNT(*) AS n, MAX(items) AS items FROM faction_duty_items WHERE character_id = ?", ctx.characterId)
        end, SQL, ctx.characterId, "medkit:3")
    end, SQL, ctx.characterId, "medkit:2,water:1")
end)

-- #105: fondos de facción atómicos (los usa el garaje) y catálogo del garaje
test("duty_fondos_de_faccion", function(t)
    local f = exports.rp_factions
    local before = f:getFactionFunds(1)
    if type(before) ~= "number" then return t.fail("getFactionFunds(1) no devuelve número") end
    if f:takeFactionFunds(1, before + 1) ~= false then return t.fail("cobró más de lo que hay en los fondos") end
    if f:takeFactionFunds(1, -5) ~= false or f:addFactionFunds(1, 0) ~= false then return t.fail("aceptó una cantidad no válida") end
    if not f:addFactionFunds(1, 7) or f:getFactionFunds(1) ~= before + 7 then return t.fail("addFactionFunds no sumó") end
    if not f:takeFactionFunds(1, 7) or f:getFactionFunds(1) ~= before then return t.fail("takeFactionFunds no restó") end
    t.pass("cobro e ingreso exactos; sin saldo no cobra")
end)

test("duty_garaje_exports", function(t)
    if exports.rp_duty:getFactionVehicleInfo(root) ~= false then return t.fail("getFactionVehicleInfo sin vehículo debe ser false") end
    if type(exports.rp_duty:adminElements("garage")) ~= "table" then return t.fail("adminElements('garage') no devuelve tabla") end
    t.pass()
end)
