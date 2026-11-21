--[[
    rp_jobs / s_config.lua  (compartido cliente/servidor)

    Catálogo de trabajos, sedes, puntos de venta y ajustes. Las coordenadas Z son
    aproximadas: el cliente ajusta marcadores y objetos al suelo real (getGroundPosition)
    cuando el punto está cargado, y el servidor compara distancias con margen.
    Si mueves una sede, cambia aquí sus coordenadas y reinicia el recurso.

    Los textos los lee también la agencia de trabajos (rp_agency) con getJobList().
]]

JOBS_CONFIG = {
    -- true: en la sede de cada trabajo se puede pedir el puesto sin pasar por la agencia.
    -- Ponlo en false cuando la agencia de trabajos (rp_agency) esté en el servidor.
    HIRE_AT_HQ = true,
    -- Minutos que hay que esperar para volver a cambiar de trabajo
    CHANGE_COOLDOWN_MIN = 10,
    -- Niveles: XP necesaria para cada nivel (índice = nivel)
    LEVEL_XP = { 0, 120, 320, 650, 1100 },
    -- Bonus de pago por nivel por encima del 1 (0.08 = +8% por nivel)
    LEVEL_PAY_BONUS = 0.08,
    -- Si el vehículo del trabajo queda solo este tiempo, el turno termina
    ABANDON_VEHICLE_MS = 4 * 60 * 1000,
    -- Distancia extra que tolera el servidor sobre el radio de cada punto
    REACH_SLACK = 4,
    -- Dinero máximo que puede dar una sola tarea (seguridad)
    MAX_TASK_PAY = 2500,
}

