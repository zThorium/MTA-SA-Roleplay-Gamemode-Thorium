--[[
    rp_clothing / s_config.lua  (compartido cliente/servidor)

    Tiendas de ropa con interior propio y accesorios ("toys") pegados a un
    hueso del personaje con bone_attach.

    IMPORTANTE: las coordenadas de puertas e interiores salen de la lista de
    interiores de GTA SA y hay que verificarlas en juego. Si alguna queda mal,
    un admin la corrige parado en el punto correcto con:
        /ropapunto <id> entrada   o   /ropapunto <id> interior
]]

CLOTHING = {
    DIMENSION_BASE = 20000,   -- cada tienda usa la dimension 20000 + id
    ENTRANCE_PICKUP = 1275,   -- pickup de camiseta
    BLIP = 45,                -- icono de tienda de ropa en el radar
    EXIT_RADIUS = 1.6,

    -- Precio base por prenda; se multiplica por el de la tienda y varia segun la prenda
    PRICES = { torso = 60, legs = 50, shoes = 40, skin = 150 },

    MAX_TOYS_OWNED = 20,
    MAX_TOYS_WORN = 5,

    -- Limites del editor (el servidor recorta a estos rangos)
    LIMITS = {
        pos = 0.75,              -- metros desde el hueso, en cada eje
        rot = 180,               -- grados
        scaleMin = 0.25, scaleMax = 2.5,
    },
}

-- Interiores de GTA SA. x, y, z, rot = punto de aparicion junto a la puerta de dentro
CLOTHING_INTERIORS = {
    binco    = { name = "Binco",        interior = 15, x = 207.74, y = -109.02, z = 1005.13, rot = 0,   multiplier = 0.6 },
    suburban = { name = "SubUrban",     interior = 1,  x = 203.82, y = -50.66,  z = 1001.80, rot = 0,   multiplier = 0.8 },
    prolaps  = { name = "ProLaps",      interior = 3,  x = 207.06, y = -140.37, z = 1003.51, rot = 0,   multiplier = 1.0 },
    zip      = { name = "ZIP",          interior = 18, x = 161.38, y = -96.52,  z = 1001.80, rot = 0,   multiplier = 1.0 },
    victim   = { name = "Victim",       interior = 5,  x = 227.56, y = -8.06,   z = 1002.21, rot = 90,  multiplier = 1.4 },
    didier   = { name = "Didier Sachs", interior = 14, x = 204.33, y = -168.70, z = 1000.52, rot = 0,   multiplier = 2.5 },
}

-- Tiendas que se crean si la tabla esta vacia (puertas de Los Santos, a verificar en juego)
CLOTHING_SEED = {
    { "Binco Ganton",            "binco",    2244.39, -1665.56, 15.48 },
    { "SubUrban Jefferson",      "suburban", 2112.86, -1211.46, 23.96 },
    { "ProLaps Market",          "prolaps",  499.50,  -1360.62, 16.37 },
    { "ZIP Downtown",            "zip",      1456.75, -1137.56, 23.95 },
    { "Victim Rodeo",            "victim",   461.70,  -1500.84, 31.04 },
    { "Didier Sachs Rodeo",      "didier",   454.20,  -1477.98, 30.81 },
}

-- Huesos de bone_attach
BONES = {
    { id = 1,  name = "Cabeza" },          { id = 2,  name = "Cuello" },
    { id = 3,  name = "Espalda / pecho" }, { id = 4,  name = "Cadera" },
    { id = 5,  name = "Clavicula izq." },  { id = 6,  name = "Clavicula der." },
    { id = 7,  name = "Hombro izq." },     { id = 8,  name = "Hombro der." },
    { id = 9,  name = "Codo izq." },       { id = 10, name = "Codo der." },
    { id = 11, name = "Mano izq." },       { id = 12, name = "Mano der." },
    { id = 13, name = "Muslo izq." },      { id = 14, name = "Muslo der." },
    { id = 15, name = "Rodilla izq." },    { id = 16, name = "Rodilla der." },
    { id = 17, name = "Tobillo izq." },    { id = 18, name = "Tobillo der." },
    { id = 19, name = "Pie izq." },        { id = 20, name = "Pie der." },
}

