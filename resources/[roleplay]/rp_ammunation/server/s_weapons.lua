--[[
    rp_ammunation / s_weapons.lua
    Armas e inventario. El arma (wpn_*) y las balas (ammo_*) son items; usar el arma
    la equipa o la guarda. Al equipar, el arma recibe tantas balas como tengas en el
    inventario; cada 2 s se descuentan del inventario las gastadas y se suman las
    nuevas (compradas o recogidas).
    shortcut: si el jugador sale/crashea, se pierden las balas disparadas en los ultimos 2 s.
]]
addEvent("rp:onItemUse", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:onCharacterLogout", false)

local equipped = {}   -- [player] = { itemId, def, loaded }
local suspended = {}  -- [player] = true mientras otro recurso (campo de tiro) controla las armas

local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end

local function holster(player)
    local eq = equipped[player]
    equipped[player] = nil
    if eq and isElement(player) then takeWeapon(player, eq.def.weapon) end
end

local function sync(player)
    local eq = equipped[player]
    if not eq or not isElement(player) then return end
    local slot = getSlotFromWeapon(eq.def.weapon)
    if not exports.rp_inventory:hasItem(player, eq.itemId, 1) or getPedWeapon(player, slot) ~= eq.def.weapon then
        return holster(player)
    end
    local remaining = getPedTotalAmmo(player, slot)
    local used = math.max(0, eq.loaded - remaining)
    if used > 0 then
        exports.rp_inventory:takeItem(player, eq.def.ammo, math.min(used, exports.rp_inventory:getItemAmount(player, eq.def.ammo)))
    end
    local have = exports.rp_inventory:getItemAmount(player, eq.def.ammo)
    if have > remaining then giveWeapon(player, eq.def.weapon, have - remaining, false) end
    eq.loaded = have
end

addEventHandler("rp:onItemUse", root, function(itemId)
    local player = source
    local def = exports.rp_inventory:getItemDefinition(itemId)
    if not def or not def.weapon then return end
    if suspended[player] then return notify(player, "No puedes sacar armas aqui.", "warning") end
    local current = equipped[player]
    if current then
        sync(player)
        holster(player)
        if current.itemId == itemId then return notify(player, "Guardas el arma.", "info") end
    end
    local ammo = exports.rp_inventory:getItemAmount(player, def.ammo)
    if ammo < 1 then return notify(player, "No tienes municion para esa arma.", "warning") end
    giveWeapon(player, def.weapon, ammo, true)
    equipped[player] = { itemId = itemId, def = def, loaded = ammo }
    notify(player, ("Sacas %s con %d balas."):format(def.name, ammo), "success")
end)

-- Export (rp_shootingrange): vuelca las balas gastadas al inventario, guarda el arma equipada y
-- bloquea equipar mientras dure. Devuelve el item del arma que tenia equipada (o false).
function suspendWeapons(player)
    local eq = equipped[player]
    local itemId = eq and eq.itemId or false
    if eq then sync(player); holster(player) end
    suspended[player] = true
    return itemId
end

-- Export: libera el bloqueo y vuelve a equipar el arma de antes si aun la tiene y le quedan balas.
function resumeWeapons(player, itemId)
    suspended[player] = nil
    if not itemId or not isElement(player) or equipped[player] then return end
    local def = exports.rp_inventory:getItemDefinition(itemId)
    if not def or not def.weapon or not exports.rp_inventory:hasItem(player, itemId, 1) then return end
    local ammo = exports.rp_inventory:getItemAmount(player, def.ammo)
    if ammo < 1 then return end
    giveWeapon(player, def.weapon, ammo, true)
    equipped[player] = { itemId = itemId, def = def, loaded = ammo }
end

setTimer(function()
    for player in pairs(equipped) do
        if isElement(player) then sync(player) else equipped[player] = nil end
    end
end, 2000, 0)

addEventHandler("rp:onCharacterLogout", root, function()
    sync(source)
    equipped[source] = nil
    suspended[source] = nil
    takeAllWeapons(source)
end)
addEventHandler("onPlayerQuit", root, function() sync(source); equipped[source] = nil; suspended[source] = nil end)
addEventHandler("rp:onCharacterSpawn", root, function() equipped[source] = nil; suspended[source] = nil; takeAllWeapons(source) end)
