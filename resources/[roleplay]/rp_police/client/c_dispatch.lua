--[[
    rp_police / c_dispatch.lua
    Alertas de despacho en pantalla (codigo, zona, descripcion y distancia) con
    sonido, y el punto de /responder en el mapa.
]]

local sw, sh = guiGetScreenSize()
local cards = {}          -- { alert, born }
local respondBlip = nil
local LIFE = 14000

addEvent("rp:pol:alert", true)
addEvent("rp:pol:setWaypoint", true)

addEventHandler("rp:pol:alert", resourceRoot, function(a)
    if type(a) ~= "table" then return end
    table.insert(cards, 1, { a = a, born = getTickCount() })
    if #cards > 4 then table.remove(cards) end
    playSoundFrontEnd(a.code == "10-99" and 20 or 5)
    exports.rp_notify:notify(("%s %s en %s. /responder %d"):format(a.code, a.title, a.zone, a.id), "warning")
end)

addEventHandler("rp:pol:setWaypoint", resourceRoot, function(x, y)
    if isElement(respondBlip) then destroyElement(respondBlip) end
    respondBlip = createBlip(x, y, 0, 41, 2, 59, 111, 224, 255, 0, 99999)
    setTimer(function() if isElement(respondBlip) then destroyElement(respondBlip) end end, 120000, 1)
end)

addEventHandler("onClientRender", root, function()
    if #cards == 0 then return end
    local now = getTickCount()
    local px, py, pz = getElementPosition(localPlayer)
    local y = 150
    for i = #cards, 1, -1 do
        if now - cards[i].born > LIFE then table.remove(cards, i) end
    end
    for _, c in ipairs(cards) do
        local a = c.a
        local age = now - c.born
        local alpha = math.min(1, age / 250, (LIFE - age) / 600)
        local w, h = 330, 78
        local x = sw - w - 18 + (1 - math.min(1, age / 250)) * 60
        local col = a.color or { 245, 165, 36 }
        dxDrawRectangle(x, y, w, h, tocolor(10, 12, 18, 225 * alpha))
        dxDrawRectangle(x, y, 4, h, tocolor(col[1], col[2], col[3], 255 * alpha))
        dxDrawText(a.code, x + 14, y + 6, x + 90, y + 28, tocolor(col[1], col[2], col[3], 255 * alpha), 1.15, "default-bold", "left", "center")
        dxDrawText(a.title, x + 90, y + 6, x + w - 70, y + 28, tocolor(255, 255, 255, 255 * alpha), 1.0, "default-bold", "left", "center", true)
        local dist = math.floor(getDistanceBetweenPoints3D(px, py, pz, a.x, a.y, a.z))
        dxDrawText(dist .. " m", x + w - 70, y + 6, x + w - 10, y + 28, tocolor(170, 178, 195, 255 * alpha), 0.95, "default", "right", "center")
        dxDrawText(a.zone .. (a.desc ~= "" and (" - " .. a.desc) or ""), x + 14, y + 30, x + w - 10, y + h - 4,
            tocolor(215, 220, 232, 255 * alpha), 0.9, "default", "left", "top", true, true)
        y = y + h + 8
    end
end)