-- Colores por trabajo (marcadores, blips y acentos de la interfaz)
--  hq        sede: marcador donde se empieza/termina el turno y (si HIRE_AT_HQ) se pide el puesto
--  vehicle   vehículo que se entrega al empezar (modelo + posición de salida)
--  cinematic planos para el botón "Más información" de la agencia (playJobCinematic)
JOBS = {
    {
        id = "garbage", name = "Recolector de basura", icon = "🗑️", color = { 120, 200, 90 },
        description = "Recorre una ruta por Los Santos con el camión de basura: recoge las bolsas de cada parada, cárgalas y ordénalas dentro del compactador. Entre la basura a veces aparecen cosas de valor.",
        pay = "$60-120 por parada + bono de ruta. Lo que encuentres es tuyo.",
        howTo = "Planta de residuos de Willowfield, al sureste de Los Santos.",
        locationName = "Planta de residuos, Willowfield",
        requirements = "Licencia de conducir recomendada.",
        hq = { x = 2190.0, y = -1977.0, z = 13.55, interior = 0, dimension = 0 },
        vehicle = { model = 408, x = 2180.0, y = -1990.0, z = 13.6, rz = 0 },
        cinematic = {
            { cam = { 2235, -1930, 45 }, look = { 2190, -1977, 13 }, ms = 4500, text = "La planta de residuos está en Willowfield. Aquí empiezas y terminas tu ruta." },
            { cam = { 2470, -1650, 30 }, look = { 2440, -1690, 13 }, ms = 4500, text = "Conduces el camión por los barrios y recoges las bolsas de cada parada." },
            { cam = { 2150, -1990, 22 }, look = { 2180, -1990, 13 }, ms = 4500, text = "Dentro del camión ordenas la basura: recicla, evita las jeringas y busca objetos de valor." },
        },
    },
    {
        id = "farmer", name = "Granjero", icon = "🌾", color = { 230, 190, 60 },
        description = "Ara el campo con el tractor, siembra a mano, cuida el cultivo de plagas, sequía o malas hierbas y cosecha con la cosechadora. Cada temporada es distinta.",
        pay = "$250-500 por cosecha según la calidad.",
        howTo = "Granja de Blueberry Acres, en Red County, al norte de Los Santos.",
        locationName = "Granja de Blueberry Acres",
        requirements = nil,
        hq = { x = -58.0, y = 45.0, z = 3.1, interior = 0, dimension = 0 },
        vehicle = { model = 531, x = -72.0, y = 30.0, z = 3.1, rz = 160 },
        cinematic = {
            { cam = { -10, 90, 30 }, look = { -58, 45, 3 }, ms = 4500, text = "La granja está en Blueberry Acres, en Red County." },
            { cam = { -170, 70, 25 }, look = { -140, 20, 3 }, ms = 4500, text = "Aras con el tractor, siembras a mano y cuidas el cultivo de lo que salga esa temporada." },
            { cam = { -100, -30, 20 }, look = { -140, 20, 3 }, ms = 4500, text = "Al final cosechas con la cosechadora y llevas el grano al silo." },
        },
    },
    {
        id = "lumber", name = "Leñador", icon = "🪓", color = { 170, 120, 70 },
        description = "Elige hacia dónde cae cada árbol, tálalo a golpe de hacha, carga los troncos en el camión y llévalos al aserradero, donde tú mismo los cortas en tablas.",
        pay = "$45-90 por tronco según el corte y la calidad de las tablas.",
        howTo = "Aserradero de Angel Pine, en el bosque de Shady Creeks, al suroeste del mapa.",
        locationName = "Aserradero de Angel Pine",
        requirements = "Licencia de conducir recomendada.",
        hq = { x = -1990.0, y = -2390.0, z = 30.6, interior = 0, dimension = 0 },
        vehicle = { model = 455, x = -1975.0, y = -2405.0, z = 30.7, rz = 140 },
        cinematic = {
            { cam = { -1950, -2350, 55 }, look = { -1990, -2390, 30 }, ms = 4500, text = "El aserradero está en Angel Pine. Aquí recoges el camión y entregas los troncos." },
            { cam = { -1640, -2140, 80 }, look = { -1680, -2200, 45 }, ms = 4500, text = "En el bosque de Shady Creeks talas los árboles que te marque el capataz." },
            { cam = { -1985, -2370, 40 }, look = { -1990, -2390, 30 }, ms = 4000, text = "En la sierra cortas los troncos en tablas: cuanto más preciso, más cobras." },
        },
    },
    {
        id = "hunter", name = "Cazador", icon = "🦌", color = { 200, 140, 80 },
        description = "Sigue rastros por los bosques de Flint County, distingue las huellas frescas, apunta con la mira teniendo en cuenta el viento y prepara la pieza. Carne y pieles se venden en la peletería.",
        pay = "Según la pieza: $80-600. Los precios del mercado cambian.",
        howTo = "Cabaña de caza de Leafy Hollow, en Flint County.",
        locationName = "Cabaña de caza, Leafy Hollow",
        requirements = nil,
        hq = { x = -1060.0, y = -1620.0, z = 76.4, interior = 0, dimension = 0 },
        vehicle = { model = 471, x = -1070.0, y = -1630.0, z = 76.4, rz = 90 },
        cinematic = {
            { cam = { -1020, -1580, 100 }, look = { -1060, -1620, 76 }, ms = 4500, text = "La cabaña de caza está en Leafy Hollow, Flint County. Te dan un quad para moverte." },
            { cam = { -850, -1450, 120 }, look = { -900, -1500, 70 }, ms = 4500, text = "Sigues rastros por el bosque. Si tardas, las huellas se enfrían." },
            { cam = { -1050, -1640, 85 }, look = { -1060, -1620, 76 }, ms = 4000, text = "Vende la carne, las pieles y los trofeos en la peletería de la cabaña." },
        },
    },
    {
        id = "fisher", name = "Pescador", icon = "🎣", color = { 70, 170, 230 },
        description = "Pesca desde el muelle o sal en barco a los bancos de peces. Lanza, espera la picada sin dejarte engañar y recoge sin romper el sedal. Cada especie pelea distinto.",
        pay = "Según la especie: $15-400 por pieza en la lonja.",
        howTo = "Muelle de Santa Maria Beach, en Los Santos.",
        locationName = "Muelle de Santa Maria Beach",
        requirements = "Nivel 2 para salir en barco.",
        hq = { x = 836.5, y = -1858.0, z = 12.87, interior = 0, dimension = 0 },
        vehicle = nil,   -- el barco se pide en el panel de la sede (nivel 2)
        boat = { model = 453, x = 720.0, y = -2020.0, z = 0.5, rz = 180 },
        cinematic = {
            { cam = { 880, -1820, 30 }, look = { 836, -1858, 12 }, ms = 4500, text = "La sede de pescadores está en el muelle de Santa Maria Beach." },
            { cam = { 800, -2080, 25 }, look = { 836, -2050, 12 }, ms = 4500, text = "Pescas desde el muelle. Con experiencia, sales en barco a los bancos de peces." },
            { cam = { 650, -2250, 20 }, look = { 700, -2300, 0 }, ms = 4000, text = "Vende lo que pesques en la lonja: los precios cambian con el mercado." },
        },
    },
    {
        id = "miner", name = "Minero", icon = "⛏️", color = { 160, 160, 180 },
        description = "Busca vetas en la cantera, rompe la roca golpeando sus grietas, decide si usar dinamita y sal corriendo si hay derrumbe. Vende el mineral en la fundición.",
        pay = "Según el mineral: $20-350 por pieza. Las gemas valen mucho más.",
        howTo = "Cantera Hunter, en Bone County, al norte de Las Venturas.",
        locationName = "Cantera Hunter",
        requirements = nil,
        hq = { x = 586.0, y = 872.0, z = -42.5, interior = 0, dimension = 0 },
        vehicle = nil,   -- la cantera se recorre a pie
        cinematic = {
            { cam = { 640, 920, 10 }, look = { 586, 872, -42 }, ms = 4500, text = "La cantera Hunter está en Bone County. La oficina queda en el fondo del pozo." },
            { cam = { 560, 780, -20 }, look = { 600, 840, -40 }, ms = 4500, text = "Busca vetas, rompe la roca por sus grietas y ojo con los derrumbes." },
            { cam = { 600, 900, -30 }, look = { 586, 872, -42 }, ms = 4000, text = "El mineral se vende en la fundición de la cantera. El oro y las gemas, aún mejor." },
        },
    },
}

