--[[
    rp_missions / client / c_core.lua

    Estado compartido del cliente, interfaz CEF (menu de contactos y sala), invitaciones y entorno.
    Tecla J o /misiones: abre el menu.  Y / N: aceptar o rechazar una invitacion.
]]

C = C or {}
C.sw, C.sh = guiGetScreenSize()
C.sc = math.max(0.8, math.min(1.5, C.sh / 900))
C.active = false           -- dentro de una instancia (cargando/en curso/resultados)
C.def = nil                -- mision actual (de MISSION_DEFS)
C.info = nil               -- datos de enter
C.cutscene = false         -- cinematica en curso (oculta el HUD)
C.results = nil
C.spectating = false

for _, ev in ipairs({ "menu", "lobby", "close", "enter", "left", "stage", "stageDone", "hud", "cutscene", "cutsceneEnd", "radio", "flash",
                      "died", "respawned", "spectate", "progress", "results", "invite" }) do
    addEvent("rp:missions:" .. ev, true)
end
for _, ev in ipairs({ "create", "join", "leave", "setrole", "vote", "invite", "start", "kick", "public", "close" }) do
    addEvent("rp:missions:ui:" .. ev, false)
end

function C.suppressHud(reason, on)
    pcall(function() exports.rp_hud:setHudSuppressed("rp_missions:" .. reason, on) end)
end

-- La radio (rp_radio y radio nativa) se solapa con los dialogos: se silencia mientras dura la mision
function C.suppressRadio(on)
    pcall(function() exports.rp_radio:setRadioSuppressed("rp_missions", on) end)
end

function C.contactColor(key, a)
    local c = (MISSIONS.CONTACTS[key] or MISSIONS.CONTACTS.enemy).color
    return tocolor(c[1], c[2], c[3], a or 255)
end

function C.ease(t) t = math.max(0, math.min(1, t)); return t * t * (3 - 2 * t) end
function C.fmtTime(ms)
    local s = math.floor((ms or 0) / 1000)
    return ("%02d:%02d"):format(math.floor(s / 60), s % 60)
end

----------------------------------------------------------------
-- UI (CEF)
----------------------------------------------------------------
local browserGui, browser, ready, pendingJS = nil, nil, false, {}

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

function C.closeUI()
    if not isElement(browserGui) then return end
    destroyElement(browserGui)
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
end

local function openUI()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, C.sw, C.sh, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
    end)
    showCursor(true)
end

local function push(fn, data)
    openUI()
    callJS(("MISSIONS_UI.%s(%s[0])"):format(fn, toJSON(data or {}, true)))
end

addEventHandler("rp:missions:menu", resourceRoot, function(data) if not C.active then push("menu", data) end end)
addEventHandler("rp:missions:lobby", resourceRoot, function(data) if not C.active then push("lobby", data) end end)
addEventHandler("rp:missions:close", resourceRoot, function() C.closeUI() end)

addEventHandler("rp:missions:ui:create", root, function(i) triggerServerEvent("rp:missions:create", resourceRoot, tonumber(i)) end)
addEventHandler("rp:missions:ui:join", root, function(id) triggerServerEvent("rp:missions:join", resourceRoot, tonumber(id)) end)
addEventHandler("rp:missions:ui:leave", root, function() C.closeUI() triggerServerEvent("rp:missions:leave", resourceRoot) end)
addEventHandler("rp:missions:ui:setrole", root, function(r) triggerServerEvent("rp:missions:setrole", resourceRoot, r ~= "" and r or false) end)
addEventHandler("rp:missions:ui:vote", root, function(d) triggerServerEvent("rp:missions:vote", resourceRoot, d) end)
addEventHandler("rp:missions:ui:invite", root, function(q)
    if tonumber(q) then q = tonumber(q) end
    triggerServerEvent("rp:missions:invite", resourceRoot, q)
end)
addEventHandler("rp:missions:ui:start", root, function() triggerServerEvent("rp:missions:start", resourceRoot) end)
addEventHandler("rp:missions:ui:kick", root, function(n) triggerServerEvent("rp:missions:kick", resourceRoot, n) end)
addEventHandler("rp:missions:ui:public", root, function(f) triggerServerEvent("rp:missions:public", resourceRoot, f == true or f == "true") end)
addEventHandler("rp:missions:ui:close", root, function() C.closeUI() end)

bindKey("j", "down", function()
    if C.active or isCursorShowing() and not isElement(browserGui) then return end
    if isElement(browserGui) then return C.closeUI() end
    triggerServerEvent("rp:missions:open", resourceRoot)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function() C.closeUI() end)

----------------------------------------------------------------
-- Invitaciones (Y / N)
----------------------------------------------------------------
local invite, inviteAt = nil, 0

addEventHandler("rp:missions:invite", resourceRoot, function(from, title, contact, duration)
    invite, inviteAt = { from = from, title = title, contact = contact, duration = duration }, getTickCount()
    playSoundFrontEnd(5)
end)

