--[[
    rp_factionduty / c_duty.lua  (cliente)

    - Aviso "E" (tecla dibujada) junto al vestuario de TU facción; en los de otras no aparece nada.
    - Panel CEF (con cursor) en dos modos: vestuario (elegir equipo, entrar/salir de servicio)
      y editor de equipos (lo abre F3 › Uniformes y equipo).
    El cliente solo pide: el servidor revalida facción, cercanía, rol y objetos.
]]

local sw, sh = guiGetScreenSize()
local lockers = {}            -- { { id, factionId, x, y, z, interior, dimension } }
local near = nil              -- id del vestuario cercano
local panelGui, panel, panelReady, panelQueue = nil, nil, false, {}
local tex, font

addEvent("rp:factionduty:lockers", true)
addEvent("rp:factionduty:panel", true)
addEvent("rp:factionduty:openEditor", false)    -- lo dispara rp_factions (F3)
addEvent("rp:factionduty:ui:action", false)
addEvent("rp:factionduty:ui:close", false)

local function json(t) return toJSON(t or {}, true) .. "[0]" end   -- toJSON envuelve en [ ]

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if getElementData(localPlayer, "rp:downed") or isPedInVehicle(localPlayer) then return false end
    local ok, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    return not (ok and sup)
end

local function myFactionId()
    local f = getElementData(localPlayer, "rp:faction")
    return type(f) == "table" and f.id or nil
end

----------------------------------------------------------------
-- Panel
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
    panelJS(("FDUTY.show(%s)"):format(json(data)))
end

addEventHandler("rp:factionduty:panel", resourceRoot, openPanel)
addEventHandler("rp:factionduty:ui:close", root, closePanel)

-- El HTML manda la acción y un JSON; se reenvía y el servidor valida
addEventHandler("rp:factionduty:ui:action", root, function(action, text)
    if type(action) ~= "string" or type(text) ~= "string" or #text > 4000 then return end
    local data = fromJSON(text)
    triggerServerEvent("rp:factionduty:action", resourceRoot, action, type(data) == "table" and data or {})
end)

addEventHandler("rp:factionduty:openEditor", localPlayer, function()
    triggerServerEvent("rp:factionduty:editorOpen", resourceRoot)
end)

addEventHandler("onClientPlayerWasted", localPlayer, closePanel)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, closePanel)

----------------------------------------------------------------
-- Cercanía y tecla E
----------------------------------------------------------------
local function findNear()
    local fid = myFactionId()
    if not fid then return nil end
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local px, py, pz = getElementPosition(localPlayer)
    for _, l in ipairs(lockers) do
        if l.factionId == fid and l.interior == int and l.dimension == dim
            and getDistanceBetweenPoints3D(px, py, pz, l.x, l.y, l.z) <= FDUTY.INTERACT_RADIUS then
            return l.id
        end
    end
end

setTimer(function() near = findNear() end, 200, 0)

local function onKeyE()
    if not near or not canInteract() then return end     -- fuera de un vestuario propio, E no es nuestra
    triggerServerEvent("rp:factionduty:use", resourceRoot, near)
end

addEventHandler("onClientRender", root, function()
    if not near or not canInteract() then return end
    local onDuty = getElementData(localPlayer, "rp:factionDuty") == true
    local text = onDuty and "Vestuario · salir de servicio o cambiar de equipo" or "Vestuario · entrar de servicio"
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawRectangle(x, y, w, 40, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y + 38, w, 2, tocolor(FDUTY.COLOR[1], FDUTY.COLOR[2], FDUTY.COLOR[3], 255))
    dxDrawImage(x + 8, y + 4, 32, 32, tex)
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("rp:factionduty:lockers", resourceRoot, function(list)
    lockers = type(list) == "table" and list or {}
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex = dxCreateTexture("images/keyboard_e.png")
    font = dxCreateFont("html/fonts/rubik_medium.ttf", 12) or "default-bold"
    bindKey("e", "down", onKeyE)
    triggerServerEvent("rp:factionduty:requestLockers", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, closePanel)
