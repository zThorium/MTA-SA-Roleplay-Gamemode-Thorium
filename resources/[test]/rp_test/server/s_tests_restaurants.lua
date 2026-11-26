-- rp_restaurants: pruebas de humo (recurso en marcha y config coherente)

test("restaurants_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_restaurants")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_restaurants no esta running") end
    t.pass()
end)

-- El export responde y no marca como comiendo a quien no lo esta
test("restaurants_export_isPlayerEating", function(t)
    local res = getResourceFromName("rp_restaurants")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_restaurants no esta running") end
    local ok, eating = pcall(function() return exports.rp_restaurants:isPlayerEating(root) end)
    if not ok then return t.fail("rp_restaurants no exporta isPlayerEating") end
    if eating ~= false then return t.fail("isPlayerEating(root) deberia ser false") end
    t.pass()
end)
