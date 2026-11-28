--[[
    rp_relojflores · cliente

    Carga los modelos de tools/build_flower_clock.py y monta el reloj sobre el ancla invisible del servidor
    (objeto con data rp:flowerclock):
      - EDIFICIOS (createBuilding, como el mapa original: solo usan su prelight, sin luz dinámica que los queme):
          reloj_pasto.dff   loma con el césped NATIVO 'hedge2' (engineSetModelTXDID al TXD union_las del modelo
                            4821, el mismo del bandejón; no se reparte) y la colisión (reloj_pasto.col)
          reloj_flores.dff  esfera, números, cantero y focos (TXD propio con mipmaps)
          reloj_flores_lod.dff  LOD de lejos, ligado con setLowLODElement
      - OBJETOS locales sin colisión (se mueven o llevan alfa, que como edificio saldría opaco):
          reloj_flores_flora.dff (matas con alfa) y las tres agujas, que siguen la matriz del ancla.
    Todo modelo lleva su COL (las piezas sin colisión, uno de solo límites): si no, hereda el de 1 m y desaparece de cerca.
]]

local C = FLOWERCLOCK
local ids = {}        -- grass, base, lod, flora, hour, minute, second
local built = {}      -- [ancla] = { grass, base, lod } (edificios u objetos de respaldo)
local near = {}       -- [ancla] = { flora, hour, minute, second } (solo cerca)
local HAND_KEYS = { "hour", "minute", "second" }

local function log(msg, level) outputDebugString("[rp_relojflores] " .. msg, level or 2) end

----------------------------------------------------------------
-- Modelos
----------------------------------------------------------------
local txd, bounds, grassCol

local function loadModel(dff, opts)
    local id = engineRequestModel("object")
    if not id then return log("no quedan IDs libres para " .. dff) end
    if opts.nativeFrom then
        -- texturas del juego sin repartirlas: el modelo apunta al TXD del suelo original
        local ok, err = pcall(engineSetModelTXDID, id, engineGetModelTXDID(opts.nativeFrom))
        if not ok then log("engineSetModelTXDID falló (" .. tostring(err) .. "): el pasto saldrá blanco") end
    elseif txd then
        engineImportTXD(txd, id)
    end
    local d = fileExists(dff) and engineLoadDFF(dff)
    if not d or not engineReplaceModel(d, id, opts.alpha or false) then
        engineFreeModel(id)
        return log("no se pudo cargar " .. dff)
    end
    local col = opts.col or bounds
    if col then engineReplaceCOL(col, id) end
    engineSetModelLODDistance(id, math.min(opts.distance or C.LOD_DISTANCE, 325))
    return id
end

local function loadModels()
    txd = fileExists("models/reloj_flores.txd") and engineLoadTXD("models/reloj_flores.txd")
    bounds = fileExists("models/reloj_bounds.col") and engineLoadCOL("models/reloj_bounds.col")
    grassCol = fileExists("models/reloj_pasto.col") and engineLoadCOL("models/reloj_pasto.col")
    ids.grass = loadModel("models/reloj_pasto.dff", { nativeFrom = C.NATIVE_TXD_FROM, col = grassCol })
    ids.base = loadModel("models/reloj_flores.dff", {})
    ids.lod = loadModel("models/reloj_flores_lod.dff", { distance = C.LOD_FAR_DISTANCE })
    ids.flora = loadModel("models/reloj_flores_flora.dff", { alpha = true, distance = C.FLORA_DISTANCE })
    ids.hour = loadModel("models/reloj_aguja_hora.dff", { distance = C.HANDS_DISTANCE })
    ids.minute = loadModel("models/reloj_aguja_minuto.dff", { distance = C.HANDS_DISTANCE })
    ids.second = loadModel("models/reloj_aguja_segundo.dff", { distance = C.HANDS_DISTANCE })
end

----------------------------------------------------------------
-- Hora: ángulos de las agujas en grados (en el sentido del reloj, 0 = las 12)
----------------------------------------------------------------
local lastMinute, minuteTick = nil, 0

local function angles()
    local h, m, s, frac
    if C.TIME_SOURCE == "real" then
        local t = getRealTime()
        h, m, s, frac = t.hour, t.minute, t.second, t.second / 60
    else
        h, m = getTime()
        -- el minuto del juego dura getMinuteDuration() ms: el minutero avanza suave entre minuto y minuto
        local now = getTickCount()
        if m ~= lastMinute then lastMinute, minuteTick = m, now end
        frac = math.min((now - minuteTick) / math.max(getMinuteDuration(), 1), 0.999)
        s = getRealTime().second
    end
    local mins = m + frac
    return ((h % 12) + mins / 60) * 30, mins * 6, s * 6
end

----------------------------------------------------------------
-- Agujas: matriz del ancla · inclinación de la esfera · giro de la aguja
----------------------------------------------------------------
local TS, TC = math.sin(math.rad(C.TILT)), math.cos(math.rad(C.TILT))

local function toWorld(B, x, y, z)
    return B[1][1] * x + B[2][1] * y + B[3][1] * z,
           B[1][2] * x + B[2][2] * y + B[3][2] * z,
           B[1][3] * x + B[2][3] * y + B[3][3] * z
end

