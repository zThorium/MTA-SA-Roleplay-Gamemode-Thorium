--[[
    rp_emergency / c_walk.lua
    Movimiento a pie de los paramedicos.

    Antes se movian con los controles del ped (forward/sprint) desde el cliente que
    "sincroniza" el ped. Si ese cliente no era el syncer real o no tenia el ped cargado,
    no se movian nunca y el servidor los teletransportaba al vencer el tiempo.

    Ahora:
      1. El servidor pide el camino al cliente de quien llamo (rp:emergency:pathRequest):
         solo el cliente tiene la colision del mapa para esquivar autos, muros y postes.
      2. El servidor valida el camino, pone la animacion de correr o caminar (sin que la
         animacion mueva al ped), le quita el syncer y lo envia a todos los jugadores
         cercanos con la duracion (rp:emergency:move).
      3. Cada cliente desplaza el ped por ese camino a la misma velocidad, cuadro a cuadro.
         Todos lo ven correr por el mismo sitio y llegar a la vez; al terminar, el servidor
         lo deja en el punto final (donde ya esta) y le devuelve el syncer.
]]

local movers = {}        -- [ped] = { pts, cum, total, start, dur }
local PED_HEIGHT = 1.0   -- centro del ped sobre el suelo

addEvent("rp:emergency:pathRequest", true)
addEvent("rp:emergency:move", true)

addEventHandler("rp:emergency:pathRequest", resourceRoot, function(callId, token, list)
    if type(list) ~= "table" then return end
    local out = {}
    for i, o in ipairs(list) do
        local ped, tx, ty, tz = o[1], tonumber(o[2]), tonumber(o[3]), tonumber(o[4])
        if isElement(ped) and tx and ty and tz then
            local ok, pts = pcall(footPath, ped, tx, ty, tz)
            if ok and type(pts) == "table" then out[i] = pts end
        end
    end
    triggerServerEvent("rp:emergency:paths", resourceRoot, callId, token, out)
end)

addEventHandler("rp:emergency:move", resourceRoot, function(ped, pts, duration)
    if not isElement(ped) or type(pts) ~= "table" or #pts < 2 then return end
    local cum = { 0 }
    for i = 2, #pts do
        cum[i] = cum[i - 1] + getDistanceBetweenPoints2D(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
    end
    movers[ped] = { pts = pts, cum = cum, total = cum[#pts], start = getTickCount(), dur = math.max(100, tonumber(duration) or 1000) }
end)

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    for ped, m in pairs(movers) do
        if not isElement(ped) then
            movers[ped] = nil
        else
            local t = math.min(1, (now - m.start) / m.dur)
            local d = t * m.total
            local i = 2
            while i < #m.pts and m.cum[i] < d do i = i + 1 end
            local a, b = m.pts[i - 1], m.pts[i]
            local seg = m.cum[i] - m.cum[i - 1]
            local k = seg > 0.001 and math.min(1, (d - m.cum[i - 1]) / seg) or 1
            if isElementStreamedIn(ped) then
                setElementPosition(ped, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k,
                    a[3] + (b[3] - a[3]) * k + PED_HEIGHT, false)
                if seg > 0.05 then
                    setElementRotation(ped, 0, 0, -math.deg(math.atan2(b[1] - a[1], b[2] - a[2])), "default", true)
                end
            end
            if t >= 1 then movers[ped] = nil end
        end
    end
end)

addEventHandler("onClientElementDestroy", root, function() movers[source] = nil end)
