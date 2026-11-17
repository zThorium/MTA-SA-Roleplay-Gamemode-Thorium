--[[
    rp_vehicles / c_fuel.lua
    Bencinera del lado del cliente: aviso en el marcador (E), camara de la
    conversacion con el bombero, dialogo de litros y datafono (html/fuel.*),
    caminata del bombero, manguera, globos de texto y sonidos del datafono.
]]

local W, H = guiGetScreenSize()
local near = false          -- nombre de la bencinera donde estoy estacionado
local active = nil          -- { ped, vehicle, startFuel, target, stage }
local walkers = {}          -- [ped] = { fx, fy, fz, tx, ty, tz, start, ms }
local bubbles = {}          -- [ped] = { text, untilTick }
local hoses = {}            -- [ped] = { x, y, z }
local camTween = nil

addEvent("rp:fuel:near", true)
addEvent("rp:fuel:start", true)
addEvent("rp:fuel:walk", true)
addEvent("rp:fuel:say", true)
addEvent("rp:fuel:hose", true)
addEvent("rp:fuel:dialog", true)
addEvent("rp:fuel:ordered", true)
addEvent("rp:fuel:pos", true)
addEvent("rp:fuel:payResult", true)
addEvent("rp:fuel:finish", true)
addEvent("rp:fuel:ui:order", false)
addEvent("rp:fuel:ui:cancel", false)
addEvent("rp:fuel:ui:pay", false)
addEvent("rp:fuel:ui:sound", false)

----------------------------------------------------------------
-- Navegador (uno solo, pantalla completa y transparente)
----------------------------------------------------------------
local browserGui, browser, ready, pending = nil, nil, false, {}

local function callJS(code)
    if isElement(browser) and ready then executeBrowserJavascript(browser, code)
    else pending[#pending + 1] = code end
end

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, W, H, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/fuel.html") end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        for _, code in ipairs(pending) do executeBrowserJavascript(source, code) end
        pending = {}
    end)
end

local function showUI(visible)
    if not isElement(browserGui) then return end
    guiSetVisible(browserGui, visible)
    showCursor(visible)
    if visible then
        guiBringToFront(browserGui)
        focusBrowser(browser)
    else
        focusBrowser(nil)
    end
end

local function json(data) return toJSON(data, true):sub(2, -2) end

----------------------------------------------------------------
-- Sonidos (generados para el gamemode: sounds/pos_*.wav)
----------------------------------------------------------------
local SOUNDS = { beep = "sounds/pos_beep.wav", swipe = "sounds/pos_swipe.wav", print = "sounds/pos_print.wav",
    error = "sounds/pos_error.wav", ok = "sounds/pos_ok.wav" }

local function play(name)
    local path = SOUNDS[name]
    if path then
        local snd = playSound(path)
        if snd then setSoundVolume(snd, name == "print" and 0.9 or 0.6) end
    end
end

addEventHandler("rp:fuel:ui:sound", root, function(name) play(name) end)

----------------------------------------------------------------
-- Geometria del vehiculo
----------------------------------------------------------------
local function toWorld(vehicle, ox, oy, oz)
    local m = getElementMatrix(vehicle)
    return ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1],
        ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2],
        ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
end

-- Donde se para el bombero: ventana del conductor y tapa del tanque (lado izquierdo)
local function spots(vehicle)
    local minX, minY, minZ, _, maxY = getElementBoundingBox(vehicle)
    minX, minY, minZ, maxY = minX or -1, minY or -2.4, minZ or -0.8, maxY or 2.4
    local feet = minZ + 1.0
    return {
        window = { minX - 0.7, math.min(0.35, maxY - 0.6), feet },
        cap = { minX - 0.65, minY + 0.9, feet },
    }
end

----------------------------------------------------------------
-- Camara
----------------------------------------------------------------
local function smooth(t) return t * t * (3 - 2 * t) end

local function camTo(px, py, pz, lx, ly, lz, ms)
    local cx, cy, cz, clx, cly, clz = getCameraMatrix()
    camTween = { from = { cx, cy, cz, clx, cly, clz }, to = { px, py, pz, lx, ly, lz }, start = getTickCount(), ms = ms or 1200 }
end

local function shot(kind)
    local v = active and active.vehicle
    if not isElement(v) then return end
    local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(v)
    minX, minY, minZ, maxX, maxY, maxZ = minX or -1, minY or -2.4, minZ or -0.8, maxX or 1, maxY or 2.4, maxZ or 0.8
    if kind == "window" then
        -- De frente y a la izquierda: se ve al bombero hablando por la ventana
        local px, py, pz = toWorld(v, minX - 2.8, maxY + 1.6, maxZ + 0.35)
        local lx, ly, lz = toWorld(v, minX - 0.5, 0.1, maxZ - 0.35)
        camTo(px, py, pz, lx, ly, lz, 1400)
    elseif kind == "cap" then
        -- Desde atras: se ve la carga y el velocimetro subiendo
        local px, py, pz = toWorld(v, minX - 3.4, minY - 2.6, maxZ + 0.9)
        local lx, ly, lz = toWorld(v, minX - 0.4, minY + 1.2, 0)
        camTo(px, py, pz, lx, ly, lz, 1600)
    end
