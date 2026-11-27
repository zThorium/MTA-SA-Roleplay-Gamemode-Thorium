--[[
    rp_admin / c_move.lua
    Editor para mover elementos del mundo (cajeros, expendedoras, maquinas, torniquetes, casas...)
    y menu de admin del cursor. Solo admins (nivel 1+); el servidor revalida y guarda (s_move.lua).

    Como se abre:
        ALT (vista de admin) + clic derecho      mueve lo que estas mirando
        M (cursor) + clic derecho sobre algo     menu: Mover · Copiar /goto · Borrar

    Editor (estilo Blender, simplificado):
        Flechas 3D roja X, verde Y, azul Z       arrastrarlas mueve en ese eje
        Anillo amarillo                          arrastrarlo a los lados gira
        Panel                                    - / + y arrastrar el numero a los lados
        Mayus                                    movimiento fino
        Mantener clic derecho                    mirar alrededor
        Enter guardar · Retroceso cancelar
    Mientras editas, lo editado se ve movido solo en tu juego; al guardar el servidor lo coloca
    para todos. Tu personaje queda congelado.
]]

local W, H = guiGetScreenSize()
local AXIS_LEN = 1.2
local RING_R = 0.9
local GRAB_PX = 14
local SCRUB_M, SCRUB_DEG = 0.02, 0.5        -- por pixel al arrastrar un numero
local ROT_PER_PX = 0.5                       -- grados por pixel al arrastrar el anillo
local STEP_M, STEP_DEG = 0.1, 5              -- botones - / +; con Mayus x0.1 y 1 grado
local FINE = 0.2
local MOVE_MAX = 60                          -- igual que s_move.lua (aviso antes de guardar)

local AXES = {
    { key = "x", color = { 235, 70, 70 },  dir = { 1, 0, 0 }, label = "X" },
    { key = "y", color = { 90, 210, 90 },  dir = { 0, 1, 0 }, label = "Y" },
    { key = "z", color = { 80, 140, 255 }, dir = { 0, 0, 1 }, label = "Z" },
}
local ROT_COLOR = { 255, 200, 60 }
local ACCENT = { 255, 126, 0 }

local ICONS = {
    enter = "images/tecla_enter.png", back = "images/tecla_retroceso.png", shift = "images/tecla_mayus.png",
    left = "images/raton_izq.png", right = "images/raton_der.png",
}

local edit   -- { entry, x, y, z, rot, orig, el, elOrig, groundOff, drag, hover, saving, froze, look }
local menu   -- { entry, x, y, confirm }
local hits = {}

local function now() return getTickCount() end
local function shift() return getKeyState("lshift") or getKeyState("rshift") end
local function notify(text, kind) exports.rp_notify:notify(text, kind or "info") end
local function inRect(px, py, r) return px >= r[1] and px <= r[1] + r[3] and py >= r[2] and py <= r[2] + r[4] end
local function cursorPx()
    local cx, cy = getCursorPosition()
    if not cx then return nil end
    return cx * W, cy * H
end

local function movable(e)
    return type(e) == "table" and (e.kind == "type" or e.kind == "house") and e.key and tonumber(e.id)
end

local function titleOf(e)
    return ("%s #%d"):format(e.typeName or "?", e.id or 0)
end

-- Distancia del punto al segmento (en pantalla)
local function segDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local qx, qy = ax + t * dx, ay + t * dy
    return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

local function groundAt(x, y, z)
    local g = getGroundPosition(x, y, z + 1.5)
    return (g and g ~= 0) and g or nil
end

----------------------------------------------------------------
-- Vista previa: mueve solo en tu juego el elemento principal
----------------------------------------------------------------
local function applyPreview()
    local e = edit
    if not e or not isElement(e.el) then return end
    local o, d = e.elOrig, math.rad(e.rot - e.orig.rot)
    local ox, oy = o.x - e.orig.x, o.y - e.orig.y
    local nx = e.x + ox * math.cos(d) - oy * math.sin(d)
    local ny = e.y + ox * math.sin(d) + oy * math.cos(d)
    setElementPosition(e.el, nx, ny, e.z + (o.z - e.orig.z))
    if e.entry.noRot then return end
    if e.isPed then
        -- Peds: el giro guardado es el de createPed; sin conformPedRotation MTA lo aplica invertido
        setElementRotation(e.el, 0, 0, e.rot, "default", true)
    else
        setElementRotation(e.el, o.rx, o.ry, o.rz + (e.rot - e.orig.rot))
    end
