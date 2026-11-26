--[[
    rp_restaurants / c_restaurants.lua
    E en la puerta (entrar/salir) o en el mostrador (abrir el menu). El menu se dibuja con dx,
    se elige con el raton o con 1-4 y se cierra con Retroceso, E o alejandote.
    El servidor vuelve a comprobar todo (precio, dinero, distancia, interior y dimension).
]]
local sw, sh = guiGetScreenSize()
local menuLoc        -- local abierto en el menu, o nil
local hover

local function blocked()
    if isCursorShowing() and not menuLoc then return true end
    if isChatBoxInputActive() or isConsoleActive() or isPedInVehicle(localPlayer) then return true end
    if getElementData(localPlayer, "rp:downed") or getElementData(localPlayer, "rp:hudHidden") then return true end
    local block = getPedAnimation(localPlayer)
    if block and block:lower() == "food" then return true end   -- comiendo o vomitando
    return false
end

local function dist(x, y, z)
    local px, py, pz = getElementPosition(localPlayer)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z)
end

-- Devuelve el local y que hay cerca: "door" o "counter"
local function nearby()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for _, loc in ipairs(RESTAURANTS.LOCATIONS) do
        local brand = RESTAURANTS.BRANDS[loc.brand]
        if brand then
            if int == 0 and dim == 0 then
                if dist(loc.x, loc.y, loc.z) <= RESTAURANTS.DOOR_DISTANCE then return loc, "door" end
            elseif int == brand.interior and dim == restaurantDimension(loc) then
                local c, e = brand.counter, brand.entry
                if dist(c.x, c.y, c.z) <= RESTAURANTS.COUNTER_DISTANCE then return loc, "counter" end
                if dist(e.x, e.y, e.z) <= RESTAURANTS.DOOR_DISTANCE then return loc, "door" end
            end
        end
    end
end

local function closeMenu()
    if not menuLoc then return end
    menuLoc, hover = nil, nil
    showCursor(false)
end

local function buy(index)
    if not menuLoc then return end
    triggerServerEvent("rp:restaurants:buy", resourceRoot, menuLoc.id, index)
    closeMenu()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("e", "down", function()
        if menuLoc then return closeMenu() end
        if blocked() then return end
        local loc, what = nearby()
        if not loc then return end
        if what == "door" then
            triggerServerEvent("rp:restaurants:door", resourceRoot, loc.id)
        else
            menuLoc = loc
            showCursor(true)
        end
    end)
    for i = 1, 4 do
        bindKey(tostring(i), "down", function()
            if menuLoc and not isChatBoxInputActive() then buy(i) end
        end)
    end
    bindKey("backspace", "down", closeMenu)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if menuLoc then showCursor(false) end
end)

-- Los empleados no reciben dano
addEventHandler("onClientPedDamage", root, function()
    if getElementData(source, "rp:restaurantClerk") then cancelEvent() end
end)

----------------------------------------------------------------
-- Dibujo
----------------------------------------------------------------
local function prompt(text, r, g, b)
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (sw - w) / 2, sh - 190
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(r, g, b, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end

local W, ROW = 420, 62
local function menuBox()
    local n = #RESTAURANTS.BRANDS[menuLoc.brand].menu
    local h = 70 + n * ROW + 40
    return (sw - W) / 2, (sh - h) / 2, W, h
end

local function drawMenu()
    local brand = RESTAURANTS.BRANDS[menuLoc.brand]
    local r, g, b = unpack(brand.color)
    local x, y, w, h = menuBox()
    local cx, cy = getCursorPosition()
    cx, cy = (cx or -1) * sw, (cy or -1) * sh

    dxDrawRectangle(x, y, w, h, tocolor(12, 14, 20, 235))
    dxDrawRectangle(x, y, w, 4, tocolor(r, g, b, 255))
    dxDrawText(brand.name, x + 20, y + 14, x + w, y + 40, tocolor(255, 255, 255), 1.5, "default-bold")
    dxDrawText(("Tu efectivo: $%d"):format(getPlayerMoney()), x + 20, y + 42, x + w - 20, y + 60,
        tocolor(154, 163, 178), 1, "default", "left")

    hover = nil
    local money = getPlayerMoney()
    for i, meal in ipairs(brand.menu) do
        local ry = y + 70 + (i - 1) * ROW
        local over = cx >= x + 10 and cx <= x + w - 10 and cy >= ry and cy <= ry + ROW - 6
        if over then hover = i end
        local afford = money >= meal.price
        dxDrawRectangle(x + 10, ry, w - 20, ROW - 6, over and tocolor(r, g, b, 70) or tocolor(255, 255, 255, 12))
        dxDrawText(tostring(i), x + 22, ry, x + 40, ry + ROW - 6, tocolor(r, g, b), 1.3, "default-bold", "left", "center")
        dxDrawText(meal.name, x + 48, ry + 8, x + w - 90, ry + 30,
            afford and tocolor(242, 244, 248) or tocolor(140, 140, 140), 1.15, "default-bold")
        dxDrawText(meal.desc, x + 48, ry + 30, x + w - 90, ry + 50, tocolor(154, 163, 178), 1, "default", "left", "top", true)
        dxDrawText("$" .. meal.price, x + w - 90, ry, x + w - 22, ry + ROW - 6,
            afford and tocolor(76, 211, 138) or tocolor(229, 72, 77), 1.3, "default-bold", "right", "center")
    end
    dxDrawText("Click o 1-4 para pedir  ·  E / Retroceso para cerrar", x, y + h - 34, x + w, y + h - 8,
        tocolor(154, 163, 178), 1, "default", "center", "center")
end

addEventHandler("onClientClick", root, function(button, state)
    if not menuLoc or button ~= "left" or state ~= "down" then return end
    if hover then return buy(hover) end
    local x, y, w, h = menuBox()
    local cx, cy = getCursorPosition()
    cx, cy = cx * sw, cy * sh
    if cx < x or cx > x + w or cy < y or cy > y + h then closeMenu() end
end)

addEventHandler("onClientRender", root, function()
    if menuLoc then
        local loc, what = nearby()
        if loc ~= menuLoc or what ~= "counter" or getElementData(localPlayer, "rp:downed") then return closeMenu() end
        return drawMenu()
    end
    if blocked() then return end
    local loc, what = nearby()
    if not loc then return end
    local r, g, b = unpack(RESTAURANTS.BRANDS[loc.brand].color)
    if what == "door" then
        prompt("Pulsa E para entrar / salir", r, g, b)
    else
        prompt("Pulsa E para ver el menú", r, g, b)
    end
end)