end

addEventHandler("onClientPreRender", root, function()
    if camTween then
        local t = math.min(1, (getTickCount() - camTween.start) / camTween.ms)
        local k, f, to = smooth(t), camTween.from, camTween.to
        setCameraMatrix(f[1] + (to[1] - f[1]) * k, f[2] + (to[2] - f[2]) * k, f[3] + (to[3] - f[3]) * k,
            f[4] + (to[4] - f[4]) * k, f[5] + (to[5] - f[5]) * k, f[6] + (to[6] - f[6]) * k)
    end

    -- Bomberos caminando (los anima cada cliente; el servidor fija la posicion final)
    local now = getTickCount()
    for ped, w in pairs(walkers) do
        if not isElement(ped) then
            walkers[ped] = nil
        else
            local t = math.min(1, (now - w.start) / w.ms)
            setElementPosition(ped, w.fx + (w.tx - w.fx) * t, w.fy + (w.ty - w.fy) * t, w.fz + (w.tz - w.fz) * t, false)
            setElementRotation(ped, 0, 0, w.rz, "default", true)
            if t >= 1 then
                walkers[ped] = nil
                setPedAnimation(ped)
            end
        end
    end
end)

addEventHandler("rp:fuel:walk", root, function(x, y, z, ms)
    local ped = source
    if not isElement(ped) then return end
    local fx, fy, fz = getElementPosition(ped)
    local rz = math.deg(math.atan2(y - fy, x - fx)) - 90
    walkers[ped] = { fx = fx, fy = fy, fz = fz, tx = x, ty = y, tz = z, start = getTickCount(), ms = math.max(50, ms), rz = rz }
    if ms > 100 then setPedAnimation(ped, "ped", "WALK_civi", -1, true, false, false, false) end
end)

----------------------------------------------------------------
-- Globos de texto, nombre del bombero y manguera
----------------------------------------------------------------
addEventHandler("rp:fuel:say", root, function(text)
    if isElement(source) and type(text) == "string" then
        bubbles[source] = { text = text, untilTick = getTickCount() + 4500 }
    end
end)

addEventHandler("rp:fuel:hose", root, function(x, y, z, on)
    if not isElement(source) then return end
    hoses[source] = on and { x, y, z + 0.9 } or nil
end)

addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:attendant") then cancelEvent() end
end)

local function drawHose(ped, h)
    local hx, hy, hz = getPedBonePosition(ped, 25)
    if not hx then return end
    -- Curva que cuelga un poco entre el surtidor y la mano
    local steps = 10
    local px, py, pz = h[1], h[2], h[3]
    local dist = getDistanceBetweenPoints3D(h[1], h[2], h[3], hx, hy, hz)
    for i = 1, steps do
        local t = i / steps
        local x = h[1] + (hx - h[1]) * t
        local y = h[2] + (hy - h[2]) * t
        local z = h[3] + (hz - h[3]) * t - math.sin(t * math.pi) * math.min(0.9, dist * 0.18)
        dxDrawLine3D(px, py, pz, x, y, z, tocolor(20, 20, 22, 255), 4)
        px, py, pz = x, y, z
    end
end

addEventHandler("onClientRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    local now = getTickCount()

    for ped, h in pairs(hoses) do
        if isElement(ped) and isElementStreamedIn(ped) then drawHose(ped, h) else hoses[ped] = nil end
    end

    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if getElementData(ped, "rp:attendant") then
            local hx, hy, hz = getPedBonePosition(ped, 8)
            if hx and getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz) < 18 then
                local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.35)
                if sx then
                    local bubble = bubbles[ped]
                    if bubble and now < bubble.untilTick then
                        local tw = dxGetTextWidth(bubble.text, 1.15, "default-bold") + 24
                        dxDrawRectangle(sx - tw / 2, sy - 44, tw, 30, tocolor(250, 250, 248, 235))
                        dxDrawText(bubble.text, sx - tw / 2, sy - 44, sx + tw / 2, sy - 14, tocolor(20, 22, 28), 1.15, "default-bold", "center", "center")
                        dxDrawRectangle(sx - 5, sy - 14, 10, 6, tocolor(250, 250, 248, 235))
                    else
                        bubbles[ped] = nil
                        dxDrawText("Bombero", sx + 1, sy - 13, sx + 1, sy - 13, tocolor(0, 0, 0, 180), 1, "default-bold", "center", "center")
                        dxDrawText("Bombero", sx, sy - 14, sx, sy - 14, tocolor(255, 210, 60, 230), 1, "default-bold", "center", "center")
                    end
                end
            end
        end
    end
