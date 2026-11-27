--[[
    rp_nametags / c_nametags.lua
    Sustituye los nametags de GTA por "Nombre Apellido [ID]" sobre la cabeza (sin vida ni
    chaleco). Solo jugadores con personaje en juego, a menos de MAX_DISTANCE metros y con
    línea de visión. También dibuja la etiqueta /ame.

    Estilo (misma línea que rp_notify y las burbujas de rp_chat):
      - Nombre en Rubik SemiBold (OFL) con sombra y el ID entre corchetes.
      - De servicio en su facción (exports.rp_factions:isPlayerOnDuty): el nombre va del
        color de la facción y debajo se escribe su rango.
      - Formas suavizadas (sin dientes de sierra) con c_dx.lua.
      - Aparece y desaparece con un fundido, sin saltos, al entrar o salir de la vista.
      - /ame: pastilla oscura con punto rosa (el color de /me), entra con un salto y una
        línea de luz que se abre desde el centro.
]]

local MAX_DISTANCE = 20
local screenW, screenH = guiGetScreenSize()
local S = math.max(0.8, math.min(1.3, screenH / 900))
local function px(v) return v * S end

local function font(file, size, fallback)
    return dxCreateFont("fonts/" .. file, math.floor(size * S + 0.5), false, "antialiased") or fallback
end
-- Las fuentes del nametag se crean a su tamaño de cerca y solo se reducen con la distancia
-- (escala <= 1): agrandar una fuente dx la emborrona, reducirla un poco no.
local F_NAME = font("rubik_medium.ttf", 16, "default-bold")
local F_ID = font("rubik_semibold.ttf", 19, "default-bold")
local F_RANK = font("rubik_medium.ttf", 15, "default-bold")
local F_AME = font("rubik_medium.ttf", 9.5, "default-bold")
local NAME_H = dxGetFontHeight(1, F_NAME)
local ID_H = dxGetFontHeight(1, F_ID)
local TAG_MIN_SCALE = 0.8      -- tamaño a MAX_DISTANCE respecto al de cerca
local RANK_GAP = 3             -- px entre la línea del nombre y la del rango

local ME_COLOR = { 255, 150, 190 }
local NAME_COLOR = { 245, 247, 250 }
local ID_COLOR = { 255, 255, 255 }
local RANK_COLOR = { 224, 228, 232 }   -- #E0E4E8
-- Color del nombre por tipo de facción cuando el de la facción es poco legible
local TYPE_NAME_COLOR = { policia = { 77, 166, 255 } }   -- #4DA6FF
local streamed = {}   -- jugadores cercanos (se refresca con un timer, no cada frame)
local vis = {}        -- [player] = alfa actual del nametag (fundido)
local ameStart = {}   -- [player] = tick en que apareció su /ame
local nameCache = {}  -- [player] = { text, idText, nameW, idW }
local duty = {}       -- [player] = { color = {r,g,b}, rank = "..." } si está de servicio en su facción

----------------------------------------------------------------
-- Utilidades de dibujo (las mismas de rp_notify)
----------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) ^ 3 end
local function easeOutBack(t)
    t = clamp(t, 0, 1)
    local c = 1.70158
    return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end
local function rgba(c, a) return tocolor(c[1], c[2], c[3], clamp(a, 0, 255)) end

-- Formas con antialiasing: c_dx.lua (DX.*)
local function circle(cx, cy, r, color) DX.circle(cx, cy, r, color, false) end
local function roundRect(x, y, w, h, r, color) DX.roundRect(x, y, w, h, r, color, false) end

local function lightLine(cx, y, half, thick, c, a)
    if half < 1 then return end
    local solid, none = rgba(c, 255 * a), rgba(c, 0)
    dxDrawPrimitive("trianglestrip", false, { cx - half, y, none }, { cx, y, solid }, { cx - half, y + thick, none }, { cx, y + thick, solid })
    dxDrawPrimitive("trianglestrip", false, { cx, y, solid }, { cx + half, y, none }, { cx, y + thick, solid }, { cx + half, y + thick, none })
end

local function hexToRGB(hex)
    local r, g, b = tostring(hex or ""):match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

