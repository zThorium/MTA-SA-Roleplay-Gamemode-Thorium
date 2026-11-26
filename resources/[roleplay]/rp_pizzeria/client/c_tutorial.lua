--[[
    rp_pizzeria / c_tutorial.lua
    Guia visual del turno, pensada para no saturar:
      - Indicadores de estacion discretos (aro fino en el suelo; nombre solo de cerca). Se encienden
        solo las estaciones utiles AHORA (segun lo que llevas en la mano y como va la cocina).
      - Tutorial: un solo objetivo a la vez. Lejos, visor de esquinas verdes; cerca, el mueble real
        (o el cliente) resaltado en blanco. Los pasos sobre la interfaz oscurecen la pantalla y
        dejan iluminada solo esa parte del HUD (foco), sin guia 3D a la vez.
    El paso sale del estado que manda el servidor, asi que avanza solo con lo que hagas.
]]
local sw, sh = guiGetScreenSize()
local tour = nil            -- final informativo: { i = paso de OUTRO, untilTick }
local target = nil          -- { x, y, z, label, obj = {modelo...} | element = ped }
local focus = nil           -- "kitchen" | "tickets" | nil
local lastKey
local takenAt = {}          -- [orderId] = tick en que vimos su comanda (para el foco de la comanda)
local relevant = {}         -- [stationId] = true: estaciones utiles ahora (fuera del tutorial)

local OUTRO = {
    { "pantry", "La despensa", "Si se acaban los ingredientes, repón aquí arrastrando cajas.", 7000 },
    { "fryer", "La freidora", "Algunos pedidos llevan papas o palitos de ajo: fríelos aquí.", 7000 },
    { nil, "¡Listo!", "Ahora llegarán más clientes. Si su cara se pone roja, date prisa.", 6000 },
}
local TOTAL = 9 + #OUTRO

----------------------------------------------------------------
-- Tarjeta y foco del HUD
----------------------------------------------------------------
local function card(step, title, text, focusId)
    local key = tostring(step) .. title .. text .. tostring(focusId)
    if key == lastKey then return end
    lastKey = key
    focus = focusId
    if not step then return Pz.hud("PZ.tutorial(null)") end
    Pz.hud(("PZ.tutorial(%s)"):format(toJSON({ step = step, total = TOTAL, title = title, text = text, focus = focusId or false }, true) .. "[0]"))
end

local function station(id) return PIZZERIA.STATION_BY_ID[id] end
local function elapsed(ago) return ago + (getTickCount() - (Pz.stateTick or getTickCount())) end

----------------------------------------------------------------
-- Pasos del tutorial: devuelve paso, objetivo (estacion o cliente), titulo, texto, foco
----------------------------------------------------------------
local function customerTarget(o)
    local ped = o and Pz.customerPed(o.id)
    if not ped then return station("order") end
    local x, y, z = getElementPosition(ped)
    return { x = x, y = y, z = z, label = o.name, element = ped }
end

local function currentStep()
    local s = Pz.state
    local o = s.orders[1]
    local hand = s.hand
    if hand and hand.kind == "boxed" then
        return 9, customerTarget(o), "Entrégala", "Ve al mostrador frente a " .. (o and o.name or "el cliente") .. " y pulsa E."
    end
    if hand and hand.kind == "baked" then
        return 8, station("cut"), "Córtala", "Pulsa E en Corte y empaque."
    end
    if hand and hand.kind == "raw" then
        return 5, (not s.ovens[1]) and station("oven1") or station("oven2"), "Al horno", "Pulsa E en el horno para meterla."
    end
    for i = 1, 2 do
        local ov = s.ovens[i]
        if ov then
            if elapsed(ov.ago) / ov.target >= 0.85 then
                return 7, station("oven" .. i), "¡Sácala!", "Está en su punto. Pulsa E en el horno."
            end
            return 6, nil, "Mira la cocina", "Aquí ves cómo se hornea. Cuando la barra llegue a la zona verde, sácala.", "kitchen"
        end
    end
    if not o then return 1, station("order"), "Espera al cliente", "Quédate en la caja. Ya viene alguien." end
    if o.status == "queue" then
        if o.arriveIn - (getTickCount() - (Pz.stateTick or 0)) > 0 then
            return 1, station("order"), "Espera al cliente", o.name .. " viene hacia la caja."
        end
        return 2, station("order"), "Toma el pedido", "Pulsa E en la caja."
    end
    if o.stage == "new" then
        takenAt[o.id] = takenAt[o.id] or getTickCount()
        if getTickCount() - takenAt[o.id] < 6000 then
            return 3, nil, "Su comanda", "Aquí arriba está lo que pidió: 4 pepperoni y 4 trozos.", "tickets"
        end
        return 4, station("assembly"), "Arma la pizza", "Pulsa E en la mesa de armado."
    end
    return 4, station("assembly"), "Sigue el pedido", "Mira la comanda de arriba."
