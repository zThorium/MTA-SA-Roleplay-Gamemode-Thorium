--[[
    rp_clothing / c_studio.lua
    Estudio de ropa y accesorios: panel CEF a la derecha (html/index.html) y el
    personaje a la izquierda con camara orbital.

      Modo "shop"     (mostrador de una tienda): ropa/conjuntos, catalogo de accesorios con
                      vista previa sobre el cuerpo y "Mis accesorios".
      Modo "wardrobe" (/accesorios en cualquier sitio): solo "Mis accesorios".

    Raton fuera del panel: arrastrar = girar la camara, rueda = acercar/alejar.
    Al ajustar un accesorio aparece el gizmo (c_gizmo.lua): G mover, R rotar, S escalar,
    Shift precision, Ctrl encajar, Ctrl+Z deshacer, Esc cancelar.

    La vista previa es un objeto SOLO de este cliente; el accesorio real (del servidor) se
    oculta mientras se ajusta. Al guardar o comprar, el servidor valida y lo aplica.
]]

local screenW, screenH = guiGetScreenSize()
local S = nil   -- estado del estudio mientras esta abierto

addEvent("rp:toys:editStart", true)
addEvent("rp:cloth:ui:close", false)
addEvent("rp:cloth:ui:try", false)
addEvent("rp:cloth:ui:buy", false)
addEvent("rp:cloth:ui:preview", false)
addEvent("rp:cloth:ui:buyToy", false)
addEvent("rp:cloth:ui:adjust", false)
addEvent("rp:cloth:ui:edit", false)
addEvent("rp:cloth:ui:wear", false)
addEvent("rp:cloth:ui:delete", false)
addEvent("rp:cloth:ui:mode", false)
addEvent("rp:cloth:ui:bone", false)
addEvent("rp:cloth:ui:reset", false)
addEvent("rp:cloth:ui:undo", false)
addEvent("rp:cloth:ui:done", false)

local FIELDS = { "bone", "x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz" }
local function copyValues(v) local r = {} for _, k in ipairs(FIELDS) do r[k] = v[k] end return r end

local tex, font, fontSmall = {}, nil, nil

function isStudioOpen() return S ~= nil end
function getStudioMode() return S and S.mode end

