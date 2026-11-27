--[[
    rp_mapeditor / c_draw.lua
    Dibujo del editor: cajas de selección, bloqueos de otros builders, puntos y quitados, gizmo,
    fantasma, caja de selección, barra inferior con las teclas dibujadas (UX-01) y el tutorial
    guiado la primera vez (UX-03): METutorial.start() / .event(nombre) / .stop().
]]

local screenW, screenH = guiGetScreenSize()
local DOCK_W = 52   -- columna de iconos de la izquierda (c_ui.lua)
local keyTex = {}
local fontB, fontS

local function E() return MEEditor.E end
local function line(x1, y1, z1, x2, y2, z2, c, w) dxDrawLine3D(x1, y1, z1, x2, y2, z2, c, w or 2) end
local function norm(a, b, c) local l = math.sqrt(a * a + b * b + c * c) if l == 0 then l = 1 end return a / l, b / l, c / l end

local function key(name)
    if keyTex[name] == nil then
        local path = "images/keys/" .. name .. ".png"
        keyTex[name] = fileExists(path) and dxCreateTexture(path, "argb", true, "clamp") or false
    end
    return keyTex[name]
end

local function text(t, x, y, color, scale, font, alignX)
    dxDrawText(t, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 220), scale or 1, font or "default-bold", alignX or "center", "top", false, false, false, true)
    dxDrawText(t, x, y, x, y, color or tocolor(255, 255, 255), scale or 1, font or "default-bold", alignX or "center", "top", false, false, false, true)
end

local function label3d(t, x, y, z, color)
    local sx, sy = getScreenFromWorldPosition(x, y, z)
    if sx then text(t, sx, sy, color) end
end

-- Caja orientada del elemento (con su escala)
local function drawBox(el, color)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(el)
    if not x1 then x1, y1, z1, x2, y2, z2 = -0.5, -0.5, 0, 0.5, 0.5, 1 end
    local m = getElementMatrix(el)
    if not m then return end
    local sx, sy, sz = 1, 1, 1
    if getElementType(el) == "object" then sx, sy, sz = getObjectScale(el) end
    local rxv = { norm(m[1][1], m[1][2], m[1][3]) }
    local fv = { norm(m[2][1], m[2][2], m[2][3]) }
    local uv = { norm(m[3][1], m[3][2], m[3][3]) }
    local px, py, pz = m[4][1], m[4][2], m[4][3]
    local function pt(a, b, c)
        a, b, c = a * (sx or 1), b * (sy or 1), c * (sz or 1)
        return px + rxv[1] * a + fv[1] * b + uv[1] * c, py + rxv[2] * a + fv[2] * b + uv[2] * c, pz + rxv[3] * a + fv[3] * b + uv[3] * c
    end
    local C = {}
    for i = 0, 7 do
        C[i] = { pt(i % 2 == 0 and x1 or x2, math.floor(i / 2) % 2 == 0 and y1 or y2, math.floor(i / 4) == 0 and z1 or z2) }
    end
    for _, ed in ipairs({ {0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7} }) do
        local a, b = C[ed[1]], C[ed[2]]
        line(a[1], a[2], a[3], b[1], b[2], b[3], color, 2)
    end
end

local function drawCross(x, y, z, r, color)
    line(x - r, y, z, x + r, y, z, color, 3)
    line(x, y - r, z, x, y + r, z, color, 3)
    line(x, y, z - r, x, y, z + r, color, 3)
end

local function drawCircle(x, y, z, r, color)
    local px, py = x + r, y
    for i = 1, 32 do
        local a = i / 32 * math.pi * 2
        local nx, ny = x + math.cos(a) * r, y + math.sin(a) * r
        line(px, py, z, nx, ny, z, color, 2)
        px, py = nx, ny
    end
end

