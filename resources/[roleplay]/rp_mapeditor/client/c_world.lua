--[[
    rp_mapeditor / c_world.lua
    Parte del cliente que corre para TODOS los jugadores:
      - ajustes de mapa (hora, clima, gravedad...) de los mapas publicados fuera del mundo abierto,
        aplicados solo mientras estás en su dimensión; en el editor, los del borrador.
      - peds decorativos: animación en bucle e invulnerables; objetos rompibles.
    API (global del cliente): MEWorld.applySettings(ctx, s) / MEWorld.restoreSettings()
]]

MEWorld = {}

local applied = nil    -- { ctx, orig = { weather, h, m, tick, gravity, speed, waves } }

local function restoreTime(o)
    -- el reloj siguió corriendo mientras estabas dentro: se devuelve la hora que tocaría ahora
    local dur = getMinuteDuration() or 1000
    local mins = math.floor((getTickCount() - o.tick) / math.max(dur, 1))
    local total = (o.h * 60 + o.m + mins) % 1440
    setTime(math.floor(total / 60), total % 60)  -- estandar:mundo (ajuste del mapa, solo en este cliente y en su dimensión)
end

function MEWorld.restoreSettings()
    if not applied then return end
    local o = applied.orig
    if o.weather then setWeather(o.weather) end  -- estandar:mundo (ajuste del mapa, solo en este cliente y en su dimensión)
    if o.h then restoreTime(o) end
    if o.gravity then setGravity(o.gravity) end
    if o.speed then setGameSpeed(o.speed) end
    if o.waves then setWaveHeight(o.waves) end
    if o.farclip then resetFarClipDistance() end
    applied = nil
end

function MEWorld.applySettings(ctx, s)
    s = type(s) == "table" and s or {}
    local key = toJSON(s)
    if applied and applied.ctx == ctx and applied.key == key then return end
    MEWorld.restoreSettings()
    if not next(s) then return end
    local h, m = getTime()
    applied = { ctx = ctx, key = key, s = s, orig = { tick = getTickCount() } }
    local o = applied.orig
    if s.hour then o.h, o.m = h, m end
    if s.weather then o.weather = getWeather() setWeather(s.weather) end  -- estandar:mundo (ajuste del mapa, solo en este cliente y en su dimensión)
    if s.gravity then o.gravity = getGravity() setGravity(s.gravity) end
    if s.speed then o.speed = getGameSpeed() setGameSpeed(s.speed) end
    if s.waves then o.waves = getWaveHeight() setWaveHeight(s.waves) end
    if s.farclip then o.farclip = true setFarClipDistance(s.farclip) end
    if s.hour then setTime(s.hour, s.minute or 0) end  -- estandar:mundo (ajuste del mapa, solo en este cliente y en su dimensión)
end

-- La hora fija se reimpone cada segundo (si no, el reloj del juego avanza)
local enforceTimer = setTimer(function()
    if MEEditor and MEEditor.active then
        if applied and applied.s and applied.s.hour then setTime(applied.s.hour, applied.s.minute or 0) end  -- estandar:mundo (ajuste del mapa, solo en este cliente y en su dimensión)
        return
    end
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local found
    if dim ~= 0 then
        for _, e in ipairs(getElementData(resourceRoot, "rp:me:live") or {}) do
            if e.dim == dim and e.int == int then found = e break end
        end
    end
    if found then
        MEWorld.applySettings("live:" .. dim, found.settings)
        if applied and applied.s and applied.s.hour then setTime(applied.s.hour, applied.s.minute or 0) end  -- estandar:mundo (ajuste del mapa, solo en este cliente y en su dimensión)
    elseif applied and applied.ctx:sub(1, 5) == "live:" then
        MEWorld.restoreSettings()
    end
end, 1000, 0)

-- Peds decorativos y objetos rompibles
local function prepare(el)
    if not isElement(el) then return end
    local t = getElementType(el)
    if t == "ped" then
        local a = getElementData(el, "rp:me:anim")
        if type(a) == "table" and a[1] and a[2] then setPedAnimation(el, a[1], a[2], -1, true, false, false, false) end
    elseif t == "object" and getElementData(el, "rp:me:brk") then
        setObjectBreakable(el, true)
    end
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementData(source, "rp:mapedit") then prepare(source) end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:me:anim" or key == "rp:me:brk" then prepare(source) end
end)

addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:me:deco") then cancelEvent() end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, t in ipairs({ "ped", "object" }) do
        for _, el in ipairs(getElementsByType(t, root, true)) do
            if getElementData(el, "rp:mapedit") then prepare(el) end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(enforceTimer) then killTimer(enforceTimer) end
    MEWorld.restoreSettings()
end)
