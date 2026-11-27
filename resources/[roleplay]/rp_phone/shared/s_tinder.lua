--[[
    rp_phone / shared / s_tinder.lua  (compartido cliente/servidor)
    Catalogo de la app Tinder: numeros de balance, intereses, escenarios donde los NPC se
    sacan las fotos y poses del estudio. Las personalidades y frases viven en el servidor
    (server/s_tinder_data.lua y server/s_tinder_lines.lua): el cliente no las necesita.
]]

TINDER = {
    -- Cupos (se reinician cada dia real)
    FREE_LIKES      = 50,      -- likes por dia sin Gold
    FREE_SUPERS     = 1,       -- super likes por dia sin Gold
    GOLD_SUPERS     = 5,
    GOLD_PRICE      = 300,     -- $ del banco por GOLD_DAYS dias
    GOLD_DAYS       = 7,
    MAX_PHOTOS      = 4,       -- fotos del perfil del jugador (la 1 es la principal)
    MAX_INTERESTS   = 5,
    BIO_MAX         = 300,
    JOB_MAX         = 40,
    MESSAGE_MAX     = 400,
    PHOTO_MAX       = 350 * 1024,   -- bytes del base64 de una foto
    THUMB_MAX       = 40 * 1024,

    -- NPC
    NPC_TARGET      = 72,      -- personas simuladas que se generan la primera vez
    NPC_RECYCLE_DAYS = 3,      -- los "nope" a NPC vuelven a salir pasado este tiempo (como en la app)
    LIKES_YOU_MAX   = 12,      -- likes pendientes de NPC que puede acumular un jugador
    PASSIVE_EVERY   = 4 * 60000,   -- ms entre rondas de "alguien te dio like"
    DECIDE_MIN      = 45,      -- segundos minimos para que un NPC vea tu like
    DECIDE_MAX      = 40 * 60, -- segundos maximos
    GHOST_BELOW     = 12,      -- interes por debajo del cual deja de contestar
    UNMATCH_BELOW   = 4,       -- y por debajo de este deshace el match
    DATE_MIN_EXCHANGES = 5,    -- intercambios minimos antes de aceptar una cita
    STALE_HOURS     = 20,      -- horas sin que contestes para que el NPC insista (una vez)
    GIVEUP_DAYS     = 4,       -- dias sin que contestes para que el NPC deshaga el match

    -- Estudio de fotos de los NPC (/tinderstudio)
    PHOTO_W = 360, PHOTO_H = 450,
    THUMB_W = 120, THUMB_H = 150,
}