local function placeHand(obj, B, deg, height)
    local a = math.rad(deg)
    local sa, ca = math.sin(a), math.cos(a)
    local rx, ry, rz = toWorld(B, ca, -sa * TC, -sa * TS)
    local fx, fy, fz = toWorld(B, sa, ca * TC, ca * TS)
    local ux, uy, uz = toWorld(B, 0, -TS, TC)
    local px, py, pz = toWorld(B, 0, -height * TS, C.CENTER_Z + height * TC)
    setElementMatrix(obj, {
        { rx, ry, rz, 0 },
        { fx, fy, fz, 0 },
        { ux, uy, uz, 0 },
        { B[4][1] + px, B[4][2] + py, B[4][3] + pz, 1 },
    })
end

----------------------------------------------------------------
-- Piezas de cada reloj
----------------------------------------------------------------
local function anchorPose(anchor)
    local x, y, z = getElementPosition(anchor)
    local _, _, rz = getElementRotation(anchor)
    return x, y, z, rz, getElementInterior(anchor), getElementDimension(anchor)
end

-- Edificio en la dimensión 0 (los edificios están en todas); en otra dimensión, objeto de respaldo
local function piece(model, anchor, lowLOD)
    if not model then return end
    local x, y, z, rz, int, dim = anchorPose(anchor)
    if dim == 0 then
        local ok, b = pcall(createBuilding, model, x, y, z, 0, 0, rz, int)
        if ok and b then return b end
        log("createBuilding falló, se usa createObject: " .. tostring(b))
    end
    local o = createObject(model, x, y, z, 0, 0, rz, lowLOD or false)
    if o then
        setElementInterior(o, int)
        setElementDimension(o, dim)
    end
    return o
end

local function localObject(model, anchor)
    local x, y, z, rz, int, dim = anchorPose(anchor)
    local o = model and createObject(model, x, y, z, 0, 0, rz)
    if not o then return end
    setElementCollisionsEnabled(o, false)
    setElementInterior(o, int)
    setElementDimension(o, dim)
    return o
end

local function destroyAll(set)
    if set then for _, e in pairs(set) do if isElement(e) then destroyElement(e) end end end
end

local function removeNear(anchor) destroyAll(near[anchor]) near[anchor] = nil end

local function forget(anchor)
    removeNear(anchor)
    destroyAll(built[anchor])
    built[anchor] = nil
end

local function build(anchor)
    if built[anchor] then return end
    local set = { grass = piece(ids.grass, anchor), base = piece(ids.base, anchor), lod = piece(ids.lod, anchor, true) }
    if set.lod then
        for _, key in ipairs({ "base", "grass" }) do
            if set[key] then pcall(setLowLODElement, set[key], set.lod) end
        end
    end
    built[anchor] = set
end

local function addNear(anchor)
    if near[anchor] then return end
    local set = { flora = localObject(ids.flora, anchor) }
    for _, key in ipairs(HAND_KEYS) do set[key] = localObject(ids[key], anchor) end
    near[anchor] = set
end

local function isAnchor(e)
    return isElement(e) and getElementType(e) == "object" and getElementData(e, "rp:flowerclock")
end

local function apply(anchor)
    if not isAnchor(anchor) then return end
    build(anchor)
    if isElementStreamedIn(anchor) then addNear(anchor) end
end

addEventHandler("onClientPreRender", root, function()
    if not next(near) then return end
    local cx, cy, cz = getCameraMatrix()
    local hourDeg, minuteDeg, secondDeg
    for anchor, set in pairs(near) do
        if not isElement(anchor) then
            forget(anchor)
        else
            local x, y, z = getElementPosition(anchor)
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
            if dist < C.FLORA_DISTANCE then
                local B = getElementMatrix(anchor)
                if B then
                    if isElement(set.flora) then setElementMatrix(set.flora, B) end
                    if dist < C.HANDS_DISTANCE then
                        if not hourDeg then hourDeg, minuteDeg, secondDeg = angles() end
                        local deg = { hour = hourDeg, minute = minuteDeg, second = secondDeg }
                        for _, key in ipairs(HAND_KEYS) do
                            if isElement(set[key]) then placeHand(set[key], B, deg[key], C.HAND_Z[key]) end
                        end
                    end
                end
            end
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadModels()
    for _, obj in ipairs(getElementsByType("object", root)) do apply(obj) end
end)

-- engineRequestModel no se deshace solo al parar el recurso: se liberan los IDs a mano
addEventHandler("onClientResourceStop", resourceRoot, function()
    for anchor in pairs(built) do forget(anchor) end
    for anchor in pairs(near) do removeNear(anchor) end
    for _, id in pairs(ids) do engineFreeModel(id) end
end)

addEventHandler("onClientElementStreamIn", root, function() apply(source) end)
addEventHandler("onClientElementStreamOut", root, function() if near[source] then removeNear(source) end end)
addEventHandler("onClientElementDestroy", root, function() if built[source] or near[source] then forget(source) end end)
addEventHandler("onClientElementDataChange", root, function(key) if key == "rp:flowerclock" then apply(source) end end)
addEventHandler("onClientElementDimensionChange", root, function() if built[source] then forget(source) apply(source) end end)
addEventHandler("onClientElementInteriorChange", root, function() if built[source] then forget(source) apply(source) end end)
