--[[
    rp_heads / c_heads.lua

    - Carga cada cabeza en un ID de modelo nuevo (engineRequestModel), asi no
      se reemplaza ningun objeto del mapa original.
    - Pone y quita las cabezas de los jugadores segun su elementData "rp:head"
      (la asigna el servidor) y cuando entran o salen del rango de stream.
    - Exporta applyHead/removeHead para peds locales (vista previa del creador).
]]

local modelIds = {}   -- [headId] = id de modelo asignado
local attached = {}   -- [ped] = objeto cabeza

-- Correccion global de altura (eje del cuello). Los ajustes de Countryside se
-- hicieron con su bone_attach compilado; con las fuentes .lua la cabeza quedaba
-- por encima del cuello. Con -0.32 se pasaba al reves: la cabeza se hundia entre
-- los hombros y el personaje parecia no tener cuello (sobre todo en el creador
-- de personajes). -0.20 deja un cuello visible. Se puede afinar en juego con
-- /ajustecabeza y fijar aqui el valor resultante.
local HEAD_Z_FIX = -0.20

----------------------------------------------------------------
-- Sangre del cuello: GTA dibuja un chorro de sangre en los peds sin cabeza.
-- Reemplazamos sus texturas por una transparente.
----------------------------------------------------------------
local bloodShader
local function hideHeadlessBlood()
    bloodShader = dxCreateShader("texreplace.fx", 1000, 0, false, "all")
    local texture = dxCreateTexture("textures/transparent.png")
    if not bloodShader or not texture then
        outputDebugString("[rp_heads] No se pudo crear el shader para ocultar la sangre", 2)
        return
    end
    dxSetShaderValue(bloodShader, "gTexture", texture)
    engineApplyShaderToWorldTexture(bloodShader, "sphere")
    engineApplyShaderToWorldTexture(bloodShader, "bloodpool_64")
end

local function loadModels()
    for id in pairs(HEADS) do
        local model = engineRequestModel("object")
        local txd = model and engineLoadTXD("models/" .. id .. ".txd")
        local dff = txd and engineLoadDFF("models/" .. id .. ".dff")
        if model and txd and dff then
            engineImportTXD(txd, model)
            engineReplaceModel(dff, model)
            modelIds[id] = model
        else
            outputDebugString("[rp_heads] No se pudo cargar la cabeza " .. id, 2)
            if model then engineFreeModel(model) end
        end
    end
end

function removeHead(ped)
    local obj = attached[ped]
    if isElement(obj) then destroyElement(obj) end
    attached[ped] = nil
    return true
end

function applyHead(ped, headId)
    removeHead(ped)
    headId = tonumber(headId)
    local head = headId and HEADS[headId]
    if not isElement(ped) or not head or not modelIds[headId] then return false end

    local x, y, z = getElementPosition(ped)
    local obj = createObject(modelIds[headId], x, y, z + 1)
    if not obj then return false end

    setObjectScale(obj, head.scale)
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, getElementInterior(ped))
    setElementDimension(obj, getElementDimension(ped))
    setElementDoubleSided(obj, true)
    exports.bone_attach:attachElementToBone(obj, ped, 2, head.x, head.y, head.z + HEAD_Z_FIX, head.rx, head.ry, head.rz)
    attached[ped] = obj
    return true
end

-- Herramienta de calibracion (solo visual, local): /ajustecabeza <z> [y]
-- Mueve todas las cabezas visibles y muestra el valor para fijarlo en HEAD_Z_FIX.
addCommandHandler("ajustecabeza", function(_, z, y)
    z, y = tonumber(z), tonumber(y) or 0
    if not z then
        outputChatBox("Uso: /ajustecabeza <correccion_z> [correccion_y]   (actual: " .. HEAD_Z_FIX .. ")", 255, 200, 0)
        return
    end
    HEAD_Z_FIX = z
    for ped, obj in pairs(attached) do
        local headId
        for id, model in pairs(modelIds) do
            if model == getElementModel(obj) then headId = id break end
        end
        local head = headId and HEADS[headId]
        if head then
            exports.bone_attach:attachElementToBone(obj, ped, 2, head.x, head.y + y, head.z + z, head.rx, head.ry, head.rz)
        end
    end
    outputChatBox(("HEAD_Z_FIX = %.3f  (y extra = %.3f)"):format(z, y), 120, 200, 255)
end)

function getPedHead(ped)
    return attached[ped]
end

----------------------------------------------------------------
-- Jugadores (sincronizado por elementData del servidor)
----------------------------------------------------------------
local function refreshPlayer(player)
    local headId = getElementData(player, "rp:head")
    if headId and isElementStreamedIn(player) then
        applyHead(player, headId)
    else
        removeHead(player)
    end
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:head" and getElementType(source) == "player" then
        refreshPlayer(source)
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" then refreshPlayer(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "player" then removeHead(source) end
end)

addEventHandler("onClientPlayerQuit", root, function()
    removeHead(source)
end)

addEventHandler("onClientElementDestroy", root, function()
    if attached[source] then removeHead(source) end
end)

-- Mantiene la cabeza en la misma dimension/interior que su dueno y la
-- oculta al apuntar con la camara o el francotirador (evita que tape la mira)
setTimer(function()
    for ped, obj in pairs(attached) do
        if not isElement(ped) or not isElement(obj) then
            removeHead(ped)
        else
            if getElementDimension(obj) ~= getElementDimension(ped) then setElementDimension(obj, getElementDimension(ped)) end
            if getElementInterior(obj) ~= getElementInterior(ped) then setElementInterior(obj, getElementInterior(ped)) end
        end
    end
end, 500, 0)

addEventHandler("onClientRender", root, function()
    local obj = attached[localPlayer]
    if not isElement(obj) then return end
    local weapon = getPedWeapon(localPlayer)
    local aiming = (weapon == 34 or weapon == 43) and getPedTask(localPlayer, "secondary", 0) == "TASK_SIMPLE_USE_GUN"
    setElementAlpha(obj, aiming and 0 or 255)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadModels()
    hideHeadlessBlood()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        refreshPlayer(player)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for ped in pairs(attached) do removeHead(ped) end
    for _, model in pairs(modelIds) do engineFreeModel(model) end
end)
