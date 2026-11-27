--[[
    rp_mapeditor / c_input.lua
    Entrada del editor: fantasma para colocar, elegir con clic o caja, gizmo (mover / girar / escalar,
    ejes del mundo o locales), arrastrar sobre el suelo, herramienta «quitar del mapa» y atajos.

        Clic izq.            elegir / colocar / arrastrar      Mayús+clic   añadir a la selección
        Arrastrar en vacío   caja de selección                 Clic der.    mirar (mantener)
        1 2 3                mover / girar / escalar           L            ejes locales o del mundo
        G                    rejilla sí/no                     R            girar 90° en Z (Mayús: al revés)
        Rueda                gira el fantasma; si no hay, velocidad de la cámara
        Re Pág / Av Pág      subir / bajar la selección        Supr         borrar
        Ctrl+Z / Ctrl+Y      deshacer / rehacer                Ctrl+C / Ctrl+V / Ctrl+D   copiar, pegar, duplicar
        F                    modo prueba                       H            ocultar paneles
        Retroceso / Esc      soltar el fantasma o la selección
    Mayús mientras arrastras = sin rejilla. Ctrl en modo escalar = escala uniforme.
]]

MEInput = {}

local screenW, screenH = guiGetScreenSize()
local AXES = { x = { 1, 0, 0 }, y = { 0, 1, 0 }, z = { 0, 0, 1 } }
local AXCOL = { x = { 235, 64, 64 }, y = { 88, 206, 96 }, z = { 70, 132, 245 } }
local RING_BASIS = { x = { { 0, 1, 0 }, { 0, 0, 1 } }, y = { { 0, 0, 1 }, { 1, 0, 0 } }, z = { { 1, 0, 0 }, { 0, 1, 0 } } }
MEInput.AXCOL = AXCOL

local mouseDown = nil     -- { x, y, kind = "gizmo"|"drag"|"box"|"click", id }

local function E() return MEEditor.E end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function snap(v, g) if g and g > 0 then return math.floor(v / g + 0.5) * g end return v end
local function shift() return getKeyState("lshift") or getKeyState("rshift") end
local function ctrl() return getKeyState("lctrl") or getKeyState("rctrl") end
local function gridNow() local e = E() if shift() or not e.gridOn then return 0 end return e.grid end
local function norm(a, b, c) local l = math.sqrt(a * a + b * b + c * c) if l == 0 then return 0, 0, 1 end return a / l, b / l, c / l end

local function cursorPx()
    local cx, cy = getCursorPosition()
    if not cx then return end
    return cx * screenW, cy * screenH
end

local function cursorRay(len)
    local mx, my = cursorPx()
    if not mx then return end
    local fx, fy, fz = getWorldFromScreenPosition(mx, my, len or 600)
    if not fx then return end
    return MECam.x, MECam.y, MECam.z, fx, fy, fz
end

local function segDist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local l2 = vx * vx + vy * vy
    local t = l2 > 0 and clamp(((px - ax) * vx + (py - ay) * vy) / l2, 0, 1) or 0
    local qx, qy = ax + vx * t, ay + vy * t
    return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

----------------------------------------------------------------
-- Fantasma (lo que vas a colocar)
----------------------------------------------------------------
local ghost = nil   -- { etype, model, props, el, rz, t = {x,y,z}, valid }

local PICKUP_MODELS = { [0] = 1240, [1] = 1242, [2] = 1239 }

local function destroyGhost()
    if ghost and isElement(ghost.el) then destroyElement(ghost.el) end
    ghost = nil
end

