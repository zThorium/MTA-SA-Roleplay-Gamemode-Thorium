--[[
    rp_nametags / s_ame.lua
    /ame [accion]: etiqueta sobre la cabeza con la accion del personaje (la dibuja c_nametags).
    Se guarda en element data "rp:ame" (se sincroniza a todos) y se borra sola.

    Export (servidor):
        setAme(player, texto, ms)  -> true | false
]]

local MAX_LEN, MIN_MS, MAX_MS = 80, 4000, 10000
local timers = {}   -- [player] = timer
local lastUse = {}  -- [player] = tick (anti spam del comando)

function setAme(player, text, ms)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    text = tostring(text or ""):gsub("[%c]", " "):sub(1, MAX_LEN)
    if text:gsub("%s", "") == "" then return false end
    ms = math.max(MIN_MS, math.min(MAX_MS, tonumber(ms) or (#text * 90)))

    if isTimer(timers[player]) then killTimer(timers[player]) end
    setElementData(player, "rp:ame", text)
    timers[player] = setTimer(function()
        if isElement(player) then removeElementData(player, "rp:ame") end
        timers[player] = nil
    end, ms, 1)
    return true
end

addCommandHandler("ame", function(player, _, ...)
    if not getElementData(player, "rp:characterId") then return end
    local now = getTickCount()
    if lastUse[player] and now - lastUse[player] < 1500 then return end
    lastUse[player] = now

    local text = table.concat({ ... }, " ")
    if text:gsub("%s", "") == "" then
        return exports.rp_notify:notify(player, "Uso: /ame [acción]  (ej: /ame mira su reloj)", "info")
    end
    setAme(player, text)
end)

addEventHandler("onPlayerQuit", root, function()
    if isTimer(timers[source]) then killTimer(timers[source]) end
    timers[source], lastUse[source] = nil, nil
end)
