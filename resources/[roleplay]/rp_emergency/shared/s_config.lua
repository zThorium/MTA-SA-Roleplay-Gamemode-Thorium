--[[
    rp_emergency / s_config.lua  (compartido cliente/servidor)
    Emergencias 911. Todos los tiempos en segundos salvo que se indique ms.
]]

EMERGENCY = {
    COMMAND = "911",

    -- Servicios del menu. "enabled" = tiene comportamiento implementado.
    SERVICES = {
        { id = "police",    name = "Policia",   desc = "Solicitar asistencia policial",  icon = "\240\159\154\148", enabled = false },
        { id = "fire",      name = "Bomberos",  desc = "Solicitar asistencia de bomberos", icon = "\240\159\154\146", enabled = false },
        { id = "ambulance", name = "Ambulancia", desc = "Solicitar asistencia medica",  icon = "\240\159\154\145", enabled = true },
    },

    -- Anti-abuso
    CALL_COOLDOWN = 60,        -- s entre llamadas del mismo jugador (tras terminar la anterior)
    MAX_ACTIVE_CALLS = 6,      -- ambulancias simultaneas en todo el servidor

    -- Ambulancia
    AMBULANCE_MODEL = 416,
    PARAMEDIC_SKINS = { 274, 275, 276 },   -- paramedicos de LS
    SPAWN_MIN = 120,           -- m desde el jugador donde aparece (fuera de la vista si se puede)
    SPAWN_MAX = 200,
    SPAWN_REQUEST_TIMEOUT = 10,
    ARRIVE_MAX_DIST = 120,     -- m: el servidor acepta "llego" si la ambulancia esta a menos de esto del jugador
    ENROUTE_TIMEOUT = 240,     -- s: si no llega, se cancela la llamada (recuperacion)
    SEARCH_RADIUS = 45,        -- m alrededor de la ambulancia para buscar abatidos
    LOOK_TIME = 4,             -- s que miran alrededor si no hay abatidos antes de volver
    WALK_TIMEOUT = 20,         -- s: a partir de aqui el paramedico se teletransporta al punto
    WALK_ARRIVE_DIST = 1.4,    -- m al paciente / destino para considerarlo llegado
    CRUISE_SPEED = 62,         -- km/h
    LEAVE_TIME = 18,           -- s alejandose antes de desaparecer
    ARRIVE_RADIUS = 12,        -- m al ultimo punto de la ruta para detenerse

    -- Reanimacion
    REVIVE_TIME = 9,           -- s de RCP por paciente (configurable)
    REVIVE_HEALTH = 40,        -- vida al reanimar
    MAX_PATIENTS = 3,          -- pacientes que atiende una ambulancia por llamada

    -- Traslado de muertos
    LOAD_TIME = 4,             -- s de "colocar en la camilla"
    TREAT_TIME = 6,            -- s de pantalla en negro en el hospital antes de aparecer en la cama
    TREAT_HEALTH = 70,
    PATIENT_SEAT = 3,          -- asiento trasero de la ambulancia
    -- Posicion del paciente mientras lo llevan (camilla simulada): attachElements al paramedico
    CARRY_OFFSET = { 0.0, 0.75, 0.25, 0, 0, 90 },

    -- Contrato con el sistema de abatidos (aun no existe en main, ver docs/EMERGENCIAS.md)
    --   elementData DOWNED_KEY = true      -> jugador abatido, se puede reanimar
    --   elementData DEAD_KEY = true / muerto de MTA -> no reanimable: se traslada al hospital
    --   al reanimar/tratar se dispara en servidor el evento "rp:emergency:revive" con source = jugador
    DOWNED_KEY = "rp:downed",
    DEAD_KEY = "rp:dead",

    -- Hospitales: road = punto de carretera donde para la ambulancia,
    -- door = puerta donde los paramedicos entregan al paciente,
    -- bed = donde reaparece ya tratado. Ajustar en juego.
    HOSPITALS = {
        { name = "All Saints General",
          road = { 1177.6, -1308.0, 13.6 }, door = { 1181.0, -1323.9, 14.0, 90 },
          bed  = { 1177.6, -1323.9, 14.1, 270, 0, 0 } },
        { name = "County General",
          road = { 2034.2, -1416.0, 16.9 }, door = { 2034.0, -1402.6, 17.3, 0 },
          bed  = { 2034.0, -1402.6, 17.3, 180, 0, 0 } },
    },
}
