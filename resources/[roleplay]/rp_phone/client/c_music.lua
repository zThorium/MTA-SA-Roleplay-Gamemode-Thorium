--[[
    rp_phone / c_music.lua

    Reproduce el estado musical que publica rp_phone/s_music.lua:
    privado con playSound, altavoz con playSound3D y vehiculo adjunto al vehiculo.
]]

local catalog = {}
local streamUrls = {}
local localState = nil
local localSound = nil
local playerSounds = {}
local vehicleSounds = {}

outputDebugString("[rp_phone][music] cliente cargado")

addEvent("rp:music:catalog", true)
addEvent("rp:music:searchResults", true)
addEvent("rp:music:state", true)
addEvent("rp:music:favoriteResult", true)
addEvent("rp:music:playTrack", true)
addEvent("rp:music:library", true)

local function callJS(code)
    if Phone and Phone.callJS then Phone.callJS(code) end
end

local function jsTable(list)
    return toJSON(list or {}, true) .. "[0]"
end

local function destroySound(info)
    if info and isElement(info.sound) then destroyElement(info.sound) end
end

local function stopLocalSound()
    destroySound(localSound)
    localSound = nil
end

local function stopPlayerSound(player)
    destroySound(playerSounds[player])
    playerSounds[player] = nil
end

local function stopVehicleSound(vehicle)
    destroySound(vehicleSounds[vehicle])
    vehicleSounds[vehicle] = nil
end

local function setVolume(info, volume)
    if info and isElement(info.sound) then
        setSoundVolume(info.sound, math.max(0, math.min(1, (tonumber(volume) or 60) / 100)))
    end
end

local function setPaused(info, paused)
    if info and isElement(info.sound) and setSoundPaused then
        setSoundPaused(info.sound, paused == true)
    end
end

local function getTrack(trackKey)
    local track = catalog[trackKey]
    if track and streamUrls[trackKey] then
        track.streamUrl = streamUrls[trackKey]
    end
    return track
end

local function startLocal(track, state)
    stopLocalSound()
    if not track then return end
    outputDebugString(("[rp_phone][music] clientPlay key=%s url=%s"):format(tostring(track.key), tostring(track.streamUrl or "")))
    local sound = playSound(track.streamUrl or "", false)
    if not sound then
        outputDebugString(("[rp_phone][music] playSound fallo key=%s"):format(tostring(track.key)), 2)
        return
    end
    outputDebugString(("[rp_phone][music] playSound creado key=%s"):format(tostring(track.key)))
    setVolume({ sound = sound }, state.volume)
    if state.position and state.position > 0 then setSoundPosition(sound, state.position) end
    setPaused({ sound = sound }, state.paused)
    localSound = { sound = sound, trackKey = state.trackKey, state = state }
end

local function reconcileLocal()
    if not localState or not localState.trackKey then
        stopLocalSound()
        return
    end
    if type(setSoundPaused) ~= "function" then
        if localState.paused then
            if localSound and isElement(localSound.sound) and getSoundPosition then
                local position = getSoundPosition(localSound.sound)
                localState.position = position
            end
            stopLocalSound()
            return
        end
        if not localSound then
            local track = getTrack(localState.trackKey)
            if track then startLocal(track, localState) end
        end
        return
    end
    local track = getTrack(localState.trackKey)
    if not track then
        stopLocalSound()
        return
    end
    if not localSound or localSound.trackKey ~= localState.trackKey then
        if localState.origin == "vehicle" then
            stopLocalSound()
        else
            startLocal(track, localState)
        end
    else
        setVolume(localSound, localState.volume)
        setPaused(localSound, localState.paused)
    end
end

