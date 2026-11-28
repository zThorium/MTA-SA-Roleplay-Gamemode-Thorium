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
    BLIP = 45,                -- icono de tienda de ropa en el radar
    MARKER_SIZE = 1.1,        -- puerta, salida y mostrador (rp_markers)
    EXIT_RADIUS = 1.6,
    COUNTER_RADIUS = 3.5,     -- distancia maxima al mostrador para comprar (lo valida el servidor)

    -- Estudio (vista de compra y editor de accesorios)
    STUDIO = {
        panelWidth = 440,             -- px del panel lateral (se adapta en pantallas pequenas)
        camDist = 2.3, camMin = 0.6, camMax = 5,
    },

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

-- Interiores de GTA SA. x, y, z, rot = punto de aparicion junto a la puerta de dentro.
-- counter = mostrador donde se abre la tienda (marcador de rp_markers, a la altura del jugador).
-- Binco esta medido en juego; los demas son provisionales a unos pasos de la puerta: un admin los
-- coloca con ALT o M + clic derecho y quedan guardados (clave caja_<tipo>, mueve todas las de ese tipo).
CLOTHING_INTERIORS = {
    binco    = { name = "Binco",        interior = 15, x = 207.74, y = -109.02, z = 1005.13, rot = 0,   multiplier = 0.6,
                 counter = { 217.161, -98.670, 1005.258 } },
    suburban = { name = "SubUrban",     interior = 1,  x = 203.82, y = -50.66,  z = 1001.80, rot = 0,   multiplier = 0.8,
                 counter = { 203.82, -47.66, 1001.80 } },
    prolaps  = { name = "ProLaps",      interior = 3,  x = 207.06, y = -140.37, z = 1003.51, rot = 0,   multiplier = 1.0,
                 counter = { 207.06, -137.37, 1003.51 } },
    zip      = { name = "ZIP",          interior = 18, x = 161.38, y = -96.52,  z = 1001.80, rot = 0,   multiplier = 1.0,
                 counter = { 161.38, -93.52, 1001.80 } },
    victim   = { name = "Victim",       interior = 5,  x = 227.56, y = -8.06,   z = 1002.21, rot = 90,  multiplier = 1.4,
                 counter = { 224.56, -8.06, 1002.21 } },
    didier   = { name = "Didier Sachs", interior = 14, x = 204.33, y = -168.70, z = 1000.52, rot = 0,   multiplier = 2.5,
                 counter = { 204.33, -165.70, 1000.52 } },
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
    -- 3027 «ciggy»: el 1485 (CJ_CIGGY) y el 3044 (CIGAR) traen incrustado el efecto 2DFX cigarette_smoke,
    -- que ilumina lo que está cerca y hacía subir y bajar el brillo de los modelos al moverse (visto en rp_turbus)
    cigar       = { name = "Puro",                      icon = "🚬", model = 3027, price = 40, bone = 1,  x = 0.03,  y = 0.11,  z = -0.05, rx = 0, ry = 0,  rz = 90 },
    cup         = { name = "Vaso de bebida",            icon = "🥤", model = 2647, price = 25,  bone = 12, x = 0,     y = 0,     z = 0,    rx = 0,  ry = 0,  rz = 0 },
}

-- Recorta un ajuste de accesorio a CLOTHING.LIMITS. Devuelve la tabla limpia o nil si algo no vale.
-- Lo usan el servidor (al guardar y al comprar) y el cliente (vista previa).
function sanitizeToyAdjust(v)
    if type(v) ~= "table" then return nil end
    local L = CLOTHING.LIMITS
    local function clamp(n, a, b)
        n = tonumber(n)
        if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
        return math.max(a, math.min(b, n))
    end
    local bone = tonumber(v.bone)
    if not bone or bone ~= math.floor(bone) or bone < 1 or bone > 20 then return nil end
    local out = {
        bone = bone,
        x = clamp(v.x, -L.pos, L.pos), y = clamp(v.y, -L.pos, L.pos), z = clamp(v.z, -L.pos, L.pos),
        rx = clamp(v.rx, -L.rot, L.rot), ry = clamp(v.ry, -L.rot, L.rot), rz = clamp(v.rz, -L.rot, L.rot),
        sx = clamp(v.sx, L.scaleMin, L.scaleMax), sy = clamp(v.sy, L.scaleMin, L.scaleMax), sz = clamp(v.sz, L.scaleMin, L.scaleMax),
    }
    for _, k in ipairs({ "x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz" }) do
        if not out[k] then return nil end
    end
    return out
end

-- Ajuste inicial de un accesorio del catalogo
function getToyDefaults(toyId)
    local t = TOYS[toyId]
    if not t then return nil end
    return { bone = t.bone, x = t.x, y = t.y, z = t.z, rx = t.rx, ry = t.ry, rz = t.rz, sx = 1, sy = 1, sz = 1 }
end

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
