--[[
    rp_gym / s_fixed.lua
    Gimnasios fijos (GYM_FIXED): puerta con marcador en la calle, interior original de GTA SA,
    maquinas en las posiciones del mapa del juego y entrenador. No usan la BD: se crean al arrancar.

    Evento cliente -> servidor (con `client`):
        rp:gym:door (doorId)    entrar o salir; doorId = indice*2-1 (puerta) o indice*2 (salida)
]]

addEvent("rp:gym:door", true)

local doors = {}       -- [doorId] = { gym, inside = bool, x, y, z, int, dim }
local lastDoor = {}    -- [player] = tick

-- Donde se coloca el personaje para que la maquina quede en (x, y, z, rz): inversa de gymSpawnMachine
local function machineRow(id, m, gym)
    local cfg = GYM_KINDS[m.kind]
    local s = cfg.seat or { 0, 0, 0, 0 }
    local rot = m.rz - s[4]
    local a = math.rad(rot)
    local ox = s[1] * math.cos(a) - s[2] * math.sin(a)
    local oy = s[1] * math.sin(a) + s[2] * math.cos(a)
    return { id = id, kind = m.kind, gym = gym.key, native = m.native, fixed = true,
             x = m.x - ox, y = m.y - oy, z = m.z - cfg.zOffset - s[3], rotation = rot,
             interior = gym.interior, dimension = gym.dimension }
end

local function addDoor(id, gym, inside, pos)
    local int, dim = inside and gym.interior or 0, inside and gym.dimension or 0
    local marker = createMarker(pos.x, pos.y, pos.z - 1, "cylinder", 1.2, 245, 165, 36, 120)
    setElementInterior(marker, int)
    setElementDimension(marker, dim)
    exports.rp_markers:setMarkerStyle(marker, inside and { icon = "exit", label = "Salir" } or { icon = "gym", label = gym.name })
    doors[id] = { gym = gym, inside = inside, x = pos.x, y = pos.y, z = pos.z, int = int, dim = dim }

    local label = inside and "Salir a la calle" or ("Entrar: " .. gym.name)
    addEventHandler("onMarkerHit", marker, function(el, sameDim)
        if getElementType(el) == "player" and sameDim and getElementInterior(el) == int and gymCharacter(el) then
            gymNear(el, "door", id, label)
        end
    end)
    addEventHandler("onMarkerLeave", marker, function(el)
        if getElementType(el) == "player" and nearTarget[el] and nearTarget[el][1] == "door" and nearTarget[el][2] == id then
            gymNear(el, false)
        end
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for i, gym in ipairs(GYM_FIXED) do
        createBlip(gym.door.x, gym.door.y, gym.door.z, gym.blip, 2, 255, 255, 255, 255, 0, 400)
        addDoor(i * 2 - 1, gym, false, gym.door)
        addDoor(i * 2, gym, true, gym.exit)
        for j, m in ipairs(gym.machines) do
            if GYM_KINDS[m.kind] then gymSpawnMachine(machineRow(GYM_FIXED_ID + i * 100 + j, m, gym)) end
        end
        local t = gym.trainer
        if t and GYM_STYLES[t.style] then
            gymSpawnTrainer({ id = GYM_FIXED_ID + i * 100, style = t.style, x = t.x, y = t.y, z = t.z, rotation = t.rot,
                              interior = gym.interior, dimension = gym.dimension, fixed = true })
        end
    end
end)

addEventHandler("rp:gym:door", resourceRoot, function(doorId)
    local p = client
    local d = doors[tonumber(doorId) or 0]
    if not d or not gymCharacter(p) then return end
    local now = getTickCount()
    if lastDoor[p] and now - lastDoor[p] < 1000 then return end
    lastDoor[p] = now
    if gymSessionOf(p) or gymInFight[p] or isPedDead(p) or isPedInVehicle(p) or getElementData(p, "rp:downed") then return end
    if getElementInterior(p) ~= d.int or getElementDimension(p) ~= d.dim then return end
    local px, py, pz = getElementPosition(p)
    if getDistanceBetweenPoints3D(px, py, pz, d.x, d.y, d.z) > GYM.USE_RANGE then return end

    local gym = d.gym
    local to = d.inside and gym.outside or gym.inside
    gymNear(p, false)
    setElementInterior(p, d.inside and 0 or gym.interior, to.x, to.y, to.z)
    setElementDimension(p, d.inside and 0 or gym.dimension)
    setElementRotation(p, 0, 0, to.rot)
    setCameraTarget(p, p)
end)

addEventHandler("onPlayerQuit", root, function() lastDoor[source] = nil end)

function gymIsFixedId(id) return (tonumber(id) or 0) >= GYM_FIXED_ID end
