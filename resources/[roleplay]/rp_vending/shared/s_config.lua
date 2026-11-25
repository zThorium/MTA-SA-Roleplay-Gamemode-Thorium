--[[
    rp_vending / s_config.lua  (compartido cliente/servidor)

    Tipos de expendedora: modelo que se coloca en el mundo y productos que vende.
    Cada producto es un item de rp_inventory (rp_inventory/shared/s_items.lua): se entrega
    al inventario y se consume desde ahi. Los precios los decide siempre el servidor.
]]

VENDING = {
    INTERACT_RADIUS = 1.6,    -- metros desde la maquina para pulsar E
    COOLDOWN_MS = 1200,       -- entre acciones del mismo jugador (lo aplica el servidor)
    CLOSE_AFTER_PAY_MS = 3000, -- tiempo para ver la boleta antes de cerrar

    -- Colocacion con /crearexpendedora: distancia delante del admin y altura sobre el suelo.
    -- Si el modelo queda enterrado o flotando, ajusta zOffset del tipo.
    -- rotOffset: giro extra del modelo (grados). La BD guarda hacia donde mira la maquina;
    -- el frente de 955/956 queda al reves, asi que se gira 180 al dibujarlo (arregla tambien las ya creadas).
    PLACE_DISTANCE = 1.1,

    TYPES = {
        drink = {
            label = "bebida", name = "Expendedora Sprunk", model = 955, zOffset = 0.4, rotOffset = 180,
            products = {
                { item = "soda_sprunk",  price = 3 },
                { item = "soda_ecola",   price = 3 },
                { item = "water",        price = 4 },
                { item = "energy_drink", price = 6 },
            },
        },
        food = {
            label = "comida", name = "Expendedora de snacks", model = 956, zOffset = 0.4, rotOffset = 180,
            products = {
                { item = "snack_chips",     price = 4 },
                { item = "snack_chocolate", price = 4 },
                { item = "snack_cookies",   price = 5 },
            },
        },
    },
}
