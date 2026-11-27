--[[
    rp_phone / c_tinder_studio.lua
    Estudio de fotos de los NPC de Tinder (/tinderstudio, admin). Lleva la camara a cada
    escenario de San Andreas (TINDER_SCENES), pone la hora y el clima del escenario, crea un
    ped local con la skin del NPC y la pose pedida (TINDER_POSES), encuadra como una foto
    de verdad (selfie con el brazo estirado, retrato, cuerpo entero, sentado, tumbado en la
    arena, junto a su auto o un paisaje sin nadie) y captura la pantalla en 4:5 + miniatura.
    El jugador no se mueve: solo la camara (el mundo se carga alrededor de la camara).
]]

local screenW, screenH = guiGetScreenSize()
local st = nil   -- estado del estudio

addEvent("rp:tinder:studio:jobs", true)
addEvent("rp:tinder:studio:done", true)

local function rad(d) return math.rad(d) end

local function cropRect()
    local h = math.floor(screenH * 0.9)
    local w = math.floor(h * TINDER.PHOTO_W / TINDER.PHOTO_H)
    return math.floor((screenW - w) / 2), math.floor((screenH - h) / 2), w, h
end

local function cleanupScene()
    if not st then return end
    if isElement(st.ped) then destroyElement(st.ped) end
    if isElement(st.veh) then destroyElement(st.veh) end
    st.ped, st.veh = nil, nil
end

local function finish(count)
    if not st then return end
    cleanupScene()
    if st.render then removeEventHandler("onClientRender", root, st.render) end
    removeEventHandler("onClientRender", root, st.overlay)
    for _, e in ipairs({ st.ss, st.rt, st.rtThumb }) do if isElement(e) then destroyElement(e) end end
    for _, t in ipairs(st.timers) do if isTimer(t) then killTimer(t) end end
    setTime(st.time[1], st.time[2]) -- estandar:mundo cambio local y temporal en el cliente del admin para la foto; se restaura al terminar
    setWeather(st.weather) -- estandar:mundo cambio local y temporal en el cliente del admin para la foto; se restaura al terminar
    setCameraTarget(localPlayer)
    setElementAlpha(localPlayer, 255)
    setElementFrozen(localPlayer, false)
    toggleAllControls(true)
    showChat(true)
    pcall(function() exports.rp_hud:setHudSuppressed("rp_phone", false) end) -- estandar:dep-opcional rp_hud con pcall: sin rp_hud el estudio sigue
    st = nil
    if count and count >= 0 then outputChatBox(("[Tinder] Estudio terminado (%d fotos)."):format(count), 255, 120, 160) end
end

