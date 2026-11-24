--[[
    rp_characters / c_body.lua
    Altura y tono de piel de los personajes, dibujados con fx/body.fx.

    MTA no puede escalar peds ni cambiar la piel de CJ, asi que cada cliente
    aplica un shader a cada personaje con altura distinta de la base o con un
    tono de piel elegido:
      - Jugadores: segun el elementData "rp:body" = { height = cm, tone = n }
        que pone el servidor al spawnear (s_spawn.lua).
      - Ped de vista previa del creador: setPedBody(ped, height, tone).

    Lo que va pegado al ped con bone_attach (cabeza de rp_heads, toys) se
    escala con el mismo punto fijo para que no quede flotando. Es solo visual:
    la colision, la camara y la mira siguen siendo las del modelo original.
]]

local SHADER_FILE = "fx/body.fx"
local ATTACH_SCAN_INTERVAL = 500

-- Luminancia media de la piel original de CJ (sToneRef de body.fx). Si los tonos
-- salen muy claros u oscuros se afina en juego con /ajustepiel.
local TONE_REF = 0.33

local tracked = {}       -- [ped] = { scale, color, body = shader, attach = shader, objects = { [obj] = true } }
local warned = false

-- Por si isElementStreamedIn no considera "streamed in" al jugador local
local function isVisible(ped)
    return ped == localPlayer or isElementStreamedIn(ped)
end

local function destroyEntry(ped)
    local e = tracked[ped]
    if not e then return end
    if isElement(e.body) then destroyElement(e.body) end
    if isElement(e.attach) then destroyElement(e.attach) end
    tracked[ped] = nil
end

local function createShader(elementType)
    local shader = dxCreateShader(SHADER_FILE, 0, 0, false, elementType)
    if not shader and not warned then
        warned = true
        outputDebugString("[rp_characters] No se pudo crear el shader del cuerpo (altura/tono no se veran)", 2)
    end
    return shader
end

-- Punto fijo de la escala: los pies (de pie) o el centro (sentado en un vehiculo)
local function updatePivot(ped, e)
    local x, y, z = getElementPosition(ped)
    if not getPedOccupiedVehicle(ped) then
        local base = getElementDistanceFromCentreOfMassToBaseOfModel(ped)
        z = z - ((base and base > 0.2) and base or 1)
    end
    dxSetShaderValue(e.body, "sPivot", x, y, z)
    if e.attach then dxSetShaderValue(e.attach, "sPivot", x, y, z) end
end

-- Aplica (o quita) altura y tono a un ped. tone solo tiene efecto con el cuerpo de CJ.
function setPedBody(ped, height, tone)
    if not isElement(ped) then return false end

    local scale = heightToScale(height)
    if math.abs(scale - 1) < 0.005 then scale = 1 end
    local color = getElementModel(ped) == CUSTOM_SKIN and getSkinToneColor(tone) or nil

    if scale == 1 and not color then
        destroyEntry(ped)
        return true
    end

    local e = tracked[ped]
    if not e then
        local body = createShader("ped")
        if not body then return false end
        dxSetShaderValue(body, "sToneRef", TONE_REF)
        engineApplyShaderToWorldTexture(body, "*", ped)
        e = { body = body, objects = {} }
        tracked[ped] = e
    end

    e.scale, e.color = scale, color
    dxSetShaderValue(e.body, "sScale", scale)
    dxSetShaderValue(e.body, "sToneOn", color and 1 or 0)
    if color then dxSetShaderValue(e.body, "sTone", color[1], color[2], color[3]) end

    -- Objetos pegados al ped: solo hace falta escalarlos si cambia la altura
    if scale ~= 1 and not isElement(e.attach) then
        e.attach = createShader("object")
        e.objects = {}
        if e.attach then dxSetShaderValue(e.attach, "sToneOn", 0) end
    elseif scale == 1 and isElement(e.attach) then
        destroyElement(e.attach)
        e.attach, e.objects = nil, {}
    end
    if e.attach then dxSetShaderValue(e.attach, "sScale", scale) end

    updatePivot(ped, e)
    return true
end

function removePedBody(ped)
    destroyEntry(ped)
end

-- Export: escala de altura que se le esta aplicando a un ped (1 = sin cambio). Lo usan recursos que dibujan
-- objetos pegados con su propio shader (rp_backpacks) para escalarlos igual.
function getPedBodyScale(ped)
    local e = tracked[ped]
    return e and e.scale or 1
end

----------------------------------------------------------------
-- Cada frame: mover el punto fijo con el ped
----------------------------------------------------------------
addEventHandler("onClientPreRender", root, function()
    for ped, e in pairs(tracked) do
        if not isElement(ped) then
            destroyEntry(ped)
        elseif e.scale ~= 1 and isVisible(ped) then
            updatePivot(ped, e)
        end
    end
end)

-- Cabezas y toys pegados con bone_attach a un ped escalado
setTimer(function()
    local any = false
    for _, e in pairs(tracked) do
        if e.attach then any = true break end
    end
    if not any then return end

    for _, obj in ipairs(getElementsByType("object", root, true)) do
        local owner = exports.bone_attach:getElementBoneAttachmentDetails(obj)
        local e = owner and tracked[owner]
        -- "rp:ownShader": el objeto lleva su propio shader con escala (rp_backpacks): no se le pisa con este
        if e and e.attach and not e.objects[obj] and not getElementData(obj, "rp:ownShader") then
            engineApplyShaderToWorldTexture(e.attach, "*", obj)
            e.objects[obj] = true
        end
    end
    for _, e in pairs(tracked) do
        for obj in pairs(e.objects) do
            if not isElement(obj) then e.objects[obj] = nil end
        end
    end
end, ATTACH_SCAN_INTERVAL, 0)

-- Herramienta de calibracion (solo visual, local): /ajustepiel <referencia>
-- Mas bajo = tonos mas claros. Muestra el valor para fijarlo en TONE_REF.
addCommandHandler("ajustepiel", function(_, value)
    value = tonumber(value)
    if not value or value <= 0 then
        outputChatBox("Uso: /ajustepiel <referencia>   (actual: " .. TONE_REF .. ", mas bajo = mas claro)", 255, 200, 0)
        return
    end
    TONE_REF = value
    for _, e in pairs(tracked) do dxSetShaderValue(e.body, "sToneRef", value) end
    outputChatBox(("TONE_REF = %.3f"):format(value), 120, 200, 255)
end)

----------------------------------------------------------------
-- Jugadores (sincronizado por elementData del servidor)
----------------------------------------------------------------
local function refreshPlayer(player)
    local data = getElementData(player, "rp:body")
    if type(data) == "table" and isVisible(player) then
        setPedBody(player, data.height, data.tone)
    else
        destroyEntry(player)
    end
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:body" and getElementType(source) == "player" then refreshPlayer(source) end
end)

-- El tono depende del modelo (solo CJ): al cambiar de skin se recalcula
addEventHandler("onClientElementModelChange", root, function()
    if getElementType(source) == "player" then refreshPlayer(source) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" then refreshPlayer(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "player" then destroyEntry(source) end
end)

addEventHandler("onClientPlayerQuit", root, function()
    destroyEntry(source)
end)

addEventHandler("onClientElementDestroy", root, function()
    if tracked[source] then destroyEntry(source) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        refreshPlayer(player)
    end
end)
