--[[
    rp_phone / c_phone.lua
    Telefono estilo smartphone (app Telefono con numeros de emergencia) en la esquina inferior derecha (CEF).
    Tecla P o usar el item desde el inventario. Esc / P para guardarlo.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}

addEvent("rp:phone:show", true)
addEvent("rp:phone:notes", true)
addEvent("rp:phone:contacts", true)
addEvent("rp:bank:data", true)
addEvent("rp:phone:callResult", true)
addEvent("rp:tinder:profile", true)
addEvent("rp:tinder:deck", true)
addEvent("rp:tinder:match", true)
addEvent("rp:tinder:matches", true)
addEvent("rp:tinder:matches:photo", true)
addEvent("rp:tinder:unmatched", true)
for _, name in ipairs({ "close", "noteSave", "noteDelete", "contactAdd", "contactDelete", "nearby", "contactAddPlayer",
    "bankOpen", "bankAction", "openApp", "call", "tinderOpen", "tinderSave", "tinderDeck", "tinderSwipe",
    "tinderMatches", "tinderMatchPhoto", "tinderUnmatch" }) do
    addEvent("rp:phone:ui:" .. name, false)
end

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

-- toJSON envuelve el valor en un array
local function json(value) return toJSON(value, true) .. "[0]" end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function isOpen() return isElement(browserGui) end

local function close()
    if not isOpen() then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
    triggerEvent("rp:phone:onClose", localPlayer)   -- Fotogram: cierra la camara si estaba abierta
end

local function open()
    if isOpen() then return end
    pcall(function() exports.rp_inventory:closeInventory() end)   -- no falla si el inventario no esta cargado
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

----------------------------------------------------------------
-- Servidor -> telefono
----------------------------------------------------------------
addEventHandler("rp:phone:show", resourceRoot, function(info)
    open()
    callJS(("RP.boot(%s)"):format(json(info or {})))
end)

addEventHandler("rp:phone:notes", resourceRoot, function(rows) callJS(("RP.setNotes(%s)"):format(json(rows or {}))) end)
addEventHandler("rp:phone:contacts", resourceRoot, function(rows) callJS(("RP.setContacts(%s)"):format(json(rows or {}))) end)

addEventHandler("rp:phone:callResult", resourceRoot, function(number, ok)
    callJS(("RP.callResult(%s, %s)"):format(jsString(number), tostring(ok == true)))
end)

addEventHandler("rp:tinder:profile", resourceRoot, function(profile) callJS(("RP.tinder.setProfile(%s)"):format(json(profile or {}))) end)

addEventHandler("rp:tinder:deck", resourceRoot, function(card) callJS(("RP.tinder.setCard(%s)"):format(card and json(card) or "null")) end)
addEventHandler("rp:tinder:match", resourceRoot, function(m) callJS(("RP.tinder.matched(%s)"):format(json(m or {}))) end)
addEventHandler("rp:tinder:matches", resourceRoot, function(list) callJS(("RP.tinder.setMatches(%s)"):format(list and json(list) or "null")) end)
addEventHandler("rp:tinder:matches:photo", resourceRoot, function(id, photo)
    if type(photo) == "string" and photo:match("^[%w%+/=]+$") then
        callJS(("RP.tinder.setMatchPhoto(%d, %s)"):format(tonumber(id) or 0, jsString(photo)))
    end
end)
addEventHandler("rp:tinder:unmatched", resourceRoot, function(id) callJS(("RP.tinder.unmatched(%d)"):format(tonumber(id) or 0)) end)

addEventHandler("rp:bank:data", root, function(view, data)
    if view == "phone" then callJS(("RP.setBank(%s)"):format(json(data or {}))) end
end)

----------------------------------------------------------------
-- Telefono -> servidor
----------------------------------------------------------------
addEventHandler("rp:phone:ui:close", root, close)
-- Apps de otros recursos: se cierra el telefono y se abre la app (p. ej. Vroom de rp_rides)
local EXTERNAL_APPS = { vroom = "rp:rides:openApp" }
addEventHandler("rp:phone:ui:openApp", root, function(app)
    local event = EXTERNAL_APPS[app]
    if not event then return end
    close()
    triggerEvent(event, localPlayer)
end)
addEventHandler("rp:phone:ui:call", root, function(number)
    number = tostring(number or ""):gsub("%D", "")
    if #number == 0 or #number > 12 then return end
    triggerServerEvent("rp:phone:call", resourceRoot, number)
end)
addEventHandler("rp:phone:ui:noteSave", root, function(id, title, body)
    triggerServerEvent("rp:phone:note:save", resourceRoot, tonumber(id), tostring(title or ""), tostring(body or ""))
end)
addEventHandler("rp:phone:ui:noteDelete", root, function(id) triggerServerEvent("rp:phone:note:delete", resourceRoot, tonumber(id)) end)
addEventHandler("rp:phone:ui:contactAdd", root, function(name, number)
    triggerServerEvent("rp:phone:contact:add", resourceRoot, tostring(name or ""), tonumber(number))
end)
addEventHandler("rp:phone:ui:contactDelete", root, function(id) triggerServerEvent("rp:phone:contact:delete", resourceRoot, tonumber(id)) end)

-- Jugadores cercanos con personaje (para agregarlos a la agenda)
local nearbyPlayers = {}
addEventHandler("rp:phone:ui:nearby", root, function()
    nearbyPlayers = {}
    local list = {}
    local x, y, z = getElementPosition(localPlayer)
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if p ~= localPlayer and getElementData(p, "rp:characterId") then
            local px, py, pz = getElementPosition(p)
            if getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= 5 then
                nearbyPlayers[#nearbyPlayers + 1] = p
                list[#list + 1] = { index = #nearbyPlayers, name = (getPlayerName(p):gsub("_", " ")) }
            end
        end
    end
    callJS(("RP.setNearby(%s)"):format(json(list)))
end)
addEventHandler("rp:phone:ui:contactAddPlayer", root, function(index)
    local target = nearbyPlayers[tonumber(index)]
    if isElement(target) then triggerServerEvent("rp:phone:contact:addPlayer", resourceRoot, target) end
end)

addEventHandler("rp:phone:ui:bankOpen", root, function() triggerServerEvent("rp:bank:open", resourceRoot, "phone") end)
addEventHandler("rp:phone:ui:bankAction", root, function(action, amount, target)
    amount = tonumber(amount)
    if not amount then return end
    if action == "deposit" then triggerServerEvent("rp:bank:deposit", resourceRoot, amount, "phone")
    elseif action == "transfer" then triggerServerEvent("rp:bank:transfer", resourceRoot, tostring(target or ""), amount, "phone") end
end)

-- Tinder
addEventHandler("rp:phone:ui:tinderOpen", root, function() triggerServerEvent("rp:tinder:profile:get", resourceRoot) end)
addEventHandler("rp:phone:ui:tinderDeck", root, function(exclude)
    local list = {}
    if type(exclude) == "table" then
        for i = 1, math.min(#exclude, 5) do list[#list + 1] = tonumber(exclude[i]) end
    end
    triggerServerEvent("rp:tinder:deck:get", resourceRoot, list)
end)
addEventHandler("rp:phone:ui:tinderSwipe", root, function(targetId, liked)
    triggerServerEvent("rp:tinder:swipe", resourceRoot, tonumber(targetId), liked == true)
end)
addEventHandler("rp:phone:ui:tinderMatches", root, function() triggerServerEvent("rp:tinder:matches:get", resourceRoot) end)
addEventHandler("rp:phone:ui:tinderMatchPhoto", root, function(id) triggerServerEvent("rp:tinder:matches:photo", resourceRoot, tonumber(id)) end)
addEventHandler("rp:phone:ui:tinderUnmatch", root, function(id) triggerServerEvent("rp:tinder:unmatch", resourceRoot, tonumber(id)) end)
addEventHandler("rp:phone:ui:tinderSave", root, function(bio, interested, active, photo)
    triggerLatentServerEvent("rp:tinder:profile:save", 200000, false, resourceRoot,
        tostring(bio or ""), tostring(interested or "a"), active == true, type(photo) == "string" and photo or nil)
end)


----------------------------------------------------------------
-- Para los otros scripts del telefono (c_social.lua, c_camera.lua)
----------------------------------------------------------------
addEvent("rp:phone:onClose", false)
Phone = {
    callJS = callJS, json = json, jsString = jsString, isOpen = isOpen, close = close,
    getGui = function() return browserGui end,
    getBrowser = function() return browser end,
}

----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("p", "down", function()
        if isOpen() then return close() end
        if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
        if getElementData(localPlayer, "rp:downed") then return end   -- abatido (rp_injury)
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:phone:open", resourceRoot)
    end)
end)

addEventHandler("onClientPlayerWasted", localPlayer, close)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)
