--[[
    rp_gym / s_main.lua
    Carga de maquinas y entrenadores desde SQL y comandos de administracion.

    Comandos (admin):
        /crearmaquina <cinta|bici|banca|mancuernas> [gimnasio]   crea una maquina en tu posicion y rumbo
        /borrarmaquina <id>
        /maquinas                                                 lista las maquinas
        /crearentrenador <boxeo|kungfu|kickboxing>                crea un entrenador en tu posicion y rumbo
        /borrarentrenador <id>
        /entrenadores                                             lista los entrenadores
    Te colocas donde quieres que quede el personaje; la maquina se dibuja debajo de ti.
]]

local function load()
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do gymSpawnMachine(row) end
        outputDebugString(("[rp_gym] %d maquinas cargadas"):format(#rows))
    end, gymDb(), "SELECT * FROM gym_machines")
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do gymSpawnTrainer(row) end
        outputDebugString(("[rp_gym] %d entrenadores cargados"):format(#rows))
    end, gymDb(), "SELECT * FROM gym_trainers")
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then load() else addEventHandler("rp:onDatabaseReady", root, load) end
end)

local NO_PERMISSION = "No tienes permiso para usar este comando."

local function kindByAlias(text)
    text = tostring(text or ""):lower()
    if text == "mancuernas" then return "dumbbells" end   -- nombre antiguo
    for key, cfg in pairs(GYM_KINDS) do
        if key == text or cfg.alias == text then return key end
    end
end

local function placement(player)
    local x, y, z = getElementPosition(player)
    local _, _, rot = getElementRotation(player)
    return x, y, z, rot, getElementInterior(player), getElementDimension(player)
end

addCommandHandler("crearmaquina", function(player, _, kindText, gym)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local kind = kindByAlias(kindText)
    if not kind then return gymNotify(player, "Uso: /crearmaquina <cinta|bici|banca|mancuernas> [gimnasio]", "warning") end
    gym = tostring(gym or "gym"):sub(1, 24)
    local x, y, z, rot, int, dim = placement(player)
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId then return gymNotify(player, "No se pudo guardar la maquina.", "error") end
        gymSpawnMachine({ id = insertId, kind = kind, gym = gym, x = x, y = y, z = z, rotation = rot, interior = int, dimension = dim })
        gymNotify(player, ("%s creada (id %d)."):format(GYM_KINDS[kind].label, insertId), "success")
    end, gymDb(), "INSERT INTO gym_machines (kind, gym, x, y, z, rotation, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        kind, gym, x, y, z, rot, int, dim)
end)

-- Exports para la gramatica Owl de rp_admin (/nearbygymmachines, /nearbytrainers, /delgymmachine...)
function adminElements(kind)
    local list = {}
    for id, e in pairs(kind == "trainer" and gymTrainerList() or gymMachineList()) do
        local row = e.row
        list[#list + 1] = { id = id, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
            interior = row.interior, dimension = row.dimension, label = e.cfg and e.cfg.label or "" }
    end
    return list
end

function adminDelete(id, kind)
    id = tonumber(id)
    if kind == "trainer" then
        if not id or not gymTrainerList()[id] then return false, "no existe" end
        if gymIsFixedId(id) then return false, "es el entrenador fijo del gimnasio (GYM_FIXED)" end
        gymDestroyTrainer(id)
        dbExec(gymDb(), "DELETE FROM gym_trainers WHERE id = ?", id)
        return true
    end
    if not id or not gymMachineList()[id] then return false, "no existe" end
    gymDestroyMachine(id)
    dbExec(gymDb(), "DELETE FROM gym_machines WHERE id = ?", id)
    return true
end

addCommandHandler("borrarmaquina", function(player, _, id)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    id = tonumber(id)
    if not id or not adminDelete(id, "machine") then return gymNotify(player, "Uso: /borrarmaquina <id> (mira /maquinas)", "warning") end
    gymNotify(player, ("Maquina %d eliminada."):format(id), "success")
end)

addCommandHandler("maquinas", function(player)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local n, nearId, nearDist = 0, nil, 10
    local px, py, pz = getElementPosition(player)
    for id, m in pairs(gymMachineList()) do
        n = n + 1
        local d = getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z)
        if d < nearDist then nearId, nearDist = id, d end
        outputChatBox(("#%d %s (%s) en %.1f, %.1f, %.1f int %d dim %d"):format(id, m.cfg.label, m.row.gym,
            m.row.x, m.row.y, m.row.z, m.row.interior, m.row.dimension), player, 255, 255, 255)
    end
    if nearId then
        gymNotify(player, ("Maquina mas cercana: id %d. Borrala con /borrarmaquina %d"):format(nearId, nearId), "info")
    else
        gymNotify(player, n == 0 and "No hay maquinas creadas." or (n .. " maquinas en el chat (ninguna a menos de 10 m)."), "info")
    end
end)

