--[[
    rp_hud / c_hud.lua
    HUD propio que sustituye al de GTA:
      - Minimapa giratorio (abajo a la izquierda) con el mapa del radar de GTA SA
        extraido de la instalacion del jugador (images/map.png), blips y flecha.
      - Panel de vida, chaleco y necesidades (hambre, sed, energia) con avisos y clima.
      - Hora del juego, dinero, zona y municion (arriba a la derecha).
      - Velocimetro y bencina (abajo a la derecha) cuando vas en un vehiculo
        (litros en el elementData "rp:fuel" / "rp:fuelMax" que pone rp_vehicles).
    /hud (o F7) oculta o muestra el HUD; /hud necesidades|mapa|velocimetro lo configura.
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.9, math.min(1.3, screenH / 900))   -- minimo 0.9: en ventanas pequenas el texto era ilegible

local MAP_SIZE = 1536          -- px del archivo map.png
local WORLD = 6000             -- unidades que cubre el mapa (-3000 a 3000)
local MS = math.floor(220 * s) -- tamano del minimapa en pantalla
local MARGIN = math.floor(22 * s)

local mapTexture, renderTarget

-- Iconos de blips dibujados para el gamemode (images/blips/<id de icono>.png)
-- 17 = tienda/robo, 22 = emergencias, 36 = autoescuela, 52 = tienda,
-- 54 = arriendo de bicicletas, 56 = trabajos/agencia, 63 = policia.
local BLIP_ICON_IDS = { 17, 22, 27, 36, 41, 45, 51, 52, 54, 55, 56, 63 }
local KNOWN_BLIP_ICON_IDS = {
    [0] = true,
    [17] = true,
    [22] = true,
    [27] = true,
    [36] = true,
    [41] = true,
    [45] = true,
    [51] = true,
    [52] = true,
    [54] = true,
    [55] = true,
    [56] = true,
    [63] = true,
}
local zoomUnits = 300
local BLIP_MAX_DISTANCE = 900   -- metros: mas lejos no se muestran en el minimapa (si en F11)
local blipIcons = {}
for _, id in ipairs(BLIP_ICON_IDS) do
    local path = ("images/blips/%d.png"):format(id)
    if fileExists(path) then blipIcons[id] = dxCreateTexture(path, "argb", true, "clamp") end
end
local enabled = true
local prefs = { needs = true, map = true, speedo = true }   -- /hud necesidades|mapa|velocimetro
local PREFS_FILE = "@hud_prefs.xml"

local COLORS = {
    panel = tocolor(12, 14, 20, 200),
    border = tocolor(255, 255, 255, 30),
    text = tocolor(242, 244, 248),
    muted = tocolor(154, 163, 178),
    accent = tocolor(245, 165, 36),
    money = tocolor(76, 211, 138),
    moneyDown = tocolor(229, 72, 77),
}
-- Paleta tomada del kit de Figma (Grand Figma Kit V):
--   vida #4f914a sobre #2e592a, dinero #84e36c / baja #f09999 (contorno negro),
--   barras de progreso "Good" #78ff74 y "Urgent" #e03232 sobre su propio color al 20 %,
--   filas con degradado negro (0 % -> 80 %) de izquierda a derecha.
local BAR = {
    health = { 79, 145, 74 }, healthLost = { 46, 89, 42 },
    armor = { 86, 150, 200 }, armorLost = { 28, 52, 72 },
    good = { 120, 255, 116 }, normal = { 245, 200, 70 }, urgent = { 224, 50, 50 },
    level = { 93, 182, 229 },
}
local MONEY_UP, MONEY_DOWN = { 132, 227, 108 }, { 240, 153, 153 }
local STRIP_H = math.floor(20 * s)   -- alto de las barras de vida/chaleco bajo el minimapa

local OUT = math.max(1, math.floor(1.5 * s + 0.5))
local OFFS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

-- Texto con contorno negro (como los numeros de dinero del juego)
local function outlineText(text, x1, y1, x2, y2, color, scale, font, ax, ay)
    local black = tocolor(0, 0, 0, 255)
    for _, o in ipairs(OFFS) do
        dxDrawText(text, x1 + o[1] * OUT, y1 + o[2] * OUT, x2 + o[1] * OUT, y2 + o[2] * OUT, black, scale, font, ax, ay, false, false, false)
    end
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, ax, ay, false, false, false)
end

