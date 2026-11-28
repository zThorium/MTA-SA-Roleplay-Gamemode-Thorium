--[[
    rp_inventory / c_inventory.lua
    Tecla I: abre/cierra el inventario (CEF). Mientras esta abierto, el propio
    HTML escucha I o Esc para cerrarlo (con el input de GUI activo los binds
    de MTA no se disparan).
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, ready = nil, nil, false
local visible = false
local lastData = nil
local dirty = false     -- hay datos nuevos que aun no se dibujaron en el CEF
local pushNearby   -- se define abajo (columnas "Cerca de ti" y "Personaje")

addEvent("rp:inv:update", true)
addEvent("rp:inv:ui:close", false)
addEvent("rp:inv:ui:use", false)
addEvent("rp:inv:ui:drop", false)

-- El navegador CEF se crea UNA vez por personaje (oculto) y se reutiliza.
-- Antes se creaba y destruia en cada pulsacion de I (arranque de Chromium +
-- carga de HTML/CSS/JS + viaje al servidor), de ahi el retraso al abrir.
-- Ahora abrir = mostrar la GUI ya cargada, con los datos que el servidor
-- mantiene sincronizados en segundo plano (rp:inv:update).

-- Posicion de cada item en las casillas: se guarda en un archivo del cliente por personaje
addEvent("rp:inv:ui:layout", false)

local function layoutFile()
    local cid = getElementData(localPlayer, "rp:characterId")
    return cid and ("layout_%d.json"):format(tonumber(cid) or 0) or nil
end

addEventHandler("rp:inv:ui:layout", root, function(json)
    local name = layoutFile()
    if not name or type(json) ~= "string" or #json > 8192 then return end
    if fileExists(name) then fileDelete(name) end
    local f = fileCreate(name)
    if f then
        fileWrite(f, json)
        fileClose(f)
    end
end)

local function pushLayout()
    local name = layoutFile()
    if not (name and fileExists(name) and isElement(browser)) then return end
    local f = fileOpen(name, true)
    if not f then return end
    local json = fileRead(f, math.min(fileGetSize(f), 8192))
    fileClose(f)
    if json and json ~= "" then
        executeBrowserJavascript(browser, ("RP.setLayout(%s[0])"):format(toJSON({ json }, true)))
    end
end

local function render()
    if not (isElement(browser) and ready and lastData) then dirty = lastData ~= nil; return end
    dirty = false
    executeBrowserJavascript(browser, ("RP.render(%s[0], %s, %s, %s[0])"):format(
        toJSON(lastData.items, true), tostring(lastData.weight), tostring(lastData.maxWeight),
        toJSON(lastData.bp or false, true)))   -- toJSON ya envuelve el valor en un array: el "[0]" lo desenvuelve
end

local function isOpen()
    return visible and isElement(browserGui)
end

local function destroyBrowser()
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser, ready, visible, dirty = nil, nil, false, false, false
end

local function createBrowser()
    if isElement(browserGui) then return end
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    guiSetVisible(browserGui, false)
    browser = guiGetBrowser(browserGui)
    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        ready = true
        pushLayout()
        render()
    end)
end

local function close()
    if not visible then return end
    visible = false
    if isElement(browserGui) then guiSetVisible(browserGui, false) end
    showCursor(false)
    guiSetInputEnabled(false)
end

local function open()
    if isOpen() then return end
    if not getElementData(localPlayer, "rp:characterId") or isPedDead(localPlayer) then return end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return end

    if not isElement(browserGui) then createBrowser() end   -- por si aun no existia
    visible = true
    guiSetVisible(browserGui, true)
    guiBringToFront(browserGui)
    focusBrowser(browser)
    showCursor(true)
    guiSetInputEnabled(true)
    -- Los datos se dibujan en segundo plano al llegar (rp:inv:update): al abrir solo se
    -- repite el render si quedaron pendientes (el CEF aun no estaba listo).
    if dirty then render() end
    if ready then
        executeBrowserJavascript(browser, "RP.opened()")
        -- "Cerca de ti" y "Personaje" recorren elementos del mundo: no bloquean la apertura
        setTimer(pushNearby, 50, 1)
    end
    -- Solo pedimos datos si aun no llegaron (normalmente ya estan sincronizados)
    if not lastData then triggerServerEvent("rp:inv:request", resourceRoot) end
end

addEventHandler("rp:inv:update", resourceRoot, function(items, weight, maxWeight, bp)
    -- bp = datos de la mochila equipada (nombre, capacidad, uso, slots) o false; sus items llevan bp = true
    lastData = { items = items or {}, weight = weight or 0, maxWeight = maxWeight or 0, bp = bp or false }
    render()
end)

-- Mochila (rp_backpacks): guardar / sacar items y tirarla
addEvent("rp:inv:ui:toBackpack", false)
addEvent("rp:inv:ui:fromBackpack", false)
addEvent("rp:inv:ui:dropBackpack", false)
addEventHandler("rp:inv:ui:toBackpack", root, function(itemId, amount)
    amount = tonumber(amount)
    if type(itemId) == "string" and amount then triggerServerEvent("rp:inv:toBackpack", resourceRoot, itemId, amount) end
end)
addEventHandler("rp:inv:ui:fromBackpack", root, function(itemId, amount)
    amount = tonumber(amount)
    if type(itemId) == "string" and amount then triggerServerEvent("rp:inv:fromBackpack", resourceRoot, itemId, amount) end
end)
addEventHandler("rp:inv:ui:dropBackpack", root, function()
    triggerServerEvent("rp:inv:dropBackpack", resourceRoot)
end)

addEventHandler("rp:inv:ui:close", root, close)

addEventHandler("rp:inv:ui:use", root, function(itemId)
    if type(itemId) == "string" then triggerServerEvent("rp:inv:use", resourceRoot, itemId) end
end)

addEventHandler("rp:inv:ui:drop", root, function(itemId, amount)
    amount = tonumber(amount)
    if type(itemId) == "string" and amount then triggerServerEvent("rp:inv:drop", resourceRoot, itemId, amount) end
end)

----------------------------------------------------------------
-- Dar a jugadores cercanos y tirar al suelo arrastrando
----------------------------------------------------------------
local GIVE_RANGE = 3          -- el servidor vuelve a validarlo
local GROUND_RANGE = 2.8      -- columna "Cerca de ti" (el servidor deja recoger hasta 3 m)
addEvent("rp:inv:ui:give", false)
addEvent("rp:inv:ui:dropAt", false)
addEvent("rp:inv:ui:pickup", false)

-- Referencia estable de cada objeto del suelo para el CEF (no se pueden pasar elementos al JS)
local groundRef, groundByRef, nextRef = setmetatable({}, { __mode = "k" }), {}, 0
local function refOf(obj)
    if not groundRef[obj] then
        nextRef = nextRef + 1
        groundRef[obj] = nextRef
    end
    groundByRef[groundRef[obj]] = obj
    return groundRef[obj]
end

local function pushGround()
    local px, py, pz = getElementPosition(localPlayer)
    local list = {}
    groundByRef = {}
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        local data = getElementData(obj, "rp:ground")
        if data and getElementDimension(obj) == getElementDimension(localPlayer) then
            local x, y, z = getElementPosition(obj)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= GROUND_RANGE then
                list[#list + 1] = { ref = refOf(obj), id = data.id, name = data.name, icon = data.icon, iconImg = data.iconImg, amount = data.amount }
            end
        end
    end
    table.sort(list, function(a, b) return a.ref < b.ref end)
    executeBrowserJavascript(browser, ("RP.ground(%s[0])"):format(toJSON(list, true)))
end

addEventHandler("rp:inv:ui:pickup", root, function(ref)
    local obj = groundByRef[tonumber(ref) or -1]
    if isElement(obj) then triggerServerEvent("rp:inv:pickup", resourceRoot, obj) end
end)

-- Columna "Personaje": vida, blindaje, el arma del inventario que lleva equipada y el objeto que
-- lleva en la mano (elementData rp:heldItem = id del item; lo pone el recurso que lo maneja, p. ej.
-- rp_metaldetector): ese item sale marcado y su acción es «Guardar».
local function pushCharacter()
    local weaponItem
    for _, it in ipairs(lastData and lastData.items or {}) do
        local def = not it.bp and ITEMS[it.id]
        local w = def and def.weapon
        if w and getPedWeapon(localPlayer, getSlotFromWeapon(w)) == w then
            weaponItem = it.id
            break
        end
    end
    local info = {
        name = (getPlayerName(localPlayer):gsub("_", " ")),
        health = math.floor(getElementHealth(localPlayer)),
        armor = math.floor(getPedArmor(localPlayer)),
        weaponItem = weaponItem,
        heldItem = getElementData(localPlayer, "rp:heldItem") or false,
    }
    executeBrowserJavascript(browser, ("RP.character(%s[0])"):format(toJSON(info, true)))
end

pushNearby = function()
    if not (isOpen() and ready) then return end
    pushGround()
    pushCharacter()
    local x, y, z = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local list = {}
    for _, p in ipairs(getElementsByType("player", root, true)) do
        local id = getElementData(p, "id")
        if p ~= localPlayer and id and getElementData(p, "rp:characterId") and not isPedDead(p)
            and getElementDimension(p) == dim and getElementInterior(p) == int then
            local px, py, pz = getElementPosition(p)
            if getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= GIVE_RANGE then
                list[#list + 1] = { id = id, name = (getPlayerName(p):gsub("_", " ")) }
            end
        end
    end
    executeBrowserJavascript(browser, ("RP.nearby(%s[0])"):format(toJSON(list, true)))
end
setTimer(pushNearby, 500, 0)

addEventHandler("rp:inv:ui:give", root, function(itemId, amount, targetId)
    amount, targetId = tonumber(amount), tonumber(targetId)
    if type(itemId) == "string" and amount and targetId then
        triggerServerEvent("rp:inv:give", resourceRoot, itemId, amount, targetId)
    end
end)

-- (sx, sy) = donde se solto el click; se traza un rayo desde la camara hasta el suelo
addEventHandler("rp:inv:ui:dropAt", root, function(itemId, amount, sx, sy)
    amount, sx, sy = tonumber(amount), tonumber(sx), tonumber(sy)
    if type(itemId) ~= "string" or not (amount and sx and sy) then return end
    local cx, cy, cz = getCameraMatrix()
    local fx, fy, fz = getWorldFromScreenPosition(sx, sy, 40)
    local hit, hx, hy, hz = processLineOfSight(cx, cy, cz, fx, fy, fz, true, false, false, true, false, false, false, false, localPlayer)
    if not hit then   -- apuntaste al cielo: lo dejamos delante del personaje
        local px, py, pz = getElementPosition(localPlayer)
        local _, _, rot = getElementRotation(localPlayer)
        hx, hy, hz = px + math.sin(math.rad(rot)) * 0.8, py + math.cos(math.rad(rot)) * 0.8, pz - 0.9
    end
    triggerServerEvent("rp:inv:dropAt", resourceRoot, itemId, amount, hx, hy, hz)
end)

-- Etiqueta sobre los items del suelo + tecla E para recogerlos
local PICK_RANGE = 2.5
local function nearestGround()
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestDist
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        if getElementData(obj, "rp:ground") then
            local x, y, z = getElementPosition(obj)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d <= PICK_RANGE and (not bestDist or d < bestDist) then best, bestDist = obj, d end
        end
    end
    return best
end

-- Lista cacheada de objetos del suelo en streaming (antes se recorrian todos los
-- objetos del recurso y se leia su elementData en cada frame)
local groundObjs = {}
local function refreshGroundObjs()
    local list = {}
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        if getElementData(obj, "rp:ground") then list[#list + 1] = obj end
    end
    groundObjs = list
end
setTimer(refreshGroundObjs, 250, 0)

addEventHandler("onClientRender", root, function()
    if #groundObjs == 0 or getElementData(localPlayer, "rp:hudHidden") then return end
    local cx, cy, cz = getCameraMatrix()
    local target = (not isOpen()) and nearestGround() or nil
    for _, obj in ipairs(groundObjs) do
        local data = isElement(obj) and getElementData(obj, "rp:ground")
        if data then
            local x, y, z = getElementPosition(obj)
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
            local sx, sy = getScreenFromWorldPosition(x, y, z + 0.4)
            if sx and dist < 12 then
                local text = ("%s %s x%d"):format(data.icon or "", data.name or "?", data.amount or 1)
                dxDrawText(text, sx + 1, sy + 1, sx + 1, sy + 1, tocolor(0, 0, 0, 220), 1, "default-bold", "center", "bottom")
                dxDrawText(text, sx, sy, sx, sy, tocolor(255, 255, 255, 255), 1, "default-bold", "center", "bottom")
                if obj == target then
                    dxDrawText("[E] Recoger", sx, sy + 2, sx, sy + 2, tocolor(245, 165, 36, 255), 1, "default-bold", "center", "top")
                end
            end
        end
    end
end)

bindKey("e", "down", function()
    if isOpen() or isCursorShowing() then return end
    local obj = nearestGround()
    if obj then triggerServerEvent("rp:inv:pickup", resourceRoot, obj) end
end)

-- Cerrar si el personaje muere o sale
addEventHandler("onClientPlayerWasted", localPlayer, close)
addEvent("rp:onClientPlayerDowned", false)
addEventHandler("rp:onClientPlayerDowned", localPlayer, close)
addEventHandler("onClientElementDataChange", localPlayer, function(key, _, new)
    if key ~= "rp:characterId" then return end
    if new then
        createBrowser()
    else
        close()
        destroyBrowser()
        lastData = nil
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "rp:characterId") then
        createBrowser()
        triggerServerEvent("rp:inv:request", resourceRoot)
    end
    bindKey("i", "down", function()
        if isOpen() then close() elseif not getElementData(localPlayer, "rp:downed") and not getElementData(localPlayer, "rp:cuffed") then open() end
    end)
end)

-- Icono del inventario en el HUD (rp_hud/c_iconbar.lua): mismas condiciones que la tecla I
addEvent("rp:hud:action", false)
addEventHandler("rp:hud:action", localPlayer, function(id)
    if id ~= "inventory" then return end
    if isOpen() then close() elseif not getElementData(localPlayer, "rp:downed") and not getElementData(localPlayer, "rp:cuffed") then open() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    close()
    destroyBrowser()
end)

-- Export cliente: permite a otros recursos saber si el inventario esta abierto
function isInventoryOpen()
    return isOpen()
end

function closeInventory()
    close()
end
