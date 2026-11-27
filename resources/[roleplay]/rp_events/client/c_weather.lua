--[[
    rp_events / c_weather.lua  (cliente)
    Vista previa de /clima para admins: el clima se cambia SOLO en este cliente
    (setWeather local) mientras el admin elige; con Enter el servidor lo pone para
    todos y con Retroceso se vuelve al clima real.

        ← / → o rueda   cambiar de clima
        ↑ / ↓           variante del clima (si tiene varias)
        Enter           ponerlo para todos
        Retroceso       cancelar
]]

addEvent("rp:events:weatherPreview", true)

local W, H = guiGetScreenSize()
local ORDER = { "sun", "smog", "cloudy", "rain", "storm", "fog" }
local KEY_FILES = {
    horiz = "keyboard_arrows_horizontal", vert = "keyboard_arrows_vertical", wheel = "mouse_scroll",
    enter = "keyboard_enter", back = "keyboard_backspace",
}

local preview   -- { index, variant, realId, realLabel }
local keys

local function sound(name) playSound("sounds/" .. name .. ".ogg") end

local function typing()
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
end

local function current()
    local name = ORDER[preview.index]
    local def = WORLD.WEATHER[name]
    return name, def, def.ids[preview.variant]
end

local function apply()
    local _, _, id = current()
    setWeather(id)
end

local function realWorld()
    local w = getElementData(root, "rp:world")
    return type(w) == "table" and w or {}
end

local function close(restore)
    if not preview then return end
    if restore then
        local id = tonumber(realWorld().id) or preview.realId
        if id then setWeather(id) end
    end
    -- descongelar solo lo que congeló la vista previa
    if preview.frozen and isElement(preview.frozen) then setElementFrozen(preview.frozen, false) end
    preview = nil
    toggleControl("next_weapon", true)
    toggleControl("previous_weapon", true)
end

local function step(dir)
    if not preview or typing() then return end
    preview.index = (preview.index - 1 + dir) % #ORDER + 1
    preview.variant = 1
    apply()
    sound("select_002")
end

local function variant(dir)
    if not preview or typing() then return end
    local _, def = current()
    if #def.ids < 2 then return end
    preview.variant = (preview.variant - 1 + dir) % #def.ids + 1
    apply()
    sound("select_002")
end

local function confirm()
    if not preview or typing() then return end
    local name, _, id = current()
    triggerServerEvent("rp:events:weatherConfirm", resourceRoot, name, id)
    sound("confirmation_001")
    close(false)
end

local function cancel()
    if not preview or typing() then return end
    sound("back_001")
    close(true)
end

addEventHandler("rp:events:weatherPreview", resourceRoot, function(name, realId)
    if not keys then
        keys = {}
        for k, file in pairs(KEY_FILES) do keys[k] = dxCreateTexture("images/keys/" .. file .. ".png", "argb", true, "clamp") end
    end
    local index = 1
    for i, n in ipairs(ORDER) do if n == name then index = i end end
    local def = WORLD.WEATHER[ORDER[index]]
    local v = 1
    for i, id in ipairs(def.ids) do if id == realId then v = i end end
    local real = WORLD.WEATHER[realWorld().weather or ""]
    if preview then close(false) end   -- /clima con la vista previa ya abierta: se reabre limpia
    preview = { index = index, variant = v, realId = realId, realLabel = real and real.label or "?" }
    -- el personaje (o su vehiculo si conduce) se queda quieto mientras se elige;
    -- si ya estaba congelado por otro sistema no se toca, para no soltarlo al cerrar
    local veh = getPedOccupiedVehicle(localPlayer)
    local target = (veh and getVehicleController(veh) == localPlayer) and veh or localPlayer
    if not isElementFrozen(target) then
        setElementFrozen(target, true)
        preview.frozen = target
    end
    -- la rueda cambia el clima, no el arma
    toggleControl("next_weapon", false)
    toggleControl("previous_weapon", false)
    apply()
    sound("maximize_003")
end)

-- Si el clima real cambia mientras se previsualiza, se mantiene la vista previa
addEventHandler("onClientElementDataChange", root, function(key)
    if preview and source == root and key == "rp:world" then
        local real = WORLD.WEATHER[realWorld().weather or ""]
        preview.realLabel = real and real.label or preview.realLabel
        apply()
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("arrow_l", "down", function() step(-1) end)
    bindKey("arrow_r", "down", function() step(1) end)
    bindKey("mouse_wheel_up", "down", function() step(-1) end)
    bindKey("mouse_wheel_down", "down", function() step(1) end)
    bindKey("arrow_u", "down", function() variant(-1) end)
    bindKey("arrow_d", "down", function() variant(1) end)
    bindKey("enter", "down", confirm)
    bindKey("num_enter", "down", confirm)
    bindKey("backspace", "down", cancel)
end)

-- Si el recurso se para con la vista previa abierta, no dejar al jugador congelado
addEventHandler("onClientResourceStop", resourceRoot, function() close(true) end)

-- Panel inferior con el clima elegido y las teclas dibujadas (UX-01)
addEventHandler("onClientRender", root, function()
    if not preview then return end
    local _, def, id = current()
    local font = "default-bold"
    local pw, ph = 460, 150
    local px, py = (W - pw) / 2, H - ph - 110
    dxDrawRectangle(px, py, pw, ph, tocolor(12, 14, 20, 220))
    dxDrawRectangle(px, py, pw, 3, tocolor(120, 200, 255))
    dxDrawText("VISTA PREVIA DEL CLIMA · solo la ves tú", px, py + 10, px + pw, py + 30,
        tocolor(120, 200, 255), 1, font, "center", "center")
    dxDrawText("‹   " .. def.label .. "   ›", px, py + 34, px + pw, py + 70,
        tocolor(255, 255, 255), 2, font, "center", "center")
    local sub = ("Clima actual del servidor: %s"):format(preview.realLabel)
    if #def.ids > 1 then sub = ("Variante %d/%d  ·  "):format(preview.variant, #def.ids) .. sub end
    dxDrawText(sub .. ("  ·  id %d"):format(id), px, py + 72, px + pw, py + 92,
        tocolor(170, 178, 190), 1, font, "center", "center")

    local help = { { "horiz", "wheel", "Clima" } }
    if #def.ids > 1 then help[#help + 1] = { "vert", nil, "Variante" } end
    help[#help + 1] = { "enter", nil, "Poner para todos" }
    help[#help + 1] = { "back", nil, "Cancelar" }
    local icon, gap = 30, 16
    local total = 0
    for _, e in ipairs(help) do total = total + icon * (e[2] and 2 or 1) + 6 + dxGetTextWidth(e[3], 1, font) + gap end
    local x, y = px + (pw - total + gap) / 2, py + ph - icon - 14
    for _, e in ipairs(help) do
        dxDrawImage(x, y, icon, icon, keys[e[1]])
        x = x + icon
        if e[2] then dxDrawImage(x, y, icon, icon, keys[e[2]]) x = x + icon end
        x = x + 6
        dxDrawText(e[3], x, y, x + 200, y + icon, tocolor(242, 244, 248), 1, font, "left", "center")
        x = x + dxGetTextWidth(e[3], 1, font) + gap
    end
end)
