--[[
    rp_firefighters / c_core.lua  (cliente)

    - Aviso "E" en vestuario y garaje de la estación, y junto a civiles atrapados.
    - HUD CEF (navegador dx sin entrada) para los bomberos de servicio: alerta entrante,
      temporizador, focos, civiles, guía del paso actual y tarjeta de resultado.
    - Panel CEF del vestuario (con cursor) para entrar o salir de servicio.
    - Barras de aire sobre los civiles con globo de estado.
    El cliente solo pide: el servidor revalida cercanía, servicio y estado.
]]

FDC = { incident = nil, onDuty = false }      -- compartido con c_fire.lua

local sw, sh = guiGetScreenSize()
local hud, hudReady, hudQueue = nil, false, {}
local panelGui, panel, panelReady, panelQueue = nil, nil, false, {}
local points = {}                -- [kind] = { x, y, z }
local near = nil                 -- { kind = "locker"|"garage"|"victim"|"drop", idx }
local tex = {}
local font

addEvent("rp:firefighters:points", true)
addEvent("rp:firefighters:lockerOpen", true)
addEvent("rp:firefighters:alert", true)
addEvent("rp:firefighters:incident", true)
addEvent("rp:firefighters:tick", true)
addEvent("rp:firefighters:result", true)
addEvent("rp:firefighters:fx", true)
addEvent("rp:firefighters:focusOut", true)
addEvent("rp:firefighters:ended", true)
addEvent("rp:firefighters:ui:duty", false)
addEvent("rp:firefighters:ui:off", false)
addEvent("rp:firefighters:ui:close", false)

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function json(t) return toJSON(t or {}, true) .. "[0]" end   -- toJSON envuelve en [ ]

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if getElementData(localPlayer, "rp:downed") then return false end
    local ok, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    return not (ok and sup)
end

local function dist3(x, y, z)
    local px, py, pz = getElementPosition(localPlayer)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z)
end

local function inWorld()
    return getElementDimension(localPlayer) == 0 and getElementInterior(localPlayer) == 0
end

----------------------------------------------------------------
-- HUD (navegador dx, sin entrada)
----------------------------------------------------------------
local function hudJS(code)
    if isElement(hud) and hudReady then executeBrowserJavascript(hud, code) else hudQueue[#hudQueue + 1] = code end
end
FDC.hudJS = hudJS

local function createHud()
    if isElement(hud) then return end
    hud = createBrowser(sw, sh, true, true)
    hudReady, hudQueue = false, hudQueue or {}
    addEventHandler("onClientBrowserCreated", hud, function()
        loadBrowserURL(source, "http://mta/local/html/index.html#hud")
    end)
    addEventHandler("onClientBrowserDocumentReady", hud, function()
        hudReady = true
        for _, c in ipairs(hudQueue) do executeBrowserJavascript(source, c) end
        hudQueue = {}
    end)
end

local function destroyHud()
    if isElement(hud) then destroyElement(hud) end
    hud, hudReady, hudQueue = nil, false, {}
end

-- El HUD se coloca bajo el bloque de arriba a la derecha de rp_hud (hora, dinero...)
setTimer(function()
    if not isElement(hud) then return end
    local ok, y = pcall(function() return exports.rp_hud:getTopRightBottom() end)
    hudJS(("FD.setTop(%d)"):format(ok and tonumber(y) or 200))
end, 1000, 0)

----------------------------------------------------------------
-- Panel del vestuario (navegador de GUI con cursor)
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
            loadBrowserURL(source, "http://mta/local/html/index.html#panel")
        end)
        addEventHandler("onClientBrowserDocumentReady", panel, function()
            panelReady = true
            for _, c in ipairs(panelQueue) do executeBrowserJavascript(source, c) end
            panelQueue = {}
        end)
        showCursor(true)
        guiSetInputEnabled(true)
    end
    panelJS(("FD.panel(%s)"):format(json(data)))
end

addEventHandler("rp:firefighters:lockerOpen", resourceRoot, openPanel)
addEventHandler("rp:firefighters:ui:close", root, closePanel)
addEventHandler("rp:firefighters:ui:duty", root, function(skin)
    triggerServerEvent("rp:firefighters:panel", resourceRoot, "duty_on", tonumber(skin))
end)
addEventHandler("rp:firefighters:ui:off", root, function()
    triggerServerEvent("rp:firefighters:panel", resourceRoot, "duty_off")
end)
addEventHandler("onClientPlayerWasted", localPlayer, closePanel)

