--[[
    rp_phone / c_messages.lua
    Puente de la app Mensajes (html/messages.js) con el servidor (server/s_messages.lua).
    JS -> mta.triggerEvent("rp:phone:ui:sms", accion, ...); Servidor -> rp:sms:<evento> ->
    RP.sms.on("<evento>", [args]). Con el telefono cerrado, un SMS nuevo sale como aviso.
]]

addEvent("rp:phone:ui:sms", false)

local SERVER_EVENTS = { "list", "chat", "message", "read", "badge", "failed" }

local function toJS(name, ...)
    if not Phone.isOpen() then return false end
    local args = {}
    for i = 1, select("#", ...) do args[i] = Phone.encode((select(i, ...))) end
    Phone.callJS(("window.RP && RP.sms && RP.sms.on(%s, [%s])"):format(Phone.encodeString(name), table.concat(args, ",")))
    return true
end

for _, name in ipairs(SERVER_EVENTS) do
    addEvent("rp:sms:" .. name, true)
    addEventHandler("rp:sms:" .. name, resourceRoot, function(...)
        if toJS(name, ...) then return end
        if name == "message" then
            local _, msg = ...
            if type(msg) == "table" and not msg.mine and msg.hasPhone ~= false then
                exports.rp_notify:notify(("💬 %s: %s"):format(tostring(msg.name or "Mensaje"), tostring(msg.body or "")), "info")
                playSoundFrontEnd(12)
            end
        end
    end)
end

local function number(v) v = tostring(v or ""):gsub("%D", "") return #v >= 3 and #v <= 7 and v or nil end

local ACTIONS = {
    list = function() triggerServerEvent("rp:sms:list:get", resourceRoot) end,
    badge = function() triggerServerEvent("rp:sms:badge:get", resourceRoot) end,
    open = function(n) if number(n) then triggerServerEvent("rp:sms:chat:open", resourceRoot, number(n)) end end,
    send = function(n, text)
        if number(n) and type(text) == "string" and #text <= 2000 then triggerServerEvent("rp:sms:send", resourceRoot, number(n), text) end
    end,
    delete = function(n) if number(n) then triggerServerEvent("rp:sms:delete", resourceRoot, number(n)) end end,
}

addEventHandler("rp:phone:ui:sms", root, function(action, ...)
    local fn = ACTIONS[action]
    if fn then fn(...) end
end)
