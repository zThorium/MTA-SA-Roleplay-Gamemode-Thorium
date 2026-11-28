--[[
    rp_test / s_tests_pronto.lua
    Pruebas de humo de rp_pronto: el recurso corre, quita la gasolinera original (laepetrol1a y su LOD), tiene muebles
    para el interior y la puerta queda fuera de la tienda, del lado de los surtidores.
]]

test("pronto_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_pronto")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_pronto no está running") end
    t.pass()
end)

test("pronto_quita_gasolinera_y_tiene_muebles", function(t)
    local info = exports.rp_pronto:getStationInfo()
    if type(info) ~= "table" then return t.fail("getStationInfo no devolvió tabla") end
    if (info.removed or 0) < 2 then return t.fail("faltan modelos originales por quitar: " .. tostring(info.removed)) end
    if (info.props or 0) < 10 then return t.fail("el interior tiene pocos muebles: " .. tostring(info.props)) end
    t.pass(("%d quitados, %d muebles"):format(info.removed, info.props))
end)

test("pronto_puerta_fuera_de_la_tienda", function(t)
    local info = exports.rp_pronto:getStationInfo()
    local b, d = info.shopBox, info.door
    if d[1] >= b[1] and d[1] <= b[4] and d[2] >= b[2] and d[2] <= b[5] then
        return t.fail("el punto de la puerta queda dentro de la tienda")
    end
    if d[1] < b[4] then return t.fail("la puerta no está en la fachada este (hacia los surtidores)") end
    t.pass(("%.1f m delante de la fachada"):format(d[1] - b[4]))
end)
