--[[
    rp_test / s_tests_turbus.lua
    Pruebas de humo de rp_turbus: el recurso corre, quita el edificio original y pone sus props, y el primer
    punto de aparición (rp_characters SPAWN.DEFAULT, Unity) queda fuera del hall de vidrio.
]]

test("turbus_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_turbus")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_turbus no está running") end
    t.pass()
end)

test("turbus_quita_estacion_y_pone_props", function(t)
    local info = exports.rp_turbus:getTerminalInfo()
    if type(info) ~= "table" then return t.fail("getTerminalInfo no devolvió tabla") end
    if (info.removed or 0) < 4 then return t.fail("faltan modelos originales por quitar: " .. tostring(info.removed)) end
    if (info.props or 0) < 1 then return t.fail("no se crearon props") end
    t.pass(("%d quitados, %d props"):format(info.removed, info.props))
end)

-- Copia de SPAWN.DEFAULT de rp_characters/server/s_config.lua (no es exportable)
local SPAWN_UNITY = { 1742.9, -1861.6, 13.58 }

test("turbus_spawn_fuera_del_hall", function(t)
    local b = exports.rp_turbus:getTerminalInfo().hallBox
    local x, y = SPAWN_UNITY[1], SPAWN_UNITY[2]
    if x >= b[1] and x <= b[4] and y >= b[2] and y <= b[5] then
        return t.fail("el punto de aparición queda dentro del hall")
    end
    local dy = y - b[5]
    if dy < 2 then return t.fail(("el punto de aparición queda pegado a la cristalera (%.1f m)"):format(dy)) end
    t.pass(("%.1f m frente a la entrada"):format(dy))
end)
