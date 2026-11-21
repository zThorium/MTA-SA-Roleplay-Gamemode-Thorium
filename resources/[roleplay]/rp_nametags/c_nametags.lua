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

addEventHandler("onClientRender", root, function()
    if getElementData(localPlayer, "rp:hudHidden") then return end   -- p. ej. camara de Fotogram (rp_phone)
    local cx, cy, cz = getCameraMatrix()
    local myDim, myInt = getElementDimension(localPlayer), getElementInterior(localPlayer)

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
