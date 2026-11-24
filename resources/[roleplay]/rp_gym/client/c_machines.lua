--[[
    rp_gym / c_machines.lua
    Controles durante el entrenamiento y la eleccion de peso.

    Cinta y bici:      A y D alternando = pasos o pedaleo · Flecha arriba/abajo = nivel · Retroceso = bajarse
    Press y mancuernas: antes de empezar, flechas arriba/abajo eligen el peso y Enter confirma;
                        Espacio (repetido) empuja la barra · Retroceso = soltar el peso
    Las teclas exactas del original no estan documentadas: estas son una adaptacion (docs/GIMNASIO.md).
    El servidor valida la alternancia y la separacion entre pulsaciones.
]]

local function inSession(kind)
    if not gymState or not gymState.ready then return false end
    if kind == "cardio" then return gymState.levels ~= nil end
    if kind == "weights" then return gymState.levels == nil end
    return true
end

local function pulse(side)
    return function()
        if gymBusy() then return end
        if side == 0 and inSession("weights") or side ~= 0 and inSession("cardio") then
            triggerServerEvent("rp:gym:pulse", resourceRoot, side)
        end
    end
end

local function level(dir)
    return function()
        if gymBusy() then return end
        if inSession("cardio") then
            triggerServerEvent("rp:gym:level", resourceRoot, dir)
        elseif gymSelecting then
            local s = gymSelecting
            s.index = math.max(1, math.min(#s.weights, s.index + dir))   -- flecha arriba = mas peso
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("a", "down", pulse(1))
    bindKey("d", "down", pulse(2))
    bindKey("space", "down", pulse(0))
    bindKey("arrow_u", "down", level(1))
    bindKey("arrow_d", "down", level(-1))

    bindKey("enter", "down", function()
        if gymBusy() or not gymSelecting then return end
        local s = gymSelecting
        gymSelecting = nil
        triggerServerEvent("rp:gym:start", resourceRoot, s.id, s.index)
    end)

    bindKey("backspace", "down", function()
        if gymBusy() then return end
        if gymSelecting then
            gymSelecting = nil
        elseif gymState then
            triggerServerEvent("rp:gym:stop", resourceRoot)
        end
    end)
end)
