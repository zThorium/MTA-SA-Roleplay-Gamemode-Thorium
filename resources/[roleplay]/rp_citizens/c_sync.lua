--[[
    rp_citizens / c_sync.lua
    Pasajeros y conductor ven el mismo trafico.

    El trafico y los peatones son elementos locales de cada cliente. Si dos jugadores van en el mismo auto,
    el conductor choca con autos que el pasajero no ve. Solucion (la mas barata que funciona):
      - El CONDUCTOR sigue con su poblacion normal y, mientras haya otros jugadores en su vehiculo, envia
        4 veces por segundo una lista de los autos y peatones cercanos (75 m, hasta 12 autos y 10 peatones:
        modelo, posicion, rotacion, velocidad y, en autos, colores, skin del conductor, variantes y luces).
        El servidor solo la retransmite a los pasajeros (s_sync.lua).
      - Los PASAJEROS suspenden su propia poblacion y dibujan copias "fantasma" (sin colision ni IA) de lo
        que ve el conductor, interpoladas cada fotograma. Cuestan menos FPS que la poblacion normal.
      - Si el conductor deja de enviar (6 s), el pasajero vuelve a su poblacion local.
    Cambiar de asiento o de conductor se resuelve solo (cada 500 ms se vuelve a decidir el rol).
]]

addEvent("rp:citizens:snapRecv", true)

local STRIDE = 22
local mirror = {}            -- [clave] = { kind, model, el, driver, x, y, z, vx, vy, vz, rx, ry, rz, at, anim }
local active = false         -- soy pasajero de un conductor humano
local mirroring = false      -- ya llego el primer paquete: poblacion local suspendida y copias visibles
local lastSnapAt = 0
local lastDriver = nil
local MAX_MIRROR = 28

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

-- d = campos 13..22 de la entidad (colores, skin del conductor, variantes, luces)
local function create(kind, model, x, y, z, rx, ry, rz, d)
    if kind == 1 then
        local veh = createVehicle(model, x, y, z, rx, ry, rz)
        if not veh then return nil end
        setElementCollisionsEnabled(veh, false)
        setElementFrozen(veh, true)
        setVehicleColor(veh, d[1], d[2], d[3], d[4], d[5], d[6])
        if d[8] and d[8] ~= 255 then setVehicleVariant(veh, d[8], d[9] or 255) end
        setVehicleOverrideLights(veh, d[10] or 0)
        local skin = d[7] and d[7] > 0 and d[7] or 29
        local drv = createPed(skin, x, y, z + 1)
        if drv then
            setElementCollisionsEnabled(drv, false)
            warpPedIntoVehicle(drv, veh)
        end
        setVehicleEngineState(veh, true)
        setElementAlpha(veh, 0)
        if drv then setElementAlpha(drv, 0) end
        return { kind = 1, model = model, el = veh, driver = drv, born = getTickCount() }
    end
    local ped = createPed(model, x, y, z, rz)
    if not ped then return nil end
    setElementCollisionsEnabled(ped, false)
    setElementAlpha(ped, 0)
    return { kind = 2, model = model, el = ped, vx = 0, vy = 0, vz = 0, anim = "idle", born = getTickCount() }
end