local function shadowText(text, x1, y1, x2, y2, color, scale, font, ax, ay)
    dxDrawText(text, x1 + 1, y1 + 1, x2 + 1, y2 + 1, tocolor(0, 0, 0, 200), scale, font, ax, ay, true)
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, ax, ay, true)
end

-- Degradado negro de las filas (64x1 px): alfa 0 -> 204 (0xCC). reversed = al reves
local gradients = {}
local function getGradient(reversed)
    local key = reversed and "r" or "n"
    if isElement(gradients[key]) then return gradients[key] end
    local tex = dxCreateTexture(64, 1, "argb", "clamp")
    if not tex then return nil end
    local px = dxGetTexturePixels(tex)
    for i = 0, 63 do
        local k = math.min(1, (reversed and (63 - i) or i) / 56)
        dxSetPixelColor(px, i, 0, 0, 0, 0, math.floor(204 * k))
    end
    dxSetTexturePixels(tex, px)
    gradients[key] = tex
    return tex
end

local function drawRowPanel(x, y, w, h, reversed)
    local tex = getGradient(reversed)
    if tex then dxDrawImage(x, y, w, h, tex) else dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 140)) end
end

----------------------------------------------------------------
-- Componentes de GTA
----------------------------------------------------------------
local function hideGtaHud()
    setPlayerHudComponentVisible("all", false)
    setPlayerHudComponentVisible("crosshair", true)
end

local function isActive()
    return enabled and getElementData(localPlayer, "rp:characterId") and not isPlayerMapVisible()
        and not getElementData(localPlayer, "rp:hudHidden")   -- p. ej. al tomar una foto con el telefono
end

----------------------------------------------------------------
-- Minimapa
----------------------------------------------------------------
local function worldToMap(x, y)
    return (x + WORLD / 2) / WORLD * MAP_SIZE, (WORLD / 2 - y) / WORLD * MAP_SIZE
end

local function getCameraHeading()
    local cx, cy, _, tx, ty = getCameraMatrix()
    return math.deg(math.atan2(tx - cx, ty - cy))   -- 0 = norte, sentido horario
end

local function rotate(x, y, angle)
    local r = math.rad(angle)
    local c, sn = math.cos(r), math.sin(r)
    return x * c - y * sn, x * sn + y * c
end

