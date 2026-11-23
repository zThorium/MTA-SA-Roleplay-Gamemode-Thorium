--[[
    rp_npcrel / shared / s_config.lua  (compartido cliente/servidor)
    Catalogo del sistema de vinculos con la gente del barrio: etapas, acciones,
    rasgos, skins por genero y animaciones. Los numeros de balance viven aqui.
]]

NPCREL = {
    KEY            = "h",        -- tecla para hablar con alguien cercano
    TALK_DISTANCE  = 3.5,        -- metros al peaton para poder hablar
    ACTION_COOLDOWN = 2500,      -- ms entre acciones
    SESSION_ACTIONS = 14,        -- acciones por conversacion antes de que tenga que irse
    SESSION_PAUSE   = 20 * 60000,-- ms que no quiere hablar tras agotar la conversacion
    FATIGUE_WINDOW  = 10 * 60000,-- ms en los que repetir la misma accion rinde menos
    FATIGUE_STEP    = 0.35,      -- cada repeticion reduce el efecto en este factor
    NEW_PEOPLE_PER_HOUR = 12,    -- desconocidos nuevos que se pueden guardar por hora
    MAX_CONTACTS    = 40,        -- vinculos guardados por personaje
    DECAY_FREE_DAYS = 3,         -- dias sin hablar antes de empezar a enfriarse
    DECAY_ROMANCE   = 2,         -- puntos de romance perdidos por dia de mas
    DECAY_FRIENDSHIP = 1,
    CALL_COOLDOWN   = 5 * 60000, -- ms entre llamadas al mismo vinculo
    SUMMON_TIME     = 4 * 60000, -- ms que dura la visita tras una llamada
    GIFT_PRICE      = 60,        -- precio del regalo
    NUMBER_MIN      = 5560000,   -- numeros de vinculos (los jugadores usan 5550000-5559999)
    NUMBER_MAX      = 5569999,
}

-- Etapas (se calculan con amistad, romance y si son pareja)
NPCREL_STAGES = {
    { id = 1, name = "Desconocido" },
    { id = 2, name = "Conocido" },
    { id = 3, name = "Amigo" },
    { id = 4, name = "Coqueteo" },
    { id = 5, name = "Pareja" },
    { id = 6, name = "Pareja estable" },
}

NPCREL_RULES = {
    KNOWN       = 15,   -- amistad para ser conocidos
    FRIEND      = 40,   -- amistad para ser amigos
    CRUSH_ROMANCE = 30, -- romance (y amistad CRUSH_FRIENDSHIP) para "se gustan": guarda el numero solo
    CRUSH_FRIENDSHIP = 25,
    ASK_OUT_ROMANCE = 60, -- romance minimo para pedirle salir
    STABLE_ROMANCE  = 90,
    STABLE_FRIENDSHIP = 70,
    MAX = 100,
}

-- Acciones del menu. min = etapa minima. kind: "friend" | "romance" | "special"
-- friendship / romance = puntos base; anim = clave de NPCREL_ANIMS; line = clave de NPCREL_LINES
NPCREL_ACTIONS = {
    { id = "talk",   label = "Charlar",       icon = "💬", min = 1, kind = "friend",  friendship = 4, romance = 0, anim = "talk" },
    { id = "joke",   label = "Bromear",       icon = "😄", min = 1, kind = "friend",  friendship = 5, romance = 0, anim = "joke" },
    { id = "compliment", label = "Cumplido",  icon = "✨", min = 2, kind = "romance", friendship = 1, romance = 3, anim = "compliment" },
    { id = "flirt",  label = "Coquetear",     icon = "😉", min = 2, kind = "romance", friendship = 0, romance = 6, anim = "flirt", risky = true },
    { id = "gift",   label = "Regalo",        icon = "🎁", min = 2, kind = "romance", friendship = 5, romance = 3, anim = "gift", cost = true },
    { id = "hug",    label = "Abrazar",       icon = "🤗", min = 3, kind = "friend",  friendship = 3, romance = 1, anim = "hug" },
    { id = "number", label = "Pedir número",  icon = "📱", min = 2, kind = "special", anim = "talk" },
    { id = "askout", label = "Pedir salir",   icon = "💘", min = 4, kind = "special", anim = "flirt" },
    { id = "kiss",   label = "Besar",         icon = "💋", min = 5, kind = "romance", friendship = 1, romance = 8, anim = "kiss" },
    { id = "bye",    label = "Despedirse",    icon = "👋", min = 1, kind = "special", anim = "wave" },
}

-- Rasgos: multiplicador por accion y gusto. Cada vinculo recibe 2 al conocerse.
NPCREL_TRAITS = {
    romantica = { label = "Romántica", mult = { compliment = 1.5, gift = 1.4, kiss = 1.3, flirt = 1.2 } },
    timida    = { label = "Tímida",    mult = { flirt = 0.5, kiss = 0.8, joke = 0.8, talk = 1.2 }, risk = 0.12 },
    fiestera  = { label = "Fiestera",  mult = { joke = 1.5, flirt = 1.2, talk = 0.9 } },
    ambiciosa = { label = "Ambiciosa", mult = { gift = 2.0, compliment = 0.8, joke = 0.7 } },
    seria     = { label = "Seria",     mult = { joke = 0.5, talk = 1.3, flirt = 0.7, hug = 0.8 }, risk = 0.05 },
    amable    = { label = "Amable",    mult = { talk = 1.3, hug = 1.4, compliment = 1.2 } },
}
NPCREL_TRAIT_IDS = { "romantica", "timida", "fiestera", "ambiciosa", "seria", "amable" }

