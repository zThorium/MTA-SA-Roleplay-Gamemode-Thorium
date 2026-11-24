--[[
    rp_characters / c_characters.lua
    Interfaz CEF de seleccion y creacion de personajes, con un ped local de
    vista previa al que se le cambia la skin y se puede girar con el raton.

    JS  -> Lua : mta.triggerEvent("rp:chars:ui:*", ...)
    Lua -> JS  : executeBrowserJavascript(browser, "RP.*(...)")
]]

local screenW, screenH = guiGetScreenSize()
local browserGui, browser, documentReady = nil, nil, false
local jsQueue = {}
local previewPed, previewRot = nil, 0

-- Escenario de la vista previa: el ped mira al norte y la camara lo enfoca
-- desplazada para que quede a la derecha de la pantalla (el panel va a la izquierda).
local SCENE = { x = 1742.9, y = -1861.6, z = 13.58 }

addEvent("rp:chars:show", true)
addEvent("rp:chars:result", true)
addEvent("rp:chars:spawned", true)
addEvent("rp:chars:ui:look", false)
addEvent("rp:chars:ui:camera", false)
addEvent("rp:chars:ui:rotate", false)
addEvent("rp:chars:ui:create", false)
addEvent("rp:chars:ui:play", false)
addEvent("rp:chars:ui:delete", false)

