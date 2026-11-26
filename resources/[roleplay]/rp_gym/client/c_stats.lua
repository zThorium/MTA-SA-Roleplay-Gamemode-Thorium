--[[
    rp_gym / c_stats.lua
    1) Aviso momentaneo cuando entrenando se gana un punto (1 %) de musculo o resistencia, o se pierde
       uno de grasa: barra con el valor nuevo y cuanto ha cambiado (se acumula si sigue en pantalla).
    2) /stats: panel con las estadisticas base de GTA SA del personaje (fisico, armas, conduccion...).
       Las lee del propio ped (el servidor las pone con setPedStat y se sincronizan).
]]

addEvent("rp:gym:statChange", true)

local sw, sh = guiGetScreenSize()
local scale = math.max(0.8, math.min(1.4, sh / 900))
local ORANGE, WHITE, BLACK = tocolor(245, 165, 36, 255), tocolor(255, 255, 255, 255), tocolor(0, 0, 0, 255)
local GREEN, MUTED = tocolor(76, 211, 138, 255), tocolor(170, 176, 188, 255)

local POPUP_MS, FADE_MS = 4500, 600
local LABELS = { muscle = "MUSCULO", stamina = "RESISTENCIA", fat = "GRASA" }
local popups = {}   -- lista de { stat, value, diff, shownAt }

local function outlined(str, x, y, w, size, align, color, alpha)
    local black = tocolor(0, 0, 0, alpha or 255)
    for ox = -1, 1 do
        for oy = -1, 1 do
            if ox ~= 0 or oy ~= 0 then
                dxDrawText(str, x + ox, y + oy, x + w + ox, y + oy, black, size * scale, "default-bold", align, "top")
            end
        end
    end
    dxDrawText(str, x, y, x + w, y, color, size * scale, "default-bold", align, "top")
end

local function withAlpha(color, alpha)
    local b = color % 256
    local g = math.floor(color / 256) % 256
    local r = math.floor(color / 65536) % 256
    return tocolor(r, g, b, alpha)
end

