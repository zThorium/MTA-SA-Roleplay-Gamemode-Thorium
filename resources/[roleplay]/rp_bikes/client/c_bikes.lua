--[[
    rp_bikes / c_bikes.lua
    Cerca de un punto de arriendo muestra "Pulsa E para arrendar" y envia la peticion al servidor.
    El servidor valida distancia, dinero y que no tengas otra bici.
]]

local screenW, screenH = guiGetScreenSize()
local nearIndex, nearName, nearPrice, nearPays = false, nil, 0, false

addEventHandler("rp:bikes:near", resourceRoot, function(index, name, price, pays)
    nearIndex, nearName, nearPrice, nearPays = index, name, tonumber(price) or 0, pays and true or false
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if not nearIndex or isPedInVehicle(localPlayer) or getElementData(localPlayer, "rp:downed") then return end
        if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() then return end
        triggerServerEvent("rp:bikes:rent", resourceRoot, nearIndex)
    end)
end)

addEventHandler("onClientRender", root, function()
    if not nearIndex or isPedInVehicle(localPlayer) then return end
    local text = "Pulsa E para arrendar una bicicleta"
    if nearPays and nearPrice > 0 then text = text .. (" ($%d)"):format(nearPrice) end
    text = text .. " - " .. (nearName or "")
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 140
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)
