--[[
    rp_achievements / c_panel.lua  (cliente)

    Panel CEF de logros (html/). Se abre con /logros (comando del servidor) o desde la app
    «Logros» del teléfono (rp_phone lanza rp:achievements:openApp). El JS solo pide; el
    servidor revalida y entrega.
      servidor -> cliente  rp:achievements:panel (datos, abrir), rp:achievements:claimed (n, ok)
      CEF -> cliente       rp:achievements:ui:close, rp:achievements:ui:claim (n), rp:achievements:ui:coachDone
    El entrenador (la barra de hitos señalada) sale solo la primera vez: se recuerda en @coach.
]]

AchUI = AchUI or {}

local sw, sh = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local COACH_FILE = "@coach"

addEvent("rp:achievements:panel", true)
addEvent("rp:achievements:claimed", true)
addEvent("rp:achievements:openApp", false)          -- lo lanza rp_phone (app Logros)
addEvent("rp:achievements:ui:close", false)
addEvent("rp:achievements:ui:claim", false)
addEvent("rp:achievements:ui:coachDone", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function close()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

-- Catálogo para el JS (una vez por apertura; los textos viven en shared/)
local function catalogJSON()
    local list = {}
    for _, a in ipairs(ACH.CATALOG) do
        list[#list + 1] = { key = a.key, cat = a.cat, icon = a.icon, name = a.name, desc = a.desc,
            tiers = a.tiers, medals = a.medals, unit = a.unit or "", secret = a.secret == true }
    end
    local medals = {}
    for i, m in ipairs(ACH.MEDALS) do medals[i] = { name = m.name, label = m.label, points = m.points, hex = m.hex } end
    local milestones = {}
    for i, m in ipairs(ACH.MILESTONES) do
        local items = {}
        for _, it in ipairs(m.items or {}) do
            local def = exports.rp_inventory:getItemDefinition(it[1])
            items[#items + 1] = { name = def and def.name or it[1], icon = def and def.icon or "📦", n = it[2] }
        end
        milestones[i] = { points = m.points, bank = m.bank or 0, xp = m.xp or 0, items = items, cosmetic = m.cosmetic or "" }
    end
    return toJSON({ achievements = list, categories = ACH.CATEGORIES, medals = medals, milestones = milestones }, true)
end

local function coachSeen() return fileExists(COACH_FILE) end

addEventHandler("rp:achievements:panel", resourceRoot, function(data, doOpen)
    if type(data) ~= "table" then return end
    if not isElement(browserGui) then
        if not doOpen then return end
        open()
        callJS(("RP.catalog(%s[0])"):format(catalogJSON()))
        data.coach = not coachSeen()
    end
    callJS(("RP.show(%s[0])"):format(toJSON(data, true)))
end)

addEventHandler("rp:achievements:claimed", resourceRoot, function(index, ok)
    callJS(("RP.claimed(%d, %s)"):format(tonumber(index) or 0, ok and "true" or "false"))
end)

addEventHandler("rp:achievements:openApp", root, function()
    triggerServerEvent("rp:achievements:request", resourceRoot)
end)

addEventHandler("rp:achievements:ui:claim", root, function(index)
    index = tonumber(index)
    if not index then return end
    triggerServerEvent("rp:achievements:claim", resourceRoot, math.floor(index))
end)

addEventHandler("rp:achievements:ui:coachDone", root, function()
    if coachSeen() then return end
    local f = fileCreate(COACH_FILE)
    if f then fileWrite(f, "1"); fileClose(f) end
end)

addEventHandler("rp:achievements:ui:close", root, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, close)

-- Puntos al día (por si el panel está abierto cuando llega una medalla)
function AchUI.onPoints(total)
    if isElement(browserGui) then triggerServerEvent("rp:achievements:request", resourceRoot) end
end
