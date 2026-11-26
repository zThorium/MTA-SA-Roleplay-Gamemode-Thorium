--[[
    rp_help / c_help.lua
    Panel de ayuda (CEF) con F1, /ayuda o /reportar.

    El navegador se crea UNA sola vez (la primera vez que se abre) y despues
    solo se oculta y se muestra, con el render pausado mientras esta oculto.
    Crear y destruir navegadores CEF seguido provoco cuelgues del driver de
    video, asi que aqui nunca se destruye hasta que se detiene el recurso.
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local visible = false
local pendingJS = {}
local reportTargets = {}   -- [indice] = jugador (lista mostrada en el formulario)

addEvent("rp:help:open", true)
addEvent("rp:help:myReports", true)
addEvent("rp:help:reportResult", true)
for _, name in ipairs({ "close", "discord", "report", "myReports", "players" }) do
    addEvent("rp:help:ui:" .. name, false)
end

local function json(value) return toJSON(value, true) .. "[0]" end   -- toJSON envuelve en un array

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function bootData()
    return {
        serverName = HELP.SERVER_NAME, welcome = HELP.WELCOME, hasDiscord = HELP.DISCORD_URL ~= "",
        rules = HELP.RULES, concepts = HELP.CONCEPTS, keys = HELP.KEYS, commands = HELP.COMMANDS, guide = HELP.GUIDE,
        categories = HELP.REPORT_CATEGORIES, minText = HELP.REPORT_MIN_TEXT, maxText = HELP.REPORT_MAX_TEXT,
    }
end

local function ensureBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    guiSetVisible(browserGui, false)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        executeBrowserJavascript(source, ("RP.boot(%s)"):format(json(bootData())))
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
        if not visible then setBrowserRenderingPaused(source, true) end
    end)
end

-- Jugadores con personaje (para el formulario de reporte)
local function playerList()
    reportTargets = {}
    local list = {}
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= localPlayer and getElementData(p, "rp:characterId") then
            reportTargets[#reportTargets + 1] = p
            list[#list + 1] = { index = #reportTargets, id = getElementData(p, "id") or "?", name = (getPlayerName(p):gsub("_", " ")) }
        end
    end
    table.sort(list, function(a, b) return (tonumber(a.id) or 999) < (tonumber(b.id) or 999) end)
    return list
end

local function hide()
    if not visible then return end
    visible = false
    guiSetVisible(browserGui, false)
    if isElement(browser) and ready then setBrowserRenderingPaused(browser, true) end
    focusBrowser(nil)
    showCursor(false)
    guiSetInputEnabled(false)
end

local function show(tab)
    if visible then
        if tab then callJS(("RP.show(%s, %s)"):format(json(tab), json(playerList()))) end
        return
    end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end
    ensureBrowser()
    visible = true
    guiSetVisible(browserGui, true)
    if ready then setBrowserRenderingPaused(browser, false) end
    focusBrowser(browser)
    showCursor(true)
    guiSetInputEnabled(true)
    callJS(("RP.show(%s, %s)"):format(json(tab or false), json(playerList())))
end

----------------------------------------------------------------
-- Panel -> Lua
----------------------------------------------------------------
addEventHandler("rp:help:ui:close", root, hide)

addEventHandler("rp:help:ui:discord", root, function()
    if HELP.DISCORD_URL == "" then
        return exports.rp_notify:notify("El Discord estara disponible pronto.", "info")
    end
    setClipboard(HELP.DISCORD_URL)
    exports.rp_notify:notify("Enlace de Discord copiado. Pegalo en tu navegador.", "success")
end)

addEventHandler("rp:help:ui:players", root, function()
    callJS(("RP.setPlayers(%s)"):format(json(playerList())))
end)

addEventHandler("rp:help:ui:report", root, function(category, targetIndex, text)
    if type(category) ~= "string" or type(text) ~= "string" or #text > HELP.REPORT_MAX_TEXT * 4 then return end
    local target = nil
    if targetIndex and targetIndex ~= "" then
        target = reportTargets[tonumber(targetIndex)]
        if not isElement(target) then
            return callJS(("RP.reportResult(false, %s)"):format(json("Ese jugador ya no esta conectado.")))
        end
    end
    triggerServerEvent("rp:help:report", resourceRoot, category, target or false, text)
end)

addEventHandler("rp:help:ui:myReports", root, function() triggerServerEvent("rp:help:myReports", resourceRoot) end)

----------------------------------------------------------------
-- Servidor -> panel
----------------------------------------------------------------
addEventHandler("rp:help:open", resourceRoot, function(tab) show(tab) end)

addEventHandler("rp:help:myReports", resourceRoot, function(list)
    callJS(("RP.setMyReports(%s)"):format(json(list or {})))
end)

addEventHandler("rp:help:reportResult", resourceRoot, function(ok, message)
    callJS(("RP.reportResult(%s, %s)"):format(ok and "true" or "false", json(tostring(message or ""))))
    exports.rp_notify:notify(tostring(message or ""), ok and "success" or "error")
end)

----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    -- Con el panel abierto el teclado va al navegador: ahi F1 y Esc los maneja app.js
    bindKey(HELP.KEY, "down", function()
        if visible then hide() else show() end
    end)
end)

-- Icono de ayuda en el HUD (rp_hud/c_iconbar.lua)
addEvent("rp:hud:action", false)
addEventHandler("rp:hud:action", localPlayer, function(id)
    if id ~= "help" then return end
    if visible then hide() else show() end
end)

addEventHandler("onClientPlayerWasted", localPlayer, hide)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if visible then
        showCursor(false)
        guiSetInputEnabled(false)
    end
end)
