--[[
    rp_mapeditor / c_editor.lua
    Núcleo del editor en el cliente: sesión, filas del borrador, operaciones al servidor (en cola),
    deshacer/rehacer, selección, portapapeles, quitados del mapa en el borrador, modo prueba y
    acciones de los paneles. La entrada (ratón, teclas, gizmo) está en c_input.lua y el dibujo en c_draw.lua.

    Estado compartido entre archivos: MEEditor.E (nil fuera del editor).
]]

MEEditor = { active = false, E = nil }

local screenW, screenH = guiGetScreenSize()
local clipboard = nil          -- sobrevive entre proyectos: copiar en uno y pegar en otro
local favorites, recents = {}, {}
local PREFS_FILE = "@prefs.json"

addEvent("rp:me:enter", true)
addEvent("rp:me:leave", true)
addEvent("rp:me:rows", true)
addEvent("rp:me:locks", true)
addEvent("rp:me:editors", true)
addEvent("rp:me:project", true)
addEvent("rp:me:settings", true)
addEvent("rp:me:reload", true)
addEvent("rp:me:versions", true)
addEvent("rp:me:exported", true)
addEvent("rp:me:browser", true)
addEvent("rp:me:openBrowser", true)

local function E() return MEEditor.E end

function MEEditor.notify(text, kind) exports.rp_notify:notify(text, kind or "info") end
function MEEditor.sound(name) playSound("html/sounds/" .. name .. ".ogg") end
function MEEditor.isTyping() return MEUI.isTyping() end

----------------------------------------------------------------
-- Preferencias locales (favoritos, recientes, tutorial)
----------------------------------------------------------------
local prefs = { tutorial = false }

local function loadPrefs()
    if not fileExists(PREFS_FILE) then return end
    local fh = fileOpen(PREFS_FILE, true)
    if not fh then return end
    local txt = fileRead(fh, fileGetSize(fh))
    fileClose(fh)
    local t = fromJSON(txt)
    if type(t) == "table" then
        prefs = t
        favorites = type(t.favorites) == "table" and t.favorites or {}
        recents = type(t.recents) == "table" and t.recents or {}
    end
end

function MEEditor.savePrefs()
    prefs.favorites, prefs.recents = favorites, recents
    if fileExists(PREFS_FILE) then fileDelete(PREFS_FILE) end
    local fh = fileCreate(PREFS_FILE)
    if not fh then return end
    fileWrite(fh, toJSON(prefs, true))
    fileClose(fh)
end

function MEEditor.prefs() return prefs end

----------------------------------------------------------------
-- Utilidades de filas
----------------------------------------------------------------
local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end
MEEditor.copy = copy

function MEEditor.resolve(id)
    local e = E()
    local n = 0
    while e and e.alias[id] and n < 50 do id, n = e.alias[id], n + 1 end
    return id
end

function MEEditor.draftDim() local e = E() return e and (MAPEDIT.DIMENSION_BASE + e.project.id) or -1 end

-- Elemento del servidor de una fila (búsqueda cacheada por "rp:me:id")
function MEEditor.el(id)
    local e = E()
    if not e then return nil end
    local el = e.cache[id]
    if isElement(el) and getElementData(el, "rp:me:id") == id then return el end
    local now = getTickCount()
    if not e.cacheDirty and now - e.lastScan < 400 then return nil end
    e.cache, e.cacheDirty, e.lastScan = {}, false, now
    local dim = MEEditor.draftDim()
    for _, t in ipairs({ "object", "vehicle", "ped", "marker", "pickup" }) do
        for _, x in ipairs(getElementsByType(t, root)) do
            local rid = getElementData(x, "rp:me:id")
            if rid and getElementDimension(x) == dim then e.cache[rid] = x end
        end
    end
    el = e.cache[id]
    return isElement(el) and el or nil
end

-- Transformación de una fila: { x, y, z, rx, ry, rz, sx, sy, sz }
function MEEditor.T(row)
    local s = row.props and row.props.scale
    return { x = row.x, y = row.y, z = row.z, rx = row.rx, ry = row.ry, rz = row.rz,
             sx = s and s[1] or 1, sy = s and s[2] or 1, sz = s and s[3] or 1 }
end

function MEEditor.rowWithT(row, t)
    local r = copy(row)
    r.x, r.y, r.z, r.rx, r.ry, r.rz = t.x, t.y, t.z, t.rx % 360, t.ry % 360, t.rz % 360
    if r.etype == "object" then
        r.props = r.props or {}
        if math.abs(t.sx - 1) < 1e-3 and math.abs(t.sy - 1) < 1e-3 and math.abs(t.sz - 1) < 1e-3 then r.props.scale = nil
        else r.props.scale = { t.sx, t.sy, t.sz } end
    end
    return r
end

