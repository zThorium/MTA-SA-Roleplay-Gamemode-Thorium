--[[
    rp_mapeditor / s_spawn.lua
    Crea los elementos de una fila (borrador y mapa publicado usan lo mismo).

    meBuild(row, interior, dimension, projectName, draft) -> elemento | nil
        En el borrador todo queda congelado e invulnerable y lleva "rp:me:id" para que el editor lo elija.
        Los puntos y los quitados no crean elemento (los dibuja el cliente / se aplican aparte).
    meApplyRemoval(row, interior) / meRestoreRemoval(row, interior)
]]

local function setCommon(el, row, interior, dimension, projectName, draft)
    setElementInterior(el, interior)
    setElementDimension(el, dimension)
    setElementData(el, "rp:mapedit", draft and (projectName .. " (borrador)") or projectName)
    if draft then setElementData(el, "rp:me:id", row.id) end
end

local BUILDERS = {}

BUILDERS.object = function(row, draft)
    local p = row.props
    local o = createObject(row.model, row.x, row.y, row.z, row.rx, row.ry, row.rz)
    if not o then return end
    if p.scale then setObjectScale(o, p.scale[1], p.scale[2], p.scale[3]) end
    if p.alpha then setElementAlpha(o, p.alpha) end
    if p.col == false then setElementCollisionsEnabled(o, false) end
    if p.ds then setElementDoubleSided(o, true) end
    setElementFrozen(o, draft or p.frozen ~= false)
    if p.brk then setElementData(o, "rp:me:brk", true) end
    return o
end

BUILDERS.vehicle = function(row, draft)
    local p = row.props
    local v = createVehicle(row.model, row.x, row.y, row.z, row.rx, row.ry, row.rz, p.plate)
    if not v then return end
    if p.color then setVehicleColor(v, p.color[1], p.color[2], p.color[3], p.color[4], p.color[5], p.color[6]) end
    for _, u in ipairs(p.upg or {}) do addVehicleUpgrade(v, u) end
    if p.paintjob then setVehiclePaintjob(v, p.paintjob) end
    setVehicleLocked(v, draft or p.locked ~= false)
    setVehicleEngineState(v, p.engine == true)
    if p.lights then setVehicleOverrideLights(v, 2) end
    if p.sirens then setVehicleSirensOn(v, true) end
    setVehicleDamageProof(v, true)
    setElementFrozen(v, draft or p.frozen ~= false)
    setElementData(v, "rp:me:deco", true)
    return v
end

BUILDERS.ped = function(row, draft)
    local p = row.props
    local ped = createPed(row.model, row.x, row.y, row.z, row.rz)
    if not ped then return end
    setElementFrozen(ped, draft or p.frozen ~= false)
    if p.block then setElementData(ped, "rp:me:anim", { p.block, p.anim }) end
    setElementData(ped, "rp:me:deco", true)
    return ped
end

BUILDERS.marker = function(row)
    local p = row.props
    local c = p.color or { 255, 200, 60, 160 }
    local m = createMarker(row.x, row.y, row.z, p.mtype or "cylinder", p.size or 1.5, c[1], c[2], c[3], c[4])
    if not m then return end
    pcall(function() exports.rp_markers:setMarkerStyle(m, { icon = p.icon, label = p.label }) end)
    return m
end

BUILDERS.pickup = function(row)
    local p = row.props
    local pk
    if p.ptype == 2 then
        pk = createPickup(row.x, row.y, row.z, 2, p.amount, p.respawn, p.ammo)
    else
        pk = createPickup(row.x, row.y, row.z, p.ptype, p.amount, p.respawn)
    end
    return pk or nil
end

function meBuild(row, interior, dimension, projectName, draft)
    local fn = BUILDERS[row.etype]
    if not fn then return nil end
    local ok, el = pcall(fn, row, draft)
    if not ok or not isElement(el) then
        outputDebugString(("[rp_mapeditor] No se pudo crear %s #%s (modelo %s): %s"):format(
            row.etype, tostring(row.id), tostring(row.model), tostring(el)), 2)
        return nil
    end
    setCommon(el, row, interior, dimension, projectName, draft)
    return el
end

function meApplyRemoval(row, interior)
    local p = row.props
    removeWorldModel(row.model, p.radius or 1, row.x, row.y, row.z, interior or 0)
    if p.lod and p.lod > 0 then removeWorldModel(p.lod, p.radius or 1, row.x, row.y, row.z, interior or 0) end
end

function meRestoreRemoval(row, interior)
    local p = row.props
    restoreWorldModel(row.model, p.radius or 1, row.x, row.y, row.z, interior or 0)
    if p.lod and p.lod > 0 then restoreWorldModel(p.lod, p.radius or 1, row.x, row.y, row.z, interior or 0) end
end
