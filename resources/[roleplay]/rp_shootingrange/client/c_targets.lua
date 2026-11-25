--[[
    rp_shootingrange / c_targets.lua  (cliente)
    Blancos de la ronda: peds locales (solo los ve este jugador). Solo dibujan; los impactos los
    decide el servidor (rp:range:hit). La posicion sale de rangeTargetState, igual que en el servidor.
]]
local entries = {}      -- [id] = { ped, def, visible, dead, hiddenUntil }
local roundStart = nil  -- getTickCount() en el que empieza la ronda (ya incluye la cuenta atras)

function rangeTargetsClear()
    for _, e in pairs(entries) do if isElement(e.ped) then destroyElement(e.ped) end end
    entries, roundStart = {}, nil
end

function rangeTargetsStart(targets, delayMs)
    rangeTargetsClear()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    for _, t in ipairs(targets) do
        local x, y, z = rangeWorldPos(t.d or t.d0, t.l or 0)
        local ped = createPed(RANGE.TARGET_SKIN, x, y, z + 1.0, RANGE.FIRE.rot + 180)
        if ped then
            setElementDimension(ped, dim)
            setElementInterior(ped, int)
            setElementFrozen(ped, true)
            setElementAlpha(ped, 0)
            setElementCollisionsEnabled(ped, false)
            addEventHandler("onClientPedDamage", ped, function() cancelEvent() end)
            entries[t.id] = { ped = ped, def = t, visible = false }
        end
    end
    roundStart = getTickCount() + delayMs
end

function rangeTargetsHit(id, rearmMs)
    local e = entries[id]
    if not e then return end
    if rearmMs > 0 then e.hiddenUntil = getTickCount() + rearmMs else e.dead = true end
end

addEventHandler("onClientRender", root, function()
    if not roundStart then return end
    local now = getTickCount()
    local el = now - roundStart
    for _, e in pairs(entries) do
        if isElement(e.ped) then
            local active, d, l = rangeTargetState(e.def, el)
            if e.dead or (e.hiddenUntil and now < e.hiddenUntil) then active = false end
            if active then
                local x, y, z = rangeWorldPos(d, l)
                setElementPosition(e.ped, x, y, z + 1.0)
            end
            if active ~= e.visible then
                e.visible = active
                setElementAlpha(e.ped, active and 255 or 0)
                setElementCollisionsEnabled(e.ped, active)
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, rangeTargetsClear)
