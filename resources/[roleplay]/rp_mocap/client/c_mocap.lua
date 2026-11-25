--[[
    rp_mocap / client / c_mocap.lua

    Carga UNA vez todos los IFP de la biblioteca y reproduce clips en peds/jugadores cuando el servidor lo pide
    (o cuando otro recurso de cliente llama a playClip/stopClip).

    !! NO reiniciar este recurso en desarrollo: MTA descarga los IFP al pararlo y el cliente puede cerrarse
    (client.dll AccessViolation). Reiniciar rp_missions no afecta: los IFP viven aqui.
    Para recargar: /mocapdescargar, esperar el aviso y entonces restart rp_mocap.
]]

addEvent("rp:mocap:play", true)
addEvent("rp:mocap:stop", true)

local ifps = {}          -- [personaje] = elemento IFP
local active = {}        -- [ped] = true (peds con un clip puesto por este recurso)

-- Carga (o recarga) las bibliotecas que falten. Se llama al iniciar, con /mocapcargar y, si hace falta, al reproducir
local function loadAll()
    local n, failed = 0, 0
    for char, data in pairs(MOCAP) do
        if not isElement(ifps[char]) then
            local ifp = engineLoadIFP(data.file, data.block)
            if ifp then ifps[char] = ifp n = n + 1
            else failed = failed + 1 outputDebugString("[rp_mocap] No se pudo cargar " .. data.file, 2) end
        end
    end
    return n, failed
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local n = loadAll()
    outputDebugString(("[rp_mocap] %d bibliotecas de mocap cargadas"):format(n), 3)
end)
local function blockOf(char, name)
    local c = MOCAP[char]
    if not c then return end
    for _, clip in ipairs(c.clips) do if clip.name == name then return c.block end end
end

-- Reproduce un clip por nombre. Devuelve true/false (resultado de setPedAnimation)
local function playByName(ped, char, name, loop)
    if not isElement(ped) then return false, "el ped ya no existe en este cliente" end
    if not isElement(ifps[char]) then loadAll() end   -- p. ej. tras /mocapdescargar
    if not isElement(ifps[char]) then return false, "IFP de " .. tostring(char) .. " no cargado" end
    local block = blockOf(char, name)
    if not block then return false, "clip " .. tostring(name) .. " no esta en el catalogo" end
    -- (ped, bloque, anim, tiempo, bucle, moverPosicion, interrumpible, congelarUltimoCuadro, mezcla)
    local ok = setPedAnimation(ped, block, name, -1, loop and true or false, false, false, false, 250)
    if ok then active[ped] = true end
    return ok, ("bloque %s clip %s setPedAnimation=%s ped=%s streamedIn=%s"):format(block, name, tostring(ok), getElementType(ped), tostring(isElementStreamedIn(ped)))
end

-- API de cliente: kind = "gesture" | "idle"; index opcional (al azar)
function playClip(ped, char, kind, index, loop)
    local c = MOCAP[char]
    if not c then return false end
    local list = {}
    for _, clip in ipairs(c.clips) do if clip.kind == kind then list[#list + 1] = clip end end
    if #list == 0 then return false end
    local clip = list[tonumber(index) or math.random(#list)]
    if not clip then return false end
    if loop == nil then loop = kind == "idle" end
    return playByName(ped, char, clip.name, loop)
end

function stopClip(ped)
    if not isElement(ped) then return false end
    active[ped] = nil
    setPedAnimation(ped)
    return true
end

addEvent("rp:mocap:result", true)
addEventHandler("rp:mocap:play", resourceRoot, function(ped, char, name, loop, debug)
    local ok, why = playByName(ped, char, name, loop)
    if debug then triggerServerEvent("rp:mocap:result", resourceRoot, tostring(ok) .. " | " .. tostring(why)) end
    if not ok then outputDebugString("[rp_mocap] no se pudo reproducir " .. tostring(name) .. ": " .. tostring(why), 2) end
end)

-- Prueba solo de cliente (sin servidor): /mocapc <personaje> <gesture|idle> [n]
addCommandHandler("mocapc", function(_, char, kind, n)
    char, kind = char or "sweet", kind == "idle" and "idle" or "gesture"
    local c = MOCAP[char]
    if not c then return outputChatBox("[mocapc] personaje desconocido", 255, 120, 120) end
    local list = {}
    for _, clip in ipairs(c.clips) do if clip.kind == kind then list[#list + 1] = clip end end
    local clip = list[tonumber(n) or 1]
    if not clip then return outputChatBox("[mocapc] no hay ese clip", 255, 120, 120) end
    local ok, why = playByName(localPlayer, char, clip.name, kind == "idle")
    outputChatBox(("[mocapc] ifp=%s %s -> %s | %s"):format(tostring(isElement(ifps[char])), clip.name, tostring(ok), tostring(why)), 120, 220, 255)
end)
addEventHandler("rp:mocap:stop", resourceRoot, function(ped) stopClip(ped) end)

addEventHandler("onClientElementDestroy", root, function() active[source] = nil end)

-- Soltar todo (sin mezcla) y destruir los IFP de forma controlada, antes de reiniciar el recurso
local function releaseAll()
    for ped in pairs(active) do
        if isElement(ped) then
            setPedAnimation(ped, "ped", "IDLE_stance", 1, false, false, true, false, 0)
            setPedAnimation(ped)
        end
    end
    active = {}
end

addCommandHandler("mocapdescargar", function()
    releaseAll()
    outputChatBox("[rp_mocap] Animaciones soltadas; destruyendo IFP en 1.5 s...", 120, 220, 255)
    setTimer(function()
        local n = 0
        for char, ifp in pairs(ifps) do if isElement(ifp) then destroyElement(ifp) n = n + 1 end ifps[char] = nil end
        outputChatBox(("[rp_mocap] %d IFP destruidos. Reinicia el recurso, o usa /mocapcargar para volver a cargarlas sin reiniciar. (Si no haces ninguna de las dos, se recargan solas al reproducir.)"):format(n), 120, 220, 255)
    end, 1500, 1)
end)

addCommandHandler("mocapcargar", function()
    local n, failed = loadAll()
    outputChatBox(("[rp_mocap] %d bibliotecas cargadas, %d con error"):format(n, failed), 120, 220, 255)
end)

addEventHandler("onClientResourceStop", resourceRoot, releaseAll)
