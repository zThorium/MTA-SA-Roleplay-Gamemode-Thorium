--[[
    rp_gym / c_interface.lua
    Medidores con dx (barra de potencia, nivel, distancia, repeticiones), como en el original:
    texto blanco con borde negro y barras naranjas. Las posiciones exactas del HUD original no
    estan documentadas: es una adaptacion.
]]

local sw, sh = guiGetScreenSize()
local scale = math.max(0.8, math.min(1.4, sh / 900))
local ORANGE, WHITE, BLACK = tocolor(245, 165, 36, 255), tocolor(255, 255, 255, 255), tocolor(0, 0, 0, 255)

local function text(str, x, y, w, size, align, color)
    size = (size or 1) * scale
    align = align or "left"
    for ox = -1, 1 do
        for oy = -1, 1 do
            if ox ~= 0 or oy ~= 0 then
                dxDrawText(str, x + ox, y + oy, x + w + ox, y + 40 + oy, BLACK, size, "default-bold", align, "top")
            end
        end
    end
    dxDrawText(str, x, y, x + w, y + 40, color or WHITE, size, "default-bold", align, "top")
end

local function bar(x, y, w, h, fraction, label)
    fraction = math.max(0, math.min(1, fraction))
    dxDrawRectangle(x - 2, y - 2, w + 4, h + 4, BLACK)
    dxDrawRectangle(x, y, w, h, tocolor(60, 60, 60, 220))
    dxDrawRectangle(x, y, w * fraction, h, fraction < 0.25 and tocolor(229, 72, 77, 255) or ORANGE)
    if label then text(label, x, y - 20 * scale, w, 0.9, "left") end
end

local function clock(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "rp:hudHidden") then return end
    local cx = sw / 2

    if gymState then
        local s = gymState
        local w = 300 * scale
        local x, y = sw - w - 40 * scale, sh * 0.35
        text(s.label, x, y, w, 1.3, "left", ORANGE)
        y = y + 34 * scale
        if s.levels then
            text(("NIVEL  %d / %d"):format(s.level, s.levels), x, y, w, 1.1)
            bar(x, y + 50 * scale, w, 18 * scale, s.gauge / 100, "POTENCIA")
            text(("DISTANCIA  %d m"):format(s.dist), x, y + 82 * scale, w, 1)
            text(("TIEMPO  %s"):format(clock(s.secs)), x, y + 106 * scale, w, 1)
            text("A y D alternando: mantener el ritmo", x, y + 140 * scale, w, 0.85)
            text("Flechas arriba/abajo: nivel   Retroceso: bajar", x, y + 160 * scale, w, 0.85)
        else
            text(("PESO  %d lb"):format(s.lb), x, y, w, 1.1)
            bar(x, y + 50 * scale, w, 18 * scale, s.gauge / 100, "POTENCIA")
            text(("REPETICIONES  %d"):format(s.reps), x, y + 82 * scale, w, 1)
            text("Espacio repetido: empujar la barra", x, y + 116 * scale, w, 0.85)
            text("Retroceso: soltar el peso", x, y + 136 * scale, w, 0.85)
        end
        if not s.ready then text("Preparando...", x, y + 190 * scale, w, 0.9, "left", ORANGE) end
        return
    end

    if gymSelecting then
        local s = gymSelecting
        text(s.label, 0, sh * 0.7, sw, 1.4, "center", ORANGE)
        text(("PESO  %d lb"):format(s.weights[s.index]), 0, sh * 0.7 + 38 * scale, sw, 1.3, "center")
        text("Flechas arriba/abajo: cambiar peso   Enter: empezar   Retroceso: cancelar", 0, sh * 0.7 + 74 * scale, sw, 0.9, "center")
        return
    end

    local n = gymNearInfo
    if n and not isPedInVehicle(localPlayer) then
        local line
        if n.kind == "trainer" then
            line = ("[E] %s (%s)"):format(n.label, tostring(n.extra))
        else
            line = ("[E] Usar: %s"):format(n.label)
        end
        text(line, 0, sh * 0.8, sw, 1.2, "center", ORANGE)
    end
end)