function MEInput.setGhost(etype, model, props)
    destroyGhost()
    local e = E()
    if not etype then return end
    e.tool = "place"
    ghost = { etype = etype, model = model, props = props or {}, rz = 0 }
    local el
    if etype == "object" then el = createObject(model, 0, 0, -50)
    elseif etype == "vehicle" then el = createVehicle(model, 0, 0, -50)
    elseif etype == "ped" then el = createPed(model, 0, 0, -50)
    elseif etype == "marker" then
        local c = props.color or { 255, 200, 60, 160 }
        el = createMarker(0, 0, -50, props.mtype or "cylinder", props.size or 1.5, c[1], c[2], c[3], c[4])
    elseif etype == "pickup" then
        local m = props.ptype == 3 and tonumber(props.amount) or PICKUP_MODELS[props.ptype or 0] or 1239
        el = createObject(m, 0, 0, -50)
    end
    if el then
        ghost.el = el
        setElementDimension(el, getElementDimension(localPlayer))
        setElementInterior(el, getElementInterior(localPlayer))
        if getElementType(el) ~= "marker" then
            setElementAlpha(el, 170)
            setElementCollisionsEnabled(el, false)
            setElementFrozen(el, true)
        end
    end
    MEEditor.pushState()
    MEEditor.sound("click_002")
end

function MEInput.ghost() return ghost end

local function groundOffset()
    if not ghost or not isElement(ghost.el) then return ghost and ghost.etype == "ped" and 1 or 0 end
    local t = getElementType(ghost.el)
    if t == "ped" then return 1 end
    if t == "marker" then return 0 end
    local _, _, z1 = getElementBoundingBox(ghost.el)
    return -(z1 or 0)
end

-- Punto del mundo bajo el cursor (edificios, objetos y vehículos), sin contar el fantasma
local function surfaceHit()
    local x1, y1, z1, x2, y2, z2 = cursorRay(800)
    if not x1 then return end
    local hit, hx, hy, hz, el = processLineOfSight(x1, y1, z1, x2, y2, z2, true, true, false, true, false, false,
        false, false, ghost and ghost.el or nil)
    if hit then return hx, hy, hz, el end
    -- sin impacto: plano a la altura actual del suelo de la cámara
    local d = 40
    return x1 + (x2 - x1) / 800 * d, y1 + (y2 - y1) / 800 * d, z1 + (z2 - z1) / 800 * d
end

function MEInput.cursorGround()
    local x, y, z = surfaceHit()
    return x, y, z
end

local function updateGhost()
    if not ghost or MEUI.overUI() then
        if ghost and isElement(ghost.el) then setElementPosition(ghost.el, 0, 0, -50) end
        if ghost then ghost.t = nil end
        return
    end
    local x, y, z = surfaceHit()
    if not x then return end
    local g = gridNow()
    x, y = snap(x, g), snap(y, g)
    z = z + groundOffset()
    ghost.t = { x = x, y = y, z = z }
    if isElement(ghost.el) then
        setElementPosition(ghost.el, x, y, z)
        if getElementType(ghost.el) == "ped" then setElementRotation(ghost.el, 0, 0, ghost.rz, "default", true)
        elseif getElementType(ghost.el) ~= "marker" then setElementRotation(ghost.el, 0, 0, ghost.rz) end
    end
end

local function placeGhost()
    if not ghost or not ghost.t then return end
    local row = { etype = ghost.etype, model = ghost.model, x = ghost.t.x, y = ghost.t.y, z = ghost.t.z,
                  rx = 0, ry = 0, rz = ghost.rz, props = MEEditor.copy(ghost.props) }
    MEEditor.createRows({ row }, not shift())
    if METutorial then METutorial.event("place") end
end

----------------------------------------------------------------
-- Herramienta «quitar del mapa»
----------------------------------------------------------------
local worldHit = nil

local function updateWorldHit()
    worldHit = nil
    local e = E()
    if e.tool ~= "remove" or MEUI.overUI() then return end
    local x1, y1, z1, x2, y2, z2 = cursorRay(800)
    if not x1 then return end
    local r = { processLineOfSight(x1, y1, z1, x2, y2, z2, true, false, false, true, true, false, false, false, nil, true) }
    -- r[12] modelo, r[13..15] posición, r[16..18] giro, r[19] LOD
    if r[1] and not r[5] and r[12] then
        worldHit = { model = r[12], x = r[13], y = r[14], z = r[15], lod = r[19] or 0, hx = r[2], hy = r[3], hz = r[4] }
    end