-- Intereses: id, etiqueta, icono y palabras (sin tildes, en minusculas) para reconocerlos en el chat
TINDER_INTERESTS = {
    { id = "gym",       label = "Gimnasio",      icon = "💪", words = { "gym", "gimnasio", "pesas", "entrenar", "entreno", "crossfit", "fitness" } },
    { id = "playa",     label = "Playa",         icon = "🏖️", words = { "playa", "mar", "arena", "santa maria", "verona" } },
    { id = "surf",      label = "Surf",          icon = "🏄", words = { "surf", "ola", "olas", "tabla" } },
    { id = "musica",    label = "Música",        icon = "🎧", words = { "musica", "cancion", "canciones", "escuchar", "playlist", "spotify" } },
    { id = "conciertos",label = "Conciertos",    icon = "🎤", words = { "concierto", "conciertos", "festival", "tocata" } },
    { id = "cocina",    label = "Cocinar",       icon = "🍳", words = { "cocinar", "cocina", "receta", "chef", "comida" } },
    { id = "viajar",    label = "Viajar",        icon = "✈️", words = { "viajar", "viaje", "viajes", "mochila", "conocer lugares" } },
    { id = "perros",    label = "Perros",        icon = "🐶", words = { "perro", "perros", "perrito", "cachorro" } },
    { id = "gatos",     label = "Gatos",         icon = "🐱", words = { "gato", "gatos", "gatito", "michi" } },
    { id = "videojuegos", label = "Videojuegos", icon = "🎮", words = { "videojuego", "videojuegos", "jugar", "gamer", "consola", "play", "xbox", "pc" } },
    { id = "anime",     label = "Anime",         icon = "🍥", words = { "anime", "manga", "otaku" } },
    { id = "cine",      label = "Cine",          icon = "🎬", words = { "cine", "pelicula", "peliculas", "peli", "pelis" } },
    { id = "series",    label = "Series",        icon = "📺", words = { "serie", "series", "maraton", "netflix" } },
    { id = "futbol",    label = "Fútbol",        icon = "⚽", words = { "futbol", "pichanga", "partido", "gol" } },
    { id = "basquet",   label = "Básquet",       icon = "🏀", words = { "basquet", "basket", "baloncesto", "canasta" } },
    { id = "autos",     label = "Autos",         icon = "🚗", words = { "auto", "autos", "coche", "coches", "carro", "carros", "motor", "tuning", "lowrider" } },
    { id = "motos",     label = "Motos",         icon = "🏍️", words = { "moto", "motos", "motocicleta", "rodada" } },
    { id = "baile",     label = "Bailar",        icon = "💃", words = { "bailar", "baile", "salsa", "bachata", "reggaeton" } },
    { id = "fiesta",    label = "Fiesta",        icon = "🎉", words = { "fiesta", "carrete", "antro", "discoteca", "club", "carretear", "salir de noche" } },
    { id = "cafe",      label = "Café",          icon = "☕", words = { "cafe", "cafecito", "capuchino", "latte" } },
    { id = "vino",      label = "Vino",          icon = "🍷", words = { "vino", "vinos", "copa", "vinito" } },
    { id = "lectura",   label = "Leer",          icon = "📚", words = { "leer", "libro", "libros", "lectura", "novela" } },
    { id = "arte",      label = "Arte",          icon = "🎨", words = { "arte", "pintar", "pintura", "dibujar", "museo", "galeria" } },
    { id = "fotografia",label = "Fotografía",    icon = "📸", words = { "foto", "fotos", "fotografia", "camara" } },
    { id = "montana",   label = "Senderismo",    icon = "⛰️", words = { "montana", "cerro", "trekking", "senderismo", "chiliad", "acampar", "camping" } },
    { id = "pesca",     label = "Pesca",         icon = "🎣", words = { "pesca", "pescar", "anzuelo", "caña" } },
    { id = "yoga",      label = "Yoga",          icon = "🧘", words = { "yoga", "meditar", "meditacion", "mindfulness" } },
    { id = "astrologia",label = "Astrología",    icon = "🔮", words = { "signo", "horoscopo", "astrologia", "tarot", "zodiaco", "escorpio", "leo", "geminis" } },
    { id = "moda",      label = "Moda",          icon = "👗", words = { "moda", "ropa", "outfit", "shopping", "compras" } },
    { id = "tatuajes",  label = "Tatuajes",      icon = "🖋️", words = { "tatuaje", "tatuajes", "tattoo", "tinta" } },
    { id = "skate",     label = "Skate",         icon = "🛹", words = { "skate", "patineta", "skatepark" } },
    { id = "golf",      label = "Golf",          icon = "⛳", words = { "golf", "hoyo", "palos" } },
    { id = "casino",    label = "Casino",        icon = "🎰", words = { "casino", "apostar", "poker", "blackjack", "ruleta", "las venturas" } },
    { id = "caballos",  label = "Caballos",      icon = "🐴", words = { "caballo", "caballos", "rodeo", "cabalgar", "rancho" } },
    { id = "karaoke",   label = "Karaoke",       icon = "🎙️", words = { "karaoke", "cantar" } },
    { id = "emprender", label = "Emprender",     icon = "📈", words = { "negocio", "emprender", "emprendimiento", "inversion", "invertir", "empresa" } },
}
TINDER_INTEREST_BY_ID = {}
for i, it in ipairs(TINDER_INTERESTS) do it.index = i; TINDER_INTEREST_BY_ID[it.id] = it end

