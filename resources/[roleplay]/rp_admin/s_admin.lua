--[[
    rp_admin / s_admin.lua
    Herramientas de administracion. Por ahora: /freecam.
]]

local function isAdmin(p) return (exports.rp_login:getPlayerAdminLevel(p) or 0) >= 1 end

addCommandHandler("freecam", function(player)
    if not isAdmin(player) then
        return exports.rp_notify:notify(player, "No tienes permiso para usar este comando.", "error")
    end
    triggerClientEvent(player, "rp:admin:freecam", resourceRoot)
end)
