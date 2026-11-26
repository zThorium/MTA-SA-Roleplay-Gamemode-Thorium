--[[
    rp_gym / c_ui.lua
    Piezas de interfaz comunes a todo el recurso (maquinas, entrenador, combate, estadisticas):
    paleta del HUD de Thorium, fuentes de rp_notify (Kenney Future para titulos, Rubik para texto),
    tarjetas, barras, teclas dibujadas (Kenney Input Prompts) y el aviso "Pulsa E".
    Todo se crea bajo demanda y se cachea; nada de esto hace trabajo pesado por fotograma.
]]

GymUI = {}

local sw, sh = guiGetScreenSize()
local S = math.max(0.75, math.min(1.5, sh / 1080))
GymUI.S, GymUI.sw, GymUI.sh = S, sw, sh

GymUI.C = {
    panel = { 12, 14, 20 }, border = { 255, 255, 255 }, text = { 242, 244, 248 }, muted = { 154, 163, 178 },
    accent = { 245, 165, 36 }, good = { 76, 211, 138 }, bad = { 229, 72, 77 }, track = { 255, 255, 255 },
}

function GymUI.col(c, a) return tocolor(c[1], c[2], c[3], a or 255) end

----------------------------------------------------------------
-- Fuentes y texturas
----------------------------------------------------------------
local fonts, keys = {}, {}
local FONT_FILES = { title = ":rp_notify/fonts/kenney_future.ttf", body = ":rp_notify/fonts/rubik_regular.ttf",
                     bold = ":rp_notify/fonts/rubik_medium.ttf" }

-- kind = title | body | bold; size en px a 1080p
function GymUI.font(kind, size)
    local id = kind .. size
    if fonts[id] == nil then
        fonts[id] = dxCreateFont(FONT_FILES[kind], math.floor(size * S + 0.5), false, "antialiased") or false
    end
    return fonts[id] or (kind == "body" and "default" or "default-bold")
end

function GymUI.key(name)
    if keys[name] == nil then keys[name] = dxCreateTexture("images/keys/" .. name .. ".png", "argb", true, "clamp") or false end
    return keys[name] or nil
end

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
function GymUI.panel(x, y, w, h, a, accent)
    a = a or 1
    dxDrawRectangle(x, y, w, h, GymUI.col(GymUI.C.panel, 215 * a))
    local b = GymUI.col(GymUI.C.border, 28 * a)
    dxDrawRectangle(x, y, w, 1, b)
    dxDrawRectangle(x, y + h - 1, w, 1, b)
    dxDrawRectangle(x, y, 1, h, b)
    dxDrawRectangle(x + w - 1, y, 1, h, b)
    if accent ~= false then dxDrawRectangle(x, y, 4 * S, h, GymUI.col(accent or GymUI.C.accent, 255 * a)) end
end

function GymUI.text(str, x, y, w, h, color, font, ax, ay, clip)
    dxDrawText(str, x, y, x + w, y + h, color, 1, font, ax or "left", ay or "top", clip or false, false, false, false, true)
end

-- Texto con sombra suave (para textos sobre el juego, sin tarjeta). scale anima el tamano sin crear fuentes nuevas.
function GymUI.shadowText(str, x, y, w, h, color, font, ax, ay, a, scale)
    local sh = tocolor(0, 0, 0, 170 * (a or 1))
    local d = 3 * S * (scale or 1)
    dxDrawText(str, x + d, y + d, x + w + d, y + h + d, sh, scale or 1, font, ax or "center", ay or "top")
    dxDrawText(str, x, y, x + w, y + h, color, scale or 1, font, ax or "center", ay or "top")
end

function GymUI.bar(x, y, w, h, frac, color, a)
    frac = math.max(0, math.min(1, frac or 0))
    dxDrawRectangle(x, y, w, h, GymUI.col(GymUI.C.track, 30 * (a or 1)))
    if frac > 0 then dxDrawRectangle(x, y, w * frac, h, color) end
end

-- Teclas dibujadas en fila: keys = { "keyboard_a", "+", "keyboard_d" } ("+" o "/" son separadores de texto)
function GymUI.keys(list, x, y, size, a)
    local cx = x
    local col = tocolor(255, 255, 255, 255 * (a or 1))
    for _, k in ipairs(list) do
        if k == "+" or k == "/" then
            GymUI.text(k, cx, y, size * 0.5, size, GymUI.col(GymUI.C.muted, 255 * (a or 1)), GymUI.font("bold", 16), "center", "center")
            cx = cx + size * 0.5
        else
            local t = GymUI.key(k)
            if t then dxDrawImage(cx, y, size, size, t, 0, 0, 0, col) end
            cx = cx + size
        end
    end
    return cx - x
end

-- Linea de ayuda: teclas + texto. Devuelve el ancho usado.
function GymUI.hint(list, label, x, y, size, a)
    local kw = GymUI.keys(list, x, y, size, a)
    local font = GymUI.font("body", 17)
    GymUI.text(label, x + kw + 8 * S, y, 400 * S, size, GymUI.col(GymUI.C.text, 255 * (a or 1)), font, "left", "center")
    return kw + 8 * S + dxGetTextWidth(label, 1, font)
end

-- Aviso de interaccion abajo al centro: [tecla] Titulo / subtitulo
function GymUI.prompt(keyName, title, sub)
    local tf, sf = GymUI.font("bold", 20), GymUI.font("body", 15)
    local ks = 46 * S
    local tw = math.max(dxGetTextWidth(title, 1, tf), sub and dxGetTextWidth(sub, 1, sf) or 0)
    local w, h = ks + tw + 44 * S, 64 * S
    local x, y = (sw - w) / 2, sh * 0.80
    GymUI.panel(x, y, w, h)
    local t = GymUI.key(keyName)
    if t then dxDrawImage(x + 16 * S, y + (h - ks) / 2, ks, ks, t) end
    local tx = x + 16 * S + ks + 12 * S
    if sub then
        GymUI.text(title, tx, y + 10 * S, tw, 26 * S, GymUI.col(GymUI.C.text), tf, "left", "center")
        GymUI.text(sub, tx, y + 34 * S, tw, 20 * S, GymUI.col(GymUI.C.muted), sf, "left", "center")
    else
        GymUI.text(title, tx, y, tw, h, GymUI.col(GymUI.C.text), tf, "left", "center")
    end
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, f in pairs(fonts) do if isElement(f) then destroyElement(f) end end
    for _, t in pairs(keys) do if isElement(t) then destroyElement(t) end end
end)
