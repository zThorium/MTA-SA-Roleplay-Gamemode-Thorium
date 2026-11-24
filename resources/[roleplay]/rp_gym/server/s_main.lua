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

addCommandHandler("borrarmaquina", function(player, _, id)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    id = tonumber(id)
    if not id or not gymMachineList()[id] then return gymNotify(player, "Uso: /borrarmaquina <id> (mira /maquinas)", "warning") end
    gymDestroyMachine(id)
    dbExec(gymDb(), "DELETE FROM gym_machines WHERE id = ?", id)
    gymNotify(player, ("Maquina %d eliminada."):format(id), "success")
end)

addCommandHandler("maquinas", function(player)
    if not gymIsAdmin(player) then return gymNotify(player, NO_PERMISSION, "error") end
    local n = 0
    for id, m in pairs(gymMachineList()) do
        n = n + 1
        outputChatBox(("#%d %s (%s) en %.1f, %.1f, %.1f int %d dim %d"):format(id, m.cfg.label, m.row.gym,
            m.row.x, m.row.y, m.row.z, m.row.interior, m.row.dimension), player, 255, 255, 255)
    end
    gymNotify(player, n == 0 and "No hay maquinas creadas." or (n .. " maquinas en el chat."), "info")
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
