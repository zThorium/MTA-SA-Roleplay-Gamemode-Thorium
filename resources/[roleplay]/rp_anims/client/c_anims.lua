--[[
    rp_anims / c_anims.lua

    Menu radial de animaciones, dibujado con dx.
      - Mantener G: se abre el radial y aparece el cursor.
      - Mover el mouse hacia una animacion (se resalta) y soltar G: se reproduce.
      - Soltar G en el centro (o un toque rapido): cancela la animacion actual.
      - Rueda del mouse: cambia de pagina.
    El servidor valida todo; aqui solo se envia el id.
]]

local sw, sh = guiGetScreenSize()
local s = math.max(0.75, math.min(1.4, sh / 1080))

local open, page, hover = false, 1, nil
local CX, CY = sw / 2, sh / 2
local R_IN, R_OUT = 80 * s, 200 * s
local N = 8
local STEP = 360 / N
local font = "default-bold"

local function rad(a) return math.rad(a) end

-- Angulo 0 = arriba, sentido horario. Sector i centrado en (i-1)*STEP.
local function point(r, ang)
    return CX + math.sin(rad(ang)) * r, CY - math.cos(rad(ang)) * r
end

local function drawSector(i, color)
    local a0, a1 = (i - 1) * STEP - STEP / 2 + 1.2, (i - 1) * STEP + STEP / 2 - 1.2
    local verts = {}
    local seg = 8
    for k = 0, seg do
        local a = a0 + (a1 - a0) * k / seg
        local x1, y1 = point(R_OUT, a)
        local x2, y2 = point(R_IN, a)
        verts[#verts + 1] = { x1, y1, color }
        verts[#verts + 1] = { x2, y2, color }
    end
    dxDrawPrimitive("trianglestrip", false, unpack(verts))
end

local function updateHover()
    local mx, my = getCursorPosition()
    if not mx then hover = nil return end
    local dx, dy = mx * sw - CX, my * sh - CY
    if math.sqrt(dx * dx + dy * dy) < R_IN * 0.85 then hover = nil return end
    local ang = math.deg(math.atan2(dx, -dy)) % 360
    hover = math.floor((ang + STEP / 2) % 360 / STEP) + 1
end

local function render()
    updateHover()
    local data = ANIM_PAGES[page]
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 90))

    for i = 1, N do
        local a = data.list[i]
        if a then
            local on = (i == hover)
            drawSector(i, on and tocolor(255, 160, 40, 235) or tocolor(18, 20, 28, 215))
            local tx, ty = point((R_IN + R_OUT) / 2, (i - 1) * STEP)
            dxDrawText(a[1], tx - 70 * s, ty - 20 * s, tx + 70 * s, ty + 20 * s,
                on and tocolor(20, 20, 20, 255) or tocolor(235, 235, 240, 255),
                1.05 * s, font, "center", "center", false, true)
        end
    end

    -- centro
    dxDrawCircle(CX, CY, R_IN * 0.8, 0, 360, tocolor(14, 16, 24, 230), tocolor(14, 16, 24, 230), 48)
    dxDrawText(data.title, CX - R_IN, CY - 26 * s, CX + R_IN, CY, tocolor(255, 190, 90, 255), 1.15 * s, font, "center", "center")
    dxDrawText(("%d/%d  ·  rueda"):format(page, #ANIM_PAGES), CX - R_IN, CY, CX + R_IN, CY + 26 * s,
        tocolor(170, 175, 190, 255), 0.85 * s, font, "center", "center")
    dxDrawText("Soltar al centro: cancelar", 0, CY + R_OUT + 20 * s, sw, CY + R_OUT + 50 * s,
        tocolor(200, 200, 210, 200), 0.9 * s, font, "center", "center")
end

local function canOpen()
    if open then return false end
    if not getElementData(localPlayer, "rp:characterId") then return false end
    if getElementData(localPlayer, "rp:downed") or isPedDead(localPlayer) or isPedInVehicle(localPlayer) then return false end
    if isCursorShowing() or isConsoleActive() or isChatBoxInputActive() or isMainMenuActive() then return false end
    return true
end

local function wheel(dir)
    if not open then return end
    page = (page - 1 + dir) % #ANIM_PAGES + 1
end

local function openRadial()
    if not canOpen() then return end
    open, hover = true, nil
    showCursor(true)
    setCursorPosition(CX, CY)
    addEventHandler("onClientRender", root, render)
    bindKey("mouse_wheel_up", "down", wheelUp)
    bindKey("mouse_wheel_down", "down", wheelDown)
end

local function closeRadial(execute)
    if not open then return end
    open = false
    removeEventHandler("onClientRender", root, render)
    unbindKey("mouse_wheel_up", "down", wheelUp)
    unbindKey("mouse_wheel_down", "down", wheelDown)
    showCursor(false)
    if execute then
        if hover then
            triggerServerEvent("rp:anims:play", resourceRoot, (page - 1) * 8 + hover - 1)
        else
            triggerServerEvent("rp:anims:stop", resourceRoot)
        end
    end
end

function wheelUp() wheel(-1) end
function wheelDown() wheel(1) end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(ANIMS_KEY, "down", openRadial)
    bindKey(ANIMS_KEY, "up", function() closeRadial(true) end)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if open then showCursor(false) end
end)

-- si se abre otro panel o el jugador cae, se cierra sin ejecutar
addEventHandler("onClientPlayerWasted", localPlayer, function() closeRadial(false) end)