local function drawGizmo()
    local e = E()
    local ox, oy, oz = MEInput.gizmoOrigin()
    if not ox then return end
    local L = MEInput.gizmoLen(ox, oy, oz)
    local hover, drag = MEInput.hover(), MEInput.drag()
    local active = drag and drag.axis or hover
    if e.gizmo == "rotate" then
        for axis, col in pairs(MEInput.AXCOL) do
            local a = axis == active and 255 or 190
            local c = tocolor(col[1], col[2], col[3], a)
            local px, py, pz
            for i = 0, 48 do
                local wx, wy, wz = MEInput.ringPoint(ox, oy, oz, axis, i / 48 * math.pi * 2, L * 0.85)
                if px then line(px, py, pz, wx, wy, wz, c, axis == active and 4 or 2) end
                px, py, pz = wx, wy, wz
            end
        end
    else
        local vecs = MEInput.axisVectors()
        for axis, col in pairs(MEInput.AXCOL) do
            local v = vecs[axis]
            local c = tocolor(col[1], col[2], col[3], axis == active and 255 or 210)
            local ex, ey, ez = ox + v[1] * L, oy + v[2] * L, oz + v[3] * L
            line(ox, oy, oz, ex, ey, ez, c, axis == active and 5 or 3)
            if e.gizmo == "scale" then
                local s = L * 0.06
                drawCross(ex, ey, ez, s, c)
            end
            label3d(axis:upper(), ex, ey, ez + L * 0.05, c)
        end
    end
    if drag and drag.info then
        local sx, sy = getScreenFromWorldPosition(ox, oy, oz)
        if sx then text(drag.info, sx, sy + 24, tocolor(255, 230, 150)) end
    end
end