--[[
    Catalogo de accesorios: solo modelos originales de GTA SA (IDs < 18000).
    GTA SA casi no trae gorras ni gafas como objeto; para mas variedad se
    pueden cargar modelos propios con engineRequestModel, como hace rp_heads,
    y agregarlos aqui.
    bone/x/y/z/rx/ry/rz = posicion inicial; cada jugador la ajusta en el editor.
]]
TOYS = {
    tommy_hat   = { name = "Sombrero Tommy",            icon = "🎩", model = 2052, price = 120, bone = 1,  x = 0,     y = 0.02,  z = 0.12, rx = 0,  ry = 0,  rz = 90 },
    jerry_hat   = { name = "Sombrero Jerry",            icon = "👒", model = 2053, price = 120, bone = 1,  x = 0,     y = 0.02,  z = 0.12, rx = 0,  ry = 0,  rz = 90 },
    capt_hat    = { name = "Gorra de capitan",          icon = "🧢", model = 2054, price = 150, bone = 1,  x = 0,     y = 0.02,  z = 0.12, rx = 0,  ry = 0,  rz = 90 },
    nv_goggles  = { name = "Gafas de vision nocturna",  icon = "🥽", model = 368,  price = 400, bone = 1,  x = 0,     y = 0.08,  z = 0.06, rx = 0,  ry = 0,  rz = 90 },
    ir_goggles  = { name = "Gafas termicas",            icon = "🥽", model = 369,  price = 400, bone = 1,  x = 0,     y = 0.08,  z = 0.06, rx = 0,  ry = 0,  rz = 90 },
    parachute   = { name = "Mochila de paracaidas",     icon = "🎒", model = 3026, price = 250, bone = 3,  x = 0,     y = -0.15, z = 0.05, rx = 0,  ry = 0,  rz = 0 },
    holdall     = { name = "Bolso deportivo",           icon = "👜", model = 2919, price = 180, bone = 12, x = 0,     y = 0,     z = 0,    rx = 0,  ry = 0,  rz = 0 },
    briefcase   = { name = "Maletin",                   icon = "💼", model = 1210, price = 200, bone = 12, x = 0.05,  y = 0.02,  z = 0,    rx = 0,  ry = 90, rz = 0 },
    boombox     = { name = "Radio portatil",            icon = "📻", model = 2226, price = 300, bone = 12, x = 0,     y = 0,     z = 0,    rx = 0,  ry = 0,  rz = 0 },
    money_bag   = { name = "Bolsa de dinero",           icon = "💰", model = 1550, price = 100, bone = 3,  x = 0,     y = -0.18, z = 0,    rx = 0,  ry = 0,  rz = 0 },
    surfboard   = { name = "Tabla de surf",             icon = "🏄", model = 2404, price = 350, bone = 3,  x = 0,     y = -0.2,  z = 0,    rx = 0,  ry = 90, rz = 0 },
    cane        = { name = "Baston",                    icon = "🦯", model = 326,  price = 90,  bone = 12, x = 0,     y = 0,     z = 0,    rx = 0,  ry = 0,  rz = 0 },
    flowers     = { name = "Ramo de flores",            icon = "💐", model = 325,  price = 60,  bone = 12, x = 0,     y = 0,     z = 0,    rx = 0,  ry = 0,  rz = 0 },
    camera      = { name = "Camara de fotos",           icon = "📷", model = 367,  price = 250, bone = 3,  x = 0.1,   y = 0.15,  z = 0,    rx = 0,  ry = 0,  rz = 0 },
    cigar       = { name = "Puro",                      icon = "🚬", model = 1485, price = 40,  bone = 1,  x = 0.03,  y = 0.11,  z = -0.05, rx = 0, ry = 0,  rz = 90 },
    cup         = { name = "Vaso de bebida",            icon = "🥤", model = 2647, price = 25,  bone = 12, x = 0,     y = 0,     z = 0,    rx = 0,  ry = 0,  rz = 0 },
}

function getToyPrice(toyId, multiplier)
    local t = TOYS[toyId]
    return t and math.floor(t.price * (multiplier or 1) + 0.5) or false
end

-- Precio de una prenda: base del tipo * tienda, con una variacion fija por prenda
function getClothesPrice(slot, index, multiplier)
    local base = CLOTHING.PRICES[slot]
    if not base then return false end
    local variation = 1 + ((tonumber(index) or 0) % 5) * 0.15
    return math.floor(base * variation * (multiplier or 1) + 0.5)
end
