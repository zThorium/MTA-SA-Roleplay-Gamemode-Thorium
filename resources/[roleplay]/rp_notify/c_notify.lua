--[[
    rp_notify / c_notify.lua
    Notificaciones de Thorium, dibujadas con dx (postGUI: por encima del CEF).

    Uso desde cualquier recurso cliente (la API no cambia):
        exports.rp_notify:notify("Compraste una botella de agua", "success")
        exports.rp_notify:popup("Bienvenido", "Juan Perez llega a Los Santos", "info")
        exports.rp_notify:bubble(ped, "Hola! Pulsa E para comprar", 5000)
    Tipos: "info", "success", "warning", "error" y "level" (dorado, para subidas de nivel)

    Diseño ("señal"):
      - Toast: tarjeta con el borde izquierdo en diagonal. Entra con un barrido del
        color del tipo que se recoge en la franja lateral, un brillo que la cruza y un
        pulso que sale del icono. El aro del icono es el tiempo que le queda.
        Cada tipo tiene su gesto: chispas (hecho), sacudida (error), latido (atención).
        El mismo aviso repetido no se apila: suma "x2", "x3"...
      - Popup: titular en una banda que se abre desde el centro; las letras del
        título se juntan, dos líneas de luz se extienden y el subtítulo aparece después.
      - Globo: bocadillo redondeado que salta, se escala con la distancia y escribe el
        texto letra a letra.
    Sonidos de Kenney (CC0) de la paleta estándar de assets/README.md. Fuentes: Rubik (OFL) para
    leer y Kenney Future (CC0) solo en etiquetas cortas y el titular. Formas suavizadas con c_dx.lua.
    Mientras el HUD está suprimido (cinemáticas, foto) los toasts y popups se pausan.
]]

local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.35, screenH / 900))
local function px(v) return math.floor(v * S + 0.5) end

----------------------------------------------------------------
-- Recursos gráficos y sonidos (se crean una vez)
----------------------------------------------------------------
local function font(file, size, fallback)
    return dxCreateFont("fonts/" .. file, size, false, "antialiased") or fallback
end
local F_LABEL = font("kenney_future.ttf", math.floor(8 * S + 0.5), "default-bold")
local F_BODY = font("rubik_medium.ttf", math.floor(10 * S + 0.5), "default")
local F_TITLE = font("kenney_future.ttf", math.floor(24 * S + 0.5), "default-bold")
local F_SUB = font("rubik_regular.ttf", math.floor(12 * S + 0.5), "default")
local F_BUBBLE = font("rubik_medium.ttf", math.floor(13 * S + 0.5), "default")

local TYPES = {
    info    = { color = { 86, 168, 255 },  label = "INFO",     glyph = "info",  sound = "glass_001.ogg",        popSound = "bong_001.ogg" },
    success = { color = { 72, 222, 140 },  label = "HECHO",    glyph = "check", sound = "confirmation_002.ogg", popSound = "confirmation_003.ogg" },
    warning = { color = { 255, 178, 46 },  label = "ATENCIÓN", glyph = "bang",  sound = "question_001.ogg",     popSound = "bong_001.ogg" },
    error   = { color = { 255, 84, 96 },   label = "ERROR",    glyph = "cross", sound = "error_004.ogg",        popSound = "error_004.ogg" },
    -- Subida de nivel (rp_levels): dorado; el popup no suena porque rp_levels pone su propio sonido
    level   = { color = { 255, 196, 64 },  label = "NIVEL",    glyph = "up",    sound = "confirmation_003.ogg", popSound = nil },
}
local function typeOf(kind) return TYPES[kind] or TYPES.info end

local MAX_TOASTS = 4
local TOAST_W = px(330)
local SKEW = px(12)
local PAD = px(12)
local BADGE_R = px(15)
local GAP = px(8)
local MARGIN_R = px(22)
local TEXT_X = SKEW + PAD + BADGE_R * 2 + PAD     -- donde empieza el texto dentro de la tarjeta
local TEXT_W = TOAST_W - TEXT_X - PAD
local LABEL_H = dxGetFontHeight(1, F_LABEL)
local BODY_H = dxGetFontHeight(1, F_BODY)