local function drawMinimap(x, y)
    if not mapTexture or not renderTarget then return end
    local px, py, pz = getElementPosition(localPlayer)
    local heading = getCameraHeading()

    -- Zoom: mas lejos cuanto mas rapido vas
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local speed = 0
    if vehicle then
        local vx, vy, vz = getElementVelocity(vehicle)
        speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
    end
    -- El zoom cambia suave: si salta, los iconos parecen moverse solos
    local target = 300 + math.min(speed, 160) * 2
    zoomUnits = zoomUnits + (target - zoomUnits) * 0.03
    local unitsAcross = zoomUnits
    local unitPx = MS / unitsAcross

    local interior = getElementInterior(localPlayer) ~= 0

    dxSetRenderTarget(renderTarget, true)
    if interior then
        dxDrawRectangle(0, 0, MS, MS, tocolor(30, 33, 40, 255))
        dxDrawText("Interior", 0, 0, MS, MS, COLORS.muted, 1.1 * s, "default-bold", "center", "center")
    else
        local mx, my = worldToMap(px, py)
        local section = unitsAcross / WORLD * MAP_SIZE * 1.5
        local size = MS * 1.5
        dxDrawImageSection(MS / 2 - size / 2, MS / 2 - size / 2, size, size,
            mx - section / 2, my - section / 2, section, section, mapTexture, -heading)

        -- Blips (tiendas, etc.): icono propio si existe images/blips/<icono>.png,
        -- si no un cuadrado del color del blip. Solo dentro de su distancia visible.
        for _, blip in ipairs(getElementsByType("blip")) do
            if getElementDimension(blip) == getElementDimension(localPlayer) then
                local bx, by = getElementPosition(blip)
                local worldDist = getDistanceBetweenPoints2D(px, py, bx, by)
                local iconId = getBlipIcon(blip)
                -- Solo se muestran blips conocidos. Los puntos normales (0) esperan
                -- a estar cerca; 41 pertenece a la navegacion activa y siempre es visible.
                local known = KNOWN_BLIP_ICON_IDS[iconId]
                local always = iconId == 41
                local visibleDistance = math.min(getBlipVisibleDistance(blip) or 99999, BLIP_MAX_DISTANCE)
                if known and (always or worldDist <= visibleDistance) then
                    local dx, dy = (bx - px) * unitPx, -(by - py) * unitPx
                    dx, dy = rotate(dx, dy, -heading)
                    local half = MS / 2 - 14 * s
                    local outside = math.abs(dx) > half or math.abs(dy) > half
                    -- Los lugares solo se dibujan si caen dentro del minimapa (no se
                    -- arrastran por el borde); el destino de navegacion si se fija al borde.
                    if outside and always then
                        local k = half / math.max(math.abs(dx), math.abs(dy))
                        dx, dy = dx * k, dy * k
                    end
                    if not outside or always then
                    local icon = blipIcons[iconId]
                    if icon then
                        local is = 26 * s
                        dxDrawImage(MS / 2 + dx - is / 2, MS / 2 + dy - is / 2, is, is, icon)
                    else
                        local r, g, b = getBlipColor(blip)
                        local bs = 11 * s
                        dxDrawRectangle(MS / 2 + dx - bs / 2 - 1, MS / 2 + dy - bs / 2 - 1, bs + 2, bs + 2, tocolor(0, 0, 0, 200))
                        dxDrawRectangle(MS / 2 + dx - bs / 2, MS / 2 + dy - bs / 2, bs, bs, tocolor(r, g, b, 255))
                    end
                    end
                end
            end
        end

        -- Norte
        local nx, ny = rotate(0, -(MS / 2 - 12 * s), -heading)
        dxDrawText("N", MS / 2 + nx - 10, MS / 2 + ny - 10, MS / 2 + nx + 10, MS / 2 + ny + 10, tocolor(255, 255, 255, 230), 1.0 * s, "default-bold", "center", "center")
    end

    -- Flecha del jugador
    local _, _, rz = getElementRotation(vehicle or localPlayer)
    -- GTA: rz=0 norte y crece en sentido antihorario -> rumbo horario = -rz
    local angle = -rz - heading
    local tip = { rotate(0, -11 * s, angle) }
    local left = { rotate(-7 * s, 8 * s, angle) }
    local right = { rotate(7 * s, 8 * s, angle) }
    local back = { rotate(0, 4 * s, angle) }
    local c, cx, cy = tocolor(245, 165, 36, 255), MS / 2, MS / 2
    dxDrawPrimitive("trianglelist", false,
        { cx + tip[1], cy + tip[2], c }, { cx + left[1], cy + left[2], c }, { cx + back[1], cy + back[2], c },
        { cx + tip[1], cy + tip[2], c }, { cx + back[1], cy + back[2], c }, { cx + right[1], cy + right[2], c })
    dxSetRenderTarget()

    -- Marco + mapa
    dxDrawRectangle(x - 3, y - 3, MS + 6, MS + 6, COLORS.panel)
    dxDrawImage(x, y, MS, MS, renderTarget)
    dxDrawRectangle(x, y, MS, 2, COLORS.accent)

    -- Zona
    local zone = interior and "Interior" or getZoneName(px, py, pz)
    dxDrawRectangle(x - 3, y - 26 * s, MS + 6, 22 * s, COLORS.panel)
    dxDrawText(zone, x, y - 26 * s, x + MS, y - 4 * s, COLORS.text, 1.0 * s, "default-bold", "center", "center", true)
end

----------------------------------------------------------------
-- Estado: vida / chaleco + necesidades compactas + avisos
-- Las necesidades se leen solo cuando cambia el elementData "rp:needs"
-- (cada minuto), no en cada frame; el resto se dibuja con rectangulos.
----------------------------------------------------------------
local NEEDS = {
    { key = "hunger", icon = "food",  r = 245, g = 165, b = 36 },
    { key = "thirst", icon = "drop", r = 70,  g = 150, b = 255 },
    { key = "energy", icon = "bolt", r = 168, g = 120, b = 255 },
    { key = "stamina", icon = "run", r = 63, g = 191, b = 106 },   -- solo cliente, no se guarda
}
local needValues = { hunger = 100, thirst = 100, energy = 100, stamina = 100 }
local needShown = { hunger = 100, thirst = 100, energy = 100, stamina = 100 }   -- valor suavizado para animar