----------------------------------------------------------------
-- Servicio
----------------------------------------------------------------
local function onDutyChanged(on)
    FDC.onDuty = on and true or false
    if FDC.onDuty then
        createHud()
        if FDC.incident then hudJS(("FD.incident(%s)"):format(json(FDC.incident))) end
    else
        destroyHud()
    end
end

addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:fireDuty" then onDutyChanged(new == true) end
end)

----------------------------------------------------------------
-- Incidente (estado que manda el servidor)
----------------------------------------------------------------
addEventHandler("rp:firefighters:incident", resourceRoot, function(data)
    FDC.incident = data or nil
    if FDC.onFire then FDC.onFire(FDC.incident) end            -- c_fire.lua
    if FDC.onDuty then hudJS(("FD.incident(%s)"):format(data and json(data) or "null")) end
end)

addEventHandler("rp:firefighters:tick", resourceRoot, function(t)
    local I = FDC.incident
    if not I or type(t) ~= "table" then return end
    I.timeLeft = t.t
    for i, hp in ipairs(t.f or {}) do if I.foci[i] then I.foci[i].hp = hp end end
    for i, v in ipairs(t.v or {}) do if I.victims[i] then I.victims[i].state, I.victims[i].life = v[1], v[2] end end
    if FDC.onDuty then
        hudJS(("FD.tick(%s, %s)"):format(json(t), jsString(FDC.guideStep())))
    end
end)

addEventHandler("rp:firefighters:alert", resourceRoot, function(a)
    if not FDC.onDuty then return end
    hudJS(("FD.alert(%s)"):format(json(a)))
    playSoundFrontEnd(42)                                  -- pitido de radio de GTA, junto a la alarma del HUD
end)

addEventHandler("rp:firefighters:result", resourceRoot, function(r)
    if FDC.onDuty then hudJS(("FD.result(%s)"):format(json(r))) end
end)

addEventHandler("rp:firefighters:fx", resourceRoot, function(kind)
    if FDC.onDuty then hudJS(("FD.sound(%s)"):format(jsString(kind))) end
end)

addEventHandler("rp:firefighters:ended", resourceRoot, function(id, success)
    local I = FDC.incident
    if I and I.id == id then I.ended = true end
    if FDC.onEnded then FDC.onEnded(id, success) end
end)

-- Paso actual de la guía (una sola cosa a la vez)
function FDC.guideStep()
    local I = FDC.incident
    if not I or I.ended then return "" end
    for _, v in ipairs(I.victims) do
        if isElement(v.ped) and getElementAttachedTo(v.ped) == localPlayer then
            return dist3(I.x, I.y, I.z) <= I.extractRadius + 1 and "drop" or "carry"
        end
    end
    if dist3(I.x, I.y, I.z) > 90 then return "goto" end
    local fire = false
    for _, f in ipairs(I.foci) do if f.hp > 0 then fire = true break end end
    local trapped = false
    for _, v in ipairs(I.victims) do if v.state == "trapped" then trapped = true break end end
    -- Si un civil se ahoga, primero él
    for _, v in ipairs(I.victims) do if v.state == "trapped" and v.life < 60 then return "rescue" end end
    if fire then return isPedInVehicle(localPlayer) and "cannon" or "extinguish" end
    if trapped then return "rescue" end
    return "wait"
end

----------------------------------------------------------------
-- Cercanía y tecla E
----------------------------------------------------------------
local function findNear()
    if not inWorld() then return nil end
    for kind, pt in pairs(points) do
        if not isPedInVehicle(localPlayer) or kind == "garage" then
            if dist3(pt.x, pt.y, pt.z) <= FIRE.INTERACT_RADIUS then return { kind = kind } end
        end
    end
    local I = FDC.incident
    if not FDC.onDuty or not I or I.ended or isPedInVehicle(localPlayer) then return nil end
    for i, v in ipairs(I.victims) do
        if isElement(v.ped) and getElementAttachedTo(v.ped) == localPlayer then
            return { kind = dist3(I.x, I.y, I.z) <= I.extractRadius + 1 and "drop" or "putdown", idx = i }
        end
    end
    for i, v in ipairs(I.victims) do
        if v.state == "trapped" and isElement(v.ped) then
            local x, y, z = getElementPosition(v.ped)
            if dist3(x, y, z) <= FIRE.INTERACT_RADIUS then return { kind = "victim", idx = i } end
        end
    end
