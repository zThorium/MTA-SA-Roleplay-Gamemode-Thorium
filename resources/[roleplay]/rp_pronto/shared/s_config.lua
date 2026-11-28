--[[
    rp_pronto · configuración compartida

    Bencinera Copec con tienda Pronto Express en Idlewood (Los Santos), en el lugar de la gasolinera original.
    En GTA la tienda, el techo de los surtidores, el letrero de precios y el cartel «Car Wash» son un solo modelo
    (laepetrol1a), así que se quita entero y se rehace: tienda con interior recorrible, túnel de lavado, techo Copec,
    isla y tótem de precios. Se conservan el suelo (laeroad24), los surtidores (washgaspump), los cepillos del
    lavado y los cables (carwashalphas_lae) y la expendedora Sprunk de la fachada (la usa rp_vending).

    Modelos generados con tools/build_pronto.py (Blender + DragonFF). Las piezas «native» solo guardan el nombre de
    las texturas del juego: el cliente las apunta al TXD barrio1_lae (el de la gasolinera) con engineSetModelTXDID.
    Los muebles del interior (góndolas, refrigeradores, cajas, café) son modelos del juego: shared/s_props.lua.
]]

local BOUNDS = "models/pronto_bounds.col"

PRONTO = {
    -- Todos los modelos están centrados aquí (ORIGIN de build_pronto.py), sin giro
    ORIGIN = { x = 1921.0, y = -1776.0, z = 12.55 },

    DRAW_DISTANCE = 300,          -- piezas de detalle (por debajo del límite de 325 de MTA, con fundido)
    LOD_DRAW_DISTANCE = 325,      -- el LOD usa 5 veces este valor
    NATIVE_TXD_FROM = 5489,       -- laeroad24 (el suelo de la gasolinera, se queda): su TXD es barrio1_lae

    -- Vidrio: no es un modelo. Sus triángulos (client/c_glass_data.lua, generado por build_pronto.py) se dibujan cada
    -- cuadro con dxDrawPrimitive3D después del mundo (client/c_glass.lua). Ver la skill mapeado-3d.
    GLASS = {
        DAY = { 60, 80, 90, 85 },       -- r, g, b, alfa: vidrio claro con un leve tinte
        NIGHT = { 25, 28, 34, 70 },     -- oscuro: de noche un tinte claro «lava» el interior y lo hace brillar
        DAWN = { 5, 7 },                -- de noche a día entre estas horas
        DUSK = { 19, 21 },              -- de día a noche
        DRAW_DISTANCE = 150,            -- metros desde el centro de la tienda
    },

    PARTS = {
        { key = "shop",     dff = "models/pronto_shop.dff",     col = "models/pronto_shop.col",   native = true },
        { key = "shop_x",   dff = "models/pronto_shop_x.dff",   txd = "models/pronto.txd", col = BOUNDS, noCollision = true },
        { key = "canopy",   dff = "models/pronto_canopy.dff",   col = "models/pronto_canopy.col", native = true },
        { key = "canopy_x", dff = "models/pronto_canopy_x.dff", txd = "models/pronto.txd", col = BOUNDS, noCollision = true },
    },
    -- Un LOD por pieza con colisión: GTA dibuja el LOD de una pieza cuando esa pieza queda fuera de cuadro; con un LOD
    -- único ligado a la tienda, el del techo de surtidores aparecía encima al mirarlo de cerca.
    LODS = {
        { dff = "models/pronto_lod.dff",        txd = "models/pronto_lod.txd", col = BOUNDS, parent = "shop" },
        { dff = "models/pronto_lod_canopy.dff", txd = "models/pronto_lod.txd", col = BOUNDS, parent = "canopy" },
    },

    -- Caja interior de la tienda (para pruebas y para quien necesite saber si un punto queda dentro)
    SHOP_BOX = { x0 = 1914.4, x1 = 1927.9, y0 = -1785.8, y1 = -1766.6, z0 = 12.63, z1 = 15.93 },
    -- Puerta de entrada (fachada este, mira a los surtidores)
    DOOR = { x = 1928.6, y = -1776.4, z = 12.63 },

    -- Mapa original que se quita: { modelo, radio, x, y, z }
    REMOVE = {
        { 5409, 5, 1918.852, -1776.328, 16.977 },   -- laepetrol1a: tienda, techo de surtidores, letreros
        { 5535, 5, 1918.852, -1776.328, 16.977 },   -- LODpetrol1a01: su LOD
    },
}
