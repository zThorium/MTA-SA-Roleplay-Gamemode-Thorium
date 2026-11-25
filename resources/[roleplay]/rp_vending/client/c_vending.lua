--[[
    rp_vending / c_vending.lua  (cliente)

    El servidor avisa con rp:vending:near cuando estas junto a una maquina; aqui solo se
    muestra "Pulsa E" y se pide la compra. El servidor revalida todo.
]]

addEvent("rp:vending:near", true)

local screenW, screenH = guiGetScreenSize()
local nearKind = nil   -- "drink" | "food" | nil

addEventHandler("rp:vending:near", resourceRoot, function(kind)
    nearKind = kind or nil
end)

local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if exports.rp_injury:isLocalPlayerDowned() then return false end
    if exports.rp_hud:isHudSuppressed() then return false end
    return true
end

addEventHandler("onClientRender", root, function()
    if not nearKind or not canInteract() then return end
    local t = VENDING.TYPES[nearKind]
    local text = ("Pulsa E para comprar %s ($%d)"):format(t.product, t.price)
    dxDrawText(text, 0, 0, screenW, screenH * 0.85, tocolor(255, 255, 255, 230), 1.2, "default-bold",
        "center", "bottom", false, false, false, true)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        -- E la usan muchos recursos: fuera de una maquina no hace nada
        if not nearKind or not canInteract() then return end
        triggerServerEvent("rp:vending:buy", resourceRoot)
    end)
end)
