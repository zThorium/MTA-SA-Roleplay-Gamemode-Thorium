-- rp_shootingrange: pruebas de humo (recurso, tabla weapon_skills y niveles)

test("shootingrange_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_shootingrange")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_shootingrange no esta running") end
    t.pass()
end)

test("shootingrange_tabla_existe", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("weapon_skills accesible")
    end, "SELECT COUNT(*) AS n FROM weapon_skills")
end)

-- Historial de sesiones (graficas de progreso) y consulta del tope diario
test("shootingrange_historial_existe", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("range_sessions accesible (tope diario: " .. tostring(rows[1] and rows[1].g) .. ")")
    end, [[SELECT COALESCE(SUM(GREATEST(CAST(skill_after AS SIGNED) - CAST(skill_before AS SIGNED), 0)), 0) AS g
           FROM range_sessions WHERE created_at >= NOW() - INTERVAL 1 DAY]])
end)
