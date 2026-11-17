--[[
    rp_injury / c_screen.lua
    Efecto de pantalla del jugador abatido. Solo corre en el cliente del jugador
    abatido: los demas jugadores no ven ningun cambio.

      - Escala de grises progresiva hasta 0 % de saturacion (files/downed.fx).
      - Desenfoque direccional segun la velocidad de giro de la camara: se mide el
        cambio de orientacion (yaw/pitch) entre fotogramas; cuanto mas rapido gira,
        mas largo el desenfoque. Con la camara quieta se recupera poco a poco la
        nitidez y queda un resto leve que se tambalea (mareo).
      - Entrada y salida graduales. El shader y la screen source solo existen
        mientras el efecto es visible; al terminar la salida se destruyen.

    Uso desde c_injury.lua (mismo recurso):
        InjuryScreen.fadeIn()    -- al quedar abatido
        InjuryScreen.fadeOut()   -- al ser reanimado o al aparecer en el hospital
        InjuryScreen.stop()      -- apagado inmediato (recurso parado)
]]

InjuryScreen = {}

local cfg = INJURY.SCREEN
local sw, sh = guiGetScreenSize()
local aspect = sw / sh

local shader, screenSource
local running = false
local intensity, target = 0, 0     -- 0 = pantalla normal, 1 = efecto completo
local motion = 0                   -- 0..1 desenfoque por movimiento (suavizado)
local dirX, dirY = 1, 0            -- direccion del ultimo giro (en pantalla)
local lastYaw, lastPitch

----------------------------------------------------------------
-- Recursos graficos
----------------------------------------------------------------
local function destroyGraphics()
    if isElement(shader) then destroyElement(shader) end
    if isElement(screenSource) then destroyElement(screenSource) end
    shader, screenSource = nil, nil
end

-- Devuelve false si la tarjeta no puede (se usa el respaldo sin shader)
local function createGraphics()
    if shader then return true end
    local technique
    shader, technique = dxCreateShader("files/downed.fx")
    if not shader or technique == "Fallback" then
        destroyGraphics()
        return false
    end
    screenSource = dxCreateScreenSource(sw, sh)
    if not screenSource then
        destroyGraphics()
        return false
    end
    dxSetShaderValue(shader, "ScreenTexture", screenSource)
    return true
end

----------------------------------------------------------------
-- Calculo por fotograma (antes de dibujar)
----------------------------------------------------------------
local function wrap180(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

local function approach(value, goal, rate, dt)
    return value + (goal - value) * math.min(1, rate * dt)
end

local function onPreRender(timeSlice)
    local dt = math.min(0.1, math.max(0.001, (timeSlice or 16) / 1000))

    -- Transicion lineal de entrada / salida
    if target > intensity then
        intensity = math.min(target, intensity + dt * 1000 / cfg.FADE_IN)
    elseif target < intensity then
        intensity = math.max(target, intensity - dt * 1000 / cfg.FADE_OUT)
    end
    if intensity <= 0 and target <= 0 then
        InjuryScreen.stop()
        return
    end

    -- Velocidad de giro de la camara (grados por segundo)
    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
    local dx, dy, dz = lx - cx, ly - cy, lz - cz
    local yaw = math.deg(math.atan2(dy, dx))
    local pitch = math.deg(math.atan2(dz, math.sqrt(dx * dx + dy * dy)))
    local speed, dYaw, dPitch = 0, 0, 0
    if lastYaw then
        dYaw, dPitch = wrap180(yaw - lastYaw), pitch - lastPitch
        speed = math.sqrt(dYaw * dYaw + dPitch * dPitch) / dt
        -- Un salto enorme es un corte de camara (spawn, teletransporte), no un giro
        if speed > cfg.CAMERA_CUT_SPEED then speed, dYaw, dPitch = 0, 0, 0 end
    end
    lastYaw, lastPitch = yaw, pitch

    -- Sube rapido al mover, baja despacio al quedarse quieta
    local goal = math.min(1, speed / cfg.BLUR_FULL_SPEED)
    motion = approach(motion, goal, goal > motion and cfg.BLUR_RISE or cfg.BLUR_DECAY, dt)

    -- Direccion del desenfoque = direccion del giro en pantalla (suavizada)
    if speed > 5 then
        local len = math.sqrt(dYaw * dYaw + dPitch * dPitch)
        local nx, ny = dYaw / len, -dPitch / len
        dirX, dirY = approach(dirX, nx, 12, dt), approach(dirY, ny, 12, dt)
        local l = math.sqrt(dirX * dirX + dirY * dirY)
        if l > 0.001 then dirX, dirY = dirX / l, dirY / l else dirX, dirY = nx, ny end
    end
end

----------------------------------------------------------------
-- Dibujo (prioridad alta: antes que el HUD y las demas interfaces)
----------------------------------------------------------------
local function onRender()
    -- Curva suave para que la entrada y la salida no se noten a saltos
    local e = intensity * intensity * (3 - 2 * intensity)

    if shader then
        -- Desenfoque por movimiento + resto leve que gira despacio (sensacion de mareo)
        local t = getTickCount() / 1000
        local mx = dirX * motion * cfg.BLUR_MAX
        local my = dirY * motion * cfg.BLUR_MAX
        local ix = math.cos(t * 0.7) * cfg.BLUR_IDLE
        local iy = math.sin(t * 0.9) * cfg.BLUR_IDLE
        -- En UV la unidad vertical es mas corta que la horizontal: se corrige con el aspecto
        local bx, by = (mx + ix) * e, (my + iy) * e * aspect

        dxUpdateScreenSource(screenSource, true)   -- fotograma actual, sin el efecto anterior
        dxSetShaderValue(shader, "Saturation", 1 - e)
        dxSetShaderValue(shader, "BlurDir", bx, by)
        dxDrawImage(0, 0, sw, sh, shader)
    else
        -- Respaldo sin shader: velo gris semitransparente
        dxDrawRectangle(0, 0, sw, sh, tocolor(70, 70, 70, 170 * e))
    end
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
local function ensureRunning()
    if running then return end
    running = true
    createGraphics()
    lastYaw, lastPitch, motion = nil, nil, 0
    addEventHandler("onClientPreRender", root, onPreRender)
    addEventHandler("onClientRender", root, onRender, true, "high+3")
end

function InjuryScreen.fadeIn()
    target = 1
    ensureRunning()
end

function InjuryScreen.fadeOut()
    target = 0
end

function InjuryScreen.stop()
    if not running then return end
    running = false
    removeEventHandler("onClientPreRender", root, onPreRender)
    removeEventHandler("onClientRender", root, onRender)
    destroyGraphics()
    intensity, target, motion = 0, 0, 0
end

-- Al volver de minimizado la screen source se rellena en el siguiente fotograma;
-- si el shader se perdio, se vuelve a crear
addEventHandler("onClientRestore", root, function()
    if running and not isElement(shader) then
        destroyGraphics()
        createGraphics()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function() InjuryScreen.stop() end)
