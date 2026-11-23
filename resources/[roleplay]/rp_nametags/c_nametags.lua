--[[
    rp_nametags / c_nametags.lua
    Sustituye los nametags de GTA por "Nombre Apellido (ID)" sobre la cabeza,
    con barra de vida y chaleco. Solo jugadores con personaje en juego, a menos
    de MAX_DISTANCE metros y con linea de vision.
]]

local MAX_DISTANCE = 20
local screenH = select(2, guiGetScreenSize())
local baseScale = math.max(0.8, math.min(1.2, screenH / 900))

local function hideDefault(player)
    setPlayerNametagShowing(player, false)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do hideDefault(player) end
end)

addEventHandler("onClientPlayerJoin", root, function()
    hideDefault(source)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do setPlayerNametagShowing(player, true) end
end)

local function drawBar(x, y, w, h, ratio, r, g, b, alpha)
    dxDrawRectangle(x - 1, y - 1, w + 2, h + 2, tocolor(0, 0, 0, 160 * alpha))
    dxDrawRectangle(x, y, w * math.max(0, math.min(1, ratio)), h, tocolor(r, g, b, 230 * alpha))
end

-- Barra roja /ame sobre la cabeza (incluye al jugador local)
local function drawAme(player, cx, cy, cz, myDim, myInt)
    local text = getElementData(player, "rp:ame")
    if not text or isPedDead(player) or getElementDimension(player) ~= myDim or getElementInterior(player) ~= myInt then return end
    local hx, hy, hz = getPedBonePosition(player, 8)
    local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
    if dist > MAX_DISTANCE then return end
    -- Mas arriba que el nametag (que ocupa ~0.35 m); el local no tiene nametag
    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + (player == localPlayer and 0.4 or 0.6))
    if not sx then return end

    local alpha = 1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))
    local scale = baseScale * math.max(0.7, 1.2 - dist / MAX_DISTANCE)
    text = "* " .. text
    local w = dxGetTextWidth(text, scale, "default-bold") + 20 * scale
    local h = 20 * scale
    dxDrawRectangle(sx - w / 2, sy - h, w, h, tocolor(170, 20, 28, 215 * alpha))
    dxDrawRectangle(sx - w / 2, sy - h, w, 2, tocolor(255, 90, 90, 230 * alpha))
    dxDrawText(text, sx - w / 2, sy - h, sx + w / 2, sy, tocolor(255, 255, 255, 255 * alpha), scale, "default-bold", "center", "center", true)
end

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "rp:hudHidden") then return end   -- p. ej. camara de Fotogram (rp_phone)
    local cx, cy, cz = getCameraMatrix()
    local myDim, myInt = getElementDimension(localPlayer), getElementInterior(localPlayer)

    drawAme(localPlayer, cx, cy, cz, myDim, myInt)
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if player ~= localPlayer and getElementData(player, "rp:characterId") then
            drawAme(player, cx, cy, cz, myDim, myInt)
        end
    end

    for _, player in ipairs(getElementsByType("player", root, true)) do
        if player ~= localPlayer
            and getElementData(player, "rp:characterId")
            and not isPedDead(player)
            and getElementDimension(player) == myDim and getElementInterior(player) == myInt
            and getElementAlpha(player) > 0 then

            local hx, hy, hz = getPedBonePosition(player, 8)
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
            if dist <= MAX_DISTANCE and isLineOfSightClear(cx, cy, cz, hx, hy, hz, true, false, false, true, false, false, false, localPlayer) then
                local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.35)
                if sx then
                    local alpha = 1 - math.max(0, (dist - MAX_DISTANCE * 0.7) / (MAX_DISTANCE * 0.3))
                    local scale = baseScale * math.max(0.7, 1.2 - dist / MAX_DISTANCE)
                    local name = getPlayerName(player):gsub("_", " ")
                    local id = getElementData(player, "id")
                    local text = id and ("%s (%d)"):format(name, id) or name

                    -- Sombra + texto
                    dxDrawText(text, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 200 * alpha), scale, "default-bold", "center", "bottom")
                    dxDrawText(text, sx, sy, sx, sy, tocolor(255, 255, 255, 255 * alpha), scale, "default-bold", "center", "bottom")

                    -- Barras de vida y chaleco
                    local w, h = 60 * scale, 4 * scale
                    drawBar(sx - w / 2, sy + 4 * scale, w, h, getElementHealth(player) / 100, 76, 211, 138, alpha)
                    local armor = getPedArmor(player)
                    if armor > 0 then
                        drawBar(sx - w / 2, sy + 4 * scale + h + 3 * scale, w, h, armor / 100, 200, 200, 210, alpha)
                    end
                end
            end
        end
    end
end)
