--[[
    rp_achievements / s_admin.lua  (servidor)

    Comandos de admin (catálogo en rp_adminpanel/server/s_catalog.lua). Todo queda en
    server.log y en admin_log.
        /verlogros <id>                       (nivel 1) puntos, medallas e hitos de un jugador
        /darlogro <id> <clave> [medalla]      (nivel 2) da la medalla 1-4 de un logro (por defecto, la máxima)
        /statlogro <id> <estadística> <valor> (nivel 2) fija una estadística (puede bajarla; las medallas no se quitan)
        /resetlogros <id> [confirmar]         (nivel 2) borra estadísticas, medallas e hitos del personaje
]]

local resetAsk = {}   -- [admin] = { target, until }

local function notify(p, text, kind, ms) exports.rp_notify:notify(p, text, kind or "info", ms) end
local function level(p) return exports.rp_login:getPlayerAdminLevel(p) or 0 end
local function dname(p) return (getPlayerName(p):gsub("_", " ")) end

local function adminLog(admin, command, target, details)
    outputServerLog(("[rp_achievements] %s /%s -> %s | %s"):format(getPlayerName(admin), command,
        target and getPlayerName(target) or "-", details or ""))
    dbExec(Achievements.db(), [[INSERT INTO admin_log (admin_account_id, admin_name, command, target_account_id,
        target_character_id, target_name, details)
        VALUES (NULLIF(?, 0), ?, ?, NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, ''), NULLIF(?, ''))]],
        exports.rp_login:getPlayerAccountId(admin) or 0, getPlayerName(admin), command,
        target and exports.rp_login:getPlayerAccountId(target) or 0,
        target and exports.rp_characters:getPlayerCharacterId(target) or 0,
        target and getPlayerName(target) or "", (details or ""):sub(1, 255))
end

-- Devuelve jugador y estado cargado, o avisa al admin
local function targetOf(admin, query, usage)
    local t = query and exports.rp_ids:findPlayer(query)
    if not t then notify(admin, usage, "warning") return nil end
    local s = Achievements.get(t)
    if not s or not s.loaded then notify(admin, "Ese jugador no tiene personaje en juego o sus logros no han cargado.", "error") return nil end
    return t, s
end

addCommandHandler("verlogros", function(admin, _, query)
    if level(admin) < 1 then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local t, s = targetOf(admin, query, "Uso: /verlogros <id o nombre>")
    if not t then return end
    local counts = { 0, 0, 0, 0 }
    for key, tier in pairs(s.tiers) do
        local a = ACH.BY_KEY[key]
        local medal = ACH.medalOf(a, tier)
        if medal then counts[medal] = counts[medal] + 1 end
    end
    local claimed = 0
    for _ in pairs(s.claimed) do claimed = claimed + 1 end
    outputChatBox(("[Logros] %s: %d puntos · %d bronce, %d plata, %d oro, %d platino · hitos reclamados %d/%d · por reclamar %d"):format(
        dname(t), Achievements.points(s), counts[1], counts[2], counts[3], counts[4], claimed, #ACH.MILESTONES,
        #Achievements.readyMilestones(s)), admin, 255, 196, 64)
end)

addCommandHandler("darlogro", function(admin, _, query, key, tier)
    if level(admin) < 2 then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local usage = "Uso: /darlogro <id o nombre> <clave> [medalla 1-4]. Claves en /logros o docs/LOGROS.md"
    local t, s = targetOf(admin, query, usage)
    if not t then return end
    local a = key and ACH.BY_KEY[key]
    if not a then return notify(admin, "Ese logro no existe. " .. usage, "error") end
    tier = math.floor(tonumber(tier) or #a.tiers)
    if tier < 1 or tier > #a.tiers then return notify(admin, ("%s tiene %d medallas."):format(a.name, #a.tiers), "error") end
    if (s.tiers[a.key] or 0) >= tier then return notify(admin, "Ya tiene esa medalla o una mayor.", "warning") end
    -- La estadística sube al umbral para que el panel cuadre con la medalla
    if (s.stats[a.stat] or 0) < a.tiers[tier] then s.stats[a.stat] = a.tiers[tier]; s.dirty[a.stat] = true end
    unlock(t, a.key, tier)
    Achievements.flush(s)
    adminLog(admin, "darlogro", t, ("%s medalla %d"):format(a.key, tier))
    notify(admin, ("Diste %s (%s) a %s."):format(a.name, ACH.MEDALS[ACH.medalOf(a, tier)].name, dname(t)), "success")
end)

addCommandHandler("statlogro", function(admin, _, query, stat, value)
    if level(admin) < 2 then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local usage = "Uso: /statlogro <id o nombre> <estadística> <valor>"
    local t = targetOf(admin, query, usage)
    if not t then return end
    if not stat or not ACH.STATS[stat] then return notify(admin, "Esa estadística no existe. " .. usage, "error") end
    value = math.floor(tonumber(value) or -1)
    if value < 0 then return notify(admin, usage, "warning") end
    setStat(t, stat, value)
    Achievements.flush(Achievements.get(t))
    adminLog(admin, "statlogro", t, ("%s = %d"):format(stat, value))
    notify(admin, ("%s de %s queda en %s."):format(stat, dname(t), ACH.fmt(value)), "success")
end)

addCommandHandler("resetlogros", function(admin, _, query, confirm)
    if level(admin) < 2 then return notify(admin, "No tienes permiso para usar este comando.", "error") end
    local t, s = targetOf(admin, query, "Uso: /resetlogros <id o nombre>")
    if not t then return end
    local ask = resetAsk[admin]
    if confirm ~= "confirmar" or not ask or ask.target ~= t or getTickCount() > ask.untilTick then
        resetAsk[admin] = { target = t, untilTick = getTickCount() + 20000 }
        return notify(admin, ("Esto borra TODOS los logros de %s. Repite con /resetlogros %s confirmar (20 s)."):format(dname(t), query), "warning", 10000)
    end
    resetAsk[admin] = nil
    local cid = s.characterId
    local db = Achievements.db()
    dbExec(db, "DELETE FROM character_achievement_stats WHERE character_id = ?", cid)
    dbExec(db, "DELETE FROM character_achievements WHERE character_id = ?", cid)
    dbExec(db, "DELETE FROM character_achievement_milestones WHERE character_id = ?", cid)
    s.dirty = {}                 -- que el guardado periódico no vuelva a escribir lo borrado
    Achievements.unload(t)
    Achievements.load(t, cid)
    adminLog(admin, "resetlogros", t, "personaje " .. cid)
    notify(admin, ("Logros de %s borrados."):format(dname(t)), "success")
end)

addEventHandler("onPlayerQuit", root, function() resetAsk[source] = nil end)
