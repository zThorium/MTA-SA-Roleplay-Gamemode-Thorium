--[[
    rp_pickupfx / s_config.lua  (compartido; el recurso es solo de cliente)
]]

PICKUPFX = {
    -- Estilo por modelo de pickup. Solo los modelos de esta lista llevan efectos.
    --   color  halo, anillo, chispas y borde del shader
    --   boost  brillo del shader (1 = original)
    --   sparks chispas por segundo (0 = sin chispas)
    --   tint   cuanto se tine el modelo de su color (0 = original, 1 = todo del color; 0.35 por defecto)
    --   scale       tamano de la copia (por defecto CLONE_SCALE; 1 = como el pickup original)
    --   fxScale     tamano de halo, haz y anillos (1 por defecto)
    --   fxDistance  metros a los que se ven los brillos (por defecto FX_DISTANCE)
    --   zOffset     metros que se sube la copia sobre la altura del pickup (0 por defecto)
    STYLES = {
        [1273] = { color = { 70, 255, 120 },  boost = 1.35, sparks = 4 },   -- casa en venta (verde)
        [1318] = { color = { 200, 225, 255 }, boost = 1.30, sparks = 3 },   -- flecha blanca (casa con dueno)
        -- estrella de policia: grande y con brillo visible de lejos, para verla desde un auto
        [1247] = { color = { 255, 210, 60 },  boost = 1.40, sparks = 5, scale = 2.2, fxScale = 2.2, fxDistance = 70,
                   zOffset = 1.0 },
        [1239] = { color = { 255, 205, 60 },  boost = 1.35, sparks = 3 },   -- "i" (tiendas robables)
        [1275] = { color = { 190, 120, 255 }, boost = 1.30, sparks = 3 },   -- camiseta (tiendas de ropa)
        [1212] = { color = { 110, 255, 110 }, boost = 1.30, sparks = 4 },   -- fajo de billetes
    },

    -- Copia animada (como el icono de rp_3dtext)
    CLONE_SCALE  = 0.85,  -- tamano de la copia respecto al pickup original
    SPIN_DEG_S   = 90,    -- giro por segundo
    BOB_HEIGHT   = 0.08,  -- metros que sube y baja al flotar
    BOB_SPEED    = 2.2,
    HIDDEN_DIMENSION = 65000,  -- donde se aparca el pickup original, solo en este cliente

    SCAN_MS      = 1000,  -- cada cuanto se buscan pickups cargados (nunca por fotograma)
    TRACK_DISTANCE   = 150,    -- metros: se cambia el original por la copia
    RELEASE_DISTANCE = 200,    -- metros: se devuelve el original y se quita la copia
    FX_DISTANCE  = 30,    -- metros: mas lejos no se dibuja nada
    SPARK_DISTANCE = 18,  -- metros: chispas solo de cerca

    -- Calidad (PCs de bajos recursos). Arranca segun "Calidad de efectos" de los ajustes de MTA
    -- del jugador (baja/media -> 1/2, alta/muy alta -> 3) y baja sola un nivel si los FPS medios
    -- caen de MIN_FPS durante FPS_WINDOW_MS. Nunca sube sola (sin ir y venir).
    MIN_FPS       = 30,
    FPS_WINDOW_MS = 3000,
    QUALITY = {
        -- 1 bajo: copia animada con shader y anillo; sin chispas, haz, onda ni nucleo
        { maxFx = 5,  animDistance = 25, maxSparks = 0,   sparkRate = 0,   beam = false, wave = false, core = false },
        -- 2 medio: con haz y pocas chispas
        { maxFx = 9,  animDistance = 40, maxSparks = 40,  sparkRate = 0.5, beam = true,  wave = false, core = false },
        -- 3 alto: todo
        { maxFx = 14, animDistance = 60, maxSparks = 120, sparkRate = 1,   beam = true,  wave = true,  core = true },
    },
}
