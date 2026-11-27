--[[
    rp_test / s_tests_admin.lua
    Gramatica Owl de rp_admin (/nearby<x>, /del<x>...): cada recurso que registra
    WORLD_TYPES (rp_admin/s_world.lua) debe exponer adminElements y adminDelete con el
    formato esperado. adminDelete se prueba solo con un id que no existe (sin efectos).
]]

local OWNERS = {
    { "rp_bank" }, { "rp_shops" }, { "rp_properties" }, { "rp_clothing" }, { "rp_vending" },
    { "rp_dealers" }, { "rp_robbery" }, { "rp_gym", "machine" }, { "rp_gym", "trainer" },
    { "rp_driving" }, { "rp_pool" }, { "rp_train" }, { "rp_train", "booth" }, { "rp_train", "sign" }, { "rp_train", "gate" }, { "rp_train", "fence" },
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
