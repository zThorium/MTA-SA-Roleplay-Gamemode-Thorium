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
        "help_up", "invite_car", "frisk", "med_revive", "fac_invite",
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
