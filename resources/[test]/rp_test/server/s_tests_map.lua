--[[
    rp_test / s_tests_map.lua
    Pruebas de humo de rp_map: tablas, siembra de categorias y lugares, cuadricula y
    exploracion guardada en hexadecimal (ida y vuelta por la BD).
]]

test("map_recurso_en_marcha", function(t)
    local res = getResourceFromName("rp_map")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_map no está running") end
    local stats = exports.rp_map:getMapStats()
    if type(stats) ~= "table" or not stats.ready then return t.fail("rp_map no terminó de cargar") end
    if stats.sectors ~= 144 then return t.fail("sectores: " .. tostring(stats.sectors)) end
    if stats.landCells < 9000 or stats.landCells > 14400 then return t.fail("celdas de tierra: " .. tostring(stats.landCells)) end
    if stats.categories < 19 then return t.fail("categorías sembradas: " .. tostring(stats.categories)) end
    if stats.places < 40 then return t.fail("lugares: " .. tostring(stats.places)) end
    t.pass(("%d lugares, %d categorías, %d celdas de tierra"):format(stats.places, stats.categories, stats.landCells))
end)

test("map_tablas_existen", function(t)
    local tables = { "map_exploration", "map_markers", "map_prefs", "map_categories", "map_places", "map_sectors", "map_settings" }
    local pending = #tables
    for _, name in ipairs(tables) do
        query(function(rows, _, _, code, msg)
            if not rows then return t.fail(name .. ": [" .. tostring(code) .. "] " .. tostring(msg)) end
            pending = pending - 1
            if pending == 0 then t.pass("7 tablas accesibles") end
        end, "SELECT COUNT(*) AS n FROM " .. name)
    end
end)

-- La exploracion se guarda como texto hexadecimal (4 celdas por letra) en map_exploration.cells
test("map_exploracion_hex_en_bd", function(t)
    local cells = { [1] = true, [5] = true, [14400] = true }
    local hex = ""
    for g = 0, 3599 do
        local v = 0
        for k = 1, 4 do v = v * 2 + (cells[g * 4 + k] and 1 or 0) end
        hex = hex .. ("0123456789abcdef"):sub(v + 1, v + 1)
    end
    if #hex ~= 3600 or hex:sub(1, 2) ~= "88" or hex:sub(-1) ~= "1" then return t.fail("codificación inesperada: " .. hex:sub(1, 4) .. "..." .. hex:sub(-2)) end
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("[%s] %s"):format(tostring(code), tostring(msg))) end
        if not rows[1] then return t.pass("omitida: no hay personajes sin exploración en la BD de prueba") end
        local cid = rows[1].id
        query(function(ok)
            if not ok then return t.fail("no se pudo guardar la exploración") end
            query(function(rows2)
                local back = rows2 and rows2[1] and rows2[1].cells
                query(function() end, "DELETE FROM map_exploration WHERE character_id = ? AND explored = 9999", cid)
                if back ~= hex then return t.fail("la exploración no vuelve igual de la BD") end
                t.pass("3600 letras ida y vuelta")
            end, "SELECT cells FROM map_exploration WHERE character_id = ?", cid)
        end, "INSERT INTO map_exploration (character_id, cells, explored) VALUES (?, ?, 9999) ON DUPLICATE KEY UPDATE character_id = character_id", cid, hex)
    end, "SELECT c.id FROM characters c LEFT JOIN map_exploration e ON e.character_id = c.id WHERE e.character_id IS NULL LIMIT 1")
end)