-- Mismo tono, pero con brillo al máximo y saturación <= 70 %: se lee de día y de noche
local function readable(c)
    local hi, lo = math.max(c[1], c[2], c[3]), math.min(c[1], c[2], c[3])
    if hi == lo then return { 255, 255, 255 } end
    local s = math.min((hi - lo) / hi, 0.7)
    local out = {}
    for i = 1, 3 do out[i] = math.floor(255 * (1 - s * (hi - c[i]) / (hi - lo)) + 0.5) end
    return out
end

----------------------------------------------------------------
-- Nametags nativos, lista de cercanos y servicio de facción
----------------------------------------------------------------
local function factionsRunning()
    local res = getResourceFromName("rp_factions")
    return res and getResourceState(res) == "running"
end

-- Color y rango solo si está de servicio (lo decide rp_factions); nil si no
local function dutyInfo(player)
    local ok, on = pcall(function() return exports.rp_factions:isPlayerOnDuty(player) end)
    if not ok or not on then return nil end
    local ok2, f = pcall(function() return exports.rp_factions:getPlayerFactionInfo(player) end)
    if not ok2 or type(f) ~= "table" then return nil end
    local rank = tostring(f.rank or "")
    local c = hexToRGB(f.color)
    local color = TYPE_NAME_COLOR[f.type] or (c and readable(c)) or NAME_COLOR
    return { color = color, rank = rank ~= "" and rank or nil }
end

local function refreshStreamed()
    streamed = getElementsByType("player", root, true)
    duty = {}
    if not factionsRunning() then return end
    for _, player in ipairs(streamed) do
        if player ~= localPlayer then duty[player] = dutyInfo(player) end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        setPlayerNametagShowing(player, false)
        if getElementData(player, "rp:ame") then ameStart[player] = getTickCount() - 1000 end
    end
    refreshStreamed()
    setTimer(refreshStreamed, 500, 0)
end)

addEventHandler("onClientPlayerJoin", root, function()
    setPlayerNametagShowing(source, false)
end)

addEventHandler("onClientPlayerQuit", root, function()
    vis[source], ameStart[source], nameCache[source], duty[source] = nil, nil, nil, nil
end)

addEventHandler("onClientPlayerChangeNick", root, function()
    nameCache[source] = nil
end)

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if getElementType(source) ~= "player" then return end
    if key == "rp:ame" then
        ameStart[source] = new and getTickCount() or nil
    elseif key == "id" then
        nameCache[source] = nil
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do setPlayerNametagShowing(player, true) end
end)

----------------------------------------------------------------
-- /ame
----------------------------------------------------------------
local function drawAme(player, cx, cy, cz, myDim, myInt, now)
    local text = getElementData(player, "rp:ame")
    if not text or isPedDead(player) or getElementDimension(player) ~= myDim or getElementInterior(player) ~= myInt then return end
    local hx, hy, hz = getPedBonePosition(player, 8)
    local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
    if dist > MAX_DISTANCE then return end
    -- Más arriba que el nametag (que ocupa ~0.35 m); el local no tiene nametag
    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + (player == localPlayer and 0.4 or 0.6))
    if not sx then return end

    local age = now - (ameStart[player] or now - 1000)
    local alpha = (1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))) * clamp(age / 140, 0, 1)
    local sc = math.max(0.7, 1.2 - dist / MAX_DISTANCE) * (0.65 + 0.35 * easeOutBack(age / 300))
    local textW = dxGetTextWidth(text, sc, F_AME)
    local dot = px(5) * sc
    local w = textW + dot * 2 + px(22) * sc
    local h = px(20) * sc
    local x, y = sx - w / 2, sy - h

    roundRect(x + px(2) * sc, y + px(3) * sc, w, h, h / 2, tocolor(0, 0, 0, 60 * alpha))
    roundRect(x, y, w, h, h / 2, tocolor(14, 12, 18, 225 * alpha))
    circle(x + px(10) * sc + dot / 2, y + h / 2, dot / 2, rgba(ME_COLOR, 255 * alpha))
    lightLine(sx, y + px(1) * sc, (w / 2 - h / 2) * easeOut((age - 60) / 380), math.max(1, px(1.5) * sc), ME_COLOR, alpha)
    dxDrawText(text, x + px(16) * sc + dot, y, x + w, y + h, tocolor(255, 226, 236, 255 * alpha), sc, F_AME, "left", "center", false, false, false, false, true)
