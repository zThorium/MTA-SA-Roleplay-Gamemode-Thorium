--[[
    rp_police / s_evidence.lua
    Criminalistica. Al disparar cae un casquillo (serie del arma, salvo que este
    limada) y al recibir dano queda sangre (ADN). Solo los policias de servicio ven
    los marcadores. Con un kit de evidencia (E cerca) se recolecta; en el laboratorio
    (punto de la comisaria) se analiza y se cruza con la base de ciudadanos.
    La evidencia sin recoger desaparece a los EVIDENCE_LIFE ms (25 min).
]]

local evidence = {}        -- [marker] = { kind, weapon, charId, name, serial, tick }
local count = 0
local lastCasing, lastBlood = {}, {}

local CALIBER = {
    [22] = "9mm", [24] = ".50 AE", [25] = "calibre 12", [26] = "calibre 12", [27] = "calibre 12", [28] = "9mm", [29] = "9mm",
    [30] = "7.62mm", [31] = "5.56mm", [32] = "9mm", [33] = ".308", [34] = ".308", [35] = "cohete", [36] = "cohete", [38] = "7.62mm",
}

local function makeSerial(charId, weapon)
    return ("LS-%06d"):format((charId * 7919 + weapon * 104729) % 1000000)
end

local function createEvidence(kind, x, y, z, data)
    if count >= POLICE.EVIDENCE_MAX then return end
    local r, g, b = 240, 200, 40
    if kind == "blood" then r, g, b = 200, 20, 20 end
    local m = createMarker(x, y, z - 0.95, "cylinder", 0.7, r, g, b, 140)
    setElementVisibleTo(m, root, false)
    for _, o in ipairs(officersOnDuty()) do setElementVisibleTo(m, o, true) end
    data.kind, data.tick = kind, getTickCount()
    evidence[m] = data
    count = count + 1
    setTimer(function()
        if evidence[m] then evidence[m] = nil count = count - 1 end
        if isElement(m) then destroyElement(m) end
    end, POLICE.EVIDENCE_LIFE, 1)
end

function addCasing(player, weapon, x, y, z)
    if not CALIBER[weapon] or weapon == 35 or weapon == 36 then return end
    local id = charOf(player)
    local now = getTickCount()
    if not id or (lastCasing[player] and now - lastCasing[player] < 3000) then return end
    lastCasing[player] = now
    local scratched = math.random() < POLICE.SCRATCHED_SERIAL_CHANCE
    createEvidence("casing", x, y, z, { weapon = weapon, charId = id, serial = (not scratched) and makeSerial(id, weapon) or nil })
end

addEventHandler("onPlayerDamage", root, function(attacker, weapon, bodypart, loss)
    local victim = source
    if not charOf(victim) or (loss or 0) < 5 then return end
    local now = getTickCount()
    if lastBlood[victim] and now - lastBlood[victim] < 10000 then return end
    lastBlood[victim] = now
    local x, y, z = getElementPosition(victim)
    createEvidence("blood", x, y, z, { charId = charOf(victim), name = dname(victim) })
end)

addEventHandler("rp:pol:onDuty", root, function(on)
    for m in pairs(evidence) do
        if isElement(m) then setElementVisibleTo(m, source, on and true or false) end
    end
end)

addEventHandler("onPlayerQuit", root, function() lastCasing[source], lastBlood[source] = nil, nil end)

----------------------------------------------------------------
-- Recoleccion (tecla E, evento rp:pol:use "evidence")
----------------------------------------------------------------
function collectEvidence(player)
    if not can(player, "pol_evidence") then return end
    if not exports.rp_inventory:hasItem(player, "pol_kit", 1) then
        return notify(player, "Necesitas un kit de evidencia (armeria).", "warning")
    end
    local px, py, pz = getElementPosition(player)
    local best, bd = nil, POLICE.EVIDENCE_PICKUP + 0.5
    for m, e in pairs(evidence) do
        if isElement(m) then
            local x, y, z = getElementPosition(m)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z + 0.95)
            if d < bd then best, bd = m, d end
        end
    end
    if not best then return end
    local e = evidence[best]
    local x, y, z = getElementPosition(best)
    evidence[best] = nil
    count = count - 1
    destroyElement(best)
    exports.rp_inventory:takeItem(player, "pol_kit", 1)
    local detail = e.kind == "casing" and ("Casquillo %s (%s)"):format(CALIBER[e.weapon] or "?", getWeaponNameFromID(e.weapon) or "arma")
        or "Muestra de sangre"
    dbExec(db(), "INSERT INTO police_evidence (kind, detail, source_char, serial, location, collected_by) VALUES (?, ?, ?, ?, ?, ?)",
        e.kind, detail, e.charId, e.serial, getZoneName(x, y, z), dname(player))
    notify(player, ("Recolectas evidencia: %s. Llevala al laboratorio."):format(detail), "success")
