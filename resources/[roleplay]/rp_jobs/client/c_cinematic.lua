--[[
    rp_jobs / c_cinematic.lua

    Cinemática de presentación de un trabajo (botón "Más información" de la agencia).
    Recorre los planos de JOBS[i].cinematic con la cámara acercándose despacio al punto
    que mira, bandas negras y subtítulo. Espacio o Enter la saltan.

    Exports (cliente):
        playJobCinematic(jobId)  -> true/false. Al terminar (o al saltarla) dispara en
                                    localPlayer el evento de cliente "rp:jobs:onCinematicEnd" (jobId).
        stopJobCinematic()
        isJobCinematicPlaying()
]]

local screenW, screenH = guiGetScreenSize()
local sc = math.max(0.75, math.min(1.3, screenH / 900))
local cine = nil   -- { job, shots, index, shotStart }
local render

addEvent("rp:jobs:onCinematicEnd", false)

local function finish()
    if not cine then return end
    local jobId = cine.job.id
    cine = nil
    removeEventHandler("onClientRender", root, render)
    unbindKey("space", "down", stopJobCinematic)
    unbindKey("enter", "down", stopJobCinematic)
    setCameraTarget(localPlayer)
    fadeCamera(true, 0.4)
    triggerEvent("rp:jobs:onCinematicEnd", localPlayer, jobId)
end

local function lerp(a, b, t) return a + (b - a) * t end

render = function()
    if not cine then return end
    local now = getTickCount()
    local shot = cine.shots[cine.index]
    local t = (now - cine.shotStart) / shot.ms
    if t >= 1 then
        cine.index = cine.index + 1
        if cine.index > #cine.shots then return finish() end
        cine.shotStart = now
        fadeCamera(false, 0)
        fadeCamera(true, 0.6)
        shot, t = cine.shots[cine.index], 0
    end
    -- la cámara avanza un 15% hacia el punto que mira, con suavizado
    local e = t * t * (3 - 2 * t)
    local c, l = shot.cam, shot.look
    local cx, cy, cz = lerp(c[1], l[1], 0.15 * e), lerp(c[2], l[2], 0.15 * e), lerp(c[3], l[3], 0.15 * e)
    setCameraMatrix(cx, cy, cz, l[1], l[2], l[3])

    local bar = screenH * 0.11
    dxDrawRectangle(0, 0, screenW, bar, tocolor(0, 0, 0, 255))
    dxDrawRectangle(0, screenH - bar, screenW, bar, tocolor(0, 0, 0, 255))
    local job = cine.job
    dxDrawText(job.icon .. "  " .. job.name:upper(), 0, bar * 0.25, screenW, bar, tocolor(job.color[1], job.color[2], job.color[3]),
        1.4 * sc, "default-bold", "center", "center")
    local alpha = math.floor(255 * math.min(1, t * 4, (1 - t) * 4))
    dxDrawText(shot.text or "", screenW * 0.12, screenH - bar, screenW * 0.88, screenH - bar * 0.35,
        tocolor(242, 244, 248, alpha), 1.25 * sc, "default-bold", "center", "center", false, true)
    dxDrawText("Espacio para saltar", 0, screenH - bar * 0.4, screenW - 20, screenH - 6, tocolor(154, 163, 178, 200), 0.9 * sc, "default", "right", "center")
    -- barra de progreso de planos
    local seg = 40 * sc
    local total = #cine.shots * (seg + 6 * sc)
    for i = 1, #cine.shots do
        local x = (screenW - total) / 2 + (i - 1) * (seg + 6 * sc)
        local fill = i < cine.index and 1 or (i == cine.index and t or 0)
        dxDrawRectangle(x, screenH - bar - 10 * sc, seg, 3 * sc, tocolor(255, 255, 255, 60))
        dxDrawRectangle(x, screenH - bar - 10 * sc, seg * fill, 3 * sc, tocolor(255, 255, 255, 220))
    end
end

function stopJobCinematic()
    if cine then finish() return true end
    return false
end

function isJobCinematicPlaying()
    return cine ~= nil
end

function playJobCinematic(jobId)
    local job = JOBS_BY_ID[jobId]
    if not job or not job.cinematic or #job.cinematic == 0 then return false end
    if cine then finish() end
    cine = { job = job, shots = job.cinematic, index = 1, shotStart = getTickCount() }
    addEventHandler("onClientRender", root, render)
    bindKey("space", "down", stopJobCinematic)
    bindKey("enter", "down", stopJobCinematic)
    fadeCamera(false, 0)
    fadeCamera(true, 0.8)
    return true
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if cine then setCameraTarget(localPlayer) end
end)
