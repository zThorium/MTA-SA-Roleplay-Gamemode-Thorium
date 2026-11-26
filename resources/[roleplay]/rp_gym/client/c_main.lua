--[[
    rp_gym / c_main.lua
    Estado compartido del cliente y tecla E (subir a una maquina o hablar con un entrenador).
    El servidor decide todo: aqui solo se avisa de lo que el jugador quiere hacer.
]]

addEvent("rp:gym:near", true)
addEvent("rp:gym:state", true)

gymNearInfo = nil     -- { kind, id, label, extra } o nil
gymState = nil        -- estado de la sesion en curso (lo manda el servidor)
gymSelecting = nil    -- { id, label, weights, index } mientras se elige el peso
local frozeForSelect = false

-- Empieza (sel) o termina (nil) la eleccion de peso. Mientras se elige, el personaje queda congelado y sin
-- controles (las flechas, Enter y Retroceso siguen funcionando: son bindKey). Solo se descongela si lo congelo esto.
function gymSelect(sel)
    gymSelecting = sel
    if sel and not frozeForSelect then
        frozeForSelect = true
        setElementFrozen(localPlayer, true)
        toggleAllControls(false, true, false)
    elseif not sel and frozeForSelect then
        frozeForSelect = false
        setElementFrozen(localPlayer, false)
        toggleAllControls(true, true, false)
    end
end

addEventHandler("rp:gym:near", resourceRoot, function(kind, id, label, extra)
    if kind then
        gymNearInfo = { kind = kind, id = id, label = label, extra = extra }
    else
        gymNearInfo = nil
        gymSelect(nil)
    end
end)

addEventHandler("rp:gym:state", resourceRoot, function(state)
    gymState = state or nil
    if state then gymSelect(nil) end
    -- NO se bloquean los controles: con toggleAllControls(false) el cliente no aplica animaciones nuevas
    -- (la subida y la bajada sonaban porque se pedian con los controles activos; los bucles no). El personaje
    -- no se mueve porque las animaciones son no interrumpibles y el servidor lo reancla en cada tick.
    toggleAllControls(true, true, false)
end)

function gymBusy()
    return isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if gymBusy() or gymState or gymSelecting or not gymNearInfo then return end
        if getElementData(localPlayer, "rp:downed") or isPedInVehicle(localPlayer) then return end
        if gymNearInfo.kind == "door" then
            triggerServerEvent("rp:gym:door", resourceRoot, gymNearInfo.id)
        elseif gymNearInfo.kind == "trainer" then
            triggerServerEvent("rp:gym:trainer", resourceRoot, gymNearInfo.id)
        elseif type(gymNearInfo.extra) == "table" then
            gymSelect({ id = gymNearInfo.id, label = gymNearInfo.label, weights = gymNearInfo.extra, index = 1 })
        else
            triggerServerEvent("rp:gym:start", resourceRoot, gymNearInfo.id, 0)
        end
    end)
end)

-- Al parar/reiniciar el recurso no se deben quedar los controles bloqueados
addEventHandler("onClientResourceStop", resourceRoot, function()
    gymSelect(nil)
    toggleAllControls(true, true, false)
end)

-- Si el personaje sale, se limpia todo
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key == "rp:characterId" and not new then gymNearInfo, gymState = nil, nil; gymSelect(nil); toggleAllControls(true, true, false) end
end)