end

setTimer(function() near = findNear() end, 200, 0)

local PROMPT = {
    locker = "Vestuario de bomberos", garage = "Sacar o guardar autobomba",
    victim = "Cargar al civil", drop = "Dejar a salvo", putdown = "Soltar al civil",
}

local function onKeyE()
    if not near or not canInteract() then return end              -- E no es nuestra fuera de nuestros puntos
    if near.kind == "locker" or near.kind == "garage" then
        triggerServerEvent("rp:firefighters:use", resourceRoot, near.kind)
    else
        triggerServerEvent("rp:firefighters:carry", resourceRoot, near.idx)
    end
end

----------------------------------------------------------------
-- Dibujo: aviso E y estado de los civiles
----------------------------------------------------------------
local function drawPrompt()
    if not near or not canInteract() then return end
    local text = PROMPT[near.kind] or ""
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawRectangle(x, y, w, 40, tocolor(14, 12, 12, 200))
    dxDrawRectangle(x, y + 38, w, 2, tocolor(235, 90, 40, 255))
    dxDrawImage(x + 8, y + 4, 32, 32, tex.e)
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end

local function drawVictims()
    local I = FDC.incident
    if not FDC.onDuty or not I or not inWorld() then return end
    for _, v in ipairs(I.victims) do
        if isElement(v.ped) and isElementOnScreen(v.ped) and getElementAttachedTo(v.ped) ~= localPlayer then
            local x, y, z = getPedBonePosition(v.ped, 8)
            local d = dist3(x, y, z)
            if d < 70 then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 0.55)
                if sx then
                    local s = math.max(0.55, 1 - d / 90)
                    local icon = v.state == "safe" and tex.happy or v.state == "dead" and tex.cross or tex.help
                    local iw, ih = 34 * s, 40 * s
                    local pulse = (v.state == "trapped" and v.life < 60) and (math.abs(math.sin(getTickCount() / 160)) * 6 * s) or 0
                    dxDrawImage(sx - iw / 2 - pulse / 2, sy - ih - 12 * s - pulse, iw + pulse, ih + pulse, icon)
                    if v.state == "trapped" or v.state == "carried" then
                        local frac = math.max(0, v.life / I.lifeTotal)
                        local bw, bh = 70 * s, 7 * s
                        local r, g = frac < 0.3 and 235 or 255, frac < 0.3 and 60 or math.floor(120 + 100 * frac)
                        dxDrawRectangle(sx - bw / 2 - 1, sy - 1, bw + 2, bh + 2, tocolor(0, 0, 0, 180))
                        dxDrawRectangle(sx - bw / 2, sy, bw * frac, bh, tocolor(r, g, 70, 235))
                    end
                end
            end
        end
    end
end

addEventHandler("onClientRender", root, function()
    if isElement(hud) and hudReady and FDC.onDuty then
        local ok, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
        if not (ok and sup) then dxDrawImage(0, 0, sw, sh, hud) end
    end
    drawVictims()
    drawPrompt()
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("rp:firefighters:points", resourceRoot, function(list) points = type(list) == "table" and list or {} end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.e = dxCreateTexture("images/keys/keyboard_e.png")
    tex.help = dxCreateTexture("images/emote_exclamation.png")
    tex.happy = dxCreateTexture("images/emote_faceHappy.png")
    tex.cross = dxCreateTexture("images/emote_cross.png")
    font = dxCreateFont("html/fonts/rubik_medium.ttf", 12) or "default-bold"
    bindKey("e", "down", onKeyE)
    triggerServerEvent("rp:firefighters:requestPoints", resourceRoot)
    triggerServerEvent("rp:firefighters:sync", resourceRoot)
    onDutyChanged(getElementData(localPlayer, "rp:fireDuty") == true)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closePanel()
    destroyHud()
end)
