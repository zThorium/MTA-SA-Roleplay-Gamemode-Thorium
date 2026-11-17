--[[
    rp_notify / c_notify.lua
    Sistema de notificaciones reutilizable (dibujado con dx, por encima de
    cualquier interfaz CEF gracias a postGUI) con sonido propio.

    Uso desde cualquier recurso cliente:
        exports.rp_notify:notify("Compraste una botella de agua", "success")
        exports.rp_notify:popup("Bienvenido", "Juan Perez llega a Los Santos", "info")
        exports.rp_notify:bubble(ped, "Hola! Pulsa E para comprar", 5000)

    Tipos: "info", "success", "warning", "error"
]]

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.8, math.min(1.25, screenH / 900))

local TYPES = {
    info    = { color = { 70, 150, 255 },  icon = "i", sound = "sounds/info.wav" },
    success = { color = { 76, 211, 138 },  icon = "+", sound = "sounds/success.wav" },
    warning = { color = { 245, 165, 36 },  icon = "!", sound = "sounds/warning.wav" },
    error   = { color = { 255, 107, 107 }, icon = "x", sound = "sounds/error.wav" },
}

local MAX_TOASTS = 5
local TOAST_W = math.floor(340 * scale)
local PAD = math.floor(14 * scale)
local FONT = "default-bold"
local FONT_TEXT = "default"
local TEXT_SCALE = 1.0 * scale

local toasts, popups, bubbles = {}, {}, {}
local muted = false

local function typeOf(kind)
    return TYPES[kind] or TYPES.info
end

local function playNotifySound(path, volume)
    if muted then return end
    local s = playSound(path)
    if s then setSoundVolume(s, volume or 0.6) end
end