local function drawHints()
    local e = E()
    local hints
    if e.tool == "place" then
        hints = { { "mouse_left", "Colocar" }, { "mouse_scroll", "Girar" }, { "keyboard_shift", "Sin rejilla" },
                  { "keyboard_backspace", "Soltar" } }
    elseif e.tool == "remove" then
        hints = { { "mouse_left", "Quitar edificio" }, { "keyboard_backspace", "Terminar" } }
    elseif next(e.sel) then
        hints = { { "keyboard_1", "Mover" }, { "keyboard_2", "Girar" }, { "keyboard_3", "Escalar" }, { "keyboard_r", "90°" },
                  { "keyboard_enter", "Propiedades" }, { "keyboard_delete", "Borrar" }, { "keyboard_ctrl", "+D duplicar" } }
    else
        hints = { { "keyboard_w", "Mover cámara" }, { "mouse_right", "Mirar" }, { "keyboard_e", "Subir" }, { "keyboard_q", "Bajar" },
                  { "mouse_left", "Elegir" }, { "keyboard_f", "Probar" }, { "keyboard_h", "Paneles" } }
    end
    local size, gap = 30, 14
    local widths, total = {}, 0
    for i, h in ipairs(hints) do
        widths[i] = size + 6 + dxGetTextWidth(h[2], 1, "default-bold")
        total = total + widths[i] + gap
    end
    local areaL = MEUI.isHidden() and 0 or DOCK_W
    local areaR = screenW
    local x = areaL + (areaR - areaL - total) / 2
    local y = screenH - size - 34
    dxDrawRectangle(x - 12, y - 8, total + 12, size + 16, tocolor(14, 18, 26, 190))
    for i, h in ipairs(hints) do
        local tex = key(h[1])
        if tex then dxDrawImage(x, y, size, size, tex) end
        dxDrawText(h[2], x + size + 6, y, x + widths[i], y + size, tocolor(235, 240, 250), 1, "default-bold", "left", "center")
        x = x + widths[i] + gap
    end

    -- Línea de estado abajo a la izquierda (como el editor de MTA): qué está elegido y dónde
    local ids = MEEditor.selectedIds()
    local status
    if #ids == 1 then
        local row = e.rows[ids[1]]
        local px, py, pz = MEEditor.posOf(ids[1])
        status = ("%s #%d · %s · %.2f, %.2f, %.2f"):format(MAPEDIT.ETYPE_NAMES[row.etype] or row.etype, ids[1],
            MEEditor.label(row), px, py, pz)
    elseif #ids > 1 then
        status = ("%d elementos elegidos"):format(#ids)
    else
        local n = 0
        for _ in pairs(e.rows) do n = n + 1 end
        status = ("%s · %d elementos · cámara x%.2g"):format(e.project.name, n, MECam.speed)
    end
    dxDrawText(status, 9, screenH - 21, screenW, screenH, tocolor(0, 0, 0, 220), 1, "default-bold")
    dxDrawText(status, 8, screenH - 22, screenW, screenH, tocolor(235, 240, 250), 1, "default-bold")
end

----------------------------------------------------------------
-- Tutorial guiado (primera vez). Los pasos avanzan al hacer la acción.
----------------------------------------------------------------
METutorial = {}
local tut = nil
local STEPS = {
    { id = "camera", title = "Mueve la cámara", body = "Usa W A S D para volar, E y Q para subir y bajar.\nMantén el clic derecho para mirar alrededor.",
      keys = { "keyboard_w", "keyboard_a", "keyboard_s", "keyboard_d", "mouse_right" }, where = "center" },
    { id = "pick", title = "Elige qué poner", body = "Pulsa el cubo de la columna de la izquierda, busca un\nobjeto (nombre o número) y haz clic en él.",
      keys = { "mouse_left" }, where = "left" },
    { id = "place", title = "Colócalo", body = "Apunta al suelo y haz clic para colocarlo.\nLa rueda lo gira antes de soltarlo.",
      keys = { "mouse_left", "mouse_scroll" }, where = "center" },
    { id = "move", title = "Ajústalo", body = "Arrastra las flechas de colores para moverlo.\n1 mover · 2 girar · 3 escalar. Ctrl+Z deshace.",
      keys = { "keyboard_1", "keyboard_2", "keyboard_3" }, where = "center" },
    { id = "publish", title = "Publícalo", body = "Todo se guarda solo en el borrador. Cuando esté listo,\npulsa el icono de publicar (arriba) y lo verán todos.",
      keys = {}, where = "top", final = true },
}

function METutorial.start() tut = { step = 1, tick = getTickCount(), cam = { MECam.x, MECam.y } } end
function METutorial.stop() tut = nil end

function METutorial.event(name)
    if not tut then return end
    local s = STEPS[tut.step]
    if s and s.id == name then
        tut.step, tut.tick = tut.step + 1, getTickCount()
        MEEditor.sound("pluck_001")
    end
end

local function drawTutorial()
    if not tut then return end
    local s = STEPS[tut.step]
    if not s then return end
    if s.id == "camera" and getDistanceBetweenPoints2D(MECam.x, MECam.y, tut.cam[1], tut.cam[2]) > 8 then
        return METutorial.event("camera")
    end
    if s.final and getTickCount() - tut.tick > 9000 then
        MEEditor.ui("tutorialDone", {})
        return
    end
    local w, h = 430, 150
    local x, y
    if s.where == "left" then x, y = DOCK_W + 12, screenH - h - 70
    elseif s.where == "top" then x, y = 20, 60
    else x, y = (screenW - w) / 2, screenH * 0.62 end
    local a = math.min(1, (getTickCount() - tut.tick) / 250)
    dxDrawRectangle(x, y, w, h, tocolor(14, 18, 26, 230 * a))
    dxDrawRectangle(x, y, 4, h, tocolor(255, 160, 40, 255 * a))
    dxDrawText(("Paso %d de %d"):format(tut.step, #STEPS), x + 18, y + 10, x + w, y + 24, tocolor(255, 180, 80, 255 * a), 1, "default-bold")
    dxDrawText(s.title, x + 18, y + 26, x + w, y + 50, tocolor(255, 255, 255, 255 * a), 1.5, "default-bold")
    dxDrawText(s.body, x + 18, y + 58, x + w - 18, y + 100, tocolor(215, 222, 235, 255 * a), 1, "default")
    local kx = x + 18
    for _, k in ipairs(s.keys) do
        local tex = key(k)
        if tex then dxDrawImage(kx, y + h - 40, 30, 30, tex, 0, 0, 0, tocolor(255, 255, 255, 255 * a)) end
        kx = kx + 34
    end
    dxDrawText("Retroceso dos veces o «Saltar tutorial» en el panel para omitirlo", x, y + h + 4, x + w, y + h + 20,
        tocolor(180, 186, 200, 200 * a), 0.9, "default", "center")
end

----------------------------------------------------------------
addEventHandler("onClientRender", root, function()
    local e = E()
    if not e or e.testing then return end
    local dim = getElementDimension(localPlayer)

    -- puntos y quitados (no tienen elemento) y lo que tiene otro builder
    for id, row in pairs(e.rows) do
        local x, y, z = MEEditor.posOf(id)
        local sel = e.sel[id]
        local lock = MEEditor.lockedByOther(id)
        if row.etype == "point" then
            local c = sel and tocolor(255, 200, 60) or tocolor(90, 200, 255)
            line(x, y, z - 1, x, y, z + 1, c, 3)
            local rz = math.rad((e.preview[id] or row).rz or 0)
            line(x, y, z, x - math.sin(rz) * 1.2, y + math.cos(rz) * 1.2, z, c, 3)
            drawCircle(x, y, z - 1, 0.5, c)
            label3d("Punto: " .. ((row.props or {}).name or ""), x, y, z + 1.2, c)
        elseif row.etype == "removal" then
            -- discreto: se desvanece con la distancia y el nombre solo sale de cerca o elegido
            local d = getDistanceBetweenPoints3D(MECam.x, MECam.y, MECam.z, x, y, z)
            if sel or d < 120 then
                local a = sel and 255 or math.floor(math.max(60, 220 - d * 1.5))
                local c = sel and tocolor(255, 200, 60) or tocolor(235, 70, 70, a)
                drawCross(x, y, z, sel and 1.2 or 0.7, c)
                if sel or d < 25 then label3d(MEEditor.label(row), x, y, z + 1.2, c) end
            end
        elseif sel or lock then
            local el = MEEditor.el(id)
            local c = lock and tocolor(235, 70, 70) or tocolor(245, 165, 36)
            if el and (row.etype == "object" or row.etype == "vehicle" or row.etype == "ped") then drawBox(el, c)
            else drawCircle(x, y, z, 0.8, c) end
            if lock then label3d(("Lo edita %s"):format(e.locks[tostring(id)]), x, y, z + 1.5, c)
            elseif row.etype == "marker" or row.etype == "pickup" then label3d(MEEditor.label(row), x, y, z + 1.4, c) end
        end
    end

    drawGizmo()

    -- fantasma
    local g = MEInput.ghost()
    if g and g.t then
        if isElement(g.el) and getElementType(g.el) ~= "marker" and getElementType(g.el) ~= "ped" then drawBox(g.el, tocolor(90, 230, 130)) end
        if g.etype == "point" then
            line(g.t.x, g.t.y, g.t.z - 1, g.t.x, g.t.y, g.t.z + 1, tocolor(90, 230, 130), 3)
        end
        label3d("Clic: colocar", g.t.x, g.t.y, g.t.z + 1.6, tocolor(200, 255, 215))
    end

    -- herramienta quitar
    local wh = MEInput.worldHit()
    if wh then
        drawCross(wh.hx, wh.hy, wh.hz, 0.6, tocolor(235, 70, 70))
        label3d(("Clic para quitar: %s (%d)"):format(engineGetModelNameFromID(wh.model) or "?", wh.model), wh.hx, wh.hy, wh.hz + 0.8,
            tocolor(255, 170, 170))
    end

    -- caja de selección
    local box = MEInput.box()
    if box then
        local cx, cy = getCursorPosition()
        if cx then
            local ax, ay = cx * screenW, cy * screenH
            local x, y = math.min(box.x, ax), math.min(box.y, ay)
            local w, h = math.abs(ax - box.x), math.abs(ay - box.y)
            if w + h > 6 then
                dxDrawRectangle(x, y, w, h, tocolor(245, 165, 36, 40))
                dxDrawRectangle(x, y, w, 1, tocolor(245, 165, 36, 220)) dxDrawRectangle(x, y + h, w, 1, tocolor(245, 165, 36, 220))
                dxDrawRectangle(x, y, 1, h, tocolor(245, 165, 36, 220)) dxDrawRectangle(x + w, y, 1, h, tocolor(245, 165, 36, 220))
            end
        end
    end

    if dim ~= MEEditor.draftDim() then
        text("Estás fuera del borrador", screenW / 2, 90, tocolor(255, 120, 120))
    end
    drawHints()
    drawTutorial()

    -- tooltip de la barra de iconos y de la columna de tipos
    local tip = MEEditor.tip
    if tip and tip ~= "" and MEUI.overUI() then
        local cx, cy = getCursorPosition()
        if cx then
            local tw = dxGetTextWidth(tip, 1, "default-bold") + 16
            local x, y = math.min(cx * screenW + 16, screenW - tw - 4), cy * screenH + 18
            dxDrawRectangle(x, y, tw, 22, tocolor(14, 18, 26, 235), true)
            dxDrawText(tip, x, y, x + tw, y + 22, tocolor(255, 255, 255), 1, "default-bold", "center", "center", false, false, true)
        end
    elseif tip and tip ~= "" then
        MEEditor.tip = ""
    end
end)

-- Retroceso dos veces seguidas omite el tutorial
local lastBack = 0
addEventHandler("onClientKey", root, function(button, press)
    if not press or button ~= "backspace" or not tut or MEUI.isTyping() then return end
    local now = getTickCount()
    if now - lastBack < 600 then MEEditor.ui("tutorialDone", {}) end
    lastBack = now
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, t in pairs(keyTex) do if t then destroyElement(t) end end
end)
