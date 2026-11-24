--[[
    rp_furniture / s_catalog.lua  (compartido)
    Catalogo de muebles. Todo sale de los modelos de interior de GTA SA (props.ide / props2.ide).

    IMPORTANTE: la base de datos guarda la CLAVE (key), nunca el ID de modelo. Nunca cambies ni
    reutilices una clave ya publicada; para cambiar el modelo de un mueble, cambia solo su `model`.

    Campos de cada mueble:
      key     clave estable                 model  ID de modelo
      name    nombre visible                cat    categoria (ver FURN_CATEGORIES)
      price   precio en $                   w      peso para el limite de objetos (por defecto 1)
      act     interaccion (ver server/s_interact.lua): sleep, sit, storage, light, tv, hifi, sink, toilet, bath
      wall    true = se cuelga de la pared  struct true = pieza de estructura (escala ampliada)
      sx,sy,sz  escala por defecto
]]

FURN_CATEGORIES = {
    { id = "sala",        name = "Sala",           icon = "🛋️" },
    { id = "comedor",     name = "Comedor",        icon = "🍽️" },
    { id = "cocina",      name = "Cocina",         icon = "🍳" },
    { id = "dormitorio",  name = "Dormitorio",     icon = "🛏️" },
    { id = "bano",        name = "Baño",           icon = "🚿" },
    { id = "oficina",     name = "Oficina",        icon = "💼" },
    { id = "electro",     name = "Electrónica",    icon = "📺" },
    { id = "luces",       name = "Luces",          icon = "💡" },
    { id = "decoracion",  name = "Decoración",     icon = "🖼️" },
    { id = "ocio",        name = "Ocio y juegos",  icon = "🎰" },
    { id = "estructura",  name = "Estructura",     icon = "🧱" },
}

FURN_ITEMS = {}          -- [key] = definicion
FURN_ORDER = {}          -- lista de claves en orden de catalogo
FURN_BY_CAT = {}         -- [cat] = { key, ... }
for _, c in ipairs(FURN_CATEGORIES) do FURN_BY_CAT[c.id] = {} end

