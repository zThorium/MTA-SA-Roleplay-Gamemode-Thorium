--[[
    rp_train · configuración compartida (la leen servidor y cliente)
    Distancias en metros, velocidades en m/s, tiempos en ms.
]]

TRAIN = {
    -- Trenes en la vía principal. station = nodo de la estación donde sale (espera en el andén y arranca);
    -- sin station, start = metros desde el nodo 1 de la vía (0..~18135).
    -- Modelos: 538 Brown Streak (pasajeros) + 570 vagón; 537 Freight + 569 plataforma / 590 caja.
    TRAINS = {
        { model = 538, carriages = { 570, 570, 570 }, station = 331 },       -- sale de Unity Station (Los Santos)
        { model = 537, carriages = { 569, 590, 569, 590 }, station = 597 },  -- carga: al otro lado del bucle (San Fierro)
    },
    -- Recorrido completo (bucle LS-SF-LV de tracks.dat) contado desde esta estación:
    -- Unity → Market → Cranberry → Yellow Bell → Sobell → Linden → Unity
    ROUTE_ORIGIN = 331,
    -- Sin jugadores a menos de esto del tren (ni de donde quedó aparcado) el servidor solo avanza su
    -- distancia en memoria: no mueve elementos ni manda nada por la red.
    PLACE_RADIUS = 450,
    -- Con un jugador a menos de esto el tren lo mueve SIEMPRE la física de su juego (se le asigna como
    -- sincronizador): movimiento fluido, nunca a saltos. Menor que la distancia de streaming de vehículos.
    SYNC_RADIUS = 180,
    OFF_TRACK = 2,            -- un vagón a más de esto de la vía principal está en otra (en LS corre pegada la de tracks4)
    CLOCKWISE = true,         -- sentido de marcha inicial; el servidor lo corrige si el juego lo mueve al revés
    CARRIAGE_GAP = 18.5,      -- separación entre enganches (para recolocar el tren sin jugadores cerca)
    DRIVER_SKIN = 255,        -- maquinista

    SPEED = 22,               -- crucero (~80 km/h)
    ACCEL = 0.9,              -- arranque (m/s²)
    BRAKE = 0.8,              -- frenada hacia la estación (m/s²)
    STATION_STOP_MS = 20000,  -- espera en cada estación, como en el juego
    STATION_NAMES = {
        [59] = "Sobell Rail Yards", [107] = "Linden Station", [331] = "Unity Station",
        [371] = "Market Station", [597] = "Cranberry Station", [823] = "Yellow Bell Station",
    },

    TICK_MS = 500,            -- paso de simulación del servidor
    VELOCITY_UNIT = 50,       -- 1.0 de setTrainSpeed = 50 m/s

    -- Bocina (cliente, solo con el tren cargado en tu juego)
    HORN_CHECK_MS = 250,
    HORN_AHEAD = 110,         -- mira hasta esta distancia por delante del tren
    HORN_WIDTH = 3.2,         -- ancho de vía a cada lado
    HORN_MS = 1400,           -- duración de cada toque

    -- Cruces
    CROSSING_APPROACH = 170,  -- metros antes del cruce en que bajan las barreras
    CROSSING_CLEAR = 20,      -- metros que deja atrás la cola antes de subirlas
    CROSSING_SNAP = 40,       -- una barrera a más de esto de la vía no se acepta
    BARRIER_MODEL = 968,      -- brazo de barrera
    BARRIER_BASE_MODEL = 966, -- poste
    BARRIER_MOVE_MS = 3500,
    BELL_DISTANCE = 120,      -- se oyen las campanas hasta aquí
    BELL_VOLUME = 0.9,
}