end)

----------------------------------------------------------------
-- Aviso del marcador y tecla E
----------------------------------------------------------------
addEventHandler("rp:fuel:near", resourceRoot, function(name)
    near = name or false
end)

local function drawCentered(text, y, r, g, b, scale)
    dxDrawText(text, 1, y + 1, W + 1, y + 1, tocolor(0, 0, 0, 200), scale, "default-bold", "center")
    dxDrawText(text, 0, y, W, y, tocolor(r, g, b, 255), scale, "default-bold", "center")
end

addEventHandler("onClientRender", root, function()
    if active then
        -- Progreso de la carga
        if active.stage == "fueling" and isElement(active.vehicle) then
            local now = tonumber(getElementData(active.vehicle, "rp:fuel")) or active.startFuel
            local loaded = math.max(0, math.min(active.target, now - active.startFuel))
            local text = ("Cargando bencina: %.1f / %.1f L  -  $%d"):format(loaded, active.target, math.ceil(loaded * FUEL.PRICE_PER_LITER))
            drawCentered(text, H * 0.82, 255, 210, 60, 1.4)
            local bw, bh = 360, 8
            dxDrawRectangle(W / 2 - bw / 2, H * 0.82 + 32, bw, bh, tocolor(0, 0, 0, 160))
            dxDrawRectangle(W / 2 - bw / 2, H * 0.82 + 32, bw * (active.target > 0 and loaded / active.target or 0), bh, tocolor(255, 200, 40, 240))
        end
        return
    end
    if not near then return end
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer then near = false return end
    drawCentered(("%s - pulsa E para llamar al bombero"):format(near), H * 0.78, 255, 210, 60, 1.4)
end)

local function callAttendant()
    if not near or active then return end
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer then return end
    triggerServerEvent("rp:fuel:call", resourceRoot, spots(v))
end
addCommandHandler("bombero", callAttendant)
bindKey("e", "down", function()
    if near and not active and not isChatBoxInputActive() and not isConsoleActive() and not isCursorShowing() then callAttendant() end
end)

----------------------------------------------------------------
-- Flujo de la atencion
----------------------------------------------------------------
addEventHandler("rp:fuel:start", resourceRoot, function(ped, vehicle)
    active = { ped = ped, vehicle = vehicle, stage = "walk", startFuel = 0, target = 0 }
    near = false
    toggleAllControls(false, true, false)
    createBrowser()
    shot("window")
end)

addEventHandler("rp:fuel:dialog", resourceRoot, function(data)
    if not active then return end
    active.stage = "talk"
    callJS(("RPF.dialog(%s)"):format(json(data)))
    showUI(true)
end)

addEventHandler("rp:fuel:ui:order", root, function(liters)
    if not active or active.stage ~= "talk" then return end
    triggerServerEvent("rp:fuel:order", resourceRoot, liters == "full" and "full" or tonumber(liters))
end)

addEventHandler("rp:fuel:ui:cancel", root, function()
    if not active or active.stage ~= "talk" then return end
    triggerServerEvent("rp:fuel:cancel", resourceRoot)
end)

addEventHandler("rp:fuel:ordered", resourceRoot, function(liters)
    if not active then return end
    active.stage = "fueling"
    active.target = tonumber(liters) or 0
    active.startFuel = tonumber(getElementData(active.vehicle, "rp:fuel")) or 0
    callJS("RPF.hide()")
    showUI(false)
    shot("cap")
end)

addEventHandler("rp:fuel:pos", resourceRoot, function(data)
    if not active then return end
    active.stage = "pay"
    shot("window")
    callJS(("RPF.pos(%s)"):format(json(data)))
    showUI(true)
end)

addEventHandler("rp:fuel:ui:pay", root, function(method, owner, pin)
    if not active or active.stage ~= "pay" then return end
    triggerServerEvent("rp:fuel:pay", resourceRoot, method == "cash" and "cash" or "card", tonumber(owner), tostring(pin or ""))
end)

addEventHandler("rp:fuel:payResult", resourceRoot, function(ok, text, cash)
    play(ok and "print" or "error")
    callJS(("RPF.result(%s, %q, %s)"):format(ok and "true" or "false", tostring(text or ""), cash and "true" or "false"))
    if ok and active then active.stage = "paid" end
end)

local function finish()
    if not active then return end
    active = nil
    camTween = nil
    callJS("RPF.hide()")
    showUI(false)
    setCameraTarget(localPlayer)
    toggleAllControls(true, true, false)
end
addEventHandler("rp:fuel:finish", resourceRoot, finish)

addEventHandler("onClientPlayerWasted", localPlayer, finish)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        setCameraTarget(localPlayer)
        toggleAllControls(true, true, false)
        showCursor(false)
    end
end)
