--[[
    rp_vending / s_config.lua  (compartido cliente/servidor)

    Tipos de expendedora: modelo que se coloca en el mundo y productos que vende.
    Cada producto es un item de rp_inventory (rp_inventory/shared/s_items.lua): se entrega
    al inventario y se consume desde ahi. Los precios los decide siempre el servidor.

    Vitrina (html/vending.*): COLUMNS espirales por estante. Cada producto ocupa "slots"
    espirales seguidas; el codigo de cada espiral es fila*10 + columna (11, 12, 13, 21...).
    Aspecto del producto dibujado en CSS: look = "can" | "bottle" | "bag" | "bar",
    color (hex) y tag (texto corto de la etiqueta).
]]

VENDING = {
    INTERACT_RADIUS = 1.6,     -- metros desde la maquina para pulsar E
    COOLDOWN_MS = 1200,        -- entre acciones del mismo jugador (lo aplica el servidor)
    TAKE_TIMEOUT_MS = 12000,   -- tras pagar, se cierra solo si no recoges el producto de la bandeja
    COLUMNS = 3,               -- espirales por estante en la vitrina
    NEARBY_RADIUS = 50,        -- radio por defecto de /nearbyexpendedoras (m)
    DELETE_NEAR_RADIUS = 5,    -- /borrarexpendedora sin id borra la mas cercana dentro de este radio (m)

    -- Colocacion con /crearexpendedora: distancia delante del admin y altura sobre el suelo.
    -- Si el modelo queda enterrado o flotando, ajusta zOffset del tipo.
    -- rotOffset: giro extra del modelo (grados). La BD guarda hacia donde mira la maquina;
    -- el frente de 955/956 queda al reves, asi que se gira 180 al dibujarlo (arregla tambien las ya creadas).
    PLACE_DISTANCE = 1.1,

    TYPES = {
        drink = {
            label = "bebida", name = "Expendedora Sprunk", brand = "Sprunk", model = 955, zOffset = 0.4, rotOffset = 180,
            products = {
                { item = "soda_sprunk",  price = 3, slots = 3, look = "can",    color = "#2f9e44", tag = "SPRUNK" },
                { item = "soda_ecola",   price = 3, slots = 3, look = "can",    color = "#c92a2a", tag = "eCOLA" },
                { item = "water",        price = 4, slots = 3, look = "bottle", color = "#4dabf7", tag = "AGUA" },
                { item = "energy_drink", price = 6, slots = 3, look = "can",    color = "#1c1c1c", tag = "VOLT" },
            },
        },
        food = {
            label = "comida", name = "Expendedora de snacks", brand = "Snacks", model = 956, zOffset = 0.4, rotOffset = 180,
            products = {
                { item = "snack_chips",     price = 4, slots = 4, look = "bag", color = "#f08c00", tag = "PAPAS" },
                { item = "snack_chocolate", price = 4, slots = 4, look = "bar", color = "#6f3b1d", tag = "CHOCO" },
                { item = "snack_cookies",   price = 5, slots = 4, look = "bag", color = "#c2a26b", tag = "GALLETAS" },
            },
        },
    },
}
