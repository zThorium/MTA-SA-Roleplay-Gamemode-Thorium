--[[
    rp_scoreboard / s_scoreboard.lua
    Publica el nombre del servidor y el maximo de jugadores para el cliente
    (getServerName solo existe en el servidor).
]]

addEventHandler("onResourceStart", resourceRoot, function()
    setElementData(resourceRoot, "server:name", getServerName())
    setElementData(resourceRoot, "server:maxPlayers", getMaxPlayers())
end)
