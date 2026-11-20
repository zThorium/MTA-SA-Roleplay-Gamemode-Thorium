--[[
    rp_phone / s_camera.lua
    Camara de Fotogram en el mundo: mientras un jugador saca una foto, los demas
    ven el telefono en su mano y la pose elegida.

    - Dato sincronizado "rp:phoneCam" = "selfie" | "rear" | nil: cada cliente
      estira el brazo derecho de ese jugador en la selfie (c_camera.lua).
    - Telefono (objeto 330) pegado a la mano con bone_attach.
    - Pose: setPedAnimation desde el servidor (FOTOGRAM_POSES), solo a pie.
]]

local active = {}    -- [player] = { mode, prop, posed, last }

addEvent("rp:social:camera", true)
addEvent("rp:social:pose", true)
addEvent("rp:onPlayerDowned", false)

local function characterOf(player) return exports.rp_characters:getPlayerCharacterId(player) end
local function canUse(player)
    return characterOf(player) and not isPedDead(player) and not getElementData(player, "rp:downed")
        and exports.rp_inventory:hasItem(player, "phone", 1)
end

local function destroyProp(state)
    if isElement(state.prop) then
        exports.bone_attach:detachElementFromBone(state.prop)
        destroyElement(state.prop)
    end
    state.prop = nil
end

local function createProp(player, state)
    destroyProp(state)
    local x, y, z = getElementPosition(player)
    local prop = createObject(PHONE_PROP.model, x, y, z)
    if not prop then return end
    setElementCollisionsEnabled(prop, false)
    setElementInterior(prop, getElementInterior(player))
    setElementDimension(prop, getElementDimension(player))
    exports.bone_attach:attachElementToBone(prop, player, PHONE_PROP.bone,
        PHONE_PROP.x, PHONE_PROP.y, PHONE_PROP.z, PHONE_PROP.rx, PHONE_PROP.ry, PHONE_PROP.rz)
    state.prop = prop
end

local function applyPose(player, state, poseId)
    local pose = FOTOGRAM_POSE_BY_ID[poseId]
    if not pose or (pose.mode ~= state.mode and pose.mode ~= "both") then return false end
    if isPedInVehicle(player) then return false end
    setPedAnimation(player, pose.block, pose.anim, -1, true, false, false, false)
    state.posed, state.pose = true, poseId
    return true
end

-- keepAnim: no tocar la animacion (p. ej. al quedar abatido, rp_injury pone la suya)
local function stopCamera(player, keepAnim)
    local state = active[player]
    if not state then return end
    active[player] = nil
    destroyProp(state)
    if isElement(player) then
        if state.posed and not keepAnim then setPedAnimation(player) end
        removeElementData(player, "rp:phoneCam")
    end
end

addEventHandler("rp:social:camera", resourceRoot, function(mode)
    local player = client
    if mode ~= "selfie" and mode ~= "rear" then return stopCamera(player) end
    if not canUse(player) then return end
    local state = active[player]
    if not state then
        state = {}
        active[player] = state
        createProp(player, state)
    end
    state.mode = mode
    setElementData(player, "rp:phoneCam", mode)
    if not applyPose(player, state, FOTOGRAM_DEFAULT_POSE[mode]) and state.posed then
        setPedAnimation(player)
        state.posed = false
    end
end)

addEventHandler("rp:social:pose", resourceRoot, function(poseId)
    local player = client
    local state = active[player]
    if not state or not canUse(player) then return end
    local now = getTickCount()
    if state.last and now - state.last < 300 then return end
    state.last = now
    applyPose(player, state, tostring(poseId or ""))
end)

-- El objeto sigue al jugador si cambia de interior o dimension
setTimer(function()
    for player, state in pairs(active) do
        if not isElement(player) then
            active[player] = nil
        elseif isElement(state.prop) then
            if getElementDimension(state.prop) ~= getElementDimension(player) then setElementDimension(state.prop, getElementDimension(player)) end
            if getElementInterior(state.prop) ~= getElementInterior(player) then setElementInterior(state.prop, getElementInterior(player)) end
        end
    end
end, 1000, 0)

addEventHandler("onPlayerQuit", root, function() stopCamera(source, true) end)
addEventHandler("onPlayerWasted", root, function() stopCamera(source, true) end)
addEventHandler("rp:onPlayerDowned", root, function() stopCamera(source, true) end)
addEventHandler("onPlayerVehicleEnter", root, function()
    local state = active[source]
    if state then state.posed = false end   -- en el vehiculo no hay pose
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(active) do stopCamera(player) end
end)

-- Para rp_test: valida la configuracion de poses y filtros
function getCameraConfigErrors()
    local errors = {}
    local seen = {}
    for _, p in ipairs(FOTOGRAM_POSES) do
        if seen[p.id] then errors[#errors + 1] = "pose repetida " .. p.id end
        seen[p.id] = true
        if p.mode ~= "selfie" and p.mode ~= "rear" and p.mode ~= "both" then errors[#errors + 1] = "modo invalido en " .. p.id end
        if type(p.block) ~= "string" or type(p.anim) ~= "string" then errors[#errors + 1] = "animacion incompleta en " .. p.id end
    end
    for mode, id in pairs(FOTOGRAM_DEFAULT_POSE) do
        local p = FOTOGRAM_POSE_BY_ID[id]
        if not p or (p.mode ~= mode and p.mode ~= "both") then errors[#errors + 1] = "pose por defecto invalida para " .. mode end
    end
    if not FOTOGRAM_FILTER_SET.original then errors[#errors + 1] = "falta el filtro original" end
    return errors
end
