--[[
    rp_admin / s_antispam.lua  (servidor)

    Límite de frecuencia común para lo que llega del cliente (#110):
      - Comandos: más de ANTISPAM.CMD_MAX en ANTISPAM.CMD_WINDOW ms se ignoran (onPlayerCommand).
      - Eventos remotos: cada evento tiene un tope por segundo y jugador (debug hook "preEvent":
        solo mira los que vienen de un cliente; el resto sale al instante). Los de alta frecuencia
        legítima van en ANTISPAM.EVENT_LIMITS con su propio tope.
      - Total de eventos por jugador: lo limita MTA (mtaserver.conf, max_player_triggered_events_per_interval)
        y avisa con onPlayerTriggerEventThreshold.
    Cada exceso suma una falta; ANTISPAM.KICK_STRIKES faltas en ANTISPAM.STRIKE_WINDOW ms = kick con
    registro en admin_log (command "antispam") y server.log. Los admins solo se registran, no se expulsan.

    Exports (servidor): getSpamStrikes(player) -> n
]]

ANTISPAM = {
    CMD_WINDOW = 2000, CMD_MAX = 8,          -- comandos por ventana
    EVENT_MAX = 20,                          -- por evento remoto y segundo (por defecto)
    -- Eventos legítimos de alta frecuencia: tope propio por segundo (prefijo terminado en ":" vale para todos los que empiezan así)
    EVENT_LIMITS = {
        ["rp:chat:typing"] = 10,
        ["rp:veh:hit"] = 40,
        ["rp:citizens:"] = 80,
        ["rp:train:"] = 60,
        ["rp:mapeditor:"] = 60,
        ["rp:paths:"] = 60,
        ["rp:freecam:"] = 60,
        ["rp:move:"] = 60,
    },
    STRIKE_WINDOW = 60000, KICK_STRIKES = 6, -- faltas para expulsar
    WARN_EVERY = 2,                          -- avisa al jugador cada N faltas
}

local cmdHits = {}     -- [player] = { ticks }
local evHits = {}      -- [player] = { [evento] = { second, n } }
local strikes = {}     -- [player] = { ticks }
local kicked = {}      -- [player] = true (ya se está expulsando)

local function adminLevel(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) end

local function record(p, what)
    local conn = exports.rp_database:getConnection()
    outputServerLog(("[rp_admin] antispam: %s (cuenta #%s) %s"):format(getPlayerName(p), tostring(exports.rp_login:getPlayerAccountId(p) or "-"), what))
    if not conn then return end
    dbExec(conn, [[INSERT INTO admin_log (admin_account_id, admin_name, command, target_account_id, target_character_id, target_name, details)
                   VALUES (NULL, 'Sistema', 'antispam', NULLIF(?, 0), NULLIF(?, 0), ?, ?)]],
        exports.rp_login:getPlayerAccountId(p) or 0, exports.rp_characters:getPlayerCharacterId(p) or 0,
        getPlayerName(p), tostring(what):sub(1, 255))
end

local function strike(p, what, weight)
    if kicked[p] or not isElement(p) then return end
    local now = getTickCount()
    local list = strikes[p] or {}
    strikes[p] = list
    for _ = 1, weight or 1 do list[#list + 1] = now end
    while list[1] and now - list[1] > ANTISPAM.STRIKE_WINDOW do table.remove(list, 1) end
    local n = #list
    if n >= ANTISPAM.KICK_STRIKES then
        if adminLevel(p) >= 1 then
            strikes[p] = {}
            return record(p, "admin por encima del límite: " .. what)
        end
        kicked[p] = true
        record(p, "expulsado por spam: " .. what)
        setTimer(function() if isElement(p) then kickPlayer(p, "Anti-spam: demasiados comandos o acciones seguidas") end end, 50, 1)
    elseif n % ANTISPAM.WARN_EVERY == 0 then
        exports.rp_notify:notify(p, "Vas demasiado rápido: espera un momento o te expulsará el anti-spam.", "warning")
    end
end

local function eventLimit(name)
    local own = ANTISPAM.EVENT_LIMITS[name]
    if own then return own end
    local prefix = name:match("^(.-:.-:)")    -- "rp:sistema:"
    return (prefix and ANTISPAM.EVENT_LIMITS[prefix]) or ANTISPAM.EVENT_MAX
end

----------------------------------------------------------------
-- Comandos
----------------------------------------------------------------
addEventHandler("onPlayerCommand", root, function(cmd)
    local p = source
    if adminLevel(p) >= 1 then return end      -- los admins encadenan comandos a propósito
    local now = getTickCount()
    local list = cmdHits[p] or {}
    cmdHits[p] = list
    while list[1] and now - list[1] > ANTISPAM.CMD_WINDOW do table.remove(list, 1) end
    if #list >= ANTISPAM.CMD_MAX then
        cancelEvent()
        return strike(p, "comandos (/" .. tostring(cmd) .. ")")
    end
    list[#list + 1] = now
end)

----------------------------------------------------------------
-- Eventos remotos
----------------------------------------------------------------
local function preEvent(_, eventName, _, eventClient)
    if not eventClient then return end          -- solo lo que llega de un cliente
    local now = getTickCount()
    local second = math.floor(now / 1000)
    local byEvent = evHits[eventClient]
    if not byEvent then byEvent = {}; evHits[eventClient] = byEvent end
    local h = byEvent[eventName]
    if not h or h.second ~= second then
        byEvent[eventName] = { second = second, n = 1 }
        return
    end
    h.n = h.n + 1
    if h.n > eventLimit(eventName) then
        if h.n == eventLimit(eventName) + 1 then strike(eventClient, "evento " .. eventName) end
        return "skip"
    end
end

-- Límite total de MTA (mtaserver.conf)
addEventHandler("onPlayerTriggerEventThreshold", root, function()
    strike(source, "límite total de eventos de MTA", 2)
end)

----------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------
function getSpamStrikes(p)
    return strikes[p] and #strikes[p] or 0
end

addEventHandler("onPlayerQuit", root, function()
    cmdHits[source], evHits[source], strikes[source], kicked[source] = nil, nil, nil, nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if not addDebugHook("preEvent", preEvent) then
        outputDebugString("[rp_admin] antispam: no se pudo poner el debug hook; solo quedan el límite de comandos y el de MTA", 2)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    removeDebugHook("preEvent", preEvent)
end)
