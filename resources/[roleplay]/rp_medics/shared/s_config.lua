--[[
    rp_medics / s_config.lua  (compartido cliente/servidor)

    Facción de médicos (fase 0): servicio en el vestuario del hospital con casillero
    personal (ítems y mochila) y ambulancias de la facción en el garaje.
    Lo que se ajusta sin tocar la lógica va aquí.
]]

MED = {
    -- Una facción es de médicos si su tipo es este (FACTION_TYPES de rp_factions)
    FACTION_TYPE = "medicos",

    INTERACT_RADIUS = 2.0,       -- metros para pulsar E en el vestuario o el garaje
    COOLDOWN_MS = 500,           -- entre acciones del mismo jugador

    -- Uniformes (paramédicos de GTA SA)
    SKINS = {
        { id = 274, name = "Los Santos" },
        { id = 275, name = "Las Venturas" },
        { id = 276, name = "San Fierro" },
    },

    -- Mochila de servicio (BACKPACKS de rp_backpacks, duty = true) y el material que lleva dentro.
    -- Se da al entrar de servicio y se retira al salir: el material no sale del servicio.
    DUTY_BACKPACK = "bp_medic",
    EQUIPMENT = {
        { item = "medkit", amount = 3 },
    },

    -- Casillero personal
    REQUIRE_UNARMED = true,      -- para entrar de servicio no puedes llevar armas (guárdalas en el casillero)
    KEEP_ITEMS = { phone = true },   -- «Guardar todo» no guarda estos (ni los documentos: DNI, licencias)

    AMBULANCES = { 416 },

    -- Puntos del hospital All Saints (Los Santos). Aproximados: un admin los deja exactos con
    -- /medmover <vestuario|garaje|ambulancia> o con el editor (ALT); se guardan en medic_points.
    POINTS = {
        locker    = { x = 1172.1, y = -1330.2, z = 13.6, rot = 0 },
        garage    = { x = 1180.6, y = -1336.8, z = 13.6, rot = 0 },
        ambulance = { x = 1185.0, y = -1342.0, z = 13.7, rot = 270 },
    },
}