local toasts, popups, bubbles, sparks = {}, {}, {}, {}
local userMuted, externalMuted = false, false
local PREFS_FILE = "@notify_prefs.xml"

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeIn(t) t = clamp(t, 0, 1); return t * t * t end
local function easeOutBack(t)
    t = clamp(t, 0, 1)
    local c = 1.70158
    return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function rgba(c, a) return tocolor(c[1], c[2], c[3], clamp(a, 0, 255)) end

-- Divide un texto en líneas que quepan en un ancho dado (solo al crear, nunca por frame)
local function wrap(text, width, fnt, maxLines)
    local lines, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if line ~= "" and dxGetTextWidth(candidate, 1, fnt) > width then
            lines[#lines + 1] = line
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    if maxLines and #lines > maxLines then
        lines[maxLines] = lines[maxLines] .. "..."
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
    end
    return lines
end

-- Formas con antialiasing: c_dx.lua (DX.*)
local function circle(cx, cy, r, color, postGUI) DX.circle(cx, cy, r, color, postGUI) end
local function ring(cx, cy, r, thick, a0, a1, color, postGUI) DX.ring(cx, cy, r, thick, a0, a1, color, postGUI) end
local function roundRect(x, y, w, h, r, color, postGUI) DX.roundRect(x, y, w, h, r, color, postGUI) end

-- Cuadrilátero con un color por esquina, sin suavizar (degradados de fondo y brillos, que ya son difusos):
-- arriba-izq, arriba-der, abajo-izq, abajo-der
local function quad(x1, y1, x2, y2, x3, y3, x4, y4, c1, c2, c3, c4, postGUI)
    dxDrawPrimitive("trianglestrip", postGUI, { x1, y1, c1 }, { x2, y2, c2 or c1 }, { x3, y3, c3 or c1 }, { x4, y4, c4 or c2 or c1 })
end

-- Paralelogramo con el borde izquierdo en diagonal, suavizado: colores izquierda y derecha
local function slanted(x, y, w, h, skew, cl, cr, postGUI)
    DX.poly({ { x + skew, y, cl }, { x + w, y, cr }, { x + w, y + h, cr }, { x, y + h, cl } }, postGUI)
end

-- Iconos vectoriales (nítidos a cualquier escala, con extremos redondos)
local function drawGlyph(glyph, cx, cy, r, color)
    local w = math.max(2, px(2.6))
    if glyph == "check" then
        DX.line(cx - r * 0.40, cy + r * 0.02, cx - r * 0.12, cy + r * 0.30, w, color, true, true)
        DX.line(cx - r * 0.12, cy + r * 0.30, cx + r * 0.42, cy - r * 0.28, w, color, true, true)
    elseif glyph == "cross" then
        DX.line(cx - r * 0.30, cy - r * 0.30, cx + r * 0.30, cy + r * 0.30, w, color, true, true)
        DX.line(cx + r * 0.30, cy - r * 0.30, cx - r * 0.30, cy + r * 0.30, w, color, true, true)
    elseif glyph == "bang" then
        DX.line(cx, cy - r * 0.44, cx, cy + r * 0.08, w, color, true, true)
        circle(cx, cy + r * 0.40, w * 0.62, color, true)
    elseif glyph == "up" then
        DX.line(cx, cy + r * 0.44, cx, cy - r * 0.36, w, color, true, true)
        DX.line(cx - r * 0.32, cy - r * 0.06, cx, cy - r * 0.40, w, color, true, true)
        DX.line(cx + r * 0.32, cy - r * 0.06, cx, cy - r * 0.40, w, color, true, true)
    else -- info
        circle(cx, cy - r * 0.42, w * 0.62, color, true)
        DX.line(cx, cy - r * 0.08, cx, cy + r * 0.44, w, color, true, true)
    end
end

----------------------------------------------------------------
-- Sonido (nunca en ráfaga: el mismo no se repite antes de 150 ms)
----------------------------------------------------------------
local lastSound, lastAny = {}, 0
local function playNotifySound(file, volume)
    if not file or userMuted or externalMuted then return end
    local now = getTickCount()
    if (lastSound[file] and now - lastSound[file] < 150) or now - lastAny < 50 then return end
    lastSound[file], lastAny = now, now
    local s = playSound("sounds/" .. file)
    if s then setSoundVolume(s, volume or 0.5) end
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function notify(text, kind, duration)
    if type(text) ~= "string" or text == "" then return false end
    local t = typeOf(kind)
    local now = getTickCount()
    outputConsole("[" .. tostring(kind or "info") .. "] " .. text)

    -- El mismo aviso que sigue en pantalla no se apila: cuenta x2, x3...
    for _, toast in ipairs(toasts) do
        if toast.text == text and toast.type == t and now - toast.start < toast.duration then
            toast.count = toast.count + 1
            toast.bump = now
            toast.start = now - 500           -- reinicia el tiempo sin repetir la entrada
            playNotifySound("tick_002.ogg", 0.4)
            return true
        end
    end

    local lines = wrap(text, TEXT_W, F_BODY, 5)
    local h = math.max(PAD * 2 + BADGE_R * 2, PAD * 2 + LABEL_H + px(2) + #lines * BODY_H)
    table.insert(toasts, 1, {
        text = text, lines = lines, type = t, start = now, count = 1, bump = 0,
        duration = tonumber(duration) or math.max(3800, 2000 + #text * 45),
        h = h, y = nil, sparked = false,
    })
    -- Si sobran, el más viejo sale (con su animación) en vez de desaparecer de golpe
    local alive = 0
    for _, toast in ipairs(toasts) do
        if now - toast.start < toast.duration then
            alive = alive + 1
            if alive > MAX_TOASTS then toast.duration = now - toast.start end
        end
    end
    playNotifySound(t.sound, 0.5)
    return true
end

function popup(title, text, kind, duration)
    local t = typeOf(kind)
    title, text = tostring(title or ""), tostring(text or "")
    local chars, widths, total = {}, {}, 0
    for i = 1, utf8.len(title) or 0 do
        local ch = utf8.sub(title, i, i)
        chars[i] = ch
        widths[i] = dxGetTextWidth(ch, 1, F_TITLE)
        total = total + widths[i]
    end
    popups[#popups + 1] = {
        chars = chars, widths = widths, titleW = total, type = t,
        sub = wrap(text, px(560), F_SUB, 3),
        start = getTickCount(), duration = tonumber(duration) or 4500,
    }
    if #popups == 1 then playNotifySound(t.popSound, 0.6) end
    return true
end

function bubble(element, text, duration)
    if not isElement(element) or type(text) ~= "string" then return false end
    local lines = wrap(text, px(300), F_BUBBLE, 7)
    local widths, w = {}, 0
    for n, l in ipairs(lines) do
        widths[n] = dxGetTextWidth(l, 1, F_BUBBLE)
        w = math.max(w, widths[n])
    end
    -- Tiempo mínimo para que termine de escribirse (60 letras/s) y dé tiempo a leerlo
    local readMs = 1500 + (utf8.len(text) or #text) * 70
    bubbles[element] = {
        lines = lines, widths = widths,
        w = w + px(30), h = #lines * dxGetFontHeight(1, F_BUBBLE) + px(22),
        start = getTickCount(), duration = math.max(tonumber(duration) or 5000, readMs),
    }
    playNotifySound("pluck_002.ogg", 0.35)
    return true
end

-- Lo usa rp_hud mientras el HUD está suprimido. No pisa la preferencia del jugador (/silenciarnotis).
function setNotificationsMuted(state)
    externalMuted = state and true or false
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
-- Chispas (VFX de "hecho")
----------------------------------------------------------------
local function burst(x, y, c)
    local now = getTickCount()
    for i = 1, 12 do
        local a = math.rad(math.random(0, 359))
        local v = (math.random(60, 160) / 1000) * S
        sparks[#sparks + 1] = {
            x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - 0.06 * S,
            born = now, life = math.random(450, 750), size = math.random(2, 4) * S, c = c,
        }
    end
end

local function drawSparks(now, dt)
    for i = #sparks, 1, -1 do
        local p = sparks[i]
        local k = (now - p.born) / p.life
        if k >= 1 then
            table.remove(sparks, i)
        else
            p.vy = p.vy + 0.00035 * S * dt
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            local sz = p.size * (1 - k * 0.5)
            circle(p.x, p.y, sz / 2, rgba(p.c, 255 * (1 - k)), true)
        end
    end
end

----------------------------------------------------------------
-- Toasts
----------------------------------------------------------------
local topCache, topCacheAt = px(160), 0
local function stackTop(now)
    if now - topCacheAt > 500 then
        topCacheAt = now
        -- Debajo del bloque de arriba a la derecha del HUD (dinero, estrellas) para no taparlo
        local hud, v = getResourceFromName("rp_hud"), nil
        if hud and getResourceState(hud) == "running" then
            local ok, r = pcall(function() return exports.rp_hud:getTopRightBottom() end)
            if ok then v = tonumber(r) end
        end
        topCache = v and (v + px(14)) or px(160)
    end
    return topCache
end

local function drawToast(toast, now, x, y, a)
    local age = now - toast.start
    local c, h, W = toast.type.color, toast.h, TOAST_W

    -- Error: sacudida corta
    if toast.type.glyph == "cross" and age < 480 then
        x = x + math.sin(age * 0.09) * px(7) * (1 - age / 480)
    end

    -- Sombra y tarjeta con degradado del color del tipo (izquierda) al negro (derecha)
    slanted(x, y + px(4), W, h, SKEW, tocolor(0, 0, 0, 70 * a), tocolor(0, 0, 0, 70 * a), true)
    local left = tocolor(10 + c[1] * 0.16, 12 + c[2] * 0.16, 18 + c[3] * 0.16, 238 * a)
    local right = tocolor(11, 13, 19, 225 * a)
    slanted(x, y, W, h, SKEW, left, right, true)
    dxDrawRectangle(x + SKEW, y, W - SKEW, 1, tocolor(255, 255, 255, 22 * a), true)

    -- Brillo que cruza la tarjeta al llegar
    if age > 180 and age < 900 then
        local k = easeOut((age - 180) / 720)
        local bx = x - px(40) + (W + px(80)) * k
        local bw, sk = px(22), px(18)
        local function cx(v) return clamp(v, x + SKEW * 0.5, x + W) end
        quad(cx(bx + sk), y, cx(bx + sk + bw), y, cx(bx), y + h, cx(bx + bw), y + h,
            tocolor(255, 255, 255, 0), tocolor(255, 255, 255, 34 * a), tocolor(255, 255, 255, 0), tocolor(255, 255, 255, 34 * a), true)
    end

    -- Barrido de color que se recoge hasta quedar como franja lateral
    local stripe = px(4)
    local wipe = stripe + (W - SKEW - stripe) * (1 - easeOut((age - 140) / 320))
    local wc = rgba(c, 255 * a)
    DX.poly({ { x + SKEW, y, wc }, { x + SKEW + wipe, y, wc }, { x + wipe, y + h, wc }, { x, y + h, wc } }, true)

    -- Icono: fondo, aro de tiempo restante, glifo y pulso de llegada
    local bcx, bcy = x + SKEW * 0.5 + PAD + BADGE_R + stripe * 0.5, y + h / 2
    local pop = easeOutBack((age - 120) / 380)
    local br = BADGE_R * pop
    if br > 1 then
        local glow = 50
        if toast.type.glyph == "bang" and age < 2400 then glow = 50 + 70 * (0.5 + 0.5 * math.sin(age / 120)) end
        circle(bcx, bcy, br - px(1), rgba(c, glow * a), true)
        ring(bcx, bcy, br, px(2), 0, 360, tocolor(255, 255, 255, 26 * a), true)
        local left01 = clamp(1 - age / toast.duration, 0, 1)
        ring(bcx, bcy, br, px(2), -90, -90 + 360 * left01, rgba(c, 255 * a), true)
        drawGlyph(toast.type.glyph, bcx, bcy, br, tocolor(255, 255, 255, 245 * a))
    end
    for _, delay in ipairs({ 260, 420 }) do
        if age > delay and age < delay + 650 then
            local e = easeOut((age - delay) / 650)
            ring(bcx, bcy, BADGE_R * (1 + 1.5 * e), px(2), 0, 360, rgba(c, 170 * (1 - e) * a), true)
        end
    end
    if toast.type.glyph == "check" and not toast.sparked and age > 300 then
        toast.sparked = true
        burst(bcx, bcy, c)
    end

    -- Etiqueta del tipo, contador de repeticiones y texto
    local tx = x + TEXT_X
    local textA = easeOut((age - 200) / 300) * a
    local ty = y + (h - (LABEL_H + px(2) + #toast.lines * BODY_H)) / 2
    dxDrawText(toast.type.label, tx, ty, 0, 0, rgba(c, 255 * textA), 1, F_LABEL, "left", "top", false, false, true)
    if toast.count > 1 then
        local lw = dxGetTextWidth(toast.type.label, 1, F_LABEL)
        local bump = 1 + 0.6 * (1 - easeOut((now - toast.bump) / 260))
        dxDrawText("x" .. toast.count, tx + lw + px(8), ty + LABEL_H / 2, tx + lw + px(8), ty + LABEL_H / 2,
            tocolor(255, 255, 255, 235 * textA), bump, F_LABEL, "left", "center", false, false, true)
    end
    for n, line in ipairs(toast.lines) do
        dxDrawText(line, tx, ty + LABEL_H + px(2) + (n - 1) * BODY_H, 0, 0, tocolor(240, 243, 248, 250 * textA), 1, F_BODY, "left", "top", false, false, true)
    end
end

local function drawToasts(now, dt)
    local targetY = stackTop(now)
    local right = screenW - MARGIN_R
    for i = #toasts, 1, -1 do
        if now - toasts[i].start > toasts[i].duration + 380 then table.remove(toasts, i) end
    end
    for _, toast in ipairs(toasts) do
        local age = now - toast.start
        local leave = easeIn((age - toast.duration) / 380)
        local enter = easeOutBack(age / 440)
        toast.ty = targetY
        toast.y = toast.y and (toast.y + (targetY - toast.y) * clamp(dt / 90, 0, 1)) or targetY
        local x = right - TOAST_W + (1 - enter) * (TOAST_W + px(40)) + leave * TOAST_W * 0.7
        local a = clamp(age / 160, 0, 1) * (1 - leave)
        if a > 0.01 then drawToast(toast, now, x, toast.y, a) end
        -- El hueco se cierra suave cuando uno sale
        targetY = targetY + (toast.h + GAP) * (1 - leave)
    end
end

----------------------------------------------------------------
-- Popup ("titular")
----------------------------------------------------------------
local function drawPopup(now)
    local p = popups[1]
    if not p then return end
    local age = now - p.start
    if age > p.duration + 460 then
        table.remove(popups, 1)
        if popups[1] then
            popups[1].start = now
            playNotifySound(popups[1].type.popSound, 0.6)
        end
        return
    end

    local c = p.type.color
    local outK = easeIn((age - p.duration) / 460)
    local open = easeOut(age / 380) * (1 - outK)
    local cx, cy = screenW / 2, math.floor(screenH * 0.22)
    local titleH, subH = dxGetFontHeight(1, F_TITLE), #p.sub * dxGetFontHeight(1, F_SUB)
    local fullH = px(34) + titleH + (subH > 0 and (px(6) + subH) or 0)
    local bh, bw = fullH * open, px(780)
    local top, bot = cy - bh / 2, cy + bh / 2

    -- Banda oscura que se abre desde el centro, más un halo del color del tipo
    local clear, dark = tocolor(10, 12, 18, 0), tocolor(10, 12, 18, 215 * open)
    quad(cx - bw / 2, top, cx, top, cx - bw / 2, bot, cx, bot, clear, dark, clear, dark, true)
    quad(cx, top, cx + bw / 2, top, cx, bot, cx + bw / 2, bot, dark, clear, dark, clear, true)
    local gw, tint, none = px(300), rgba(c, 46 * open), rgba(c, 0)
    quad(cx - gw, top, cx, top, cx - gw, bot, cx, bot, none, tint, none, tint, true)
    quad(cx, top, cx + gw, top, cx, bot, cx + gw, bot, tint, none, tint, none, true)
    if age < 280 then -- destello al llegar
        local fl = tocolor(255, 255, 255, 110 * (1 - age / 280))
        quad(cx - gw, top, cx, top, cx - gw, bot, cx, bot, tocolor(255, 255, 255, 0), fl, tocolor(255, 255, 255, 0), fl, true)
        quad(cx, top, cx + gw, top, cx, bot, cx + gw, bot, fl, tocolor(255, 255, 255, 0), fl, tocolor(255, 255, 255, 0), true)
    end

    -- Líneas de luz que se extienden desde el centro (arriba y abajo)
    local lw = bw * 0.46 * easeOut((age - 80) / 560) * (1 - outK)
    local lt = math.max(1, px(2))
    local solid = rgba(c, 255 * open)
    for _, ly in ipairs({ top, bot - lt }) do
        quad(cx - lw, ly, cx, ly, cx - lw, ly + lt, cx, ly + lt, none, solid, none, solid, true)
        quad(cx, ly, cx + lw, ly, cx, ly + lt, cx + lw, ly + lt, solid, none, solid, none, true)
    end

    -- Rombo en el centro de la línea de arriba, con su pulso
    local d = px(7) * easeOutBack((age - 60) / 360) * (1 - outK)
    if d > 0.5 then
        DX.poly({ { cx, top - d, solid }, { cx + d, top, solid }, { cx, top + d, solid }, { cx - d, top, solid } }, true)
    end
    if age > 120 and age < 900 then
        local e = easeOut((age - 120) / 780)
        ring(cx, top, px(8) + px(30) * e, px(2), 0, 360, rgba(c, 180 * (1 - e)), true)
    end

    -- Título: las letras llegan separadas y se juntan
    local n = #p.chars
    local spacing = px(18) * (1 - easeOut((age - 60) / 650))
    local x = cx - (p.titleW + spacing * math.max(0, n - 1)) / 2
    local ty = cy - fullH / 2 + px(18)
    for i = 1, n do
        local ca = easeOut((age - 60 - i * 22) / 260) * (1 - outK)
        if ca > 0.01 then
            local ch = p.chars[i]
            dxDrawText(ch, x + px(2), ty + px(2), 0, 0, tocolor(0, 0, 0, 170 * ca), 1, F_TITLE, "left", "top", false, false, true)
            dxDrawText(ch, x, ty, 0, 0, tocolor(255, 255, 255, 255 * ca), 1, F_TITLE, "left", "top", false, false, true)
        end
        x = x + p.widths[i] + spacing
    end

    -- Subtítulo después del título
    local sa = easeOut((age - 380) / 420) * (1 - outK)
    if sa > 0.01 then
        local sy = ty + titleH + px(6)
        local lh = dxGetFontHeight(1, F_SUB)
        for k, line in ipairs(p.sub) do
            dxDrawText(line, 0, sy + (k - 1) * lh, screenW, 0, tocolor(225, 230, 238, 235 * sa), 1, F_SUB, "center", "top", false, false, true)
        end
    end
end

----------------------------------------------------------------
-- Globos sobre personajes y objetos
----------------------------------------------------------------
local BUBBLE_LH = dxGetFontHeight(1, F_BUBBLE)
local function drawBubbles(now)
    local camX, camY, camZ = getCameraMatrix()
    for element, b in pairs(bubbles) do
        local age = now - b.start
        if not isElement(element) or age > b.duration then
            bubbles[element] = nil
        elseif isElementOnScreen(element) then
            local x, y, z = getElementPosition(element)
            local et = getElementType(element)
            if et == "player" or et == "ped" then
                x, y, z = getPedBonePosition(element, 8)
                z = z + 0.45
            else
                z = z + 1
            end
            local dist = getDistanceBetweenPoints3D(camX, camY, camZ, x, y, z)
            local sx, sy = getScreenFromWorldPosition(x, y, z)
            if sx and dist < 30 then
                local outK = easeIn((age - (b.duration - 300)) / 300)
                -- Casi sin encoger con la distancia: el texto escalado hacia abajo se vuelve ilegible
                local sc = clamp(1.15 - dist / 40, 0.85, 1) * (0.55 + 0.45 * easeOutBack(age / 320)) * (1 - 0.25 * outK)
                local a = clamp(age / 140, 0, 1) * (1 - outK)
                local w, h = b.w * sc, b.h * sc
                local bx, by = sx - w / 2, sy - h - px(14) * sc
                local r = px(11) * sc

                roundRect(bx + px(3) * sc, by + px(4) * sc, w, h, r, tocolor(0, 0, 0, 60 * a), false)
                local white = tocolor(250, 250, 252, 245 * a)
                roundRect(bx, by, w, h, r, white, false)
                DX.poly({ { sx - px(9) * sc, by + h, white }, { sx + px(4) * sc, by + h, white }, { sx - px(4) * sc, by + h + px(11) * sc, white } }, false)

                -- Texto letra a letra (60 por segundo)
                local left = math.floor((age - 120) * 0.06)
                for n, line in ipairs(b.lines) do
                    if left <= 0 then break end
                    local len = utf8.len(line) or #line
                    local shown = left >= len and line or utf8.sub(line, 1, left)
                    left = left - len - 1
                    local lx = sx - b.widths[n] * sc / 2
                    dxDrawText(shown, math.floor(lx + 0.5), math.floor(by + px(11) * sc + (n - 1) * BUBBLE_LH * sc + 0.5), 0, 0, tocolor(12, 14, 20, 255 * a), sc, F_BUBBLE, "left", "top")
                end
            end
        end
    end
end

----------------------------------------------------------------
-- Bucle de dibujo
----------------------------------------------------------------
local lastFrame = getTickCount()
addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(now - lastFrame, 100)
    lastFrame = now

    drawBubbles(now)
    -- Con el HUD suprimido (cinemática, foto) toasts y popups se pausan: su tiempo no corre
    if getElementData(localPlayer, "rp:hudHidden") then
        for _, t in ipairs(toasts) do t.start = t.start + dt; t.bump = t.bump + dt end
        if popups[1] then popups[1].start = popups[1].start + dt end
        sparks = {}
        return
    end
    drawToasts(now, dt)
    drawPopup(now)
    drawSparks(now, dt)
end)

----------------------------------------------------------------
-- Preferencia del jugador y prueba visual
----------------------------------------------------------------
local function savePrefs()
    local xml = xmlCreateFile(PREFS_FILE, "notify")
    if not xml then return end
    xmlNodeSetAttribute(xml, "muted", userMuted and "1" or "0")
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local xml = xmlLoadFile(PREFS_FILE)
    if xml then
        userMuted = xmlNodeGetAttribute(xml, "muted") == "1"
        xmlUnloadFile(xml)
    end
end)

addCommandHandler("silenciarnotis", function()
    userMuted = not userMuted
    savePrefs()
    notify(userMuted and "Sonido de notificaciones desactivado." or "Sonido de notificaciones activado.", "info")
end)

-- /probarnotis: muestra todos los tipos (solo en tu pantalla)
local demoTimers = {}
addCommandHandler("probarnotis", function()
    for _, tm in ipairs(demoTimers) do if isTimer(tm) then killTimer(tm) end end
    demoTimers = {}
    local steps = {
        function() notify("Así se ve un aviso de información.", "info") end,
        function() notify("Compraste una botella de agua por $5.", "success") end,
        function() notify("No tienes suficiente dinero en el banco.", "warning") end,
        function() notify("No puedes hacer eso ahora mismo.", "error") end,
        function() notify("No puedes hacer eso ahora mismo.", "error") end,
        function() popup("Bienvenido a Los Santos", "Tu historia empieza aquí. Pulsa F1 si necesitas ayuda.", "info") end,
        function() bubble(localPlayer, "¡Hola! Así se ven los globos de diálogo.", 5000) end,
    }
    for i, fn in ipairs(steps) do
        demoTimers[#demoTimers + 1] = setTimer(fn, 50 + (i - 1) * 700, 1)
    end
end)
