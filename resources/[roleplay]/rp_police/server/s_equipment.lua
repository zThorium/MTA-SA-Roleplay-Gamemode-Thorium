--[[
    rp_police / s_equipment.lua
    Armeria (articulos por rol; el equipo reglamentario lo da el Estado y se devuelve
    al salir de servicio, las armas de fuego se pagan en efectivo), equipar taser y
    porra, garaje de patrullas por nivel de rol y sirenas.
]]

addEvent("rp:onItemUse", false)
addEvent("rp:onCharacterSpawn", false)
addEvent("rp:pol:siren", true)

POLICE_EQUIPPED = {}          -- [player] = "pol_taser" | "pol_baton"
local fleet = {}              -- [player] = vehiculo del garaje
local WEAPON_OF = { pol_taser = { 23, 500 }, pol_baton = { 3, 1 } }

local function unequip(p)
    local id = POLICE_EQUIPPED[p]
    POLICE_EQUIPPED[p] = nil
    if id and isElement(p) then takeWeapon(p, WEAPON_OF[id][1]) end
end

addEventHandler("rp:onItemUse", root, function(itemId)
    local p = source
    local def = exports.rp_inventory:getItemDefinition(itemId)
    if not def or not def.use or def.use.event ~= "police_equip" then return end
    if not isOnDuty(p) then return notify(p, "Solo puedes usar el equipo reglamentario de servicio.", "warning") end
    local current = POLICE_EQUIPPED[p]
    if current then
        unequip(p)
        if current == itemId then return notify(p, "Guardas " .. def.name .. ".", "info") end
    end
    local w = WEAPON_OF[itemId]
    if not w then return end
    giveWeapon(p, w[1], w[2], true)
    POLICE_EQUIPPED[p] = itemId
    notify(p, "Sacas " .. def.name .. ".", "success")
end)

addEventHandler("rp:onCharacterSpawn", root, function() POLICE_EQUIPPED[source] = nil end)

----------------------------------------------------------------
-- Armeria
----------------------------------------------------------------
local function armoryData(p)
    local lv, list = rankLevel(p), {}
    for _, a in ipairs(POLICE_ARMORY) do
        local def = exports.rp_inventory:getItemDefinition(a.item)
        if def then
            list[#list + 1] = { item = a.item, name = def.name, icon = def.icon, price = a.price, level = a.level, amount = a.amount,
                issued = a.issued or false, locked = lv < a.level, have = exports.rp_inventory:getItemAmount(p, a.item),
                description = def.description }
        end
    end
    return { items = list, cash = getPlayerMoney(p), level = lv }
end

function openArmory(p)
    if not can(p, "pol_armory") then return notify(p, "Tu rol no tiene acceso a la armeria.", "warning") end
    showUI(p, "armory", armoryData(p))
end

UI_ACTIONS.armory_buy = function(p, d)
    if not can(p, "pol_armory") or not nearPoint(p, "armory") then return end
    local entry
    for _, a in ipairs(POLICE_ARMORY) do if a.item == d.item then entry = a break end end
    if not entry then return end
    if rankLevel(p) < entry.level then return notify(p, "Tu rol no alcanza el nivel para este articulo.", "warning") end
    if entry.price > 0 and getPlayerMoney(p) < entry.price then return notify(p, ("Necesitas $%d en efectivo."):format(entry.price), "error") end
    local ok, reason = exports.rp_inventory:giveItem(p, entry.item, entry.amount)
    if not ok then return notify(p, reason or "No puedes llevar mas.", "warning") end
    if entry.price > 0 then
        takePlayerMoney(p, entry.price)
        exports.rp_characters:saveCharacter(p)
    end
    local def = exports.rp_inventory:getItemDefinition(entry.item)
    notify(p, ("%s x%d%s."):format(def.name, entry.amount, entry.price > 0 and (" por $" .. entry.price) or " (equipo del Estado)"), "success")
    updateUI(p, "armory", armoryData(p))
end

----------------------------------------------------------------
-- Garaje
----------------------------------------------------------------
local function destroyFleet(p)
    local v = fleet[p]
    fleet[p] = nil
    if isElement(v) then destroyElement(v) end
end

