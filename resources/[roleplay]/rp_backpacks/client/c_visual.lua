--[[
    rp_backpacks / c_visual.lua
    La mochila que se ve en la espalda (y en el suelo) se crea EN EL CLIENTE para cada jugador cercano:
      - el servidor solo publica el elementData "rp:backpack" (id del item) en el jugador;
      - aqui se crea el objeto, se pega al hueso con bone_attach y se le aplica el shader de su tipo.
    Asi hace stream-in/out con el jugador (un objeto de servidor creado en 0,0,0 no se veria nunca),
    y cada tipo recibe su material (fx/backpack.fx con la receta de BACKPACKS[id].look.shader).
]]

local SHADER_FILE = "fx/backpack.fx"

local shaders = {}   -- [id] = shader (uno por tipo, compartido por todas las mochilas de ese tipo)
local visuals = {}   -- [player] = { obj = objeto, id = id }
local shaderFailed = false

addEvent("rp:bp:offset", true)

----------------------------------------------------------------
-- Shaders
----------------------------------------------------------------
local function getShader(id)
    if shaders[id] ~= nil then return shaders[id] or nil end
    local cfg = BACKPACKS[id]
    local recipe = cfg and cfg.look and cfg.look.shader
    if not recipe or shaderFailed then shaders[id] = false return nil end

    local shader = dxCreateShader(SHADER_FILE, 0, 0, false, "object")
    if not shader then
        shaderFailed = true   -- GPU sin shader model 3 o archivo roto: se ve la textura original
        outputDebugString("[rp_backpacks] No se pudo crear el shader; las mochilas usaran la textura original.", 2)
        shaders[id] = false
        return nil
    end
    dxSetShaderValue(shader, "sBody", recipe.body[1], recipe.body[2], recipe.body[3])
    dxSetShaderValue(shader, "sAccent", recipe.accent[1], recipe.accent[2], recipe.accent[3])
    dxSetShaderValue(shader, "sDark", recipe.dark[1], recipe.dark[2], recipe.dark[3])
    dxSetShaderValue(shader, "sPattern", recipe.pattern[1], recipe.pattern[2], recipe.pattern[3], recipe.pattern[4])
    dxSetShaderValue(shader, "sTile", recipe.tile)
    dxSetShaderValue(shader, "sBandV", recipe.bandV)
    dxSetShaderValue(shader, "sBandW", recipe.bandW)
    dxSetShaderValue(shader, "sSheen", recipe.sheen)
    dxSetShaderValue(shader, "sReflect", recipe.reflect)
    dxSetShaderValue(shader, "sSeed", recipe.seed)
    shaders[id] = shader
    return shader
end

local function applyShader(obj, id)
    local shader = getShader(id)
    if shader then engineApplyShaderToWorldTexture(shader, "*", obj) end
end

----------------------------------------------------------------
-- Mochila en la espalda
----------------------------------------------------------------
local function placement(cfg)
    local o = BACKPACK_OFFSET
    -- el origen del modelo esta en su base: se baja desde el borde superior segun el alto
    return o[1], o[2], o[3] - BACKPACK_MODEL_HEIGHT * cfg.look.size[1], o[4], o[5], o[6]
end

local function removeVisual(player)
    local v = visuals[player]
    if not v then return end
    visuals[player] = nil
    if isElement(v.obj) then
        exports.bone_attach:detachElementFromBone(v.obj)
        destroyElement(v.obj)
    end
end

local function refreshVisual(player)
    removeVisual(player)
    if not isElement(player) or not isElementStreamedIn(player) then return end
    local id = getElementData(player, "rp:backpack")
    local cfg = id and BACKPACKS[id]
    if not cfg then return end

    local x, y, z = getElementPosition(player)
    local obj = createObject(cfg.model, x, y, z)
    if not obj then return end
    local s = cfg.look.size
    setObjectScale(obj, s[1], s[2], s[3])
    setElementCollisionsEnabled(obj, false)
    setElementDimension(obj, getElementDimension(player))
    setElementInterior(obj, getElementInterior(player))
    exports.bone_attach:attachElementToBone(obj, player, BACKPACK_BONE, placement(cfg))
    applyShader(obj, id)
    visuals[player] = { obj = obj, id = id }
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" then
        refreshVisual(source)
    elseif getElementType(source) == "object" then
        local g = getElementData(source, "rp:ground")
        if type(g) == "table" and BACKPACKS[g.id] then applyShader(source, g.id) end
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "player" then removeVisual(source) end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:backpack" and getElementType(source) == "player" then refreshVisual(source) end
end)

addEventHandler("onClientPlayerQuit", root, function() removeVisual(source) end)

-- El objeto no cambia de dimension/interior solo; tambien limpia mochilas de jugadores que ya no estan
setTimer(function()
    for player, v in pairs(visuals) do
        if not isElement(player) or not isElement(v.obj) then
            removeVisual(player)
        else
            local d, i = getElementDimension(player), getElementInterior(player)
            if getElementDimension(v.obj) ~= d then setElementDimension(v.obj, d) end
            if getElementInterior(v.obj) ~= i then setElementInterior(v.obj, i) end
        end
    end
end, 250, 0)

-- /mochilaoffset (servidor) reenvia el offset a todos para ajustarlo en vivo
addEventHandler("rp:bp:offset", resourceRoot, function(offset)
    if type(offset) ~= "table" or #offset ~= 6 then return end
    for i = 1, 6 do
        if type(offset[i]) ~= "number" then return end
    end
    BACKPACK_OFFSET = offset
    for player in pairs(visuals) do refreshVisual(player) end
end)

----------------------------------------------------------------
-- Arranque / parada
----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do refreshVisual(player) end
    for _, obj in ipairs(getElementsByType("object", root, true)) do
        local g = getElementData(obj, "rp:ground")
        if type(g) == "table" and BACKPACKS[g.id] then applyShader(obj, g.id) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for player in pairs(visuals) do removeVisual(player) end
    for _, shader in pairs(shaders) do
        if isElement(shader) then destroyElement(shader) end
    end
end)