end

function MEInput.worldHit() return worldHit end

local function removeWorldHit()
    if not worldHit then return end
    local row = { etype = "removal", model = worldHit.model, x = worldHit.x, y = worldHit.y, z = worldHit.z,
                  rx = 0, ry = 0, rz = 0, props = { radius = 1, lod = worldHit.lod or 0 } }
    MEEditor.createRows({ row }, false)
    worldHit = nil
end

----------------------------------------------------------------
-- Elegir con el ratón
----------------------------------------------------------------
local function pickAt(mx, my)
    local e = E()
    local x1, y1, z1, x2, y2, z2 = cursorRay(800)
    if x1 then
        local hit, _, _, _, el = processLineOfSight(x1, y1, z1, x2, y2, z2, false, true, false, true, false, false,
            false, false, ghost and ghost.el or nil)
        local id = hit and isElement(el) and getElementData(el, "rp:me:id")
        if id and e.rows[id] then return id end
    end
    -- apoyo por pantalla: marcadores, pickups, puntos, quitados y objetos sin colisión
    local best, bestD = nil, 24
    for id in pairs(e.rows) do
        local x, y, z = MEEditor.posOf(id)
        local sx, sy = getScreenFromWorldPosition(x, y, z + 0.3)
        if sx then
            local d = math.sqrt((sx - mx) ^ 2 + (sy - my) ^ 2)
            if d < bestD then best, bestD = id, d end
        end
    end
    return best
end

----------------------------------------------------------------
-- Gizmo
----------------------------------------------------------------
local gdrag = nil      -- { mode, axis, items, ox, oy, oz, L, vec, t0 | a0, moved, info }
local hover = nil

function MEInput.gizmoOrigin()
    local e = E()
    local ids = MEEditor.selectedIds()
    if #ids == 0 or e.tool ~= "select" then return end
    local x, y, z, n = 0, 0, 0, 0
    for _, id in ipairs(ids) do
        local px, py, pz = MEEditor.posOf(id)
        if px then x, y, z, n = x + px, y + py, z + pz, n + 1 end
    end
    if n == 0 then return end
    return x / n, y / n, z / n
end

function MEInput.gizmoLen(ox, oy, oz)
    local d = getDistanceBetweenPoints3D(MECam.x, MECam.y, MECam.z, ox, oy, oz)
    return clamp(d * 0.13, 0.6, 12)
end

-- Ejes que muestra el gizmo: del mundo, o los del primer elemento (escalar siempre es local)
function MEInput.axisVectors()
    local e = E()
    local ids = MEEditor.selectedIds()
    if (e.localAxes or e.gizmo == "scale") and e.gizmo ~= "rotate" and ids[1] then
        local el = MEEditor.el(ids[1])
        local m = el and getElementMatrix(el)
        if m then
            local x1, y1, z1 = norm(m[1][1], m[1][2], m[1][3])
            local x2, y2, z2 = norm(m[2][1], m[2][2], m[2][3])
            local x3, y3, z3 = norm(m[3][1], m[3][2], m[3][3])
            return { x = { x1, y1, z1 }, y = { x2, y2, z2 }, z = { x3, y3, z3 } }
        end
    end
    return AXES
end

function MEInput.ringPoint(ox, oy, oz, axis, ang, r)
    local b = RING_BASIS[axis]
    local c, s = math.cos(ang) * r, math.sin(ang) * r
    return ox + b[1][1] * c + b[2][1] * s, oy + b[1][2] * c + b[2][2] * s, oz + b[1][3] * c + b[2][3] * s
end

