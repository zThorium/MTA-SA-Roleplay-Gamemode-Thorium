--[[
    rp_gym / s_config.lua (compartido)

    Cada valor lleva su origen (ver docs/GIMNASIO.md):
      [C] confirmado del GTA SA original
      [A] adaptacion propia: el original no documenta el dato (decision del proyecto)

    Las stats van en la escala interna del juego, 0-1000 (1 % = 10 unidades).
]]

GYM = {
    USE_RANGE = 2.5,        -- [A] metros maximos a una maquina o entrenador para usarla (el servidor lo comprueba)
    TRIGGER_RADIUS = 1.4,   -- [A] radio del aviso "Pulsa E"
    GETON_MS = 1800,        -- [A] tiempo de la animacion de subir a la maquina
    GETOFF_MS = 1800,       -- [A] tiempo de la animacion de bajar
    TICK_MS = 250,          -- [A] cada cuanto el servidor recalcula la sesion y avisa al cliente
    APPLY_EVERY = 2,        -- [A] segundos entre guardados de stats durante cinta y bici
    PULSE_MIN_MS = 100,     -- [A] separacion minima entre pulsaciones aceptadas (anti-macro)

    -- Ritmos de cinta y bici [C]: +4 % resistencia, +1 % musculo, -2,5 % grasa cada 14 s.
    -- [A] se toman como el ritmo del nivel 10; los niveles inferiores escalan nivel/10.
    RATE_SECONDS = 14,
    RATE_STAMINA = 40,
    RATE_MUSCLE = 10,
    RATE_FAT = -25,

    -- Pesas, por repeticion completada.
    -- Musculo [C, GTA Wiki]: +0,1 % a +0,9 %; mas con mas peso, menos cuanto mas fuerte ya es CJ, y el
    -- press supera a las mancuernas al mismo nivel de peso. [A] la formula exacta no esta documentada:
    -- ganancia = MIN + (MAX - MIN) x pesoRelativo x (1 - musculoActual/1000), por el factor de la maquina.
    -- (El fallo del original por el que la primera mancuerna de 20 lb daba siempre la ganancia completa
    -- no se reproduce.)
    REP_MUSCLE_MIN = 1,     -- 0,1 %
    REP_MUSCLE_MAX = 9,     -- 0,9 %
    -- Grasa: decision del proyecto -0,5 % por repeticion (el original, segun GTA Wiki, es -0,1 %).
    REP_FAT = -5,

    -- Limite diario [C, fuente unica Grand Theft Wiki]: si en un dia se pierde 40 % de grasa o se gana
    -- 20 % de resistencia o de musculo, hay que esperar 12 horas. [A] "un dia" = ventana de 24 h
    -- desde el primer entrenamiento.
    DAY_SECONDS = 24 * 3600,
    LIMIT_FAT = 400,
    LIMIT_STAMINA = 200,
    LIMIT_MUSCLE = 200,
    LOCK_SECONDS = 12 * 3600,

    -- Entrenadores
    MIN_MUSCLE = 350,       -- [C, fuente unica] 35 % de musculo para pelear con un entrenador
    CONFIRM_MS = 8000,      -- [A] tiempo para confirmar el combate pulsando E otra vez
    TRAINER_WIN_HP = 20,    -- [A] el entrenador cae al bajar de esta vida
    PLAYER_LOSE_HP = 20,    -- [A] el jugador pierde al bajar de esta vida
    TRAINER_HIT_MS = { 650, 1100 },   -- [A] intervalo entre golpes del entrenador
}