local function callJS(code)
    if not S then return end
    if S.ready and isElement(S.browser) then executeBrowserJavascript(S.browser, code)
    else S.pending[#S.pending + 1] = code end
end

local function js(fn, ...)
    local args = {}
    for i, a in ipairs({ ... }) do args[i] = toJSON(a, true):sub(2, -2) end
    callJS(("RP.%s(%s)"):format(fn, table.concat(args, ",")))
end

local function setHud(hidden)
    local res = getResourceFromName("rp_hud")
    if res and getResourceState(res) == "running" then pcall(function() exports.rp_hud:setHudHidden("rp_clothing", hidden) end) end
end

----------------------------------------------------------------
-- Vista previa del accesorio
----------------------------------------------------------------
local function applyPreview()
    local p = S and S.preview
    if not p or not isElement(p.obj) then return end
    local v = p.values
    setObjectScale(p.obj, v.sx, v.sy, v.sz)
    exports.bone_attach:attachElementToBone(p.obj, localPlayer, v.bone, v.x, v.y, v.z, v.rx, v.ry, v.rz)
    HeadLink.relink(p.obj)   -- cabeza custom: al cuello, como la cabeza
end

local function clearPreview()
    local p = S and S.preview
    if not p then return end
    if isElement(p.obj) then
        exports.bone_attach:detachElementFromBone(p.obj)
        destroyElement(p.obj)
    end
    if isElement(p.serverObj) then setElementAlpha(p.serverObj, 255) end
    S.preview = nil
end

-- toyKey del catalogo; values = ajuste inicial; ownedId/serverObj si es un accesorio propio
local function showPreview(toyKey, values, ownedId, serverObj)
    clearPreview()
    local def = TOYS[toyKey]
    if not def then return end
    local x, y, z = getElementPosition(localPlayer)
    local obj = createObject(def.model, x, y, z)
    if not obj then return end
    setElementInterior(obj, getElementInterior(localPlayer))
    setElementDimension(obj, getElementDimension(localPlayer))
    setElementCollisionsEnabled(obj, false)
    if isElement(serverObj) then setElementAlpha(serverObj, 0) end
    S.preview = { key = toyKey, obj = obj, values = values, ownedId = ownedId, serverObj = serverObj }
    HeadLink.track(obj)
    applyPreview()
end

----------------------------------------------------------------
-- Edicion con gizmo
----------------------------------------------------------------
local function editState()
    if not S or not S.edit then return end
    js("editState", { mode = Gizmo.getMode(), bone = S.preview.values.bone, canUndo = #S.edit.undo > 0 })
end

local function startEdit()
    local p = S and S.preview
    if not p or S.edit then return end
    S.edit = { before = copyValues(p.values), undo = {} }
    Gizmo.start({
        ped = localPlayer, object = p.obj, values = p.values,
        onChange = applyPreview,
        onCommit = function(before, mode)
            local u = S.edit.undo
            u[#u + 1] = copyValues(before)
            if #u > 40 then table.remove(u, 1) end
            js("did", mode)
            editState()
        end,
    })
    local def = TOYS[p.key]
    js("editStart", {
        key = p.key, name = def.name, icon = def.icon, isNew = p.ownedId == nil, bones = BONES,
        price = S.data and getToyPrice(p.key, S.data.multiplier) or nil,
    })
    editState()
end

-- save: los accesorios propios se guardan en el servidor; los de la tienda se quedan en
-- la vista previa (se guardan al comprar). Cancelar vuelve a como estaba.
local function endEdit(save)
    local p = S and S.preview
    if not S or not S.edit or Gizmo.isDragging() then return end
    if not save then
        for k, n in pairs(S.edit.before) do p.values[k] = n end
        applyPreview()
    end
    Gizmo.stop()
    S.edit = nil
    if p.ownedId then
        if save then
            triggerServerEvent("rp:toys:save", resourceRoot, p.ownedId, copyValues(p.values))
            -- el servidor vuelve a crear el accesorio con el ajuste nuevo; si algo falla, que no quede invisible
            local serverObj = p.serverObj
            p.serverObj = nil
            if isTimer(S.alphaTimer) then killTimer(S.alphaTimer) end
            S.alphaTimer = setTimer(function() if isElement(serverObj) then setElementAlpha(serverObj, 255) end end, 1500, 1)
        end
        clearPreview()
    else
        S.adjusted[p.key] = save and copyValues(p.values) or S.adjusted[p.key]
    end
    js("editEnd", save == true)
    js("setPreview", S.preview and S.preview.key or false, S.preview and S.adjusted[S.preview.key] ~= nil or false)
end

----------------------------------------------------------------
-- Camara orbital
----------------------------------------------------------------
local function panelWidth()
    return math.floor(math.min(CLOTHING.STUDIO.panelWidth, screenW * 0.36))
end

local function focusPoint()
    if S.preview then
        local gx, gy, gz = Gizmo.getOrigin()
        if gx then return gx, gy, gz end
        local x, y, z = getElementPosition(S.preview.obj)
        if x and x ~= 0 then return x, y, z end
    end
    local x, y, z = getPedBonePosition(localPlayer, 3)
    if not x then x, y, z = getElementPosition(localPlayer) end
    return x, y, z - 0.15
end

local function updateCamera()
    if not S then return end
    local c = S.cam
    local fx, fy, fz = focusPoint()
    local k = 0.12
    c.tx, c.ty, c.tz = c.tx + (fx - c.tx) * k, c.ty + (fy - c.ty) * k, c.tz + (fz - c.tz) * k
    local wantDist = S.preview and math.min(c.dist, 1.6) or c.dist
    c.cur = c.cur + (wantDist - c.cur) * 0.15

    local yaw = math.rad(S.heading + c.yaw)
    local fwdX, fwdY = -math.sin(yaw), math.cos(yaw)
    local h = math.cos(c.pitch) * c.cur
    local cx, cy, cz = c.tx + fwdX * h, c.ty + fwdY * h, c.tz + math.sin(c.pitch) * c.cur
    -- Desplazar camara y punto de mira juntos hacia la derecha de la camara (paneo, sin girarla) deja al
    -- personaje en el centro del hueco libre a la izquierda del panel. El centro del hueco esta
    -- panel/2 px a la izquierda del centro de la pantalla; a la distancia d eso son
    -- (panel / ancho) * d * tan(fov/2) metros.
    local fov = select(8, getCameraMatrix())
    if not fov or fov < 20 or fov > 120 then fov = 70 end
    local shift = (panelWidth() / screenW) * c.cur * math.tan(math.rad(fov / 2))
    local rightX, rightY = -fwdY, fwdX   -- derecha de la camara (que mira hacia -fwd)
    local sx, sy = rightX * shift, rightY * shift
    setCameraMatrix(cx + sx, cy + sy, cz, c.tx + sx, c.ty + sy, c.tz, 0, fov)
end

----------------------------------------------------------------
-- Abrir y cerrar
----------------------------------------------------------------
function closeStudio()
    if not S then return end
    if S.edit then Gizmo.stop() end
    clearPreview()
    local mode = S.mode
    if isElement(S.gui) then destroyElement(S.gui) end
    S = nil
    if mode == "shop" then triggerServerEvent("rp:cloth:close", resourceRoot) end
    setCameraTarget(localPlayer)
    toggleAllControls(true, true, true)
    showCursor(false)
    setHud(false)
end

function openStudio(mode)
    if S then
        S.mode = mode
        return
    end
    local _, _, heading = getElementRotation(localPlayer)
    local x, y, z = getElementPosition(localPlayer)
    local w = panelWidth()
    S = {
        mode = mode, pending = {}, ready = false, adjusted = {}, heading = heading,
        cam = { yaw = 18, pitch = 0.12, dist = CLOTHING.STUDIO.camDist, cur = CLOTHING.STUDIO.camDist, tx = x, ty = y, tz = z },
    }
    S.gui = guiCreateBrowser(screenW - w, 0, w, screenH, true, true, false)
    S.browser = guiGetBrowser(S.gui)
    local state = S
    addEventHandler("onClientBrowserCreated", S.browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", S.browser, function()
        if S ~= state then return end
        S.ready = true
        for _, code in ipairs(S.pending) do executeBrowserJavascript(source, code) end
        S.pending = {}
    end)
    toggleAllControls(false, true, false)
    showCursor(true)
    setHud(true)
end

----------------------------------------------------------------
-- Datos del servidor
----------------------------------------------------------------
function studioShowShop(data)
    openStudio("shop")
    S.data = data
    js("show", data)
    if S.preview and not S.preview.ownedId then
        js("setPreview", S.preview.key, S.adjusted[S.preview.key] ~= nil)
    end
end

function studioWardrobe()
    openStudio("wardrobe")
    js("wardrobeMode")
    triggerServerEvent("rp:toys:open", resourceRoot)
end

function studioSetOwned(list, limits)
    if not S then return end
    S.owned = list
    js("setOwned", list or {}, limits or {})
end

-- El servidor confirmo una compra
function studioBought(kind, toyKey)
    if not S then return end
    if kind == "toy" and S.preview and S.preview.key == toyKey and not S.preview.ownedId then
        if S.edit then Gizmo.stop() S.edit = nil js("editEnd", true) end
        clearPreview()
        S.adjusted[toyKey] = nil
        js("setPreview", false, false)
    end
    js("sound", "confirmation_001")
end

-- Accesorio propio listo para ajustar (respuesta a rp:toys:edit)
addEventHandler("rp:toys:editStart", resourceRoot, function(row, serverObj)
    if not S or type(row) ~= "table" or not TOYS[row.toy] then return end
    local values = sanitizeToyAdjust(row) or getToyDefaults(row.toy)
    showPreview(row.toy, values, tonumber(row.id), serverObj)
    startEdit()
end)

----------------------------------------------------------------
-- Eventos de la interfaz (CEF -> Lua -> servidor)
----------------------------------------------------------------
addEventHandler("rp:cloth:ui:close", root, function() closeStudio() end)

addEventHandler("rp:cloth:ui:try", root, function(slot, index)
    if S and S.mode == "shop" and type(slot) == "string" then triggerServerEvent("rp:cloth:try", resourceRoot, slot, tonumber(index)) end
end)

addEventHandler("rp:cloth:ui:buy", root, function(slot, index)
    if S and S.mode == "shop" and type(slot) == "string" then triggerServerEvent("rp:cloth:buy", resourceRoot, slot, tonumber(index)) end
end)

-- Probarse un accesorio del catalogo ("" = quitar la vista previa)
addEventHandler("rp:cloth:ui:preview", root, function(key)
    if not S or S.mode ~= "shop" or S.edit then return end
    if type(key) ~= "string" or not TOYS[key] or (S.preview and S.preview.key == key) then
        clearPreview()
        js("setPreview", false, false)
        return
    end
    showPreview(key, S.adjusted[key] and copyValues(S.adjusted[key]) or getToyDefaults(key))
    js("setPreview", key, S.adjusted[key] ~= nil)
end)

addEventHandler("rp:cloth:ui:buyToy", root, function(key)
    if not S or S.mode ~= "shop" or type(key) ~= "string" or not TOYS[key] then return end
    local p = S.preview
    local adjust = p and p.key == key and not p.ownedId and copyValues(p.values) or S.adjusted[key]
    triggerServerEvent("rp:cloth:buyToy", resourceRoot, key, adjust)
end)

-- Ajustar el accesorio de la vista previa (antes de comprarlo)
addEventHandler("rp:cloth:ui:adjust", root, function(key)
    if not S or S.edit or type(key) ~= "string" or not TOYS[key] then return end
    if not S.preview or S.preview.key ~= key or S.preview.ownedId then
        showPreview(key, S.adjusted[key] and copyValues(S.adjusted[key]) or getToyDefaults(key))
    end
    startEdit()
end)

-- Ajustar un accesorio propio: el servidor se lo pone si hace falta y responde con editStart
addEventHandler("rp:cloth:ui:edit", root, function(id)
    if not S or S.edit then return end
    clearPreview()
    js("setPreview", false, false)
    triggerServerEvent("rp:toys:edit", resourceRoot, tonumber(id))
end)

addEventHandler("rp:cloth:ui:wear", root, function(id, state)
    triggerServerEvent("rp:toys:wear", resourceRoot, tonumber(id), state == "1" or state == true)
end)

addEventHandler("rp:cloth:ui:delete", root, function(id)
    triggerServerEvent("rp:toys:delete", resourceRoot, tonumber(id))
end)

addEventHandler("rp:cloth:ui:mode", root, function(mode)
    if S and S.edit then Gizmo.setMode(mode) editState() end
end)

-- Cambiar de hueso: la posicion vuelve al hueso (si no, saldria volando); giro y tamano se quedan
addEventHandler("rp:cloth:ui:bone", root, function(bone)
    bone = tonumber(bone)
    if not S or not S.edit or not bone or bone < 1 or bone > 20 or bone ~= math.floor(bone) then return end
    local v = S.preview.values
    local u = S.edit.undo
    u[#u + 1] = copyValues(v)
    v.bone, v.x, v.y, v.z = bone, 0, 0, 0
    local def = TOYS[S.preview.key]
    if def and bone == def.bone then v.x, v.y, v.z = def.x, def.y, def.z end
    applyPreview()
    editState()
end)

addEventHandler("rp:cloth:ui:reset", root, function()
    if not S or not S.edit then return end
    local v = S.preview.values
    S.edit.undo[#S.edit.undo + 1] = copyValues(v)
    for k, n in pairs(getToyDefaults(S.preview.key)) do v[k] = n end
    applyPreview()
    editState()
end)

local function undo()
    if not S or not S.edit or Gizmo.isDragging() then return end
    local last = table.remove(S.edit.undo)
    if not last then return end
    for k, n in pairs(last) do S.preview.values[k] = n end
    applyPreview()
    editState()
    js("sound", "click_002")
end
addEventHandler("rp:cloth:ui:undo", root, undo)

addEventHandler("rp:cloth:ui:done", root, function(save) endEdit(save == "1" or save == true) end)

----------------------------------------------------------------
-- Raton y teclas (fuera del panel)
----------------------------------------------------------------
local orbit = nil   -- { x, y } mientras se arrastra la camara

local function overPanel(x) return x >= screenW - panelWidth() end

addEventHandler("onClientClick", root, function(button, state, x, y)
    if not S then return end
    if state == "up" then
        if Gizmo.isDragging() then Gizmo.release() end
        orbit = nil
        return
    end
    if overPanel(x) then return end
    if button == "left" and S.edit and Gizmo.press(x, y) then return end
    orbit = { x, y }
end)

addEventHandler("onClientCursorMove", root, function(_, _, x, y)
    if not S then return end
    -- Si se solto el boton encima del panel no llega el "up": se suelta aqui
    if (Gizmo.isDragging() or orbit) and not getKeyState("mouse1") and not getKeyState("mouse2") then
        if Gizmo.isDragging() then Gizmo.release() end
        orbit = nil
        return
    end
    if Gizmo.isDragging() then
        Gizmo.move(x, y)
    elseif orbit then
        local c = S.cam
        c.yaw = c.yaw - (x - orbit[1]) * 0.35
        c.pitch = math.max(-0.6, math.min(1.1, c.pitch + (y - orbit[2]) * 0.006))
        orbit[1], orbit[2] = x, y
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not S or not press or isChatBoxInputActive() or isConsoleActive() then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local cx = getCursorPosition()
        if cx and overPanel(cx * screenW) then return end
        local c = S.cam
        c.dist = math.max(CLOTHING.STUDIO.camMin, math.min(CLOTHING.STUDIO.camMax, c.dist * (key == "mouse_wheel_up" and 0.88 or 1.12)))
        if S.preview then c.cur = math.min(c.cur, c.dist) end
        return
    end
    if key == "escape" then
        cancelEvent()
        if S.edit then endEdit(false) else closeStudio() end
        return
    end
    if not S.edit then return end
    local ctrl = getKeyState("lctrl") or getKeyState("rctrl")
    if key == "z" and ctrl then
        cancelEvent()
        undo()
    elseif not ctrl and (key == "g" or key == "r" or key == "s") then
        cancelEvent()
        Gizmo.setMode(key == "g" and "move" or key == "r" and "rotate" or "scale")
        js("sound", "select_002")
        editState()
    elseif key == "enter" then
        endEdit(true)
    end
end)

----------------------------------------------------------------
-- Dibujo: gizmo y ayuda de controles con las teclas dibujadas
----------------------------------------------------------------
local function drawKeyRow(x, y, icons, text)
    local size = 34
    for _, name in ipairs(icons) do
        if tex[name] then dxDrawImage(x, y, size, size, tex[name]) end
        x = x + size - 2
    end
    dxDrawText(text, x + 6, y, x + 400, y + size, tocolor(240, 242, 248, 235), 1, fontSmall or "default-bold", "left", "center")
end

local function drawHelp()
    local rows
    if S.edit then
        local mode = Gizmo.getMode()
        local what = mode == "rotate" and "Arrastra un anillo para girarlo"
            or mode == "scale" and "Arrastra un cubo (el blanco: todo) para cambiar el tamaño"
            or "Arrastra una flecha de color para moverlo"
        rows = {
            { { "mouse_left" }, what },
            { { "keyboard_g", "keyboard_r", "keyboard_s" }, "Mover · Rotar · Escalar" },
            { { "keyboard_shift" }, "Mantén para mover con precisión" },
            { { "keyboard_ctrl", "keyboard_z" }, "Deshacer" },
            { { "mouse_move" }, "Arrastra fuera del objeto para girar la cámara" },
        }
    else
        rows = {
            { { "mouse_move" }, "Arrastra para girar la cámara" },
            { { "mouse_scroll" }, "Rueda para acercar o alejar" },
            { { "keyboard_escape" }, "Salir" },
        }
    end
    local x, y = 28, screenH - 28 - #rows * 38
    dxDrawRectangle(x - 12, y - 12, 440, #rows * 38 + 18, tocolor(10, 12, 18, 150))
    for i, r in ipairs(rows) do drawKeyRow(x, y + (i - 1) * 38, r[1], r[2]) end
end

addEventHandler("onClientPreRender", root, function()
    if S then updateCamera() end
end)

addEventHandler("onClientRender", root, function()
    if not S then return end
    if S.edit then Gizmo.render() end
    drawHelp()
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, name in ipairs({ "mouse_left", "mouse_move", "mouse_scroll", "keyboard_g", "keyboard_r", "keyboard_s",
            "keyboard_shift", "keyboard_ctrl", "keyboard_z", "keyboard_escape" }) do
        tex[name] = dxCreateTexture("images/keys/" .. name .. ".png", "argb", true, "clamp")
    end
    fontSmall = dxCreateFont("fonts/rubik_medium.ttf", 10) or "default-bold"
end)

addEventHandler("onClientPlayerWasted", localPlayer, closeStudio)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, closeStudio)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if S then
        clearPreview()
        if isElement(S.gui) then destroyElement(S.gui) end
        S = nil
        setCameraTarget(localPlayer)
        toggleAllControls(true, true, true)
        showCursor(false)
        setHud(false)
    end
end)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then closeStudio() end
end)