function openGarage(p)
    if not can(p, "pol_garage") then return notify(p, "Tu rol no tiene acceso al garaje.", "warning") end
    local lv, list = rankLevel(p), {}
    for _, g in ipairs(POLICE_GARAGE) do list[#list + 1] = { model = g.model, name = g.name, level = g.level, locked = lv < g.level } end
    showUI(p, "garage", { vehicles = list, level = lv, hasVehicle = isElement(fleet[p]) })
end

UI_ACTIONS.garage_spawn = function(p, d)
    if not can(p, "pol_garage") or not nearPoint(p, "garage") then return end
    local entry
    for _, g in ipairs(POLICE_GARAGE) do if g.model == tonumber(d.model) then entry = g break end end
    if not entry then return end
    if rankLevel(p) < entry.level then return notify(p, "Tu rol no alcanza el nivel para este vehiculo.", "warning") end
    destroyFleet(p)
    local s = POINTS.garage_spawn
    -- Si hay otro vehiculo encima de la salida, avisar en vez de apilarlos
    for _, v in ipairs(getElementsByType("vehicle")) do
        local x, y, z = getElementPosition(v)
        if getDistanceBetweenPoints3D(x, y, z, s.x, s.y, s.z) < 3.5 then
            return notify(p, "La salida del garaje esta ocupada. Espera un momento.", "warning")
        end
    end
    local v = createVehicle(entry.model, s.x, s.y, s.z, 0, 0, s.rot or 0, ("LSPD%03d"):format(exports.rp_ids:getPlayerId(p) or 0))
    if not v then return end
    setElementData(v, "rp:policeVeh", charOf(p))
    setVehicleEngineState(v, true)
    fleet[p] = v
    pcall(function()
        if doesVehicleHaveSirens and not doesVehicleHaveSirens(v) then
            addVehicleSirens(v, 2, 2, false, true, true, true)
            setVehicleSirens(v, 1, -0.5, 0.4, 0.95, 255, 0, 0, 255, 200)
            setVehicleSirens(v, 2, 0.5, 0.4, 0.95, 0, 0, 255, 255, 200)
        end
    end)
    warpPedIntoVehicle(p, v)
    triggerClientEvent(p, "rp:pol:ui:close", resourceRoot)
    notify(p, ("Sacas %s. Sirena: tecla %s."):format(entry.name, POLICE.KEY_SIREN:upper()), "success")
end

UI_ACTIONS.garage_return = function(p)
    if not can(p, "pol_garage") then return end
    local v = fleet[p]
    if not isElement(v) then return notify(p, "No tienes un vehiculo del garaje.", "info") end
    local x, y, z = getElementPosition(v)
    local g = POINTS.garage
    if getDistanceBetweenPoints3D(x, y, z, g.x, g.y, g.z) > 45 then return notify(p, "Trae el vehiculo cerca del garaje.", "warning") end
    destroyFleet(p)
    notify(p, "Devuelves el vehiculo al garaje.", "success")
    updateUI(p, "garage", { hasVehicle = false })
end

addEventHandler("rp:pol:onDuty", root, function(on)
    if not on then unequip(source) destroyFleet(source) end
end)
addEventHandler("onPlayerQuit", root, function() POLICE_EQUIPPED[source] = nil destroyFleet(source) end)
addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    for p, v in pairs(fleet) do if v == source then fleet[p] = nil end end
end)

-- Solo los policias de servicio conducen los vehiculos del garaje (los detenidos van de pasajeros)
addEventHandler("onVehicleStartEnter", root, function(player, seat)
    if seat == 0 and getElementData(source, "rp:policeVeh") and not isOnDuty(player) then
        cancelEvent()
        notify(player, "Es un vehiculo policial.", "warning")
    end
end)

----------------------------------------------------------------
-- Sirena
----------------------------------------------------------------
addEventHandler("rp:pol:siren", resourceRoot, function()
    local p = client
    local v = getPedOccupiedVehicle(p)
    if not v or getVehicleController(v) ~= p or not isOnDuty(p) or not POLICE_VEHICLE_MODELS[getElementModel(v)] then return end
    setVehicleSirensOn(v, not getVehicleSirensOn(v))
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(fleet) do destroyFleet(p) end
    for p in pairs(POLICE_EQUIPPED) do unequip(p) end
end)
