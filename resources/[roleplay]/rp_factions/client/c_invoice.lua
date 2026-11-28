--[[
    rp_factions / c_invoice.lua  (cliente)
    Ventana de factura que recibe el cliente (#106): emisor, facción, monto y concepto, con las
    teclas dibujadas: 1 pagar en efectivo, 2 pagar con el banco, Retroceso rechazar.
    Una barra muestra el tiempo que queda. El servidor valida y cobra (s_invoices.lua).
]]

local sw, sh = guiGetScreenSize()
local S = math.max(0.8, math.min(1.25, sh / 900))
local inv = nil          -- datos de la factura abierta + start
local tex, fTitle, fText, fBig = {}, nil, nil, nil

addEvent("rp:fac:invoice", true)
addEvent("rp:fac:invoiceEnd", true)

local function hexColor(h, a)
    local r, g, b = tostring(h or ""):match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return tocolor(245, 165, 36, a or 255) end
    return tocolor(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), a or 255)
end

local function money(n)
    local s = tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1."):reverse()
    return "$" .. s:gsub("^%.", "")
end

local function answer(method)
    if not inv then return end
    inv = nil
    triggerServerEvent("rp:fac:invoiceAnswer", resourceRoot, method)
    local s = playSound(method and "sounds/confirmation_003.ogg" or "sounds/error_004.ogg")
    if s then setSoundVolume(s, 0.5) end
end

local function onKey(key, press)
    if not press or not inv or isChatBoxInputActive() or isConsoleActive() then return end
    if key == "1" then answer("cash"); cancelEvent()
    elseif key == "2" then answer("bank"); cancelEvent()
    elseif key == "backspace" then answer(false); cancelEvent() end
end

addEventHandler("rp:fac:invoice", resourceRoot, function(d)
    if type(d) ~= "table" then return end
    inv = d
    inv.start = getTickCount()
    local s = playSound("sounds/glass_001.ogg")
    if s then setSoundVolume(s, 0.6) end
end)
addEventHandler("rp:fac:invoiceEnd", resourceRoot, function() inv = nil end)

local function keyRow(x, y, img, text, enabled)
    local a = enabled and 255 or 110
    dxDrawImage(x, y, 34 * S, 34 * S, img, 0, 0, 0, tocolor(255, 255, 255, a))
    dxDrawText(text, x + 42 * S, y, x + 300 * S, y + 34 * S, tocolor(235, 240, 248, a), 1, fText, "left", "center")
end

addEventHandler("onClientRender", root, function()
    if not inv then return end
    local left = inv.seconds * 1000 - (getTickCount() - inv.start)
    if left <= 0 then inv = nil return end
    local w, h = 380 * S, 290 * S
    local x, y = sw - w - 30 * S, sh * 0.30
    local accent = hexColor(inv.color)
    dxDrawRectangle(x + 4 * S, y + 6 * S, w, h, tocolor(0, 0, 0, 90))
    dxDrawRectangle(x, y, w, h, tocolor(12, 16, 24, 235))
    dxDrawRectangle(x, y, w, 4 * S, accent)
    -- Barra del tiempo
    dxDrawRectangle(x, y + h - 4 * S, w * (left / (inv.seconds * 1000)), 4 * S, left < 10000 and tocolor(255, 90, 90) or accent)

    local px = x + 18 * S
    dxDrawText("FACTURA · " .. tostring(inv.tag or ""), px, y + 14 * S, x + w, 0, accent, 1, fText, "left", "top")
    dxDrawText(tostring(inv.faction or ""), px, y + 34 * S, x + w - 18 * S, 0, tocolor(255, 255, 255), 1, fTitle, "left", "top", true)
    dxDrawText("De " .. tostring(inv.from or ""), px, y + 58 * S, x + w, 0, tocolor(160, 175, 200), 1, fText, "left", "top")
    dxDrawText(money(inv.amount), px, y + 80 * S, x + w, 0, tocolor(255, 255, 255), 1, fBig, "left", "top")
    dxDrawText(tostring(inv.concept or ""), px, y + 124 * S, x + w - 18 * S, y + 150 * S, tocolor(200, 210, 225), 1, fText, "left", "top", true, true)

    local cashOk = (inv.cash or 0) >= inv.amount
    keyRow(px, y + 158 * S, tex.k1, "Pagar en efectivo" .. (cashOk and "" or " (no te alcanza)"), cashOk)
    keyRow(px, y + 194 * S, tex.k2, "Pagar con el banco", true)
    keyRow(px, y + 230 * S, tex.back, "Rechazar", true)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    tex.k1 = dxCreateTexture("images/keyboard_1.png")
    tex.k2 = dxCreateTexture("images/keyboard_2.png")
    tex.back = dxCreateTexture("images/keyboard_backspace.png")
    fText = dxCreateFont("fonts/rubik_medium.ttf", math.floor(10 * S + 0.5)) or "default"
    fTitle = dxCreateFont("fonts/rubik_semibold.ttf", math.floor(13 * S + 0.5)) or "default-bold"
    fBig = dxCreateFont("fonts/rubik_semibold.ttf", math.floor(24 * S + 0.5)) or "default-bold"
    addEventHandler("onClientKey", root, onKey)
end)