local function reconcilePlayerSpeakers()
    local seen = {}
    local px, py, pz = getElementPosition(localPlayer)
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if player ~= localPlayer and getElementData(player, "rp:musicSpeaker") == true then
            local trackKey = getElementData(player, "rp:musicTrackKey")
            local track = getTrack(trackKey)
            if track then
                if getElementDimension(player) ~= getElementDimension(localPlayer)
                    or getElementInterior(player) ~= getElementInterior(localPlayer) then
                    stopPlayerSound(player)
                else
                    local ax, ay, az = getElementPosition(player)
                    if getDistanceBetweenPoints3D(px, py, pz, ax, ay, az) <= MUSIC_CONFIG.PERSON_DISTANCE then
                        seen[player] = true
                        if not playerSounds[player] or playerSounds[player].trackKey ~= trackKey then
                            stopPlayerSound(player)
                            local sound = playSound3D(track.streamUrl or "", ax, ay, az, false)
                            if sound then
                                attachElements(sound, player)
                                setSoundMinDistance(sound, 3)
                                setSoundMaxDistance(sound, MUSIC_CONFIG.PERSON_DISTANCE)
                                setVolume({ sound = sound }, getElementData(player, "rp:musicVolume") or 60)
                                setPaused({ sound = sound }, getElementData(player, "rp:musicPaused") == true)
                                playerSounds[player] = { sound = sound, trackKey = trackKey }
                            end
                        else
                            setVolume(playerSounds[player], getElementData(player, "rp:musicVolume") or 60)
                            setPaused(playerSounds[player], getElementData(player, "rp:musicPaused") == true)
                        end
                    else
                        stopPlayerSound(player)
                    end
                end
            else
                stopPlayerSound(player)
            end
        else
            stopPlayerSound(player)
        end
    end
    for player in pairs(playerSounds) do
        if not seen[player] or not isElement(player) then stopPlayerSound(player) end
    end
end

local function reconcileVehicleAudio()
    local mine = getPedOccupiedVehicle(localPlayer)
    local seen = {}
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        local trackKey = getElementData(vehicle, "rp:musicTrackKey")
        local track = getTrack(trackKey)
        if track and isElement(vehicle) then
            seen[vehicle] = true
            if mine == vehicle then
                stopVehicleSound(vehicle)
                if not localSound or localSound.trackKey ~= trackKey then
                    startLocal(track, {
                        trackKey = trackKey,
                        position = tonumber(getElementData(vehicle, "rp:musicPosition")) or 0,
                        volume = tonumber(getElementData(vehicle, "rp:musicVolume")) or 60,
                        paused = getElementData(vehicle, "rp:musicPaused") == true,
                    })
                    if localSound then localSound.vehicle = vehicle end
                else
                    setVolume(localSound, tonumber(getElementData(vehicle, "rp:musicVolume")) or 60)
                    setPaused(localSound, getElementData(vehicle, "rp:musicPaused") == true)
                end
            else
                if getElementDimension(vehicle) == getElementDimension(localPlayer)
                    and getElementInterior(vehicle) == getElementInterior(localPlayer) then
                    local vx, vy, vz = getElementPosition(vehicle)
                    local px, py, pz = getElementPosition(localPlayer)
                    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= MUSIC_CONFIG.VEHICLE_DISTANCE then
                        if not vehicleSounds[vehicle] or vehicleSounds[vehicle].trackKey ~= trackKey then
                            stopVehicleSound(vehicle)
                            local sound = playSound3D(track.streamUrl or "", vx, vy, vz, false)
                            if sound then
                                attachElements(sound, vehicle)
                                setSoundMinDistance(sound, 8)
                                setSoundMaxDistance(sound, MUSIC_CONFIG.VEHICLE_DISTANCE)
                                setVolume({ sound = sound }, tonumber(getElementData(vehicle, "rp:musicVolume")) or 60)
                                setPaused({ sound = sound }, getElementData(vehicle, "rp:musicPaused") == true)
                                vehicleSounds[vehicle] = { sound = sound, trackKey = trackKey }
                            end
                        else
                            setVolume(vehicleSounds[vehicle], tonumber(getElementData(vehicle, "rp:musicVolume")) or 60)
                            setPaused(vehicleSounds[vehicle], getElementData(vehicle, "rp:musicPaused") == true)
                        end
                    else
                        stopVehicleSound(vehicle)
                    end
                else
                    stopVehicleSound(vehicle)
                end
            end
        else
            stopVehicleSound(vehicle)
        end
    end
    for vehicle in pairs(vehicleSounds) do
        if not seen[vehicle] or not isElement(vehicle) then stopVehicleSound(vehicle) end
    end
end

local function reconcile()
    reconcileLocal()
    reconcilePlayerSpeakers()
    reconcileVehicleAudio()
end

addEventHandler("rp:music:catalog", resourceRoot, function(items)
    catalog = {}
    for _, track in ipairs(type(items) == "table" and items or {}) do
        if track and track.key then catalog[track.key] = track end
    end
    callJS(("RP.music.setCatalog(%s)"):format(jsTable(items or {})))
end)

addEventHandler("rp:music:searchResults", resourceRoot, function(items)
    for _, track in ipairs(type(items) == "table" and items or {}) do
        if track and track.key then catalog[track.key] = track end
    end
    callJS(("RP.music.setSearchResults(%s)"):format(jsTable(items or {})))
end)

