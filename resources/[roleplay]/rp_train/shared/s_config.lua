--[[
    rp_train · configuración compartida (la leen servidor y cliente)
    Distancias en metros, velocidades en m/s, tiempos en ms.
]]

TRAIN = {
    -- Trenes en la vía principal. station = nodo de la estación donde sale (espera en el andén y arranca);
    -- sin station, start = metros desde el nodo 1 de la vía (0..~18135).
    -- Modelos: 538 Brown Streak (pasajeros) + 570 vagón; 537 Freight + 569 plataforma / 590 caja.
    -- passenger = true: lleva pasajeros con boleto y aparece en los carteles LED de las estaciones.
    TRAINS = {
        { model = 538, carriages = { 570, 570, 570 }, station = 331, passenger = true }, -- sale de Unity Station (Los Santos)
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
    CARRIAGE_GAP = 18.5,      -- separación aproximada entre centros (servidor; el cliente usa el largo real de cada modelo)
    COUPLING = 1.0,           -- hueco entre vagón y vagón (m)
    CAR_SNAP = 25,            -- un vagón más desfasado que esto se coloca de una vez (al aparecer)
    CAR_CATCHUP = 4,          -- m/s máximos de corrección para recuperar su sitio (suave, sin saltos)
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

    -- Claxon de salida (sounds/claxon.mp3): suena cuando faltan DEPART_HORN_MS para dejar el andén
    DEPART_HORN_MS = 10000,
    DEPART_HORN_DISTANCE = 250, -- se oye hasta aquí
    DEPART_HORN_VOLUME = 1.0,

    -- Pasajeros: boleto (item de rp_inventory) que se gasta al subir; solo se baja en estaciones
    TICKET_ITEM = "train_ticket",
    TICKET_PRICE = 25,
    CAR_HALF_LENGTH = 9.8,    -- media longitud de un vagón 570 (para saber si estás junto a él)
    BOARD_SIDE = 5,           -- distancia máxima al eje del vagón para subir
    ALIGHT_SIDE = 3.6,        -- al bajar quedas a esta distancia del eje, del lado del andén
    PASSENGERS_PER_CAR = 10,
    CAM_DISTANCE = 16,        -- cámara del pasajero: distancia y altura sobre el vagón (gira con el ratón)
    CAM_HEIGHT = 3,

    -- Estaciones: boleterías y carteles LED que colocan los admins (tabla train_fixtures)
    STATION_SNAP = 300,       -- una boletería o cartel se asigna a la estación más cercana a menos de esto
    BOOTH_SKIN = 253,         -- empleado de la boletería (uniforme de conductor de tren)
    BOOTH_NAME = "Boletería",
    ETA_MS = 2000,            -- cada cuánto el servidor publica la llegada estimada (rp:train:eta)
    SIGN_WIDTH = 3.2,         -- cartel LED en el mundo (m)
    SIGN_HEIGHT = 0.6,
    SIGN_LIFT = 1.4,          -- altura sobre el admin que lo coloca
    SIGN_FORWARD = 1.0,       -- metros delante del admin (el cartel lo mira)
    SIGN_DRAW_DISTANCE = 70,
    -- Editor 3D del cartel (/editarcartel, y al crearlo): m/s y grados/s; Mayús los multiplica por SIGN_EDIT_FINE
    SIGN_EDIT_SPEED = 1.5,
    SIGN_EDIT_TURN = 60,
    SIGN_EDIT_FINE = 0.15,
    SIGN_EDIT_RANGE = 30,     -- el cartel no puede alejarse más de esto de donde estaba
    SIGN_EDIT_NEAR = 15,      -- /editarcartel sin id edita el más cercano a menos de esto
    -- /duplicar en el editor: máximo de copias de una vez y de metros entre una copia y la siguiente
    DUP_MAX = 20,
    DUP_STEP_MAX = 10,

    -- Boletero destacado (c_booth.lua): aura en el piso que respira para que se vea quién vende los boletos
    BOOTH_AURA_COLOR = { 255, 255, 255 },
    BOOTH_AURA_RADIUS = 0.9,        -- radio del aura (m)
    BOOTH_AURA_PERIOD = 2600,       -- una respiración completa (ms)
    BOOTH_AURA_DISTANCE = 45,       -- se dibuja a menos de esto de la cámara

    -- Torniquetes (/creartorniquete): el admin se pone FUERA mirando hacia el andén. Desde fuera se
    -- valida el boleto (lo gasta y deja un pase para esa estación); desde el andén se sale libre.
    -- En una estación con torniquetes se sube al tren con el pase, no con el boleto.
    GATE_POST_MODEL = 966,          -- poste
    GATE_ARM_MODEL = 968,           -- brazo (vertical con rotación Y 0; se baja girándolo 90°)
    GATE_ARM_LENGTH = 0.24,         -- escala del brazo a lo largo (el 968 de serie mide ~6 m)
    GATE_ARM_SIDE = 1,              -- -1 si el brazo baja hacia el lado contrario del paso
    GATE_HALF_WIDTH = 0.75,         -- medio ancho del paso (el poste queda a la izquierda, mirando al andén)
    GATE_FORWARD = 1.2,             -- el paso queda a esta distancia delante del admin
    GATE_USE = 2.2,                 -- distancia a la que aparece el boleto o se abre al salir
    GATE_OPEN_MS = 3500,            -- tiempo que queda abierto
    GATE_MOVE_MS = 500,             -- subir o bajar el brazo
    GATE_PASS_MS = 30 * 60000,      -- un boleto validado sirve para subir al tren durante esto

    -- Rejas (/crearreja [tipo]): cierran los lados de los torniquetes para que nadie entre al andén por fuera.
    -- Objetos del juego, congelados e irrompibles. El número de la lista es el [tipo] del comando.
    FENCE_MODELS = {
        { model = 970,  name = "Barandilla metálica" },  -- fencesmallb
        { model = 1419, name = "Reja de hierro" },       -- DYN_F_IRON_1
        { model = 1411, name = "Malla metálica" },       -- DYN_MESH_1
        { model = 983,  name = "Malla alta" },           -- fenceshit3
        { model = 994,  name = "Valla de metal baja" },  -- lhouse_barrier2
    },
    FENCE_FORWARD = 1.5,            -- la reja aparece a esta distancia delante del admin
    FENCE_DROP = 1.0,               -- y esto por debajo de su centro (luego se ajusta en el editor)
}

-- Torniquete: dónde van el poste y el brazo a partir del centro del paso (x, y, z del jugador) y su
-- rotación (mira hacia el andén). Lo usan el servidor (s_stations.lua) y el editor 3D (c_signeditor.lua).
function TrainGateLayout(x, y, z, rot)
    local r = math.rad(rot)
    return x - math.cos(r) * TRAIN.GATE_HALF_WIDTH, y - math.sin(r) * TRAIN.GATE_HALF_WIDTH, z - 1, z - 0.3
end

function TrainFenceModel(model)
    for i, f in ipairs(TRAIN.FENCE_MODELS) do if f.model == model then return f, i end end
end
