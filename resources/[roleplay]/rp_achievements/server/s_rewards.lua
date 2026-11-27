--[[
    rp_achievements / s_rewards.lua  (servidor)

    Panel y hitos. El cliente solo pide; aquí se revalida todo:
      rp:achievements:request          abrir el panel (/logros o la app del teléfono)
      rp:achievements:claim (n)        reclamar el hito n

    Reclamo atómico: se comprueba en memoria (puntos, no reclamado, que quepan los items) y
    luego INSERT IGNORE en character_achievement_milestones. Solo si inserta la fila
    (affectedRows == 1) se entrega: dinero al banco + bank_transactions, XP e items.
    Dos clics seguidos o dos servidores de juego no pueden cobrar el mismo hito dos veces.
]]

addEvent("rp:achievements:request", true)
addEvent("rp:achievements:claim", true)
addEvent("rp:achievements:statusRequest", true)   -- el cliente arranca (p. ej. tras un restart) y pide el globo del HUD

local lastStatus = {}
addEventHandler("rp:achievements:statusRequest", resourceRoot, function()
    local p = client
    local s = Achievements.get(p)
    if not s or not s.loaded then return end      -- al terminar de cargar ya se le manda
    local now = getTickCount()
    if lastStatus[p] and now - lastStatus[p] < 2000 then return end
    lastStatus[p] = now
    triggerClientEvent(p, "rp:achievements:status", resourceRoot, #Achievements.readyMilestones(s), 0)
end)

local lastPanel, lastClaim, claiming = {}, {}, {}

local function notify(p, text, kind, ms) exports.rp_notify:notify(p, text, kind or "info", ms) end
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function sendPanel(p, s, open)
    local snap = Achievements.snapshot(s)
    snap.ready = #Achievements.readyMilestones(s, snap.points)   -- para el globo de la ficha del HUD
    triggerClientEvent(p, "rp:achievements:panel", resourceRoot, snap, open and true or false)
end

addEventHandler("rp:achievements:request", resourceRoot, function()
    local p = client
    local s = Achievements.get(p)
    if not s then return end
    if not s.loaded then return notify(p, "Tus logros aún se están cargando. Prueba en un momento.", "warning") end
    local now = getTickCount()
    if lastPanel[p] and now - lastPanel[p] < ACH.PANEL_COOLDOWN then return end
    lastPanel[p] = now
    sendPanel(p, s, true)
end)

-- ¿Caben todos los items del hito? Devuelve true o false, nombre del item
local function itemsFit(p, m)
    if not m.items then return true end
    for _, it in ipairs(m.items) do
        local ok = exports.rp_inventory:canCarry(p, it[1], it[2])
        if not ok then
            local def = exports.rp_inventory:getItemDefinition(it[1])
            return false, def and def.name or it[1]
        end
    end
    return true
end

local function deliver(p, s, index, m)
    local parts = {}
    if (m.bank or 0) > 0 then
        local db = Achievements.db()
        dbExec(db, "UPDATE characters SET bank_money = bank_money + ? WHERE id = ?", m.bank, s.characterId)
        dbExec(db, "INSERT INTO bank_transactions (character_id, type, amount, other_name) VALUES (?, 'reward', ?, ?)",
            s.characterId, m.bank, ACH.BANK_CONCEPT)
        parts[#parts + 1] = "$" .. ACH.fmt(m.bank) .. " al banco"
    end
    if (m.xp or 0) > 0 and running("rp_levels") then
        exports.rp_levels:giveXP(p, m.xp, "logros")
        parts[#parts + 1] = ACH.fmt(m.xp) .. " XP"
    end
    for _, it in ipairs(m.items or {}) do
        local ok = exports.rp_inventory:giveItem(p, it[1], it[2])
        local def = exports.rp_inventory:getItemDefinition(it[1])
        if ok then parts[#parts + 1] = ("%dx %s"):format(it[2], def and def.name or it[1])
        else Achievements.log(("no se pudo entregar %s a %s (hito %d)"):format(it[1], getPlayerName(p), index), 1) end
    end
    if m.cosmetic then parts[#parts + 1] = m.cosmetic end
    exports.rp_notify:popup(p, ("Recompensa de logros %d"):format(index), table.concat(parts, " · "), "success", 7000)
    Achievements.log(("%s reclamó el hito %d (%d puntos)"):format(getPlayerName(p), index, m.points))
end

addEventHandler("rp:achievements:claim", resourceRoot, function(index)
    local p = client
    local s = Achievements.get(p)
    if not s or not s.loaded or claiming[p] then return end
    local now = getTickCount()
    if lastClaim[p] and now - lastClaim[p] < ACH.CLAIM_COOLDOWN then return end
    lastClaim[p] = now

    index = math.floor(tonumber(index) or 0)
    local m = ACH.MILESTONES[index]
    if not m then return end
    if s.claimed[index] then return notify(p, "Ya reclamaste esta recompensa.", "warning") end
    if Achievements.points(s) < m.points then
        return notify(p, ("Necesitas %s puntos de logro para esta recompensa."):format(ACH.fmt(m.points)), "error")
    end
    local fits, itemName = itemsFit(p, m)
    if not fits then
        triggerClientEvent(p, "rp:achievements:claimed", resourceRoot, index, false)
        return notify(p, ("No te cabe %s en el inventario. Haz sitio y vuelve a reclamar."):format(itemName), "error", 7000)
    end

    claiming[p] = true
    local characterId = s.characterId
    dbQuery(function(qh)
        local _, affected = dbPoll(qh, 0)
        claiming[p] = nil
        if not isElement(p) or Achievements.get(p) ~= s then return end
        if not affected or affected < 1 then
            s.claimed[index] = true     -- ya estaba reclamado en la BD
            sendPanel(p, s, false)
            return notify(p, "Ya reclamaste esta recompensa.", "warning")
        end
        s.claimed[index] = true
        deliver(p, s, index, m)
        triggerClientEvent(p, "rp:achievements:claimed", resourceRoot, index, true)
        sendPanel(p, s, false)
    end, Achievements.db(), "INSERT IGNORE INTO character_achievement_milestones (character_id, milestone) VALUES (?, ?)",
        characterId, index)
end)

addEventHandler("onPlayerQuit", root, function()
    lastPanel[source], lastClaim[source], claiming[source], lastStatus[source] = nil, nil, nil, nil
end)

-- /logros también desde el servidor (por si el cliente aún no cargó el script)
addCommandHandler(ACH.COMMAND, function(p)
    local s = Achievements.get(p)
    if not s then return end
    if not s.loaded then return notify(p, "Tus logros aún se están cargando. Prueba en un momento.", "warning") end
    sendPanel(p, s, true)
end)
