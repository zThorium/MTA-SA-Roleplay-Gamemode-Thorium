--[[
    rp_seatbelt / s_config.lua
    Ajustes del cinturon de seguridad y de los choques sin cinturon.
    Velocidades en km/h. La "caida" es la velocidad que pierde el vehiculo en el choque.
]]

SEATBELT = {
    KEY = "c",                -- poner / quitar el cinturon (dentro de un coche)
    COOLDOWN = 800,           -- ms entre usos de la tecla

    -- Tipos de vehiculo con cinturon (motos, bicis, barcos y aviones no tienen)
    VEHICLE_TYPES = { ["Automobile"] = true, ["Monster Truck"] = true },

    -- Choques sin cinturon
    LIGHT_DROP = 18,          -- caida minima para un choque leve (rasguno y algo de vida)
    EJECT_DROP = 70,          -- caida minima para salir disparado por el parabrisas
    MEASURE_DELAY = 120,      -- ms tras el golpe para medir cuanta velocidad perdio
    CRASH_COOLDOWN = 1500,    -- ms entre choques evaluados

    LIGHT_DAMAGE = 3,         -- vida que quita un choque leve
    LIGHT_MIN_HEALTH = 20,    -- un choque leve nunca baja la vida de aqui

    -- Salida por el parabrisas
    EJECT = {
        SLOWMO = 0.3,         -- velocidad del juego durante el vuelo (1 = normal)
        FORCE = 0.85,         -- fraccion de la velocidad previa que se lleva el cuerpo
        MAX_SPEED = 1.6,      -- tope de la velocidad de salida (1 = ~180 km/h)
        LIFT = 0.18,          -- empuje hacia arriba
        MIN_FLIGHT = 250,     -- ms reales antes de aceptar el impacto (al despegar)
        MAX_FLIGHT = 6000,    -- ms reales maximos de vuelo
        SERVER_TIMEOUT = 9000, -- si el cliente no avisa del impacto, el servidor lo abate igual
        ANIM_BLOCK = "ped", ANIM_NAME = "EV_dive",
    },

    -- Pantalla tras el impacto
    BLACK_TIME = 2500,        -- ms en negro
    WAKE_TIME = 7000,         -- ms del efecto de abrir los ojos
    SCRATCH_TIME = 2200,      -- ms que dura el rasguno en los bordes
}
