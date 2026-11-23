--[[
    rp_phone / c_camera.lua
    Camara de Fotogram: HUD de camara (html/social.js), selfie con el brazo
    estirado o camara trasera, poses, zoom, temporizador y captura en 4:5.

    Controles (los lee el navegador y los reenvia, el telefono tiene el foco):
        A / D o flechas   girar al personaje (cambia el fondo)
        W / S             subir o bajar la camara (selfie) / inclinarla (trasera)
        Rueda, + / -      acercar o alejar
        Q / E             pose anterior / siguiente      F  cambiar de camara
        Espacio / Enter   disparar                       Esc  volver al telefono

    La foto se recorta del centro de la pantalla (el visor del HUD) y se manda al
    telefono como JPEG en base64; alli se editan los filtros (social.js).
]]

local C = FOTOGRAM
local screenW, screenH = guiGetScreenSize()

local cam = nil          -- estado mientras la camara esta abierta
local screenSource, renderTarget = nil, nil
local shooting = false

addEvent("rp:phone:ui:camera", false)

local function frameRect()
    local h = math.floor(screenH * C.FRAME_SCREEN_H)
    local w = math.floor(h * C.PHOTO_W / C.PHOTO_H)
    return math.floor((screenW - w) / 2), math.floor((screenH - h) / 2), w, h
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function posesFor(mode)
    local list = {}
    for _, p in ipairs(FOTOGRAM_POSES) do
        if p.mode == mode or p.mode == "both" then list[#list + 1] = { id = p.id, name = p.name, icon = p.icon } end
    end
    return list
end

local function poseIndex(mode, id)
    for i, p in ipairs(posesFor(mode)) do if p.id == id then return i end end
    return 1
end

----------------------------------------------------------------
-- Camara en cada frame
----------------------------------------------------------------
local function updateCamera(dt)
    if not cam then return end
    dt = math.min((dt or 16) / 1000, 0.1)

    -- Girar al personaje (a pie)
    local turn = (cam.keys.left and 1 or 0) - (cam.keys.right and 1 or 0)
    if turn ~= 0 and not isPedInVehicle(localPlayer) then
        local _, _, rz = getElementRotation(localPlayer)
        setElementRotation(localPlayer, 0, 0, (rz + turn * C.TURN_SPEED * dt) % 360, "default", true)
    end
    local vertical = (cam.keys.up and 1 or 0) - (cam.keys.down and 1 or 0)
    if cam.mode == "selfie" then
        cam.height = clamp(cam.height + vertical * 0.5 * dt, C.SELFIE_HEIGHT.min, C.SELFIE_HEIGHT.max)
    else
        cam.pitch = clamp(cam.pitch + vertical * 45 * dt, C.REAR_PITCH.min, C.REAR_PITCH.max)
    end

    local element = getPedOccupiedVehicle(localPlayer) or localPlayer
    local _, _, rz = getElementRotation(element)
    local rad = math.rad(rz + cam.yaw)                -- cam.yaw: giro libre con clic derecho
    local fx, fy = -math.sin(rad), math.cos(rad)      -- hacia delante
    local rx, ry = math.cos(rad), math.sin(rad)       -- hacia la derecha
    local hx, hy, hz = getPedBonePosition(localPlayer, 8)
    if not hx then return end

    local tx, ty, tz, lx, ly, lz, fov
    if cam.mode == "selfie" then
        -- Telefono delante de la cara, un poco a la derecha (brazo derecho)
        local d = cam.dist
        tx, ty, tz = hx + fx * d + rx * 0.12 * d, hy + fy * d + ry * 0.12 * d, hz + cam.height
        lx, ly, lz = hx, hy, hz + 0.02
        fov = 70
    else
        local p = math.rad(cam.pitch)
        tx, ty, tz = hx + fx * 0.3 + rx * 0.08, hy + fy * 0.3 + ry * 0.08, hz - 0.03
        lx, ly, lz = tx + fx * math.cos(p) * 10, ty + fy * math.cos(p) * 10, tz + math.sin(p) * 10
        fov = cam.fov
    end

    -- Suavizado (las animaciones mueven la cabeza)
    local k = math.min(1, dt * 10)
    if not cam.pos then cam.pos, cam.look = { tx, ty, tz }, { lx, ly, lz } end
    cam.pos[1], cam.pos[2], cam.pos[3] = cam.pos[1] + (tx - cam.pos[1]) * k, cam.pos[2] + (ty - cam.pos[2]) * k, cam.pos[3] + (tz - cam.pos[3]) * k
    cam.look[1], cam.look[2], cam.look[3] = cam.look[1] + (lx - cam.look[1]) * k, cam.look[2] + (ly - cam.look[2]) * k, cam.look[3] + (lz - cam.look[3]) * k
    setCameraMatrix(cam.pos[1], cam.pos[2], cam.pos[3], cam.look[1], cam.look[2], cam.look[3], 0, fov)
end

----------------------------------------------------------------
-- Brazo estirado en la selfie (para todos los jugadores con rp:phoneCam = selfie)
----------------------------------------------------------------
local armOverride = {}   -- copia editable con /selfieajuste
for bone, v in pairs(SELFIE_ARM) do armOverride[bone] = { v[1], v[2], v[3] } end

-- Desactivado: rotar los huesos del brazo con la cabeza custom (ped sin cabeza)
-- duplicaba la cabeza sobre el brazo levantado. Poner en true para volver a probarlo.
local APPLY_SELFIE_ARM = false

addEventHandler("onClientPedsProcessed", root, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if getElementData(player, "rp:phoneCam") == "selfie" and isElementOnScreen(player) and not isPedDead(player) then
            if getElementData(player, "rp:head") and setPedHeadless then setPedHeadless(player, true) end
            if APPLY_SELFIE_ARM and setElementBoneRotation then
                for bone, v in pairs(armOverride) do
                    setElementBoneRotation(player, bone, v[1], v[2], v[3])
                end
                updateElementRpHAnim(player)
                if getElementData(player, "rp:head") and setPedHeadless then setPedHeadless(player, true) end
            end
        end
    end
end)

-- Ajuste en vivo del brazo (solo afecta a tu vista; copia los valores a SELFIE_ARM)
addCommandHandler("selfieajuste", function(_, bone, yaw, pitch, roll)
    bone = tonumber(bone)
    if not bone or not armOverride[bone] then
        for b, v in pairs(armOverride) do outputChatBox(("[%d] = { %g, %g, %g },"):format(b, v[1], v[2], v[3]), 200, 200, 255) end
        return outputChatBox("Uso: /selfieajuste <22|23|24> <yaw> <pitch> <roll>", 255, 200, 0)
    end
    local v = armOverride[bone]
    v[1], v[2], v[3] = tonumber(yaw) or v[1], tonumber(pitch) or v[2], tonumber(roll) or v[3]
    outputChatBox(("[%d] = { %g, %g, %g },"):format(bone, v[1], v[2], v[3]), 200, 200, 255)
end)

----------------------------------------------------------------
-- Abrir / cerrar
----------------------------------------------------------------
local function sendState()
    if not cam then return end
    Phone.callJS(("RP.camera.state(%s)"):format(Phone.json({
        mode = cam.mode, pose = cam.pose, poses = posesFor(cam.mode),
        canPose = not isPedInVehicle(localPlayer),
        zoom = cam.mode == "selfie"
            and (cam.dist - C.SELFIE_DIST.min) / (C.SELFIE_DIST.max - C.SELFIE_DIST.min)
            or (C.REAR_FOV.max - cam.fov) / (C.REAR_FOV.max - C.REAR_FOV.min),
    })))
end

local function stopCamera(keepServerPose)
    if not cam then return end
    cam = nil
    removeEventHandler("onClientPreRender", root, updateCamera)
    setCameraTarget(localPlayer)
    setElementData(localPlayer, "rp:hudHidden", false, false)
    if not keepServerPose then triggerServerEvent("rp:social:camera", resourceRoot, false) end
    if isElement(renderTarget) then destroyElement(renderTarget) end
    if isElement(screenSource) then destroyElement(screenSource) end
    renderTarget, screenSource, shooting = nil, nil, false
    local gui = Phone.getGui()
    if isElement(gui) then guiSetVisible(gui, true) end
end

local function startCamera(mode)
    mode = mode == "rear" and "rear" or "selfie"
    if not Phone.isOpen() or isPedDead(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
    if not cam then
        cam = {
            keys = {}, dist = C.SELFIE_DIST.default, height = C.SELFIE_HEIGHT.default,
            fov = C.REAR_FOV.default, pitch = 0, yaw = 0,
        }
        addEventHandler("onClientPreRender", root, updateCamera)
        setElementData(localPlayer, "rp:hudHidden", true, false)
    end
    cam.mode, cam.pos, cam.look = mode, nil, nil
    cam.pose = FOTOGRAM_DEFAULT_POSE[mode]
    triggerServerEvent("rp:social:camera", resourceRoot, mode)
    local x, y, w, h = frameRect()
    Phone.callJS(("RP.camera.open(%s)"):format(Phone.json({ x = x, y = y, w = w, h = h, screenW = screenW, screenH = screenH })))
    sendState()
end

local function setPose(id)
    if not cam or isPedInVehicle(localPlayer) then return end
    local pose = FOTOGRAM_POSE_BY_ID[id]
    if not pose or (pose.mode ~= cam.mode and pose.mode ~= "both") then return end
    cam.pose = id
    triggerServerEvent("rp:social:pose", resourceRoot, id)
    sendState()
end

local function cyclePose(step)
    if not cam then return end
    local list = posesFor(cam.mode)
    local i = (poseIndex(cam.mode, cam.pose) - 1 + step) % #list + 1
    setPose(list[i].id)
end

local function zoom(step)
    if not cam then return end
    if cam.mode == "selfie" then
        cam.dist = clamp(cam.dist - step * 0.06, C.SELFIE_DIST.min, C.SELFIE_DIST.max)
    else
        cam.fov = clamp(cam.fov - step * 4, C.REAR_FOV.min, C.REAR_FOV.max)
    end
    sendState()
end

----------------------------------------------------------------
-- Captura: oculta el HUD de la camara dos frames, copia la pantalla, recorta 4:5
----------------------------------------------------------------
local function capture()
    local x, y, w, h = frameRect()
    if not screenSource then screenSource = dxCreateScreenSource(screenW, screenH) end
    if not renderTarget then renderTarget = dxCreateRenderTarget(C.PHOTO_W, C.PHOTO_H, false) end
    if not screenSource or not renderTarget then return nil end
    dxUpdateScreenSource(screenSource, true)
    dxSetRenderTarget(renderTarget, true)
    dxSetBlendMode("modulate_add")
    dxDrawImageSection(0, 0, C.PHOTO_W, C.PHOTO_H, x, y, w, h, screenSource)
    dxSetBlendMode("blend")
    dxSetRenderTarget()
    local pixels = dxGetTexturePixels(renderTarget)
    return pixels and dxConvertPixels(pixels, "jpeg", 92)
end

local function shoot()
    if not cam or shooting then return end
    shooting = true
    local gui = Phone.getGui()
    if isElement(gui) then guiSetVisible(gui, false) end
    local frames = 0
    local function onRender()
        frames = frames + 1
        if frames < 3 then return end   -- el navegador tarda un frame en desaparecer
        removeEventHandler("onClientRender", root, onRender)
        local jpeg = cam and capture()
        if isElement(gui) then guiSetVisible(gui, true) end
        shooting = false
        if not jpeg then
            exports.rp_notify:notify("No se pudo tomar la foto.", "error")
            return
        end
        playSoundFrontEnd(41)
        stopCamera()
        Phone.callJS(("RP.camera.shot(%s)"):format(Phone.jsString(encodeString("base64", jpeg))))
    end
    addEventHandler("onClientRender", root, onRender, true, "low-1000")
end

----------------------------------------------------------------
-- Telefono -> camara
----------------------------------------------------------------
local KEYS = { left = true, right = true, up = true, down = true }

addEventHandler("rp:phone:ui:camera", root, function(action, a, b)
    if action == "open" then return startCamera(a) end
    if not cam then return end
    if action == "close" then stopCamera()
    elseif action == "flip" then startCamera(cam.mode == "selfie" and "rear" or "selfie")
    elseif action == "key" and KEYS[a] then cam.keys[a] = b == true
    elseif action == "release" then cam.keys = {}
    elseif action == "look" then
        -- Clic derecho + arrastrar: el visor sigue al raton (a = dx, b = dy en pixeles)
        local dx, dy = clamp(tonumber(a) or 0, -300, 300), clamp(tonumber(b) or 0, -300, 300)
        cam.yaw = (cam.yaw + dx * 0.3) % 360
        if cam.mode == "selfie" then cam.height = clamp(cam.height + dy * 0.004, C.SELFIE_HEIGHT.min, C.SELFIE_HEIGHT.max)
        else cam.pitch = clamp(cam.pitch + dy * 0.25, C.REAR_PITCH.min, C.REAR_PITCH.max) end
    elseif action == "resetLook" then cam.yaw = 0
    elseif action == "zoom" then zoom(tonumber(a) or 0)
    elseif action == "zoomTo" then
        local t = clamp(tonumber(a) or 0, 0, 1)
        if cam.mode == "selfie" then cam.dist = C.SELFIE_DIST.min + t * (C.SELFIE_DIST.max - C.SELFIE_DIST.min)
        else cam.fov = C.REAR_FOV.max - t * (C.REAR_FOV.max - C.REAR_FOV.min) end
    elseif action == "pose" then setPose(tostring(a or ""))
    elseif action == "nextPose" then cyclePose(tonumber(a) or 1)
    elseif action == "shoot" then shoot()
    end
end)

-- Limpieza: nunca dejar la camara atascada
addEventHandler("rp:phone:onClose", localPlayer, function() stopCamera() end)
addEventHandler("onClientPlayerWasted", localPlayer, function() stopCamera(true) end)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, function() stopCamera(true) end)
addEventHandler("onClientResourceStop", resourceRoot, function() stopCamera(true) end)
addEventHandler("onClientRestore", root, function()
    -- Al perder el dispositivo (alt+tab) el render target se vacia: se recrea al disparar
    if isElement(renderTarget) then destroyElement(renderTarget) end
    renderTarget = nil
end)
addEventHandler("onClientPlayerVehicleEnter", localPlayer, sendState)
addEventHandler("onClientPlayerVehicleExit", localPlayer, sendState)
