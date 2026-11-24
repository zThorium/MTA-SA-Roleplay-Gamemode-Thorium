--[[
    rp_citizens / s_telemetry.lua
    Recibe la telemetria de conduccion del cliente (fallos de autos, resultados de /trafico_test) y la guarda
    en telemetry/trafico_AAAAMMDD.jsonl (una linea JSON por evento: {"ts":unix,"d":<evento>}). Se lee con
    tools/trafico (replay.js, compare.js) o a mano. Opcionalmente tambien la reenvia por HTTP a un colector local
    (tools/trafico/collector.js): pon su URL en el setting "collector_url" del meta.xml.
    Solo admins (nivel >= 1). Limites: 16 KB por evento, 20 eventos/s por jugador, 25 MB por archivo.
]]

local MAX_BYTES, MAX_FILE, MAX_PER_SEC = 16384, 25 * 1024 * 1024, 20

addEvent("rp:citizens:tel", true)

local window = {}   -- [jugador] = { t = inicio de ventana, n = eventos }

local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function fileForToday()
    local rt = getRealTime()
    return ("telemetry/trafico_%04d%02d%02d.jsonl"):format(rt.year + 1900, rt.month + 1, rt.monthday)
end

local function append(line)
    local name = fileForToday()
    local f = fileExists(name) and fileOpen(name) or fileCreate(name)
    if not f then return false end
    local size = fileGetSize(f)
    if size > MAX_FILE then fileClose(f) return false end
    fileSetPos(f, size)
    fileWrite(f, line .. "\n")
    fileClose(f)
    return true
end

addEventHandler("rp:citizens:tel", resourceRoot, function(json)
    if not client or not isAdmin(client) then return end
    if type(json) ~= "string" or #json > MAX_BYTES then return end
    local first = json:sub(1, 1)
    if first ~= "{" and first ~= "[" then return end

    local now = getTickCount()
    local w = window[client]
    if not w or now - w.t > 1000 then w = { t = now, n = 0 } window[client] = w end
    w.n = w.n + 1
    if w.n > MAX_PER_SEC then return end

    local line = ('{"ts":%d,"d":%s}'):format(getRealTime().timestamp, json)
    append(line)

    local url = get("collector_url")
    if url and url ~= "" then
        fetchRemote(url, { method = "POST", postData = line, headers = { ["Content-Type"] = "application/json" } }, function() end)
    end
end)

addEventHandler("onPlayerQuit", root, function() window[source] = nil end)
