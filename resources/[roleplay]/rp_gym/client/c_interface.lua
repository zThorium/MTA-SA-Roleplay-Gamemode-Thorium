--[[
    rp_gym / c_interface.lua
    Interfaz de las maquinas y avisos de interaccion (con GymUI, client/c_ui.lua):
      - Aviso "Pulsa E" junto a una maquina, un entrenador o la puerta.
      - Elegir peso (press y mancuernas): tarjeta con el peso, las flechas y Enter dibujados.
      - Entrenando: tarjeta a la derecha con nivel o peso, barra de potencia, distancia, tiempo o
        repeticiones y los controles dibujados.
]]

local function clock(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function stat(label, value, x, y, w)
    local S = GymUI.S
    GymUI.text(label, x, y, w, 20 * S, GymUI.col(GymUI.C.muted), GymUI.font("body", 15), "left", "center")
    GymUI.text(value, x, y, w, 20 * S, GymUI.col(GymUI.C.text), GymUI.font("bold", 17), "right", "center")
end

local function drawSession(s)
    local S, sw, sh = GymUI.S, GymUI.sw, GymUI.sh
    local w, h = 340 * S, (s.levels and 300 or 262) * S
    local x, y = sw - w - 32 * S, sh * 0.30
    GymUI.panel(x, y, w, h)
    local px, pw = x + 22 * S, w - 40 * S
    GymUI.text("GIMNASIO", px, y + 14 * S, pw, 18 * S, GymUI.col(GymUI.C.accent), GymUI.font("title", 13), "left", "center")
    GymUI.text(s.label, px, y + 32 * S, pw, 30 * S, GymUI.col(GymUI.C.text), GymUI.font("bold", 22), "left", "center")

    local cy = y + 74 * S
    if s.levels then
        stat("Nivel", ("%d / %d"):format(s.level, s.levels), px, cy, pw)
        -- Escalera de niveles
        local seg = pw / s.levels
        for i = 1, s.levels do
            local c = i <= s.level and GymUI.col(GymUI.C.accent) or GymUI.col(GymUI.C.track, 30)
            dxDrawRectangle(px + (i - 1) * seg + 1, cy + 26 * S, seg - 3, 6 * S, c)
        end
        cy = cy + 44 * S
    else
        stat("Peso", ("%d lb"):format(s.lb), px, cy, pw)
        cy = cy + 30 * S
    end

    local frac = (s.gauge or 0) / 100
    GymUI.text("POTENCIA", px, cy, pw, 18 * S, GymUI.col(GymUI.C.muted), GymUI.font("title", 12), "left", "center")
    GymUI.text(("%d %%"):format(math.floor(s.gauge or 0)), px, cy, pw, 18 * S, GymUI.col(GymUI.C.text), GymUI.font("bold", 15), "right", "center")
    GymUI.bar(px, cy + 22 * S, pw, 12 * S, frac, frac < 0.25 and GymUI.col(GymUI.C.bad) or GymUI.col(GymUI.C.accent))
    cy = cy + 46 * S

    if s.levels then
        stat("Distancia", ("%d m"):format(s.dist), px, cy, pw)
        stat("Tiempo", clock(s.secs), px, cy + 24 * S, pw)
        cy = cy + 58 * S
        local ks = 30 * S
        GymUI.hint({ "keyboard_a", "/", "keyboard_d" }, "Alterna para mantener el ritmo", px, cy, ks)
        GymUI.hint({ "keyboard_arrow_up", "keyboard_arrow_down" }, "Nivel", px, cy + 36 * S, ks)
        GymUI.hint({ "keyboard_backspace" }, "Bajar", px + 170 * S, cy + 36 * S, ks)
    else
        stat("Repeticiones", tostring(s.reps), px, cy, pw)
        cy = cy + 34 * S
        local ks = 30 * S
        GymUI.hint({ "keyboard_space" }, "Pulsa rápido para levantar", px, cy, ks)
        GymUI.hint({ "keyboard_backspace" }, "Soltar el peso", px, cy + 36 * S, ks)
    end
    if s.tired then
        GymUI.text("¡Te quedas sin fuerzas!", px, y + h - 30 * S, pw, 20 * S, GymUI.col(GymUI.C.bad), GymUI.font("bold", 16), "left", "center")
    elseif not s.ready then
        GymUI.text("Preparando...", px, y + h - 30 * S, pw, 20 * S, GymUI.col(GymUI.C.accent), GymUI.font("bold", 16), "left", "center")
    end
end

local function drawSelector(s)
    local S, sw, sh = GymUI.S, GymUI.sw, GymUI.sh
    local w, h = 420 * S, 190 * S
    local x, y = (sw - w) / 2, sh * 0.68
    GymUI.panel(x, y, w, h)
    GymUI.text(s.label:upper(), x, y + 14 * S, w, 20 * S, GymUI.col(GymUI.C.accent), GymUI.font("title", 14), "center", "center")
    local ks = 40 * S
    local up, down = GymUI.key("keyboard_arrow_up"), GymUI.key("keyboard_arrow_down")
    if down then dxDrawImage(x + 40 * S, y + 50 * S, ks, ks, down, 0, 0, 0, tocolor(255, 255, 255, s.index > 1 and 255 or 70)) end
    if up then dxDrawImage(x + w - 40 * S - ks, y + 50 * S, ks, ks, up, 0, 0, 0, tocolor(255, 255, 255, s.index < #s.weights and 255 or 70)) end
    GymUI.text(("%d lb"):format(s.weights[s.index]), x, y + 40 * S, w, 60 * S, GymUI.col(GymUI.C.text), GymUI.font("bold", 40), "center", "center")
    -- Indicador de cuanto pesa respecto al maximo
    local seg = (w - 80 * S) / #s.weights
    for i = 1, #s.weights do
        dxDrawRectangle(x + 40 * S + (i - 1) * seg + 1, y + 108 * S, seg - 3, 6 * S,
            i <= s.index and GymUI.col(GymUI.C.accent) or GymUI.col(GymUI.C.track, 30))
    end
    local hy, hs = y + 132 * S, 32 * S
    local a = GymUI.hint({ "keyboard_enter" }, "Empezar", x + 40 * S, hy, hs)
    GymUI.hint({ "keyboard_backspace" }, "Cancelar", x + 40 * S + a + 40 * S, hy, hs)
end

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "rp:hudHidden") then return end
    if gymState then return drawSession(gymState) end
    if gymSelecting then return drawSelector(gymSelecting) end

    local n = gymNearInfo
    if n and not isPedInVehicle(localPlayer) and not getElementData(localPlayer, "rp:gymFight") then
        if n.kind == "door" then
            GymUI.prompt("keyboard_e", n.label)
        elseif n.kind == "trainer" then
            GymUI.prompt("keyboard_e", n.label, "Pelea con él para aprender " .. tostring(n.extra))
        else
            GymUI.prompt("keyboard_e", "Usar: " .. n.label, type(n.extra) == "table" and "Eliges el peso antes de empezar" or "Cinta y bici: 10 niveles")
        end
    end
end)
