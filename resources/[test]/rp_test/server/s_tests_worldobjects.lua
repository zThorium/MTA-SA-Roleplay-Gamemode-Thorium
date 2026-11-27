--[[
    rp_test / s_tests_worldobjects.lua
    Pruebas de humo de rp_worldobjects: el indice de objetos del mapa se construye y la
    cuadricula encuentra objetos conocidos.
]]

test("worldobjects_indice_del_mapa", function(t)
    local res = getResourceFromName("rp_worldobjects")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_worldobjects no está running") end
    local s = exports.rp_worldobjects:getWorldObjectStats()
    if type(s) ~= "table" then return t.fail("sin estadísticas") end
    if s.objects < 900 then return t.fail("objetos: " .. tostring(s.objects)) end
    if s.seats < s.objects then return t.fail("plazas: " .. tostring(s.seats)) end
    if s.nearTest < 1 then return t.fail("la cuadrícula no encuentra las bancas de prueba") end
    if exports.rp_worldobjects:isPlayerSeated(root) ~= false then return t.fail("isPlayerSeated con no-jugador") end
    t.pass(("%d objetos, %d plazas, %d modelos"):format(s.objects, s.seats, s.models))
end)
