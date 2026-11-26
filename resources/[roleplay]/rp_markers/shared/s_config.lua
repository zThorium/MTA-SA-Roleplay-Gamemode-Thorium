--[[
    rp_markers / s_config.lua  (compartido cliente/servidor)

    Marcadores modernos para toda la GM. El cliente oculta el cilindro nativo de GTA
    (alfa 0, sigue funcionando como zona de colisión) y en su lugar dibuja:
    aro de suelo que respira, aro segmentado que gira, ondas de pulso, haz de luz,
    partículas que suben y, al acercarte, una insignia flotante con icono y texto.

    Funciona con TODOS los createMarker de tipo cilindro sin tocar los demás recursos.
    El icono y el texto se ponen con el export setMarkerStyle (ver RECURSOS.md).
]]

MARKERS = {
    -- Tipos de marcador que se rediseñan. "checkpoint", "ring", "arrow" y "corona"
    -- se dejan nativos (carreras, autoescuela y flechas de misión siguen como el juego).
    TYPES = { cylinder = true },

    SCAN_MS = 400,            -- cada cuánto se buscan marcadores nuevos o cambiados
    DRAW_DIST = 70,           -- metros: más lejos no se dibuja nada
    PARTICLE_DIST = 30,       -- metros: partículas solo de cerca
    ICON_DIST = 16,           -- metros: aparece la insignia con el icono
    LABEL_DIST = 8,           -- metros: aparece el texto bajo la insignia

    RADIUS_SCALE = 0.55,      -- radio dibujado = tamaño del marcador * esto
    BEAM_HEIGHT = 1.7,        -- metros del haz de luz
    PARTICLES = 9,            -- partículas por marcador
    ICON_SIZE = 0.55,         -- metros de la insignia
    ICON_HEIGHT = 1.45,       -- altura de la insignia sobre la base del marcador

    -- Iconos disponibles (images/icons/<nombre>.png, blancos; se generan con tools/gen_textures.ps1)
    ICONS = {
        "info", "enter", "exit", "door", "shop", "money", "car", "gun", "job", "wrench",
        "fuel", "medical", "bike", "house", "key", "star", "food", "drink", "target",
        "flag", "person", "phone", "arrow", "bank", "police", "gym", "clothes", "license",
    },

    -- Lenguaje de colores: el color lo decide el TIPO de lugar (el icono), no el recurso.
    -- Manda sobre el color con el que se creó el marcador; un style.color explícito manda sobre esto.
    -- Un marcador sin icono conserva su color original.
    PALETTE = {
        exit     = { 76, 211, 138 },   -- verde: salir
        access   = { 70, 160, 255 },   -- azul claro: entrar a un sitio
        commerce = { 255, 200, 60 },   -- amarillo: comprar, vender, dinero
        danger   = { 235, 70, 70 },    -- rojo: armas y tiro
        vehicle  = { 60, 215, 230 },   -- cian: vehículos y sus servicios
        work     = { 245, 140, 40 },   -- naranja: trabajos y trámites
        police   = { 59, 111, 224 },   -- azul policía: autoridad
        health   = { 255, 95, 120 },   -- rosa: salud
        mission  = { 180, 110, 255 },  -- morado: contactos de misión
        objective = { 255, 225, 60 },  -- amarillo GTA: ve aquí (objetivos)
        leisure  = { 255, 80, 190 },   -- magenta: ocio y carreras
    },
    ICON_CATEGORY = {
        exit = "exit",
        enter = "access", door = "access", house = "access",
        shop = "commerce", money = "commerce", food = "commerce", drink = "commerce",
        clothes = "commerce", bank = "commerce",
        gun = "danger", target = "danger",
        car = "vehicle", fuel = "vehicle", wrench = "vehicle", bike = "vehicle", key = "vehicle",
        job = "work", license = "work", info = "work", person = "work", phone = "work",
        police = "police",
        medical = "health",
        star = "mission",
        arrow = "objective",
        flag = "leisure", gym = "leisure",
    },

    ELEMENT_DATA = "rp:marker",   -- estilo sincronizado puesto por el servidor
    DEMO_ADMIN_LEVEL = 1,         -- /markerdemo
}
