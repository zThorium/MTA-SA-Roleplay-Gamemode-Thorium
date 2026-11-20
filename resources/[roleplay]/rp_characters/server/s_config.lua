--[[
    rp_characters / s_config.lua
]]

CHARS = {
    MAX_SLOTS = 3,
    NAME_PART_MIN = 2,          -- Nombre y Apellido, cada uno
    NAME_PART_MAX = 15,
    AGE_MIN = 16, AGE_MAX = 90,
    -- Altura, complexion y tono: limites en shared/s_body.lua (BODY). El peso lo
    -- calcula el servidor a partir de la altura y la complexion.
    ORIGIN_MIN = 3, ORIGIN_MAX = 48,
    STORY_MIN = 30, STORY_MAX = 2000,   -- caracteres (no bytes)
    START_MONEY = 500,
}

SPAWN = {
    -- Estacion Unity, Los Santos (primer spawn de cada personaje)
    DEFAULT = { x = 1742.9, y = -1861.6, z = 13.58, rot = 0, interior = 0, dimension = 0 },
    -- Hospital All Saints, Los Santos
    HOSPITAL = { x = 1177.6, y = -1323.9, z = 14.1, rot = 270 },
    RESPAWN_DELAY = 5000,
    AUTOSAVE_INTERVAL = 5 * 60000,
}
