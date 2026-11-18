--[[
    rp_adminpanel / s_adminpanel.lua

    Panel CEF de referencia para administradores: lista los comandos de
    administracion con su descripcion. El catalogo esta en s_catalog.lua.

    Comandos:
        /adminpanel, /apanel     (admin) abre el panel (tambien F10)
]]

local cooldown = {}   -- [player] = tick

addEvent("rp:adminpanel:open", true)

local function notify(p, t, k, d) exports.rp_notify:notify(p, t, k, d) end
local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

local function open(player)
    if not isAdmin(player) then
        return notify(player, "No tienes permiso para usar este comando.", "error")
    end
    local now = getTickCount()
    if cooldown[player] and now - cooldown[player] < 400 then return end
    cooldown[player] = now
    triggerClientEvent(player, "rp:adminpanel:show", resourceRoot, ADMIN_CATALOG)
end

addCommandHandler("adminpanel", open)
addCommandHandler("apanel", open)

addEventHandler("rp:adminpanel:open", resourceRoot, function()
    open(client)
end)

addEventHandler("onPlayerQuit", root, function() cooldown[source] = nil end)
