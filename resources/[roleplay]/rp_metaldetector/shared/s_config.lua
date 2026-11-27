--[[
    rp_metaldetector / s_config.lua  (compartido cliente/servidor)

    Todo lo ajustable del detector de metales. Las PROBABILIDADES del botín están en
    server/s_config.lua (el cliente no las ve); aquí solo lo que dibuja la interfaz.
]]

METALDETECTOR = {
    ----------------------------------------------------------------
    -- Detectores: 5 niveles. Cada uno es un item propio (rp_inventory) y un modelo 3D propio
    -- (models/detector_<n>.dff, mismo modelo con otros colores; tools/build_detector.py).
    -- Estadísticas de 0 a 10:
    --   radius   -> distancia a la que empieza a sonar (12 + radius * 1.8 m)
    --   depth    -> profundidad máxima que alcanza (10 + depth * 2.7 cm): lo más hondo es lo más valioso
    --   accuracy -> error de la lectura VDI y probabilidad de lecturas engañosas
    -- level = nivel de buscador necesario para comprarlo (y para usarlo).
    ----------------------------------------------------------------
    TIERS = {
        { item = "metal_detector_1", name = "Pionero",          price = 850,   level = 1, color = "#1f6ff2", radius = 4,   depth = 3,   accuracy = 4,
          desc = "Sencillo y fiable. Ideal para empezar a recorrer la arena." },
        { item = "metal_detector_2", name = "Rastreador",       price = 2400,  level = 2, color = "#4cc43a", radius = 5.5, depth = 5,   accuracy = 5.5,
          desc = "Más alcance y mejor lectura del metal. Llega a monedas y relojes enterrados." },
        { item = "metal_detector_3", name = "Cazatesoros",      price = 5200,  level = 3, color = "#d61a14", radius = 7,   depth = 6.5, accuracy = 7,
          desc = "Sensible y preciso: separa el hierro del oro y alcanza anillos y cadenas." },
        { item = "metal_detector_4", name = "Buscador de Oro",  price = 9500,  level = 4, color = "#ffb805", radius = 8.5, depth = 8,   accuracy = 8.5,
          desc = "Hecho para profesionales. Llega a los doblones piratas más hondos." },
        { item = "metal_detector_5", name = "Abisal Pro",       price = 16000, level = 5, color = "#c9a227", radius = 10,  depth = 10,  accuracy = 10,
          desc = "Lo máximo: alcance, profundidad y análisis del objetivo. Nada se le escapa." },
    },
    SHOVEL_ITEM = "shovel",
    SHOVEL_PRICE = 120,

    ----------------------------------------------------------------
    -- Nivel de buscador (propio del detector): XP por hallazgo según la rareza (RARITIES.dxp)
    ----------------------------------------------------------------
    LEVEL_XP = { 0, 120, 350, 800, 1600 },   -- XP total para llegar a cada nivel (1..5)

    ----------------------------------------------------------------
    -- Tienda (panel CEF propio). El vendedor se puede mover con el editor (rp_markers, clave "shop").
    -- Lo encontrado se vende en el mercado "beachfinds" de rp_jobs (al lado) y algo en la compraventa.
    ----------------------------------------------------------------
    SHOP = {
        name = "Equipo de playa",
        x = 812.5, y = -1855.0, z = 12.87, rot = 90, interior = 0, dimension = 0,
        skin = 97,   -- socorrista de la playa
        radius = 3.0,
    },
    MARKET_ID = "beachfinds",   -- mercado de rp_jobs donde se vende (precio estimado y dinero ganado)

    ----------------------------------------------------------------
    -- Detector en la mano (cliente, para todos los jugadores con elementData rp:heldItem = metal_detector_<n>).
    -- La empuñadura va en la posición de la mano derecha (hueso 25) y el detector se orienta con el rumbo
    -- del personaje: vara hacia delante y abajo, bobina apoyada en el suelo (se inclina sola) y barrido.
    -- PROP_OFFSET: desfase en el marco del personaje (x derecha, y delante, z arriba), rx inclina, rz gira.
    -- POSE (rotar huesos del brazo) va apagada: el brazo cuelga con su animación natural.
    -- Ajustables en vivo con /mdprop y /mdpose. FALLBACK_MODEL: si no están los .dff, palo de golf.
    ----------------------------------------------------------------
    HAND_BONE = 25,
    PROP_OFFSET = { x = 0.0, y = 0.04, z = 0.0, rx = 0, ry = 0, rz = 0 },
    FALLBACK_MODEL = 333,
    POSE_ENABLED = false,
    POSE = {                     -- [hueso] = { yaw, pitch, roll } (setElementBoneRotation)
        [22] = { 0, 60, 10 },    -- hombro derecho: brazo bajado y algo adelantado
        [23] = { 0, 25, 0 },     -- codo derecho: casi recto
        [24] = { 0, 0, 0 },      -- muñeca
    },
    SWEEP = { angle = 18, idleSpeed = 1.1, walkSpeed = 2.2 },   -- barrido de lado a lado (grados, ciclos/s)
    BONE = 12,                   -- mano derecha en bone_attach (la pala al cavar)
    SHOVEL_PROP = { model = 337, x = 0.0, y = 0.0, z = 0.0, rx = 0, ry = 0, rz = 0 },

    ----------------------------------------------------------------
    -- Terreno válido
    -- IDs de material de surfinfo.dat (9º retorno de processLineOfSight). 28-33 = SAND_*,
    -- 74-79 = P_SAND* (arena de los procedurales). Afinar en juego con /detectorsuelo.
    ----------------------------------------------------------------
    SAND_MATERIALS = {
        [28] = true, [29] = true, [30] = true, [31] = true, [32] = true, [33] = true,
        [74] = true, [75] = true, [76] = true, [77] = true, [78] = true, [79] = true,
    },
    -- Zonas (getZoneName) donde se pueden enterrar puntos. El servidor lo revalida.
    BEACH_ZONES = {
        ["Santa Maria Beach"] = true,
        ["Verona Beach"] = true,
        ["Playa del Seville"] = true,
    },
    SURFACE_CHECK_MS = 250,       -- cada cuánto el cliente mira qué pisa

    ----------------------------------------------------------------
    -- Puntos ocultos
    ----------------------------------------------------------------
    SPOT_MIN_DIST = 15,           -- metros desde el jugador
    SPOT_MAX_DIST = 45,
    SPOT_LOST_DIST = 70,          -- si te alejas más, se busca un punto nuevo
    SPOT_TRIES = 24,              -- intentos del cliente para encontrar arena alrededor
    DIG_RADIUS = 2.0,             -- distancia para poder excavar (igual que el tono continuo de BEEPS: si suena «¡AQUÍ!», se puede)
    NEXT_SPOT_MS = 5000,          -- espera tras excavar antes de un punto nuevo

    ----------------------------------------------------------------
    -- Señal: distancia 2D al punto -> cada cuántos ms pita (nil = silencio), fuerza (0-1) y LED
    ----------------------------------------------------------------
    -- (la distancia a la que empieza a oírse depende del detector: TIERS.radius)
    BEEP_TICK_MS = 60,
    BEEPS = {
        { maxDist = 2,  every = 0,    led = { 235, 60, 50 } },      -- tono continuo (pinpoint)
        { maxDist = 5,  every = 260,  led = { 245, 140, 40 } },
        { maxDist = 10, every = 600,  led = { 240, 210, 50 } },
        { maxDist = 99, every = 1300, led = { 80, 200, 90 } },     -- hasta el alcance del detector
    },
    VOLUME = { beep = 0.38, tone = 0.22, hum = 0.035 },

    ----------------------------------------------------------------
    -- Identificación del objetivo (VDI 0-99, como un detector real). El servidor manda la lectura
    -- con un margen de error; el cliente la muestra y elige el tono: grave = hierro, agudo = no ferroso.
    ----------------------------------------------------------------
    VDI_RANGES = {
        { max = 19, name = "Hierro",        color = { 220, 90, 70 } },
        { max = 39, name = "Latón / lata",  color = { 235, 180, 70 } },
        { max = 69, name = "Oro",           color = { 250, 210, 90 } },
        { max = 99, name = "Plata / cobre", color = { 150, 205, 255 } },
    },
    VDI_LOW_TONE = 20,            -- por debajo, gruñido grave (hierro)

    ----------------------------------------------------------------
    -- Rarezas (color de tarjeta, XP general de rp_levels, XP de buscador dxp, golpes de pala,
    -- bonus de peso por nivel de detector, sonido y efectos del hallazgo)
    ----------------------------------------------------------------
    RARITIES = {
        common    = { order = 1, name = "Común",      color = { 170, 176, 186 }, xp = 2,  dxp = 4,  strokes = 3, sound = "reveal_common" },
        uncommon  = { order = 2, name = "Poco común", color = { 90, 210, 110 },  xp = 3,  dxp = 7,  strokes = 3, sound = "reveal_common" },
        rare      = { order = 3, name = "Raro",       color = { 70, 160, 255 },  xp = 5,  dxp = 12, strokes = 4, sound = "reveal_rare" },
        epic      = { order = 4, name = "Épico",      color = { 185, 95, 255 },  xp = 8,  dxp = 20, strokes = 5, sound = "reveal_rare", beam = true },
        legendary = { order = 5, name = "Legendario", color = { 255, 196, 50 },  xp = 15, dxp = 40, strokes = 6, sound = "reveal_legendary", beam = true, closeup = true },
    },
    TIER_RARE_BONUS = 0.15,       -- cada nivel de detector sobre el 1 multiplica el peso de raro+ por (1 + 0.15 * n)

    -- Lo que puede salir de la arena (orden de la colección). vdi = lectura típica; depth = cm.
    FINDS = {
        { item = "rusty_can",     rarity = "common",    vdi = 26, depth = 10 },
        { item = "scrap_metal",   rarity = "common",    vdi = 8,  depth = 12 },
        { item = "rusty_key",     rarity = "common",    vdi = 14, depth = 14 },
        { item = "lost_keys",     rarity = "uncommon",  vdi = 36, depth = 12 },
        { item = "old_coin",      rarity = "uncommon",  vdi = 78, depth = 18 },
        { item = "old_compass",   rarity = "rare",      vdi = 32, depth = 22 },
        { item = "old_watch",     rarity = "rare",      vdi = 47, depth = 20 },
        { item = "gold_earrings", rarity = "rare",      vdi = 52, depth = 16 },
        { item = "gold_ring",     rarity = "epic",      vdi = 58, depth = 24 },
        { item = "gold_chain",    rarity = "epic",      vdi = 55, depth = 26 },
        { item = "doubloon",      rarity = "legendary", vdi = 64, depth = 30 },
        { item = "jeweled_tiara", rarity = "legendary", vdi = 72, depth = 35 },
    },

    ----------------------------------------------------------------
    -- Excavación a golpes de pala: una barra oscila y E en la zona buena = palada buena.
    -- Palada buena = 1 de progreso; floja = WEAK_STROKE. Golpes necesarios según la rareza.
    -- El servidor exige STROKE_MIN_MS entre golpes (no se puede acelerar) y corta si pasas STROKE_TIMEOUT_MS sin cavar.
    ----------------------------------------------------------------
    STROKE_MIN_MS = 550,
    STROKE_TIMEOUT_MS = 20000,
    WEAK_STROKE = 0.4,
    STROKE_ZONE = 0.22,           -- ancho de la zona buena (fracción de la barra)
    STROKE_SPEED = 1.15,          -- vueltas por segundo del indicador
    DIG_ANIM = { block = "BOMBER", name = "BOM_Plant_Loop" },
    DIG_COOLDOWN_MS = 6000,       -- entre dos excavaciones del mismo jugador (antifraude)
}

