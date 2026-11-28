--[[
    rp_pronto · cliente

    Carga las piezas de la bencinera (models/, generadas con tools/build_pronto.py) en IDs nuevos y las crea como
    edificios (createBuilding) en PRONTO.ORIGIN:
      - shop / canopy: texturas NATIVAS del juego. El DFF solo trae los nombres; el modelo se apunta al TXD
        barrio1_lae (el de la gasolinera) con engineSetModelTXDID. Llevan la colisión (COL propio).
      - shop_x / canopy_x: texturas propias (pronto.txd), sin colisión (la tienen shop y canopy).
        El vidrio no es un modelo: lo dibuja c_glass.lua con primitivas 3D.
      - LOD: cajas simples, una por pieza (tienda y techo), ligadas con setLowLODElement.
    Los muebles del interior (PRONTO_PROPS, modelos del juego) también se crean como edificios: así usan su propia
    luz horneada y no cambian de tono con los faroles. El servidor (s_pronto.lua) quita la gasolinera original.
]]

local C = PRONTO
local ids, objs, props = {}, {}, {}
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
    if not ok then outputDebugString("[rp_pronto] textura nativa: " .. tostring(err), 2) end
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
    local dff = fileExists(part.dff) and engineLoadDFF(part.dff)
    if not dff or not engineReplaceModel(dff, id) then
        engineFreeModel(id)
        outputDebugString("[rp_pronto] no se pudo cargar " .. part.dff, 2)
        return nil
    end
    if part.col then
        local col = fileExists(part.col) and engineLoadCOL(part.col)
        if col then engineReplaceCOL(col, id) end
    end
    return id
end

-- Edificio (solo usa su prelight, como el mapa original). Si createBuilding fallara (cliente antiguo o un modelo
-- que no lo admite), se usa createObject congelado como respaldo.
local function spawn(id, x, y, z, rz, lowLOD)
    local ok, b = pcall(createBuilding, id, x, y, z, 0, 0, rz or 0, 0)
    if ok and b then return b, true end
    local obj = createObject(id, x, y, z, 0, 0, rz or 0, lowLOD or false)
    if obj then setElementFrozen(obj, true) end
    return obj, false
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local o = C.ORIGIN
    for _, part in ipairs(C.PARTS) do
        local id = loadPart(part)
        if id then
            ids[part.key] = id
            engineSetModelLODDistance(id, C.DRAW_DISTANCE)
            local el, building = spawn(id, o.x, o.y, o.z, 0)
            if el then
                objs[part.key] = el
                if part.noCollision and not building then setElementCollisionsEnabled(el, false) end
            else
                outputDebugString("[rp_pronto] no se pudo crear la pieza " .. part.key, 2)
            end
        end
    end
    for i, def in ipairs(C.LODS) do
        local lodId = loadPart(def)
        if lodId then
            ids["lod" .. i] = lodId
            engineSetModelLODDistance(lodId, C.LOD_DRAW_DISTANCE)
            local lod, building = spawn(lodId, o.x, o.y, o.z, 0, true)
            if lod then
                if not building then setElementCollisionsEnabled(lod, false) end
                objs["lod" .. i] = lod
                if objs[def.parent] then setLowLODElement(objs[def.parent], lod) end
            end
        end
    end
    -- muebles del interior (modelos del juego)
    local fallback = 0
    for _, p in ipairs(type(PRONTO_PROPS) == "table" and PRONTO_PROPS or {}) do
        local el, building = spawn(p[1], p[2], p[3], p[4], p[5])
        if el then
            props[#props + 1] = el
            if not building then fallback = fallback + 1 end
        end
    end
    if fallback > 0 then
        outputDebugString(("[rp_pronto] %d muebles creados como objeto (createBuilding no los admitió)"):format(fallback), 3)
    end
end)

-- engineRequestModel no se deshace solo al parar el recurso (wiki): se liberan los IDs a mano
addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, list in ipairs({ objs, props }) do
        for _, el in pairs(list) do
            if isElement(el) then destroyElement(el) end
        end
    end
    for _, id in pairs(ids) do engineFreeModel(id) end
end)
