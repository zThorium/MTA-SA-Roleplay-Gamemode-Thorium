--[[
    rp_carwash · cliente

    - Conductor: cada segundo mira la superficie bajo el vehículo (processLineOfSight) y acumula suciedad según
      CARWASH.SURFACES/RATES; cada SEND_EVERY ms la manda al servidor (rp:carwash:dirt).
    - Todos: aplica fx/dirt.fx a la carrocería de los vehículos cercanos con "rp:dirt" >= MIN_VISIBLE.
    - Lavado: dentro del marcador con el auto sucio se dibuja la tecla E; durante el lavado, agua alrededor del
      auto, la suciedad baja de a poco y una barra de progreso para el conductor.
]]

local C = CARWASH
local sw, sh = guiGetScreenSize()
local shaders = {}      -- [vehicle] = shader
local washing = {}      -- [vehicle] = { t0, dur, from, nextFx }
local pending, lastSend = 0, getTickCount()
local texE, font

addEvent("rp:carwash:start", true)
addEvent("rp:carwash:finish", true)
addEvent("rp:carwash:denied", true)

local function dirtOf(v) return tonumber(getElementData(v, "rp:dirt")) or 0 end

local function sound(name) playSound("sounds/" .. name .. ".ogg").volume = 0.6 end

----------------------------------------------------------------
-- Shader por vehículo
----------------------------------------------------------------
local function dropShader(v)
    if shaders[v] then
        if isElement(shaders[v]) then destroyElement(shaders[v]) end
        shaders[v] = nil
    end
end

local function shownDirt(v)
    local w = washing[v]
    if not w then return dirtOf(v) end
    return w.from * (1 - math.min(1, (getTickCount() - w.t0) / w.dur))
end

local function refresh(v)
    if not isElement(v) then return dropShader(v) end
    local d = shownDirt(v)
    if d < C.MIN_VISIBLE or not isElementStreamedIn(v) then return dropShader(v) end
    if not shaders[v] then
        local s = dxCreateShader("fx/dirt.fx", 0, C.SHADER_DIST, false, "vehicle")
        if not s then return end
        engineApplyShaderToWorldTexture(s, "vehiclegrunge256", v)
        shaders[v] = s
    end
    dxSetShaderValue(shaders[v], "gDirt", d)
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then refresh(source) end
end)
addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "vehicle" then dropShader(source) end
end)
addEventHandler("onClientElementDestroy", root, function()
    if getElementType(source) == "vehicle" then dropShader(source); washing[source] = nil end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:dirt" and getElementType(source) == "vehicle" then refresh(source) end
end)

----------------------------------------------------------------
-- Acumular suciedad (solo el conductor)
----------------------------------------------------------------
local function surfaceRate(v)
    local x, y, z = getElementPosition(v)
    local hit, _, _, _, _, _, _, _, material = processLineOfSight(x, y, z, x, y, z - 3, true, false, false, true, false, false, false, false, v)
    if not hit then return 0 end
    return C.RATES[C.SURFACES[material] or "road"] or 0
end

local function accumulate()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer or washing[v] then return end
    if not C.VEHICLE_TYPES[getVehicleType(v)] or not isVehicleOnGround(v) then return end
    local vx, vy, vz = getElementVelocity(v)
    local kmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
    if kmh >= C.MIN_SPEED then
        local factor = math.max(0.3, math.min(C.MAX_SPEED_FACTOR, kmh / C.REF_SPEED))
        pending = pending + surfaceRate(v) * factor
    end
    if pending > 0 and getTickCount() - lastSend >= C.SEND_EVERY then
        if dirtOf(v) < 1 then triggerServerEvent("rp:carwash:dirt", resourceRoot, v, pending) end
        pending, lastSend = 0, getTickCount()
    end
end

addEventHandler("onClientVehicleExit", root, function(player)
    if player == localPlayer then pending = 0 end
end)

