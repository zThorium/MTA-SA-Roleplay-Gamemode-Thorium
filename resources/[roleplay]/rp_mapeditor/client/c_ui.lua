--[[
    rp_mapeditor / c_ui.lua
    Paneles CEF con la organización del editor de mapas de MTA: lo mínimo siempre a la vista y el
    resto en ventanas que se abren al usarlas (en pantallas pequeñas el mundo queda libre).

        top    barra de iconos arriba a la izquierda (proyecto, publicar, deshacer, gizmo, probar...)
        dock   columna de iconos a la izquierda: un botón por tipo de elemento y «quitar del mapa»
        win    ventana flotante junto al dock: navegador de modelos, opciones de marcador/pickup/punto
               o la lista de elementos. Se cierra sola al elegir un modelo
        props  ventana flotante a la derecha: propiedades de lo elegido (doble clic o Enter)
        modal  pantalla completa: proyectos, ajustes, versiones, importar y exportar

    Un navegador opaco por panel (MTA solo acepta clics sobre píxeles opacos del navegador).
    Lua -> JS:  MEUI.push(panel | "all", tipo, datos)       -> ME.recv(tipo, datos) en app.js
    JS -> Lua:  mta.triggerEvent("rp:me:ui", accion, json)   -> MEEditor.ui(accion, datos)
]]

MEUI = {}

local screenW, screenH = guiGetScreenSize()
local panels = {}      -- [nombre] = { gui, browser, ready, pending, shown }
local hidden = false   -- H: oculta todo menos el modal

addEvent("rp:me:ui", false)

local TOP_H, DOCK_W, GAP = 40, 46, 6
local DOCK_ITEMS = 7

local RECTS = {
    top   = function() return 0, 0, math.min(screenW, 690), TOP_H end,
    dock  = function() return 0, TOP_H + GAP, DOCK_W, math.min(screenH - TOP_H - 60, DOCK_ITEMS * 44 + 10) end,
    win   = function()
        local w = math.min(380, math.floor(screenW * 0.32))
        return DOCK_W + GAP, TOP_H + GAP, w, math.min(620, screenH - TOP_H - 70)
    end,
    props = function()
        local w = math.min(310, math.floor(screenW * 0.26))
        return screenW - w - GAP, TOP_H + GAP, w, math.min(600, screenH - TOP_H - 70)
    end,
    modal = function() return 0, 0, screenW, screenH end,
}
local ALWAYS = { top = true, dock = true }

function MEUI.rect(name) return RECTS[name]() end

local function create(name)
    if panels[name] then return panels[name] end
    local x, y, w, h = RECTS[name]()
    local gui = guiCreateBrowser(x, y, w, h, true, name == "modal", false)
    local browser = guiGetBrowser(gui)
    local p = { gui = gui, browser = browser, ready = false, pending = {}, shown = true }
    panels[name] = p
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html#" .. name)
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        if panels[name] ~= p then return end
        p.ready = true
        for _, code in ipairs(p.pending) do executeBrowserJavascript(source, code) end
        p.pending = {}
    end)
    if hidden and name ~= "modal" then guiSetVisible(gui, false) end
    return p
end

local function js(name, code)
    local p = panels[name]
    if not p then return end
    if p.ready and isElement(p.browser) then executeBrowserJavascript(p.browser, code)
    else p.pending[#p.pending + 1] = code end
end

-- datos siempre como JSON (toJSON envuelve en [ ], de ahí el [0]). JS -> Lua manda siempre un
-- objeto: fromJSON toma un array de primer nivel como lista de argumentos
function MEUI.push(name, kind, data)
    if data == nil then data = false end
    local code = "ME.recv(\"" .. tostring(kind) .. "\", " .. toJSON(data, true) .. "[0])"
    if name == "all" then
        for n in pairs(panels) do js(n, code) end
    else
        js(name, code)
    end
end

-- Las ventanas flotantes se crean una vez y se muestran u ocultan (así conservan su estado)
function MEUI.show(name, on)
    local p = on and create(name) or panels[name]
    if not p then return end
    p.shown = on == true
    guiSetVisible(p.gui, p.shown and not hidden)
    if p.shown then guiBringToFront(p.gui) else MEUI.typing(false) end
    if MEEditor and MEEditor.onPanels then MEEditor.onPanels() end
end

function MEUI.isShown(name)
    local p = panels[name]
    return p ~= nil and p.shown and not hidden
end

function MEUI.openEditor()
    hidden = false
    for n in pairs(ALWAYS) do create(n) end
    -- se crean ya (ocultas) para que el catálogo y las miniaturas estén listos al abrirlas
    create("win").shown = false
    guiSetVisible(panels.win.gui, false)
    create("props").shown = false
    guiSetVisible(panels.props.gui, false)
end

function MEUI.closeEditor()
    for _, n in ipairs({ "top", "dock", "win", "props" }) do
        local p = panels[n]
        if p and isElement(p.gui) then destroyElement(p.gui) end
        panels[n] = nil
    end
end

function MEUI.openModal()
    local p = create("modal")
    p.shown = true
    guiSetVisible(p.gui, true)
    guiBringToFront(p.gui)
    showCursor(true)
end

function MEUI.closeModal()
    local p = panels.modal
    if p and isElement(p.gui) then destroyElement(p.gui) end
    panels.modal = nil
    MEUI.typing(false)
    if not (MEEditor and MEEditor.active) then showCursor(false) end
end

function MEUI.modalOpen() return panels.modal ~= nil end

function MEUI.setHidden(on)
    hidden = on
    for n, p in pairs(panels) do
        if n ~= "modal" and isElement(p.gui) then guiSetVisible(p.gui, p.shown and not on) end
    end
end

function MEUI.isHidden() return hidden end

-- ¿el cursor está sobre un panel visible?
function MEUI.overUI()
    if panels.modal then return true end
    if hidden then return false end
    local cx, cy = getCursorPosition()
    if not cx then return true end
    local ax, ay = cx * screenW, cy * screenH
    for n, p in pairs(panels) do
        if n ~= "modal" and p.shown and isElement(p.gui) then
            local x, y, w, h = RECTS[n]()
            if ax >= x and ax <= x + w and ay >= y and ay <= y + h then return true end
        end
    end
    return false
end

-- Escribir en un campo: el teclado va al navegador y no mueve la cámara
local typingNow = false
function MEUI.typing(on, panelName)
    typingNow = on == true
    if typingNow then
        local p = panels[panelName or "modal"]
        if p and isElement(p.browser) then focusBrowser(p.browser) end
        guiSetInputEnabled(true)
    else
        pcall(focusBrowser)
        guiSetInputEnabled(false)
    end
end

function MEUI.isTyping() return typingNow end

function MEUI.destroyAll()
    for _, p in pairs(panels) do if isElement(p.gui) then destroyElement(p.gui) end end
    panels = {}
    MEUI.typing(false)
end

addEventHandler("rp:me:ui", root, function(action, json)
    local data = json and json ~= "" and fromJSON(json) or nil
    if action == "typing" then
        return MEUI.typing(data and data.on, data and data.panel)
    end
    if MEEditor and MEEditor.ui then MEEditor.ui(tostring(action), data) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function() MEUI.destroyAll() end)