-- Estamina: baja corriendo (sprint), sube trotando/caminando/quieto. Al agotarse
-- se bloquea el sprint hasta recuperar STAMINA_RESUME.
local STAMINA_DRAIN, STAMINA_REGEN, STAMINA_RESUME = 8, 5, 20   -- puntos/segundo, puntos/segundo, %
local staminaTick = getTickCount()
local staminaLocked = false

local function updateStamina()
    local now = getTickCount()
    local dt = math.min((now - staminaTick) / 1000, 0.5)
    staminaTick = now
    local st = needValues.stamina
    if not isPedInVehicle(localPlayer) and getPedMoveState(localPlayer) == "sprint" then
        st = st - STAMINA_DRAIN * dt
    else
        st = st + STAMINA_REGEN * dt
    end
    st = math.max(0, math.min(100, st))
    needValues.stamina = st
    if st <= 0 and not staminaLocked then
        staminaLocked = true
        toggleControl("sprint", false)
    elseif staminaLocked and st >= STAMINA_RESUME and needValues.energy > 0 then   -- energia 0 la bloquea rp_needs
        staminaLocked = false
        toggleControl("sprint", true)
    end
end
local statusLines = {}
local hasNeeds = false   -- false hasta recibir "rp:needs" (no mostrar 100 falsos)
local worldLabel = nil

