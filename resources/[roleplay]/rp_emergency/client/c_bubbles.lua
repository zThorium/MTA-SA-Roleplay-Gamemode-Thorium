--[[
    rp_emergency / c_bubbles.lua
    Globos de texto de rol sobre la cabeza de los paramedicos (lo que dicen, sus /me
    y la radio), y la misma linea en el chat local para quien este cerca.
    Tambien el destello y el temblor de la descarga del desfibrilador para el paciente.
]]

local bubbles = {}       -- [ped] = { text, kind, name, started, ms }
local CHAT_RANGE = 20
local DRAW_RANGE = 32
local MAX_WIDTH = 270

local COLORS = {
    say   = { 255, 255, 255 },
    me    = { 194, 162, 218 },
    radio = { 140, 200, 255 },
}

addEvent("rp:emergency:say", true)
addEvent("rp:emergency:shock", true)

addEventHandler("rp:emergency:say", resourceRoot, function(ped, text, kind, ms, name)
    if not isElement(ped) or type(text) ~= "string" then return end
    kind = COLORS[kind] and kind or "say"
    name = tostring(name or "Paramedico")
    bubbles[ped] = { text = text, kind = kind, name = name, started = getTickCount(), ms = tonumber(ms) or 4000 }

    local x, y, z = getElementPosition(ped)
    local px, py, pz = getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= CHAT_RANGE then
        local c = COLORS[kind]
        if kind == "me" then
            outputChatBox("* " .. name .. " " .. text, c[1], c[2], c[3])
        elseif kind == "radio" then
            outputChatBox("[Radio] " .. name .. ": " .. text, c[1], c[2], c[3])
        else
            outputChatBox(name .. " dice: " .. text, 230, 230, 230)
        end
    end
end)

-- Parte el texto en lineas que quepan en el ancho maximo
local function wrap(text, scale, font, maxW)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if dxGetTextWidth(try, scale, font) > maxW and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local cx, cy, cz = getCameraMatrix()
    for ped, b in pairs(bubbles) do
        local age = now - b.started
        if not isElement(ped) or age > b.ms then
            bubbles[ped] = nil
        elseif isElementStreamedIn(ped) then
            local hx, hy, hz = getPedBonePosition(ped, 8)
            if hx then
                local d = getDistanceBetweenPoints3D(cx, cy, cz, hx, hy, hz)
                if d <= DRAW_RANGE and isLineOfSightClear(cx, cy, cz, hx, hy, hz + 0.4, true, false, false, true, false, false, false) then
                    local sx, sy = getScreenFromWorldPosition(hx, hy, hz + 0.45, 0.06)
                    if sx then
                        local alpha = math.min(1, age / 150, (b.ms - age) / 400)
                        local scale = math.max(0.75, math.min(1.1, 1.25 - d / 30))
                        local font = "default-bold"
                        local text = b.kind == "me" and ("* " .. b.text) or b.text
                        local lines = wrap(text, scale, font, MAX_WIDTH * scale)
                        local lh = dxGetFontHeight(scale, font)
                        local w = 0
                        for _, l in ipairs(lines) do w = math.max(w, dxGetTextWidth(l, scale, font)) end
                        local nameH = dxGetFontHeight(scale * 0.85, "default")
                        local pad = 7 * scale
                        local bw, bh = w + pad * 2, #lines * lh + nameH + pad * 2
                        local bx, by = sx - bw / 2, sy - bh
                        dxDrawRectangle(bx, by, bw, bh, tocolor(12, 14, 20, 200 * alpha))
                        dxDrawRectangle(bx, by, 3 * scale, bh, tocolor(230, 70, 70, 230 * alpha))
                        dxDrawText(b.name, bx + pad, by + pad * 0.6, bx + bw, by + nameH, tocolor(255, 120, 120, 255 * alpha), scale * 0.85, "default")
                        local c = COLORS[b.kind]
                        for k, l in ipairs(lines) do
                            dxDrawText(l, bx + pad, by + pad * 0.6 + nameH + (k - 1) * lh, bx + bw, by + bh,
                                tocolor(c[1], c[2], c[3], 255 * alpha), scale, font)
                        end
                    end
                end
            end
        end
    end
end)

----------------------------------------------------------------
-- Descarga del desfibrilador (solo la ve el paciente)
----------------------------------------------------------------
local flashUntil = 0
local function drawFlash()
    local left = flashUntil - getTickCount()
    if left <= 0 then
        removeEventHandler("onClientRender", root, drawFlash)
        setCameraDrunkLevel(0)
        return
    end
    local sw, sh = guiGetScreenSize()
    dxDrawRectangle(0, 0, sw, sh, tocolor(255, 255, 255, math.min(220, left / 450 * 220)))
end

addEventHandler("rp:emergency:shock", resourceRoot, function()
    if flashUntil > getTickCount() then return end
    flashUntil = getTickCount() + 450
    addEventHandler("onClientRender", root, drawFlash)
    setCameraDrunkLevel(200)
    playSoundFrontEnd(40)
end)
