--[[
    rp_restaurants / s_restaurants.lua
    Puertas (E), empleados en el mostrador y compra de menus que se comen alli mismo
    con la animacion original de GTA SA. El precio, el dinero y la cercania los valida
    siempre el servidor; el cliente solo dice que local y que linea del menu.

    Export: isPlayerEating(player) -> bool
]]
addEvent("rp:restaurants:door", true)
addEvent("rp:restaurants:buy", true)

local eating = {}     -- [player] = { prop, timer, loc }
local lastAction = {} -- [player] = tick

local function notify(p, text, kind) exports.rp_notify:notify(p, text, kind or "info") end

local function canAct(p)
    if not isElement(p) or not exports.rp_characters:getPlayerCharacterId(p) then return false end
    if isPedDead(p) or isPedInVehicle(p) then return false end
    if getElementData(p, "rp:downed") or getElementData(p, "rp:cuffed") or getElementData(p, "rp:carried") then return false end
    local now = getTickCount()
    if lastAction[p] and now - lastAction[p] < RESTAURANTS.COOLDOWN_MS then return false end
    lastAction[p] = now
    return true
end

local function insideOf(p, loc)
    local brand = RESTAURANTS.BRANDS[loc.brand]
    return getElementInterior(p) == brand.interior and getElementDimension(p) == restaurantDimension(loc)
end

----------------------------------------------------------------
-- Mundo: marcadores, blips y empleados
----------------------------------------------------------------
-- Puertas (marcadores y blip). Se rehacen si un admin las mueve con el editor (rp_markers)
local function spawnDoors(loc)
    for _, el in ipairs(loc.doorEls or {}) do if isElement(el) then destroyElement(el) end end
    local brand = RESTAURANTS.BRANDS[loc.brand]
    local r, g, b = unpack(brand.color)
    local entryM = createMarker(loc.x, loc.y, loc.z - 1, "cylinder", 1.2, r, g, b, 120)
    exports.rp_markers:setMarkerStyle(entryM, { icon = "food", label = loc.name })
    exports.rp_markers:registerMarker(entryM, "loc" .. loc.id, { label = loc.name .. " · entrada", point = { loc.x, loc.y, loc.z } })
    local blip = createBlip(loc.x, loc.y, loc.z, brand.blip, 2, 255, 255, 255, 255, 0, 400)

    local e = brand.entry
    local exitM = createMarker(e.x, e.y, e.z - 1, "cylinder", 1.2, r, g, b, 120)
    setElementInterior(exitM, brand.interior)
    setElementDimension(exitM, restaurantDimension(loc))
    exports.rp_markers:setMarkerStyle(exitM, { icon = "exit", label = "Salir" })
    exports.rp_markers:registerMarker(exitM, "exit_" .. loc.brand, { label = ("Salida %s (todos los locales)"):format(loc.brand), point = { e.x, e.y, e.z } })
    loc.doorEls = { entryM, blip, exitM }
end

addEvent("rp:markers:moved")
addEventHandler("rp:markers:moved", root, function(owner, key)
    if owner ~= getResourceName(resource) then return end
    restaurantResolvePoints()
    for _, loc in ipairs(RESTAURANTS.LOCATIONS) do
        if RESTAURANTS.BRANDS[loc.brand] and (key == "loc" .. loc.id or key == "exit_" .. loc.brand) then spawnDoors(loc) end
    end
end)

local function spawnLocation(loc)
    local brand = RESTAURANTS.BRANDS[loc.brand]
    local dim = restaurantDimension(loc)
    spawnDoors(loc)

    local c = brand.clerk
    local ped = createPed(c.skin, c.x, c.y, c.z, c.rot)
    setElementFrozen(ped, true)
    setElementInterior(ped, brand.interior)
    setElementDimension(ped, dim)
    setElementData(ped, "rp:restaurantClerk", loc.id)   -- no recibe dano ni interaccion de otros recursos
    loc.ped = ped
end

addEventHandler("onResourceStart", resourceRoot, function()
    restaurantResolvePoints()
    for _, loc in ipairs(RESTAURANTS.LOCATIONS) do
        if RESTAURANTS.BRANDS[loc.brand] then
            spawnLocation(loc)
        else
            outputDebugString("[rp_restaurants] marca desconocida en el local " .. tostring(loc.id), 2)
        end
    end
end)

-- Los empleados no se pueden matar
addEventHandler("onPedWasted", resourceRoot, function()
    local loc = getRestaurantLocation(getElementData(source, "rp:restaurantClerk"))
    if not loc then return end
    destroyElement(source)
    setTimer(function() spawnLocation(loc) end, 5000, 1)
end)

----------------------------------------------------------------
-- Puertas
----------------------------------------------------------------
addEventHandler("rp:restaurants:door", resourceRoot, function(id)
    local p = client
    if not canAct(p) or eating[p] then return end
    local loc = getRestaurantLocation(tonumber(id))
    if not loc then return end
    local brand = RESTAURANTS.BRANDS[loc.brand]
    local px, py, pz = getElementPosition(p)
    local e = brand.entry
    local maxD = RESTAURANTS.DOOR_DISTANCE + 0.6

    if insideOf(p, loc) then
        if getDistanceBetweenPoints3D(px, py, pz, e.x, e.y, e.z) > maxD then return end
        setElementInterior(p, 0, loc.x, loc.y, loc.z)
        setElementDimension(p, 0)
    else
        if getElementInterior(p) ~= 0 or getElementDimension(p) ~= 0 then return end
        if getDistanceBetweenPoints3D(px, py, pz, loc.x, loc.y, loc.z) > maxD then return end
        setElementInterior(p, brand.interior, e.x, e.y, e.z)
        setElementDimension(p, restaurantDimension(loc))
        setElementRotation(p, 0, 0, e.rot)
    end
end)

