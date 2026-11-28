--[[
    rp_quiz / c_quiz.lua  (cliente)
    - Cuestionario de rol en CEF (html/), sobre la pantalla de personajes. El servidor corrige.
    - Tutorial jugable la primera vez que entra un personaje: una tarjeta arriba a la derecha con
      la tecla dibujada de cada paso; el paso se cumple al hacerlo (moverse, abrir el chat, el
      inventario, el teléfono, el mapa y la ayuda). /saltartutorial lo salta.
]]

local sw, sh = guiGetScreenSize()
local S = math.max(0.8, math.min(1.25, sh / 900))

----------------------------------------------------------------
-- Cuestionario (CEF)
----------------------------------------------------------------
local gui, browser, ready, queue = nil, nil, false, {}
local prevInput = false   -- la pantalla de personajes puede tener la entrada de texto activa

addEvent("rp:quiz:open", true)
addEvent("rp:quiz:result", true)

local function js(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code) else queue[#queue + 1] = code end
end

local function closeQuiz()
    if isElement(gui) then destroyElement(gui) end
    gui, browser, ready, queue = nil, nil, false, {}
    guiSetInputEnabled(prevInput)
end

local function openQuiz(data)
    if not isElement(gui) then
        gui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
        browser = guiGetBrowser(gui)
        addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
        addEventHandler("onClientBrowserDocumentReady", browser, function()
            ready = true
            for _, c in ipairs(queue) do executeBrowserJavascript(source, c) end
            queue = {}
        end)
        guiBringToFront(gui)
        prevInput = guiGetInputEnabled()
        guiSetInputEnabled(true)
        showCursor(true)
    end
    js(("Quiz.open(%s[0])"):format(toJSON(data, true)))
end

addEventHandler("rp:quiz:open", resourceRoot, openQuiz)
addEventHandler("rp:quiz:result", resourceRoot, function(r) js(("Quiz.result(%s[0])"):format(toJSON(r, true))) end)

addEvent("rp:quiz:ui:submit", false)
addEventHandler("rp:quiz:ui:submit", root, function(json)
    local a = type(json) == "string" and #json < 500 and fromJSON(json)
    if type(a) == "table" then triggerServerEvent("rp:quiz:submit", resourceRoot, a) end
end)
addEvent("rp:quiz:ui:retry", false)
addEventHandler("rp:quiz:ui:retry", root, function() triggerServerEvent("rp:quiz:request", resourceRoot) end)
-- Al cerrar tras aprobar se vuelve a la pantalla de personajes (que sigue abierta debajo)
addEvent("rp:quiz:ui:close", false)
addEventHandler("rp:quiz:ui:close", root, closeQuiz)

----------------------------------------------------------------
-- Tutorial jugable
----------------------------------------------------------------
local STEPS = {
    { keys = { "w", "a", "s", "d" }, title = "Muévete", text = "Camina unos pasos con W A S D." },
    { keys = { "t" },   title = "Habla", text = "Pulsa T para abrir el chat y saluda. Lo que escribes lo oye quien está cerca." },
    { keys = { "i" },   title = "Tu inventario", text = "Pulsa I para ver lo que llevas encima." },
    { keys = { "p" },   title = "Tu teléfono", text = "Pulsa P: mensajes, banco, Vroom para viajar y más." },
    { keys = { "f11" }, title = "El mapa", text = "Pulsa F11. Haz clic en un lugar para poner ruta con el GPS. Busca la Agencia de empleo para tu primer trabajo." },
    { keys = { "f1" },  title = "Ayuda", text = "Pulsa F1 cuando tengas dudas: reglas, teclas y reportes." },
}
local tut = nil         -- { step, start = {x,y,z}, chatOpened, shown }
local tex, fTitle, fText = {}, nil, nil

local function playStep()
    local s = playSound("sounds/confirmation_002.ogg")
    if s then setSoundVolume(s, 0.5) end
end

local function nextStep()
    if not tut then return end
    tut.step = tut.step + 1
    tut.shown = getTickCount()
    playStep()
    if tut.step > #STEPS then
        tut = nil
        triggerServerEvent("rp:quiz:tutorialDone", resourceRoot, true)
        exports.rp_notify:notify("¡Tutorial terminado! Ya sabes lo básico. Busca la Agencia de empleo en el mapa (F11) para empezar a ganar dinero.", "success")
    end
end

addEvent("rp:quiz:tutorial", true)
addEventHandler("rp:quiz:tutorial", resourceRoot, function()
    local x, y, z = getElementPosition(localPlayer)
    tut = { step = 1, start = { x, y, z }, shown = getTickCount() }
end)

addEvent("rp:quiz:tutorialStop", true)
addEventHandler("rp:quiz:tutorialStop", resourceRoot, function() tut = nil end)

addCommandHandler("saltartutorial", function()
    if not tut then return end
    tut = nil
    triggerServerEvent("rp:quiz:tutorialDone", resourceRoot, false)
    exports.rp_notify:notify("Saltaste el tutorial. Tienes la ayuda en F1.", "info")
end)

-- Detección de cada paso
local KEY_STEP = { i = 3, p = 4, f11 = 5, f1 = 6 }
addEventHandler("onClientKey", root, function(key, press)
    if not press or not tut then return end
    if KEY_STEP[key] == tut.step then setTimer(nextStep, 600, 1) end
end)

local stepTimer = setTimer(function()
    if not tut then return end
    if tut.step == 1 then
        local x, y, z = getElementPosition(localPlayer)
        if getDistanceBetweenPoints3D(x, y, z, tut.start[1], tut.start[2], tut.start[3]) > 6 then nextStep() end
    elseif tut.step == 2 then
        if isChatBoxInputActive() then tut.chatOpened = true
        elseif tut.chatOpened then nextStep() end
    end
end, 250, 0)

addEventHandler("onClientRender", root, function()
    if not tut or not STEPS[tut.step] then return end
    local ok, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    if ok and sup then return end
    local st = STEPS[tut.step]
    local w, h = 340 * S, 150 * S
    local x, y = sw - w - 24 * S, sh * 0.30
    local appear = math.min(1, (getTickCount() - tut.shown) / 300)
    x = x + (1 - appear) * 40 * S
    local a = math.floor(255 * appear)
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 18, 225 * appear))
    dxDrawRectangle(x, y, 4 * S, h, tocolor(245, 165, 36, a))
    dxDrawText(("TUTORIAL · PASO %d DE %d"):format(tut.step, #STEPS), x + 18 * S, y + 12 * S, 0, 0, tocolor(245, 165, 36, a), 1, fText)
    dxDrawText(st.title, x + 18 * S, y + 30 * S, 0, 0, tocolor(255, 255, 255, a), 1, fTitle)
    local kx = x + 18 * S
    for _, k in ipairs(st.keys) do
        dxDrawImage(kx, y + 58 * S, 34 * S, 34 * S, tex[k], 0, 0, 0, tocolor(255, 255, 255, a))
        kx = kx + 38 * S
    end
    dxDrawText(st.text, x + 18 * S, y + 96 * S, x + w - 14 * S, y + h - 18 * S, tocolor(210, 218, 230, a), 1, fText, "left", "top", true, true)
    dxDrawText("/saltartutorial para saltarlo", x, y + h - 16 * S, x + w - 12 * S, y + h, tocolor(130, 140, 155, a), 0.85, fText, "right", "top")
    -- Puntos de progreso
    for i = 1, #STEPS do
        local c = i < tut.step and tocolor(76, 211, 138, a) or (i == tut.step and tocolor(245, 165, 36, a) or tocolor(80, 86, 98, a))
        dxDrawRectangle(x + w - (#STEPS - i + 1) * 14 * S - 10 * S, y + 16 * S, 9 * S, 9 * S, c)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, k in ipairs({ "w", "a", "s", "d", "t", "i", "p", "f11", "f1" }) do tex[k] = dxCreateTexture("images/keyboard_" .. k .. ".png") end
    fText = dxCreateFont("html/fonts/rubik_medium.ttf", math.floor(10 * S + 0.5)) or "default"
    fTitle = dxCreateFont("html/fonts/rubik_semibold.ttf", math.floor(15 * S + 0.5)) or "default-bold"
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(stepTimer) then killTimer(stepTimer) end
    closeQuiz()
end)
