--[[
    rp_characters / s_body.lua  (compartido cliente/servidor)

    Cuerpo del personaje: complexion (grasa y musculo), altura y tono de piel.

    - Grasa y musculo: stats de GTA (FAT = 21, BODY_MUSCLE = 23) con setPedStat.
      GTA solo los aplica al cuerpo de CJ (skin 0), es decir, a los personajes
      masculinos. En la BD se guardan de 0 a 100 y aqui se pasan a 0-1000.
    - Altura y tono de piel: MTA no tiene una funcion para escalar peds ni para
      cambiar el color de piel de CJ, asi que los dibuja un shader en cada
      cliente (client/c_body.lua + fx/body.fx) a partir del elementData "rp:body".
      Es solo visual: la colision y la camara del ped siguen siendo las de GTA.
]]

BODY = {
    STAT_FAT = 21,
    STAT_MUSCLE = 23,
    STAT_STAMINA = 22,
    STAT_MAX = 1000,        -- escala interna de GTA para grasa, musculo y resistencia
    STAMINA_DEFAULT = 100,  -- resistencia inicial del juego original (10 %)
    FAT_MAX = 100,
    MUSCLE_MAX = 100,

    HEIGHT_MIN = 155, HEIGHT_MAX = 200,   -- cm
    HEIGHT_BASE = 175,                    -- altura del modelo original de GTA (escala 1)

    -- Tonos de piel para el cuerpo de CJ. color = albedo objetivo de la piel
    -- (0-1). El ultimo es el de CJ sin tocar (sin shader).
    TONES = {
        { name = "Muy claro", hex = "#ecc3a4", color = { 0.93, 0.76, 0.64 } },
        { name = "Claro",     hex = "#d7a582", color = { 0.84, 0.64, 0.50 } },
        { name = "Medio",     hex = "#c28c66", color = { 0.76, 0.55, 0.40 } },
        { name = "Trigueno",  hex = "#a8774f", color = { 0.66, 0.47, 0.32 } },
        { name = "Moreno",    hex = "#8a5d3d", color = { 0.54, 0.37, 0.25 } },
        { name = "Oscuro",    hex = "#5e3e2a", color = nil },
    },
    -- Tono que se propone al elegir raza (rp_heads: 1 blanco, 2 negro, 3 latino, 4 asiatico)
    TONE_BY_RACE = { [1] = 2, [2] = 6, [3] = 4, [4] = 3 },
}

local function clamp(v, a, b)
    v = tonumber(v) or a
    if v < a then return a elseif v > b then return b end
    return v
end

-- Escala visual del ped a partir de la altura en cm (1 = altura base)
function heightToScale(height)
    height = tonumber(height)
    if not height then return 1 end
    return clamp(height, BODY.HEIGHT_MIN, BODY.HEIGHT_MAX) / BODY.HEIGHT_BASE
end

-- Color del tono (tabla {r,g,b}) o nil si no hay que tenir la piel
function getSkinToneColor(tone)
    local t = BODY.TONES[tonumber(tone) or 0]
    return t and t.color or nil
end

function isValidSkinTone(tone)
    return type(tone) == "number" and BODY.TONES[tone] ~= nil
end

-- Peso aproximado (kg) a partir de la altura y la complexion. Lo calcula el
-- servidor; el cliente solo lo muestra como referencia.
function estimateWeight(height, fat, muscle)
    local m = clamp(height, BODY.HEIGHT_MIN, BODY.HEIGHT_MAX) / 100
    local bmi = 19.5 + clamp(fat, 0, BODY.FAT_MAX) * 0.14 + clamp(muscle, 0, BODY.MUSCLE_MAX) * 0.05
    return math.floor(bmi * m * m + 0.5)
end

-- Grasa y musculo (0-100) -> stats de GTA. Hay que llamarlo ANTES de poner la
-- ropa: GTA reconstruye el cuerpo de CJ al cambiar la ropa.
function applyBodyStats(ped, fat, muscle)
    setPedStat(ped, BODY.STAT_FAT, clamp(fat, 0, BODY.FAT_MAX) * 10)
    setPedStat(ped, BODY.STAT_MUSCLE, clamp(muscle, 0, BODY.MUSCLE_MAX) * 10)
end
