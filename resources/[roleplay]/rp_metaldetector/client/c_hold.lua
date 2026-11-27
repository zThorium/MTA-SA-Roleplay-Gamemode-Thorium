--[[
    rp_metaldetector / c_hold.lua  (cliente)

    Detector en la mano de TODOS los jugadores que lo llevan (elementData rp:heldItem = metal_detector_<n>):
    - Modelos propios: models/detector_<n>.dff + models/detector.txd (tools/build_detector.py), cada uno
      en un ID nuevo (engineRequestModel). Si faltan, palo de golf (FALLBACK_MODEL).
    - Colocación: la empuñadura va en la POSICIÓN de la mano (hueso 25), pero la orientación sale del
      rumbo del personaje (no de los ejes del hueso, que giran con la animación): la vara apunta hacia
      delante y abajo, inclinada cada fotograma para que la bobina toque el suelo, y barre de lado a lado.
    - Pose opcional del brazo (POSE_ENABLED, setElementBoneRotation); apagada por defecto: el brazo va
      con su animación natural, colgando. Con cabeza custom (rp_heads) se vuelve a ocultar la original.
    Ajuste en vivo (solo tu vista; copia los valores a shared/s_config.lua):
        /mdprop <x> <y> <z> [rx ry rz]         desfase en el marco del personaje (x derecha, y delante, z arriba)
                                               y giro extra (rx inclina, rz gira hacia los lados)
        /mdpose <hueso> <yaw> <pitch> <roll>   rotación de un hueso del brazo (22, 23, 24)
        /mdpose off | on                       quitar o poner la pose
]]

MDX = MDX or {}

local models = {}      -- [nivel] = id de modelo
local txd
local props = {}       -- [player] = { obj, tier }
local offset, pose, poseOn

----------------------------------------------------------------
-- Modelos
----------------------------------------------------------------
local function loadModels()
    if fileExists("models/detector.txd") then txd = engineLoadTXD("models/detector.txd") end
    for i = 1, #METALDETECTOR.TIERS do
        local path = ("models/detector_%d.dff"):format(i)
        if fileExists(path) then
            local id = engineRequestModel("object")
            local dff = id and engineLoadDFF(path)
            if id and dff then
                if txd then engineImportTXD(txd, id) end
                engineReplaceModel(dff, id)
                models[i] = id
            else
                if id then engineFreeModel(id) end
                outputDebugString("[rp_metaldetector] no se pudo cargar " .. path, 2)
            end
        end
    end
end

local function modelFor(tier) return models[tier] or METALDETECTOR.FALLBACK_MODEL end

----------------------------------------------------------------
-- Matrices (convención de RenderWare: vector fila, mundo = local * M)
----------------------------------------------------------------
-- El modelo tiene la empuñadura en el origen y la bobina en (0, COIL_Y, COIL_Z) (tools/build_detector.py):
-- +Y hacia delante, +Z arriba. Inclinarlo un ángulo a sobre su eje X baja la bobina a L·sin(a − BASE).
local COIL_Y, COIL_Z = 0.62, -0.88
local COIL_LEN = math.sqrt(COIL_Y * COIL_Y + COIL_Z * COIL_Z)
local COIL_BASE = math.atan2(-COIL_Z, COIL_Y)

-- Suelo bajo la bobina (si no hay nada, nil)
local function groundBelow(player, x, y, z)
    local hit, _, _, hz = processLineOfSight(x, y, z + 0.3, x, y, z - 2.2, true, false, false, true, false, false, false, false, player)
    return hit and hz or nil
end

-- Matriz del objeto: posición de la mano + rumbo del personaje + barrido + inclinación hasta el suelo
local function objectMatrix(player, hx, hy, hz, sweepDeg)
    local o = offset
    local _, _, heading = getElementRotation(player)
    local h = math.rad(heading)
    -- Desfase en el marco del personaje (x derecha, y delante, z arriba)
    local gx = hx + math.cos(h) * o.x - math.sin(h) * o.y
    local gy = hy + math.sin(h) * o.x + math.cos(h) * o.y
    local gz = hz + o.z
    -- Rumbo del detector (barrido incluido)
    local yaw = math.rad(heading + sweepDeg + o.rz)
    local cy, sy = math.cos(yaw), math.sin(yaw)
    -- Inclinación para que la bobina toque el suelo delante
    local reach = COIL_LEN * math.cos(COIL_BASE)
    local ground = groundBelow(player, gx - sy * reach, gy + cy * reach, gz)
    local drop = ground and (gz - ground - 0.03) or -COIL_Z
    drop = math.max(0.25, math.min(COIL_LEN * 0.97, drop))
    local a = COIL_BASE + math.asin(-drop / COIL_LEN) + math.rad(o.rx)
    local ca, sa = math.cos(a), math.sin(a)
    -- Filas (vector fila): primero inclinar sobre X del modelo, luego girar al rumbo
    return {
        { cy, sy, 0, 0 },
        { -sy * ca, cy * ca, sa, 0 },
        { sy * sa, -cy * sa, ca, 0 },
        { gx, gy, gz, 1 },
    }
end

----------------------------------------------------------------
-- Props por jugador
----------------------------------------------------------------
local function removeProp(player)
    local pr = props[player]
    if pr and isElement(pr.obj) then destroyElement(pr.obj) end
    props[player] = nil
