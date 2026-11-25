--[[
    rp_animlab / c_animlab.lua
    Carga el mocap de las cinematicas con engineLoadIFP y lo reproduce con setPedAnimation (solo local: herramienta de prueba).

    Variantes del archivo: "p" (por defecto) = ANP3 solo con huesos del esqueleto de peds (la que funciona),
    "anpk" = ANPK con huesos renombrados, "orig" = ANPK sin tocar.

    !! CRASH CONOCIDO (client.dll+0xC2155, AccessViolation): al DETENER o REINICIAR el recurso con un IFP cargado, MTA lo descarga solo
    y el cliente se cierra. Antes de reiniciar usa  /animlab descargar  (suelta las animaciones, espera 1.5 s y destruye los IFP).
]]

addEvent("rp:animlab:run", true)

local blocks = {}        -- [clave] = { block = nombre, ifp = elemento }
local target = "yo"
local testPed

local function say(text) triggerServerEvent("rp:animlab:result", resourceRoot, text) end

local function suffix(variant)
    if variant == "orig" then return "_orig" end
    if variant == "anpk" then return "" end
    return "_p"
end

local function loadScene(scene, variant)
    local key = scene .. suffix(variant)
    if blocks[key] then return blocks[key].block end
    local block = "animlab_" .. key
    local ifp = engineLoadIFP("anims/" .. key .. ".ifp", block)
    if not ifp then say("engineLoadIFP FALLO con anims/" .. key .. ".ifp") return nil end
    blocks[key] = { block = block, ifp = ifp }
    say("IFP cargado: bloque " .. block)
    return block
end

local function who()
    if target == "ped" and isElement(testPed) then return testPed end
    return localPlayer
end

-- Suelta la animacion sin mezcla (una animacion personalizada que se desvanece mientras se descarga su IFP es peligrosa)
local function releaseAnimation(el)
    if not isElement(el) then return end
    setPedAnimation(el, "ped", "IDLE_stance", 1, false, false, true, false, 0)
    setPedAnimation(el)
end

local segTimer

addEventHandler("rp:animlab:run", resourceRoot, function(args)
    local cmd = (args[1] or ""):lower()
    if cmd == "cargar" then
        loadScene(args[2] or "sweet1b", args[3])

    elseif cmd == "tocar" then
        -- /animlab tocar <escena> <actor> [bucle 0|1] [mover 0|1] [p|anpk|orig]
        local scene, actor = args[2] or "sweet1b", args[3] or "cssweet"
        local loop = args[4] ~= "0"
        local move = args[5] == "1"
        local block = loadScene(scene, args[6])
        if not block then return end
        local ok = setPedAnimation(who(), block, actor, -1, loop, move, false, false, 250)
        say(("setPedAnimation(%s, %s, %s) -> %s"):format(target, block, actor, tostring(ok)))

    elseif cmd == "segmento" then
        -- /animlab segmento <escena> <actor> <inicio_s> <dur_s> [total_s=60.4]   (tramo del clip, en bucle durante <dur_s>)
        local scene, actor = args[2] or "sweet1b", args[3] or "cssweet"
        local from, dur, total = tonumber(args[4]) or 0, tonumber(args[5]) or 3, tonumber(args[6]) or 60.4
        local block = loadScene(scene, "p")
        if not block then return end
        local el = who()
        local ok = setPedAnimation(el, block, actor, -1, true, false, false, false, 250)
        if ok then
            setPedAnimationProgress(el, actor, math.max(0, math.min(1, from / total)))
            if isTimer(segTimer) then killTimer(segTimer) end
            segTimer = setTimer(function() releaseAnimation(el) end, math.max(500, dur * 1000), 1)
        end
        say(("segmento %s %s %.1fs..%.1fs -> %s"):format(scene, actor, from, from + dur, tostring(ok)))

    elseif cmd == "ped" then
        if isElement(testPed) then releaseAnimation(testPed) destroyElement(testPed) end
        local x, y, z = getElementPosition(localPlayer)
        local _, _, rz = getElementRotation(localPlayer)
        local a = math.rad(rz)
        testPed = createPed(tonumber(args[2]) or 270, x - math.sin(a) * 2.2, y + math.cos(a) * 2.2, z, rz + 180)
        setElementDimension(testPed, getElementDimension(localPlayer))
        setElementInterior(testPed, getElementInterior(localPlayer))
        target = "ped"
        say("Ped de prueba creado (objetivo = ped)")

    elseif cmd == "objetivo" then
        target = args[2] == "ped" and "ped" or "yo"
        say("Objetivo = " .. target)

    elseif cmd == "parar" then
        if isTimer(segTimer) then killTimer(segTimer) end
        releaseAnimation(who())
        say("Animacion detenida")

    elseif cmd == "descargar" then
        -- Descarga controlada: sirve para saber si el crash esta en destroyElement(ifp) o solo en la descarga automatica al parar el recurso
        if isTimer(segTimer) then killTimer(segTimer) end
        releaseAnimation(localPlayer)
        releaseAnimation(testPed)
        say("Soltando animaciones; destruyendo IFP en 1.5 s...")
        setTimer(function()
            local n = 0
            for key, b in pairs(blocks) do
                if isElement(b.ifp) then destroyElement(b.ifp) n = n + 1 end
                blocks[key] = nil
            end
            say(("IFP destruidos: %d (si ves este mensaje, destroyElement no crashea)"):format(n))
        end, 1500, 1)
    else
        say("Comando desconocido: " .. cmd)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    releaseAnimation(testPed)
    releaseAnimation(localPlayer)
    if isElement(testPed) then destroyElement(testPed) end
end)
