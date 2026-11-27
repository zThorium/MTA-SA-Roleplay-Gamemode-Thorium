--[[
    rp_test / s_tests_mapeditor.lua
    Pruebas de humo de rp_mapeditor: tablas y borrado en cascada, reglas de validación,
    ida y vuelta de .map y exports de mapas publicados.
]]

test("mapeditor_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_mapeditor")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_mapeditor no esta running") end
    t.pass()
end)

test("mapeditor_proyecto_elemento_version_y_cascada", function(t, ctx)
    local name = "rptest_mapa_" .. getTickCount()
    query(function(rows, _, pid, code, msg)
        if not rows or not pid or pid == 0 then return t.fail(("proyecto: [%s] %s"):format(tostring(code), tostring(msg))) end
        query(function(r2, _, eid)
            if not r2 or not eid or eid == 0 then
                query(function() end, "DELETE FROM mapedit_projects WHERE id = ?", pid)
                return t.fail("no se inserto el elemento")
            end
            query(function(r3, _, vid)
                if not r3 or not vid or vid == 0 then
                    query(function() end, "DELETE FROM mapedit_projects WHERE id = ?", pid)
                    return t.fail("no se inserto la version")
                end
                query(function(_, affected)
                    if affected ~= 1 then return t.fail("no se borro el proyecto") end
                    query(function(r4)
                        local left = r4 and r4[1] and tonumber(r4[1].n)
                        if left ~= 0 then return t.fail(tostring(left) .. " filas huerfanas tras borrar el proyecto") end
                        t.pass("proyecto, elemento y version borrados en cascada")
                    end, [[SELECT (SELECT COUNT(*) FROM mapedit_elements WHERE project_id = ?)
                                + (SELECT COUNT(*) FROM mapedit_versions WHERE project_id = ?) AS n]], pid, pid)
                end, "DELETE FROM mapedit_projects WHERE id = ?", pid)
            end, "INSERT INTO mapedit_versions (project_id, version, snapshot, element_count, published_by) VALUES (?, 1, '{}', 1, 'rptest')", pid)
        end, "INSERT INTO mapedit_elements (project_id, etype, model, x, y, z, props) VALUES (?, 'object', 1337, 0, 0, 3, '{}')", pid)
    end, "INSERT INTO mapedit_projects (name, created_name, updated_name) VALUES (?, 'rptest', 'rptest')", name)
end)

test("mapeditor_validacion_de_elementos", function(t)
    local me = exports.rp_mapeditor
    local ok = me:validateMapElement({ etype = "object", model = 1337, x = 10, y = 20, z = 5, rz = 450, props = { scale = 99, alpha = 300 } })
    if type(ok) ~= "table" then return t.fail("rechazo un objeto valido") end
    if ok.rz ~= 90 then return t.fail("no normalizo el giro (" .. tostring(ok.rz) .. ")") end
    if not ok.props.scale or ok.props.scale[1] ~= 20 then return t.fail("no acoto la escala") end
    if ok.props.alpha ~= nil and ok.props.alpha > 255 then return t.fail("no acoto la opacidad") end
    local cases = {
        { "modelo inexistente", { etype = "object", model = 19999, x = 0, y = 0, z = 0 } },
        { "fuera del mapa", { etype = "object", model = 1337, x = 99999, y = 0, z = 0 } },
        { "tipo desconocido", { etype = "bomba", model = 1337, x = 0, y = 0, z = 0 } },
        { "vehiculo invalido", { etype = "vehicle", model = 1337, x = 0, y = 0, z = 0 } },
        { "posicion NaN", { etype = "point", x = 0 / 0, y = 0, z = 0 } },
    }
    for _, c in ipairs(cases) do
        local r = me:validateMapElement(c[2])
        if r then return t.fail("acepto: " .. c[1]) end
    end
    t.pass(#cases .. " casos invalidos rechazados")
end)

test("mapeditor_ida_y_vuelta_map", function(t)
    local me = exports.rp_mapeditor
    local rows = {
        { etype = "object", model = 1337, x = 1.5, y = 2.25, z = 3, rx = 0, ry = 0, rz = 90, props = { scale = { 2, 2, 2 }, ds = true } },
        { etype = "vehicle", model = 411, x = 10, y = 10, z = 3, rx = 0, ry = 0, rz = 180, props = { plate = "THORIUM", color = { 255, 0, 0, 0, 0, 255 } } },
        { etype = "ped", model = 7, x = 5, y = 5, z = 3, rx = 0, ry = 0, rz = 45, props = { block = "ped", anim = "SEAT_idle" } },
        { etype = "marker", model = 0, x = 0, y = 0, z = 3, rx = 0, ry = 0, rz = 0, props = { mtype = "cylinder", size = 2, color = { 255, 200, 60, 160 } } },
        { etype = "pickup", model = 0, x = 1, y = 1, z = 3, rx = 0, ry = 0, rz = 0, props = { ptype = 2, amount = 22, ammo = 30, respawn = 5000 } },
        { etype = "point", model = 0, x = 2, y = 2, z = 3, rx = 0, ry = 0, rz = 10, props = { name = "salida" } },
        { etype = "removal", model = 1226, x = 3, y = 3, z = 3, rx = 0, ry = 0, rz = 0, props = { radius = 2, lod = 0 } },
    }
    local text = me:rowsToMapFile(rows, 0, 0)
    if type(text) ~= "string" or not text:find("<map") then return t.fail("no genero el .map") end
    local back, bad = me:parseMapFile(text)
    if type(back) ~= "table" then return t.fail("no lo pudo leer: " .. tostring(bad)) end
    if #back ~= #rows then return t.fail(("vuelven %d de %d elementos (%s descartados)"):format(#back, #rows, tostring(bad))) end
    local byType = {}
    for _, r in ipairs(back) do byType[r.etype] = r end
    local o, v, pk = byType.object, byType.vehicle, byType.pickup
    if not o or o.rz ~= 90 or not o.props.scale or o.props.scale[1] ~= 2 or not o.props.ds then return t.fail("el objeto no conserva giro, escala o doble cara") end
    if not v or v.props.plate ~= "THORIUM" or v.props.color[1] ~= 255 then return t.fail("el vehiculo no conserva matricula o color") end
    if not pk or pk.props.ptype ~= 2 or pk.props.amount ~= 22 or pk.props.ammo ~= 30 then return t.fail("el pickup de arma no conserva arma o municion") end
    if not byType.removal or byType.removal.props.radius ~= 2 then return t.fail("el quitado no conserva el radio") end
    if not byType.point or byType.point.props.name ~= "salida" then return t.fail("el punto no conserva el nombre") end
    t.pass("7 tipos exportados e importados sin perdidas")
end)

test("mapeditor_exports_de_mapas_publicados", function(t)
    local me = exports.rp_mapeditor
    local list = me:getPublishedMaps()
    if type(list) ~= "table" then return t.fail("getPublishedMaps no devuelve tabla") end
    if me:isMapPublished("rptest_no_existe") then return t.fail("isMapPublished da true a un mapa inexistente") end
    local pts = me:getMapPoints("rptest_no_existe")
    if type(pts) ~= "table" or #pts ~= 0 then return t.fail("getMapPoints de un mapa inexistente no esta vacio") end
    t.pass(#list .. " mapas publicados")
end)