local function jsString(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", ""):gsub("<", "\\u003c")
    return "\"" .. s .. "\""
end

-- toJSON envuelve el valor en un array: "[ valor ]"
local function json(value)
    return toJSON(value, true) .. "[0]"
end

local function callJS(code)
    if isElement(browser) and documentReady then
        executeBrowserJavascript(browser, code)
    else
        jsQueue[#jsQueue + 1] = code
    end
end

----------------------------------------------------------------
-- Escena de vista previa
----------------------------------------------------------------
-- "body": cuerpo entero | "face": primer plano de la cabeza
local cameraMode = "body"
local function setPreviewCamera()
    local s = SCENE
    if cameraMode == "face" then
        setCameraMatrix(s.x, s.y + 1.25, s.z + 0.72, s.x + 0.32, s.y, s.z + 0.62, 0, 45)
    else
        setCameraMatrix(s.x, s.y + 3.4, s.z + 0.45, s.x + 1.0, s.y, s.z + 0.15, 0, 60)
    end
end

-- Apariencia de la vista previa: { skin, height } o { head, torso, legs, shoes, fat, muscle, height, tone }
local function setPreviewLook(look)
    if not isElement(previewPed) or type(look) ~= "table" then return end
    local head = applyCharacterLook(previewPed, look)
    if head then
        exports.rp_heads:applyHead(previewPed, head)
    else
        exports.rp_heads:removeHead(previewPed)
    end
    setPedBody(previewPed, look.height, head and tonumber(look.tone or look.skin_tone) or 0)   -- c_body.lua
end

-- Datos de apariencia para la interfaz
local function appearanceData()
    local heads = {}
    for race in pairs(exports.rp_heads:getRaces()) do
        heads[tostring(race)] = exports.rp_heads:getHeadsByRace(race)
    end
    local clothes = {}
    for _, slot in ipairs(CLOTHES_SLOTS) do
        clothes[slot.key] = getClothesCount(slot.type)
    end
    local tones = {}
    for i, tone in ipairs(BODY.TONES) do tones[i] = { name = tone.name, hex = tone.hex } end
    local toneByRace = {}
    for race, tone in pairs(BODY.TONE_BY_RACE) do toneByRace[tostring(race)] = tone end
    return {
        male = SKINS[0], female = SKINS[1], races = exports.rp_heads:getRaces(), heads = heads, clothes = clothes,
        tones = tones, toneByRace = toneByRace,
        body = { heightMin = BODY.HEIGHT_MIN, heightMax = BODY.HEIGHT_MAX, heightBase = BODY.HEIGHT_BASE,
                 fatMax = BODY.FAT_MAX, muscleMax = BODY.MUSCLE_MAX },
    }
end

local function createScene()
    if not isElement(previewPed) then
        previewPed = createPed(26, SCENE.x, SCENE.y, SCENE.z, 0)
        setElementFrozen(previewPed, true)
        previewRot = 0
    end
    setPreviewCamera()
end

local function destroyScene()
    if isElement(previewPed) then
        exports.rp_heads:removeHead(previewPed)
        removePedBody(previewPed)
        destroyElement(previewPed)
    end
    previewPed = nil
end

----------------------------------------------------------------
-- Navegador
----------------------------------------------------------------
local function openUI()
    if isElement(browserGui) then return end

    showChat(false)
    setPlayerHudComponentVisible("all", false)
    fadeCamera(true, 1)
    createScene()

    documentReady, jsQueue = false, {}
    browserGui = guiCreateBrowser(0, 0, screenW, screenH, true, true, false)
    browser = guiGetBrowser(browserGui)

    addEventHandler("onClientBrowserCreated", browser, function()
        loadBrowserURL(source, "http://mta/local/html/index.html")
    end)
    addEventHandler("onClientBrowserDocumentReady", browser, function()
        documentReady = true
        executeBrowserJavascript(source, ("RP.setAppearance(%s)"):format(json(appearanceData())))
        for _, code in ipairs(jsQueue) do executeBrowserJavascript(source, code) end
        jsQueue = {}
    end)

    showCursor(true)
    guiSetInputEnabled(true)
end

local function closeUI(restoreGame)
    if isElement(browserGui) then destroyElement(browserGui) end
    browserGui, browser, documentReady, jsQueue = nil, nil, false, {}
    destroyScene()
    showCursor(false)
    guiSetInputEnabled(false)
    if restoreGame then
        showChat(true)
        -- El HUD lo dibuja rp_hud; aqui solo se restaura el punto de mira de GTA
        setPlayerHudComponentVisible("crosshair", true)
    end
end

----------------------------------------------------------------
-- Servidor -> interfaz
----------------------------------------------------------------
addEventHandler("rp:chars:show", resourceRoot, function(characters, maxSlots)
    openUI()
    callJS(("RP.showSelect(%s, %d)"):format(json(characters or {}), tonumber(maxSlots) or 3))
end)

addEventHandler("rp:chars:result", resourceRoot, function(ok, message)
    callJS(("RP.onResult(%s, %s)"):format(ok and "true" or "false", jsString(message)))
    exports.rp_notify:notify(message, ok and "success" or "error")
end)

-- Avisos de validacion del formulario (JS) -> notificacion con sonido
addEvent("rp:chars:ui:notify", false)
addEventHandler("rp:chars:ui:notify", root, function(message, kind)
    if type(message) == "string" then exports.rp_notify:notify(message, kind == "error" and "error" or "info") end
end)

addEventHandler("rp:chars:spawned", resourceRoot, function()
    closeUI(true)
end)

----------------------------------------------------------------
-- Interfaz -> cliente / servidor
----------------------------------------------------------------
addEventHandler("rp:chars:ui:look", root, function(payload)
    setPreviewLook(type(payload) == "string" and fromJSON(payload))
end)

addEventHandler("rp:chars:ui:camera", root, function(mode)
    cameraMode = mode == "face" and "face" or "body"
    setPreviewCamera()
end)

addEventHandler("rp:chars:ui:rotate", root, function(delta)
    delta = tonumber(delta)
    if delta and isElement(previewPed) then
        previewRot = (previewRot + delta) % 360
        setElementRotation(previewPed, 0, 0, previewRot)
    end
end)

addEventHandler("rp:chars:ui:create", root, function(payload)
    local data = type(payload) == "string" and fromJSON(payload)
    if type(data) ~= "table" then return end
    triggerServerEvent("rp:chars:create", resourceRoot, {
        firstName = data.firstName, lastName = data.lastName,
        gender = tonumber(data.gender), age = tonumber(data.age), height = tonumber(data.height),
        fat = tonumber(data.fat), muscle = tonumber(data.muscle), tone = tonumber(data.tone),
        origin = data.origin, story = data.story, skin = tonumber(data.skin),
        race = tonumber(data.race), head = tonumber(data.head),
        torso = tonumber(data.torso), legs = tonumber(data.legs), shoes = tonumber(data.shoes),
    })
end)

addEventHandler("rp:chars:ui:play", root, function(id)
    id = tonumber(id)
    if id then triggerServerEvent("rp:chars:play", resourceRoot, id) end
end)

addEventHandler("rp:chars:ui:delete", root, function(id)
    id = tonumber(id)
    if id then triggerServerEvent("rp:chars:delete", resourceRoot, id) end
end)

----------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("rp:chars:clientReady", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeUI(false)
end)


-- Para otros recursos (panel de admin): viste un ped local con la apariencia de un personaje.
-- look = getCharacterLook(). Aplica skin/ropa, cabeza custom y altura/tono (shaders de c_body.lua).
-- Devuelve el id de cabeza o false.
function applyPedLook(ped, look)
    if not isElement(ped) or type(look) ~= "table" then return false end
    local head = applyCharacterLook(ped, look)
    if head then exports.rp_heads:applyHead(ped, head) else exports.rp_heads:removeHead(ped) end
    setPedBody(ped, look.height, head and tonumber(look.skin_tone) or 0)
    return head or false
end

function clearPedLook(ped)
    if not isElement(ped) then return end
    exports.rp_heads:removeHead(ped)
    removePedBody(ped)
end