addEventHandler("rp:music:state", resourceRoot, function(state)
    localState = type(state) == "table" and state or nil
    callJS(("RP.music.setState(%s)"):format(localState and toJSON(localState, true) .. "[0]" or "null"))
    reconcile()
end)

addEventHandler("rp:music:favoriteResult", resourceRoot, function(trackKey, favorite)
    callJS(("RP.music.setFavorite(%s, %s)")
        :format(toJSON(trackKey, true), tostring(favorite == true)))
end)

addEventHandler("rp:music:playTrack", resourceRoot, function(trackKey, streamUrl)
    trackKey = tostring(trackKey or "")
    streamUrl = tostring(streamUrl or "")
    if trackKey == "" or streamUrl == "" then return end
    streamUrls[trackKey] = streamUrl
    reconcile()
end)

addEventHandler("rp:music:library", resourceRoot, function(favorites, history)
    callJS(("RP.music.setLibrary(%s, %s)")
        :format(jsTable(favorites or {}), jsTable(history or {})))
end)

addEvent("rp:phone:ui:musicSearch", false)
addEvent("rp:phone:ui:musicPlay", false)
addEvent("rp:phone:ui:musicStop", false)
addEvent("rp:phone:ui:musicSpeaker", false)
addEvent("rp:phone:ui:musicVolume", false)
addEvent("rp:phone:ui:musicVehicle", false)
addEvent("rp:phone:ui:musicFavorite", false)
addEvent("rp:phone:ui:musicPause", false)
addEvent("rp:phone:ui:musicLibrary", false)

addEventHandler("rp:phone:ui:musicSearch", root, function(query)
    outputDebugString(("[rp_phone][music] c_searchArg type=%s value=%s")
        :format(type(query), type(query) == "string" and query or tostring(query)))
    if type(query) == "table" then
        query = query[1] or query[0] or query.query or query.text or query.value
    end
    if type(query) ~= "string" then query = tostring(query or "") end
    triggerServerEvent("rp:music:search", resourceRoot, query)
end)
addEventHandler("rp:phone:ui:musicPlay", root, function(trackKey)
    triggerServerEvent("rp:music:play", resourceRoot, tostring(trackKey or ""))
end)
addEventHandler("rp:phone:ui:musicStop", root, function()
    triggerServerEvent("rp:music:stop", resourceRoot)
end)
addEventHandler("rp:phone:ui:musicSpeaker", root, function(enabled)
    triggerServerEvent("rp:music:speaker", resourceRoot, enabled == true)
end)
addEventHandler("rp:phone:ui:musicVolume", root, function(volume)
    triggerServerEvent("rp:music:volume", resourceRoot, tonumber(volume))
end)
addEventHandler("rp:phone:ui:musicVehicle", root, function(enabled)
    triggerServerEvent("rp:music:vehicle", resourceRoot, enabled == true)
end)
addEventHandler("rp:phone:ui:musicFavorite", root, function(trackKey)
    triggerServerEvent("rp:music:favorite", resourceRoot, tostring(trackKey or ""))
end)
addEventHandler("rp:phone:ui:musicPause", root, function(paused)
    triggerServerEvent("rp:music:pause", resourceRoot, paused)
end)
addEventHandler("rp:phone:ui:musicLibrary", root, function()
    triggerServerEvent("rp:music:library", resourceRoot)
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:musicTrackKey" or key == "rp:musicVolume" or key == "rp:musicSpeaker"
        or key == "rp:musicPaused" then
        reconcile()
    end
end)

setTimer(reconcile, 750, 0)

addEventHandler("onClientSoundStopped", root, function(sound)
    for _, info in pairs(playerSounds) do
        if info and info.sound == sound then
            outputDebugString("[rp_phone][music] sonido 3D detenido")
            return
        end
    end
    if localSound and localSound.sound == sound then
        outputDebugString("[rp_phone][music] sonido local detenido")
    end
end)

addEventHandler("onClientPlayerQuit", root, function()
    stopPlayerSound(source)
end)

addEventHandler("onClientPlayerVehicleExit", localPlayer, function()
    reconcile()
end)

addEventHandler("onClientPlayerVehicleEnter", localPlayer, function()
    reconcile()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopLocalSound()
    for player in pairs(playerSounds) do stopPlayerSound(player) end
    for vehicle in pairs(vehicleSounds) do stopVehicleSound(vehicle) end
end)
