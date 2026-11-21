--[[
    rp_robbery / c_negotiation.lua
    Negociacion con la policia al salir con el botin. El texto y las opciones
    van en un navegador CEF (html/); este archivo mueve la camara:
      - Plano de presentacion: detras de las patrullas, mirando la puerta.
      - Cuando habla el sargento: primer plano con zoom exagerado (FOV de 70 a
        28 en un golpe) y gestos; si le pillan el farol, temblor y giro.
      - Cuando habla el jugador: primer plano desde la policia.
    El servidor valida cada opcion (rp:robbery:choose).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local pendingJS = {}
local N        -- { negotiator, cops, cars, name, copName, cam = { who, mood, at } }

addEvent("rp:robbery:negotiation", true)
addEvent("rp:robbery:turn", true)
addEvent("rp:robbery:ui:speaker", false)
addEvent("rp:robbery:ui:choose", false)
addEvent("rp:robbery:ui:closed", false)

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pendingJS[#pendingJS + 1] = code end
end

local function jsString(v)
    v = tostring(v or "")
    v = v:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. v .. "\""
end

local function closeUI()
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser, ready, pendingJS = nil, nil, false, {}
    showCursor(false)
    guiSetInputEnabled(false)
end

local function close()
    if not N then return closeUI() end
    if isElement(N.negotiator) then setPedAnimation(N.negotiator) end
    setPedAnimation(localPlayer)
    N = nil
    RC.negotiating = false
    closeUI()
    setCameraTarget(localPlayer)
end

local function openUI()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pendingJS) do executeBrowserJavascript(source, code) end
        pendingJS = {}
        focusBrowser(source)
    end)
    showCursor(true)
    guiSetInputEnabled(true)
end

addEventHandler("rp:robbery:negotiation", resourceRoot, function(data)
    N = data
    N.cam = { who = "intro", mood = "", at = getTickCount() }
    RC.negotiating = true
    setCameraInterior(0)
    openUI()
    callJS(("RP.start(%s, %s)"):format(jsString(data.name), jsString(data.copName)))
end)

addEventHandler("rp:robbery:turn", resourceRoot, function(turn)
    if not N then return end
    callJS(("RP.turn(%s[0])"):format(toJSON(turn, true)))
end)

-- Gestos (animaciones locales: solo las ve quien negocia)
local COP_GESTURES = {
    default = { "GHANDS", "gsign2" }, intro = { "ON_LOOKERS", "shout_01" }, bluff_fail = { "RAPPING", "Laugh_01" },
    bluff_broken = { "ON_LOOKERS", "shout_02" }, deal = { "GHANDS", "gsign5" }, surrender = { "ON_LOOKERS", "point_loop" },
    bluff_ok_traps = { "ped", "handsup" }, bluff_ok_tires = { "ped", "handsup" }, bluff_ok_seconds = { "ped", "handsup" },
}

addEventHandler("rp:robbery:ui:speaker", root, function(who, mood)
    if not N then return end
    N.cam = { who = who, mood = mood or "", at = getTickCount() }
    if who == "cop" and isElement(N.negotiator) then
        local g = COP_GESTURES[mood] or COP_GESTURES.default
        setPedAnimation(N.negotiator, g[1], g[2], -1, false, false, false, true)
    elseif who == "player" then
        setPedAnimation(localPlayer, "GANGS", math.random(2) == 1 and "prtial_gngtlkA" or "prtial_gngtlkB", -1, false, false, false, true)
    end
end)

addEventHandler("rp:robbery:ui:choose", root, function(id)
    if not N or type(id) ~= "string" then return end
    triggerServerEvent("rp:robbery:choose", resourceRoot, id)
end)

addEventHandler("rp:robbery:ui:closed", root, function()
    if not N then return end
    triggerServerEvent("rp:robbery:negotiationClosed", resourceRoot)
    close()
end)

addEventHandler("rp:robbery:stop", resourceRoot, close)
addEventHandler("rp:robbery:escape", resourceRoot, close)
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEventHandler("onClientResourceStop", resourceRoot, function() if N then setCameraTarget(localPlayer) end closeUI() end)

----------------------------------------------------------------
-- Camara
----------------------------------------------------------------
local function lerp(a, b, t) return a + (b - a) * t end
local function easeOut(t) return 1 - (1 - t) ^ 3 end

local function headOf(el)
    local x, y, z = getElementPosition(el)
    return x, y, z + 0.65
end

-- Primer plano de "speaker" visto desde "other", con golpe de zoom
local function closeUp(speaker, other, k, mood, now)
    local sx, sy, sz = headOf(speaker)
    local ox, oy = getElementPosition(other)
    local dx, dy = ox - sx, oy - sy
    local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    dx, dy = dx / len, dy / len
    local zoom = easeOut(math.min(1, k / 0.35))
    local dist = lerp(3.2, 1.25, zoom)
    local side = 0.35
    local cx, cy, cz = sx + dx * dist - dy * side, sy + dy * dist + dx * side, sz + 0.05
    local fov, roll = lerp(75, 30, zoom), 0
    if mood == "bluff_fail" or mood == "bluff_broken" or mood == "surrender" then
        -- temblor fuerte y giro: "¡MENTIRA!"
        local shake = math.max(0, 1 - k / 1.4) * 0.18
        cx, cz = cx + math.sin(now / 25) * shake, cz + math.cos(now / 31) * shake
        roll = math.sin(now / 90) * 12 * math.max(0, 1 - k / 1.6)
        fov = lerp(30, 24, math.min(1, k / 2))
    elseif mood:find("^bluff_ok") then
        -- cara de susto: el zoom se va hacia atras
        fov = lerp(28, 85, easeOut(math.min(1, k / 0.5)))
        roll = -8
    elseif mood == "intro" then
        roll = lerp(-15, 0, zoom)
    end
    return cx, cy, cz, sx, sy, sz, roll, fov
end

addEventHandler("onClientPreRender", root, function()
    if not N then return end
    local now = getTickCount()
    local k = (now - N.cam.at) / 1000
    local neg = N.negotiator
    if N.cam.who == "intro" or not isElement(neg) then
        -- detras de las patrullas, mirando a la puerta, con un travelling lento
        local px, py, pz = getElementPosition(localPlayer)
        local nx, ny = px + 1, py
        if isElement(neg) then nx, ny = getElementPosition(neg) end
        local dx, dy = nx - px, ny - py
        local len = math.max(0.001, math.sqrt(dx * dx + dy * dy))
        dx, dy = dx / len, dy / len
        local back = len + 9 - math.min(4, k * 1.2)
        setCameraMatrix(px + dx * back - dy * 3, py + dy * back + dx * 3, pz + 3.5, px, py, pz + 0.4, 0, 70)
        return
    end
    local cx, cy, cz, lx, ly, lz, roll, fov
    if N.cam.who == "cop" then
        cx, cy, cz, lx, ly, lz, roll, fov = closeUp(neg, localPlayer, k, N.cam.mood, now)
    else
        cx, cy, cz, lx, ly, lz, roll, fov = closeUp(localPlayer, neg, k, "", now)
    end
    setCameraMatrix(cx, cy, cz, lx, ly, lz, roll, fov)
end)
