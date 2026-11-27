--[[
    rp_pickupfx / s_config.lua  (compartido; el recurso es solo de cliente)
]]

PICKUPFX = {
    -- Estilo por modelo de pickup. Solo los modelos de esta lista llevan efectos.
    --   color  halo, anillo, chispas y borde del shader
    --   boost  brillo del shader (1 = original)
    --   sparks chispas por segundo (0 = sin chispas)
    --   tint   cuanto se tine el modelo de su color (0 = original, 1 = todo del color; 0.35 por defecto)
    STYLES = {
        [1273] = { color = { 70, 255, 120 },  boost = 1.35, sparks = 4 },   -- casa en venta (verde)
        [1318] = { color = { 200, 225, 255 }, boost = 1.30, sparks = 3 },   -- flecha blanca (casa con dueno)
        [1247] = { color = { 255, 210, 60 },  boost = 1.40, sparks = 5 },   -- estrella de policia
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
    ANIM_DISTANCE    = 60,     -- metros: mas lejos la copia queda quieta
    FX_DISTANCE  = 30,    -- metros: mas lejos no se dibuja nada
    SPARK_DISTANCE = 18,  -- metros: chispas solo de cerca
    MAX_FX       = 14,    -- como mucho, efectos de los N pickups mas cercanos
    MAX_SPARKS   = 120,   -- tope total de chispas vivas
}
