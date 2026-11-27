--[[
    rp_worldobjects / client/c_worldobjects.lua
    Busca bancas, sillas y sofas del mapa original junto al jugador y dibuja la tecla E encima
    de la plaza mas cercana. Con E se sienta (y con E otra vez se levanta).

    Las posiciones vienen de shared/s_data.lua (IPL del juego). La altura del asiento y hacia donde
    mira se miden aqui con raycasts sobre el modelo real: si otro recurso quito el objeto, no aparece.
]]

local sw, sh = guiGetScreenSize()
local tex, font, fontSmall = {}, nil, nil
local seated = false
local target = nil       -- { idx, seat, x, y, z, rz, label, px, py, pz }
local cache = {}         -- [idx] = { ok = bool, t = tick, rz, seats = { {x, y, z, side} } }
local CACHE_MS = 8000

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if getPedOccupiedVehicle(localPlayer) or isPedDead(localPlayer) or isElementInWater(localPlayer) then return false end
    local ok, downed = pcall(function() return exports.rp_injury:isLocalPlayerDowned() end)
    if ok and downed then return false end
    local ok2, sup = pcall(function() return exports.rp_hud:isHudSuppressed() end)
    if ok2 and sup then return false end
    return true
end

-- Raycast que devuelve la altura y el giro real si choca con el modelo buscado
local function hitModel(model, sx, sy, sz, ex, ey, ez)
    local r = { processLineOfSight(sx, sy, sz, ex, ey, ez, true, false, false, true, true, false, false, false, localPlayer, true) }
    if not r[1] then return nil end
    if r[12] ~= model then return nil end
    return r[2], r[3], r[4], r[18]
end

local function rot(lx, ly, rzDeg)
    local a = math.rad(rzDeg)
    local c, s = math.cos(a), math.sin(a)
    return lx * c - ly * s, lx * s + ly * c
end

