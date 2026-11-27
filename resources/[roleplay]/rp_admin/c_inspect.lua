--[[
    rp_admin / c_inspect.lua
    Vista de admin: mantener ALT dibuja encima de cada elemento cercano su tipo e ID.
    Lo que esta mas cerca del centro de la pantalla se amplia con dueno, creador, fecha,
    posicion y los comandos para ir hasta el o borrarlo. Los datos los manda el servidor
    (s_inspect.lua) y se refrescan mientras ALT siga pulsado. Solo admins (nivel 1+).
]]

local REFRESH_MS = 1500
local MAX_DRAW_DIST = 75
local FOCUS_PX = 140            -- radio alrededor del centro de la pantalla para ampliar

local COLORS = {
    type    = { 255, 126, 0 },   -- naranja rp_admin: elementos colocados por admins
    house   = { 90, 200, 120 },
    vehicle = { 80, 160, 255 },
    loose   = { 150, 150, 150 },
}

local enabled, active = false, false
local entries, viewInt, viewDim = {}, 0, 0
local refreshTimer
local sw, sh = guiGetScreenSize()
local altIcon = "images/tecla_alt.png"

local function canUse()
    return enabled and not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
end

local function request() triggerServerEvent("rp:admin:inspect:request", resourceRoot) end

-- Globales para c_move.lua
InspectFocus = nil      -- entrada ampliada ahora mismo (la del centro de la pantalla)
InspectPick = nil       -- callback del menu del cursor cuando llegan sus datos
function isInspectEnabled() return enabled end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function worldPos(e)
    if e.elem then
        if not isElement(e.elem) then return nil end
        local x, y, z = getElementPosition(e.elem)
        local lift = e.kind == "vehicle" and 1.3 or 0.6
        return x, y, z + lift
    end
    return e.x, e.y, e.z + 1.0
end

local function title(e)
    if e.kind == "loose" then
        return ("%s · %s"):format(e.res or "?", e.info or e.etype)
    elseif e.kind == "vehicle" then
        return e.id and ("Vehiculo #%d · %s"):format(e.id, e.label or "") or ("Vehiculo temporal · %s"):format(e.label or "")
    end
    return ("%s #%d"):format(e.typeName or "?", e.id or 0)
end

local function subtitle(e)
    if e.owner then return "Dueno: " .. e.owner end
    if e.creator then return "Creado por " .. e.creator end
    if e.kind == "house" then return "En venta" end
    if e.kind == "vehicle" and not e.id then return e.res or "" end
    return nil
end

