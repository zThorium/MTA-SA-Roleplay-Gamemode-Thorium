--[[
    rp_phone / shared/s_social.lua
    Configuracion de Fotogram compartida por servidor y cliente: limites, filtros
    validos, poses de la camara y ajuste del brazo/telefono en la selfie.
]]

FOTOGRAM = {
    -- Limites (el servidor los aplica; el cliente solo los usa para avisar antes)
    MAX_IMAGE      = 350 * 1024,  -- bytes del base64 de una foto (JPEG)
    FEED_PAGE      = 8,           -- publicaciones por pagina del feed
    COMMENTS_PAGE  = 20,
    GRID_SIZE      = 30,          -- miniaturas del perfil y de Explorar
    CAPTION_MAX    = 280,
    COMMENT_MAX    = 200,
    BIO_MAX        = 150,
    POSTS_PER_DAY  = 20,          -- por personaje
    NOTIFY_DAYS    = 30,          -- las notificaciones mas viejas se borran al arrancar

    -- Esperas minimas entre acciones del mismo personaje (ms)
    COOLDOWN = {
        post = 20000, comment = 2500, follow = 800, like = 250,
        search = 700, profile = 2000, avatar = 2000,
    },
    COMMENTS_PER_MINUTE = 8,

    -- Foto: recorte vertical 4:5 (como Instagram) del centro de la pantalla
    PHOTO_W = 576,
    PHOTO_H = 720,
    FRAME_SCREEN_H = 0.80,        -- alto del visor respecto a la pantalla

    -- Camara
    SELFIE_DIST = { min = 0.45, max = 1.25, default = 0.7 },   -- m desde la cara (>0.75 = palo selfie)
    SELFIE_HEIGHT = { min = -0.35, max = 0.45, default = 0.08 },
    REAR_FOV = { min = 25, max = 85, default = 70 },
    REAR_PITCH = { min = -45, max = 45 },
    TURN_SPEED = 90,              -- grados por segundo al girar con A/D
}

-- Filtros (el aspecto se define en html/social.js; aqui solo los ids validos)
FOTOGRAM_FILTERS = {
    "original", "vivido", "calido", "frio", "vintage", "noir", "sepia",
    "atardecer", "neon", "desvanecido", "drama", "pastel",
}
FOTOGRAM_FILTER_SET = {}
for _, id in ipairs(FOTOGRAM_FILTERS) do FOTOGRAM_FILTER_SET[id] = true end

--[[
    Poses de la camara. El servidor las pone con setPedAnimation (las ven todos).
    En la selfie el brazo derecho sostiene el telefono (ver SELFIE_ARM), asi que
    los gestos usan la mano izquierda (bloque GHANDS ...LH) o el cuerpo.
    mode: "selfie", "rear" o "both". vehicle = false: no se puede en un vehiculo.
]]
FOTOGRAM_POSES = {
    { id = "natural",   name = "Natural",    icon = "🙂", mode = "selfie", block = "ped",         anim = "IDLE_stance" },
    { id = "paz",       name = "Paz",        icon = "✌️", mode = "selfie", block = "GHANDS",      anim = "gsign2LH" },
    { id = "sena",      name = "Seña",       icon = "🤟", mode = "selfie", block = "GHANDS",      anim = "gsign1LH" },
    { id = "rock",      name = "Rockera",    icon = "🤘", mode = "selfie", block = "GHANDS",      anim = "gsign5LH" },
    { id = "pensativo", name = "Pensativo",  icon = "🤔", mode = "selfie", block = "COP_AMBIENT", anim = "Coplook_think" },
    { id = "charla",    name = "Hablando",   icon = "💬", mode = "selfie", block = "ped",         anim = "IDLE_chat" },
    { id = "risa",      name = "Riendo",     icon = "😂", mode = "selfie", block = "RAPPING",     anim = "Laugh_01" },
    { id = "baile",     name = "Bailando",   icon = "💃", mode = "selfie", block = "DANCING",     anim = "dnce_M_a" },
    { id = "cansado",   name = "Cansado",    icon = "😮‍💨", mode = "selfie", block = "ped",         anim = "IDLE_tired" },
    { id = "sentado",   name = "Sentado",    icon = "🪑", mode = "selfie", block = "BEACH",       anim = "ParkSit_M_loop" },
    { id = "tumbado",   name = "Tumbado",    icon = "🏖️", mode = "selfie", block = "BEACH",       anim = "Lay_Bac_Loop" },
    { id = "foto",      name = "De pie",     icon = "📱", mode = "rear",   block = "CAMERA",      anim = "camstnd_idleloop" },
    { id = "agachado",  name = "Agachado",   icon = "🧎", mode = "rear",   block = "CAMERA",      anim = "camcrch_idleloop" },
}
FOTOGRAM_POSE_BY_ID = {}
for _, p in ipairs(FOTOGRAM_POSES) do FOTOGRAM_POSE_BY_ID[p.id] = p end
FOTOGRAM_DEFAULT_POSE = { selfie = "natural", rear = "foto" }

--[[
    Brazo derecho estirado sujetando el telefono en la selfie. Se aplica en cada
    cliente con setElementBoneRotation (MTA 1.6) a todos los jugadores con el dato
    "rp:phoneCam" = "selfie". Huesos de GTA SA: 21 clavicula, 22 brazo, 23 antebrazo,
    24 mano derecha. Valores = { yaw, pitch, roll } en grados.
    Para afinarlos en juego: /selfieajuste <hueso> <yaw> <pitch> <roll> (ver c_camera.lua).
]]
SELFIE_ARM = {
    [22] = { 0, -70, -15 },
    [23] = { 0, -25, 0 },
    [24] = { 0, 0, 90 },
}

-- Telefono en la mano derecha (bone_attach: hueso 12) mientras se usa la camara
PHONE_PROP = { model = 330, bone = 12, x = 0.02, y = 0.03, z = 0.04, rx = 0, ry = -90, rz = 0 }
