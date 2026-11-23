--[[
    rp_phone / s_music.lua compartido

    Catalogo base reproducible de la app Musica. Las URLs directas solo se usan
    desde el servidor; el cliente siempre recibe el track_key y nunca valida URLs.
]]

MUSIC_CONFIG = {
    PERSON_DISTANCE = 18,
    VEHICLE_DISTANCE = 55,
    DEFAULT_VOLUME = 60,
    MAX_VOLUME = 100,
    SEARCH_COOLDOWN_MS = 1000,
    PLAY_COOLDOWN_MS = 350,
}

MUSIC_DEMO_TRACKS = {
    {
        key = "local:soundhelix-1",
        provider = "local",
        providerId = "",
        title = "SoundHelix Song 1",
        artist = "SoundHelix",
        artwork = "",
        streamUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
        durationMs = 372000,
    },
    {
        key = "local:soundhelix-2",
        provider = "local",
        providerId = "",
        title = "SoundHelix Song 2",
        artist = "SoundHelix",
        artwork = "",
        streamUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3",
        durationMs = 425000,
    },
    {
        key = "local:soundhelix-3",
        provider = "local",
        providerId = "",
        title = "SoundHelix Song 3",
        artist = "SoundHelix",
        artwork = "",
        streamUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3",
        durationMs = 347000,
    },
}
