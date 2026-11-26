--[[
    rp_restaurants / s_config.lua  (compartido cliente/servidor)

    Restaurantes de comida rapida de Los Santos con su interior original de GTA SA:
    Burger Shot (interior 10), Cluckin' Bell (interior 9) y Well Stacked Pizza (interior 5).
    Cada local usa su propia dimension (DIMENSION_BASE + id), asi que puedes anadir locales
    sin que se mezclen los jugadores ni los empleados.

    Se compra en el mostrador con E y se come alli mismo con la animacion original
    (bloque FOOD: EAT_Burger, EAT_Chicken, EAT_Pizza). Si ya estas lleno, vomitas como en SA.

    shortcut: las puertas exteriores, el punto de entrada y la posicion de los empleados salen de
    los enex y scripts conocidos de SA; si alguno queda desplazado, ajustarlo aqui tras probar en juego.
]]

RESTAURANTS = {
    DIMENSION_BASE = 25000,
    DOOR_DISTANCE = 1.8,       -- metros a la puerta (fuera o dentro) para pulsar E
    COUNTER_DISTANCE = 1.6,    -- metros al punto del mostrador para pedir
    COOLDOWN_MS = 1500,
    FULL_AT = 90,              -- con hambre >= esto, comer otra vez te hace vomitar (como en SA)
    VOMIT_MS = 6500,

    -- Marcas: interior, puntos interiores, empleado y menu (nombres originales del juego)
    -- anim = animacion de comer del bloque FOOD; prop = objeto en la mano derecha mientras come.
    -- hunger/thirst = puntos que recupera (rp_needs, 0-100); health = vida que suma.
    BRANDS = {
        burger = {
            name = "Burger Shot", color = { 227, 120, 40 }, icon = "food", blip = 10,
            interior = 10,
            entry   = { x = 363.11, y = -74.88, z = 1001.51, rot = 315 },
            clerk   = { x = 376.50, y = -65.85, z = 1001.51, rot = 180, skin = 205 },
            counter = { x = 376.50, y = -67.45, z = 1001.51, rot = 0 },
            anim = "EAT_Burger", animMs = 4600, prop = { model = 2703, x = 0.05, y = 0.04, z = 0.02, rx = 0, ry = -90, rz = 0 },
            menu = {
                { name = "Moo Kids Meal",  desc = "Hamburguesa chica, papas y bebida", price = 8,  hunger = 20, thirst = 10, health = 5 },
                { name = "Beef Tower",     desc = "Doble carne con queso, papas y bebida", price = 15, hunger = 40, thirst = 15, health = 10 },
                { name = "Meat Stack",     desc = "Torre de carne, papas grandes y bebida", price = 25, hunger = 70, thirst = 20, health = 15 },
                { name = "Salad Meal",     desc = "Ensalada fresca con agua", price = 18, hunger = 30, thirst = 25, health = 20 },
            },
        },
        chicken = {
            name = "Cluckin' Bell", color = { 235, 190, 40 }, icon = "food", blip = 14,
            interior = 9,
            entry   = { x = 364.98, y = -11.39, z = 1001.85, rot = 0 },
            clerk   = { x = 368.11, y = -4.49,  z = 1001.85, rot = 180, skin = 167 },
            counter = { x = 368.11, y = -6.10,  z = 1001.85, rot = 0 },
            anim = "EAT_Chicken", animMs = 4600, prop = { model = 2703, x = 0.05, y = 0.04, z = 0.02, rx = 0, ry = -90, rz = 0 },
            menu = {
                { name = "Cluckin' Little Meal", desc = "Nuggets, papas y bebida", price = 8,  hunger = 20, thirst = 10, health = 5 },
                { name = "Cluckin' Big Meal",    desc = "Pollo frito, papas y bebida", price = 15, hunger = 40, thirst = 15, health = 10 },
                { name = "Cluckin' Huge Meal",   desc = "Cubeta de pollo, papas grandes y bebida", price = 25, hunger = 70, thirst = 20, health = 15 },
                { name = "Salad Meal",           desc = "Ensalada de pollo con agua", price = 18, hunger = 30, thirst = 25, health = 20 },
            },
        },
        pizza = {
            name = "Well Stacked Pizza", color = { 200, 60, 50 }, icon = "food", blip = 29,
            interior = 5,
            entry   = { x = 372.35, y = -133.55, z = 1001.49, rot = 0 },
            clerk   = { x = 374.76, y = -117.26, z = 1001.49, rot = 180, skin = 155 },
            counter = { x = 374.76, y = -118.90, z = 1001.49, rot = 0 },
            anim = "EAT_Pizza", animMs = 4600, prop = { model = 2702, x = 0.05, y = 0.04, z = 0.02, rx = 0, ry = -90, rz = 0 },
            menu = {
                { name = "Buster",        desc = "Porcion de pizza y bebida", price = 8,  hunger = 20, thirst = 10, health = 5 },
                { name = "Double D-Luxe", desc = "Dos porciones, palitos de ajo y bebida", price = 15, hunger = 40, thirst = 15, health = 10 },
                { name = "Full Rack",     desc = "Pizza familiar entera y bebida", price = 25, hunger = 70, thirst = 20, health = 15 },
                { name = "Salad Meal",    desc = "Ensalada italiana con agua", price = 18, hunger = 30, thirst = 25, health = 20 },
            },
        },
    },

    -- Locales de Los Santos (puerta exterior). id unico: decide la dimension.
    LOCATIONS = {
        { id = 1, brand = "burger",  name = "Burger Shot Marina",         x = 810.48,  y = -1616.18, z = 13.55 },
        { id = 2, brand = "burger",  name = "Burger Shot Temple",         x = 1199.26, y = -918.14,  z = 43.12 },
        { id = 3, brand = "chicken", name = "Cluckin' Bell Market",       x = 928.92,  y = -1352.92, z = 13.34 },
        { id = 4, brand = "chicken", name = "Cluckin' Bell Willowfield",  x = 2397.83, y = -1898.64, z = 13.55 },
        { id = 5, brand = "chicken", name = "Cluckin' Bell East LS",      x = 2419.73, y = -1509.03, z = 24.00 },
        { id = 6, brand = "pizza",   name = "Well Stacked Pizza Idlewood", x = 2105.49, y = -1806.50, z = 13.55 },
    },
}

function restaurantDimension(loc) return RESTAURANTS.DIMENSION_BASE + loc.id end

function getRestaurantLocation(id)
    for _, loc in ipairs(RESTAURANTS.LOCATIONS) do
        if loc.id == id then return loc end
    end
end