-- Maquinas. Los modelos y el desplazamiento Z son [A]: ajustar en juego si la maquina se ve mal colocada.
-- seat = { dx, dy, dz, giro }: mueve/gira la maquina respecto a donde estaba el admin al crearla
-- (dx adelante-derecha, dy adelante segun el rumbo del admin; metros y grados). Tras cambiarlo: restart rp_gym.
GYM_KINDS = {
    treadmill = {
        label = "Cinta de correr", alias = "cinta", model = 2627, zOffset = -1.0, seat = { 0, 2.0, 0, 0 }, levels = 10,
        getonMs = 2500, getoffMs = 3400,       -- duracion real de gym_tread_geton / getoff (IFP)   -- seat ajustado en juego
        speedBase = 3, speedStep = 1.0,        -- [A] km/h = base + step * nivel
        drainBase = 6, drainStep = 2.4,        -- [A] % de potencia que se pierde por segundo
        pulseGain = 12,                        -- [A] % de potencia por pulsacion alterna
        distStat = 28, timeStat = 44,          -- stats de GTA: DIST_TREADMILL, LONGEST_TREADMILL_TIME
        geton = { "GYMNASIUM", "gym_tread_geton" }, getoff = { "GYMNASIUM", "gym_tread_getoff" },
        fall = { "GYMNASIUM", "gym_tread_falloff" }, tired = { "GYMNASIUM", "gym_tread_tired" },
        -- Las de PED (walk/run) llevan desplazamiento incorporado y el personaje "avanza" de A a B; las gym_tread_*
        -- estan hechas para correr en el sitio, como en el juego original. { hasta nivel, animacion, bloque }
        loops = { { 3, "gym_tread_walk", "GYMNASIUM" }, { 7, "gym_tread_jog", "GYMNASIUM" }, { 10, "gym_tread_sprint", "GYMNASIUM" } },
    },
    bike = {
        label = "Bicicleta estatica", alias = "bici", model = 2630, zOffset = -1.0, seat = { 0.5, 0.5, 0, 180 }, levels = 10,   -- seat ajustado en juego
        getonMs = 1700, getoffMs = 1700,       -- gym_bike_geton / getoff
        speedBase = 8, speedStep = 1.5,
        drainBase = 6, drainStep = 2.4,
        pulseGain = 12,
        distStat = 29, timeStat = 45,          -- DIST_EXCERSISE_BIKE, LONGEST_EXCERSISE_BIKE_TIME
        geton = { "GYMNASIUM", "gym_bike_geton" }, getoff = { "GYMNASIUM", "gym_bike_getoff" },
        fall = { "GYMNASIUM", "gym_bike_falloff" }, tired = { "GYMNASIUM", "gym_bike_slow" },
        loops = { { 3, "gym_bike_slow" }, { 6, "gym_bike_pedal" }, { 8, "gym_bike_fast" }, { 10, "gym_bike_faster" } },
    },
    bench = {
        label = "Press de banca", alias = "banca", model = 2629, zOffset = -1.0, seat = { 0, 1.0, 0, 0 },   -- seat ajustado en juego
        getonMs = 5400, getoffMs = 7000,       -- gym_bp_geton dura 5,3 s; gym_bp_getoff 8,7 s (se recorta a 7)
        -- Barra apoyada sobre el banco antes de empezar (se oculta al entrenar: pasa a las manos). Posicion a ajustar con /ajustarextra
        extra = { { model = 2913, dx = -0.40, dy = 0.53, dz = 1.00, rx = 0, ry = 90, rz = 0 } },   -- ajustado en juego
        weights = { 40, 60, 80, 100, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300, 320 },   -- [C] 40-320 lb, [A] paso de 20
        gainBase = 18, gainHeavy = 10,         -- [A] % por pulsacion = base - heavy * (peso relativo)
        decayBase = 10, decayHeavy = 25,       -- [A] % que baja por segundo = base + heavy * (peso relativo)
        muscleFactor = 1.0,                    -- [A] el press supera a las mancuernas al mismo peso
        recordStat = 46,                       -- HEAVIEST_WEIGHT_BENCH_PRESS
        geton = { "BENCHPRESS", "gym_bp_geton" }, getoff = { "BENCHPRESS", "gym_bp_getoff" },
        rest = { "BENCHPRESS", "gym_bp_down" }, up = { "BENCHPRESS", "gym_bp_up_smooth" },
        -- Objetos pegados a un hueso del personaje durante la sesion (hueso 12 = mano derecha, 11 = izquierda).
        -- off = { x, y, z, rx, ry, rz }: son estimaciones, se afinan en juego con /ajustarprop
        props = { { model = 2913, bone = 12, off = { -0.80, -0.01, 0.09, 90, 90, 0 } } },   -- ajustado en juego; 2913 = kmb_bpress, la barra con discos
    },
    dumbbells = {
        label = "Pesas", alias = "pesas", model = 2916, zOffset = -1.0, seat = { 0, 1.0, 0.1, 0 },   -- seat ajustado en juego
        -- Segunda mancuerna en el suelo (par): dx/dy en metros respecto a la primera, segun el rumbo. Se oculta mientras se entrena.
        hideMain = true,   -- al entrenar tambien se oculta la mancuerna principal
        extra = { { model = 2915, dx = 0.35, dy = 0, dz = 0, rz = 0 } },   -- 2916 = kmb_dumbbell (2913 es kmb_bpress, la barra del press)
        getonMs = 3200, getoffMs = 3200,       -- gym_free_pickup / putdown
        weights = { 20, 30, 40, 50, 60, 70, 80, 90, 100, 110 },   -- [C] 20-110 lb, [A] paso de 10
        gainBase = 18, gainHeavy = 10,
        decayBase = 10, decayHeavy = 25,
        muscleFactor = 0.8,
        recordStat = 47,                       -- HEAVIEST_WEIGHT_DUMBELLS
        geton = { "FREEWEIGHTS", "gym_free_pickup" }, getoff = { "FREEWEIGHTS", "gym_free_putdown" },
        rest = { "FREEWEIGHTS", "gym_free_down" }, up = { "FREEWEIGHTS", "gym_free_a" }, up2 = { "FREEWEIGHTS", "gym_free_b" },
        props = { { model = 3072, bone = 11, off = { 0, 0, 0, 90, 90, 0 } }, { model = 3071, bone = 12, off = { 0, 0, 0, 90, 90, 0 } } },   -- kmb_dumbbell_L / _R
    },
}