end

----------------------------------------------------------------
-- Estaciones utiles ahora (fuera del tutorial)
----------------------------------------------------------------
local function updateRelevant()
    relevant = {}
    local s = Pz.state
    if not s then return end
    local hand = s.hand
    if hand then
        if hand.kind == "raw" then
            if not s.ovens[1] then relevant.oven1 = true end
            if not s.ovens[2] then relevant.oven2 = true end
        elseif hand.kind == "baked" then relevant.cut = true
        elseif hand.kind == "boxed" then relevant.pickup = true end
        return
    end
    for i = 1, 2 do
        local ov = s.ovens[i]
        if ov and elapsed(ov.ago) / ov.target >= 0.85 then relevant["oven" .. i] = true end
    end
    local front = s.queue[1]
    for _, o in ipairs(s.orders) do
        if o.id == front and o.arriveIn - (getTickCount() - (Pz.stateTick or 0)) <= 0 then relevant.order = true end
        if o.status == "waiting" and o.stage == "new" then relevant.assembly = true end
        if o.status == "waiting" and o.side and not o.sideState then relevant.fryer = true end
    end
    for _, f in ipairs(s.fryer) do if f then relevant.fryer = true end end
end

local function update()
    if not Pz.onShift or not Pz.state then return end
    updateRelevant()
    if tour then
        local item = OUTRO[tour.i]
        if not item then
            tour, target = nil, nil
            return card(nil, "", "")
        end
        if getTickCount() > tour.untilTick then
            tour.i = tour.i + 1
            tour.untilTick = getTickCount() + (OUTRO[tour.i] and OUTRO[tour.i][4] or 0)
            return
        end
        target = item[1] and station(item[1]) or nil
        return card(9 + tour.i, item[2], item[3])
    end
    if not Pz.state.tutorial then
        target = nil
        return card(nil, "", "")
    end
    local step, t, title, text, f = currentStep()
    target = t
    card(step, title, text, f)
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local ghost, ghostFor
local function ghostOf(st)
    if ghostFor == st then return ghost end
    if isElement(ghost) then destroyElement(ghost) end
    ghost, ghostFor = nil, st
    if st and st.obj then
        local o = st.obj
        ghost = createObject(o[1], o[2], o[3], o[4], 0, 0, o[5])
        setElementAlpha(ghost, 0)
        setElementCollisionsEnabled(ghost, false)
        setElementInterior(ghost, PIZZERIA.INTERIOR)
        setElementDimension(ghost, Pz.dim)
    end
    return ghost
end

local function corners(x1, y1, x2, y2, len, color, w)
    dxDrawLine(x1, y1, x1 + len, y1, color, w); dxDrawLine(x1, y1, x1, y1 + len, color, w)
    dxDrawLine(x2, y1, x2 - len, y1, color, w); dxDrawLine(x2, y1, x2, y1 + len, color, w)
    dxDrawLine(x1, y2, x1 + len, y2, color, w); dxDrawLine(x1, y2, x1, y2 - len, color, w)
    dxDrawLine(x2, y2, x2 - len, y2, color, w); dxDrawLine(x2, y2, x2, y2 - len, color, w)
end

