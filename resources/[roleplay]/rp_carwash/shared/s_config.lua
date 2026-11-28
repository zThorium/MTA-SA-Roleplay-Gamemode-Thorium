--[[
    rp_carwash · configuración compartida

    Suciedad de los vehículos y lavados.
    - El cliente del conductor mira cada segundo qué superficie pisa el vehículo (material de GTA bajo las ruedas)
      y suma suciedad según el terreno: barro > tierra > arena > pasto > calle. El servidor la limita y la publica
      en el elementData "rp:dirt" (0 = limpio, 1 = cubierto de barro); los autos con dueño la guardan en vehicles.dirt.
    - Cada cliente pinta la suciedad con un shader (fx/dirt.fx) sobre la textura de carrocería "vehiclegrunge256":
      más barro abajo y en manchas, más tapado cuanto más sucio.
    - Lavados: el conductor entra al marcador con el auto, pulsa E y paga en efectivo. El auto queda quieto mientras
      el agua lo limpia (efecto de agua y la suciedad baja de a poco).
]]

CARWASH = {
    PRICE = 40,                 -- $ en efectivo por lavado
    DURATION = 9000,            -- ms que dura el lavado (el auto queda congelado)
    MIN_TO_WASH = 0.05,         -- por debajo de esto el auto ya está limpio
    USE_DIST = 4.0,             -- metros desde el punto del lavado al centro del auto
    MARKER_SIZE = 3.5,

    -- Lavados: clave para rp_markers (los admins los mueven), nombre y posición del suelo
    WASHES = {
        { key = "pronto", name = "Lavado Pronto Copec", x = 1911.2, y = -1776.3, z = 12.4 },   -- túnel de rp_pronto, Idlewood
    },

    -- Suciedad que se suma por segundo de manejo a 50 km/h (1 = tapado). Material de GTA (surfinfo.dat) -> tipo
    RATES = {
        mud   = 1 / 90,      -- ~1,5 min en barro
        dirt  = 1 / 180,     -- ~3 min en tierra o ripio
        sand  = 1 / 240,     -- ~4 min en arena
        grass = 1 / 360,     -- ~6 min en pasto
        road  = 1 / 7200,    -- 2 h por calle: polvo de ciudad
    },
    SURFACES = {
        [24] = "mud", [25] = "mud",                                   -- MUD_WET, MUD_DRY
        [6] = "dirt", [21] = "dirt", [22] = "dirt", [26] = "dirt",    -- GRAVEL, WASTEGROUND, WOODLANDGROUND, DIRT
        [27] = "dirt", [40] = "dirt",                                 -- DIRTTRACK, CORNFIELD
        [28] = "sand", [29] = "sand", [30] = "sand", [31] = "sand",   -- SAND_DEEP, MEDIUM, COMPACT, ARID
        [32] = "sand", [33] = "sand",                                 -- SAND_MORE, SAND_BEACH
        [9] = "grass", [10] = "grass", [11] = "grass", [12] = "grass", [13] = "grass", [14] = "grass",
        [15] = "grass", [16] = "grass", [17] = "grass", [19] = "grass", [20] = "grass", [23] = "grass",
    },
    MIN_SPEED = 8,              -- km/h: parado no se ensucia
    REF_SPEED = 50,             -- km/h: a esta velocidad se suma la tasa tal cual (de 0,3x a 1,5x)
    MAX_SPEED_FACTOR = 1.5,
    SEND_EVERY = 10000,         -- ms: el conductor manda lo acumulado al servidor
    SAVE_STEP = 0.05,           -- se guarda en BD cuando cambia al menos esto
    VEHICLE_TYPES = { Automobile = true, ["Monster Truck"] = true, Quad = true, Bike = true },

    -- Dibujo
    MIN_VISIBLE = 0.03,         -- por debajo no se aplica el shader (el auto conserva su brillo nativo)
    SHADER_DIST = 80,           -- metros
}

-- Tasa máxima posible (el servidor rechaza más que esto)
CARWASH.MAX_RATE = CARWASH.RATES.mud * CARWASH.MAX_SPEED_FACTOR
