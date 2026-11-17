--[[
    rp_clothing / c_editor.lua
    Editor de accesorios: hueso, posicion, rotacion y escala por eje.

    Mientras se edita, el accesorio real (del servidor) se oculta solo para ti
    y se muestra una copia local que cambia en vivo con los controles. Al
    guardar se mandan los valores al servidor, que los valida y los aplica.
    La camara gira alrededor del personaje con los controles del panel.
]]

local screenW, screenH = guiGetScreenSize()
local editor = nil   -- { row, preview, serverObj, browserGui, browser, ready, values, cam = { angle, zoom } }

addEvent("rp:toys:editStart", true)
addEvent("rp:toyed:change", false)
addEvent("rp:toyed:camera", false)
addEvent("rp:toyed:save", false)
addEvent("rp:toyed:cancel", false)

function isToyEditorActive() return editor ~= nil end

local FIELDS = { "x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz" }

-- Altura de la camara segun la zona del cuerpo
local function boneHeight(bone)
    if bone <= 2 then return 0.65 end
    if bone == 4 or bone >= 13 then return bone >= 15 and -0.55 or -0.1 end
    return 0.3
end

local function applyPreview()
    local e = editor
    if not e or not isElement(e.preview) then return end
    local v = e.values
    setObjectScale(e.preview, v.sx, v.sy, v.sz)
    exports.bone_attach:attachElementToBone(e.preview, localPlayer, v.bone, v.x, v.y, v.z, v.rx, v.ry, v.rz)
end

local function updateCamera()
    local e = editor
    if not e then return end
    local px, py, pz = getElementPosition(localPlayer)
    local _, _, heading = getElementRotation(localPlayer)
    local tz = pz + boneHeight(e.values.bone)
    -- angle 0 = de frente al personaje
    local a = math.rad(heading + e.cam.angle)
    local dist = e.cam.zoom
    local cx, cy = px - math.sin(a) * dist, py + math.cos(a) * dist
    setCameraMatrix(cx, cy, tz + 0.15, px, py, tz)
end

local function stop(save)
    local e = editor
    if not e then return end
    editor = nil
    if save then
        local v = e.values
        triggerServerEvent("rp:toys:save", resourceRoot, e.row.id, {
            bone = v.bone, x = v.x, y = v.y, z = v.z, rx = v.rx, ry = v.ry, rz = v.rz, sx = v.sx, sy = v.sy, sz = v.sz,
        })
    end
    if isElement(e.preview) then
        exports.bone_attach:detachElementFromBone(e.preview)
        destroyElement(e.preview)
    end
    if isElement(e.serverObj) then setElementAlpha(e.serverObj, 255) end
    if isElement(e.browserGui) then destroyElement(e.browserGui) end
    removeEventHandler("onClientPreRender", root, updateCamera)
    setCameraTarget(localPlayer)
    toggleAllControls(true, true, true)
    showCursor(false)
    guiSetInputEnabled(false)
end

addEventHandler("rp:toys:editStart", resourceRoot, function(row, serverObj)
    if editor or type(row) ~= "table" then return end
    local def = TOYS[row.toy]
    if not def then return end

    local x, y, z = getElementPosition(localPlayer)
    local preview = createObject(def.model, x, y, z)
    if not preview then return end
    setElementInterior(preview, getElementInterior(localPlayer))
    setElementDimension(preview, getElementDimension(localPlayer))
    setElementCollisionsEnabled(preview, false)

    local values = { bone = tonumber(row.bone) or def.bone }
    for _, k in ipairs(FIELDS) do values[k] = tonumber(row[k]) or 0 end
    editor = {
        row = row, preview = preview, serverObj = serverObj, values = values,
        cam = { angle = 0, zoom = 1.6 },
    }
    if isElement(serverObj) then setElementAlpha(serverObj, 0) end
    applyPreview()

    -- Panel lateral (CEF)
    editor.browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    editor.browser = guiGetBrowser(editor.browserGui)
    local e = editor
    addEventHandler("onClientBrowserCreated", e.browser, function()
        loadBrowserURL(source, "http://mta/local/html/editor.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", e.browser, function()
        local init = {
            name = def.name, values = e.values, bones = BONES, limits = CLOTHING.LIMITS,
            defaults = { bone = def.bone, x = def.x, y = def.y, z = def.z, rx = def.rx, ry = def.ry, rz = def.rz, sx = 1, sy = 1, sz = 1 },
        }
        executeBrowserJavascript(source, ("RP.init(%s[0])"):format(toJSON(init, true)))
    end)

    toggleAllControls(false, true, false)
    showCursor(true)
    guiSetInputEnabled(true)
    addEventHandler("onClientPreRender", root, updateCamera)
end)

-- Valores del panel (JSON). Se recortan igual que en el servidor.
addEventHandler("rp:toyed:change", root, function(json)
    if not editor or type(json) ~= "string" or #json > 2000 then return end
    local v = fromJSON(json)
    if type(v) ~= "table" then return end
    local L = CLOTHING.LIMITS
    local function clamp(n, a, b)
        n = tonumber(n)
        if not n or n ~= n then return nil end
        return math.max(a, math.min(b, n))
    end
    local bone = tonumber(v.bone)
    if bone and bone >= 1 and bone <= 20 then editor.values.bone = math.floor(bone) end
    for _, k in ipairs(FIELDS) do
        local isScale, isRot = k:sub(1, 1) == "s", k:sub(1, 1) == "r"
        local n = isScale and clamp(v[k], L.scaleMin, L.scaleMax) or isRot and clamp(v[k], -L.rot, L.rot) or clamp(v[k], -L.pos, L.pos)
        if n then editor.values[k] = n end
    end
    applyPreview()
end)

addEventHandler("rp:toyed:camera", root, function(angle, zoom)
    if not editor then return end
    editor.cam.angle = tonumber(angle) or editor.cam.angle
    editor.cam.zoom = math.max(0.8, math.min(4, tonumber(zoom) or editor.cam.zoom))
end)

addEventHandler("rp:toyed:save", root, function() stop(true) end)
addEventHandler("rp:toyed:cancel", root, function() stop(false) end)

addEventHandler("onClientPlayerWasted", localPlayer, function() stop(false) end)
addEventHandler("onClientResourceStop", resourceRoot, function() stop(false) end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then stop(false) end
end)
