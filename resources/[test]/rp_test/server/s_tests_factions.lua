--[[
    rp_test / s_tests_factions.lua
    API central de rp_factions: la consultan todos los recursos para saber de facciones.
]]

test("fac_api_exports", function(t)
    local names = { "isPlayerInFaction", "isPlayerOnDuty", "getPlayerFactionId", "getPlayerFactionType",
        "isPlayerFactionLeader", "getPlayerFactionInfo", "getFactionInfo", "getFactions", "getFactionPlayers",
        "getCharacterFaction", "getPlayerFaction" }
    for _, n in ipairs(names) do
        local ok = pcall(function() return exports.rp_factions[n](exports.rp_factions, root) end)
        if not ok then return t.fail("export que falla: " .. n) end
    end
    t.pass(#names .. " exports responden")
end)

-- El esquema crea la facción 1 como policía: la API la encuentra por id y por tipo
test("fac_api_policia_por_tipo", function(t)
    local info = exports.rp_factions:getFactionInfo(1)
    if type(info) ~= "table" or info.type ~= "policia" then return t.fail("la facción 1 no es de tipo policia") end
    local list = exports.rp_factions:getFactions("policia")
    for _, f in ipairs(list) do
        if f.id == 1 then return t.pass(("%d facciones de policía"):format(#list)) end
    end
    t.fail("getFactions('policia') no incluye la facción 1")
end)

-- Sin facción no se pertenece a nada (root no es un jugador)
test("fac_api_sin_faccion", function(t)
    local f = exports.rp_factions
    if f:isPlayerInFaction(root) or f:isPlayerInFaction(root, "policia") or f:isPlayerOnDuty(root, "policia")
        or f:getPlayerFactionId(root) or f:getPlayerFactionInfo(root) or f:getCharacterFaction(0) then
        return t.fail("un elemento sin facción aparece como miembro")
    end
    if type(f:getFactionPlayers("policia")) ~= "table" then return t.fail("getFactionPlayers no devuelve lista") end
    t.pass()
end)

-- #102: los tipos que usan los sistemas nuevos existen y son válidos (nombre, color #rrggbb,
-- clave que cabe en factions.type VARCHAR(16) y, si hay servicio, duty + dutyData)
test("fac_tipos_registrados", function(t)
    local types = exports.rp_factions:getFactionTypes()
    if type(types) ~= "table" then return t.fail("getFactionTypes no devuelve una tabla") end
    local needed = { "gobierno", "policia", "medicos", "bomberos", "empresa", "banda", "otra",
        "mecanicos", "noticias", "transporte", "logistica", "seguros", "seguridad", "concesionaria", "mafia" }
    for _, k in ipairs(needed) do
        if not types[k] then return t.fail("falta el tipo " .. k) end
    end
    for k, ty in pairs(types) do
        if #k > 16 then return t.fail(k .. ": clave de más de 16 caracteres") end
        if type(ty.name) ~= "string" or ty.name == "" then return t.fail(k .. ": sin nombre") end
        if type(ty.color) ~= "string" or not ty.color:match("^#%x%x%x%x%x%x$") then return t.fail(k .. ": color no es #rrggbb") end
        if (ty.duty ~= nil) ~= (ty.dutyData ~= nil) then return t.fail(k .. ": duty y dutyData van juntos") end
    end
    t.pass(#needed .. " tipos válidos")
end)
