--[[
    rp_factions / c_api.lua
    API de facciones en el cliente (misma forma que la del servidor, solo lectura).
    Lee el dato público que publica el servidor ("rp:faction"), así los demás recursos
    de cliente no dependen de su formato. El cliente nunca decide permisos: solo muestra.

        exports.rp_factions:isPlayerInFaction(player [, which])   which = id o tipo ("policia")
        exports.rp_factions:getPlayerFactionId(player)
        exports.rp_factions:getPlayerFactionType(player)
        exports.rp_factions:getPlayerFactionInfo(player)          { id, name, tag, type, color, rank, leader }
        exports.rp_factions:isPlayerOnDuty(player [, which])      según FACTION_TYPES[tipo].dutyData; tipos sin servicio: false
]]

local function data(player)
    local f = isElement(player) and getElementData(player, "rp:faction")
    return type(f) == "table" and f or nil
end

function isPlayerInFaction(player, which)
    local f = data(player)
    if not f then return false end
    if which == nil or which == true then return true end
    local n = tonumber(which)
    if n then return tonumber(f.id) == n end
    return f.type == tostring(which):lower()
end

function getPlayerFactionId(player)
    local f = data(player)
    return f and tonumber(f.id) or false
end

function getPlayerFactionType(player)
    local f = data(player)
    return f and f.type or false
end

function getPlayerFactionInfo(player)
    local f = data(player)
    if not f then return false end
    return { id = tonumber(f.id), name = f.name, tag = f.tag, type = f.type, color = f.color, rank = f.rank, leader = f.leader }
end

function isPlayerOnDuty(player, which)
    if not isPlayerInFaction(player, which) then return false end
    local t = FACTION_TYPES[data(player).type]
    return (t and t.dutyData and getElementData(player, t.dutyData) == true) and true or false
end
