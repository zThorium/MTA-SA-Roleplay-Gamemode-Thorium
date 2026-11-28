--[[
    rp_test / s_tests_cartheft.lua
    Pruebas de rp_cartheft: ganzua en el catalogo y en las tiendas, exports y los
    exports nuevos de rp_vehicles (solo actuan sobre vehiculos con dueno).
]]

test("cartheft_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_cartheft")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_cartheft no esta running") end
    t.pass()
end)

test("cartheft_ganzua_en_catalogo", function(t)
    local def = exports.rp_inventory:getItemDefinition("lockpick")
    if not def then return t.fail("falta el item lockpick en rp_inventory") end
    if not (def.use and def.use.event) then return t.fail("lockpick debe tener use = { event = ... }") end
    t.pass(def.name)
end)

test("cartheft_ganzua_en_todas_las_tiendas", function(t)
    query(function(rows)
        if not rows then return t.fail("consulta fallida") end
        local n = tonumber(rows[1] and rows[1].n) or 0
        if n > 0 then return t.fail(n .. " tiendas sin ganzua") end
        t.pass("todas las tiendas venden ganzua")
    end, "SELECT COUNT(*) AS n FROM shops s WHERE NOT EXISTS (SELECT 1 FROM shop_items i WHERE i.shop_id = s.id AND i.item_id = 'lockpick')")
end)

test("cartheft_exports", function(t)
    if exports.rp_cartheft:isPlayerStealing(root) ~= false then return t.fail("isPlayerStealing sin jugador debe ser false") end
    local v = createVehicle(410, 0, 0, -50)
    local alarm = exports.rp_cartheft:isVehicleAlarmOn(v)
    -- vehiculo sin dueno: rp_vehicles no lo abre ni le hace el puente
    local lock = exports.rp_vehicles:setVehicleLockState(v, false)
    local wire = exports.rp_vehicles:setVehicleHotwired(v, true)
    destroyElement(v)
    if alarm ~= false then return t.fail("un vehiculo nuevo no debe tener la alarma puesta") end
    if lock ~= false or wire ~= false then return t.fail("setVehicleLockState/setVehicleHotwired deben ignorar vehiculos sin dueno") end
    t.pass()
end)
