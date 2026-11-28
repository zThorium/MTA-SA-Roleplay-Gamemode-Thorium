--[[
    rp_test / s_tests_ballistics.lua
    Pruebas de rp_ballistics: tiro en la cabeza mata siempre y al cuerpo cada calibre mata en sus balas.
]]

local function shotsToKill(weapon, health, armor)
    for n = 1, 20 do
        local kill
        kill, health, armor = exports.rp_ballistics:computeHit(weapon, 3, health, armor)
        if kill then return n end
    end
end

test("ballistics_cabeza_instantanea", function(t)
    for _, w in ipairs({ 22, 28, 31, 24, 34 }) do
        if not exports.rp_ballistics:computeHit(w, 9, 200, 100) then return t.fail("arma " .. w .. " no mata a la cabeza") end
    end
    t.pass()
end)

test("ballistics_balas_por_calibre", function(t)
    local want = { [22] = 5, [32] = 5, [29] = 4, [31] = 3, [30] = 2, [24] = 1, [25] = 1, [34] = 1 }
    for w, n in pairs(want) do
        local got = shotsToKill(w, 100, 0)
        if got ~= n then return t.fail(("arma %d: %s balas, se esperaban %d"):format(w, tostring(got), n)) end
    end
    if exports.rp_ballistics:computeHit(0, 9, 100, 0) then return t.fail("los puños no deben matar a la cabeza") end
    t.pass()
end)

test("ballistics_chaleco_absorbe", function(t)
    local got = shotsToKill(24, 100, 100)
    if got ~= 2 then return t.fail("Desert Eagle contra 100 de chaleco: " .. tostring(got) .. " balas, se esperaban 2") end
    t.pass()
end)
