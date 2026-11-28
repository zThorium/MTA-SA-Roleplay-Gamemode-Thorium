--[[
    rp_duty / c_duty.lua  (cliente)
    Aviso «E · Vestuario» junto a un vestuario y panel CEF (html/) para entrar o salir de
    servicio y, si eres líder, editar los uniformes. El servidor valida todo.
]]

local sw, sh = guiGetScreenSize()
local near = nil          -- { id, label }
local panelGui, panel, panelReady, queue = nil, nil, false, {}
local tex, font

addEvent("rp:duty:near", true)
addEvent("rp:duty:panel", true)

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isPedInVehicle(localPlayer) then return false end
    if getElementData(localPlayer, "rp:downed") then return false end
    local ok, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    return not (ok and sup)
end

----------------------------------------------------------------
-- Panel CEF
----------------------------------------------------------------
local function js(code)
    if isElement(panel) and panelReady then executeBrowserJavascript(panel, code) else queue[#queue + 1] = code end
end

local function closePanel()
    if isElement(panelGui) then destroyElement(panelGui) end
    panelGui, panel, panelReady, queue = nil, nil, false, {}
    showCursor(false)
    guiSetInputMode("allow_binds")
end

local function openPanel(data)
    if not isElement(panelGui) then
        panelGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
        panel = guiGetBrowser(panelGui)
        addEventHandler("onClientBrowserCreated", panel, function()
            loadBrowserURL(source, "http://mta/local/html/index.html")
        end)
        addEventHandler("onClientBrowserDocumentReady", panel, function()
            panelReady = true
            for _, c in ipairs(queue) do executeBrowserJavascript(source, c) end
            queue = {}
        end)
        showCursor(true)
        guiSetInputMode("no_binds_when_editing")
    end
    js(("window.dutyOpen(%s[0])"):format(toJSON(data, true)))   -- toJSON envuelve en [ ]
end
addEventHandler("rp:duty:panel", resourceRoot, openPanel)

-- Del navegador
addEvent("rp:duty:ui:close", false)
addEventHandler("rp:duty:ui:close", root, closePanel)
addEvent("rp:duty:ui:action", false)
addEventHandler("rp:duty:ui:action", root, function(action, json)
    local d = type(json) == "string" and fromJSON(json) or {}
    triggerServerEvent("rp:duty:action", resourceRoot, tostring(action), type(d) == "table" and d or {})
end)

----------------------------------------------------------------
-- Aviso «Pulsa E»
----------------------------------------------------------------
addEventHandler("rp:duty:near", resourceRoot, function(id, label)
    near = id and { id = id, label = tostring(label or "Vestuario") } or nil
    if not near and isElement(panelGui) then closePanel() end
end)

local function onKeyE()
    if not near or not canInteract() then return end    -- fuera de un vestuario la E no es nuestra
    triggerServerEvent("rp:duty:use", resourceRoot, near.id)
end

addEventHandler("onClientRender", root, function()
    if not near or isElement(panelGui) or not canInteract() then return end
    local text = near.label
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawRectangle(x, y, w, 40, tocolor(12, 16, 24, 205))
    dxDrawRectangle(x, y + 38, w, 2, tocolor(DUTY.MARKER_COLOR[1], DUTY.MARKER_COLOR[2], DUTY.MARKER_COLOR[3], 255))
    dxDrawImage(x + 8, y + 4, 32, 32, tex)
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex = dxCreateTexture("images/keyboard_e.png")
    font = dxCreateFont("html/fonts/rubik_medium.ttf", 12) or "default-bold"
    bindKey("e", "down", onKeyE)
end)

addEventHandler("onClientResourceStop", resourceRoot, closePanel)
