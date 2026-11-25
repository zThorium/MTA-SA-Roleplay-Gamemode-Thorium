--[[
    rp_shootingrange / c_targets.lua  (cliente)
    Blancos de la ronda: peds locales (solo los ve este jugador). Cuando una bala del jugador toca un
    blanco, GTA dice en que parte del cuerpo (onClientPedDamage) y se informa al servidor, que lo valida
    contra un disparo real y decide (rp:range:hit). La posicion sale de rangeTargetState, igual que en el servidor.
]]
local entries = {}      -- [id] = { ped, def, visible, dead, hiddenUntil, lastReport }
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
        local skins = RANGE.TARGET_SKINS
        local ped = createPed(skins[math.random(#skins)], x, y, z + 1.0, RANGE.FIRE.rot + 180)
        if ped then
            setElementDimension(ped, dim)
            setElementInterior(ped, int)
            setElementFrozen(ped, true)
            setElementAlpha(ped, 0)
            setElementCollisionsEnabled(ped, false)
            local entry = { ped = ped, def = t, visible = false }
            addEventHandler("onClientPedDamage", ped, function(attacker, _, bodypart)
                cancelEvent()
                if attacker ~= localPlayer or not entry.visible or entry.dead then return end
                -- Una escopeta da varios perdigones al mismo blanco: un aviso por disparo como mucho
                local now = getTickCount()
                if entry.lastReport and now - entry.lastReport < 120 then return end
                entry.lastReport = now
                triggerServerEvent("rp:range:hitReport", resourceRoot, t.id, bodypart)
            end)
            entries[t.id] = entry
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