-- Ajuste en vivo de donde se dibuja el modelo respecto al personaje (GYM_KINDS[kind].seat).
-- Afecta a todas las maquinas de ese tipo hasta el proximo restart; los numeros definitivos van en shared/s_config.lua.
addCommandHandler("ajustarmaquina", function(player, _, dx, dy, dz, giro)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local px, py, pz = getElementPosition(player)
    local nearId, nearDist
    for id, m in pairs(gymMachineList()) do
        local d = getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z)
        if d < 10 and (not nearDist or d < nearDist) then nearId, nearDist = id, d end
    end
    if not nearId then return gymNotify(player, "No hay ninguna maquina a menos de 10 m.", "warning") end
    local kind = gymMachineList()[nearId].row.kind
    local cfg = GYM_KINDS[kind]
    local s = cfg.seat or { 0, 0, 0, 0 }
    if not tonumber(dx) then
        return outputChatBox(("Uso: /ajustarmaquina <dx> <dy> <dz> <giro>. Ahora (%s): { %.2f, %.2f, %.2f, %.0f }. dx = derecha, dy = adelante (segun tu rumbo), dz = altura, giro = grados."):format(
            kind, s[1], s[2], s[3], s[4]), player, 255, 255, 255)
    end
    cfg.seat = { tonumber(dx) or s[1], tonumber(dy) or s[2], tonumber(dz) or s[3], tonumber(giro) or s[4] }
    local rows = {}
    for id, m in pairs(gymMachineList()) do
        if m.row.kind == kind then rows[#rows + 1] = m.row end
    end
    for _, row in ipairs(rows) do
        gymDestroyMachine(row.id)
        gymSpawnMachine(row)
    end
    outputChatBox(("seat de %s = { %.2f, %.2f, %.2f, %.0f }  (%d maquinas redibujadas)"):format(
        kind, cfg.seat[1], cfg.seat[2], cfg.seat[3], cfg.seat[4], #rows), player, 120, 255, 120)
end)

-- Como /ajustarmaquina pero SUMA a lo que hay (para afinar de a poco): /sumarmaquina 0 0.1 0 0
addCommandHandler("sumarmaquina", function(player, _, dx, dy, dz, giro)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local px, py, pz = getElementPosition(player)
    local nearKind, nearDist
    for _, m in pairs(gymMachineList()) do
        local d = getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z)
        if d < 10 and (not nearDist or d < nearDist) then nearKind, nearDist = m.row.kind, d end
    end
    if not nearKind then return gymNotify(player, "No hay ninguna maquina a menos de 10 m.", "warning") end
    local s = GYM_KINDS[nearKind].seat or { 0, 0, 0, 0 }
    executeCommandHandler("ajustarmaquina", player, ("%f %f %f %f"):format(
        s[1] + (tonumber(dx) or 0), s[2] + (tonumber(dy) or 0), s[3] + (tonumber(dz) or 0), s[4] + (tonumber(giro) or 0)))
end)

-- Ajuste en vivo del objeto que lleva el personaje en la mano (barra del press, mancuernas). Hay que estar
-- entrenando en esa maquina: /ajustarprop <n> <x> <y> <z> <rx> <ry> <rz>   (n = 1 barra / mancuerna izquierda, 2 = derecha)
addCommandHandler("ajustarprop", function(player, _, n, x, y, z, rx, ry, rz)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local s = gymSessionOf(player)
    if not s or not s.cfg.props then return gymNotify(player, "Entrena en el press o las pesas para ajustar el objeto de la mano.", "warning") end
    n = tonumber(n)
    local p = n and s.cfg.props[n]
    if not p then return gymNotify(player, "Uso: /ajustarprop <1-" .. #s.cfg.props .. "> <x> <y> <z> <rx> <ry> <rz>", "warning") end
    if not tonumber(x) then
        return outputChatBox(("prop %d de %s: { %.2f, %.2f, %.2f, %.0f, %.0f, %.0f }"):format(n, s.kind,
            p.off[1], p.off[2], p.off[3], p.off[4], p.off[5], p.off[6]), player, 255, 255, 255)
    end
    local off = { tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0, tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0 }
    gymSetProp(s.kind, n, off)
    outputChatBox(("prop %d de %s = { %.2f, %.2f, %.2f, %.0f, %.0f, %.0f }"):format(n, s.kind,
        off[1], off[2], off[3], off[4], off[5], off[6]), player, 120, 255, 120)
end)

-- Posicion del objeto extra de la maquina mas cercana (barra sobre el banco, segunda mancuerna):
-- /ajustarextra <n> <dx> <dy> <dz> <rx> <ry> <rz>   (metros respecto a donde estaba el personaje y grados)
addCommandHandler("ajustarextra", function(player, _, n, dx, dy, dz, rx, ry, rz)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local px, py, pz = getElementPosition(player)
    local kind, best
    for _, m in pairs(gymMachineList()) do
        local d = getDistanceBetweenPoints3D(px, py, pz, m.row.x, m.row.y, m.row.z)
        if d < 10 and m.cfg.extra and (not best or d < best) then kind, best = m.row.kind, d end
    end
    if not kind then return gymNotify(player, "No hay cerca ninguna maquina con objeto extra (banca o pesas).", "warning") end
    n = tonumber(n) or 1
    local e = GYM_KINDS[kind].extra[n]
    if not e then return gymNotify(player, "Ese objeto extra no existe.", "warning") end
    if not tonumber(dx) then
        return outputChatBox(("extra %d de %s: { dx %.2f, dy %.2f, dz %.2f, rx %.0f, ry %.0f, rz %.0f }  Uso: /ajustarextra <n> <dx> <dy> <dz> <rx> <ry> <rz>"):format(
            n, kind, e.dx or 0, e.dy or 0, e.dz or 0, e.rx or 0, e.ry or 0, e.rz or 0), player, 255, 255, 255)
    end
    gymSetExtra(kind, n, { dx = tonumber(dx) or 0, dy = tonumber(dy) or 0, dz = tonumber(dz) or 0,
        rx = tonumber(rx) or 0, ry = tonumber(ry) or 0, rz = tonumber(rz) or 0 })
    outputChatBox(("extra %d de %s = { dx %.2f, dy %.2f, dz %.2f, rx %.0f, ry %.0f, rz %.0f }"):format(
        n, kind, tonumber(dx) or 0, tonumber(dy) or 0, tonumber(dz) or 0, tonumber(rx) or 0, tonumber(ry) or 0, tonumber(rz) or 0), player, 120, 255, 120)
end)

-- Quita el agotamiento (limite diario de 12 h) y reinicia los contadores del dia. Sin argumento, a ti mismo.
addCommandHandler("reiniciargym", function(player, _, targetName)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local target = player
    if targetName then
        target = getPlayerFromName(targetName:gsub(" ", "_"))
        if not target then return gymNotify(player, "No encuentro a ese jugador (nombre exacto).", "warning") end
    end
    local p = profiles[target]
    if not p or p.loading then return gymNotify(player, "Ese jugador no tiene perfil de gimnasio cargado.", "warning") end
    p.locked_until, p.day_start, p.day_fat, p.day_stamina, p.day_muscle = 0, 0, 0, 0, 0
    saveProfile(target)
    gymNotify(player, "Agotamiento del gimnasio reiniciado.", "success")
    if target ~= player then gymNotify(target, "Un administrador reinicio tu limite de entrenamiento.", "info") end
end)

addCommandHandler("crearentrenador", function(player, _, styleText)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local style = GYM_STYLE_ALIAS[tostring(styleText or ""):lower()]
    if not style then return gymNotify(player, "Uso: /crearentrenador <boxeo|kungfu|kickboxing>", "warning") end
    local x, y, z, rot, int, dim = placement(player)
    dbQuery(function(qh)
        local _, _, insertId = dbPoll(qh, 0)
        if not insertId then return gymNotify(player, "No se pudo guardar el entrenador.", "error") end
        gymSpawnTrainer({ id = insertId, style = style, x = x, y = y, z = z, rotation = rot, interior = int, dimension = dim })
        gymNotify(player, ("%s creado (id %d)."):format(GYM_STYLES[style].label, insertId), "success")
    end, gymDb(), "INSERT INTO gym_trainers (style, x, y, z, rotation, interior, dimension) VALUES (?, ?, ?, ?, ?, ?, ?)",
        style, x, y, z, rot, int, dim)
end)

addCommandHandler("borrarentrenador", function(player, _, id)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    id = tonumber(id)
    if not id or not gymTrainerList()[id] then return gymNotify(player, "Uso: /borrarentrenador <id> (mira /entrenadores)", "warning") end
    if gymIsFixedId(id) then return gymNotify(player, "Es el entrenador fijo del gimnasio original: se cambia en GYM_FIXED (shared/s_config.lua).", "warning") end
    gymDestroyTrainer(id)
    dbExec(gymDb(), "DELETE FROM gym_trainers WHERE id = ?", id)
    gymNotify(player, ("Entrenador %d eliminado."):format(id), "success")
end)

addCommandHandler("entrenadores", function(player)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local n = 0
    for id, t in pairs(gymTrainerList()) do
        n = n + 1
        outputChatBox(("#%d %s en %.1f, %.1f, %.1f int %d dim %d"):format(id, t.cfg.label,
            t.row.x, t.row.y, t.row.z, t.row.interior, t.row.dimension), player, 255, 255, 255)
    end
    gymNotify(player, n == 0 and "No hay entrenadores creados." or (n .. " entrenadores en el chat."), "info")
end)
