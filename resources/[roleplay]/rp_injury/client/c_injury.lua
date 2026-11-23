--[[
    rp_injury / c_injury.lua
    Lado cliente del estado abatido:
      - Intercepta el dano mortal y avisa al servidor.
      - Pantalla en escala de grises y desenfoque al mover la camara (c_screen.lua).
      - Contador: reloj de arena verde en el centro; cuando se vacia, muere.
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
-- Reloj de arena (contador de los 2 minutos). Texturas de 256 px: circulo verde, marco
-- y la arena de cada bulbo por separado; la arena de arriba baja y la de abajo sube.
local HOURGLASS = {
    circle = dxCreateTexture("files/hourglass_circle.png", "argb", true, "clamp"),
    frame  = dxCreateTexture("files/hourglass_frame.png", "argb", true, "clamp"),
    top    = dxCreateTexture("files/hourglass_sand_top.png", "argb", true, "clamp"),
    bottom = dxCreateTexture("files/hourglass_sand_bottom.png", "argb", true, "clamp"),
    TOP_Y0 = 72, TOP_Y1 = 128,      -- filas de la arena del bulbo superior (en la textura)
    BOT_Y0 = 128, BOT_Y1 = 184,     -- filas de la arena del bulbo inferior
    TEX = 256,
}

local function drawHourglass(cx, cy, size, left, alpha)
    local h = HOURGLASS
    if not (h.circle and h.frame and h.top and h.bottom) then return false end
    local k = size / h.TEX
    local x, y = cx - size / 2, cy - size / 2
    local white = tocolor(255, 255, 255, alpha)

    dxDrawImage(x, y, size, size, h.circle, 0, 0, 0, white)

    -- Los bulbos son casi triangulos: la altura de la arena va con la raiz del area
    local topH = math.sqrt(left) * (h.TOP_Y1 - h.TOP_Y0)
    if topH > 0.5 then
        local v = h.TOP_Y1 - topH
        dxDrawImageSection(x, y + v * k, size, topH * k, 0, v, h.TEX, topH, h.top, 0, 0, 0, white)
    end
    local botH = (1 - math.sqrt(left)) * (h.BOT_Y1 - h.BOT_Y0)
    if botH > 0.5 then
        local v = h.BOT_Y1 - botH
        dxDrawImageSection(x, y + v * k, size, botH * k, 0, v, h.TEX, botH, h.bottom, 0, 0, 0, white)
    end
    -- Hilo de arena cayendo por el cuello
    if left > 0.005 then
        local sy = y + h.BOT_Y0 * k
        local ey = y + (h.BOT_Y1 - botH) * k
        local flicker = 0.75 + 0.25 * math.sin(getTickCount() / 60)
        dxDrawRectangle(cx - 1.2 * k, sy, 2.4 * k, math.max(0, ey - sy), tocolor(255, 255, 255, alpha * flicker))
    end

    dxDrawImage(x, y, size, size, h.frame, 0, 0, 0, white)
    return true
end

-- Encima de todo (prioridad baja): el reloj es el contador; cuando se vacia, muere
local function drawOverlay()
    local now = getTickCount()
    local left = math.max(0, math.min(1, (expiresAt - now) / total))
    local alpha = math.min(1, (now - startedAt) / 1000) * 255
    local size = 120 * scale

    if not drawHourglass(sw / 2, sh / 2, size, left, alpha) then
        -- Sin texturas: contador en texto
        local s = math.max(0, math.ceil((expiresAt - now) / 1000))
        dxDrawText(("%d:%02d"):format(math.floor(s / 60), s % 60), 0, 0, sw, sh,
            tocolor(255, 255, 255, alpha), 2 * scale, "default-bold", "center", "center")
    end
    local y = sh / 2 + size / 2 + 14 * scale
    dxDrawText("Espera a que alguien te atienda", 1, y + 1, sw + 1, y + 25 * scale,
        tocolor(0, 0, 0, alpha * 0.6), 1.1 * scale, "default-bold", "center", "top")
    dxDrawText("Espera a que alguien te atienda", 0, y, sw, y + 24 * scale,
        tocolor(225, 225, 225, alpha * 0.9), 1.1 * scale, "default-bold", "center", "top")
end

-- Si la animacion se corta (stream, empujon...), se pide reponerla al servidor
local animWatch
local function checkAnimation()
    if not active or isPedDead(localPlayer) then return end
    if isPedInVehicle(localPlayer) and getElementData(localPlayer, "rp:loaded") then return end
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
        InjuryScreen.fadeIn()
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
    removeEventHandler("onClientRender", root, drawOverlay)
    if isTimer(animWatch) then killTimer(animWatch) end
    animWatch = nil
end

addEventHandler("rp:injury:state", resourceRoot, function(state, remaining)
    if state == true then
        start(tonumber(remaining) or INJURY.DOWNED_TIME)
    else
        stop()
        dyingLocal = state == "dying"
        requested = false
        -- Reanimado: los colores vuelven poco a poco. Si murio desangrado, la pantalla
        -- sigue gris durante la muerte y se recupera al aparecer en el hospital.
        if not dyingLocal then InjuryScreen.fadeOut() end
    end
end)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    if dyingLocal then InjuryScreen.fadeOut() end
    dyingLocal, requested = false, false
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if isDowned(player) then addPool(player) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stop()
    InjuryScreen.stop()
end)

-- Export cliente para otros recursos
function isLocalPlayerDowned()
    return getElementData(localPlayer, "rp:downed") and true or false
end
