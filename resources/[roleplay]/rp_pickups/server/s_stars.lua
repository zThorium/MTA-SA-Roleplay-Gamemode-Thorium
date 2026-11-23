-- Estrellas de policia: al tocarlas quitan 1 estrella de rp_wanted.
-- Si el jugador no esta buscado, la estrella no se consume.

local stars = {}

local function onStarUse(player)
    if not stars[source] or getElementType(player) ~= "player" then return end
    local level = exports.rp_wanted:getWantedLevel(player)
    if level <= 0 then
        cancelEvent() -- no se gasta
        return
    end
    exports.rp_wanted:setWantedLevel(player, level - 1)
    local left = level - 1
    exports.rp_notify:notify(player, left > 0
        and ("Una estrella menos. Te quedan %d."):format(left)
        or "Ya no te busca la policia.", "success")
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, p in ipairs(STAR_POSITIONS) do
        local pickup = createPickup(p[1], p[2], p[3], 3, STAR_MODEL, STAR_RESPAWN_MS)
        if pickup then
            stars[pickup] = true
            addEventHandler("onPickupUse", pickup, onStarUse)
        end
    end
    outputDebugString(("[rp_pickups] %d estrellas de policia creadas"):format(#STAR_POSITIONS))
end)

-- /estrellas: dice cual es la estrella mas cercana y la marca en el radar 60 s.
local marks = {}
addCommandHandler("estrellas", function(player)
    local px, py, pz = getElementPosition(player)
    local best, bd
    for _, p in ipairs(STAR_POSITIONS) do
        local d = getDistanceBetweenPoints3D(px, py, pz, p[1], p[2], p[3])
        if not bd or d < bd then best, bd = p, d end
    end
    if not best then return end
    if isElement(marks[player]) then destroyElement(marks[player]) end
    local blip = createBlip(best[1], best[2], best[3], 0, 2, 255, 220, 0, 255, 0, 99999, player)
    marks[player] = blip
    setTimer(function() if isElement(blip) then destroyElement(blip) end end, 60000, 1)
    exports.rp_notify:notify(player, ("Estrella mas cercana a %d m (%d, %d, %d), marcada en el radar."):format(
        math.floor(bd), best[1], best[2], best[3]), "info")
end)