end

local function restorePreview()
    local e = edit
    if not e or not isElement(e.el) then return end
    local o = e.elOrig
    setElementPosition(e.el, o.x, o.y, o.z)
    if e.isPed then
        setElementRotation(e.el, 0, 0, e.orig.rot, "default", true)
    else
        setElementRotation(e.el, o.rx, o.ry, o.rz)
    end
end

local function setValue(axis, v)
    if axis == "rot" then edit.rot = v % 360 else edit[axis] = v end
    applyPreview()
end

----------------------------------------------------------------
-- Abrir / cerrar
----------------------------------------------------------------
local render, onCursorMove, onClick, onKey

local function closeEditor(restore)
    if not edit then return end
    if restore then restorePreview() end
    if edit.froze then setElementFrozen(localPlayer, false) end
    if not edit.look then showCursor(false) end
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientCursorMove", root, onCursorMove)
    removeEventHandler("onClientClick", root, onClick)
    removeEventHandler("onClientKey", root, onKey)
    edit = nil
end

function isMoveEditorOpen() return edit ~= nil end

function openMoveEditor(entry)
    if not movable(entry) then return end
    if edit then closeEditor(true) end
    menu = nil
    local el = isElement(entry.element) and entry.element or nil
    local elOrig
    if el then
        local x, y, z = getElementPosition(el)
        local rx, ry, rz = getElementRotation(el)
        elOrig = { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz }
    end
    local g = groundAt(entry.x, entry.y, entry.z)
    edit = {
        entry = entry, x = entry.x, y = entry.y, z = entry.z, rot = entry.rot or 0,
        orig = { x = entry.x, y = entry.y, z = entry.z, rot = entry.rot or 0 },
        el = el, elOrig = elOrig, groundOff = g and (entry.z - g) or 0,
        isPed = el and getElementType(el) == "ped" or false,
        froze = not isElementFrozen(localPlayer),
    }
    if edit.froze then setElementFrozen(localPlayer, true) end
    showCursor(true)
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientCursorMove", root, onCursorMove)
    addEventHandler("onClientClick", root, onClick)
    addEventHandler("onClientKey", root, onKey)
    playSoundFrontEnd(41)
end

local function save()
    if not edit or edit.saving then return end
    local o = edit.orig
    if getDistanceBetweenPoints3D(edit.x, edit.y, edit.z, o.x, o.y, o.z) > MOVE_MAX then
        return notify(("No se puede mover más de %d m de una vez."):format(MOVE_MAX), "warning")
    end
    edit.saving = now()
    triggerServerEvent("rp:admin:move:save", resourceRoot, edit.entry.key, edit.entry.id, edit.entry.part or false,
        edit.x, edit.y, edit.z, edit.rot)
end

addEvent("rp:admin:move:result", true)
addEventHandler("rp:admin:move:result", resourceRoot, function(ok, why)
    if not edit then return end
    if ok then
        playSoundFrontEnd(46)
        closeEditor(false)   -- el servidor ya lo volvio a crear en el sitio nuevo
    else
        edit.saving = nil
        playSoundFrontEnd(4)
        notify(tostring(why or "No se pudo mover."), "error")
    end
end)

----------------------------------------------------------------
-- Acciones del panel
----------------------------------------------------------------
local function snapGround()
    local g = groundAt(edit.x, edit.y, edit.z)
    if not g then return notify("No hay suelo debajo.", "warning") end
    setValue("z", g + edit.groundOff)
end

local function toMyFeet()
    local px, py, pz = getElementPosition(localPlayer)
    edit.x, edit.y = px, py
    setValue("z", (pz - 1) + edit.groundOff)
end

local function undo()
    edit.x, edit.y, edit.z, edit.rot = edit.orig.x, edit.orig.y, edit.orig.z, edit.orig.rot
    applyPreview()
end

local function stepValue(axis, sign)
    local step = axis == "rot" and (shift() and 1 or STEP_DEG) or (shift() and STEP_M * 0.1 or STEP_M)
    setValue(axis, edit[axis] + sign * step)
    playSoundFrontEnd(1)
end

----------------------------------------------------------------
-- Gizmo
----------------------------------------------------------------
local function axisScreen(a)
    local d = a.dir
    local sx0, sy0 = getScreenFromWorldPosition(edit.x, edit.y, edit.z, 0.2)
    local sx1, sy1 = getScreenFromWorldPosition(edit.x + d[1] * AXIS_LEN, edit.y + d[2] * AXIS_LEN, edit.z + d[3] * AXIS_LEN, 0.2)
    if not sx0 or not sx1 then return nil end
    return sx0, sy0, sx1, sy1
