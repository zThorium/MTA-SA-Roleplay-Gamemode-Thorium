--[[
    rp_gym / c_animations.lua
    Las animaciones las pone el servidor con setPedAnimation (asi las ven todos). Aqui solo se
    ajusta, en el cliente del que entrena, la velocidad del bucle segun el nivel de la cinta o la bici
    (setPedAnimationSpeed no se sincroniza: los demas jugadores lo ven a velocidad normal).
]]

local lastSpeed, lastKind = 1, nil

local function setLoopSpeed(kind, speed)
    local cfg = GYM_KINDS[kind]
    if not cfg or not cfg.loops then return end
    for _, entry in ipairs(cfg.loops) do setPedAnimationSpeed(localPlayer, entry[2], speed) end
end

addEventHandler("onClientPreRender", root, function()
    local s = gymState
    local speed = 1
    if s and s.ready and s.levels and not s.tired then
        speed = 0.6 + 0.06 * s.level   -- el limite de 1.0 de la wiki se supera con cuidado: maximo 1.2
    end
    if speed == lastSpeed then return end
    lastSpeed = speed
    local kind = s and s.kind or lastKind
    if kind then setLoopSpeed(kind, speed) end
    lastKind = s and s.kind or nil
end)
