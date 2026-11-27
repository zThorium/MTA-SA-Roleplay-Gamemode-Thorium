--[[
    rp_metaldetector / server/s_config.lua  (solo servidor)

    Probabilidades del botín y límites antifraude. El cliente no ve esto.
    weight = peso relativo (admite decimales; no hace falta que sumen 100); amount = { mín, máx } unidades.
    Cada item debe estar en METALDETECTOR.FINDS (shared) para tener rareza, lectura, profundidad e imagen.
    El detector decide qué se puede encontrar: solo lo que está a su alcance de profundidad
    (metalDetectorStats(tier).maxDepth) y con más peso para lo raro cuanto mejor es.
]]

METALDETECTOR_LOOT = {
    { item = "rusty_can",     weight = 22,  amount = { 1, 2 } },
    { item = "scrap_metal",   weight = 20,  amount = { 1, 3 } },
    { item = "rusty_key",     weight = 12,  amount = { 1, 1 } },
    { item = "lost_keys",     weight = 10,  amount = { 1, 1 } },
    { item = "old_coin",      weight = 10,  amount = { 1, 3 } },
    { item = "old_compass",   weight = 7,   amount = { 1, 1 } },
    { item = "old_watch",     weight = 7,   amount = { 1, 1 } },
    { item = "gold_earrings", weight = 5,   amount = { 1, 1 } },
    { item = "gold_ring",     weight = 3.5, amount = { 1, 1 } },
    { item = "gold_chain",    weight = 3,   amount = { 1, 1 } },
    { item = "doubloon",      weight = 1.2, amount = { 1, 2 } },
    { item = "jeweled_tiara", weight = 0.5, amount = { 1, 1 } },
}

METALDETECTOR_LIMITS = {
    MAX_FINDS_PER_HOUR = 40,      -- por personaje
    PROPOSE_COOLDOWN_MS = 1500,   -- entre dos propuestas de punto del cliente
    MAX_Z_DIFF = 12,              -- diferencia de altura máxima entre el jugador y el punto
    DEPTH_NOISE = 4,              -- ± cm de error de la profundidad mostrada
    BUY_COOLDOWN_MS = 1500,
}

-- Sorteo ponderado con el detector usado (índice 1..5). Devuelve itemId, cantidad.
-- rnd01/rndInt opcionales (pruebas): function() -> [0,1), function(a,b) -> entero.
function pickMetalDetectorLoot(tierIndex, rnd01, rndInt)
    rnd01, rndInt = rnd01 or math.random, rndInt or math.random
    local stats = metalDetectorStats(tierIndex or 1)
    local pool, total = {}, 0
    for _, e in ipairs(METALDETECTOR_LOOT) do
        local find = METALDETECTOR_FIND_BY_ITEM[e.item]
        if find and find.depth <= stats.maxDepth then
            local rarity = METALDETECTOR.RARITIES[find.rarity]
            local w = e.weight * ((rarity and rarity.order >= 3) and stats.rareBonus or 1)
            pool[#pool + 1] = { e = e, w = w }
            total = total + w
        end
    end
    local roll = rnd01() * total
    for _, p in ipairs(pool) do
        roll = roll - p.w
        if roll < 0 then return p.e.item, rndInt(p.e.amount[1], p.e.amount[2]) end
    end
    local last = pool[#pool].e
    return last.item, last.amount[1]
end