local function refreshNeeds()
    local n = getElementData(localPlayer, "rp:needs")
    local lines = {}
    hasNeeds = type(n) == "table"
    if type(n) == "table" then
        for _, need in ipairs(NEEDS) do needValues[need.key] = tonumber(n[need.key]) or needValues[need.key] end
        if (n.hunger or 100) <= 0 or (n.thirst or 100) <= 0 then
            lines[#lines + 1] = { "Sin comida/bebida: pierdes vida", 229, 72, 77 }
        end
        if (n.energy or 100) <= 0 then lines[#lines + 1] = { "Agotado: no puedes correr (/dormir)", 168, 120, 255 } end
    end
    statusLines = lines
end

local function refreshWorld()
    local w = getElementData(root, "rp:world")
    worldLabel = type(w) == "table" and w.label or nil
end

local ICONS = {}
for _, name in ipairs({ "heart", "shield", "food", "drop", "bolt", "run" }) do
    ICONS[name] = dxCreateTexture("images/icons/" .. name .. ".png", "argb", true, "clamp")
end

-- Vida y chaleco bajo el minimapa (barras de 138x9 del kit, escaladas al ancho del mapa)
local function drawBars(x, y, w)
    if not prefs.needs then return end
    local gap = math.floor(4 * s)
    local h = math.floor(10 * s)
    local health, armor = getElementHealth(localPlayer), getPedArmor(localPlayer)
    local wH = armor > 0 and math.floor((w - gap) * 0.62) or w
    local pulse = health <= 25 and (150 + (getTickCount() % 600 < 300 and 105 or 0)) or 255

    dxDrawRectangle(x - 1, y - 1, wH + 2, h + 2, tocolor(0, 0, 0, 200))
    dxDrawRectangle(x, y, wH, h, tocolor(BAR.healthLost[1], BAR.healthLost[2], BAR.healthLost[3], 255))
    local hc = health <= 25 and BAR.urgent or BAR.health
    dxDrawRectangle(x, y, wH * math.max(0, math.min(1, health / 100)), h, tocolor(hc[1], hc[2], hc[3], pulse))
    if armor > 0 then
        local ax, aw = x + wH + gap, w - wH - gap
        dxDrawRectangle(ax - 1, y - 1, aw + 2, h + 2, tocolor(0, 0, 0, 200))
        dxDrawRectangle(ax, y, aw, h, tocolor(BAR.armorLost[1], BAR.armorLost[2], BAR.armorLost[3], 255))
        dxDrawRectangle(ax, y, aw * math.min(1, armor / 100), h, tocolor(BAR.armor[1], BAR.armor[2], BAR.armor[3], 255))
    end
end

-- Hambre / sed / energia: filas "Progress Bar" del kit (etiqueta + barra de 10 px sobre
-- degradado). Verde >= 50, ambar >= 20, rojo parpadeante por debajo.
-- Anillo que se llena en sentido horario desde las 12 (frac 0..1), como tira de triangulos
local function drawRing(cx, cy, r, thick, frac, color)
    frac = math.max(0, math.min(1, frac))
    if frac <= 0.002 then return end
    local segs = math.max(2, math.ceil(90 * frac))
    local verts = {}
    for i = 0, segs do
        local a = math.rad(-90 + 360 * frac * i / segs)
        local ca, sa = math.cos(a), math.sin(a)
        verts[#verts + 1] = { cx + ca * r, cy + sa * r, color }
        verts[#verts + 1] = { cx + ca * (r - thick), cy + sa * (r - thick), color }
    end
    dxDrawPrimitive("trianglestrip", false, unpack(verts))
end

-- Hambre / sed / energia: iconos compactos; el contorno se vacia segun lo que te queda.
-- Cada necesidad tiene su color (NEEDS); ambar < 35, rojo parpadeante < 20.
local function drawNeeds(x, bottom)
    if not prefs.needs or not hasNeeds then return bottom end
    updateStamina()
    for k, v in pairs(needValues) do needShown[k] = needShown[k] + (v - needShown[k]) * 0.12 end
    local D = math.floor(50 * s)          -- diametro de cada icono
    local gap = math.floor(10 * s)
    local thick = math.max(4, math.floor(5 * s))
    local top = bottom - D - math.floor(14 * s)   -- deja sitio al porcentaje
    local t = getTickCount()
    for i, need in ipairs(NEEDS) do
        local real, shown = needValues[need.key], needShown[need.key]
        local cx = x + D / 2 + (i - 1) * (D + gap)
        local cy = top + D / 2
        local r, g, b = need.r, need.g, need.b
        local low = real < 20
        if low then r, g, b = BAR.urgent[1], BAR.urgent[2], BAR.urgent[3]
        elseif real < 35 then r, g, b = BAR.normal[1], BAR.normal[2], BAR.normal[3] end
        local pulse = low and (math.sin(t / 170) * 0.5 + 0.5) or 0

        -- resplandor suave cuando esta critico
        if low then
            dxDrawCircle(cx, cy, D / 2 + 5 * s, 0, 360, tocolor(r, g, b, 40 + 60 * pulse), tocolor(r, g, b, 0), 40)
        end
        -- sombra + fondo + cristal
        dxDrawCircle(cx, cy, D / 2 + 2, 0, 360, tocolor(0, 0, 0, 150), tocolor(0, 0, 0, 150), 48)
        dxDrawCircle(cx, cy, D / 2, 0, 360, tocolor(14, 16, 24, 225), tocolor(14, 16, 24, 225), 48)
        -- pista (ring vacio) y progreso
        drawRing(cx, cy, D / 2, thick, 1, tocolor(255, 255, 255, 30))
        drawRing(cx, cy, D / 2, thick, shown / 100, tocolor(r, g, b, math.floor(215 + 40 * pulse)))
        -- disco interior ligeramente teñido con el color de la necesidad
        dxDrawCircle(cx, cy, D / 2 - thick - 1, 0, 360, tocolor(r, g, b, 38), tocolor(r, g, b, 14), 40)
        -- icono
        local isz = math.floor(D * 0.42)
        local tex = ICONS[need.icon]
        if tex then
            dxDrawImage(cx - isz / 2, cy - isz / 2, isz, isz, tex, 0, 0, 0, tocolor(255, 255, 255, 245))
        end
        -- porcentaje
        shadowText(("%d%%"):format(math.floor(shown + 0.5)), cx - D / 2, top + D + 1 * s, cx + D / 2, top + D + 14 * s,
            low and tocolor(r, g, b, 255) or tocolor(220, 224, 232, 230), 0.75 * s, "default-bold", "center", "center")
    end
    return top
end

-- Avisos de necesidades y clima, encima de las filas
local function drawStatusText(x, bottom)
    if not prefs.needs then return end
    local lh = 18 * s
    local ly = bottom - lh
    if worldLabel then
        shadowText("Clima: " .. worldLabel, x + 12 * s, ly, x + 280 * s, ly + lh, tocolor(235, 238, 245), 0.9 * s, "default-bold", "left", "center")
        ly = ly - lh
    end
    for i = #statusLines, 1, -1 do
        local line = statusLines[i]
        shadowText(line[1], x + 12 * s, ly, x + 340 * s, ly + lh, tocolor(line[2], line[3], line[4], 255), 0.9 * s, "default-bold", "left", "center")
        ly = ly - lh
    end
end

----------------------------------------------------------------
-- Hora, dinero y arma
----------------------------------------------------------------
local function formatMoney(n)
    local digits = tostring(math.floor(math.abs(n)))
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-$" or "$") .. digits
end

local MONEY_FLASH_MS = 2000
local lastMoney, moneyFlash
local MONEY_FONT = "pricedown"

local function drawTopRight()
    local hour, minute = getTime()
    local clock = ("%02d:%02d"):format(hour, minute)
    local right, top = screenW - MARGIN, MARGIN

    local clockH = dxGetFontHeight(1.5 * s, "default-bold")
    outlineText(clock, 0, top, right, top + clockH, tocolor(255, 255, 255), 1.5 * s, "default-bold", "right", "top")

    -- Dinero (Rockstar Pricedown 48 px, #84e36c con contorno negro); al cambiar muestra la
    -- diferencia debajo: sube = verde, baja = #f09999
    local current = getPlayerMoney(localPlayer)
    local now = getTickCount()
    if lastMoney and current ~= lastMoney then moneyFlash = { delta = current - lastMoney, t0 = now } end
    lastMoney = current
    local k = 0
    if moneyFlash then
        k = 1 - (now - moneyFlash.t0) / MONEY_FLASH_MS
        if k <= 0 then moneyFlash, k = nil, 0 end
    end

    local mScale = 1.35 * s
    local mH = dxGetFontHeight(mScale, MONEY_FONT)
    local my = top + clockH + 4 * s
    outlineText(formatMoney(current), 0, my, right, my + mH, tocolor(MONEY_UP[1], MONEY_UP[2], MONEY_UP[3]), mScale, MONEY_FONT, "right", "top")
    local nextY = my + mH + 2 * s

    -- Saldo del banco (elementData "rp:bankMoney" de rp_bank)
    local bank = tonumber(getElementData(localPlayer, "rp:bankMoney"))
    if bank then
        local bScale = 0.95 * s
        local bH = dxGetFontHeight(bScale, MONEY_FONT)
        local txt = formatMoney(bank)
        local tw = dxGetTextWidth(txt, bScale, MONEY_FONT)
        outlineText(txt, 0, nextY, right, nextY + bH, tocolor(130, 190, 255), bScale, MONEY_FONT, "right", "top")
        outlineText("BANCO", 0, nextY, right - tw - 8 * s, nextY + bH, tocolor(190, 200, 215), 0.8 * s, "default-bold", "right", "center")
        nextY = nextY + bH + 2 * s
    end

    if moneyFlash then
        local d = moneyFlash.delta
        local c = d > 0 and MONEY_UP or MONEY_DOWN
        local dScale = 1.0 * s
        local dH = dxGetFontHeight(dScale, MONEY_FONT)
        local txt = (d > 0 and "+" or "-") .. formatMoney(math.abs(d))
        local black = tocolor(0, 0, 0, 255 * k)
        for _, o in ipairs(OFFS) do
            dxDrawText(txt, o[1] * OUT, nextY + o[2] * OUT, right + o[1] * OUT, nextY + dH + o[2] * OUT, black, dScale, MONEY_FONT, "right", "top")
        end
        dxDrawText(txt, 0, nextY, right, nextY + dH, tocolor(c[1], c[2], c[3], 255 * k), dScale, MONEY_FONT, "right", "top")
        nextY = nextY + dH + 2 * s
    end

    local weapon = getPedWeapon(localPlayer)
    if weapon and weapon ~= 0 then
        local ammo = ("%s  %d / %d"):format(getWeaponNameFromID(weapon) or "Arma", getPedAmmoInClip(localPlayer), getPedTotalAmmo(localPlayer) - getPedAmmoInClip(localPlayer))
        local aH = dxGetFontHeight(1.05 * s, "default-bold")
        outlineText(ammo, 0, nextY, right, nextY + aH, tocolor(255, 255, 255), 1.05 * s, "default-bold", "right", "top")
        nextY = nextY + aH + 6 * s
    end

    -- Nivel (rp_levels): fila con degradado y barra de 10 tramos
    local level = tonumber(getElementData(localPlayer, "rp:level"))
    local frac = tonumber(getElementData(localPlayer, "rp:levelFrac"))
    if level and frac then
        local rowW, rowH = math.floor(260 * s), math.floor(35 * s)
        local rx = screenW - rowW
        local barW, barH = math.floor(144 * s), math.floor(10 * s)
        drawRowPanel(rx, nextY, rowW, rowH, false)
        dxDrawText("NIVEL " .. level, rx + 12 * s, nextY, rx + 12 * s + 96 * s, nextY + rowH, tocolor(255, 255, 255), 0.95 * s, "default-bold", "left", "center")
        local bx, by = rx + 12 * s + 96 * s, nextY + (rowH - barH) / 2
        local c = BAR.level
        dxDrawRectangle(bx, by, barW, barH, tocolor(c[1], c[2], c[3], 51))
        dxDrawRectangle(bx, by, barW * math.max(0, math.min(1, frac)), barH, tocolor(c[1], c[2], c[3], 255))
        for i = 1, 9 do dxDrawRectangle(bx + barW * i / 10 - 1, by, 2, barH, tocolor(0, 0, 0, 160)) end
    end
end


----------------------------------------------------------------
-- Velocimetro y bencina
----------------------------------------------------------------
local SPEEDO_MAX = 240   -- km/h al final de la escala

-- Arco grueso de a.. b grados (0 = derecha, sentido horario)
local function drawArc(cx, cy, r, a, b, width, color)
    local step = 4
    local px, py = cx + math.cos(math.rad(a)) * r, cy + math.sin(math.rad(a)) * r
    local ang = a
    while ang < b do
        ang = math.min(b, ang + step)
        local x, y = cx + math.cos(math.rad(ang)) * r, cy + math.sin(math.rad(ang)) * r
        dxDrawLine(px, py, x, y, color, width)
        px, py = x, y
    end
end

local function drawSpeedometer()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle then return end
    local R = 92 * s
    local cx, cy = screenW - MARGIN - R, screenH - MARGIN - R
    local vx, vy, vz = getElementVelocity(vehicle)
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
    local frac = math.min(1, speed / SPEEDO_MAX)

    dxDrawCircle(cx, cy, R, 0, 360, COLORS.panel, COLORS.panel, 48)
    -- Escala: de 135 grados (abajo a la izquierda) a 405 (abajo a la derecha)
    local A0, SPAN = 135, 270
    drawArc(cx, cy, R * 0.82, A0, A0 + SPAN, 7 * s, tocolor(255, 255, 255, 28))
    if frac > 0.004 then
        local hot = frac > 0.75
        drawArc(cx, cy, R * 0.82, A0, A0 + SPAN * frac, 7 * s, hot and tocolor(229, 72, 77, 240) or COLORS.accent)
    end
    for kmh = 0, SPEEDO_MAX, 20 do
        local ang = math.rad(A0 + SPAN * kmh / SPEEDO_MAX)
        local major = kmh % 40 == 0
        local r1, r2 = R * (major and 0.66 or 0.70), R * 0.74
        dxDrawLine(cx + math.cos(ang) * r1, cy + math.sin(ang) * r1, cx + math.cos(ang) * r2, cy + math.sin(ang) * r2,
            tocolor(255, 255, 255, major and 170 or 80), major and 2 or 1)
        if major then
            local tx, ty = cx + math.cos(ang) * R * 0.55, cy + math.sin(ang) * R * 0.55
            dxDrawText(tostring(kmh), tx, ty, tx, ty, COLORS.muted, 0.75 * s, "default", "center", "center")
        end
    end

    dxDrawText(("%d"):format(math.floor(speed + 0.5)), cx, cy - 18 * s, cx, cy - 18 * s, COLORS.text, 2.4 * s, "default-bold", "center", "center")
    dxDrawText("km/h", cx, cy + 6 * s, cx, cy + 6 * s, COLORS.muted, 0.85 * s, "default", "center", "center")

    -- Indicadores: freno de mano y motor
    local engineOn = getVehicleEngineState(vehicle)
    dxDrawText("MOTOR", cx - 26 * s, cy + 24 * s, cx - 26 * s, cy + 24 * s,
        engineOn and COLORS.money or tocolor(255, 255, 255, 70), 0.75 * s, "default-bold", "center", "center")
    dxDrawText("P", cx + 26 * s, cy + 24 * s, cx + 26 * s, cy + 24 * s,
        getElementData(vehicle, "rp:handbrake") and tocolor(229, 72, 77, 255) or tocolor(255, 255, 255, 70), 1.0 * s, "default-bold", "center", "center")

    -- Bencina
    local fuel, max = tonumber(getElementData(vehicle, "rp:fuel")), tonumber(getElementData(vehicle, "rp:fuelMax"))
    if fuel and max and max > 0 then
        local f = math.max(0, math.min(1, fuel / max))
        local low = f <= 0.15
        local refueling = getElementData(vehicle, "rp:refueling")
        local pulse = (low or refueling) and (math.sin(getTickCount() / 160) * 0.35 + 0.65) or 1
        local bw, bh = R * 1.05, 7 * s
        local bx, by = cx - bw / 2, cy + 44 * s
        dxDrawRectangle(bx, by, bw, bh, tocolor(255, 255, 255, 30))
        local r, g, b = 255, 200, 40
        if low then r, g, b = 229, 72, 77 end
        if refueling then r, g, b = 76, 211, 138 end
        dxDrawRectangle(bx, by, bw * f, bh, tocolor(r, g, b, 255 * pulse))
        for i = 1, 3 do dxDrawRectangle(bx + bw * i / 4, by, 1, bh, tocolor(0, 0, 0, 120)) end
        local label = refueling and ("CARGANDO  %.1f L"):format(fuel) or ("BENCINA  %d / %d L"):format(math.floor(fuel + 0.5), max)
        dxDrawText(label, cx, by + bh + 9 * s, cx, by + bh + 9 * s, low and tocolor(255, 140, 140) or COLORS.muted, 0.75 * s, "default-bold", "center", "center")
    end
end

----------------------------------------------------------------
addEventHandler("onClientRender", root, function()
    if not isActive() then return end
    local stripY = screenH - MARGIN - STRIP_H + 3 * s
    local mapX, mapY = MARGIN, screenH - MARGIN - MS - STRIP_H
    if prefs.map then drawMinimap(mapX, mapY) end
    drawBars(mapX, stripY, MS)
    local needsTop = drawNeeds(mapX + MS + 12 * s, screenH - MARGIN)
    drawStatusText(mapX + MS + 12 * s, needsTop)
    drawTopRight()
    if prefs.speedo then drawSpeedometer() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    mapTexture = dxCreateTexture("images/map.png", "dxt1", true, "wrap")
    renderTarget = dxCreateRenderTarget(MS, MS, false)
    if not mapTexture or not renderTarget then
        outputDebugString("[rp_hud] No se pudo crear la textura del minimapa", 2)
    end
    local f = xmlLoadFile(PREFS_FILE)
    if f then
        for k in pairs(prefs) do
            local v = xmlNodeGetAttribute(f, k)
            if v then prefs[k] = v == "1" end
        end
        xmlUnloadFile(f)
    end
    refreshNeeds()
    refreshWorld()
    hideGtaHud()
end)

-- Si el render target se pierde (al minimizar), se recrea
addEventHandler("onClientRestore", root, function(cleared)
    if cleared and isElement(renderTarget) then destroyElement(renderTarget) end
    if cleared then renderTarget = dxCreateRenderTarget(MS, MS, false) end
end)

addEventHandler("onClientPlayerSpawn", localPlayer, hideGtaHud)
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "rp:characterId" then hideGtaHud() end
    if key == "rp:needs" then refreshNeeds() end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if source == root and key == "rp:world" then refreshWorld() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    setPlayerHudComponentVisible("all", true)
end)

local function savePrefs()
    local f = xmlCreateFile(PREFS_FILE, "hud")
    if not f then return end
    for k, v in pairs(prefs) do xmlNodeSetAttribute(f, k, v and "1" or "0") end
    xmlSaveFile(f)
    xmlUnloadFile(f)
end

-- /hud                 oculta o muestra todo (tecla F7)
-- /hud necesidades     panel de vida y necesidades
-- /hud mapa            minimapa
-- /hud velocimetro     velocimetro (en vehiculo)
local ALIASES = { necesidades = "needs", needs = "needs", mapa = "map", map = "map", velocimetro = "speedo", speedo = "speedo" }
addCommandHandler("hud", function(_, what)
    local key = what and ALIASES[what:lower()]
    if not key then
        enabled = not enabled
        exports.rp_notify:notify(enabled and "HUD visible. Opciones: /hud necesidades | mapa | velocimetro" or "HUD oculto (/hud o F7 para mostrarlo).", "info")
        return
    end
    prefs[key] = not prefs[key]
    savePrefs()
    exports.rp_notify:notify(("%s: %s"):format(what:lower(), prefs[key] and "visible" or "oculto"), "info")
end)
bindKey("F7", "down", function() executeCommandHandler("hud") end)