end

local function ringPoints()
    local pts = {}
    for i = 0, 40 do
        local a = (i / 40) * math.pi * 2
        pts[#pts + 1] = { edit.x + math.cos(a) * RING_R, edit.y + math.sin(a) * RING_R, edit.z }
    end
    return pts
end

-- Que asa hay bajo el raton: "x", "y", "z", "rot" o nil
local function handleAt(px, py)
    for _, a in ipairs(AXES) do
        local x0, y0, x1, y1 = axisScreen(a)
        if x0 and math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) > 12 and segDist(px, py, x0, y0, x1, y1) <= GRAB_PX then
            return a.key, x0, y0, x1, y1
        end
    end
    if not edit.entry.noRot then
        local prev
        for _, p in ipairs(ringPoints()) do
            local sx, sy = getScreenFromWorldPosition(p[1], p[2], p[3], 0.2)
            if sx and prev and segDist(px, py, prev[1], prev[2], sx, sy) <= GRAB_PX then return "rot" end
            prev = sx and { sx, sy } or nil
        end
    end
end

local function drawGizmo()
    local x, y, z = edit.x, edit.y, edit.z
    -- Donde estaba: punto gris y linea hasta donde va
    local o = edit.orig
    dxDrawLine3D(o.x, o.y, o.z, x, y, z, tocolor(160, 160, 160, 160), 1)
    dxDrawLine3D(o.x, o.y, o.z - 0.15, o.x, o.y, o.z + 0.15, tocolor(160, 160, 160, 200), 2)
    -- Ejes
    for _, a in ipairs(AXES) do
        local c, d = a.color, a.dir
        local hot = edit.hover == a.key or (edit.drag and edit.drag.axis == a.key)
        local alpha = hot and 255 or 210
        dxDrawLine3D(x, y, z, x + d[1] * AXIS_LEN, y + d[2] * AXIS_LEN, z + d[3] * AXIS_LEN,
            tocolor(c[1], c[2], c[3], alpha), hot and 6 or 4)
        local sx, sy = getScreenFromWorldPosition(x + d[1] * AXIS_LEN, y + d[2] * AXIS_LEN, z + d[3] * AXIS_LEN, 0.2)
        if sx then
            dxDrawCircle(sx, sy, hot and 11 or 9, 0, 360, tocolor(c[1], c[2], c[3], alpha), tocolor(c[1], c[2], c[3], alpha))
            dxDrawText(a.label, sx - 10, sy - 10, sx + 10, sy + 10, tocolor(0, 0, 0, 255), 1, "default-bold", "center", "center")
        end
    end
    -- Anillo de giro
    if not edit.entry.noRot then
        local hot = edit.hover == "rot" or (edit.drag and edit.drag.axis == "rot")
        local pts, c = ringPoints(), ROT_COLOR
        for i = 2, #pts do
            local p, q = pts[i - 1], pts[i]
            dxDrawLine3D(p[1], p[2], p[3], q[1], q[2], q[3], tocolor(c[1], c[2], c[3], hot and 255 or 170), hot and 4 or 2)
        end
        -- Marca hacia donde mira
        local a = math.rad(edit.rot + 90)
        dxDrawLine3D(x, y, z, x + math.cos(a) * RING_R, y + math.sin(a) * RING_R, z, tocolor(c[1], c[2], c[3], 220), 2)
    end
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0.2)
    if sx then dxDrawCircle(sx, sy, 5, 0, 360, tocolor(255, 255, 255, 230), tocolor(255, 255, 255, 230)) end
end

