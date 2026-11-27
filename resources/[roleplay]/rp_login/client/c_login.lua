--[[
    rp_login / c_login.lua
    Muestra la interfaz CEF (html/index.html) y hace de puente entre el
    JavaScript del navegador y los eventos del servidor.

    JS  -> Lua : mta.triggerEvent("rp:ui:login" | "rp:ui:register" | "rp:ui:music", ...)
    Lua -> JS  : executeBrowserJavascript(browser, "RP.onResult(...)")

    Ojo: mta.triggerEvent convierte TODOS los argumentos a texto. Un booleano
    de JS llega a Lua como "true"/"false", nunca como true/false.

    Fondo: recorrido cinematografico por Los Santos (setCameraMatrix) con musica
    (music/login.mp3). La musica sigue en la seleccion de personajes y se apaga
    al entrar al juego. Se silencia con el boton de musica (esquina inferior).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser = nil, nil

-- Credenciales recordadas: archivo privado del recurso en el PC del jugador
-- (el prefijo "@" lo hace inaccesible a otros recursos). Solo se guarda tras
-- un login correcto y solo si el jugador marco "Recordar".
local SAVED_FILE = "@saved_login.xml"
local PREFS_FILE = "@login_prefs.xml"
local pendingRemember = nil  -- { user, pass } del ultimo intento con "Recordar"

local function loadSaved()
    if not fileExists(SAVED_FILE) then return nil, nil end
    local node = xmlLoadFile(SAVED_FILE)
    if not node then return nil, nil end
    local user = xmlNodeGetAttribute(node, "user")
    local pass = xmlNodeGetAttribute(node, "pass")
    xmlUnloadFile(node)
    if type(user) ~= "string" or type(pass) ~= "string" or user == "" then return nil, nil end
    return user, pass
end

local function writeSaved(user, pass)
    if fileExists(SAVED_FILE) then fileDelete(SAVED_FILE) end
    if not user then return end
    local node = xmlCreateFile(SAVED_FILE, "login")
    if not node then return end
    xmlNodeSetAttribute(node, "user", user)
    xmlNodeSetAttribute(node, "pass", pass)
    xmlSaveFile(node)
    xmlUnloadFile(node)
end

addEvent("rp:ui:login", false)
addEvent("rp:ui:register", false)
addEvent("rp:ui:music", false)
addEvent("rp:auth:result", true)
addEvent("rp:auth:success", true)

-- Convierte un texto Lua en un literal de cadena JavaScript seguro
local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function callJS(code)
    if isElement(browser) then
        executeBrowserJavascript(browser, code)
    end
end

----------------------------------------------------------------
-- Musica de fondo (preferencia guardada en el PC del jugador)
----------------------------------------------------------------
local MUSIC_VOLUME = 0.45
local music, musicOn, musicFade = nil, true, nil

local function loadMusicPref()
    local node = fileExists(PREFS_FILE) and xmlLoadFile(PREFS_FILE)
    if not node then return true end
    local on = xmlNodeGetAttribute(node, "music") ~= "0"
    xmlUnloadFile(node)
    return on
end

local function saveMusicPref(on)
    local node = fileExists(PREFS_FILE) and xmlLoadFile(PREFS_FILE) or xmlCreateFile(PREFS_FILE, "prefs")
    if not node then return end
    xmlNodeSetAttribute(node, "music", on and "1" or "0")
    xmlSaveFile(node)
    xmlUnloadFile(node)
end

-- Lleva el volumen de la musica a "target" en "ms"; si stop, la destruye al terminar
local function fadeMusic(target, ms, stop)
    if not isElement(music) then return end
    if isTimer(musicFade) then killTimer(musicFade) end
    local from, steps = getSoundVolume(music), math.max(1, math.floor(ms / 50))
    local i = 0
    musicFade = setTimer(function()
        i = i + 1
        if not isElement(music) then return end
        setSoundVolume(music, from + (target - from) * (i / steps))
        if i >= steps then
            musicFade = nil
            if stop then destroyElement(music); music = nil end
        end
    end, 50, steps)
end

local function startMusic()
    if isElement(music) or not musicOn then return end
    music = playSound("music/login.mp3", true)
    if not music then return end
    setSoundVolume(music, 0)
    fadeMusic(MUSIC_VOLUME, 2500)
end

local function setMusicOn(on)
    musicOn = on and true or false
    saveMusicPref(musicOn)
    if musicOn then
        startMusic()
    elseif isElement(music) then
        fadeMusic(0, 600, true)
    end
    callJS(("RP.setMusic(%s)"):format(musicOn and "true" or "false"))
    return musicOn
end

-- Exports de cliente: la seleccion de personajes (rp_characters) usa el mismo boton
function isLoginMusicOn() return musicOn end
function toggleLoginMusic() return setMusicOn(not musicOn) end

-- Al entrar al juego con un personaje: la musica se apaga con un fundido
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and new then
        if isElement(music) then fadeMusic(0, 2500, true) end
    end
end, false)

----------------------------------------------------------------
-- Recorrido cinematografico por Los Santos
-- Cada plano: posicion de camara y punto de mira al inicio y al final,
-- duracion (ms), fov y balanceo. Se interpola con suavizado y un leve
-- movimiento "de mano"; entre planos hay un fundido a negro.
----------------------------------------------------------------
local SHOTS = {
    -- Letrero de Vinewood, travelling lateral
    { name = "Vinewood", from = { 1290, -930, 112 }, to = { 1470, -950, 106 }, look = { 1395, -805, 88 }, lookTo = { 1440, -800, 86 }, ms = 11000, fov = 55 },
    -- Rascacielos del centro, vuelo en grua
    { name = "Downtown", from = { 1290, -1520, 150 }, to = { 1400, -1190, 175 }, look = { 1560, -1340, 95 }, lookTo = { 1590, -1290, 110 }, ms = 12000, fov = 65, roll = 4 },
    -- Grove Street desde arriba
    { name = "Grove Street", from = { 2455, -1630, 38 }, to = { 2535, -1635, 34 }, look = { 2495, -1690, 14 }, lookTo = { 2500, -1685, 14 }, ms = 10000, fov = 60 },
    -- Muelle de Santa Maria sobre el agua
    { name = "Santa Maria Beach", from = { 690, -2120, 18 }, to = { 785, -2160, 26 }, look = { 836, -1980, 12 }, lookTo = { 836, -2005, 12 }, ms = 11000, fov = 58, roll = -3 },
    -- Pista del aeropuerto a ras de suelo
    { name = "Aeropuerto de Los Santos", from = { 1580, -2425, 28 }, to = { 1980, -2425, 40 }, look = { 1800, -2493, 13 }, lookTo = { 2200, -2493, 13 }, ms = 10000, fov = 70 },
    -- Panoramica de la ciudad desde Mulholland
    { name = "Mulholland", from = { 1080, -810, 118 }, to = { 1260, -775, 128 }, look = { 1500, -1300, 60 }, lookTo = { 1660, -1360, 62 }, ms = 13000, fov = 62, roll = 2 },
}
local FADE_MS = 900

local cinema = { active = false, shot = 1, start = 0 }

local function announceShot()
    callJS(("RP.setLocation(%s)"):format(jsString(SHOTS[cinema.shot].name)))
end

local function ease(t) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end

local function cinemaRender()
    local now = getTickCount()
    local s = SHOTS[cinema.shot]
    local elapsed = now - cinema.start
    if elapsed >= s.ms then
        cinema.shot = cinema.shot % #SHOTS + 1
        cinema.start, elapsed, s = now, 0, SHOTS[cinema.shot]
        announceShot()
    end
    local t = ease(elapsed / s.ms)
    -- balanceo de camara en mano: unos centimetros, nunca mareo
    local sway = now / 1000
    local sx, sz = math.sin(sway * 0.7) * 0.35, math.sin(sway * 0.9 + 1) * 0.25
    setCameraMatrix(
        lerp(s.from[1], s.to[1], t) + sx, lerp(s.from[2], s.to[2], t), lerp(s.from[3], s.to[3], t) + sz,
        lerp(s.look[1], s.lookTo[1], t), lerp(s.look[2], s.lookTo[2], t), lerp(s.look[3], s.lookTo[3], t),
        (s.roll or 0) * (1 - t) + math.sin(sway * 0.5) * 0.6, s.fov or 60)

    -- fundido a negro al entrar y al salir de cada plano
    local alpha = 0
    if elapsed < FADE_MS then alpha = 1 - elapsed / FADE_MS
    elseif elapsed > s.ms - FADE_MS then alpha = (elapsed - (s.ms - FADE_MS)) / FADE_MS end
    if alpha > 0 then dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, 255 * alpha)) end
