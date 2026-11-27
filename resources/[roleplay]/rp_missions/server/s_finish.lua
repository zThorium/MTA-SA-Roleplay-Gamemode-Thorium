--[[
    rp_missions / server / s_finish.lua

    COMPLETED / FAILED -> CLEANUP.
    Recompensas por jugador segun lo registrado en inst.stats:
        XP = (BASE + kills*KILL + objetivos*OBJETIVO + bono de mision) * multiplicador de dificultad
        Dinero y respeto * multiplicador. El respeto sube la estadistica nativa 64 de GTA SA.
    Persistencia antes de devolver a la dimension 0 (anti-rollback): XP (suma atomica), dinero (UPDATE
    atomico), respeto y progreso (INSERT ... ON DUPLICATE KEY) y despues saveCharacter.
]]

local floor, max, min = math.floor, math.max, math.min

local function computeReward(inst, p, success)
    local R, D = MISSIONS.REWARD, inst.diff
    local s = inst.stats[p] or { kills = 0, objs = 0, deaths = 0 }
    local xp, cash, respect = 0, 0, 0
    if success then
        xp = floor((R.BASE_XP + (inst.def.xpBonus or 0) + s.kills * R.KILL_XP + s.objs * R.OBJECTIVE_XP) * D.reward)
        cash = floor(inst.def.cash * D.reward)
        respect = floor(inst.def.respect * D.reward)
    else
        xp = floor(s.kills * R.FAIL_KILL_XP * D.reward)
    end
    return xp, cash, respect
end

local function persist(inst, p, xp, cash, respect, success, elapsed)
    local cid = M.characterOf(p)
    if not cid then return end
    if xp > 0 then pcall(function() exports.rp_levels:giveXP(p, xp, "mision " .. inst.def.key) end) end
    if cash > 0 then
        givePlayerMoney(p, cash)
        dbExec(M.db(), "UPDATE characters SET money = money + ? WHERE id = ?", cash, cid)
    end
    if respect > 0 then
        local room = MISSIONS.RESPECT_MAX - M.totalRespect(p)
        respect = max(0, min(respect, room))
        M.respect[p] = M.respect[p] or {}
        M.respect[p][inst.def.contact] = (M.respect[p][inst.def.contact] or 0) + respect
        dbExec(M.db(), "INSERT INTO character_respect (character_id, contact, respect) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE respect = respect + VALUES(respect)",
            cid, inst.def.contact, respect)
        M.applyRespectStat(p)
    end
    if success then
        M.progress[p] = M.progress[p] or {}
        local prog = M.progress[p][inst.def.key] or { n = 0 }
        prog.n = prog.n + 1
        if not prog.best or elapsed < prog.best then prog.best = elapsed end
        M.progress[p][inst.def.key] = prog
        dbExec(M.db(), [[INSERT INTO mission_progress (character_id, mission_key, completions, best_ms) VALUES (?, ?, 1, ?)
            ON DUPLICATE KEY UPDATE completions = completions + 1, best_ms = LEAST(COALESCE(best_ms, VALUES(best_ms)), VALUES(best_ms))]],
            cid, inst.def.key, elapsed)
        triggerEvent("rp:achievements:progress", p, "missions_done", 1)   -- logros (rp_achievements)
    end
    return respect
end

function M.finish(inst, success, reason)
    if inst.destroyed or (inst.state ~= "IN_PROGRESS" and inst.state ~= "LOADING") then return end
    inst.state = success and "COMPLETED" or "FAILED"
    if isTimer(inst.timers.tick) then killTimer(inst.timers.tick) end
    if inst.rt then
        for p in pairs(inst.rt.holders or {}) do M.releaseHold(inst, p) end
        if isTimer(inst.rt.cutsceneTimer) then killTimer(inst.rt.cutsceneTimer) end
        if isTimer(inst.rt.nextTimer) then killTimer(inst.rt.nextTimer) end
    end
    local elapsed = getTickCount() - (inst.startedAt or getTickCount())
    for _, ped in ipairs(inst.entities.peds) do if isElement(ped) then destroyElement(ped) end end

    local rows, mine = {}, {}
    for _, m in ipairs(inst.members) do
        if isElement(m) then
            local xp, cash, respect = computeReward(inst, m, success)
            respect = persist(inst, m, xp, cash, respect, success, elapsed) or 0
            local s = inst.stats[m] or { kills = 0, objs = 0, deaths = 0 }
            local row = { name = M.nameOf(m), kills = s.kills, objs = s.objs, deaths = s.deaths, xp = xp, cash = cash, respect = respect, role = M.roleDef(inst, m).name }
            rows[#rows + 1] = row
            mine[m] = row
        end
    end

    -- Pose de victoria / pantalla final
    if success and inst.def.victory then
        local v = inst.def.victory
        local list = {}
        for _, m in ipairs(inst.members) do
            if isElement(m) then
                if inst.spec[m] then
                    inst.spec[m] = nil
                    setElementAlpha(m, 255)
                    setElementCollisionsEnabled(m, true)
                    triggerClientEvent(m, "rp:missions:spectate", resourceRoot, false)
                end
                list[#list + 1] = m
            end
        end
        for i, m in ipairs(list) do
            pcall(function() exports.rp_injury:revivePlayer(m) end)
            removePedFromVehicle(m)
            local off = (i - (#list + 1) / 2) * (v.spread or 1.5)
            local a = math.rad(v[4])   -- lado a lado, no en fila
            setElementPosition(m, v[1] + math.cos(a) * off, v[2] + math.sin(a) * off, v[3])
            setElementRotation(m, 0, 0, v[4])
            setElementHealth(m, 100)
            setElementFrozen(m, true)
            setElementData(m, "rp:noNeckFix", true)
            setPedAnimation(m, "CASINO", i % 2 == 1 and "manwinb" or "manwind", -1, true, false, false, false)
        end
    end

    local payload = {
        success = success, reason = reason, title = inst.def.title, contact = inst.def.contact, contactName = MISSIONS.CONTACTS[inst.def.contact].name,
        difficulty = inst.diff.label, diffColor = inst.diff.color, mult = inst.diff.reward, elapsed = elapsed, rows = rows,
        victory = success and inst.def.victoryCam or nil, victoryTime = MISSIONS.VICTORY_CAM_TIME,
        wait = success and MISSIONS.RESULT_TIME or MISSIONS.FAIL_TIME,
    }
    for _, m in ipairs(inst.members) do
        if isElement(m) then
            local copy = {}
            for k, v in pairs(payload) do copy[k] = v end
            copy.you = mine[m] and mine[m].name
            triggerClientEvent(m, "rp:missions:results", resourceRoot, copy)
        end
    end
    inst.timers.cleanup = setTimer(function() M.cleanup(inst) end, (success and MISSIONS.RESULT_TIME or MISSIONS.FAIL_TIME) + 800, 1)
end

function M.cleanup(inst)
    if inst.destroyed then return end
    inst.state = "CLEANUP"
    for _, m in ipairs(inst.members) do
        if isElement(m) then fadeCamera(m, false, 0.8) end
    end
    setTimer(function()
        if inst.destroyed then return end
        local members = {}
        for _, m in ipairs(inst.members) do members[#members + 1] = m end
        M.cleanupEntities(inst)
        for _, m in ipairs(members) do
            if isElement(m) then
                M.restorePlayer(inst, m)
                M.playerInst[m] = nil
                local ok = pcall(function() exports.rp_characters:saveCharacter(m) end)
            end
        end
        inst.members = {}
        M.destroyInstance(inst)
    end, 1000, 1)
end