local function axisParam(ox, oy, oz, a)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local dx, dy, dz = norm(x2 - x1, y2 - y1, z2 - z1)
    local b = dx * a[1] + dy * a[2] + dz * a[3]
    local denom = 1 - b * b
    if denom < 1e-4 then return end
    local wx, wy, wz = x1 - ox, y1 - oy, z1 - oz
    local d_ = dx * wx + dy * wy + dz * wz
    local e_ = a[1] * wx + a[2] * wy + a[3] * wz
    return (e_ - b * d_) / denom
end

local function ringAngle(ox, oy, oz, axis)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local n = AXES[axis]
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local denom = dx * n[1] + dy * n[2] + dz * n[3]
    if math.abs(denom) < 1e-6 then return end
    local s = ((ox - x1) * n[1] + (oy - y1) * n[2] + (oz - z1) * n[3]) / denom
    local hx, hy, hz = x1 + dx * s - ox, y1 + dy * s - oy, z1 + dz * s - oz
    local b = RING_BASIS[axis]
    local u = hx * b[1][1] + hy * b[1][2] + hz * b[1][3]
    local v = hx * b[2][1] + hy * b[2][2] + hz * b[2][3]
    return math.deg(math.atan2(v, u))
end

local function hoverGizmo()
    hover = nil
    local e = E()
    if gdrag or ghost or mouseDown or MECam.looking or MEUI.overUI() then return end
    local ox, oy, oz = MEInput.gizmoOrigin()
    if not ox then return end
    local mx, my = cursorPx()
    if not mx then return end
    local L = MEInput.gizmoLen(ox, oy, oz)
    local vecs = MEInput.axisVectors()
    local best, bestD = nil, 14
    local sx0, sy0 = getScreenFromWorldPosition(ox, oy, oz)
    for axis in pairs(AXES) do
        local d
        if e.gizmo == "rotate" then
            local px, py
            for i = 0, 40 do
                local wx, wy, wz = MEInput.ringPoint(ox, oy, oz, axis, i / 40 * math.pi * 2, L * 0.85)
                local sx, sy = getScreenFromWorldPosition(wx, wy, wz)
                if sx and px then
                    local dd = segDist(mx, my, px, py, sx, sy)
                    if not d or dd < d then d = dd end
                end
                px, py = sx, sy
            end
        else
            local a = vecs[axis]
            local sx1, sy1 = getScreenFromWorldPosition(ox + a[1] * L, oy + a[2] * L, oz + a[3] * L)
            if sx0 and sx1 then d = segDist(mx, my, sx0, sy0, sx1, sy1) end
        end
        if d and d < bestD then best, bestD = axis, d end
    end
    hover = best
end

function MEInput.hover() return hover end
function MEInput.drag() return gdrag end