GYM_REP_LOCK_MS = 1500       -- [A] tiempo de la repeticion (la barra no se puede llenar mientras tanto)
GYM_IDLE_FAIL_MS = 5000      -- [A] con la barra vacia tanto tiempo, se suelta el peso y se termina la serie
GYM_GAUGE_START = 50         -- [A] potencia inicial de cinta y bici
GYM_GRACE_MS = 2000          -- [A] margen al empezar antes de poder caerse

-- Estilos de combate. id = setPedFightingStyle (MTA wiki). Kickboxing = KNEE_HEAD (7) es una inferencia
-- sin confirmar. Las skins de los entrenadores son [A].
GYM_STYLES = {
    boxing     = { id = 5, name = "Boxeo",       column = "boxing",     skin = 80,  ring = 7.0, label = "Entrenador de boxeo" },
    kungfu     = { id = 6, name = "Kung Fu",     column = "kungfu",     skin = 49,  ring = 3.5, label = "Maestro de kung fu" },   -- esterilla pequena: salir = rendirse
    kickboxing = { id = 7, name = "Kickboxing",  column = "kickboxing", skin = 81,  ring = 7.0, label = "Entrenador de kickboxing" },
}
GYM_STANDARD_STYLE = 4

-- Nombres de comando en espanol -> clave interna
GYM_STYLE_ALIAS = { boxeo = "boxing", kungfu = "kungfu", kickboxing = "kickboxing" }

-- Gimnasios fijos con el interior original de GTA SA. Las maquinas van donde estan en el mapa del juego
-- (gta_int.img, gen_int3_stream0.ipl, leido con scripts/leer-ipl-interior.ps1): x, y, z, rz son los del
-- objeto. native = true usa el objeto que ya trae el interior (no se crea otro encima).
-- Sus ids empiezan en GYM_FIXED_ID para no chocar con las maquinas que crean los admins en la BD.
GYM_FIXED_ID = 900000
GYM_FIXED = {
    {
        key = "ganton", name = "Gimnasio de Ganton", blip = 54,
        door = { x = 2228.929, y = -1721.508, z = 13.563 },                         -- puerta, en la calle
        outside = { x = 2227.35, y = -1722.37, z = 13.55, rot = 118.6 },           -- donde sales (frente a la puerta)
        interior = 5, dimension = 0,
        inside = { x = 772.11, y = -3.89, z = 1000.73, rot = 0 },                   -- donde entras [C]
        exit = { x = 772.06, y = -5.55, z = 1000.73 },                              -- marcador de salida, junto a la puerta
        machines = {
            { kind = "treadmill", x = 773.492, y = -2.602, z = 999.672, rz = 180, native = true },
            { kind = "bench",     x = 773.898, y = 1.453,  z = 999.672, rz = 90,  native = true },
            { kind = "dumbbells", x = 772.992, y = 5.383,  z = 999.772, rz = 0 },   -- mancuernas sobre la colchoneta (gym_mat1)
            { kind = "bike",      x = 772.172, y = 9.414,  z = 999.680, rz = 90,  native = true },
        },
        -- [A] junto al ring, mirando hacia el: el juego no guarda la posicion del entrenador en el mapa
        trainer = { style = "boxing", x = 768.2, y = 5.4, z = 1000.72, rot = 90 },
    },
}