----------------------------------------------------------------
-- Panel
----------------------------------------------------------------
local function button(x, y, w, h, text, action, color, hint)
    local cx, cy = cursorPx()
    local hot = cx and inRect(cx, cy, { x, y, w, h })
    local c = color or { 60, 60, 66 }
    local k = hot and 1.25 or 1
    dxDrawRectangle(x, y, w, h, tocolor(math.min(255, c[1] * k), math.min(255, c[2] * k), math.min(255, c[3] * k), 235))
    dxDrawText(text, x, y, x + w, y + h, tocolor(255, 255, 255, 255), 1, "default-bold", "center", "center")
    hits[#hits + 1] = { x, y, w, h, action = action }
    if hot and hint then edit.hint = hint end
end

local function drawPanel()
    local pw, x0 = 300, W - 330
    local rows = edit.entry.noRot and 3 or 4
    local ph = 118 + rows * 38 + 120
    local y0 = math.floor(H / 2 - ph / 2)
    edit.hint = nil
    dxDrawRectangle(x0, y0, pw, ph, tocolor(15, 15, 18, 225))
    dxDrawRectangle(x0, y0, pw, 4, tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 255))
    dxDrawText("Mover " .. titleOf(edit.entry), x0 + 14, y0 + 12, x0 + pw, y0 + 32, tocolor(255, 255, 255, 255), 1.15, "default-bold")
    dxDrawText(edit.entry.label or "", x0 + 14, y0 + 34, x0 + pw - 10, y0 + 50, tocolor(190, 190, 190, 255), 1, "default", "left", "top", true)

    local list = {
        { key = "x", label = "X", color = AXES[1].color, fmt = "%.2f" },
        { key = "y", label = "Y", color = AXES[2].color, fmt = "%.2f" },
        { key = "z", label = "Z", color = AXES[3].color, fmt = "%.2f" },
    }
    if not edit.entry.noRot then list[4] = { key = "rot", label = "Giro", color = ROT_COLOR, fmt = "%.1f°" } end
    local y = y0 + 60
    for _, r in ipairs(list) do
        local c = r.color
        dxDrawRectangle(x0 + 14, y, 4, 30, tocolor(c[1], c[2], c[3], 255))
        dxDrawText(r.label, x0 + 24, y, x0 + 70, y + 30, tocolor(c[1], c[2], c[3], 255), 1.1, "default-bold", "left", "center")
        button(x0 + 72, y, 30, 30, "-", { step = r.key, sign = -1 }, nil, "Restar (Mayús = fino)")
        -- Campo arrastrable (Blender): clic y arrastra a los lados
        local fx, fw = x0 + 106, pw - 106 - 50
        local cx, cy = cursorPx()
        local hot = (cx and inRect(cx, cy, { fx, y, fw, 30 })) or (edit.drag and edit.drag.scrub == r.key)
        dxDrawRectangle(fx, y, fw, 30, tocolor(35, 35, 40, 255))
        if hot then dxDrawRectangle(fx, y + 28, fw, 2, tocolor(c[1], c[2], c[3], 255)) end
        dxDrawText(("<  " .. r.fmt .. "  >"):format(edit[r.key]), fx, y, fx + fw, y + 30, tocolor(255, 255, 255, 255), 1, "default-bold", "center", "center")
        hits[#hits + 1] = { fx, y, fw, 30, action = { scrub = r.key } }
        if hot then edit.hint = "Arrastra a los lados para cambiarlo" end
        button(x0 + pw - 44, y, 30, 30, "+", { step = r.key, sign = 1 }, nil, "Sumar (Mayús = fino)")
        y = y + 38
    end

    local moved = getDistanceBetweenPoints3D(edit.x, edit.y, edit.z, edit.orig.x, edit.orig.y, edit.orig.z)
    dxDrawText(("Movido %.2f m%s"):format(moved, moved > MOVE_MAX and ("  ·  máximo " .. MOVE_MAX .. " m") or ""),
        x0 + 14, y, x0 + pw, y + 18, moved > MOVE_MAX and tocolor(255, 90, 90, 255) or tocolor(170, 170, 170, 255), 1, "default")
    y = y + 22
    local bw = (pw - 28 - 16) / 3
    button(x0 + 14, y, bw, 30, "Al suelo", "ground", nil, "Lo apoya en el suelo de debajo (misma altura sobre el suelo)")
    button(x0 + 14 + bw + 8, y, bw, 30, "A mis pies", "feet", nil, "Lo trae a donde estás tú")
    button(x0 + 14 + (bw + 8) * 2, y, bw, 30, "Deshacer", "undo", nil, "Vuelve a la posición original")
    y = y + 38
    local hw = (pw - 28 - 8) / 2
    button(x0 + 14, y, hw, 34, edit.saving and "Guardando..." or "Guardar", "save", { 40, 140, 70 })
    button(x0 + 14 + hw + 8, y, hw, 34, "Cancelar", "cancel", { 120, 45, 45 })
    dxDrawImage(x0 + 14 + hw - 30, y + 3, 28, 28, ICONS.enter)
    dxDrawImage(x0 + pw - 14 - 30, y + 3, 28, 28, ICONS.back)
    y = y + 44
    -- Ayuda con las teclas y botones dibujados (UX-01)
    dxDrawImage(x0 + 14, y, 24, 24, ICONS.left)
    dxDrawText(edit.hint or "Arrastra las flechas o los números", x0 + 42, y, x0 + pw - 10, y + 24, tocolor(220, 220, 220, 255), 1, "default", "left", "center", true)
    dxDrawImage(x0 + 14, y + 26, 24, 24, ICONS.right)
    dxDrawText("Mantén para mirar alrededor", x0 + 42, y + 26, x0 + pw, y + 50, tocolor(220, 220, 220, 255), 1, "default", "left", "center")
    dxDrawImage(x0 + 160, y + 26, 24, 24, ICONS.shift)
    dxDrawText("fino", x0 + 188, y + 26, x0 + pw, y + 50, tocolor(220, 220, 220, 255), 1, "default", "left", "center")
    edit.panel = { x0, y0, pw, ph }
end

function render()
    if not edit then return end
    if edit.saving and now() - edit.saving > 6000 then edit.saving = nil end
    hits = {}
    drawGizmo()
    drawPanel()
end

----------------------------------------------------------------
-- Raton y teclado
----------------------------------------------------------------
function onCursorMove(_, _, ax, ay)
    if not edit then return end
    local d = edit.drag
    if not d then
        local inPanel = edit.panel and inRect(ax, ay, edit.panel)
        edit.hover = not inPanel and handleAt(ax, ay) or nil
        return
    end
    local fine = shift() and FINE or 1
    if d.scrub then
        local per = d.scrub == "rot" and SCRUB_DEG or SCRUB_M
        setValue(d.scrub, d.start + (ax - d.mx) * per * fine)
    elseif d.axis == "rot" then
        setValue("rot", d.start + (ax - d.mx) * ROT_PER_PX * fine)
    else
        local delta = ((ax - d.mx) * d.dx + (ay - d.my) * d.dy) / d.pxPerM
        setValue(d.axis, d.start + delta * fine)
    end
end

function onClick(button, state, ax, ay)
    if not edit then return end
    if button == "right" then
        -- Mantener clic derecho: esconder el cursor para mirar alrededor
        if state == "down" and not edit.drag then
            edit.look = true
            showCursor(false)
        end
        return
    end
    if button ~= "left" then return end
    if state == "up" then
        if edit.drag then edit.drag = nil playSoundFrontEnd(1) end
        return
    end
    for i = #hits, 1, -1 do
        local h = hits[i]
        if inRect(ax, ay, h) then
            local a = h.action
            if type(a) == "table" and a.step then return stepValue(a.step, a.sign) end
            if type(a) == "table" and a.scrub then
                edit.drag = { scrub = a.scrub, start = edit[a.scrub], mx = ax }
                return
            end
            if a == "save" then return save() end
            if a == "cancel" then return closeEditor(true) end
            if a == "ground" then return snapGround() end
            if a == "feet" then return toMyFeet() end
            if a == "undo" then return undo() end
            return
        end
    end
    if edit.panel and inRect(ax, ay, edit.panel) then return end
    local axis, x0, y0, x1, y1 = handleAt(ax, ay)
    if not axis then return end
    if axis == "rot" then
        edit.drag = { axis = "rot", start = edit.rot, mx = ax }
    else
        local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        edit.drag = { axis = axis, start = edit[axis], mx = ax, my = ay,
            dx = (x1 - x0) / len, dy = (y1 - y0) / len, pxPerM = len / AXIS_LEN }
    end
    playSoundFrontEnd(1)
end

function onKey(key, press)
    if not edit then return end
    if key == "mouse2" and not press and edit.look then
        edit.look = false
        showCursor(true)
        return
    end
    if not press or isChatBoxInputActive() or isConsoleActive() then return end
    if key == "enter" or key == "num_enter" then
        cancelEvent()
        save()
    elseif key == "backspace" then
        cancelEvent()
        closeEditor(true)
    end
end

----------------------------------------------------------------
-- Menu de admin del cursor (M + clic derecho sobre algo)
----------------------------------------------------------------
local function cursorModeActive()
    local res = getResourceFromName("rp_vehicles")
    if not res or getResourceState(res) ~= "running" then return isCursorShowing() end
    local ok, on = pcall(function() return exports.rp_vehicles:isCursorModeActive() end)
    return ok and on
end

local function drawMenu()
    if not menu then return end
    local e = menu.entry
    local items = {
        { id = "move", text = "Mover" },
        { id = "copy", text = ("Copiar /goto%s %d"):format(e.key, e.id) },
        { id = "delete", text = menu.confirm and "¿Seguro? Clic para borrar" or "Borrar", danger = true },
    }
    local w, rh = 230, 30
    local x, y = math.min(menu.x, W - w - 10), math.min(menu.y, H - (#items * rh + 36) - 10)
    dxDrawRectangle(x, y, w, #items * rh + 34, tocolor(15, 15, 18, 235))
    dxDrawRectangle(x, y, w, 3, tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 255))
    dxDrawText(titleOf(e), x + 10, y + 6, x + w, y + 28, tocolor(ACCENT[1], ACCENT[2], ACCENT[3], 255), 1, "default-bold", "left", "center")
    menu.rects = {}
    local cx, cy = cursorPx()
    for i, it in ipairs(items) do
        local r = { x + 4, y + 30 + (i - 1) * rh, w - 8, rh - 2 }
        local hot = cx and inRect(cx, cy, r)
        local bg = it.danger and (menu.confirm and { 150, 40, 40 } or { 70, 35, 35 }) or { 40, 40, 46 }
        dxDrawRectangle(r[1], r[2], r[3], r[4], tocolor(bg[1] * (hot and 1.4 or 1), bg[2] * (hot and 1.4 or 1), bg[3] * (hot and 1.4 or 1), 240))
        dxDrawText(it.text, r[1] + 10, r[2], r[1] + r[3], r[2] + r[4], tocolor(255, 255, 255, 255), 1, "default-bold", "left", "center")
        menu.rects[#menu.rects + 1] = { r = r, id = it.id }
    end
end

local function closeMenu()
    if not menu then return end
    menu = nil
    removeEventHandler("onClientRender", root, drawMenu)
end

local function openMenu(entry, x, y)
    closeMenu()
    menu = { entry = entry, x = x, y = y }
    addEventHandler("onClientRender", root, drawMenu)
    playSoundFrontEnd(41)
end

local pending   -- { x, y, at, clicked }

addEventHandler("onClientClick", root, function(button, state, ax, ay, _, _, _, clicked)
    if edit or state ~= "down" then return end
    -- Clic sobre el menu abierto
    if menu then
        if button == "left" then
            for _, it in ipairs(menu.rects or {}) do
                if inRect(ax, ay, it.r) then
                    local e = menu.entry
                    if it.id == "move" then
                        closeMenu()
                        return openMoveEditor(e)
                    elseif it.id == "copy" then
                        setClipboard(("/goto%s %d"):format(e.key, e.id))
                        notify("Comando copiado al portapapeles.", "success")
                        return closeMenu()
                    elseif it.id == "delete" then
                        if not menu.confirm then menu.confirm = true return end
                        triggerServerEvent("rp:admin:world:delete", resourceRoot, e.key, e.id)
                        return closeMenu()
                    end
                end
            end
        end
        closeMenu()
        if button == "left" then return end
    end
    if button ~= "right" or not isInspectEnabled or not isInspectEnabled() or not cursorModeActive() then return end
    if isElement(clicked) then
        local et = getElementType(clicked)
        if et == "vehicle" or et == "player" then return end   -- esos menus son de rp_vehicles y rp_interact
    end
    pending = { x = ax, y = ay, at = now(), clicked = clicked }
    triggerServerEvent("rp:admin:inspect:request", resourceRoot, true)
end)

-- Llegan los datos del entorno: se elige lo mas cercano al clic en pantalla
InspectPick = function(list)
    local p = pending
    pending = nil
    if not p or now() - p.at > 3000 or edit then return end
    local best, bestD = nil, 70
    for _, e in ipairs(list) do
        if movable(e) then
            if isElement(p.clicked) and e.element == p.clicked then best = e break end
            local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 0.5, 0.05)
            if sx then
                local d = math.sqrt((sx - p.x) ^ 2 + (sy - p.y) ^ 2)
                if d < bestD then best, bestD = e, d end
            end
        end
    end
    if best then openMenu(best, p.x, p.y) end
end

addEventHandler("onClientKey", root, function(key, press)
    if menu and press and key == "backspace" then cancelEvent() closeMenu() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeMenu()
    closeEditor(true)
end)
addEventHandler("onClientPlayerWasted", localPlayer, function() closeMenu() closeEditor(true) end)
