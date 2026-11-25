--[[
    rp_sistema / c_sistema.lua  (cliente)

    Detecta cercanía a los puntos, muestra "Pulsa E para..." y pide la acción al servidor.
    El cliente nunca decide nada: el servidor revalida todo.
]]

local screenW, screenH = guiGetScreenSize()
local nearIndex = nil          -- punto cercano actual (o nil)
local suppressed = false       -- si este recurso ocultó HUD/radio (para liberarlo siempre)

----------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------
local function canInteract()
    if isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return false end
    if exports.rp_injury:isLocalPlayerDowned() then return false end
    if exports.rp_hud:isHudSuppressed() then return false end      -- cinemática u otra pantalla completa
    return true
end

local function findNear()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local px, py, pz = getElementPosition(localPlayer)
    for i, pt in ipairs(SISTEMA.POINTS) do
        if (pt.dimension or 0) == dim and (pt.interior or 0) == int
            and getDistanceBetweenPoints3D(px, py, pz, pt.x, pt.y, pt.z) <= SISTEMA.INTERACT_RADIUS then
            return i
        end
    end
end

----------------------------------------------------------------
-- Cercanía: comprobar unas veces por segundo, no cada frame
----------------------------------------------------------------
setTimer(function() nearIndex = findNear() end, 250, 0)

addEventHandler("onClientRender", root, function()
    if not nearIndex or not canInteract() then return end
    local text = "Pulsa E para usar " .. (SISTEMA.POINTS[nearIndex].name or "esto")
    dxDrawText(text, 0, 0, screenW, screenH * 0.85, tocolor(255, 255, 255, 230), 1.2, "default-bold",
        "center", "bottom", false, false, false, true)
end)

----------------------------------------------------------------
-- Teclas
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        -- E la usan muchos recursos: si no estás en TU punto, no hagas nada
        if not nearIndex or not canInteract() then return end
        triggerServerEvent("rp:sistema:use", resourceRoot, nearIndex)
    end)
end)

----------------------------------------------------------------
-- HUD / radio (solo para pantallas completas o cinemáticas propias)
----------------------------------------------------------------
local function setFullscreen(on)
    suppressed = on
    exports.rp_hud:setHudSuppressed("rp_sistema", on)
    exports.rp_radio:setRadioSuppressed("rp_sistema", on)
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if suppressed then setFullscreen(false) end
    -- devolver cámara, controles y cursor si se tocaron:
    -- setCameraTarget(localPlayer); toggleAllControls(true); showCursor(false)
end)
