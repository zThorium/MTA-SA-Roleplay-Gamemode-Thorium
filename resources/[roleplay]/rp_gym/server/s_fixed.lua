--[[
    rp_gym / s_fixed.lua
    Gimnasios fijos (GYM_FIXED): puerta con marcador en la calle, interior original de GTA SA (sin sus
    maquinas: las crean los admins) y entrenador con ring. No usan la BD: se crean al arrancar.

    Evento cliente -> servidor (con `client`):
        rp:gym:door (doorId)    entrar o salir; doorId = indice*2-1 (puerta) o indice*2 (salida)
]]

addEvent("rp:gym:door", true)

local doors = {}       -- [doorId] = { gym, inside = bool, x, y, z, int, dim }
local lastDoor = {}    -- [player] = tick

-- Quita (o devuelve) las maquinas que trae el interior original: las crean los admins con /crearmaquina
local function originalMachines(gym, remove)
    local r = gym.removeModels
    if not r then return end
    for _, model in ipairs(r.models) do
        if remove then
            removeWorldModel(model, r.radius, r.x, r.y, r.z, gym.interior)
        else
            restoreWorldModel(model, r.radius, r.x, r.y, r.z, gym.interior)
        end
    end
end

addEventHandler("onResourceStop", resourceRoot, function()
    for _, gym in ipairs(GYM_FIXED) do originalMachines(gym, false) end
end)

-- Posicion efectiva de una puerta (la de GYM_FIXED o la que movio un admin, rp_markers).
-- `follow` (donde apareces al cruzarla) se desplaza lo mismo que la puerta.
local function place(p, key, follow)
    p.base = p.base or { p.x, p.y, p.z }
    local ok, x, y, z = pcall(function() return exports.rp_markers:placePoint(key, p.base[1], p.base[2], p.base[3]) end)
    if not (ok and x) then x, y, z = p.base[1], p.base[2], p.base[3] end
    p.x, p.y, p.z = x, y, z
    if follow then
        follow.base = follow.base or { follow.x, follow.y, follow.z }
        follow.x, follow.y, follow.z = follow.base[1] + x - p.base[1], follow.base[2] + y - p.base[2], follow.base[3] + z - p.base[3]
    end
end

local function addDoor(id, gym, inside, pos)
    local old = doors[id]
    if old and isElement(old.marker) then destroyElement(old.marker) end
    local int, dim = inside and gym.interior or 0, inside and gym.dimension or 0
    local marker = createMarker(pos.x, pos.y, pos.z - 1, "cylinder", 1.2, 245, 165, 36, 120)
    setElementInterior(marker, int)
    setElementDimension(marker, dim)
    exports.rp_markers:setMarkerStyle(marker, inside and { icon = "exit", label = "Salir" } or { icon = "gym", label = gym.name })
    exports.rp_markers:registerMarker(marker, (inside and "exit" or "door") .. gym.key,
        { label = gym.name .. (inside and " · salida" or " · puerta"), point = { pos.x, pos.y, pos.z } })
    doors[id] = { gym = gym, inside = inside, x = pos.x, y = pos.y, z = pos.z, int = int, dim = dim, marker = marker }

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

local function spawnDoors(i, gym)
    place(gym.door, "door" .. gym.key, gym.outside)
    place(gym.exit, "exit" .. gym.key, gym.inside)
    if isElement(gym.blipEl) then destroyElement(gym.blipEl) end
    gym.blipEl = createBlip(gym.door.x, gym.door.y, gym.door.z, gym.blip, 2, 255, 255, 255, 255, 0, 400)
    addDoor(i * 2 - 1, gym, false, gym.door)
    addDoor(i * 2, gym, true, gym.exit)
end

-- Un admin movio una puerta con el editor (rp_admin): rehacer las de ese gimnasio
addEvent("rp:markers:moved")
addEventHandler("rp:markers:moved", root, function(owner, key)
    if owner ~= getResourceName(resource) then return end
    for i, gym in ipairs(GYM_FIXED) do
        if key == "door" .. gym.key or key == "exit" .. gym.key then spawnDoors(i, gym) end
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for i, gym in ipairs(GYM_FIXED) do
        spawnDoors(i, gym)
        originalMachines(gym, true)
        local t = gym.trainer
        if t and GYM_STYLES[t.style] then
            gymSpawnTrainer({ id = GYM_FIXED_ID + i * 100, style = t.style, x = t.x, y = t.y, z = t.z, rotation = t.rot,
                              interior = gym.interior, dimension = gym.dimension, ring = t.ring })
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
