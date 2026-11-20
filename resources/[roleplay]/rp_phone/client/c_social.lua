--[[
    rp_phone / c_social.lua
    Puente entre la app Fotogram (html/social.js) y el servidor (s_social.lua).
    CEF -> Lua: mta.triggerEvent("rp:phone:ui:social", accion, ...)
    Lua -> CEF: RP.social.<metodo>(datos)
    El cliente solo reenvia: el servidor valida todo.
]]

addEvent("rp:phone:ui:social", false)
addEvent("rp:phone:show", true)

-- Acciones que el telefono puede pedir y como se limpian sus argumentos
local function num(v) return tonumber(v) or 0 end
local function str(v, max) v = tostring(v or ""); return v:sub(1, max or 300) end

local ACTIONS = {
    feed          = function(mode, beforeId) return mode == "all" and "all" or "following", num(beforeId) end,
    image         = function(id) return num(id) end,
    like          = function(id) return num(id) end,
    deletePost    = function(id) return num(id) end,
    getPost       = function(id) return num(id) end,
    comments      = function(id, beforeId) return num(id), num(beforeId) end,
    comment       = function(id, text) return num(id), str(text, 400) end,
    deleteComment = function(id) return num(id) end,
    profile       = function(id) return num(id) end,
    editProfile   = function(username, bio) return str(username, 40), str(bio, 300) end,
    setAvatar     = function(id) return num(id) end,
    follow        = function(id, follow) return num(id), follow == true end,
    follows       = function(id, which) return num(id), which == "following" and "following" or "followers" end,
    search        = function(text) return str(text, 40) end,
    explore       = function() end,
    notifications = function() end,
}

addEventHandler("rp:phone:ui:social", root, function(action, ...)
    local clean = ACTIONS[action]
    if not clean then return end
    triggerServerEvent("rp:social:" .. action, resourceRoot, clean(...))
end)

-- Publicar: la foto ya viene editada (filtros) desde el telefono como JPEG en base64
addEvent("rp:phone:ui:socialPost", false)
addEventHandler("rp:phone:ui:socialPost", root, function(caption, image, filter)
    if type(image) ~= "string" or #image > FOTOGRAM.MAX_IMAGE then
        Phone.callJS("RP.social.posted(false)")
        return exports.rp_notify:notify("La foto es demasiado grande.", "error")
    end
    triggerLatentServerEvent("rp:social:post", 200000, false, resourceRoot, str(caption, 600), image, str(filter, 16))
end)

----------------------------------------------------------------
-- Servidor -> telefono
----------------------------------------------------------------
local function forward(event, method)
    addEvent(event, true)
    addEventHandler(event, resourceRoot, function(...)
        if not Phone.isOpen() then return end
        local args = { ... }
        local parts = {}
        for i = 1, select("#", ...) do
            local v = args[i]
            local t = type(v)
            if t == "string" then parts[i] = Phone.jsString(v)
            elseif t == "number" or t == "boolean" then parts[i] = tostring(v)
            elseif t == "table" then parts[i] = Phone.json(v)
            else parts[i] = "null" end
        end
        Phone.callJS(("RP.social.%s(%s)"):format(method, table.concat(parts, ",")))
    end)
end

forward("rp:social:me", "me")
forward("rp:social:feed", "feed")
forward("rp:social:image", "image")
forward("rp:social:posted", "posted")
forward("rp:social:likeState", "likeState")
forward("rp:social:postDeleted", "postDeleted")
forward("rp:social:post", "post")
forward("rp:social:comments", "comments")
forward("rp:social:profile", "profile")
forward("rp:social:followState", "followState")
forward("rp:social:follows", "follows")
forward("rp:social:search", "search")
forward("rp:social:explore", "explore")
forward("rp:social:notifications", "notifications")
forward("rp:social:badge", "badge")

-- Al abrir el telefono se pide el perfil propio (crea el @usuario la primera vez) y el contador
addEventHandler("rp:phone:show", resourceRoot, function()
    triggerServerEvent("rp:social:open", resourceRoot)
end)