end

----------------------------------------------------------------
-- Laboratorio
----------------------------------------------------------------
local function labData(cb)
    dbQuery(function(qh)
        local out = { pending = {}, done = {} }
        for _, r in ipairs(dbPoll(qh, 0) or {}) do
            local item = { id = tonumber(r.id), kind = r.kind, detail = r.detail, location = r.location, by = r.collected_by,
                at = r.at, result = r.result }
            local list = tonumber(r.analyzed) == 1 and out.done or out.pending
            list[#list + 1] = item
        end
        cb(out)
    end, db(), [[SELECT id, kind, detail, location, collected_by, analyzed, result, DATE_FORMAT(created_at, '%d/%m %H:%i') AS at
        FROM police_evidence ORDER BY id DESC LIMIT 40]])
end

function openLab(player)
    if not can(player, "pol_evidence") then return notify(player, "Tu rol no tiene acceso al laboratorio.", "warning") end
    labData(function(data)
        if isElement(player) then showUI(player, "lab", data) end
    end)
end

UI_ACTIONS.lab_analyze = function(player, d)
    if not can(player, "pol_evidence") or not nearPoint(player, "lab") then return end
    local id = math.floor(tonumber(d.id) or 0)
    if id < 1 then return end
    dbQuery(function(qh)
        local e = (dbPoll(qh, 0) or {})[1]
        if not e or tonumber(e.analyzed) == 1 or not isElement(player) then return end
        local function finish(result)
            dbExec(db(), "UPDATE police_evidence SET analyzed = 1, result = ? WHERE id = ? AND analyzed = 0", result:sub(1, 255), id)
            factionLog(("%s analizo la evidencia #%d."):format(dname(player), id))
            notify(player, "Analisis completado.", "success")
            labData(function(data) updateUI(player, "lab", data) end)
        end
        local function owner(cb)
            dbQuery(function(q2)
                local c = (dbPoll(q2, 0) or {})[1]
                cb(c and c.name:gsub("_", " ") or nil)
            end, db(), "SELECT name FROM characters WHERE id = ?", e.source_char)
        end
        if e.kind == "blood" then
            owner(function(name)
                finish(name and ("ADN coincide con %s (ciudadano #%d)."):format(name, tonumber(e.source_char)) or "ADN sin coincidencias en la base.")
            end)
        elseif not e.serial then
            finish("Numero de serie limado: no se puede identificar al propietario del arma.")
        else
            owner(function(name)
                dbQuery(function(q3)
                    local rows = dbPoll(q3, 0) or {}
                    local extra = ""
                    if #rows > 0 then
                        local ids = {}
                        for _, r in ipairs(rows) do ids[#ids + 1] = "#" .. r.id end
                        extra = " Misma arma que la evidencia " .. table.concat(ids, ", ") .. "."
                    end
                    finish(("Serie %s: arma registrada a %s.%s"):format(e.serial, name or "desconocido", extra))
                end, db(), "SELECT id FROM police_evidence WHERE serial = ? AND id <> ? AND analyzed = 1 LIMIT 5", e.serial, id)
            end)
        end
    end, db(), "SELECT id, kind, serial, source_char, analyzed FROM police_evidence WHERE id = ?", id)
end

UI_ACTIONS.mdt_evidence = function(player)
    if not can(player, "pol_evidence") then return end
    labData(function(data) updateUI(player, "evidence", data) end)
end