end

----------------------------------------------------------------
-- Nametag
----------------------------------------------------------------
local function nameData(player)
    local c = nameCache[player]
    if c then return c end
    local id = getElementData(player, "id")
    local text = getPlayerName(player):gsub("_", " ")
    local idText = id and ("[" .. tostring(id) .. "]") or nil
    c = { text = text, idText = idText, nameW = dxGetTextWidth(text, 1, F_NAME), idW = idText and dxGetTextWidth(idText, 1, F_ID) or 0 }
    nameCache[player] = c
    return c
end

-- Sombra paralela suave de 1 px (abajo a la derecha), sin contorno: las letras no se cierran.
-- Posiciones redondeadas a píxel entero para que el texto quede nítido.
local function shadowText(text, x, y, color, sc, fnt, alpha)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    dxDrawText(text, x + 1, y + 1, 0, 0, tocolor(0, 0, 0, 217 * alpha), sc, fnt, "left", "top")
    dxDrawText(text, x, y, 0, 0, rgba(color, 255 * alpha), sc, fnt, "left", "top")
end

local function drawTag(player, sx, sy, dist, alpha)
    local sc = math.max(TAG_MIN_SCALE, 1 - (1 - TAG_MIN_SCALE) * dist / MAX_DISTANCE)
    local d = nameData(player)
    local f = duty[player]

    -- Nombre (color de la facción si está de servicio) + [ID]
    local gap = px(5) * sc
    local total = d.nameW * sc + (d.idText and (gap + d.idW * sc) or 0)
    local x = sx - total / 2
    local nameY = sy - NAME_H * sc
    shadowText(d.text, x, nameY, f and f.color or NAME_COLOR, sc, F_NAME, alpha)
    if d.idText then
        -- El ID va más grande que el nombre; se alinea por abajo con él
        shadowText(d.idText, x + d.nameW * sc + gap, sy - ID_H * sc, ID_COLOR, sc, F_ID, alpha)
    end

    -- Rango debajo del nombre (solo de servicio)
    if f and f.rank then
        local w = dxGetTextWidth(f.rank, sc, F_RANK)
        shadowText(f.rank, sx - w / 2, sy + math.max(2, px(RANK_GAP) * sc), RANK_COLOR, sc, F_RANK, alpha)
    end
end

local lastFrame = getTickCount()
addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local dt = math.min(now - lastFrame, 100)
    lastFrame = now
    if getElementData(localPlayer, "rp:hudHidden") then return end   -- p. ej. cámara de Fotogram (rp_phone)
    local cx, cy, cz = getCameraMatrix()
    local myDim, myInt = getElementDimension(localPlayer), getElementInterior(localPlayer)

    drawAme(localPlayer, cx, cy, cz, myDim, myInt, now)
    for _, player in ipairs(streamed) do
        if isElement(player) and player ~= localPlayer and getElementData(player, "rp:characterId") then
            drawAme(player, cx, cy, cz, myDim, myInt, now)
        end
    end

    for _, player in ipairs(streamed) do
        if isElement(player) and player ~= localPlayer then
            local show, hx, hy, hz, dist = false
            if getElementData(player, "rp:characterId")
                and not isPedDead(player)
                and getElementDimension(player) == myDim and getElementInterior(player) == myInt
                and getElementAlpha(player) > 0 then
                hx, hy, hz = getPedBonePosition(player, 8)
                dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
                show = dist <= MAX_DISTANCE and isLineOfSightClear(cx, cy, cz, hx, hy, hz, true, false, false, true, false, false, false, localPlayer)
            end
            -- Fundido de entrada y salida en vez de aparecer de golpe
            local v = vis[player] or 0
            v = clamp(v + (show and 1 or -1) * dt / 180, 0, 1)
            vis[player] = v
            if v > 0 and hx then
                local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.35)
                if sx then
                    local alpha = (1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))) * easeOut(v)
                    drawTag(player, sx, sy, dist, alpha)
                end
            end
        end
    end
end)
