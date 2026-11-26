--[[
    rp_hud / c_tutorial.lua
    Que el HUD se entienda solo (reglas UX-03 y UX-04 de docs/EXPERIENCIA_JUEGO.md):

    1. Tutorial guiado la primera vez que juegas en este PC (y con /hud tutorial o /tutorial):
       la pantalla se oscurece y solo queda iluminada la parte del HUD que se explica
       (minimapa, vida, cada necesidad, dinero...), con una tarjeta al lado de una linea o dos.
       Las necesidades hacen una demostracion: se vacian hasta rojo y se vuelven a llenar.
       Clic o Enter = siguiente, flecha izquierda = atras, Retroceso = saltar.
       Si llega una cinematica o se oculta el HUD, se pausa y sigue despues.

    2. Consejos de primera vez: la primera vez que algo importa (hambre baja, sin aliento,
       vida baja, poca bencina, motor apagado, estrellas...) aparece un globo junto a ese
       indicador, una sola vez, con lo que hay que hacer.

    Lo visto se guarda en @hud_tutorial.xml (archivo privado del servidor en el PC del jugador).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.9, math.min(1.3, screenH / 900))
local SAVE_FILE = "@hud_tutorial.xml"

local saved = { done = false, tips = {} }

local function load()
    local f = xmlLoadFile(SAVE_FILE)
    if not f then return end
    saved.done = xmlNodeGetAttribute(f, "done") == "1"
    local tips = xmlNodeGetAttribute(f, "tips") or ""
    for id in tips:gmatch("[^,]+") do saved.tips[id] = true end
    xmlUnloadFile(f)
end

local function save()
    local f = xmlCreateFile(SAVE_FILE, "tutorial")
    if not f then return end
    xmlNodeSetAttribute(f, "done", saved.done and "1" or "0")
    local list = {}
    for id in pairs(saved.tips) do list[#list + 1] = id end
    xmlNodeSetAttribute(f, "tips", table.concat(list, ","))
    xmlSaveFile(f)
    xmlUnloadFile(f)
end

local KEYS = {}
local function key(name)
    if KEYS[name] == nil then KEYS[name] = dxCreateTexture("images/keys/" .. name .. ".png", "argb", true, "clamp") or false end
    return KEYS[name] or nil
end

----------------------------------------------------------------
-- Pasos del tutorial. rect = parte del HUD que se ilumina (Hud.setRect en c_hud);
-- si esa parte no esta en pantalla (sin banco, sin nivel, minimapa oculto) el paso se salta.
-- demo = necesidad que hace la animacion de vaciarse y llenarse.
----------------------------------------------------------------
local STEPS = {
    { title = "Bienvenido a Thorium", text = "En un minuto te enseno a leer lo que ves en pantalla. Cada indicador te dice algo de tu personaje." },
    { rect = "map", title = "Minimapa", text = "La flecha naranja eres tu. Los iconos son lugares utiles: tiendas, restaurantes, trabajos, policia... Arriba ves el nombre de la zona.",
      keys = { { "keyboard_f11", "Mapa grande" } } },
    { rect = "bars", title = "Vida y chaleco", text = "La barra verde es tu vida: si llega a 0 quedas abatido. La azul es el chaleco y te protege antes que la vida." },
    { rect = "need_hunger", demo = "hunger", title = "Hambre", text = "Baja sola con el tiempo. Come en restaurantes, tiendas 24/7 o expendedoras. Si llega a 0 empiezas a perder vida." },
    { rect = "need_thirst", demo = "thirst", title = "Sed", text = "Baja mas rapido que el hambre. Bebe en expendedoras o tiendas. A 0 tambien pierdes vida." },
    { rect = "need_energy", demo = "energy", title = "Energia", text = "Es tu cansancio. Sin energia no puedes correr. Recuperala con /dormir dentro de un interior o con un cafe." },
    { rect = "need_stamina", demo = "stamina", title = "Aliento", text = "Se gasta al correr y al saltar, y vuelve caminando. Solo aparece cuando lo usas. Una mochila pesada lo gasta antes." },
    { rect = "need_sanity", demo = "sanity", title = "Cordura", text = "Baja con la violencia. Se recupera sola si te mantienes tranquilo. Solo aparece cuando baja." },
    { rect = "needs", title = "Los colores te avisan", text = "Su color = bien. Ambar = queda poco. Rojo que late = urgente: suena un aviso y el HUD te dice que hacer." },
    { rect = "money", title = "Dinero en mano", text = "Lo que llevas encima. Al cobrar o pagar veras volar la diferencia y oiras monedas." },
    { rect = "bank", title = "Banco", text = "Tu dinero a salvo. Sacalo en un cajero (E) o usalo desde el telefono (P). El sueldo llega aqui." },
    { rect = "level", title = "Nivel", text = "Sube trabajando y haciendo actividades. Cada nivel abre nuevas oportunidades." },
    { rect = "clock", title = "Hora", text = "La hora de la ciudad. Algunos negocios y eventos dependen de ella." },
    { rect = "iconbar", title = "Accesos rapidos", text = "Tu faccion, el inventario, el telefono y la ayuda. Pulsa M para sacar el cursor y haz clic en un icono, o usa su tecla. Si un icono se pone rojo, algo te limita (esposado, abatido).",
      keys = { { "keyboard_m", "Cursor" }, { "mouse_left", "Usar" } } },
    { title = "Listo!", text = "Cuando algo importe por primera vez te aparecera un consejo junto a ese indicador. Repite esta guia con /hud tutorial.",
      keys = { { "keyboard_f7", "Ocultar HUD" }, { "keyboard_f1", "Ayuda" } } },
}

local tut = nil        -- { i = paso, t0 = inicio del paso, paused = bool, cur = {x,y,w,h} animado }
local tip = nil        -- consejo visible { def, t0 }
local lastTipAt = 0

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end

local function canShow()
    return Hud.isActive and Hud.isActive() and not getElementData(localPlayer, "rp:downed")
        and not isPedDead(localPlayer) and type(getElementData(localPlayer, "rp:needs")) == "table"
end

----------------------------------------------------------------
-- Tarjeta (compartida por tutorial y consejos)
----------------------------------------------------------------
local CARD_W = math.floor(380 * s)
local PAD = math.floor(14 * s)

local function textHeight(text, width, scale, font)
    if dxGetTextSize then
        local _, h = dxGetTextSize(text, width, scale, scale, font, true)
        if h then return h end
    end
    local lines = math.ceil(dxGetTextWidth(text, scale, font) / width) + 1
    return lines * dxGetFontHeight(scale, font)
end

-- Coloca la tarjeta al lado del rectangulo (derecha, izquierda, encima o debajo, lo que quepa)
local function placeCard(rect, w, h)
    if not rect then return (screenW - w) / 2, (screenH - h) / 2, nil end
    local gap = 22 * s
    local rx, ry, rw, rh = rect[1], rect[2], rect[3], rect[4]
    local cy = clamp(ry + rh / 2 - h / 2, 12 * s, screenH - h - 12 * s)
    if rx + rw + gap + w < screenW - 12 * s then return rx + rw + gap, cy, "left" end
    if rx - gap - w > 12 * s then return rx - gap - w, cy, "right" end
    local cx = clamp(rx + rw / 2 - w / 2, 12 * s, screenW - w - 12 * s)
    if ry - gap - h > 12 * s then return cx, ry - gap - h, "bottom" end
    return cx, math.min(ry + rh + gap, screenH - h - 12 * s), "top"
end

-- step: { title, text, keys }; footer: true = botones del tutorial; header: "Paso 3 de 12"
local function drawCard(step, rect, alpha, header, footer, appear)
    local innerW = CARD_W - PAD * 2 - 4 * s
    local titleH = dxGetFontHeight(1.25 * s, "default-bold")
    local bodyH = textHeight(step.text, innerW, 1.0 * s, "default")
    local keysH = step.keys and (30 * s) or 0
    local headH = header and dxGetFontHeight(0.8 * s, "default-bold") + 2 * s or 0
    local footH = footer and (34 * s) or 0
    local h = PAD + headH + titleH + 6 * s + bodyH + (keysH > 0 and keysH + 8 * s or 0) + (footH > 0 and footH + 6 * s or 0) + PAD
    local x, y, side = placeCard(rect, CARD_W, h)
    local slide = (1 - easeOut(appear)) * 16 * s
    if side == "left" then x = x + slide elseif side == "right" then x = x - slide elseif side == "bottom" then y = y - slide else y = y + slide end
    local a = alpha

    -- puntero hacia lo que se explica
    if rect and side then
        local c = tocolor(16, 18, 26, 240 * a)
        local rcx, rcy = rect[1] + rect[3] / 2, rect[2] + rect[4] / 2
        local t = 10 * s
        if side == "left" then
            local py = clamp(rcy, y + 16 * s, y + h - 16 * s)
            dxDrawPrimitive("trianglelist", false, { x - t, py, c }, { x, py - t, c }, { x, py + t, c })
        elseif side == "right" then
            local py = clamp(rcy, y + 16 * s, y + h - 16 * s)
            dxDrawPrimitive("trianglelist", false, { x + CARD_W + t, py, c }, { x + CARD_W, py - t, c }, { x + CARD_W, py + t, c })
        elseif side == "bottom" then
            local px = clamp(rcx, x + 16 * s, x + CARD_W - 16 * s)
            dxDrawPrimitive("trianglelist", false, { px, y + h + t, c }, { px - t, y + h, c }, { px + t, y + h, c })
        else
            local px = clamp(rcx, x + 16 * s, x + CARD_W - 16 * s)
            dxDrawPrimitive("trianglelist", false, { px, y - t, c }, { px - t, y, c }, { px + t, y, c })
        end
    end

    dxDrawRectangle(x + 4 * s, y + 4 * s, CARD_W, h, tocolor(0, 0, 0, 90 * a))          -- sombra
    dxDrawRectangle(x, y, CARD_W, h, tocolor(16, 18, 26, 240 * a))
    dxDrawRectangle(x, y, 4 * s, h, tocolor(245, 165, 36, 255 * a))                    -- franja de acento
    local tx, ty = x + PAD + 4 * s, y + PAD
    if header then
        dxDrawText(header, tx, ty, tx + innerW, ty + headH, tocolor(245, 165, 36, 255 * a), 0.8 * s, "default-bold", "left", "top")
        ty = ty + headH
    end
    dxDrawText(step.title, tx, ty, tx + innerW, ty + titleH, tocolor(255, 255, 255, 255 * a), 1.25 * s, "default-bold", "left", "top")
    ty = ty + titleH + 6 * s
    dxDrawText(step.text, tx, ty, tx + innerW, ty + bodyH, tocolor(215, 220, 230, 255 * a), 1.0 * s, "default", "left", "top", false, true)
    ty = ty + bodyH
    if step.keys then
        ty = ty + 8 * s
        local kx = tx
        for _, k in ipairs(step.keys) do
            local tex = key(k[1])
            if tex then dxDrawImage(kx, ty, 30 * s, 30 * s, tex, 0, 0, 0, tocolor(255, 255, 255, 255 * a)) end
            dxDrawText(k[2], kx + 34 * s, ty, kx + 200 * s, ty + 30 * s, tocolor(235, 238, 245, 255 * a), 0.95 * s, "default-bold", "left", "center")
            kx = kx + 34 * s + dxGetTextWidth(k[2], 0.95 * s, "default-bold") + 18 * s
        end
        ty = ty + keysH
    end
    if footer then
        ty = ty + 6 * s
        dxDrawRectangle(tx, ty, innerW, 1, tocolor(255, 255, 255, 25 * a))
        local fy = ty + 4 * s
        local ks = 26 * s
        local fx = tx
        local blink = 180 + 75 * math.sin(getTickCount() / 220)
        for _, k in ipairs({ "mouse_left", "keyboard_enter" }) do
            local tex = key(k)
            if tex then dxDrawImage(fx, fy, ks, ks, tex, 0, 0, 0, tocolor(255, 255, 255, blink * a)) end
            fx = fx + ks + 2 * s
        end
        dxDrawText("Siguiente", fx + 4 * s, fy, fx + 120 * s, fy + ks, tocolor(255, 255, 255, 255 * a), 0.95 * s, "default-bold", "left", "center")
        local skip = "Saltar"
        local sw = dxGetTextWidth(skip, 0.9 * s, "default-bold")
        local sx = tx + innerW - sw
        dxDrawText(skip, sx, fy, sx + sw, fy + ks, tocolor(154, 163, 178, 255 * a), 0.9 * s, "default-bold", "left", "center")
        local bk = key("keyboard_backspace")
        if bk then dxDrawImage(sx - ks - 2 * s, fy, ks, ks, bk, 0, 0, 0, tocolor(255, 255, 255, 200 * a)) end
    end
    return x, y, CARD_W, h
end

----------------------------------------------------------------
-- Tutorial guiado
----------------------------------------------------------------
local function stepAvailable(step)
    return not step.rect or Hud.getRect(step.rect) ~= nil
end

local function setStep(i, dir)
    dir = dir or 1
    while STEPS[i] and not stepAvailable(STEPS[i]) do i = i + dir end
    if i < 1 then i = 1 end
    tut.i, tut.t0 = i, getTickCount()
    local step = STEPS[i]
    Hud.demo = step and step.demo and { key = step.demo, t0 = getTickCount() } or nil
    if step then Hud.sound("step", 100) end
end

local function finish(skipped)
    if not tut then return end
    tut = nil
    Hud.demo, Hud.showAll = nil, false
    showCursor(false)
    saved.done = true
    save()
    if skipped then
        exports.rp_notify:notify("Guia del HUD saltada. Puedes verla cuando quieras con /hud tutorial.", "info")
    else
        Hud.sound("done", 500)
        exports.rp_notify:notify("Ya conoces tu HUD. Mas ayuda en F1; repite la guia con /hud tutorial.", "success")
    end
end

local function nextStep()
    if not tut or tut.paused or getTickCount() - tut.t0 < 350 then return end   -- evita saltarse pasos con doble clic
    if tut.i >= #STEPS then return finish(false) end
    setStep(tut.i + 1, 1)
    if not STEPS[tut.i] then finish(false) end
end

local function prevStep()
    if not tut or tut.paused or tut.i <= 1 then return end
    setStep(tut.i - 1, -1)
end

function Hud.startTutorial(manual)
    if tut then return end
    if not canShow() then
        if manual then exports.rp_notify:notify("Ahora no se puede mostrar la guia del HUD.", "warning") end
        return
    end
    tip = nil
    Hud.showAll = true   -- estamina y cordura visibles para poder explicarlas
    tut = { i = 1, t0 = getTickCount(), paused = false, cur = nil }
    showCursor(true)     -- el cursor quita los controles: el personaje se queda quieto mientras lees
    setStep(1, 1)
end

addCommandHandler("tutorial", function() Hud.startTutorial(true) end)

-- (el cursor lo muestra la propia guia, asi que solo se ignoran chat y consola)
local function typing() return isChatBoxInputActive() or isConsoleActive() end
bindKey("enter", "down", function() if tut and not typing() then nextStep() end end)
bindKey("arrow_l", "down", function() if tut and not typing() then prevStep() end end)
bindKey("backspace", "down", function() if tut and not tut.paused and not typing() then finish(true) end end)
addEventHandler("onClientClick", root, function(button, state)
    if tut and button == "left" and state == "up" then nextStep() end
end)

local DIM = 175
local function drawTutorial(now)
    -- pausa: cinematica, HUD oculto, abatido... (se retoma en el mismo paso)
    if not canShow() then
        if not tut.paused then tut.paused = true; showCursor(false) end
        return
    end
    if tut.paused then
        tut.paused = false
        tut.t0 = now
        Hud.showAll = true
        showCursor(true)
    end
    local step = STEPS[tut.i]
    if not step then return finish(false) end
    local target = step.rect and Hud.getRect(step.rect)
    if step.rect and not target then setStep(tut.i + 1, 1); return end

    local pad = 8 * s
    local tr
    if target then
        tr = { target[1] - pad, target[2] - pad, target[3] + pad * 2, target[4] + pad * 2 }
    else
        tr = { screenW / 2, screenH / 2, 0, 0 }
    end
    -- el foco viaja suave de un indicador al siguiente
    if not tut.cur then tut.cur = { tr[1], tr[2], tr[3], tr[4] } end
    local c = tut.cur
    for i = 1, 4 do c[i] = c[i] + (tr[i] - c[i]) * 0.2 end
    local x, y, w, h = c[1], c[2], c[3], c[4]

    -- pantalla oscura con un agujero sobre lo que se explica
    local dim = tocolor(0, 0, 0, DIM)
    dxDrawRectangle(0, 0, screenW, math.max(0, y), dim)
    dxDrawRectangle(0, y + h, screenW, math.max(0, screenH - y - h), dim)
    dxDrawRectangle(0, y, math.max(0, x), h, dim)
    dxDrawRectangle(x + w, y, math.max(0, screenW - x - w), h, dim)
    if w > 4 then
        local blink = 150 + 105 * math.sin(now / 180)
        local col, t = tocolor(255, 255, 255, blink), math.max(2, math.floor(2 * s))
        dxDrawRectangle(x - t, y - t, w + t * 2, t, col)
        dxDrawRectangle(x - t, y + h, w + t * 2, t, col)
        dxDrawRectangle(x - t, y, t, h, col)
        dxDrawRectangle(x + w, y, t, h, col)
    end

    local appear = (now - tut.t0) / 350
    local total, idx = 0, 0
    for i, st in ipairs(STEPS) do
        if stepAvailable(st) then total = total + 1; if i <= tut.i then idx = idx + 1 end end
    end
    drawCard(step, target and tr or nil, clamp(appear * 1.5, 0, 1), ("PASO %d DE %d"):format(idx, total), true, appear)
end

----------------------------------------------------------------
-- Consejos de primera vez (una sola vez cada uno, junto a su indicador)
----------------------------------------------------------------
local TIP_MS = 9000
local engineOffSince = nil

local function needVal(k) return (Hud.needValues and Hud.needValues[k]) or 100 end
local function driverVehicle()
    local v = getPedOccupiedVehicle(localPlayer)
    if v and getVehicleController(v) == localPlayer then return v end
end

local TIPS = {
    { id = "health", rect = "bars", title = "Vida baja", text = "Evita mas peleas y busca un hospital. Si caes abatido, pide ayuda con /911.",
      cond = function() return getElementHealth(localPlayer) < 30 end },
    { id = "hunger", rect = "need_hunger", title = "Tienes hambre", text = "Come en un restaurante (Burger Shot, Cluckin' Bell, pizzeria), una tienda 24/7 o una expendedora. Buscalos en el minimapa.",
      cond = function() return needVal("hunger") < 35 end },
    { id = "thirst", rect = "need_thirst", title = "Tienes sed", text = "Bebe en una expendedora o compra agua o un refresco en una tienda 24/7.",
      cond = function() return needVal("thirst") < 35 end },
    { id = "energy", rect = "need_energy", title = "Estas cansado", text = "Escribe /dormir dentro de un interior (tu casa, un hotel) o tomate un cafe.",
      cond = function() return needVal("energy") < 35 end },
    { id = "stamina", rect = "need_stamina", title = "Sin aliento", text = "Correr y saltar gastan aliento. Camina unos segundos y podras correr de nuevo.",
      cond = function() return Hud.staminaLocked end },
    { id = "sanity", rect = "need_sanity", title = "Tu cordura baja", text = "La violencia te pasa factura. Mantente tranquilo un rato y se recuperara sola.",
      cond = function() return needVal("sanity") < 70 end },
    { id = "engine", rect = "speedo", title = "Motor apagado", text = "Pulsa J para encender el motor. Necesitas la llave del vehiculo.",
      keys = { { "keyboard_j", "Motor" } },
      cond = function()
          local v = driverVehicle()
          if v and not getVehicleEngineState(v) then
              engineOffSince = engineOffSince or getTickCount()
              return getTickCount() - engineOffSince > 2500
          end
          engineOffSince = nil
          return false
      end },
    { id = "vehbar", rect = "vehbar", title = "Controles del vehiculo", text = "Motor, freno de mano, cerradura, cinturon, balizas y radio. En color = encendido, gris = apagado. Pulsa M y haz clic en un icono, o usa su tecla.",
      keys = { { "keyboard_m", "Cursor" }, { "mouse_left", "Usar" } },
      cond = function() return getPedOccupiedVehicle(localPlayer) ~= false end },
    { id = "fuel", rect = "speedo", title = "Poca bencina", text = "El vehiculo se esta quedando sin bencina. Llena el tanque en una gasolinera.",
      cond = function()
          local v = driverVehicle()
          local f, m = v and tonumber(getElementData(v, "rp:fuel")), v and tonumber(getElementData(v, "rp:fuelMax"))
          return f and m and m > 0 and f / m <= 0.15
      end },
    { id = "wanted", rect = "wanted", title = "La policia te busca", text = "Cada estrella es mas busqueda. Sal de la vista de la policia y las estrellas bajaran solas.",
      cond = function() return (tonumber(getElementData(localPlayer, "rp:wanted")) or 0) > 0 end },
}

local function checkTips()
    if tut or tip or not saved.done or not canShow() then return end
    if getTickCount() - lastTipAt < 15000 then return end
    for _, def in ipairs(TIPS) do
        if not saved.tips[def.id] and def.cond() and Hud.getRect(def.rect) then
            tip = { def = def, t0 = getTickCount() }
            saved.tips[def.id] = true
            save()
            Hud.sound("tip", 1000)
            return
        end
    end
end

local function drawTip(now)
    if not canShow() then return end
    local t = now - tip.t0
    if t > TIP_MS then tip = nil; lastTipAt = now; return end
    local rect = Hud.getRect(tip.def.rect)
    if not rect then return end
    local a = t < 300 and t / 300 or (t > TIP_MS - 500 and (TIP_MS - t) / 500 or 1)
    -- aro que late alrededor del indicador
    local pad = 6 * s + 3 * s * math.sin(now / 160)
    local col, th = tocolor(255, 214, 110, 220 * a), math.max(2, math.floor(2 * s))
    local x, y, w, h = rect[1] - pad, rect[2] - pad, rect[3] + pad * 2, rect[4] + pad * 2
    dxDrawRectangle(x - th, y - th, w + th * 2, th, col)
    dxDrawRectangle(x - th, y + h, w + th * 2, th, col)
    dxDrawRectangle(x - th, y, th, h, col)
    dxDrawRectangle(x + w, y, th, h, col)
    drawCard(tip.def, { x, y, w, h }, a, "CONSEJO", false, t / 350)
end

----------------------------------------------------------------
-- Arranque automatico: la primera vez, cuando el personaje ya esta en el mundo
-- y nada mas ocupa la pantalla (login, seleccion de personaje, paneles con cursor).
----------------------------------------------------------------
local readySince = nil
local checkTimer = setTimer(function()
    if tut then return end
    if not saved.done then
        if canShow() and not isCursorShowing() and Hud.getRect("needs") then
            readySince = readySince or getTickCount()
            if getTickCount() - readySince > 5000 then Hud.startTutorial(false) end
        else
            readySince = nil
        end
        return
    end
    checkTips()
end, 1000, 0)

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    if tut then drawTutorial(now) elseif tip then drawTip(now) end
end, true, "low")

addEventHandler("onClientResourceStart", resourceRoot, load)
addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(checkTimer) then killTimer(checkTimer) end
    if tut then showCursor(false) end
end)
addEventHandler("onClientElementDataChange", localPlayer, function(k)
    -- al cambiar de personaje a mitad de la guia, se cierra sin marcarla como vista
    if k == "rp:characterId" and tut then
        tut = nil
        Hud.demo, Hud.showAll = nil, false
        showCursor(false)
    end
end)
