--[[
    rp_scoreboard / shared/s_config.lua
    Catalogo de lo que cada jugador puede poner en su fila del Tab (/perfil).
    El servidor valida contra estas listas; el cliente se las pasa al editor.
]]

SB = {}

-- Letras animadas del nombre (la animacion vive en html/style.css: .fx-<clave>)
SB.EFFECTS = {
    { key = "none",    name = "Sin efecto" },
    { key = "shine",   name = "Destello" },
    { key = "rainbow", name = "Arcoíris" },
    { key = "wave",    name = "Ola" },
    { key = "glow",    name = "Neón" },
    { key = "glitch",  name = "Glitch" },
    { key = "flicker", name = "Letrero roto" },
    { key = "bounce",  name = "Saltitos" },
    { key = "type",    name = "Máquina de escribir" },
}

-- Iconos animados: emoji + animacion CSS (.ico-<anim>)
SB.ICONS = {
    { key = "fire",    emoji = "🔥", anim = "flame",  name = "Fuego" },
    { key = "star",    emoji = "⭐", anim = "spin",   name = "Estrella" },
    { key = "crown",   emoji = "👑", anim = "float",  name = "Corona" },
    { key = "gem",     emoji = "💎", anim = "shine",  name = "Diamante" },
    { key = "heart",   emoji = "❤️", anim = "beat",   name = "Corazón" },
    { key = "bolt",    emoji = "⚡", anim = "flash",  name = "Rayo" },
    { key = "music",   emoji = "🎵", anim = "sway",   name = "Música" },
    { key = "skull",   emoji = "💀", anim = "shake",  name = "Calavera" },
    { key = "money",   emoji = "💰", anim = "bounce", name = "Dinero" },
    { key = "car",     emoji = "🚗", anim = "drive",  name = "Auto" },
    { key = "rose",    emoji = "🌹", anim = "sway",   name = "Rosa" },
    { key = "clover",  emoji = "🍀", anim = "spin",   name = "Trébol" },
    { key = "moon",    emoji = "🌙", anim = "float",  name = "Luna" },
    { key = "wolf",    emoji = "🐺", anim = "shake",  name = "Lobo" },
    { key = "game",    emoji = "🎮", anim = "bounce", name = "Gamer" },
    { key = "dice",    emoji = "🎲", anim = "roll",   name = "Dados" },
    { key = "ghost",   emoji = "👻", anim = "float",  name = "Fantasma" },
    { key = "sparkle", emoji = "✨", anim = "flash",  name = "Brillo" },
}

-- Banderas (svg de flag-icons en html/flags/<code>.svg)
SB.FLAGS = {
    { key = "ar", name = "Argentina" }, { key = "bo", name = "Bolivia" }, { key = "br", name = "Brasil" },
    { key = "cl", name = "Chile" }, { key = "co", name = "Colombia" }, { key = "cr", name = "Costa Rica" },
    { key = "cu", name = "Cuba" }, { key = "ec", name = "Ecuador" }, { key = "sv", name = "El Salvador" },
    { key = "es", name = "España" }, { key = "us", name = "Estados Unidos" }, { key = "gt", name = "Guatemala" },
    { key = "gq", name = "Guinea Ecuatorial" }, { key = "hn", name = "Honduras" }, { key = "mx", name = "México" },
    { key = "ni", name = "Nicaragua" }, { key = "pa", name = "Panamá" }, { key = "py", name = "Paraguay" },
    { key = "pe", name = "Perú" }, { key = "pr", name = "Puerto Rico" }, { key = "do", name = "Rep. Dominicana" },
    { key = "uy", name = "Uruguay" }, { key = "ve", name = "Venezuela" }, { key = "ca", name = "Canadá" },
    { key = "pt", name = "Portugal" }, { key = "it", name = "Italia" }, { key = "fr", name = "Francia" },
    { key = "de", name = "Alemania" }, { key = "gb", name = "Reino Unido" },
}

-- Foto pequena: solo https de estos hosts de imagenes (evita que el servidor pida URLs internas)
SB.AVATAR_HOSTS = {
    ["i.imgur.com"] = true, ["i.ibb.co"] = true, ["i.postimg.cc"] = true,
    ["cdn.discordapp.com"] = true, ["media.discordapp.net"] = true,
    ["media.tenor.com"] = true, ["media.giphy.com"] = true, ["i.giphy.com"] = true,
}
SB.AVATAR_MAX_BYTES = 200 * 1024
SB.AVATAR_COOLDOWN = 20000   -- ms entre fotos nuevas
SB.SAVE_COOLDOWN = 1500      -- ms entre guardados del perfil
SB.DEFAULT_COLOR = "#f2f4f8"

local function index(list)
    local t = {}
    for _, v in ipairs(list) do t[v.key] = v end
    return t
end
SB.EFFECT_BY_KEY = index(SB.EFFECTS)
SB.ICON_BY_KEY = index(SB.ICONS)
SB.FLAG_BY_KEY = index(SB.FLAGS)
