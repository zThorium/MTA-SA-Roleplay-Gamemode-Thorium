--[[
    rp_furniture / c_editor.lua
    Modo construccion (F4 o /decorar). Camara orbital, mueble fantasma con rejilla, seleccion
    multiple (clic, Mayus, caja), mover arrastrando, girar, escalar, color y material, ocultar
    objetos originales, deshacer/rehacer y todos los paneles (3 navegadores CEF en los bordes).

    Teclas:
        Clic derecho + arrastrar   orbitar          WASD / Espacio / Ctrl   mover el centro de la camara
        Rueda                      acercar/alejar   Alt + rueda             subir/bajar lo seleccionado
        Clic izq.                  seleccionar o colocar    Mayus+clic  anadir    arrastrar vacio  caja
        Q / E                      girar            R   girar 180            Av/Re Pag   subir/bajar
        Flechas                    empujar seleccion   Supr   a la bodega
        Ctrl+Z / Ctrl+Y            deshacer / rehacer       Ctrl+D   duplicar
        Tab                        siguiente rejilla        1 2 3   vistas
        Esc                        soltar mueble / quitar seleccion        F4   terminar
]]

FurnEditor = { active = false }

local screenW, screenH = guiGetScreenSize()
local L_W, R_W, T_W, T_H = 360, 310, 720, 58

local E = nil                 -- estado de la sesion (nil si no esta activo)
local panels = {}             -- { left, right, top } = { gui, browser, ready, pending }

addEvent("rp:furn:buildOn", true)
addEvent("rp:furn:buildOff", true)
addEvent("rp:furn:ack", true)
addEvent("rp:furn:sync", true)
addEvent("rp:furn:updated", true)
addEvent("rp:furn:removed", true)
addEvent("rp:furn:members", true)
addEvent("rp:furn:blueprints", true)
addEvent("rp:furn:reload", true)
addEvent("rp:furn:ui:cmd", false)
addEvent("rp:furn:ui:ready", false)

-- Cada aviso tambien se muestra en grande en pantalla y se escribe en el debug (para diagnosticar)
local function notify(text, kind)
    if E then E.flash = { text = tostring(text), tick = getTickCount(), kind = kind or "info" } end
    outputDebugString("[rp_furniture] " .. tostring(text), 3)
    exports.rp_notify:notify(text, kind or "info")
end

local function dbg(text) outputDebugString("[rp_furniture] " .. tostring(text), 3) end

-- Quita el foco del navegador CEF para que teclas y clics vuelvan al juego
local function releaseFocus()
    pcall(focusBrowser)
    guiSetInputEnabled(false)
    if E then E.typing = false end
end

----------------------------------------------------------------
-- Paneles CEF
----------------------------------------------------------------
local PANEL_RECT = {
    left  = function() return 0, 0, L_W, screenH end,
    right = function() return screenW - R_W, 0, R_W, screenH end,
    top   = function() return L_W + (screenW - L_W - R_W - T_W) / 2, 6, T_W, T_H end,
}