local function later(ms, fn)
    if not st then return end
    st.timers[#st.timers + 1] = setTimer(function() if st then fn() end end, ms, 1)
end

-- Suelo bajo (x, y): rayo de arriba abajo (necesita la colision cargada alrededor de la camara)
local function groundAt(x, y, z)
    local hit, _, _, hz = processLineOfSight(x, y, z + 80, x, y, z - 120, true, false, false, true, false, false, false, false)
    if hit then return hz end
    local gz = getGroundPosition(x, y, z + 80)
    if gz and gz ~= 0 then return gz end
    return nil
end

local function animFor(pose, gender)
    local a = pose.anim
    if not a then return nil end
    if a[0] or a[1] then return a[gender] or a[0] end
    return a
end

----------------------------------------------------------------
-- Captura (onClientRender, despues de dibujar el mundo)
----------------------------------------------------------------
local function capture()
    local x, y, w, h = cropRect()
    if not st.ss then st.ss = dxCreateScreenSource(screenW, screenH) end
    if not st.rt then st.rt = dxCreateRenderTarget(TINDER.PHOTO_W, TINDER.PHOTO_H, false) end
    if not st.rtThumb then st.rtThumb = dxCreateRenderTarget(TINDER.THUMB_W, TINDER.THUMB_H, false) end
    if not st.ss or not st.rt or not st.rtThumb then return nil end
    dxUpdateScreenSource(st.ss, true)
    dxSetBlendMode("modulate_add")
    dxSetRenderTarget(st.rt, true)
    dxDrawImageSection(0, 0, TINDER.PHOTO_W, TINDER.PHOTO_H, x, y, w, h, st.ss)
    dxSetRenderTarget(st.rtThumb, true)
    dxDrawImageSection(0, 0, TINDER.THUMB_W, TINDER.THUMB_H, x, y, w, h, st.ss)
    dxSetRenderTarget()
    dxSetBlendMode("blend")
    local p1, p2 = dxGetTexturePixels(st.rt), dxGetTexturePixels(st.rtThumb)
    if not p1 or not p2 then return nil end
    local big, small = dxConvertPixels(p1, "jpeg", 86), dxConvertPixels(p2, "jpeg", 80)
    if not big or not small then return nil end
    return encodeString("base64", big), encodeString("base64", small)
end

----------------------------------------------------------------
-- Encuadre de cada tipo de foto
----------------------------------------------------------------
local function frame(job, pose, base, view)
    local fx, fy = -math.sin(rad(view)), math.cos(rad(view))   -- hacia donde mira la camara
    local rx, ry = math.cos(rad(view)), math.sin(rad(view))    -- derecha
    local gx, gy, gz = base[1], base[2], base[3]
    local cam = pose.cam
    if cam == "landscape" then
        local cx, cy, cz = gx, gy, gz + 1.7
        return cx, cy, cz, cx + fx * 60, cy + fy * 60, cz - 2.5, 0, 65
    end
    local hx, hy, hz = getPedBonePosition(st.ped, 8)
    if not hx then hx, hy, hz = gx, gy, gz + 1.6 end
    if cam == "selfie" then
        local d = 0.58
        return hx - fx * d + rx * 0.12, hy - fy * d + ry * 0.12, hz + 0.1, hx, hy, hz + 0.02, math.random(-5, 5), 72
    elseif cam == "portrait" then
        return gx - fx * 2.3, gy - fy * 2.3, hz - 0.12, hx, hy, hz - 0.25, 0, 46
    elseif cam == "full" then
        return gx - fx * 4.8, gy - fy * 4.8, gz + 1.25, gx, gy, gz + 0.9, 0, 50
    elseif cam == "sit" then
        return gx - fx * 2.4 + rx * 0.4, gy - fy * 2.4 + ry * 0.4, hz + 0.15, hx, hy, hz - 0.35, 0, 50
    elseif cam == "lay" then
        local px, py, pz = getPedBonePosition(st.ped, 3)
        if not px then px, py, pz = gx, gy, gz + 0.3 end
        return px - fx * 1.4, py - fy * 1.4, pz + 2.1, px, py, pz, 0, 62
    elseif cam == "car" then
        local mx, my = gx + rx * 1.3, gy + ry * 1.3
        return mx - fx * 7, my - fy * 7, gz + 1.4, mx, my, gz + 0.8, 0, 55
    end
    return gx - fx * 3, gy - fy * 3, gz + 1.5, gx, gy, gz + 1, 0, 50
end

----------------------------------------------------------------
-- Una foto
----------------------------------------------------------------
local nextJob

local function shoot(job, pose, base, view)
    local cx, cy, cz, lx, ly, lz, roll, fov = frame(job, pose, base, view)
    setCameraMatrix(cx, cy, cz, lx, ly, lz, roll, fov)
    if isElement(st.ped) then setPedLookAt(st.ped, cx, cy, cz, -1, 0) end
    later(600, function()
        -- Encuadre final (la cabeza se movio al mirar a camara) y captura dos frames despues
        cx, cy, cz, lx, ly, lz, roll, fov = frame(job, pose, base, view)
        setCameraMatrix(cx, cy, cz, lx, ly, lz, roll, fov)
        st.hideOverlay = true
        local frames = 0
        st.render = function()
            frames = frames + 1
            if frames < 3 then return end
            removeEventHandler("onClientRender", root, st.render)
            st.render = nil
            local img, thumb = capture()
            st.hideOverlay = false
            if img then
                triggerLatentServerEvent("rp:tinder:studio:photo", 300000, false, resourceRoot, job.id, img, thumb)
                st.done = st.done + 1
            end
            cleanupScene()
            later(250, nextJob)
        end
        addEventHandler("onClientRender", root, st.render, true, "low-1000")
    end)
end

local function placeAndShoot(job)
    local scene = TINDER_SCENES[job.scene]
    local pose = TINDER_POSES[job.pose] or TINDER_POSES.portrait
    -- Variacion: cada foto en el mismo escenario se corre unos metros y gira un poco
    local view = scene.view + math.random(-25, 25)
    local rx, ry = math.cos(rad(view)), math.sin(rad(view))
    local off = math.random(-40, 40) / 10
    local x, y = scene.x + rx * off, scene.y + ry * off
    local gz = groundAt(x, y, scene.z) or groundAt(scene.x, scene.y, scene.z)
    if not gz then
        st.failed = st.failed + 1
        return later(100, nextJob)
    end
    if not groundAt(x, y, scene.z) then x, y = scene.x, scene.y end
    setTime(scene.hour, scene.minute) -- estandar:mundo cambio local y temporal en el cliente del admin para la foto; se restaura al terminar
    setWeather(scene.weather) -- estandar:mundo cambio local y temporal en el cliente del admin para la foto; se restaura al terminar
    local base = { x, y, gz }
    if pose.cam ~= "landscape" then
        local face = (view + 180 + math.random(-12, 12)) % 360
        st.ped = createPed(job.skin, x, y, gz + 1, face)
        if not st.ped then st.failed = st.failed + 1 return later(100, nextJob) end
        if setElementStreamable then setElementStreamable(st.ped, false) end
        local anim = animFor(pose, job.gender)
        if anim then setPedAnimation(st.ped, anim[1], anim[2], -1, true, false, false, false) end
        if pose.cam == "car" then
            local vx, vy = x + rx * 2.6, y + ry * 2.6
            st.veh = createVehicle(job.car or 411, vx, vy, gz + 1, 0, 0, (view + 90) % 360)
            if st.veh then
                if setElementStreamable then setElementStreamable(st.veh, false) end
                setVehicleColor(st.veh, math.random(0, 126), math.random(0, 126), 0, 0)
            end
        end
    end
    later(900, function() shoot(job, pose, base, view) end)
end

nextJob = function()
    if not st then return end
    st.index = st.index + 1
    local job = st.jobs[st.index]
    if not job then
        triggerServerEvent("rp:tinder:studio:next", resourceRoot)
        return
    end
    local scene = TINDER_SCENES[job.scene]
    if not scene then st.failed = st.failed + 1 return nextJob() end
    st.current = scene.label
    if st.scene ~= job.scene then
        -- Escenario nuevo: llevar la camara y esperar a que cargue el mundo
        st.scene = job.scene
        local fx, fy = -math.sin(rad(scene.view)), math.cos(rad(scene.view))
        setCameraMatrix(scene.x - fx * 6, scene.y - fy * 6, scene.z + 4, scene.x, scene.y, scene.z + 1)
        setTime(scene.hour, scene.minute) -- estandar:mundo cambio local y temporal en el cliente del admin para la foto; se restaura al terminar
        setWeather(scene.weather) -- estandar:mundo cambio local y temporal en el cliente del admin para la foto; se restaura al terminar
        later(3500, function() placeAndShoot(job) end)
    else
        placeAndShoot(job)
    end
end

----------------------------------------------------------------
-- Inicio / fin
----------------------------------------------------------------
addEventHandler("rp:tinder:studio:jobs", resourceRoot, function(jobs)
    if type(jobs) ~= "table" or #jobs == 0 then return end
    if not st then
        if Phone and Phone.isOpen() then Phone.close() end
        local h, m = getTime()
        st = { timers = {}, done = 0, failed = 0, time = { h, m }, weather = getWeather() }
        st.overlay = function()
            if not st or st.hideOverlay then return end
            local text = ("ESTUDIO DE TINDER  ·  %d fotos  ·  %s  ·  /tinderstudio para detener"):format(st.done, st.current or "")
            dxDrawRectangle(0, screenH - 34, screenW, 34, tocolor(0, 0, 0, 170))
            dxDrawText(text, 0, screenH - 34, screenW, screenH, tocolor(255, 120, 160), 1.1, "default-bold", "center", "center")
        end
        addEventHandler("onClientRender", root, st.overlay, true, "low-2000")
        setElementFrozen(localPlayer, true)
        setElementAlpha(localPlayer, 0)
        toggleAllControls(false)
        showChat(false)
        pcall(function() exports.rp_hud:setHudSuppressed("rp_phone", true) end) -- estandar:dep-opcional rp_hud con pcall: sin rp_hud el estudio sigue
    end
    st.jobs, st.index = jobs, 0
    nextJob()
end)

addEventHandler("rp:tinder:studio:done", resourceRoot, function(count) finish(count) end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if st then
        triggerServerEvent("rp:tinder:studio:stop", resourceRoot)
        finish(-1)
    end
end)
addEventHandler("onClientPlayerWasted", localPlayer, function()
    if st then
        triggerServerEvent("rp:tinder:studio:stop", resourceRoot)
        finish(-1)
    end
end)