----------------------------------------------------------------
-- Lavado
----------------------------------------------------------------
local function nearWash(v)
    local x, y, z = getElementPosition(v)
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        local mx, my, mz = getElementPosition(m)
        if getElementDimension(m) == getElementDimension(v) and getDistanceBetweenPoints3D(x, y, z, mx, my, mz) <= C.USE_DIST then
            return m
        end
    end
end

local function drawWorldPrompt(x, y, z, image, text)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 1.2)
    if not sx then return end
    local k = image and 42 * (1 + math.sin(getTickCount() / 260) * 0.04) or 0
    if image then dxDrawImage(sx - k / 2, sy - k / 2, k, k, image) end
    local tw = dxGetTextWidth(text, 1, font) + 20
    local ty = sy + k / 2 + 4
    dxDrawRectangle(sx - tw / 2, ty, tw, 26, tocolor(14, 12, 12, 190))
    dxDrawText(text, sx - tw / 2, ty, sx + tw / 2, ty + 26, tocolor(255, 255, 255), 1, font, "center", "center")
end

local function drawProgress(p)
    local w, h = 300, 40
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawRectangle(x, y, w, h, tocolor(14, 12, 12, 190))
    dxDrawRectangle(x + 6, y + h - 10, (w - 12) * p, 4, tocolor(60, 215, 230, 255))
    dxDrawText(("Lavando… %d%%"):format(p * 100), x, y, x + w, y + h - 8, tocolor(255, 255, 255), 1, font, "center", "center")
end

local function washFx(v, w, now)
    if now < w.nextFx then return end
    w.nextFx = now + 120
    local x, y, z = getElementPosition(v)
    for _ = 1, 3 do
        fxAddWaterSplash(x + math.random(-25, 25) / 10, y + math.random(-30, 30) / 10, z + math.random(0, 12) / 10)
    end
end

addEventHandler("rp:carwash:start", resourceRoot, function(v, dur, from)
    if not isElement(v) then return end
    washing[v] = { t0 = getTickCount(), dur = dur, from = from, nextFx = 0 }
    if getPedOccupiedVehicle(localPlayer) == v then sound("drop_002") end
end)

addEventHandler("rp:carwash:finish", resourceRoot, function(v, ok)
    if not isElement(v) then return end
    washing[v] = nil
    refresh(v)
    if ok and getPedOccupiedVehicle(localPlayer) == v then sound("confirmation_002") end
end)

addEventHandler("rp:carwash:denied", resourceRoot, function() sound("error_004") end)

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    for v, w in pairs(washing) do
        if isElement(v) then
            refresh(v)
            if isElementStreamedIn(v) then washFx(v, w, now) end
        else
            washing[v] = nil
        end
    end

    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer then return end
    local w = washing[v]
    if w then return drawProgress(math.min(1, (now - w.t0) / w.dur)) end
    if not C.VEHICLE_TYPES[getVehicleType(v)] then return end
    local m = nearWash(v)
    if not m then return end
    local x, y, z = getElementPosition(m)
    local d = dirtOf(v)
    if d < C.MIN_TO_WASH then
        drawWorldPrompt(x, y, z, nil, "Tu vehículo está limpio")
    else
        drawWorldPrompt(x, y, z, texE, ("Lavar el auto · $%d  (suciedad %d%%)"):format(C.PRICE, d * 100))
    end
end)

local function onKeyE()
    local v = getPedOccupiedVehicle(localPlayer)
    if not v or getVehicleController(v) ~= localPlayer or washing[v] or isCursorShowing() then return end
    local m = nearWash(v)
    if not m or dirtOf(v) < C.MIN_TO_WASH then return end
    triggerServerEvent("rp:carwash:ui:wash", resourceRoot, getElementData(m, "rp:carwash:id"))
end

----------------------------------------------------------------
-- Arranque
----------------------------------------------------------------

addEventHandler("onClientResourceStart", resourceRoot, function()
    texE = dxCreateTexture("images/keys/keyboard_e.png", "argb", true, "clamp")
    font = dxCreateFont("fonts/rubik_medium.ttf", 11) or "default-bold"
    bindKey("e", "down", onKeyE)
    setTimer(accumulate, 1000, 0)
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do refresh(v) end
end)