end

local function refreshProp(player)
    local held = isElement(player) and METALDETECTOR_TIER_BY_ITEM[getElementData(player, "rp:heldItem") or ""]
    local tier = held and held.index
    tier = tonumber(tier)
    if not tier or not isElementStreamedIn(player) then return removeProp(player) end
    local pr = props[player]
    if pr and pr.tier == tier and isElement(pr.obj) then return end
    removeProp(player)
    local x, y, z = getElementPosition(player)
    local obj = createObject(modelFor(tier), x, y, z)
    if not obj then return end
    setElementCollisionsEnabled(obj, false)
    setElementInterior(obj, getElementInterior(player))
    setElementDimension(obj, getElementDimension(player))
    setObjectBreakable(obj, false)
    props[player] = { obj = obj, tier = tier, phase = math.random() * 10 }
end
MDX.refreshHoldProp = refreshProp

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:heldItem" and getElementType(source) == "player" then refreshProp(source) end
end)
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" then refreshProp(source) end
end)
addEventHandler("onClientElementStreamOut", root, function()
    if props[source] then removeProp(source) end
end)
addEventHandler("onClientPlayerQuit", root, function() removeProp(source) end)

----------------------------------------------------------------
-- Pose y matriz cada fotograma (después de animar a los peds)
----------------------------------------------------------------
addEventHandler("onClientPedsProcessed", root, function()
    if not next(props) then return end
    local now = getTickCount() / 1000
    local sw = METALDETECTOR.SWEEP
    for player, pr in pairs(props) do
        if not isElement(player) or not isElement(pr.obj) then
            removeProp(player)
        elseif isElementOnScreen(player) or player == localPlayer then
            if poseOn and setElementBoneRotation then
                for bone, v in pairs(pose) do setElementBoneRotation(player, bone, v[1], v[2], v[3]) end
                updateElementRpHAnim(player)
                -- rp_heads: el ped con cabeza custom va sin cabeza; actualizar los huesos la vuelve a mostrar
                if setPedHeadless and getElementData(player, "rp:head") then setPedHeadless(player, true) end
            end
            local hx, hy, hz = getPedBonePosition(player, METALDETECTOR.HAND_BONE)
            if hx then
                local vx, vy = getElementVelocity(player)
                local moving = (vx * vx + vy * vy) > 0.0004
                pr.phase = pr.phase + (moving and sw.walkSpeed or sw.idleSpeed) * 0.016 * math.pi * 2
                setElementMatrix(pr.obj, objectMatrix(player, hx, hy, hz, math.sin(pr.phase) * sw.angle))
            end
        end
    end
end)

----------------------------------------------------------------
-- Ajuste en vivo
----------------------------------------------------------------
local function say(text) outputConsole("[detector] " .. text); exports.rp_notify:notify(text, "info") end

addCommandHandler("mdprop", function(_, x, y, z, rx, ry, rz)
    local v = { tonumber(x), tonumber(y), tonumber(z), tonumber(rx), tonumber(ry), tonumber(rz) }
    if not (v[1] and v[2] and v[3]) then
        return say(("Uso: /mdprop x y z [rx ry rz]. Ahora: %.3f %.3f %.3f %d %d %d"):format(offset.x, offset.y, offset.z, offset.rx, offset.ry, offset.rz))
    end
    offset = { x = v[1], y = v[2], z = v[3], rx = v[4] or offset.rx, ry = v[5] or offset.ry, rz = v[6] or offset.rz }
    say(("PROP_OFFSET = { x = %.3f, y = %.3f, z = %.3f, rx = %d, ry = %d, rz = %d }"):format(offset.x, offset.y, offset.z, offset.rx, offset.ry, offset.rz))
end)

addCommandHandler("mdpose", function(_, bone, yaw, pitch, roll)
    if bone == "off" or bone == "on" then
        poseOn = bone == "on"
        return say("Pose del brazo " .. (poseOn and "activada" or "desactivada") .. ".")
    end
    bone = tonumber(bone)
    if not bone or not tonumber(yaw) then
        local parts = {}
        for b, v in pairs(pose) do parts[#parts + 1] = ("[%d] = { %d, %d, %d }"):format(b, v[1], v[2], v[3]) end
        return say("Uso: /mdpose <hueso> <yaw> <pitch> <roll> | on | off. Ahora: " .. table.concat(parts, ", "))
    end
    pose[bone] = { tonumber(yaw) or 0, tonumber(pitch) or 0, tonumber(roll) or 0 }
    say(("POSE[%d] = { %d, %d, %d }"):format(bone, pose[bone][1], pose[bone][2], pose[bone][3]))
end)

----------------------------------------------------------------
-- Arranque y parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    local o = METALDETECTOR.PROP_OFFSET
    offset = { x = o.x, y = o.y, z = o.z, rx = o.rx, ry = o.ry, rz = o.rz }
    pose = {}
    for b, v in pairs(METALDETECTOR.POSE) do pose[b] = { v[1], v[2], v[3] } end
    poseOn = METALDETECTOR.POSE_ENABLED
    loadModels()
    for _, player in ipairs(getElementsByType("player", root, true)) do refreshProp(player) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for player in pairs(props) do removeProp(player) end
    for _, id in pairs(models) do engineFreeModel(id) end
end)
