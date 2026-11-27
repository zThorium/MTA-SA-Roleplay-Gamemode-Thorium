--[[
    rp_train · postes de metro (cliente)

    Carga el modelo de cada estación (models/metro_pole_<nodo>.dff, colisión compartida metro_pole.col,
    generados con tools/build_metro_pole.py) en un ID nuevo y se lo pone a los objetos que el servidor
    marca con data rp:train:pole = nodo (s_stations.lua, /crearpostemetro). Sin el modelo queda el provisional.
]]

local models = {} -- [nodo] = id de modelo

local function loadModels()
    -- Texturas compartidas (pintura, acero, rojo, letrero y el reflejo mp_env)
    local txd = fileExists("models/metro_pole.txd") and engineLoadTXD("models/metro_pole.txd")
    for node in pairs(TRAIN.STATION_NAMES) do
        local path = ("models/metro_pole_%d.dff"):format(node)
        if fileExists(path) then
            local id = engineRequestModel("object")
            if id and txd then engineImportTXD(txd, id) end
            local dff = id and engineLoadDFF(path)
            if id and dff and engineReplaceModel(dff, id) then
                local col = fileExists("models/metro_pole.col") and engineLoadCOL("models/metro_pole.col")
                if col then engineReplaceCOL(col, id) end
                engineSetModelLODDistance(id, TRAIN.POLE_LOD_DISTANCE)
                models[node] = id
            else
                if id then engineFreeModel(id) end
                outputDebugString("[rp_train] no se pudo cargar " .. path, 2)
            end
        end
    end
end

local function apply(obj)
    if not isElement(obj) or getElementType(obj) ~= "object" then return end
    local id = models[tonumber(getElementData(obj, "rp:train:pole"))]
    if id and getElementModel(obj) ~= id then setElementModel(obj, id) end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadModels()
    for _, obj in ipairs(getElementsByType("object", root)) do apply(obj) end
end)
addEventHandler("onClientElementStreamIn", root, function() apply(source) end)
addEventHandler("onClientElementDataChange", root, function(key) if key == "rp:train:pole" then apply(source) end end)
