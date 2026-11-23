--[[
    rp_citizens / c_sync.lua
    Pasajeros y conductor ven el mismo trafico.

    El trafico y los peatones son elementos locales de cada cliente. Si dos jugadores van en el mismo auto,
    el conductor choca con autos que el pasajero no ve. Solucion (la mas barata que funciona):
      - El CONDUCTOR sigue con su poblacion normal y, mientras haya otros jugadores en su vehiculo, envia
        4 veces por segundo una lista de los autos y peatones cercanos (75 m, hasta 12 autos y 10 peatones:
        posicion, rotacion y velocidad). El servidor solo la retransmite a los pasajeros (s_sync.lua).
      - Los PASAJEROS suspenden su propia poblacion y dibujan copias "fantasma" (sin colision ni IA) de lo
        que ve el conductor, interpoladas cada fotograma. Cuestan menos FPS que la poblacion normal.
      - Si el conductor deja de enviar (6 s), el pasajero vuelve a su poblacion local.
    Cambiar de asiento o de conductor se resuelve solo (cada 500 ms se vuelve a decidir el rol).
]]

addEvent("rp:citizens:snapRecv", true)

local mirror = {}            -- [clave] = { kind, el, driver, x, y, z, vx, vy, vz, rx, ry, rz, at }
local active = false         -- soy pasajero de un conductor humano
local fallback = false       -- el conductor no envia: poblacion local mientras tanto
local lastSnapAt = 0
local MAX_MIRROR = 28
local DRIVER_SKINS = { 7, 14, 20, 29, 37, 44, 60, 76, 93, 141 }

local function key(kind, id) return kind * 1000000 + id end

local function angDiff(a, b)
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

local function destroyMirror(m)
    if m.driver and isElement(m.driver) then destroyElement(m.driver) end
    if isElement(m.el) then destroyElement(m.el) end
end

local function clearMirror()
    for _, m in pairs(mirror) do destroyMirror(m) end
    mirror = {}
end

local function create(kind, model, x, y, z, rx, ry, rz)
    if kind == 1 then
        local veh = createVehicle(model, x, y, z, rx, ry, rz)
        if not veh then return nil end
        setElementCollisionsEnabled(veh, false)
        setElementFrozen(veh, true)
        local drv = createPed(DRIVER_SKINS[math.random(#DRIVER_SKINS)], x, y, z + 1)
        if drv then
            setElementCollisionsEnabled(drv, false)
            warpPedIntoVehicle(drv, veh)
        end
        setVehicleEngineState(veh, true)
        return { kind = 1, el = veh, driver = drv }
    end
    local ped = createPed(model, x, y, z, rz)
    if not ped then return nil end
    setElementCollisionsEnabled(ped, false)
    return { kind = 2, el = ped }
end

-- Paquete del conductor: lista plana { tipo, id, modelo, x, y, z, rx, ry, rz, vx, vy, vz, ... }
addEventHandler("rp:citizens:snapRecv", resourceRoot, function(list)
    if not active or type(list) ~= "table" then return end
    local now = getTickCount()
    lastSnapAt = now
    if fallback then
        fallback = false
        setCitizensSuspended(true)
    end
    local seen, count = {}, 0
    for i = 1, #list - 11, 12 do
        if count >= MAX_MIRROR then break end
        local kind, id, model = list[i], list[i + 1], list[i + 2]
        local x, y, z = list[i + 3], list[i + 4], list[i + 5]
        local k = key(kind, id)
        local m = mirror[k] or create(kind, model, x, y, z, list[i + 6], list[i + 7], list[i + 8])
        if m then
            mirror[k] = m
            seen[k] = true
            count = count + 1
            m.x, m.y, m.z = x, y, z
            m.rx, m.ry, m.rz = list[i + 6], list[i + 7], list[i + 8]
            m.vx, m.vy, m.vz = list[i + 9], list[i + 10], list[i + 11]
            m.at = now
        end
    end
    for k, m in pairs(mirror) do
        if not seen[k] then
            destroyMirror(m)
            mirror[k] = nil
        end
    end
end)

-- Copias fantasma: se acercan al ultimo estado conocido con la velocidad extrapolada (hasta 0.6 s)
addEventHandler("onClientPreRender", root, function()
    if not active or fallback or not next(mirror) then return end
    local now = getTickCount()
    for k, m in pairs(mirror) do
        if not isElement(m.el) then
            mirror[k] = nil
        else
            local dt = math.min(0.6, (now - m.at) / 1000)
            local tx, ty, tz = m.x + m.vx * dt * 50, m.y + m.vy * dt * 50, m.z + m.vz * dt * 50
            local cx, cy, cz = getElementPosition(m.el)
            local f = 0.4
            if (tx - cx) ^ 2 + (ty - cy) ^ 2 > 100 then f = 1 end   -- muy lejos: salta
            setElementPosition(m.el, cx + (tx - cx) * f, cy + (ty - cy) * f, cz + (tz - cz) * f)
            local rx, ry, rz = getElementRotation(m.el)
            if m.kind == 1 then
                setElementRotation(m.el, rx + angDiff(m.rx, rx) * f, ry + angDiff(m.ry, ry) * f, rz + angDiff(m.rz, rz) * f)
            else
                setElementRotation(m.el, 0, 0, rz + angDiff(m.rz, rz) * f)
                -- animacion de caminar o correr segun la velocidad
                local sp = math.sqrt(m.vx * m.vx + m.vy * m.vy) * 50
                local moving = sp > 0.6
                setPedControlState(m.el, "forwards", moving)
                setPedControlState(m.el, "walk", moving and sp < 2.6)
                setPedControlState(m.el, "sprint", moving and sp >= 2.6)
            end
        end
    end
end)

----------------------------------------------------------------
-- Rol: pasajero (copias) o conductor (envia). Se decide cada 500 ms.
----------------------------------------------------------------
local function isPassengerOfPlayer()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return false end
    local seat = getPedOccupiedVehicleSeat(localPlayer)
    if not seat or seat == 0 then return false end
    local drv = getVehicleOccupant(veh, 0)
    return isElement(drv) and getElementType(drv) == "player"
end

local function decideRole()
    local want = isPassengerOfPlayer()
    local now = getTickCount()
    if want and not active then
        active, fallback, lastSnapAt = true, false, now
        setCitizensSuspended(true)
    elseif not want and active then
        active, fallback = false, false
        clearMirror()
        setCitizensSuspended(false)
    elseif active and not fallback and now - lastSnapAt > 6000 then
        -- el conductor no envia (sin el recurso, desconectado...): poblacion local mientras tanto
        fallback = true
        clearMirror()
        setCitizensSuspended(false)
    end
end
setTimer(decideRole, 500, 0)

local function broadcast()
    if active then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh or getPedOccupiedVehicleSeat(localPlayer) ~= 0 then return end
    local hasPassenger = false
    for _, occ in pairs(getVehicleOccupants(veh)) do
        if occ ~= localPlayer and getElementType(occ) == "player" then hasPassenger = true break end
    end
    if not hasPassenger then return end
    local x, y = getElementPosition(veh)
    triggerServerEvent("rp:citizens:snap", resourceRoot, getNearbyForSync(x, y, 75, 12, 10))
end
setTimer(broadcast, 250, 0)

addEventHandler("onClientResourceStop", resourceRoot, clearMirror)
