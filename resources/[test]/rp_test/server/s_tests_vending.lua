-- rp_vending: pruebas de humo (recurso en marcha, tabla y config)

test("vending_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_vending")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_vending no esta running") end
    t.pass()
end)

test("vending_tabla_existe", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("vending_machines accesible")
    end, "SELECT COUNT(*) AS n FROM vending_machines")
end)
