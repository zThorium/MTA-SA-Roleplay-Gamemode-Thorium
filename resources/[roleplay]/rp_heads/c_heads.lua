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
-- unos 0.3 por encima del cuello. Se puede afinar en juego con /ajustecabeza.
local HEAD_Z_FIX = -0.28

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

----------------------------------------------------------------
-- Vinculo a la matriz real del hueso de la cabeza (sin bone_attach).
-- bone_attach deduce la orientacion de 3 posiciones de huesos y la pasa por
-- angulos de Euler: se rompe al agacharse o girar rapido la mira. Aqui se usa
-- getElementBoneMatrix(ped, 8) + setElementMatrix, sin Euler. Los offsets de
-- HEADS siguen expresados en el marco del cuello de bone_attach; se convierten
-- con una matriz fija C (cuello -> hueso cabeza) medida con un ped de pie.
-- USE_BONE_MATRIX = false vuelve al metodo antiguo de bone_attach.
----------------------------------------------------------------
local USE_BONE_MATRIX = false
local HEAD_Y_FIX = 0
local headInfo = {}   -- [ped] = datos HEADS de su cabeza
local calib           -- { R = 3x3 (cuello*cabeza^T), c = {x,y,z} }

local function dot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end

local function normalized(x, y, z)
    local l = math.sqrt(x*x + y*y + z*z)
    if l < 1e-6 then return nil end
    return { x/l, y/l, z/l }
end

-- Marco del cuello igual que bone_attach (hueso 2: origen 4, destino 5, referencia 8)
local function getNeckFrame(ped)
    local x, y, z = getPedBonePosition(ped, 4)
    local tx, ty, tz = getPedBonePosition(ped, 5)
    local fx, fy, fz = getPedBonePosition(ped, 8)
    local ax, ay, az = tx - x, ty - y, tz - z
    local bx, by, bz = fx - x, fy - y, fz - z
    local x1, y1, z1 = by*az - bz*ay, bz*ax - bx*az, bx*ay - by*ax
    local x2, y2, z2 = ay*z1 - az*y1, az*x1 - ax*z1, ax*y1 - ay*x1
    local r1, r2, r3 = normalized(x1, y1, z1), normalized(x2, y2, z2), normalized(ax, ay, az)
    if not (r1 and r2 and r3) then return nil end
    return { r1, r2, r3 }, { x, y, z }
end

local function getHeadBoneFrame(ped)
    updateElementRpHAnim(ped)
    local m = getElementBoneMatrix(ped, 8)
    if not m then return nil end
    local r1 = normalized(m[1][1], m[1][2], m[1][3])
    local r2 = normalized(m[2][1], m[2][2], m[2][3])
    local r3 = normalized(m[3][1], m[3][2], m[3][3])
    if not (r1 and r2 and r3) then return nil end
    return { r1, r2, r3 }, { m[4][1], m[4][2], m[4][3] }
end

-- Mide C con un ped de pie y quieto (el marco del cuello es fiable en esa pose)
local function tryCalibrate(ped)
    if calib or not isElement(ped) then return end
    if isPedDucked(ped) or isPedInVehicle(ped) or getPedMoveState(ped) ~= "stand" then return end
    if getPedTask(ped, "secondary", 0) == "TASK_SIMPLE_USE_GUN" then return end  -- apuntando: no es pose neutra
    local Rn, pn = getNeckFrame(ped)
    local Rh, ph = getHeadBoneFrame(ped)
    if not (Rn and Rh) then return end
    local R = {}
    for i = 1, 3 do
        R[i] = {}
        for j = 1, 3 do R[i][j] = dot(Rn[i], Rh[j]) end
    end
    local d = { pn[1] - ph[1], pn[2] - ph[2], pn[3] - ph[3] }
    calib = { R = R, c = { dot(d, Rh[1]), dot(d, Rh[2]), dot(d, Rh[3]) } }
end

local function eulerRows(x, y, z)
    x, y, z = math.rad(x), math.rad(y), math.rad(z)
    local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
    return {
        { cy*cz - sy*sx*sz,  cy*sz + sy*sx*cz, -sy*cx },
        { -cx*sz,            cx*cz,             sx },
        { sy*cz + cy*sx*sz,  sy*sz - cy*sx*cz,  cy*cx },
    }
end