local function screenBox(el)
    local x0, y0, z0, x1, y1, z1 = getElementBoundingBox(el)
    local m = getElementMatrix(el)
    if not x0 or not m then return nil end
    local minX, minY, maxX, maxY
    for _, cx in ipairs({ x0, x1 }) do
        for _, cy in ipairs({ y0, y1 }) do
            for _, cz in ipairs({ z0, z1 }) do
                local sx, sy = getScreenFromWorldPosition(
                    cx * m[1][1] + cy * m[2][1] + cz * m[3][1] + m[4][1],
                    cx * m[1][2] + cy * m[2][2] + cz * m[3][2] + m[4][2],
                    cx * m[1][3] + cy * m[2][3] + cz * m[3][3] + m[4][3], 0, false)
                if not sx then return nil end
                minX, maxX = math.min(minX or sx, sx), math.max(maxX or sx, sx)
                minY, maxY = math.min(minY or sy, sy), math.max(maxY or sy, sy)
            end
        end
    end
    return minX, minY, maxX, maxY
end

-- Aro fino en el suelo de una estacion
local function ring(st, r, g, b, a, radius)
    local z = st.z - 0.95
    local n, prevX, prevY = 24, nil, nil
    for i = 0, n do
        local ang = i / n * math.pi * 2
        local x, y = st.x + math.cos(ang) * radius, st.y + math.sin(ang) * radius
        if prevX then dxDrawLine3D(prevX, prevY, z, x, y, z, tocolor(r, g, b, a), 2) end
        prevX, prevY = x, y
    end
end

local function drawStations(px, py, pz, now)
    local tutorial = Pz.state and (Pz.state.tutorial or tour)
    local pulse = 0.5 + 0.5 * math.sin(now / 220)
    for _, st in ipairs(PIZZERIA.STATIONS) do
        if st.kind ~= "pickup" then
            local d = getDistanceBetweenPoints3D(px, py, pz, st.x, st.y, st.z)
            local on = tutorial and target == st or (not tutorial and relevant[st.id])
            if on then
                ring(st, 255, 200, 50, 150 + pulse * 100, 0.45 + pulse * 0.05)
            else
                ring(st, 200, 200, 210, tutorial and 25 or 55, 0.4)
            end
            -- nombre: solo de cerca, o si es util ahora (fuera del tutorial)
            if d < 2.2 or (on and not tutorial) then
                local sx, sy = getScreenFromWorldPosition(st.x, st.y, st.z + 0.15, 0, false)
                if sx then
                    local a = on and 235 or 150
                    dxDrawText(st.label, sx - 80, sy, sx + 80, sy + 18, tocolor(0, 0, 0, a * 0.7), 1, "default-bold", "center", "top")
                    dxDrawText(st.label, sx - 81, sy - 1, sx + 79, sy + 17, on and tocolor(255, 215, 90, a) or tocolor(235, 235, 240, a),
                        1, "default-bold", "center", "top")
                end
            end
        end
    end
    -- con la pizza empacada, el borde del mostrador se marca como zona de entrega
    if not tutorial and relevant.pickup then
        local z, c = PIZZERIA.COUNTER, tocolor(255, 200, 50, 120 + pulse * 100)
        local y, zz = z.y2 - 0.55, PIZZERIA.START.z - 0.95
        dxDrawLine3D(z.x1, y, zz, z.x2, y, zz, c, 3)
    end
end

-- Avisa al HUD de donde esta el objetivo en pantalla para poner la tarjeta a su lado (como mucho 10 veces/s)
local lastAnchor = { x = -999, y = -999, t = 0 }
local function sendAnchor(tx, ty, tz, now)
    if now - lastAnchor.t < 100 then return end
    local sx, sy = getScreenFromWorldPosition(tx, ty, tz + 0.8, 0, false)
    sx, sy = sx and math.floor(sx) or -1, sy and math.floor(sy) or -1
    if math.abs(sx - lastAnchor.x) < 10 and math.abs(sy - lastAnchor.y) < 10 then return end
    lastAnchor.x, lastAnchor.y, lastAnchor.t = sx, sy, now
    Pz.hud(("PZ.tutorialAt(%d, %d)"):format(sx, sy))
