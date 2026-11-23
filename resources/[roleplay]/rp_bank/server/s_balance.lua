--[[
    rp_bank / s_balance.lua
    Publica el saldo bancario en el elementData "rp:bankMoney" (solo lo ve su dueno)
    para que el HUD lo muestre. Muchos recursos modifican bank_money directamente,
    asi que se refresca con UNA consulta cada pocos segundos para todos los conectados.
]]

local REFRESH_MS = 4000

local function refresh()
    local byId, ids = {}, {}
    for _, player in ipairs(getElementsByType("player")) do
        local id = exports.rp_characters:getPlayerCharacterId(player)
        if id then
            byId[id] = player
            ids[#ids + 1] = id
        end
    end
    if #ids == 0 then return end
    local marks = string.rep("?,", #ids):sub(1, -2)
    dbQuery(function(qh)
        local rows = dbPoll(qh, 0)
        if not rows then return end
        for _, row in ipairs(rows) do
            local player = byId[tonumber(row.id)]
            if isElement(player) then
                local balance = tonumber(row.bank_money) or 0
                if getElementData(player, "rp:bankMoney") ~= balance then
                    setElementData(player, "rp:bankMoney", balance)
                end
            end
        end
    end, exports.rp_database:getConnection(), "SELECT id, bank_money FROM characters WHERE id IN (" .. marks .. ")", unpack(ids))
end

addEvent("rp:onCharacterSpawn", false)
setTimer(refresh, REFRESH_MS, 0)
addEventHandler("rp:onCharacterSpawn", root, function() setTimer(refresh, 1000, 1) end)
