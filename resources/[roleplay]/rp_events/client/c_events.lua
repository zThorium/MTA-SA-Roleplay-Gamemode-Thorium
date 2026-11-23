--[[
    rp_events / c_events.lua  (cliente)
      - Busca el punto del evento cuando el servidor se lo pide (usa la red vial y peatonal
        de rp_citizens, que solo existe aqui) y se lo devuelve para que lo valide.
      - Recibe la lista de eventos activos (pequena, solo cuando cambia) y hace que los
        peatones cercanos se paren a mirar.
      - Efectos visuales (humo y fuego) de los vehiculos de evento, solo mientras estan
        en el rango de carga del jugador.
]]

addEvent("rp:events:locate", true)
addEvent("rp:events:list", true)

local events = {}   -- lista recibida del servidor

local function spot(kind, forced)
    local ok, x, y, z, h = pcall(function()
        if kind == "walk" then
            if forced then return exports.rp_citizens:citizenWalkSpot(6, 22, false) end
            return exports.rp_citizens:citizenWalkSpot(55, 140, true)
        end
        if forced then return exports.rp_citizens:citizenRoadSpot(0, 0, false) end
        return exports.rp_citizens:citizenRoadSpot(60, 150, true)
    end)
    if ok and x then return x, y, z, h end
end

addEventHandler("rp:events:locate", resourceRoot, function(token, kind, forced)
    local x, y, z, h = spot(kind, forced)
    if not x then return end
    -- en aceras: hacia donde estan las casas (la calle queda al otro lado)
    local ax, ay
    if kind == "walk" then
        local ok, vx, vy = pcall(function() return exports.rp_citizens:citizenAwayFromRoad(x, y) end)
        if ok then ax, ay = vx, vy end
    end
    triggerServerEvent("rp:events:located", resourceRoot, token, x, y, z, h, ax, ay)
end)

addEventHandler("rp:events:list", resourceRoot, function(list)
    events = type(list) == "table" and list or {}
end)

-- Los curiosos: peatones cerca de un evento se paran a mirar
setTimer(function()
    if #events == 0 then return end
    local px, py = getElementPosition(localPlayer)
    for _, ev in ipairs(events) do
        if (px - ev.x) ^ 2 + (py - ev.y) ^ 2 < 8100 then   -- 90 m
            pcall(function() exports.rp_citizens:citizenWatch(ev.x, ev.y, 18, 9000) end)
        end
    end
end, 3000, 0)

----------------------------------------------------------------
-- Humo y fuego en vehiculos de evento (elementData "rp:fx")
----------------------------------------------------------------
local EFFECTS = {
    smoke = { "smoke30m", "smoke30lit", "smoke50lit" },
    fire = { "fire", "fire_med" },
}
local fx = {}   -- [vehiculo] = { kind, effect }

local function clearFx(v)
    local e = fx[v]
    if not e then return end
    if isElement(e.effect) then destroyElement(e.effect) end
    fx[v] = nil
end

local function applyFx(v)
    if not isElement(v) or not isElementStreamedIn(v) then return clearFx(v) end
    local kind = getElementData(v, "rp:fx")
    local cur = fx[v]
    if cur and cur.kind == kind then return end
    clearFx(v)
    local names = kind and EFFECTS[kind]
    if not names then return end
    local m = getElementMatrix(v)
    -- delante del capo, algo elevado
    local x = m[4][1] + m[2][1] * 1.7 + m[3][1] * 0.6
    local y = m[4][2] + m[2][2] * 1.7 + m[3][2] * 0.6
    local z = m[4][3] + m[2][3] * 1.7 + m[3][3] * 0.6
    for _, name in ipairs(names) do
        local e = createEffect(name, x, y, z, 0, 0, 0, 80)
        if e then
            fx[v] = { kind = kind, effect = e }
            return
        end
    end
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" and getElementData(source, "rp:fx") then applyFx(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if fx[source] then clearFx(source) end
end)

addEventHandler("onClientElementDestroy", root, function()
    if fx[source] then clearFx(source) end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:fx" and getElementType(source) == "vehicle" then applyFx(source) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementData(v, "rp:fx") then applyFx(v) end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rp:events:ready", resourceRoot)
end)