-- Vista previa local de una transformación (sin servidor)
function MEEditor.applyLocal(id, t)
    local e = E()
    e.preview[id] = t
    local el = MEEditor.el(id)
    if not el then return end
    setElementPosition(el, t.x, t.y, t.z)
    if getElementType(el) == "ped" then setElementRotation(el, 0, 0, t.rz, "default", true)
    elseif getElementType(el) ~= "marker" and getElementType(el) ~= "pickup" then setElementRotation(el, t.rx, t.ry, t.rz) end
    if getElementType(el) == "object" then setObjectScale(el, t.sx, t.sy, t.sz) end
end

function MEEditor.posOf(id)
    local e = E()
    local t = e.preview[id]
    if t then return t.x, t.y, t.z end
    local r = e.rows[id]
    if r then return r.x, r.y, r.z end
end

function MEEditor.label(row)
    if not row then return "?" end
    local p = row.props or {}
    if row.etype == "object" then return (engineGetModelNameFromID(row.model) or "objeto") .. " (" .. row.model .. ")"
    elseif row.etype == "vehicle" then return (getVehicleNameFromModel(row.model) or "vehículo") .. " (" .. row.model .. ")"
    elseif row.etype == "ped" then return "Ped skin " .. row.model
    elseif row.etype == "marker" then return "Marcador " .. (p.label or p.mtype or "")
    elseif row.etype == "pickup" then return ({ [0] = "Pickup de vida", [1] = "Pickup de chaleco", [2] = "Pickup de arma", [3] = "Pickup" })[p.ptype or 0] or "Pickup"
    elseif row.etype == "point" then return "Punto «" .. (p.name or "punto") .. "»"
    elseif row.etype == "removal" then return "Quitado: " .. (engineGetModelNameFromID(row.model) or row.model)
    end
    return row.etype
end

----------------------------------------------------------------
-- Cola de operaciones al servidor (el servidor limita la frecuencia)
----------------------------------------------------------------
local function rawOf(row, ref)
    return { id = row.id and row.id > 0 and row.id or nil, ref = ref, etype = row.etype, model = row.model,
             x = row.x, y = row.y, z = row.z, rx = row.rx, ry = row.ry, rz = row.rz, props = row.props or {} }
end

