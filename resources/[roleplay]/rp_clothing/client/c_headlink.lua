--[[
    rp_clothing / c_headlink.lua
    Accesorios en la «Cabeza» (hueso 1 de bone_attach) de personajes con cabeza custom (rp_heads).

    Problema: rp_heads pega su objeto cabeza al CUELLO (hueso 2) y queda rigido respecto a el,
    pero el hueso 1 sigue la cabeza de CJ, que la animacion de andar balancea por su cuenta. Quieto
    coinciden; al moverse el accesorio se separa de la cabeza custom y vuelve al pararse.

    Solucion: con el personaje quieto se mide una vez la relacion entre el hueso 1 y el hueso 2
    (B1 = K * N, origen o1 = on + p * N). Con ella los offsets guardados (relativos al hueso 1) se
    pasan al hueso 2 y el accesorio se vuelve a pegar con bone_attach al CUELLO, igual que la cabeza.
    Asi lo mueve el mismo codigo y en el mismo momento que la cabeza: va rigido con ella sin
    recolocarlo a mano cada fotograma. Estando quieto el resultado es el mismo que en el hueso 1.

    (Version anterior: cada fotograma leia la matriz del objeto cabeza y recolocaba el accesorio
    encima de bone_attach; provocaba destellos de la cabeza con texturas gigantes.)

    La conversion es solo local (cada cliente); el servidor sigue guardando hueso 1 y sus offsets.
    El gizmo pide el marco del hueso 1 reconstruido con HeadLink.getFrame para dibujar los ejes.
]]

HeadLink = {}

local HEAD_BONE, NECK_BONE = 1, 2
local tracked = {}    -- [objeto] = true (vistas previas locales)
local calib = {}      -- [ped] = { K = 3x3, p = {x,y,z} }

----------------------------------------------------------------
-- Matematica (convencion de bone_attach: matrices por filas)
----------------------------------------------------------------
local function matrixFromEuler(x, y, z)
    x, y, z = math.rad(x), math.rad(y), math.rad(z)
    local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
    return {
        { cy * cz - sy * sx * sz, cy * sz + sy * sx * cz, -sy * cx },
        { -cx * sz, cx * cz, sx },
        { sy * cz + cy * sx * sz, sy * sz - cy * sx * cz, cy * cx },
    }
end

local function eulerFromMatrix(m)
    local x1, y1, z1 = m[1][1], m[1][2], m[1][3]
    local x2, y2, z2 = m[2][1], m[2][2], m[2][3]
    local x3, y3, z3 = m[3][1], m[3][2], m[3][3]
    z2 = math.max(-1, math.min(1, z2))
    local nz3 = math.sqrt(x2 * x2 + y2 * y2)
    if nz3 < 1e-6 then nz3 = 1e-6 end
    local nz1, nz2 = -x2 * z2 / nz3, -y2 * z2 / nz3
    local vx = nz1 * x1 + nz2 * y1 + nz3 * z1
    local vz = nz1 * x3 + nz2 * y3 + nz3 * z3
    return math.deg(math.asin(z2)), -math.deg(math.atan2(vx, vz)), -math.deg(math.atan2(x2, y2))
end

local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

local function mul(a, b)
    local r = {}
    for i = 1, 3 do
        r[i] = {}
        for j = 1, 3 do r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
    end
    return r
end

