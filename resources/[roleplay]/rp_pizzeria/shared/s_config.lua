--[[
    rp_pizzeria / s_config.lua  (compartido cliente/servidor)

    Trabajo de pizzero en la Well Stacked Pizza de Idlewood (interior 5).
    El puesto, los niveles, la XP y los pagos los lleva rp_jobs (trabajo externo "pizza").

    Cada turno es una instancia: el jugador pasa a su propia dimension (DIM_BASE + slot) dentro
    del mismo interior, y los clientes (peds de cliente) solo los ve el. Las posiciones del
    mobiliario salen del IPL original del juego (gen_int5_stream2.ipl en gta_int.img):
    mostrador y cajas en y = -117.97, hornos CJ_FF_PIZZA_OVEN en x = 376.72 / 378.68,
    freidora en 374.95, cocina en 373.90, mesas CJ_PIZZA_TABLE en x = 373.97 con sillas a ambos lados.

    Flujo de un pedido: caja (tomar pedido) -> mesa de armado (masa, salsa, queso, ingredientes)
    -> horno (sacar a tiempo) -> mesa de corte (cortar y empacar) -> [freidora si lleva guarnicion]
    -> entregas (el cliente recoge, reacciona y se va a comer a una mesa).
]]

PIZZERIA = {
    JOB_ID = "pizza",
    INTERIOR = 5,
    DIM_BASE = 26000,            -- 26001..26500: una por turno
    DIM_COUNT = 500,

    -- Marcador de contratacion (comedor del local de Idlewood de rp_restaurants: dimension 25000 + 6)
    HIRE = { x = 369.08, y = -119.16, z = 1001.49, dimension = 25006, radius = 1.3 },
    -- Donde apareces al empezar el turno (detras del mostrador) y donde vuelves al terminar
    START = { x = 375.6, y = -116.3, z = 1001.49, rot = 180 },
    -- Dentro de la instancia, el mismo punto del comedor sirve para terminar el turno
    LEAVE = { x = 369.08, y = -119.16, z = 1001.49, radius = 1.2 },

    STATION_RADIUS = 1.0,        -- metros: gana la estacion mas cercana dentro de este radio
    STATION_SLACK = 0.8,         -- margen extra que tolera el servidor

    -- Estaciones (punto donde se para el jugador). kind decide que hace E.
    -- obj = { modelo, x, y, z, rz } del mueble real (IPL del juego): el tutorial lo resalta al llegar.
    STATIONS = {
        { id = "order",    kind = "order",    label = "Caja: tomar pedidos", x = 374.90, y = -117.20, z = 1001.49, rot = 180, obj = { 2422, 374.977, -117.875, 1001.539, 0 } },
        { id = "pickup",   kind = "pickup",   label = "Entregas",            x = 372.95, y = -117.20, z = 1001.49, rot = 180, obj = { 2422, 372.984, -117.875, 1001.539, 0 } },
        { id = "assembly", kind = "assembly", label = "Mesa de armado",      x = 379.14, y = -114.47, z = 1001.49, rot = 268, obj = { 2418, 379.977, -113.883, 1000.508, 90 } },
        { id = "oven1",    kind = "oven", slot = 1, label = "Horno 1",       x = 376.72, y = -113.55, z = 1001.49, rot = 0, obj = { 2426, 376.719, -112.477, 1001.453, 0 } },
        { id = "oven2",    kind = "oven", slot = 2, label = "Horno 2",       x = 378.50, y = -113.55, z = 1001.49, rot = 0, obj = { 2426, 378.680, -112.477, 1001.453, 0 } },
        { id = "fryer",    kind = "fryer",    label = "Freidora",            x = 374.96, y = -113.62, z = 1001.49, rot = 0, obj = { 2415, 374.945, -112.914, 1000.508, 0 } },
        { id = "pantry",   kind = "pantry",   label = "Despensa",            x = 373.89, y = -113.52, z = 1001.49, rot = 0, obj = { 2417, 373.898, -112.680, 1000.508, 0 } },
        { id = "cut",      kind = "cut",      label = "Corte y empaque",     x = 372.51, y = -113.75, z = 1001.49, rot = 0, obj = { 2451, 371.984, -112.891, 1000.492, 0 } },
    },

    -- Tiempos (ms)
    -- Musica de fondo del turno: html/sounds/musica_fondo.mp3 en bucle (acelera cuando un cliente esta por irse). 0 = sin musica.
    MUSIC_VOLUME = 0.18,
    BAKE_MS = 22000,             -- punto "normal" del horno
    BAKE = { poco = 0.8, normal = 1.0, bien = 1.25 },    -- multiplicador de BAKE_MS segun lo pedido
    BURN_AT = 1.7,               -- veces el objetivo: se quema (nota 0)
    FRY_MS = 9000,               -- punto de la guarnicion
    FRY_BURN_AT = 1.9,
    WALK_SPEED = 1.25,           -- m/s de los clientes (ritmo de la animacion WALK_civi)
    -- ARRIVE_MS (lo que tarda un cliente en llegar a la caja) se calcula abajo con el camino real
    -- El cliente avisa cuando su ped llega a la caja; el servidor lo acepta desde esta fraccion de ARRIVE_MS
    -- (y si nunca avisa, ARRIVE_MS sirve de respaldo).
    MIN_ARRIVE_FRACTION = 0.4,
    FIRST_CUSTOMER_MS = 5000,
    TUTORIAL_PATIENCE_MS = 15 * 60000,   -- el cliente del tutorial no se va
    AFTER_TUTORIAL_MS = 12000,           -- primer cliente normal tras terminar el tutorial
    SPAWN_MS = { 30000, 46000 }, -- intervalo entre clientes (se acorta con el nivel y la racha)
    PATIENCE_MS = 150000,        -- base; +20 s por ingrediente distinto, +25 s si lleva guarnicion
    EAT_MS = { 30000, 55000 },   -- cuanto se queda comiendo en la mesa

    -- Anti-abuso: tiempos minimos de cada panel desde que el servidor lo abre
    MIN_ASSEMBLY_MS = 2500, MIN_PER_PIECE_MS = 200,
    MIN_CUT_MS = 1200,
    GUIDES_UP_TO_LEVEL = 2,      -- hasta este nivel (y en el tutorial) armado y corte van guiados paso a paso
    RESTOCK_COOLDOWN_MS = 1500,
    MAX_PIECES = 40,

    -- Ingredientes. stock = maximo en la despensa; restock = cuanto repone cada caja.
    BASE = {
        dough  = { name = "Masa",  stock = 8,  restock = 4 },
        sauce  = { name = "Salsa", stock = 10, restock = 5 },
        cheese = { name = "Queso", stock = 10, restock = 5 },
    },
    -- level = nivel de pizzero (rp_jobs) desde el que aparece en los pedidos
    TOPPINGS = {
        { id = "pepperoni", name = "Pepperoni",   level = 1, stock = 36, restock = 18 },
        { id = "mushroom",  name = "Champiñones", level = 1, stock = 36, restock = 18 },
        { id = "olive",     name = "Aceitunas",   level = 1, stock = 36, restock = 18 },
        { id = "pepper",    name = "Pimentón",    level = 2, stock = 36, restock = 18 },
        { id = "onion",     name = "Cebolla",     level = 2, stock = 36, restock = 18 },
        { id = "ham",       name = "Jamón",       level = 3, stock = 36, restock = 18 },
        { id = "pineapple", name = "Piña",        level = 3, stock = 36, restock = 18 },
        { id = "sausage",   name = "Salchicha",   level = 4, stock = 36, restock = 18 },
    },
    SIDES = {
        fries  = { name = "Papas fritas" },
        garlic = { name = "Palitos de ajo" },
    },
    COUNTS = { 4, 6, 8 },        -- piezas por ingrediente que puede pedir un cliente
    SLICES = { 4, 6, 8 },

    -- Dificultad por nivel (indice = nivel 1..5)
    DIFFICULTY = {
        { maxActive = 2, types = { 1, 2 }, halfChance = 0,    sideChance = 0,    bakeVariants = false },
        { maxActive = 3, types = { 1, 2 }, halfChance = 0.25, sideChance = 0.3,  bakeVariants = false },
        { maxActive = 3, types = { 1, 3 }, halfChance = 0.4,  sideChance = 0.4,  bakeVariants = true },
        { maxActive = 4, types = { 2, 3 }, halfChance = 0.5,  sideChance = 0.5,  bakeVariants = true },
        { maxActive = 5, types = { 2, 3 }, halfChance = 0.6,  sideChance = 0.55, bakeVariants = true },
    },

    -- Pago (antes del bonus de nivel de rp_jobs)
    PAY_BASE = 40, PAY_PER_TYPE = 6, PAY_SIDE = 10,
    TIP_FROM = 70,               -- nota desde la que hay propina
    TIP_MAX = 0.8,               -- propina maxima = 80% del pago base (con nota 100)
    STREAK_TIP = 0.1,            -- +10% de propina por cada entrega buena seguida (max 5)
    STREAK_GOOD = 80,

    -- Clientes (peds de cliente). Puerta, cola, espera, recogida y mesas.
    SKINS = { 7, 12, 13, 14, 15, 19, 20, 22, 23, 26, 40, 41, 44, 46, 55, 56, 59, 69, 72, 91, 93, 98, 101, 141, 148, 150, 170, 185, 188, 192, 211, 216, 226, 233, 250, 261 },
    NAMES = { "Rosa", "Kevin", "Tamara", "Luis", "Marta", "Darnell", "Lupe", "Tony", "Keisha", "Ramón", "Jenny", "Marcus", "Inés", "Big Al", "Carla", "Dwayne", "Paco", "Shawna", "Iván", "Brenda", "Cesar", "Lola", "Tyrone", "Nadia" },
    DOOR = { x = 372.40, y = -132.90, z = 1001.49 },
    ENTRY_PATH = { { x = 376.90, y = -131.50 }, { x = 376.90, y = -121.80 } },
    QUEUE = {                    -- [1] = frente a la caja
        { x = 374.95, y = -118.85 }, { x = 376.00, y = -119.70 }, { x = 376.90, y = -120.70 },
        { x = 376.90, y = -121.80 }, { x = 376.90, y = -122.90 }, { x = 376.90, y = -124.00 },
    },
    WAIT = {                     -- esperando su pizza tras pedir
        { x = 378.40, y = -119.00 }, { x = 379.50, y = -119.10 }, { x = 380.60, y = -119.20 },
        { x = 378.90, y = -120.10 }, { x = 380.10, y = -120.20 },
    },
    PICKUP = { x = 372.98, y = -118.85 },   -- y = linea del mostrador del lado de los clientes; x = donde estes tu al entregar
    -- Mostrador (lado del personal): con la caja en la mano, E en cualquier punto entrega la pizza
    COUNTER = { x1 = 372.4, x2 = 381.2, y1 = -117.75, y2 = -116.3 },
    -- Sillas CJ_PIZZA_CHAIR del IPL. side: "w" = lado oeste de la mesa (mira al este), "e" = al reves.
    SEAT_X = { w = 372.945, e = 374.961 },
    SEAT_ROT = { w = 270, e = 90 },
    AISLE_X = { w = 371.60, e = 376.30 },
    SEAT_Y = { -122.063, -123.148, -125.680, -126.773, -129.031, -130.125 },
    SEAT_Z = 1001.49,
    TABLE_X = 373.969, PLATE_Z = 1001.47,
}

