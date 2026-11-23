--[[
    rp_backpacks / s_config.lua (compartido)
    Cada mochila es un item de rp_inventory (mismo id). Al usarla se equipa en la espalda.
      capacity  kg que caben dentro
      weight    kg que pesa la mochila vacia (se suma a la carga del personaje)
      model     modelo GTA SA (el unico de vanilla es 3026 = para_pack)
      look.size { alto, fondo, ancho }: escala en los ejes del modelo (X = alto, Y = fondo, Z = ancho)
      look.shader receta de fx/backpack.fx (ver la cabecera del .fx):
                  body/accent/dark = colores, pattern = { nylon, ripstop, camuflaje, lona },
                  tile, bandV/bandW = banda de contraste, sheen, reflect, seed

    Geometria del modelo 3026 (medida del DFF): X 0..0.474 (alto, el origen esta en la base y las correas
    en el extremo +X), Y -0.15..0.22 (la caja va en -Y, las correas salen hacia +Y = pecho), Z -0.155..0.155
    (ancho, centrado). Por eso la rotacion para ponerla de pie con las correas al pecho es ry = -90.
]]
BACKPACKS = {
    bp_small = {
        capacity = 5, weight = 0.4, model = 3026,
        look = {
            size = { 0.60, 0.90, 0.80 },
            shader = { body = { 0.17, 0.70, 0.64 }, accent = { 1.00, 0.82, 0.25 }, dark = { 0.05, 0.25, 0.23 },
                       pattern = { 1.0, 0.0, 0.0, 0.0 }, tile = 48, bandV = 0.80, bandW = 0.10, sheen = 0.9, reflect = 0.0, seed = 0 },
        },
    },
    bp_school = {
        capacity = 10, weight = 0.6, model = 3026,
        look = {
            size = { 0.80, 1.00, 0.95 },
            shader = { body = { 0.17, 0.27, 0.62 }, accent = { 0.89, 0.27, 0.30 }, dark = { 0.06, 0.09, 0.25 },
                       pattern = { 0.4, 0.9, 0.0, 0.0 }, tile = 40, bandV = 0.25, bandW = 0.12, sheen = 0.6, reflect = 0.6, seed = 0 },
        },
    },
    bp_hiking = {
        capacity = 20, weight = 1.2, model = 3026,
        look = {
            size = { 1.00, 1.25, 1.10 },
            shader = { body = { 0.91, 0.47, 0.18 }, accent = { 0.17, 0.36, 0.22 }, dark = { 0.35, 0.16, 0.06 },
                       pattern = { 0.0, 1.0, 0.0, 0.3 }, tile = 36, bandV = 0.22, bandW = 0.22, sheen = 0.3, reflect = 0.0, seed = 0 },
        },
    },
    bp_tactical = {
        capacity = 30, weight = 1.8, model = 3026,
        look = {
            size = { 0.95, 1.25, 1.20 },
            shader = { body = { 0.29, 0.34, 0.21 }, accent = { 0.58, 0.52, 0.36 }, dark = { 0.10, 0.13, 0.08 },
                       pattern = { 0.5, 0.0, 1.0, 0.0 }, tile = 44, bandV = 0.0, bandW = 0.0, sheen = 0.0, reflect = 0.0, seed = 1.7 },
        },
    },
    bp_expedition = {
        capacity = 45, weight = 2.5, model = 3026,
        look = {
            size = { 1.15, 1.30, 1.30 },
            shader = { body = { 0.19, 0.21, 0.26 }, accent = { 0.96, 0.72, 0.10 }, dark = { 0.06, 0.07, 0.09 },
                       pattern = { 0.0, 0.2, 0.0, 1.0 }, tile = 30, bandV = 0.50, bandW = 0.05, sheen = 0.2, reflect = 1.0, seed = 0 },
        },
    },
}

BACKPACK_BONE = 3          -- columna (hueso 3 de bone_attach; sus ejes: X = derecha, Y = delante, Z = arriba)
BACKPACK_MODEL_HEIGHT = 0.474   -- alto del modelo sin escalar (X)
-- x, y, z, rx, ry, rz relativos al hueso. z es la altura del BORDE SUPERIOR de la mochila sobre el hueso:
-- la base se calcula como z - 0.474 * alto, asi todas las mochilas llegan a la misma altura de hombros.
-- y es donde queda la cara que toca la espalda (la caja crece hacia atras desde ahi).
-- Ajustable en vivo con /mochilaoffset (admin).
BACKPACK_OFFSET = { 0, -0.14, 0.25, 0, -90, 0 }
