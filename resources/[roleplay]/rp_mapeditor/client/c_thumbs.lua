--[[
    rp_mapeditor / c_thumbs.lua
    Miniaturas 3D del catálogo (adaptado de rp_furniture/client/c_thumbs.lua). object_preview dibuja
    el modelo en un render target; se copian sus píxeles a PNG y se mandan al panel como data URI.
    Una sola instancia para toda la tanda; si cambia el tipo (objeto, vehículo, ped) se rehace.

    API: METhumbs.request({ "o:1337", "v:411", "p:7" })   (reemplaza la cola)
]]

METhumbs = {}

local SIZE = 96
local FRAMES_MODEL, FRAMES_DRAW, FRAMES_IDLE = 3, 4, 25
local MAX_CACHE = 1500

local screenW, screenH = guiGetScreenSize()
local cache, cacheN = {}, 0
local queue = {}
local pv, job, idle = nil, nil, 0

local function available()
    local res = getResourceFromName("object_preview")
    if not res or getResourceState(res) ~= "running" then return false end
    return (tonumber(dxGetStatus().VideoCardNumRenderTargets) or 1) > 1
end

local function push(key)
    local data = cache[key]
    if data then MEUI.push("win", "thumb", { key = key, src = data }) end
end

function METhumbs.request(list)
    queue = {}
    for _, key in ipairs(type(list) == "table" and list or {}) do
        key = tostring(key)
        if key:match("^[ovp]:%d+$") then
            if cache[key] == nil then queue[#queue + 1] = key
            elseif cache[key] then push(key) end
        end
        if #queue >= 60 then break end
    end
end

local function radiusOf(el)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
    local r = 1
    if x1 then r = math.max(1, math.abs(x1), math.abs(y1), math.abs(z1), math.abs(x2), math.abs(y2), math.abs(z2)) end
    return math.max(r, getElementRadius(el) or 0)
end

local function destroyPreview()
    if pv then
        pcall(function() exports.object_preview:destroyObjectPreview(pv.prev) end)
        if isElement(pv.el) then destroyElement(pv.el) end
        pv = nil
    end
    job = nil
end

local function makeElement(kind, model)
    if kind == "o" then return createObject(model, 0, 0, -100)
    elseif kind == "v" then return createVehicle(model, 0, 0, -100)
    else return createPed(model, 0, 0, -100) end
end

local function createPreview(kind, model)
    local el = makeElement(kind, model)
    if not el then return false end
    setElementDimension(el, getElementDimension(localPlayer))
    setElementInterior(el, getElementInterior(localPlayer))
    -- el recuadro queda bajo el panel derecho, que lo tapa
    local px, py = screenW - SIZE - 24, screenH - SIZE - 24
    local ok, prev = pcall(function()
        return exports.object_preview:createObjectPreview(el, -22, 0, 145, px, py, SIZE, SIZE, false, false, true)
    end)
    if not ok or not prev then destroyElement(el) return false end
    pv = { el = el, kind = kind, prev = prev, R0 = radiusOf(el), px = px, py = py }
    return true
end

local function capture(key)
    local ok, data = pcall(function()
        local rt = exports.object_preview:getRenderTarget()
        if not rt then return nil end
        local pixels = dxGetTexturePixels(rt, pv.px, pv.py, SIZE, SIZE)
        if not pixels then return nil end
        local png = dxConvertPixels(pixels, "png")
        return png and ("data:image/png;base64," .. encodeString("base64", png)) or nil
    end)
    if cacheN > MAX_CACHE then cache, cacheN = {}, 0 end
    cache[key] = (ok and data) or false
    cacheN = cacheN + 1
    push(key)
end

addEventHandler("onClientRender", root, function()
    if not (MEEditor and MEEditor.active) then
        if pv then destroyPreview() end
        return
    end
    if job then
        job.frames = job.frames + 1
        if job.stage == 1 and job.frames >= FRAMES_MODEL then
            local r = radiusOf(pv.el)
            pcall(function() exports.object_preview:setDistanceSpread(pv.prev, 1.9 * r - 1.6 * pv.R0) end)
            job.stage, job.frames = 2, 0
        elseif job.stage == 2 and job.frames >= FRAMES_DRAW then
            capture(job.key)
            job = nil
        end
        return
    end
    if #queue == 0 then
        if pv then
            idle = idle + 1
            if idle >= FRAMES_IDLE then destroyPreview() end
        end
        return
    end
    idle = 0
    if not available() then
        for _, key in ipairs(queue) do cache[key] = false end
        queue = {}
        return
    end
    local key = table.remove(queue, 1)
    if cache[key] ~= nil then return end
    local kind, model = key:match("^(%a):(%d+)$")
    model = tonumber(model)
    if pv and pv.kind ~= kind then destroyPreview() end
    if not pv then
        if not createPreview(kind, model) then cache[key] = false return end
    elseif not setElementModel(pv.el, model) then
        cache[key] = false
        return
    end
    job = { key = key, stage = 1, frames = 0 }
end)

addEventHandler("onClientResourceStop", resourceRoot, destroyPreview)
