--[[
    rp_phone / c_gallery.lua
    Puente entre la app Galeria (html/gallery.js) y el servidor (s_gallery.lua).
    El cliente solo reenvia: el servidor valida todo.
]]

addEvent("rp:phone:ui:gallery", false)
addEvent("rp:gallery:list", true)
addEvent("rp:gallery:saved", true)
addEvent("rp:gallery:image", true)
addEvent("rp:gallery:deleted", true)

addEventHandler("rp:phone:ui:gallery", root, function(action, arg)
    if action == "list" then triggerServerEvent("rp:gallery:list", resourceRoot)
    elseif action == "get" then triggerServerEvent("rp:gallery:get", resourceRoot, tonumber(arg) or 0)
    elseif action == "delete" then triggerServerEvent("rp:gallery:delete", resourceRoot, tonumber(arg) or 0)
    elseif action == "save" then
        if type(arg) ~= "string" or #arg > FOTOGRAM.MAX_IMAGE then
            return exports.rp_notify:notify("La foto es demasiado grande.", "error")
        end
        triggerLatentServerEvent("rp:gallery:save", 200000, false, resourceRoot, arg)
    end
end)

local function forward(event, method, ...)
    addEventHandler(event, resourceRoot, function(a, b)
        if not Phone.isOpen() then return end
        Phone.callJS(("RP.gallery.%s(%s%s)"):format(method,
            type(a) == "table" and Phone.json(a) or tostring(tonumber(a) or 0),
            b and ("," .. Phone.jsString(b)) or ""))
    end)
end

forward("rp:gallery:list", "list")
forward("rp:gallery:saved", "saved")
forward("rp:gallery:image", "image")
forward("rp:gallery:deleted", "deleted")
