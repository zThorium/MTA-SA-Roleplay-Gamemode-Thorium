--[[
    rp_ballistics / shared / s_config.lua
    Daño de las armas de fuego de los jugadores a los NPC (peds), por calibre.
    - Tiro en la cabeza (bodypart 9) con arma de fuego: muerte instantánea.
    - Al cuerpo: SHOTS[arma] balas matan a un NPC de 100 de vida sin chaleco. El chaleco y la vida extra
      (enemigos de misión en dificultad alta) absorben daño como en GTA: hacen falta más balas.
]]

BALLISTICS = {
    BASE_HEALTH = 100,
    HEAD = 9,
    MAX_RANGE = 250,   -- metros: el servidor descarta impactos más lejanos
    REPORT_MS = 60,    -- cliente: como mucho un aviso por NPC cada 60 ms (los perdigones de escopeta llegan juntos)

    -- arma = balas al cuerpo para matar
    SHOTS = {
        [22] = 5,   -- Colt 45 (9 mm)
        [23] = 5,   -- pistola con silenciador (9 mm)
        [28] = 5,   -- Uzi (9 mm)
        [32] = 5,   -- Tec-9 (9 mm)
        [29] = 4,   -- MP5 (9 mm, ráfaga más precisa)
        [31] = 3,   -- M4 (5,56 mm)
        [30] = 2,   -- AK-47 (7,62x39 mm)
        [38] = 2,   -- minigun (7,62 mm)
        [24] = 1,   -- Desert Eagle (.50 AE)
        [25] = 1,   -- escopeta (calibre 12)
        [26] = 1,   -- recortada (calibre 12)
        [27] = 1,   -- escopeta de combate (calibre 12)
        [33] = 1,   -- rifle de caza (.308)
        [34] = 1,   -- francotirador (.308)
    },
}

-- Resultado de un impacto: muere?, vida y chaleco que quedan. Sin efectos: lo aplica quien lo llama.
function ballisticsHit(weapon, bodypart, health, armor)
    local shots = BALLISTICS.SHOTS[weapon]
    if not shots then return false, health, armor end
    if bodypart == BALLISTICS.HEAD then return true, 0, armor end
    local dmg = BALLISTICS.BASE_HEALTH / shots
    local absorbed = math.min(armor or 0, dmg)
    armor = (armor or 0) - absorbed
    health = health - (dmg - absorbed)
    -- margen de 0,5 para que 5 x 20 = 100 no deje al NPC con 0,0001 de vida
    if health <= 0.5 then return true, 0, armor end
    return false, health, armor
end
