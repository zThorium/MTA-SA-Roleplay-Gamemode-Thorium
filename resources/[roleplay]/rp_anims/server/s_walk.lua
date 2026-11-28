--[[
    rp_anims / s_walk.lua

    Estilo de caminar del personaje, guardado en characters.walk_style.
    Comandos:
        /caminar            lista los estilos y muestra el actual
        /caminar <estilo>   cambia el estilo (alias /setcaminar)
]]

local style = {}     -- [player] = id de estilo del personaje activo
local cooldown = {}

local function db() return exports.rp_database:getConnection() end
local function notify(p, t, k) exports.rp_notify:notify(p, t, k) end

local function apply(p)
    if isElement(p) and style[p] then setPedWalkingStyle(p, style[p]) end
end

local function load(p, characterId)
    style[p] = nil
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not isElement(p) or exports.rp_characters:getPlayerCharacterId(p) ~= characterId then return end
        local id = rows and rows[1] and tonumber(rows[1].walk_style) or 0
        style[p] = isWalkStyle(id) and id or 0
        apply(p)
    end, db(), "SELECT walk_style FROM characters WHERE id = ?", characterId)
end

local function keyOf(id)
    for _, w in ipairs(WALK_STYLES) do
        if w[2] == id then return w[1] end
    end
    return "normal"
end

local function cmd(p, _, key)
    local characterId = exports.rp_characters:getPlayerCharacterId(p)
    if not characterId then return end
    if not key then
        local names = {}
        for _, w in ipairs(WALK_STYLES) do names[#names + 1] = w[1] end
        notify(p, ("Caminas: %s. Estilos: %s. Usa /caminar <estilo>."):format(keyOf(style[p] or 0), table.concat(names, ", ")), "info")
        return
    end
    local id = getWalkStyle(key)
    if not id then notify(p, "No existe ese estilo. Usa /caminar para ver la lista.", "error") return end
    local now = getTickCount()
    if cooldown[p] and now - cooldown[p] < 2000 then return end
    cooldown[p] = now
    style[p] = id
    apply(p)
    dbExec(db(), "UPDATE characters SET walk_style = ? WHERE id = ?", id, characterId)
    notify(p, "Ahora caminas: " .. keyOf(id) .. ".", "success")
end
addCommandHandler("caminar", cmd)
addCommandHandler("setcaminar", cmd)

addEventHandler("rp:onCharacterSpawn", root, function(characterId) load(source, characterId) end)
addEventHandler("rp:onCharacterLogout", root, function()
    style[source] = nil
    setPedWalkingStyle(source, 0)
end)
addEventHandler("onPlayerQuit", root, function() style[source], cooldown[source] = nil, nil end)
-- reaparecer (hospital) o cambiar de skin (ropa) puede dejar el estilo de serie
addEventHandler("onPlayerSpawn", root, function() apply(source) end)
addEventHandler("onElementModelChange", root, function()
    if getElementType(source) == "player" then
        local p = source
        setTimer(apply, 100, 1, p)   -- el evento salta antes de aplicar el modelo nuevo
    end
end)

local function loadAll()
    for _, p in ipairs(getElementsByType("player")) do
        local id = exports.rp_characters:getPlayerCharacterId(p)
        if id then load(p, id) end
    end
end
addEvent("rp:onDatabaseReady", false)
addEventHandler("onResourceStart", resourceRoot, function()
    if exports.rp_database:isReady() then loadAll() else addEventHandler("rp:onDatabaseReady", root, loadAll) end
end)