-- Índice por id (lo llenan cliente y servidor al cargar)
JOBS_BY_ID = {}
for _, job in ipairs(JOBS) do JOBS_BY_ID[job.id] = job end

----------------------------------------------------------------
-- Puntos de venta con precios dinámicos (s_market.lua)
--  items: [itemId] = precio base. El precio real fluctúa cada MARKET.TICK_MIN minutos
--  y baja un poco con cada unidad vendida (saturación); se recupera solo con el tiempo.
----------------------------------------------------------------
MARKET = {
    TICK_MIN = 15,
    MIN_FACTOR = 0.6, MAX_FACTOR = 1.35,
    DRIFT = 0.08,          -- variación aleatoria máxima por tick
    SATURATION = 0.012,    -- lo que baja el precio por unidad vendida
    RECOVERY = 0.04,       -- lo que vuelve hacia 1.0 en cada tick
}

MARKETS = {
    {
        id = "fishmarket", name = "Lonja del puerto", icon = "🐟",
        x = 822.0, y = -1866.0, z = 12.87, interior = 0, dimension = 0,
        items = { fish_sardine = 15, fish_bass = 45, fish_tuna = 120, fish_swordfish = 380, old_boot = 3 },
    },
    {
        id = "furrier", name = "Carnicería y peletería", icon = "🥩",
        x = -1048.0, y = -1612.0, z = 76.4, interior = 0, dimension = 0,
        items = { meat_game = 35, hide_rabbit = 25, hide_deer = 140, hide_boar = 110, hide_bear = 480, antlers = 260 },
    },
    {
        id = "foundry", name = "Fundición de la cantera", icon = "🏭",
        x = 572.0, y = 880.0, z = -42.5, interior = 0, dimension = 0,
        items = { ore_coal = 18, ore_iron = 32, ore_copper = 45, ore_silver = 110, ore_gold = 190 },
    },
    {
        id = "pawnshop", name = "Compraventa El Trapero", icon = "💰",
        x = 1310.0, y = -1370.0, z = 13.55, interior = 0, dimension = 0,
        items = {
            old_watch = 150, gold_ring = 320, rare_vinyl = 180, old_coin = 60, broken_phone = 40,
            pearl = 260, gem_raw = 520, message_bottle = 90,
        },
    },
}

MARKETS_BY_ID = {}
for _, m in ipairs(MARKETS) do MARKETS_BY_ID[m.id] = m end

