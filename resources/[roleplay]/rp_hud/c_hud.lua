--[[
    rp_hud / c_hud.lua
    HUD propio que sustituye al de GTA:
      - Minimapa giratorio (abajo a la izquierda) con el mapa del radar de GTA SA
        extraido de la instalacion del jugador (images/map.png), blips y flecha.
        El destino de navegacion late; al cambiar de zona aparece su nombre en grande.
      - Vida y chaleco con estela de dano y destello al curarse.
      - Necesidades (hambre, sed, energia, estamina, cordura) en anillos: al subir
        rebotan y muestran "+N", al bajar a rojo laten, suenan y dicen que hacer.
        Estamina y cordura solo aparecen cuando no estan llenas.
      - Hora, dinero y banco con contador que rueda y "+$N" flotante con sonido,
        municion, estrellas (c_wanted.lua) y nivel (arriba a la derecha).
      - Velocimetro y bencina (abajo a la derecha) cuando vas en un vehiculo
        (litros en el elementData "rp:fuel" / "rp:fuelMax" que pone rp_vehicles),
        con la tecla J dibujada si el motor esta apagado.
      - Vineta roja con latido si la vida esta baja (c_fx.lua).
    /hud (o F7) oculta o muestra el HUD; /hud necesidades|mapa|velocimetro|sonidos lo configura;
    /hud tutorial (o /tutorial) repite la explicacion del HUD (c_tutorial.lua).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.9, math.min(1.3, screenH / 900))   -- minimo 0.9: en ventanas pequenas el texto era ilegible

local MAP_SIZE = 1536          -- px del archivo map.png
local WORLD = 6000             -- unidades que cubre el mapa (-3000 a 3000)
local MS = math.floor(220 * s) -- tamano del minimapa en pantalla
local MARGIN = math.floor(22 * s)

local mapTexture, renderTarget
local navRoute   -- ruta del GPS de rp_map: { x1, y1, x2, y2, ... } o nil

-- Iconos de blips dibujados para el gamemode (images/blips/<id de icono>.png)
-- 17 = tienda/robo, 22 = emergencias, 36 = autoescuela, 52 = tienda,
-- 54 = arriendo de bicicletas, 56 = trabajos/agencia, 63 = policia,
-- 10 / 14 / 29 = Burger Shot / Cluckin Bell / pizzeria (rp_restaurants).
local BLIP_ICON_IDS = { 10, 14, 17, 22, 27, 29, 36, 41, 45, 51, 52, 54, 55, 56, 63 }
local KNOWN_BLIP_ICON_IDS = {
    [0] = true,
    [10] = true,
    [14] = true,
    [29] = true,
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
local prefs = Hud.prefs        -- compartidas con c_fx / c_tutorial
local PREFS_FILE = "@hud_prefs.xml"

local KEYS = {}
for _, k in ipairs({ "keyboard_j" }) do KEYS[k] = dxCreateTexture("images/keys/" .. k .. ".png", "argb", true, "clamp") end

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

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end

-- Texto con contorno negro (como los numeros de dinero del juego)
local function outlineText(text, x1, y1, x2, y2, color, scale, font, ax, ay, alpha)
    local black = tocolor(0, 0, 0, alpha or 255)
    for _, o in ipairs(OFFS) do
        dxDrawText(text, x1 + o[1] * OUT, y1 + o[2] * OUT, x2 + o[1] * OUT, y2 + o[2] * OUT, black, scale, font, ax, ay, false, false, false)
    end
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, ax, ay, false, false, false)
end

local function shadowText(text, x1, y1, x2, y2, color, scale, font, ax, ay, alpha)
    dxDrawText(text, x1 + 1, y1 + 1, x2 + 1, y2 + 1, tocolor(0, 0, 0, alpha or 200), scale, font, ax, ay, true)
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

local hiddenBy = {}   -- [motivo] = true: otros recursos que piden ocultar SOLO este HUD (setHudHidden)

local function isActive()
    return enabled and next(hiddenBy) == nil and getElementData(localPlayer, "rp:characterId") and not isPlayerMapVisible()
        and not getElementData(localPlayer, "rp:hudHidden")   -- p. ej. al tomar una foto con el telefono
end
Hud.isActive = isActive

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

-- La lista de blips se refresca una vez por segundo, no en cada frame
local blipCache, blipCacheAt = {}, 0
local function getBlips()
    local now = getTickCount()
    if now - blipCacheAt > 1000 then
        blipCache, blipCacheAt = getElementsByType("blip"), now
    end
    return blipCache
end

-- Nombre de la zona: al cambiar (y quedarse ahi un momento) se anuncia en grande
local zone = { name = nil, pending = nil, pendingAt = 0, shownAt = 0, prev = nil, changedAt = 0 }
local ZONE_STABLE_MS, ZONE_BANNER_MS = 1200, 3200

local function updateZone(name, now)
    if name == zone.name then zone.pending = nil; return end
    if zone.name == nil then zone.name = name; return end   -- primera vez (al aparecer): sin anuncio
    if zone.pending ~= name then zone.pending, zone.pendingAt = name, now; return end
    if now - zone.pendingAt >= ZONE_STABLE_MS then
        zone.prev, zone.name, zone.pending = zone.name, name, nil
        zone.changedAt = now
        -- entrar o salir de una tienda no se anuncia en grande, solo cambiar de barrio
        if name ~= "Interior" and zone.prev ~= "Interior" then zone.shownAt = now end
    end
end

local function drawZoneBanner(now)
    local t = now - zone.shownAt
    if zone.shownAt == 0 or t > ZONE_BANNER_MS then return end
    local a = t < 350 and t / 350 or (t > ZONE_BANNER_MS - 700 and (ZONE_BANNER_MS - t) / 700 or 1)
    local inVeh = getPedOccupiedVehicle(localPlayer) and prefs.speedo
    local bottom = inVeh and (screenH - MARGIN - 2 * 92 * s - 18 * s) or (screenH - MARGIN - 8 * s)
    local slide = (1 - easeOut(t / 450)) * 30 * s
    local right = screenW - MARGIN + slide
    local sc = 1.25 * s
    local h = dxGetFontHeight(sc, "bankgothic")
    outlineText(zone.name, 0, bottom - h, right, bottom, tocolor(255, 255, 255, 255 * a), sc, "bankgothic", "right", "bottom", 255 * a)
    local w = dxGetTextWidth(zone.name, sc, "bankgothic") * easeOut(t / 600)
    dxDrawRectangle(right - w, bottom + 2 * s, w, 3 * s, tocolor(245, 165, 36, 230 * a))
end

local function drawMinimap(x, y, now)
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
    local pulse = (now % 1400) / 1400   -- latido del destino de navegacion

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

        -- Ruta del GPS (rp_map: setNavRoute), por las calles hasta el destino
        if navRoute then
            local reach = unitsAcross
            local lw, col = math.max(3, 5 * s), tocolor(197, 92, 255, 235)
            local prevX, prevY, prevSx, prevSy
            for i = 1, #navRoute - 1, 2 do
                local wx, wy = navRoute[i], navRoute[i + 1]
                local dx, dy = rotate((wx - px) * unitPx, -(wy - py) * unitPx, -heading)
                local sx, sy = MS / 2 + dx, MS / 2 + dy
                if prevX and (math.abs(wx - px) < reach or math.abs(prevX - px) < reach)
                    and (math.abs(wy - py) < reach or math.abs(prevY - py) < reach) then
                    dxDrawLine(prevSx, prevSy, sx, sy, col, lw)
                end
                prevX, prevY, prevSx, prevSy = wx, wy, sx, sy
            end
        end

        -- Blips (tiendas, etc.): icono propio si existe images/blips/<icono>.png,
        -- si no un cuadrado del color del blip. Solo dentro de su distancia visible.
        local dim = getElementDimension(localPlayer)
        for _, blip in ipairs(getBlips()) do
            if isElement(blip) and getElementDimension(blip) == dim then
                local bx, by = getElementPosition(blip)
                local worldDist = getDistanceBetweenPoints2D(px, py, bx, by)
                local iconId = getBlipIcon(blip)
                -- Solo se muestran blips conocidos. Los puntos normales (0) esperan
                -- a estar cerca; 41 pertenece a la navegacion activa y siempre es visible.
                local known = KNOWN_BLIP_ICON_IDS[iconId]
                -- elementData "rp:radarEdge" = true: punto de objetivo (p. ej. misiones) que se fija al borde del radar y se ve siempre
                local always = iconId == 41 or getElementData(blip, "rp:radarEdge") == true
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
                        local bxs, bys = MS / 2 + dx, MS / 2 + dy
                        if always then
                            -- onda que se expande: "ve aqui"
                            local r, g, b = getBlipColor(blip)
                            if iconId == 41 then r, g, b = 245, 165, 36 end
                            dxDrawCircle(bxs, bys, (10 + 16 * pulse) * s, 0, 360, tocolor(r, g, b, 150 * (1 - pulse)), tocolor(r, g, b, 0), 24)
                        end
                        local icon = blipIcons[iconId]
                        if icon then
                            local is = 26 * s
                            dxDrawImage(bxs - is / 2, bys - is / 2, is, is, icon)
                        else
                            local r, g, b = getBlipColor(blip)
                            local bs = 11 * s
                            dxDrawRectangle(bxs - bs / 2 - 1, bys - bs / 2 - 1, bs + 2, bs + 2, tocolor(0, 0, 0, 200))
                            dxDrawRectangle(bxs - bs / 2, bys - bs / 2, bs, bs, tocolor(r, g, b, 255))
                        end
                    end
                end
            end
        end

        -- Norte
        local nx, ny = rotate(0, -(MS / 2 - 12 * s), -heading)
        dxDrawText("N", MS / 2 + nx - 10, MS / 2 + ny - 10, MS / 2 + nx + 10, MS / 2 + ny + 10, tocolor(255, 255, 255, 230), 1.0 * s, "default-bold", "center", "center")
    end

    -- Flecha del jugador (con un halo suave para encontrarla de un vistazo)
    local _, _, rz = getElementRotation(vehicle or localPlayer)
    -- GTA: rz=0 norte y crece en sentido antihorario -> rumbo horario = -rz
    local angle = -rz - heading
    local c, cx, cy = tocolor(245, 165, 36, 255), MS / 2, MS / 2
    dxDrawCircle(cx, cy, 15 * s, 0, 360, tocolor(245, 165, 36, 55), tocolor(245, 165, 36, 0), 24)
    local tip = { rotate(0, -11 * s, angle) }
    local left = { rotate(-7 * s, 8 * s, angle) }
    local right = { rotate(7 * s, 8 * s, angle) }
    local back = { rotate(0, 4 * s, angle) }
    dxDrawPrimitive("trianglelist", false,
        { cx + tip[1], cy + tip[2], c }, { cx + left[1], cy + left[2], c }, { cx + back[1], cy + back[2], c },
        { cx + tip[1], cy + tip[2], c }, { cx + back[1], cy + back[2], c }, { cx + right[1], cy + right[2], c })
    dxSetRenderTarget()

    -- Marco + mapa
    dxDrawRectangle(x - 3, y - 3, MS + 6, MS + 6, COLORS.panel)
    dxDrawImage(x, y, MS, MS, renderTarget)
    dxDrawRectangle(x, y, MS, 2, COLORS.accent)
    Hud.setRect("map", x - 3, y - 26 * s, MS + 6, MS + 26 * s + 3)

    -- Zona (el nombre nuevo entra con un fundido)
    local zoneName = interior and "Interior" or getZoneName(px, py, pz)
    updateZone(zoneName, now)
    dxDrawRectangle(x - 3, y - 26 * s, MS + 6, 22 * s, COLORS.panel)
    local k = easeOut((now - zone.changedAt) / 500)
    if zone.prev and k < 1 then
        dxDrawText(zone.prev, x, y - 26 * s - 8 * s * k, x + MS, y - 4 * s - 8 * s * k, tocolor(242, 244, 248, 255 * (1 - k)), 1.0 * s, "default-bold", "center", "center", true)
    end
    dxDrawText(zone.name or zoneName, x, y - 26 * s + 8 * s * (1 - k), x + MS, y - 4 * s + 8 * s * (1 - k),
        tocolor(242, 244, 248, 255 * k), 1.0 * s, "default-bold", "center", "center", true)
end

----------------------------------------------------------------
-- Estado: vida / chaleco + necesidades compactas + avisos
-- Las necesidades se leen solo cuando cambia el elementData "rp:needs"
-- (cada minuto), no en cada frame; el resto se dibuja con rectangulos.
----------------------------------------------------------------
-- hint: lo que se le dice al jugador cuando esa necesidad esta baja (una linea, en imperativo)
local NEEDS = {
    { key = "hunger", name = "Hambre",  icon = "food",  r = 245, g = 165, b = 36,  hint = "Come algo: restaurante, tienda 24/7 o expendedora" },
    { key = "thirst", name = "Sed",     icon = "drop",  r = 70,  g = 150, b = 255, hint = "Bebe algo: expendedora o tienda 24/7" },
    { key = "energy", name = "Energia", icon = "bolt",  r = 168, g = 120, b = 255, hint = "Descansa: /dormir en un interior o toma un cafe" },
    { key = "stamina", name = "Aliento", icon = "run",  r = 63,  g = 191, b = 106, hint = "Camina un poco para recuperar el aliento" },   -- solo cliente, no se guarda
    { key = "sanity", name = "Cordura", icon = "heart", r = 224, g = 98,  b = 190, hint = "Evita la violencia: se recupera sola con calma" },   -- baja al matar civiles (rp_needs)
}
Hud.NEEDS = NEEDS
local needValues = { hunger = 100, thirst = 100, energy = 100, stamina = 100, sanity = 100 }
local needShown = { hunger = 100, thirst = 100, energy = 100, stamina = 100, sanity = 100 }   -- valor suavizado para animar
Hud.needValues = needValues
local needFx = {}      -- [key] = { pop = tick, label = tick hasta el que se ve el nombre, slot = posicion animada, alpha }
for _, n in ipairs(NEEDS) do needFx[n.key] = { pop = 0, label = 0, alpha = (n.key == "stamina" or n.key == "sanity") and 0 or 1 } end
local staminaFullAt = 0

-- Estamina: baja corriendo (sprint), sube trotando/caminando/quieto. Al agotarse
-- se bloquea el sprint hasta recuperar STAMINA_RESUME.
local STAMINA_DRAIN, STAMINA_REGEN, STAMINA_RESUME = 8, 5, 20   -- puntos/segundo, puntos/segundo, %
local staminaTick = getTickCount()
local staminaLocked = false
local STAMINA_JUMP_COST = 8   -- puntos por salto
local jumpPressed = false

-- Carga de la mochila en kg (rp_backpacks la publica). 30 kg = -24 % de velocidad y +90 % de gasto al correr.
local function packKg() return tonumber(getElementData(localPlayer, "rp:packWeight")) or 0 end
local function packSlowdown() return math.max(0.7, 1 - packKg() * 0.008) end
local function packDrainFactor() return 1 + packKg() * 0.03 end

-- Tecla de salto (bindKey respeta el rebind del jugador). Solo cuenta si realmente despega.
bindKey("jump", "down", function()
    if staminaLocked or isPedInVehicle(localPlayer) or not isPedOnGround(localPlayer) then return end
    jumpPressed = true
end)

local function updateStamina()
    local now = getTickCount()
    local dt = math.min((now - staminaTick) / 1000, 0.5)
    staminaTick = now
    local st = needValues.stamina
    local meth = getElementData(localPlayer, "rp:meth") == true
    local state = getPedMoveState(localPlayer)
    local jumping = state == "jump"
    if jumpPressed then
        jumpPressed = false
        if not meth then st = st - STAMINA_JUMP_COST end   -- saltar gasta estamina (una vez por salto)
    end
    if not meth and not isPedInVehicle(localPlayer) and state == "sprint" then
        st = st - STAMINA_DRAIN * packDrainFactor() * dt
    elseif not jumping then
        st = st + STAMINA_REGEN * dt
    end
    st = math.max(0, math.min(100, st))
    needValues.stamina = st
    if st <= 0 and not staminaLocked then
        staminaLocked = true
        toggleControl("sprint", false)
        toggleControl("jump", false)   -- sin estamina no se salta
        needFx.stamina.pop = now
        Hud.sound("critical", 4000)
    elseif staminaLocked and (st >= STAMINA_RESUME or meth) and needValues.energy > 0 then   -- energia 0 la bloquea rp_needs
        staminaLocked = false
        toggleControl("sprint", true)
        toggleControl("jump", true)
    end
    Hud.staminaLocked = staminaLocked
end

-- Metanfetamina: correr mas rapido acelerando las animaciones de trote/sprint.
local METH_SPEED = 1.5
local RUN_ANIMS = { "run_player", "run_civi", "run_fat", "run_old", "run_gang1", "run_wuzi",
                    "sprint_civi", "sprint_panic", "swat_run", "woman_run", "woman_runfast", "woman_runpanic" }
-- Mochila (rp_backpacks): el peso que lleva a la espalda frena trote y caminata.
local WALK_ANIMS = { "walk_player", "walk_civi", "walk_fat", "walk_old", "walk_gang1", "walk_gang2", "walk_wuzi", "woman_walknorm" }
local lastRunSpeed, lastWalkSpeed = 1, 1
addEventHandler("onClientPreRender", root, function()
    local meth = getElementData(localPlayer, "rp:meth") == true
    local slow = packSlowdown()
    local run = (meth and METH_SPEED or 1) * slow
    if run ~= 1 or lastRunSpeed ~= 1 then
        for i = 1, #RUN_ANIMS do setPedAnimationSpeed(localPlayer, RUN_ANIMS[i], run) end
        lastRunSpeed = run
    end
    if slow ~= 1 or lastWalkSpeed ~= 1 then
        for i = 1, #WALK_ANIMS do setPedAnimationSpeed(localPlayer, WALK_ANIMS[i], slow) end
        lastWalkSpeed = slow
    end
end)
local statusLines = {}
local hasNeeds = false   -- false hasta recibir "rp:needs" (no mostrar 100 falsos)
local worldLabel = nil
local starving = false

local needCenters = {}   -- [key] = { x, y } centro del icono en pantalla (para los "+N")

local function refreshNeeds()
    local n = getElementData(localPlayer, "rp:needs")
    local lines = {}
    local hadNeeds = hasNeeds
    hasNeeds = type(n) == "table"
    starving = false
    if type(n) == "table" then
        local now = getTickCount()
        for _, need in ipairs(NEEDS) do
            local old = needValues[need.key]
            local new = tonumber(n[need.key])
            if new then
                needValues[need.key] = new
                if hadNeeds then
                    local fx = needFx[need.key]
                    if new - old >= 3 then
                        -- comio, bebio o durmio: rebote, "+N" y sonido de recompensa
                        fx.pop, fx.label = now, now + 3500
                        local c = needCenters[need.key]
                        if c then Hud.float(("+%d"):format(math.floor(new - old + 0.5)), c[1], c[2] - 30 * s, 120, 255, 116, 1.1 * s) end
                        Hud.sound("recover", 1200)
                    elseif (old >= 35 and new < 35) or (old >= 20 and new < 20) then
                        -- entra en ambar o en rojo: se nombra y avisa
                        fx.pop, fx.label = now, now + 6000
                        if new < 20 then Hud.sound("critical", 3000) end
                    end
                else
                    needShown[need.key] = new   -- primera lectura: sin animar desde 100
                end
            end
        end
        if (n.hunger or 100) <= 0 or (n.thirst or 100) <= 0 then
            starving = true
            lines[#lines + 1] = { "Sin comida o bebida: pierdes vida", 229, 72, 77 }
        end
        if (n.energy or 100) <= 0 then lines[#lines + 1] = { "Agotado: no puedes correr (/dormir)", 168, 120, 255 } end
        if (n.sanity or 100) <= 25 then lines[#lines + 1] = { "Tu cordura esta al limite", 224, 98, 190 } end
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
Hud.ICONS = ICONS

-- Vida y chaleco bajo el minimapa (barras de 138x9 del kit, escaladas al ancho del mapa).
-- Al recibir dano queda una estela clara que se encoge despues (se ve cuanto perdiste);
-- al curarte la barra destella en verde y sale "+N".
local healthGhost, lastHealth = 100, nil
local healthGhostHold = 0
local function drawBars(x, y, w, now)
    if not prefs.needs then return end
    local gap = math.floor(4 * s)
    local h = math.floor(10 * s)
    local health, armor = getElementHealth(localPlayer), getPedArmor(localPlayer)
    if lastHealth then
        if health < lastHealth - 0.5 then
            healthGhostHold = now + 450
            healthGhost = math.max(healthGhost, lastHealth)
        elseif health > lastHealth + 4 and lastHealth > 1 then   -- al reaparecer no cuenta como curarse
            Hud.onHeal()
            Hud.float(("+%d"):format(math.floor(health - lastHealth + 0.5)), x + w * 0.3, y - 6 * s, 120, 255, 116, 1.0 * s)
        end
    end
    lastHealth = health
    if now > healthGhostHold then healthGhost = healthGhost + (health - healthGhost) * 0.08 end
    if healthGhost < health then healthGhost = health end

    local wH = armor > 0 and math.floor((w - gap) * 0.62) or w
    local pulse = health <= 25 and (150 + (now % 600 < 300 and 105 or 0)) or 255

    dxDrawRectangle(x - 1, y - 1, wH + 2, h + 2, tocolor(0, 0, 0, 200))
    dxDrawRectangle(x, y, wH, h, tocolor(BAR.healthLost[1], BAR.healthLost[2], BAR.healthLost[3], 255))
    dxDrawRectangle(x, y, wH * clamp(healthGhost / 100, 0, 1), h, tocolor(255, 235, 200, 200))   -- estela del dano
    local hc = health <= 25 and BAR.urgent or BAR.health
    dxDrawRectangle(x, y, wH * clamp(health / 100, 0, 1), h, tocolor(hc[1], hc[2], hc[3], pulse))
    dxDrawRectangle(x, y, wH * clamp(health / 100, 0, 1), math.max(1, math.floor(h * 0.3)), tocolor(255, 255, 255, 40))   -- brillo
    Hud.setRect("health", x - 1, y - 1, wH + 2, h + 2)
    if armor > 0 then
        local ax, aw = x + wH + gap, w - wH - gap
        dxDrawRectangle(ax - 1, y - 1, aw + 2, h + 2, tocolor(0, 0, 0, 200))
        dxDrawRectangle(ax, y, aw, h, tocolor(BAR.armorLost[1], BAR.armorLost[2], BAR.armorLost[3], 255))
        dxDrawRectangle(ax, y, aw * math.min(1, armor / 100), h, tocolor(BAR.armor[1], BAR.armor[2], BAR.armor[3], 255))
        dxDrawRectangle(ax, y, aw * math.min(1, armor / 100), math.max(1, math.floor(h * 0.3)), tocolor(255, 255, 255, 40))
        Hud.setRect("armor", ax - 1, y - 1, aw + 2, h + 2)
    end
    Hud.setRect("bars", x - 1, y - 1, w + 2, h + 2)
end

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

-- Valor de demostracion del tutorial: baja hasta rojo y vuelve a llenarse (+ rebote)
local function demoValue(t)
    local cycle = t % 4200
    if cycle < 2400 then return 100 - 88 * easeOut(cycle / 2400) end
    if cycle < 3000 then return 12 end
    return 12 + 88 * easeOut((cycle - 3000) / 700)
end

-- Que necesidades se ven: hambre, sed y energia siempre; estamina mientras no este llena
-- (y 2,5 s despues); cordura solo si no esta al 100 %. El tutorial las muestra todas.
local function needWanted(key, now)
    if Hud.showAll then return true end
    if key == "stamina" then
        if needValues.stamina < 99.5 then staminaFullAt = now; return true end
        return now - staminaFullAt < 2500
    elseif key == "sanity" then
        return needValues.sanity < 99.5
    end
    return true
end

-- Necesidades: iconos con anillo que se vacia segun lo que te queda.
-- Cada necesidad tiene su color (NEEDS); ambar < 35, rojo parpadeante < 20.
-- Debajo, el porcentaje; al cambiar de estado se ve un momento su nombre.
local function drawNeeds(x, bottom, now)
    if not prefs.needs or not hasNeeds then return bottom end
    updateStamina()
    for k, v in pairs(needValues) do needShown[k] = needShown[k] + (v - needShown[k]) * 0.12 end
    local D = math.floor(50 * s)          -- diametro de cada icono
    local gap = math.floor(10 * s)
    local thick = math.max(4, math.floor(5 * s))
    local top = bottom - D - math.floor(14 * s)   -- deja sitio al porcentaje
    local demo = Hud.demo
    local slotIndex = 0
    local minX, maxX
    for _, need in ipairs(NEEDS) do
        local fx = needFx[need.key]
        local want = needWanted(need.key, now)
        fx.alpha = fx.alpha + ((want and 1 or 0) - fx.alpha) * 0.12
        if want then slotIndex = slotIndex + 1 end
        fx.slot = fx.slot and (fx.slot + ((want and slotIndex or fx.slot) - fx.slot) * 0.18) or math.max(1, slotIndex)
        if fx.alpha > 0.02 then
            local A = fx.alpha
            local real, shown = needValues[need.key], needShown[need.key]
            local isDemo = demo and demo.key == need.key
            if isDemo then
                shown = demoValue(now - demo.t0); real = shown
                if (now - demo.t0) % 4200 > 3000 and (now - demo.t0) % 4200 < 3060 then fx.pop = now end
            end
            local cx = x + D / 2 + (fx.slot - 1) * (D + gap)
            local cy = top + D / 2
            needCenters[need.key] = { cx, cy }
            local r, g, b = need.r, need.g, need.b
            local low = real < 20
            if need.key == "stamina" and getElementData(localPlayer, "rp:meth") == true and not isDemo then
                r, g, b, low = 255, 196, 40, false   -- dorado: la droga evita que se gaste
            elseif low then r, g, b = BAR.urgent[1], BAR.urgent[2], BAR.urgent[3]
            elseif real < 35 then r, g, b = BAR.normal[1], BAR.normal[2], BAR.normal[3] end
            local pulse = low and (math.sin(now / 170) * 0.5 + 0.5) or 0

            -- rebote al cambiar (escala) y temblor si esta en rojo
            local pk = (now - fx.pop) / 450
            local scale = (pk >= 0 and pk < 1) and (1 + 0.22 * math.sin(pk * math.pi) * (1 - pk)) or 1
            scale = scale * (0.85 + 0.15 * A)
            if low then cx = cx + math.sin(now / 35) * 1.2 * s * pulse end
            local R = D / 2 * scale

            -- resplandor suave cuando esta critico o acaba de subir
            if low then
                dxDrawCircle(cx, cy, R + 6 * s, 0, 360, tocolor(r, g, b, (40 + 70 * pulse) * A), tocolor(r, g, b, 0), 40)
            elseif pk >= 0 and pk < 1.5 then
                dxDrawCircle(cx, cy, R + 8 * s, 0, 360, tocolor(r, g, b, 120 * (1 - pk / 1.5) * A), tocolor(r, g, b, 0), 40)
            end
            -- sombra + fondo + cristal
            dxDrawCircle(cx, cy, R + 2, 0, 360, tocolor(0, 0, 0, 150 * A), tocolor(0, 0, 0, 150 * A), 48)
            dxDrawCircle(cx, cy, R, 0, 360, tocolor(14, 16, 24, 225 * A), tocolor(14, 16, 24, 225 * A), 48)
            -- pista (ring vacio) y progreso
            drawRing(cx, cy, R, thick, 1, tocolor(255, 255, 255, 30 * A))
            drawRing(cx, cy, R, thick, shown / 100, tocolor(r, g, b, math.floor((215 + 40 * pulse) * A)))
            -- disco interior ligeramente teñido con el color de la necesidad
            dxDrawCircle(cx, cy, R - thick - 1, 0, 360, tocolor(r, g, b, 38 * A), tocolor(r, g, b, 14 * A), 40)
            -- icono
            local isz = math.floor(D * 0.42 * scale)
            local tex = ICONS[need.icon]
            if tex then
                dxDrawImage(cx - isz / 2, cy - isz / 2, isz, isz, tex, 0, 0, 0, tocolor(255, 255, 255, 245 * A))
            end
            -- porcentaje, o el nombre cuando acaba de cambiar / esta en rojo / tutorial
            local showName = now < fx.label or isDemo or (low and (now % 4000) < 2000)
            local label = showName and need.name:upper() or ("%d%%"):format(math.floor(shown + 0.5))
            shadowText(label, cx - D / 2 - 6 * s, top + D + 1 * s, cx + D / 2 + 6 * s, top + D + 14 * s,
                low and tocolor(r, g, b, 255 * A) or tocolor(220, 224, 232, 230 * A), 0.75 * s, "default-bold", "center", "center", 200 * A)
            Hud.setRect("need_" .. need.key, cx - D / 2 - 4 * s, top - 4 * s, D + 8 * s, D + 20 * s)
            minX = math.min(minX or cx - D / 2, cx - D / 2)
            maxX = math.max(maxX or cx + D / 2, cx + D / 2)
        end
    end
    if minX then Hud.setRect("needs", minX - 6 * s, top - 6 * s, maxX - minX + 12 * s, D + 24 * s) end
    return top
end

-- Avisos de necesidades y clima, encima de los iconos. Cada aviso dice QUE HACER.
local function drawStatusText(x, bottom, now)
    if not prefs.needs then return end
    local lh = 18 * s
    local ly = bottom - lh
    if worldLabel then
        shadowText("Clima: " .. worldLabel, x + 12 * s, ly, x + 280 * s, ly + lh, tocolor(235, 238, 245), 0.9 * s, "default-bold", "left", "center")
        ly = ly - lh
    end
    local lines = {}
    for i = 1, #statusLines do lines[#lines + 1] = statusLines[i] end
    -- la necesidad mas urgente (en rojo) con su consejo
    local worst, worstV
    for _, need in ipairs(NEEDS) do
        local v = needValues[need.key]
        if hasNeeds and v < 20 and needWanted(need.key, now) and (not worstV or v < worstV) then worst, worstV = need, v end
    end
    if worst then lines[#lines + 1] = { worst.hint, 255, 214, 110, true } end
    for i = #lines, 1, -1 do
        local line = lines[i]
        local a = line[5] and (200 + 55 * math.sin(now / 250)) or 255
        shadowText(line[1], x + 12 * s, ly, x + 380 * s, ly + lh, tocolor(line[2], line[3], line[4], a), 0.9 * s, "default-bold", "left", "center")
        ly = ly - lh
    end
end

----------------------------------------------------------------
-- Hora, dinero y arma
----------------------------------------------------------------
local function formatMoney(n)
    local digits = tostring(math.floor(math.abs(n) + 0.5))
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-$" or "$") .. digits
end

local MONEY_FONT = "pricedown"
-- El contador rueda hasta el valor nuevo; la diferencia sale flotando con sonido
local money = { last = nil, shown = 0, pulse = 0 }
local bankM = { last = nil, shown = 0, pulse = 0 }

local function trackMoney(m, current, now, fx, x, y, color)
    if m.last == nil then
        m.last, m.shown = current, current
        return
    end
    if current ~= m.last and now < (money.quietUntil or 0) then
        -- recien cargado el personaje: el saldo llega ahora, no es un cobro
        m.last, m.shown = current, current
    elseif current ~= m.last then
        local d = current - m.last
        m.pulse = now
        Hud.float((d > 0 and "+" or "-") .. formatMoney(math.abs(d)), x, y, color[1], color[2], color[3], 0.95 * s, MONEY_FONT)
        if fx then Hud.sound(d > 0 and "earn" or "spend", 500) end
        m.last = current
    end
    local diff = current - m.shown
    if math.abs(diff) < 1 then m.shown = current else m.shown = m.shown + diff * 0.14 end
end

local function drawTopRight(now)
    local hour, minute = getTime()
    local clock = ("%02d:%02d"):format(hour, minute)
    local right, top = screenW - MARGIN, MARGIN

    local clockH = dxGetFontHeight(1.5 * s, "default-bold")
    outlineText(clock, 0, top, right, top + clockH, tocolor(255, 255, 255), 1.5 * s, "default-bold", "right", "top")

    -- Dinero (Rockstar Pricedown, #84e36c con contorno negro): rueda al cambiar y crece un instante
    local current = getPlayerMoney(localPlayer)
    local mScale = 1.35 * s
    local mH = dxGetFontHeight(mScale, MONEY_FONT)
    local my = top + clockH + 4 * s
    local up = current >= (money.last or current)
    trackMoney(money, current, now, true, right - 70 * s, my + mH * 0.5, up and MONEY_UP or MONEY_DOWN)
    local pk = (now - money.pulse) / 500
    local bump = (pk >= 0 and pk < 1) and (1 + 0.12 * math.sin(pk * math.pi)) or 1
    outlineText(formatMoney(money.shown), 0, my, right, my + mH, tocolor(MONEY_UP[1], MONEY_UP[2], MONEY_UP[3]), mScale * bump, MONEY_FONT, "right", "top")
    local mW = dxGetTextWidth(formatMoney(current), mScale, MONEY_FONT)
    Hud.setRect("money", right - mW - 8 * s, my - 2 * s, mW + 16 * s, mH + 4 * s)
    local nextY = my + mH + 2 * s

    -- Saldo del banco (elementData "rp:bankMoney" de rp_bank)
    local bank = tonumber(getElementData(localPlayer, "rp:bankMoney"))
    if bank then
        local bScale = 0.95 * s
        local bH = dxGetFontHeight(bScale, MONEY_FONT)
        trackMoney(bankM, bank, now, false, right - 60 * s, nextY + bH * 0.5, { 130, 190, 255 })
        local txt = formatMoney(bankM.shown)
        local tw = dxGetTextWidth(txt, bScale, MONEY_FONT)
        outlineText(txt, 0, nextY, right, nextY + bH, tocolor(130, 190, 255), bScale, MONEY_FONT, "right", "top")
        outlineText("BANCO", 0, nextY, right - tw - 8 * s, nextY + bH, tocolor(190, 200, 215), 0.8 * s, "default-bold", "right", "center")
        local lw = dxGetTextWidth("BANCO", 0.8 * s, "default-bold")
        Hud.setRect("bank", right - tw - lw - 16 * s, nextY - 2 * s, tw + lw + 24 * s, bH + 4 * s)
        nextY = nextY + bH + 2 * s
    else
        bankM.last = nil
    end

    local weapon = getPedWeapon(localPlayer)
    if weapon and weapon ~= 0 then
        local clip = getPedAmmoInClip(localPlayer)
        local ammo = ("%s  %d / %d"):format(getWeaponNameFromID(weapon) or "Arma", clip, getPedTotalAmmo(localPlayer) - clip)
        local aH = dxGetFontHeight(1.05 * s, "default-bold")
        local lowAmmo = clip <= 3 and getPedTotalAmmo(localPlayer) > 0 and weapon >= 22
        outlineText(ammo, 0, nextY, right, nextY + aH, lowAmmo and tocolor(255, 140, 140) or tocolor(255, 255, 255), 1.05 * s, "default-bold", "right", "top")
        nextY = nextY + aH + 6 * s
    end

    -- Estrellas de busqueda (c_wanted.lua) van aqui
    Hud.starsY = nextY + 6 * s
    if (tonumber(getElementData(localPlayer, "rp:wanted")) or 0) > 0 then nextY = nextY + 40 * s end

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
        Hud.setRect("level", rx, nextY, rowW - MARGIN + 8 * s, rowH)
        nextY = nextY + rowH + 4 * s
    end
    Hud.setRect("clock", right - dxGetTextWidth(clock, 1.5 * s, "default-bold") - 8 * s, top - 2 * s, dxGetTextWidth(clock, 1.5 * s, "default-bold") + 16 * s, clockH + 4 * s)
    Hud.topRightBottom = nextY

    -- Borde izquierdo del bloque, para las fichas clicables (c_iconbar.lua):
    --   topRightLeft = hora, dinero y banco (fila de arriba); topRightLeftLow = tambien arma, estrellas y nivel
    local left = right - math.max(dxGetTextWidth(clock, 1.5 * s, "default-bold"), mW)
    local bankR = Hud.getRect("bank")
    if bank and bankR then left = math.min(left, bankR[1]) end
    local low = left
    if weapon and weapon ~= 0 then
        local clip = getPedAmmoInClip(localPlayer)
        local ammo = ("%s  %d / %d"):format(getWeaponNameFromID(weapon) or "Arma", clip, getPedTotalAmmo(localPlayer) - clip)
        low = math.min(low, right - dxGetTextWidth(ammo, 1.05 * s, "default-bold"))
    end
    if (tonumber(getElementData(localPlayer, "rp:wanted")) or 0) > 0 then low = math.min(low, right - 200 * s) end
    if level and frac then low = math.min(low, screenW - math.floor(260 * s)) end
    Hud.topRightLeft, Hud.topRightLeftLow = left, low
end


----------------------------------------------------------------
-- Velocimetro y bencina
----------------------------------------------------------------
local SPEEDO_MAX = 240   -- km/h al final de la escala
local speedShown = 0
local fuelWarned = {}    -- [vehiculo] = true: ya sono el aviso de poca bencina

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

local function drawSpeedometer(now)
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle then speedShown = 0; return end
    local R = 92 * s
    local cx, cy = screenW - MARGIN - R, screenH - MARGIN - R
    local vx, vy, vz = getElementVelocity(vehicle)
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
    speedShown = speedShown + (speed - speedShown) * 0.2
    local frac = math.min(1, speedShown / SPEEDO_MAX)

    dxDrawCircle(cx, cy, R, 0, 360, COLORS.panel, COLORS.panel, 48)
    -- Escala: de 135 grados (abajo a la izquierda) a 405 (abajo a la derecha)
    local A0, SPAN = 135, 270
    drawArc(cx, cy, R * 0.82, A0, A0 + SPAN, 7 * s, tocolor(255, 255, 255, 28))
    if frac > 0.004 then
        local hot = frac > 0.75
        if hot then drawArc(cx, cy, R * 0.82, A0, A0 + SPAN * frac, 14 * s, tocolor(229, 72, 77, 50 + 30 * math.sin(now / 90))) end
        drawArc(cx, cy, R * 0.82, A0, A0 + SPAN * frac, 7 * s, hot and tocolor(229, 72, 77, 240) or COLORS.accent)
        -- punta luminosa al final del arco
        local ea = math.rad(A0 + SPAN * frac)
        dxDrawCircle(cx + math.cos(ea) * R * 0.82, cy + math.sin(ea) * R * 0.82, 6 * s, 0, 360, tocolor(255, 255, 255, 220), tocolor(255, 255, 255, 0), 16)
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

    dxDrawText(("%d"):format(math.floor(speedShown + 0.5)), cx, cy - 18 * s, cx, cy - 18 * s, COLORS.text, 2.4 * s, "default-bold", "center", "center")
    dxDrawText("km/h", cx, cy + 6 * s, cx, cy + 6 * s, COLORS.muted, 0.85 * s, "default", "center", "center")

    -- Indicadores: motor y freno de mano. Con el motor apagado (y al volante) se dibuja la tecla J.
    local engineOn = getVehicleEngineState(vehicle)
    local driver = getVehicleController(vehicle) == localPlayer
    if not engineOn and driver and KEYS.keyboard_j then
        local blink = 170 + 85 * math.sin(now / 200)
        local ks = 20 * s
        dxDrawImage(cx - 26 * s - 24 * s - ks / 2, cy + 24 * s - ks / 2, ks, ks, KEYS.keyboard_j, 0, 0, 0, tocolor(255, 255, 255, blink))
        dxDrawText("MOTOR", cx - 26 * s, cy + 24 * s, cx - 26 * s, cy + 24 * s, tocolor(255, 200, 80, blink), 0.75 * s, "default-bold", "center", "center")
    else
        dxDrawText("MOTOR", cx - 26 * s, cy + 24 * s, cx - 26 * s, cy + 24 * s,
            engineOn and COLORS.money or tocolor(255, 255, 255, 70), 0.75 * s, "default-bold", "center", "center")
    end
    dxDrawText("P", cx + 26 * s, cy + 24 * s, cx + 26 * s, cy + 24 * s,
        getElementData(vehicle, "rp:handbrake") and tocolor(229, 72, 77, 255) or tocolor(255, 255, 255, 70), 1.0 * s, "default-bold", "center", "center")
    Hud.setRect("speedo", cx - R, cy - R, R * 2, R * 2)

    -- Bencina
    local fuel, max = tonumber(getElementData(vehicle, "rp:fuel")), tonumber(getElementData(vehicle, "rp:fuelMax"))
    if fuel and max and max > 0 then
        local f = math.max(0, math.min(1, fuel / max))
        local low = f <= 0.15
        local refueling = getElementData(vehicle, "rp:refueling")
        if low and driver and not fuelWarned[vehicle] then
            fuelWarned[vehicle] = true
            Hud.sound("critical", 3000)
            Hud.float("Poca bencina", cx, cy - R - 8 * s, 255, 140, 140, 1.0 * s)
        elseif f > 0.25 then
            fuelWarned[vehicle] = nil
        end
        local pulse = (low or refueling) and (math.sin(now / 160) * 0.35 + 0.65) or 1
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
    local now = getTickCount()
    Hud.drawVignette(getElementHealth(localPlayer), starving)
    local stripY = screenH - MARGIN - STRIP_H + 3 * s
    local mapX, mapY = MARGIN, screenH - MARGIN - MS - STRIP_H
    if prefs.map then drawMinimap(mapX, mapY, now) end
    drawBars(mapX, stripY, MS, now)
    local needsTop = drawNeeds(mapX + MS + 12 * s, screenH - MARGIN, now)
    drawStatusText(mapX + MS + 12 * s, needsTop, now)
    drawTopRight(now)
    if prefs.speedo then drawSpeedometer(now) end
    if Hud.drawIconBars then Hud.drawIconBars(now) end   -- iconos clicables (c_iconbar.lua)
    drawZoneBanner(now)
    Hud.drawFloats()
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
    if key == "rp:characterId" then
        hideGtaHud()
        -- otro personaje: el dinero y la vida no "ruedan" ni suenan desde los del anterior
        money.last, bankM.last, lastHealth = nil, nil, nil
        money.quietUntil = getTickCount() + 4000
        zone.name, zone.shownAt = nil, 0
    end
    if key == "rp:needs" then refreshNeeds() end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if source == root and key == "rp:world" then refreshWorld() end
end)
addEventHandler("onClientElementDestroy", root, function()
    if fuelWarned[source] then fuelWarned[source] = nil end
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
-- /hud sonidos         sonidos del HUD (dinero, necesidades, latido)
-- /hud tutorial        repite la explicacion del HUD
local ALIASES = {
    necesidades = "needs", needs = "needs", mapa = "map", map = "map", velocimetro = "speedo", speedo = "speedo",
    sonidos = "sounds", sonido = "sounds", sounds = "sounds",
}
local NAMES = { needs = "Necesidades", map = "Minimapa", speedo = "Velocimetro", sounds = "Sonidos del HUD" }
addCommandHandler("hud", function(_, what)
    local w = what and what:lower()
    if w == "tutorial" or w == "ayuda" then
        if Hud.startTutorial then Hud.startTutorial(true) end
        return
    end
    local key = w and ALIASES[w]
    if not key then
        enabled = not enabled
        exports.rp_notify:notify(enabled and "HUD visible. Opciones: /hud necesidades | mapa | velocimetro | sonidos | tutorial" or "HUD oculto (/hud o F7 para mostrarlo).", "info")
        return
    end
    prefs[key] = not prefs[key]
    savePrefs()
    exports.rp_notify:notify(("%s: %s"):format(NAMES[key], prefs[key] and "activado" or "desactivado"), "info")
end)
bindKey("F7", "down", function()
    if isChatBoxInputActive() or isConsoleActive() then return end
    executeCommandHandler("hud")
end)

----------------------------------------------------------------
-- API para otros recursos (cinematicas, misiones, minijuegos a pantalla completa)
--   exports.rp_hud:setHudSuppressed("mi_recurso:motivo", true)   oculta HUD propio, HUD nativo, chat y toasts
--   exports.rp_hud:setHudSuppressed("mi_recurso:motivo", false)  lo devuelve cuando ya no queda ningun motivo activo
-- Varios recursos pueden pedirlo a la vez: solo se muestra de nuevo al quitar el ultimo motivo.
----------------------------------------------------------------
local suppressed = {}

function setHudSuppressed(reason, on)
    suppressed[tostring(reason or "?")] = on and true or nil
    local hidden = next(suppressed) ~= nil
    setElementData(localPlayer, "rp:hudHidden", hidden, false)
    showChat(not hidden)
    pcall(function() exports.rp_notify:setNotificationsMuted(hidden) end)
    if hidden then
        setPlayerHudComponentVisible("all", false)
        setPlayerHudComponentVisible("crosshair", false)
    else
        hideGtaHud()
    end
    return true
end

function isHudSuppressed() return next(suppressed) ~= nil end

-- Ocultar SOLO el HUD de rp_hud (minimapa, necesidades, velocimetro...), como F7, sin tocar el chat,
-- los avisos ni rp:hudHidden. Para recursos con HUD propio a pantalla completa (p. ej. rp_pizzeria).
--   exports.rp_hud:setHudHidden("mi_recurso", true / false)
function setHudHidden(reason, on)
    hiddenBy[tostring(reason or "?")] = on and true or nil
    return true
end

-- Desactivar los clics del HUD (fichas de la barra de iconos) sin ocultarlo, para recursos con
-- cursor propio a pantalla completa (p. ej. el modo decorar de rp_furniture), así sus botones
-- no compiten con los del HUD que quedan detrás.
--   exports.rp_hud:setHudClicksDisabled("mi_recurso", true / false)
local clicksBlockedBy = {}
function setHudClicksDisabled(reason, on)
    clicksBlockedBy[tostring(reason or "?")] = on and true or nil
    return true
end
function Hud.clicksDisabled() return next(clicksBlockedBy) ~= nil end

-- Y (px) donde termina el bloque de arriba a la derecha (hora, dinero, banco, arma, estrellas, nivel).
-- Para que otros recursos pongan sus paneles debajo sin solaparse (p. ej. el miedo del cajero en rp_robbery).
function getTopRightBottom()
    return Hud.topRightBottom or (MARGIN + 120 * s)
end

-- Ruta del GPS dibujada en el minimapa (la calcula rp_map por las calles reales).
--   exports.rp_hud:setNavRoute({ x1, y1, x2, y2, ... })   nil o {} la quita
function setNavRoute(points)
    if type(points) ~= "table" or #points < 4 then navRoute = nil; return true end
    local clean = {}
    for i = 1, #points do
        local v = tonumber(points[i])
        if not v then navRoute = nil; return false end
        clean[i] = v
    end
    navRoute = clean
    return true
end
