--[[
    rp_radio / s_config.lua

    Emisoras disponibles. Para anadir una: nueva fila con id unico (no reutilizar ids),
    nombre, genero y la URL directa del stream (mp3/aac/ogg). Probadas al crear el recurso;
    si una emisora cambia de URL, solo hay que editarla aqui.
]]

RADIO_STATIONS = {
    { id = 1,  name = "LOS40",              genre = "Pop",        url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40AAC.aac" },
    { id = 2,  name = "LOS40 Dance",        genre = "Electronica", url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_DANCEAAC.aac" },
    { id = 3,  name = "LOS40 Urban",        genre = "Urbano",     url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_URBANAAC.aac" },
    { id = 4,  name = "LOS40 Classic",      genre = "Clasicos",   url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_CLASSICAAC.aac" },
    { id = 5,  name = "LOS40 Mexico",       genre = "Pop",        url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_MEXICOAAC.aac" },
    { id = 6,  name = "LOS40 Colombia",     genre = "Pop",        url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_COLOMBIAAAC.aac" },
    { id = 7,  name = "LOS40 Chile",        genre = "Pop",        url = "https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_CHILEAAC.aac" },
    { id = 8,  name = "Cadena Dial",        genre = "Pop latino", url = "https://playerservices.streamtheworld.com/api/livestream-redirect/CADENADIAL_SC.aac" },
    { id = 9,  name = "M80 Radio",          genre = "Retro",      url = "https://playerservices.streamtheworld.com/api/livestream-redirect/M80RADIOAAC.aac" },
    { id = 10, name = "Melodia FM",         genre = "Retro",      url = "https://playerservices.streamtheworld.com/api/livestream-redirect/MELODIA_FMAAC.aac" },
    { id = 11, name = "Radiole",            genre = "Flamenco",   url = "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIOLEAAC.aac" },
    { id = 12, name = "Cadena SER",         genre = "Noticias",   url = "https://playerservices.streamtheworld.com/api/livestream-redirect/CADENASERAAC.aac" },
    { id = 13, name = "Radio Corazon",      genre = "Romantica",  url = "https://playerservices.streamtheworld.com/api/livestream-redirect/CORAZONAAC.aac" },
}

RADIO_BY_ID = {}
for _, st in ipairs(RADIO_STATIONS) do RADIO_BY_ID[st.id] = st end

RADIO_DATA_KEY = "rp:radio"     -- element data del vehiculo: id de emisora (nil = apagada)