-- Animaciones: bloque, nombre y si hacen bucle. player = el jugador, npc = el otro.
-- Se eligen al azar de la lista; "bad" es la reaccion si la accion sale mal.
NPCREL_ANIMS = {
    talk = {
        player = { { "GANGS", "prtial_gngtlkA" }, { "GANGS", "prtial_gngtlkB" }, { "GANGS", "prtial_gngtlkC" } },
        npc    = { { "GANGS", "prtial_gngtlkD" }, { "GANGS", "prtial_gngtlkE" }, { "PED", "IDLE_chat" } },
        bad    = { { "PED", "endchat_02" } },
    },
    joke = {
        player = { { "GANGS", "prtial_gngtlkF" }, { "GANGS", "prtial_gngtlkG" } },
        npc    = { { "RAPPING", "Laugh_01" } },
        bad    = { { "PED", "endchat_03" } },
    },
    compliment = {
        player = { { "GANGS", "prtial_gngtlkH" } },
        npc    = { { "KISSING", "gfwave2" }, { "GANGS", "prtial_gngtlkE" } },
        bad    = { { "PED", "endchat_02" } },
    },
    flirt = {
        player = { { "GANGS", "prtial_gngtlkB" }, { "KISSING", "BD_GF_Wave" } },
        npc    = { { "KISSING", "gfwave2" }, { "KISSING", "BD_GF_Wave" } },
        bad    = { { "PED", "endchat_03" }, { "COP_AMBIENT", "Coplook_loop" } },
    },
    gift = {
        player = { { "KISSING", "gift_give" } },
        npc    = { { "KISSING", "gift_get" } },
        bad    = { { "PED", "endchat_02" } },
    },
    hug = {
        player = { { "GANGS", "hndshkaa" } },
        npc    = { { "GANGS", "hndshkaa" } },
        bad    = { { "PED", "endchat_02" } },
    },
    kiss = {
        player = { { "KISSING", "Playa_Kiss_02" }, { "KISSING", "Playa_Kiss_01" } },
        npc    = { { "KISSING", "Grlfrd_Kiss_02" }, { "KISSING", "Grlfrd_Kiss_01" } },
        bad    = { { "PED", "endchat_03" } },
    },
    wave = {
        player = { { "ON_LOOKERS", "wave_loop" } },
        npc    = { { "ON_LOOKERS", "wave_loop" } },
        bad    = { { "ON_LOOKERS", "wave_loop" } },
    },
}

-- Skins permitidas (las mismas civiles de rp_characters): hombres y mujeres
NPCREL_SKINS = {
    [0] = {
        1, 2, 7, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 32, 33,
        34, 35, 36, 37, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 57, 58, 59, 60, 61, 62,
        66, 67, 68, 72, 73, 78, 79, 80, 81, 82, 83, 84, 94, 95, 96, 98, 100, 101, 102, 103,
        104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122, 123, 124,
        125, 126, 127, 128, 132, 133, 134, 135, 136, 137, 142, 143, 144, 146, 147, 153, 154, 155, 156, 158,
        159, 160, 161, 162, 168, 170, 171, 173, 174, 175, 176, 177, 179, 180, 181, 182, 183, 184, 185, 186,
        187, 188, 189, 200, 202, 203, 204, 206, 209, 210, 212, 213, 217, 220, 221, 222, 223, 227, 228, 229,
        230, 234, 235, 236, 239, 240, 241, 242, 247, 248, 249, 250, 253, 254, 255, 258, 259, 260, 261, 262,
        268, 272,
    },
    [1] = {
        9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 69, 76, 77, 88, 89, 90,
        91, 93, 129, 130, 131, 138, 139, 140, 141, 148, 150, 151, 157, 169, 172, 190, 191, 192, 193, 194,
        195, 196, 197, 198, 199, 201, 205, 207, 211, 214, 215, 216, 218, 219, 224, 225, 226, 231, 232, 233,
        251, 263,
    },
}

NPCREL_SKIN_GENDER = {}
for gender, list in pairs(NPCREL_SKINS) do
    for _, skin in ipairs(list) do NPCREL_SKIN_GENDER[skin] = gender end
end

-- Calcula la etapa a partir de los valores. Es la unica fuente de verdad (cliente y servidor).
function npcrelStage(friendship, romance, dating)
    local R = NPCREL_RULES
    local stage = 1
    if friendship >= R.KNOWN then stage = 2 end
    if friendship >= R.FRIEND then stage = 3 end
    if romance >= R.CRUSH_ROMANCE and friendship >= R.CRUSH_FRIENDSHIP then stage = math.max(stage, 4) end
    if dating == 1 then
        stage = 5
        if romance >= R.STABLE_ROMANCE and friendship >= R.STABLE_FRIENDSHIP then stage = 6 end
    end
    return stage
end
