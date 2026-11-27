--[[
    rp_events / s_world.lua
    Reloj y clima compartidos. Antes cada cliente tenia su propio tiempo; ahora el
    servidor manda: la hora avanza a WORLD.MINUTE_MS por minuto de juego y el clima
    sigue una maquina de estados con transiciones ponderadas y cambios graduales.

    Exports (servidor):
        getWorldState()        -> { hour, minute, weather, label, id, raining, night, since }
        setWeatherState(name, instant, id) -> true | false (nombre o variante invalidos)

    Evento de servidor (para otros recursos):
        rp:events:onWorldChanged (weather, previous)   source = resourceRoot

    elementData publico: root "rp:world" = { weather, label, raining, id }
]]

addEvent("rp:events:onWorldChanged", false)

local state = { weather = WORLD.START_WEATHER, id = 0, since = 0 }
local weatherTimer

local function pickWeighted(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + w end
    local r = math.random() * total
    for name, w in pairs(weights) do
        r = r - w
        if r <= 0 then return name end
    end
end

local function publish()
    local def = WORLD.WEATHER[state.weather]
    setElementData(root, "rp:world", { weather = state.weather, label = def.label, raining = def.rain, id = state.id })
end

local function scheduleNext()
    if isTimer(weatherTimer) then killTimer(weatherTimer) end
    local def = WORLD.WEATHER[state.weather]
    local secs = math.random(def.dwell[1], def.dwell[2])
    weatherTimer = setTimer(function()
        local nextName = pickWeighted(def.next) or "sun"
        setWeatherState(nextName)
    end, secs * 1000, 1)
end

function setWeatherState(name, instant, id)
    local def = WORLD.WEATHER[name]
    if not def then return false end
    -- id opcional: una variante concreta del estado (la que el admin vio en /clima)
    if id ~= nil then
        local ok = false
        for _, v in ipairs(def.ids) do if v == id then ok = true end end
        if not ok then return false end
    end
    local previous = state.weather
    state.weather = name
    state.id = id or def.ids[math.random(#def.ids)]
    state.since = getRealTime().timestamp
    if instant then setWeather(state.id) else setWeatherBlended(state.id) end
    publish()
    scheduleNext()
    if previous ~= name then
        triggerEvent("rp:events:onWorldChanged", resourceRoot, name, previous)
        outputServerLog(("[rp_events] clima: %s -> %s (id %d)"):format(previous, name, state.id))
    end
    return true
end

function getWorldState()
    local hour, minute = getTime()
    local def = WORLD.WEATHER[state.weather]
    return {
        hour = hour, minute = minute, weather = state.weather, label = def.label, id = state.id,
        raining = def.rain, night = hour >= 21 or hour < 6, since = state.since,
    }
end

-- Hora de juego a partir del reloj real: continua entre reinicios
local timeOffset = 0   -- ajuste de /hora (minutos de juego)

local function baseMinutes()
    return math.floor(getRealTime().timestamp * 1000 / WORLD.MINUTE_MS) % 1440
end

local function syncClock()
    setMinuteDuration(WORLD.MINUTE_MS)
    local gm = (baseMinutes() + timeOffset) % 1440
    setTime(math.floor(gm / 60), gm % 60)
end

function setGameTime(hour, minute)
    timeOffset = ((hour * 60 + (minute or 0)) - baseMinutes()) % 1440
    syncClock()
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    syncClock()
    setWeatherState(WORLD.START_WEATHER, true)
end)

-- Rebote del reloj: un cuelgue largo del servidor no debe dejar la hora desfasada
setTimer(syncClock, 30 * 60 * 1000, 0)