----------------------------------------------------------------
-- Comer
----------------------------------------------------------------
local function stopEating(p, keepAnim)
    local st = eating[p]
    if not st then return end
    eating[p] = nil
    if isTimer(st.timer) then killTimer(st.timer) end
    if isElement(st.prop) then destroyElement(st.prop) end
    if isElement(p) then
        setElementFrozen(p, false)
        toggleAllControls(p, true, true, false)
        if not keepAnim then setPedAnimation(p) end
    end
end

local function clerkAnim(loc, anim, ms)
    if not isElement(loc.ped) then return end
    setPedAnimation(loc.ped, "FOOD", anim, ms, false, false, false, false)
end

local function startEating(p, loc, meal)
    local brand = RESTAURANTS.BRANDS[loc.brand]
    local full = (exports.rp_needs:getNeed(p, "hunger") or 0) >= RESTAURANTS.FULL_AT
    local cnt = brand.counter

    -- Coloca al jugador mirando al mostrador, quieto y sin controles mientras come
    setElementPosition(p, cnt.x, cnt.y, cnt.z)
    setElementRotation(p, 0, 0, cnt.rot)
    setElementFrozen(p, true)
    toggleAllControls(p, false, true, false)

    local st = { loc = loc }
    eating[p] = st

    -- El empleado entrega la bandeja y luego da las gracias (animaciones de la tienda del juego)
    clerkAnim(loc, "SHP_Tray_Out", 1500)
    setTimer(clerkAnim, 1500, 1, loc, "SHP_Thank", 2000)

    local pr = brand.prop
    local obj = createObject(pr.model, cnt.x, cnt.y, cnt.z)
    setElementInterior(obj, brand.interior)
    setElementDimension(obj, restaurantDimension(loc))
    setElementCollisionsEnabled(obj, false)
    exports.bone_attach:attachElementToBone(obj, p, 12, pr.x, pr.y, pr.z, pr.rx, pr.ry, pr.rz)
    st.prop = obj

    setPedAnimation(p, "FOOD", brand.anim, brand.animMs, false, false, false, false)

    st.timer = setTimer(function()
        if not isElement(p) or eating[p] ~= st then return end
        if isElement(st.prop) then destroyElement(st.prop) end
        if full then
            -- Como en SA: si comes estando lleno, lo devuelves todo y no te alimenta
            setPedAnimation(p, "FOOD", "EAT_Vomit_P", RESTAURANTS.VOMIT_MS, false, false, false, false)
            notify(p, "Comiste demasiado... no te sento nada bien.", "warning")
            st.timer = setTimer(function() stopEating(p) end, RESTAURANTS.VOMIT_MS, 1)
            return
        end
        exports.rp_needs:addNeed(p, "hunger", meal.hunger)
        exports.rp_needs:addNeed(p, "thirst", meal.thirst)
        if meal.health > 0 then setElementHealth(p, math.min(100, getElementHealth(p) + meal.health)) end
        notify(p, ("Te comiste un %s."):format(meal.name), "success")
        stopEating(p)
    end, brand.animMs, 1)
end

addEventHandler("rp:restaurants:buy", resourceRoot, function(id, index)
    local p = client
    if not canAct(p) then return end
    if eating[p] then return notify(p, "Termina de comer primero.", "error") end

    local loc = getRestaurantLocation(tonumber(id))
    if not loc or not insideOf(p, loc) then return end
    local brand = RESTAURANTS.BRANDS[loc.brand]
    local meal = brand.menu[tonumber(index) or 0]
    if not meal then return end

    local cnt = brand.counter
    local px, py, pz = getElementPosition(p)
    if getDistanceBetweenPoints3D(px, py, pz, cnt.x, cnt.y, cnt.z) > RESTAURANTS.COUNTER_DISTANCE + 0.6 then
        return notify(p, "Acercate al mostrador para pedir.", "error")
    end
    if not isElement(loc.ped) then return notify(p, "No hay nadie atendiendo ahora mismo.", "error") end

    -- Cobro antes de entregar (efectivo)
    if getPlayerMoney(p) < meal.price then
        return notify(p, ("No te alcanza: el %s cuesta $%d."):format(meal.name, meal.price), "error")
    end
    takePlayerMoney(p, meal.price)
    exports.rp_characters:saveCharacter(p)
    triggerEvent("rp:achievements:progress", p, "meals_eaten", 1)   -- logros (rp_achievements)

    startEating(p, loc, meal)
end)

----------------------------------------------------------------
-- Limpieza
----------------------------------------------------------------
addEventHandler("onPlayerQuit", root, function()
    stopEating(source, true)
    lastAction[source] = nil
end)

addEvent("rp:onCharacterLogout", false)
addEventHandler("rp:onCharacterLogout", root, function() stopEating(source) end)

addEvent("rp:onPlayerDowned", false)
addEventHandler("rp:onPlayerDowned", root, function() stopEating(source, true) end)

addEventHandler("onPlayerWasted", root, function() stopEating(source, true) end)

addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(eating) do stopEating(p) end
end)

function isPlayerEating(player)
    return eating[player] ~= nil
end
