--[[
    rp_dealers / c_dealers.lua
    Los policias IA (rp_citizens) solo existen en el cliente, asi que aqui se
    detecta si un policia tiene linea de vision hacia el jugador mientras esta
    junto a un traficante y se avisa al servidor (que lo usa al comprar).
]]

local NEAR_DEALER = 6

local function copNear(px, py, pz)
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        if (DEALERS.COP_SKINS[getElementModel(ped)] or getElementData(ped, "rp:cop")) and not isPedDead(ped) then
            local x, y, z = getElementPosition(ped)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= DEALERS.COP_RADIUS
                and isLineOfSightClear(px, py, pz + 0.6, x, y, z + 0.6, true, false, false, true, false, false, false, ped) then
                return true
            end
        end
    end
    return false
end

setTimer(function()
    if not getElementData(localPlayer, "rp:characterId") then return end
    local px, py, pz = getElementPosition(localPlayer)
    local dealerNear = false
    for _, ped in ipairs(getElementsByType("ped", resourceRoot, true)) do
        if getElementData(ped, "rp:dealer") then
            local x, y, z = getElementPosition(ped)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= NEAR_DEALER then dealerNear = true break end
        end
    end
    if dealerNear and copNear(px, py, pz) then
        triggerServerEvent("rp:dealers:copSeen", resourceRoot)
    end
end, 1000, 0)