local function detailLines(e, x, y, z)
    local lines = {}
    local function add(text) if text and text ~= "" then lines[#lines + 1] = text end end
    if e.kind ~= "loose" then add(e.label) end
    add(e.info)
    if e.kind == "house" or e.kind == "vehicle" then
        add(e.owner and ("Dueno: " .. e.owner) or (e.id and "Sin dueno" or nil))
    end
    if e.kind ~= "loose" and e.kind ~= "vehicle" then
        add(e.creator and ("Creado por " .. e.creator) or "Creador: sin registro (anterior a la vista ALT)")
    end
    add(e.createdAt and ("Fecha: " .. e.createdAt) or nil)
    add(("Recurso: %s"):format(e.res or "?"))
    if e.elementId and e.elementId ~= "" then add("ID de elemento: " .. e.elementId) end
    add(("Pos: %.2f, %.2f, %.2f  ·  int %d  dim %d"):format(x, y, z, viewInt, viewDim))
    if e.kind == "type" or e.kind == "house" then
        add(("/goto%s %d   ·   /del%s %d"):format(e.key, e.id, e.key, e.id))
        add("Clic derecho = mover")
    elseif e.kind == "vehicle" and e.id then
        add(("/gotoveh %d   ·   /getveh %d   ·   /vehinfo"):format(e.id, e.id))
    end
    return lines
end

local function drawTag(sx, sy, e, alpha, focused)
    local c = COLORS[e.kind] or COLORS.loose
    local scale = focused and 1.1 or (e.kind == "loose" and 0.85 or 1)
    local font = "default-bold"
    local t = title(e)
    local sub = not focused and subtitle(e) or nil
    local fh = dxGetFontHeight(scale, font)
    local tw = dxGetTextWidth(t, scale, font)
    local subw = sub and dxGetTextWidth(sub, scale * 0.9, "default") or 0
    local w = math.max(tw, subw) + 16
    local h = fh + 8 + (sub and fh or 0)
    local x0, y0 = sx - w / 2, sy - h
    dxDrawRectangle(x0, y0, w, h, tocolor(15, 15, 18, 200 * alpha))
    dxDrawRectangle(x0, y0, 3, h, tocolor(c[1], c[2], c[3], 255 * alpha))
    dxDrawText(t, x0 + 9, y0 + 4, x0 + w, y0 + 4 + fh, tocolor(c[1], c[2], c[3], 255 * alpha), scale, font)
    if sub then
        dxDrawText(sub, x0 + 9, y0 + 4 + fh, x0 + w, y0 + h, tocolor(220, 220, 220, 230 * alpha), scale * 0.9, "default")
    end

    if not focused then return end
    local x, y, z = e.x, e.y, e.z
    if e.elem then x, y, z = getElementPosition(e.elem) end
    local lines = detailLines(e, x, y, z)
    local lh = dxGetFontHeight(1, "default") + 2
    local dw = w
    for _, l in ipairs(lines) do dw = math.max(dw, dxGetTextWidth(l, 1, "default") + 18) end
    local dy = sy + 2
    dxDrawRectangle(sx - dw / 2, dy, dw, #lines * lh + 8, tocolor(15, 15, 18, 225))
    dxDrawRectangle(sx - dw / 2, dy, 3, #lines * lh + 8, tocolor(c[1], c[2], c[3], 255))
    for i, l in ipairs(lines) do
        local isCmd = l:sub(1, 1) == "/"
        dxDrawText(l, sx - dw / 2 + 9, dy + 4 + (i - 1) * lh, 0, 0,
            isCmd and tocolor(255, 200, 120, 255) or tocolor(235, 235, 235, 255), 1, "default")
    end
end

local stop

local function render()
    if not canUse() then return end
    if not getKeyState("lalt") and not getKeyState("ralt") then return stop() end
    if isMoveEditorOpen and isMoveEditorOpen() then return stop() end
    local cx, cy, cz = getCameraMatrix()
    local visible, focus, focusD = {}, nil, FOCUS_PX
    for _, e in ipairs(entries) do
        local x, y, z = worldPos(e)
        if x then
            local d = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
            if d <= MAX_DRAW_DIST then
                local sx, sy = getScreenFromWorldPosition(x, y, z, 0.05)
                if sx then
                    local v = { e = e, sx = sx, sy = sy, d = d }
                    visible[#visible + 1] = v
                    local pd = math.sqrt((sx - sw / 2) ^ 2 + (sy - sh / 2) ^ 2)
                    if pd < focusD then focus, focusD = v, pd end
                end
            end
        end
    end
    -- Lejos primero para que lo cercano quede encima; el ampliado al final
    table.sort(visible, function(a, b) return a.d > b.d end)
    for _, v in ipairs(visible) do
        if v ~= focus then
            local alpha = math.max(0.35, 1 - v.d / MAX_DRAW_DIST)
            drawTag(v.sx, v.sy, v.e, alpha, false)
        end
    end
    InspectFocus = focus and focus.e or nil
    if focus then drawTag(focus.sx, focus.sy, focus.e, 1, true) end

    -- Cabecera: tecla dibujada + resumen (UX-01)
    local text = ("Vista de admin  ·  %d elementos  ·  int %d  dim %d  ·  mira algo para ver su ficha")
        :format(#visible, viewInt, viewDim)
    local tw = dxGetTextWidth(text, 1, "default-bold")
    local w = tw + 60
    local x0, y0 = (sw - w) / 2, 24
    dxDrawRectangle(x0, y0, w, 36, tocolor(15, 15, 18, 210))
    dxDrawImage(x0 + 6, y0 + 2, 32, 32, altIcon)
    dxDrawText(text, x0 + 46, y0, x0 + w, y0 + 36, tocolor(255, 255, 255, 255), 1, "default-bold", "left", "center")
    -- Punto de mira para saber que se va a ampliar
    dxDrawRectangle(sw / 2 - 2, sh / 2 - 2, 4, 4, tocolor(255, 126, 0, 200))
end

----------------------------------------------------------------
-- Tecla
----------------------------------------------------------------
function stop()
    if not active then return end
    active = false
    InspectFocus = nil
    removeEventHandler("onClientRender", root, render)
    if isTimer(refreshTimer) then killTimer(refreshTimer) end
    refreshTimer = nil
    entries = {}
end

local function onAlt(_, state)
    if state == "down" then
        if active or not canUse() or (isMoveEditorOpen and isMoveEditorOpen()) then return end
        active = true
        request()
        refreshTimer = setTimer(request, REFRESH_MS, 0)
        addEventHandler("onClientRender", root, render)
    elseif not getKeyState("lalt") and not getKeyState("ralt") then
        stop()
    end
end

addEvent("rp:admin:inspect:enable", true)
addEventHandler("rp:admin:inspect:enable", resourceRoot, function(on)
    enabled = on == true
    if not enabled then stop() end
end)

addEvent("rp:admin:inspect:data", true)
addEventHandler("rp:admin:inspect:data", resourceRoot, function(list, int, dim, forPick)
    if type(list) ~= "table" then return end
    if forPick then
        if InspectPick then InspectPick(list, tonumber(int) or 0, tonumber(dim) or 0) end
        return
    end
    if not active then return end
    entries, viewInt, viewDim = list, tonumber(int) or 0, tonumber(dim) or 0
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("lalt", "both", onAlt)
    bindKey("ralt", "both", onAlt)
    -- ALT + clic derecho sobre lo que se mira: abrir el editor para moverlo (c_move.lua)
    bindKey("mouse2", "down", function()
        if active and canUse() and InspectFocus and openMoveEditor then openMoveEditor(InspectFocus) end
    end)
end)

-- Si se pierde el foco con ALT pulsado (Alt+Tab) no llega el "up"
addEventHandler("onClientMinimize", root, stop)
