--[[
    rp_scoreboard / client/c_scoreboard.lua
    Tab (mantener): lista de jugadores en CEF que se expande al abrir y se contrae al soltar.
    Rueda del raton para desplazarse. /perfil abre el editor de tu fila del Tab
    (color o degradado, letras animadas, icono animado, bandera y foto).

    El navegador se crea una vez y se muestra/oculta (patron de rp_inventory).
    La foto de cada jugador se pide al servidor una sola vez por version (rp:tabProfile.a).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local mode = nil            -- nil | "board" | "editor"
local refreshTimer, hideTimer
local avatarAsked = {}      -- [player] = version pedida

addEvent("rp:scoreboard:avatar", true)
addEvent("rp:scoreboard:ui:save", false)
addEvent("rp:scoreboard:ui:avatar", false)
addEvent("rp:scoreboard:ui:clearAvatar", false)
addEvent("rp:scoreboard:ui:closeEditor", false)
addEvent("rp:scoreboard:ui:hidden", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function playerKey(player) return "p" .. tostring(getElementData(player, "id") or tostring(player):sub(-6)) end

local function rowOf(player)
    -- estandar:dep-opcional rp_factions sin él la fila sale sin facción (pcall)
    local ok, fac = pcall(function() return exports.rp_factions:getPlayerFactionInfo(player) end)
    if not ok then fac = false end
    local pr = getElementData(player, "rp:tabProfile")
    local row = {
        k = playerKey(player),
        id = tonumber(getElementData(player, "id")) or 0,
        name = getPlayerName(player):gsub("_", " "),
        ping = getPlayerPing(player),
        lvl = tonumber(getElementData(player, "rp:level")) or 0,
        me = player == localPlayer,
        off = not getElementData(player, "rp:characterId"),
        fac = type(fac) == "table" and { tag = fac.tag, name = fac.name, color = fac.color } or false,
        pr = type(pr) == "table" and pr or false,
    }
    -- foto nueva o no pedida todavia
    if row.pr and (row.pr.a or 0) > 0 and avatarAsked[player] ~= row.pr.a then
        avatarAsked[player] = row.pr.a
        triggerServerEvent("rp:scoreboard:getAvatar", resourceRoot, player)
    end
    return row
end

local function snapshot()
    local list = {}
    for _, player in ipairs(getElementsByType("player")) do list[#list + 1] = rowOf(player) end
    table.sort(list, function(a, b) return (a.id == 0 and 9999 or a.id) < (b.id == 0 and 9999 or b.id) end)
    return {
        server = getElementData(resourceRoot, "server:name") or "Thorium Roleplay",
        max = getElementData(resourceRoot, "server:maxPlayers") or 0,
        players = list,
    }
end

local function catalog()
    return { effects = SB.EFFECTS, icons = SB.ICONS, flags = SB.FLAGS, defaultColor = SB.DEFAULT_COLOR }
end

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        executeBrowserJavascript(source, ("RP.setCatalog(%s)"):format(toJSON(catalog(), true):sub(2, -2)))
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
end

local function stopRefresh()
    if isTimer(refreshTimer) then killTimer(refreshTimer) end
    refreshTimer = nil
end

local function onScroll(key)
    callJS(("RP.scroll(%d)"):format(key == "mouse_wheel_down" and 1 or -1))
end

local function hideBoard()
    if mode ~= "board" then return end
    stopRefresh()
    unbindKey("mouse_wheel_up", "down", onScroll)
    unbindKey("mouse_wheel_down", "down", onScroll)
    callJS("RP.close()")
    -- se oculta cuando termina la animacion de contraerse (o por seguridad a los 600 ms)
    if isTimer(hideTimer) then killTimer(hideTimer) end
    hideTimer = setTimer(function()
        if mode == "board" then mode = nil; guiSetVisible(browserGui, false) end
    end, 600, 1)
end

local function showBoard()
    if mode == "editor" or not ready then return end
    if isTimer(hideTimer) then killTimer(hideTimer) end
    mode = "board"
    guiSetVisible(browserGui, true)
    callJS(("RP.open(%s)"):format(toJSON(snapshot(), true):sub(2, -2)))
    stopRefresh()
    refreshTimer = setTimer(function()
        callJS(("RP.update(%s)"):format(toJSON(snapshot(), true):sub(2, -2)))
    end, 1000, 0)
    bindKey("mouse_wheel_up", "down", onScroll)
    bindKey("mouse_wheel_down", "down", onScroll)
end

addEventHandler("rp:scoreboard:ui:hidden", root, function()
    if mode == "board" then mode = nil; guiSetVisible(browserGui, false) end
end)

local function onTab(_, state)
    if state ~= "down" then return hideBoard() end
    -- no abrir mientras se escribe en el chat/consola o hay otra ventana con cursor
    if isChatBoxInputActive() or isConsoleActive() or isCursorShowing() then return end
    showBoard()
end

----------------------------------------------------------------
-- Editor (/perfil)
----------------------------------------------------------------
local function closeEditor()
    if mode ~= "editor" then return end
    mode = nil
    callJS("RP.closeEditor()")
    guiSetVisible(browserGui, false)
    showCursor(false)
    guiSetInputEnabled(false)
end

addCommandHandler("perfil", function()
    if not getElementData(localPlayer, "rp:characterId") or not ready then return end
    if mode == "board" then
        stopRefresh()
        unbindKey("mouse_wheel_up", "down", onScroll)
        unbindKey("mouse_wheel_down", "down", onScroll)
    end
    mode = "editor"
    guiSetVisible(browserGui, true)
    showCursor(true)
    guiSetInputEnabled(true)
    focusBrowser(browser)
    callJS(("RP.openEditor(%s)"):format(toJSON(rowOf(localPlayer), true):sub(2, -2)))
end)

addEventHandler("rp:scoreboard:ui:save", root, function(json)
    if mode ~= "editor" or type(json) ~= "string" then return end
    triggerServerEvent("rp:scoreboard:save", resourceRoot, json)
end)

addEventHandler("rp:scoreboard:ui:avatar", root, function(url)
    if mode ~= "editor" or type(url) ~= "string" then return end
    triggerServerEvent("rp:scoreboard:setAvatar", resourceRoot, url)
end)

addEventHandler("rp:scoreboard:ui:clearAvatar", root, function()
    if mode ~= "editor" then return end
    triggerServerEvent("rp:scoreboard:clearAvatar", resourceRoot)
    callJS(("RP.setAvatar(%s, 0, null)"):format(jsString(playerKey(localPlayer))))
end)

addEventHandler("rp:scoreboard:ui:closeEditor", root, closeEditor)

addEventHandler("rp:scoreboard:avatar", resourceRoot, function(player, version, uri)
    if not isElement(player) or type(uri) ~= "string" or uri:sub(1, 11) ~= "data:image/" then return end
    avatarAsked[player] = version
    callJS(("RP.setAvatar(%s, %d, %s)"):format(jsString(playerKey(player)), tonumber(version) or 0, jsString(uri)))
end)

addEventHandler("onClientPlayerQuit", root, function() avatarAsked[source] = nil end)
addEventHandler("onClientPlayerWasted", localPlayer, closeEditor)

addEventHandler("onClientResourceStart", resourceRoot, function()
    createBrowser()
    bindKey("tab", "both", onTab)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if mode == "editor" then showCursor(false); guiSetInputEnabled(false) end
end)
