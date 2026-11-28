--[[
    rp_test / s_tests_carwash.lua
    Pruebas de humo de rp_carwash: el recurso corre, hay marcador de lavado y setVehicleDirt limita a 0..1.
]]

test("carwash_recurso_y_marcador", function(t)
    local res = getResourceFromName("rp_carwash")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_carwash no está running") end
    local n = #getElementsByType("marker", getResourceDynamicElementRoot(res))
    if n < 1 then return t.fail("no hay marcadores de lavado") end
    t.pass(n .. " lavado(s)")
end)

test("carwash_suciedad_se_limita", function(t)
    local v = createVehicle(410, 0, 0, -50)
    if not v then return t.fail("no se pudo crear el vehículo") end
    local ok = exports.rp_carwash:setVehicleDirt(v, 5)
    local hi = exports.rp_carwash:getVehicleDirt(v)
    exports.rp_carwash:setVehicleDirt(v, -3)
    local lo = exports.rp_carwash:getVehicleDirt(v)
    exports.rp_carwash:setVehicleDirt(v, 0.4)
    local mid = exports.rp_carwash:getVehicleDirt(v)
    destroyElement(v)
    if not ok or hi ~= 1 or lo ~= 0 or math.abs(mid - 0.4) > 0.001 then
        return t.fail(("ok=%s hi=%s lo=%s mid=%s"):format(tostring(ok), tostring(hi), tostring(lo), tostring(mid)))
    end
    t.pass()
end)
