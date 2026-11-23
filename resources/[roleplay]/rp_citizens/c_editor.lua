--[[
    rp_citizens / c_editor.lua
    1) Aplica los cambios de rutas guardados en SQL (los pide al arrancar y los
       recibe en vivo cuando un admin edita).
    2) Editor visual (/nodos, solo admins). Mejor con /freecam.

    Controles del editor:
      Clic izquierdo         seleccionar nodo (y arrastrarlo para moverlo)
      Shift + clic           seleccionar un segundo nodo
      N                      nuevo nodo: entre los dos seleccionados (si estan enlazados)
                             o en el suelo bajo el cursor, enlazado al seleccionado
      K                      enlazar / desenlazar los dos nodos seleccionados
      Supr                   borrar el nodo seleccionado
      1 / 2 / 3              mostrar u ocultar nodos peatonales / viales / carriles
      Clic derecho (freecam) mantener para girar la camara
]]

local screenW, screenH = guiGetScreenSize()
local NODES = { p = PED_NODES, v = VEH_NODES }
local LINKS = { p = PED_LINKS, v = VEH_LINKS }

-- Historial para deshacer (ver mas abajo)
local BASECOUNT = { p = #PED_NODES / 3, v = #VEH_NODES / 3 }   -- nodos de la red original (los nuevos son mayores)
local history, expectAdd, dragOrig = {}, nil, nil
local HISTORY_MAX = 100

local function pushHistory(entry)
    history[#history + 1] = entry
    if #history > HISTORY_MAX then table.remove(history, 1) end
end

----------------------------------------------------------------
-- Aplicar cambios al grafo
----------------------------------------------------------------
local function hasLink(t, a, b)
    for _, n in ipairs(LINKS[t][a] or {}) do if n == b then return true end end
    return false
end

-- En la red vial, VEH_LANES / VEH_OFFSET son listas paralelas a VEH_LINKS:
-- se mantienen alineadas al agregar o quitar enlaces (enlace nuevo: 1 carril, 2.5 m)
local function addLink(t, a, b)
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local from, to = pair[1], pair[2]
        LINKS[t][from] = LINKS[t][from] or {}
        if not hasLink(t, from, to) then
            table.insert(LINKS[t][from], to)
            if t == "v" then
                VEH_LANES[from] = VEH_LANES[from] or {}
                VEH_OFFSET[from] = VEH_OFFSET[from] or {}
                table.insert(VEH_LANES[from], #LINKS[t][from], 1)
                table.insert(VEH_OFFSET[from], #LINKS[t][from], 2.5)
            end
        end
    end
end

local function removeLink(t, a, b)
    for _, pair in ipairs({ { a, b }, { b, a } }) do
        local list = LINKS[t][pair[1]]
        if list then
            for k = #list, 1, -1 do
                if list[k] == pair[2] then
                    table.remove(list, k)
                    if t == "v" then
                        if VEH_LANES[pair[1]] then table.remove(VEH_LANES[pair[1]], k) end
                        if VEH_OFFSET[pair[1]] then table.remove(VEH_OFFSET[pair[1]], k) end
                    end
                end
            end
        end
    end
end

local function setNode(t, i, x, y, z)
    local nodes = NODES[t]
    -- nodos nuevos: rellena huecos si los hubiera
    local count = #nodes / 3
    for j = count + 1, i - 1 do
        nodes[j * 3 - 2], nodes[j * 3 - 1], nodes[j * 3] = 0, 0, -1000
        LINKS[t][j] = LINKS[t][j] or {}
    end
    nodes[i * 3 - 2], nodes[i * 3 - 1], nodes[i * 3] = x, y, z
    LINKS[t][i] = LINKS[t][i] or {}
    if t == "v" then
        VEH_LANES[i] = VEH_LANES[i] or {}
        VEH_OFFSET[i] = VEH_OFFSET[i] or {}
    end
end

local function deleteNode(t, i)
    for _, n in ipairs(LINKS[t][i] or {}) do removeLink(t, i, n) end
    LINKS[t][i] = {}
end

local editorGrid = nil   -- se recalcula cuando cambia el grafo

addEvent("rp:paths:apply", true)
addEventHandler("rp:paths:apply", resourceRoot, function(ops)
    for _, o in ipairs(ops or {}) do
        local t = o.t
        if NODES[t] then
            if o.op == "node" then
                setNode(t, o.i, o.x, o.y, o.z)
                -- nodo recien creado por este editor: se anota para poder deshacerlo
                if expectAdd and expectAdd.t == t and o.i > BASECOUNT[t] and o.i > (expectAdd.minIdx or 0) then
                    pushHistory({ k = "add", t = t, i = o.i, a = expectAdd.a, b = expectAdd.b, snap = expectAdd.snap, x = o.x, y = o.y, z = o.z })
                    expectAdd = nil
                end
            elseif o.op == "delete" then deleteNode(t, o.i)
            elseif o.op == "link" then
                if o.removed then removeLink(t, o.a, o.b) else addLink(t, o.a, o.b) end
            end
        end
    end
    rebuildCitizenGrids()
    editorGrid = nil
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rp:paths:request", resourceRoot)
end)

----------------------------------------------------------------
-- Editor
----------------------------------------------------------------
local editing = false
local show = { p = true, v = true }
local selected, second = nil, nil     -- { t, i }
local dragging = false

----------------------------------------------------------------
-- Deshacer (Ctrl+Z): historial de las ultimas operaciones de esta sesion del editor
----------------------------------------------------------------
-- Carriles y desplazamiento de a->b y b->a (para recuperarlos al rehacer un enlace borrado)
local function laneSnapshot(t, a, b)
    if t ~= "v" or not hasLink(t, a, b) then return nil end
    local l1, o1 = getLaneInfo(a, b)
    local l2, o2 = getLaneInfo(b, a)
    return { a = a, b = b, l1 = l1, o1 = o1, l2 = l2, o2 = o2 }
end

local function restoreLanes(t, snap)
    if t ~= "v" or not snap then return end
    for _, p in ipairs({ { snap.a, snap.b, snap.l1, snap.o1 }, { snap.b, snap.a, snap.l2, snap.o2 } }) do
        local list = LINKS.v[p[1]]
        for k = 1, #(list or {}) do
            if list[k] == p[2] then
                VEH_LANES[p[1]] = VEH_LANES[p[1]] or {}
                VEH_OFFSET[p[1]] = VEH_OFFSET[p[1]] or {}
                VEH_LANES[p[1]][k], VEH_OFFSET[p[1]][k] = p[3], p[4]
            end
        end
    end
    rebuildCitizenGrids()
end

local VIEW = 90                      -- metros alrededor de la camara
local CELL = 50

local function buildEditorGrid()
    editorGrid = { p = {}, v = {} }
    for t, nodes in pairs(NODES) do
        for i = 1, #nodes / 3 do
            if LINKS[t][i] and #LINKS[t][i] > 0 then
                local key = math.floor(nodes[i * 3 - 2] / CELL) * 1000 + math.floor(nodes[i * 3 - 1] / CELL)
                local cell = editorGrid[t][key]
                if not cell then cell = {} editorGrid[t][key] = cell end
                cell[#cell + 1] = i
            end
        end
    end
end

-- Nodos visibles cerca de la camara: { t, i, sx, sy, x, y, z }
local function visibleNodes()
    if not editorGrid then buildEditorGrid() end
    local cx, cy, cz = getCameraMatrix()
    local list = {}
    local r = math.ceil(VIEW / CELL)
    local gx, gy = math.floor(cx / CELL), math.floor(cy / CELL)
    for t, grid in pairs(editorGrid) do
        if show[t] then
            local nodes = NODES[t]
            for ox = -r, r do
                for oy = -r, r do
                    local cell = grid[(gx + ox) * 1000 + (gy + oy)]
                    if cell then
                        for _, i in ipairs(cell) do
                            local x, y, z = nodes[i * 3 - 2], nodes[i * 3 - 1], nodes[i * 3]
                            if getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) < VIEW then
                                local sx, sy = getScreenFromWorldPosition(x, y, z + 0.3, 0, false)
                                list[#list + 1] = { t = t, i = i, sx = sx, sy = sy, x = x, y = y, z = z }
                            end
                        end
                    end
                end
            end
        end
    end
    return list
end

local function isSel(sel, t, i) return sel and sel.t == t and sel.i == i end

local COLORS = { p = tocolor(80, 200, 255, 220), v = tocolor(255, 160, 40, 140) }
local LANE_COLOR = tocolor(90, 230, 120, 230)
local CURVE_COLOR = tocolor(230, 90, 255, 220)
local PLAN_COLOR = tocolor(255, 230, 40, 255)
local showLanes = true
local showPlans = true

-- Carril real de un sentido (a -> b): linea verde desplazada a la derecha con flecha
function drawLane(a, b, ax, ay, az, bx, by, bz)
    local lanes, off = getLaneInfo(a, b)
    if lanes <= 0 then return end
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    dx, dy = dx / len, dy / len
    local rx, ry = dy * off, -dx * off
    local sx, sy, ex, ey = ax + rx, ay + ry, bx + rx, by + ry
    dxDrawLine3D(sx, sy, az + 0.25, ex, ey, bz + 0.25, LANE_COLOR, 2)
    -- flecha en el centro del tramo
    local mx, my, mz = (sx + ex) / 2, (sy + ey) / 2, (az + bz) / 2 + 0.25
    dxDrawLine3D(mx, my, mz, mx - dx * 1.5 + dy * 0.8, my - dy * 1.5 - dx * 0.8, mz, LANE_COLOR, 2)
    dxDrawLine3D(mx, my, mz, mx - dx * 1.5 - dy * 0.8, my - dy * 1.5 + dx * 0.8, mz, LANE_COLOR, 2)
end

local function render()
    local list = visibleNodes()
    -- Enlaces (cada par una sola vez)
    for _, n in ipairs(list) do
        local nodes = NODES[n.t]
        for _, j in ipairs(LINKS[n.t][n.i] or {}) do
            if j > n.i or not editorGrid then
                local bx, by, bz = nodes[j * 3 - 2], nodes[j * 3 - 1], nodes[j * 3]
                local sel = isSel(selected, n.t, n.i) or isSel(selected, n.t, j)
                dxDrawLine3D(n.x, n.y, n.z + 0.3, bx, by, bz + 0.3, sel and tocolor(255, 255, 0, 255) or COLORS[n.t], n.t == "v" and 2 or 2)
                if n.t == "v" and showLanes then
                    drawLane(n.i, j, n.x, n.y, n.z, bx, by, bz)
                    drawLane(j, n.i, bx, by, bz, n.x, n.y, n.z)
                end
            end
        end
    end
    -- Nodos
    for _, n in ipairs(list) do
        if n.sx then
            local size = (isSel(selected, n.t, n.i) or isSel(second, n.t, n.i)) and 12 or 7
            local color = isSel(selected, n.t, n.i) and tocolor(255, 255, 0) or isSel(second, n.t, n.i) and tocolor(255, 80, 200) or COLORS[n.t]
            dxDrawRectangle(n.sx - size / 2, n.sy - size / 2, size, size, color)
        end
    end

    -- Curvas de giro en los cruces (las mismas que calculan los autos)
    if show.v and showLanes then
        for _, n in ipairs(list) do
            local links = n.t == "v" and LINKS.v[n.i]
            if links and #links >= 2 then
                for _, a in ipairs(links) do
                    if getLaneInfo(a, n.i) > 0 then
                        for _, c in ipairs(links) do
                            if c ~= a and getLaneInfo(n.i, c) > 0 then
                                local pts, turn = computeTurnPoints(a, n.i, c)
                                if turn >= 10 then
                                    for k = 1, #pts - 1 do
                                        dxDrawLine3D(pts[k][1], pts[k][2], pts[k][3] + 0.3, pts[k + 1][1], pts[k + 1][2], pts[k + 1][3] + 0.3, CURVE_COLOR, 2)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Ruta planificada de cada auto de la poblacion
    if showPlans then
        for _, p in ipairs(getCitizenCarPlans()) do
            local px, py, pz = getElementPosition(p.vehicle)
            local lx, ly, lz = px, py, pz
            for k = 1, math.min(#p.wp, 30) do
                local w = p.wp[k]
                dxDrawLine3D(lx, ly, lz + 0.6, w[1], w[2], w[3] + 0.6, PLAN_COLOR, 4)
                lx, ly, lz = w[1], w[2], w[3]
            end
            local sx, sy = getScreenFromWorldPosition(px, py, pz + 1.6)
            if sx then
                dxDrawText(("%s  [%s]"):format(p.state or "?", p.lod == "dummy" and "dummy" or "fisica"), sx, sy, sx, sy, tocolor(255, 255, 255), 1, "default-bold", "center", "bottom")
            end
        end
    end

    -- Panel de ayuda
    local lines = {
        "EDITOR DE RUTAS  (/nodos para salir)",
        "Clic: seleccionar y arrastrar   Shift+clic: 2o nodo",
        "N: nuevo nodo   K: enlazar/desenlazar   Supr: borrar   Ctrl+Z: deshacer",
        ("1: peatones [%s]   2: vehiculos [%s]   3: carriles [%s]"):format(show.p and "si" or "no", show.v and "si" or "no", showLanes and "si" or "no"),
        ("Naranja = centro (se edita)  Verde = carril  Morado = curvas  Amarillo = ruta de cada auto [4: %s]"):format(showPlans and "si" or "no"),
        selected and ("Seleccionado: %s #%d  (%d enlaces)"):format(selected.t == "v" and "vial" or "peatonal", selected.i, #(LINKS[selected.t][selected.i] or {})) or "Nada seleccionado",
    }
    dxDrawRectangle(20, screenH / 2 - 70, 560, 20 + #lines * 20, tocolor(12, 14, 20, 210))
    for k, l in ipairs(lines) do
        dxDrawText(l, 32, screenH / 2 - 60 + (k - 1) * 20, 0, 0, k == 1 and tocolor(245, 165, 36) or tocolor(242, 244, 248), 1, k == 1 and "default-bold" or "default")
    end
end

-- Punto del mundo bajo el cursor (suelo/edificios)
local function worldUnderCursor()
    local cx, cy = getCursorPosition()
    if not cx then return end
    local ax, ay = cx * screenW, cy * screenH
    local camX, camY, camZ = getCameraMatrix()
    local wx, wy, wz = getWorldFromScreenPosition(ax, ay, 300)
    local hit, hx, hy, hz = processLineOfSight(camX, camY, camZ, wx, wy, wz, true, false, false, true, false, true)
    if hit then return hx, hy, hz end
end

local function pickNode(absX, absY)
    local best, bestD = nil, 14
    for _, n in ipairs(visibleNodes()) do
        if n.sx then
            local d = math.sqrt((n.sx - absX) ^ 2 + (n.sy - absY) ^ 2)
            if d < bestD then best, bestD = n, d end
        end
    end
    return best
end

local function onClick(button, state, absX, absY)
    if button ~= "left" then return end
    if state == "down" then
        local n = pickNode(absX, absY)
        if getKeyState("lshift") or getKeyState("rshift") then
            if n and selected and n.t == selected.t then second = { t = n.t, i = n.i } end
            return
        end
        if n then
            selected, second = { t = n.t, i = n.i }, nil
            dragging = true
            local nd = NODES[n.t]
            dragOrig = { t = n.t, i = n.i, x = nd[n.i * 3 - 2], y = nd[n.i * 3 - 1], z = nd[n.i * 3] }
        else
            selected, second, dragging = nil, nil, false
        end
    elseif state == "up" and dragging then
        dragging = false
        if selected and selected.moved then
            local nodes = NODES[selected.t]
            local i = selected.i
            triggerServerEvent("rp:paths:move", resourceRoot, selected.t, i, nodes[i * 3 - 2], nodes[i * 3 - 1], nodes[i * 3])
            if dragOrig and dragOrig.t == selected.t and dragOrig.i == i then
                pushHistory({ k = "move", t = dragOrig.t, i = i, x = dragOrig.x, y = dragOrig.y, z = dragOrig.z })
            end
            selected.moved = nil
        end
    end
end

local function onCursorMove()
    if not dragging or not selected then return end
    local x, y, z = worldUnderCursor()
    if not x then return end
    local nodes = NODES[selected.t]
    local i = selected.i
    nodes[i * 3 - 2], nodes[i * 3 - 1], nodes[i * 3] = x, y, z   -- vista previa local
    selected.moved = true
    editorGrid = nil
end

local function keyNew()
    if not selected then return end
    local t, a = selected.t, selected.i
    local nodes = NODES[t]
    if second and hasLink(t, a, second.i) then
        local b = second.i
        local mx = (nodes[a * 3 - 2] + nodes[b * 3 - 2]) / 2
        local my = (nodes[a * 3 - 1] + nodes[b * 3 - 1]) / 2
        local mz = (nodes[a * 3] + nodes[b * 3]) / 2
        expectAdd = { t = t, a = a, b = b, snap = laneSnapshot(t, a, b), minIdx = BASECOUNT[t] }
        triggerServerEvent("rp:paths:add", resourceRoot, t, mx, my, mz, a, b)
    else
        local x, y, z = worldUnderCursor()
        if x then
            expectAdd = { t = t, a = a, minIdx = BASECOUNT[t] }
            triggerServerEvent("rp:paths:add", resourceRoot, t, x, y, z, a)
        end
    end
end

local function keyLink()
    if not selected or not second then
        return exports.rp_notify:notify("Selecciona dos nodos (clic y Shift+clic).", "warning")
    end
    local t = selected.t
    local had = hasLink(t, selected.i, second.i)
    pushHistory({ k = "link", t = t, a = selected.i, b = second.i, had = had, snap = laneSnapshot(t, selected.i, second.i) })
    triggerServerEvent("rp:paths:link", resourceRoot, t, selected.i, second.i, had)
end

local function keyDelete()
    if not selected then return end
    local nodes = NODES[selected.t]
    local i = selected.i
    -- se guardan los enlaces del nodo (con carriles) para poder recuperarlo con Ctrl+Z
    local snaps = {}
    for _, n in ipairs(LINKS[selected.t][i] or {}) do snaps[#snaps + 1] = { b = n, snap = laneSnapshot(selected.t, i, n) } end
    pushHistory({ k = "delete", t = selected.t, i = i, x = nodes[i * 3 - 2], y = nodes[i * 3 - 1], z = nodes[i * 3], links = snaps })
    triggerServerEvent("rp:paths:delete", resourceRoot, selected.t, i, nodes[i * 3 - 2], nodes[i * 3 - 1], nodes[i * 3])
    selected, second = nil, nil
end

-- Ctrl+Z: deshace la ultima operacion del editor (mover, crear, enlazar/desenlazar, borrar)
local function keyUndo()
    if not (getKeyState("lctrl") or getKeyState("rctrl")) then return end
    local e = table.remove(history)
    if not e then return exports.rp_notify:notify("No hay nada que deshacer.", "info") end
    local t = e.t
    if e.k == "move" then
        local nodes = NODES[t]
        nodes[e.i * 3 - 2], nodes[e.i * 3 - 1], nodes[e.i * 3] = e.x, e.y, e.z
        triggerServerEvent("rp:paths:move", resourceRoot, t, e.i, e.x, e.y, e.z)
    elseif e.k == "add" then
        local nodes = NODES[t]
        triggerServerEvent("rp:paths:delete", resourceRoot, t, e.i, nodes[e.i * 3 - 2], nodes[e.i * 3 - 1], nodes[e.i * 3])
        if e.b then
            -- el nodo nuevo se habia insertado entre a y b: se recupera el enlace directo
            triggerServerEvent("rp:paths:link", resourceRoot, t, e.a, e.b, false)
            setTimer(restoreLanes, 500, 1, t, e.snap)
        end
        if selected and selected.t == t and selected.i == e.i then selected, second = nil, nil end
    elseif e.k == "link" then
        triggerServerEvent("rp:paths:link", resourceRoot, t, e.a, e.b, not e.had)
        if e.had then setTimer(restoreLanes, 500, 1, t, e.snap) end
    elseif e.k == "delete" then
        -- el nodo vuelve a su sitio y sus enlaces (con los carriles que tenian)
        triggerServerEvent("rp:paths:move", resourceRoot, t, e.i, e.x, e.y, e.z)
        for _, l in ipairs(e.links or {}) do
            triggerServerEvent("rp:paths:link", resourceRoot, t, e.i, l.b, false)
            setTimer(restoreLanes, 600, 1, t, l.snap)
        end
    end
    exports.rp_notify:notify("Deshecho. (" .. #history .. " operaciones mas en el historial)", "info")
end

local function toggleP() show.p = not show.p end
local function toggleV() show.v = not show.v end
local function toggleLanes() showLanes = not showLanes end
local function togglePlans() showPlans = not showPlans end

local function setEditing(state)
    editing = state
    if state then
        buildEditorGrid()
        addEventHandler("onClientRender", root, render)
        addEventHandler("onClientClick", root, onClick)
        addEventHandler("onClientCursorMove", root, onCursorMove)
        bindKey("n", "down", keyNew)
        bindKey("k", "down", keyLink)
        bindKey("delete", "down", keyDelete)
        bindKey("z", "down", keyUndo)
        bindKey("1", "down", toggleP)
        bindKey("2", "down", toggleV)
        bindKey("3", "down", toggleLanes)
        bindKey("4", "down", togglePlans)
        showCursor(true)
        exports.rp_notify:notify("Editor de rutas activado. Usa /freecam para moverte libremente.", "info")
    else
        removeEventHandler("onClientRender", root, render)
        removeEventHandler("onClientClick", root, onClick)
        removeEventHandler("onClientCursorMove", root, onCursorMove)
        unbindKey("n", "down", keyNew)
        unbindKey("k", "down", keyLink)
        unbindKey("delete", "down", keyDelete)
        unbindKey("z", "down", keyUndo)
        unbindKey("1", "down", toggleP)
        unbindKey("2", "down", toggleV)
        unbindKey("3", "down", toggleLanes)
        unbindKey("4", "down", togglePlans)
        showCursor(false)
        selected, second, dragging = nil, nil, false
        exports.rp_notify:notify("Editor de rutas desactivado.", "info")
    end
end

addEvent("rp:paths:editor", true)
addEventHandler("rp:paths:editor", resourceRoot, function() setEditing(not editing) end)

function isPathEditorActive() return editing end
