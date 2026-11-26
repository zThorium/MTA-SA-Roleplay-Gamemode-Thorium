--[[
    rp_map / shared/s_config.lua
    Configuracion central del mapa F11 (servidor y cliente). Los admins pueden cambiar
    en caliente el radio, el intervalo y las funciones activas desde la pestana Admin del
    mapa (tabla map_settings); estos son los valores por defecto.
]]

MAPA = {
    -- Mundo y cuadricula (no cambiar sin regenerar tools/generar-datos.ps1)
    WORLD = 6000,            -- metros que cubre el mapa (-3000 a 3000)
    CELL = 50,               -- metros por celda de exploracion (120 x 120 celdas)
    SECTOR_CELLS = 10,       -- celdas por lado de cada cuadricula/sector (500 m -> 12 x 12 sectores)

    -- Exploracion (niebla)
    EXPLORE_RADIUS = 100,         -- metros que se descubren alrededor del jugador
    EXPLORE_INTERVAL_MS = 2000,   -- cada cuanto el servidor mira donde esta cada jugador
    SPEED_FULL_KMH = 80,          -- por encima de esta velocidad el radio se encoge
    SPEED_MIN_FACTOR = 0.3,       -- radio minimo (fraccion) a toda velocidad
    AIR_FACTOR = 0.5,             -- en avion o helicoptero se descubre la mitad
    TELEPORT_METERS = 600,        -- salto mayor que esto entre dos lecturas = teletransporte (no descubre el camino)
    SAVE_INTERVAL_MS = 60000,     -- guardado periodico del progreso (ademas de al salir)
    SECTOR_DISCOVERED_PCT = 90,   -- % de tierra explorada para dar una cuadricula por descubierta

    -- Zonas descubiertas desde el inicio para todos (ademas de las cuadriculas que marquen los admins)
    -- { x, y, radio, nombre }
    START_ZONES = {
        { 1742.9, -1861.6, 250, "Estacion Unity (primer spawn)" },
    },

    -- GPS
    GPS_ARRIVE_METERS = 25,        -- llegada en coche (a pie: la mitad)
    GPS_OFFROUTE_METERS = 45,      -- distancia a la ruta para recalcular
    GPS_REROUTE_MIN_MS = 3000,     -- minimo entre recalculos
    GPS_CHECK_MS = 500,            -- cada cuanto se revisa el avance

    -- Interfaz
    AUDIO_REASON = "rp_map",       -- motivo para pausar la radio y la musica del telefono con el mapa abierto
    MUSIC_FILE = "sounds/map_theme.mp3",   -- "Calm Relax 1" de cynicmusic (ver CREDITOS.md)
    MUSIC_VOLUME = 0.5,

    -- Ajustes que cambian los admins (clave = valor por defecto). Tipos: n = numero, b = 0/1
    SETTINGS = {
        radius   = { "n", 100, 25, 400 },     -- radio de exploracion (min, max)
        interval = { "n", 2000, 500, 10000 }, -- intervalo de exploracion en ms
        fog      = { "b", 1 },                -- niebla activa (0 = mapa entero visible)
        gps      = { "b", 1 },
        mode3d   = { "b", 1 },
        music    = { "b", 1 },                -- tema de fondo con el mapa abierto
        blips    = { "b", 1 },                -- importar como iconos los puntos de otros recursos (tiendas, bencineras...)
        houses   = { "b", 1 },                -- mostrar casas de rp_properties
    },

    -- Categorias iniciales (se siembran en map_categories; luego las editan los admins).
    -- public = visibles en el mapa aunque no se haya explorado la zona.
    CATEGORIES = {
        { key = "hospital",     name = "Hospitales",             icon = "hospital",  color = "#ff4d5e", public = true },
        { key = "policia",      name = "Comisarías",             icon = "police",    color = "#4d8dff", public = true },
        { key = "tienda",       name = "Tiendas",                icon = "shop",      color = "#f5a524" },
        { key = "super",        name = "Supermercados",          icon = "cart",      color = "#ffc15e" },
        { key = "restaurante",  name = "Restaurantes",           icon = "food",      color = "#ff8a3d" },
        { key = "bar",          name = "Bares",                  icon = "bar",       color = "#c88cff" },
        { key = "disco",        name = "Discotecas",             icon = "music",     color = "#ff5fd2" },
        { key = "gimnasio",     name = "Gimnasios",              icon = "gym",       color = "#5fe0a0" },
        { key = "gasolinera",   name = "Gasolineras",            icon = "fuel",      color = "#ffd84d" },
        { key = "cajero",       name = "Cajeros",                icon = "atm",       color = "#4cd38a" },
        { key = "concesionario",name = "Concesionarios",         icon = "car",       color = "#58c7ff" },
        { key = "taller",       name = "Talleres mecánicos",     icon = "wrench",    color = "#9fb1c8" },
        { key = "aeropuerto",   name = "Aeropuertos",            icon = "plane",     color = "#7fd7ff", public = true },
        { key = "transporte",   name = "Estaciones de transporte", icon = "train",   color = "#6fb7ff" },
        { key = "trabajo",      name = "Trabajos",               icon = "job",       color = "#f2c94c" },
        { key = "empresa",      name = "Empresas",               icon = "building",  color = "#b5bdc9" },
        { key = "casa",         name = "Casas",                  icon = "house",     color = "#7be37b" },
        { key = "apartamento",  name = "Apartamentos",           icon = "apartment", color = "#4fd1c5" },
        { key = "especial",     name = "Lugares especiales",     icon = "star",      color = "#ffe08a" },
    },

    -- Iconos disponibles (dibujados en html/js/icons.js)
    ICONS = { "hospital", "police", "shop", "cart", "food", "bar", "music", "gym", "fuel", "atm", "car", "wrench",
              "plane", "train", "job", "building", "house", "apartment", "star", "pin", "flag", "gun", "dice", "boat" },

    -- Puntos de otros recursos que se importan como iconos: icono de blip -> categoria
    BLIP_CATEGORIES = {
        [10] = "restaurante", [14] = "restaurante", [29] = "restaurante",
        [17] = "super", [22] = "hospital", [27] = "taller", [36] = "trabajo", [45] = "tienda",
        [51] = "gasolinera", [52] = "tienda", [54] = "transporte", [55] = "concesionario",
        [56] = "trabajo", [63] = "policia",
    },
}

-- Nombres de ciudades/territorios que devuelve getZoneName(x, y, z, true)
MAPA_CITIES = { "Los Santos", "San Fierro", "Las Venturas", "Red County", "Flint County", "Bone County", "Tierra Robada", "Whetstone" }
