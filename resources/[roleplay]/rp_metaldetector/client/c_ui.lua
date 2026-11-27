--[[
    rp_metaldetector / c_ui.lua  (cliente)

    Utilidades de dibujo compartidas por c_fx.lua y c_metaldetector.lua: escala, fuentes Rubik,
    texturas en caché, sonidos y formas (paneles, arcos, texto con sombra).
    Todo cuelga de la tabla MDX (única global del cliente del recurso).
]]

MDX = MDX or {}

local sw, sh = guiGetScreenSize()
MDX.sw, MDX.sh = sw, sh
MDX.S = math.max(0.75, math.min(1.25, sh / 1080))

----------------------------------------------------------------
-- Fuentes y texturas (se crean una vez, perezosas)
----------------------------------------------------------------
local fonts, textures = {}, {}
local FONT_FILES = { medium = "fonts/rubik_medium.ttf", bold = "fonts/rubik_semibold.ttf" }

function MDX.font(kind, size)
    local key = kind .. size
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(FONT_FILES[kind] or FONT_FILES.medium, math.floor(size * MDX.S + 0.5), false, "antialiased") or false
    end
    return fonts[key] or "default-bold"
end

function MDX.tex(path)
    if textures[path] == nil then
        textures[path] = dxCreateTexture(path, "argb", true, "clamp") or false
    end
    return textures[path] or nil
end

function MDX.itemTex(itemId) return MDX.tex("images/items/" .. tostring(itemId) .. ".png") end

----------------------------------------------------------------
-- Sonidos
----------------------------------------------------------------
function MDX.sound(name, volume, speed, loop)
    local ext = name:find("%.") and "" or (fileExists("sounds/" .. name .. ".wav") and ".wav" or ".ogg")
    local s = playSound("sounds/" .. name .. ext, loop == true)
    if s then
        setSoundVolume(s, volume or 0.7)
        if speed then setSoundSpeed(s, speed) end
    end
    return s
end

function MDX.sound3D(name, x, y, z, volume, maxDist)
    local ext = fileExists("sounds/" .. name .. ".wav") and ".wav" or ".ogg"
    local s = playSound3D("sounds/" .. name .. ext, x, y, z)
    if s then
        setSoundVolume(s, volume or 0.8)
        setSoundMaxDistance(s, maxDist or 60)
    end
    return s
end

----------------------------------------------------------------
-- Formas
----------------------------------------------------------------
function MDX.rgba(c, a) return tocolor(c[1], c[2], c[3], a or 255) end

-- Panel con esquinas redondeadas (r px) y fondo oscuro
function MDX.panel(x, y, w, h, color, r)
    r = r or 10 * MDX.S
    color = color or tocolor(14, 16, 22, 232)
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 8)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 8)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 8)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 8)
end

-- Arco grueso: sector de radio exterior menos sector de radio interior (fondo bg)
function MDX.arc(cx, cy, rOut, rIn, a1, a2, color, bg)
    dxDrawCircle(cx, cy, rOut, a1, a2, color, color, 24)
    dxDrawCircle(cx, cy, rIn, a1 - 1, a2 + 1, bg, bg, 24)
end

function MDX.text(text, x, y, x2, y2, color, font, alignX, alignY, shadow, wordBreak)
    if shadow ~= false then
        dxDrawText(text, x + 1, y + 2, x2 + 1, y2 + 2, tocolor(0, 0, 0, 150), 1, font, alignX or "left", alignY or "top", false, wordBreak == true, false, true)
    end
    dxDrawText(text, x, y, x2, y2, color, 1, font, alignX or "left", alignY or "top", false, wordBreak == true, false, true)
end

-- Tecla dibujada + texto (UX-01). Devuelve el ancho usado.
function MDX.keyHint(keyTex, label, x, y, size, font, color)
    size = size or 30 * MDX.S
    if keyTex then dxDrawImage(x, y, size, size, keyTex) end
    local fw = dxGetTextWidth(label, 1, font)
    MDX.text(label, x + size + 6 * MDX.S, y, x + size + 6 * MDX.S + fw, y + size, color or tocolor(235, 238, 244), font, "left", "center")
    return size + 6 * MDX.S + fw
end

function MDX.lerp(a, b, t) return a + (b - a) * t end
function MDX.clamp(v, a, b) return math.max(a, math.min(b, v)) end
function MDX.easeOutBack(t) local c = 1.70158; t = t - 1; return 1 + (c + 1) * t * t * t + c * t * t end
function MDX.easeOutCubic(t) t = 1 - t; return 1 - t * t * t end

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, f in pairs(fonts) do if isElement(f) then destroyElement(f) end end
    for _, t in pairs(textures) do if isElement(t) then destroyElement(t) end end
end)
