--[[
    rp_turbus · cliente

    Carga las piezas del terminal (models/, generadas con tools/build_terminal.py) en IDs nuevos y las crea como
    edificios (createBuilding) en TURBUS.ORIGIN:
      - hall / canopy: texturas NATIVAS del juego. El DFF solo trae los nombres; el modelo se apunta al TXD
        railway_las (el de las escaleras de Unity) con engineSetModelTXDID. Llevan la colisión (COL propio).
      - hall_x / canopy_x: texturas propias (turbus.txd), sin colisión (la tienen hall y canopy).
        El vidrio no es un modelo: lo dibuja c_glass.lua con primitivas 3D.
      - LOD: caja simple ligada al hall con setLowLODElement, visible de lejos sin parpadeos.
    El servidor (s_terminal.lua) quita el edificio original para todos.
]]

local C = TURBUS
local ids, objs = {}, {}
local txds = {}

local function loadTXD(path)
    if not path then return nil end
    if txds[path] == nil then
        txds[path] = fileExists(path) and engineLoadTXD(path) or false
    end
    return txds[path] or nil
end

-- engineSetModelTXDID lanza error si falla (wiki): se protege y se avisa en /debugscript
local function useNativeTXD(id)
    local ok, err = pcall(function()
        local slot = engineGetModelTXDID(C.NATIVE_TXD_FROM)
        assert(slot, "sin TXD del modelo " .. C.NATIVE_TXD_FROM)
        engineSetModelTXDID(id, slot)
    end)
    if not ok then outputDebugString("[rp_turbus] textura nativa: " .. tostring(err), 2) end
end

local function loadPart(part)
    local id = engineRequestModel("object")
    if not id then return nil end
    if part.native then
        useNativeTXD(id)
    else
        local txd = loadTXD(part.txd)
        if txd then engineImportTXD(txd, id) end
    end
    -- Marcas del modelo ANTES de poner el DFF (GTA prepara el dibujo del modelo al asignarlo). Vidrio: draw_last
    -- (después de todo), disable_backface_culling (una sola cara que se ve por los dos lados) y no_zbuffer_write
    -- (un vidrio no tapa a otro que está detrás)
    for _, flag in ipairs(part.flags or {}) do
        local ok, err = pcall(engineSetModelFlag, id, flag, true)
        if not ok then outputDebugString("[rp_turbus] " .. flag .. ": " .. tostring(err), 2) end
    end
    local dff = fileExists(part.dff) and engineLoadDFF(part.dff)
    if not dff or not engineReplaceModel(dff, id) then
        engineFreeModel(id)
        outputDebugString("[rp_turbus] no se pudo cargar " .. part.dff, 2)
        return nil
    end
    if part.col then
        local col = fileExists(part.col) and engineLoadCOL(part.col)
        if col then engineReplaceCOL(col, id) end
    end
    return id
end

-- Se crean como EDIFICIOS (createBuilding), igual que el mapa original: solo usan su prelight. Como objetos
-- (createObject) GTA les aplica luz dinámica de los faroles que la cámara tiene a la vista y el terminal entero
-- cambiaba de tono al moverse. Las piezas sin colisión llevan un COL que solo da límites (sin cajas).
-- Si createBuilding fallara (cliente antiguo), se usa createObject como respaldo.
local function spawn(id, lowLOD, asObject)
    local o = C.ORIGIN
    if not asObject then
        local ok, b = pcall(createBuilding, id, o.x, o.y, o.z, 0, 0, 0, 0)
        if ok and b then return b, true end
        outputDebugString("[rp_turbus] createBuilding falló, se usa createObject: " .. tostring(b), 2)
    end
    local obj = createObject(id, o.x, o.y, o.z, 0, 0, 0, lowLOD or false)
    if obj then setElementFrozen(obj, true) end
    return obj, false
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, part in ipairs(C.PARTS) do
        local id = loadPart(part)
        if id then
            ids[part.key] = id
            engineSetModelLODDistance(id, C.DRAW_DISTANCE)
            local el, building = spawn(id, false, part.asObject)
            if el then
                objs[part.key] = el
                if part.noCollision and not building then setElementCollisionsEnabled(el, false) end
            end
        end
    end
    local lodId = loadPart(C.LOD)
    if lodId then
        ids.lod = lodId
        engineSetModelLODDistance(lodId, C.LOD_DRAW_DISTANCE)
        local lod, building = spawn(lodId, true)
        if lod then
            if not building then setElementCollisionsEnabled(lod, false) end
            objs.lod = lod
            if objs[C.LOD.parent] then setLowLODElement(objs[C.LOD.parent], lod) end
        end
    end
end)

-- engineRequestModel no se deshace solo al parar el recurso (wiki): se liberan los IDs a mano
addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, obj in pairs(objs) do
        if isElement(obj) then destroyElement(obj) end
    end
    for _, id in pairs(ids) do engineFreeModel(id) end
end)
