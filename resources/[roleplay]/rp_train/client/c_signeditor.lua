--[[
    rp_train · editor 3D de carteles LED, torniquetes y rejas (cliente, solo admins)

    Se abre al crear uno (/crearcartel, /creartorniquete, /crearreja) o con /editarcartel,
    /editartorniquete y /editarreja [id]. Lo editado se ve en vivo donde quedará, con un marco verde:
        Flechas         mover adelante/atrás/izquierda/derecha según hacia dónde mira la cámara
        Re Pág / Av Pág subir / bajar
        Z / X           girar
        Mayús           movimiento fino
        Enter           guardar        Retroceso   cancelar
        /duplicar <cantidad> <x> <y> <z> [rot]
                        copias en fila: cada una a x, y, z metros de la anterior (ejes del mundo, dibujados
                        en rojo X, azul Y, amarillo Z) y girada rot grados; se ven antes de guardar con Enter
    Mientras editas, tu personaje queda congelado.
    - Cartel: lo dibuja c_stations.lua en la posición de SignPreview.
    - Torniquete: se mueven aquí (solo en tu juego) el poste y el brazo con TrainGateLayout; el marco marca el
      paso, con ENTRADA (lado del boleto) y ANDÉN.
    - Reja: se mueve el objeto en tu juego; el marco es su caja.
    El servidor valida y guarda (rp:train:fixtureSave, s_stations.lua) y coloca las piezas para todos.
]]

addEvent("rp:train:fixtureEdit", true)
addEvent("rp:train:fixtureEditFailed", true)

SignPreview = nil -- { el, id, x, y, z, rot }: lo dibuja c_stations.lua en vez de la posición guardada

local W, H = guiGetScreenSize()
local edit        -- { kind, el, id, x, y, z, rot, post, arm, orig = { x, y, z, rot } }
local restoreLater -- pieza editada y su posición original, por si el servidor rechaza el guardado
local keys        -- texturas de las teclas dibujadas (se crean al abrir el editor por primera vez)
local KEY_FILES = { move = "keyboard_arrows_all", up = "keyboard_page_up", down = "keyboard_page_down",
    z = "keyboard_z", x = "keyboard_x", shift = "keyboard_shift", enter = "keyboard_enter", back = "keyboard_backspace" }
local TITLE = { sign = "Cartel", gate = "Torniquete", fence = "Reja", pole = "Poste de metro" }
local OBJECT_KIND = { fence = true, pole = true } -- un solo objeto que se mueve tal cual

local function typing()
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or isCursorShowing()
end

-- Coloca en tu juego las piezas del torniquete o la reja en (x, y, z, rot)
local function placeLocal(e, x, y, z, rot)
    if e.kind == "gate" then
        local px, py, postZ, armZ = TrainGateLayout(x, y, z, rot)
        if isElement(e.post) then setElementPosition(e.post, px, py, postZ) setElementRotation(e.post, 0, 0, rot) end
        if isElement(e.arm) then setElementPosition(e.arm, px, py, armZ) setElementRotation(e.arm, 0, 90 * TRAIN.GATE_ARM_SIDE, rot) end
    elseif OBJECT_KIND[e.kind] and isElement(e.el) then
        setElementPosition(e.el, x, y, z)
        setElementRotation(e.el, 0, 0, rot)
    end
end

local frozeMe = false -- el editor congeló al personaje (lo descongela al cerrar)

local function close(restore)
    if edit and restore then placeLocal(edit, edit.orig.x, edit.orig.y, edit.orig.z, edit.orig.rot) end
    edit, SignPreview = nil, nil
    if frozeMe then setElementFrozen(localPlayer, false) frozeMe = false end
end

addEventHandler("rp:train:fixtureEdit", resourceRoot, function(kind, el, id, x, y, z, rot, post, arm)
    if not keys then
        keys = {}
        for k, file in pairs(KEY_FILES) do keys[k] = dxCreateTexture("images/keys/" .. file .. ".png", "argb", true, "clamp") end
    end
    close(true)
    edit = { kind = kind, el = el, id = id, x = x, y = y, z = z, rot = rot, post = post or nil, arm = arm or nil,
        orig = { x = x, y = y, z = z, rot = rot } }
    if kind == "sign" then SignPreview = edit end
    if not isElementFrozen(localPlayer) then setElementFrozen(localPlayer, true) frozeMe = true end
end)

