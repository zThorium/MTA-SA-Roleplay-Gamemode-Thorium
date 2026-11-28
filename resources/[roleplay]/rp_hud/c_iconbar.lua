--[[
    rp_hud / c_iconbar.lua
    Fichas clicables a la izquierda del dinero (idea del HUD de OwlGaming; codigo e iconos propios en SVG).
    Cada ficha: cuadro negro pequeno con una muesca arriba y el icono (el nombre, en la tarjeta).
      - Fila de arriba: accesos rapidos del personaje (faccion, inventario, telefono, logros con globo de pendientes, ayuda, ocultar HUD)
        y estados que te limitan, en rojo (esposado, abatido).
      - Fila de abajo, solo en un vehiculo: motor, freno de mano, cerradura, cinturon, balizas y radio.
    Encendido = icono y borde de color, apagado = gris. Con el cursor visible (M) cada ficha muestra su tecla dibujada;
    el que esta bajo el raton crece y abre una tarjeta con su estado, la tecla y lo que hace el clic.
    Un clic hace lo mismo que la tecla:
      - vehiculo: los comandos de rp_vehicles (bloquear, toggleengine, frenodemano, balizas),
        asi respetan las teclas que el jugador haya cambiado;
      - el resto: evento de cliente "rp:hud:action" (id) que escucha el recurso dueno
        (rp_phone, rp_inventory, rp_factions, rp_achievements, rp_help, rp_seatbelt, rp_radio) con sus mismas
        comprobaciones. El servidor revalida todo como con la tecla.
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.9, math.min(1.3, screenH / 900))
local MARGIN = math.floor(22 * s)
local GAP = math.floor(4 * s)         -- separacion entre fichas

addEvent("rp:hud:action", false)

----------------------------------------------------------------
-- Iconos (SVG propios, trazo blanco; el color se aplica al dibujar)
----------------------------------------------------------------
local W = 'stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"'
local ICON_SVG = {
    phone = '<rect x="15" y="6" width="18" height="36" rx="4" fill="none" ' .. W .. '/><path d="M21 36h6" ' .. W .. '/>',
    bag = '<path d="M11 18h26l-2 23H13z" fill="none" ' .. W .. '/><path d="M18 18v-3a6 6 0 0 1 12 0v3" fill="none" ' .. W .. '/>',
    flag = '<path d="M13 42V7" ' .. W .. '/><path d="M13 9h22l-5 7 5 7H13z" fill="#fff"/>',
    help = '<circle cx="24" cy="24" r="17" fill="none" ' .. W .. '/><path d="M18.5 19a5.5 5.5 0 1 1 7.5 5.1c-1.3.6-2 1.6-2 3V29" fill="none" ' .. W .. '/><circle cx="24" cy="34.5" r="2.4" fill="#fff"/>',
    eye = '<path d="M4 24s7-12 20-12 20 12 20 12-7 12-20 12S4 24 4 24z" fill="none" ' .. W .. '/><circle cx="24" cy="24" r="5.5" fill="#fff"/>',
    cuffs = '<circle cx="14" cy="29" r="8" fill="none" ' .. W .. '/><circle cx="34" cy="29" r="8" fill="none" ' .. W .. '/><path d="M19 20c2.5-5 7.5-5 10 0" fill="none" ' .. W .. '/>',
    cross = '<path d="M19 8h10v11h11v10H29v11H19V29H8V19h11z" fill="#fff"/>',
    power = '<path d="M15 13a15 15 0 1 0 18 0" fill="none" ' .. W .. '/><path d="M24 6v17" ' .. W .. '/>',
    lock = '<rect x="11" y="21" width="26" height="20" rx="3" fill="#fff"/><path d="M16 21v-5a8 8 0 0 1 16 0v5" fill="none" ' .. W .. '/>',
    unlock = '<rect x="11" y="21" width="26" height="20" rx="3" fill="#fff"/><path d="M16 21v-5a8 8 0 0 1 15.5-2.8" fill="none" ' .. W .. '/>',
    handbrake = '<circle cx="24" cy="24" r="13" fill="none" ' .. W .. '/><path d="M9 12a18 18 0 0 0 0 24M39 12a18 18 0 0 1 0 24" fill="none" ' .. W .. '/><path d="M21 31V17h4.5a4 4 0 0 1 0 8H21" fill="none" ' .. W .. '/>',
    belt = '<circle cx="24" cy="10" r="5" fill="#fff"/><path d="M14 42V27a10 10 0 0 1 20 0v15" fill="none" ' .. W .. '/><path d="M15 21l18 18" ' .. W .. '/>',
    hazard = '<path d="M24 6l19 33H5z" fill="none" ' .. W .. '/><path d="M24 19l8 14H16z" fill="none" ' .. W .. '/>',
    radio = '<path d="M19 34V11l18-4v23" fill="none" ' .. W .. '/><circle cx="14" cy="34" r="5.5" fill="#fff"/><circle cx="32" cy="30" r="5.5" fill="#fff"/>',
    trophy = '<path d="M15 8h18v10a9 9 0 0 1-18 0z" fill="#fff"/><path d="M15 11H9a5 5 0 0 0 6 8M33 11h6a5 5 0 0 1-6 8" fill="none" ' .. W .. '/><path d="M24 27v7M17 40h14" ' .. W .. '/>',
}
local icons = {}
local function icon(name)
    if icons[name] == nil then
        local body = ICON_SVG[name]
        icons[name] = body and svgCreate(96, 96,
            '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 48 48">' .. body .. '</svg>') or false
    end
    return icons[name] or nil
end

-- Teclas dibujadas (Kenney, images/keys). Sin imagen se dibuja el nombre de la tecla en un recuadro.
local KEY_ALIAS = { arrow_d = "arrow_down", arrow_u = "arrow_up", arrow_l = "arrow_left", arrow_r = "arrow_right" }
local keyTextures = {}
local function keyTex(name)
    if keyTextures[name] == nil then
        local path = "images/keys/" .. name .. ".png"
        keyTextures[name] = fileExists(path) and dxCreateTexture(path, "argb", true, "clamp") or false
    end
    return keyTextures[name] or nil
end

local function drawKey(k, x, y, size, alpha)
    if not k then return 0 end
    local tex = keyTex("keyboard_" .. (KEY_ALIAS[k] or k))
    if tex then
        dxDrawImage(x, y, size, size, tex, 0, 0, 0, tocolor(255, 255, 255, alpha))
        return size
    end
    local label = k:upper()
    local w = math.max(size, dxGetTextWidth(label, 0.8 * s, "default-bold") + 8 * s)
    dxDrawRectangle(x, y + size * 0.1, w, size * 0.8, tocolor(255, 255, 255, alpha * 0.9))
    dxDrawText(label, x, y, x + w, y + size, tocolor(20, 22, 28, alpha), 0.8 * s, "default-bold", "center", "center")
    return w
end

----------------------------------------------------------------
-- Botones
--   kind: "toggle" (encendido / apagado), "open" (abre un panel), "status" (solo informa, sin clic)
--   state(v) devuelve: encendido, texto de estado, color {r,g,b} cuando esta encendido, alerta (late)
----------------------------------------------------------------
local GREEN, AMBER, RED, BLUE, WHITE = { 76, 211, 138 }, { 245, 165, 36 }, { 229, 72, 77 }, { 93, 182, 229 }, { 235, 238, 244 }

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end
local function action(id) return function() triggerEvent("rp:hud:action", localPlayer, id) end end
local function command(cmd) return function() executeCommandHandler(cmd) end end
-- Tecla actual de un comando (el jugador puede cambiarla en Ajustes > Binds)
local function boundKey(cmd, default) return function() return getKeyBoundToCommand(cmd) or default end end

local function isDriver(v) return v and getVehicleController(v) == localPlayer end
local function vtype(v) return v and getVehicleType(v) end
local NO_ENGINE = { BMX = true }
local NO_DOORS = { BMX = true, Bike = true, Quad = true }
local BELT_TYPES = { Automobile = true, ["Monster Truck"] = true }   -- mismos que rp_seatbelt

local PLAYER_BUTTONS = {
    { id = "cuffed", label = "ESPOSADO", kind = "status", icon = "cuffs", title = "Esposado",
      visible = function() return getElementData(localPlayer, "rp:cuffed") end,
      state = function() return true, "No puedes usar el telefono ni el inventario", RED, true end },
    { id = "downed", label = "ABATIDO", kind = "status", icon = "cross", title = "Abatido",
      visible = function() return getElementData(localPlayer, "rp:downed") end,
      state = function() return true, "Te desangras: pide ayuda con /911", RED, true end },
    { id = "faction", label = "FACCION", kind = "open", icon = "flag", key = "f3", hint = "abrir el panel de tu faccion",
      visible = function() return type(getElementData(localPlayer, "rp:faction")) == "table" and running("rp_factions") end,
      title = function()
          local f = getElementData(localPlayer, "rp:faction")
          return type(f) == "table" and tostring(f.name or "Faccion") or "Faccion"
      end,
      state = function()
          local f = getElementData(localPlayer, "rp:faction")
          local rank = type(f) == "table" and f.rank or ""
          return true, rank ~= "" and ("Rango: " .. rank) or "Miembro", WHITE
      end,
      run = action("faction") },
    { id = "inventory", label = "OBJETOS", kind = "open", icon = "bag", key = "i", title = "Inventario", hint = "ver lo que llevas encima",
      visible = function() return running("rp_inventory") end,
      state = function() return true, "Tus objetos, armas y llaves", WHITE end,
      run = action("inventory") },
    { id = "phone", label = "TELEFONO", kind = "open", icon = "phone", key = "p", title = "Telefono", hint = "sacar el telefono",
      visible = function() return running("rp_phone") end,
      state = function() return true, "Llamadas, banco, Vroom, redes...", WHITE end,
      run = action("phone") },
    -- Logros (rp_achievements): globo con lo pendiente (medallas nuevas sin ver + recompensas por
    -- reclamar; "!" si nunca abriste los logros). Lo publica rp_achievements en el elementData
    -- local (sin sincronizar) rp:achBadge = numero o "!".
    { id = "achievements", label = "LOGROS", kind = "open", icon = "trophy", title = "Logros", hint = "ver tus logros y recompensas",
      visible = function() return running("rp_achievements") end,
      badge = function() return getElementData(localPlayer, "rp:achBadge") end,
      state = function()
          local b = getElementData(localPlayer, "rp:achBadge")
          if b == "!" then return true, "¡Descubre tus logros y gana recompensas!", AMBER end
          if tonumber(b) and b > 0 then return true, ("Tienes %d novedades: medallas o recompensas"):format(b), AMBER end
          return true, "Medallas, puntos y recompensas", WHITE
      end,
      run = action("achievements") },
    { id = "help", label = "AYUDA", kind = "open", icon = "help", key = "f1", title = "Ayuda", hint = "abrir la ayuda",
      visible = function() return running("rp_help") end,
      state = function() return true, "Guia, reglas, teclas y reportes", WHITE end,
      run = action("help") },
    { id = "hud", label = "HUD", kind = "open", icon = "eye", key = "f7", title = "Ocultar HUD", hint = "ocultarlo (vuelve con F7)",
      visible = function() return true end,
      state = function() return true, "Para capturas o rol sin distracciones", WHITE end,
      run = command("hud") },
}

local VEHICLE_BUTTONS = {
    { id = "engine", label = "MOTOR", kind = "toggle", icon = "power", title = "Motor", key = boundKey("toggleengine", "j"),
      visible = function(v) return isDriver(v) and not NO_ENGINE[vtype(v)] end,
      state = function(v)
          local on = getVehicleEngineState(v)
          return on, on and "Encendido" or "Apagado (necesitas la llave)", GREEN
      end,
      hint = function(on) return on and "apagarlo" or "encenderlo" end,
      run = command("toggleengine") },
    { id = "handbrake", label = "FRENO", kind = "toggle", icon = "handbrake", title = "Freno de mano", key = boundKey("frenodemano", "x"),
      visible = function(v) return isDriver(v) and not NO_ENGINE[vtype(v)] end,
      state = function(v)
          local on = getElementData(v, "rp:handbrake") and true or false
          return on, on and "Puesto" or "Quitado", RED
      end,
      hint = function(on) return on and "quitarlo" or "ponerlo (detenido)" end,
      run = command("frenodemano") },
    { id = "lock", label = "PUERTAS", kind = "toggle", title = "Cerradura", key = boundKey("bloquear", "l"),
      icon = function(v) return isVehicleLocked(v) and "lock" or "unlock" end,
      visible = function(v) return not NO_DOORS[vtype(v)] end,
      state = function(v)
          local on = isVehicleLocked(v)
          return on, on and "Puertas cerradas" or "Puertas abiertas", AMBER
      end,
      hint = function(on) return on and "abrir (con la llave)" or "cerrar (con la llave)" end,
      run = command("bloquear") },
    { id = "seatbelt", label = "CINTURON", kind = "toggle", icon = "belt", title = "Cinturon", key = "c",
      visible = function(v) return BELT_TYPES[vtype(v)] and running("rp_seatbelt") end,
      state = function(v)
          local on = getElementData(localPlayer, "rp:seatbelt") == true
          local vx, vy, vz = getElementVelocity(v)
          local fast = (vx * vx + vy * vy + vz * vz) ^ 0.5 * 180 > 30
          return on, on and "Puesto" or "Sin cinturon: un choque te saca por el parabrisas", GREEN, not on and fast
      end,
      hint = function(on) return on and "quitartelo" or "ponertelo" end,
      run = action("seatbelt") },
    { id = "hazard", label = "BALIZAS", kind = "toggle", icon = "hazard", title = "Balizas", key = boundKey("balizas", "arrow_d"),
      visible = function(v) return isDriver(v) and not NO_ENGINE[vtype(v)] end,
      state = function(v)
          local on = getElementData(v, "rp:indicator") == "hazard"
          return on, on and "Encendidas" or "Apagadas", AMBER
      end,
      hint = function(on) return on and "apagarlas" or "encenderlas" end,
      run = command("balizas") },
    { id = "radio", label = "RADIO", kind = "toggle", icon = "radio", title = "Radio", key = "r",
      visible = function(v)
          local seat = getPedOccupiedVehicleSeat(localPlayer)
          return (seat == 0 or seat == 1) and running("rp_radio")
      end,
      state = function(v)
          local on = getElementData(v, "rp:radio") and true or false
          return on, on and "Sonando" or "Apagada", BLUE
      end,
      hint = function() return "elegir emisora" end,
      run = action("radio") },
}

----------------------------------------------------------------
-- Dibujo: fichas negras con muesca arriba, nombre en mayusculas y el icono debajo
----------------------------------------------------------------
-- Fichas pequenas, como las de OwlGaming: solo el icono; el nombre sale en la tarjeta al pasar el raton.
-- Las medidas siguen la proporcion de la silueta SVG (56 x 61, muesca de 7,5).
local TW = math.floor(30 * s)          -- ancho de la ficha
local TH = math.floor(TW * 61 / 56)    -- alto total
local NOTCH = math.floor(TH * 7.5 / 61 + 0.5)  -- alto de la muesca de arriba
local TB = TH - NOTCH                  -- alto del cuerpo
local ROW_GAP = math.floor(5 * s)
local SHOW_LABEL = false               -- true = nombre en mayusculas dentro de la ficha (fichas grandes)

-- Silueta de la ficha (blanca; se tine al dibujar): cuerpo redondeado y muesca centrada arriba
local TILE_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="112" height="122" viewBox="0 0 56 61">'
    .. '<path d="M22 7.5L28 1l6 6.5h13a8 8 0 0 1 8 8V53a8 8 0 0 1-8 8H9a8 8 0 0 1-8-8V15.5a8 8 0 0 1 8-8z" fill="%s" %s/></svg>'
local tileFill, tileLine
local function tileTextures()
    if tileFill == nil then
        tileFill = svgCreate(112, 122, TILE_SVG:format("#fff", "")) or false
        tileLine = svgCreate(112, 122, TILE_SVG:format("none", 'stroke="#fff" stroke-width="2"')) or false
    end
    return tileFill or nil, tileLine or nil
end

local labelFont
local function font()
    if labelFont == nil then
        labelFont = dxCreateFont("fonts/rubik_semibold.ttf", math.max(8, math.floor(11 * s)), false, "antialiased") or false
    end
    return labelFont or "default-bold"
end

-- Globo rojo de contador (esquina de arriba a la derecha de la ficha)
local badgeTex
local function badgeTexture()
    if badgeTex == nil then
        badgeTex = svgCreate(64, 64, '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            .. '<circle cx="32" cy="32" r="29" fill="#fff"/></svg>') or false
    end
    return badgeTex or nil
end
local lastBadge = {}      -- [id] = ultimo valor (para el salto al subir)
local badgeBump = {}      -- [id] = tick del salto

local function drawBadge(b, dx, dy, w, now)
    local v = b.badge and b.badge()
    local n = tonumber(v)
    if not (v == "!" or (n and n > 0)) then lastBadge[b.id] = v return end
    if v ~= lastBadge[b.id] and (v == "!" or (tonumber(lastBadge[b.id]) or 0) < (n or 0)) then badgeBump[b.id] = now end
    lastBadge[b.id] = v
    local text = v == "!" and "!" or (n > 9 and "9+" or tostring(n))
    local k = badgeBump[b.id] and (now - badgeBump[b.id]) / 450 or 1
    local bump = k < 1 and (1 + 0.45 * math.sin(k * math.pi)) or (1 + 0.06 * math.sin(now / 260))   -- late un poco siempre
    local size = math.floor(15 * s) * bump
    local cx, cy = dx + w - 2 * s, dy + 4 * s
    local tex = badgeTexture()
    local red = tocolor(229, 72, 77, 255)
    if tex then
        dxDrawImage(cx - size / 2 - 1, cy - size / 2 - 1, size + 2, size + 2, tex, 0, 0, 0, tocolor(0, 0, 0, 200))   -- borde
        dxDrawImage(cx - size / 2, cy - size / 2, size, size, tex, 0, 0, 0, red)
    else
        dxDrawCircle(cx, cy, size / 2, 0, 360, red)
    end
    local scale = 0.62 * s * bump
    dxDrawText(text, cx - size, cy - size, cx + size, cy + size, tocolor(255, 255, 255), scale, font(), "center", "center")
end

local hover = {}          -- [id] = 0..1 (animacion al pasar el raton)
local pop = {}            -- [id] = tick del ultimo clic
local hovered = nil       -- { b = boton, st = estado, x, y }
local hoveredAt = 0
local lastHoverId = nil
local lastClick = {}

local function value(f, ...) if type(f) == "function" then return f(...) end return f end

local function drawButton(b, st, x, y, now, cursor, mx, my)
    local on, color, alert = st[1], st[3] or WHITE, st[4]
    local isOver = cursor and mx >= x and mx <= x + TW and my >= y and my <= y + TH
    hover[b.id] = (hover[b.id] or 0) + ((isOver and 1 or 0) - (hover[b.id] or 0)) * 0.25
    local h = hover[b.id]
    local p = pop[b.id] and (now - pop[b.id]) / 260 or 1
    local press = p < 1 and (1 - 0.08 * math.sin(p * math.pi)) or 1
    local k = (1 + 0.15 * h) * press
    local w, hh = TW * k, TH * k
    local dx, dy = x + (TW - w) / 2, y + (TH - hh) / 2
    local pulse = alert and (0.55 + 0.45 * math.sin(now / 140)) or 1
    local off = b.kind == "toggle" and not on and not alert

    -- Fondo: negro; rojo que late si es una alerta o un estado; mas transparente si esta apagado
    local fill, line = tileTextures()
    local bg
    if alert or b.kind == "status" then
        bg = tocolor(150 + 50 * pulse, 30, 34, 235)
    else
        bg = tocolor(0, 0, 0, off and 165 or 230)
    end
    if fill then dxDrawImage(dx, dy, w, hh, fill, 0, 0, 0, bg) else dxDrawRectangle(dx, dy + NOTCH * k, w, TB * k, bg) end
    -- Borde: color del estado si esta encendido, blanco al pasar el raton
    if line then
        local lc
        if h > 0.05 then lc = tocolor(255, 255, 255, 230 * h)
        elseif b.kind == "toggle" and on then lc = tocolor(color[1], color[2], color[3], 200) end
        if lc then dxDrawImage(dx, dy, w, hh, line, 0, 0, 0, lc) end
    end

    -- Nombre arriba (se encoge si no cabe) e icono debajo
    local textCol = off and tocolor(150, 156, 166, 170) or tocolor(255, 255, 255, 255)
    local bodyY = dy + NOTCH * k
    local labelH = 0
    if SHOW_LABEL then
        local label = tostring(b.label or "")
        local f = font()
        local scale = k
        local tw = dxGetTextWidth(label, scale, f)
        if tw > w - 6 * s then scale = scale * (w - 6 * s) / tw end
        labelH = dxGetFontHeight(scale, f) + 4 * s
        dxDrawText(label, dx, bodyY + 3 * s, dx + w, bodyY + 3 * s + labelH, textCol, scale, f, "center", "top")
    end

    local tex = icon(value(b.icon, b.vehicle))
    if tex then
        local is = math.min(w * 0.68, TB * k - labelH - 6 * s)
        local tint
        if off then tint = tocolor(150, 156, 166, 150)
        elseif b.kind == "toggle" then tint = tocolor(color[1], color[2], color[3], 255)
        else tint = tocolor(255, 255, 255, 255) end
        dxDrawImage(dx + (w - is) / 2, bodyY + labelH + ((TB * k - labelH) - is) / 2, is, is, tex, 0, 0, 0, tint)
    end

    -- Con el cursor visible: la tecla de cada accion en la esquina
    local key = value(b.key)
    if cursor and key and b.kind ~= "status" then
        local ks = math.floor(14 * s)
        drawKey(key, dx + w - ks * 0.7, dy + hh - ks * 0.7, ks, 240)
    end
    if b.badge then drawBadge(b, dx, dy, w, now) end

    if isOver then
        hovered = { b = b, st = st, x = x, y = y }
        hoveredAt = now
    end
end

-- Tarjeta con titulo, estado y "tecla o clic para ..." (debajo de la ficha)
local function drawTooltip(hv)
    local b, st = hv.b, hv.st
    local title = tostring(value(b.title) or "")
    local stateText = tostring(st[2] or "")
    local k = value(b.key)
    local hint = b.kind ~= "status" and value(b.hint, st[1]) or nil
    local pad, ks = 10 * s, math.floor(20 * s)
    local tS, sS = 1.0 * s, 0.9 * s
    local w = math.max(dxGetTextWidth(title, tS, "default-bold"), dxGetTextWidth(stateText, sS, "default"))
    if hint then
        w = math.max(w, ks + dxGetTextWidth(" o ", sS, "default") + ks + 6 * s + dxGetTextWidth(hint, sS, "default"))
    end
    w = w + pad * 2
    local th, sh = dxGetFontHeight(tS, "default-bold"), dxGetFontHeight(sS, "default")
    local h = pad * 2 + th + 2 * s + sh + (hint and (ks + 6 * s) or 0)
    local x = math.max(8 * s, math.min(hv.x + TW / 2 - w / 2, screenW - w - 8 * s))
    local y = hv.y + TH + 8 * s

    local c = st[3] or WHITE
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 235), true)
    dxDrawRectangle(x, y, w, math.max(2, math.floor(2 * s)), tocolor(c[1], c[2], c[3], 255), true)
    local ty = y + pad
    dxDrawText(title, x + pad, ty, x + w - pad, ty + th, tocolor(255, 255, 255), tS, "default-bold", "left", "top", false, false, true)
    ty = ty + th + 2 * s
    local stateCol = (b.kind == "toggle" and not st[1] and not st[4]) and tocolor(170, 178, 190) or tocolor(c[1], c[2], c[3])
    dxDrawText(stateText, x + pad, ty, x + w - pad, ty + sh, stateCol, sS, "default", "left", "top", false, false, true)
    if hint then
        ty = ty + sh + 6 * s
        local hx = x + pad
        if k then
            local tex = keyTex("keyboard_" .. (KEY_ALIAS[k] or k))
            local kw
            if tex then
                dxDrawImage(hx, ty, ks, ks, tex, 0, 0, 0, tocolor(255, 255, 255), true); kw = ks
            else
                local label = k:upper()
                kw = dxGetTextWidth(label, 0.8 * s, "default-bold") + 8 * s
                dxDrawRectangle(hx, ty + ks * 0.1, kw, ks * 0.8, tocolor(235, 238, 244), true)
                dxDrawText(label, hx, ty, hx + kw, ty + ks, tocolor(20, 22, 28), 0.8 * s, "default-bold", "center", "center", false, false, true)
            end
            hx = hx + kw
            dxDrawText(" o ", hx, ty, hx + 30 * s, ty + ks, tocolor(170, 178, 190), sS, "default", "left", "center", false, false, true)
            hx = hx + dxGetTextWidth(" o ", sS, "default")
        end
        local mouse = keyTex("mouse_left")
        if mouse then dxDrawImage(hx, ty, ks, ks, mouse, 0, 0, 0, tocolor(255, 255, 255), true) end
        hx = hx + ks + 6 * s
        dxDrawText(hint, hx, ty, x + w, ty + ks, tocolor(255, 255, 255), sS, "default", "left", "center", false, false, true)
    end