-- Plazas de un objeto en coordenadas del mundo (se calcula una vez y se cachea)
local function measure(idx)
    local now = getTickCount()
    local c = cache[idx]
    if c and now - c.t < CACHE_MS then return c.ok and c or nil end
    local o = WO_LIST[idx]
    local b = WO_BOX[o.model]
    local cx, cy = (b[1] + b[4]) / 2, (b[2] + b[5]) / 2
    local top, bottom = o.z + b[6] + 0.3, o.z + b[3] - 0.3

    -- 1) El objeto sigue ahi y su giro real
    local wx, wy = rot(cx, cy, o.rz)
    local hx, hy, hz, realRz = hitModel(o.model, o.x + wx, o.y + wy, top, o.x + wx, o.y + wy, bottom)
    if not hz then cache[idx] = { ok = false, t = now } return nil end
    local rz = o.rz
    if realRz then rz = realRz % 360 end

    -- 2) Ejes: A = a lo largo (donde van las plazas), P = fondo (respaldo / frente)
    local alongX = (b[4] - b[1]) >= (b[5] - b[2])
    local width = alongX and (b[4] - b[1]) or (b[5] - b[2])
    local depth = alongX and (b[5] - b[2]) or (b[4] - b[1])
    local ax, ay = rot(alongX and 1 or 0, alongX and 0 or 1, rz)
    local qx, qy = rot(alongX and 0 or 1, alongX and 1 or 0, rz)
    local ox, oy = rot(cx, cy, rz)
    local centerX, centerY = o.x + ox, o.y + oy

    local seats = {}
    for i = 1, o.seats do
        local t = (o.seats == 1) and 0 or ((i - 0.5) / o.seats - 0.5) * width
        local mx, my = centerX + ax * t, centerY + ay * t
        -- Perfil del fondo: alturas en varias muestras de delante a atras. El asiento es la zona
        -- mas baja y plana; el respaldo, el lado claramente mas alto (un rayo solo en el centro
        -- puede caer sobre un respaldo grueso, como en las bancas de piedra).
        local samples, minZ = {}, nil
        local half = math.max(0.05, depth / 2 - 0.06)
        for k = -WO.DEPTH_SAMPLES, WO.DEPTH_SAMPLES do
            local u = half * k / WO.DEPTH_SAMPLES
            local sx, sy = mx + qx * u, my + qy * u
            local _, _, sz = hitModel(o.model, sx, sy, top, sx, sy, bottom)
            if sz then
                samples[#samples + 1] = { u = u, z = sz }
                if not minZ or sz < minZ then minZ = sz end
            end
        end
        if minZ then
            local seatU, nSeat, hiPos, hiNeg = 0, 0, 0, 0
            for _, s in ipairs(samples) do
                if s.z - minZ <= 0.12 then
                    seatU, nSeat = seatU + s.u, nSeat + 1
                elseif s.z - minZ >= 0.25 then
                    if s.u > 0 then hiPos = hiPos + 1 elseif s.u < 0 then hiNeg = hiNeg + 1 end
                end
            end
            seatU = seatU / nSeat
            local back
            if hiPos > 0 and hiNeg == 0 then back = 1 elseif hiNeg > 0 and hiPos == 0 then back = -1 end
            seats[#seats + 1] = { x = mx + qx * seatU, y = my + qy * seatU, z = minZ, back = back }
        end
    end
    c = { ok = #seats > 0, t = now, qx = qx, qy = qy, seats = seats }
    cache[idx] = c
    return c.ok and c or nil
end

-- ¿Hay alguien (jugador o NPC) ya sentado ahi?
local function seatTaken(x, y, z)
    for _, t in ipairs({ "player", "ped" }) do
        for _, e in ipairs(getElementsByType(t, root, true)) do
            if e ~= localPlayer then
                local ex, ey, ez = getElementPosition(e)
                if getDistanceBetweenPoints3D(x, y, z + 0.5, ex, ey, ez) < 0.55 then return true end
            end
        end
    end
    return false
end

----------------------------------------------------------------
-- Postura: altura, retroceso y giro (del tipo, del modelo o del ajuste provisional /setseatoffset)
----------------------------------------------------------------
local tune = {}          -- [modelo] = { zOffset, back, rot } (solo en memoria de este cliente)
local current = nil      -- plaza en la que estamos sentados (para reajustar en vivo)

local function offsetsOf(model)
    local def = WO.MODELS[model]
    local kind = WO.KINDS[def.kind]
    local tn = tune[model] or {}
    return tn.zOffset or def.zOffset or kind.zOffset, tn.back or def.back or kind.back, tn.rot or def.rot or 0
end

local function place(t)
    local zOff, back, rotOff = offsetsOf(t.model)
    local fx, fy = -t.qx * t.side, -t.qy * t.side
    t.x = t.sx + t.qx * t.side * back
    t.y = t.sy + t.qy * t.side * back
    t.z = t.sz + zOff
    t.rz = (math.deg(math.atan2(-fx, fy)) + rotOff) % 360
    return t
end

----------------------------------------------------------------
-- Busqueda del asiento mas cercano (cada 200 ms, no cada frame)
----------------------------------------------------------------
local function findTarget()
    if seated or not canInteract() then return nil end
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestD
    for _, idx in ipairs(WO_nearby(px, py, getElementInterior(localPlayer), WO.SCAN_RADIUS)) do
        local o = WO_LIST[idx]
        if math.abs(o.z - pz) < 2.5 then
            local m = measure(idx)
            if m then
                for s, seat in ipairs(m.seats) do
                    local d = getDistanceBetweenPoints3D(px, py, pz, seat.x, seat.y, seat.z + 0.5)
                    if d <= WO.USE_DISTANCE and (not bestD or d < bestD) and not seatTaken(seat.x, seat.y, seat.z) then
                        best, bestD = { idx = idx, s = s, m = m, seat = seat, o = o }, d
                    end
                end
            end
        end
    end
    if not best then return nil end

    -- Hacia donde mira: de espaldas al respaldo; sin respaldo, hacia el lado del jugador
    local seat, m = best.seat, best.m
    local side = seat.back
    if not side then
        local dot = (px - seat.x) * m.qx + (py - seat.y) * m.qy
        side = dot >= 0 and -1 or 1
    end
    local t = {
        idx = best.idx, seat = best.s, model = best.o.model,
        sx = seat.x, sy = seat.y, sz = seat.z, qx = m.qx, qy = m.qy, side = side,
        label = WO.KINDS[WO.MODELS[best.o.model].kind].label, name = WO.MODELS[best.o.model].name,
        markZ = seat.z,
    }
    place(t)
    return t
end

setTimer(function() target = findTarget() end, 200, 0)

----------------------------------------------------------------
-- Tecla E
----------------------------------------------------------------
local function onKeyE()
    if seated then
        if isChatBoxInputActive() or isConsoleActive() or isCursorShowing() then return end
        triggerServerEvent("rp:worldobjects:stand", resourceRoot)
        return
    end
    if not target or not canInteract() then return end    -- E no es nuestra fuera de un asiento
    local t = target
    current = t
    triggerServerEvent("rp:worldobjects:use", resourceRoot, t.idx, t.seat, t.x, t.y, t.z, t.rz)
end

-- Ajuste provisional (/setseatoffset, solo admins: el servidor decide). Sin valores: muestra los actuales.
local function fmt(n) return ("%.2f"):format(n) end
addEvent("rp:worldobjects:tune", true)
addEventHandler("rp:worldobjects:tune", resourceRoot, function(z, back, rot)
    if not seated or not current then
        return outputChatBox("[asiento] Sientate primero en una banca o silla.", 255, 180, 60)
    end
    local m = current.model
    if z then
        local cz, cb, cr = offsetsOf(m)
        tune[m] = { zOffset = z, back = back or cb, rot = rot or cr }
        place(current)
        triggerServerEvent("rp:worldobjects:adjust", resourceRoot, current.x, current.y, current.z, current.rz)
    end
    local zo, bo, ro = offsetsOf(m)
    outputChatBox(("[asiento] modelo %d (%s): altura %s, respaldo %s, giro %s"):format(m, WO.MODELS[m].name, fmt(zo), fmt(bo), fmt(ro)), 120, 200, 255)
    outputChatBox(("[asiento] superficie %s, %s, %s · ped %s, %s, %s · rz %s · lado %d"):format(
        fmt(current.sx), fmt(current.sy), fmt(current.sz), fmt(current.x), fmt(current.y), fmt(current.z), fmt(current.rz), current.side), 120, 200, 255)
    outputChatBox(("[asiento] config: [%d] = { ..., zOffset = %s, back = %s, rot = %s }"):format(m, fmt(zo), fmt(bo), fmt(ro)), 200, 200, 200)
end)

addEvent("rp:worldobjects:state", true)
addEventHandler("rp:worldobjects:state", resourceRoot, function(state)
    seated = state == true
    if not seated then current = nil end
    target = nil
    if seated then
        local snd = playSound("sounds/impactSoft_medium_000.ogg")
        if snd then setSoundVolume(snd, 0.35) end
    end
end)

----------------------------------------------------------------
-- Dibujo: tecla E sobre la plaza y aviso para levantarse
----------------------------------------------------------------
local function drawWorldPrompt(t)
    local sx, sy = getScreenFromWorldPosition(t.x, t.y, t.markZ + 0.75)
    if not sx then return end
    local px, py, pz = getElementPosition(localPlayer)
    local d = getDistanceBetweenPoints3D(px, py, pz, t.x, t.y, t.z)
    local s = math.max(0.7, 1.15 - d / 6)
    local pulse = 1 + math.sin(getTickCount() / 260) * 0.04
    local k = 42 * s * pulse
    dxDrawImage(sx - k / 2, sy - k / 2, k, k, tex.e)
    local text = t.label
    local tw = dxGetTextWidth(text, 1, font) + 20
    local ty = sy + k / 2 + 4
    dxDrawRectangle(sx - tw / 2, ty, tw, 26, tocolor(14, 12, 12, 190))
    dxDrawText(text, sx - tw / 2, ty, sx + tw / 2, ty + 26, tocolor(255, 255, 255), 1, font, "center", "center")
    dxDrawText(t.name, sx - 100, ty + 27, sx + 100, ty + 46, tocolor(220, 220, 220, 200), 1, fontSmall, "center", "center")
end

local function drawSeatedPrompt()
    local text = "Levantarse"
    local w = dxGetTextWidth(text, 1, font) + 70
    local x, y = (sw - w) / 2, sh * 0.82
    dxDrawRectangle(x, y, w, 40, tocolor(14, 12, 12, 190))
    dxDrawImage(x + 8, y + 4, 32, 32, tex.e)
    dxDrawText(text, x + 50, y, x + w, y + 40, tocolor(255, 255, 255), 1, font, "left", "center")
end

addEventHandler("onClientRender", root, function()
    if seated then
        if canInteract() then drawSeatedPrompt() end
    elseif target and canInteract() then
        drawWorldPrompt(target)
    end
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.e = dxCreateTexture("images/keys/keyboard_e.png", "argb", true, "clamp")
    font = dxCreateFont("fonts/rubik_medium.ttf", 11) or "default-bold"
    fontSmall = dxCreateFont("fonts/rubik_medium.ttf", 9) or "default"
    bindKey("e", "down", onKeyE)
end)
