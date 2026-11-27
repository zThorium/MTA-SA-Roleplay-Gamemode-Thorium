--[[
    rp_phone / c_tinder.lua
    Puente entre la app Tinder (html/tinder.js) y el servidor (server/s_tinder*.lua).
    JS -> mta.triggerEvent("rp:phone:ui:tinder", accion, ...) -> aqui se valida el tipo y se
    reenvia al servidor. Servidor -> rp:tinder:<evento> -> RP.tinder.on("<evento>", datos).
    Con el telefono cerrado, los mensajes nuevos salen como aviso (rp_notify).
]]

addEvent("rp:phone:ui:tinder", false)

local SERVER_EVENTS = {
    "profile", "deck", "card", "rewound", "quota", "outOfLikes", "needGold", "match", "matches",
    "chat", "message", "typing", "read", "unmatched", "likes", "badge",
}

--[[
    JSON propio: el toJSON de MTA falla con textos de mas de 65535 caracteres
    ("Invalid string specified") y las fotos en base64 los superan.
]]
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["<"] = "\\u003c" }
local function encodeString(s)
    return '"' .. s:gsub('[%c"\\<]', function(c) return ESCAPES[c] or ("\\u%04x"):format(c:byte()) end) .. '"'
end

local encode
local function isArray(t)
    local n = #t
    if n == 0 then return next(t) == nil end
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end
encode = function(v)
    local kind = type(v)
    if kind == "string" then return encodeString(v) end
    if kind == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return tostring(v)
    end
    if kind == "boolean" then return v and "true" or "false" end
    if kind ~= "table" then return "null" end
    local out = {}
    if isArray(v) then
        for i = 1, #v do out[i] = encode(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    for k, val in pairs(v) do
        if type(k) == "string" or type(k) == "number" then
            out[#out + 1] = encodeString(tostring(k)) .. ":" .. encode(val)
        end
    end
    return "{" .. table.concat(out, ",") .. "}"
end

-- Para otras apps del telefono (c_messages.lua)
Phone.encode, Phone.encodeString = encode, encodeString

local function toJS(name, ...)
    if not Phone.isOpen() then return false end
    local args = {}
    for i = 1, select("#", ...) do args[i] = encode((select(i, ...))) end
    Phone.callJS(("RP.tinder && RP.tinder.on(%s, [%s])"):format(encodeString(name), table.concat(args, ",")))
    return true
end

for _, name in ipairs(SERVER_EVENTS) do
    addEvent("rp:tinder:" .. name, true)
    addEventHandler("rp:tinder:" .. name, resourceRoot, function(...)
        if toJS(name, ...) then return end
        -- Telefono cerrado: solo avisamos de lo importante
        if name == "message" then
            local _, msg = ...
            if type(msg) == "table" and not msg.mine then
                exports.rp_notify:notify(("💬 %s en Tinder: %s"):format(tostring(msg.name or "Alguien"), tostring(msg.body or "")), "info")
                playSoundFrontEnd(12)
            end
        end
    end)
end

local function str(v, max) v = tostring(v or "") return #v <= (max or 64) and v or nil end
local function key(v) v = tostring(v or "") return v:match("^[pn]%d+$") and v or nil end

-- Acciones de la app
local ACTIONS = {
    open = function() triggerServerEvent("rp:tinder:profile:get", resourceRoot) end,
    badge = function() triggerServerEvent("rp:tinder:badge:get", resourceRoot) end,
    -- CEF solo pasa textos y numeros: los objetos llegan como JSON
    save = function(json)
        local data = type(json) == "string" and #json < 4000 and fromJSON(json) or nil
        if type(data) == "table" then triggerServerEvent("rp:tinder:profile:save", resourceRoot, data) end
    end,
    photo = function(slot, image, thumb)
        if type(image) ~= "string" then return end
        triggerLatentServerEvent("rp:tinder:photo:save", 300000, false, resourceRoot, tonumber(slot), image,
            type(thumb) == "string" and thumb or nil)
    end,
    photoRemove = function(slot) triggerServerEvent("rp:tinder:photo:remove", resourceRoot, tonumber(slot)) end,
    deck = function(exclude)
        local list = {}
        for k in tostring(exclude or ""):gmatch("[^,]+") do
            if #list < 12 and key(k) then list[#list + 1] = k end
        end
        triggerServerEvent("rp:tinder:deck:get", resourceRoot, list)
    end,
    swipe = function(k, action) if key(k) then triggerServerEvent("rp:tinder:swipe", resourceRoot, key(k), str(action, 8)) end end,
    rewind = function() triggerServerEvent("rp:tinder:rewind", resourceRoot) end,
    matches = function() triggerServerEvent("rp:tinder:matches:get", resourceRoot) end,
    chat = function(k) if key(k) then triggerServerEvent("rp:tinder:chat:open", resourceRoot, key(k)) end end,
    send = function(k, text) if key(k) and type(text) == "string" then triggerServerEvent("rp:tinder:chat:send", resourceRoot, key(k), text) end end,
    unmatch = function(k) if key(k) then triggerServerEvent("rp:tinder:unmatch", resourceRoot, key(k)) end end,
    likes = function() triggerServerEvent("rp:tinder:likes:get", resourceRoot) end,
    card = function(k) if key(k) then triggerServerEvent("rp:tinder:card:get", resourceRoot, key(k)) end end,
    gold = function() triggerServerEvent("rp:tinder:gold:buy", resourceRoot) end,
    tutorial = function() triggerServerEvent("rp:tinder:tutorial:done", resourceRoot) end,
}

addEventHandler("rp:phone:ui:tinder", root, function(action, ...)
    local fn = ACTIONS[action]
    if fn then fn(...) end
end)
