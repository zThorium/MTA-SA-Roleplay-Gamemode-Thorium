--[[
    rp_ids / s_ids.lua
    Asigna a cada jugador el ID libre mas bajo al entrar (se reutilizan al salir).
    El ID se publica como elementData "id" para que los clientes lo lean
    (scoreboard, nametags).

        exports.rp_ids:getPlayerId(player)      -> number | false
        exports.rp_ids:getPlayerFromId(id)      -> player | false
        exports.rp_ids:findPlayer("12" | "Juan") -> player | false
]]

local byId = {}   -- [id] = player

local function assign(player)
    local id = 1
    while byId[id] do id = id + 1 end
    byId[id] = player
    setElementData(player, "id", id)
    return id
end

addEventHandler("onPlayerJoin", root, function()
    assign(source)
end)

addEventHandler("onPlayerQuit", root, function()
    local id = getElementData(source, "id")
    if id and byId[id] == source then byId[id] = nil end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        assign(player)
    end
end)

function getPlayerId(player)
    local id = isElement(player) and getElementData(player, "id")
    return id and byId[id] == player and id or false
end

function getPlayerFromId(id)
    local player = byId[tonumber(id)]
    return isElement(player) and player or false
end

-- Busca por ID o por parte del nombre (sin distinguir mayusculas ni "_")
function findPlayer(query)
    if type(query) ~= "string" and type(query) ~= "number" then return false end
    local byNumber = getPlayerFromId(query)
    if byNumber then return byNumber end

    query = tostring(query):lower():gsub("_", " ")
    local found = false
    for _, player in ipairs(getElementsByType("player")) do
        local name = getPlayerName(player):lower():gsub("_", " ")
        if name:find(query, 1, true) then
            if found then return false end   -- ambiguo
            found = player
        end
    end
    return found
end

-- /id <nombre o ID>
addCommandHandler("id", function(player, _, query)
    if not query then
        outputChatBox("Tu ID es " .. tostring(getPlayerId(player)) .. ". Uso: /id <nombre o ID>", player, 200, 200, 200)
        return
    end
    local target = findPlayer(query)
    if target then
        outputChatBox(("%s - ID %d"):format((getPlayerName(target):gsub("_", " ")), getPlayerId(target)), player, 120, 200, 255)
    else
        outputChatBox("No se encontro un unico jugador con ese nombre o ID.", player, 255, 120, 120)
    end
end)
