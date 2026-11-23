--[[
    rp_phone / s_music.lua

    Motor de Musica del telefono: catalogo local y busqueda remota en Internet Archive,
    reproduccion privada, altavoz y radio vehicular. El servidor decide que
    pista existe y el cliente nunca recibe ni valida URLs directamente.
]]

local db = function() return exports.rp_database:getConnection() end
local active = {}
local catalog = {}
local cooldownSearch = {}
local cooldownPlay = {}
local remoteSearchCache = {}
local resolvedUrls = {} -- identifier de archive.org -> URL mp3/ogg ya resuelta

local function notify(player, text, kind)
    if exports.rp_notify then exports.rp_notify:notify(player, text, kind or "info") end
end

local function characterOf(player)
    if not exports.rp_characters then return false end
    return exports.rp_characters:getPlayerCharacterId(player)
end

local function hasPhone(player)
    return characterOf(player) and exports.rp_inventory and exports.rp_inventory:hasItem(player, "phone", 1)
end

local function cleanQuery(value)
    if type(value) == "table" then
        value = value[1] or value[0] or value.query or value.text or value.value
    end
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("[%z\1-\31]", " ")
    if #value == 0 or #value > 80 then return nil end
    return value
end

local function urlEncode(value)
    value = tostring(value or "")
    local hex = "0123456789ABCDEF"
    local out = {}
    for i = 1, #value do
        local c = value:sub(i, i)
        if c:match("[%w%-%.%_%~]") then
            out[#out + 1] = c
        else
            local b = c:byte()
            out[#out + 1] = "%"
            out[#out + 1] = hex:sub(math.floor(b / 16) + 1, math.floor(b / 16) + 1)
            out[#out + 1] = hex:sub((b % 16) + 1, (b % 16) + 1)
        end
    end
    return table.concat(out)
end

local function publicTrack(track)
    if not track then return nil end
    return {
        key = track.key,
        provider = track.provider,
        title = track.title,
        artist = track.artist,
        artwork = track.artwork or "",
        durationMs = tonumber(track.durationMs) or 0,
    }
end

local function addCatalogTrack(track)
    if not track or not track.key or not track.streamUrl then return false end
    catalog[track.key] = track
    return true
end

local function loadLocalCatalog()
    for _, track in ipairs(MUSIC_DEMO_TRACKS or {}) do
        addCatalogTrack({
            key = track.key,
            provider = track.provider,
            providerId = track.providerId,
            title = track.title,
            artist = track.artist,
            artwork = track.artwork,
            streamUrl = track.streamUrl,
            durationMs = track.durationMs,
        })
    end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        for _, row in ipairs(rows) do
            addCatalogTrack({
                key = row.track_key,
                provider = row.provider,
                providerId = row.provider_id,
                title = row.title,
                artist = row.artist,
                artwork = row.artwork_url,
                streamUrl = row.stream_url,
                durationMs = tonumber(row.duration_ms) or 0,
            })
        end
        outputDebugString(("[rp_phone][music] %d pistas cargadas"):format(#MUSIC_DEMO_TRACKS + #rows))
    end, db(), "SELECT track_key, provider, provider_id, title, artist, artwork_url, stream_url, duration_ms FROM music_tracks WHERE active = 1")
end

local function allPublicTracks()
    local list = {}
    for _, track in pairs(catalog) do
        list[#list + 1] = publicTrack(track)
    end
    table.sort(list, function(a, b)
        if a.artist == b.artist then return a.title < b.title end
        return a.artist < b.artist
    end)
    return list
end

local function sendCatalog(player)
    triggerClientEvent(player, "rp:music:catalog", resourceRoot, allPublicTracks())
end

local function sendLibrary(player)
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(favQh)
        local favorites = dbPoll(favQh, 0) or {}
        dbQuery(function(historyQh)
            local history = dbPoll(historyQh, 0) or {}
            local favoriteList = {}
            local seen = {}
            for _, row in ipairs(favorites) do
                local track = catalog[row.track_key]
                if track and not seen[track.key] then
                    seen[track.key] = true
                    favoriteList[#favoriteList + 1] = publicTrack(track)
                end
            end
            local historyList = {}
            local historySeen = {}
            for _, row in ipairs(history) do
                local track = catalog[row.track_key]
                if track and not historySeen[track.key] then
                    historySeen[track.key] = true
                    historyList[#historyList + 1] = publicTrack(track)
                end
            end
            triggerClientEvent(player, "rp:music:library", resourceRoot, favoriteList, historyList)
        end, db(), [[
            SELECT track_key FROM (
                SELECT track_key, played_at FROM music_history
                WHERE character_id = ?
                ORDER BY played_at DESC LIMIT 30
            ) recent
            ORDER BY played_at DESC
        ]], characterId)
    end, db(), [[
        SELECT track_key FROM music_favorites
        WHERE character_id = ?
        ORDER BY created_at DESC
    ]], characterId)
end

local function sendState(player)
    local state = active[player]
    if not state then
        triggerClientEvent(player, "rp:music:state", resourceRoot, nil)
        return
    end
    triggerClientEvent(player, "rp:music:state", resourceRoot, {
        trackKey = state.trackKey,
        origin = state.origin,
        vehicle = state.vehicle,
        paused = state.paused,
        position = state.position,
        startedAt = state.startedAt,
        volume = state.volume,
        speaker = state.speaker,
    })
end

local function clearPlayerData(player)
    for _, key in ipairs({
        "rp:musicTrackKey", "rp:musicStartedAt", "rp:musicPaused",
        "rp:musicPosition", "rp:musicVolume", "rp:musicSpeaker", "rp:musicOrigin",
    }) do
        removeElementData(player, key)
    end
end

local function syncPlayer(player)
    local state = active[player]
    if not state then
        clearPlayerData(player)
        return
    end
    setElementData(player, "rp:musicTrackKey", state.trackKey, true)
    setElementData(player, "rp:musicStartedAt", state.startedAt, true)
    setElementData(player, "rp:musicPaused", state.paused, true)
    setElementData(player, "rp:musicPosition", state.position, true)
    setElementData(player, "rp:musicVolume", state.volume, true)
    setElementData(player, "rp:musicSpeaker", state.speaker, true)
    setElementData(player, "rp:musicOrigin", state.origin, true)
end

local function stopPlayer(player)
    active[player] = nil
    syncPlayer(player)
    if isElement(player) then sendState(player) end
end

local function isInRange(player, target, distance)
    if getElementDimension(player) ~= getElementDimension(target) then return false end
    if getElementInterior(player) ~= getElementInterior(target) then return false end
    local ax, ay, az = getElementPosition(player)
    local bx, by, bz = getElementPosition(target)
    return getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz) <= distance
end

local function vehicleCanControl(player, vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    if getPedOccupiedVehicle(player) ~= vehicle then return false end
    local seat = getPedOccupiedVehicleSeat(player)
    return seat == 0 or seat == 1
end

local function clearVehicleState(vehicle)
    if not isElement(vehicle) then return end
    for _, key in ipairs({
        "rp:musicTrackKey", "rp:musicStartedAt", "rp:musicPaused",
        "rp:musicPosition", "rp:musicVolume",
    }) do
        removeElementData(vehicle, key)
    end
end

local function syncVehicle(vehicle, state)
    if not isElement(vehicle) then return end
    setElementData(vehicle, "rp:musicTrackKey", state.trackKey, true)
    setElementData(vehicle, "rp:musicStartedAt", state.startedAt, true)
    setElementData(vehicle, "rp:musicPaused", state.paused, true)
    setElementData(vehicle, "rp:musicPosition", state.position, true)
    setElementData(vehicle, "rp:musicVolume", state.volume, true)
end

-- Un vehiculo suena con UNA sola fuente: al usar el telefono se apaga la radio de rp_radio
local function silenceVehicleRadio(vehicle)
    if not isElement(vehicle) then return end
    pcall(function() exports.rp_radio:setVehicleStation(vehicle, nil) end)
end

-- Export para rp_radio: detiene la musica del vehiculo (la radio la reemplaza) y limpia el vehiculo
function stopVehicleMusic(vehicle)
    local owners = {}
    for player, state in pairs(active) do
        if state.origin == "vehicle" and state.vehicle == vehicle then owners[#owners + 1] = player end
    end
    for _, player in ipairs(owners) do stopPlayer(player) end
    clearVehicleState(vehicle)
end

local function sendTrackToPlayer(player, track)
    if not isElement(player) or not track then return end
    if track.provider == "archive" then
        local base = tostring(MUSIC_PROVIDER_CONFIG.archiveBaseUrl or "https://archive.org")
        local identifier = tostring(track.providerId or "")
        if identifier == "" then
            triggerClientEvent(player, "rp:music:playTrack", resourceRoot, track.key, track.streamUrl)
            return
        end
        local cached = resolvedUrls[identifier]
        if cached then
            triggerClientEvent(player, "rp:music:playTrack", resourceRoot, track.key, cached)
            return
        end
        local metadataUrl = base .. "/metadata/" .. urlEncode(identifier)
        fetchRemote(metadataUrl, function(body, statusCode)
            local statusNumber = tonumber(statusCode)
            local statusOk = statusNumber == 200 or statusNumber == 0
            if type(statusCode) == "table" then
                statusOk = statusCode.success == true
                    or tonumber(statusCode.statusCode) == 200
                    or tonumber(statusCode.status) == 200
            end
            outputDebugString(("[rp_phone][music] metadata id=%s bodyType=%s status=%s bytes=%d")
                :format(identifier, type(body), tostring(statusCode), type(body) == "string" and #body or 0))
            if not statusOk or type(body) ~= "string" or body == "" then
                notify(player, "No se pudo resolver el audio externo.", "warning")
                return
            end
            local metadata = fromJSON(body)
            local parsedFiles = type(metadata) == "table" and metadata.files or nil
            if type(parsedFiles) == "table" then
                outputDebugString(("[rp_phone][music] metadataFiles=%d"):format(#parsedFiles))
            end
            local resolved = nil
            local foundFormat = nil
            local directServer = tostring(type(metadata) == "table" and (metadata.d1 or metadata.d2) or "")
            local directDir = tostring(type(metadata) == "table" and (metadata.dir or "") or "")
            if directServer == "" then directServer = "ia800700.us.archive.org" end
            local function inspectFile(file)
                local name = tostring(file.name or "")
                local format = tostring(file.format or ""):lower()
                if not resolved and (name:match("%.mp3$") or name:match("%.ogg$") or format:find("mp3") or format:find("ogg")) then
                    foundFormat = format ~= "" and format or name:match("%.(%w+)$")
                    if directDir ~= "" then
                        resolved = "https://" .. directServer .. directDir .. "/" .. urlEncode(name)
                    else
                        resolved = base .. "/download/" .. urlEncode(identifier) .. "/" .. urlEncode(name)
                    end
                end
            end
            if type(parsedFiles) == "table" then
                for index = 1, #parsedFiles do
                    local file = parsedFiles[index]
                    if type(file) == "table" then inspectFile(file) end
                end
                if not resolved then
                    for _, file in pairs(parsedFiles) do
                        if type(file) == "table" then inspectFile(file) end
                    end
                end
            end
            if not resolved then
                local rawName = body:match([["name"%s*:%s*"([^"]+%.mp3)"]])
                if not rawName then rawName = body:match([["name"%s*:%s*"([^"]+%.ogg)"]]) end
                if rawName then
                    rawName = rawName:gsub("\\u(%x%x%x%x)", function(hex)
                        local code = tonumber(hex, 16)
                        if code and code < 128 then return string.char(code) end
                        return ""
                    end)
                    if directDir ~= "" then
                        resolved = "https://" .. directServer .. directDir .. "/" .. urlEncode(rawName)
                    else
                        resolved = base .. "/download/" .. urlEncode(identifier) .. "/" .. urlEncode(rawName)
                    end
                    foundFormat = rawName:match("%.(%w+)$")
                end
            end
            if not resolved then
                notify(player, "Esta grabacion no tiene MP3/Ogg compatible.", "warning")
                return
            end
            outputDebugString(("[rp_phone][music] resolved id=%s format=%s url=%s")
                :format(identifier, tostring(foundFormat), resolved))
            resolvedUrls[identifier] = resolved
            triggerClientEvent(player, "rp:music:playTrack", resourceRoot, track.key, resolved)
        end)
        return
    end
    triggerClientEvent(player, "rp:music:playTrack", resourceRoot, track.key, track.streamUrl)
end

local function sendTrackToListeners(track, state)
    if not track then return end
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if state.origin == "personal" and state.speaker and isInRange(state.owner or player, player, MUSIC_CONFIG.PERSON_DISTANCE) then
            sendTrackToPlayer(player, track)
        elseif state.origin == "vehicle" and isElement(state.vehicle) then
            local occupied = getPedOccupiedVehicle(player)
            if occupied == state.vehicle then
                sendTrackToPlayer(player, track)
            else
                local ax, ay, az = getElementPosition(state.vehicle)
                local bx, by, bz = getElementPosition(player)
                if getElementDimension(player) == getElementDimension(state.vehicle)
                    and getElementInterior(player) == getElementInterior(state.vehicle)
                    and getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz) <= MUSIC_CONFIG.VEHICLE_DISTANCE then
                    sendTrackToPlayer(player, track)
                end
            end
        end
    end
end

addEvent("rp:music:search", true)
addEvent("rp:music:play", true)
addEvent("rp:music:stop", true)
addEvent("rp:music:speaker", true)
addEvent("rp:music:volume", true)
addEvent("rp:music:vehicle", true)
addEvent("rp:music:favorite", true)
addEvent("rp:music:pause", true)
addEvent("rp:music:library", true)

addEventHandler("rp:music:search", resourceRoot, function(query)
    local player = client
    if not hasPhone(player) then return end
    outputDebugString(("[rp_phone][music] searchArg type=%s value=%s")
        :format(type(query), type(query) == "string" and query or tostring(query)))
    query = cleanQuery(query)
    if not query then return notify(player, "Escribe una busqueda valida.", "warning") end
    local now = getTickCount()
    if cooldownSearch[player] and now - cooldownSearch[player] < MUSIC_CONFIG.SEARCH_COOLDOWN_MS then return end
    cooldownSearch[player] = now

    local results = {}
    local lower = query:lower()
    for _, track in pairs(catalog) do
        local haystack = (track.title .. " " .. track.artist):lower()
        if haystack:find(lower, 1, true) then
            results[#results + 1] = publicTrack(track)
        end
    end
    table.sort(results, function(a, b)
        if a.artist == b.artist then return a.title < b.title end
        return a.artist < b.artist
    end)

    local cacheKey = "ia3:" .. query:lower()
    local cached = remoteSearchCache[cacheKey]
    if cached and getTickCount() - cached.at < 1800000 then
        triggerClientEvent(player, "rp:music:searchResults", resourceRoot, cached.results)
        return
    end
    dbQuery(function(cacheQh)
        local cacheRows = dbPoll(cacheQh, 0) or {}
        if cacheRows[1] and type(cacheRows[1].payload) == "string" then
            local cachedResults = fromJSON(cacheRows[1].payload)
            if type(cachedResults) == "table" then
                remoteSearchCache[cacheKey] = { at = getTickCount(), results = cachedResults }
                triggerClientEvent(player, "rp:music:searchResults", resourceRoot, cachedResults)
                return
            end
        end

        local base = tostring(MUSIC_PROVIDER_CONFIG.archiveBaseUrl or "https://archive.org")
        local queryText = query:gsub("[\"%%+]", " ")
        -- solo items de audio con MP3, si no la mayoria de resultados no se pueden reproducir
        queryText = "mediatype:audio AND format:MP3 AND (" .. queryText .. ")"
        local url = ("%s/advancedsearch.php?q=%s&fl%%5B%%5D=identifier&fl%%5B%%5D=title&fl%%5B%%5D=creator&rows=50&page=1&output=json")
            :format(base, urlEncode(queryText))
        fetchRemote(url, {
            method = "GET",
            headers = { ["Accept"] = "application/json", ["User-Agent"] = "Thorium-MTA/1.0" },
        }, function(body, statusCode)
            outputDebugString(("[rp_phone][music] fetchCallback bodyType=%s statusType=%s status=%s")
                :format(type(body), type(statusCode), tostring(statusCode)))
            local statusOk = tonumber(statusCode) == 200 or tonumber(statusCode) == 0
            if type(statusCode) == "table" then
                statusOk = statusCode.success == true
                    or tonumber(statusCode.statusCode) == 200
                    or tonumber(statusCode.status) == 200
            end
            if not statusOk or type(body) ~= "string" or body == "" then
                triggerClientEvent(player, "rp:music:searchResults", resourceRoot, results)
                return
            end
            outputDebugString(("[rp_phone][music] searchResponse bytes=%d status=%s"):format(#body, tostring(statusCode)))
        local data = fromJSON(body)
        outputDebugString(("[rp_phone][music] responsePrefix=%s"):format(tostring(body:sub(1, 120))))
        local docs = type(data) == "table" and type(data.response) == "table"
            and type(data.response.docs) == "table" and data.response.docs or nil
        if not docs then
            triggerClientEvent(player, "rp:music:searchResults", resourceRoot, results)
            return
        end
        outputDebugString(("[rp_phone][music] searchDocs=%d"):format(#docs))
        for _, item in ipairs(docs) do
            local identifier = tostring(item.identifier or "")
            if identifier ~= "" then
                local trackKey = "ia:" .. identifier
                local title = tostring(type(item.title) == "table" and item.title[1] or item.title or identifier)
                local artist = tostring(type(item.creator) == "table" and item.creator[1] or item.creator or "Internet Archive")
                local artwork = base .. "/services/img/" .. urlEncode(identifier)
                local streamUrl = base .. "/metadata/" .. urlEncode(identifier)
                addCatalogTrack({
                    key = trackKey,
                    provider = "archive",
                    providerId = identifier,
                    title = title,
                    artist = artist,
                    artwork = artwork,
                    streamUrl = streamUrl,
                    durationMs = 0,
                })
                results[#results + 1] = publicTrack(catalog[trackKey])
                dbExec(db(), [[
                    INSERT INTO music_tracks
                        (track_key, provider, provider_id, title, artist, artwork_url, stream_url, duration_ms)
                    VALUES (?, 'archive', ?, ?, ?, ?, ?, 0)
                    ON DUPLICATE KEY UPDATE
                        provider_id = VALUES(provider_id),
                        title = VALUES(title),
                        artist = VALUES(artist),
                        artwork_url = VALUES(artwork_url),
                        stream_url = VALUES(stream_url),
                        active = 1
                ]], trackKey, identifier, title, artist, artwork, streamUrl)
            end
        end
        local unique, deduped = {}, {}
        for _, track in ipairs(results) do
            if not unique[track.key] then unique[track.key] = true deduped[#deduped + 1] = track end
        end
        remoteSearchCache[cacheKey] = { at = getTickCount(), results = deduped }
        dbExec(db(), [[
            INSERT INTO music_search_cache (provider, query_key, payload, expires_at)
            VALUES ('archive', ?, ?, DATE_ADD(NOW(), INTERVAL 30 MINUTE))
            ON DUPLICATE KEY UPDATE payload = VALUES(payload), expires_at = VALUES(expires_at)
        ]], cacheKey, toJSON(deduped, true))
        triggerClientEvent(player, "rp:music:searchResults", resourceRoot, deduped)
        end)
    end, db(), "SELECT payload FROM music_search_cache WHERE provider = 'archive' AND query_key = ? AND expires_at > NOW()", cacheKey)
end)

addEventHandler("rp:music:play", resourceRoot, function(trackKey)
    local player = client
    if not hasPhone(player) then return end
    trackKey = tostring(trackKey or "")
    local now = getTickCount()
    if cooldownPlay[player] and now - cooldownPlay[player] < MUSIC_CONFIG.PLAY_COOLDOWN_MS then return end
    cooldownPlay[player] = now
    local track = catalog[trackKey]
    if not track then return notify(player, "Esa cancion no esta disponible.", "warning") end

    local vehicle = getPedOccupiedVehicle(player)
    local origin = "personal"
    if vehicle and vehicleCanControl(player, vehicle) then origin = "vehicle" end
    local previous = active[player]
    active[player] = {
        trackKey = trackKey,
        owner = player,
        origin = origin,
        vehicle = origin == "vehicle" and vehicle or nil,
        paused = false,
        position = 0,
        startedAt = getTickCount(),
        volume = previous and previous.volume or MUSIC_CONFIG.DEFAULT_VOLUME,
        -- el altavoz se conserva al cambiar de cancion
        speaker = origin == "personal" and previous ~= nil and previous.speaker == true,
    }
    syncPlayer(player)
    if origin == "vehicle" then
        silenceVehicleRadio(vehicle)
        syncVehicle(vehicle, active[player])
    end
    sendTrackToPlayer(player, track)
    sendTrackToListeners(track, active[player])
    sendState(player)
    sendCatalog(player)

    local characterId = characterOf(player)
    if characterId then
        dbExec(db(), "INSERT INTO music_history (character_id, track_key) VALUES (?, ?)", characterId, trackKey)
        sendLibrary(player)
    end
end)

addEventHandler("rp:music:stop", resourceRoot, function()
    local player = client
    if not hasPhone(player) then return end
    local state = active[player]
    if state and state.origin == "vehicle" and isElement(state.vehicle) then clearVehicleState(state.vehicle) end
    stopPlayer(player)
end)

addEventHandler("rp:music:pause", resourceRoot, function(paused)
    local player = client
    if not hasPhone(player) then return end
    local state = active[player]
    if not state then return end
    if paused == nil then paused = not state.paused end
    state.paused = paused == true
    if state.paused then
        state.position = state.position + math.max(0, getTickCount() - state.startedAt) / 1000
    end
    state.startedAt = getTickCount()
    syncPlayer(player)
    if state.origin == "vehicle" and isElement(state.vehicle) then syncVehicle(state.vehicle, state) end
    sendState(player)
end)

addEventHandler("rp:music:speaker", resourceRoot, function(enabled)
    local player = client
    if not hasPhone(player) then return end
    local state = active[player]
    if not state or state.origin == "vehicle" then
        return notify(player, "Desactiva el modo vehiculo antes de usar el altavoz.", "warning")
    end
    state.speaker = enabled == true
    syncPlayer(player)
    sendTrackToListeners(catalog[state.trackKey], state)
    sendState(player)
    notify(player, state.speaker and "Altavoz activado." or "Altavoz desactivado.", "success")
end)

addEventHandler("rp:music:volume", resourceRoot, function(volume)
    local player = client
    if not hasPhone(player) then return end
    volume = tonumber(volume)
    if not volume then return end
    volume = math.floor(math.max(0, math.min(MUSIC_CONFIG.MAX_VOLUME, volume)))
    local state = active[player]
    if not state then return end
    state.volume = volume
    syncPlayer(player)
    if state.origin == "vehicle" and isElement(state.vehicle) then
        syncVehicle(state.vehicle, state)
    end
    sendState(player)
end)

addEventHandler("rp:music:vehicle", resourceRoot, function(enabled)
    local player = client
    if not hasPhone(player) then return end
    local vehicle = getPedOccupiedVehicle(player)
    outputDebugString(("[rp_phone][music] vehicleToggle enabled=%s type=%s vehicle=%s seat=%s")
        :format(tostring(enabled), type(enabled), tostring(vehicle), tostring(getPedOccupiedVehicleSeat(player))))
    if enabled == true then
        if not vehicleCanControl(player, vehicle) then
            return notify(player, "Solo el conductor o copiloto pueden activar la radio.", "warning")
        end
        local state = active[player]
        if not state then return notify(player, "Primero elige una cancion.", "warning") end
        state.origin = "vehicle"
        state.vehicle = vehicle
        state.speaker = false
        silenceVehicleRadio(vehicle)
        syncPlayer(player)
        syncVehicle(vehicle, state)
        sendTrackToListeners(catalog[state.trackKey], state)
        sendState(player)
        notify(player, "Musica configurada para el vehiculo.", "success")
    else
        local state = active[player]
        if state and state.origin == "vehicle" and isElement(state.vehicle) then clearVehicleState(state.vehicle) end
        if state then
            state.origin = "personal"
            state.vehicle = nil
            syncPlayer(player)
            sendState(player)
        end
    end
end)

addEventHandler("rp:music:favorite", resourceRoot, function(trackKey)
    local player = client
    if not hasPhone(player) then return end
    trackKey = tostring(trackKey or "")
    if not catalog[trackKey] then return end
    local characterId = characterOf(player)
    if not characterId then return end
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0) or {}
        if rows and rows[1] then
            dbExec(db(), "DELETE FROM music_favorites WHERE character_id = ? AND track_key = ?", characterId, trackKey)
            triggerClientEvent(player, "rp:music:favoriteResult", resourceRoot, trackKey, false)
            sendLibrary(player)
        else
            dbExec(db(), "INSERT IGNORE INTO music_favorites (character_id, track_key) VALUES (?, ?)", characterId, trackKey)
            triggerClientEvent(player, "rp:music:favoriteResult", resourceRoot, trackKey, true)
            sendLibrary(player)
        end
    end, db(), "SELECT 1 FROM music_favorites WHERE character_id = ? AND track_key = ?", characterId, trackKey)
end)

addEventHandler("rp:phone:open", root, function()
    sendCatalog(client)
    sendState(client)
    sendLibrary(client)
end)

addEventHandler("rp:music:library", resourceRoot, function()
    local player = client
    if hasPhone(player) then sendLibrary(player) end
end)

setTimer(function()
    for _, state in pairs(active) do
        sendTrackToListeners(catalog[state.trackKey], state)
    end
end, 1500, 0)

addEventHandler("onPlayerQuit", root, function()
    -- si se va el dueño, el vehiculo no debe seguir sonando solo
    local state = active[source]
    if state and state.origin == "vehicle" then clearVehicleState(state.vehicle) end
    active[source] = nil
    cooldownSearch[source] = nil
    cooldownPlay[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(active) do
        if isElement(player) then
            syncPlayer(player)
            if active[player].origin == "vehicle" and isElement(active[player].vehicle) then
                clearVehicleState(active[player].vehicle)
            end
        end
    end
end)

function getMusicConfigErrors()
    local errors = {}
    if type(MUSIC_CONFIG) ~= "table" then errors[#errors + 1] = "falta MUSIC_CONFIG" end
    if type(MUSIC_DEMO_TRACKS) ~= "table" or #MUSIC_DEMO_TRACKS == 0 then errors[#errors + 1] = "falta catalogo local" end
    return errors
end

addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database and exports.rp_database:isReady() then loadLocalCatalog()
    else addEventHandler("rp:onDatabaseReady", root, loadLocalCatalog) end
end)
