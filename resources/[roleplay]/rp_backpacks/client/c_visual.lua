--[[
    rp_backpacks / c_visual.lua
    La mochila que se ve en la espalda (y en el suelo) se crea EN EL CLIENTE para cada jugador cercano:
      - el servidor solo publica el elementData "rp:backpack" (id del item) en el jugador;
      - aqui se crea el objeto, se pega al hueso con bone_attach y se le aplica el shader de su tipo.
    Asi hace stream-in/out con el jugador (un objeto de servidor creado en 0,0,0 no se veria nunca),
    y cada tipo recibe su material (fx/backpack.fx con la receta de BACKPACKS[id].look.shader).

    Por que cada mochila lleva SU PROPIO shader (no uno compartido por tipo):
      - rp_characters/c_body.lua escala a los personajes con altura distinta de la base y aplica body.fx a
        todo lo que llevan pegado; ese shader pisaba el de la mochila y la dejaba con la textura original.
        Ahora el objeto se marca con "rp:ownShader" (c_body lo ignora), el shader tiene prioridad 1 y hace
        el mismo escalado de altura que body.fx (sScale / sPivot).
      - Al cambiar de interior o dimension el objeto sale y vuelve a entrar en el streamer y MTA puede soltar
        el shader del elemento: se vuelve a aplicar al hacer stream-in, en los segundos posteriores a un cambio
        de mundo y, por seguridad, cada 2 segundos.
]]

local SHADER_FILE = "fx/backpack.fx"
local SHADER_PRIORITY = 1
local TICK_MS = 250

local groundShaders = {}   -- [id] = shader compartido para las mochilas del suelo (no se escalan)
local visuals = {}         -- [player] = { obj, id, shader, scale, world, reapply, tick }
local own = {}             -- [obj] = visual, para re-aplicar el shader al hacer stream-in del objeto
local shaderFailed = false

addEvent("rp:bp:offset", true)

----------------------------------------------------------------
-- Shaders
----------------------------------------------------------------
local function createShader(id)
    local cfg = BACKPACKS[id]
    local recipe = cfg and cfg.look and cfg.look.shader
    if not recipe or shaderFailed then return nil end

    local shader = dxCreateShader(SHADER_FILE, SHADER_PRIORITY, 0, false, "object")
    if not shader then
        shaderFailed = true   -- GPU sin shader model 3 o archivo roto: se ve la textura original
        outputDebugString("[rp_backpacks] No se pudo crear el shader; las mochilas usaran la textura original.", 2)
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
    return shader
end

-- Quita y vuelve a poner: asi tambien se rehace la asociacion si MTA la solto al recrear el objeto
local function applyShader(shader, obj)
    if not (isElement(shader) and isElement(obj)) then return end
    engineRemoveShaderFromWorldTexture(shader, "*", obj)
    engineApplyShaderToWorldTexture(shader, "*", obj)
end

local function groundShader(id)
    if groundShaders[id] == nil then groundShaders[id] = createShader(id) or false end
    return groundShaders[id] or nil
end

----------------------------------------------------------------
-- Escala de altura del personaje (misma que rp_characters/c_body.lua)
----------------------------------------------------------------
local function bodyScale(player)
    local res = getResourceFromName("rp_characters")
    if res and getResourceState(res) == "running" then
        return tonumber(exports.rp_characters:getPedBodyScale(player)) or 1
    end
    return 1
end

-- Punto fijo de la escala: los pies (de pie) o el centro (sentado en un vehiculo)
local function updatePivot(player, v)
    local x, y, z = getElementPosition(player)
    if not getPedOccupiedVehicle(player) then
        local base = getElementDistanceFromCentreOfMassToBaseOfModel(player)
        z = z - ((base and base > 0.2) and base or 1)
    end
    dxSetShaderValue(v.shader, "sPivot", x, y, z)
end

addEventHandler("onClientPreRender", root, function()
    for player, v in pairs(visuals) do
        if v.scale ~= 1 and isElement(player) and isElement(v.shader) then updatePivot(player, v) end
    end
end)

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
    own[v.obj] = nil
    if isElement(v.obj) then
        exports.bone_attach:detachElementFromBone(v.obj)
        destroyElement(v.obj)
    end
    if isElement(v.shader) then destroyElement(v.shader) end
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
    setElementData(obj, "rp:ownShader", true, false)   -- c_body.lua no le aplica su shader
    exports.bone_attach:attachElementToBone(obj, player, BACKPACK_BONE, placement(cfg))

    local v = {
        obj = obj, id = id, shader = createShader(id), scale = 1, tick = 0, reapply = 0,
        world = getElementDimension(player) .. ":" .. getElementInterior(player),
    }
    if v.shader then
        v.scale = bodyScale(player)
        dxSetShaderValue(v.shader, "sScale", v.scale)
        updatePivot(player, v)
        applyShader(v.shader, obj)
    end
    visuals[player] = v
    own[obj] = v
end

addEventHandler("onClientElementStreamIn", root, function()
    local kind = getElementType(source)
    if kind == "player" then
        refreshVisual(source)
    elseif kind == "object" then
        local v = own[source]
        if v then
            applyShader(v.shader, source)   -- el objeto de la espalda volvio al streamer: rehacer el shader
            return
        end
        local g = getElementData(source, "rp:ground")
        if type(g) == "table" and BACKPACKS[g.id] then applyShader(groundShader(g.id), source) end
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "player" then removeVisual(source) end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rp:backpack" and getElementType(source) == "player" then refreshVisual(source) end
    if key == "rp:body" and getElementType(source) == "player" and visuals[source] then
        local v = visuals[source]
        v.scale = bodyScale(source)
        if isElement(v.shader) then dxSetShaderValue(v.shader, "sScale", v.scale) end
    end
end)

addEventHandler("onClientPlayerQuit", root, function() removeVisual(source) end)

-- Sincroniza dimension/interior con el jugador y mantiene el shader aplicado
setTimer(function()
    for player, v in pairs(visuals) do
        if not isElement(player) or not isElement(v.obj) then
            removeVisual(player)
        else
            local d, i = getElementDimension(player), getElementInterior(player)
            if getElementDimension(v.obj) ~= d then setElementDimension(v.obj, d) end
            if getElementInterior(v.obj) ~= i then setElementInterior(v.obj, i) end

            local world = d .. ":" .. i
            if v.world ~= world then
                v.world = world
                v.reapply = 5   -- ~1,2 s volviendo a aplicarlo: el objeto se recrea en el streamer al cambiar de mundo
            end

            v.tick = v.tick + 1
            if isElement(v.shader) then
                if v.reapply > 0 then
                    v.reapply = v.reapply - 1
                    applyShader(v.shader, v.obj)
                elseif v.tick % 8 == 0 then
                    applyShader(v.shader, v.obj)   -- seguro: cada 2 s por si algo lo piso
                end
                if v.tick % 2 == 0 then
                    local scale = bodyScale(player)
                    if scale ~= v.scale then
                        v.scale = scale
                        dxSetShaderValue(v.shader, "sScale", scale)
                    end
                end
            end
        end
    end
end, TICK_MS, 0)

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
        if type(g) == "table" and BACKPACKS[g.id] then applyShader(groundShader(g.id), obj) end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for player in pairs(visuals) do removeVisual(player) end
    for _, shader in pairs(groundShaders) do
        if isElement(shader) then destroyElement(shader) end
    end
end)