-- /duplicar <cantidad> <x> <y> <z> [rot]: prepara copias en fila del objeto que se edita (se ven en el
-- editor y se crean al guardar con Enter). /duplicar 0 las quita. El servidor vuelve a validar los límites.
addCommandHandler("duplicar", function(_, n, x, y, z, rot)
    if not edit then
        return exports.rp_notify:notify("Primero abre el editor: /editartorniquete, /editarreja, /editarcartel o /editarpostemetro.", "warning")
    end
    n = math.floor(tonumber(n) or -1)
    if n == 0 then
        edit.dup = nil
        return exports.rp_notify:notify("Duplicado quitado.", "info")
    end
    x, y, z, rot = tonumber(x), tonumber(y), tonumber(z), tonumber(rot) or 0
    if n < 1 or not (x and y and z) then
        return exports.rp_notify:notify("Uso: /duplicar <cantidad> <x> <y> <z> [rot] · ej.: /duplicar 6 1.6 0 0 0", "warning")
    end
    if n > TRAIN.DUP_MAX or math.sqrt(x * x + y * y + z * z) > TRAIN.DUP_STEP_MAX then
        return exports.rp_notify:notify(("Máximo %d copias y %d m entre cada una."):format(TRAIN.DUP_MAX, TRAIN.DUP_STEP_MAX), "warning")
    end
    edit.dup = { n = n, dx = x, dy = y, dz = z, drot = rot }
    exports.rp_notify:notify(("%d copias preparadas (se ven en verde claro). Enter guarda y las crea; /duplicar 0 las quita."):format(n), "info")
end)

addEventHandler("rp:train:fixtureEditFailed", resourceRoot, function()
    if restoreLater then
        local e = restoreLater
        placeLocal(e, e.orig.x, e.orig.y, e.orig.z, e.orig.rot)
        restoreLater = nil
    end
end)

addEventHandler("onClientPreRender", root, function(dt)
    local s = edit
    if not s then return end
    if not isElement(s.el) then return close() end
    if typing() then return end
    local k = dt / 1000 * ((getKeyState("lshift") or getKeyState("rshift")) and TRAIN.SIGN_EDIT_FINE or 1)
    -- adelante y derecha según la cámara (en el plano del suelo)
    local cx, cy, _, lx, ly = getCameraMatrix()
    local fx, fy = lx - cx, ly - cy
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 0.001 then return end
    fx, fy = fx / len, fy / len
    local f = (getKeyState("arrow_u") and 1 or 0) - (getKeyState("arrow_d") and 1 or 0)
    local r = (getKeyState("arrow_r") and 1 or 0) - (getKeyState("arrow_l") and 1 or 0)
    local u = (getKeyState("pgup") and 1 or 0) - (getKeyState("pgdn") and 1 or 0)
    local t = (getKeyState("z") and 1 or 0) - (getKeyState("x") and 1 or 0)
    if f == 0 and r == 0 and u == 0 and t == 0 then return end
    local step = TRAIN.SIGN_EDIT_SPEED * k
    s.x = s.x + (fx * f + fy * r) * step
    s.y = s.y + (fy * f - fx * r) * step
    s.z = s.z + u * step
    s.rot = (s.rot + t * TRAIN.SIGN_EDIT_TURN * k) % 360
    placeLocal(s, s.x, s.y, s.z, s.rot)
end)

----------------------------------------------------------------
-- Marcos verdes
----------------------------------------------------------------
local GREEN = tocolor(80, 230, 120, 230)
local COPY = tocolor(170, 255, 200, 150) -- copias de /duplicar
local LINE = GREEN

-- Rectángulo girado rot grados: medio ancho hw (a lo ancho), medio fondo hd (hacia el frente), de z0 a z1
local function box(x, y, z0, z1, rot, hw, hd, ox, oy)
    local GREEN = LINE
    local a = math.rad(rot)
    local rx, ry = math.cos(a), math.sin(a)      -- derecha
    local fx, fy = -math.sin(a), math.cos(a)     -- frente
    ox, oy = ox or 0, oy or 0
    local c = {}
    for i, s in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
        local w, d = ox + s[1] * hw, oy + s[2] * hd
        c[i] = { x + rx * w + fx * d, y + ry * w + fy * d }
    end
    for i = 1, 4 do
        local p, q = c[i], c[i % 4 + 1]
        dxDrawLine3D(p[1], p[2], z0, q[1], q[2], z0, GREEN, 3)
        if z1 then
            dxDrawLine3D(p[1], p[2], z1, q[1], q[2], z1, GREEN, 3)
            dxDrawLine3D(p[1], p[2], z0, p[1], p[2], z1, GREEN, 3)
        end
    end
end

local function label3D(x, y, z, text)
    local sx, sy = getScreenFromWorldPosition(x, y, z)
    if sx then dxDrawText(text, sx - 100, sy - 12, sx + 100, sy + 12, tocolor(80, 230, 120), 1.2, "default-bold", "center", "center") end
end