local function updateHeadMatrices()
    for ped, obj in pairs(attached) do
        local head = headInfo[ped]
        if head and isElement(ped) and isElement(obj) and isElementStreamedIn(ped) then
            tryCalibrate(ped)
            local Rh, ph = getHeadBoneFrame(ped)
            if Rh then
                if not calib then
                    setElementPosition(obj, ph[1], ph[2], ph[3])
                else
                    local Roff = eulerRows(head.rx, head.ry, head.rz)
                    local C = calib.R
                    -- Rc = Roff * C ; Rw = Rc * Rh
                    local Rw = {}
                    for i = 1, 3 do
                        local rc = {}
                        for j = 1, 3 do rc[j] = Roff[i][1]*C[1][j] + Roff[i][2]*C[2][j] + Roff[i][3]*C[3][j] end
                        Rw[i] = {
                            rc[1]*Rh[1][1] + rc[2]*Rh[2][1] + rc[3]*Rh[3][1],
                            rc[1]*Rh[1][2] + rc[2]*Rh[2][2] + rc[3]*Rh[3][2],
                            rc[1]*Rh[1][3] + rc[2]*Rh[2][3] + rc[3]*Rh[3][3],
                        }
                    end
                    local o = { head.x, head.y + HEAD_Y_FIX, head.z + HEAD_Z_FIX }
                    local ph2 = {}
                    for j = 1, 3 do ph2[j] = o[1]*C[1][j] + o[2]*C[2][j] + o[3]*C[3][j] + calib.c[j] end
                    local px = ph[1] + ph2[1]*Rh[1][1] + ph2[2]*Rh[2][1] + ph2[3]*Rh[3][1]
                    local py = ph[2] + ph2[1]*Rh[1][2] + ph2[2]*Rh[2][2] + ph2[3]*Rh[3][2]
                    local pz = ph[3] + ph2[1]*Rh[1][3] + ph2[2]*Rh[2][3] + ph2[3]*Rh[3][3]
                    setElementMatrix(obj, {
                        { Rw[1][1], Rw[1][2], Rw[1][3], 0 },
                        { Rw[2][1], Rw[2][2], Rw[2][3], 0 },
                        { Rw[3][1], Rw[3][2], Rw[3][3], 0 },
                        { px, py, pz, 1 },
                    })
                end
            end
        end
    end
end
addEventHandler("onClientPedsProcessed", root, function()
    if USE_BONE_MATRIX then updateHeadMatrices() end
end)

function removeHead(ped)
    local obj = attached[ped]
    if isElement(obj) then destroyElement(obj) end
    attached[ped] = nil
    headInfo[ped] = nil
    if isElement(ped) and setPedHeadless then setPedHeadless(ped, false) end
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
    if USE_BONE_MATRIX then
        headInfo[ped] = head
    else
        exports.bone_attach:attachElementToBone(obj, ped, 2, head.x, head.y, head.z + HEAD_Z_FIX, head.rx, head.ry, head.rz)
    end
    if setPedHeadless then setPedHeadless(ped, true) end
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
    HEAD_Y_FIX = y
    for ped, obj in pairs(attached) do
        if USE_BONE_MATRIX then break end
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
-- Muerto de un disparo en la cabeza (rp_injury): sin cabeza, ni la propia ni la personalizada
local headshotPeds = {}   -- [ped] = true

local function bloodBurst(ped)
    local x, y, z = getPedBonePosition(ped, 8)
    if not x then return end
    for _ = 1, 6 do
        fxAddBlood(x, y, z, (math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.2, 0.4 + math.random() * 0.5, math.random(3, 6), 1.2)
    end
end

local function refreshPlayer(player)
    if getElementData(player, "rp:headshot") then
        removeHead(player)
        if setPedHeadless then setPedHeadless(player, true) end
        if not headshotPeds[player] then bloodBurst(player) end
        headshotPeds[player] = true
        return
    end
    headshotPeds[player] = nil
    local headId = getElementData(player, "rp:head")
    if headId and isElementStreamedIn(player) then
        applyHead(player, headId)
    else
        removeHead(player)
    end
end

addEventHandler("onClientElementDataChange", root, function(key)
    if (key == "rp:head" or key == "rp:headshot") and getElementType(source) == "player" then
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
    headshotPeds[source] = nil
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
    local aiming = (weapon == 34 or weapon == 43) and getPedTask(localPlayer, "secondary", 0) == "TASK_SIMPLE_USE_GUN" or getElementData(localPlayer, "rp:hideBody") == true
    setElementAlpha(obj, aiming and 0 or 255)
end)

-- Oculta la cabeza original del ped en cada frame (tambien durante la pose de
-- selfie con el brazo levantado, que la volvia a mostrar y duplicaba la cabeza).
local function forceHeadless()
    if not setPedHeadless then return end
    for ped, obj in pairs(attached) do
        if isElement(ped) and isElement(obj) then setPedHeadless(ped, true) end
    end
    for ped in pairs(headshotPeds) do
        if isElement(ped) then setPedHeadless(ped, true) else headshotPeds[ped] = nil end
    end
end
addEventHandler("onClientPreRender", root, forceHeadless)
addEventHandler("onClientPedsProcessed", root, forceHeadless)

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
