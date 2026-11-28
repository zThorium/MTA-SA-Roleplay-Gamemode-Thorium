--[[
    rp_test / s_tests_admin.lua
    Gramatica Owl de rp_admin (/nearby<x>, /del<x>...): cada recurso que registra
    WORLD_TYPES (rp_admin/s_world.lua) debe exponer adminElements y adminDelete con el
    formato esperado. adminDelete se prueba solo con un id que no existe (sin efectos).
]]

local OWNERS = {
    { "rp_bank" }, { "rp_shops" }, { "rp_properties" }, { "rp_clothing" }, { "rp_vending" },
    { "rp_dealers" }, { "rp_robbery" }, { "rp_gym", "machine" }, { "rp_gym", "trainer" },
    { "rp_driving" }, { "rp_pool" }, { "rp_train" }, { "rp_train", "booth" }, { "rp_train", "sign" }, { "rp_train", "gate" }, { "rp_train", "fence" }, { "rp_train", "pole" }, { "rp_relojflores" }, { "rp_markers" },
}

test("admin_exports_de_elementos", function(t)
    local total = 0
    for _, o in ipairs(OWNERS) do
        local res = getResourceFromName(o[1])
        if not res or getResourceState(res) ~= "running" then return t.fail(o[1] .. " no esta running") end
        local ok, list = pcall(call, res, "adminElements", o[2])
        if not ok or type(list) ~= "table" then return t.fail(o[1] .. ":adminElements no devolvio una tabla") end
        for _, e in ipairs(list) do
            if not (tonumber(e.id) and tonumber(e.x) and tonumber(e.y) and tonumber(e.z)
                and tonumber(e.interior) and tonumber(e.dimension)) then
                return t.fail(("%s: elemento con campos invalidos (id %s)"):format(o[1], tostring(e.id)))
            end
        end
        local okDel, done = pcall(call, res, "adminDelete", 987654321, o[2])
        if not okDel or done ~= false then return t.fail(o[1] .. ":adminDelete de un id inexistente no devolvio false") end
        total = total + #list
    end
    t.pass(("%d tipos, %d elementos con formato valido"):format(#OWNERS, total))
end)

test("admin_columnas_jail_y_mute", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("accounts.ojail_minutes, ojail_reason y mute_until accesibles")
    end, "SELECT ojail_minutes, ojail_reason, mute_until FROM accounts LIMIT 1")
end)

-- Vista ALT: tabla de creadores (alta, nombres con FIND_IN_SET como en s_inspect.lua y baja)
test("admin_creadores_de_elementos", function(t)
    query(function(_, affected, _, code, msg)
        if not affected or affected < 1 then return t.fail(("insert: [%s] %s"):format(tostring(code), tostring(msg))) end
        query(function(rows)
            local r = rows and rows[1]
            if not r or r.admin_name ~= "rptest" then return t.fail("no se leyo el creador guardado") end
            query(function(_, del)
                if del ~= 1 then return t.fail("no se borro la fila de prueba") end
                t.pass("creador guardado, leido y borrado")
            end, "DELETE FROM admin_world_creators WHERE type_key = 'rptest' AND element_id = 987654321")
        end, "SELECT admin_name FROM admin_world_creators WHERE type_key = 'rptest' AND FIND_IN_SET(element_id, ?)", "1,987654321")
    end, [[INSERT INTO admin_world_creators (type_key, element_id, account_id, admin_name) VALUES ('rptest', 987654321, NULL, 'rptest')
           ON DUPLICATE KEY UPDATE admin_name = VALUES(admin_name)]])
end)

-- Editor de mover (c_move.lua): todo recurso de WORLD_TYPES exporta adminMove y rechaza un id que no existe
test("admin_exports_mover", function(t)
    for _, o in ipairs(OWNERS) do
        local res = getResourceFromName(o[1])
        if not res or getResourceState(res) ~= "running" then return t.fail(o[1] .. " no esta running") end
        local ok, done = pcall(call, res, "adminMove", 987654321, o[2], 0, 0, 3, 0)
        if not ok then return t.fail(o[1] .. " no exporta adminMove") end
        if done ~= false then return t.fail(o[1] .. ":adminMove de un id inexistente no devolvio false") end
    end
    t.pass(("%d tipos con adminMove"):format(#OWNERS))
end)

-- Marcadores movibles (rp_markers/s_points.lua): tabla marker_points y placePoint sin movimiento
test("admin_marcadores_movibles", function(t)
    local res = getResourceFromName("rp_markers")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_markers no esta running") end
    local x, y, z = exports.rp_markers:placePoint("rptest_punto", 1, 2, 3)
    if x ~= 1 or y ~= 2 or z ~= 3 then return t.fail("placePoint cambio un punto que nadie movio") end
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("marker_points accesible")
    end, "SELECT id, marker_key, base_x, x FROM marker_points LIMIT 1")
end)

test("relojflores_tabla", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass(("flower_clocks accesible (%d relojes)"):format(#rows))
    end, "SELECT id, x, y, z, rot, interior, dimension FROM flower_clocks")
end)

-- #110: anti-spam de comandos y eventos remotos (rp_admin/s_antispam.lua)
test("admin_antispam_activo", function(t)
    local ok, n = pcall(function() return exports.rp_admin:getSpamStrikes(root) end)
    if not ok or n ~= 0 then return t.fail("getSpamStrikes no responde 0 para un no-jugador") end
    local interval = tonumber(getServerConfigSetting("player_triggered_event_interval"))
    local max = tonumber(getServerConfigSetting("max_player_triggered_events_per_interval"))
    if not interval or not max or max <= 0 then return t.fail("falta el límite de eventos de MTA en mtaserver.conf") end
    t.pass(("anti-spam en marcha; límite MTA %d eventos / %d ms"):format(max, interval))
end)
