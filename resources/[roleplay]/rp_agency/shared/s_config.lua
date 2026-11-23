--[[
    rp_agency / s_config.lua  (compartido cliente/servidor)

    Agencia de empleo y registro civil: dispensador de turnos, cola, mostradores
    con trabajadora, emision del DNI y asignacion de trabajo.

    La sala se monta en el interior "Planning Department" (interior 3) en una
    dimension propia. Todo el mobiliario se coloca RELATIVO a ORIGIN: si en juego
    algo queda dentro de una pared, basta con mover ORIGIN (o un offset concreto).
    Offsets en metros: ox = hacia la derecha de la entrada, oy = hacia el fondo.
]]

AGENCY = {
    NAME = "Agencia de Empleo y Registro Civil",

    -- Puerta exterior (Ayuntamiento de Los Santos, Pershing Square)
    ENTRANCE = { x = 1481.03, y = -1771.31, z = 18.79 },
    EXIT_SPAWN = { x = 1481.05, y = -1768.80, z = 18.79, rot = 0 },   -- al norte de la puerta (hacia Pershing Square); el edificio queda al sur

    -- Interior: Planning Department
    INTERIOR = 3,
    DIMENSION = 30001,
    -- Punto de aparicion al entrar y origen de la sala (z = suelo + 1)
    INSIDE_SPAWN = { x = 383.40, y = 173.80, z = 1008.38, rot = 90 },
    ORIGIN = { x = 384.81, y = 173.80, z = 1008.38, rot = 90 },   -- rot = hacia donde mira la sala
    EXIT_OFFSET = { ox = 0, oy = -0.3 },        -- puerta de salida (la aparicion queda 1.4 m mas adentro)

    -- Dispensador rojo de turnos
    DISPENSER = { ox = 2.2, oy = 2.0, h = 0.35, face = 270 },   -- face: rotacion relativa del objeto

    -- Mostradores. Cada uno tiene una trabajadora (ped de cliente) y una silla
    -- para el jugador. "ox/oy" = silla del jugador; la trabajadora queda enfrente.
    COUNTERS = {
        { name = "Mostrador 1", ox = -2.6, oy = 6.0, clerk = { name = "Marta", skin = 150 } },
        { name = "Mostrador 2", ox = 2.6,  oy = 6.0, clerk = { name = "Lucia", skin = 141 } },
    },
    DESK_DEPTH = 1.55,          -- distancia silla del jugador -> trabajadora

    -- Cola
    TICKET_MAX = 99,            -- los numeros dan la vuelta al llegar aqui
    CALL_TIMEOUT = 60,          -- s para acercarse al mostrador cuando te llaman
    CALL_DELAY = 3,             -- s entre sacar el ticket y que te llamen si no hay cola
    NEXT_DELAY = 4,             -- s entre que se libera un mostrador y llama al siguiente
    TICKET_COOLDOWN = 5,        -- s entre dos tickets del mismo jugador

    -- Tramites (tiempos minimos que el servidor exige antes de aceptar el resultado,
    -- para que nadie se salte la cinematica disparando el evento a mano)
    DNI_MIN_SECONDS = 12,
    JOB_MIN_SECONDS = 3,
    DNI_DUPLICATE_PRICE = 50,   -- el primer DNI es gratis; los duplicados (si lo perdiste) cuestan esto en efectivo
    REQUIRE_DNI_FOR_JOB = true,

    -- Motivos del dispensador
    REASONS = {
        dni = { key = 1, label = "Obtencion de DNI", prefix = "D" },
        job = { key = 2, label = "Obtencion de trabajo", prefix = "T" },
    },

    -- Distancias
    USE_DISTANCE = 1.6,         -- dispensador
    DOOR_DISTANCE = 1.4,        -- puertas
    SHOW_DISTANCE = 3,          -- /mostrardni

    -- Catalogo de ejemplo. Solo se usa si rp_jobs no esta arrancado.
    -- Mismo formato que exports.rp_jobs:getJobList() (ver docs/AGENCIA.md).
    FALLBACK_JOBS = {
        { id = "farmer", name = "Granjero", icon = "🌾",
          description = "Ara, siembra y cosecha los campos de Blueberry con el tractor y vende la cosecha en la cooperativa.",
          pay = "$150 - $300 por cosecha", howTo = "Sal de Los Santos por la autopista hacia el oeste y sigue hasta Blueberry.",
          location = { x = -1060.0, y = -1205.0, z = 129.2 } },
        { id = "garbage", name = "Recolector de basura", icon = "🚛",
          description = "Recorre la ruta con el camion, vacia los contenedores y separa la basura. A veces aparecen cosas de valor.",
          pay = "$20 por contenedor + hallazgos", howTo = "El deposito esta en Willowfield, al sureste de la ciudad.",
          location = { x = 2190.0, y = -1975.0, z = 13.55 } },
        { id = "lumber", name = "Lenador", icon = "🪓",
          description = "Tala arboles en los bosques de Flint County, corta los troncos y cargalos en el camion del aserradero.",
          pay = "$40 por tronco", howTo = "Ve hacia Angel Pine por la carretera de la costa; el aserradero esta a la entrada.",
          location = { x = -1980.0, y = -2430.0, z = 30.6 } },
        { id = "hunter", name = "Cazador", icon = "🦌",
          description = "Rastrea ciervos y jabalies en los bosques, caza con licencia y vende la carne y las pieles.",
          pay = "$60 - $200 por pieza", howTo = "La cabana del cazador esta en Shady Creeks, al pie del Monte Chiliad.",
          location = { x = -1632.0, y = -2236.0, z = 31.5 } },
        { id = "fisher", name = "Pescador", icon = "🎣",
          description = "Pesca desde el muelle o sal en barca. Cada pez tiene su minijuego y los raros valen mucho.",
          pay = "$10 - $400 por pez", howTo = "Ve al muelle de Santa Maria Beach, al sur de Verona.",
          location = { x = 836.0, y = -2058.0, z = 12.87 } },
        { id = "miner", name = "Minero", icon = "⛏️",
          description = "Pica en la cantera de Hunter Quarry, separa los minerales y llevalos a la fundicion.",
          pay = "$30 - $250 por carga", howTo = "La cantera esta en Bone County; sal por el norte de Los Santos hacia Las Venturas.",
          location = { x = 588.0, y = 868.0, z = -42.5 } },
    },
}