local function reply(ok)
    if not invite then return end
    invite = nil
    triggerServerEvent("rp:missions:reply", resourceRoot, ok)
end
bindKey("y", "down", function() if invite then reply(true) end end)
bindKey("n", "down", function() if invite then reply(false) end end)

local function drawInvite(now)
    if not invite then return end
    local el = now - inviteAt
    if el > invite.duration then invite = nil return end
    local sc = C.sc
    local w, h = 400 * sc, 92 * sc
    local slide = C.ease(el / 350)
    local x, y = C.sw / 2 - w / 2, C.sh * 0.1 - (1 - slide) * 140 * sc
    dxDrawRectangle(x, y, w, h, tocolor(14, 16, 22, 232))
    dxDrawRectangle(x, y, 4 * sc, h, C.contactColor(invite.contact))
    dxDrawRectangle(x, y + h - 3 * sc, w * (1 - el / invite.duration), 3 * sc, tocolor(245, 165, 36, 255))
    dxDrawText("INVITACION A MISION", x + 18 * sc, y + 8 * sc, x + w, y + 26 * sc, tocolor(154, 163, 178, 255), 0.9 * sc, "default-bold")
    dxDrawText(("%s te invita a \"%s\""):format(invite.from, invite.title), x + 18 * sc, y + 26 * sc, x + w - 10 * sc, y + 56 * sc, tocolor(242, 244, 248), 1.05 * sc, "default-bold", "left", "top", true, true)
    dxDrawText("[Y] Aceptar     [N] Rechazar", x + 18 * sc, y + 62 * sc, x + w, y + h, tocolor(245, 165, 36, 255), 1.0 * sc, "default-bold")
end

----------------------------------------------------------------
-- Etiquetas sobre los puntos de contacto
----------------------------------------------------------------
local function drawContactLabels()
    if C.active then return end
    local px, py, pz = getElementPosition(localPlayer)
    for _, mk in ipairs(getElementsByType("marker", resourceRoot, true)) do
        local contact = getElementData(mk, "rp:mcontact")
        if contact then
            local x, y, z = getElementPosition(mk)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d < 28 then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 1.9)
                if sx then
                    local a = math.min(255, (28 - d) * 40)
                    local name = (MISSIONS.CONTACTS[contact] or {}).name or contact
                    local s = C.sc * (1.05 - d / 60)
                    dxDrawText(name, sx - 150 + 1, sy + 1, sx + 150 + 1, sy + 31, tocolor(0, 0, 0, a), s * 1.3, "default-bold", "center")
                    dxDrawText(name, sx - 150, sy, sx + 150, sy + 30, C.contactColor(contact, a), s * 1.3, "default-bold", "center")
                    dxDrawText("Misiones - entra o pulsa J", sx - 150, sy + 20 * C.sc, sx + 150, sy + 50, tocolor(242, 244, 248, a), s * 0.95, "default", "center")
                end
            end
        end
    end
end

----------------------------------------------------------------
-- Entorno (hora / clima de la mision)
----------------------------------------------------------------
local savedEnv

local function applyEnv(hour, weather)
    if not savedEnv then
        local h, m = getTime()
        savedEnv = { h = h, m = m, w = getWeather(), md = getMinuteDuration() }
    end
    if hour then setTime(hour, 0) setMinuteDuration(600000) end
    if weather then setWeather(weather) end
end

local function resetEnv()
    if not savedEnv then return end
    setMinuteDuration(savedEnv.md or 1000)
    setTime(savedEnv.h, savedEnv.m)
    setWeather(savedEnv.w or 0)
    savedEnv = nil
end

addEventHandler("rp:missions:enter", resourceRoot, function(info)
    C.active, C.info, C.results, C.cutscene, C.spectating = true, info, nil, false, false
    C.hud = nil
    for _, d in ipairs(MISSION_DEFS) do if d.key == info.key then C.def = d end end
    applyEnv(info.hour, info.weather)
    C.suppressRadio(true)
    C.closeUI()
    if C.onEnter then C.onEnter(info) end
end)

addEventHandler("rp:missions:left", resourceRoot, function()
    C.active, C.info, C.def, C.hud, C.results, C.cutscene, C.spectating = false, nil, nil, nil, nil, false, false
    resetEnv()
    C.suppressRadio(false)
    if C.onLeft then C.onLeft() end
    setCameraTarget(localPlayer)
    C.suppressHud("cinematic", false)
    C.suppressHud("results", false)
end)

-- Si rp_radio o rp_hud se reinician con una mision en curso, se vuelven a silenciar
addEventHandler("onClientResourceStart", root, function(res)
    if not C.active then return end
    local name = getResourceName(res)
    if name == "rp_radio" then C.suppressRadio(true)
    elseif name == "rp_hud" and C.cutscene then C.suppressHud("cinematic", true) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    C.suppressRadio(false)
    resetEnv()
    C.suppressHud("cinematic", false)
    C.suppressHud("results", false)
    setCameraTarget(localPlayer)
end)

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    drawContactLabels()
    drawInvite(now)
end)
