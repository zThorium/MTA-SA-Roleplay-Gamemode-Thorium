--[[
    rp_injury / c_injury.lua
    Lado cliente del estado abatido:
      - Intercepta el dano mortal y avisa al servidor.
      - Pantalla gris con vinyeta y latido rojo (shader), cuenta atras y barra.
      - Sangrado: gotas de sangre (fxAddBlood) y un charco que crece bajo cada abatido.
      - Avisa a los demas recursos con "rp:onClientPlayerDowned" para que cierren sus interfaces.
]]

addEvent("rp:injury:state", true)
addEvent("rp:onClientPlayerDowned", false)

local sw, sh = guiGetScreenSize()
local scale = math.max(0.75, sh / 1080)

local active = false      -- abatido (estado local)
local dyingLocal = false  -- murio desangrado, esperando el hospital
local startedAt, expiresAt, total = 0, 0, 1
local requested = false   -- ya pedimos quedar abatido (evita repetir el evento)

local screenSource, shader
local poolTexture = dxCreateTexture("files/blood_pool.png", "argb", true, "clamp")
local pools = {}          -- [player] = { x, y, z, started }
local BLEED_BONES = { 3, 2, 8 }

local function isDowned(player)
    return getElementData(player, "rp:downed") == true
end

----------------------------------------------------------------
-- Dano
----------------------------------------------------------------
addEventHandler("onClientPlayerDamage", localPlayer, function(attacker, weapon, bodypart, loss)
    if getElementData(localPlayer, "rp:downed") or dyingLocal then
        cancelEvent()
        return
    end
    if not getElementData(localPlayer, "rp:characterId") then return end
    if loss < getElementHealth(localPlayer) then return end

    -- Este golpe lo mataria: queda abatido
    cancelEvent()
    if requested then return end
    requested = true
    triggerServerEvent("rp:injury:down", resourceRoot, isElement(attacker) and attacker or nil, weapon)
    setTimer(function() if not active then requested = false end end, 3000, 1)
end)

----------------------------------------------------------------
-- Charcos de sangre (de cualquier jugador abatido cercano)
----------------------------------------------------------------
local function addPool(player)
    if pools[player] or not isElementStreamedIn(player) then return end
    local x, y, z = getElementPosition(player)
    local gz = getGroundPosition(x, y, z + 1)
    if gz and gz ~= 0 and math.abs(gz - z) < 3 then z = gz else z = z - 0.95 end
    pools[player] = { x = x, y = y, z = z + 0.02, started = getTickCount() }
end

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if key ~= "rp:downed" or getElementType(source) ~= "player" then return end
    if new == true then
        -- La posicion se toma un momento despues, cuando ya cayo al suelo
        local player = source
        setTimer(function() if isElement(player) and isDowned(player) then addPool(player) end end, 900, 1)
    else
        pools[source] = nil
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" and isDowned(source) then addPool(source) end
end)

addEventHandler("onClientPlayerQuit", root, function() pools[source] = nil end)

