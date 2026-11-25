--[[
    rp_mocap / server / s_mocap.lua

    API de servidor para reproducir clips de mocap (las animaciones personalizadas NO se sincronizan solas: el servidor avisa a
    cada cliente y cada uno las aplica al ped/jugador localmente).

        exports.rp_mocap:hasCharacter("sweet")                    -> true/false
        exports.rp_mocap:getClipCount("sweet", "gesture")         -> n   (kind: "gesture" | "idle")
        exports.rp_mocap:pickClip("sweet", "gesture", ultimo)     -> indice al azar distinto de `ultimo`
        exports.rp_mocap:play(jugadores, ped, "sweet", "gesture", indice, loop)   (loop por defecto: true solo para idle)
        exports.rp_mocap:stop(jugadores, ped)

    `jugadores` es la lista de jugadores que deben verlo (p. ej. los integrantes de la mision).
    Catalogo y detalles: MOCAP_CATALOGO.md. Personajes: ver shared/mocap_catalog.lua.
]]

local function clips(char, kind)
    local c = MOCAP[char]
    local list = {}
    if c then
        for _, clip in ipairs(c.clips) do if clip.kind == kind then list[#list + 1] = clip end end
    end
    return list
end

function hasCharacter(char) return MOCAP[char] ~= nil end

function getClipCount(char, kind) return #clips(char, kind) end

function pickClip(char, kind, last)
    local n = #clips(char, kind)
    if n == 0 then return false end
    if n == 1 then return 1 end
    local i = math.random(n)
    if i == last then i = i % n + 1 end
    return i
end

local function send(players, event, ...)
    if type(players) ~= "table" then return false end
    for _, p in ipairs(players) do
        if isElement(p) and getElementType(p) == "player" then triggerClientEvent(p, event, resourceRoot, ...) end
    end
    return true
end

addEvent("rp:mocap:result", true)
addEventHandler("rp:mocap:result", resourceRoot, function(text)
    if client then outputChatBox("[mocap] cliente: " .. tostring(text):sub(1, 220), client, 120, 220, 255) end
end)

function play(players, ped, char, kind, index, loop, debug)
    if not isElement(ped) or not MOCAP[char] then return false end
    local list = clips(char, kind)
    index = tonumber(index) or 1
    if not list[index] then return false end
    if loop == nil then loop = kind == "idle" end
    return send(players, "rp:mocap:play", ped, char, list[index].name, loop and true or false, debug and true or false)
end

function stop(players, ped)
    if not isElement(ped) then return false end
    return send(players, "rp:mocap:stop", ped)
end

----------------------------------------------------------------
-- Comandos de prueba (admin nivel 2)
--   /mocap <personaje> <gesture|idle> [n]   reproduce el clip n en ti (solo lo ves tu); sin n = al azar
--   /mocap lista                            personajes y cantidad de clips
--   /mocapped <personaje>                   ped de prueba con la skin del personaje que alterna idle y gestos (otra vez = lo quita)
--   /mocapparar                             te quita la animacion
----------------------------------------------------------------
local SKINS = { sweet = 270, ryder = 271, smoke = 271, cesar = 292, cj = 0, kendl = 269, tenpenny = 280, bigbear = 271 }
local demo = {}   -- [admin] = { ped, timer }

local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 2 end
local function say(p, text) outputChatBox("[mocap] " .. text, p, 120, 220, 255) end

addCommandHandler("mocap", function(player, _, char, kind, n)
    if not isAdmin(player) then return end
    if not char or char == "lista" then
        local names = {}
        for c in pairs(MOCAP) do names[#names + 1] = ("%s(%dg/%di)"):format(c, getClipCount(c, "gesture"), getClipCount(c, "idle")) end
        table.sort(names)
        return say(player, table.concat(names, "  "))
    end
    kind = kind == "idle" and "idle" or "gesture"
    if not hasCharacter(char) then return say(player, "Personaje desconocido. /mocap lista") end
    local idx = tonumber(n) or pickClip(char, kind)
    local ok = play({ player }, player, char, kind, idx, nil, true)
    say(player, ("%s %s #%s -> %s"):format(char, kind, tostring(idx), tostring(ok)))
end)

addCommandHandler("mocapparar", function(player)
    if isAdmin(player) then stop({ player }, player) end
end)

local function removeDemo(player)
    local d = demo[player]
    if not d then return end
    if isTimer(d.timer) then killTimer(d.timer) end
    if isElement(d.ped) then stop({ player }, d.ped) destroyElement(d.ped) end
    demo[player] = nil
end

addCommandHandler("mocapped", function(player, _, char)
    if not isAdmin(player) then return end
    if demo[player] then removeDemo(player) return say(player, "Ped de prueba quitado") end
    if not char or not hasCharacter(char) then return say(player, "Uso: /mocapped <personaje>  (ver /mocap lista)") end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local a = math.rad(rz)
    local ped = createPed(SKINS[char] or 270, x - math.sin(a) * 2.2, y + math.cos(a) * 2.2, z, rz + 180)
    setElementDimension(ped, getElementDimension(player))
    setElementInterior(ped, getElementInterior(player))
    local state = { ped = ped, last = nil }
    demo[player] = state
    play({ player }, ped, char, "idle", pickClip(char, "idle") or 1)
    local nextIsGesture = true
    state.timer = setTimer(function()
        if not isElement(player) or not isElement(ped) then return removeDemo(player) end
        if nextIsGesture then
            local idx = pickClip(char, "gesture", state.last)
            state.last = idx
            play({ player }, ped, char, "gesture", idx)
        else
            play({ player }, ped, char, "idle", pickClip(char, "idle") or 1)
        end
        nextIsGesture = not nextIsGesture
    end, 3100, 0)
    say(player, ("Ped de %s creado: idle y gestos alternando. /mocapped otra vez para quitarlo."):format(char))
end)

addEventHandler("onPlayerQuit", root, function() removeDemo(source) end)
addEventHandler("onResourceStop", resourceRoot, function() for p in pairs(demo) do removeDemo(p) end end)