addEventHandler("rp:gym:statChange", resourceRoot, function(changes)
    if type(changes) ~= "table" then return end
    local now = getTickCount()
    for _, c in ipairs(changes) do
        if LABELS[c.stat] then
            local found
            for _, p in ipairs(popups) do
                if p.stat == c.stat then found = p end
            end
            if found then
                found.value, found.diff, found.shownAt = c.value, found.diff + c.diff, now
            else
                popups[#popups + 1] = { stat = c.stat, value = c.value, diff = c.diff, shownAt = now }
            end
        end
    end
    playSound("sounds/stat_up.ogg")
end)

local function drawPopups()
    local now = getTickCount()
    local w, h = 280 * scale, 58 * scale
    local x, y = sw - w - 40 * scale, sh * 0.16
    for i = #popups, 1, -1 do
        if now - popups[i].shownAt > POPUP_MS then table.remove(popups, i) end
    end
    for _, p in ipairs(popups) do
        local left = POPUP_MS - (now - p.shownAt)
        local a = math.floor(255 * math.min(1, left / FADE_MS))
        dxDrawRectangle(x - 10 * scale, y - 8 * scale, w + 20 * scale, h, tocolor(12, 14, 20, math.floor(a * 0.75)))
        outlined(LABELS[p.stat], x, y, w, 1.1, "left", withAlpha(ORANGE, a), a)
        local sign = p.diff > 0 and "+" or ""
        outlined(("%s%d %%   %d %%"):format(sign, p.diff, math.floor(p.value / 10)), x, y, w, 1.1, "right", withAlpha(GREEN, a), a)
        local by = y + 24 * scale
        dxDrawRectangle(x - 2, by - 2, w + 4, 14 * scale + 4, tocolor(0, 0, 0, a))
        dxDrawRectangle(x, by, w, 14 * scale, tocolor(60, 60, 60, math.floor(a * 0.86)))
        dxDrawRectangle(x, by, w * math.max(0, math.min(1, p.value / 1000)), 14 * scale, withAlpha(ORANGE, a))
        y = y + h + 8 * scale
    end
end

----------------------------------------------------------------
-- /stats
----------------------------------------------------------------
-- Ids de setPedStat / getPedStat (wiki de MTA, "Ped stats")
local SECTIONS = {
    { title = "FISICO", rows = {
        { "Musculo", 23 }, { "Resistencia", 22 }, { "Grasa", 21 }, { "Sex appeal", 25 },
        { "Capacidad pulmonar", 225 }, { "Salud maxima", 24 },
    } },
    { title = "CONDUCCION", rows = {
        { "Conduccion", 160 }, { "Moto", 229 }, { "Bicicleta", 230 }, { "Vuelo", 223 },
    } },
    { title = "OTROS", rows = { { "Respeto", 64 }, { "Apuestas", 81 } } },
    { title = "ARMAS", column = 2, rows = {
        { "Pistola", 69 }, { "Pistola con silenciador", 70 }, { "Desert Eagle", 71 }, { "Escopeta", 72 },
        { "Escopeta recortada", 73 }, { "Escopeta de combate", 74 }, { "Micro SMG / Tec-9", 75 }, { "MP5", 76 },
        { "AK-47", 77 }, { "M4", 78 }, { "Rifle de francotirador", 79 },
    } },
}
local STYLE_NAMES = { [4] = "Estandar", [5] = "Boxeo", [6] = "Kung Fu", [7] = "Kickboxing", [15] = "Codazos", [16] = "Codazos" }
local showStats = false

local function statRow(label, value, x, y, w)
    value = math.max(0, math.min(1000, value or 0))
    dxDrawText(label, x, y, x + w, y, WHITE, 0.95 * scale, "default-bold", "left", "top")
    dxDrawText(("%d %%"):format(math.floor(value / 10)), x, y, x + w, y, MUTED, 0.95 * scale, "default-bold", "right", "top")
    local by, bh = y + 17 * scale, 5 * scale
    dxDrawRectangle(x, by, w, bh, tocolor(60, 60, 60, 220))
    dxDrawRectangle(x, by, w * value / 1000, bh, ORANGE)
end

local function drawStats()
    local colW, rowH, gap = 270 * scale, 30 * scale, 36 * scale
    local w, h = colW * 2 + gap * 3, 560 * scale
    local x0, y0 = (sw - w) / 2, (sh - h) / 2
    dxDrawRectangle(x0, y0, w, h, tocolor(12, 14, 20, 225))
    dxDrawRectangle(x0, y0, w, 3 * scale, ORANGE)
    dxDrawText("ESTADISTICAS", x0, y0 + 16 * scale, x0 + w, y0, ORANGE, 1.5 * scale, "default-bold", "center", "top")

    local cols = { y0 + 60 * scale, y0 + 60 * scale }
    for _, sec in ipairs(SECTIONS) do
        local c = sec.column or 1
        local x, y = x0 + gap + (c - 1) * (colW + gap), cols[c]
        dxDrawText(sec.title, x, y, x + colW, y, ORANGE, 1.0 * scale, "default-bold", "left", "top")
        y = y + 24 * scale
        for _, r in ipairs(sec.rows) do
            statRow(r[1], getPedStat(localPlayer, r[2]), x, y, colW)
            y = y + rowH
        end
        cols[c] = y + 10 * scale
    end
    -- Estilo de pelea, al final de la columna de armas
    local x, y = x0 + gap * 2 + colW, cols[2]
    local style = getPedFightingStyle(localPlayer)
    dxDrawText("ESTILO DE PELEA", x, y, x + colW, y, ORANGE, 1.0 * scale, "default-bold", "left", "top")
    dxDrawText(STYLE_NAMES[style] or tostring(style), x, y + 24 * scale, x + colW, y, WHITE, 1.1 * scale, "default-bold", "left", "top")

    dxDrawText("Escribe /stats otra vez para cerrar", x0, y0 + h - 30 * scale, x0 + w, y0, MUTED, 0.9 * scale, "default", "center", "top")
end

addCommandHandler("stats", function()
    if not getElementData(localPlayer, "rp:characterId") then return end
    showStats = not showStats
    playSound(showStats and "sounds/open.ogg" or "sounds/close.ogg")
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then showStats, popups = false, {} end
end)

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "rp:hudHidden") then return end
    if #popups > 0 then drawPopups() end
    if showStats then drawStats() end
end)