end

local function drawGuide(px, py, pz, now)
    local t = target
    if not t or focus then return end   -- con foco en el HUD no hay guia 3D: una cosa a la vez
    local tx, ty, tz = t.x, t.y, t.z
    if t.element and isElement(t.element) then tx, ty, tz = getElementPosition(t.element) end
    sendAnchor(tx, ty, tz, now)
    local dist = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
    local pulse = 0.5 + 0.5 * math.sin(now / 180)

    if dist <= 2.6 then
        local el = t.element or ghostOf(t)
        local x1, y1, x2, y2
        if el then x1, y1, x2, y2 = screenBox(el) end
        if x1 then
            local pad = 6 + pulse * 4
            x1, y1, x2, y2 = x1 - pad, y1 - pad, x2 + pad, y2 + pad
            dxDrawRectangle(x1, y1, x2 - x1, y2 - y1, tocolor(255, 255, 255, 18 + pulse * 22))
            corners(x1, y1, x2, y2, math.min(28, (x2 - x1) / 3), tocolor(255, 255, 255, 240), 3)
            -- tecla E sobre el objeto resaltado (Kenney Input Prompts)
            local k = 34 + pulse * 6
            if Pz.keyE then dxDrawImage((x1 + x2) / 2 - k / 2, y1 - k - 6, k, k, Pz.keyE)
            else dxDrawText("E", x1, y1 - 30, x2, y1 - 4, tocolor(255, 255, 255), 1.6, "default-bold", "center", "bottom") end
        end
        return
    end

    local sx, sy = getScreenFromWorldPosition(tx, ty, tz + 0.4, 0, false)
    local green = tocolor(60, 230, 90, 240)
    if sx and sx > 30 and sx < sw - 30 and sy > 30 and sy < sh - 30 then
        local r = 16 + pulse * 6
        corners(sx - r, sy - r, sx + r, sy + r, 9, green, 3)
        dxDrawRectangle(sx - 3, sy - 3, 6, 6, green)
    else
        local cx, cy, _, lx, ly = getCameraMatrix()
        local a = math.atan2(tx - cx, ty - cy) - math.atan2(lx - cx, ly - cy)
        local ex, ey = sw / 2 + math.sin(a) * (sw / 2 - 60), sh / 2 - math.cos(a) * (sh / 2 - 60)
        local fx, fy = math.sin(a), -math.cos(a)
        local qx, qy = -fy, fx
        dxDrawPrimitive("trianglelist", false,
            { ex + fx * 18, ey + fy * 18, green },
            { ex - fx * 10 + qx * 13, ey - fy * 10 + qy * 13, green },
            { ex - fx * 10 - qx * 13, ey - fy * 10 - qy * 13, green })
    end
end

addEventHandler("onClientRender", root, function()
    if not Pz.onShift then
        if ghost then ghostOf(nil) end
        return
    end
    if getElementData(localPlayer, "rp:hudHidden") or isCursorShowing() then return end
    if getElementInterior(localPlayer) ~= PIZZERIA.INTERIOR or getElementDimension(localPlayer) ~= Pz.dim then return end
    local px, py, pz = getElementPosition(localPlayer)
    local now = getTickCount()
    drawStations(px, py, pz, now)
    drawGuide(px, py, pz, now)
end)

----------------------------------------------------------------
-- Enganches con c_pizzeria.lua (encadenados con los de c_customers.lua)
----------------------------------------------------------------
local prevShift, prevFx = Pz.onShiftChanged, Pz.onFx
Pz.onShiftChanged = function(on, dim)
    if prevShift then prevShift(on, dim) end
    tour, target, focus, lastKey, takenAt, relevant = nil, nil, nil, nil, {}, {}
    ghostOf(nil)
end
Pz.onFx = function(kind, data)
    if prevFx then prevFx(kind, data) end
    if kind == "tutorial_done" then tour = { i = 1, untilTick = getTickCount() + OUTRO[1][4] } end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(update, 250, 0)
end)
