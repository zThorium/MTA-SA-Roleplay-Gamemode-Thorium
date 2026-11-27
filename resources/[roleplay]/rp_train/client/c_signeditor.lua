--[[
    rp_train · editor 3D del cartel LED (cliente, solo admins)

    Se abre al crear un cartel (/crearcartel) o con /editarcartel [id]. El cartel se ve en vivo donde
    quedará (c_stations.lua lee SignPreview) con un marco verde y una flecha hacia su frente.
        Flechas         mover adelante/atrás/izquierda/derecha según hacia dónde mira la cámara
        Re Pág / Av Pág subir / bajar
        Z / X           girar
        Mayús           movimiento fino
        Enter           guardar        Retroceso   cancelar
    El servidor valida y guarda (rp:train:signSave, s_stations.lua).
]]

addEvent("rp:train:signEdit", true)

SignPreview = nil -- { el, id, x, y, z, rot }: lo dibuja c_stations.lua en vez de la posición guardada

local W, H = guiGetScreenSize()
local keys        -- texturas de las teclas dibujadas (se crean al abrir el editor por primera vez)
local KEY_FILES = { move = "keyboard_arrows_all", up = "keyboard_page_up", down = "keyboard_page_down",
    z = "keyboard_z", x = "keyboard_x", shift = "keyboard_shift", enter = "keyboard_enter", back = "keyboard_backspace" }

local function typing()
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or isCursorShowing()
end

local function close()
    SignPreview = nil
end

addEventHandler("rp:train:signEdit", resourceRoot, function(el, id, x, y, z, rot)
    if not keys then
        keys = {}
        for k, file in pairs(KEY_FILES) do keys[k] = dxCreateTexture("images/keys/" .. file .. ".png", "argb", true, "clamp") end
    end
    SignPreview = { el = el, id = id, x = x, y = y, z = z, rot = rot }
end)

addEventHandler("onClientPreRender", root, function(dt)
    local s = SignPreview
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
    local step = TRAIN.SIGN_EDIT_SPEED * k
    s.x = s.x + (fx * f + fy * r) * step
    s.y = s.y + (fy * f - fx * r) * step
    s.z = s.z + u * step
    s.rot = (s.rot + t * TRAIN.SIGN_EDIT_TURN * k) % 360
end)

local GREEN = tocolor(80, 230, 120, 230)

local function drawFrame(s)
    local a = math.rad(s.rot)
    local rx, ry = math.cos(a) * TRAIN.SIGN_WIDTH / 2, math.sin(a) * TRAIN.SIGN_WIDTH / 2
    local h = TRAIN.SIGN_HEIGHT / 2 + 0.05
    local x, y, z = s.x, s.y, s.z
    dxDrawLine3D(x - rx, y - ry, z + h, x + rx, y + ry, z + h, GREEN, 3)
    dxDrawLine3D(x - rx, y - ry, z - h, x + rx, y + ry, z - h, GREEN, 3)
    dxDrawLine3D(x - rx, y - ry, z - h, x - rx, y - ry, z + h, GREEN, 3)
    dxDrawLine3D(x + rx, y + ry, z - h, x + rx, y + ry, z + h, GREEN, 3)
    dxDrawLine3D(x, y, z, x - math.sin(a) * 0.8, y + math.cos(a) * 0.8, z, GREEN, 3) -- hacia el frente
end

-- Barra de ayuda con las teclas dibujadas (UX-01)
local HELP = {
    { "move", nil, "Mover" }, { "up", "down", "Subir / bajar" }, { "z", "x", "Girar" },
    { "shift", nil, "Fino" }, { "enter", nil, "Guardar" }, { "back", nil, "Cancelar" },
}

addEventHandler("onClientRender", root, function()
    local s = SignPreview
    if not s then return end
    drawFrame(s)
    local icon, gap, font = 30, 16, "default-bold"
    local total = 0
    for _, e in ipairs(HELP) do total = total + icon * (e[2] and 2 or 1) + 6 + dxGetTextWidth(e[3], 1, font) + gap end
    local x, y = (W - total) / 2, H - 150
    dxDrawRectangle(x - 12, y - 8, total + 12, icon + 16, tocolor(12, 14, 20, 215))
    dxDrawText(("Cartel #%d"):format(s.id), x - 12, y - 30, x + total, y - 10, tocolor(80, 230, 120), 1.1, font)
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
        local s = SignPreview
        if not s or typing() then return end
        triggerServerEvent("rp:train:signSave", resourceRoot, s.id, s.x, s.y, s.z, s.rot)
        close()
    end)
    bindKey("backspace", "down", function()
        if not SignPreview or typing() then return end
        close()
        exports.rp_notify:notify("Edición del cartel cancelada.", "info")
    end)
end)