end

local function startCinema()
    if cinema.active then return end
    cinema.active, cinema.shot, cinema.start = true, math.random(#SHOTS), getTickCount()
    addEventHandler("onClientRender", root, cinemaRender)
end

local function stopCinema()
    if not cinema.active then return end
    cinema.active = false
    removeEventHandler("onClientRender", root, cinemaRender)
end

----------------------------------------------------------------
-- Pantalla de login
----------------------------------------------------------------
local function showLoginScreen()
    if isElement(browserGui) then return end

    showChat(false)
    setPlayerHudComponentVisible("all", false)
    fadeCamera(true, 2)
    startCinema()
    musicOn = loadMusicPref()
    startMusic()

    -- guiCreateBrowser gestiona raton y teclado automaticamente (local = true)
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)

    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        callJS(("RP.setMusic(%s)"):format(musicOn and "true" or "false"))
        if cinema.active then announceShot() end
        local user, pass = loadSaved()
        if user then
            callJS(("RP.setSaved(%s, %s)"):format(jsString(user), jsString(pass)))
        end
    end)

    showCursor(true)
    guiSetInputEnabled(true)
end

-- Solo cierra la interfaz de login; la camara, el HUD y el chat los gestiona
-- rp_characters, que muestra la seleccion de personajes a continuacion.
local function hideLoginScreen()
    stopCinema()
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser = nil, nil
    showCursor(false)
