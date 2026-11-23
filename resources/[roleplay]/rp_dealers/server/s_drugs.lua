--[[
    rp_dealers / s_drugs.lua
    Efectos de las drogas. rp_inventory avisa con el evento rp:onDrugUsed (source = jugador,
    argumento = "weed" | "cocaine" | "lsd") despues de gastar el item. Aqui se lleva la
    cuenta de dosis recientes (sobredosis) y se manda el efecto visual al cliente
    (client/c_effects.lua). Al terminar el efecto se aplica el "bajon" en rp_needs.

    Sobredosis: cada droga suma DRUGS[x].dose puntos, que bajan 1 cada DOSE_DECAY_MS.
    Si llegan a DRUGS.OD_LIMIT, el personaje cae casi muerto (vida 15) y pierde los efectos.
]]

addEvent("rp:onDrugUsed", false)

local doses = {}    -- [player] = { points, tick }
local token = {}    -- [player] = n: invalida el bajon si el jugador murio o uso otra dosis despues

local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end

local function currentPoints(player)
    local d = doses[player] or { points = 0, tick = getTickCount() }
    local now = getTickCount()
    d.points = math.max(0, d.points - math.floor((now - d.tick) / DRUGS.DOSE_DECAY_MS))
    d.tick = now
    doses[player] = d
    return d
end

local function clearEffects(player)
    token[player] = (token[player] or 0) + 1
    if isElement(player) then triggerClientEvent(player, "rp:drugs:stop", resourceRoot) end
end

addEventHandler("rp:onDrugUsed", root, function(kind)
    local player, def = source, DRUGS[kind]
    if getElementType(player) ~= "player" or type(def) ~= "table" then return end

    local d = currentPoints(player)
    d.points = d.points + def.dose
    if d.points >= DRUGS.OD_LIMIT then
        d.points = 0
        clearEffects(player)
        setElementHealth(player, math.min(getElementHealth(player), 15))
        triggerClientEvent(player, "rp:drugs:overdose", resourceRoot)
        notify(player, "Sobredosis. Mezclaste demasiado y tu cuerpo no aguanta: necesitas un medico.", "error")
        outputServerLog(("[rp_dealers] %s tuvo una sobredosis (%s)"):format(getPlayerName(player), kind))
        return
    end

    if kind == "weed" and not isPedInVehicle(player) then
        setPedAnimation(player, "smoking", "M_smk_drag", 3000, false, false, false, false)
    end
    triggerClientEvent(player, "rp:drugs:start", resourceRoot, kind, def.ms)

    token[player] = (token[player] or 0) + 1
    local mine = token[player]
    setTimer(function()
        if not isElement(player) or token[player] ~= mine then return end
        for need, amount in pairs(def.crash or {}) do
            pcall(function() exports.rp_needs:addNeed(player, need, amount) end)
        end
        notify(player, "Se te pasa el efecto y notas el bajon.", "warning")
    end, def.ms, 1)
end)

-- Morir o reaparecer corta los efectos
addEventHandler("onPlayerWasted", root, function() doses[source] = nil clearEffects(source) end)
addEventHandler("onPlayerSpawn", root, function() clearEffects(source) end)
addEventHandler("onPlayerQuit", root, function() doses[source], token[source] = nil, nil end)