local function panelJS(name, code)
    local p = panels[name]
    if not p then return end
    if p.ready and isElement(p.browser) then executeBrowserJavascript(p.browser, code) else p.pending[#p.pending + 1] = code end
end

FurnEditor.panelJS = function(name, code) panelJS(name, code) end

local function pushAll(code)
    for name in pairs(panels) do panelJS(name, code) end
end

local function createPanels()
    for name, rectFn in pairs(PANEL_RECT) do
        local x, y, w, h = rectFn()
        -- opaco (no transparente): MTA solo acepta clics sobre pixeles opacos del ultimo cuadro dibujado
        local gui = guiCreateBrowser(x, y, w, h, true, false, false)
        local browser = guiGetBrowser(gui)
        panels[name] = { gui = gui, browser = browser, ready = false, pending = {} }
        addEventHandler("onClientBrowserCreated", browser, function() loadBrowserURL(source, "http://mta/local/html/index.html#" .. name) end)
        addEventHandler("onClientBrowserDocumentReady", browser, function()
            local p = panels[name]
            if not p then return end
            p.ready = true
            for _, code in ipairs(p.pending) do executeBrowserJavascript(source, code) end
            p.pending = {}
        end)
    end
end

local function destroyPanels()
    for _, p in pairs(panels) do if isElement(p.gui) then destroyElement(p.gui) end end
    panels = {}
end

local function overUI()
    local cx, cy = getCursorPosition()
    if not cx then return true end
    local ax, ay = cx * screenW, cy * screenH
    if isElement(panels.left and panels.left.gui) then
        for _, rectFn in pairs(PANEL_RECT) do
            local x, y, w, h = rectFn()
            if ax >= x and ax <= x + w and ay >= y and ay <= y + h then return true end
        end
    end
    return false
end

----------------------------------------------------------------
-- Matematica auxiliar
----------------------------------------------------------------
local function snap(v, g) if g and g > 0 then return math.floor(v / g + 0.5) * g end return v end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function round3(v) return math.floor(v * 1000 + (v >= 0 and 0.5 or -0.5)) / 1000 end

local function getT(obj)
    local x, y, z = getElementPosition(obj)
    local rx, ry, rz = getElementRotation(obj)
    local sx, sy, sz = getObjectScale(obj)
    return { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, sx = sx or 1, sy = sy or 1, sz = sz or 1 }
end

local function copyT(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

local function validPos(x, y, z)
    local b = E.bounds
    local dx, dy = x - b.x, y - b.y
    local d2 = dx * dx + dy * dy
    if d2 > b.r * b.r then return false end
    if z < b.zmin or z > b.zmax then return false end
    if d2 < b.door * b.door and math.abs(z - b.z) < 2.5 then return false end
    return true
end

local function resolve(fid)
    local n = 0
    while E.alias[fid] and n < 20 do fid = E.alias[fid] n = n + 1 end
    return fid
end

local function objOf(fid)
    local obj, d = FurnCore.byId(resolve(fid))
    return obj, d
end

local function defOf(obj)
    local d = getElementData(obj, "rp:furn", false)
    return d and FURN_ITEMS[d.key], d
end

----------------------------------------------------------------
-- Estado enviado a los paneles
----------------------------------------------------------------
local function selectedList()
    local list = {}
    for fid in pairs(E.sel) do
        local obj, d = objOf(fid)
        if obj then list[#list + 1] = { fid = fid, obj = obj, d = d } else E.sel[fid] = nil end
    end
    table.sort(list, function(a, b) return a.fid < b.fid end)
    return list
end

local function buildState()
    local sel = selectedList()
    local first
    if #sel >= 1 then
        local s = sel[1]
        local def = FURN_ITEMS[s.d.key]
        local t = getT(s.obj)
        first = {
            fid = s.fid, key = s.d.key, name = def and def.name or s.d.key, struct = def and def.struct or false,
            x = round3(t.x), y = round3(t.y), z = round3(t.z), rx = round3(t.rx), ry = round3(t.ry), rz = round3(t.rz),
            sx = round3(t.sx), sy = round3(t.sy), sz = round3(t.sz), color = s.d.color or -1, mat = s.d.mat or "",
            sell = def and math.floor(def.price * (E.placed[s.fid] and FURN.SESSION_REFUND or FURN.SELL_REFUND)) or 0,
        }
    end
    return {
        tool = E.tool, gizmo = E.gizmo, grid = E.grid, rotStep = E.rotStep, view = E.view, money = E.money, weight = E.weight, limit = E.limit,
        count = E.count, stock = E.stock, selCount = #sel, first = first, ghost = E.ghost and E.ghost.key or "",
        ghostColor = E.paintColor, ghostMat = E.paintMat,
        removed = E.removed, members = E.members, blueprints = E.blueprints, isOwner = E.isOwner, name = E.name,
        canUndo = #E.undo > 0, canRedo = #E.redo > 0,
    }
end

local dirty = true
local function markDirty() dirty = true end

local function pushState()
    pushAll(("FURN.state(%s[0])"):format(toJSON(buildState(), true)))
end

----------------------------------------------------------------
-- Fantasma (mueble que se esta colocando)
----------------------------------------------------------------
local function destroyGhost()
    if E.ghost then
        if isElement(E.ghost.obj) then
            FurnStyle.clear(E.ghost.obj)
            destroyElement(E.ghost.obj)
        end
        E.ghost = nil
    end
end

local function setGhost(key)
    destroyGhost()
    local def = FURN_ITEMS[key]
    if not def then return end
    local obj = createObject(def.model, E.bounds.x, E.bounds.y, E.bounds.z - 1)
    if not obj then return end
    setElementInterior(obj, FurnCore.interior)
    setElementDimension(obj, getElementDimension(localPlayer))
    setElementCollisionsEnabled(obj, false)
    local sx, sy, sz = def.sx or 1, def.sy or 1, def.sz or 1
    setObjectScale(obj, sx, sy, sz)
    E.ghost = { key = key, def = def, obj = obj, rx = 0, ry = 0, rz = 0, sx = sx, sy = sy, sz = sz, hOff = 0, flip = 0, valid = nil, t = nil }
    E.tool = "place"
    markDirty()
end

----------------------------------------------------------------
-- Rayo desde el cursor
----------------------------------------------------------------
local function cursorRay()
    local cx, cy = getCursorPosition()
    if not cx then return end
    local fx, fy, fz = getWorldFromScreenPosition(cx * screenW, cy * screenH, 90)
    if not fx then return end
    return E.cam.x, E.cam.y, E.cam.z, fx, fy, fz
end

-- Empieza el rayo dentro de la casa (por debajo del techo) para que el techo no lo bloquee
local function castFromCursor(ignore, withWorld)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local floorZ = E.bounds.z - 1
    local startZ = floorZ + 2.3
    if z1 > startZ and z2 < z1 then
        local t = (z1 - startZ) / (z1 - z2)
        x1, y1, z1 = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, startZ
    end
    local r = { processLineOfSight(x1, y1, z1, x2, y2, z2, true, false, false, true, false, false, false, false, ignore, withWorld and true or false) }
    if r[1] then return r end
    -- sin impacto: plano del suelo
    if z2 < z1 then
        local t = (z1 - floorZ) / (z1 - z2)
        if t > 0 then
            return { true, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, floorZ, nil, 0, 0, 1, plane = true }
        end
    end
end

local function projectCenter(obj)
    local x, y, z = getElementPosition(obj)
    local sx, sy = getScreenFromWorldPosition(x, y, z + 0.3)
    return sx, sy
end

local function pickFurniture(hit)
    if hit and hit[5] and isElement(hit[5]) and getElementData(hit[5], "rp:furn", false) then return hit[5] end
    -- apoyo por pantalla (objetos sin colision)
    local cx, cy = getCursorPosition()
    if not cx then return end
    local ax, ay = cx * screenW, cy * screenH
    local best, bestD = nil, 38
    for _, obj in ipairs(FurnCore.objects()) do
        local sx, sy = projectCenter(obj)
        if sx then
            local d = math.sqrt((sx - ax) ^ 2 + (sy - ay) ^ 2)
            if d < bestD then best, bestD = obj, d end
        end
    end
    return best
end

----------------------------------------------------------------
-- Colocacion libre: Mayus = sin rejilla, X / Y / Z = bloquear a un eje
----------------------------------------------------------------
local function freeMode() return getKeyState("lshift") or getKeyState("rshift") end
local function gridNow() if freeMode() then return 0 end return E.grid end

local function axisLock()
    if E.typing or getKeyState("lctrl") or getKeyState("rctrl") then return nil end
    if getKeyState("x") then return "x" end
    if getKeyState("y") then return "y" end
    if getKeyState("z") then return "z" end
end

-- Punto del cursor sobre el plano horizontal z = zPlane
local function floorPoint(zPlane)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 or z2 >= z1 then return end
    local t = (z1 - zPlane) / (z1 - z2)
    if t <= 0 then return end
    return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
end

-- Altura (z) donde el rayo del cursor corta el plano vertical que pasa por (px, py) y mira a la camara
local function verticalZ(px, py)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local nx, ny = E.cam.x - px, E.cam.y - py
    local l = math.sqrt(nx * nx + ny * ny)
    if l < 0.001 then return end
    nx, ny = nx / l, ny / l
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local denom = dx * nx + dy * ny
    if math.abs(denom) < 1e-4 then return end
    local s = ((px - x1) * nx + (py - y1) * ny) / denom
    if s <= 0 then return end
    return z1 + dz * s
end

-- Rayo contra muebles, sin edificios: el techo y las paredes no estorban
local function furnitureHit(ignore)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local r = { processLineOfSight(x1, y1, z1, x2, y2, z2, false, false, false, true, false, false, false, false, ignore) }
    if r[1] and isElement(r[5]) and getElementData(r[5], "rp:furn", false) then return r end
end

-- Los objetos pequenos se apoyan sobre otros muebles (mesas, repisas)
local function canStack(def) return not def.struct and not def.wall and ((def.w or 1) <= 0.5 or def.cat == "electro" or def.cat == "luces") end

----------------------------------------------------------------
-- Seleccion
----------------------------------------------------------------
local function clearSelection() E.sel = {} markDirty() end

local function selectObj(obj, additive)
    local d = getElementData(obj, "rp:furn", false)
    if not d then return end
    if not additive then E.sel = {} end
    if additive and E.sel[d.id] then E.sel[d.id] = nil else E.sel[d.id] = true end
    markDirty()
end

----------------------------------------------------------------
-- Envio al servidor (con deshacer)
----------------------------------------------------------------
local function pushUndo(entry)
    E.undo[#E.undo + 1] = entry
    if #E.undo > 80 then table.remove(E.undo, 1) end
    E.redo = {}
    markDirty()
end

local function sendUpdate(list)
    for _, e in ipairs(list) do E.inflight[e.id] = E.inflight[e.id] or E.snapshots[e.id] end
    triggerServerEvent("rp:furn:update", resourceRoot, list)
end

local function updateEntry(fid, t, color, mat)
    local e = { id = fid }
    if t then for k, v in pairs(t) do e[k] = v end end
    if color ~= nil then e.color = color end
    if mat ~= nil then e.mat = mat end
    return e
end

-- Aplica transformaciones a la seleccion localmente y las envia
local function commitTransforms(items, label)
    -- items: { { fid, obj, before = T, after = T } }
    local list, undoEntry = {}, { type = "move", items = {} }
    for _, it in ipairs(items) do
        local a = it.after
        a.x, a.y, a.z = round3(a.x), round3(a.y), round3(a.z)
        if validPos(a.x, a.y, a.z) then
            E.snapshots[it.fid] = it.before
            list[#list + 1] = updateEntry(it.fid, a)
            undoEntry.items[#undoEntry.items + 1] = { fid = it.fid, before = it.before, after = a }
        else
            -- vuelve a su sitio
            setElementPosition(it.obj, it.before.x, it.before.y, it.before.z)
            setElementRotation(it.obj, it.before.rx, it.before.ry, it.before.rz)
            setObjectScale(it.obj, it.before.sx, it.before.sy, it.before.sz)
            notify("Esa posicion esta fuera de la zona o bloquea la puerta.", "warning")
        end
    end
    if #list > 0 then
        sendUpdate(list)
        pushUndo(undoEntry)
    end
end

local function selectionItems()
    local items = {}
    for _, s in ipairs(selectedList()) do
        items[#items + 1] = { fid = s.fid, obj = s.obj, before = getT(s.obj), after = getT(s.obj) }
    end
    return items
end

local function applyLocal(it)
    local a = it.after
    setElementPosition(it.obj, a.x, a.y, a.z)
    setElementRotation(it.obj, a.rx, a.ry, a.rz)
    setObjectScale(it.obj, a.sx, a.sy, a.sz)
end

local function centroid(items)
    local x, y, z = 0, 0, 0
    for _, it in ipairs(items) do x, y, z = x + it.before.x, y + it.before.y, z + it.before.z end
    local n = math.max(1, #items)
    return x / n, y / n, z / n
end

local function nudge(dx, dy, dz)
    local items = selectionItems()
    if #items == 0 then return end
    for _, it in ipairs(items) do
        it.after.x, it.after.y, it.after.z = it.before.x + dx, it.before.y + dy, it.before.z + dz
        applyLocal(it)
    end
    commitTransforms(items)
end

local function rotateSelection(deg)
    local items = selectionItems()
    if #items == 0 then return end
    local cx, cy = centroid(items)
    local rad = math.rad(deg)
    local c, s = math.cos(rad), math.sin(rad)
    for _, it in ipairs(items) do
        if #items > 1 then
            local px, py = it.before.x - cx, it.before.y - cy
            it.after.x, it.after.y = cx + px * c - py * s, cy + px * s + py * c
        end
        it.after.rz = (it.before.rz + deg) % 360
        applyLocal(it)
    end
    commitTransforms(items)
end

local function paintSelection(color, mat)
    local sel = selectedList()
    if #sel == 0 then return end
    local list, undoEntry = {}, { type = "paint", items = {} }
    for _, s in ipairs(sel) do
        local oc, om = s.d.color or -1, s.d.mat or ""
        local nc = color ~= nil and color or oc
        local nm = mat ~= nil and mat or om
        list[#list + 1] = { id = s.fid, color = nc, mat = nm }
        undoEntry.items[#undoEntry.items + 1] = { fid = s.fid, beforeColor = oc, beforeMat = om, afterColor = nc, afterMat = nm }
    end
    triggerServerEvent("rp:furn:update", resourceRoot, list)
    pushUndo(undoEntry)
end

local function removeSelection(mode)
    local sel = selectedList()
    if #sel == 0 then return end
    local ids, snap = {}, {}
    for _, s in ipairs(sel) do
        ids[#ids + 1] = s.fid
        local t = getT(s.obj)
        snap[#snap + 1] = { fid = s.fid, key = s.d.key, t = t, color = s.d.color, mat = s.d.mat }
    end
    if mode == "sell" then
        E.undo, E.redo = {}, {}
    else
        pushUndo({ type = "remove", items = snap })
    end
    triggerServerEvent("rp:furn:remove", resourceRoot, ids, mode)
    E.sel = {}
    markDirty()
end

local function nextRef() E.ref = E.ref + 1 return E.ref end

local function sendPlace(key, t, color, mat, forceStock, cb)
    local def = FURN_ITEMS[key]
    if not def then return end
    local inStock = (E.stock[key] or 0) > 0
    local src = (forceStock or inStock) and "stock" or "buy"
    if src == "buy" and def.price > E.money then return notify(("Necesitas $%d en tu cuenta bancaria."):format(def.price), "error") end
    if E.weight + (def.w or 1) > E.limit + 1e-6 then return notify("Alcanzaste el limite de objetos de esta propiedad.", "warning") end
    local ref = nextRef()
    E.pending[ref] = function(ok, data)
        if ok and cb then cb(data.id) end
    end
    local msg = { ref = ref, key = key, src = src, color = color, mat = mat }
    for k, v in pairs(t) do msg[k] = v end
    if msg.color == nil then msg.color = nil end
    triggerServerEvent("rp:furn:place", resourceRoot, msg)
    -- reserva local mientras llega la respuesta
    E.weight = E.weight + (def.w or 1)
end

local function placeGhost()
    local g = E.ghost
    if not g then return end
    if not g.t then return notify("Apunta al suelo de la casa para colocar el mueble.", "warning") end
    if not g.valid then return notify("No se puede colocar ahi: queda fuera de la zona o bloquea la puerta.", "warning") end
    local t = copyT(g.t)
    local key, color, mat = g.key, E.paintColor, E.paintMat
    dbg(("enviando colocacion de %s en %.1f, %.1f, %.1f"):format(key, t.x, t.y, t.z))
    sendPlace(key, t, color, mat, false, function(fid)
        E.placed[fid] = true
        pushUndo({ type = "place", fid = fid, key = key, t = t, color = color, mat = mat })
    end)
end

local function duplicateSelection()
    local sel = selectedList()
    if #sel == 0 then return end
    local newIds = {}
    for _, s in ipairs(sel) do
        local t = getT(s.obj)
        t.x, t.y = t.x + 0.6, t.y + 0.6
        local key, color, mat = s.d.key, s.d.color, s.d.mat
        sendPlace(key, t, color, mat, false, function(fid)
            E.placed[fid] = true
            pushUndo({ type = "place", fid = fid, key = key, t = t, color = color, mat = mat })
            newIds[#newIds + 1] = fid
            E.sel = {}
            for _, id in ipairs(newIds) do E.sel[id] = true end
            markDirty()
        end)
    end
end

----------------------------------------------------------------
-- Deshacer / rehacer
----------------------------------------------------------------
local function applyEntry(entry, undo)
    if entry.type == "move" then
        local list = {}
        for _, it in ipairs(entry.items) do
            local fid = resolve(it.fid)
            local obj = FurnCore.byId(fid)
            if obj then E.snapshots[fid] = getT(obj) end
            list[#list + 1] = updateEntry(fid, undo and it.before or it.after)
            if obj then
                local a = undo and it.before or it.after
                setElementPosition(obj, a.x, a.y, a.z)
                setElementRotation(obj, a.rx, a.ry, a.rz)
                setObjectScale(obj, a.sx, a.sy, a.sz)
            end
        end
        sendUpdate(list)
    elseif entry.type == "paint" then
        local list = {}
        for _, it in ipairs(entry.items) do
            list[#list + 1] = { id = resolve(it.fid), color = undo and it.beforeColor or it.afterColor, mat = undo and it.beforeMat or it.afterMat }
        end
        triggerServerEvent("rp:furn:update", resourceRoot, list)
    elseif entry.type == "place" then
        if undo then
            triggerServerEvent("rp:furn:remove", resourceRoot, { resolve(entry.fid) }, "refund")
        else
            local old = entry.fid
            sendPlace(entry.key, entry.t, entry.color, entry.mat, false, function(fid)
                E.alias[old] = fid
                entry.fid = fid
                E.placed[fid] = true
            end)
        end
    elseif entry.type == "hide" then
        if undo then
            -- se buscan las entradas ocultas actuales y se restauran de una vez
            local idx = {}
            for _, e in ipairs(entry.items) do
                for i, r in ipairs(E.removed or {}) do
                    if r.m == e.m and math.abs(r.x - e.x) < 0.02 and math.abs(r.y - e.y) < 0.02 and math.abs(r.z - e.z) < 0.02
                        and math.abs((tonumber(r.r) or 0) - (tonumber(e.r) or 0)) < 0.02 then idx[#idx + 1] = i break end
                end
            end
            if #idx > 0 then triggerServerEvent("rp:furn:restoreProp", resourceRoot, idx) end
        else
            triggerServerEvent("rp:furn:hideProps", resourceRoot, entry.items)
        end
    elseif entry.type == "remove" then
        if undo then
            for _, it in ipairs(entry.items) do
                local old = it.fid
                sendPlace(it.key, it.t, it.color, it.mat, true, function(fid) E.alias[old] = fid it.fid = fid end)
            end
        else
            local ids = {}
            for _, it in ipairs(entry.items) do ids[#ids + 1] = resolve(it.fid) end
            triggerServerEvent("rp:furn:remove", resourceRoot, ids, "stock")
        end
    end
end

local function undo()
    local entry = table.remove(E.undo)
    if not entry then return end
    applyEntry(entry, true)
    E.redo[#E.redo + 1] = entry
    markDirty()
end

local function redo()
    local entry = table.remove(E.redo)
    if not entry then return end
    applyEntry(entry, false)
    E.undo[#E.undo + 1] = entry
    markDirty()
end

----------------------------------------------------------------
-- Camara
----------------------------------------------------------------
local function setView(n)
    E.view = n
    if n == 1 then E.cam.pitch, E.cam.dist = 88, 12
    elseif n == 2 then E.cam.pitch, E.cam.dist = 50, 9
    else E.cam.pitch, E.cam.dist = 14, 5 end
    markDirty()
end

local function updateCamera(dt)
    local c = E.cam
    if not E.typing and not isElement(FurnCore.modalGui) then
        local speed = (getKeyState("lshift") and 14 or 5) * dt
        local fx, fy = -math.cos(c.yaw), -math.sin(c.yaw)
        local rx, ry = -fy, fx
        if getKeyState("w") then c.px, c.py = c.px + fx * speed, c.py + fy * speed end
        if getKeyState("s") then c.px, c.py = c.px - fx * speed, c.py - fy * speed end
        if getKeyState("d") then c.px, c.py = c.px - rx * speed, c.py - ry * speed end
        if getKeyState("a") then c.px, c.py = c.px + rx * speed, c.py + ry * speed end
        if getKeyState("space") then c.pz = c.pz + speed end
        if getKeyState("lctrl") and not getKeyState("z") and not getKeyState("y") and not getKeyState("d") then c.pz = c.pz - speed end
    end
    local b = E.bounds
    local dx, dy = c.px - b.x, c.py - b.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > b.r then c.px, c.py = b.x + dx / d * b.r, b.y + dy / d * b.r end
    c.pz = clamp(c.pz, b.zmin, b.zmax)
    local p, y = math.rad(c.pitch), c.yaw
    c.x = c.px + c.dist * math.cos(p) * math.cos(y)
    c.y = c.py + c.dist * math.cos(p) * math.sin(y)
    c.z = c.pz + c.dist * math.sin(p)
    setCameraMatrix(c.x, c.y, c.z, c.px, c.py, c.pz)
end

----------------------------------------------------------------
-- Actualizacion por cuadro: fantasma y arrastre
----------------------------------------------------------------
local function bbox(obj)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(obj)
    if x1 then return x1, y1, z1, x2, y2, z2 end
    return -0.5, -0.5, 0, 0.5, 0.5, 1
end

-- Altura real del suelo bajo (x, y): rayo corto hacia abajo contra el edificio
local function floorHeightAt(x, y, guessZ)
    local hit, _, _, hz = processLineOfSight(x, y, guessZ + 2.0, x, y, guessZ - 2.0, true, false, false, false, false, false, false, false)
    if hit and hz and math.abs(hz - guessZ) < 2.0 then return hz end
    return guessZ
end

local function updateGhost()
    local g = E.ghost
    if not g or not isElement(g.obj) then return end
    if overUI() or E.drag or E.gdrag or E.cam.orbiting then g.t = nil return setElementAlpha(g.obj, 0) end

    local grid = gridNow()
    local floorZ = E.bounds.z - 1
    local px, py, pz, nx, ny
    local onWall = false

    -- 1) muebles de pared: rayo contra el edificio, solo si impacta una pared dentro de la zona
    if g.def.wall then
        local hit = castFromCursor(g.obj, false)
        if hit and not hit.plane and math.abs(hit[8] or 1) < 0.6 and validPos(hit[2], hit[3], hit[4]) then
            px, py, pz, nx, ny, onWall = hit[2], hit[3], hit[4], hit[6] or 0, hit[7] or 0, true
        end
    end
    -- 2) objetos pequenos sobre otros muebles
    if not px and canStack(g.def) then
        local fh = furnitureHit(g.obj)
        if fh and (fh[8] or 0) > 0.6 then px, py, pz = fh[2], fh[3], fh[4] end
    end
    -- 3) suelo: plano de la casa (siempre da un punto aunque el techo o las paredes estorben)
    if not px then
        local fx, fy = floorPoint(floorZ)
        if not fx then g.t = nil return setElementAlpha(g.obj, 0) end
        px, py = fx, fy
        pz = floorHeightAt(fx, fy, floorZ)
    end

    local minX, minY, minZ, maxX, maxY, maxZ = bbox(g.obj)
    local rz = g.rz
    local sx, sy, sz = g.sx, g.sy, g.sz
    local x, y, z
    if onWall then
        -- pared: el mueble queda pegado mirando hacia fuera y centrado en el punto
        rz = (math.deg(math.atan2(ny, nx)) - 90 + g.flip) % 360
        local depth = (maxY - minY) * sy / 2
        x, y = px + nx * depth, py + ny * depth
        z = pz - ((minZ + maxZ) / 2) * sz + g.hOff
        if grid > 0 then z = snap(z, grid) end
    else
        x, y = snap(px, grid), snap(py, grid)
        z = pz - minZ * sz + g.hOff
    end

    -- bloqueo a un eje (X / Y / Z mantenida): se parte de la ultima posicion libre
    local lock = axisLock()
    if lock then
        if not g.lock or g.lock.axis ~= lock then
            local a = g.free or { x = x, y = y, z = z }
            g.lock = { axis = lock, ax = a.x, ay = a.y, az = a.z, vref = verticalZ(a.x, a.y) }
        end
        local L = g.lock
        if lock == "x" then y, z = L.ay, L.az
        elseif lock == "y" then x, z = L.ax, L.az
        else
            x, y = L.ax, L.ay
            local vz = verticalZ(L.ax, L.ay)
            if vz and L.vref then
                z = L.az + vz - L.vref
                if grid > 0 then z = snap(z, grid) end
            else z = L.az end
        end
        g.lockAxis = lock
    else
        g.lock, g.lockAxis = nil, nil
        g.free = { x = x, y = y, z = z }
    end

    setElementAlpha(g.obj, 255)
    setElementPosition(g.obj, x, y, z)
    setElementRotation(g.obj, g.rx, g.ry, rz)
    setObjectScale(g.obj, sx, sy, sz)
    local ok = validPos(x, y, z)
    if g.valid ~= ok then
        g.valid = ok
        FurnStyle.apply(g.obj, ok and 0x77FF99 or 0xFF5555, nil, 0.7)
    end
    g.t = { x = x, y = y, z = z, rx = g.rx, ry = g.ry, rz = rz, sx = sx, sy = sy, sz = sz }
end

local function updateDrag()
    local d = E.drag
    if not d then return end
    local grid = gridNow()
    local lock = axisLock()
    local first = d.items[1]
    local dx, dy, dz = 0, 0, d.dz
    d.lockAxis = lock

    if lock == "z" then
        -- vertical: el movimiento del raton arriba y abajo sube y baja el mueble
        local vz = verticalZ(d.startX, d.startY)
        if not vz then return end
        if not d.vref then d.vref = vz end
        dz = d.dz + (vz - d.vref)
        if grid > 0 then dz = snap(first.before.z + dz, grid) - first.before.z end
    else
        d.vref = nil
        local hx, hy = floorPoint(d.planeZ)
        if not hx then return end
        dx, dy = hx - d.startX, hy - d.startY
        if lock == "x" then dy = 0 elseif lock == "y" then dx = 0 end
        -- se ajusta el primer objeto a la rejilla y los demas siguen su desplazamiento
        if grid > 0 then
            if lock ~= "y" then dx = snap(first.before.x + dx, grid) - first.before.x end
            if lock ~= "x" then dy = snap(first.before.y + dy, grid) - first.before.y end
        end
    end
    for _, it in ipairs(d.items) do
        it.after.x, it.after.y, it.after.z = it.before.x + dx, it.before.y + dy, it.before.z + dz
        applyLocal(it)
    end
    d.moved = d.moved or (math.abs(dx) > 0.02 or math.abs(dy) > 0.02 or math.abs(dz - d.dz) > 0.02)
end

----------------------------------------------------------------
-- Vaciar interior: un comodin (m = -1) oculta TODOS los modelos de mobiliario de GTA
-- (FURN_DEFAULT_PROP_IDS, de props.ide / props2.ide) en el radio de la casa, incluidos los
-- objetos sin colision. Las paredes, los suelos y las puertas no estan en esa lista.
----------------------------------------------------------------
local function startScan()
    for _, e in ipairs(E.removed or {}) do
        if e.m == -1 then return notify("Ya se ocultaron todos los muebles originales.", "info") end
    end
    local b = E.bounds
    local entry = { m = -1, x = b.x, y = b.y, z = b.z, r = b.r + 3 }
    triggerServerEvent("rp:furn:hideProps", resourceRoot, { entry })
    pushUndo({ type = "hide", items = { entry } })
    notify("Ocultando los muebles originales de la casa...", "success")
end

----------------------------------------------------------------
-- Gizmo estilo Blender: flechas X (rojo) Y (verde) Z (azul)
--   4 mover  5 girar (anillos)  6 escalar. Se arrastra un eje y solo cambia esa coordenada.
----------------------------------------------------------------
local AXES = { x = { 1, 0, 0 }, y = { 0, 1, 0 }, z = { 0, 0, 1 } }
local AXCOL = { x = { 235, 64, 64 }, y = { 88, 206, 96 }, z = { 70, 132, 245 } }
local RING_BASIS = { x = { { 0, 1, 0 }, { 0, 0, 1 } }, y = { { 0, 0, 1 }, { 1, 0, 0 } }, z = { { 1, 0, 0 }, { 0, 1, 0 } } }

local function gizmoOrigin()
    local sel = selectedList()
    if #sel == 0 then return end
    local x, y, z = 0, 0, 0
    for _, s in ipairs(sel) do
        local px, py, pz = getElementPosition(s.obj)
        x, y, z = x + px, y + py, z + pz
    end
    return x / #sel, y / #sel, z / #sel
end

local function gizmoLen() return clamp(E.cam.dist * 0.15, 0.7, 2.6) end

local function cursorPx()
    local cx, cy = getCursorPosition()
    if not cx then return end
    return cx * screenW, cy * screenH
end

local function segDist(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local l2 = vx * vx + vy * vy
    local t = l2 > 0 and clamp(((px - ax) * vx + (py - ay) * vy) / l2, 0, 1) or 0
    local qx, qy = ax + vx * t, ay + vy * t
    return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

local function ringPoint(ox, oy, oz, axis, ang, r)
    local b = RING_BASIS[axis]
    local c, s = math.cos(ang) * r, math.sin(ang) * r
    return ox + b[1][1] * c + b[2][1] * s, oy + b[1][2] * c + b[2][2] * s, oz + b[1][3] * c + b[2][3] * s
end

-- Parametro t de la recta eje (origen + t * a) mas cercano al rayo del cursor
local function axisParam(ox, oy, oz, a)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / dl, dy / dl, dz / dl
    local b = dx * a[1] + dy * a[2] + dz * a[3]
    local denom = 1 - b * b
    if denom < 1e-4 then return end
    local wx, wy, wz = x1 - ox, y1 - oy, z1 - oz
    local d_ = dx * wx + dy * wy + dz * wz
    local e_ = a[1] * wx + a[2] * wy + a[3] * wz
    return (e_ - b * d_) / denom
end

-- Angulo del cursor alrededor del eje (grados), sobre el plano del anillo
local function ringAngle(ox, oy, oz, axis)
    local x1, y1, z1, x2, y2, z2 = cursorRay()
    if not x1 then return end
    local n = AXES[axis]
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local denom = dx * n[1] + dy * n[2] + dz * n[3]
    if math.abs(denom) < 1e-4 then return end
    local s = ((ox - x1) * n[1] + (oy - y1) * n[2] + (oz - z1) * n[3]) / denom
    local hx, hy, hz = x1 + dx * s - ox, y1 + dy * s - oy, z1 + dz * s - oz
    local b = RING_BASIS[axis]
    local u = hx * b[1][1] + hy * b[1][2] + hz * b[1][3]
    local v = hx * b[2][1] + hy * b[2][2] + hz * b[2][3]
    return math.deg(math.atan2(v, u))
end

local function hoverGizmo()
    E.gizmoHover = nil
    if overUI() or E.drag or E.gdrag or E.ghost or E.box or E.cam.orbiting or E.tool ~= "select" then return end
    local ox, oy, oz = gizmoOrigin()
    if not ox then return end
    local mx, my = cursorPx()
    if not mx then return end
    local L = gizmoLen()
    local best, bestD = nil, 13
    local sx0, sy0 = getScreenFromWorldPosition(ox, oy, oz)
    for axis, a in pairs(AXES) do
        local d
        if E.gizmo == "rotate" then
            local px, py
            for i = 0, 40 do
                local wx, wy, wz = ringPoint(ox, oy, oz, axis, i / 40 * math.pi * 2, L * 0.85)
                local sx, sy = getScreenFromWorldPosition(wx, wy, wz)
                if sx and px then
                    local dd = segDist(mx, my, px, py, sx, sy)
                    if not d or dd < d then d = dd end
                end
                px, py = sx, sy
            end
        else
            local sx1, sy1 = getScreenFromWorldPosition(ox + a[1] * L, oy + a[2] * L, oz + a[3] * L)
            if sx0 and sx1 then d = segDist(mx, my, sx0, sy0, sx1, sy1) end
        end
        if d and d < bestD then best, bestD = axis, d end
    end
    E.gizmoHover = best
end

local function startGizmoDrag(axis)
    local items = selectionItems()
    if #items == 0 then return end
    local ox, oy, oz = gizmoOrigin()
    local g = { mode = E.gizmo, axis = axis, items = items, ox = ox, oy = oy, oz = oz, L = gizmoLen(), moved = false }
    if E.gizmo == "rotate" then g.a0 = ringAngle(ox, oy, oz, axis) else g.t0 = axisParam(ox, oy, oz, AXES[axis]) end
    if not (g.a0 or g.t0) then return end
    E.gdrag = g
end

local function updateGizmoDrag()
    local g = E.gdrag
    if not g then return end
    local axis, grid, first = g.axis, gridNow(), g.items[1]
    if g.mode == "move" then
        local t = axisParam(g.ox, g.oy, g.oz, AXES[axis])
        if not t then return end
        local delta = t - g.t0
        if grid > 0 then delta = snap(first.before[axis] + delta, grid) - first.before[axis] end
        for _, it in ipairs(g.items) do
            it.after.x, it.after.y, it.after.z = it.before.x, it.before.y, it.before.z
            it.after[axis] = it.before[axis] + delta
            applyLocal(it)
        end
        g.info = ("Mover %s: %+.2f m"):format(axis:upper(), delta)
        g.moved = g.moved or math.abs(delta) > 0.01
    elseif g.mode == "scale" then
        local t = axisParam(g.ox, g.oy, g.oz, AXES[axis])
        if not t then return end
        local f = clamp(1 + (t - g.t0) / g.L, 0.2, 6)
        if grid > 0 then f = snap(f, 0.1) end
        local key = "s" .. axis
        for _, it in ipairs(g.items) do
            local def = defOf(it.obj)
            local smax = def and def.struct and FURN.SCALE_STRUCT_MAX or FURN.SCALE_MAX
            it.after[key] = clamp(it.before[key] * f, FURN.SCALE_MIN, smax)
            applyLocal(it)
        end
        g.info = ("Escalar %s: x%.2f"):format(axis:upper(), f)
        g.moved = g.moved or math.abs(f - 1) > 0.01
    else
        local ang = ringAngle(g.ox, g.oy, g.oz, axis)
        if not ang then return end
        local delta = ang - g.a0
        if E.rotStep > 0 and not freeMode() then delta = snap(delta, E.rotStep) end
        local rad = math.rad(delta)
        local c, s = math.cos(rad), math.sin(rad)
        for _, it in ipairs(g.items) do
            local a = it.after
            a.x, a.y, a.z = it.before.x, it.before.y, it.before.z
            if axis == "z" then
                a.rz = (it.before.rz + delta) % 360
                if #g.items > 1 then
                    local px, py = it.before.x - g.ox, it.before.y - g.oy
                    a.x, a.y = g.ox + px * c - py * s, g.oy + px * s + py * c
                end
            else
                a["r" .. axis] = (it.before["r" .. axis] + delta) % 360
            end
            applyLocal(it)
        end
        g.info = ("Girar %s: %+d°"):format(axis:upper(), math.floor(delta + 0.5))
        g.moved = g.moved or math.abs(delta) > 0.5
    end
end

local function endGizmoDrag()
    local g = E.gdrag
    E.gdrag = nil
    if not g then return end
    if g.moved then
        commitTransforms(g.items)
    else
        for _, it in ipairs(g.items) do
            setElementPosition(it.obj, it.before.x, it.before.y, it.before.z)
            setElementRotation(it.obj, it.before.rx, it.before.ry, it.before.rz)
            setObjectScale(it.obj, it.before.sx, it.before.sy, it.before.sz)
        end
    end
end

addEventHandler("onClientPreRender", root, function(ms)
    if not E then return end
    local dt = math.min(ms, 100) / 1000
    updateCamera(dt)
    updateGhost()
    updateDrag()
    hoverGizmo()
    updateGizmoDrag()
    if dirty then dirty = false pushState() end
end)

----------------------------------------------------------------
-- Dibujo 3D
----------------------------------------------------------------
local function line(x1, y1, z1, x2, y2, z2, color, w) dxDrawLine3D(x1, y1, z1, x2, y2, z2, color, w or 2) end

local function drawBox(obj, color)
    local x1, y1, z1, x2, y2, z2 = bbox(obj)
    local sx, sy, sz = getObjectScale(obj)
    sx, sy, sz = sx or 1, sy or 1, sz or 1
    local m = getElementMatrix(obj)
    if not m then return end
    local function norm(a, b, c) local l = math.sqrt(a * a + b * b + c * c) if l == 0 then l = 1 end return a / l, b / l, c / l end
    local rx_, ry_, rz_ = norm(m[1][1], m[1][2], m[1][3])
    local fx, fy, fz = norm(m[2][1], m[2][2], m[2][3])
    local ux, uy, uz = norm(m[3][1], m[3][2], m[3][3])
    local px, py, pz = m[4][1], m[4][2], m[4][3]
    local function pt(a, b, c)
        a, b, c = a * sx, b * sy, c * sz
        return px + rx_ * a + fx * b + ux * c, py + ry_ * a + fy * b + uy * c, pz + rz_ * a + fz * b + uz * c
    end
    local C = {}
    for i = 0, 7 do
        C[i] = { pt(i % 2 == 0 and x1 or x2, math.floor(i / 2) % 2 == 0 and y1 or y2, math.floor(i / 4) == 0 and z1 or z2) }
    end
    local edges = { {0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7} }
    for _, e in ipairs(edges) do
        local a, b = C[e[1]], C[e[2]]
        line(a[1], a[2], a[3], b[1], b[2], b[3], color, 2)
    end
end

local function drawCircle(cx, cy, z, r, color)
    local steps = 56
    local px, py = cx + r, cy
    for i = 1, steps do
        local a = i / steps * math.pi * 2
        local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        line(px, py, z, x, y, z, color, 2)
        px, py = x, y
    end
end

addEventHandler("onClientRender", root, function()
    if not E then return end
    local b = E.bounds
    drawCircle(b.x, b.y, b.z - 0.95, b.r, tocolor(76, 155, 245, 140))
    drawCircle(b.x, b.y, b.z - 0.95, b.door, tocolor(229, 72, 77, 200))

    for _, s in ipairs(selectedList()) do drawBox(s.obj, tocolor(245, 165, 36, 255)) end

    -- rejilla alrededor del punto de trabajo
    local fx, fy, fz
    if E.ghost and E.ghost.t then fx, fy, fz = E.ghost.t.x, E.ghost.t.y, b.z - 0.97
    elseif E.drag then fx, fy, fz = E.drag.items[1].after.x, E.drag.items[1].after.y, b.z - 0.97 end
    if fx and E.grid >= 0.1 then
        local g, n = E.grid, math.floor(2.5 / E.grid)
        local cx, cy = snap(fx, g), snap(fy, g)
        for i = -n, n do
            local a = clamp(255 - math.abs(i) * (255 / (n + 1)), 20, 150)
            line(cx + i * g, cy - n * g, fz, cx + i * g, cy + n * g, fz, tocolor(255, 255, 255, a), 1)
            line(cx - n * g, cy + i * g, fz, cx + n * g, cy + i * g, fz, tocolor(255, 255, 255, a), 1)
        end
    end

    -- ocultar objetos originales: resalta el que apunta el cursor
    if E.tool == "hide" and E.worldHit then
        local h = E.worldHit
        dxDrawLine3D(h.x - 0.4, h.y, h.z, h.x + 0.4, h.y, h.z, tocolor(229, 72, 77), 3)
        dxDrawLine3D(h.x, h.y - 0.4, h.z, h.x, h.y + 0.4, h.z, tocolor(229, 72, 77), 3)
        dxDrawLine3D(h.x, h.y, h.z - 0.4, h.x, h.y, h.z + 0.4, tocolor(229, 72, 77), 3)
        local sx, sy = getScreenFromWorldPosition(h.x, h.y, h.z + 0.5)
        if sx then
            local name = engineGetModelNameFromID(h.model) or ("modelo " .. h.model)
            dxDrawText("Clic para ocultar: " .. name, sx - 150, sy - 12, sx + 150, sy + 12, tocolor(255, 255, 255), 1.1, "default-bold", "center", "center")
        end
    end
    if E.tool == "hide" and E.worldBlocked then
        local h = E.worldBlocked
        local sx, sy = getScreenFromWorldPosition(h.x, h.y, h.z + 0.3)
        if sx then
            dxDrawText("Estructura de la casa: no se puede ocultar", sx - 200, sy - 12, sx + 200, sy + 12, tocolor(255, 140, 140), 1.1, "default-bold", "center", "center")
        end
    end

    -- caja de seleccion
    if E.box then
        local cx, cy = getCursorPosition()
        if cx then
            local ax, ay = cx * screenW, cy * screenH
            local x, y = math.min(E.box.x, ax), math.min(E.box.y, ay)
            local w, h = math.abs(ax - E.box.x), math.abs(ay - E.box.y)
            dxDrawRectangle(x, y, w, h, tocolor(245, 165, 36, 40))
            dxDrawRectangle(x, y, w, 1, tocolor(245, 165, 36, 220)); dxDrawRectangle(x, y + h, w, 1, tocolor(245, 165, 36, 220))
            dxDrawRectangle(x, y, 1, h, tocolor(245, 165, 36, 220)); dxDrawRectangle(x + w, y, 1, h, tocolor(245, 165, 36, 220))
        end
    end

    -- recuadro del mueble fantasma (verde = valido, rojo = no) aunque el shader de color falle
    if E.ghost and E.ghost.t and isElement(E.ghost.obj) then
        drawBox(E.ghost.obj, E.ghost.valid and tocolor(90, 230, 130, 255) or tocolor(235, 80, 80, 255))
        local sx, sy = getScreenFromWorldPosition(E.ghost.t.x, E.ghost.t.y, E.ghost.t.z + 1.4)
        if sx then
            local msg = E.ghost.valid and "Clic: colocar" or "Fuera de la zona o bloquea la puerta"
            if E.ghost.lockAxis then msg = "Eje " .. E.ghost.lockAxis:upper() .. " bloqueado" end
            dxDrawText(msg, sx - 160 + 1, sy + 1, sx + 160 + 1, sy + 21, tocolor(0, 0, 0, 230), 1, "default-bold", "center", "top")
            dxDrawText(msg, sx - 160, sy, sx + 160, sy + 20, E.ghost.valid and tocolor(220, 255, 230) or tocolor(255, 180, 180), 1, "default-bold", "center", "top")
        end
        -- linea del eje bloqueado
        if E.ghost.lockAxis and E.ghost.lock then
            local a, L = AXES[E.ghost.lockAxis], E.ghost.lock
            local c = AXCOL[E.ghost.lockAxis]
            line(L.ax - a[1] * 12, L.ay - a[2] * 12, L.az - a[3] * 12, L.ax + a[1] * 12, L.ay + a[2] * 12, L.az + a[3] * 12, tocolor(c[1], c[2], c[3], 220), 2)
        end
    end

    -- eje bloqueado al arrastrar un mueble
    if E.drag and E.drag.lockAxis then
        local f = E.drag.items[1].after
        local a, c = AXES[E.drag.lockAxis], AXCOL[E.drag.lockAxis]
        line(f.x - a[1] * 12, f.y - a[2] * 12, f.z - a[3] * 12, f.x + a[1] * 12, f.y + a[2] * 12, f.z + a[3] * 12, tocolor(c[1], c[2], c[3], 220), 2)
    end

    -- gizmo de la seleccion
    if E.tool == "select" and not E.ghost and not E.drag then
        local ox, oy, oz = gizmoOrigin()
        if ox then
            local L = E.gdrag and E.gdrag.L or gizmoLen()
            for axis, a in pairs(AXES) do
                local c = AXCOL[axis]
                local active = (E.gdrag and E.gdrag.axis == axis) or (not E.gdrag and E.gizmoHover == axis)
                local col = active and tocolor(255, 224, 80, 255) or tocolor(c[1], c[2], c[3], 235)
                local w = active and 5 or 3
                if E.gizmo == "rotate" then
                    local px, py, pz
                    for i = 0, 48 do
                        local x, y, z = ringPoint(ox, oy, oz, axis, i / 48 * math.pi * 2, L * 0.85)
                        if px then line(px, py, pz, x, y, z, col, w) end
                        px, py, pz = x, y, z
                    end
                else
                    local tx, ty, tz = ox + a[1] * L, oy + a[2] * L, oz + a[3] * L
                    line(ox, oy, oz, tx, ty, tz, col, w)
                    if E.gizmo == "move" then
                        -- punta de flecha
                        local b = RING_BASIS[axis]
                        for k = 0, 3 do
                            local ang = k * math.pi / 2
                            local c1, s1 = math.cos(ang) * L * 0.07, math.sin(ang) * L * 0.07
                            line(tx, ty, tz, tx - a[1] * L * 0.2 + b[1][1] * c1 + b[2][1] * s1, ty - a[2] * L * 0.2 + b[1][2] * c1 + b[2][2] * s1,
                                tz - a[3] * L * 0.2 + b[1][3] * c1 + b[2][3] * s1, col, w)
                        end
                    else
                        -- cubo al final del eje (escala)
                        local h = L * 0.06
                        for _, o in ipairs({ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }) do
                            line(tx - o[1] * h, ty - o[2] * h, tz - o[3] * h, tx + o[1] * h, ty + o[2] * h, tz + o[3] * h, col, w + 2)
                        end
                    end
                    local sx, sy = getScreenFromWorldPosition(tx + a[1] * 0.2, ty + a[2] * 0.2, tz + a[3] * 0.2)
                    if sx then dxDrawText(axis:upper(), sx - 10, sy - 10, sx + 10, sy + 10, col, 1.1, "default-bold", "center", "center") end
                end
            end
        end
    end

    -- lectura numerica mientras se arrastra
    local info = (E.gdrag and E.gdrag.info) or nil
    if info then
        dxDrawText(info, (L_W + screenW - R_W) / 2 - 200 + 1, 81, (L_W + screenW - R_W) / 2 + 200 + 1, 101, tocolor(0, 0, 0, 230), 1.3, "default-bold", "center", "top")
        dxDrawText(info, (L_W + screenW - R_W) / 2 - 200, 80, (L_W + screenW - R_W) / 2 + 200, 100, tocolor(255, 224, 80), 1.3, "default-bold", "center", "top")
    end

    -- estado y avisos grandes, centrados entre los paneles
    local cx = (L_W + screenW - R_W) / 2
    local status = ("Cuenta: $%d  ·  Capacidad %d/%d  ·  %s"):format(E.money or 0, E.weight or 0, E.limit or 0,
        E.ghost and ("Colocando: " .. E.ghost.def.name) or (E.tool == "hide" and "Ocultar objeto original" or "Elige un mueble del catálogo"))
    dxDrawText(status, cx - 300 + 1, 71, cx + 300 + 1, 91, tocolor(0, 0, 0, 230), 1, "default-bold", "center", "top")
    dxDrawText(status, cx - 300, 70, cx + 300, 90, tocolor(255, 255, 255, 235), 1, "default-bold", "center", "top")
    if E.flash and getTickCount() - E.flash.tick < 4500 then
        local col = E.flash.kind == "error" and tocolor(255, 120, 120) or (E.flash.kind == "warning" and tocolor(255, 210, 110) or tocolor(255, 255, 255))
        dxDrawText(E.flash.text, cx - 400 + 2, 111, cx + 400 + 2, 151, tocolor(0, 0, 0, 240), 1.25, "default-bold", "center", "top", true, true)
        dxDrawText(E.flash.text, cx - 400, 110, cx + 400, 150, col, 1.25, "default-bold", "center", "top", true, true)
    end

    -- ayuda en pantalla
    local help = "RMB orbitar · WASD mover · Mayús: sin rejilla · X/Y/Z: bloquear eje · 4/5/6 mover/girar/escalar · Q/E girar · Ctrl+Z/Y · F4 terminar"
    dxDrawText(help, L_W + 11, screenH - 29, screenW - R_W + 1, screenH - 9, tocolor(0, 0, 0, 220), 1, "default-bold", "center", "center")
    dxDrawText(help, L_W + 10, screenH - 30, screenW - R_W, screenH - 10, tocolor(255, 255, 255, 235), 1, "default-bold", "center", "center")
end)

----------------------------------------------------------------
-- Raton
----------------------------------------------------------------
local lastAx, lastAy = 0, 0

addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
    if not E then return end
    local dx, dy = ax - lastAx, ay - lastAy
    lastAx, lastAy = ax, ay
    if E.cam.orbiting then
        E.cam.yaw = E.cam.yaw - dx * 0.006
        E.cam.pitch = clamp(E.cam.pitch + dy * 0.25, 4, 89)
        E.cam.rmbMoved = (E.cam.rmbMoved or 0) + math.abs(dx) + math.abs(dy)
    end
    if E.tool == "hide" and not overUI() then
        local hit = castFromCursor(nil, true)
        local model = hit and not hit.plane and hit[12]
        if model and model > 0 and not (hit[5] and getElementData(hit[5], "rp:furn", false)) then
            local info = { model = model, x = hit[13] or hit[2], y = hit[14] or hit[3], z = hit[15] or hit[4] }
            -- solo mobiliario: ocultar una pared o un suelo dejaria la casa sin estructura
            if FURN_DEFAULT_PROP_IDS[model] then E.worldHit, E.worldBlocked = info, nil
            else E.worldHit, E.worldBlocked = nil, info end
        else
            E.worldHit, E.worldBlocked = nil, nil
        end
    end
end)

local function boxSelect(x1, y1, x2, y2, additive)
    local minX, maxX, minY, maxY = math.min(x1, x2), math.max(x1, x2), math.min(y1, y2), math.max(y1, y2)
    if not additive then E.sel = {} end
    for _, obj in ipairs(FurnCore.objects()) do
        local sx, sy = projectCenter(obj)
        if sx and sx >= minX and sx <= maxX and sy >= minY and sy <= maxY then
            local d = getElementData(obj, "rp:furn", false)
            E.sel[d.id] = true
        end
    end
    markDirty()
end

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not E then return end
    if button == "right" then
        if state == "down" then
            if overUI() then return end
            E.cam.orbiting, E.cam.rmbMoved = true, 0
        else
            local wasOrbit = E.cam.orbiting
            E.cam.orbiting = false
            -- clic derecho sin arrastrar: suelta el mueble o la seleccion
            if wasOrbit and (E.cam.rmbMoved or 0) < 6 then
                if E.ghost then destroyGhost() E.tool = "select" elseif next(E.sel) then clearSelection() end
                markDirty()
            end
        end
        return
    end
    if button ~= "left" then return end

    if state == "up" then
        if E.gdrag then
            endGizmoDrag()
        elseif E.drag then
            local d = E.drag
            E.drag = nil
            for _, it in ipairs(d.items) do setElementCollisionsEnabled(it.obj, true) end
            if d.moved then commitTransforms(d.items) else
                for _, it in ipairs(d.items) do setElementPosition(it.obj, it.before.x, it.before.y, it.before.z) end
            end
        elseif E.box then
            local b = E.box
            E.box = nil
            if math.abs(ax - b.x) > 6 or math.abs(ay - b.y) > 6 then boxSelect(b.x, b.y, ax, ay, b.additive) end
        end
        return
    end

    -- state == "down"
    if overUI() then return end
    local shift = getKeyState("lshift") or getKeyState("rshift")

    -- un clic en el mundo siempre devuelve el foco al juego (si no, el modo de texto bloquea atajos)
    releaseFocus()
    dbg(("clic en el mundo: herramienta=%s fantasma=%s posicion=%s valido=%s"):format(
        tostring(E.tool), E.ghost and E.ghost.key or "no", E.ghost and E.ghost.t and "si" or "no", tostring(E.ghost and E.ghost.valid)))

    -- si se perdio un "soltar" anterior, se limpia el estado para que el clic nuevo funcione
    if E.gdrag then endGizmoDrag() end
    if E.drag then
        for _, it in ipairs(E.drag.items) do if isElement(it.obj) then setElementCollisionsEnabled(it.obj, true) end end
        E.drag = nil
    end
    E.box = nil

    if E.tool == "place" and E.ghost then return placeGhost() end

    if E.gizmoHover and E.tool == "select" then return startGizmoDrag(E.gizmoHover) end

    if E.tool == "hide" then
        if E.worldBlocked and not E.worldHit then notify("Eso es parte de la estructura de la casa y no se puede ocultar.", "warning") end
        if E.worldHit then
            local entry = { m = E.worldHit.model, x = round3(E.worldHit.x), y = round3(E.worldHit.y), z = round3(E.worldHit.z) }
            triggerServerEvent("rp:furn:hideProps", resourceRoot, { entry })
            pushUndo({ type = "hide", items = { entry } })
            E.worldHit = nil
        end
        return
    end

    local obj = pickFurniture(furnitureHit(nil))
    if obj then
        local d = getElementData(obj, "rp:furn", false)
        if not E.sel[d.id] or shift then selectObj(obj, shift) end
        if E.sel[d.id] and not shift then
            -- empieza el arrastre de la seleccion
            local items = selectionItems()
            if #items > 0 then
                local cx, cy, cz = centroid(items)
                local x1, y1, z1, x2, y2, z2 = cursorRay()
                local px, py = cx, cy
                if x1 and z2 < z1 then
                    local t = (z1 - cz) / (z1 - z2)
                    px, py = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
                end
                for _, it in ipairs(items) do setElementCollisionsEnabled(it.obj, false) end
                E.drag = { items = items, planeZ = cz, startX = px, startY = py, dz = 0, moved = false }
            end
        end
    else
        E.box = { x = ax, y = ay, additive = shift }
        if not shift then clearSelection() end
    end
end)

----------------------------------------------------------------
-- Teclado
----------------------------------------------------------------
local ARROWS = { arrow_u = { 0, 1 }, arrow_d = { 0, -1 }, arrow_l = { -1, 0 }, arrow_r = { 1, 0 } }

addEventHandler("onClientKey", root, function(key, press)
    if not E or not press then return end
    if E.typing then return end
    local ctrl = getKeyState("lctrl") or getKeyState("rctrl")

    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        if overUI() then return end
        local dir = key == "mouse_wheel_up" and 1 or -1
        if getKeyState("lalt") then
            if E.ghost then E.ghost.hOff = E.ghost.hOff + dir * math.max(0.05, E.grid) else nudge(0, 0, dir * math.max(0.05, E.grid)) end
        else
            E.cam.dist = clamp(E.cam.dist * (dir > 0 and 0.88 or 1.14), 2.5, 34)
        end
        return
    end

    if key == "escape" then
        if E.ghost then destroyGhost() E.tool = "select" markDirty() cancelEvent() return end
        if E.tool == "hide" then E.tool = "select" markDirty() cancelEvent() return end
        if next(E.sel) then clearSelection() cancelEvent() return end
        return
    end

    local function rotAmount(sign) return sign * E.rotStep end
    if key == "q" or key == "e" then
        local sign = key == "e" and 1 or -1
        if E.ghost then E.ghost.rz = (E.ghost.rz + rotAmount(sign)) % 360 else rotateSelection(rotAmount(sign)) end
    elseif key == "r" then
        if E.ghost then E.ghost.rz = (E.ghost.rz + 180) % 360 E.ghost.flip = (E.ghost.flip + 180) % 360 else rotateSelection(180) end
    elseif key == "pgup" or key == "pgdn" then
        local dz = (key == "pgup" and 1 or -1) * math.max(0.05, E.grid)
        if E.ghost then E.ghost.hOff = E.ghost.hOff + dz else nudge(0, 0, dz) end
    elseif ARROWS[key] and not E.ghost then
        local a = ARROWS[key]
        local step = math.max(0.05, E.grid)
        -- las flechas siguen la orientacion de la camara
        local fx, fy = -math.cos(E.cam.yaw), -math.sin(E.cam.yaw)
        local rx, ry = fy, -fx
        nudge((fx * a[2] + rx * a[1]) * step, (fy * a[2] + ry * a[1]) * step, 0)
        cancelEvent()
    elseif key == "delete" then
        removeSelection("stock")
    elseif ctrl and key == "z" then undo()
    elseif ctrl and key == "y" then redo()
    elseif ctrl and key == "d" then duplicateSelection()
    elseif key == "tab" then
        local idx = 1
        for i, g in ipairs(FURN_GRIDS) do if g == E.grid then idx = i end end
        E.grid = FURN_GRIDS[idx % #FURN_GRIDS + 1]
        markDirty()
        cancelEvent()
    elseif key == "4" then E.gizmo = "move"
    elseif key == "5" then E.gizmo = "rotate"
    elseif key == "6" then E.gizmo = "scale"
    elseif key == "1" then setView(1)
    elseif key == "2" then setView(2)
    elseif key == "3" then setView(3)
    end
    markDirty()
end)

----------------------------------------------------------------
-- Ordenes desde los paneles
----------------------------------------------------------------
local function setFieldOnSelection(name, value)
    value = tonumber(value)
    if not value then return end
    local items = selectionItems()
    if #items == 0 then return end
    local it = items[1]
    local def = defOf(it.obj)
    local smax = def and def.struct and FURN.SCALE_STRUCT_MAX or FURN.SCALE_MAX
    if name == "sx" or name == "sy" or name == "sz" then value = clamp(value, FURN.SCALE_MIN, smax) end
    it.after[name] = value
    applyLocal(it)
    commitTransforms({ it })
end

addEventHandler("rp:furn:ui:cmd", root, function(cmd, a, b, c)
    if not E then return end
    if cmd == "typing" then E.typing = a and true or false guiSetInputEnabled(E.typing)
    elseif cmd == "pick" then
        if type(a) == "string" and FURN_ITEMS[a] then
            clearSelection()
            setGhost(a)
            releaseFocus()
            dbg(("elegido '%s' (fantasma %s)"):format(a, E.ghost and "creado" or "NO creado"))
            if E.ghost then notify("Mueble elegido: " .. FURN_ITEMS[a].name .. ". Apunta al suelo y haz clic para colocarlo.", "info")
            else notify("No se pudo crear el mueble elegido.", "error") end
        else
            dbg("pick con clave no valida: " .. tostring(a))
        end
    elseif cmd == "tool" then
        E.tool = a == "hide" and "hide" or "select"
        if E.tool == "hide" then destroyGhost() E.worldHit = nil end
    elseif cmd == "grid" then E.grid = tonumber(a) or 0
    elseif cmd == "gizmo" then E.gizmo = (a == "rotate" or a == "scale") and a or "move"
    elseif cmd == "thumbs" then FurnThumbs.request(tostring(a or ""))
    elseif cmd == "rotstep" then E.rotStep = tonumber(a) or 15
    elseif cmd == "view" then setView(tonumber(a) or 2)
    elseif cmd == "field" then setFieldOnSelection(tostring(a), b)
    elseif cmd == "paint" then
        local color = tonumber(a)
        local mat = type(b) == "string" and b or nil
        if E.ghost and not next(E.sel) then
            if color ~= nil then E.paintColor = color >= 0 and color or nil end
            if mat ~= nil then E.paintMat = mat ~= "" and mat or nil end
        else
            paintSelection(color, mat)
        end
    elseif cmd == "undo" then undo()
    elseif cmd == "redo" then redo()
    elseif cmd == "delete" then removeSelection("stock")
    elseif cmd == "sell" then removeSelection("sell")
    elseif cmd == "duplicate" then duplicateSelection()
    elseif cmd == "rotate" then rotateSelection(tonumber(a) or 90)
    elseif cmd == "selectall" then
        E.sel = {}
        for _, obj in ipairs(FurnCore.objects()) do E.sel[getElementData(obj, "rp:furn", false).id] = true end
    elseif cmd == "clearall" then E.undo, E.redo = {}, {} triggerServerEvent("rp:furn:clearAll", resourceRoot)
    elseif cmd == "scan" then startScan()
    elseif cmd == "unhide" then triggerServerEvent("rp:furn:restoreProp", resourceRoot, tonumber(a) or 0)
    elseif cmd == "bpSave" then triggerServerEvent("rp:furn:bpSave", resourceRoot, tostring(a or ""))
    elseif cmd == "bpApply" then E.undo, E.redo = {}, {} triggerServerEvent("rp:furn:bpApply", resourceRoot, tonumber(a), b and true or false)
    elseif cmd == "bpDelete" then triggerServerEvent("rp:furn:bpDelete", resourceRoot, tonumber(a))
    elseif cmd == "memberAdd" then triggerServerEvent("rp:furn:memberAdd", resourceRoot, tonumber(a))
    elseif cmd == "memberRemove" then triggerServerEvent("rp:furn:memberRemove", resourceRoot, tonumber(a))
    elseif cmd == "finish" then FurnEditor.requestStop(true)
    elseif cmd == "cancel" then FurnEditor.requestStop(false)
    end
    markDirty()
end)

addEventHandler("rp:furn:ui:ready", root, function(name)
    if not E or not panels[name] then return end
    local cats = {}
    for _, c in ipairs(FURN_CATEGORIES) do cats[#cats + 1] = c end
    local payload = { items = name == "left" and furnPublicCatalog() or {}, cats = cats, swatches = FURN_SWATCHES,
                      mats = FURN_MATERIALS, grids = FURN_GRIDS, rots = FURN_ROT_STEPS }
    panelJS(name, ("FURN.init(%s[0])"):format(toJSON(payload, true)))
    markDirty()
end)

----------------------------------------------------------------
-- Respuestas del servidor
----------------------------------------------------------------
addEventHandler("rp:furn:ack", resourceRoot, function(ref, ok, data)
    dbg(("respuesta del servidor a la colocacion #%s: %s %s"):format(tostring(ref), ok and "OK" or "RECHAZADA", type(data) == "string" and data or ""))
    if not E then return end
    local cb = E.pending[ref]
    E.pending[ref] = nil
    if not ok then
        if type(data) == "string" then notify(data, "warning") end
        triggerServerEvent("rp:furn:requestStock", resourceRoot)
        return
    end
    if cb then cb(ok, data) end
    markDirty()
end)

addEventHandler("rp:furn:sync", resourceRoot, function(s)
    if not E then return end
    E.weight, E.limit, E.money, E.stock, E.count = s.weight, s.limit, s.money, s.stock or {}, s.count or 0
    markDirty()
end)

addEventHandler("rp:furn:updated", resourceRoot, function(applied)
    if not E then return end
    local ok = {}
    for _, id in ipairs(applied or {}) do ok[id] = true end
    for fid, prev in pairs(E.inflight) do
        if not ok[fid] and prev then
            local obj = FurnCore.byId(fid)
            if obj then
                setElementPosition(obj, prev.x, prev.y, prev.z)
                setElementRotation(obj, prev.rx, prev.ry, prev.rz)
                setObjectScale(obj, prev.sx, prev.sy, prev.sz)
            end
        end
    end
    E.inflight = {}
    markDirty()
end)

addEventHandler("rp:furn:removed", resourceRoot, function(ids)
    if not E then return end
    for _, id in ipairs(ids or {}) do E.sel[id] = nil end
    markDirty()
end)

addEventHandler("rp:furn:members", resourceRoot, function(list) if E then E.members = list markDirty() end end)
addEventHandler("rp:furn:blueprints", resourceRoot, function(list) if E then E.blueprints = list markDirty() end end)
addEventHandler("rp:furn:reload", resourceRoot, function() if E then E.sel = {} markDirty() end end)
addEventHandler("rp:furn:props", resourceRoot, function(list) if E then E.removed = list or {} markDirty() end end)

addEventHandler("rp:furn:buildOn", resourceRoot, function(data) FurnEditor.start(data) end)
addEventHandler("rp:furn:buildOff", resourceRoot, function() FurnEditor.stop(false) end)

----------------------------------------------------------------
-- Entrar y salir
----------------------------------------------------------------
function FurnEditor.start(data)
    if E then return end
    local b = data.bounds
    local cx, cy, cz = getElementPosition(localPlayer)
    E = {
        bounds = b, name = data.name, isOwner = data.isOwner, money = data.money, stock = data.stock or {},
        weight = data.weight, limit = data.limit, count = 0, removed = data.removed or {}, members = data.members or {},
        blueprints = data.blueprints or {}, tool = "select", gizmo = "move", grid = 0.25, rotStep = 15, view = 2, sel = {}, undo = {}, redo = {},
        alias = {}, pending = {}, ref = 0, placed = {}, inflight = {}, snapshots = {},
        paintColor = nil, paintMat = nil, typing = false,
        cam = { px = cx, py = cy, pz = cz, yaw = math.pi / 2, pitch = 50, dist = 9, x = 0, y = 0, z = 0, orbiting = false },
    }
    FurnEditor.active = true
    FurnCore.building = true
    local n = 0
    for _ in pairs(FurnCore.objects()) do n = n + 1 end
    E.count = n
    toggleAllControls(false, true, false)
    showCursor(true)
    createPanels()
    setView(2)
    markDirty()
    notify("Modo construccion. F4 para terminar.", "info")
end

function FurnEditor.stop(silent)
    if not E then return end
    destroyGhost()
    E = nil
    FurnEditor.active = false
    FurnCore.building = false
    destroyPanels()
    setCameraTarget(localPlayer)
    toggleAllControls(true, true, true)
    showCursor(false)
    guiSetInputEnabled(false)
end

function FurnEditor.requestStop(commit)
    if not E then return end
    triggerServerEvent("rp:furn:endBuild", resourceRoot, commit)
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if E then FurnEditor.stop(true) end
end)

addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, function()
    if E then FurnEditor.requestStop(true) end
end)
