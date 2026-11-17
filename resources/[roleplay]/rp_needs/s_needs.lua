--[[
    rp_needs / s_needs.lua
    Hambre, sed y cansancio (0-100) por personaje, guardados en characters.
    Bajan con el tiempo; a 0 de hambre o sed se pierde vida y a 0 de energia
    no se puede correr. Se recuperan con items (rp_inventory) o con /dormir.

    Exports (servidor):
        addNeed(player, "hunger" | "thirst" | "energy", cantidad) -> nuevo valor
        getNeed(player, need)                                      -> valor
        getNeeds(player)                                           -> { hunger, thirst, energy }
]]

local CONFIG = {
    TICK = 60000,                                   -- cada minuto
    DECAY = { hunger = 0.8, thirst = 1.2, energy = 0.6 },   -- puntos por minuto
    STARVING_DAMAGE = 3,                            -- vida por minuto si hambre o sed llegan a 0
    WARN_AT = 20,
    SAVE_INTERVAL = 5 * 60000,
    SLEEP_TIME = 10000,                             -- ms dormido
}

local NAMES = { hunger = "hambre", thirst = "sed", energy = "cansancio" }
local needs = {}      -- [player] = { characterId, hunger, thirst, energy, warned = {} }
local sleeping = {}   -- [player] = timer

addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)

local function db()
    return exports.rp_database:getConnection()
end

local function notify(player, text, kind)
    exports.rp_notify:notify(player, text, kind)
end

local function publish(player)
    local n = needs[player]
    if not n or not isElement(player) then return end
    setElementData(player, "rp:needs", {
        hunger = math.floor(n.hunger + 0.5), thirst = math.floor(n.thirst + 0.5), energy = math.floor(n.energy + 0.5),
    }, "local")
end

local function save(player)
    local n = needs[player]
    if not n then return end
    dbExec(db(), "UPDATE characters SET hunger = ?, thirst = ?, energy = ? WHERE id = ?",
        math.floor(n.hunger + 0.5), math.floor(n.thirst + 0.5), math.floor(n.energy + 0.5), n.characterId)
end

local function applyEffects(player)
    local n = needs[player]
    if not n then return end
    -- Sin energia no se puede correr
    local tired = n.energy <= 0
    if tired ~= n.tired then
        n.tired = tired
        toggleControl(player, "sprint", not tired)
        if tired then notify(player, "Estas agotado. Duerme (/dormir en un interior) o toma un cafe.", "warning") end
    end
end

----------------------------------------------------------------
-- Carga / descarga
----------------------------------------------------------------
local function load(player, characterId)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        local row = rows and rows[1]
        if not isElement(player) or not row then return end
        needs[player] = {
            characterId = characterId,
            hunger = tonumber(row.hunger) or 100, thirst = tonumber(row.thirst) or 100, energy = tonumber(row.energy) or 100,
            warned = {},
        }
        publish(player)
        applyEffects(player)
    end, db(), "SELECT hunger, thirst, energy FROM characters WHERE id = ?", characterId)
end

local function unload(player)
    save(player)
    if isTimer(sleeping[player]) then killTimer(sleeping[player]) end
    needs[player], sleeping[player] = nil, nil
    if isElement(player) then
        setElementData(player, "rp:needs", false)
        toggleControl(player, "sprint", true)
    end
end

addEventHandler("rp:onCharacterSpawn", root, function(characterId) load(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function() unload(source) end)
addEventHandler("onPlayerQuit", root, function() if needs[source] then unload(source) end end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local characterId = exports.rp_characters:getPlayerCharacterId(player)
        if characterId then load(player, characterId) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(needs) do save(player) end
end)

----------------------------------------------------------------
-- Paso del tiempo
----------------------------------------------------------------
setTimer(function()
    for player, n in pairs(needs) do
        if isElement(player) and not isPedDead(player) and not sleeping[player] then
            for need, rate in pairs(CONFIG.DECAY) do
                n[need] = math.max(0, n[need] - rate)
                if n[need] <= CONFIG.WARN_AT and not n.warned[need] then
                    n.warned[need] = true
                    notify(player, ("Tienes mucha %s."):format(NAMES[need]), "warning")
                elseif n[need] > CONFIG.WARN_AT + 10 then
                    n.warned[need] = nil
                end
            end
            if n.hunger <= 0 or n.thirst <= 0 then
                setElementHealth(player, math.max(1, getElementHealth(player) - CONFIG.STARVING_DAMAGE))
                if getElementHealth(player) <= 1 then killPed(player) end
            end
            applyEffects(player)
            publish(player)
        end
    end
end, CONFIG.TICK, 0)

setTimer(function()
    for player in pairs(needs) do save(player) end
end, CONFIG.SAVE_INTERVAL, 0)

----------------------------------------------------------------
-- API
----------------------------------------------------------------
function addNeed(player, need, amount)
    local n = needs[player]
    if not n or not CONFIG.DECAY[need] or type(amount) ~= "number" then return false end
    n[need] = math.max(0, math.min(100, n[need] + amount))
    applyEffects(player)
    publish(player)
    return n[need]
end

function getNeed(player, need)
    local n = needs[player]
    return n and n[need] or false
end

function getNeeds(player)
    local n = needs[player]
    return n and { hunger = n.hunger, thirst = n.thirst, energy = n.energy } or false
end

----------------------------------------------------------------
-- /dormir (solo dentro de un interior)
----------------------------------------------------------------
addCommandHandler("dormir", function(player)
    local n = needs[player]
    if not n then return end
    if sleeping[player] then return notify(player, "Ya estas durmiendo.", "warning") end
    if getElementInterior(player) == 0 and getElementDimension(player) == 0 then
        return notify(player, "Solo puedes dormir dentro de un interior.", "error")
    end
    if isPedInVehicle(player) or isPedDead(player) then return notify(player, "Ahora no puedes dormir.", "error") end
    if n.energy >= 95 then return notify(player, "No tienes sueno.", "info") end

    setElementFrozen(player, true)
    toggleAllControls(player, false, true, false)
    fadeCamera(player, false, 1.5)
    exports.rp_notify:popup(player, "Durmiendo...", "Tu personaje descansa unos instantes.", "info", CONFIG.SLEEP_TIME - 1500)

    sleeping[player] = setTimer(function()
        sleeping[player] = nil
        if not isElement(player) then return end
        setElementFrozen(player, false)
        toggleAllControls(player, true, true, false)
        fadeCamera(player, true, 1.5)
        if needs[player] then
            addNeed(player, "energy", 100)
            setElementHealth(player, math.min(100, getElementHealth(player) + 10))
        end
        notify(player, "Te despiertas descansado.", "success")
    end, CONFIG.SLEEP_TIME, 1)
end)
