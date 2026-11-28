--[[
    rp_furniture / c_core.lua
    Parte del cliente que funciona siempre (sin modo construccion):
      - estilo (color/material) de cada mueble al aparecer en pantalla
      - sonido 3D de TV y equipos de musica
      - objetos originales del interior ocultados por el dueno
      - tecla G: usar mueble (Shift+G elige emisora) y ventana modal (contenedores, emisoras)
]]

FurnCore = { pid = nil, canBuild = false, interior = 0, removed = {}, building = false }

local screenW, screenH = guiGetScreenSize()
local sounds = {}          -- [obj] = { sound, key }
local hiddenApplied = {}   -- lista aplicada con removeWorldModel
local modal = { gui = nil, browser = nil, ready = false, pending = {} }
local nearObj = nil

addEvent("rp:furn:enter", true)
addEvent("rp:furn:leave", true)
addEvent("rp:furn:props", true)
addEvent("rp:furn:toggle", true)
addEvent("rp:furn:storage", true)
addEvent("rp:furn:ui:modalClose", false)
addEvent("rp:furn:ui:stPut", false)
addEvent("rp:furn:ui:stTake", false)
addEvent("rp:furn:ui:station", false)

----------------------------------------------------------------
-- Utilidades compartidas
----------------------------------------------------------------
function FurnCore.objects()
    local list = {}
    if not FurnCore.pid then return list end
    local dim = getElementDimension(localPlayer)
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        local d = getElementData(obj, "rp:furn", false)
        if d and getElementDimension(obj) == dim then list[#list + 1] = obj end
    end
    return list
end

function FurnCore.byId(fid)
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do
        local d = getElementData(obj, "rp:furn", false)
        if d and d.id == fid then return obj, d end
    end
end

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end
FurnCore.jsString = jsString

----------------------------------------------------------------
-- Estilo y sonido de cada mueble
----------------------------------------------------------------
local function stopObjSound(obj)
    local s = sounds[obj]
    if s then
        if isElement(s.sound) then destroyElement(s.sound) end
        sounds[obj] = nil
    end
end

local function applyObject(obj)
    if not isElement(obj) then return end
    local d = getElementData(obj, "rp:furn", false)
    if not d then return end
    FurnStyle.apply(obj, d.color, d.mat)

    local def = FURN_ITEMS[d.key]
    local wantSound = def and (def.act == "tv" or def.act == "hifi") and d.on and FURN_STATION_BY_ID[d.st]
    local cur = sounds[obj]
    if not wantSound then return stopObjSound(obj) end
    local key = d.st
    if cur and cur.key == key and isElement(cur.sound) then return end
    stopObjSound(obj)
    local x, y, z = getElementPosition(obj)
    local snd = playSound3D(FURN_STATION_BY_ID[d.st].url, x, y, z, true)
    if snd then
        setSoundMaxDistance(snd, def.act == "hifi" and 28 or 18)
        setSoundVolume(snd, 0.75)
        setElementInterior(snd, getElementInterior(obj))
        setElementDimension(snd, getElementDimension(obj))
        sounds[obj] = { sound = snd, key = key }
    end
end

addEventHandler("onClientElementStreamIn", resourceRoot, function()
    if getElementType(source) == "object" then applyObject(source) end
end)
addEventHandler("onClientElementStreamOut", resourceRoot, function()
    if getElementType(source) == "object" then stopObjSound(source) FurnStyle.clear(source) end
end)
addEventHandler("onClientElementDestroy", resourceRoot, function()
    if getElementType(source) == "object" then stopObjSound(source) end
end)
addEventHandler("onClientElementDataChange", resourceRoot, function(key)
    if key == "rp:furn" and getElementType(source) == "object" then applyObject(source) end
end)

local function refreshAll()
    for _, obj in ipairs(getElementsByType("object", resourceRoot, true)) do applyObject(obj) end
end
FurnCore.refreshAll = refreshAll

----------------------------------------------------------------
-- Objetos originales ocultos
----------------------------------------------------------------
local propIdList

local function eachPropId(fn)
    if not propIdList then
        propIdList = {}
        for id in pairs(FURN_DEFAULT_PROP_IDS) do propIdList[#propIdList + 1] = id end
        table.sort(propIdList)
    end
    for _, id in ipairs(propIdList) do fn(id) end
end

local function keyOf(m, x, y, z, r) return ("%d|%.2f|%.2f|%.2f|%.2f"):format(m, x, y, z, r) end

local function restoreEntry(e)
    e.active = false
    if e.m == -1 then
        eachPropId(function(id) restoreWorldModel(id, e.r, e.x, e.y, e.z, e.int) end)
    else
        restoreWorldModel(e.m, e.r, e.x, e.y, e.z, e.int)
    end
end

local function applyEntry(e, interior)
    local rad = tonumber(e.r) or 0.4
    local entry = { m = e.m, x = e.x, y = e.y, z = e.z, r = rad, int = interior, active = true, key = keyOf(e.m, e.x, e.y, e.z, rad) }
    hiddenApplied[#hiddenApplied + 1] = entry
    if e.m == -1 then
        -- comodin: unos 1100 modelos de mobiliario; por tandas para no congelar el juego
        eachPropId(function() end)
        local i = 1
        local function step()
            if not entry.active then return end
            for _ = 1, 120 do
                local id = propIdList[i]
                if not id then return end
                removeWorldModel(id, rad, e.x, e.y, e.z, interior)
                i = i + 1
            end
            setTimer(step, 30, 1)
        end
        step()
    else
        removeWorldModel(e.m, rad, e.x, e.y, e.z, interior)
    end
end

local function restoreHidden()
    for _, a in ipairs(hiddenApplied) do restoreEntry(a) end
    hiddenApplied = {}
end

-- Aplica la lista de objetos ocultos tocando solo lo que cambio (restaurar y volver a quitar
-- todo el mobiliario cada vez seria lento)
local function applyHidden(list, interior)
    FurnCore.removed = list or {}
    local wanted = {}
    for _, e in ipairs(FurnCore.removed) do
        if type(e) == "table" and tonumber(e.m) and tonumber(e.x) and tonumber(e.y) and tonumber(e.z) then
            wanted[keyOf(e.m, e.x, e.y, e.z, tonumber(e.r) or 0.4)] = e
        end
    end
    local keep = {}
    for _, a in ipairs(hiddenApplied) do
        if wanted[a.key] and a.int == interior and not keep[a.key] then keep[a.key] = a else restoreEntry(a) end
    end
    hiddenApplied = {}
    for _, a in pairs(keep) do hiddenApplied[#hiddenApplied + 1] = a end
    for k, e in pairs(wanted) do
        if not keep[k] then applyEntry(e, interior) end
    end
end

addEventHandler("rp:furn:enter", resourceRoot, function(pid, canBuild, removed)
    FurnCore.pid, FurnCore.canBuild = pid, canBuild
    FurnCore.interior = getElementInterior(localPlayer)
    applyHidden(removed, FurnCore.interior)
    refreshAll()
end)

addEventHandler("rp:furn:props", resourceRoot, function(list)
    if FurnCore.pid then applyHidden(list, FurnCore.interior) end
end)

addEventHandler("rp:furn:leave", resourceRoot, function()
    if FurnEditor and FurnEditor.active then FurnEditor.stop(true) end
    restoreHidden()
    FurnCore.pid, FurnCore.canBuild, FurnCore.removed = nil, false, {}
    for obj in pairs(sounds) do stopObjSound(obj) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    restoreHidden()
    for obj in pairs(sounds) do stopObjSound(obj) end
end)

----------------------------------------------------------------
-- Ventana modal (contenedores y emisoras)
----------------------------------------------------------------
local function modalJS(code)
    if isElement(modal.browser) and modal.ready then executeBrowserJavascript(modal.browser, code)
    else modal.pending[#modal.pending + 1] = code end
end

function FurnCore.closeModal()
    if not isElement(modal.gui) then return end
    destroyElement(modal.gui)
    modal.gui, modal.browser, modal.ready, modal.pending = nil, nil, false, {}
    if not FurnCore.building then
        showCursor(false)
        guiSetInputEnabled(false)
    end
    if FurnCore.modalKind == "storage" then triggerServerEvent("rp:furn:stClose", resourceRoot) end
    FurnCore.modalKind = nil
end

function FurnCore.openModal(kind, payload)
    if not isElement(modal.gui) then
        modal.gui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
        modal.browser = guiGetBrowser(modal.gui)
        addEventHandler("onClientBrowserCreated", modal.browser, function() loadBrowserURL(source, "http://mta/local/html/index.html#modal") end)
        addEventHandler("onClientBrowserDocumentReady", modal.browser, function()
            modal.ready = true
            for _, code in ipairs(modal.pending) do executeBrowserJavascript(source, code) end
            modal.pending = {}
        end)
        showCursor(true)
        -- misma escala que los paneles del editor (diseno a 1000 px de alto)
        modalJS(("FURN.zoom(%.4f)"):format(math.max(0.8, math.min(1.8, screenH / 1000))))
    end
    FurnCore.modalKind = kind
    modalJS(("FURN.modal(%s, %s[0])"):format(jsString(kind), toJSON(payload or {}, true)))
end

addEventHandler("rp:furn:ui:modalClose", root, function() FurnCore.closeModal() end)

addEventHandler("rp:furn:storage", resourceRoot, function(data)
    if FurnCore.modalKind and FurnCore.modalKind ~= "storage" then return end
    FurnCore.openModal("storage", data)
end)
addEventHandler("rp:furn:ui:stPut", root, function(fid, item, amount)
    triggerServerEvent("rp:furn:stPut", resourceRoot, fid, item, amount)
end)
addEventHandler("rp:furn:ui:stTake", root, function(fid, item, amount)
    triggerServerEvent("rp:furn:stTake", resourceRoot, fid, item, amount)
end)
addEventHandler("rp:furn:ui:station", root, function(fid, id)
    triggerServerEvent("rp:furn:setStation", resourceRoot, fid, id)
    FurnCore.closeModal()
end)

----------------------------------------------------------------
-- Usar muebles (G)
----------------------------------------------------------------
local function findNear()
    if not FurnCore.pid or FurnCore.building then return end
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestD
    for _, obj in ipairs(FurnCore.objects()) do
        local d = getElementData(obj, "rp:furn", false)
        local def = FURN_ITEMS[d.key]
        if def and def.act then
            local ox, oy, oz = getElementPosition(obj)
            local dist = getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz)
            local limit = FURN.USE_DISTANCE + 0.6 * (def.struct and 0 or 1)
            if dist <= limit and (not bestD or dist < bestD) then best, bestD = obj, dist end
        end
    end
    return best
end

setTimer(function() nearObj = findNear() end, 250, 0)

local function useNear(shift)
    if isChatBoxInputActive() or isElement(modal.gui) or isMainMenuActive() then return end
    if getElementData(localPlayer, "rp:downed") then return end
    local obj = nearObj
    if not obj then
        -- sentado: G para levantarse (el servidor sabe si estas sentado)
        if FurnCore.pid and not FurnCore.building then triggerServerEvent("rp:furn:use", resourceRoot, -1) end
        return
    end
    local d = getElementData(obj, "rp:furn", false)
    local def = d and FURN_ITEMS[d.key]
    if not def then return end
    if shift and (def.act == "tv" or def.act == "hifi") then
        local list = {}
        for _, st in ipairs(FURN_STATIONS) do list[#list + 1] = { id = st.id, name = st.name } end
        return FurnCore.openModal("stations", { fid = d.id, current = d.st, stations = list, title = def.name })
    end
    triggerServerEvent("rp:furn:use", resourceRoot, d.id)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(FURN.USE_KEY, "down", function() useNear(getKeyState("lshift") or getKeyState("rshift")) end)
    bindKey(FURN.BUILD_KEY, "down", function()
        if isChatBoxInputActive() or isMainMenuActive() then return end
        if FurnEditor and FurnEditor.active then FurnEditor.requestStop(true) else triggerServerEvent("rp:furn:startBuild", resourceRoot) end
    end)
end)

addEventHandler("rp:furn:toggle", resourceRoot, function()
    if FurnEditor and FurnEditor.active then FurnEditor.requestStop(true) else triggerServerEvent("rp:furn:startBuild", resourceRoot) end
end)

local ACT_VERB = { sleep = "dormir", sit = "sentarte", light = "encender/apagar", tv = "encender/apagar", hifi = "encender/apagar",
                   storage = "abrir", sink = "beber", toilet = "usar", bath = "usar" }

addEventHandler("onClientRender", root, function()
    if not nearObj or not isElement(nearObj) or isElement(modal.gui) or FurnCore.building then return end
    local d = getElementData(nearObj, "rp:furn", false)
    local def = d and FURN_ITEMS[d.key]
    if not def then return end
    local text = ("G: %s %s"):format(ACT_VERB[def.act] or "usar", def.name:lower())
    if def.act == "tv" or def.act == "hifi" then text = text .. "  |  Shift+G: emisora" end
    local w = dxGetTextWidth(text, 1.1, "default-bold") + 40
    local x, y = (screenW - w) / 2, screenH - 190
    dxDrawRectangle(x, y, w, 36, tocolor(12, 14, 20, 210))
    dxDrawRectangle(x, y, 3, 36, tocolor(245, 165, 36, 255))
    dxDrawText(text, x, y, x + w, y + 36, tocolor(242, 244, 248), 1.1, "default-bold", "center", "center")
end)
