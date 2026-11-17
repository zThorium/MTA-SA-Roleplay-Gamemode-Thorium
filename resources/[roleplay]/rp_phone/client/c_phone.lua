--[[
    rp_phone / c_phone.lua
    Telefono estilo smartphone en la esquina inferior derecha (CEF).
    Tecla P o usar el item desde el inventario. Esc / P para guardarlo.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local screenSource = nil
local capturing = false

addEvent("rp:phone:show", true)
addEvent("rp:phone:notes", true)
addEvent("rp:phone:contacts", true)
addEvent("rp:social:feed", true)
addEvent("rp:bank:data", true)
for _, name in ipairs({ "close", "noteSave", "noteDelete", "contactAdd", "contactDelete", "nearby", "contactAddPlayer",
    "bankOpen", "bankAction", "feed", "capture", "post", "like" }) do
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
end

local function open()
    if isOpen() then return end
    exports.rp_inventory:closeInventory()
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
addEventHandler("rp:social:feed", resourceRoot, function(rows) callJS(("RP.setFeed(%s)"):format(json(rows or {}))) end)

addEventHandler("rp:bank:data", root, function(view, data)
    if view == "phone" then callJS(("RP.setBank(%s)"):format(json(data or {}))) end
end)

----------------------------------------------------------------
-- Telefono -> servidor
----------------------------------------------------------------
addEventHandler("rp:phone:ui:close", root, close)
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

addEventHandler("rp:phone:ui:feed", root, function() triggerServerEvent("rp:social:feed", resourceRoot) end)
addEventHandler("rp:phone:ui:like", root, function(id) triggerServerEvent("rp:social:like", resourceRoot, tonumber(id)) end)
addEventHandler("rp:phone:ui:post", root, function(caption, image)
    if type(image) ~= "string" then return end
    triggerLatentServerEvent("rp:social:post", 200000, false, resourceRoot, tostring(caption or ""), image)
end)

----------------------------------------------------------------
-- Camara: oculta el telefono y el HUD, captura la pantalla y la devuelve
----------------------------------------------------------------
local function doCapture()
    removeEventHandler("onClientRender", root, doCapture)
    if not screenSource then screenSource = dxCreateScreenSource(640, 360) end
    dxUpdateScreenSource(screenSource, true)
    local pixels = dxGetTexturePixels(screenSource)
    local jpeg = pixels and dxConvertPixels(pixels, "jpeg", 70)

    setElementData(localPlayer, "rp:hudHidden", false, false)
    if isElement(browserGui) then guiSetVisible(browserGui, true) end
    showCursor(true)
    capturing = false

    if jpeg then
        playSoundFrontEnd(41)
        callJS(("RP.setPhoto(%s)"):format(jsString(encodeString("base64", jpeg))))
    else
        exports.rp_notify:notify("No se pudo tomar la foto.", "error")
    end
end

addEventHandler("rp:phone:ui:capture", root, function()
    if capturing or not isOpen() then return end
    capturing = true
    guiSetVisible(browserGui, false)
    showCursor(false)
    setElementData(localPlayer, "rp:hudHidden", true, false)
    -- Deja pasar un instante para que la escena se vea sin interfaz
    setTimer(function() addEventHandler("onClientRender", root, doCapture, true, "low-1000") end, 400, 1)
end)

----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("p", "down", function()
        if isOpen() then return close() end
        if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:phone:open", resourceRoot)
    end)
end)

addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)