local function add(cat, key, model, name, price, opts)
    assert(not FURN_ITEMS[key], "clave de mueble repetida: " .. key)
    local it = { key = key, model = model, name = name, cat = cat, price = price, w = 1 }
    if opts then for k, v in pairs(opts) do it[k] = v end end
    FURN_ITEMS[key] = it
    FURN_ORDER[#FURN_ORDER + 1] = key
    local list = FURN_BY_CAT[cat]
    list[#list + 1] = key
end

-- Serie: add varios modelos con el mismo prefijo ("Sofa", "sofa") y precio
local function series(cat, prefix, label, ids, price, opts, startAt)
    for i, model in ipairs(ids) do
        add(cat, ("%s_%d"):format(prefix, i + (startAt or 0)), model, ("%s %d"):format(label, i + (startAt or 0)), price, opts)
    end
end

----------------------------------------------------------------
-- SALA
----------------------------------------------------------------
series("sala", "sofa_eco",    "Sofa economico",   { 1763, 1764, 1768, 1756, 1757 }, 380,  { act = "sit" })
series("sala", "sofa_medio",  "Sofa medio",       { 1766, 1760 },                   720,  { act = "sit" })
series("sala", "sofa_lujo",   "Sofa de lujo",     { 1753, 1761, 2290 },             1450, { act = "sit" })
series("sala", "sillon_eco",  "Sillon economico", { 1759, 1765, 1769, 1758 },       190,  { act = "sit" })
series("sala", "sillon_medio","Sillon medio",     { 1767, 1755 },                   340,  { act = "sit" })
series("sala", "sillon_lujo", "Sillon de lujo",   { 1754, 1762, 2291, 2292 },       620,  { act = "sit" })
series("sala", "sofa_casino", "Sofa clasico",     { 1702, 1703, 1706, 1709 },       900,  { act = "sit" })
add("sala", "sillon_facil",   1735, "Sillon orejero",     260, { act = "sit" })
add("sala", "mecedora",       2096, "Mecedora",           310, { act = "sit" })
add("sala", "puf",            2295, "Puf",                120, { act = "sit" })
add("sala", "reposapies_1",   1746, "Reposapies",         90)
add("sala", "reposapies_2",   2293, "Reposapies de lujo", 140)
series("sala", "mesa_centro_eco",   "Mesa de centro economica", { 1813, 1815, 1816, 1820, 1821, 2234 }, 90)
series("sala", "mesa_centro_media", "Mesa de centro media",     { 1814, 1817, 1823, 2082, 2083, 2235 }, 170)
series("sala", "mesa_centro_lujo",  "Mesa de centro de lujo",   { 1818, 1819, 1822, 2081, 2126, 2236 }, 320)
add("sala", "estante_libros", 1742, "Biblioteca",          340)
add("sala", "estante_medio",  1744, "Estante",             210)
add("sala", "mueble_tv_eco",  2093, "Mueble de TV economico", 180)
add("sala", "mueble_tv_med",  2091, "Mueble de TV medio",      310)
series("sala", "mueble_bajo", "Aparador", { 1740, 1741, 2088, 2095, 1743, 2084, 2087, 2078, 2089, 2092, 2094, 2306, 2307 }, 230)

----------------------------------------------------------------
-- COMEDOR
----------------------------------------------------------------
series("comedor", "mesa_eco",   "Mesa de comedor economica", { 2115, 1770, 2109, 2110, 2111, 2116 }, 220)
series("comedor", "mesa_media", "Mesa de comedor media",     { 2030, 2031, 2032, 1737, 2112, 2119 }, 420)
series("comedor", "mesa_lujo",  "Mesa de comedor de lujo",   { 2029, 2080, 2085, 2086, 2117, 2118, 2357 }, 780)
series("comedor", "silla_eco",   "Silla economica", { 2121 }, 55, { act = "sit" })
series("comedor", "silla_media", "Silla media",     { 1811, 2120, 2125 }, 95, { act = "sit" })
series("comedor", "silla_lujo",  "Silla de lujo",   { 1739, 2079, 2122, 2123, 2124, 2310 }, 160, { act = "sit" })
add("comedor", "mesa_sillas_1", 1825, "Mesa con sillas", 460, { w = 2 })
add("comedor", "mesa_simple",   1826, "Mesa sencilla",   150)
add("comedor", "taburete_bar",  1805, "Taburete alto",    70, { act = "sit" })
add("comedor", "taburete_bar_2",2350, "Taburete de bar",  85, { act = "sit" })
add("comedor", "silla_plegable",1810, "Silla plegable",   30, { act = "sit" })

----------------------------------------------------------------
-- COCINA
----------------------------------------------------------------
series("cocina", "nevera", "Nevera", { 2127, 2131, 2147 }, 520, { act = "storage", storage = "food" })
add("cocina", "nevera_fina", 1780, "Nevera delgada", 420, { act = "storage", storage = "food" })
series("cocina", "cocina_gas", "Cocina", { 2135, 2144, 2170, 2294, 2339 }, 380)
series("cocina", "fregadero_cocina", "Fregadero de cocina", { 2130, 2132, 2136, 2150, 2336 }, 260, { act = "sink" })
series("cocina", "mueble_cocina", "Mueble de cocina", { 2129, 2137, 2138, 2139, 2142, 2143, 2148, 2151, 2152, 2154, 2155, 2156, 2157, 2159, 2160, 2334, 2335, 2158, 2133, 2134, 2141, 2145, 2153, 2304, 2305, 2338, 2341 }, 210)
series("cocina", "alacena", "Alacena alta", { 2128, 2140 }, 240)
series("cocina", "lavadora", "Lavadora", { 2303, 2337, 2340, 2018 }, 340)
add("cocina", "microondas", 2149, "Microondas",     120)
add("cocina", "carrito",    2146, "Carrito de cocina", 80)
add("cocina", "cocina_ind_1", 1777, "Cocina industrial", 600)
add("cocina", "dispensador_agua", 1808, "Dispensador de agua", 160, { act = "sink" })

----------------------------------------------------------------
-- DORMITORIO
----------------------------------------------------------------
series("dormitorio", "cama_eco",   "Cama economica", { 1793, 1794, 1796, 1800, 1812, 2302 }, 260, { act = "sleep", w = 2 })
series("dormitorio", "cama_media", "Cama media",     { 1725, 1745, 1799, 1802, 1803, 1804, 2300, 2301 }, 520, { act = "sleep", w = 2 })
series("dormitorio", "cama_lujo",  "Cama de lujo",   { 1795, 1797, 1798, 1801, 2090, 2298, 2299 }, 1100, { act = "sleep", w = 2 })
add("dormitorio", "litera",        1771, "Litera",   420, { act = "sleep", w = 2 })
series("dormitorio", "cama_hotel", "Cama de hotel", { 2563, 2564, 2565, 2566, 2575 }, 480, { act = "sleep", w = 2 })
add("dormitorio", "cama_hotel_s",  2571, "Cama individual", 300, { act = "sleep", w = 2 })
add("dormitorio", "cama_hotel_s2", 2572, "Cama individual 2", 300, { act = "sleep", w = 2 })
add("dormitorio", "dormitorio_1",  2323, "Juego de dormitorio", 900, { act = "sleep", w = 3 })
series("dormitorio", "comoda", "Comoda", { 2562, 2568, 2569, 2570, 2573, 2574, 2576 }, 240, { act = "storage", storage = "wardrobe" })
series("dormitorio", "mesita", "Mesita de noche", { 2020, 2021, 2331, 2333, 2328, 2329 }, 110, { act = "storage", storage = "wardrobe" })
add("dormitorio", "armario_1", 2025, "Armario", 380, { act = "storage", storage = "wardrobe" })

----------------------------------------------------------------
-- BAÑO
----------------------------------------------------------------
series("bano", "inodoro", "Inodoro", { 2514, 2521, 2525, 2528, 2738 }, 180, { act = "toilet" })
series("bano", "lavabo",  "Lavabo",  { 2515, 2518, 2523, 2524, 2739 }, 150, { act = "sink" })
series("bano", "banera",  "Banera",  { 2516, 2519, 2522, 2526, 2097 }, 520, { act = "bath", w = 2 })
series("bano", "ducha",   "Ducha",   { 2517, 2520, 2527 }, 340, { act = "bath" })
add("bano", "jabonera",   2741, "Dispensador de jabon", 40, { wall = true })
add("bano", "secador_manos", 2742, "Secador de manos", 60, { wall = true })

----------------------------------------------------------------
-- OFICINA
----------------------------------------------------------------
series("oficina", "escritorio", "Escritorio", { 1998, 1999, 2008, 2009, 2162, 2165, 2166, 2169, 2171, 2172, 2173, 2174, 2175, 2180, 2181, 2182, 2183, 2184, 2185, 2193, 2198, 2205, 2206, 2207, 2209, 2308, 1963 }, 260, { w = 2 })
series("oficina", "silla_oficina", "Silla de oficina", { 1806, 2309, 1714, 1715, 1721, 1722, 2356 }, 140, { act = "sit" })
add("oficina", "computadora", 2190, "Computadora", 380)
add("oficina", "impresora",   2201, "Impresora", 160)
series("oficina", "fotocopiadora", "Fotocopiadora", { 2186, 2202 }, 420)
series("oficina", "archivador", "Archivador", { 2000, 2007, 2197, 2065, 2066, 2067, 2609, 2610 }, 120, { act = "storage", storage = "docs" })
series("oficina", "mueble_oficina", "Mueble de oficina", { 2161, 2163, 2164, 2167, 2191, 2200, 2204, 2208, 2210, 2211 }, 240)
add("oficina", "caja_fuerte",  2332, "Caja fuerte", 900, { act = "storage", storage = "safe" })
add("oficina", "caja_fuerte_2",2003, "Caja fuerte grande", 1400, { act = "storage", storage = "safe" })
series("oficina", "particion", "Particion de oficina", { 2168, 2187 }, 150, { struct = true })
add("oficina", "ventilador",   2192, "Ventilador", 60)
add("oficina", "enfriador_agua", 2002, "Enfriador de agua", 180, { act = "sink" })

----------------------------------------------------------------
-- ELECTRÓNICA
----------------------------------------------------------------
series("electro", "tv_eco",   "Televisor economico", { 1747, 1748, 1717 }, 250, { act = "tv" })
series("electro", "tv_medio", "Televisor medio",     { 1749, 1750, 1751, 1781 }, 480, { act = "tv" })
series("electro", "tv_lujo",  "Televisor de lujo",   { 1752, 1786, 1791, 1792, 2224 }, 950, { act = "tv" })
series("electro", "tv_mesa",  "Televisor sobre mesa", { 2312, 2316, 2317, 2318, 2320, 2322 }, 520, { act = "tv" })
series("electro", "mueble_tele", "Mesa de TV", { 2311, 2313, 2314, 2315, 2319, 2321 }, 180)
series("electro", "tv_unidad", "Unidad de TV", { 2296, 2297 }, 700, { act = "tv" })
series("electro", "equipo_musica_eco",   "Equipo de musica economico", { 2103, 2102, 2226 }, 280, { act = "hifi" })
series("electro", "equipo_musica_medio", "Equipo de musica medio",     { 1809, 2099, 2100, 2101 }, 520, { act = "hifi" })
series("electro", "equipo_musica_lujo",  "Equipo de musica de lujo",   { 2104, 2225, 2227, 1839 }, 980, { act = "hifi" })
series("electro", "parlante", "Parlante", { 1840, 1841, 2229, 2230, 2231, 2232, 2233 }, 110)
add("electro", "mesa_hifi",   2346, "Mesa de equipo", 120)
series("electro", "videograbadora", "Videograbadora", { 1782, 1783, 1784, 1785, 1787, 1788, 1790 }, 160)
add("electro", "consola_1", 1719, "Consola de videojuegos", 300)
add("electro", "consola_2", 2028, "Consola de lujo", 520)
add("electro", "consola_retro", 1718, "Consola retro", 150)

----------------------------------------------------------------
-- LUCES
----------------------------------------------------------------
series("luces", "lampara_techo", "Lampara de techo", { 1731, 1734, 2069, 2070, 2071, 2072, 2073, 2074, 2075, 2076, 2077, 2105, 2106, 2107, 2108, 2239 }, 120, { act = "light" })
add("luces", "lampara_pie",    2023, "Lampara de pie", 150, { act = "light" })
add("luces", "lampara_lava",   2238, "Lampara de lava", 90, { act = "light", color = { 255, 90, 160 } })
add("luces", "lampara_trabajo",2196, "Lampara de escritorio", 70, { act = "light" })
add("luces", "luz_strip",      2726, "Lampara de club", 130, { act = "light", color = { 255, 60, 140 } })
series("luces", "luz_casino", "Luz de casino", { 2176, 2177, 2178, 2179 }, 160, { act = "light", color = { 255, 200, 90 } })
add("luces", "luz_proyector",  2701, "Foco de tienda", 90, { act = "light", color = { 255, 245, 210 } })

----------------------------------------------------------------
-- DECORACIÓN
----------------------------------------------------------------
do
    local frames = {}
    for id = 2254, 2289 do frames[#frames + 1] = id end
    series("decoracion", "cuadro", "Cuadro", frames, 70, { wall = true, w = 0.5 })
end
series("decoracion", "planta", "Planta", { 2194, 2195, 2203, 2240, 2241, 2242, 2243, 2244, 2245, 2246, 2247, 2248, 2249, 2250, 2251, 2252, 2253, 2345, 2001, 2010, 2011 }, 45, { w = 0.5 })
series("decoracion", "alfombra", "Alfombra", { 2815, 2833, 2834, 2835, 2836, 2817, 2818, 2841, 2842, 2847, 1828 }, 130, { w = 0.5 })
series("decoracion", "cortina", "Cortina", { 2558, 2559, 2560, 2561 }, 110, { wall = true })
series("decoracion", "estatua", "Estatua", { 2743, 2744, 2745 }, 480)
series("decoracion", "adorno", "Adorno", { 2828, 2868, 2869, 2870, 2811 }, 40, { w = 0.5 })
add("decoracion", "libros_1", 2813, "Libros", 25, { w = 0.5 })
series("decoracion", "novelas", "Novelas", { 2824, 2825, 2826, 2827 }, 25, { w = 0.5 })
add("decoracion", "cabeza_ciervo", 1736, "Cabeza de ciervo", 260, { wall = true })
series("decoracion", "bandera", "Bandera", { 2047, 2048, 2614 }, 90, { wall = true })
add("decoracion", "extintor", 2690, "Extintor", 50, { wall = true })
add("decoracion", "reloj_pared", 2710, "Reloj", 70, { wall = true, w = 0.5 })
add("decoracion", "macetas", 1807, "Macetas medianas", 55, { w = 0.5 })
add("decoracion", "cubo_trapeador", 2713, "Cubeta", 25, { w = 0.5 })
add("decoracion", "trapeador", 2712, "Trapeador", 20, { w = 0.5 })
add("decoracion", "cajas_apiladas", 2669, "Caja de madera", 40)
add("decoracion", "tabla_surf", 2404, "Tabla de surf", 220, { wall = true })
add("decoracion", "tabla_surf_2", 2405, "Tabla de surf 2", 220, { wall = true })
add("decoracion", "tabla_surf_3", 2406, "Tabla de surf 3", 220, { wall = true })
add("dormitorio", "cama_celda", 2603, "Catre", 90, { act = "sleep", w = 2 })

----------------------------------------------------------------
-- OCIO Y JUEGOS
----------------------------------------------------------------
add("ocio", "gramola", 1732, "Gramola", 1800, { act = "hifi" })
series("ocio", "tragamonedas", "Tragamonedas", { 1830, 1831, 1832, 1833, 1834, 1835, 1836, 1837, 1838 }, 1500)
add("ocio", "mesa_blackjack", 2188, "Mesa de blackjack", 2400, { w = 3 })
add("ocio", "mesa_poker",     2189, "Mesa de poker", 2400, { w = 3 })
add("ocio", "mesa_ruleta",    1978, "Mesa de ruleta", 3200, { w = 3 })
add("ocio", "mesa_dados",     1824, "Mesa de dados", 2000, { w = 3 })
add("ocio", "caminadora",   2627, "Caminadora", 600, { w = 2 })
add("ocio", "banco_pesas_1", 2629, "Banco de pesas", 320, { w = 2 })
add("ocio", "banco_pesas_2", 2628, "Banco de pesas 2", 320, { w = 2 })
add("ocio", "bicicleta_est", 2630, "Bicicleta estatica", 480, { w = 2 })
add("ocio", "saco_boxeo",    1985, "Saco de boxeo", 260)
series("ocio", "pesas", "Pesa", { 1944, 1945, 1942, 1943 }, 30, { w = 0.5 })
add("ocio", "pelota_basket", 2114, "Balon de basket", 25, { w = 0.5 })
add("ocio", "canasta", 2113, "Aro de basket", 150, { wall = true })
add("ocio", "diana", 2049, "Diana", 60, { wall = true, w = 0.5 })

----------------------------------------------------------------
-- ESTRUCTURA (paneles escalables: paredes, suelos, puertas)
-- Se pueden estirar en cada eje (hasta FURN.SCALE_STRUCT_MAX) y se pintan con color o material.
----------------------------------------------------------------
add("estructura", "pared_particion_1", 2168, "Pared ligera", 140, { struct = true, w = 1.5 })
add("estructura", "pared_particion_2", 2187, "Pared ligera 2", 140, { struct = true, w = 1.5 })
add("estructura", "pared_particion_3", 2591, "Pared de bodega", 160, { struct = true, w = 1.5 })
add("estructura", "pared_dojo",        2755, "Pared de dojo", 180, { struct = true, w = 1.5 })
add("estructura", "suelo_alfombra_1",  2631, "Suelo plano", 90, { struct = true, w = 1 })
add("estructura", "suelo_alfombra_2",  2632, "Suelo plano 2", 90, { struct = true, w = 1 })
add("estructura", "suelo_pasarela",    2633, "Pasarela", 120, { struct = true, w = 1 })
add("estructura", "valla_madera_1",    1408, "Valla de madera", 70, { struct = true, w = 1 })
add("estructura", "valla_madera_2",    1446, "Valla de madera baja", 60, { struct = true, w = 1 })
add("estructura", "paleta_madera",     1219, "Palet de madera", 25, { struct = true, w = 1 })
add("estructura", "puerta_int_1", 1491, "Puerta interior", 130, { struct = true, w = 1 })
add("estructura", "puerta_int_2", 1492, "Puerta interior 2", 130, { struct = true, w = 1 })
add("estructura", "puerta_int_3", 1494, "Puerta interior 3", 130, { struct = true, w = 1 })
add("estructura", "puerta_int_4", 1499, "Puerta interior 4", 130, { struct = true, w = 1 })
add("estructura", "puerta_int_5", 1502, "Puerta interior 5", 130, { struct = true, w = 1 })
add("estructura", "puerta_tienda", 1493, "Puerta de tienda", 160, { struct = true, w = 1 })
add("estructura", "puerta_ext_1", 1495, "Puerta de entrada", 190, { struct = true, w = 1 })
add("estructura", "puerta_ext_2", 1497, "Puerta de entrada 2", 190, { struct = true, w = 1 })
add("estructura", "pilar_aeropuerto", 2774, "Pilares", 200, { struct = true, w = 2 })
add("estructura", "muro_skate_1", 2651, "Muro de skate", 150, { struct = true, w = 1.5 })
add("estructura", "muro_skate_2", 2650, "Muro de skate 2", 150, { struct = true, w = 1.5 })

-- Catalogo en forma de lista serializable para el cliente (sin funciones)
function furnPublicCatalog()
    local list = {}
    for _, key in ipairs(FURN_ORDER) do
        local it = FURN_ITEMS[key]
        list[#list + 1] = {
            key = it.key, name = it.name, cat = it.cat, price = it.price, model = it.model,
            act = it.act, wall = it.wall or false, struct = it.struct or false, w = it.w,
        }
    end
    return list
end