-- Gotas de sangre saliendo del cuerpo
setTimer(function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if isDowned(player) and not isPedDead(player) then
            local bone = BLEED_BONES[math.random(#BLEED_BONES)]
            local x, y, z = getPedBonePosition(player, bone)
            if x then
                fxAddBlood(x, y, z, (math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, -0.4, math.random(1, 3), 0.8)
            end
            if not pools[player] then addPool(player) end
        end
    end
end, 350, 0)

addEventHandler("onClientRender", root, function()
    if not poolTexture then return end
    local now = getTickCount()
    local cx, cy, cz = getCameraMatrix()
    for player, p in pairs(pools) do
        if not isElement(player) then
            pools[player] = nil
        elseif getDistanceBetweenPoints3D(cx, cy, cz, p.x, p.y, p.z) < 80 then
            local grow = math.min(1, (now - p.started) / 70000)
            local size = 0.5 + 1.7 * grow
            dxDrawMaterialLine3D(p.x, p.y - size / 2, p.z, p.x, p.y + size / 2, p.z, poolTexture, size,
                tocolor(255, 255, 255, 230), p.x, p.y, p.z + 10)
        end
    end
end, true, "high+5")

----------------------------------------------------------------
-- Pantalla
----------------------------------------------------------------
local function createShader()
    if shader then return true end
    screenSource = dxCreateScreenSource(sw, sh)
    shader = dxCreateShader("files/downed.fx")
    if not screenSource or not shader then
        if isElement(screenSource) then destroyElement(screenSource) end
        if isElement(shader) then destroyElement(shader) end
        screenSource, shader = nil, nil
        return false
    end
    dxSetShaderValue(shader, "ScreenTexture", screenSource)
    return true
end

local function destroyShader()
    if isElement(shader) then destroyElement(shader) end
    if isElement(screenSource) then destroyElement(screenSource) end
    shader, screenSource = nil, nil
end

-- Se dibuja antes que las demas interfaces (prioridad alta), asi el mundo queda gris
local function drawScreen()
    local now = getTickCount()
    local progress = math.min(1, (now - startedAt) / total)
    local fadeIn = math.min(1, (now - startedAt) / 1500)
    -- Latido: mas rapido y fuerte cuanto menos tiempo queda
    local rate = 1.0 + progress * 1.6
    local beat = math.abs(math.sin((now / 1000) * math.pi * rate)) ^ 6

    if shader then
        dxUpdateScreenSource(screenSource, true)
        dxSetShaderValue(shader, "Saturation", 1 - fadeIn * 0.95)
        dxSetShaderValue(shader, "Darkness", (0.35 + progress * 0.5) * fadeIn)
        dxSetShaderValue(shader, "Pulse", (0.35 + beat * 0.65) * fadeIn)
        dxDrawImage(0, 0, sw, sh, shader)
    else
        dxDrawRectangle(0, 0, sw, sh, tocolor(45, 45, 45, 150 * fadeIn))
        dxDrawRectangle(0, 0, sw, sh, tocolor(120, 0, 0, 40 * beat * fadeIn))
    end
end

local function formatTime(ms)
    local s = math.max(0, math.ceil(ms / 1000))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- Texto encima de todo (prioridad baja)
local function drawOverlay()
    local now = getTickCount()
    local left = expiresAt - now
    local alpha = math.min(1, (now - startedAt) / 1000) * 255

    local cx = sw / 2
    local y = sh * 0.68
    dxDrawText("ABATIDO", 0, y + 2 * scale, sw + 2 * scale, y + 60 * scale, tocolor(0, 0, 0, alpha * 0.7), 2.6 * scale, "default-bold", "center", "top")
    dxDrawText("ABATIDO", 0, y, sw, y + 60 * scale, tocolor(200, 30, 30, alpha), 2.6 * scale, "default-bold", "center", "top")
    y = y + 52 * scale
    dxDrawText(("Te estas desangrando  -  %s"):format(formatTime(left)), 0, y, sw, y + 30 * scale,
        tocolor(235, 235, 235, alpha), 1.4 * scale, "default-bold", "center", "top")
    y = y + 34 * scale

    local bw, bh = 360 * scale, 6 * scale
    local frac = math.max(0, math.min(1, left / total))
    dxDrawRectangle(cx - bw / 2, y, bw, bh, tocolor(0, 0, 0, alpha * 0.6))
    dxDrawRectangle(cx - bw / 2, y, bw * frac, bh, tocolor(170, 20, 20, alpha))
    y = y + 16 * scale
    dxDrawText("Espera a que alguien te atienda", 0, y, sw, y + 24 * scale,
        tocolor(190, 190, 190, alpha * 0.9), 1.1 * scale, "default", "center", "top")
end

-- Si la animacion se corta (stream, empujon...), se pide reponerla al servidor
local animWatch
local function checkAnimation()
    if not active or isPedDead(localPlayer) then return end
    local block, anim = getPedAnimation(localPlayer)
    if isPedInVehicle(localPlayer) or not block or block:lower() ~= INJURY.ANIM_BLOCK:lower()
        or not anim or anim:lower() ~= INJURY.ANIM_NAME:lower() then
        triggerServerEvent("rp:injury:reanim", resourceRoot)
    end
end

local function start(remaining)
    local now = getTickCount()
    if not active then
        startedAt = now
        total = INJURY.DOWNED_TIME
        createShader()
        addEventHandler("onClientRender", root, drawScreen, true, "high+3")
        addEventHandler("onClientRender", root, drawOverlay, true, "low-10")
        animWatch = setTimer(checkAnimation, 1000, 0)
        showCursor(false)
        guiSetInputEnabled(false)
    end
    active, dyingLocal, requested = true, false, false
    expiresAt = now + remaining
    total = math.max(total, remaining)
    triggerEvent("rp:onClientPlayerDowned", localPlayer)
end

local function stop()
    if not active then return end
    active = false
    removeEventHandler("onClientRender", root, drawScreen)
    removeEventHandler("onClientRender", root, drawOverlay)
    if isTimer(animWatch) then killTimer(animWatch) end
    animWatch = nil
    destroyShader()
end

addEventHandler("rp:injury:state", resourceRoot, function(state, remaining)
    if state == true then
        start(tonumber(remaining) or INJURY.DOWNED_TIME)
    else
        stop()
        dyingLocal = state == "dying"
        requested = false
    end
end)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    dyingLocal, requested = false, false
end)

-- La pantalla se puede perder al minimizar; se recrea
addEventHandler("onClientRestore", root, function()
    if active then destroyShader(); createShader() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if isDowned(player) then addPool(player) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, stop)

-- Export cliente para otros recursos
function isLocalPlayerDowned()
    return getElementData(localPlayer, "rp:downed") and true or false
end
