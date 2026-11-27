--[[
    rp_train · carteles LED de las estaciones (cliente)

    Cada elemento rp_trainsign (s_stations.lua) es un letrero de matriz de LED rojos con el texto que
    se desplaza: llegada estimada del tren de pasajeros a esa estación (rp:train:eta, la publica el
    servidor cada TRAIN.ETA_MS y aquí se descuenta entre medias), o la cuenta atrás de la salida si el
    tren está en el andén.

    Solo se dibujan los carteles a menos de SIGN_DRAW_DISTANCE de la cámara: cada uno tiene su render
    target (se crea al acercarse y se libera al alejarse). El efecto de LED es una máscara de puntos
    (images/led_dot.png) repetida sobre el texto.
]]

local RT_W, RT_H = 512, 96
local BORDER = 6
local PITCH = 4               -- px del render target por LED
local SCALE, FONT = 3.6, "default-bold"
local SCROLL = 70             -- px por segundo del texto que se desplaza
local LIT, UNLIT = tocolor(255, 48, 24), tocolor(52, 8, 6)

local near = {}               -- [cartel] = render target
local eta, etaAt = {}, 0
local dotTex

local function readEta()
    eta, etaAt = getElementData(resourceRoot, "rp:train:eta") or {}, getTickCount()
end

addEventHandler("onClientElementDataChange", resourceRoot, function(key)
    if key == "rp:train:eta" then readEta() end
end)

local function clock(sec)
    sec = math.max(0, math.floor(sec))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function signText(el, now)
    local name = tostring(getElementData(el, "name") or "Estación"):upper()
    local e = eta[tostring(getElementData(el, "station"))]
    if not e then return name .. "  ·  SIN SERVICIO" end
    local left = e[1] - (now - etaAt) / 1000
    local nextStop = tostring(e[3] or ""):upper()
    if e[2] == 1 then
        return ("TREN EN ANDÉN  ·  SALE EN %d s  ·  PRÓXIMA PARADA: %s"):format(math.max(0, math.ceil(left)), nextStop)
    end
    if left < 30 then return ("%s  ·  EL TREN ESTÁ LLEGANDO"):format(name) end
    return ("%s  ·  PRÓXIMO TREN EN %s  ·  DIRECCIÓN %s"):format(name, clock(left), nextStop)
end

local function drawSign(rt, text, now)
    dxSetRenderTarget(rt, true)
    local iw, ih = RT_W - BORDER * 2, RT_H - BORDER * 2
    dxDrawRectangle(BORDER, BORDER, iw, ih, UNLIT)
    local tw = dxGetTextWidth(text, SCALE, FONT)
    local x = tw <= iw and BORDER + (iw - tw) / 2 or BORDER + iw - ((now / 1000 * SCROLL) % (tw + iw))
    dxDrawText(text, x, BORDER, x + tw, RT_H - BORDER, LIT, SCALE, FONT, "left", "center")
    -- matriz de puntos: la máscara (negro con huecos redondos) se repite cada PITCH px
    dxDrawImageSection(BORDER, BORDER, iw, ih, 0, 0, iw / PITCH * 8, ih / PITCH * 8, dotTex)
    -- carcasa (tapa también el texto que se sale por los lados)
    local case = tocolor(18, 18, 20)
    dxDrawRectangle(0, 0, RT_W, BORDER, case)
    dxDrawRectangle(0, RT_H - BORDER, RT_W, BORDER, case)
    dxDrawRectangle(0, 0, BORDER, RT_H, case)
    dxDrawRectangle(RT_W - BORDER, 0, BORDER, RT_H, case)
    dxSetRenderTarget()
end

-- Cada 500 ms: qué carteles están cerca de la cámara (crea o libera su render target)
local function refreshNear()
    local cx, cy, cz = getCameraMatrix()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local seen = {}
    for _, el in ipairs(getElementsByType("rp_trainsign")) do
        local x, y, z = getElementPosition(el)
        if getElementDimension(el) == dim and getElementInterior(el) == int
            and getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) < TRAIN.SIGN_DRAW_DISTANCE then
            seen[el] = true
            if not near[el] then near[el] = dxCreateRenderTarget(RT_W, RT_H, false) or false end
        end
    end
    for el, rt in pairs(near) do
        if not seen[el] then
            if isElement(rt) then destroyElement(rt) end
            near[el] = nil
        end
    end
end

addEventHandler("onClientRender", root, function()
    if not next(near) then return end
    local now = getTickCount()
    for el, rt in pairs(near) do
        if rt and isElement(el) then
            drawSign(rt, signText(el, now), now)
            local x, y, z = getElementPosition(el)
            local rot = math.rad(tonumber(getElementData(el, "rot")) or 0)
            local h = TRAIN.SIGN_HEIGHT / 2
            dxDrawMaterialLine3D(x, y, z + h, x, y, z - h, rt, TRAIN.SIGN_WIDTH, tocolor(255, 255, 255),
                x - math.sin(rot), y + math.cos(rot), z)
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    dotTex = dxCreateTexture("images/led_dot.png", "argb", false, "wrap")
    readEta()
    setTimer(refreshNear, 500, 0)
end)
