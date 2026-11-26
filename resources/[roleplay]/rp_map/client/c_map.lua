--[[
    rp_map / client/c_map.lua  (cliente)
    Sustituye el mapa F11 de GTA por el mapa CEF (html/). Guarda lo que el servidor
    deja ver a este jugador (celdas exploradas, lugares...) y lo pasa al navegador,
    que ocupa toda la pantalla. Mientras el mapa esta abierto:
      - el personaje no se mueve (guiSetInputEnabled) y se recuperan los controles al cerrar;
      - suena el tema del mapa en bucle desde el inicio (se corta al cerrar);
      - la radio y la musica del telefono se pausan (setRadioSuppressed / setMusicSuppressed).
    Se cierra con F11, Esc o la X.
    El tutorial sale solo la primera vez: se marca en las preferencias del personaje y en
    @map_tutorial.xml de este PC.
]]

MapC = MapC or {}

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local isOpen = false
local theme
local posTimer

-- Estado que manda el servidor (solo lo que este jugador puede ver)
local S = { loaded = false, cells = {}, start = {}, places = {}, cats = {}, sectors = {}, settings = {},
    prefs = {}, totals = { all = 0, city = {} }, isAdmin = false, adminView = false }
MapC.state = S

local sectors, cellCity, zoneCells

addEvent("rp:map:init", true)
addEvent("rp:map:cells", true)
addEvent("rp:map:places", true)
addEvent("rp:map:config", true)
addEvent("rp:map:admin:data", true)
addEvent("rp:map:admin:player", true)
for _, e in ipairs({ "ready", "close", "navigate", "navStop", "prefs", "admin" }) do
    addEvent("rp:map:ui:" .. e, false)
end

----------------------------------------------------------------
-- Navegador
----------------------------------------------------------------
local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end
MapC.callJS = function(code) if isOpen or ready then callJS(code) end end

local function js(v) return toJSON(v, true):sub(2, -2) end   -- toJSON envuelve en [ ]: se quita

