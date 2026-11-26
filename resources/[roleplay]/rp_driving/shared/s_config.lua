--[[
    rp_driving / s_config.lua  (compartido cliente/servidor)

    Configuracion de la autoescuela y catalogo de pruebas.

    Coordenadas de las pruebas: todo es RELATIVO a la pista (arena) de cada
    autoescuela. La pista es un punto + rumbo sobre un terreno plano y libre:
        f = metros hacia delante (sentido del rumbo de la pista)
        r = metros a la derecha
        a = rumbo del auto relativo a la pista (0 = hacia delante, 90 = mirando
            a la izquierda, 180 = mirando hacia atras, -90 = a la derecha)
    Asi la misma prueba funciona en cualquier sitio: un admin mueve la pista con
    /arenaautoescuela y no hay que tocar ninguna coordenada de aqui.

    Puntaje (0-100) de cada intento, como en la autoescuela de San Andreas:
        100
        - TIME_PENALTY por cada segundo por encima de "par"
        - DAMAGE_PENALTY por cada 100 de vida que pierde el auto (de 1000)
        - CONE_PENALTY por cada cono derribado
        - precision al detenerse en la zona final (distancia al centro y angulo)
    Medallas: bronce >= 70, plata >= 85, oro = 100 y platino = 100 en menos de
    "platinum" segundos. Con menos de 70 la prueba no se aprueba.
]]

DRIVING = {
    KEY = "e",                    -- hablar con el instructor
    INTERACT_RADIUS = 2.5,
    PED_SKIN = 17,                -- instructor
    BLIP = 36,                    -- icono de autoescuela en el radar
    BOARD_DISTANCE = 30,          -- m a los que se ve la pizarra de mejores puntajes
    BOARD_ROWS = 5,

    -- Autoescuela que se crea si la tabla esta vacia (Pershing Square, Los Santos).
    -- Los admins la mueven con /crearautoescuela y /borrarautoescuela.
    DEFAULT_SCHOOL = { x = 1460.0, y = -1650.0, z = 14.05, rot = 90 },

    -- Pista por defecto: pista sur del aeropuerto de Los Santos, mirando al este.
    -- Cada autoescuela puede tener la suya (/arenaautoescuela <id>).
    DEFAULT_ARENA = { x = 1500.0, y = -2593.6, z = 13.55, rot = 270 },
    ARENA_RADIUS = 320,           -- m desde el inicio: si te alejas mas, suspendes

    -- Cada intento corre en una dimension privada (sin trafico ni otros jugadores)
    DIMENSION_BASE = 21000,
    MAX_RUNS = 200,

    INTRO_TIMEOUT = 20000,        -- ms maximos de la presentacion antes de arrancar solo
    COUNTDOWN = 3,                -- segundos de cuenta atras
    STOP_SPEED = 3,               -- km/h por debajo de los cuales el auto "esta parado"
    STOP_HOLD = 600,              -- ms parado dentro de la zona para terminar
    FLIP_TIME = 3000,             -- ms volcado antes de suspender
    TICK = 100,                   -- ms entre comprobaciones del servidor

    -- Puntaje
    TIME_PENALTY = 4,             -- puntos por segundo por encima del par
    DAMAGE_PENALTY = 6,           -- puntos por cada 100 de vida del auto perdidos
    CONE_PENALTY = 5,             -- puntos por cono derribado
    DIST_FREE = 0.6,              -- m de error al centro de la zona que no restan
    DIST_PENALTY = 6,             -- puntos por metro de error por encima de lo anterior
    ANGLE_FREE = 6,               -- grados de error que no restan
    ANGLE_PENALTY = 0.5,          -- puntos por grado por encima de lo anterior

    MEDALS = {
        { id = 1, key = "bronze",   name = "Bronce",  min = 70 },
        { id = 2, key = "silver",   name = "Plata",   min = 85 },
        { id = 3, key = "gold",     name = "Oro",     min = 100 },
        { id = 4, key = "platinum", name = "Platino", min = 100 },   -- ademas, tiempo <= platinum
    },

    -- Licencia
    LICENSE_PREFIX = "SA",
    REPRINT_PRICE = 150,          -- $ en efectivo por un duplicado del papel
    SHOW_DISTANCE = 3,            -- m para /mostrarlicencia
    REVOKE_DISTANCE = 5,          -- m para /retirarlicencia (la policia)
    POLICE_FACTION_TYPE = "policia", -- quien puede retirar licencias: cualquier faccion de este tipo
    REASON_MAX = 120,

    -- Colores (r, g, b) de la interfaz dx
    COLOR = { 245, 165, 36 },
}