-- Barrios donde viven los NPC (x, y para la distancia que muestra la tarjeta)
TINDER_ZONES = {
    ganton       = { label = "Ganton",           city = "Los Santos",    x = 2400,  y = -1700 },
    idlewood     = { label = "Idlewood",         city = "Los Santos",    x = 2000,  y = -1700 },
    santa_maria  = { label = "Santa Maria Beach",city = "Los Santos",    x = 400,   y = -1800 },
    verona       = { label = "Verona Beach",     city = "Los Santos",    x = 800,   y = -1750 },
    rodeo        = { label = "Rodeo",            city = "Los Santos",    x = 400,   y = -1450 },
    vinewood     = { label = "Vinewood",         city = "Los Santos",    x = 1000,  y = -1050 },
    mulholland   = { label = "Mulholland",       city = "Los Santos",    x = 1200,  y = -900 },
    downtown_ls  = { label = "Downtown",         city = "Los Santos",    x = 1500,  y = -1300 },
    el_corona    = { label = "El Corona",        city = "Los Santos",    x = 1900,  y = -2050 },
    willowfield  = { label = "Willowfield",      city = "Los Santos",    x = 2500,  y = -1950 },
    east_ls      = { label = "East Los Santos",  city = "Los Santos",    x = 2400,  y = -1300 },
    jefferson    = { label = "Jefferson",        city = "Los Santos",    x = 2150,  y = -1300 },
    market       = { label = "Market",           city = "Los Santos",    x = 1100,  y = -1450 },
    downtown_sf  = { label = "Downtown",         city = "San Fierro",    x = -1800, y = 700 },
    doherty      = { label = "Doherty",          city = "San Fierro",    x = -2100, y = 200 },
    garcia       = { label = "Garcia",           city = "San Fierro",    x = -2300, y = 100 },
    juniper      = { label = "Juniper Hill",     city = "San Fierro",    x = -2400, y = 800 },
    calton       = { label = "Calton Heights",   city = "San Fierro",    x = -2100, y = 1100 },
    strip        = { label = "The Strip",        city = "Las Venturas",  x = 2050,  y = 1500 },
    roca         = { label = "Roca Escalante",   city = "Las Venturas",  x = 2400,  y = 1100 },
    redsands     = { label = "Redsands",         city = "Las Venturas",  x = 1800,  y = 2000 },
    palomino     = { label = "Palomino Creek",   city = "Red County",    x = 2300,  y = 50 },
    blueberry    = { label = "Blueberry",        city = "Red County",    x = 200,   y = -150 },
    montgomery   = { label = "Montgomery",       city = "Red County",    x = 1300,  y = 250 },
    dillimore    = { label = "Dillimore",        city = "Red County",    x = 680,   y = -550 },
    angel_pine   = { label = "Angel Pine",       city = "Whetstone",     x = -2150, y = -2400 },
    bayside      = { label = "Bayside",          city = "Tierra Robada", x = -2450, y = 2350 },
    fort_carson  = { label = "Fort Carson",      city = "Bone County",   x = -100,  y = 1100 },
}