-- Calcula la posicion mundial de un offset relativo a ORIGIN
function agencyPoint(ox, oy, z)
    local o = AGENCY.ORIGIN
    local r = math.rad(o.rot)
    -- forward = hacia donde mira la sala; right = 90 grados a la derecha
    local fx, fy = -math.sin(r), math.cos(r)
    local rx, ry = math.cos(r), math.sin(r)
    return o.x + rx * ox + fx * oy, o.y + ry * ox + fy * oy, (z or o.z)
end

-- Silla del jugador y posicion de la trabajadora de un mostrador
function agencyCounterPoints(i)
    local c = AGENCY.COUNTERS[i]
    if not c then return nil end
    local o = AGENCY.ORIGIN
    local px, py = agencyPoint(c.ox, c.oy)
    local cx, cy = agencyPoint(c.ox, c.oy + AGENCY.DESK_DEPTH)
    return {
        seat = { x = px, y = py, z = o.z, rot = o.rot },              -- jugador mira al fondo
        clerk = { x = cx, y = cy, z = o.z, rot = (o.rot + 180) % 360 }, -- trabajadora mira a la entrada
        desk = { x = (px + cx) / 2, y = (py + cy) / 2, z = o.z, rot = o.rot },
    }
end

function agencyFormatTicket(reason, number)
    local r = AGENCY.REASONS[reason]
    return ("%s-%02d"):format(r and r.prefix or "?", number or 0)
end