local function selectionItems()
    local e = E()
    local items = {}
    for _, id in ipairs(MEEditor.selectedIds()) do
        local row = e.rows[id]
        if row then
            local t = MEEditor.T(row)
            items[#items + 1] = { id = id, row = row, before = t, after = MEEditor.copy(t) }
        end
    end
    return items
end

local function startGizmoDrag(axis)
    local e = E()
    local items = selectionItems()
    if #items == 0 then return false end
    local ox, oy, oz = MEInput.gizmoOrigin()
    local vec = MEInput.axisVectors()[axis]
    local g = { mode = e.gizmo, axis = axis, items = items, ox = ox, oy = oy, oz = oz, L = MEInput.gizmoLen(ox, oy, oz),
                vec = vec, moved = false }
    if e.gizmo == "rotate" then g.a0 = ringAngle(ox, oy, oz, axis) else g.t0 = axisParam(ox, oy, oz, vec) end
    if not (g.a0 or g.t0) then return false end
    gdrag = g
    return true
end

local function updateGizmoDrag()
    local g = gdrag
    if not g or g.mode == "plane" then return end
    local e = E()
    local grid = gridNow()
    if g.mode == "move" then
        local t = axisParam(g.ox, g.oy, g.oz, g.vec)
        if not t then return end
        local delta = t - g.t0
        if grid > 0 then delta = snap(delta, grid) end
        for _, it in ipairs(g.items) do
            local a, b = it.after, it.before
            a.x, a.y, a.z = b.x + g.vec[1] * delta, b.y + g.vec[2] * delta, b.z + g.vec[3] * delta
            MEEditor.applyLocal(it.id, a)
        end
        g.info = ("Mover %s: %+.2f m"):format(g.axis:upper(), delta)
        g.moved = g.moved or math.abs(delta) > 0.001
    elseif g.mode == "scale" then
        local t = axisParam(g.ox, g.oy, g.oz, g.vec)
        if not t then return end
        local f = clamp(1 + (t - g.t0) / g.L, 0.05, 20)
        if grid > 0 then f = math.max(0.05, snap(f, 0.05)) end
        local uniform = ctrl()
        for _, it in ipairs(g.items) do
            if it.row.etype == "object" then
                local a, b = it.after, it.before
                if uniform then
                    a.sx = clamp(b.sx * f, MAPEDIT.SCALE_MIN, MAPEDIT.SCALE_MAX)
                    a.sy = clamp(b.sy * f, MAPEDIT.SCALE_MIN, MAPEDIT.SCALE_MAX)
                    a.sz = clamp(b.sz * f, MAPEDIT.SCALE_MIN, MAPEDIT.SCALE_MAX)
                else
                    local k = "s" .. g.axis
                    a[k] = clamp(b[k] * f, MAPEDIT.SCALE_MIN, MAPEDIT.SCALE_MAX)
                end
                MEEditor.applyLocal(it.id, a)
            end
        end
        g.info = ("Escalar %s: x%.2f"):format(uniform and "todo" or g.axis:upper(), f)
        g.moved = g.moved or math.abs(f - 1) > 0.001
    else
        local ang = ringAngle(g.ox, g.oy, g.oz, g.axis)
        if not ang then return end
        local delta = ang - g.a0
        if e.rotStep > 0 and not shift() then delta = snap(delta, e.rotStep) end
        local rad = math.rad(delta)
        local c, s = math.cos(rad), math.sin(rad)
        for _, it in ipairs(g.items) do
            local a, b = it.after, it.before
            a.x, a.y, a.z = b.x, b.y, b.z
            a["r" .. g.axis] = (b["r" .. g.axis] + delta) % 360
            if g.axis == "z" and #g.items > 1 then
                local px, py = b.x - g.ox, b.y - g.oy
                a.x, a.y = g.ox + px * c - py * s, g.oy + px * s + py * c
            end
            MEEditor.applyLocal(it.id, a)
        end
        g.info = ("Girar %s: %+d°"):format(g.axis:upper(), math.floor(delta + 0.5))
        g.moved = g.moved or math.abs(delta) > 0.1
    end
end

-- Arrastrar lo elegido sobre el plano horizontal (clic sobre el propio elemento)
local function startPlaneDrag()
    local items = selectionItems()
    if #items == 0 then return false end
    local ox, oy, oz = MEInput.gizmoOrigin()
    gdrag = { mode = "plane", items = items, ox = ox, oy = oy, oz = oz, moved = false }
    return true
end

local function planePoint(z)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 or math.abs(z2 - z1) < 1e-4 then return end
    local t = (z - z1) / (z2 - z1)
    if t <= 0 then return end
    return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
end

local function updatePlaneDrag()
    local g = gdrag
    if not g or g.mode ~= "plane" then return end
    local px, py = planePoint(g.oz)
    if not px then return end
    if not g.p0 then g.p0 = { px, py } return end
    local dx, dy = px - g.p0[1], py - g.p0[2]
    local grid = gridNow()
    if grid > 0 then dx, dy = snap(dx, grid), snap(dy, grid) end
    for _, it in ipairs(g.items) do
        it.after.x, it.after.y = it.before.x + dx, it.before.y + dy
        MEEditor.applyLocal(it.id, it.after)
    end
    g.info = ("Mover: %+.2f, %+.2f m"):format(dx, dy)
    g.moved = g.moved or math.abs(dx) + math.abs(dy) > 0.001
end

local function endDrag()
    local g = gdrag
    gdrag = nil
    if not g then return end
    if g.moved then
        MEEditor.commitTransforms(g.items)
        MEEditor.sound("drop_00" .. math.random(1, 3))
        if METutorial then METutorial.event("move") end
    else
        for _, it in ipairs(g.items) do MEEditor.applyLocal(it.id, it.before) E().preview[it.id] = nil end
    end
end

-- Mueve la selección un paso (teclas)
local function nudge(dx, dy, dz, drz)
    local items = selectionItems()
    if #items == 0 then return end
    for _, it in ipairs(items) do
        local a = it.after
        a.x, a.y, a.z, a.rz = a.x + dx, a.y + dy, a.z + dz, (a.rz + (drz or 0)) % 360
        MEEditor.applyLocal(it.id, a)
    end
    MEEditor.commitTransforms(items)
end

----------------------------------------------------------------
-- Caja de selección
----------------------------------------------------------------
local function boxSelect(x1, y1, x2, y2, additive)
    local e = E()
    local ax, bx, ay, by = math.min(x1, x2), math.max(x1, x2), math.min(y1, y2), math.max(y1, y2)
    local ids = {}
    for id in pairs(e.rows) do
        local x, y, z = MEEditor.posOf(id)
        local sx, sy = getScreenFromWorldPosition(x, y, z)
        if sx and sx >= ax and sx <= bx and sy >= ay and sy <= by then ids[#ids + 1] = id end
    end
    MEEditor.selectMany(ids, additive)
end

function MEInput.box() return mouseDown and mouseDown.kind == "box" and mouseDown or nil end

-- Doble clic sobre el mismo elemento (< 350 ms) abre sus propiedades
local lastClick = { id = nil, tick = 0 }
local function doubleClick(id)
    local now = getTickCount()
    local isDouble = lastClick.id == id and now - lastClick.tick < 350
    lastClick.id, lastClick.tick = id, now
    if isDouble then
        lastClick.id = nil
        if not E().sel[id] then MEEditor.select(id, false) end
        MEEditor.openProps()
        return true
    end
    return false
end

----------------------------------------------------------------
-- Ratón y teclado
----------------------------------------------------------------
local function blocked()
    local e = E()
    return not e or e.testing or MEUI.modalOpen() or MEUI.isTyping() or isChatBoxInputActive() or isConsoleActive()
end

local function onMouse1(press)
    local e = E()
    local mx, my = cursorPx()
    if press then
        if not mx or MEUI.overUI() then return end
        if e.tool == "place" and ghost then
            placeGhost()
            return
        end
        if e.tool == "remove" then
            removeWorldHit()
            return
        end
        if hover and startGizmoDrag(hover) then
            mouseDown = { x = mx, y = my, kind = "gizmo" }
            return
        end
        local id = pickAt(mx, my)
        if id and e.sel[id] and not shift() then
            mouseDown = { x = mx, y = my, kind = "drag", id = id }
            return
        end
        mouseDown = { x = mx, y = my, kind = id and "click" or "box", id = id }
    else
        local md = mouseDown
        mouseDown = nil
        if not md then return end
        if md.kind == "gizmo" or md.kind == "drag" then
            if md.kind == "drag" and not (gdrag and gdrag.moved) then
                gdrag = nil
                -- clic simple sobre algo ya elegido: lo deja como única selección (doble clic: propiedades)
                if not doubleClick(md.id) then MEEditor.select(md.id, false) end
            else
                endDrag()
            end
        elseif md.kind == "click" then
            if not doubleClick(md.id) then MEEditor.select(md.id, shift()) end
        elseif md.kind == "box" then
            if mx and math.abs(mx - md.x) + math.abs(my - md.y) > 6 then
                boxSelect(md.x, md.y, mx, my, shift())
            elseif not shift() then
                MEEditor.clearSelection()
            end
        end
    end
end

local KEYS = {}
KEYS["1"] = function() E().gizmo = "move" MEEditor.pushState() end
KEYS["2"] = function() E().gizmo = "rotate" MEEditor.pushState() end
KEYS["3"] = function() E().gizmo = "scale" MEEditor.pushState() end
KEYS.l = function() E().localAxes = not E().localAxes MEEditor.pushState() end
KEYS.g = function() E().gridOn = not E().gridOn MEEditor.pushState() end
KEYS.r = function() nudge(0, 0, 0, shift() and -90 or 90) end
KEYS.pgup = function() nudge(0, 0, shift() and 0.05 or (E().gridOn and E().grid or 0.25)) end
KEYS.pgdn = function() nudge(0, 0, -(shift() and 0.05 or (E().gridOn and E().grid or 0.25))) end
KEYS.delete = function() MEEditor.deleteSelection() end
KEYS.h = function() MEUI.setHidden(not MEUI.isHidden()) end
KEYS.enter = function() MEEditor.openProps() end
-- Retroceso deshace lo último abierto: herramienta, propiedades, ventana y por último la selección
KEYS.backspace = function()
    if ghost or E().tool ~= "select" then
        destroyGhost()
        E().tool = "select"
        MEEditor.pushState()
    elseif MEUI.isShown("props") then
        MEUI.show("props", false)
    elseif MEUI.isShown("win") then
        MEEditor.closeWin()
    else
        MEEditor.clearSelection()
    end
end
KEYS.escape = KEYS.backspace

local CTRL_KEYS = {
    z = function() MEEditor.undo() end,
    y = function() MEEditor.redo() end,
    c = function() MEEditor.copySelection() MEEditor.pushState() end,
    v = function() local x, y, z = MEInput.cursorGround() MEEditor.paste(x and { x, y, z } or nil) end,
    d = function() MEEditor.duplicateSelection() end,
}

local function onKey(button, press)
    local e = E()
    if not e then return end
    -- F sale del modo prueba aunque los paneles estén ocultos
    if button == "f" and press and not MEUI.modalOpen() and not MEUI.isTyping() and not isChatBoxInputActive() then
        MEEditor.toggleTest()
        cancelEvent()
        return
    end
    if blocked() then return end
    if button == "mouse1" then
        onMouse1(press)
        return
    end
    if button == "mouse2" then
        if press then if not MEUI.overUI() then MECam.beginLook() end else MECam.endLook() end
        return
    end
    if button == "mouse_wheel_up" or button == "mouse_wheel_down" then
        if MEUI.overUI() then return end
        local up = button == "mouse_wheel_up"
        if ghost then
            ghost.rz = (ghost.rz + (up and 1 or -1) * (shift() and 1 or math.max(e.rotStep, 5))) % 360
        else
            MECam.wheel(up)
            MEEditor.pushState()
        end
        return
    end
    if not press then return end
    if ctrl() then
        local fn = CTRL_KEYS[button]
        if fn then fn() cancelEvent() end
        return
    end
    local fn = KEYS[button]
    if fn then
        fn()
        if button ~= "escape" then cancelEvent() end
    end
end

addEventHandler("onClientPreRender", root, function()
    local e = E()
    if not e or e.testing then return end
    updateGhost()
    updateWorldHit()
    hoverGizmo()
    if mouseDown and mouseDown.kind == "drag" and not gdrag then
        local mx, my = cursorPx()
        if mx and math.abs(mx - mouseDown.x) + math.abs(my - mouseDown.y) > 4 then startPlaneDrag() end
    end
    updateGizmoDrag()
    updatePlaneDrag()
end)

function MEInput.start()
    addEventHandler("onClientKey", root, onKey)
end

function MEInput.stop()
    removeEventHandler("onClientKey", root, onKey)
    destroyGhost()
    gdrag, hover, mouseDown, worldHit = nil, nil, nil, nil
end