--[[
    Escenarios de las fotos de los NPC. El estudio (client/c_tinder_studio.lua) lleva al admin
    a cada sitio, busca el suelo con un rayo y saca las fotos con la hora y el clima indicados.
    view = hacia donde mira la camara (grados de MTA: 0 norte, 90 oeste, 180 sur, 270 este);
    lo que queda detras de la persona es lo que se ve de fondo.
]]
TINDER_SCENES = {
    beach_sunset  = { label = "Atardecer en Santa Maria", x = 370,   y = -1870, z = 4,   view = 160, hour = 20, minute = 10, weather = 1 },
    pier_sunset   = { label = "Muelle de Santa Maria",    x = 836,   y = -1990, z = 13,  view = 150, hour = 20, minute = 0,  weather = 1 },
    verona_day    = { label = "Verona Beach",             x = 665,   y = -1870, z = 5,   view = 180, hour = 13, minute = 0,  weather = 1 },
    grove         = { label = "Grove Street",             x = 2486,  y = -1668, z = 13,  view = 0,   hour = 17, minute = 30, weather = 1 },
    ganton_gym    = { label = "Gimnasio de Ganton",       x = 2229,  y = -1735, z = 13,  view = 0,   hour = 11, minute = 0,  weather = 1 },
    vinewood_view = { label = "Colinas de Vinewood",      x = 1400,  y = -830,  z = 80,  view = 180, hour = 19, minute = 30, weather = 1 },
    vinewood_night= { label = "Vinewood de noche",        x = 1400,  y = -830,  z = 80,  view = 180, hour = 23, minute = 0,  weather = 1 },
    pershing      = { label = "Pershing Square",          x = 1480,  y = -1665, z = 13,  view = 180, hour = 12, minute = 0,  weather = 1 },
    rodeo_shops   = { label = "Rodeo",                    x = 455,   y = -1480, z = 31,  view = 300, hour = 15, minute = 0,  weather = 1 },
    unity         = { label = "Unity Station",            x = 1745,  y = -1880, z = 13,  view = 0,   hour = 18, minute = 0,  weather = 1 },
    chiliad_top   = { label = "Cima del Monte Chiliad",   x = -2324, y = -1636, z = 483, view = 45,  hour = 7,  minute = 0,  weather = 0 },
    angel_forest  = { label = "Bosque de Angel Pine",     x = -2150, y = -2330, z = 30,  view = 0,   hour = 10, minute = 30, weather = 0 },
    sf_cranberry  = { label = "Estación Cranberry",       x = -1980, y = 120,   z = 27,  view = 90,  hour = 16, minute = 0,  weather = 9 },
    sf_downtown   = { label = "Downtown San Fierro",      x = -1800, y = 900,   z = 25,  view = 0,   hour = 19, minute = 0,  weather = 9 },
    bayside_dock  = { label = "Marina de Bayside",        x = -2350, y = 2390,  z = 5,   view = 0,   hour = 19, minute = 45, weather = 0 },
    lv_strip      = { label = "The Strip de noche",       x = 2040,  y = 1520,  z = 10,  view = 0,   hour = 23, minute = 30, weather = 10 },
    lv_dragons    = { label = "Four Dragons",             x = 2030,  y = 1010,  z = 10,  view = 90,  hour = 22, minute = 0,  weather = 10 },
    lv_golf       = { label = "Yellow Bell Golf Course",  x = 1420,  y = 2780,  z = 10,  view = 0,   hour = 10, minute = 0,  weather = 10 },
    blueberry     = { label = "Blueberry",                x = 230,   y = -150,  z = 1,   view = 180, hour = 9,  minute = 0,  weather = 0 },
    palomino      = { label = "Palomino Creek",           x = 2290,  y = 30,    z = 26,  view = 180, hour = 18, minute = 45, weather = 0 },
    fort_carson   = { label = "Fort Carson",              x = -100,  y = 1130,  z = 19,  view = 270, hour = 19, minute = 50, weather = 10 },
}

--[[
    Poses del estudio. cam = encuadre: selfie (brazo estirado), portrait (te la saca un amigo),
    full (cuerpo entero), landscape (paisaje sin persona), car (posando junto a su auto).
    anim = { bloque, animacion } o por genero { [0] = {...}, [1] = {...} }.
]]
TINDER_POSES = {
    selfie     = { cam = "selfie",    anim = { "ped", "IDLE_stance" } },
    selfie_paz = { cam = "selfie",    anim = { "GHANDS", "gsign2LH" } },
    selfie_risa= { cam = "selfie",    anim = { "RAPPING", "Laugh_01" } },
    portrait   = { cam = "portrait",  anim = { "ped", "IDLE_chat" } },
    pensativo  = { cam = "portrait",  anim = { "COP_AMBIENT", "Coplook_think" } },
    full       = { cam = "full",      anim = { "ped", "IDLE_stance" } },
    baile      = { cam = "full",      anim = { [0] = { "DANCING", "dnce_M_a" }, [1] = { "DANCING", "DAN_Left_A" } } },
    sentado    = { cam = "sit",       anim = { [0] = { "BEACH", "ParkSit_M_loop" }, [1] = { "BEACH", "ParkSit_W_loop" } } },
    tumbado    = { cam = "lay",       anim = { "BEACH", "Lay_Bac_Loop" } },
    paisaje    = { cam = "landscape" },
    auto       = { cam = "car",       anim = { "ped", "IDLE_stance" } },
}
