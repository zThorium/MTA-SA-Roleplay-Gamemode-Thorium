--[[
    rp_test / s_tests_npcrel.lua
    Pruebas de humo de rp_npcrel: el banco de dialogos cubre todas las acciones y
    etapas, y ninguna frase deja marcas ({n}, {p}, {o}, {e}) sin sustituir.
]]

test("npcrel_banco_de_dialogos", function(t)
    local res = getResourceFromName("rp_npcrel")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_npcrel no está running") end
    local s = exports.rp_npcrel:getDialogueStats()
    if type(s) ~= "table" then return t.fail("sin estadísticas") end
    if #s.missing > 0 then return t.fail("faltan grupos: " .. table.concat(s.missing, ", ")) end
    if s.leftovers > 0 then return t.fail(s.leftovers .. " frases con marcas sin sustituir") end
    if s.lines < 250 then return t.fail("pocas frases: " .. tostring(s.lines)) end
    t.pass(s.lines .. " frases")
end)
