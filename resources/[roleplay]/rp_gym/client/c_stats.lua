--[[
    rp_gym / c_stats.lua
    1) Aviso momentaneo cuando entrenando se gana un punto (1 %) de musculo o resistencia, o se pierde
       uno de grasa: tarjeta con la barra del valor nuevo y cuanto ha cambiado (se acumula si sigue en pantalla).
    2) /stats: panel con las estadisticas base de GTA SA del personaje (fisico, armas, conduccion...).
       Las lee del propio ped (el servidor las pone con setPedStat y se sincronizan).
    Dibujo con GymUI (client/c_ui.lua).
]]

addEvent("rp:gym:statChange", true)

local POPUP_MS, FADE_MS, SLIDE_MS = 4500, 600, 250
local LABELS = { muscle = "MÚSCULO", stamina = "RESISTENCIA", fat = "GRASA" }
local popups = {}   -- lista de { stat, value, diff, shownAt }

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
    local S, sw, sh = GymUI.S, GymUI.sw, GymUI.sh
    local now = getTickCount()
    local w, h = 320 * S, 76 * S
    local y = sh * 0.14
    for i = #popups, 1, -1 do
        if now - popups[i].shownAt > POPUP_MS then table.remove(popups, i) end
    end
    for _, p in ipairs(popups) do
        local age = now - p.shownAt
        local a = math.min(1, (POPUP_MS - age) / FADE_MS)
        local slide = (1 - math.min(1, age / SLIDE_MS)) ^ 2 * 60 * S   -- entra desde la derecha
        local x = sw - w - 32 * S + slide
        GymUI.panel(x, y, w, h, a, GymUI.C.good)
        local px, pw = x + 20 * S, w - 38 * S
        GymUI.text(LABELS[p.stat], px, y + 10 * S, pw, 20 * S, GymUI.col(GymUI.C.muted, 255 * a), GymUI.font("title", 13), "left", "center")
        GymUI.text(("%s%d %%"):format(p.diff > 0 and "+" or "", p.diff), px, y + 8 * S, pw, 24 * S,
            GymUI.col(GymUI.C.good, 255 * a), GymUI.font("bold", 22), "right", "center")
        GymUI.text(("%d %%"):format(math.floor(p.value / 10)), px, y + 32 * S, pw, 18 * S, GymUI.col(GymUI.C.text, 255 * a), GymUI.font("bold", 15), "left", "center")
        GymUI.bar(px, y + 56 * S, pw, 8 * S, p.value / 1000, GymUI.col(GymUI.C.accent, 255 * a), a)
        y = y + h + 10 * S
    end
end

----------------------------------------------------------------
-- /stats
----------------------------------------------------------------
-- Ids de setPedStat / getPedStat (wiki de MTA, "Ped stats")
local SECTIONS = {
    { title = "FÍSICO", rows = {
        { "Músculo", 23 }, { "Resistencia", 22 }, { "Grasa", 21 }, { "Sex appeal", 25 },
        { "Capacidad pulmonar", 225 }, { "Salud máxima", 24 },
    } },
    { title = "CONDUCCIÓN", rows = {
        { "Conducción", 160 }, { "Moto", 229 }, { "Bicicleta", 230 }, { "Vuelo", 223 },
    } },
    { title = "OTROS", rows = { { "Respeto", 64 }, { "Apuestas", 81 } } },
    { title = "ARMAS", column = 2, rows = {
        { "Pistola", 69 }, { "Pistola con silenciador", 70 }, { "Desert Eagle", 71 }, { "Escopeta", 72 },
        { "Escopeta recortada", 73 }, { "Escopeta de combate", 74 }, { "Micro SMG / Tec-9", 75 }, { "MP5", 76 },
        { "AK-47", 77 }, { "M4", 78 }, { "Rifle de francotirador", 79 },
    } },
}
local STYLE_NAMES = { [4] = "Estándar", [5] = "Boxeo", [6] = "Kung Fu", [7] = "Kickboxing", [15] = "Codazos", [16] = "Codazos" }
local showStats, openedAt = false, 0

local function statRow(label, value, x, y, w)
    local S = GymUI.S
    value = math.max(0, math.min(1000, value or 0))
    GymUI.text(label, x, y, w, 20 * S, GymUI.col(GymUI.C.text), GymUI.font("body", 16), "left", "center")
    GymUI.text(("%d %%"):format(math.floor(value / 10)), x, y, w, 20 * S,
        value >= 999 and GymUI.col(GymUI.C.accent) or GymUI.col(GymUI.C.muted), GymUI.font("bold", 15), "right", "center")
    GymUI.bar(x, y + 23 * S, w, 5 * S, value / 1000, GymUI.col(GymUI.C.accent))
end

local function drawStats()
    local S, sw, sh = GymUI.S, GymUI.sw, GymUI.sh
    local a = math.min(1, (getTickCount() - openedAt) / 180)
    local colW, rowH, gap = 300 * S, 36 * S, 40 * S
    local w, h = colW * 2 + gap * 3, 640 * S
    local x0, y0 = (sw - w) / 2, (sh - h) / 2 + (1 - a) * 20 * S
    GymUI.panel(x0, y0, w, h, a)
    GymUI.text("ESTADÍSTICAS", x0 + gap, y0 + 22 * S, w, 30 * S, GymUI.col(GymUI.C.text, 255 * a), GymUI.font("title", 24), "left", "center")
    GymUI.text(getPlayerName(localPlayer):gsub("_", " "), x0, y0 + 22 * S, w - gap, 30 * S, GymUI.col(GymUI.C.muted, 255 * a), GymUI.font("body", 16), "right", "center")
    dxDrawRectangle(x0 + gap, y0 + 64 * S, w - gap * 2, 1, GymUI.col(GymUI.C.border, 30 * a))

    local cols = { y0 + 82 * S, y0 + 82 * S }
    for _, sec in ipairs(SECTIONS) do
        local c = sec.column or 1
        local x, y = x0 + gap + (c - 1) * (colW + gap), cols[c]
        GymUI.text(sec.title, x, y, colW, 20 * S, GymUI.col(GymUI.C.accent, 255 * a), GymUI.font("title", 14), "left", "center")
        y = y + 28 * S
        for _, r in ipairs(sec.rows) do
            statRow(r[1], getPedStat(localPlayer, r[2]), x, y, colW)
            y = y + rowH
        end
        cols[c] = y + 14 * S
    end
    -- Estilo de pelea, al final de la columna de armas
    local x, y = x0 + gap * 2 + colW, cols[2]
    GymUI.text("ESTILO DE PELEA", x, y, colW, 20 * S, GymUI.col(GymUI.C.accent, 255 * a), GymUI.font("title", 14), "left", "center")
    local style = getPedFightingStyle(localPlayer)
    GymUI.text(STYLE_NAMES[style] or tostring(style), x, y + 26 * S, colW, 26 * S, GymUI.col(GymUI.C.text, 255 * a), GymUI.font("bold", 22), "left", "center")

    GymUI.text("Escribe /stats otra vez para cerrar", x0, y0 + h - 36 * S, w, 20 * S, GymUI.col(GymUI.C.muted, 255 * a), GymUI.font("body", 15), "center", "center")
end

addCommandHandler("stats", function()
    if not getElementData(localPlayer, "rp:characterId") then return end
    showStats = not showStats
    openedAt = getTickCount()
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
