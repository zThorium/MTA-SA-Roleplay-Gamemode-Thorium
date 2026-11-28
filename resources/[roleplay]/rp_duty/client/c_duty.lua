--[[
    rp_duty / c_duty.lua  (cliente)
    Aviso con la E dibujada junto a un vestuario o un garaje de facción y panel CEF (html/):
      - Vestuario: entrar o salir de servicio y, si eres líder, editar los uniformes.
      - Garaje: sacar vehículos de la facción y, si eres líder, comprarlos y venderlos.
        Al volante de un vehículo de la facción, E en el garaje lo guarda.
    El servidor valida todo.
]]

local sw, sh = guiGetScreenSize()
local near = nil          -- { id, label } del vestuario
local nearGarage = nil    -- { id, label } del garaje
local panelGui, panel, panelReady, queue = nil, nil, false, {}
local tex, font

addEvent("rp:duty:near", true)
addEvent("rp:duty:nearGarage", true)
addEvent("rp:duty:panel", true)
addEvent("rp:duty:garage", true)
addEvent("rp:duty:garageClose", true)

local function canInteract(allowVehicle)
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return false end
    if not allowVehicle and isPedInVehicle(localPlayer) then return false end
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

local function ensurePanel()
    if isElement(panelGui) then return end
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

-- toJSON envuelve en [ ]: se toma el primer elemento en el navegador
addEventHandler("rp:duty:panel", resourceRoot, function(data)
    ensurePanel()
    js(("window.dutyOpen(%s[0])"):format(toJSON(data, true)))
end)
addEventHandler("rp:duty:garage", resourceRoot, function(data)
    ensurePanel()
    js(("window.garageOpen(%s[0])"):format(toJSON(data, true)))
end)
addEventHandler("rp:duty:garageClose", resourceRoot, closePanel)

-- Del navegador
addEvent("rp:duty:ui:close", false)
addEventHandler("rp:duty:ui:close", root, closePanel)
addEvent("rp:duty:ui:action", false)
addEventHandler("rp:duty:ui:action", root, function(action, json)
    local d = type(json) == "string" and fromJSON(json) or {}
    triggerServerEvent("rp:duty:action", resourceRoot, tostring(action), type(d) == "table" and d or {})
end)
addEvent("rp:duty:ui:garage", false)
addEventHandler("rp:duty:ui:garage", root, function(action, json)
    local d = type(json) == "string" and fromJSON(json) or {}
    triggerServerEvent("rp:duty:garageAction", resourceRoot, tostring(action), type(d) == "table" and d or {})
end)

----------------------------------------------------------------
-- Aviso «Pulsa E»
----------------------------------------------------------------
addEventHandler("rp:duty:near", resourceRoot, function(id, label)
    near = id and { id = id, label = tostring(label or "Vestuario") } or nil
    if not near and not nearGarage and isElement(panelGui) then closePanel() end
end)
addEventHandler("rp:duty:nearGarage", resourceRoot, function(id, label)
    nearGarage = id and { id = id, label = tostring(label or "Garaje") } or nil
    if not near and not nearGarage and isElement(panelGui) then closePanel() end
end)

-- Qué hace la E ahora (o nil: la E no es nuestra)
local function currentAction()
    if nearGarage and canInteract(true) then
        local v = getPedOccupiedVehicle(localPlayer)
        if not v then return "garage", nearGarage.label end
        if getVehicleController(v) == localPlayer and getElementData(v, "rp:factionVehicle") then
            return "garage", "Guardar el vehículo en el garaje"
        end
        return nil
    end
    if near and canInteract(false) then return "locker", near.label end
    return nil
end

local function onKeyE()
    local kind = currentAction()
    if kind == "garage" then triggerServerEvent("rp:duty:garageUse", resourceRoot)
    elseif kind == "locker" then triggerServerEvent("rp:duty:use", resourceRoot, near.id) end
end

addEventHandler("onClientRender", root, function()
    if isElement(panelGui) then return end
    local kind, text = currentAction()
    if not kind then return end
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.78
    local c = DUTY.MARKER_COLOR
    dxDrawRectangle(x, y, w, 40, tocolor(12, 16, 24, 205))
    dxDrawRectangle(x, y + 38, w, 2, tocolor(c[1], c[2], c[3], 255))
    dxDrawImage(x + 8, y + 4, 32, 32, tex)
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex = dxCreateTexture("images/keyboard_e.png")
    font = dxCreateFont("html/fonts/rubik_medium.ttf", 12) or "default-bold"
    bindKey("e", "down", onKeyE)
end)

addEventHandler("onClientResourceStop", resourceRoot, closePanel)
