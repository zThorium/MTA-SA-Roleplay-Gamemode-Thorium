--[[
    rp_test / s_tests_tinder.lua

    Tinder (rp_phone/server/s_tinder*.lua): catalogo (escenarios, poses, gustos, arquetipos),
    personas simuladas generadas con sus fotos planificadas, tablas nuevas y el motor de chat
    de los NPC (tinderSimulateReply no toca la BD).
]]

local function phoneRunning()
    local res = getResourceFromName("rp_phone")
    return res and getResourceState(res) == "running"
end

test("tinder_catalogo", function(t)
    if not phoneRunning() then return t.fail("rp_phone no está running") end
    local errors = exports.rp_phone:getTinderConfigErrors()
    if type(errors) ~= "table" then return t.fail("getTinderConfigErrors no responde") end
    if #errors > 0 then return t.fail(table.concat(errors, "; ")) end
    t.pass("arquetipos, escenarios, poses, gustos y barrios válidos")
end)

test("tinder_tablas", function(t)
    query(function(rows, _, _, code, msg)
        if not rows then return t.fail(("tablas de Tinder: [%s] %s"):format(tostring(code), tostring(msg))) end
        t.pass("tinder_npcs, tinder_npc_photos, tinder_npc_links, tinder_npc_messages, tinder_messages, tinder_profile_photos")
    end, [[
        SELECT (SELECT COUNT(*) FROM tinder_npcs) AS a, (SELECT COUNT(*) FROM tinder_npc_photos) AS b,
               (SELECT COUNT(*) FROM tinder_npc_links) AS c, (SELECT COUNT(*) FROM tinder_npc_messages) AS d,
               (SELECT COUNT(*) FROM tinder_messages) AS e, (SELECT COUNT(*) FROM tinder_profile_photos) AS f,
               (SELECT COUNT(*) FROM tinder_profiles WHERE gold_until IS NULL OR interests IS NOT NULL) AS g
    ]])
end)

test("tinder_npcs_con_fotos_planificadas", function(t)
    if not phoneRunning() then return t.fail("rp_phone no está running") end
    local count = exports.rp_phone:getTinderNpcCount()
    if (tonumber(count) or 0) < 30 then return t.fail("pocas personas simuladas cargadas: " .. tostring(count)) end
    query(function(rows)
        local r = rows and rows[1]
        if not r then return t.fail("no se pudo contar") end
        if tonumber(r.sin_fotos) > 0 then return t.fail(r.sin_fotos .. " NPC sin fotos planificadas") end
        t.pass(("%d personas, %s fotos (%s ya sacadas por el estudio)"):format(count, tostring(r.total), tostring(r.hechas)))
    end, [[
        SELECT (SELECT COUNT(*) FROM tinder_npcs n WHERE NOT EXISTS (SELECT 1 FROM tinder_npc_photos p WHERE p.npc_id = n.id)) AS sin_fotos,
               (SELECT COUNT(*) FROM tinder_npc_photos) AS total,
               (SELECT COUNT(*) FROM tinder_npc_photos WHERE image IS NOT NULL) AS hechas
    ]])
end)

test("tinder_chat_npc", function(t)
    if not phoneRunning() then return t.fail("rp_phone no está running") end
    local function reply(text, interest, exchanges)
        return exports.rp_phone:tinderSimulateReply(nil, text, interest, exchanges)
    end
    -- Pregunta normal: contesta algo y sin marcas sin sustituir
    local r = reply("hola! a que te dedicas?", 50, 2)
    if type(r) ~= "table" then return t.fail("tinderSimulateReply no responde") end
    if #r.bubbles == 0 then return t.fail("no contestó a una pregunta") end
    for _, b in ipairs(r.bubbles) do
        if b:find("{%a+}") then return t.fail("marca sin sustituir: " .. b) end
    end
    -- Groseria: se va
    local rude = reply("eres una idiota", 70, 4)
    if rude.state ~= "leaving" then return t.fail("una grosería no deshizo el match (estado " .. tostring(rude.state) .. ")") end
    -- Aburrido con interes bajo: ghost (visto sin respuesta)
    local boring = reply("ok", 13, 6)
    if boring.state ~= "ghost" or #boring.bubbles > 0 then return t.fail("con interés bajo debería ghostear") end
    -- Cita con interes alto: acepta
    local date = reply("te gustaria salir conmigo a tomar algo?", 85, 9)
    if date.interest <= 85 then return t.fail("aceptar una cita debería subir el interés") end
    t.pass(r.npc .. ": \"" .. r.bubbles[1] .. "\"")
end)
