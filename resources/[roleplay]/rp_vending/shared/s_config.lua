--[[
    rp_vending / s_config.lua  (compartido cliente/servidor)

    Tipos de expendedora. "need" es la barra de rp_needs que sube ("thirst" = sed, "hunger" = hambre).
]]

VENDING = {
    INTERACT_RADIUS = 1.6,   -- metros para pulsar E
    COOLDOWN_MS = 1500,      -- entre compras del mismo jugador (lo aplica el servidor)

    TYPES = {
        drink = { label = "bebida", name = "Expendedora de bebidas", need = "thirst", price = 3, amount = 30, product = "una lata de refresco" },
        food  = { label = "comida", name = "Expendedora de comida",  need = "hunger", price = 5, amount = 25, product = "un snack" },
    },
}