local function listOf(set)
    local t = {}
    for i in pairs(set) do t[#t + 1] = i end
    return t
end

local function placesList()
    local t = {}
    for _, pl in pairs(S.places) do t[#t + 1] = pl end
    return t
end

-- Zonas (barrios) por celda de tierra, para el buscador: se calculan una vez
local function buildZones()
    if zoneCells then return zoneCells end
    local byName = {}
    for i = 1, MapGrid.size() ^ 2 do
        if MapGrid.isLand(i) then
            local x, y = MapGrid.cellCenter(i)
            local name = getZoneName(x, y, 30, false)
            local z = byName[name]
            if not z then z = { name = name, city = cellCity[i], cells = {} }; byName[name] = z end
            z.cells[#z.cells + 1] = i
        end
    end
    zoneCells = {}
    for _, z in pairs(byName) do zoneCells[#zoneCells + 1] = z end
    return zoneCells
end

local function fullState()
    local secs = {}
    for s, sec in ipairs(sectors) do
        local o = S.sectors[sec.id] or {}
        secs[s] = { id = sec.id, name = o.name or sec.name, city = o.city or sec.city, land = sec.land, revealed = o.revealed == true }
    end
    return {
        land = MAP_LAND, cells = listOf(S.cells), start = listOf(S.start), places = placesList(), cats = S.cats,
        sectors = secs, zones = buildZones(), settings = S.settings, prefs = S.prefs,
        totals = S.totals, isAdmin = S.isAdmin, adminView = S.adminView, cities = MAPA_CITIES, discoveredPct = MAPA.SECTOR_DISCOVERED_PCT,
        icons = MAPA.ICONS,
    }
end

local function pushPlayer()
    if not isOpen then return end
    local x, y, z = getElementPosition(localPlayer)
    local _, _, rz = getElementRotation(getPedOccupiedVehicle(localPlayer) or localPlayer)
    local cx, cy, _, tx, ty = getCameraMatrix()
    local interior = getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0
    callJS(("RP.player(%s)"):format(js({ x = x, y = y, z = z, rot = rz,
        cam = math.deg(math.atan2(tx - cx, ty - cy)), zone = interior and "Interior" or getZoneName(x, y, z),
        city = getZoneName(x, y, z, true), inside = interior })))
end

local function createBrowserOnce()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    guiSetVisible(browserGui, false)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
end

addEventHandler("rp:map:ui:ready", root, function()
    ready = true
    for _, code in ipairs(pendingJS) do executeBrowserJavascript(browser, code) end
    pendingJS = {}
end)

----------------------------------------------------------------
-- Pausar otros audios con el mapa abierto
----------------------------------------------------------------
-- rp_radio y rp_phone son opcionales: solo se llaman si estan en marcha
-- estandar:dep-opcional rp_radio
-- estandar:dep-opcional rp_phone
local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setOtherAudioSuppressed(on)
    if running("rp_radio") then pcall(function() exports.rp_radio:setRadioSuppressed(MAPA.AUDIO_REASON, on) end) end
    if running("rp_phone") then pcall(function() exports.rp_phone:setMusicSuppressed(MAPA.AUDIO_REASON, on) end) end
end

local function stopTheme()
    if isElement(theme) then destroyElement(theme) end
    theme = nil
end

local function startTheme()
    stopTheme()
    if S.settings.music == 0 or not fileExists(MAPA.MUSIC_FILE) then return end
    theme = playSound(MAPA.MUSIC_FILE, true)   -- true = en bucle: al terminar vuelve a empezar
    if theme then setSoundVolume(theme, MAPA.MUSIC_VOLUME) end
end

-- Tutorial: solo la primera vez (preferencia del personaje o marca local de este PC)
local TUTORIAL_FILE = "@map_tutorial.xml"
local function tutorialSeen()
    return S.prefs.tutorial == true or fileExists(TUTORIAL_FILE)
end
local function markTutorialSeen()
    if not fileExists(TUTORIAL_FILE) then
        local f = fileCreate(TUTORIAL_FILE)
        if f then fileWrite(f, "<tutorial visto=\"1\" />"); fileClose(f) end
    end
    if S.prefs.tutorial ~= true then
        S.prefs.tutorial = true
        triggerServerEvent("rp:map:prefs", resourceRoot, S.prefs)
    end
end

----------------------------------------------------------------
-- Abrir / cerrar
----------------------------------------------------------------
local function canOpen()
    if not getElementData(localPlayer, "rp:characterId") then return false end
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    local ok, suppressed = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    if ok and suppressed then return false end   -- cinematicas
    return true
end

function MapC.open()
    if isOpen then return end
    if not canOpen() then return end
    if not S.loaded then
        triggerServerEvent("rp:map:request", resourceRoot)
        return exports.rp_notify:notify("Cargando tu mapa... vuelve a pulsar F11 en un momento.", "info")
    end
    createBrowserOnce()
    isOpen = true
    if isPlayerMapVisible() then forcePlayerMap(false) end
    guiSetVisible(browserGui, true)
    guiBringToFront(browserGui)
    setBrowserRenderingPaused(browser, false)
    focusBrowser(browser)
    showCursor(true)
    guiSetInputEnabled(true)
    pcall(function() exports.rp_hud:setHudHidden("rp_map", true) end)
    setOtherAudioSuppressed(true)
    startTheme()
    local state = fullState()
    if not tutorialSeen() then
        markTutorialSeen()                       -- se muestra esta vez y ya no vuelve
        state.prefs = {}
        for k, v in pairs(S.prefs) do state.prefs[k] = v end
        state.prefs.tutorial = false
    else
        state.prefs.tutorial = true
    end
    callJS(("RP.open(%s)"):format(js(state)))
    if MapC.gpsState then callJS(("RP.route(%s)"):format(js(MapC.gpsState()))) end
    pushPlayer()
    posTimer = setTimer(pushPlayer, 150, 0)
end

function MapC.close()
    if not isOpen then return end
    isOpen = false
    if isTimer(posTimer) then killTimer(posTimer) end
    callJS("RP.close()")
    stopTheme()
    setOtherAudioSuppressed(false)
    pcall(function() exports.rp_hud:setHudHidden("rp_map", false) end)
    guiSetInputEnabled(false)
    showCursor(false)
    if isElement(browser) then
        focusBrowser(nil)
        setBrowserRenderingPaused(browser, true)
    end
    if isElement(browserGui) then guiSetVisible(browserGui, false) end
end

function MapC.isOpen() return isOpen end

addEventHandler("rp:map:ui:close", root, MapC.close)

-- F11 abre/cierra (sustituye al mapa de GTA) y Esc cierra. onClientKey corre antes que los binds.
addEventHandler("onClientKey", root, function(key, press)
    if not press then return end
    if key == "F11" then
        cancelEvent()
        if isOpen then MapC.close() else MapC.open() end
    elseif key == "escape" and isOpen then
        cancelEvent()
        MapC.close()
    end
end)

-- El mapa nativo de GTA no debe abrirse nunca (por si otro bind lo fuerza)
addEventHandler("onClientRender", root, function()
    if isPlayerMapVisible() then forcePlayerMap(false) end
end)

addEventHandler("onClientPlayerWasted", localPlayer, MapC.close)

----------------------------------------------------------------
-- Datos del servidor
----------------------------------------------------------------
local function setFromList(list)
    local t = {}
    for _, i in ipairs(type(list) == "table" and list or {}) do t[i] = true end
    return t
end

local function placesFromList(list)
    local t = {}
    for _, pl in ipairs(type(list) == "table" and list or {}) do t[tostring(pl.id)] = pl end
    return t
end

addEventHandler("rp:map:init", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    S.cells = setFromList(data.cells)
    S.start = setFromList(data.start)
    S.places = placesFromList(data.places)
    S.cats, S.sectors, S.settings = data.cats or {}, data.sectors or {}, data.settings or {}
    S.prefs, S.totals, S.isAdmin, S.adminView = data.prefs or {}, data.totals or S.totals, data.isAdmin == true, data.adminView == true
    S.loaded = true
    if isOpen then callJS(("RP.open(%s)"):format(js(fullState()))) end
end)

addEventHandler("rp:map:cells", resourceRoot, function(list, newPlaces)
    for _, i in ipairs(list or {}) do S.cells[i] = true end
    for _, pl in ipairs(newPlaces or {}) do S.places[tostring(pl.id)] = pl end
    if isOpen then callJS(("RP.cells(%s, %s)"):format(js(list or {}), js(newPlaces or {}))) end
end)

addEventHandler("rp:map:places", resourceRoot, function(list, totals)
    S.places = placesFromList(list)
    S.totals = totals or S.totals
    if isOpen then callJS(("RP.places(%s, %s)"):format(js(placesList()), js(S.totals))) end
end)

addEventHandler("rp:map:config", resourceRoot, function(data)
    if type(data) ~= "table" then return end
    S.cats, S.sectors, S.settings = data.cats or S.cats, data.sectors or S.sectors, data.settings or S.settings
    S.start = setFromList(data.start)
    if S.settings.music == 0 then stopTheme() end
    if isOpen then callJS(("RP.open(%s)"):format(js(fullState()))) end
end)

addEventHandler("rp:map:admin:data", resourceRoot, function(data)
    if isOpen then callJS(("RP.adminData(%s)"):format(js(data))) end
end)

addEventHandler("rp:map:admin:player", resourceRoot, function(info)
    if isOpen then callJS(("RP.adminPlayer(%s)"):format(info and js(info) or "null")) end
end)

----------------------------------------------------------------
-- Acciones del navegador (el servidor revalida todo)
----------------------------------------------------------------
local function num(v) return tonumber(v) end

addEventHandler("rp:map:ui:navigate", root, function(x, y, z, label)
    x, y = num(x), num(y)
    if not x or not y or not MapC.gpsStart then return end
    MapC.gpsStart(x, y, num(z) or 0, type(label) == "string" and label:sub(1, 60) or "Destino")
end)

addEventHandler("rp:map:ui:navStop", root, function()
    if MapC.gpsStop then MapC.gpsStop(true) end
end)

addEventHandler("rp:map:ui:prefs", root, function(json)
    local data = type(json) == "string" and fromJSON(json)
    if type(data) ~= "table" then return end
    if S.prefs.tutorial == true then data.tutorial = true end
    S.prefs = data
    triggerServerEvent("rp:map:prefs", resourceRoot, data)
end)

-- Admin: el cliente solo reenvia; s_admin.lua comprueba el nivel y todos los datos
local ADMIN_EVENTS = { open = true, placeSave = true, placeDelete = true, catSave = true, catDelete = true,
    sectorSave = true, settingsSave = true, playerQuery = true, playerReset = true, view = true }
addEventHandler("rp:map:ui:admin", root, function(action, json, extra)
    if not ADMIN_EVENTS[action] then return end
    local data = json
    if type(json) == "string" and (json:sub(1, 1) == "{" or json:sub(1, 1) == "[") then data = fromJSON(json) end
    if action == "sectorSave" then
        triggerServerEvent("rp:map:admin:sectorSave", resourceRoot, extra, data)
    else
        triggerServerEvent("rp:map:admin:" .. action, resourceRoot, data)
    end
end)

----------------------------------------------------------------
-- Arranque / parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    sectors, cellCity = MapGrid.buildSectors()
    toggleControl("radar", false)
    if getElementData(localPlayer, "rp:characterId") then triggerServerEvent("rp:map:request", resourceRoot) end
end)

-- Al cambiar de personaje se descarta lo del anterior
addEventHandler("onClientElementDataChange", localPlayer, function(key, old, new)
    if key ~= "rp:characterId" then return end
    MapC.close()
    S.loaded = false
    if MapC.gpsStop then MapC.gpsStop(false) end
    if new then setTimer(function() triggerServerEvent("rp:map:request", resourceRoot) end, 1500, 1) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    MapC.close()
    toggleControl("radar", true)
end)