local function isNum(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or v ~= v then return false end
    end
    return true
end

-- Marco de un hueso de bone_attach: origen {x,y,z} y filas, o nil
local function boneFrame(ped, bone)
    local x, y, z, rx, ry, rz = exports.bone_attach:getBonePositionAndRotation(ped, bone)
    if not isNum(x, y, z, rx, ry, rz) then return nil end
    return { x, y, z }, matrixFromEuler(rx, ry, rz)
end

----------------------------------------------------------------
-- Calibracion por personaje (hueso 1 respecto al hueso 2, en reposo)
----------------------------------------------------------------
local function hasCustomHead(ped)
    local res = getResourceFromName("rp_heads")
    if not res or getResourceState(res) ~= "running" then return false end
    local ok, obj = pcall(function() return exports.rp_heads:getPedHead(ped) end)
    return ok and isElement(obj)
end

local function isRestPose(ped)
    if isPedInVehicle(ped) or isPedDucked(ped) or getPedMoveState(ped) ~= "stand" then return false end
    if getPedTask(ped, "secondary", 0) == "TASK_SIMPLE_USE_GUN" then return false end
    local vx, vy, vz = getElementVelocity(ped)
    return (vx * vx + vy * vy + vz * vz) < 0.0004
end

local function tryCalibrate(ped)
    local c = calib[ped]
    if c then return c end
    if not isElementStreamedIn(ped) or not isRestPose(ped) then return nil end
    local o1, B = boneFrame(ped, HEAD_BONE)
    local on, N = boneFrame(ped, NECK_BONE)
    if not (o1 and on) then return nil end
    local K = {}   -- K = B * N^T
    for i = 1, 3 do K[i] = { dot(B[i], N[1]), dot(B[i], N[2]), dot(B[i], N[3]) } end
    local d = { o1[1] - on[1], o1[2] - on[2], o1[3] - on[3] }
    c = { K = K, p = { dot(d, N[1]), dot(d, N[2]), dot(d, N[3]) } }
    calib[ped] = c
    return c
end

-- Marco del hueso «Cabeza» reconstruido desde el cuello: origen {x,y,z} y filas B, o nil (gizmo)
function HeadLink.getFrame(ped, bone)
    if bone ~= HEAD_BONE or not isElement(ped) or not hasCustomHead(ped) then return nil end
    local c = tryCalibrate(ped)
    if not c then return nil end
    local on, N = boneFrame(ped, NECK_BONE)
    if not on then return nil end
    local p = c.p
    local o = {
        on[1] + p[1] * N[1][1] + p[2] * N[2][1] + p[3] * N[3][1],
        on[2] + p[1] * N[1][2] + p[2] * N[2][2] + p[3] * N[3][2],
        on[3] + p[1] * N[1][3] + p[2] * N[2][3] + p[3] * N[3][3],
    }
    return o, mul(c.K, N)
end

----------------------------------------------------------------
-- Pasar un accesorio del hueso 1 al cuello (solo si su dueno lleva cabeza custom)
----------------------------------------------------------------
function HeadLink.relink(obj)
    if not isElement(obj) then return false end
    local ped, bone, x, y, z, rx, ry, rz = exports.bone_attach:getElementBoneAttachmentDetails(obj)
    if not ped or bone ~= HEAD_BONE or not isElement(ped) or not hasCustomHead(ped) then return false end
    local c = tryCalibrate(ped)
    if not c then return false end
    local K, p = c.K, c.p
    local nx = p[1] + x * K[1][1] + y * K[2][1] + z * K[3][1]
    local ny = p[2] + x * K[1][2] + y * K[2][2] + z * K[3][2]
    local nz = p[3] + x * K[1][3] + y * K[2][3] + z * K[3][3]
    local erx, ery, erz = eulerFromMatrix(mul(matrixFromEuler(rx, ry, rz), K))
    if not isNum(nx, ny, nz, erx, ery, erz) then return false end
    return exports.bone_attach:attachElementToBone(obj, ped, NECK_BONE, nx, ny, nz, erx, ery, erz)
end

function HeadLink.track(obj) if isElement(obj) then tracked[obj] = true end end
function HeadLink.untrack(obj) tracked[obj] = nil end

-- Revisa los accesorios visibles (y las vistas previas) cada medio segundo: los que el servidor
-- acaba de (re)pegar al hueso 1 o los de personajes que aun no se habian calibrado.
local function refresh()
    for _, obj in ipairs(getElementsByType("object", root, true)) do
        if getElementData(obj, "rp:toy") then HeadLink.relink(obj) end
    end
    for obj in pairs(tracked) do
        if isElement(obj) then HeadLink.relink(obj) else tracked[obj] = nil end
    end
    for ped in pairs(calib) do
        if not isElement(ped) or not isElementStreamedIn(ped) then calib[ped] = nil end
    end
end
setTimer(refresh, 500, 0)
addEventHandler("onClientResourceStart", resourceRoot, refresh)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "object" and getElementData(source, "rp:toy") then HeadLink.relink(source) end
end)

----------------------------------------------------------------
-- Camara pegada al personaje: cuando choca con una pared o un poste, GTA deja de dibujar el cuerpo
-- del jugador local, pero los accesorios son objetos aparte y se veian enormes delante de la camara
-- por un instante. Se ocultan los propios mientras la camara esta a menos de CAMERA_NEAR de la cabeza
-- (lo mismo hace rp_heads con la cabeza custom). Solo se toca el alfa al cambiar de estado.
----------------------------------------------------------------
local CAMERA_NEAR = 0.6
local hiddenByCamera = {}   -- [objeto] = true (ocultos por la camara)
local cameraNear = false

local function cameraNearHead()
    local cx, cy, cz = getCameraMatrix()
    local hx, hy, hz = getPedBonePosition(localPlayer, 8)
    if not (cx and hx) then return false end
    local dx, dy, dz = cx - hx, cy - hy, cz - hz
    return dx * dx + dy * dy + dz * dz < CAMERA_NEAR * CAMERA_NEAR
end

local function showHiddenToys()
    for obj in pairs(hiddenByCamera) do
        if isElement(obj) then setElementAlpha(obj, 255) end
    end
    hiddenByCamera = {}
end

addEventHandler("onClientPedsProcessed", root, function()
    local near = not isStudioOpen() and cameraNearHead()
    if near == cameraNear then return end
    cameraNear = near
    if not near then return showHiddenToys() end
    for _, obj in ipairs(getElementsByType("object", root, true)) do
        if getElementData(obj, "rp:toy") and getElementAlpha(obj) > 0
            and exports.bone_attach:getElementBoneAttachmentDetails(obj) == localPlayer then
            setElementAlpha(obj, 0)
            hiddenByCamera[obj] = true
        end
    end
end)
addEventHandler("onClientResourceStop", resourceRoot, showHiddenToys)

-- El servidor vuelve a pegar el accesorio al hueso 1 al guardarlo: convertirlo enseguida
-- (prioridad baja: despues del handler de bone_attach que guarda los datos nuevos)
addEvent("boneAttach_attach", true)   -- ya lo crea bone_attach; por si arranca despues
addEventHandler("boneAttach_attach", root, function(element)
    if isElement(element) and getElementData(element, "rp:toy") then HeadLink.relink(element) end
end, true, "low-10")