--[[
    Catalogo de pruebas, en orden: cada una se desbloquea al aprobar la anterior.
    Al aprobar todas se entrega la licencia.

    Campos:
      id, name, short   identificador, nombre y resumen de una linea
      howto             instrucciones que se muestran en la presentacion
      model             auto de la prueba
      par               segundos para no perder puntos por tiempo
      platinum          segundos para la medalla de platino (con 100 puntos)
      limit             segundos maximos: pasado ese tiempo se suspende
      start             { f, r, a } donde aparece el auto
      cones             lista de { f, r } (conos que restan puntos si se derriban)
      checkpoints       lista de { f, r, size, reverse = true (hay que pasarlo en marcha atras) }
      laps              vueltas al recorrido de checkpoints (por defecto 1)
      box               zona final donde hay que detenerse: { f, r, a, w (ancho), l (largo),
                        sym = true (vale mirando hacia un lado o el contrario) }.
                        Sin box, la prueba termina al pasar el ultimo checkpoint.
      spin              grados de giro acumulado que hay que hacer antes de parar (trompo)
]]

local function lane(fromF, toF, step, r)
    local list = {}
    for f = fromF, toF, step do
        list[#list + 1] = { f, -r }
        list[#list + 1] = { f, r }
    end
    return list
end

local function boxCones(f, r, w, l, list)
    list = list or {}
    local hw, hl = w / 2 + 0.6, l / 2 + 0.6
    list[#list + 1] = { f - hl, r - hw }
    list[#list + 1] = { f - hl, r + hw }
    list[#list + 1] = { f + hl, r - hw }
    list[#list + 1] = { f + hl, r + hw }
    return list
end

local function concat(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, v in ipairs(list) do out[#out + 1] = v end
    end
    return out
end

DRIVING_TESTS = {
    {
        id = "frenada", name = "Frenada exacta", short = "Acelera y detente justo dentro de la zona.",
        howto = "Pisa a fondo por el carril de conos y frena para quedar detenido dentro de la zona amarilla del final. Cuanto mas cerca del centro y mas recto, mejor.",
        model = 445, par = 9, platinum = 7.5, limit = 30,
        start = { 0, 0, 0 },
        cones = concat(lane(12, 96, 12, 4.5), boxCones(110, 0, 4, 7)),
        checkpoints = {},
        box = { f = 110, r = 0, a = 0, w = 4, l = 7 },
    },
    {
        id = "mediavuelta", name = "Media vuelta", short = "Ve hasta el fondo, da la vuelta y vuelve a la salida.",
        howto = "Conduce hasta el punto del fondo, da media vuelta como prefieras (freno de mano, maniobra...) y vuelve a detenerte en la zona de salida mirando hacia donde viniste.",
        model = 445, par = 14, platinum = 11.5, limit = 40,
        start = { 0, 0, 0 },
        cones = concat(lane(14, 70, 14, 5), boxCones(0, 0, 4, 7)),
        checkpoints = { { 82, 0, 6 } },
        box = { f = 0, r = 0, a = 180, w = 4, l = 7 },
    },
    {
        id = "trompo", name = "Trompo de 360", short = "Gira el auto una vuelta completa y para en la zona.",
        howto = "Acelera, tira del freno de mano y haz girar el auto una vuelta completa (360 grados) sin salirte. Termina detenido en la zona amarilla mirando hacia delante.",
        model = 445, par = 8, platinum = 6, limit = 30,
        start = { 0, 0, 0 },
        cones = concat(boxCones(0, 0, 4, 7), { { 24, -12 }, { 24, 12 }, { -12, -12 }, { -12, 12 } }),
        checkpoints = {},
        spin = 340,
        box = { f = 0, r = 0, a = 0, w = 4, l = 7 },
    },
    {
        id = "slalom", name = "Slalom", short = "Zigzaguea entre los conos sin derribar ninguno.",
        howto = "Pasa por los puntos alternando a cada lado de la fila de conos. Rapido pero suave: cada cono derribado resta puntos.",
        model = 445, par = 17, platinum = 14.5, limit = 45,
        start = { 0, 0, 0 },
        cones = { { 25, 0 }, { 45, 0 }, { 65, 0 }, { 85, 0 }, { 105, 0 }, { 125, 0 }, { 145, 0 } },
        checkpoints = {
            { 35, 4.5, 4 }, { 55, -4.5, 4 }, { 75, 4.5, 4 }, { 95, -4.5, 4 },
            { 115, 4.5, 4 }, { 135, -4.5, 4 }, { 160, 0, 5 },
        },
    },
    {
        id = "reversa", name = "Marcha atras", short = "Recorre la curva en reversa y aparca.",
        howto = "Sin dar la vuelta: recorre los puntos en marcha atras (si pasas un punto hacia delante no cuenta) y detente dentro de la zona del final.",
        model = 445, par = 18, platinum = 14.5, limit = 50,
        start = { 100, 0, 0 },
        cones = concat({ { 82, 0 }, { 62, 0 }, { 42, 0 } }, boxCones(5, 0, 4, 7)),
        checkpoints = { { 82, -4.5, 4, reverse = true }, { 62, 4.5, 4, reverse = true }, { 42, -4.5, 4, reverse = true } },
        box = { f = 5, r = 0, a = 0, w = 4, l = 7 },
    },
    {
        id = "noventa", name = "Derrape de 90", short = "Entra de lado en el hueco con el freno de mano.",
        howto = "Acelera por el carril y, con el freno de mano, cruza el auto para quedar parado de lado (a 90 grados) dentro de la zona entre los conos. Vale hacia cualquiera de los dos lados.",
        model = 445, par = 9, platinum = 7, limit = 30,
        start = { 0, 0, 0 },
        cones = concat(lane(12, 72, 12, 5), boxCones(96, 0, 7, 4)),
        checkpoints = {},
        box = { f = 96, r = 0, a = 90, w = 4, l = 7, sym = true },
    },
    {
        id = "vueltas", name = "Tres vueltas", short = "Tres vueltas rapidas alrededor de la isla de conos.",
        howto = "Da tres vueltas al circuito rodeando la fila central de conos, pasando por todos los puntos. Al final, para en la zona de llegada.",
        model = 602, par = 52, platinum = 45, limit = 120,
        start = { 0, 6, 0 },
        cones = concat({ { 30, -5 }, { 50, -5 }, { 70, -5 }, { 90, -5 }, { 110, -5 } }, boxCones(60, 6, 4, 7)),
        checkpoints = { { 120, 6, 6 }, { 132, -5, 6 }, { 120, -16, 6 }, { 20, -16, 6 }, { 8, -5, 6 }, { 20, 6, 6 } },
        laps = 3,
        box = { f = 60, r = 6, a = 0, w = 4, l = 7 },
    },
    {
        id = "examen", name = "Examen final", short = "Todo lo aprendido en un solo recorrido.",
        howto = "Slalom, media vuelta al fondo, vuelta por el carril exterior y, para terminar, detente en la zona de salida. Es la prueba que te da la licencia: hazlo limpio.",
        model = 602, par = 40, platinum = 34, limit = 100,
        start = { 0, 0, 0 },
        cones = concat(
            { { 30, 0 }, { 50, 0 }, { 70, 0 }, { 90, 0 } },
            lane(120, 180, 20, 6),
            { { 150, -20 }, { 110, -20 }, { 70, -20 }, { 30, -20 } },
            boxCones(0, -26, 4, 7)
        ),
        checkpoints = {
            { 40, 4.5, 4 }, { 60, -4.5, 4 }, { 80, 4.5, 4 }, { 100, 0, 5 },
            { 190, 0, 6 }, { 175, -26, 6 }, { 130, -26, 5 }, { 90, -26, 5 }, { 50, -26, 5 },
        },
        box = { f = 0, r = -26, a = 180, w = 4, l = 7 },
    },
}

DRIVING_TEST_INDEX = {}
for i, t in ipairs(DRIVING_TESTS) do
    t.index = i
    DRIVING_TEST_INDEX[t.id] = t
end

----------------------------------------------------------------
-- Geometria compartida
----------------------------------------------------------------
-- Pasa (f, r) relativo a la pista a coordenadas del mundo
function drivingToWorld(arena, f, r)
    local h = math.rad(arena.rot)
    local fx, fy = -math.sin(h), math.cos(h)      -- adelante
    local rx, ry = math.cos(h), math.sin(h)       -- derecha
    return arena.x + fx * f + rx * r, arena.y + fy * f + ry * r
end

-- Pasa coordenadas del mundo a (f, r) relativo a la pista
function drivingToLocal(arena, x, y)
    local h = math.rad(arena.rot)
    local dx, dy = x - arena.x, y - arena.y
    return dx * -math.sin(h) + dy * math.cos(h), dx * math.cos(h) + dy * math.sin(h)
end

-- Angulo en (-180, 180]
function drivingWrap(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end

-- Medalla (0 = suspendida) para un puntaje y un tiempo en segundos
function drivingMedalFor(test, score, seconds)
    if score >= 100 then
        return (test.platinum and seconds <= test.platinum) and 4 or 3
    end
    if score >= 85 then return 2 end
    if score >= 70 then return 1 end
    return 0
end
