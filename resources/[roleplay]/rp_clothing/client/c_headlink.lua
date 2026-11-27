--[[
    rp_clothing / c_headlink.lua
    Accesorios en la «Cabeza» (hueso 1 de bone_attach) de personajes con cabeza custom (rp_heads).

    Problema: rp_heads pega su objeto cabeza al CUELLO (hueso 2) y queda rigido respecto a el,
    pero el hueso 1 sigue la cabeza de CJ, que la animacion de andar balancea por su cuenta. Quieto
    coinciden; al moverse el accesorio se separa de la cabeza custom y vuelve al pararse.

    Solucion (en cada cliente, para todos los personajes visibles): con el personaje quieto se mide
    una vez la relacion K entre el marco del hueso 1 y el objeto cabeza (K = B1 * H^T). Despues, en
    cada fotograma y DESPUES de bone_attach, el marco del hueso 1 se reconstruye a partir del objeto
    cabeza (B1' = K * H) y el accesorio se recoloca con sus offsets de siempre. Asi va rigido con la
    cabeza custom y los ajustes guardados significan lo mismo (estando quieto el resultado es igual).

    Lo usan los accesorios del servidor (elementData "rp:toy") y las vistas previas del estudio
    (HeadLink.track). El gizmo pide el mismo marco con HeadLink.getFrame para dibujar los ejes.
]]

HeadLink = {}

local HEAD_BONE = 1
local tracked = {}    -- [objeto] = true (vistas previas locales)
local toys = {}       -- [objeto] = true (accesorios del servidor visibles)
local calib = {}      -- [ped] = { head = objeto cabeza, R = 3x3, p = {x,y,z} }
local headOf = {}     -- [ped] = objeto cabeza (cache, se refresca cada poco)

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

local function unit(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 or l ~= l then return nil end
    return { x / l, y / l, z / l }
end

-- Matriz del objeto cabeza sin escala: filas = ejes, p = posicion
local function headFrame(head)
    local m = getElementMatrix(head)
    if not m then return nil end
    local r1, r2, r3 = unit(m[1][1], m[1][2], m[1][3]), unit(m[2][1], m[2][2], m[2][3]), unit(m[3][1], m[3][2], m[3][3])
    if not (r1 and r2 and r3) then return nil end
    return { r1, r2, r3 }, { m[4][1], m[4][2], m[4][3] }
end

----------------------------------------------------------------
-- Calibracion por personaje
----------------------------------------------------------------
local function getHead(ped)
    local h = headOf[ped]
    if h == nil then
        local res = getResourceFromName("rp_heads")
        h = false
        if res and getResourceState(res) == "running" then
            local ok, obj = pcall(function() return exports.rp_heads:getPedHead(ped) end)
            if ok and isElement(obj) then h = obj end
        end
        headOf[ped] = h
    end
    return h and isElement(h) and h or nil
end

local function isRestPose(ped)
    if isPedInVehicle(ped) or isPedDucked(ped) or getPedMoveState(ped) ~= "stand" then return false end
    if getPedTask(ped, "secondary", 0) == "TASK_SIMPLE_USE_GUN" then return false end
    local vx, vy, vz = getElementVelocity(ped)
    return (vx * vx + vy * vy + vz * vz) < 0.0004
end

local function tryCalibrate(ped, head)
    local c = calib[ped]
    if c and c.head == head then return c end
    if not isRestPose(ped) then return nil end
    local bx, by, bz, brx, bry, brz = exports.bone_attach:getBonePositionAndRotation(ped, HEAD_BONE)
    if not bx or bx ~= bx or brx ~= brx then return nil end
    local H, hp = headFrame(head)
    if not H then return nil end
    local B = matrixFromEuler(brx, bry, brz)
    local R = {}   -- K = B * H^T
    for i = 1, 3 do R[i] = { dot(B[i], H[1]), dot(B[i], H[2]), dot(B[i], H[3]) } end
    local d = { bx - hp[1], by - hp[2], bz - hp[3] }
    c = { head = head, R = R, p = { dot(d, H[1]), dot(d, H[2]), dot(d, H[3]) } }
    calib[ped] = c
    return c
end

-- Marco del hueso «Cabeza» pegado a la cabeza custom: origen {x,y,z} y filas B, o nil
function HeadLink.getFrame(ped, bone)
    if bone ~= HEAD_BONE or not isElement(ped) then return nil end
    local head = getHead(ped)
    if not head then return nil end
    local c = tryCalibrate(ped, head)
    if not c then return nil end
    local H, hp = headFrame(head)
    if not H then return nil end
    local B = mul(c.R, H)
    local o = {
        hp[1] + c.p[1] * H[1][1] + c.p[2] * H[2][1] + c.p[3] * H[3][1],
        hp[2] + c.p[1] * H[1][2] + c.p[2] * H[2][2] + c.p[3] * H[3][2],
        hp[3] + c.p[1] * H[1][3] + c.p[2] * H[2][3] + c.p[3] * H[3][3],
    }
    return o, B
end

function HeadLink.track(obj) if isElement(obj) then tracked[obj] = true end end
function HeadLink.untrack(obj) tracked[obj] = nil end

----------------------------------------------------------------
-- Recolocar cada fotograma, despues de bone_attach (prioridad baja)
----------------------------------------------------------------
local function place(obj)
    local ped, bone, x, y, z, rx, ry, rz = exports.bone_attach:getElementBoneAttachmentDetails(obj)
    if not ped or bone ~= HEAD_BONE or not isElementStreamedIn(ped) then return end
    local o, B = HeadLink.getFrame(ped, bone)
    if not o then return end
    local px = o[1] + x * B[1][1] + y * B[2][1] + z * B[3][1]
    local py = o[2] + x * B[1][2] + y * B[2][2] + z * B[3][2]
    local pz = o[3] + x * B[1][3] + y * B[2][3] + z * B[3][3]
    local erx, ery, erz = eulerFromMatrix(mul(matrixFromEuler(rx, ry, rz), B))
    if px == px and py == py and pz == pz and erx == erx and ery == ery and erz == erz then
        setElementPosition(obj, px, py, pz)
        setElementRotation(obj, erx, ery, erz)
    end
end

addEventHandler("onClientPedsProcessed", root, function()
    for obj in pairs(toys) do
        if isElement(obj) then place(obj) else toys[obj] = nil end
    end
    for obj in pairs(tracked) do
        if isElement(obj) then place(obj) else tracked[obj] = nil end
    end
end, true, "low-10")

-- Lista de accesorios visibles y cache de cabezas (cambian poco: cada medio segundo basta)
local function refresh()
    toys = {}
    for _, obj in ipairs(getElementsByType("object", root, true)) do
        if getElementData(obj, "rp:toy") then toys[obj] = true end
    end
    headOf = {}
    for ped, c in pairs(calib) do
        if not isElement(ped) or not isElement(c.head) then calib[ped] = nil end
    end
end
setTimer(refresh, 500, 0)
addEventHandler("onClientResourceStart", resourceRoot, refresh)
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "object" and getElementData(source, "rp:toy") then toys[source] = true end
end)