end

-- Fila de fichas de izquierda a derecha terminando en "right". Devuelve x inicial y ancho.
local function drawRow(list, right, y, now, cursor, mx, my, vehicle)
    local shown = {}
    for _, b in ipairs(list) do
        if b.visible(vehicle) then
            b.vehicle = vehicle
            shown[#shown + 1] = { b = b, st = { b.state(vehicle) } }
        end
    end
    if #shown == 0 then return nil end
    local total = #shown * TW + (#shown - 1) * GAP
    local x = right - total
    for i, e in ipairs(shown) do
        drawButton(e.b, e.st, x + (i - 1) * (TW + GAP), y, now, cursor, mx, my)
    end
    return x, total
end

-- Lo llama c_hud.lua cada frame, despues de la parte de arriba a la derecha.
-- Las fichas van a la izquierda del dinero: arriba los accesos rapidos y, en un vehiculo,
-- debajo sus controles.
function Hud.drawIconBars(now)
    local cursor = isCursorShowing() and not isMainMenuActive() and not Hud.clicksDisabled()
    local mx, my = 0, 0
    if cursor then
        local cx, cy = getCursorPosition()
        if cx then mx, my = cx * screenW, cy * screenH else cursor = false end
    end
    hovered = nil

    local right = (Hud.topRightLeft or (screenW - MARGIN - 160 * s)) - 14 * s
    local y = MARGIN - NOTCH

    local x, w = drawRow(PLAYER_BUTTONS, right, y, now, cursor, mx, my, nil)
    if x then
        Hud.setRect("iconbar", x - 4 * s, y - 4 * s, w + 8 * s, TH + 8 * s)
        y = y + TH + ROW_GAP
    end

    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle then
        -- la segunda fila queda a la altura del arma, las estrellas y el nivel: va a la izquierda de todo eso
        local lowRight = math.min(right, (Hud.topRightLeftLow or Hud.topRightLeft or right) - 14 * s)
        local vx, vw = drawRow(VEHICLE_BUTTONS, lowRight, y, now, cursor, mx, my, vehicle)
        if vx then Hud.setRect("vehbar", vx - 4 * s, y - 4 * s, vw + 8 * s, TH + 8 * s) end
    end

    if hovered then
        if lastHoverId ~= hovered.b.id then Hud.sound("hover", 60) end
        lastHoverId = hovered.b.id
        drawTooltip(hovered)
    else
        lastHoverId = nil
    end
end

----------------------------------------------------------------
-- Clic
----------------------------------------------------------------
addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" or not hovered or Hud.clicksDisabled() then return end
    local now = getTickCount()
    if now - hoveredAt > 200 then return end           -- el HUD dejo de dibujarse
    if isChatBoxInputActive() or isConsoleActive() then return end
    local b = hovered.b
    if b.kind == "status" or not b.run then return end
    if lastClick[b.id] and now - lastClick[b.id] < 400 then return end
    lastClick[b.id] = now
    pop[b.id] = now
    Hud.sound("click", 0)
    b.run()
end)
