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
local s = math.max(0.75, math.min(1.3, screenH / 900))

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
}


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
}
local needValues = { hunger = 100, thirst = 100, energy = 100 }
local needShown = { hunger = 100, thirst = 100, energy = 100 }   -- valor suavizado para animar
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
for _, name in ipairs({ "heart", "shield", "food", "drop", "bolt" }) do
    ICONS[name] = dxCreateTexture("images/icons/" .. name .. ".png", "argb", true, "clamp")
end

local function drawBars(x, bottom)
    if not prefs.needs then return end
    local now = getTickCount()
    for k, v in pairs(needValues) do needShown[k] = needShown[k] + (v - needShown[k]) * 0.15 end

    local armor = getPedArmor(localPlayer)
    local rows = {
        { icon = "heart", value = getElementHealth(localPlayer), r = 229, g = 72, b = 77, always = true },
    }
    if armor > 0 then rows[#rows + 1] = { icon = "shield", value = armor, r = 200, g = 205, b = 215, always = true, noAlert = true } end
    for _, need in ipairs(hasNeeds and NEEDS or {}) do
        rows[#rows + 1] = { icon = need.icon, value = needValues[need.key], shown = needShown[need.key], r = need.r, g = need.g, b = need.b }
    end

    local w, pad, rowH = 210 * s, 9 * s, 31 * s
    local iconS = 26 * s
    local extraH = (#statusLines + (worldLabel and 1 or 0)) * 17 * s
    local h = pad * 2 + #rows * rowH + extraH
    local y = bottom - h
    dxDrawRectangle(x, y, w, h, COLORS.panel)
    dxDrawRectangle(x, y, 2, h, COLORS.accent)

    for i, row in ipairs(rows) do
        local ry = y + pad + (i - 1) * rowH
        local v = math.max(0, math.min(100, row.shown or row.value))
        local real = row.value
        local r, g, b, a = row.r, row.g, row.b, 255
        if not row.noAlert then
            local critical = real <= (row.always and 25 or 20)
            local low = real <= (row.always and 40 or 35)
            if critical then
                r, g, b = 229, 72, 77
                a = 150 + (math.sin(now / 170) * 0.5 + 0.5) * 105
            elseif not row.always and not low then
                a = 150      -- todo bien: se atenua
            end
        end
        local col = tocolor(r, g, b, a)
        local icon = ICONS[row.icon]
        if icon then dxDrawImage(x + pad + 2, ry + (rowH - iconS) / 2, iconS, iconS, icon, 0, 0, 0, col) end
        local bx = x + pad + iconS + 10 * s
        local bw, bh = w - pad * 2 - iconS - 10 * s - 40 * s, 10 * s
        local by = ry + rowH / 2 - bh / 2
        dxDrawRectangle(bx, by, bw, bh, tocolor(255, 255, 255, 30))
        dxDrawRectangle(bx, by, bw * v / 100, bh, col)
        dxDrawText(tostring(math.floor(real + 0.5)), bx + bw, ry, x + w - pad, ry + rowH,
            tocolor(255, 255, 255, a < 255 and math.max(a, 190) or 255), 1.1 * s, "default-bold", "right", "center")
    end

    local ly = y + pad + #rows * rowH
    for _, line in ipairs(statusLines) do
        dxDrawText(line[1], x + pad, ly, x + w - pad, ly + 17 * s, tocolor(line[2], line[3], line[4], 240), 0.85 * s, "default-bold", "left", "center", true)
        ly = ly + 17 * s
    end
    if worldLabel then
        dxDrawText("Clima: " .. worldLabel, x + pad, ly, x + w - pad, ly + 17 * s, COLORS.muted, 0.85 * s, "default", "left", "center", true)
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

local function drawTopRight()
    local hour, minute = getTime()
    local clock = ("%02d:%02d"):format(hour, minute)
    local right, top = screenW - MARGIN, MARGIN

    dxDrawText(clock, 0, top, right + 2, 0, tocolor(0, 0, 0, 160), 2.2 * s, "default-bold", "right", "top")
    dxDrawText(clock, 0, top, right, 0, COLORS.text, 2.2 * s, "default-bold", "right", "top")

    local money = formatMoney(getPlayerMoney(localPlayer))
    local my = top + dxGetFontHeight(2.2 * s, "default-bold") + 2 * s
    dxDrawText(money, 0, my + 1, right + 1, 0, tocolor(0, 0, 0, 160), 1.5 * s, "default-bold", "right", "top")
    dxDrawText(money, 0, my, right, 0, COLORS.money, 1.5 * s, "default-bold", "right", "top")

    local weapon = getPedWeapon(localPlayer)
    if weapon and weapon ~= 0 then
        local ay = my + dxGetFontHeight(1.5 * s, "default-bold") + 4 * s
        local ammo = ("%s  %d / %d"):format(getWeaponNameFromID(weapon) or "Arma", getPedAmmoInClip(localPlayer), getPedTotalAmmo(localPlayer) - getPedAmmoInClip(localPlayer))
        dxDrawText(ammo, 0, ay, right, 0, COLORS.text, 1.0 * s, "default-bold", "right", "top")
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
    local mapX, mapY = MARGIN, screenH - MARGIN - MS
    if prefs.map then drawMinimap(mapX, mapY) end
    drawBars(mapX + MS + 12 * s, screenH - MARGIN)
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