-- Búsquedas rápidas (compartidas)
METALDETECTOR_FIND_BY_ITEM = {}
for i, f in ipairs(METALDETECTOR.FINDS) do
    f.index = i
    METALDETECTOR_FIND_BY_ITEM[f.item] = f
end

METALDETECTOR_TIER_BY_ITEM = {}
for i, t in ipairs(METALDETECTOR.TIERS) do
    t.index = i
    METALDETECTOR_TIER_BY_ITEM[t.item] = t
end

-- Efecto real de las estadísticas de un detector (índice 1..5)
function metalDetectorStats(tierIndex)
    local t = METALDETECTOR.TIERS[tierIndex] or METALDETECTOR.TIERS[1]
    return {
        range = 12 + t.radius * 1.8,                     -- m a los que empieza a sonar
        maxDepth = 10 + t.depth * 2.7,                   -- cm
        noise = math.max(1, math.floor(12 - t.accuracy + 0.5)),   -- ± error del VDI
        falseChance = math.max(0.03, 0.25 - t.accuracy * 0.02),   -- lecturas engañosas
        rareBonus = 1 + (t.index - 1) * METALDETECTOR.TIER_RARE_BONUS,
    }
end

-- Nivel de buscador a partir de la XP: nivel, XP del nivel actual, XP del siguiente (nil en el máximo)
function metalDetectorLevel(xp)
    local levels = METALDETECTOR.LEVEL_XP
    local level = 1
    for i = 1, #levels do
        if (xp or 0) >= levels[i] then level = i end
    end
    return level, levels[level], levels[level + 1]
end

function metalDetectorVdiRange(vdi)
    for _, r in ipairs(METALDETECTOR.VDI_RANGES) do
        if vdi <= r.max then return r end
    end
    return METALDETECTOR.VDI_RANGES[#METALDETECTOR.VDI_RANGES]
end