-- Paquete del conductor: lista plana de STRIDE numeros por entidad (ver getNearbyForSync)
addEventHandler("rp:citizens:snapRecv", resourceRoot, function(list)
    if not active or type(list) ~= "table" then return end
    local now = getTickCount()
    lastSnapAt = now
    if not mirroring then
        -- primer paquete: la poblacion local se desvanece y aparecen las copias del conductor
        mirroring = true
        setCitizensSuspended(true)
    end
    local seen, count = {}, 0
    for i = 1, #list - (STRIDE - 1), STRIDE do
        if count >= MAX_MIRROR then break end
        local kind, id, model = list[i], list[i + 1], list[i + 2]
        local x, y, z = list[i + 3], list[i + 4], list[i + 5]
        local k = key(kind, id)
        local m = mirror[k]
        -- el mismo id con otro modelo (otro conductor, otro auto): se vuelve a crear
        if m and m.model ~= model then
            destroyMirror(m)
            mirror[k], m = nil, nil
        end
        local d = { list[i + 12], list[i + 13], list[i + 14], list[i + 15], list[i + 16], list[i + 17],
            list[i + 18], list[i + 19], list[i + 20], list[i + 21] }
        m = m or create(kind, model, x, y, z, list[i + 6], list[i + 7], list[i + 8], d)
        if m then
            mirror[k] = m
            seen[k] = true
            count = count + 1
            if kind == 2 then
                -- la velocidad de un peaton no es fiable (anda por controles): se deduce de su avance
                if m.at and now - m.at > 50 then
                    local dt = (now - m.at) / 1000
                    m.vx = m.vx * 0.3 + ((x - m.x) / dt / 50) * 0.7
                    m.vy = m.vy * 0.3 + ((y - m.y) / dt / 50) * 0.7
                    m.vz = 0
                end
            else
                m.vx, m.vy, m.vz = list[i + 9], list[i + 10], list[i + 11]
                -- las luces pueden cambiar (anochece)
                if d[10] then setVehicleOverrideLights(m.el, d[10]) end
            end
            m.x, m.y, m.z = x, y, z
            m.rx, m.ry, m.rz = list[i + 6], list[i + 7], list[i + 8]
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

-- Animacion de un peaton copiado: solo se cambian los controles cuando cambia el estado
local function setPedAnim(m, sp)
    local want = "idle"
    if sp > (m.anim == "idle" and 0.7 or 0.35) then want = sp >= 2.6 and "sprint" or "walk" end
    if want == m.anim then return end
    m.anim = want
    setPedControlState(m.el, "forwards", want ~= "idle")
    setPedControlState(m.el, "walk", want == "walk")
    setPedControlState(m.el, "sprint", want == "sprint")
end

-- Copias fantasma: se acercan al ultimo estado conocido con la velocidad extrapolada (hasta 0.6 s)
addEventHandler("onClientPreRender", root, function()
    if not active or not mirroring or not next(mirror) then return end
    local now = getTickCount()
    for k, m in pairs(mirror) do
        if not isElement(m.el) then
            mirror[k] = nil
        else
            -- aparicion gradual (~0.8 s) en vez de salir de golpe
            if not m.shown then
                local a = math.min(1, (now - m.born) / 800)
                setElementAlpha(m.el, math.floor(255 * a))
                if m.driver and isElement(m.driver) then setElementAlpha(m.driver, math.floor(255 * a)) end
                if a >= 1 then m.shown = true end
            end
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
                setPedAnim(m, math.sqrt(m.vx * m.vx + m.vy * m.vy) * 50)
            end
        end
    end
end)

----------------------------------------------------------------
-- Rol: pasajero (copias) o conductor (envia). Se decide cada 500 ms.
----------------------------------------------------------------
local function currentPassengerDriver()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return nil end
    local seat = getPedOccupiedVehicleSeat(localPlayer)
    if not seat or seat == 0 then return nil end
    local drv = getVehicleOccupant(veh, 0)
    if isElement(drv) and getElementType(drv) == "player" then return drv end
end

-- Al dejar de ser pasajero (bajarse, el conductor deja de enviar): las copias cercanas (< 80 m) pasan a ser
-- autos y peatones reales de la poblacion local, con su posicion y velocidad; las lejanas se retiran.
-- Asi no desaparece de golpe lo que se estaba viendo.
local function handOver()
    local px, py = getElementPosition(localPlayer)
    for _, m in pairs(mirror) do
        local ok = false
        if isElement(m.el) then
            local x, y = getElementPosition(m.el)
            if getDistanceBetweenPoints2D(px, py, x, y) < 80 then
                setElementAlpha(m.el, 255)
                if m.kind == 1 then
                    if m.driver and isElement(m.driver) then
                        setElementAlpha(m.driver, 255)
                        ok = adoptMirrorCar(m.el, m.driver, math.sqrt((m.vx or 0) ^ 2 + (m.vy or 0) ^ 2) * 50)
                    end
                else
                    ok = adoptMirrorPed(m.el)
                end
            end
        end
        if not ok then destroyMirror(m) end
    end
    mirror = {}
end

local function decideRole()
    local drv = currentPassengerDriver()
    local now = getTickCount()
    if drv and not active then
        -- sigue con su poblacion local hasta que llegue el primer paquete del conductor (sin huecos)
        active, mirroring, lastSnapAt, lastDriver = true, false, now, drv
    elseif not drv and active then
        active, lastDriver = false, nil
        if mirroring then
            mirroring = false
            handOver()
            setCitizensSuspended(false)
        end
    elseif drv and drv ~= lastDriver then
        -- cambio de conductor: los ids de la lista anterior ya no valen
        lastDriver = drv
        clearMirror()
    elseif active and mirroring and now - lastSnapAt > 6000 then
        -- el conductor no envia (sin el recurso, desconectado...): se vuelve a la poblacion local
        mirroring = false
        handOver()
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