end

----------------------------------------------------------------
-- Puente JS -> servidor (validacion basica; la real esta en el servidor)
----------------------------------------------------------------
local function forward(serverEvent)
    return function(username, password, remember)
        if type(username) ~= "string" or type(password) ~= "string" then return end
        if #username > 24 or #password > 64 then return end
        if serverEvent == "rp:auth:login" then
            -- llega como texto desde el CEF ("true"/"false")
            local wants = remember == true or remember == "true"
            pendingRemember = wants and { username, password } or false
        end
        triggerServerEvent(serverEvent, resourceRoot, username, password)
    end
end

addEventHandler("rp:ui:login", root, forward("rp:auth:login"))
addEventHandler("rp:ui:register", root, forward("rp:auth:register"))
addEventHandler("rp:ui:music", root, function() toggleLoginMusic() end)

----------------------------------------------------------------
-- Respuestas del servidor
----------------------------------------------------------------
addEventHandler("rp:auth:result", resourceRoot, function(ok, message, form)
    callJS(("RP.onResult(%s, %s, %s)"):format(ok and "true" or "false", jsString(message), jsString(form)))
end)

addEventHandler("rp:auth:success", resourceRoot, function(username)
    -- Login correcto: guarda u olvida segun la casilla "Recordar"
    if pendingRemember then
        writeSaved(pendingRemember[1], pendingRemember[2])
    elseif pendingRemember == false then
        writeSaved(nil)
    end
    pendingRemember = nil
    -- la seleccion de personajes toma la camara enseguida: el recorrido para ya
    stopCinema()
    callJS(("RP.onSuccess(%s)"):format(jsString(username)))
    -- deja que la animacion de salida termine antes de cerrar el navegador
    setTimer(hideLoginScreen, 900, 1)
end)

addEventHandler("onClientResourceStart", resourceRoot, showLoginScreen)
addEventHandler("onClientResourceStop", resourceRoot, hideLoginScreen)