-- Ingredientes por id (cliente y servidor)
PIZZERIA.TOPPING_BY_ID = {}
for _, t in ipairs(PIZZERIA.TOPPINGS) do PIZZERIA.TOPPING_BY_ID[t.id] = t end

PIZZERIA.STATION_BY_ID = {}
for _, s in ipairs(PIZZERIA.STATIONS) do PIZZERIA.STATION_BY_ID[s.id] = s end

-- Todas las sillas como lista { x, y, rot, side, ax (pasillo) }
PIZZERIA.SEATS = {}
for _, y in ipairs(PIZZERIA.SEAT_Y) do
    for _, side in ipairs({ "w", "e" }) do
        PIZZERIA.SEATS[#PIZZERIA.SEATS + 1] = {
            x = PIZZERIA.SEAT_X[side], y = y, rot = PIZZERIA.SEAT_ROT[side], side = side, ax = PIZZERIA.AISLE_X[side],
        }
    end
end

-- Tiempo de la puerta a la caja siguiendo el camino real, a WALK_SPEED, con un pequeno margen
do
    local C, len = PIZZERIA, 0
    local pts = { C.DOOR }
    for _, p in ipairs(C.ENTRY_PATH) do pts[#pts + 1] = p end
    pts[#pts + 1] = C.QUEUE[1]
    for i = 2, #pts do
        len = len + math.sqrt((pts[i].x - pts[i - 1].x) ^ 2 + (pts[i].y - pts[i - 1].y) ^ 2)
    end
    C.ARRIVE_MS = math.floor(len / C.WALK_SPEED * 1000) + 800
end