----------------------------------------------------------------
-- Ajustes de cada trabajo
----------------------------------------------------------------
GARBAGE = {
    STOPS_PER_ROUTE = 5,
    BAGS_MIN = 2, BAGS_MAX = 4,
    PAY_PER_STOP = 60, PAY_PER_STOP_MAX = 120,  -- 60 al cargar; hasta +60 por parada según el compactador
    COMPACT_EVERY = 2,                          -- paradas hasta que el camión se llena y toca ordenar
    ROUTE_BONUS = 150,                          -- al volver a la planta con la ruta completa
    TRUCK_REAR = { 0, -5.2, 0 },                -- dónde se cargan las bolsas (relativo al camión)
    -- Probabilidad base de que una parada esconda algo de valor (+3% por nivel)
    FIND_CHANCE = 0.22, FIND_CHANCE_PER_LEVEL = 0.03,
    FINDS = {   -- peso relativo; cash = fajo de billetes (dinero directo)
        { item = "old_coin", weight = 30 }, { item = "broken_phone", weight = 25 },
        { item = "old_watch", weight = 18 }, { item = "rare_vinyl", weight = 12 },
        { item = "gold_ring", weight = 8 }, { cash = { 80, 300 }, weight = 7 },
    },
    POINTS = {
        { 2470, -1680, 13.4 }, { 2440, -1640, 13.4 }, { 2330, -1690, 13.5 }, { 2230, -1740, 13.5 },
        { 2080, -1690, 13.4 }, { 1960, -1770, 13.4 }, { 1830, -2030, 13.4 }, { 1870, -2120, 13.4 },
        { 2400, -1960, 13.4 }, { 2310, -2010, 13.4 }, { 2150, -1300, 23.9 }, { 2350, -1330, 23.9 },
        { 1970, -1200, 25.0 }, { 1450, -1600, 13.4 }, { 1100, -1400, 13.4 }, { 840, -1620, 13.4 },
        { 1250, -1830, 13.4 }, { 1530, -1730, 13.4 },
    },
}

FARMER = {
    -- Campo: filas de puntos que hay que recorrer con el tractor (arar) y la cosechadora (cosechar)
    FIELD = { x = -140, y = 20, z = 3.0, width = 80, rows = 4, rowGap = 14, angle = 0 },
    PLOW_POINTS = 8,
    HARVEST_MODEL = 532,
    SOW_POINTS = 5,                            -- puntos del surco que se siembran a pie
    CARE_CHANCE = 0.6,                         -- probabilidad de que la temporada traiga un problema
    SILO = { -40.0, 60.0, 3.1 },               -- donde se entrega la cosecha
    PAY_MIN = 250, PAY_MAX = 500,
    CROPS = {
        { id = "wheat", name = "Trigo", icon = "🌾" },
        { id = "corn", name = "Maíz", icon = "🌽" },
        { id = "tomato", name = "Tomate", icon = "🍅" },
        { id = "potato", name = "Papa", icon = "🥔" },
    },
    -- Problemas posibles (minijuego) cuando la temporada trae uno
    CARE_EVENTS = { "pests", "water", "weeds" },
}

LUMBER = {
    TREES_PER_LOAD = 4,
    TRICKY_CHANCE = 0.3,                        -- árboles complicados (minijuego de dirección de caída)
    TREE_MODELS = { 654, 655, 656, 657 },       -- pinos de Flint County
    LOG_MODEL = 1463,                           -- pila de troncos (se carga en el camión)
    SAWMILL = { -1995.0, -2375.0, 30.6 },       -- donde se entrega y se corta
    PAY_PER_LOG = 45, PAY_PER_LOG_MAX = 90,
    TREES = {
        { -1680, -2200, 45 }, { -1700, -2160, 50 }, { -1640, -2240, 40 }, { -1620, -2180, 48 },
        { -1730, -2230, 42 }, { -1600, -2300, 38 }, { -1760, -2160, 55 }, { -1660, -2130, 58 },
        { -1580, -2240, 42 }, { -1720, -2280, 36 }, { -1790, -2210, 48 }, { -1610, -2120, 62 },
    },
}

