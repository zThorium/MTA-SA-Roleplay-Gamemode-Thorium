--[[
    rp_achievements / s_listeners.lua  (servidor)

    Hechos que otros recursos ya anuncian con un evento propio: se escuchan aquí y se
    convierten en estadísticas sin tocar el recurso de origen. Lo que no tiene evento lo
    avisa el propio recurso con triggerEvent("rp:achievements:progress", ...) (docs/LOGROS.md).
]]

addEvent("rp:jobs:onShiftEnd", false)
addEvent("rp:jobs:onMarketSale", false)
addEvent("rp:shop:onBought", false)
addEvent("rp:onPlayerDowned", false)

-- Turno terminado (cualquier trabajo de rp_jobs, también los externos como la pizzería)
addEventHandler("rp:jobs:onShiftEnd", root, function(_, earned, tasks)
    if (tonumber(tasks) or 0) >= 1 then progress(source, "jobs_shifts", 1) end
    earned = tonumber(earned) or 0
    if earned > 0 then progress(source, "jobs_earned", earned) end
end)

-- Venta en un mercado de rp_jobs (pescado, minerales, hallazgos de playa...)
addEventHandler("rp:jobs:onMarketSale", root, function(_, _, _, total)
    if (tonumber(total) or 0) > 0 then progress(source, "market_sales", 1) end
end)

-- Compra en una tienda (rp_shops y tiendas temporales, como la de los traficantes)
addEventHandler("rp:shop:onBought", root, function(_, itemId, quantity)
    local def = type(itemId) == "string" and exports.rp_inventory:getItemDefinition(itemId)
    if def and def.use and def.use.drug then progress(source, "drugs_bought", tonumber(quantity) or 1) end
end)

-- Quedar abatido (logro secreto «Superviviente»)
addEventHandler("rp:onPlayerDowned", root, function()
    progress(source, "times_downed", 1)
end)
