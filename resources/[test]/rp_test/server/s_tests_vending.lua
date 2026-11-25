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

-- Cada producto de las maquinas es un item real del inventario y tiene precio entero > 0
test("vending_productos_son_items", function(t)
    local ok, cfg = pcall(function() return exports.rp_vending:getVendingTypes() end)
    if not ok or type(cfg) ~= "table" then return t.fail("rp_vending no exporta getVendingTypes") end
    local bad, n = {}, 0
    for kind, def in pairs(cfg) do
        for _, p in ipairs(def.products or {}) do
            n = n + 1
            if not exports.rp_inventory:getItemDefinition(p.item) then bad[#bad + 1] = kind .. ":" .. tostring(p.item) .. " (no existe)" end
            if type(p.price) ~= "number" or p.price < 1 or p.price ~= math.floor(p.price) then bad[#bad + 1] = kind .. ":" .. tostring(p.item) .. " (precio)" end
        end
    end
    if #bad > 0 then return t.fail(table.concat(bad, ", ")) end
    t.pass(n .. " productos validos")
end)