function MEEditor.send(kind, list)
    local e = E()
    if not e or #list == 0 then return end
    for i = 1, #list, MAPEDIT.MAX_BATCH do
        local chunk = {}
        for j = i, math.min(#list, i + MAPEDIT.MAX_BATCH - 1) do chunk[#chunk + 1] = list[j] end
        e.queue[#e.queue + 1] = { kind, chunk }
    end
end

addEventHandler("onClientRender", root, function()
    local e = E()
    if not e or #e.queue == 0 then return end
    local now = getTickCount()
    if now - e.lastSend < 90 then return end
    e.lastSend = now
    local op = table.remove(e.queue, 1)
    triggerServerEvent("rp:me:op", resourceRoot, op[1], op[2])
end)

-- Crea filas nuevas. tempIds: ids negativos (o antiguos) que el ack convierte en el id real
local function sendCreate(rows, select)
    local e = E()
    local list = {}
    for _, row in ipairs(rows) do
        e.refN = e.refN + 1
        local ref = e.token .. ":" .. e.refN
        e.pendingRefs[ref] = { alias = row.id, select = select }
        list[#list + 1] = rawOf(row, ref)
    end
    MEEditor.send("create", list)
end

local function sendUpdate(rows)
    local list = {}
    for _, row in ipairs(rows) do
        local r = copy(row)
        r.id = MEEditor.resolve(row.id)
        if r.id and r.id > 0 and E().rows[r.id] then list[#list + 1] = rawOf(r) end
    end
    MEEditor.send("update", list)
end

local function sendDelete(ids)
    local list = {}
    for _, id in ipairs(ids) do
        id = MEEditor.resolve(id)
        if id and id > 0 and E().rows[id] then list[#list + 1] = id end
    end
    MEEditor.send("delete", list)
end

----------------------------------------------------------------
-- Deshacer / rehacer
----------------------------------------------------------------
local function pushUndo(entry)
    local e = E()
    e.undo[#e.undo + 1] = entry
    if #e.undo > 100 then table.remove(e.undo, 1) end
    e.redo = {}
    MEEditor.pushState()
end

local function applyEntry(entry, undo)
    if entry.type == "update" then
        sendUpdate(undo and entry.before or entry.after)
    elseif entry.type == "create" then
        if undo then
            local ids = {}
            for _, r in ipairs(entry.rows) do ids[#ids + 1] = r.id end
            sendDelete(ids)
        else
            sendCreate(entry.rows, false)
        end
    elseif entry.type == "delete" then
        if undo then sendCreate(entry.rows, false) else
            local ids = {}
            for _, r in ipairs(entry.rows) do ids[#ids + 1] = r.id end
            sendDelete(ids)
        end
    end
end

function MEEditor.undo()
    local e = E()
    local entry = table.remove(e.undo)
    if not entry then return end
    applyEntry(entry, true)
    e.redo[#e.redo + 1] = entry
    MEEditor.sound("scroll_001")
    MEEditor.pushState()
end

function MEEditor.redo()
    local e = E()
    local entry = table.remove(e.redo)
    if not entry then return end
    applyEntry(entry, false)
    e.undo[#e.undo + 1] = entry
    MEEditor.sound("scroll_001")
    MEEditor.pushState()
end

----------------------------------------------------------------
-- Acciones de alto nivel (las usan la entrada y los paneles)
----------------------------------------------------------------
function MEEditor.selectedIds()
    local e = E()
    local out = {}
    for id in pairs(e.sel) do if e.rows[id] then out[#out + 1] = id end end
    table.sort(out)
    return out
end

function MEEditor.lockedByOther(id)
    local e = E()
    return e.locks[tostring(id)] and e.locks[tostring(id)] ~= e.me
end

local selSyncAt = nil
function MEEditor.selectionChanged()
    selSyncAt = getTickCount() + 150
    MEEditor.pushSelection()
end

function MEEditor.clearSelection()
    local e = E()
    if not next(e.sel) then return end
    e.sel = {}
    MEEditor.selectionChanged()
end

function MEEditor.select(id, additive)
    local e = E()
    if not e.rows[id] then return end
    if MEEditor.lockedByOther(id) then
        return MEEditor.notify(("Lo está editando %s."):format(e.locks[tostring(id)]), "warning")
    end
    if not additive then e.sel = {} end
    if additive and e.sel[id] then e.sel[id] = nil else e.sel[id] = true end
    MEEditor.sound("select_002")
    MEEditor.selectionChanged()
end

function MEEditor.selectMany(ids, additive)
    local e = E()
    if not additive then e.sel = {} end
    for _, id in ipairs(ids) do
        if e.rows[id] and not MEEditor.lockedByOther(id) then e.sel[id] = true end
    end
    MEEditor.selectionChanged()
end

-- Confirma transformaciones: items = { { id, before = T, after = T } }
function MEEditor.commitTransforms(items)
    local e = E()
    local before, after = {}, {}
    for _, it in ipairs(items) do
        local row = e.rows[it.id]
        if row then
            before[#before + 1] = MEEditor.rowWithT(row, it.before)
            after[#after + 1] = MEEditor.rowWithT(row, it.after)
        end
    end
    if #after == 0 then return end
    pushUndo({ type = "update", before = before, after = after })
    sendUpdate(after)
end

-- Cambia campos de filas (panel de propiedades): rows = filas completas nuevas
function MEEditor.commitRows(newRows)
    local e = E()
    local before = {}
    for _, r in ipairs(newRows) do
        if e.rows[r.id] then before[#before + 1] = copy(e.rows[r.id]) end
    end
    if #before == 0 then return end
    pushUndo({ type = "update", before = before, after = copy(newRows) })
    sendUpdate(newRows)
end

function MEEditor.createRows(rows, select)
    local e = E()
    local total = 0
    for _ in pairs(e.rows) do total = total + 1 end
    if total + #rows > MAPEDIT.MAX_ELEMENTS then
        return MEEditor.notify(("Límite de %d elementos por proyecto."):format(MAPEDIT.MAX_ELEMENTS), "error")
    end
    for _, r in ipairs(rows) do
        e.tempN = e.tempN - 1
        r.id = e.tempN
    end
    pushUndo({ type = "create", rows = copy(rows) })
    sendCreate(rows, select)
    MEEditor.sound("drop_00" .. math.random(1, 3))
end

function MEEditor.deleteSelection()
    local e = E()
    local ids, rows = {}, {}
    for _, id in ipairs(MEEditor.selectedIds()) do
        ids[#ids + 1] = id
        rows[#rows + 1] = copy(e.rows[id])
    end
    if #ids == 0 then return end
    pushUndo({ type = "delete", rows = rows })
    sendDelete(ids)
    e.sel = {}
    MEEditor.selectionChanged()
    MEEditor.sound("minimize_003")
end

function MEEditor.copySelection()
    local e = E()
    local rows = {}
    for _, id in ipairs(MEEditor.selectedIds()) do rows[#rows + 1] = copy(e.rows[id]) end
    if #rows == 0 then return end
    clipboard = rows
    MEEditor.notify(("Copiados %d elementos."):format(#rows), "info")
end

-- Pega el portapapeles centrado en un punto (o desplazado si no hay punto)
function MEEditor.paste(at)
    if not clipboard or #clipboard == 0 then return MEEditor.notify("El portapapeles está vacío.", "warning") end
    local cx, cy, cz = 0, 0, 0
    for _, r in ipairs(clipboard) do cx, cy, cz = cx + r.x, cy + r.y, cz + r.z end
    cx, cy, cz = cx / #clipboard, cy / #clipboard, cz / #clipboard
    local dx, dy, dz = 1, 1, 0
    if at then dx, dy, dz = at[1] - cx, at[2] - cy, at[3] - cz end
    local rows = {}
    for _, r in ipairs(clipboard) do
        local n = copy(r)
        n.x, n.y, n.z = r.x + dx, r.y + dy, r.z + dz
        rows[#rows + 1] = n
    end
    MEEditor.createRows(rows, true)
end

function MEEditor.duplicateSelection()
    local e = E()
    local rows = {}
    for _, id in ipairs(MEEditor.selectedIds()) do
        local n = copy(e.rows[id])
        if n.etype ~= "removal" then
            local g = e.gridOn and e.grid > 0 and e.grid or 1
            n.x, n.y = n.x + g, n.y + g
            rows[#rows + 1] = n
        end
    end
    if #rows == 0 then return end
    MEEditor.createRows(rows, true)
end

-- Baja la selección hasta el suelo (rayo hacia abajo)
function MEEditor.dropToGround()
    local e = E()
    local items = {}
    for _, id in ipairs(MEEditor.selectedIds()) do
        local row = e.rows[id]
        local el = MEEditor.el(id)
        local t = MEEditor.T(row)
        local hit, _, _, hz = processLineOfSight(t.x, t.y, t.z + 0.5, t.x, t.y, t.z - 200, true, true, false, true, false,
            false, false, false, el)
        if hit then
            local off = 0
            if el and (row.etype == "object" or row.etype == "vehicle") then
                local _, _, z1 = getElementBoundingBox(el)
                off = -(z1 or 0) * (row.etype == "object" and t.sz or 1)
            elseif row.etype == "ped" then off = 1 end
            local a = copy(t)
            a.z = hz + off
            items[#items + 1] = { id = id, before = t, after = a }
        end
    end
    if #items > 0 then MEEditor.commitTransforms(items) end
end

function MEEditor.focusSelection()
    local e = E()
    local ids = MEEditor.selectedIds()
    if #ids == 0 then return end
    local x, y, z = MEEditor.posOf(ids[1])
    MECam.focus(x, y, z + 1, 12)
end

----------------------------------------------------------------
-- Quitados del mapa en el borrador (solo en tu cliente)
----------------------------------------------------------------
local function removalArgs(row)
    local p = row.props or {}
    return row.model, p.lod or 0, p.radius or 1, row.x, row.y, row.z
end

local function applyRemovals()
    local e = E()
    local int = e.project.interior
    for id, row in pairs(e.rows) do
        if row.etype == "removal" and not e.removed[id] then
            local m, lod, r, x, y, z = removalArgs(row)
            removeWorldModel(m, r, x, y, z, int)
            if lod > 0 then removeWorldModel(lod, r, x, y, z, int) end
            e.removed[id] = { m, lod, r, x, y, z, int }
        end
    end
end

local function reapplyLiveRemovals()
    for _, r in ipairs(getElementData(resourceRoot, "rp:me:liveRem") or {}) do
        removeWorldModel(r[1], r[3], r[4], r[5], r[6], r[7])
        if r[2] > 0 then removeWorldModel(r[2], r[3], r[4], r[5], r[6], r[7]) end
    end
end

local function restoreRemoval(id)
    local e = E()
    local a = e.removed[id]
    if not a then return end
    restoreWorldModel(a[1], a[3], a[4], a[5], a[6], a[7])
    if a[2] > 0 then restoreWorldModel(a[2], a[3], a[4], a[5], a[6], a[7]) end
    e.removed[id] = nil
end

local function restoreAllRemovals()
    local e = E()
    for id in pairs(e.removed) do restoreRemoval(id) end
    reapplyLiveRemovals()
end

----------------------------------------------------------------
-- Datos hacia los paneles
----------------------------------------------------------------
local rowsDirty = false

function MEEditor.pushState()
    local e = E()
    if not e then return end
    local n = 0
    for _ in pairs(e.sel) do n = n + 1 end
    local g = MEInput and MEInput.ghost and MEInput.ghost()
    MEUI.push("all", "state", {
        tool = e.tool, gizmo = e.gizmo, localAxes = e.localAxes, grid = e.grid, gridOn = e.gridOn, rotStep = e.rotStep,
        canUndo = #e.undo > 0, canRedo = #e.redo > 0, selCount = n, testing = e.testing,
        speed = math.floor(MECam.speed * 100 + 0.5) / 100, hasClipboard = clipboard ~= nil,
        win = MEUI.isShown("win") and e.winView or false, props = MEUI.isShown("props"),
        placing = g and g.etype or false,
    })
end

function MEEditor.onPanels() MEEditor.pushState() end

-- Ventana flotante de la izquierda: navegador de modelos, opciones de un tipo o lista de elementos.
-- Pulsar el mismo botón otra vez la cierra (como en el editor de MTA)
function MEEditor.openWin(view, toggle)
    local e = E()
    if not e then return end
    if toggle and MEUI.isShown("win") and e.winView == view then
        MEUI.show("win", false)
        return
    end
    e.winView = view
    MEUI.show("win", true)
    MEUI.push("win", "view", view)
    MEEditor.sound("click_002")
    MEEditor.pushState()
end

function MEEditor.closeWin() MEUI.show("win", false) end

-- Propiedades: doble clic sobre algo elegido o Enter
function MEEditor.openProps()
    local e = E()
    if not e or not next(e.sel) then return end
    MEUI.show("props", true)
    MEEditor.pushSelection()
    MEEditor.sound("maximize_003")
end

function MEEditor.pushSelection()
    local e = E()
    if not e then return end
    local rows = {}
    for _, id in ipairs(MEEditor.selectedIds()) do
        local r = copy(e.rows[id])
        r.label = MEEditor.label(r)
        rows[#rows + 1] = r
    end
    if #rows == 0 and MEUI.isShown("props") then MEUI.show("props", false) end
    MEUI.push("props", "selection", rows)
    MEUI.push("win", "selected", MEEditor.selectedIds())
    MEEditor.pushState()
end

local function pushRows()
    local e = E()
    local list = {}
    for id, r in pairs(e.rows) do
        list[#list + 1] = { id = id, etype = r.etype, model = r.model, label = MEEditor.label(r),
                            lock = e.locks[tostring(id)] ~= e.me and e.locks[tostring(id)] or false }
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    MEUI.push("win", "rows", list)
end

local function pushProject()
    local e = E()
    MEUI.push("all", "project", { project = e.project, settings = e.settings, editors = e.editors })
end

addEventHandler("onClientRender", root, function()
    local e = E()
    if not e then return end
    if rowsDirty then rowsDirty = false pushRows() end
    if selSyncAt and getTickCount() >= selSyncAt then
        selSyncAt = nil
        MEEditor.send("select", MEEditor.selectedIds())
        -- "select" vacío también libera: el servidor necesita la lista aunque esté vacía
        if #MEEditor.selectedIds() == 0 then e.queue[#e.queue + 1] = { "select", { 0 } } end
    end
end)

----------------------------------------------------------------
-- Sesión
----------------------------------------------------------------
local function catalogInit()
    local veh = {}
    for m = 400, 611 do
        local n = getVehicleNameFromModel(m)
        if n and n ~= "" then veh[#veh + 1] = { m, n } end
    end
    local peds = {}
    for _, id in ipairs(getValidPedModels()) do peds[#peds + 1] = id end
    local anims = {}
    for _, a in ipairs(MAPEDIT.PED_ANIMS) do anims[#anims + 1] = { a[1], a[2], a[3] } end
    return { vehicles = veh, peds = peds, anims = anims, favorites = favorites, recents = recents }
end

local function startSession(summary, settings, rows, locks)
    local fresh = not MEEditor.E
    if not fresh then restoreAllRemovals() end
    local e = MEEditor.E or {}
    MEEditor.E = e
    e.project, e.settings, e.locks = summary, settings or {}, locks or {}
    e.rows, e.sel, e.preview, e.cache, e.cacheDirty, e.lastScan = {}, {}, {}, {}, true, 0
    e.removed = e.removed or {}
    e.undo, e.redo, e.alias, e.pendingRefs = {}, {}, {}, {}
    e.queue, e.lastSend = e.queue or {}, e.lastSend or 0
    e.refN, e.tempN = e.refN or 0, e.tempN or 0
    e.token = e.token or tostring(math.random(100000, 999999))
    e.me = getPlayerName(localPlayer):gsub("_", " ")
    e.editors = e.editors or {}
    for _, r in ipairs(rows or {}) do e.rows[r.id] = r end
    if fresh then
        e.tool, e.gizmo, e.localAxes = "select", "move", false
        e.grid, e.gridOn, e.rotStep = MAPEDIT.GRID, true, MAPEDIT.ROT_STEP
        e.testing = false
        MEEditor.active = true
        local x, y, z = getElementPosition(localPlayer)
        local _, _, rz = getElementRotation(localPlayer)
        MECam.speed = 1
        MECam.start(x, y, z + 4, -rz, -20)
        MECam.focus(x, y, z, 10)
        exports.rp_hud:setHudHidden("rp_mapeditor", true)
        showCursor(true)
        MEUI.openEditor()
        MEUI.push("all", "catalog", catalogInit())
        MEEditor.sound("maximize_003")
        if MEInput and MEInput.start then MEInput.start() end
        if not prefs.tutorial and METutorial then METutorial.start() end
    end
    applyRemovals()
    MEWorld.applySettings("draft", e.settings)
    pushProject()
    rowsDirty = true
    MEEditor.pushSelection()
end

local function stopSession()
    local e = E()
    if not e then return end
    if MEInput and MEInput.stop then MEInput.stop() end
    restoreAllRemovals()
    MEWorld.restoreSettings()
    MECam.stop()
    MEUI.closeEditor()
    MEUI.closeModal()
    MEUI.setHidden(false)
    exports.rp_hud:setHudHidden("rp_mapeditor", false)
    showCursor(false)
    MEEditor.E, MEEditor.active = nil, false
    if METutorial then METutorial.stop() end
end
MEEditor.stopSession = stopSession

addEventHandler("rp:me:enter", resourceRoot, function(summary, settings, rows, locks)
    MEUI.closeModal()
    startSession(summary, settings, rows, locks)
    MEEditor.notify(("Editando «%s». Pulsa H para ocultar los paneles."):format(summary.name), "info")
end)

addEventHandler("rp:me:leave", resourceRoot, function() stopSession() end)

addEventHandler("rp:me:reload", resourceRoot, function(summary, settings, rows, locks)
    local e = E()
    if not e then return end
    restoreAllRemovals()
    e.removed = {}
    e.project, e.settings, e.locks = summary, settings or {}, locks or {}
    e.rows, e.sel, e.preview, e.cacheDirty = {}, {}, {}, true
    e.undo, e.redo, e.alias = {}, {}, {}
    for _, r in ipairs(rows or {}) do e.rows[r.id] = r end
    applyRemovals()
    MEWorld.applySettings("draft", e.settings)
    pushProject()
    rowsDirty = true
    MEEditor.pushSelection()
end)

addEventHandler("rp:me:rows", resourceRoot, function(kind, data, refs)
    local e = E()
    if not e then return end
    e.cacheDirty = true
    if kind == "add" then
        local selectNew = {}
        for ref, id in pairs(refs or {}) do
            local pend = e.pendingRefs[ref]
            if pend then
                if pend.alias then e.alias[pend.alias] = id end
                if pend.select then selectNew[#selectNew + 1] = id end
                e.pendingRefs[ref] = nil
            end
        end
        for _, r in ipairs(data) do e.rows[r.id] = r end
        if #selectNew > 0 then MEEditor.selectMany(selectNew, false) end
    elseif kind == "upd" then
        for _, r in ipairs(data) do
            if r.etype == "removal" then restoreRemoval(r.id) end
            e.rows[r.id] = r
            e.preview[r.id] = nil
        end
    elseif kind == "del" then
        for _, id in ipairs(data) do
            restoreRemoval(id)
            e.rows[id], e.sel[id], e.preview[id] = nil, nil, nil
        end
        -- otros quitados podían coincidir con el restaurado
        for id in pairs(e.removed) do e.removed[id] = nil end
        for id, row in pairs(e.rows) do
            if row.etype == "removal" then
                local m, lod, r, x, y, z = removalArgs(row)
                removeWorldModel(m, r, x, y, z, e.project.interior)
                if lod > 0 then removeWorldModel(lod, r, x, y, z, e.project.interior) end
                e.removed[id] = { m, lod, r, x, y, z, e.project.interior }
            end
        end
    end
    applyRemovals()
    rowsDirty = true
    MEEditor.pushSelection()
end)

addEventHandler("rp:me:locks", resourceRoot, function(locks)
    local e = E()
    if not e then return end
    e.locks = locks or {}
    -- si otro tomó algo que yo tenía seleccionado (no debería), lo suelto
    for id in pairs(e.sel) do if MEEditor.lockedByOther(id) then e.sel[id] = nil end end
    rowsDirty = true
end)

addEventHandler("rp:me:editors", resourceRoot, function(list)
    local e = E()
    if not e then return end
    e.editors = list or {}
    pushProject()
end)

addEventHandler("rp:me:project", resourceRoot, function(summary)
    local e = E()
    if not e then return end
    e.project = summary
    pushProject()
end)

addEventHandler("rp:me:settings", resourceRoot, function(s)
    local e = E()
    if not e then return end
    e.settings = s or {}
    MEWorld.applySettings("draft", e.settings)
    pushProject()
end)

addEventHandler("rp:me:versions", resourceRoot, function(pid, list)
    MEUI.push("modal", "versions", { pid = pid, list = list })
end)

addEventHandler("rp:me:exported", resourceRoot, function(name, text, path)
    setClipboard(text)
    MEUI.push("modal", "exported", { name = name, text = text, path = path })
    MEEditor.notify("El .map se copió al portapapeles.", "success")
end)

-- Navegador de proyectos (modal)
addEventHandler("rp:me:openBrowser", resourceRoot, function()
    MEUI.openModal()
    MEUI.push("modal", "view", "browser")
end)

addEventHandler("rp:me:browser", resourceRoot, function(list, info)
    MEUI.push("modal", "browser", { list = list, info = info })
end)

----------------------------------------------------------------
-- Modo prueba (F)
----------------------------------------------------------------
function MEEditor.toggleTest()
    local e = E()
    if not e then return end
    if not e.testing then
        local x, y, z = MECam.x, MECam.y, MECam.z
        local hit, _, _, hz = processLineOfSight(x, y, z, x, y, z - 300, true, true, false, true, false)
        e.testing = true
        e.sel = {}
        MEEditor.selectionChanged()
        MECam.stop()
        MEUI.setHidden(true)
        showCursor(false)
        setElementPosition(localPlayer, x, y, (hit and hz or z) + 1)
        setElementFrozen(localPlayer, false)
        setElementAlpha(localPlayer, 255)
        triggerServerEvent("rp:me:test", resourceRoot, true)
        MEEditor.notify("Modo prueba: pulsa F para volver al editor.", "info")
    else
        e.testing = false
        local x, y, z = getElementPosition(localPlayer)
        local _, _, rz = getElementRotation(localPlayer)
        setElementFrozen(localPlayer, true)
        setElementAlpha(localPlayer, 0)
        triggerServerEvent("rp:me:test", resourceRoot, false)
        MECam.start(x, y, z + 2, -rz, -20)
        MECam.focus(x, y, z, 8)
        MEUI.setHidden(false)
        showCursor(true)
    end
    MEEditor.pushState()
end

addEventHandler("onClientPlayerDamage", localPlayer, function()
    if MEEditor.active then cancelEvent() end
end)

----------------------------------------------------------------
-- Acciones de los paneles (rp:me:ui)
----------------------------------------------------------------
local UI = {}

UI.cmd = function(d)
    -- acciones de proyecto: el servidor revalida todo
    if type(d) ~= "table" then return end
    triggerServerEvent("rp:me:cmd", resourceRoot, tostring(d.kind), d.a, d.b, d.c)
end

UI.closeModal = function()
    triggerServerEvent("rp:me:cmd", resourceRoot, "closebrowser")
    MEUI.closeModal()
end

UI.openModal = function(d)
    local e = E()
    MEUI.openModal()
    MEUI.push("modal", "view", d and d.view or "browser")
    if e then MEUI.push("modal", "project", { project = e.project, settings = e.settings, editors = e.editors }) end
    if not d or d.view == "browser" then triggerServerEvent("rp:me:cmd", resourceRoot, "list")
    elseif d.view == "versions" and e then triggerServerEvent("rp:me:cmd", resourceRoot, "versions", e.project.id)
    elseif d.view == "export" and e then triggerServerEvent("rp:me:cmd", resourceRoot, "export", e.project.id) end
end

UI.pick = function(d)
    if not E() or type(d) ~= "table" then return end
    MEInput.setGhost(d.etype, tonumber(d.model) or 0, type(d.props) == "table" and d.props or {})
    if d.etype == "object" and tonumber(d.model) then
        local m = tonumber(d.model)
        for i = #recents, 1, -1 do if recents[i] == m then table.remove(recents, i) end end
        table.insert(recents, 1, m)
        while #recents > 40 do table.remove(recents) end
        MEEditor.savePrefs()
        MEUI.push("win", "recents", recents)
    end
    -- como en el editor de MTA: al elegir, el navegador se cierra y queda el mundo libre para colocar
    MEEditor.closeWin()
    if METutorial then METutorial.event("pick") end
end

-- Columna de la izquierda: un botón por tipo. «remove» activa la herramienta de quitar edificios
UI.dock = function(d)
    local e = E()
    local kind = d and tostring(d.kind) or ""
    if kind == "remove" then
        MEInput.setGhost(nil)
        e.tool = e.tool == "remove" and "select" or "remove"
        MEEditor.closeWin()
        MEEditor.sound("click_002")
        MEEditor.pushState()
    elseif kind == "objects" or kind == "vehicles" or kind == "peds" or kind == "marker" or kind == "pickup"
        or kind == "point" or kind == "list" then
        MEEditor.openWin(kind, true)
    end
end
UI.closeWin = function() MEEditor.closeWin() end

-- Confirmación pedida desde una barra pequeña: se muestra centrada en la ventana modal y, al aceptar,
-- se ejecuta la acción (solo las de esta lista; el servidor revalida igual las de proyecto)
local CONFIRMABLE = { cmd = true, exit = true }
local pendingConfirm = nil
UI.confirm = function(d)
    if type(d) ~= "table" or not CONFIRMABLE[d.action] then return end
    pendingConfirm = { action = d.action, data = type(d.data) == "table" and d.data or {} }
    MEUI.openModal()
    MEUI.push("modal", "confirm", tostring(d.text or "¿Seguro?"):sub(1, 200))
end
UI.confirmOk = function()
    local p = pendingConfirm
    pendingConfirm = nil
    MEUI.closeModal()
    if p and UI[p.action] then
        if p.action == "cmd" and p.data.kind == "publish" then MEEditor.sound("confirmation_003") end
        UI[p.action](p.data)
    end
end
-- Tooltip de los botones de icono (lo dibuja c_draw.lua junto al cursor)
UI.hover = function(d) MEEditor.tip = d and type(d.text) == "string" and d.text:sub(1, 80) or "" end
UI.openProps = function() MEEditor.openProps() end
UI.closeProps = function() MEUI.show("props", false) end

UI.favorite = function(d)
    local m = tonumber(d and d.model)
    if not m then return end
    local found = false
    for i = #favorites, 1, -1 do if favorites[i] == m then table.remove(favorites, i) found = true end end
    if not found then table.insert(favorites, 1, m) end
    MEEditor.savePrefs()
    MEUI.push("win", "favorites", favorites)
end

UI.thumbs = function(d) METhumbs.request(d and d.list or {}) end
UI.tool = function(d)
    local e = E()
    e.tool = d and d.tool == "remove" and "remove" or "select"
    MEInput.setGhost(nil)
    MEEditor.pushState()
end
UI.gizmo = function(d)
    local e = E()
    if d and (d.mode == "move" or d.mode == "rotate" or d.mode == "scale") then e.gizmo = d.mode end
    MEEditor.pushState()
end
UI.localAxes = function() local e = E() e.localAxes = not e.localAxes MEEditor.pushState() end
UI.grid = function(d)
    local e = E()
    if d.on ~= nil then e.gridOn = d.on == true end
    if tonumber(d.grid) then e.grid = math.max(0.01, math.min(50, tonumber(d.grid))) end
    if tonumber(d.rotStep) then e.rotStep = math.max(0, math.min(90, tonumber(d.rotStep))) end
    MEEditor.pushState()
end
UI.undo = function() MEEditor.undo() end
UI.redo = function() MEEditor.redo() end
UI.delete = function() MEEditor.deleteSelection() end
UI.duplicate = function() MEEditor.duplicateSelection() end
UI.copy = function() MEEditor.copySelection() MEEditor.pushState() end
UI.paste = function() MEEditor.paste(MEInput.cursorGround and { MEInput.cursorGround() } or nil) end
UI.ground = function() MEEditor.dropToGround() end
UI.focus = function() MEEditor.focusSelection() end
UI.test = function() MEEditor.toggleTest() end
UI.hide = function() MEUI.setHidden(not MEUI.isHidden()) end
UI.exit = function() triggerServerEvent("rp:me:cmd", resourceRoot, "leave") end
UI.selectId = function(d)
    local id = tonumber(d and d.id)
    if not id then return end
    MEEditor.select(id, d.add == true)
    if d.focus then MEEditor.focusSelection() end
end
UI.selectNone = function() MEEditor.clearSelection() end

-- Cambios desde el panel de propiedades: { rows = { fila, ... } } con los campos nuevos
UI.props = function(d)
    local e = E()
    if type(d) ~= "table" or type(d.rows) ~= "table" then return end
    local list = {}
    for _, r in ipairs(d.rows) do
        local id = tonumber(r.id)
        local cur = id and e.rows[id]
        if cur then
            local n = copy(cur)
            for _, k in ipairs({ "model", "x", "y", "z", "rx", "ry", "rz" }) do
                if tonumber(r[k]) then n[k] = tonumber(r[k]) end
            end
            if type(r.props) == "table" then n.props = r.props end
            list[#list + 1] = n
        end
    end
    MEEditor.commitRows(list)
end

UI.tutorialDone = function()
    prefs.tutorial = true
    MEEditor.savePrefs()
    if METutorial then METutorial.stop() end
end
UI.tutorialReset = function()
    prefs.tutorial = false
    MEEditor.savePrefs()
    if METutorial then METutorial.start() end
end

UI.sound = function(d) if d and type(d.name) == "string" and d.name:match("^[%w_]+$") then MEEditor.sound(d.name) end end

function MEEditor.ui(action, data)
    local fn = UI[action]
    if not fn then return end
    -- el navegador de proyectos funciona también fuera del editor
    if not E() and action ~= "cmd" and action ~= "closeModal" and action ~= "openModal" and action ~= "sound" then return end
    fn(data or {})
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    math.randomseed(getTickCount())
    loadPrefs()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if MEEditor.E then
        restoreAllRemovals()
        exports.rp_hud:setHudHidden("rp_mapeditor", false)
    end
end)
