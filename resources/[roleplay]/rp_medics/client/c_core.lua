--[[
    rp_medics / c_core.lua  (cliente)

    - Aviso "E" en el vestuario y el garaje del hospital.
    - Panel CEF del vestuario (con cursor): uniforme, servicio y casillero personal.
    El cliente solo pide: el servidor revalida facción, cercanía y estado.
]]

local sw, sh = guiGetScreenSize()
local panelGui, panel, panelReady, panelQueue = nil, nil, false, {}
local points = {}                -- [kind] = { x, y, z }
local near = nil                 -- "locker" | "garage"
local tex = {}
local font

addEvent("rp:medics:points", true)
addEvent("rp:medics:lockerOpen", true)
addEvent("rp:medics:ui:action", false)
addEvent("rp:medics:ui:close", false)

local function json(t) return toJSON(t or {}, true) .. "[0]" end   -- toJSON envuelve en [ ]

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if getElementData(localPlayer, "rp:downed") then return false end
    local ok, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    return not (ok and sup)
end

----------------------------------------------------------------
-- Panel del vestuario
----------------------------------------------------------------
local function panelJS(code)
    if isElement(panel) and panelReady then executeBrowserJavascript(panel, code) else panelQueue[#panelQueue + 1] = code end
end

local function closePanel()
    if not isElement(panelGui) then return end
    destroyElement(panelGui)
    panelGui, panel, panelReady, panelQueue = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function openPanel(data)
    if not isElement(panelGui) then
        panelGui = guiCreateBrowser(0, 0, sw, sh, true, true, false)
        panel = guiGetBrowser(panelGui)
        panelReady, panelQueue = false, {}
        addEventHandler("onClientBrowserCreated", panel, function()
            loadBrowserURL(source, "http://mta/local/html/index.html")
        end)
        addEventHandler("onClientBrowserDocumentReady", panel, function()
            panelReady = true
            for _, c in ipairs(panelQueue) do executeBrowserJavascript(source, c) end
            panelQueue = {}
        end)
        showCursor(true)
        guiSetInputEnabled(true)
    end
    panelJS(("MD.panel(%s)"):format(json(data)))
end

addEventHandler("rp:medics:lockerOpen", resourceRoot, openPanel)
addEventHandler("rp:medics:ui:close", root, closePanel)
addEventHandler("rp:medics:ui:action", root, function(action, a, b)
    if type(action) ~= "string" then return end
    triggerServerEvent("rp:medics:panel", resourceRoot, action, a, b)
end)
addEventHandler("onClientPlayerWasted", localPlayer, closePanel)

-- Si se aleja del vestuario con el panel abierto, se cierra
setTimer(function()
    if isElement(panelGui) and near ~= "locker" then closePanel() end
end, 500, 0)

----------------------------------------------------------------
-- Cercanía y tecla E
----------------------------------------------------------------
setTimer(function()
    near = nil
    if getElementDimension(localPlayer) ~= 0 or getElementInterior(localPlayer) ~= 0 then return end
    local px, py, pz = getElementPosition(localPlayer)
    for kind, pt in pairs(points) do
        if (not isPedInVehicle(localPlayer) or kind == "garage")
            and getDistanceBetweenPoints3D(px, py, pz, pt.x, pt.y, pt.z) <= MED.INTERACT_RADIUS then
            near = kind
            return
        end
    end
end, 200, 0)

local PROMPT = { locker = "Vestuario y casillero", garage = "Sacar o guardar ambulancia" }

local function onKeyE()
    if not near or not canInteract() then return end              -- E no es nuestra fuera de nuestros puntos
    triggerServerEvent("rp:medics:use", resourceRoot, near)
end

addEventHandler("onClientRender", root, function()
    if not near or not canInteract() then return end
    local text = PROMPT[near]
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawRectangle(x, y, w, 40, tocolor(14, 12, 14, 200))
    dxDrawRectangle(x, y + 38, w, 2, tocolor(229, 72, 77, 255))
    dxDrawImage(x + 8, y + 4, 32, 32, tex.e)
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("rp:medics:points", resourceRoot, function(list) points = type(list) == "table" and list or {} end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.e = dxCreateTexture("images/keys/keyboard_e.png")
    font = dxCreateFont("html/fonts/rubik_medium.ttf", 12) or "default-bold"
    bindKey("e", "down", onKeyE)
    triggerServerEvent("rp:medics:requestPoints", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, closePanel)
