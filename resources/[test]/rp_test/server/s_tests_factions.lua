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

-- #107: radio de facción, canal de departamentos y megáfono registrados en rp_chat
test("fac_radio_comandos", function(t)
    local res = getResourceFromName("rp_chat")
    if not res or getResourceState(res) ~= "running" then return t.fail("rp_chat no esta running") end
    local have = {}
    for _, c in ipairs(getCommandHandlers(res) or {}) do have[type(c) == "table" and c[1] or c] = true end
    for _, cmd in ipairs({ "r", "d", "meg", "megafono" }) do
        if not have[cmd] then return t.fail("falta el comando /" .. cmd) end
    end
    t.pass("/r, /d, /meg y /megafono")
end)
