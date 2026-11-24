--[[
    rp_furniture / c_thumbs.lua
    Miniaturas 3D del catalogo. Usa object_preview (Ren712): dibuja un modelo en un render target,
    se copian sus pixeles, se convierten a PNG y se mandan al panel como data URI.

    Se usa UNA sola instancia de object_preview para toda la tanda (se cambia el modelo del mismo
    objeto con setElementModel). Crear y destruir una instancia por mueble hacia parpadear los
    objetos en el centro de la pantalla. La instancia se destruye tras unos cuadros sin trabajo.

    API: FurnThumbs.request("key1,key2,...")   pide miniaturas (reemplaza la cola)
]]

FurnThumbs = {}

local SIZE = 128
local FRAMES_MODEL = 3        -- cuadros para que cargue el modelo antes de medirlo
local FRAMES_DRAW = 4         -- cuadros para que object_preview dibuje con la distancia nueva
local FRAMES_IDLE = 25        -- cuadros sin trabajo antes de destruir la instancia

local screenW, screenH = guiGetScreenSize()
local cache = {}        -- [key] = "data:image/png;base64,..." | false (fallo)
local queue = {}
local pv = nil          -- { obj, prev, R0, px, py }
local job = nil         -- { key, stage, frames }
local idle = 0

local function available()
    local res = getResourceFromName("object_preview")
    if not res or getResourceState(res) ~= "running" then return false end
    return (tonumber(dxGetStatus().VideoCardNumRenderTargets) or 1) > 1
end

local function push(key)
    local data = cache[key]
    if data and FurnEditor and FurnEditor.panelJS then
        FurnEditor.panelJS("left", ("FURN.thumb(%s, %s)"):format(FurnCore.jsString(key), FurnCore.jsString(data)))
    end
end

function FurnThumbs.request(csv)
    queue = {}
    for key in tostring(csv or ""):gmatch("[^,]+") do
        if FURN_ITEMS[key] then
            if cache[key] == nil then queue[#queue + 1] = key
            elseif cache[key] then push(key) end
        end
    end
end

-- mismo calculo del radio que hace object_preview al crear la instancia
local function radiusOf(obj)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(obj)
    local r = 1
    if x1 then r = math.max(1, math.abs(x1), math.abs(y1), math.abs(z1), math.abs(x2), math.abs(y2), math.abs(z2)) end
    return math.max(r, getElementRadius(obj) or 0)
end

local function destroyPreview()
    if pv then
        pcall(function() exports.object_preview:destroyObjectPreview(pv.prev) end)
        if isElement(pv.obj) then destroyElement(pv.obj) end
        pv = nil
    end
    job = nil
end

local function createPreview(def)
    local obj = createObject(def.model, 0, 0, -100)   -- object_preview lo recoloca delante de la camara
    if not obj then return false end
    -- debe estar en la misma dimension e interior que el jugador para dibujarse
    setElementDimension(obj, getElementDimension(localPlayer))
    setElementInterior(obj, getElementInterior(localPlayer))
    -- el recuadro queda bajo el panel derecho, que lo tapa
    local px, py = screenW - SIZE - 24, screenH - SIZE - 24
    local ok, prev = pcall(function()
        return exports.object_preview:createObjectPreview(obj, -22, 0, 145, px, py, SIZE, SIZE, false, false, true)
    end)
    if not ok or not prev then
        destroyElement(obj)
        return false
    end
    pv = { obj = obj, prev = prev, R0 = radiusOf(obj), px = px, py = py }
    return true
end

local function capture(key)
    local ok, data = pcall(function()
        local rt = exports.object_preview:getRenderTarget()
        if not rt then return nil end
        local pixels = dxGetTexturePixels(rt, pv.px, pv.py, SIZE, SIZE)
        if not pixels then return nil end
        local png = dxConvertPixels(pixels, "png")
        if not png then return nil end
        return "data:image/png;base64," .. encodeString("base64", png)
    end)
    cache[key] = (ok and data) or false
    if not (ok and data) then
        outputDebugString("[rp_furniture] No se pudo generar la miniatura de " .. key .. " (" .. tostring(data) .. ")", 2)
    end
    push(key)
end

addEventHandler("onClientRender", root, function()
    if not FurnEditor or not FurnEditor.active then
        if pv then destroyPreview() end
        return
    end

    if job then
        job.frames = job.frames + 1
        if job.stage == 1 and job.frames >= FRAMES_MODEL then
            -- el modelo ya cargo: se acerca la camara segun su tamano (~85% del recuadro)
            local r = radiusOf(pv.obj)
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
    local def = FURN_ITEMS[key]
    if not pv then
        if not createPreview(def) then cache[key] = false return end
    else
        setElementModel(pv.obj, def.model)
    end
    job = { key = key, stage = 1, frames = 0 }
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    destroyPreview()
end)
