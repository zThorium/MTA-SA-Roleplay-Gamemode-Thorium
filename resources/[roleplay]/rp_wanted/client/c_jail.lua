--[[
    rp_wanted / c_jail.lua
    Timer de la carcel arriba al centro: tiempo restante y fianza (/fianza).
    Los valores vienen del servidor (elementData rp:jail y rp:jailBail).
]]

local screenW, screenH = guiGetScreenSize()
local s = math.max(0.75, math.min(1.3, screenH / 900))

addEventHandler("onClientRender", root, function()
    local left = tonumber(getElementData(localPlayer, "rp:jail"))
    if not left then return end
    local bail = tonumber(getElementData(localPlayer, "rp:jailBail")) or 0
    local w, h = 330 * s, 74 * s
    local x, y = (screenW - w) / 2, 28 * s
    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, w, 3 * s, tocolor(229, 72, 77, 255))
    dxDrawText("CARCEL", x, y + 8 * s, x + w, y + 26 * s, tocolor(154, 163, 178), 0.9 * s, "default-bold", "center", "center")
    dxDrawText(("%d:%02d"):format(math.floor(left / 60), left % 60), x, y + 22 * s, x + w, y + 52 * s,
        tocolor(242, 244, 248), 1.9 * s, "default-bold", "center", "center")
    dxDrawText(("Fianza $%d  -  /fianza"):format(bail), x, y + 50 * s, x + w, y + h - 4 * s,
        tocolor(76, 211, 138), 0.95 * s, "default-bold", "center", "center")
end)
