--[[
    rp_mapeditor / s_config.lua (compartido)
    Ajustes del editor de mapas. La config se lee dentro de funciones (CLI-04).
]]

MAPEDIT = {
    DIMENSION_BASE = 27000,         -- borrador de cada proyecto: 27000 + id (REGISTROS.md)
    MAX_PROJECTS = 300,
    MAX_ELEMENTS = 2000,            -- por proyecto
    MAX_BATCH = 250,                -- elementos por operacion (pegar, duplicar, importar en tandas)
    OP_COOLDOWN_MS = 40,
    MAX_IMPORT_BYTES = 1500000,     -- .map pegado
    COORD_MAX = 6000, Z_MIN = -200, Z_MAX = 3000,
    SCALE_MIN = 0.05, SCALE_MAX = 20,
    REMOVAL_RADIUS_MAX = 250,
    MAX_VERSIONS_LISTED = 30,
    NAME_PATTERN = "^[%w _%-%.]+$", NAME_MIN = 3, NAME_MAX = 48,

    -- Cámara del editor (m/s)
    CAM_SPEED = 18, CAM_FAST = 4, CAM_SLOW = 0.2,

    -- Rejilla y paso de giro por defecto
    GRID = 0.5, ROT_STEP = 15,

    ETYPES = { "object", "vehicle", "ped", "marker", "pickup", "point", "removal" },
    ETYPE_NAMES = {
        object = "Objeto", vehicle = "Vehículo", ped = "Ped", marker = "Marcador",
        pickup = "Pickup", point = "Punto", removal = "Quitado del mapa",
    },
    MARKER_TYPES = { cylinder = true, checkpoint = true, ring = true, arrow = true, corona = true },

    -- Animaciones sugeridas para peds decorativos (bloque, animación)
    PED_ANIMS = {
        { "Ninguna", "", "" },
        { "Sentado", "ped", "SEAT_idle" },
        { "Apoyado en la pared", "GANGS", "leanIDLE" },
        { "Fumando", "SMOKING", "M_smklean_loop" },
        { "Hablando", "GANGS", "prtial_gngtlkA" },
        { "Brazos cruzados", "COP_AMBIENT", "Coplook_loop" },
        { "Bailando", "DANCING", "dnce_M_a" },
        { "Hablando por teléfono", "ped", "phone_talk" },
        { "Tumbado", "BEACH", "Lay_Bac_Loop" },
        { "Guardia", "ped", "IDLE_armed" },
        { "Reparando", "CAR", "Fixn_Car_Loop" },
        { "Bebiendo", "BAR", "dnk_stndM_loop" },
    },

    -- Ajustes del mapa (nil = no se toca). Rango [min, max]
    SETTINGS = {
        hour     = { 0, 23 },
        minute   = { 0, 59 },
        weather  = { 0, 255 },
        gravity  = { 0.001, 0.05 },
        speed    = { 0.1, 3 },
        waves    = { 0, 100 },
        farclip  = { 100, 3000 },
    },
}
