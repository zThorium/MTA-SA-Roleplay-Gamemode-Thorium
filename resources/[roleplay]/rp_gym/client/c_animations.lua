--[[
    rp_gym / c_animations.lua
    Las animaciones las pone el servidor con setPedAnimation (asi las ven todos). Aqui solo hay un
    vigilante: si durante la sesion el personaje no tiene ninguna animacion, pide al servidor que la repita.
    (Se quito setPedAnimationSpeed: el cliente de MTA se cerraba con una violacion de acceso en gta_sa.exe
    al cambiar la velocidad de animaciones.)
]]

local lastResync = 0

setTimer(function()
    if not gymState then return end
    if getPedAnimation(localPlayer) then return end
    local now = getTickCount()
    if now - lastResync > 1200 then
        lastResync = now
        triggerServerEvent("rp:gym:resync", resourceRoot)
    end
end, 300, 0)
