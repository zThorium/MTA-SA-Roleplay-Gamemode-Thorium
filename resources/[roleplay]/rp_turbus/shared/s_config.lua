--[[
    rp_turbus · configuración compartida

    Terminal Turbus en Unity Station (El Corona, Los Santos). Reemplaza el edificio original de la estación y su
    estacionamiento; conserva el suelo, las vías y las escaleras de los andenes del tren (rp_train sale de aquí)
    y el primer punto de aparición de los personajes (rp_characters), que queda en la explanada de la entrada.

    Modelos generados con tools/build_terminal.py (Blender + DragonFF). Las piezas «native» solo guardan el nombre
    de las texturas del juego: el cliente las apunta al TXD railway_las (el de las escaleras de Unity, modelo 4881).
]]

-- COL que solo da los límites a las piezas sin colisión: GTA recorta cada modelo con los límites de su COL y,
-- sin él, heredan el del modelo base (1 m) y desaparecen al acercarse. En esas piezas la colisión va desactivada.
local BOUNDS = "models/turbus_bounds.col"

TURBUS = {
    -- Todos los modelos están centrados aquí (ORIGIN de build_terminal.py), sin giro
    ORIGIN = { x = 1768.0, y = -1903.0, z = 12.58 },

    DRAW_DISTANCE = 300,          -- piezas de detalle (por debajo del límite de 325 de MTA, con fundido)
    LOD_DRAW_DISTANCE = 325,      -- el LOD usa 5 veces este valor
    NATIVE_TXD_FROM = 4881,       -- uninstps_LAS01: su TXD es railway_las (hormigón, baldosa, chapa)
    -- Vidrio: no es un modelo. Sus triángulos (client/c_glass_data.lua, generado por build_terminal.py) se dibujan cada
    -- cuadro con dxDrawPrimitive3D después del mundo (client/c_glass.lua). Como modelo, GTA no garantiza el orden entre
    -- un objeto con alfa y los edificios: el vidrio tapaba el interior o el interior lo borraba según la cámara.
    GLASS = {
        DAY = { 70, 100, 105, 95 },     -- r, g, b, alfa: verde-gris translúcido
        NIGHT = { 150, 140, 110, 70 },  -- cálido y más claro: el interior está encendido
        DAWN = { 5, 7 },                -- de noche a día entre estas horas
        DUSK = { 19, 21 },              -- de día a noche
        DRAW_DISTANCE = 250,            -- metros desde el centro del terminal
    },

    -- asObject = true crea esa pieza con createObject en vez de createBuilding (respaldo; hoy ninguna lo usa:
    -- como objeto GTA le aplica luz dinámica de faroles y focos de autos).
    PARTS = {
        { key = "hall",     dff = "models/turbus_hall.dff",     col = "models/turbus_hall.col",   native = true },
        { key = "hall_x",   dff = "models/turbus_hall_x.dff",   txd = "models/turbus.txd", col = BOUNDS, noCollision = true },
        { key = "canopy",   dff = "models/turbus_canopy.dff",   col = "models/turbus_canopy.col", native = true },
        { key = "canopy_x", dff = "models/turbus_canopy_x.dff", txd = "models/turbus.txd", col = BOUNDS, noCollision = true },
    },
    LOD = { dff = "models/turbus_lod.dff", txd = "models/turbus_lod.txd", col = BOUNDS, parent = "hall" },

    -- Caja del hall de vidrio (para pruebas y para quien necesite saber si un punto queda dentro)
    HALL_BOX = { x0 = 1729.5, x1 = 1755.5, y0 = -1939.0, y1 = -1866.5, z0 = 12.70, z1 = 22.1 },

    -- Mapa original que se quita: { modelo, radio, x, y, z }
    REMOVE = {
        { 5033, 5, 1745.203, -1882.852, 26.141 },   -- unmainstat_LAS: edificio de la estación
        { 5055, 5, 1745.203, -1882.852, 26.141 },   -- lodainstat_LAS: su LOD
        { 5024, 5, 1748.844, -1883.031, 14.188 },   -- snpedtee_LAS: reloj, letrero y detalles con alpha del edificio
        { 5083, 5, 1748.844, -1883.031, 14.188 },   -- alphbrk1_las: más detalles con alpha del edificio
        { 673, 1, 1727.195, -1930.898, 11.445 },    -- árboles pegados a la cristalera oeste
        { 673, 1, 1727.195, -1916.305, 11.445 },
        { 673, 1, 1727.195, -1908.094, 11.445 },
        { 673, 1, 1727.195, -1893.156, 11.445 },
        { 1226, 1, 1774.758, -1931.313, 16.375 },   -- faroles donde ahora va el andén (los reemplaza la marquesina)
        { 1226, 1, 1774.758, -1901.539, 16.375 },
    },

    -- Props nativos del juego: { modelo, x, y, z, rotZ }
    PROPS = {
        -- conos en el borde de los andenes, entre los buses (como en el terminal)
        { 1238, 1775.6, -1896.0, 12.70, 0 }, { 1238, 1775.6, -1904.0, 12.70, 0 }, { 1238, 1775.6, -1912.0, 12.70, 0 },
        { 1238, 1775.6, -1920.0, 12.70, 0 }, { 1238, 1775.6, -1928.0, 12.70, 0 }, { 1238, 1775.6, -1936.0, 12.70, 0 },
        { 1238, 1782.0, -1887.0, 12.70, 0 }, { 1238, 1790.0, -1887.0, 12.70, 0 }, { 1238, 1798.0, -1887.0, 12.70, 0 },
        { 1238, 1806.0, -1887.0, 12.70, 0 },
        -- bancas en la explanada de la entrada, a los lados (el centro queda libre para el punto de aparición)
        { 1280, 1733.0, -1861.9, 12.94, 0 }, { 1280, 1752.0, -1861.9, 12.94, 0 },
    },
}
