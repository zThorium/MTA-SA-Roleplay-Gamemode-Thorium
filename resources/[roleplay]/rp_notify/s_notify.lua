--[[
    rp_notify / s_notify.lua
    Exports de servidor que reenvian la notificacion al cliente.

        exports.rp_notify:notify(player, "Texto", "success")
        exports.rp_notify:notify(root, "Aviso para todos", "warning")
        exports.rp_notify:popup(player, "Titulo", "Texto", "info")
        exports.rp_notify:bubble(player, elemento, "Texto del globo", 5000)
]]

local function valid(target)
    return target == root or (isElement(target) and getElementType(target) == "player")
end

function notify(target, text, kind, duration)
    if not valid(target) or type(text) ~= "string" then return false end
    return triggerClientEvent(target, "rp:notify", resourceRoot, text, kind, duration)
end

function popup(target, title, text, kind, duration)
    if not valid(target) then return false end
    return triggerClientEvent(target, "rp:notify:popup", resourceRoot, title, text, kind, duration)
end

function bubble(target, element, text, duration)
    if not valid(target) or not isElement(element) then return false end
    return triggerClientEvent(target, "rp:notify:bubble", resourceRoot, element, text, duration)
end
