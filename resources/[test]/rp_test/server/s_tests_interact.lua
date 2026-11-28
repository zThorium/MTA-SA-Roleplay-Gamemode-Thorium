--[[
    rp_test / s_tests_interact.lua
    Pruebas de humo de rp_interact: cada opción que puede salir en el menú tiene quien la
    ejecute, cada propuesta tiene su aceptación, y rp_police expone sus acciones.
]]

local function runningRes(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

test("interact_acciones_con_manejador", function(t)
    if not runningRes("rp_interact") then return t.fail("rp_interact no está running") end
    local c = exports.rp_interact:getActionIds()
    if type(c) ~= "table" then return t.fail("sin catálogo") end
    local have = {}
    for _, id in ipairs(c.actions) do have[id] = true end
    -- Lo que buildMenu puede ofrecer (salvo "report", que lo resuelve el cliente, y "pol:*", que va a rp_police)
    local menu = { "greet", "handshake", "gang", "kiss", "show_dni", "show_license", "give_money", "give_item",
        "help_up", "invite_car", "frisk", "examine", "med_revive", "fac_invite",
        "adm_check", "adm_recon", "adm_goto", "adm_get", "adm_freeze", "adm_heal" }
    local missing = {}
    for _, id in ipairs(menu) do if not have[id] then missing[#missing + 1] = id end end
    if #missing > 0 then return t.fail("sin manejador: " .. table.concat(missing, ", ")) end
    local accepts = {}
    for _, k in ipairs(c.accepts) do accepts[k] = true end
    for _, k in ipairs({ "gesture", "item", "car", "frisk" }) do
        if not accepts[k] then return t.fail("propuesta sin aceptación: " .. k) end
    end
    for key, g in pairs(c.gestures) do
        if not (g.me and g.them and g.me[1] and g.them[2] and tonumber(g.gap) and tonumber(g.ms)) then
            return t.fail("gesto mal definido: " .. key)
        end
    end
    t.pass(#c.actions .. " acciones, " .. #c.accepts .. " propuestas")
end)

test("interact_exports_policia", function(t)
    if not runningRes("rp_police") then return t.fail("rp_police no está running") end
    -- Sin jugadores reales: deben responder false sin romper
    local ok, res = pcall(function() return exports.rp_police:getPlayerActions(root, root) end)
    if not ok then return t.fail("getPlayerActions falló: " .. tostring(res)) end
    if res ~= false then return t.fail("getPlayerActions debía devolver false con objetivos no válidos") end
    local ok2, res2 = pcall(function() return exports.rp_police:doPlayerAction(root, root, "cuff") end)
    if not ok2 then return t.fail("doPlayerAction falló: " .. tostring(res2)) end
    if res2 ~= false then return t.fail("doPlayerAction debía devolver false") end
    t.pass("exports de rp_police responden")
end)

-- Descripciones de rol (rp_chat: /yo, /descveh, /desccasa, /examinar)
test("descripciones_guardar_y_leer", function(t)
    if not runningRes("rp_chat") then return t.fail("rp_chat no está running") end
    if exports.rp_chat:examinePlayer(false, false) ~= false then return t.fail("examinePlayer sin personaje debería dar false") end
    local REF = 4294967000   -- ref_id que ningún personaje real usa
    local upsert = "INSERT INTO descriptions (kind, ref_id, text) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE text = VALUES(text)"
    query(function(r1, _, _, c1, m1)
        if not r1 then return t.fail(("insertar: [%s] %s"):format(tostring(c1), tostring(m1))) end
        query(function()
            query(function(rows)
                local text = rows and rows[1] and rows[1].text
                query(function() end, "DELETE FROM descriptions WHERE kind = 'character' AND ref_id = ?", REF)
                if text ~= "Cicatriz en la ceja" then return t.fail("se leyó " .. tostring(text)) end
                t.pass("upsert y lectura por (kind, ref_id)")
            end, "SELECT text FROM descriptions WHERE kind = 'character' AND ref_id = ?", REF)
        end, upsert, "character", REF, "Cicatriz en la ceja")
    end, upsert, "character", REF, "Tatuaje")
end)