local function drawFrame(s, copy)
    LINE = copy and COPY or GREEN
    local GREEN = LINE
    local label3D = copy and function() end or label3D
    local a = math.rad(s.rot)
    local fx, fy = -math.sin(a), math.cos(a)
    if s.kind == "sign" then
        local h = TRAIN.SIGN_HEIGHT / 2 + 0.05
        box(s.x, s.y, s.z - h, s.z + h, s.rot, TRAIN.SIGN_WIDTH / 2, 0.02)
        dxDrawLine3D(s.x, s.y, s.z, s.x + fx * 0.8, s.y + fy * 0.8, s.z, GREEN, 3) -- hacia el frente
    elseif s.kind == "gate" then
        local gz = s.z - 0.95
        box(s.x, s.y, gz, nil, s.rot, TRAIN.GATE_HALF_WIDTH, 0.35)
        dxDrawLine3D(s.x - fx * 0.8, s.y - fy * 0.8, gz, s.x + fx * 1.2, s.y + fy * 1.2, gz, GREEN, 4)
        label3D(s.x + fx * 1.5, s.y + fy * 1.5, gz + 0.3, "ANDÉN")
        label3D(s.x - fx * 1.2, s.y - fy * 1.2, gz + 0.3, "ENTRADA (boleto)")
    elseif OBJECT_KIND[s.kind] and isElement(s.el) then
        local x0, y0, z0, x1, y1, z1 = getElementBoundingBox(s.el)
        if x0 then
            box(s.x, s.y, s.z + z0, s.z + z1, s.rot, (x1 - x0) / 2, (y1 - y0) / 2, (x0 + x1) / 2, (y0 + y1) / 2)
        end
    end
end

-- Barra de ayuda con las teclas dibujadas (UX-01)
local HELP = {
    { "move", nil, "Mover" }, { "up", "down", "Subir / bajar" }, { "z", "x", "Girar" },
    { "shift", nil, "Fino" }, { "enter", nil, "Guardar" }, { "back", nil, "Cancelar" },
}

addEventHandler("onClientRender", root, function()
    local s = edit
    if not s then return end
    drawFrame(s)
    -- copias de /duplicar donde quedarán
    local d = s.dup
    if d then
        for i = 1, d.n do
            drawFrame({ kind = s.kind, el = s.el, x = s.x + d.dx * i, y = s.y + d.dy * i, z = s.z + d.dz * i,
                rot = (s.rot + d.drot * i) % 360 }, true)
        end
    end
    -- ejes del mundo para elegir las coordenadas de /duplicar
    local ax, ay, az = s.x, s.y, s.z + 0.2
    dxDrawLine3D(ax, ay, az, ax + 1.5, ay, az, tocolor(255, 70, 60), 3)
    dxDrawLine3D(ax, ay, az, ax, ay + 1.5, az, tocolor(70, 140, 255), 3)
    dxDrawLine3D(ax, ay, az, ax, ay, az + 1.2, tocolor(255, 220, 60), 3)
    for _, e in ipairs({ { 1.7, 0, 0, "+X", tocolor(255, 70, 60) }, { 0, 1.7, 0, "+Y", tocolor(70, 140, 255) }, { 0, 0, 1.4, "+Z", tocolor(255, 220, 60) } }) do
        local sx, sy = getScreenFromWorldPosition(ax + e[1], ay + e[2], az + e[3])
        if sx then dxDrawText(e[4], sx - 20, sy - 10, sx + 20, sy + 10, e[5], 1.2, "default-bold", "center", "center") end
    end
    local icon, gap, font = 30, 16, "default-bold"
    local total = 0
    for _, e in ipairs(HELP) do total = total + icon * (e[2] and 2 or 1) + 6 + dxGetTextWidth(e[3], 1, font) + gap end
    local x, y = (W - total) / 2, H - 150
    dxDrawRectangle(x - 12, y - 8, total + 12, icon + 16, tocolor(12, 14, 20, 215))
    local info = ("%s #%d · X %.2f  Y %.2f  Z %.2f  rot %.1f°"):format(TITLE[s.kind] or "Objeto", s.id, s.x, s.y, s.z, s.rot)
    if d then info = info .. ("  ·  +%d copias"):format(d.n) end
    dxDrawText(info, x - 12, y - 30, x + total, y - 10, tocolor(80, 230, 120), 1.1, font)
    dxDrawText("/duplicar <cantidad> <x> <y> <z> [rot]  ·  copias en fila", x - 12, y + icon + 10, x + total, y + icon + 30,
        tocolor(170, 178, 190), 1, font)
    for _, e in ipairs(HELP) do
        dxDrawImage(x, y, icon, icon, keys[e[1]])
        x = x + icon
        if e[2] then dxDrawImage(x, y, icon, icon, keys[e[2]]) x = x + icon end
        x = x + 6
        dxDrawText(e[3], x, y, x + 200, y + icon, tocolor(242, 244, 248), 1, font, "left", "center")
        x = x + dxGetTextWidth(e[3], 1, font) + gap
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("enter", "down", function()
        local s = edit
        if not s or typing() then return end
        triggerServerEvent("rp:train:fixtureSave", resourceRoot, s.id, s.x, s.y, s.z, s.rot, s.dup or false)
        restoreLater = s
        close()
    end)
    bindKey("backspace", "down", function()
        if not edit or typing() then return end
        local name = TITLE[edit.kind] or "objeto"
        close(true)
        exports.rp_notify:notify(("Edición cancelada (%s)."):format(name:lower()), "info")
    end)
end)

addEventHandler("onClientResourceStop", resourceRoot, function() close(true) end)

-- Morir con el editor abierto: se cancela (y se descongela)
addEventHandler("onClientPlayerWasted", localPlayer, function() if edit then close(true) end end)