-- Divide un texto en lineas que quepan en un ancho dado
local function wrap(text, width, font, size)
    local lines, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if dxGetTextWidth(candidate, size, font) > width and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function easeOut(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function notify(text, kind, duration)
    if type(text) ~= "string" or text == "" then return false end
    local t = typeOf(kind)
    local lines = wrap(text, TOAST_W - PAD * 3 - 26 * scale, FONT_TEXT, TEXT_SCALE)
    table.insert(toasts, 1, {
        lines = lines, type = t, start = getTickCount(),
        duration = tonumber(duration) or math.max(3500, 1800 + #text * 45),
        height = PAD * 2 + #lines * dxGetFontHeight(TEXT_SCALE, FONT_TEXT),
    })
    while #toasts > MAX_TOASTS do table.remove(toasts) end
    playNotifySound(t.sound, 0.55)
    outputConsole("[" .. (kind or "info") .. "] " .. text)
    return true
end

function popup(title, text, kind, duration)
    local t = typeOf(kind)
    popups[#popups + 1] = {
        title = tostring(title or ""), text = tostring(text or ""), type = t,
        start = getTickCount(), duration = tonumber(duration) or 4500,
    }
    if #popups == 1 then playNotifySound("sounds/popup.wav", 0.7) end
    return true
end

function bubble(element, text, duration)
    if not isElement(element) or type(text) ~= "string" then return false end
    bubbles[element] = { text = text, start = getTickCount(), duration = tonumber(duration) or 5000 }
    playNotifySound("sounds/info.wav", 0.35)
    return true
end

function setNotificationsMuted(state)
    muted = state and true or false
    return true
end

----------------------------------------------------------------
-- Eventos desde el servidor
----------------------------------------------------------------
addEvent("rp:notify", true)
addEventHandler("rp:notify", resourceRoot, notify)
addEvent("rp:notify:popup", true)
addEventHandler("rp:notify:popup", resourceRoot, popup)
addEvent("rp:notify:bubble", true)
addEventHandler("rp:notify:bubble", resourceRoot, bubble)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function drawToasts(now)
    local y = math.floor(24 * scale)
    local lineH = dxGetFontHeight(TEXT_SCALE, FONT_TEXT)
    for i = #toasts, 1, -1 do
        if now - toasts[i].start > toasts[i].duration + 400 then table.remove(toasts, i) end
    end
    for _, toast in ipairs(toasts) do
        local age = now - toast.start
        local appear = easeOut(age / 300)
        local leave = 1 - easeOut((age - toast.duration) / 400)
        local alpha = math.min(appear, leave)
        local x = screenW - TOAST_W - 24 * scale + (1 - appear) * 60 + (1 - leave) * 60
        local h = toast.height
        local r, g, b = unpack(toast.type.color)

        dxDrawRectangle(x, y, TOAST_W, h, tocolor(14, 16, 22, 235 * alpha), true)
        dxDrawRectangle(x, y, 4 * scale, h, tocolor(r, g, b, 255 * alpha), true)

        -- Icono
        local ix, iy, is = x + PAD, y + h / 2 - 11 * scale, 22 * scale
        dxDrawRectangle(ix, iy, is, is, tocolor(r, g, b, 60 * alpha), true)
        dxDrawText(toast.type.icon, ix, iy, ix + is, iy + is, tocolor(r, g, b, 255 * alpha), TEXT_SCALE, FONT, "center", "center", false, false, true)

        local tx = ix + is + PAD
        for n, line in ipairs(toast.lines) do
            dxDrawText(line, tx, y + PAD + (n - 1) * lineH, x + TOAST_W - PAD, 0, tocolor(242, 244, 248, 255 * alpha), TEXT_SCALE, FONT_TEXT, "left", "top", false, false, true)
        end

        -- Barra de tiempo restante
        local remaining = math.max(0, 1 - age / toast.duration)
        dxDrawRectangle(x, y + h - 2, TOAST_W * remaining, 2, tocolor(r, g, b, 140 * alpha), true)

        y = y + (h + 10 * scale) * math.min(appear, 1)
    end
end

local function drawPopup(now)
    local p = popups[1]
    if not p then return end
    local age = now - p.start
    if age > p.duration + 500 then
        table.remove(popups, 1)
        if popups[1] then
            popups[1].start = now
            playNotifySound("sounds/popup.wav", 0.7)
        end
        return
    end

    local appear = easeOut(age / 350)
    local leave = 1 - easeOut((age - p.duration) / 500)
    local alpha = math.min(appear, leave)
    local w, h = 460 * scale, 96 * scale
    local x = (screenW - w) / 2
    local y = 90 * scale - (1 - appear) * 30
    local r, g, b = unpack(p.type.color)

    dxDrawRectangle(x, y, w, h, tocolor(14, 16, 22, 240 * alpha), true)
    dxDrawRectangle(x, y, w, 3 * scale, tocolor(r, g, b, 255 * alpha), true)
    dxDrawText(p.title, x, y + 16 * scale, x + w, y + 46 * scale, tocolor(r, g, b, 255 * alpha), 1.6 * scale, FONT, "center", "center", true, false, true)
    dxDrawText(p.text, x + 20 * scale, y + 48 * scale, x + w - 20 * scale, y + h - 10 * scale, tocolor(242, 244, 248, 230 * alpha), TEXT_SCALE, FONT_TEXT, "center", "top", true, true, true)
end

local function drawBubbles(now)
    local cx, cy, cz = getCameraMatrix()
    for element, b in pairs(bubbles) do
        local age = now - b.start
        if not isElement(element) or age > b.duration then
            bubbles[element] = nil
        elseif isElementOnScreen(element) then
            local x, y, z = getElementPosition(element)
            if getElementType(element) == "player" or getElementType(element) == "ped" then
                x, y, z = getPedBonePosition(element, 8)
                z = z + 0.45
            else
                z = z + 1
            end
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
            local sx, sy = getScreenFromWorldPosition(x, y, z)
            if sx and dist < 30 then
                local alpha = math.min(easeOut(age / 250), 1 - easeOut((age - b.duration + 400) / 400))
                local lines = wrap(b.text, 220 * scale, FONT_TEXT, TEXT_SCALE)
                local lineH = dxGetFontHeight(TEXT_SCALE, FONT_TEXT)
                local w = 0
                for _, l in ipairs(lines) do w = math.max(w, dxGetTextWidth(l, TEXT_SCALE, FONT_TEXT)) end
                w = w + 24 * scale
                local h = #lines * lineH + 16 * scale
                local bx, by = sx - w / 2, sy - h - 10 * scale
                dxDrawRectangle(bx, by, w, h, tocolor(250, 250, 252, 235 * alpha), false)
                -- "pico" del globo
                for i = 0, 7 do
                    dxDrawRectangle(sx - (8 - i) * scale, by + h + i * scale, (16 - i * 2) * scale, scale, tocolor(250, 250, 252, 235 * alpha), false)
                end
                for n, l in ipairs(lines) do
                    dxDrawText(l, bx, by + 8 * scale + (n - 1) * lineH, bx + w, 0, tocolor(20, 22, 28, 255 * alpha), TEXT_SCALE, FONT_TEXT, "center", "top")
                end
            end
        end
    end
end

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    drawBubbles(now)
    drawToasts(now)
    drawPopup(now)
end)

addCommandHandler("silenciarnotis", function()
    muted = not muted
    notify(muted and "Sonido de notificaciones desactivado." or "Sonido de notificaciones activado.", "info")
end)