HUNTER = {
    TRACKS = { 4, 6 },                           -- huellas por rastro (mín, máx)
    TRACK_STEP = { 28, 45 },                     -- metros entre huellas
    TRACK_COLD_MS = 3 * 60 * 1000,               -- si tardas más, el rastro se enfría y se pierde
    ZONES = {
        { -900, -1500, 70 }, { -1200, -1400, 60 }, { -760, -1260, 60 }, { -1300, -1750, 90 },
    },
    -- Animales: peso por nivel mínimo y lo que dan según la calidad del disparo
    ANIMALS = {
        { id = "rabbit", name = "Conejo", weight = 35, minLevel = 1, difficulty = 0.9, meat = 1, hide = "hide_rabbit" },
        { id = "deer", name = "Ciervo", weight = 35, minLevel = 1, difficulty = 0.5, meat = 3, hide = "hide_deer", trophy = "antlers" },
        { id = "boar", name = "Jabalí", weight = 22, minLevel = 2, difficulty = 0.65, meat = 3, hide = "hide_boar", charges = true },
        { id = "bear", name = "Oso", weight = 8, minLevel = 4, difficulty = 0.55, meat = 5, hide = "hide_bear", charges = true },
    },
}

FISHER = {
    BOAT_LEVEL = 2,
    REEL_DIFFICULTY = 0.45,                      -- desde esta dificultad el pez pelea (minijuego de recoger)
    SPOT_STOCK = { 3, 6 },                       -- capturas por punto antes de agotarse
    PIER_SPOTS = {
        { 836.5, -1950, 12.9 }, { 836.5, -2010, 12.9 }, { 836.5, -2060, 12.9 }, { 826, -2063, 12.9 },
        { 847, -2063, 12.9 },
    },
    SEA_SPOTS = {
        { 700, -2300, 0.5 }, { 500, -2200, 0.5 }, { 950, -2350, 0.5 }, { 620, -2450, 0.5 }, { 820, -2500, 0.5 },
    },
    -- Peso de cada especie según dónde pescas; difficulty 0..1 (lo nervioso que es el pez)
    SPECIES = {
        { item = "fish_sardine", name = "Sardina", difficulty = 0.25, pier = 45, sea = 15 },
        { item = "fish_bass", name = "Lubina", difficulty = 0.45, pier = 30, sea = 30 },
        { item = "fish_tuna", name = "Atún", difficulty = 0.7, pier = 5, sea = 30 },
        { item = "fish_swordfish", name = "Pez espada", difficulty = 0.9, pier = 0, sea = 10, minLevel = 3 },
        { item = "old_boot", name = "Bota vieja", difficulty = 0.1, pier = 12, sea = 5 },
        { item = "message_bottle", name = "Botella con mensaje", difficulty = 0.15, pier = 2, sea = 4 },
        { item = "pearl", name = "Ostra con perla", difficulty = 0.3, pier = 1, sea = 3 },
    },
}

MINER = {
    VEINS_PER_SHIFT = 5,
    RICH_CHANCE = 0.25,            -- vetas de carbón/hierro/cobre que también son "ricas" (minijuego)
    ROCK_MODELS = { 905, 897, 896 },
    VEINS = {
        { 560, 820, -40 }, { 610, 800, -38 }, { 650, 860, -36 }, { 640, 930, -34 }, { 560, 920, -38 },
        { 530, 870, -36 }, { 600, 950, -32 }, { 680, 900, -30 }, { 520, 800, -30 }, { 590, 760, -28 },
    },
    -- Mineral posible (peso) y cuántas piezas da según la puntuación de la veta
    ORES = {
        { item = "ore_coal", weight = 34, yield = { 2, 5 } },
        { item = "ore_iron", weight = 28, yield = { 2, 4 } },
        { item = "ore_copper", weight = 20, yield = { 1, 4 } },
        { item = "ore_silver", weight = 11, yield = { 1, 3 }, minLevel = 2 },
        { item = "ore_gold", weight = 7, yield = { 1, 3 }, minLevel = 3 },
    },
    GEM_CHANCE = 0.06,             -- probabilidad de gema por veta (x2 con dinamita bien puesta)
    CAVEIN_CHANCE = 0.12,          -- probabilidad de derrumbe (x2 con dinamita)
    CAVEIN_DAMAGE = 25,
}
